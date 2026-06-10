using Dynesty
using Random

prior_transform(u) = [-6.0 + 12.0 * u[1], -6.0 + 12.0 * u[2]]

function shell_logl(v, center, radius, width)
    r = sqrt(sum(abs2, v .- center))
    return -0.5 * ((r - radius) / width)^2
end

function loglikelihood(v)
    l1 = shell_logl(v, [-2.0, -2.0], 2.0, 0.18)
    l2 = shell_logl(v, [2.0, 2.0], 2.0, 0.18)
    m = max(l1, l2)
    return m + log(exp(l1 - m) + exp(l2 - m))
end

function main(; rng=MersenneTwister(66), nlive=55, maxiter=60)
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
