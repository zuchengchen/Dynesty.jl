#!/usr/bin/env julia

using Dates
using JSON3
using Printf
using Statistics

include(joinpath(@__DIR__, "..", "examples", "air_quality_likelihood.jl"))
using .AirQualityPE

const ROOT = abspath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT_DIR = joinpath(ROOT, "examples", "output", "air_quality_pe_compare")
const PYTHON_DYNESTY_PATH = abspath(joinpath(ROOT, "..", "dynesty", "py"))
const TIME_COMMAND = "/usr/bin/time"
const MEMORY_SAMPLE_INTERVAL_SECONDS = 0.2

mutable struct RunConfig
    mode::String
    output_dir::String
    repeats::Int
    nlive::Int
    dlogz::Float64
    smoke_nlive::Int
    smoke_dlogz::Float64
    queue_size::Int
    smoke_queue_size::Int
    threads::Int
    nproc::Int
    smoke_nproc::Int
    julia_exe::String
    python_exe::String
    work_repeats::Union{Nothing, Int}
    sleep_ms::Float64
    calibration_trials::Int
    target_likelihood_seconds::Float64
    allow_missing_usr_time::Bool
    skip_python::Bool
    skip_plots::Bool
    resume::Bool
    python_start_method::String
end

mutable struct MemoryPeak
    peak_rss_kb::Int
    peak_pss_kb::Union{Nothing, Int}
    peak_processes::Int
    pss_available::Bool
end

function usage()
    return """
    Usage:
      julia --project=. benchmark/air_quality_pe_compare.jl --mode smoke|formal [options]

    Key options:
      --output-dir PATH              default: examples/output/air_quality_pe_compare
      --mode smoke|formal
      --repeats N                    formal repeats, default 2
      --nlive N                      formal nlive, default 500
      --dlogz X                      formal dlogz, default 0.08
      --smoke-nlive N                default 100
      --smoke-dlogz X                default 0.5
      --queue-size N                 formal queue size, default 31
      --smoke-queue-size N           smoke queue size, default 4
      --threads N                    Julia worker threads, default 31
      --nproc N                      formal Python worker processes, default 31
      --smoke-nproc N                smoke Python worker processes, default 4
      --work-repeats N               skip auto-calibration and use this repeat count
      --allow-missing-usr-time       accepted for older scripts; Linux /proc monitoring
                                     is used automatically when /usr/bin/time is absent
      --skip-python                  run Julia side only and record Python as skipped
      --skip-plots                   keep summary even if overlay plots are not needed
      --resume                       skip reusable successful run directories
    """
end

function parse_cli(args)
    cfg = RunConfig(
        "smoke",
        DEFAULT_OUTPUT_DIR,
        2,
        500,
        0.08,
        100,
        0.5,
        31,
        4,
        31,
        31,
        4,
        get(ENV, "JULIA", "julia"),
        get(ENV, "PYTHON", "python3"),
        nothing,
        0.0,
        9,
        0.01,
        false,
        false,
        false,
        false,
        "spawn",
    )
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            println(usage())
            exit(0)
        elseif arg == "--mode"
            cfg.mode = args[i + 1]
            i += 2
        elseif arg == "--output-dir"
            cfg.output_dir = abspath(args[i + 1])
            i += 2
        elseif arg == "--repeats"
            cfg.repeats = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--nlive"
            cfg.nlive = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--dlogz"
            cfg.dlogz = parse(Float64, args[i + 1])
            i += 2
        elseif arg == "--smoke-nlive"
            cfg.smoke_nlive = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--smoke-dlogz"
            cfg.smoke_dlogz = parse(Float64, args[i + 1])
            i += 2
        elseif arg == "--queue-size"
            cfg.queue_size = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--smoke-queue-size"
            cfg.smoke_queue_size = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--threads"
            cfg.threads = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--nproc"
            cfg.nproc = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--smoke-nproc"
            cfg.smoke_nproc = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--julia-exe"
            cfg.julia_exe = args[i + 1]
            i += 2
        elseif arg == "--python-exe"
            cfg.python_exe = args[i + 1]
            i += 2
        elseif arg == "--work-repeats"
            cfg.work_repeats = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--sleep-ms"
            cfg.sleep_ms = parse(Float64, args[i + 1])
            i += 2
        elseif arg == "--calibration-trials"
            cfg.calibration_trials = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--target-likelihood-seconds"
            cfg.target_likelihood_seconds = parse(Float64, args[i + 1])
            i += 2
        elseif arg == "--python-start-method"
            cfg.python_start_method = args[i + 1]
            i += 2
        elseif arg == "--allow-missing-usr-time"
            cfg.allow_missing_usr_time = true
            i += 1
        elseif arg == "--skip-python"
            cfg.skip_python = true
            i += 1
        elseif arg == "--skip-plots"
            cfg.skip_plots = true
            i += 1
        elseif arg == "--resume"
            cfg.resume = true
            i += 1
        else
            throw(ArgumentError("unknown argument $arg\n$(usage())"))
        end
    end
    cfg.mode in ("smoke", "formal") ||
        throw(ArgumentError("--mode must be smoke or formal; got $(cfg.mode)"))
    cfg.repeats > 0 || throw(ArgumentError("--repeats must be positive"))
    cfg.nlive > 0 || throw(ArgumentError("--nlive must be positive"))
    cfg.smoke_nlive > 0 || throw(ArgumentError("--smoke-nlive must be positive"))
    cfg.queue_size > 0 || throw(ArgumentError("--queue-size must be positive"))
    cfg.smoke_queue_size > 0 || throw(ArgumentError("--smoke-queue-size must be positive"))
    cfg.threads > 0 || throw(ArgumentError("--threads must be positive"))
    cfg.nproc > 0 || throw(ArgumentError("--nproc must be positive"))
    cfg.smoke_nproc > 0 || throw(ArgumentError("--smoke-nproc must be positive"))
    cfg.sleep_ms >= 0 || throw(ArgumentError("--sleep-ms must be nonnegative"))
    cfg.calibration_trials > 0 ||
        throw(ArgumentError("--calibration-trials must be positive"))
    cfg.python_start_method in ("spawn", "forkserver", "fork") ||
        throw(ArgumentError("--python-start-method must be spawn, forkserver, or fork"))
    return cfg
