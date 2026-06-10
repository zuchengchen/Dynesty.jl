using Dynesty
using Random

prior_transform(u) = [10.0 * pi * u[1], 10.0 * pi * u[2]]

function loglikelihood(v)
    amp = 2.0 + cos(v[1] / 2.0) * cos(v[2] / 2.0)
    return 5.0 * log(amp)
end

function main(; rng=MersenneTwister(55), nlive=50, maxiter=55)
    sampler = NestedSampler(
        loglikelihood,
        prior_transform,
        2;
        nlive,
        bound=:multi,
        sample=:unif,
        rng,
        enlarge=1.2,
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    res = results(sampler)
    return (logz=res.logz[end], maxlogl=maximum(res.logl), nsamples=length(res.logl))
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) maxlogl=$(summary.maxlogl)")
end
