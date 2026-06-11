using Dynesty
using LinearAlgebra
using Random

const NOISY_NDIM = 3
const NOISY_LOGNORM = -0.5 * NOISY_NDIM * log(2.0 * pi)

prior_transform(u) = 20.0 .* u .- 10.0

function gaussian_loglikelihood(x)
    return -0.5 * dot(x, x) + NOISY_LOGNORM
end

function make_noisy_loglikelihood(; rng=MersenneTwister(819), noise=1.0)
    return function (x)
        xp = x .+ noise .* randn(rng, length(x))
        bias_correction = -0.5 * noise^2 * length(x)
        return gaussian_loglikelihood(xp) - bias_correction
    end
end

function run_case(loglikelihood; rng, nlive, maxiter)
    sampler = NestedSampler(
        loglikelihood, prior_transform, NOISY_NDIM; nlive, bound=:single, sample=:unif, rng
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    return results(sampler)
end

function main(; rng=MersenneTwister(820), nlive=42, maxiter=48)
    clean = run_case(gaussian_loglikelihood; rng, nlive, maxiter)
    noisy = run_case(
        make_noisy_loglikelihood(; rng=MersenneTwister(821));
        rng=MersenneTwister(822),
        nlive,
        maxiter,
    )
    corrected = reweight_run(
        noisy, [gaussian_loglikelihood(row) for row in eachrow(noisy.samples)]
    )
    clean_mean, clean_cov = mean_and_cov(clean.samples, importance_weights(clean))
    corrected_mean, corrected_cov = mean_and_cov(
        corrected.samples, importance_weights(corrected)
    )
    return (
        logz=corrected.logz[end],
        clean_logz=clean.logz[end],
        noisy_logz=noisy.logz[end],
        nsamples=length(corrected.logl),
        clean_mean=clean_mean,
        corrected_mean=corrected_mean,
        clean_var=diag(clean_cov),
        corrected_var=diag(corrected_cov),
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println(
        "logz=$(summary.logz) noisy_logz=$(summary.noisy_logz) corrected_var=$(summary.corrected_var)",
    )
end
