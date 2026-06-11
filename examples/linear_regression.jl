using Dynesty
using Random

const LINEAR_TRUTH = (m=-0.9594, b=4.294, f=0.534)

function make_linear_data(; rng=MersenneTwister(56101), n=32)
    x = sort!(10.0 .* rand(rng, n))
    yerr = 0.1 .+ 0.5 .* rand(rng, n)
    ytrue = LINEAR_TRUTH.m .* x .+ LINEAR_TRUTH.b
    y = ytrue .+ abs.(LINEAR_TRUTH.f .* ytrue) .* randn(rng, n)
    y .+= yerr .* randn(rng, n)
    return x, y, yerr
end

function linear_prior_transform(u)
    return [5.5 * u[1] - 5.0, 10.0 * u[2], 11.0 * u[3] - 10.0]
end

function make_linear_loglikelihood(x, y, yerr)
    return function (theta)
        m, b, lnf = theta
        model = m .* x .+ b
        inv_sigma2 = 1.0 ./ (yerr .^ 2 .+ model .^ 2 .* exp(2.0 * lnf))
        return -0.5 * sum((y .- model) .^ 2 .* inv_sigma2 .- log.(inv_sigma2))
    end
end

function main(; rng=MersenneTwister(56102), nlive=45, maxiter_init=42, maxiter_batch=12)
    x, y, yerr = make_linear_data()
    sampler = DynamicSampler(
        make_linear_loglikelihood(x, y, yerr),
        linear_prior_transform,
        3;
        nlive,
        bound=:multi,
        sample=:rwalk,
        walks=4,
        rng,
        enlarge=1.15,
        bootstrap=0,
    )
    run_nested!(
        sampler;
        maxiter_init,
        dlogz_init=nothing,
        nlive_batch=12,
        maxbatch=1,
        maxiter_batch,
        maxcall_batch=800,
        use_stop=false,
        print_progress=false,
    )
    res = results(sampler)
    weights = importance_weights(res)
    mean, _ = mean_and_cov(res.samples, weights)
    return (
        logz=res.logz[end],
        nsamples=length(res.logl),
        mean=mean,
        truth=[LINEAR_TRUTH.m, LINEAR_TRUTH.b, log(LINEAR_TRUTH.f)],
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) mean=$(summary.mean)")
end