end

active_repeats(cfg::RunConfig) = cfg.mode == "smoke" ? 1 : cfg.repeats
active_nlive(cfg::RunConfig) = cfg.mode == "smoke" ? cfg.smoke_nlive : cfg.nlive
active_dlogz(cfg::RunConfig) = cfg.mode == "smoke" ? cfg.smoke_dlogz : cfg.dlogz
active_queue_size(cfg::RunConfig) =
    cfg.mode == "smoke" ? cfg.smoke_queue_size : cfg.queue_size
active_nproc(cfg::RunConfig) = cfg.mode == "smoke" ? cfg.smoke_nproc : cfg.nproc

function run_matrix(cfg::RunConfig)
    items = NamedTuple[]
    for repeat in 1:active_repeats(cfg)
        push!(items, (implementation="julia", repeat=repeat))
        cfg.skip_python || push!(items, (implementation="python", repeat=repeat))
    end
    return items
end

function read_proc_children(pid::Integer)
    path = "/proc/$pid/task/$pid/children"
    isfile(path) || return Int[]
    text = try
        read(path, String)
    catch
        return Int[]
    end
    isempty(strip(text)) && return Int[]
    return [parse(Int, item) for item in split(text)]
end

function process_tree(root_pid::Integer)
    seen = Set{Int}()
    queue = [root_pid]
    while !isempty(queue)
        pid = popfirst!(queue)
        pid in seen && continue
        isdir("/proc/$pid") || continue
        push!(seen, pid)
        append!(queue, read_proc_children(pid))
    end
    return collect(seen)
end

function status_rss_kb(pid::Integer)
    path = "/proc/$pid/status"
    isfile(path) || return nothing
    for line in eachline(path)
        if startswith(line, "VmRSS:")
            parts = split(line)
            length(parts) >= 2 && return parse(Int, parts[2])
        end
    end
    return nothing
end

function smaps_rollup_pss_kb(pid::Integer)
    path = "/proc/$pid/smaps_rollup"
    isfile(path) || return nothing
    try
        for line in eachline(path)
            if startswith(line, "Pss:")
                parts = split(line)
                length(parts) >= 2 && return parse(Int, parts[2])
            end
        end
    catch
        return nothing
    end
    return nothing
end

function sample_tree_memory(root_pid::Integer)
    pids = process_tree(root_pid)
    rss_total = 0
    pss_total = 0
    pss_available = !isempty(pids)
    live_count = 0
    for pid in pids
        rss = status_rss_kb(pid)
        isnothing(rss) && continue
        live_count += 1
        rss_total += rss
        pss = smaps_rollup_pss_kb(pid)
        if isnothing(pss)
            pss_available = false
        else
            pss_total += pss
        end
    end
    return (
        rss_kb=rss_total,
        pss_kb=pss_available ? pss_total : nothing,
        pss_available=pss_available,
        processes=live_count,
    )
end

function monitor_memory!(peak::MemoryPeak, root_pid::Integer, proc::Base.Process)
    function record_sample!(sample)
        sample.processes == 0 && return peak
        if sample.rss_kb > peak.peak_rss_kb
            peak.peak_rss_kb = sample.rss_kb
            peak.peak_processes = sample.processes
        end
        if sample.pss_available && !isnothing(sample.pss_kb)
            if isnothing(peak.peak_pss_kb) || sample.pss_kb > peak.peak_pss_kb
                peak.peak_pss_kb = sample.pss_kb
            end
            peak.pss_available = true
        end
        return peak
    end
    while process_running(proc)
        record_sample!(sample_tree_memory(root_pid))
        sleep(MEMORY_SAMPLE_INTERVAL_SECONDS)
    end
    record_sample!(sample_tree_memory(root_pid))
    return peak
end

function parse_elapsed_seconds(text::AbstractString)
    parts = split(strip(text), ":")
    if length(parts) == 3
        return parse(Float64, parts[1]) * 3600 +
               parse(Float64, parts[2]) * 60 +
               parse(Float64, parts[3])
    elseif length(parts) == 2
        return parse(Float64, parts[1]) * 60 + parse(Float64, parts[2])
    else
        return tryparse(Float64, strip(text))
    end
end

function time_value_after_label(line::AbstractString)
    idx = findlast(==(':'), line)
    isnothing(idx) && return ""
    return strip(line[nextind(line, idx):end])
end

