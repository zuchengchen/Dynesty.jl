using JLD2
using Serialization

const RESULTS_FORMAT_VERSION = 1
const CHECKPOINT_FORMAT_VERSION = 1
const USER_FUNCTION_KEYS = Set((
    :loglikelihood,
    :loglike,
    :likelihood,
    :prior_transform,
    :ptform,
    :pool,
    :mapper,
    :worker,
    :workers,
))

struct SamplerCheckpoint
    state::Any
    metadata::Dict{Symbol, Any}
    backend_metadata::Dict{Symbol, Any}
end

struct RestoredSampler{L, P}
    state::Any
    loglikelihood::L
    prior_transform::P
    metadata::Dict{Symbol, Any}
    backend_metadata::Dict{Symbol, Any}
end

function sampler_snapshot end

function _require_extension(
    path::AbstractString, extension::AbstractString, kind::AbstractString
)
    endswith(lowercase(path), extension) ||
        throw(ArgumentError("$kind path must use $extension extension; got $path"))
    return nothing
end

function _base_metadata(extra=Dict{Symbol, Any}())
    metadata = Dict{Symbol, Any}(
        :package => "Dynesty",
        :package_version => "0.1.0",
        :julia_version => string(VERSION),
    )
    for (key, value) in extra
        metadata[Symbol(key)] = value
    end
    return metadata
end

"""
    save_results(path, res; metadata=Dict())

Save a `Results` archive using JLD2. Result archives are intended for Julia
analysis and are not a checkpoint/resume format.
"""
function save_results(path::AbstractString, res::Results; metadata=Dict{Symbol, Any}())
    _require_extension(path, ".jld2", "results archive")
    payload = Dict{Symbol, Any}(
        :format_version => RESULTS_FORMAT_VERSION,
        :metadata => _base_metadata(metadata),
        :keys => keys(res),
        :data => asdict(res),
    )
    JLD2.jldsave(path; payload)
    return path
end

function save_results(res::Results, path::AbstractString; metadata=Dict{Symbol, Any}())
    return save_results(path, res; metadata)
end

"""
    load_results(path)

Load a JLD2 results archive produced by `save_results`.
"""
function load_results(path::AbstractString)
    _require_extension(path, ".jld2", "results archive")
    loaded = JLD2.load(path, "payload")
    loaded[:format_version] == RESULTS_FORMAT_VERSION || throw(
        ArgumentError(
            "unsupported Results archive format version $(loaded[:format_version])"
        ),
    )
    ordered = [(key, loaded[:data][key]) for key in loaded[:keys]]
    return Results(ordered)
end

function _sanitize_state(value; skip_unserializable::Bool=false)
    if value isa AbstractDict
        out = Dict{Symbol, Any}()
        skipped = Symbol[]
        for (raw_key, item) in value
            key = Symbol(raw_key)
            if key in USER_FUNCTION_KEYS || item isa Function
                push!(skipped, key)
                continue
            end
            out[key] = item
        end
        return out, skipped
    elseif value isa NamedTuple
        out = Dict{Symbol, Any}()
        skipped = Symbol[]
        for key in keys(value)
            item = getfield(value, key)
            if key in USER_FUNCTION_KEYS || item isa Function
                push!(skipped, key)
                continue
            end
            out[key] = item
        end
        return out, skipped
    else
        T = typeof(value)
        if fieldcount(T) == 0
            return value, Symbol[]
        end
        out = Dict{Symbol, Any}()
        skipped = Symbol[]
        for key in fieldnames(T)
            item = getfield(value, key)
            if key in USER_FUNCTION_KEYS || item isa Function
                push!(skipped, key)
            else
                out[key] = item
            end
        end
        if isempty(out) && !isempty(skipped) && !skip_unserializable
            throw(
                ArgumentError(
                    "sampler state only contained user functions or worker objects; provide a numeric sampler_snapshot",
                ),
            )
        end
        return out, skipped
    end
end

function _serialize_atomic(path::AbstractString, value)
    tmp = string(path, ".tmp")
    try
        open(tmp, "w") do io
            serialize(io, value)
        end
        mv(tmp, path; force=true)
    catch
        isfile(tmp) && rm(tmp; force=true)
        rethrow()
    end
    return path
end

"""
    save_sampler(sampler, path; metadata=Dict(), backend_metadata=Dict())

Save a high-performance Julia checkpoint with Serialization. User function
bodies and worker objects are intentionally excluded; users must provide
callables again when restoring.
"""
function save_sampler(
    sampler,
    path::AbstractString;
    metadata=Dict{Symbol, Any}(),
    backend_metadata=Dict{Symbol, Any}(),
    skip_unserializable::Bool=false,
)
    _require_extension(path, ".jls", "sampler checkpoint")
    state_source = if hasmethod(sampler_snapshot, Tuple{typeof(sampler)})
        sampler_snapshot(sampler)
    else
        sampler
    end
    state, skipped = _sanitize_state(state_source; skip_unserializable)
    merged_metadata = _base_metadata(metadata)
    merged_metadata[:format_version] = CHECKPOINT_FORMAT_VERSION
    merged_metadata[:skipped_user_state] = skipped
    checkpoint = SamplerCheckpoint(
        state,
        merged_metadata,
        Dict(Symbol(key) => value for (key, value) in backend_metadata),
    )
    return _serialize_atomic(path, checkpoint)
end

"""
    checkpoint!(sampler, path; kwargs...)

Alias for `save_sampler` used by sampler implementations.
"""
checkpoint!(sampler, path::AbstractString; kwargs...) =
    save_sampler(sampler, path; kwargs...)

"""
    restore_sampler(path; loglikelihood, prior_transform)

Restore a checkpoint framework object and reattach user callables.
"""
function restore_sampler(
    path::AbstractString; loglikelihood=nothing, prior_transform=nothing
)
    _require_extension(path, ".jls", "sampler checkpoint")
    isnothing(loglikelihood) && throw(
        ArgumentError(
            "restore_sampler requires loglikelihood because checkpoints do not save user function bodies",
        ),
    )
    isnothing(prior_transform) && throw(
        ArgumentError(
            "restore_sampler requires prior_transform because checkpoints do not save user function bodies",
        ),
    )
    checkpoint = open(deserialize, path)
    checkpoint isa SamplerCheckpoint ||
        throw(ArgumentError("file does not contain a Dynesty sampler checkpoint"))
    checkpoint.metadata[:format_version] == CHECKPOINT_FORMAT_VERSION || throw(
        ArgumentError(
            "unsupported sampler checkpoint format version $(checkpoint.metadata[:format_version])",
        ),
    )
    if checkpoint.state isa AbstractDict &&
        get(checkpoint.state, :type, nothing) === :NestedSampler
        return _restore_nested_sampler(checkpoint.state, loglikelihood, prior_transform)
    elseif checkpoint.state isa AbstractDict &&
        get(checkpoint.state, :type, nothing) === :DynamicSampler
        return _restore_dynamic_sampler(checkpoint.state, loglikelihood, prior_transform)
    else
        return RestoredSampler(
            checkpoint.state,
            loglikelihood,
            prior_transform,
            checkpoint.metadata,
            checkpoint.backend_metadata,
        )
    end
end
