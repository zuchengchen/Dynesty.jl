using BenchmarkTools
using Dynesty
using Random

const SUITE = BenchmarkGroup()

gaussian_prior(u) = [-5.0 + 10.0 * u[1], -5.0 + 10.0 * u[2]]
gaussian_loglikelihood(v) = -0.5 * (v[1]^2 + v[2]^2)

function run_static_gaussian(; seed=101, nlive=40, maxiter=45)
    sampler = NestedSampler(
        gaussian_loglikelihood,
        gaussian_prior,
        2;
        nlive,
        bound=:single,
        sample=:unif,
        rng=MersenneTwister(seed),
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    return results(sampler).logz[end]
end

function run_dynamic_gaussian(; seed=202, nlive=32, nlive_batch=12)
    sampler = DynamicSampler(
        gaussian_loglikelihood,
        gaussian_prior,
        2;
        nlive,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(seed),
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
    return results(sampler).logz[end]
end

function run_persistence_roundtrip(; seed=303, nlive=24, maxiter=25)
    sampler = NestedSampler(
        gaussian_loglikelihood,
        gaussian_prior,
        2;
        nlive,
        bound=:none,
        sample=:unif,
        rng=MersenneTwister(seed),
    )
    run_nested!(sampler; maxiter, dlogz=nothing, print_progress=false)
    res = results(sampler)
    mktempdir() do dir
        path = joinpath(dir, "results.jld2")
        save_results(path, res)
        loaded = load_results(path)
        return loaded.logz[end]
    end
end

SUITE["sampler"]["static_gaussian"] = @benchmarkable run_static_gaussian()
SUITE["sampler"]["dynamic_gaussian"] = @benchmarkable run_dynamic_gaussian()
SUITE["persistence"]["results_roundtrip"] = @benchmarkable run_persistence_roundtrip()

function smoke()
    static_logz = run_static_gaussian()
    dynamic_logz = run_dynamic_gaussian()
    persisted_logz = run_persistence_roundtrip()
    return (; static_logz, dynamic_logz, persisted_logz)
end

function main()
    if get(ENV, "DYNESTY_RUN_BENCHMARKS", "false") == "true"
        return run(SUITE; verbose=true)
    else
        summary = smoke()
        println(
            "Benchmark smoke: static=$(summary.static_logz), dynamic=$(summary.dynamic_logz), persistence=$(summary.persisted_logz)",
        )
        return summary
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