function parse_time_v(stderr_text::String)
    metrics = Dict{String, Any}()
    for line in split(stderr_text, '\n')
        if occursin("User time (seconds):", line)
            metrics["user_cpu_seconds"] = parse(Float64, time_value_after_label(line))
        elseif occursin("System time (seconds):", line)
            metrics["system_cpu_seconds"] = parse(Float64, time_value_after_label(line))
        elseif occursin("Percent of CPU this job got:", line)
            raw = time_value_after_label(line)
            metrics["time_percent_cpu"] = raw
            metrics["time_percent_cpu_numeric"] = tryparse(Float64, replace(raw, "%" => ""))
        elseif occursin("Elapsed (wall clock) time", line)
            metrics["wall_time_seconds"] = parse_elapsed_seconds(
                time_value_after_label(line)
            )
        elseif occursin("Maximum resident set size (kbytes):", line)
            metrics["time_max_rss_kb"] = parse(Int, time_value_after_label(line))
        end
    end
    if haskey(metrics, "user_cpu_seconds") && haskey(metrics, "system_cpu_seconds")
        total = metrics["user_cpu_seconds"] + metrics["system_cpu_seconds"]
        metrics["total_cpu_seconds"] = total
        wall = get(metrics, "wall_time_seconds", nothing)
        metrics["cpu_utilization"] = (!isnothing(wall) && wall > 0) ? total / wall : nothing
    end
    return metrics
end

function csv_escape(value)
    isnothing(value) && return ""
    s = string(value)
    if occursin(',', s) || occursin('"', s) || occursin('\n', s)
        return "\"" * replace(s, "\"" => "\"\"") * "\""
    end
    return s
end

function write_csv(path::String, rows::Vector{Dict{String, Any}}, columns::Vector{String})
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, join(columns, ","))
        for row in rows
            println(io, join((csv_escape(get(row, col, nothing)) for col in columns), ","))
        end
    end
    return path
end

function read_json_dict(path::String)
    isfile(path) || return Dict{String, Any}()
    return JSON3.read(read(path, String), Dict{String, Any})
end

function write_json(path::String, payload)
    mkpath(dirname(path))
    open(path, "w") do io
        JSON3.pretty(io, payload)
        println(io)
    end
    return path
end

function time_command_available()
    return isfile(TIME_COMMAND) && Sys.isexecutable(TIME_COMMAND)
end

function monitor_kind()
    return time_command_available() ? "gnu_time" : "process_monitor"
end

function monitor_kind(monitor::AbstractDict)
    if haskey(monitor, "monitor_kind")
        return String(monitor["monitor_kind"])
    elseif get(monitor, "used_usr_bin_time", false) == true &&
        get(monitor, "time_unavailable", false) != true
        return "gnu_time"
    elseif get(monitor, "used_process_monitor", false) == true
        return "process_monitor"
    else
        return "unknown"
    end
end

function base_env_pairs(implementation::String)
    pairs = [
        "OPENBLAS_NUM_THREADS" => "1", "OMP_NUM_THREADS" => "1", "MKL_NUM_THREADS" => "1"
    ]
    if implementation == "python"
        push!(pairs, "PYTHONPATH" => PYTHON_DYNESTY_PATH)
    end
    return pairs
end

run_id(implementation::String, repeat::Int) = "$(implementation)_repeat$(repeat)"

function command_for(
    cfg::RunConfig, implementation::String, repeat::Int, run_dir::String, work_repeats::Int
)
    seed = 20240621 + repeat + (implementation == "python" ? 10_000 : 0)
    common = [
        "--output-dir",
        run_dir,
        "--nlive",
        string(active_nlive(cfg)),
        "--dlogz",
        @sprintf("%.17g", active_dlogz(cfg)),
        "--seed",
        string(seed),
        "--queue-size",
        string(active_queue_size(cfg)),
        "--work-repeats",
        string(work_repeats),
        "--sleep-ms",
        @sprintf("%.17g", cfg.sleep_ms),
        "--calibration-trials",
        string(cfg.calibration_trials),
    ]
    cfg.mode == "smoke" && push!(common, "--quick")
    if implementation == "julia"
        return [
            cfg.julia_exe,
            "--threads=$(cfg.threads)",
            "--project=.",
            joinpath(ROOT, "examples", "air_quality_pe_julia.jl"),
            common...,
            "--proposal-scheduler",
            "auto",
        ]
    else
        return [
            cfg.python_exe,
            joinpath(ROOT, "examples", "air_quality_pe_python.py"),
            common...,
            "--nproc",
            string(active_nproc(cfg)),
            "--multiprocessing-start-method",
            cfg.python_start_method,
        ]
    end
end

