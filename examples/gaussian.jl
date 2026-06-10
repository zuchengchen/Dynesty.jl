using Dynesty
using Random

const MU = [0.2, -0.3]
const SIGMA = [0.12, 0.20]

prior_transform(u) = [-1.0 + 2.0 * u[1], -1.0 + 2.0 * u[2]]
loglikelihood(v) = -0.5 * sum(((v .- MU) ./ SIGMA) .^ 2)

function main(; rng=MersenneTwister(44), nlive=45, maxiter=50)
    sampler = NestedSampler(
        loglikelihood,
        prior_transform,
        2;
        nlive,
        bound=:multi,
        sample=:unif,
        rng,
        enlarge=1.1,
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    res = results(sampler)
    weights = importance_weights(res)
    mean = vec(sum(res.samples .* weights; dims=1))
    return (logz=res.logz[end], mean=mean, nsamples=length(res.logl))
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) mean=$(summary.mean)")
end
