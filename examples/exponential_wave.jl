using Dynesty
using Random

const X_WAVE = collect(range(0.0, 1.0; length=18))
const Y_WAVE = exp.(0.35 .* sin.(2pi .* X_WAVE .+ 0.2) .+ 0.18 .* sin.(6pi .* X_WAVE .- 0.5))
const SIGMA_WAVE = 0.08

function prior_transform(u)
    return [
        -1.0 + 2.0u[1],
        -1.0 + 2.0u[2],
        0.25 + 2.0u[3],
        0.25 + 4.0u[4],
        2pi * u[5],
        2pi * u[6],
        log(0.03) + log(0.20 / 0.03) * u[7],
    ]
end

function loglikelihood(v)
    a, b, fa, fb, pa, pb, logsigma = v
    sigma = exp(logsigma)
    ypred = exp.(a .* sin.(2pi .* fa .* X_WAVE .+ pa) .+ b .* sin.(2pi .* fb .* X_WAVE .+ pb))
    return -0.5 * sum(((Y_WAVE .- ypred) ./ sigma) .^ 2) -
           length(X_WAVE) * logsigma
end

function main(; rng=MersenneTwister(81), nlive=60, maxiter=65)
    sampler = DynamicNestedSampler(
        loglikelihood,
        prior_transform,
        7;
        nlive,
        bound=:multi,
        sample=:unif,
        periodic=[5, 6],
        rng,
        enlarge=1.1,
        bootstrap=0,
    )
    run_nested!(
        sampler;
        maxiter_init=maxiter,
        dlogz_init=nothing,
        nlive_batch=max(12, nlive ÷ 4),
        maxbatch=1,
        maxiter_batch=max(8, maxiter ÷ 5),
        maxcall_batch=500,
        use_stop=false,
        print_progress=false,
    )
    res = results(sampler)
    return (logz=res.logz[end], nsamples=length(res.logl), ndim=7)
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) nsamples=$(summary.nsamples) ndim=$(summary.ndim)")
end