function run_monitored!(
    cmd_words::Vector{String},
    env_pairs,
    run_dir::String;
    allow_missing_usr_time::Bool=false,
)
    mkpath(run_dir)
    stdout_path = joinpath(run_dir, "stdout.txt")
    stderr_path = joinpath(run_dir, "stderr.txt")
    monitor_path = joinpath(run_dir, "monitor_metadata.json")
    use_usr_time = time_command_available()
    full_cmd = use_usr_time ? [TIME_COMMAND, "-v", cmd_words...] : cmd_words
    cmd_env = copy(ENV)
    for (key, value) in env_pairs
        cmd_env[string(key)] = string(value)
    end
    cmd = setenv(Cmd(Cmd(Cmd(full_cmd); ignorestatus=true); dir=ROOT), cmd_env)
    start_wall = time()
    peak = MemoryPeak(0, nothing, 0, false)
    proc = nothing
    stdout_io = open(stdout_path, "w")
    stderr_io = open(stderr_path, "w")
    try
        proc = run(pipeline(cmd; stdout=stdout_io, stderr=stderr_io); wait=false)
        root_pid = try
            getpid(proc)
        catch
            nothing
        end
        monitor_task = if isnothing(root_pid)
            nothing
        else
            Threads.@async monitor_memory!(peak, root_pid, proc)
        end
        wait(proc)
        !isnothing(monitor_task) && wait(monitor_task)
    finally
        close(stdout_io)
        close(stderr_io)
    end
    measured_wall = time() - start_wall
    exit_code = isnothing(proc) ? -1 : getfield(proc, :exitcode)
    stderr_text = isfile(stderr_path) ? read(stderr_path, String) : ""
    time_metrics = use_usr_time ? parse_time_v(stderr_text) : Dict{String, Any}()
    if !haskey(time_metrics, "wall_time_seconds")
        time_metrics["wall_time_seconds"] = measured_wall
    end
    if !haskey(time_metrics, "time_max_rss_kb") && peak.peak_rss_kb > 0
        time_metrics["time_max_rss_kb"] = peak.peak_rss_kb
    end
    if haskey(time_metrics, "user_cpu_seconds") &&
        haskey(time_metrics, "system_cpu_seconds")
        total = time_metrics["user_cpu_seconds"] + time_metrics["system_cpu_seconds"]
        time_metrics["total_cpu_seconds"] = total
        wall = get(time_metrics, "wall_time_seconds", measured_wall)
        if isnothing(wall) || !(wall isa Real) || wall <= 0
            wall = measured_wall
            time_metrics["wall_time_seconds"] = wall
        end
        time_metrics["cpu_utilization"] = wall > 0 ? total / wall : nothing
    end
    payload = Dict{String, Any}(
        "command" => full_cmd,
        "raw_command" => cmd_words,
        "env" => Dict(env_pairs),
        "stdout_file" => stdout_path,
        "stderr_file" => stderr_path,
        "exit_code" => exit_code,
        "success" => exit_code == 0,
        "used_usr_bin_time" => use_usr_time,
        "time_unavailable" => !use_usr_time,
        "monitor_kind" => use_usr_time ? "gnu_time" : "process_monitor",
        "used_process_monitor" => true,
        "measured_wall_time_seconds" => measured_wall,
        "memory_sample_interval_seconds" => MEMORY_SAMPLE_INTERVAL_SECONDS,
        "process_tree_peak_rss_kb" => peak.peak_rss_kb == 0 ? nothing : peak.peak_rss_kb,
        "process_tree_peak_pss_kb" => peak.pss_available ? peak.peak_pss_kb : nothing,
        "process_tree_peak_processes" => peak.peak_processes,
        "pss_available" => peak.pss_available,
        "time_metrics" => time_metrics,
    )
    write_json(monitor_path, payload)
    return payload
end

function metadata_paths(run_dir::String, implementation::String)
    prefix = implementation == "julia" ? "julia" : "python"
    return (
        metadata=joinpath(run_dir, "$(prefix)_metadata.json"),
        samples=joinpath(run_dir, "$(prefix)_weighted_samples.csv"),
    )
end

function expected_run_shape(
    cfg::RunConfig, implementation::String, repeat::Int, work_repeats::Int
)
    return Dict{String, Any}(
        "mode" => cfg.mode,
        "implementation" => implementation,
        "repeat" => repeat,
        "work_repeats" => work_repeats,
        "queue_size" => active_queue_size(cfg),
        "threads" => cfg.threads,
        "nproc" => active_nproc(cfg),
        "nlive" => active_nlive(cfg),
        "dlogz" => active_dlogz(cfg),
        "sleep_ms" => cfg.sleep_ms,
    )
end

function reusable_existing_run(
    cfg::RunConfig,
    implementation::String,
    repeat::Int,
    run_dir::String,
    monitor::Dict{String, Any},
    work_repeats::Int,
)
    get(monitor, "success", false) == true || return false
    if cfg.mode == "formal"
        monitor_kind(monitor) in ("gnu_time", "process_monitor") || return false
    end
    config_path = joinpath(run_dir, "run_config.json")
    isfile(config_path) || return false
    run_cfg = read_json_dict(config_path)
    expected = expected_run_shape(cfg, implementation, repeat, work_repeats)
    for key in ("mode", "implementation", "repeat", "work_repeats", "queue_size", "nlive")
        get(run_cfg, key, nothing) == expected[key] || return false
    end
    paths = metadata_paths(run_dir, implementation)
    meta = read_json_dict(paths.metadata)
    get(meta, "nlive", nothing) == expected["nlive"] || return false
    get(meta, "work_repeats", nothing) == expected["work_repeats"] || return false
    isfile(paths.samples) || return false
    return true
end

