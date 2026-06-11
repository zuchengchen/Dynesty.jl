using Dynesty
using Random
using Statistics

const PYRAMID_S = 100.0
const PYRAMID_SIGMA = 1.0

prior_transform(u) = collect(u)

function hyper_pyramid_loglikelihood(x)
    radius = maximum(abs.((x .- 0.5) ./ PYRAMID_SIGMA))
    return -(radius)^(1.0 / PYRAMID_S)
end

function shrinkage_slices(logl, ndim)
    vol = (2.0 .* ((-logl) .^ PYRAMID_S)) .^ ndim
    t = vol[2:end] ./ vol[1:(end - 1)]
    return 1.0 .- t .^ (1.0 / ndim)
end

function main(; rng=MersenneTwister(121), ndim=4, nlive=60, maxiter=70)
    sampler = NestedSampler(
        hyper_pyramid_loglikelihood,
        prior_transform,
        ndim;
        nlive,
        bound=:multi,
        sample=:unif,
        rng,
        enlarge=1.0,
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, add_live=false, print_progress=false)
    res = results(sampler)
    slices = shrinkage_slices(res.logl, ndim)
    return (
        logz=res.logz[end],
        nsamples=length(res.logl),
        mean_slice=mean(slices),
        expected_slice=1.0 / (ndim * nlive + 1.0),
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) mean_slice=$(summary.mean_slice)")
end
