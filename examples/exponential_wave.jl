using Dynesty
using Random

const EXPWAVE_TRUTH = (
    logna=log10(0.8),
    logfa=log10(4.2 / 4.0),
    pa=0.1,
    lognb=log10(0.3),
    logfb=log10(42.0 / 10.0),
    pb=2.4,
    logsigma=log10(0.2),
)

function expwave_model(x, theta)
    logna, logfa, pa, lognb, logfb, pb, logsigma = theta
    _ = logsigma
    na, fa = 10.0^logna, 10.0^logfa
    nb, fb = 10.0^lognb, 10.0^logfb
    return exp.(na .* sin.(x .* fa .+ pa) .+ nb .* sin.(x .* fb .+ pb))
end

function make_expwave_data(; rng=MersenneTwister(916301), n=48)
    x = sort!(2.0 * pi .* rand(rng, n))
    theta = [
        EXPWAVE_TRUTH.logna,
        EXPWAVE_TRUTH.logfa,
        EXPWAVE_TRUTH.pa,
        EXPWAVE_TRUTH.lognb,
        EXPWAVE_TRUTH.logfb,
        EXPWAVE_TRUTH.pb,
        EXPWAVE_TRUTH.logsigma,
    ]
    ypred = expwave_model(x, theta)
    sigma = 10.0^EXPWAVE_TRUTH.logsigma
    y = ypred .+ sigma .* randn(rng, n)
    return x, y
end

function expwave_prior_transform(u)
    return [
        4.0 * u[1] - 2.0,
        4.0 * u[2] - 2.0,
        2.0 * pi * u[3],
        4.0 * u[4] - 2.0,
        4.0 * u[5] - 2.0,
        2.0 * pi * u[6],
        2.0 * u[7] - 2.0,
    ]
end

function make_expwave_loglikelihood(x, y)
    return function (theta)
        ypred = expwave_model(x, theta)
        sigma = 10.0^theta[7]
        sigma2 = sigma^2
        logl = -0.5 * sum((ypred .- y) .^ 2 ./ sigma2 .+ log(2.0 * pi * sigma2))
        return isfinite(logl) ? logl : -1.0e300
    end
end

function main(; rng=MersenneTwister(916302), nlive=55, maxiter=62)
    x, y = make_expwave_data()
    sampler = NestedSampler(
        make_expwave_loglikelihood(x, y),
        expwave_prior_transform,
        7;
        nlive,
        bound=:multi,
        sample=:rwalk,
        walks=4,
        periodic=[3, 6],
        rng,
        enlarge=1.2,
        bootstrap=0,
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    res = results(sampler)
    return (logz=res.logz[end], maxlogl=maximum(res.logl), nsamples=length(res.logl))
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) maxlogl=$(summary.maxlogl)")
end