function row_from_run(
    cfg::RunConfig,
    implementation::String,
    repeat::Int,
    run_dir::String,
    monitor::Dict{String, Any},
)
    paths = metadata_paths(run_dir, implementation)
    meta = read_json_dict(paths.metadata)
    time_metrics = get(monitor, "time_metrics", Dict{String, Any}())
    wall = get(
        time_metrics,
        "wall_time_seconds",
        get(monitor, "measured_wall_time_seconds", nothing),
    )
    user_cpu = get(time_metrics, "user_cpu_seconds", nothing)
    system_cpu = get(time_metrics, "system_cpu_seconds", nothing)
    total_cpu = get(time_metrics, "total_cpu_seconds", nothing)
    cpu_util = get(time_metrics, "cpu_utilization", nothing)
    return Dict{String, Any}(
        "mode" => cfg.mode,
        "implementation" => implementation,
        "repeat" => repeat,
        "run_id" => run_id(implementation, repeat),
        "status" =>
            if get(monitor, "success", false) == true &&
                get(meta, "status", "ok") != "failed"
                "ok"
            else
                "failed"
            end,
        "exit_code" => get(monitor, "exit_code", nothing),
        "used_usr_bin_time" => get(monitor, "used_usr_bin_time", false),
        "time_unavailable" => get(monitor, "time_unavailable", false),
        "monitor_kind" => monitor_kind(monitor),
        "wall_time_seconds" => wall,
        "user_cpu_seconds" => user_cpu,
        "system_cpu_seconds" => system_cpu,
        "total_cpu_seconds" => total_cpu,
        "cpu_utilization" => cpu_util,
        "time_percent_cpu" => get(time_metrics, "time_percent_cpu", nothing),
        "time_max_rss_kb" => get(time_metrics, "time_max_rss_kb", nothing),
        "process_tree_peak_rss_kb" => get(monitor, "process_tree_peak_rss_kb", nothing),
        "process_tree_peak_pss_kb" => get(monitor, "process_tree_peak_pss_kb", nothing),
        "pss_available" => get(monitor, "pss_available", false),
        "memory_sample_interval_seconds" =>
            get(monitor, "memory_sample_interval_seconds", nothing),
        "nlive" => get(meta, "nlive", active_nlive(cfg)),
        "dlogz" => get(meta, "dlogz", active_dlogz(cfg)),
        "queue_size" => get(meta, "queue_size", active_queue_size(cfg)),
        "threads" =>
            get(meta, "threads", implementation == "julia" ? cfg.threads : nothing),
        "nproc" =>
            get(meta, "nproc", implementation == "python" ? active_nproc(cfg) : nothing),
        "pool" => get(
            meta,
            "pool",
            implementation == "python" ? "multiprocessing.Pool" : "Julia threads",
        ),
        "bridge_kind" => get(meta, "bridge_kind", nothing),
        "bridge_init_status" => get(
            meta,
            "bridge_init_status",
            implementation == "julia" ? "not_applicable" : nothing,
        ),
        "bridge_init_seconds" => get(meta, "bridge_init_seconds", nothing),
        "proposal_scheduler" =>
            get(meta, "proposal_scheduler", implementation == "julia" ? "auto" : nothing),
        "work_repeats" => get(meta, "work_repeats", nothing),
        "sleep_ms" => get(meta, "sleep_ms", cfg.sleep_ms),
        "seed" => get(meta, "seed", nothing),
        "likelihood_call_count" => get(meta, "likelihood_call_count", nothing),
        "direct_julia_likelihood_median_seconds" =>
            get(meta, "direct_julia_likelihood_median_seconds", nothing),
        "python_bridge_likelihood_median_seconds" =>
            get(meta, "python_bridge_likelihood_median_seconds", nothing),
        "nsamples" => get(meta, "nsamples", nothing),
        "ncall" => get(meta, "ncall", nothing),
        "logz" => get(meta, "logz", nothing),
        "logzerr" => get(meta, "logzerr", nothing),
        "posterior_weighted_mean" => get(meta, "posterior_weighted_mean", nothing),
        "posterior_weighted_covariance_diagonal" =>
            get(meta, "posterior_weighted_covariance_diagonal", nothing),
        "truth" => get(meta, "truth", nothing),
        "dataset_shape" =>
            get(get(meta, "dataset", Dict{String, Any}()), "dataset_shape", nothing),
        "python_executable" => get(
            meta,
            "python_executable",
            implementation == "python" ? cfg.python_exe : nothing,
        ),
        "python_version" => get(meta, "python_version", nothing),
        "julia_version" => get(meta, "julia_version", nothing),
        "dynesty_file" => get(meta, "dynesty_file", nothing),
        "dynesty_version" => get(meta, "dynesty_version", nothing),
        "numpy_version" => get(meta, "numpy_version", nothing),
        "scipy_version" => get(meta, "scipy_version", nothing),
        "corner_available" => get(meta, "corner_available", nothing),
        "matplotlib_available" => get(meta, "matplotlib_available", nothing),
        "run_dir" => run_dir,
        "samples_file" => paths.samples,
        "metadata_file" => paths.metadata,
        "stdout_file" => get(monitor, "stdout_file", joinpath(run_dir, "stdout.txt")),
        "stderr_file" => get(monitor, "stderr_file", joinpath(run_dir, "stderr.txt")),
        "monitor_metadata_file" => joinpath(run_dir, "monitor_metadata.json"),
        "command" => join(get(monitor, "command", String[]), " "),
    )
end

function run_one!(cfg::RunConfig, implementation::String, repeat::Int, work_repeats::Int)
    id = run_id(implementation, repeat)
    run_dir = joinpath(cfg.output_dir, "runs", id)
    monitor_path = joinpath(run_dir, "monitor_metadata.json")
    if cfg.resume && isfile(monitor_path)
        monitor = read_json_dict(monitor_path)
        if reusable_existing_run(
            cfg, implementation, repeat, run_dir, monitor, work_repeats
        )
            @info "Skipping existing successful run" id
            return row_from_run(cfg, implementation, repeat, run_dir, monitor)
        end
    end
    mkpath(run_dir)
    cmd = command_for(cfg, implementation, repeat, run_dir, work_repeats)
    expected = expected_run_shape(cfg, implementation, repeat, work_repeats)
    write_json(
        joinpath(run_dir, "run_config.json"),
        Dict{String, Any}(
            expected...,
            "command" => cmd,
            "python_dynesty_path" => PYTHON_DYNESTY_PATH,
            "comparison_label" => "Julia $(cfg.threads) threads direct Julia likelihood vs Python dynesty $(active_nproc(cfg)) worker processes through Julia bridge",
            "python_start_method" => cfg.python_start_method,
        ),
    )
    @info "Starting air-quality PE benchmark run" id command = join(cmd, " ")
    monitor = run_monitored!(
        cmd,
        base_env_pairs(implementation),
        run_dir;
        allow_missing_usr_time=cfg.allow_missing_usr_time,
    )
    row = row_from_run(cfg, implementation, repeat, run_dir, monitor)
    row["status"] == "ok" ||
        @warn "Air-quality PE benchmark run failed" id exit_code = row["exit_code"]
    return row
