using Dynesty
using LinearAlgebra
using Random
using Test

static_prior_identity(u) = copy(u)
static_loglike_gaussian(v) = -0.5 * sum(((v .- 0.5) ./ 0.12) .^ 2)

@testset "Static sampler factories and live points" begin
    @test Dynesty._get_bound(:none, 2) isa UnitCube
    @test Dynesty._get_bound("single", 2) isa Ellipsoid
    @test Dynesty._get_bound(:multi, 2) isa MultiEllipsoid
    @test Dynesty._get_bound(:balls, 2) isa RadFriends
    @test Dynesty._get_bound(:cubes, 2) isa SupFriends
    @test_throws ArgumentError Dynesty._get_bound(:unknown, 2)

    @test Dynesty._get_internal_sampler(:auto, 2, 2) isa UniformBoundSampler
    @test Dynesty._get_internal_sampler(:rwalk, 2, 2; walks=7) isa RWalkSampler
    @test Dynesty._get_internal_sampler(:slice, 2, 2; slices=2) isa SliceSampler
    @test Dynesty._get_internal_sampler(:rslice, 2, 2; slices=2) isa RSliceSampler
    @test_throws BoundsError Dynesty._get_internal_sampler(:rwalk, 2, 2; periodic=[0])
    @test_throws ArgumentError Dynesty._get_internal_sampler(
        :rwalk, 2, 2; periodic=[1], reflective=[1]
    )
    @test Dynesty._get_enlarge_bootstrap(UnitCubeSampler(; ndim=2), nothing, 4) == (1.0, 4)

    live, logvol_init, ncalls = Dynesty._initialize_live_points(
        nothing,
        u -> (2u[1] - 1, 2u[2] - 1),
        v -> -sum(abs2, v);
        nlive=12,
        ndim=2,
        rng=MersenneTwister(11),
    )
    live_u, live_v, live_logl, live_blobs = live
    @test size(live_u) == (12, 2)
    @test size(live_v) == (12, 2)
    @test length(live_logl) == 12
    @test live_blobs === nothing
    @test logvol_init == 0.0
    @test ncalls == 12
    @test all(0 .< live_u .< 1)
    @test all(isfinite, live_logl)

    @test_throws ArgumentError Dynesty._initialize_live_points(
        nothing, static_prior_identity, v -> NaN; nlive=4, ndim=2, rng=MersenneTwister(12)
    )
end

@testset "Static nested sampler smoke run" begin
    sampler = NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=40,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(21),
    )
    @test sampler.map_backend isa SerialMapBackend
    @test sampler.map_backend.queue_size == 1
    @test size(sampler.live_u) == (40, 2)
    @test size(sampler.live_v) == (40, 2)
    @test sampler.ncall == 40

    run_nested!(sampler; maxiter=35, dlogz=nothing, add_live=true, print_progress=false)
    res = results(sampler)
    @test res isa Results
    @test size(res.samples, 2) == 2
    @test size(res.samples_u, 1) == length(res.logl)
    @test length(res.logl) == 75
    @test all(isfinite, res.logz)
    @test all(diff(res.logvol) .< 0)
    @test res.logzerr[end] >= 0
    @test sampler.added_live
    @test n_effective(sampler) > 1
    @test importance_weights(res) ≈
        exp.(res.logwt .- res.logz[end]) ./ sum(exp.(res.logwt .- res.logz[end]))
end

@testset "Static sampler progress callback" begin
    sampler = NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=20,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(22),
    )
    calls = Ref(0)
    seen = Ref{Any}(nothing)
    callback = function (itresult, niter, ncall; kwargs...)
        calls[] += 1
        seen[] = (itresult=itresult, niter=niter, ncall=ncall, kwargs=kwargs)
        return nothing
    end
    run_nested!(
        sampler;
        maxiter=3,
        dlogz=0.0,
        add_live=false,
        print_progress=true,
        print_func=callback,
    )
    @test calls[] == 3
    @test seen[].niter == sampler.it
    @test seen[].ncall == sampler.ncall
    @test haskey(Dict(seen[].kwargs), :dlogz)
    @test isfinite(seen[].itresult.logz)
end

@testset "Static sampler parallel backend interface" begin
    threaded_backend = ThreadedMapBackend(queue_size=2)
    sampler = NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=24,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(51),
        map_backend=threaded_backend,
    )
    @test sampler.map_backend === threaded_backend
    run_nested!(sampler; maxiter=10, dlogz=nothing, add_live=true)
    res = results(sampler)
    @test res isa Results
    @test length(res.logl) == 34
    @test all(isfinite, res.logz)

    symbol_sampler = NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=8,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(52),
        parallel=:threads,
        queue_size=2,
    )
    @test symbol_sampler.map_backend isa ThreadedMapBackend
    @test symbol_sampler.map_backend.queue_size == 2

    string_sampler = NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=8,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(53),
        parallel="threaded",
        queue_size=2,
    )
    @test string_sampler.map_backend isa ThreadedMapBackend
    @test string_sampler.map_backend.queue_size == 2

    none_sampler = NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=6,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(54),
        parallel=:none,
    )
    @test none_sampler.map_backend isa SerialMapBackend

    @test_throws ArgumentError NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=6,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(55),
        parallel=:unknown,
    )
    @test_throws ArgumentError NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=6,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(56),
        map_backend=ThreadedMapBackend(queue_size=2),
        queue_size=2,
    )
