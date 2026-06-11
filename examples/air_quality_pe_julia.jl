#!/usr/bin/env julia

using Dates
using Dynesty
using JSON3
using LinearAlgebra
using Printf
using Random
using Statistics

include(joinpath(@__DIR__, "air_quality_likelihood.jl"))
using .AirQualityPE

const DEFAULT_OUTPUT_DIR = joinpath(@__DIR__, "output", "air_quality_pe_compare")

function usage()
    return """
    Usage:
      julia --threads=31 --project=. examples/air_quality_pe_julia.jl [options]

    Options:
      --output-dir PATH
      --nlive N
      --quick-nlive N
      --dlogz X
      --quick-dlogz X
      --seed N
      --queue-size N
      --proposal-scheduler auto|batch|async
      --work-repeats N
      --sleep-ms X
      --calibration-trials N
      --quick
    """
end

function parse_cli(args)
    opts = Dict{Symbol, Any}(
        :output_dir => DEFAULT_OUTPUT_DIR,
        :nlive => 800,
        :quick_nlive => 120,
        :dlogz => 0.08,
        :quick_dlogz => 0.5,
        :seed => 20240621,
        :queue_size => min(max(Threads.nthreads(), 1), 31),
        :proposal_scheduler => "auto",
        :work_repeats => 1,
        :sleep_ms => 0.0,
        :calibration_trials => 9,
        :quick => false,
    )
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            println(usage())
            exit(0)
        elseif arg == "--quick"
            opts[:quick] = true
            i += 1
        elseif arg == "--output-dir"
            opts[:output_dir] = args[i + 1]
            i += 2
        elseif arg == "--nlive"
            opts[:nlive] = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--quick-nlive"
            opts[:quick_nlive] = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--dlogz"
            opts[:dlogz] = parse(Float64, args[i + 1])
            i += 2
        elseif arg == "--quick-dlogz"
            opts[:quick_dlogz] = parse(Float64, args[i + 1])
            i += 2
        elseif arg == "--seed"
            opts[:seed] = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--queue-size"
            opts[:queue_size] = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--proposal-scheduler"
            opts[:proposal_scheduler] = args[i + 1]
            i += 2
        elseif arg == "--work-repeats"
            opts[:work_repeats] = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--sleep-ms"
            opts[:sleep_ms] = parse(Float64, args[i + 1])
            i += 2
        elseif arg == "--calibration-trials"
            opts[:calibration_trials] = parse(Int, args[i + 1])
            i += 2
        else
            throw(ArgumentError("unknown argument $arg\n$(usage())"))
        end
    end
    opts[:nlive_effective] = opts[:quick] ? opts[:quick_nlive] : opts[:nlive]
    opts[:dlogz_effective] = opts[:quick] ? opts[:quick_dlogz] : opts[:dlogz]
    opts[:proposal_scheduler] = Symbol(opts[:proposal_scheduler])
    Int(opts[:nlive_effective]) > 0 || throw(ArgumentError("nlive must be positive"))
    Int(opts[:queue_size]) > 0 || throw(ArgumentError("queue_size must be positive"))
    Int(opts[:work_repeats]) >= 0 ||
        throw(ArgumentError("work_repeats must be nonnegative"))
    Float64(opts[:sleep_ms]) >= 0 || throw(ArgumentError("sleep_ms must be nonnegative"))
    return opts
end

function weighted_mean_cov(samples, weights)
    mean = vec(sum(samples .* reshape(weights, :, 1); dims=1))
    centered = samples .- reshape(mean, 1, :)
    cov = centered' * (centered .* reshape(weights, :, 1))
    return mean, cov
end

function write_weighted_samples(path, samples, weights)
    mkpath(dirname(abspath(path)))
    names = air_quality_parameter_names()
    open(path, "w") do io
        println(io, join(vcat(names, ["weight"]), ","))
        for i in axes(samples, 1)
            @printf(io, "%.17g", samples[i, 1])
            for j in 2:size(samples, 2)
                @printf(io, ",%.17g", samples[i, j])
            end
            @printf(io, ",%.17g\n", weights[i])
        end
    end
    return path
end

function write_json(path, payload)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        JSON3.pretty(io, payload)
        println(io)
    end
    return path
end

function environment_summary()
    return Dict{String, Any}(
        "OPENBLAS_NUM_THREADS" => get(ENV, "OPENBLAS_NUM_THREADS", nothing),
        "OMP_NUM_THREADS" => get(ENV, "OMP_NUM_THREADS", nothing),
        "MKL_NUM_THREADS" => get(ENV, "MKL_NUM_THREADS", nothing),
        "JULIA_NUM_THREADS" => get(ENV, "JULIA_NUM_THREADS", nothing),
    )
end