end

function maybe_plot_pair(
    cfg::RunConfig, julia_row::Dict{String, Any}, python_row::Dict{String, Any}
)
    repeat = Int(julia_row["repeat"])
    plot_summary = joinpath(
        cfg.output_dir, "plots", "air_quality_repeat$(repeat)_julia_vs_python_summary.json"
    )
    plot_png = joinpath(
        cfg.output_dir, "plots", "air_quality_repeat$(repeat)_julia_vs_python.png"
    )
    missing_samples =
        !isfile(String(julia_row["samples_file"])) ||
        !isfile(String(python_row["samples_file"]))
    pair_failed = julia_row["status"] != "ok" || python_row["status"] != "ok"
    if cfg.skip_plots || pair_failed || missing_samples
        payload = Dict{String, Any}(
            "status" => cfg.skip_plots ? "skipped" : "failed",
            "message" => if cfg.skip_plots
                "plot generation skipped"
            elseif pair_failed
                "one or both runs failed"
            else
                "one or both runs did not produce samples"
            end,
            "plot_file" => nothing,
            "method" => nothing,
            "comparison" => "air_quality_julia_vs_python",
            "repeat" => repeat,
        )
        write_json(plot_summary, payload)
        return Dict{String, Any}(
            "repeat" => repeat,
            "comparison" => "air_quality_julia_vs_python",
            "status" => payload["status"],
            "method" => payload["method"],
            "plot_file" => payload["plot_file"],
            "message" => payload["message"],
            "summary_file" => plot_summary,
            "julia_run_dir" => julia_row["run_dir"],
            "python_run_dir" => python_row["run_dir"],
            "julia_samples_file" => julia_row["samples_file"],
            "python_samples_file" => python_row["samples_file"],
            "julia_metadata_file" => julia_row["metadata_file"],
            "python_metadata_file" => python_row["metadata_file"],
        )
    end
    cmd = [
        cfg.python_exe,
        joinpath(ROOT, "benchmark", "air_quality_corner_overlay.py"),
        "--julia-samples",
        String(julia_row["samples_file"]),
        "--julia-metadata",
        String(julia_row["metadata_file"]),
        "--python-samples",
        String(python_row["samples_file"]),
        "--python-metadata",
        String(python_row["metadata_file"]),
        "--output-png",
        plot_png,
        "--summary-json",
        plot_summary,
        "--repeat",
        string(repeat),
        "--title",
        "Air-quality PM2.5 PE repeat $(repeat): Julia vs Python",
    ]
    proc = run(Cmd(Cmd(cmd); ignorestatus=true))
    payload = read_json_dict(plot_summary)
    if !success(proc) && isempty(payload)
        payload = Dict{String, Any}(
            "status" => "failed",
            "message" => "plot command exited nonzero and did not write summary",
            "plot_file" => nothing,
            "method" => nothing,
        )
        write_json(plot_summary, payload)
    end
    return Dict{String, Any}(
        "repeat" => repeat,
        "comparison" => "air_quality_julia_vs_python",
        "status" => get(payload, "status", "unknown"),
        "method" => get(payload, "method", nothing),
        "plot_file" => get(payload, "plot_file", nothing),
        "message" => get(payload, "message", ""),
        "summary_file" => plot_summary,
        "julia_run_dir" => julia_row["run_dir"],
        "python_run_dir" => python_row["run_dir"],
        "julia_samples_file" => julia_row["samples_file"],
        "python_samples_file" => python_row["samples_file"],
        "julia_metadata_file" => julia_row["metadata_file"],
        "python_metadata_file" => python_row["metadata_file"],
        "julia_nsamples" => julia_row["nsamples"],
        "python_nsamples" => python_row["nsamples"],
        "julia_logz" => julia_row["logz"],
        "python_logz" => python_row["logz"],
        "julia_logzerr" => julia_row["logzerr"],
        "python_logzerr" => python_row["logzerr"],
    )
end

function refresh_overlay_plots!(
    cfg::RunConfig,
    rows::Vector{Dict{String, Any}},
    plot_rows_by_key::Dict{Int, Dict{String, Any}},
)
    rows_by_key = Dict{Tuple{Int, String}, Dict{String, Any}}()
    for row in rows
        rows_by_key[(Int(row["repeat"]), String(row["implementation"]))] = row
    end
    for repeat in 1:active_repeats(cfg)
        haskey(plot_rows_by_key, repeat) && continue
        julia_row = get(rows_by_key, (repeat, "julia"), nothing)
        python_row = get(rows_by_key, (repeat, "python"), nothing)
        (isnothing(julia_row) || isnothing(python_row)) && continue
        plot_rows_by_key[repeat] = maybe_plot_pair(cfg, julia_row, python_row)
    end
    return plot_rows_by_key
