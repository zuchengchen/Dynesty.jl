module AirQualityPE

using Random
using Statistics

export AIR_QUALITY_NDIM,
    air_quality_call_count,
    air_quality_dataset_metadata,
    air_quality_loglikelihood,
    air_quality_parameter_names,
    air_quality_prior_bounds,
    air_quality_prior_transform,
    air_quality_truth,
    auto_calibrate_air_quality_likelihood,
    calibrate_air_quality_likelihood,
    reset_air_quality_call_count!

const AIR_QUALITY_NDIM = 6
const DEFAULT_WORK_REPEATS = 1
const LOG2PI = log(2 * pi)

const PARAM_NAMES = [
    "source_strength",
    "background_pm25",
    "wind_decay",
    "diffusion_length",
    "global_bias",
    "log_noise_scale",
]

const PRIOR_LOW = [25.0, 4.0, 0.1, 0.8, -8.0, log(1.5)]
const PRIOR_HIGH = [130.0, 35.0, 4.5, 7.0, 8.0, log(10.0)]
const TRUE_THETA = [74.0, 12.5, 2.1, 3.2, 1.1, log(3.2)]

struct AirQualityDataset
    sensor_x::Vector{Float64}
    sensor_y::Vector{Float64}
    distance::Vector{Float64}
    bearing::Vector{Float64}
    wind_dir::Vector{Float64}
    wind_speed::Vector{Float64}
    diurnal::Vector{Float64}
    observed::Matrix{Float64}
    source_x::Float64
    source_y::Float64
    seed::Int
end

const AIR_QUALITY_CALL_COUNT = Threads.Atomic{Int}(0)

function _angle_delta(a::Float64, b::Float64)
    return atan(sin(a - b), cos(a - b))
end

function _sensor_layout(rng::AbstractRNG, nsensors::Int)
    side = ceil(Int, sqrt(nsensors))
    xs = Float64[]
    ys = Float64[]
    for iy in 1:side
        for ix in 1:side
            length(xs) >= nsensors && break
            x = -6.0 + 12.0 * (ix - 1) / max(side - 1, 1) + 0.22 * randn(rng)
            y = -5.0 + 10.0 * (iy - 1) / max(side - 1, 1) + 0.22 * randn(rng)
            push!(xs, x)
            push!(ys, y)
        end
    end
    return xs, ys
end

function _plume_prediction(
    theta::AbstractVector{<:Real},
    distance::Float64,
    bearing::Float64,
    wind_dir::Float64,
    wind_speed::Float64,
    diurnal::Float64,
)
    strength = Float64(theta[1])
    background = Float64(theta[2])
    wind_decay = Float64(theta[3])
    diffusion_length = Float64(theta[4])
    global_bias = Float64(theta[5])

    diffusion_length <= 0 && return NaN
    wind_speed <= 0 && return NaN

    alignment = exp(-wind_decay * (1.0 - cos(_angle_delta(bearing, wind_dir))))
    distance_decay = exp(-distance / diffusion_length) / (1.0 + 0.035 * distance^2)
    ventilation = 1.0 / sqrt(wind_speed)
    source_term = strength * diurnal * distance_decay * alignment * ventilation
    return background + global_bias + source_term
end

function _make_dataset(; seed::Int=20240611, nsensors::Int=56, nhours::Int=48)
    rng = MersenneTwister(seed)
    source_x = 1.7
    source_y = -1.4
    sensor_x, sensor_y = _sensor_layout(rng, nsensors)
    distance = Vector{Float64}(undef, nsensors)
    bearing = Vector{Float64}(undef, nsensors)
    @inbounds for i in 1:nsensors
        dx = sensor_x[i] - source_x
        dy = sensor_y[i] - source_y
        distance[i] = hypot(dx, dy) + 0.08
        bearing[i] = atan(dy, dx)
    end

    wind_dir = Vector{Float64}(undef, nhours)
    wind_speed = Vector{Float64}(undef, nhours)
    diurnal = Vector{Float64}(undef, nhours)
    @inbounds for t in 1:nhours
        hour = t - 1
        wind_dir[t] = 0.72 + 0.58 * sin(2 * pi * hour / 24.0 + 0.35) +
                      0.12 * sin(2 * pi * hour / 8.0)
        wind_speed[t] = 2.5 + 0.65 * cos(2 * pi * hour / 24.0 - 0.4) +
                        0.25 * sin(2 * pi * hour / 12.0)
        diurnal[t] = 0.82 + 0.23 * sin(2 * pi * (hour - 7.0) / 24.0)^2 +
                     0.11 * cos(2 * pi * hour / 48.0)
    end

    sigma = exp(TRUE_THETA[6])
    observed = Matrix{Float64}(undef, nsensors, nhours)
    @inbounds for t in 1:nhours
        for i in 1:nsensors
            mu = _plume_prediction(
                TRUE_THETA,
                distance[i],
                bearing[i],
                wind_dir[t],
                wind_speed[t],
                diurnal[t],
            )
            observed[i, t] = mu + sigma * randn(rng)
        end
    end

    return AirQualityDataset(
        sensor_x,
        sensor_y,
        distance,
        bearing,
        wind_dir,
        wind_speed,
        diurnal,
        observed,
        source_x,
        source_y,
        seed,
    )