function run_julia_air_quality_pe(opts)
    work_repeats = Int(opts[:work_repeats])
    sleep_ms = Float64(opts[:sleep_ms])
    reset_air_quality_call_count!()
    direct_calibration = calibrate_air_quality_likelihood(;
        work_repeats, ntrial=Int(opts[:calibration_trials]), sleep_ms
    )
    loglike = theta -> air_quality_loglikelihood(theta, work_repeats, sleep_ms)
    sampler = NestedSampler(
        loglike,
        air_quality_prior_transform,
        AIR_QUALITY_NDIM;
        nlive=Int(opts[:nlive_effective]),
        bound=:single,
        sample=:unif,
        rng=MersenneTwister(Int(opts[:seed])),
        parallel=:threads,
        queue_size=Int(opts[:queue_size]),
        proposal_scheduler=opts[:proposal_scheduler],
        enlarge=1.1,
        bootstrap=0,
    )
    start_wall = time()
    run_nested!(
        sampler; dlogz=Float64(opts[:dlogz_effective]), print_progress=false, add_live=true
    )
    sampler_wall = time() - start_wall
    res = results(sampler)
    weights = importance_weights(res)
    weights ./= sum(weights)
    mean, cov = weighted_mean_cov(res.samples, weights)
    return (; sampler, res, weights, mean, cov, direct_calibration, sampler_wall)
end

function main(args=ARGS)
    opts = parse_cli(args)
    output_dir = abspath(String(opts[:output_dir]))
    samples_path = joinpath(output_dir, "julia_weighted_samples.csv")
    metadata_path = joinpath(output_dir, "julia_metadata.json")
    fit = run_julia_air_quality_pe(opts)
    write_weighted_samples(samples_path, fit.res.samples, fit.weights)
    metadata = Dict{String, Any}(
        "implementation" => "Dynesty.jl",
        "run_kind" => "air_quality_pe",
        "canonical_likelihood" => "examples/air_quality_likelihood.jl",
        "likelihood_language" => "Julia",
        "likelihood_call_path" => "direct Julia call",
        "bridge_kind" => nothing,
        "bridge_init_status" => "not_applicable",
        "backend" => "ThreadedMapBackend",
        "pool" => "Julia threads",
        "queue_size" => fit.sampler.map_backend.queue_size,
        "threads" => Threads.nthreads(),
        "proposal_scheduler" => fit.sampler.proposal_scheduler,
        "proposal_tasks_submitted" => fit.sampler.proposal_tasks_submitted,
        "proposal_batches_submitted" => fit.sampler.proposal_batches_submitted,
        "parallel_stats" => Dynesty._parallel_stats_config(fit.sampler.parallel_stats),
        "quick" => Bool(opts[:quick]),
        "nlive" => Int(opts[:nlive_effective]),
        "dlogz" => Float64(opts[:dlogz_effective]),
        "seed" => Int(opts[:seed]),
        "ndim" => AIR_QUALITY_NDIM,
        "work_repeats" => Int(opts[:work_repeats]),
        "sleep_ms" => Float64(opts[:sleep_ms]),
        "likelihood_call_count" => air_quality_call_count(),
        "direct_julia_likelihood_median_seconds" =>
            fit.direct_calibration["median_seconds"],
        "python_bridge_likelihood_median_seconds" => nothing,
        "direct_julia_likelihood_calibration" => fit.direct_calibration,
        "sampler_wall_time_seconds_internal" => fit.sampler_wall,
        "nsamples" => length(fit.res.logl),
        "ncall" => fit.sampler.ncall,
        "logz" => fit.res.logz[end],
        "logzerr" => fit.res.logzerr[end],
        "posterior_weighted_mean" => fit.mean,
        "posterior_weighted_covariance_diagonal" => diag(fit.cov),
        "cov" => fit.cov,
        "param_names" => air_quality_parameter_names(),
        "true_theta" => air_quality_truth(),
        "truth" =>
            air_quality_dataset_metadata(; work_repeats=Int(opts[:work_repeats]))["truth"],
        "dataset" => air_quality_dataset_metadata(;
            work_repeats=Int(opts[:work_repeats]), sleep_ms=Float64(opts[:sleep_ms])
        ),
        "environment_variables" => environment_summary(),
        "julia_version" => string(VERSION),
        "samples_file" => samples_path,
        "metadata_file" => metadata_path,
        "created_at" => string(now()),
    )
    write_json(metadata_path, metadata)
    @printf(
        "Julia air-quality PE: nlive=%d nsamples=%d logz=%.6f logzerr=%.6f calls=%d queue_size=%d wrote %s\n",
        Int(opts[:nlive_effective]),
        length(fit.res.logl),
        fit.res.logz[end],
        fit.res.logzerr[end],
        air_quality_call_count(),
        fit.sampler.map_backend.queue_size,
        samples_path,
    )
    return fit
end

const THIS_FILE = @__FILE__

if abspath(PROGRAM_FILE) == abspath(THIS_FILE)
    main()
end
