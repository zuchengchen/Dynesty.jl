using Dynesty
using LinearAlgebra
using Random

function correlated_precision(ndim, rho)
    cov = fill(rho, ndim, ndim)
    cov[diagind(cov)] .= 1.0
    return inv(cov), logdet(cov)
end

function main(; rng=MersenneTwister(87), ndim=25, rho=0.4, nlive=90, maxiter=75)
    invcov, logdetcov = correlated_precision(ndim, rho)
    prior_transform(u) = 5.0 .* (2.0 .* u .- 1.0)
    loglikelihood(v) = -0.5 * (dot(v, invcov * v) + ndim * log(2pi) + logdetcov)
    sampler = NestedSampler(
        loglikelihood,
        prior_transform,
        ndim;
        nlive,
        bound=:single,
        sample=:rslice,
        rng,
        slices=4,
        enlarge=1.1,
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    res = results(sampler)
    return (logz=res.logz[end], nsamples=length(res.logl), ndim)
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("ndim=$(summary.ndim) logz=$(summary.logz) nsamples=$(summary.nsamples)")
end