end

const DATASET = _make_dataset()

air_quality_parameter_names() = copy(PARAM_NAMES)
air_quality_truth() = copy(TRUE_THETA)
air_quality_prior_bounds() = Dict("low" => copy(PRIOR_LOW), "high" => copy(PRIOR_HIGH))
air_quality_call_count() = AIR_QUALITY_CALL_COUNT[]

function reset_air_quality_call_count!()
    AIR_QUALITY_CALL_COUNT[] = 0
    return nothing
end

function air_quality_dataset_metadata(; work_repeats::Integer=DEFAULT_WORK_REPEATS, sleep_ms::Real=0.0)
    obs = DATASET.observed
    return Dict{String, Any}(
        "description" =>
            "Synthetic PM2.5 sensor calibration/source-strength inverse problem; not for environmental regulatory decisions.",
        "seed" => DATASET.seed,
        "sensor_count" => size(obs, 1),
        "hour_count" => size(obs, 2),
        "observation_count" => length(obs),
        "dataset_shape" => [size(obs, 1), size(obs, 2)],
        "source_location_km" => Dict("x" => DATASET.source_x, "y" => DATASET.source_y),
        "parameter_names" => air_quality_parameter_names(),
        "truth" => Dict(PARAM_NAMES[i] => TRUE_THETA[i] for i in eachindex(PARAM_NAMES)),
        "truth_vector" => copy(TRUE_THETA),
        "prior_bounds" => air_quality_prior_bounds(),
        "work_repeats" => Int(work_repeats),
        "sleep_ms" => Float64(sleep_ms),
    )
end

function air_quality_prior_transform(u)
    uv = collect(Float64, u)
    length(uv) == AIR_QUALITY_NDIM ||
        throw(DimensionMismatch("expected $AIR_QUALITY_NDIM unit-cube parameters, got $(length(uv))"))
    return PRIOR_LOW .+ (PRIOR_HIGH .- PRIOR_LOW) .* uv
end

function _work_stabilizer(theta::AbstractVector{<:Real}, work_repeats::Int)
    work_repeats <= 0 && return 0.0
    data = DATASET
    strength = Float64(theta[1])
    wind_decay = Float64(theta[3])
    diffusion_length = Float64(theta[4])
    acc = 0.0
    @inbounds for rep in 1:work_repeats
        scale = 1.0 + 0.00037 * rep
        for t in eachindex(data.wind_dir)
            wd = data.wind_dir[t] + 0.00011 * rep
            ws = data.wind_speed[t]
            diurnal = data.diurnal[t]
            for i in eachindex(data.distance)
                d = data.distance[i]
                alignment = exp(-wind_decay * (1.0 - cos(_angle_delta(data.bearing[i], wd))))
                decay = exp(-d / (diffusion_length * scale)) / (1.0 + 0.035 * d^2)
                plume = strength * diurnal * decay * alignment / sqrt(ws)
                acc += sqrt(abs(plume) + 1.0e-9) + sin(0.003 * plume + 0.01 * rep)^2
            end
        end
    end
    return acc
end