end

function ordered_plot_rows(plot_rows_by_key::Dict{Int, Dict{String, Any}})
    rows = collect(values(plot_rows_by_key))
    sort!(rows; by=row -> Int(row["repeat"]))
    return rows
end

function median_or_nothing(values)
    clean = Float64[]
    for value in values
        isnothing(value) && continue
        parsed = tryparse(Float64, string(value))
        if !isnothing(parsed) && isfinite(parsed)
            push!(clean, parsed)
        end
    end
    isempty(clean) && return nothing
    return median(clean)
end

function aggregate_rows(rows)
    groups = Dict{String, Vector{Dict{String, Any}}}()
    for row in rows
        row["status"] == "ok" || continue
        push!(get!(groups, String(row["implementation"]), Dict{String, Any}[]), row)
    end
    aggs = Dict{String, Any}[]
    for implementation in sort(collect(keys(groups)))
        group = groups[implementation]
        push!(
            aggs,
            Dict{String, Any}(
                "implementation" => implementation,
                "successful_runs" => length(group),
                "median_wall_time_seconds" => median_or_nothing([
                    get(row, "wall_time_seconds", nothing) for row in group
                ]),
                "median_cpu_utilization" => median_or_nothing([
                    get(row, "cpu_utilization", nothing) for row in group
                ]),
                "median_process_tree_peak_rss_kb" => median_or_nothing([
                    get(row, "process_tree_peak_rss_kb", nothing) for row in group
                ]),
                "median_process_tree_peak_pss_kb" => median_or_nothing([
                    get(row, "process_tree_peak_pss_kb", nothing) for row in group
                ]),
                "median_nsamples" =>
                    median_or_nothing([get(row, "nsamples", nothing) for row in group]),
                "median_logz" =>
                    median_or_nothing([get(row, "logz", nothing) for row in group]),
                "median_logzerr" =>
                    median_or_nothing([get(row, "logzerr", nothing) for row in group]),
                "median_direct_julia_likelihood_seconds" => median_or_nothing([
                    get(row, "direct_julia_likelihood_median_seconds", nothing) for
                    row in group
                ]),
                "median_python_bridge_likelihood_seconds" => median_or_nothing([
                    get(row, "python_bridge_likelihood_median_seconds", nothing) for
                    row in group
                ]),
            ),
        )
    end
    return aggs
end

function write_outputs(cfg::RunConfig, rows, plot_rows, calibration)
    summary_columns = [
        "mode",
        "implementation",
        "repeat",
        "run_id",
        "status",
        "exit_code",
        "used_usr_bin_time",
        "time_unavailable",
        "monitor_kind",
        "wall_time_seconds",
        "user_cpu_seconds",
        "system_cpu_seconds",
        "total_cpu_seconds",
        "cpu_utilization",
        "time_percent_cpu",
        "time_max_rss_kb",
        "process_tree_peak_rss_kb",
        "process_tree_peak_pss_kb",
        "pss_available",
        "memory_sample_interval_seconds",
        "nlive",
        "dlogz",
        "queue_size",
        "threads",
        "nproc",
        "pool",
        "bridge_kind",
        "bridge_init_status",
        "bridge_init_seconds",
        "proposal_scheduler",
        "work_repeats",
        "sleep_ms",
        "seed",
        "likelihood_call_count",
        "direct_julia_likelihood_median_seconds",
        "python_bridge_likelihood_median_seconds",
        "nsamples",
        "ncall",
        "logz",
        "logzerr",
        "python_executable",
        "python_version",
        "julia_version",
        "dynesty_file",
        "dynesty_version",
        "numpy_version",
        "scipy_version",
        "corner_available",
        "matplotlib_available",
        "run_dir",
        "samples_file",
        "metadata_file",
        "stdout_file",
        "stderr_file",
        "monitor_metadata_file",
        "command",
    ]
    plot_columns = [
        "repeat",
        "comparison",
        "status",
        "method",
        "plot_file",
        "message",
        "summary_file",
        "julia_run_dir",
        "python_run_dir",
        "julia_samples_file",
        "python_samples_file",
        "julia_metadata_file",
        "python_metadata_file",
        "julia_nsamples",
        "python_nsamples",
        "julia_logz",
        "python_logz",
        "julia_logzerr",
        "python_logzerr",
    ]
    summary_csv = joinpath(cfg.output_dir, "summary.csv")
    plot_csv = joinpath(cfg.output_dir, "plot_index.csv")
    calibration_json = joinpath(cfg.output_dir, "calibration.json")
    write_csv(summary_csv, rows, summary_columns)
    write_csv(plot_csv, plot_rows, plot_columns)
    write_json(calibration_json, calibration)
    payload = Dict{String, Any}(
        "created_at" => string(now()),
        "mode" => cfg.mode,
        "comparison_label" => "Julia $(cfg.threads) threads direct Julia likelihood vs Python dynesty $(active_nproc(cfg)) worker processes through Julia bridge",
        "output_dir" => cfg.output_dir,
        "python_dynesty_path" => PYTHON_DYNESTY_PATH,
        "configuration" => Dict(
            "queue_size" => active_queue_size(cfg),
            "threads" => cfg.threads,
            "nproc" => active_nproc(cfg),
            "nlive" => active_nlive(cfg),
            "dlogz" => active_dlogz(cfg),
            "repeats" => active_repeats(cfg),
            "formal_request" => Dict(
                "nlive" => cfg.nlive,
                "dlogz" => cfg.dlogz,
                "repeats" => cfg.repeats,
                "queue_size" => cfg.queue_size,
                "threads" => cfg.threads,
                "nproc" => cfg.nproc,
            ),
            "smoke_request" => Dict(
                "nlive" => cfg.smoke_nlive,
                "dlogz" => cfg.smoke_dlogz,
                "queue_size" => cfg.smoke_queue_size,
                "nproc" => cfg.smoke_nproc,
            ),
            "work_repeats" => calibration["work_repeats"],
            "sleep_ms" => cfg.sleep_ms,
            "python_start_method" => cfg.python_start_method,
            "used_usr_bin_time" =>
                any(get(row, "used_usr_bin_time", false) == true for row in rows),
            "monitor_kind" => monitor_kind(),
            "time_command" => TIME_COMMAND,
            "time_command_available" => time_command_available(),
            "process_monitor_available" => Sys.islinux(),
            "memory_sample_interval_seconds" => MEMORY_SAMPLE_INTERVAL_SECONDS,
        ),
        "environment" => Dict(
            "OPENBLAS_NUM_THREADS" => "1",
            "OMP_NUM_THREADS" => "1",
            "MKL_NUM_THREADS" => "1",
        ),
        "likelihood_model" => air_quality_dataset_metadata(;
            work_repeats=Int(calibration["work_repeats"]), sleep_ms=cfg.sleep_ms
        ),
        "bridge" => Dict(
            "preferred" => "juliacall",
            "fallback" => "PyJulia",
            "observed_kinds" => sort(
                collect(
                    Set([
                        String(row["bridge_kind"]) for
                        row in rows if !isnothing(row["bridge_kind"])
                    ]),
                ),
            ),
            "observed_statuses" => sort(
                collect(
                    Set([
                        String(row["bridge_init_status"]) for
                        row in rows if !isnothing(row["bridge_init_status"])
                    ]),
                ),
            ),
        ),
        "calibration" => calibration,
        "runs" => rows,
        "plots" => plot_rows,
        "aggregates" => aggregate_rows(rows),
    )
    summary_json = joinpath(cfg.output_dir, "summary.json")
    write_json(summary_json, payload)
    return (
        summary_csv=summary_csv,
        summary_json=summary_json,
        plot_csv=plot_csv,
        calibration_json=calibration_json,
    )
