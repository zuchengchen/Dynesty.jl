using Dynesty
using Random

const HYPER_SIGMA = 0.18
const HYPER_SHAPE = 2.0

prior_transform(u) = copy(u)

function loglikelihood(v)
    radius = maximum(abs.((v .- 0.5) ./ HYPER_SIGMA))
    return -(radius)^(1 / HYPER_SHAPE)
end

function main(; rng=MersenneTwister(82), ndim=4, nlive=55, maxiter=55)
    sampler = NestedSampler(
        loglikelihood,
        prior_transform,
        ndim;
        nlive,
        bound=:multi,
        sample=:unif,
        rng,
        enlarge=1.1,
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    res = results(sampler)
    return (logz=res.logz[end], nsamples=length(res.logl), ndim)
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) nsamples=$(summary.nsamples) ndim=$(summary.ndim)")
end
