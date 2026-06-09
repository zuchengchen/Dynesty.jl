using Distributed
using Random

abstract type AbstractMapBackend end

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
    active_workers = filter(!=(myid()), backend.workers)
    if isempty(active_workers)
        return map_ordered(SerialMapBackend(; queue_size=1), f, items)
    end
    indexed = collect(enumerate(items))
    runner = pair -> _run_task(backend, f, pair[1], pair[2])
    return Distributed.pmap(runner, indexed; batch_size=backend.queue_size)
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
