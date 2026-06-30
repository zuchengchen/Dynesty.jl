using Dynesty
using LinearAlgebra
using Random
using Test

regression_prior_box(u) = 20.0 .* u .- 10.0
regression_loglike_gaussian(v) = -0.5 * sum(abs2, v)

function regression_weighted_mean(res)
    weights = importance_weights(res)
    return vec(sum(res.samples .* weights; dims=1))
end

function rosenbrock_prior(u)
    return 20.0 .* u .- 10.0
end

function rosenbrock_loglike(v)
    x, y = v
    return -0.5 * ((1.0 - x)^2 + 100.0 * (y - x^2)^2)
end

function pathology_prior(u)
    return 2.0 .* u .- 1.0
end

function pathology_loglike(v)
    alpha = 1.0e-8
    return -log(max(abs(v[1]), alpha)) - 1.0e-8 * sum(abs2, v)
end

function large_negative_loglike(v)
    logp = -0.5 * sum(abs2, v)
    return v[1] < 0 ? -1.0e300 : logp
end

function static_regression_run(loglike, prior; rng, nlive, maxiter, sample=:unif)
    sampler = NestedSampler(
        loglike,
        prior,
        2;
        nlive,
        bound=:multi,
        sample,
        rng,
        walks=8,
        slices=4,
        enlarge=1.1,
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, add_live=true, print_progress=false)
    return sampler, results(sampler)
end

@testset "Python regression behavior smoke" begin
    large_sampler, large_res = static_regression_run(
        large_negative_loglike,
        regression_prior_box;
        rng=MersenneTwister(9101),
        nlive=45,
        maxiter=45,
        sample=:rslice,
    )
    @test large_sampler.ncall >= 45
    @test all(isfinite, large_res.logzerr)
    @test large_res.logzerr[end] < 5.0
    @test all(large_res.logl .>= Dynesty.LOWL_VAL)

    dynamic = DynamicSampler(
        regression_loglike_gaussian,
        regression_prior_box,
        2;
        nlive=18,
        bound=:single,
        sample=:unif,
        rng=MersenneTwister(9102),
    )
    run_nested!(dynamic; maxiter_init=10, dlogz_init=nothing, maxbatch=0)
    add_batch!(
        dynamic;
        nlive=10,
        mode=:manual,
        logl_bounds=((dynamic |> results).logl[end - 3], (dynamic |> results).logl[end]),
        maxiter=5,
        maxcall=200,
        print_progress=false,
    )
    dres = results(dynamic)
    @test sort(unique(dres.samples_batch)) == [0, 1]
    @test dres.samples_it[dres.samples_batch .== 1] |> minimum > 0
    @test dres.ncall |> sum > 0
    @test all(isfinite, dres.logz)

    pathology_sampler, pathology_res = static_regression_run(
        pathology_loglike,
        pathology_prior;
        rng=MersenneTwister(9103),
        nlive=45,
        maxiter=45,
        sample=:unif,
    )
    @test pathology_sampler.ncall >= 45
    @test all(isfinite, pathology_res.logz)
    @test pathology_res.logzerr[end] >= 0
    @test maximum(pathology_res.logl) > 1.0
end

if get(ENV, "DYNESTY_RUN_SLOW_TESTS", "false") == "true"
    @testset "Slow Python regression analogs" begin
        means = Vector{Vector{Float64}}()
        logzs = Float64[]
        for (i, sample) in enumerate((:rwalk, :rslice, :rwalk, :rslice))
            _, res = static_regression_run(
                rosenbrock_loglike,
                rosenbrock_prior;
                rng=MersenneTwister(9200 + i),
                nlive=90,
                maxiter=120,
                sample,
            )
            push!(means, regression_weighted_mean(res))
            push!(logzs, res.logz[end])
            @test all(isfinite, res.logz)
            @test res.logzerr[end] >= 0
            @test norm(means[end]) < 4.0
        end
        mean_of_means = vec(sum(reduce(hcat, means); dims=2)) ./ length(means)
        @test -1.0 < mean_of_means[1] < 2.5
        @test -1.0 < mean_of_means[2] < 5.0
        @test maximum(logzs) - minimum(logzs) < 12.0

        for (i, sample) in enumerate((:unif, :rwalk, :rslice))
            _, res = static_regression_run(
                pathology_loglike,
                pathology_prior;
                rng=MersenneTwister(9300 + i),
                nlive=80,
                maxiter=110,
                sample,
            )
            logz_truth = log(1 - log(1.0e-8))
            @test isfinite(res.logz[end])
            @test abs(res.logz[end] - logz_truth) < 6.0 * max(res.logzerr[end], 0.3)
        end
    end
end