end

function choose_calibration(cfg::RunConfig)
    selected = if isnothing(cfg.work_repeats)
        auto_calibrate_air_quality_likelihood(;
            target_seconds=cfg.target_likelihood_seconds,
            ntrial=cfg.calibration_trials,
            sleep_ms=cfg.sleep_ms,
        )
    else
        calibrate_air_quality_likelihood(;
            work_repeats=cfg.work_repeats,
            ntrial=cfg.calibration_trials,
            sleep_ms=cfg.sleep_ms,
        )
    end
    selected["dataset"] = air_quality_dataset_metadata(;
        work_repeats=Int(selected["work_repeats"]), sleep_ms=cfg.sleep_ms
    )
    return selected
end

function main(args=ARGS)
    cfg = parse_cli(args)
    mkpath(cfg.output_dir)
    if !isdir(PYTHON_DYNESTY_PATH)
        error("expected read-only Python dynesty source at $PYTHON_DYNESTY_PATH")
    end
    if !time_command_available()
        @warn "/usr/bin/time is missing; using Julia/Linux process monitor for wall time and process-tree RSS/PSS metrics" mode =
            cfg.mode
    end
    calibration = choose_calibration(cfg)
    work_repeats = Int(calibration["work_repeats"])
    @info "Air-quality likelihood calibration selected" work_repeats median_seconds = calibration["median_seconds"]
    rows = Dict{String, Any}[]
    plot_rows_by_key = Dict{Int, Dict{String, Any}}()
    try
        for item in run_matrix(cfg)
            row = run_one!(cfg, item.implementation, item.repeat, work_repeats)
            push!(rows, row)
            refresh_overlay_plots!(cfg, rows, plot_rows_by_key)
            plot_rows = ordered_plot_rows(plot_rows_by_key)
            outputs = write_outputs(cfg, rows, plot_rows, calibration)
            @info "Updated air-quality benchmark summaries" summary_csv =
                outputs.summary_csv summary_json = outputs.summary_json
            if row["status"] != "ok"
                error(
                    "benchmark run $(row["run_id"]) failed; see $(row["stderr_file"]) and $(row["stdout_file"])",
                )
            end
        end
    catch err
        plot_rows = ordered_plot_rows(plot_rows_by_key)
        outputs = write_outputs(cfg, rows, plot_rows, calibration)
        @error "Air-quality benchmark stopped before completing all requested runs" error =
            err summary_json = outputs.summary_json
        rethrow()
    end
    plot_rows = ordered_plot_rows(plot_rows_by_key)
    outputs = write_outputs(cfg, rows, plot_rows, calibration)
    println("Wrote summary CSV: $(outputs.summary_csv)")
    println("Wrote summary JSON: $(outputs.summary_json)")
    println("Wrote plot index CSV: $(outputs.plot_csv)")
    println("Wrote calibration JSON: $(outputs.calibration_json)")
    println(
        "Comparison: Julia $(cfg.threads) threads direct Julia likelihood vs Python dynesty $(active_nproc(cfg)) worker processes through Julia bridge",
    )
    return rows
end

const THIS_FILE = @__FILE__

if abspath(PROGRAM_FILE) == abspath(THIS_FILE)
    main()
end
