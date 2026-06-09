using Dynesty
using LinearAlgebra
using Random
using Test

const IDENTITY_AXES_2 = Matrix{Float64}(I, 2, 2)

prior_identity(u) = copy(u)
loglike_center(v) = -sum((v .- 0.5) .^ 2)

@testset "UnitCube and UniformBound samplers" begin
    unit_sampler = UnitCubeSampler(ndim=2)
    ret = sample(
        unit_sampler;
        loglstar=-0.5,
        prior_transform=prior_identity,
        loglikelihood=loglike_center,
        rng=MersenneTwister(1),
    )
    @test length(ret.u) == 2
    @test unitcheck(ret.u)
    @test ret.logl > -0.5
    @test ret.ncalls >= 1
    @test length(ret.evaluation_history) == ret.ncalls

    bound = UnitCube(2)
    uniform_sampler = UniformBoundSampler()
    ret2 = sample(
        uniform_sampler;
        bound,
        loglstar=-0.5,
        prior_transform=prior_identity,
        loglikelihood=loglike_center,
        ndim=2,
        rng=MersenneTwister(2),
    )
    @test unitcheck(ret2.u)
    @test ret2.logl > -0.5
    @test haskey(ret2.proposal_stats, :n_proposals)
end

@testset "Ball proposal boundary handling" begin
    rng = MersenneTwister(3)
    u_prop, failed = propose_ball_point(
        [0.95, 0.5], 1.0, IDENTITY_AXES_2, 2, 2; rng, periodic=[1]
    )
    @test !failed
    @test 0.0 < u_prop[1] < 1.0

    u_reflect, failed_reflect = propose_ball_point(
        [0.05, 0.5], 1.0, [1.0 0.0; 0.0 0.0], 2, 2; rng=MersenneTwister(4), reflective=[1]
    )
    @test !failed_reflect
    @test 0.0 < u_reflect[1] < 1.0

    _, failed_plain = propose_ball_point(
        [0.99, 0.99], 5.0, IDENTITY_AXES_2, 2, 2; rng=MersenneTwister(5)
    )
    @test failed_plain
    @test_throws BoundsError propose_ball_point(
        [0.5, 0.5], 1.0, IDENTITY_AXES_2, 2, 2; rng=MersenneTwister(6), periodic=[0]
    )
end

@testset "Random-walk sampler" begin
    sampler = RWalkSampler(walks=8, ncdim=2, facc=0.4)
    ret = sample(
        sampler,
        [0.5, 0.5];
        loglstar=-0.5,
        axes=IDENTITY_AXES_2 .* 0.25,
        prior_transform=prior_identity,
        loglikelihood=loglike_center,
        rng=MersenneTwister(7),
    )
    @test unitcheck(ret.u)
    @test ret.logl > -0.5
    @test ret.ncalls == 8
    @test ret.proposal_stats[:n_accept] + ret.proposal_stats[:n_reject] == 8

    old_scale = sampler.scale
    Dynesty.tune!(sampler, ret.tuning_info; update=true)
    @test sampler.scale != old_scale || ret.tuning_info[:accept] == sampler.facc * 8
end

@testset "Slice samplers" begin
    slice = SliceSampler(slices=2)
    ret = sample(
        slice,
        [0.5, 0.5];
        loglstar=-0.5,
        axes=IDENTITY_AXES_2 .* 0.2,
        prior_transform=prior_identity,
        loglikelihood=loglike_center,
        rng=MersenneTwister(8),
        kwargs=Dict(:nonperiodic => [1, 2]),
    )
    @test unitcheck(ret.u)
    @test ret.logl > -0.5
    @test ret.ncalls > 0
    @test haskey(ret.proposal_stats, :n_expand)
    old_scale = slice.scale
    tune_slice(slice, ret.tuning_info; update=true)
    @test slice.scale != old_scale || ret.tuning_info[:n_expand] == 0

    rslice = RSliceSampler(slices=3)
    ret2 = sample(
        rslice,
        [0.5, 0.5];
        loglstar=-0.5,
        axes=IDENTITY_AXES_2 .* 0.2,
        prior_transform=prior_identity,
        loglikelihood=loglike_center,
        rng=MersenneTwister(9),
        kwargs=Dict(:nonperiodic => [1, 2]),
    )
    @test unitcheck(ret2.u)
    @test ret2.logl > -0.5
    @test ret2.ncalls > 0
end

@testset "Slice helper functions" begin
    history = Dynesty.EvaluationHistoryItem[]
    step = generic_slice_step(
        [0.5, 0.5],
        [0.2, 0.0],
        [1, 2],
        -0.5,
        loglike_center,
        prior_identity,
        false,
        history,
        MersenneTwister(10),
    )
    @test unitcheck(step[1])
    @test step[3] > -0.5
    @test step[4] >= 1
    @test length(history) <= step[4]

    F = x -> ([0.5 + x, 0.5], -1.0)
    @test !Dynesty._slice_doubling_accept(-0.25, F, -0.5, -1.0, 1.0, -1.0, -1.0)
    @test Dynesty._slice_doubling_accept(0.25, F, -0.5, -1.0, 1.0, -1.0, -1.0)
end
