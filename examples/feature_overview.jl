using Dynesty
using Random

prior_transform(u) = -2.0 .+ 4.0 .* u
loglikelihood(v) = -0.5 * sum(abs2, v)

function main(; rng=MersenneTwister(88), nlive=40, maxiter=25)
    sampler = NestedSampler(
        loglikelihood,
        prior_transform,
        2;
        nlive,
        bound=Ellipsoid(2),
        sample=RWalkSampler(; walks=6),
        rng,
        first_update=Dict(:min_ncall => nlive, :min_eff => 100.0),
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, add_live=true, print_progress=false)
    res = results(sampler)
    stats_count = count(!isnothing, res.proposal_stats)
    plot_data = runplot(res; kde=false)
    return (
        logz=res.logz[end],
        nsamples=length(res.logl),
        proposal_stats=stats_count,
        runplot_series=length(plot_data.xseries),
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println(
        "logz=$(summary.logz) nsamples=$(summary.nsamples) proposal_stats=$(summary.proposal_stats)",
    )
end
