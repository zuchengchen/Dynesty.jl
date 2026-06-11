using Dynesty
using Distributed
using Random
using Test

mutable struct CountingMapBackend <: Dynesty.AbstractMapBackend
    queue_size::Int
    calls::Int
    sizes::Vector{Int}
end

CountingMapBackend(queue_size::Integer) = CountingMapBackend(Int(queue_size), 0, Int[])

Dynesty.backend_kind(::CountingMapBackend) = :counting

function Dynesty.map_ordered(backend::CountingMapBackend, f, inputs)
    items = collect(inputs)
    backend.calls += 1
    push!(backend.sizes, length(items))
    return Dynesty.map_ordered(SerialMapBackend(), f, items)
end

dist_parallel_prior(u) = copy(u)
dist_parallel_loglike(v) = -sum(abs2, v .- 0.5)
dist_parallel_fail(v) = error("distributed likelihood marker")

@testset "Map backends" begin
    serial = SerialMapBackend()
    @test serial.queue_size == 1
    @test map_ordered(serial, x -> x^2, [3, 2, 1]) == [9, 4, 1]
    @test_throws ArgumentError SerialMapBackend(queue_size=0)
    @test Dynesty._get_map_backend(:serial, nothing, nothing) isa SerialMapBackend
    @test_throws ArgumentError Dynesty._get_map_backend("none", nothing, nothing)

    threaded = ThreadedMapBackend(queue_size=2)
    @test map_ordered(threaded, x -> x + 1, 1:5) == [2, 3, 4, 5, 6]
    @test Dynesty._get_map_backend(:threads, nothing, 2) == threaded
    @test_throws ArgumentError Dynesty._get_map_backend("threaded", nothing, 2)

    distributed = DistributedMapBackend(workers=Int[], queue_size=2)
    @test map_ordered(distributed, x -> 2x, 1:4) == [2, 4, 6, 8]
    @test Dynesty._get_map_backend(:distributed, nothing, 2) isa DistributedMapBackend
    @test Dynesty._map_backend_from_config(Dynesty._backend_config(threaded)) == threaded
    @test_throws ArgumentError Dynesty._get_map_backend(:bad, nothing, nothing)
    @test_throws ArgumentError Dynesty._get_map_backend(:threads, threaded, 2)

    seeds1 = task_seeds(1234, 5)
    seeds2 = task_seeds(1234, 5)
    @test seeds1 == seeds2
    @test length(unique(seeds1)) == 5

    rng_values1 = map_with_rng(serial, (input, rng) -> input + rand(rng), [1, 2, 3]; seed=9)
    rng_values2 = map_with_rng(serial, (input, rng) -> input + rand(rng), [1, 2, 3]; seed=9)
    @test rng_values1 == rng_values2
end

@testset "Parallel policy parsing" begin
    default_usage = ParallelPolicy()
    @test default_usage.initialization
    @test default_usage.proposals
    @test !default_usage.bounds
    @test !default_usage.stopping
    @test Dynesty._parallel_policy_initial(default_usage)

    usage = Dynesty._get_parallel_policy((initialization=false, proposals=false))
    @test usage isa ParallelPolicy
    @test !usage.initialization
    @test !usage.proposals

    policy = Dynesty._get_parallel_policy((
        initialization=false, proposals=false, bounds=true, stopping=true
    ))
    @test policy.proposals == false
    @test policy.bounds == true
    @test policy.stopping == true
    @test !Dynesty._parallel_policy_initial(policy)

    roundtrip = Dynesty._parallel_policy_from_config(
        Dynesty._parallel_policy_config(policy)
    )
    @test roundtrip == policy

    @test_throws ArgumentError Dynesty._get_parallel_policy((unknown=true,))
    @test_throws ArgumentError Dynesty._get_parallel_policy((proposals=1,))
    @test_throws ArgumentError Dynesty._get_parallel_policy(Dict("proposals" => true))
    @test_throws ArgumentError Dynesty._get_parallel_policy(["proposals"])
end

@testset "Map errors include context" begin
    err = try
        map_ordered(SerialMapBackend(), x -> x == 2 ? error("boom") : x, [1, 2, 3])
        nothing
    catch caught
        caught
    end
    @test err isa MapTaskError
    @test err.index == 2
    @test occursin("task index 2", sprint(showerror, err))
    @test occursin("boom", sprint(showerror, err))
end

@testset "Proposal/evolve queue uses map backend" begin
    backend = CountingMapBackend(3)
    sampler = NestedSampler(
        v -> -sum(abs2, v .- 0.5),
        u -> copy(u),
        2;
        nlive=14,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(910),
        map_backend=backend,
    )
    @test backend.calls == 1
    @test backend.sizes == [14]

    run_nested!(sampler; maxiter=5, dlogz=nothing, add_live=false)
    @test backend.calls > 1
    @test any(==(3), backend.sizes[2:end])
    @test sampler.proposal_tasks_submitted >= 3
    @test sampler.proposal_batches_submitted >= 1
    @test length(results(sampler).logl) == 5
end

@testset "Proposal scheduler parsing" begin
    @test Dynesty._proposal_scheduler_symbol(:batch) == :batch
    @test_throws ArgumentError Dynesty._proposal_scheduler_symbol("async")
    @test Dynesty._proposal_scheduler_symbol(:auto) == :auto
    @test_throws ArgumentError Dynesty._proposal_scheduler_symbol(:streaming)
end

if get(ENV, "DYNESTY_RUN_DISTRIBUTED_TESTS", "false") == "true"
    @testset "Distributed proposal/evolve queue" begin
        added_workers = Int[]
        try
            needed = max(0, 2 - length(Distributed.workers()))
            if needed > 0
                added_workers = Distributed.addprocs(
                    needed; exeflags=`--project=$(Base.active_project())`
                )
            end
            for worker in Distributed.workers()
                Distributed.remotecall_wait(
                    Core.eval,
                    worker,
                    Main,
                    quote
                        using Dynesty
                        dist_parallel_prior(u) = copy(u)
                        dist_parallel_loglike(v) = -sum(abs2, v .- 0.5)
                        dist_parallel_fail(v) = error("distributed likelihood marker")
                    end,
                )
            end
            backend = DistributedMapBackend(;
                workers=Distributed.workers()[1:min(2, length(Distributed.workers()))],
                queue_size=2,
            )
            sampler = NestedSampler(
                dist_parallel_loglike,
                dist_parallel_prior,
                2;
                nlive=12,
                bound=:none,
                sample=:unif,
                rng=MersenneTwister(920),
                map_backend=backend,
            )
            run_nested!(sampler; maxiter=3, dlogz=nothing, add_live=false)
            @test sampler.proposal_tasks_submitted > 0
            @test sampler.proposal_batches_submitted > 0
            @test length(results(sampler).logl) == 3

            err = try
                NestedSampler(
                    dist_parallel_fail,
                    dist_parallel_prior,
                    2;
                    nlive=6,
                    bound=:none,
                    sample=:unif,
                    rng=MersenneTwister(921),
                    map_backend=backend,
                )
                nothing
            catch caught
                caught
            end
            @test err isa MapTaskError
            @test err.backend == :distributed
            msg = sprint(showerror, err)
            @test occursin("distributed likelihood marker", msg)
            @test occursin("Distributed backend hint", msg)
        finally
            !isempty(added_workers) && Distributed.rmprocs(added_workers)
        end
    end
end
