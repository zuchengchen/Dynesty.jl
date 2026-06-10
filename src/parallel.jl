using Distributed
using Random

abstract type AbstractMapBackend end

const PARALLEL_OPTIONS = (:serial, :none, :threads, :threaded, :distributed)
const POOL_USAGE_KEYS = (
    :initial,
    :prior_transform,
    :loglikelihood,
    :proposals,
    :bounds,
    :stopping,
)

"""
    PoolUsage(; initial=true, prior_transform=true, loglikelihood=true,
              proposals=true, bounds=false, stopping=false)

Julia-native policy describing which sampler paths may use the configured map
backend. `use_pool` dictionaries from Python-adjacent workflows are parsed into
this type; the backend object itself remains Julia-native.
"""
Base.@kwdef struct PoolUsage
    initial::Bool = true
    prior_transform::Bool = true
    loglikelihood::Bool = true
    proposals::Bool = true
    bounds::Bool = false
    stopping::Bool = false
end

function _pool_usage_key(raw_key)
    if raw_key isa Symbol
        key = raw_key
    elseif raw_key isa AbstractString
        key = Symbol(strip(String(raw_key)))
    else
        throw(
            ArgumentError(
                "pool usage keys must be symbols or strings; got $(repr(raw_key))",
            ),
        )
    end
    key === :logl && return :loglikelihood
    key === :loglike && return :loglikelihood
    key === :likelihood && return :loglikelihood
    key === :proposal && return :proposals
    key === :propose && return :proposals
    key === :propose_point && return :proposals
    key === :evolve && return :proposals
    key === :update_bound && return :bounds
    key === :bound && return :bounds
    key === :stop_function && return :stopping
    key === :stopfn && return :stopping
    key === :stop && return :stopping
    key in POOL_USAGE_KEYS || throw(
        ArgumentError(
            "unrecognized pool usage key $(repr(raw_key)); expected one of $(collect(POOL_USAGE_KEYS)) or a documented use_pool alias",
        ),
    )
    return key
end

function _pool_usage_bool(raw_value, key::Symbol)
    raw_value isa Bool ||
        throw(ArgumentError("pool usage key $(repr(key)) must be Bool; got $(repr(raw_value))"))
    return raw_value
end

function _pool_usage_pairs(value)
    if value isa AbstractDict
        return pairs(value)
    elseif value isa NamedTuple
        return ((key, getfield(value, key)) for key in keys(value))
    else
        throw(
            ArgumentError(
                "pool_usage/use_pool must be PoolUsage, Dict, or NamedTuple; got $(typeof(value))",
            ),
        )
    end
end

function _pool_usage_from_pairs(value)
    cfg = _pool_usage_config(PoolUsage())
    for (raw_key, raw_value) in _pool_usage_pairs(value)
        key = _pool_usage_key(raw_key)
        cfg[key] = _pool_usage_bool(raw_value, key)
    end
    return PoolUsage(;
        initial=cfg[:initial],
        prior_transform=cfg[:prior_transform],
        loglikelihood=cfg[:loglikelihood],
        proposals=cfg[:proposals],
        bounds=cfg[:bounds],
        stopping=cfg[:stopping],
    )
end

_pool_usage(value::PoolUsage) = value
_pool_usage(value) = isnothing(value) ? PoolUsage() : _pool_usage_from_pairs(value)

function _get_pool_usage(pool_usage=nothing, use_pool=nothing)
    if !isnothing(pool_usage) && !isnothing(use_pool)
        throw(ArgumentError("specify either pool_usage or use_pool, not both"))
    end
    return _pool_usage(isnothing(pool_usage) ? use_pool : pool_usage)
end

function _pool_usage_config(usage::PoolUsage)
    return Dict{Symbol, Any}(key => getfield(usage, key) for key in POOL_USAGE_KEYS)
end

function _pool_usage_from_config(config)
    isnothing(config) && return PoolUsage()
    return _pool_usage(config)
