using Dynesty
using Random

prior_transform(u) = [2.0 * u[1] - 1.0, 2.0 * u[2] - 1.0]
loglikelihood(v) = -0.5 * ((v[1] / 0.18)^2 + (v[2] / 0.32)^2)

function main(; rng=MersenneTwister(22), nlive=32, nlive_batch=12)
    sampler = DynamicNestedSampler(
        loglikelihood, prior_transform, 2; nlive, bound=:none, sample=:unif, rng
    )
    run_nested!(
        sampler;
        maxiter_init=28,
        dlogz_init=nothing,
        nlive_batch,
        maxbatch=1,
        maxiter_batch=10,
        maxcall_batch=500,
        use_stop=false,
        print_progress=false,
    )
    res = results(sampler)
    return (
        logz=res.logz[end],
        nsamples=length(res.logl),
        nbatches=length(res.batch_nlive),
        batches=sort(unique(res.samples_batch)),
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println(
        "logz=$(summary.logz) nsamples=$(summary.nsamples) nbatches=$(summary.nbatches)"
    )
end
