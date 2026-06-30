using Dynesty
using Random

const X_LINREG = collect(range(0.0, 1.0; length=16))
const Y_LINREG = @. 0.7 * X_LINREG - 0.25 + 0.03 * sin(10.0 * X_LINREG)
const YERR_LINREG = fill(0.06, length(X_LINREG))

function prior_transform(u)
    return [
        -2.0 + 4.0u[1],
        -1.0 + 2.0u[2],
        log(0.01) + log(0.50 / 0.01) * u[3],
    ]
end

function loglikelihood(v)
    m, b, logf = v
    model = @. m * X_LINREG + b
    sigma2 = @. YERR_LINREG^2 + (exp(logf) * model)^2
    return -0.5 * sum(@. (Y_LINREG - model)^2 / sigma2 + log(sigma2))
end

function main(; rng=MersenneTwister(83), nlive=50, maxiter=55)
    sampler = NestedSampler(
        loglikelihood,
        prior_transform,
        3;
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
    return (logz=res.logz[end], nsamples=length(res.logl), mean=mean)
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) nsamples=$(summary.nsamples) mean=$(summary.mean)")
end
