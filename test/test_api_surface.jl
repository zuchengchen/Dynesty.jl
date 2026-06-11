using Dynesty
using Random
using Test

@testset "Julia-native public API surface" begin
    exported = Set(names(Dynesty))

    @test :run_nested! in exported
    @test :checkpoint! in exported
    @test :add_live_points! in exported
    @test :combine_runs! in exported
    @test :ParallelPolicy in exported

    @test :run_nested ∉ exported
    @test :DynamicNestedSampler ∉ exported
    @test :PoolUsage ∉ exported
    @test :citations ∉ exported
    @test :from_python_indices ∉ exported
    @test !isdefined(Dynesty, :run_nested)
    @test !isdefined(Dynesty, :DynamicNestedSampler)
    @test !isdefined(Dynesty, :PoolUsage)
    @test !isdefined(Dynesty, :citations)
    @test !isdefined(Dynesty, :from_python_indices)

    loglike(v) = -sum(abs2, v .- 0.5)
    prior(u) = copy(u)

    @test_throws ArgumentError NestedSampler(
        loglike, prior, 2; nlive=6, bound="none", sample=:unif
    )
    @test_throws ArgumentError NestedSampler(
        loglike, prior, 2; nlive=6, bound=:none, sample="unif"
    )
    @test_throws ArgumentError NestedSampler(
        loglike, prior, 2; nlive=6, bound=:none, sample=:unif, parallel="threaded"
    )
    @test_throws ArgumentError NestedSampler(
        loglike, prior, 2; nlive=6, bound=:none, sample=:unif, proposal_scheduler="batch"
    )
    @test_throws ArgumentError NestedSampler(
        loglike, prior, 2; nlive=6, bound=:none, sample=:unif, rstate=MersenneTwister(1)
    )
    @test_throws ArgumentError NestedSampler(
        loglike,
        prior,
        2;
        nlive=6,
        bound=:none,
        sample=:unif,
        random_state=MersenneTwister(1),
    )
    @test_throws ArgumentError NestedSampler(
        loglike,
        prior,
        2;
        nlive=6,
        bound=:none,
        sample=:unif,
        use_pool=Dict(:proposals => false),
    )
    @test_throws MethodError ParallelPolicy(initial=false)
    @test_throws ArgumentError Dynesty._get_parallel_policy(Dict("proposals" => false))

    sampler_a = NestedSampler(loglike, prior, 2; nlive=8, bound=:none, sample=:unif, rng=11)
    sampler_b = NestedSampler(loglike, prior, 2; nlive=8, bound=:none, sample=:unif, rng=11)
    @test sampler_a.live_u == sampler_b.live_u
    @test sampler_a.rng isa AbstractRNG
end
