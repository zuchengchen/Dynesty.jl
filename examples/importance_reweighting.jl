using Dynesty
using LinearAlgebra
using Random

const RW_COV_OLD = Matrix{Float64}(I, 3, 3)
const RW_COV_NEW = [
    1.0 0.55 0.25
    0.55 1.0 0.35
    0.25 0.35 1.0
]
const RW_INV_OLD = inv(RW_COV_OLD)
const RW_INV_NEW = inv(RW_COV_NEW)
const RW_LOGDET_OLD = logdet(RW_COV_OLD)
const RW_LOGDET_NEW = logdet(RW_COV_NEW)

prior_transform(u) = -4.0 .+ 8.0 .* u

function mvn_loglike(v, invcov, logdetcov)
    return -0.5 * (dot(v, invcov * v) + length(v) * log(2pi) + logdetcov)
end

old_loglikelihood(v) = mvn_loglike(v, RW_INV_OLD, RW_LOGDET_OLD)
new_loglikelihood(v) = mvn_loglike(v, RW_INV_NEW, RW_LOGDET_NEW)

function main(; rng=MersenneTwister(86), nlive=55, maxiter=60)
    sampler = DynamicNestedSampler(
        old_loglikelihood,
        prior_transform,
        3;
        nlive,
        bound=:multi,
        sample=:unif,
        rng,
        enlarge=1.1,
        bootstrap=0,
    )
    run_nested!(
        sampler;
        maxiter_init=maxiter,
        dlogz_init=nothing,
        nlive_batch=12,
        maxbatch=1,
        maxiter_batch=8,
        maxcall_batch=400,
        use_stop=false,
        print_progress=false,
    )
    res = results(sampler)
    reweighted = reweight_run(res, [new_loglikelihood(row) for row in eachrow(res.samples)])
    return (
        logz=res.logz[end],
        reweighted_logz=reweighted.logz[end],
        nsamples=length(res.logl),
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println(
        "logz=$(summary.logz) reweighted=$(summary.reweighted_logz) nsamples=$(summary.nsamples)",
    )
end