end

@testset "Static sampler parallel live-point errors" begin
    err = try
        NestedSampler(
            v -> error("parallel likelihood marker"),
            static_prior_identity,
            2;
            nlive=6,
            bound=:none,
            sample=:unif,
            rng=MersenneTwister(61),
            parallel=:threads,
            queue_size=2,
        )
        nothing
    catch caught
        caught
    end
    @test err isa MapTaskError
    @test err.backend == :threaded
    @test 1 <= err.index <= 6
    msg = sprint(showerror, err)
    @test occursin("task index", msg)
    @test occursin("input", msg)
    @test occursin("parallel likelihood marker", msg)
end

@testset "Static sampler threaded reproducibility and checkpoint restore" begin
    function threaded_run(seed)
        sampler = NestedSampler(
            static_loglike_gaussian,
            static_prior_identity,
            2;
            nlive=18,
            bound=:none,
            sample=:unif,
            rng=MersenneTwister(seed),
            parallel=:threads,
            queue_size=2,
        )
        run_nested!(sampler; maxiter=12, dlogz=nothing, add_live=true)
        res = results(sampler)
        return (
            logl=copy(res.logl),
            samples_u=copy(res.samples_u),
            logz=copy(res.logz),
            ncall=copy(res.ncall),
        )
    end
    first = threaded_run(71)
    second = threaded_run(71)
    @test first.logl == second.logl
    @test first.samples_u == second.samples_u
    @test first.logz == second.logz
    @test first.ncall == second.ncall

    sampler = NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=18,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(72),
        parallel=:threads,
        queue_size=2,
    )
    run_nested!(sampler; maxiter=5, dlogz=nothing, add_live=false)
    mktempdir() do dir
        path = joinpath(dir, "threaded_sampler.jls")
        checkpoint!(sampler, path)
        restored = restore_sampler(
            path; loglikelihood=static_loglike_gaussian, prior_transform=static_prior_identity
        )
        @test restored isa NestedSampler
        @test restored.map_backend isa ThreadedMapBackend
        @test restored.map_backend.queue_size == 2
        run_nested!(restored; maxiter=3, dlogz=nothing, add_live=true)
        @test restored.added_live
        @test length(results(restored).logl) == 5 + 3 + restored.nlive
    end
end

@testset "Static sampler bounds, blobs, and checkpoint restore" begin
    blob_loglike(v) = (static_loglike_gaussian(v), (radius=norm(v .- 0.5), first=v[1]))
    sampler = NestedSampler(
        blob_loglike,
        static_prior_identity,
        2;
        nlive=35,
        bound=:single,
        sample=:rwalk,
        walks=5,
        first_update=Dict(:min_ncall => 35, :min_eff => 100.0),
        bootstrap=0,
        blob=true,
        rng=MersenneTwister(31),
    )
    run_nested!(sampler; maxiter=12, dlogz=nothing, add_live=false)
    @test !sampler.unit_cube_sampling
    @test sampler.bound isa Ellipsoid
    res = results(sampler)
    @test length(res.logl) == 12
    @test haskey(res, :blobs)
    @test length(res.blobs) == 12
    @test res.blobs[1].radius >= 0
    @test :bound in keys(res)

    mktempdir() do dir
        path = joinpath(dir, "static_sampler.jls")
        checkpoint!(sampler, path)
        restored = restore_sampler(
            path; loglikelihood=blob_loglike, prior_transform=static_prior_identity
        )
        @test restored isa NestedSampler
        @test restored.ndim == sampler.ndim
        @test restored.nlive == sampler.nlive
        @test restored.ncall == sampler.ncall
        @test length(results(restored).logl) == length(res.logl)
        run_nested!(restored; maxiter=3, dlogz=nothing, add_live=true)
        @test restored.added_live
        @test length(results(restored).logl) == 12 + 3 + restored.nlive
    end
end

@testset "Static sampler ellipsoid bootstrap update" begin
    sampler = NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=30,
        bound=:single,
        sample=:rwalk,
        walks=4,
        first_update=Dict(:min_ncall => 30, :min_eff => 100.0),
        bootstrap=3,
        rng=MersenneTwister(36),
    )
    run_nested!(sampler; maxiter=6, dlogz=nothing, add_live=false)
    @test sampler.bound isa Ellipsoid
    @test sampler.bound_bootstrap == 3
    @test sampler.nbound >= 1
    @test all(isfinite, results(sampler).logz)
end

@testset "Static sampler periodic and reflective dimensions" begin
    sampler = NestedSampler(
        static_loglike_gaussian,
        static_prior_identity,
        2;
        nlive=25,
        bound=:single,
        sample=:rwalk,
        walks=4,
        periodic=[1],
        reflective=[2],
        first_update=Dict(:min_ncall => 25, :min_eff => 100.0),
        bootstrap=0,
        rng=MersenneTwister(41),
    )
    run_nested!(sampler; maxiter=8, dlogz=nothing, add_live=true)
    res = results(sampler)
    @test size(res.samples_u, 2) == 2
    @test all(0 .< res.samples_u .< 1)
end