function air_quality_loglikelihood(
    theta,
    work_repeats::Integer=DEFAULT_WORK_REPEATS,
    sleep_ms::Real=0.0,
)
    Threads.atomic_add!(AIR_QUALITY_CALL_COUNT, 1)
    tv = collect(Float64, theta)
    length(tv) == AIR_QUALITY_NDIM || return -Inf
    sigma = exp(tv[6])
    isfinite(sigma) && sigma > 0 || return -Inf

    data = DATASET
    inv_sigma = 1.0 / sigma
    log_norm = LOG2PI + 2.0 * log(sigma)
    logl = 0.0
    @inbounds for t in axes(data.observed, 2)
        for i in axes(data.observed, 1)
            mu = _plume_prediction(
                tv,
                data.distance[i],
                data.bearing[i],
                data.wind_dir[t],
                data.wind_speed[t],
                data.diurnal[t],
            )
            if !isfinite(mu)
                return -Inf
            end
            r = (data.observed[i, t] - mu) * inv_sigma
            logl += -0.5 * (r * r + log_norm)
        end
    end

    stabilizer = _work_stabilizer(tv, Int(work_repeats))
    if !isfinite(stabilizer)
        return -Inf
    end
    sleep_ms > 0 && sleep(Float64(sleep_ms) / 1000.0)
    return logl + 1.0e-300 * stabilizer
end

function _calibration_thetas(ntrial::Integer, seed::Integer)
    rng = MersenneTwister(Int(seed))
    return [air_quality_prior_transform(rand(rng, AIR_QUALITY_NDIM)) for _ in 1:Int(ntrial)]
end

function calibrate_air_quality_likelihood(;
    work_repeats::Integer=DEFAULT_WORK_REPEATS,
    ntrial::Integer=15,
    seed::Integer=20240612,
    sleep_ms::Real=0.0,
)
    ntrial_i = Int(ntrial)
    ntrial_i > 0 || throw(ArgumentError("ntrial must be positive"))
    thetas = _calibration_thetas(ntrial_i, seed)
    air_quality_loglikelihood(thetas[1], work_repeats, sleep_ms)
    times = Float64[]
    for theta in thetas
        start = time_ns()
        air_quality_loglikelihood(theta, work_repeats, sleep_ms)
        push!(times, (time_ns() - start) / 1.0e9)
    end
    return Dict{String, Any}(
        "status" => "ok",
        "kind" => "julia_direct",
        "median_seconds" => median(times),
        "min_seconds" => minimum(times),
        "max_seconds" => maximum(times),
        "ntrial" => ntrial_i,
        "seed" => Int(seed),
        "work_repeats" => Int(work_repeats),
        "sleep_ms" => Float64(sleep_ms),
        "target_note" => "Median measures Julia direct likelihood calls after warm-up.",
    )
end

function auto_calibrate_air_quality_likelihood(;
    target_seconds::Real=0.01,
    ntrial::Integer=9,
    seed::Integer=20240612,
    sleep_ms::Real=0.0,
    max_work_repeats::Integer=2_000,
)
    target = Float64(target_seconds)
    target > 0 || throw(ArgumentError("target_seconds must be positive"))
    repeats = 1
    history = Vector{Dict{String, Any}}()
    selected = calibrate_air_quality_likelihood(;
        work_repeats=repeats,
        ntrial,
        seed,
        sleep_ms,
    )
    push!(history, copy(selected))
    while Float64(selected["median_seconds"]) < 0.005 && repeats < max_work_repeats
        ratio = target / max(Float64(selected["median_seconds"]), 1.0e-6)
        factor = clamp(ceil(Int, ratio), 2, 8)
        repeats = min(Int(max_work_repeats), repeats * factor)
        selected = calibrate_air_quality_likelihood(;
            work_repeats=repeats,
            ntrial,
            seed,
            sleep_ms,
        )
        push!(history, copy(selected))
    end
    while Float64(selected["median_seconds"]) > 0.02 && repeats > 1
        ratio = target / Float64(selected["median_seconds"])
        new_repeats = max(1, floor(Int, repeats * ratio))
        new_repeats == repeats && (new_repeats = max(1, repeats - 1))
        repeats = new_repeats
        selected = calibrate_air_quality_likelihood(;
            work_repeats=repeats,
            ntrial,
            seed,
            sleep_ms,
        )
        push!(history, copy(selected))
    end
    selected["target_seconds"] = target
    selected["history"] = history
    selected["selection_note"] =
        "Auto-selected deterministic repeated plume work to target a 0.005--0.02 second median direct Julia likelihood."
    return selected
end

end # module
