using Dynesty
using Random

function make_prior(ndim)
    return u -> -3.0 .+ 6.0 .* u
end

function make_loglikelihood(ndim)
    scales = range(0.15, 0.35; length=ndim)
    return v -> -0.5 * sum((v ./ scales) .^ 2)
end

function main(; rng=MersenneTwister(77), ndim=6, nlive=70, maxiter=75)
    sampler = NestedSampler(
        make_loglikelihood(ndim),
        make_prior(ndim),
        ndim;
        nlive,
        bound=:single,
        sample=:unif,
        rng,
        enlarge=1.1,
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    res = results(sampler)
    return (logz=res.logz[end], ndim, nsamples=length(res.logl))
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("ndim=$(summary.ndim) logz=$(summary.logz) nsamples=$(summary.nsamples)")
end
