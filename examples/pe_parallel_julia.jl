using Dynesty
using LinearAlgebra
using Printf
using Random

# Julia side of the sampler-level parallel PE comparison.
#
# Full run:
#   OPENBLAS_NUM_THREADS=1 julia --threads=31 --project=. \
#     examples/pe_parallel_julia.jl --nlive 3000 --queue-size 31
#
# Quick smoke:
#   OPENBLAS_NUM_THREADS=1 JULIA_NUM_THREADS=2 julia --project=. \
#     examples/pe_parallel_julia.jl --quick --queue-size 2
#
# Outputs are written under examples/output/pe_parallel_compare/ by default.

const PARAM_NAMES = ["theta1", "theta2", "theta3", "theta4"]
const TRUE_THETA = [0.65, -0.35, 0.45, -0.10]
const POSTERIOR_COV = [
    0.20 0.08 0.03 0.00
    0.08 0.30 -0.04 0.05
    0.03 -0.04 0.16 0.06
    0.00 0.05 0.06 0.25
]
const POSTERIOR_INVCOV = inv(POSTERIOR_COV)
const PRIOR_LOW = [-3.0, -3.0, -3.0, -3.0]
const PRIOR_HIGH = [3.0, 3.0, 3.0, 3.0]
const PRIOR_WIDTH = PRIOR_HIGH .- PRIOR_LOW

prior_transform(u) = PRIOR_LOW .+ PRIOR_WIDTH .* u

function loglikelihood(theta)
    delta = theta .- TRUE_THETA
    return -0.5 * dot(delta, POSTERIOR_INVCOV * delta)
end

function _json_value(value)
    if value isa AbstractString
        return "\"" * replace(value, "\\" => "\\\\", "\"" => "\\\"") * "\""
    elseif value isa Symbol
        return _json_value(String(value))
    elseif value isa Bool
        return value ? "true" : "false"
    elseif value isa Integer
        return string(value)
    elseif value isa Real
        return isfinite(value) ? @sprintf("%.17g", Float64(value)) : _json_value(string(value))
    elseif value isa AbstractVector
        return "[" * join((_json_value(item) for item in value), ", ") * "]"
    elseif value isa AbstractMatrix
        rows = [_json_value(vec(value[i, :])) for i in axes(value, 1)]
        return "[" * join(rows, ", ") * "]"
    elseif value isa AbstractDict
        parts = String[]
        for key in sort!(collect(keys(value)); by=string)
            push!(parts, _json_value(string(key)) * ": " * _json_value(value[key]))
        end
        return "{" * join(parts, ", ") * "}"
    else
        return _json_value(string(value))
    end
end

function write_json(path, data)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        println(io, _json_value(data))
    end
    return path
end

function write_weighted_samples(path, samples, weights)
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        println(io, join(vcat(PARAM_NAMES, ["weight"]), ","))
        for i in axes(samples, 1)
            values = [samples[i, j] for j in axes(samples, 2)]
            push!(values, weights[i])
            @printf(io, "%.17g", values[1])
            for value in values[2:end]
                @printf(io, ",%.17g", value)
            end
            println(io)
        end
    end
    return path
end

function weighted_mean_cov(samples, weights)
    mean = vec(sum(samples .* reshape(weights, :, 1); dims=1))
    centered = samples .- reshape(mean, 1, :)
    cov = centered' * (centered .* reshape(weights, :, 1))
    return mean, cov
end

function parse_cli(args)
    opts = Dict{Symbol, Any}(
        :output_dir => joinpath(@__DIR__, "output", "pe_parallel_compare"),
        :nlive => 3000,
        :quick_nlive => 180,
        :dlogz => 0.01,
        :quick_dlogz => 0.5,
        :seed => 20240610,
        :queue_size => min(max(Threads.nthreads(), 1), 31),
        :quick => false,
    )
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--quick"
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
        else
            throw(ArgumentError("unknown argument $arg"))
        end
    end
    opts[:nlive_effective] = opts[:quick] ? opts[:quick_nlive] : opts[:nlive]
    opts[:dlogz_effective] = opts[:quick] ? opts[:quick_dlogz] : opts[:dlogz]
    return opts
end

function run_julia_pe(opts)
    queue_size = Int(opts[:queue_size])
    sampler = NestedSampler(
        loglikelihood,
        prior_transform,
        length(TRUE_THETA);
        nlive=Int(opts[:nlive_effective]),
        bound=:single,
        sample=:unif,
        rng=MersenneTwister(Int(opts[:seed])),
        parallel=:threads,
        queue_size,
        enlarge=1.1,
        bootstrap=0,
    )
    sampler.map_backend isa ThreadedMapBackend || error("expected ThreadedMapBackend")
    sampler.map_backend.queue_size == queue_size ||
        error("expected queue_size=$queue_size, got $(sampler.map_backend.queue_size)")

    run_nested!(
        sampler; dlogz=Float64(opts[:dlogz_effective]), print_progress=false, add_live=true
    )
    res = results(sampler)
    weights = importance_weights(res)
    weights ./= sum(weights)
    mean, cov = weighted_mean_cov(res.samples, weights)
    return (; sampler, res, weights, mean, cov)
end

function main(args=ARGS)
    opts = parse_cli(args)
    output_dir = abspath(String(opts[:output_dir]))
    samples_path = joinpath(output_dir, "julia_weighted_samples.csv")
    metadata_path = joinpath(output_dir, "julia_metadata.json")

    fit = run_julia_pe(opts)
    write_weighted_samples(samples_path, fit.res.samples, fit.weights)
    write_json(
        metadata_path,
        Dict{Symbol, Any}(
            :implementation => "Dynesty.jl",
            :backend => "ThreadedMapBackend",
            :queue_size => fit.sampler.map_backend.queue_size,
            :threads => Threads.nthreads(),
            :quick => Bool(opts[:quick]),
            :nlive => Int(opts[:nlive_effective]),
            :dlogz => Float64(opts[:dlogz_effective]),
            :seed => Int(opts[:seed]),
            :ndim => length(TRUE_THETA),
            :nsamples => length(fit.res.logl),
            :logz => fit.res.logz[end],
            :logzerr => fit.res.logzerr[end],
            :mean => fit.mean,
            :cov => fit.cov,
            :param_names => PARAM_NAMES,
            :true_theta => TRUE_THETA,
            :posterior_cov => POSTERIOR_COV,
            :samples_file => samples_path,
        ),
    )
    @printf(
        "Julia Dynesty.jl threaded PE: nlive=%d nsamples=%d logz=%.6f logzerr=%.6f queue_size=%d wrote %s\n",
        Int(opts[:nlive_effective]),
        length(fit.res.logl),
        fit.res.logz[end],
        fit.res.logzerr[end],
        fit.sampler.map_backend.queue_size,
        samples_path,
    )
    return fit
end

const THIS_FILE = @__FILE__

if abspath(PROGRAM_FILE) == abspath(THIS_FILE)
    main()
end