end

_pool_usage_initial(usage::PoolUsage) =
    usage.initial && usage.prior_transform && usage.loglikelihood

struct SerialMapBackend <: AbstractMapBackend
    queue_size::Int
end

SerialMapBackend(; queue_size=nothing) =
    SerialMapBackend(_normalize_queue_size(queue_size, 1))

struct ThreadedMapBackend <: AbstractMapBackend
    queue_size::Int
end

function ThreadedMapBackend(; queue_size=nothing)
    default = max(Threads.nthreads(), 1)
    return ThreadedMapBackend(_normalize_queue_size(queue_size, default))
end

struct DistributedMapBackend <: AbstractMapBackend
    workers::Vector{Int}
    queue_size::Int
end

function DistributedMapBackend(; workers=Distributed.workers(), queue_size=nothing)
    worker_ids = collect(Int, workers)
    default = max(length(worker_ids), 1)
    return DistributedMapBackend(worker_ids, _normalize_queue_size(queue_size, default))
end

function _normalize_queue_size(queue_size, default::Integer)
    if isnothing(queue_size)
        return Int(default)
    end
    q = Int(queue_size)
    q >= 1 || throw(ArgumentError("queue_size must be at least 1; got $queue_size"))
    return q
end

backend_kind(::SerialMapBackend) = :serial
backend_kind(::ThreadedMapBackend) = :threaded
backend_kind(::DistributedMapBackend) = :distributed

function _parallel_kind(parallel)
    if parallel isa Symbol
        kind = Symbol(lowercase(String(parallel)))
    elseif parallel isa AbstractString
        kind = Symbol(lowercase(strip(String(parallel))))
    else
        throw(
            ArgumentError(
                "parallel must be one of $(collect(PARALLEL_OPTIONS)); got $(repr(parallel))"
            ),
        )
    end
    kind in PARALLEL_OPTIONS || throw(
        ArgumentError(
            "unsupported parallel $(repr(parallel)); expected one of $(collect(PARALLEL_OPTIONS))"
        ),
    )
    return kind === :threads ? :threaded : (kind === :none ? :serial : kind)
end

function _get_map_backend(parallel=:serial, map_backend=nothing, queue_size=nothing)
    if !isnothing(map_backend)
        map_backend isa AbstractMapBackend || throw(
            ArgumentError(
                "map_backend must be an AbstractMapBackend; got $(typeof(map_backend))"
            ),
        )
        isnothing(queue_size) || throw(
            ArgumentError(
                "queue_size cannot be supplied with an explicit map_backend; configure queue_size on the backend itself",
            ),
        )
        return map_backend
    end
    kind = _parallel_kind(parallel)
    if kind === :serial
        return SerialMapBackend(; queue_size)
    elseif kind === :threaded
        return ThreadedMapBackend(; queue_size)
    elseif kind === :distributed
        return DistributedMapBackend(; queue_size)
    end
end

function _backend_config(backend::AbstractMapBackend)
    config = Dict{Symbol, Any}(
        :kind => backend_kind(backend), :queue_size => getfield(backend, :queue_size)
    )
    backend isa DistributedMapBackend && (config[:workers] = copy(backend.workers))
    return config
end

function _map_backend_from_config(config)
    isnothing(config) && return SerialMapBackend()
    cfg = Dict{Symbol, Any}(Symbol(key) => value for (key, value) in config)
    kind = Symbol(get(cfg, :kind, :serial))
    queue_size = get(cfg, :queue_size, nothing)
    if kind === :serial
        return SerialMapBackend(; queue_size)
    elseif kind === :threaded || kind === :threads
        return ThreadedMapBackend(; queue_size)
    elseif kind === :distributed
        workers = Vector{Int}(get(cfg, :workers, Distributed.workers()))
        return DistributedMapBackend(; workers, queue_size)
    else
        throw(ArgumentError("unsupported map backend checkpoint kind $(repr(kind))"))
    end
