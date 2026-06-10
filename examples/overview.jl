using Dynesty
using Random

prior_transform(u) = [-5.0 + 10.0 * u[1], -5.0 + 10.0 * u[2]]
loglikelihood(v) = -0.5 * (v[1]^2 + v[2]^2)

function main(; rng=MersenneTwister(11), nlive=40, maxiter=45)
    sampler = NestedSampler(
        loglikelihood, prior_transform, 2; nlive, bound=:single, sample=:unif, rng
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    res = results(sampler)
    return (logz=res.logz[end], logzerr=res.logzerr[end], nsamples=length(res.logl))
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) logzerr=$(summary.logzerr) nsamples=$(summary.nsamples)")
end
