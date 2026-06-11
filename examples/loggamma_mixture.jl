using Dynesty
using Random

logsumexp2(a, b) = max(a, b) + log(exp(a - max(a, b)) + exp(b - max(a, b)))

function unit_normal_logpdf(x; loc, scale)
    z = (x - loc) / scale
    return -0.5 * z^2 - log(scale) - 0.5 * log(2.0 * pi)
end

function unit_loggamma_logpdf(x; loc, scale)
    y = (x - loc) / scale
    return y - exp(y) - log(scale)
end

function mixture_loggamma_coordinate(x)
    a = unit_loggamma_logpdf(x; loc=1.0 / 3.0, scale=1.0 / 30.0)
    b = unit_loggamma_logpdf(x; loc=2.0 / 3.0, scale=1.0 / 30.0)
    return logsumexp2(a, b) + log(0.5)
end

function mixture_normal_coordinate(x)
    a = unit_normal_logpdf(x; loc=1.0 / 3.0, scale=1.0 / 30.0)
    b = unit_normal_logpdf(x; loc=2.0 / 3.0, scale=1.0 / 30.0)
    return logsumexp2(a, b) + log(0.5)
end

prior_transform(u) = collect(u)

function make_loggamma_loglikelihood(ndim)
    return function (x)
        logl = mixture_loggamma_coordinate(x[1]) + mixture_normal_coordinate(x[2])
        for i in 3:ndim
            logl += if i <= (ndim + 2) / 2
                unit_loggamma_logpdf(x[i]; loc=2.0 / 3.0, scale=1.0 / 30.0)
            else
                unit_normal_logpdf(x[i]; loc=2.0 / 3.0, scale=1.0 / 30.0)
            end
        end
        return isfinite(logl) ? logl : -1.0e300
    end
end

function main(; rng=MersenneTwister(1028), ndim=4, nlive=60, maxiter=65)
    sampler = NestedSampler(
        make_loggamma_loglikelihood(ndim),
        prior_transform,
        ndim;
        nlive,
        bound=:multi,
        sample=:rwalk,
        walks=4,
        rng,
        enlarge=1.15,
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    res = results(sampler)
    weights = importance_weights(res)
    mean, _ = mean_and_cov(res.samples, weights)
    return (logz=res.logz[end], ndim, mean=mean, nsamples=length(res.logl))
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("ndim=$(summary.ndim) logz=$(summary.logz) mean=$(summary.mean)")
end
