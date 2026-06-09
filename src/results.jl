using Random

const RESULTS_ALLOWED_KEYS = Set{Symbol}((
    :samples,
    :samples_u,
    :samples_id,
    :samples_it,
    :samples_n,
    :live_points,
    :live_u,
    :live_v,
    :live_logl,
    :logl,
    :logvol,
    :logwt,
    :logz,
    :logzerr,
    :logzvar,
    :h,
    :nlive,
    :niter,
    :ncall,
    :eff,
    :information,
    :bound,
    :bound_iter,
    :boundidx,
    :proposal_stats,
    :blobs,
    :batch,
    :batch_nlive,
    :batch_logl_bounds,
))

"""
    Results(pairs_or_dict)
    Results(; kwargs...)

Immutable user-facing results container. Public arrays follow Python dynesty's
shape convention: `samples`, `samples_u`, `live_u`, and `live_v` are
`nsamples x ndim`/`nlive x ndim`.
"""
struct Results
    data::Dict{Symbol, Any}
    order::Vector{Symbol}
    dynamic::Bool
end

Results(; kwargs...) = Results(Dict{Symbol, Any}(kwargs))

function Results(key_values)
    pairs_iter = key_values isa AbstractDict ? pairs(key_values) : key_values
    data = Dict{Symbol, Any}()
    order = Symbol[]
    for (raw_key, value) in pairs_iter
        key = Symbol(raw_key)
        key === :blob && (key = :blobs)
        key in RESULTS_ALLOWED_KEYS ||
            throw(ArgumentError("unknown Results key $(repr(key))"))
        haskey(data, key) && throw(ArgumentError("duplicate Results key $(repr(key))"))
        data[key] = _result_copy(value)
        push!(order, key)
    end
    for required in (:samples_u, :samples_id, :logl, :samples)
        haskey(data, required) ||
            throw(ArgumentError("Results key $(repr(required)) must be provided"))
    end
    if !haskey(data, :proposal_stats)
        data[:proposal_stats] = nothing
        push!(order, :proposal_stats)
    end
    dynamic = if haskey(data, :nlive)
        false
    elseif haskey(data, :samples_n)
        true
    else
        throw(ArgumentError("Results requires either :nlive or :samples_n"))
    end
    return Results(data, order, dynamic)
end

function Base.getproperty(res::Results, name::Symbol)
    if name in (:data, :order, :dynamic)
        return getfield(res, name)
    elseif haskey(getfield(res, :data), name)
        return getfield(res, :data)[name]
    else
        return getfield(res, name)
    end
end

function Base.getindex(res::Results, key::Symbol)
    haskey(res.data, key) || throw(KeyError(key))
    return res.data[key]
end

Base.getindex(res::Results, key::AbstractString) = getindex(res, Symbol(key))
Base.haskey(res::Results, key::Symbol) = haskey(res.data, key)
Base.keys(res::Results) = copy(res.order)
Base.pairs(res::Results) = ((key, res.data[key]) for key in res.order)

_result_copy(value) = value
_result_copy(value::AbstractArray) = copy(value)
_result_copy(value::AbstractDict) = copy(value)

function asdict(res::Results)
    return Dict(key => _result_copy(res.data[key]) for key in res.order)
end

isdynamic(res::Results) = res.dynamic

function Base.show(io::IO, res::Results)
    print(io, "Results(")
    print(io, join(string.(res.order), ", "))
    print(io, ")")
end

function importance_weights(res::Results)
    haskey(res, :logwt) || throw(KeyError(:logwt))
    haskey(res, :logz) || throw(KeyError(:logz))
    logwt = Float64.(res[:logwt]) .- Float64(last(res[:logz]))
    weights = exp.(logwt)
    return weights ./ sum(weights)
end

function samples_equal(res::Results; rng::AbstractRNG=Random.default_rng())
    return resample_equal(res[:samples], importance_weights(res); rng)
end

function results_substitute(res::Results, replacements::AbstractDict)
    data = asdict(res)
    for (raw_key, value) in replacements
        key = Symbol(raw_key)
        key === :blob && (key = :blobs)
        haskey(data, key) || throw(KeyError(key))
        data[key] = value
    end
    return Results([(key, data[key]) for key in res.order])
end
