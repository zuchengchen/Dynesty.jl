using Dynesty
using Random

const NOISY_SIGMA = [0.25, 0.35, 0.45]
const NOISY_CENTER = [0.2, -0.1, 0.3]

prior_transform(u) = -2.0 .+ 4.0 .* u

function exact_loglikelihood(v)
    return -0.5 * sum(((v .- NOISY_CENTER) ./ NOISY_SIGMA) .^ 2)
end

function noisy_loglikelihood(v)
    deterministic_noise = 0.04 * sin(17.0 * sum(v) + 3.0 * v[1])
    noise_variance = 0.04^2
    return exact_loglikelihood(v) + deterministic_noise - 0.5 * noise_variance
end

function main(; rng=MersenneTwister(85), nlive=50, maxiter=55)
    sampler = DynamicNestedSampler(
        noisy_loglikelihood,
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
    return (logz=res.logz[end], nsamples=length(res.logl), ndim=3)
end

if abspath(PROGRAM_FILE) == @__FILE__
    summary = main()
    println("logz=$(summary.logz) nsamples=$(summary.nsamples)")
end
