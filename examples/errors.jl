using Dynesty
using Random

prior_transform(u) = [u[1]]
loglikelihood(v) = -0.5 * ((v[1] - 0.4) / 0.08)^2

function main(; rng=MersenneTwister(33))
    sampler = NestedSampler(
        loglikelihood, prior_transform, 1; nlive=35, bound=:none, sample=:unif, rng
    )
    run_nested!(sampler; maxiter=35, dlogz=nothing, print_progress=false)
    res = results(sampler)
    jittered = jitter_run(res; rng=MersenneTwister(34))
    resampled = resample_run(res; rng=MersenneTwister(35))
    return (
        logz=res.logz[end],
        jitter_logz=jittered.logz[end],
        resampled_logz=resampled.logz[end],
        neff=n_effective(sampler),
        nsamples=length(res.logl),
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println(
        "logz=$(summary.logz) jitter=$(summary.jitter_logz) resampled=$(summary.resampled_logz)",
    )
end
