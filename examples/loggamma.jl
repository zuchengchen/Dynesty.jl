using Dynesty
using Random
using SpecialFunctions

const LOGGAMMA_K = 3.0
const LOGGAMMA_THETA = 0.8

function prior_transform(u)
    return [-5.0 + 10.0u[1], -5.0 + 10.0u[2]]
end

function loggamma_logpdf(x; k=LOGGAMMA_K, theta=LOGGAMMA_THETA)
    return k * x - exp(x) / theta - loggamma(k) - k * log(theta)
end

function logsum2(a, b)
    m = max(a, b)
    return m + log(exp(a - m) + exp(b - m))
end

function loglikelihood(v)
    x, y = v
    comp1 = loggamma_logpdf(x) - 0.5 * ((y - 0.8) / 0.45)^2 - log(0.45)
    comp2 = loggamma_logpdf(-x; k=2.2, theta=0.7) -
            0.5 * ((y + 1.0) / 0.55)^2 - log(0.55)
    return logsum2(log(0.6) + comp1, log(0.4) + comp2)
end

function main(; rng=MersenneTwister(84), nlive=55, maxiter=60)
    sampler = NestedSampler(
        loglikelihood,
        prior_transform,
        2;
        nlive,
        bound=:multi,
        sample=:unif,
        rng,
        enlarge=1.15,
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    res = results(sampler)
    return (logz=res.logz[end], nsamples=length(res.logl), ndim=2)
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) nsamples=$(summary.nsamples)")
end