end

struct MapTaskError <: Exception
    backend::Symbol
    index::Int
    input_context::String
    cause::Any
end

function Base.showerror(io::IO, err::MapTaskError)
    print(
        io,
        "Dynesty map task failed on backend $(err.backend), task index $(err.index), input $(err.input_context): ",
    )
    showerror(io, err.cause)
end

_input_context(input) = sprint(show, input; context=:limit => true)

function _run_task(backend::AbstractMapBackend, f, index::Int, input)
    try
        return f(input)
    catch err
        throw(MapTaskError(backend_kind(backend), index, _input_context(input), err))
    end
end

"""
    map_ordered(backend, f, inputs)

Map `f` over `inputs` using a Julia-native backend. Outputs preserve input
order. Failures include the task index and a compact input representation.
"""
function map_ordered(backend::SerialMapBackend, f, inputs)
    items = collect(inputs)
    out = Vector{Any}(undef, length(items))
    for (index, input) in enumerate(items)
        out[index] = _run_task(backend, f, index, input)
    end
    return out
end

function map_ordered(backend::ThreadedMapBackend, f, inputs)
    items = collect(inputs)
    n = length(items)
    out = Vector{Any}(undef, n)
    n == 0 && return out
    nworkers = min(backend.queue_size, Threads.nthreads(), n)
    nworkers = max(nworkers, 1)
    next_index = Threads.Atomic{Int}(1)
    first_error = Ref{Union{Nothing, MapTaskError}}(nothing)
    err_lock = ReentrantLock()
    Threads.@sync for _ in 1:nworkers
        Threads.@spawn begin
            while true
                index = Threads.atomic_add!(next_index, 1)
                index > n && break
                !isnothing(first_error[]) && break
                try
                    out[index] = f(items[index])
                catch err
                    wrapped = MapTaskError(
                        backend_kind(backend), index, _input_context(items[index]), err
                    )
                    lock(err_lock) do
                        if isnothing(first_error[])
                            first_error[] = wrapped
                        end
                    end
                    break
                end
            end
        end
    end
    if !isnothing(first_error[])
        throw(first_error[])
    end
    return out
end

function map_ordered(backend::DistributedMapBackend, f, inputs)
    items = collect(inputs)
    if isempty(items)
        return Any[]
    end
    current_workers = Distributed.workers()
    active_workers = filter(w -> w != myid() && w in current_workers, backend.workers)
    if isempty(active_workers)
        return map_ordered(SerialMapBackend(; queue_size=1), f, items)
    end
    indexed = collect(enumerate(items))
    runner = pair -> _run_task(backend, f, pair[1], pair[2])
    pool = Distributed.WorkerPool(active_workers)
    return Distributed.pmap(runner, pool, indexed; batch_size=backend.queue_size)
end

function _splitmix64(x::UInt64)
    z = x + 0x9e3779b97f4a7c15
    z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
    z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
    return z ⊻ (z >> 31)
end

"""
    task_seeds(seed, n)

Deterministically split `seed` into `n` per-task seeds.
"""
function task_seeds(seed::Integer, n::Integer)
    n >= 0 || throw(ArgumentError("n must be nonnegative; got $n"))
    base = UInt64(seed % UInt64)
    return [Int(_splitmix64(base + UInt64(i)) % UInt64(typemax(Int))) for i in 1:n]
end

"""
    map_with_rng(backend, f, inputs; seed)

Map `f(input, rng)` using deterministic per-task RNGs. Reproducibility is
guaranteed for the same seed, backend, backend configuration, and queue size.
"""
function map_with_rng(backend::AbstractMapBackend, f, inputs; seed::Integer)
    items = collect(inputs)
    seeds = task_seeds(seed, length(items))
    return map_ordered(
        backend, pair -> begin
            index, input = pair
            rng = MersenneTwister(seeds[index])
            return f(input, rng)
        end, enumerate(items)
    )
end
