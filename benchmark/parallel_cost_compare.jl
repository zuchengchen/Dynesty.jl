#!/usr/bin/env julia

using Dates
using JSON3
using Printf
using Statistics

const ROOT = abspath(joinpath(@__DIR__, ".."))
const DEFAULT_OUTPUT_DIR = joinpath(ROOT, "examples", "output", "parallel_cost_compare")
const PYTHON_DYNESTY_PATH = abspath(joinpath(ROOT, "..", "dynesty", "py"))
const COST_DEFAULTS = Dict("cheap" => 0, "medium" => 2_000, "heavy" => 10_000)
const IMPLEMENTATIONS = ("julia", "python")
const TIME_COMMAND = "/usr/bin/time"
const MEMORY_SAMPLE_INTERVAL_SECONDS = 0.2

mutable struct RunConfig
    mode::String
    output_dir::String
    costs::Vector{String}
    repeats::Int
    nlive::Int
    dlogz::Float64
    smoke_nlive::Int
    smoke_dlogz::Float64
    queue_size::Int
    threads::Int
    nproc::Int
    julia_exe::String
    python_exe::String
    heavy_work_size::Int
    allow_missing_usr_time::Bool
    skip_plots::Bool
    resume::Bool
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
      julia --project=. benchmark/parallel_cost_compare.jl --mode smoke|formal [options]

    Key options:
      --output-dir PATH              default: examples/output/parallel_cost_compare
      --mode smoke|formal            smoke runs cheap Julia/Python once; formal runs 18 total
      --queue-size N                 default: 31
      --threads N                    Julia worker threads, default: 31
      --nproc N                      Python multiprocessing worker processes, default: 31
      --heavy-work-size N            default: 10000
      --allow-missing-usr-time       only for smoke/debug on hosts without /usr/bin/time
      --skip-plots                   keep performance summary even if plots are not needed
      --resume                       skip successful run directories already present
    """
end

function parse_cli(args)
    cfg = RunConfig(
        "smoke",
        DEFAULT_OUTPUT_DIR,
        ["cheap", "medium", "heavy"],
        3,
        1500,
        0.02,
        180,
        0.5,
        31,
        31,
        31,
        get(ENV, "JULIA", "julia"),
        get(ENV, "PYTHON", "python3"),
        10_000,
        false,
        false,
        false,
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
        elseif arg == "--costs"
            cfg.costs = split(args[i + 1], ",")
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
        elseif arg == "--threads"
            cfg.threads = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--nproc"
            cfg.nproc = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--julia-exe"
            cfg.julia_exe = args[i + 1]
            i += 2
        elseif arg == "--python-exe"
            cfg.python_exe = args[i + 1]
            i += 2
        elseif arg == "--heavy-work-size"
            cfg.heavy_work_size = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--allow-missing-usr-time"
            cfg.allow_missing_usr_time = true
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
    cfg.queue_size > 0 || throw(ArgumentError("--queue-size must be positive"))
    cfg.threads > 0 || throw(ArgumentError("--threads must be positive"))
    cfg.nproc > 0 || throw(ArgumentError("--nproc must be positive"))
    cfg.heavy_work_size >= 0 || throw(ArgumentError("--heavy-work-size must be nonnegative"))
    unknown = setdiff(cfg.costs, collect(keys(COST_DEFAULTS)))
    isempty(unknown) || throw(ArgumentError("unknown costs: $(join(unknown, ", "))"))
    return cfg
end

work_size_for(cost::String, cfg::RunConfig) =
    cost == "heavy" ? cfg.heavy_work_size : COST_DEFAULTS[cost]

function run_matrix(cfg::RunConfig)
    if cfg.mode == "smoke"
        return [(cost="cheap", implementation=impl, repeat=1) for impl in IMPLEMENTATIONS]
    end
    return [
        (cost=cost, implementation=impl, repeat=repeat)
        for cost in cfg.costs for impl in IMPLEMENTATIONS for repeat in 1:cfg.repeats
    ]
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
    while process_running(proc)
        sample = sample_tree_memory(root_pid)
        if sample.rss_kb > peak.peak_rss_kb
            peak.peak_rss_kb = sample.rss_kb
            peak.peak_processes = sample.processes
        end
        if sample.pss_available && !isnothing(sample.pss_kb)
            if isnothing(peak.peak_pss_kb) || sample.pss_kb > peak.peak_pss_kb
                peak.peak_pss_kb = sample.pss_kb
            end
        else
            peak.pss_available = false
        end
        sleep(MEMORY_SAMPLE_INTERVAL_SECONDS)
    end
    sample = sample_tree_memory(root_pid)
    peak.peak_rss_kb = max(peak.peak_rss_kb, sample.rss_kb)
    if sample.pss_available && !isnothing(sample.pss_kb)
        peak.peak_pss_kb = isnothing(peak.peak_pss_kb) ? sample.pss_kb :
                           max(peak.peak_pss_kb, sample.pss_kb)
    else
        peak.pss_available = false
    end
    return peak
end

function parse_elapsed_seconds(text::AbstractString)
    parts = split(strip(text), ":")
    if length(parts) == 3
        return parse(Float64, parts[1]) * 3600 + parse(Float64, parts[2]) * 60 +
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
            value = replace(raw, "%" => "")
            metrics["time_percent_cpu_numeric"] = tryparse(Float64, value)
        elseif occursin("Elapsed (wall clock) time", line)
            metrics["wall_time_seconds"] = parse_elapsed_seconds(time_value_after_label(line))
        elseif occursin("Maximum resident set size (kbytes):", line)
            metrics["time_max_rss_kb"] = parse(Int, time_value_after_label(line))
        end
    end
    if haskey(metrics, "user_cpu_seconds") && haskey(metrics, "system_cpu_seconds")
        total = metrics["user_cpu_seconds"] + metrics["system_cpu_seconds"]
        metrics["total_cpu_seconds"] = total
        wall = get(metrics, "wall_time_seconds", nothing)
        metrics["cpu_utilization"] =
            (!isnothing(wall) && wall > 0) ? total / wall : nothing
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

function base_env_pairs(cfg::RunConfig, implementation::String)
    pairs = [
        "OPENBLAS_NUM_THREADS" => "1",
        "OMP_NUM_THREADS" => "1",
        "MKL_NUM_THREADS" => "1",
    ]
    if implementation == "python"
        push!(pairs, "PYTHONPATH" => PYTHON_DYNESTY_PATH)
    end
    return pairs
end

function run_id(cost::String, implementation::String, repeat::Int)
    return "$(cost)_$(implementation)_repeat$(repeat)"
end

function command_for(cfg::RunConfig, cost::String, implementation::String, repeat::Int, run_dir::String)
    nlive = cfg.mode == "smoke" ? cfg.smoke_nlive : cfg.nlive
    dlogz = cfg.mode == "smoke" ? cfg.smoke_dlogz : cfg.dlogz
    seed = 20240610 + repeat + (cost == "medium" ? 100 : cost == "heavy" ? 200 : 0) +
           (implementation == "python" ? 10_000 : 0)
    work_size = work_size_for(cost, cfg)
    common = [
        "--output-dir",
        run_dir,
        "--nlive",
        string(nlive),
        "--dlogz",
        @sprintf("%.17g", dlogz),
        "--seed",
        string(seed),
        "--queue-size",
        string(cfg.queue_size),
        "--likelihood-cost",
        cost,
        "--sleep-ms",
        "0",
        "--work-size",
        string(work_size),
    ]
    if implementation == "julia"
        return [
            cfg.julia_exe,
            "--threads=$(cfg.threads)",
            "--project=.",
            joinpath(ROOT, "examples", "pe_parallel_julia.jl"),
            common...,
            "--proposal-scheduler",
            "auto",
        ]
    else
        return [
            cfg.python_exe,
            joinpath(ROOT, "examples", "pe_parallel_python.py"),
            common...,
            "--nproc",
            string(cfg.nproc),
            "--pool-kind",
            "multiprocessing",
        ]
    end
end

function time_command_available()
    return isfile(TIME_COMMAND) && Sys.isexecutable(TIME_COMMAND)
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
    if !use_usr_time && !allow_missing_usr_time
        error(
            "required /usr/bin/time -v is not available on this host; install GNU time or rerun smoke/debug with --allow-missing-usr-time",
        )
    end
    full_cmd = use_usr_time ? [TIME_COMMAND, "-v", cmd_words...] : cmd_words
    cmd = Cmd(Cmd(Cmd(full_cmd); ignorestatus=true); dir=ROOT)
    cmd_env = copy(ENV)
    for (key, value) in env_pairs
        cmd_env[string(key)] = string(value)
    end
    cmd = setenv(cmd, cmd_env)
    start_wall = time()
    peak = MemoryPeak(0, nothing, 0, true)
    proc = nothing
    stdout_io = open(stdout_path, "w")
    stderr_io = open(stderr_path, "w")
    try
        proc = run(pipeline(cmd, stdout=stdout_io, stderr=stderr_io), wait=false)
        root_pid = try
            getpid(proc)
        catch
            nothing
        end
        monitor_task = isnothing(root_pid) ? nothing :
                       Threads.@async monitor_memory!(peak, root_pid, proc)
        wait(proc)
        if !isnothing(monitor_task)
            wait(monitor_task)
        end
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
    if haskey(time_metrics, "user_cpu_seconds") && haskey(time_metrics, "system_cpu_seconds")
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
        "measured_wall_time_seconds" => measured_wall,
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

function maybe_plot_run(cfg::RunConfig, row::Dict{String, Any})
    plot_summary = joinpath(String(row["run_dir"]), "plot_summary.json")
    plot_png = joinpath(
        cfg.output_dir,
        "plots",
        "corner_$(row["cost"])_$(row["implementation"])_repeat$(row["repeat"]).png",
    )
    if cfg.skip_plots || row["status"] != "ok" || !isfile(String(row["samples_file"]))
        payload = Dict{String, Any}(
            "status" => cfg.skip_plots ? "skipped" : "failed",
            "message" => cfg.skip_plots ? "plot generation skipped" : "run did not produce samples",
            "plot_file" => nothing,
            "method" => nothing,
        )
        write_json(plot_summary, payload)
        return payload
    end
    cmd = [
        cfg.python_exe,
        joinpath(ROOT, "benchmark", "parallel_cost_corner.py"),
        "--samples",
        String(row["samples_file"]),
        "--metadata",
        String(row["metadata_file"]),
        "--output-png",
        plot_png,
        "--summary-json",
        plot_summary,
        "--implementation",
        String(row["implementation"]),
        "--cost",
        String(row["cost"]),
        "--repeat",
        string(row["repeat"]),
        "--title",
        "$(row["cost"]) $(row["implementation"]) repeat $(row["repeat"])",
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
    return payload
end

function row_from_run(
    cfg::RunConfig,
    cost::String,
    implementation::String,
    repeat::Int,
    run_dir::String,
    monitor::Dict{String, Any},
)
    paths = metadata_paths(run_dir, implementation)
    meta = read_json_dict(paths.metadata)
    time_metrics = get(monitor, "time_metrics", Dict{String, Any}())
    wall = get(time_metrics, "wall_time_seconds", get(monitor, "measured_wall_time_seconds", nothing))
    user_cpu = get(time_metrics, "user_cpu_seconds", nothing)
    system_cpu = get(time_metrics, "system_cpu_seconds", nothing)
    total_cpu = get(time_metrics, "total_cpu_seconds", nothing)
    cpu_util = get(time_metrics, "cpu_utilization", nothing)
    true_theta = get(meta, "true_theta", Any[])
    mean = get(meta, "mean", Any[])
    mean_abs_max = nothing
    mean_l2 = nothing
    if length(true_theta) == length(mean) && !isempty(mean)
        deltas = [abs(Float64(mean[i]) - Float64(true_theta[i])) for i in eachindex(mean)]
        mean_abs_max = maximum(deltas)
        mean_l2 = sqrt(sum(abs2, deltas))
    end
    return Dict{String, Any}(
        "mode" => cfg.mode,
        "cost" => cost,
        "implementation" => implementation,
        "repeat" => repeat,
        "run_id" => run_id(cost, implementation, repeat),
        "status" => get(monitor, "success", false) == true ? "ok" : "failed",
        "exit_code" => get(monitor, "exit_code", nothing),
        "used_usr_bin_time" => get(monitor, "used_usr_bin_time", false),
        "time_unavailable" => get(monitor, "time_unavailable", false),
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
        "nlive" => get(meta, "nlive", cfg.mode == "smoke" ? cfg.smoke_nlive : cfg.nlive),
        "dlogz" => get(meta, "dlogz", cfg.mode == "smoke" ? cfg.smoke_dlogz : cfg.dlogz),
        "queue_size" => get(meta, "queue_size", cfg.queue_size),
        "threads" => get(meta, "threads", implementation == "julia" ? cfg.threads : nothing),
        "nproc" => get(meta, "nproc", implementation == "python" ? cfg.nproc : nothing),
        "pool" => get(meta, "pool", implementation == "python" ? "multiprocessing.Pool" : nothing),
        "proposal_scheduler" => get(meta, "proposal_scheduler", implementation == "julia" ? "auto" : nothing),
        "worker_label" => implementation == "python" ? "Python $(cfg.nproc) worker processes" :
                          "Julia $(cfg.threads) threads",
        "work_size" => get(meta, "work_size", work_size_for(cost, cfg)),
        "sleep_ms" => get(meta, "sleep_ms", 0),
        "seed" => get(meta, "seed", nothing),
        "nsamples" => get(meta, "nsamples", nothing),
        "logz" => get(meta, "logz", nothing),
        "logzerr" => get(meta, "logzerr", nothing),
        "mean_abs_max_delta_from_truth" => mean_abs_max,
        "mean_l2_delta_from_truth" => mean_l2,
        "python_executable" => get(meta, "python_executable", implementation == "python" ? cfg.python_exe : nothing),
        "python_version" => get(meta, "python_version", nothing),
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

function expected_run_shape(cfg::RunConfig, cost::String, implementation::String, repeat::Int)
    return Dict{String, Any}(
        "mode" => cfg.mode,
        "cost" => cost,
        "implementation" => implementation,
        "repeat" => repeat,
        "work_size" => work_size_for(cost, cfg),
        "queue_size" => cfg.queue_size,
        "threads" => cfg.threads,
        "nproc" => cfg.nproc,
        "nlive" => cfg.mode == "smoke" ? cfg.smoke_nlive : cfg.nlive,
        "dlogz" => cfg.mode == "smoke" ? cfg.smoke_dlogz : cfg.dlogz,
    )
end

function _same_number(left, right)
    isnothing(left) && return false
    parsed = tryparse(Float64, string(left))
    isnothing(parsed) && return false
    return isapprox(parsed, Float64(right); atol=1.0e-12, rtol=1.0e-12)
end

function reusable_existing_run(
    cfg::RunConfig,
    cost::String,
    implementation::String,
    repeat::Int,
    run_dir::String,
    monitor::Dict{String, Any},
)
    get(monitor, "success", false) == true || return false
    cfg.mode == "formal" && get(monitor, "used_usr_bin_time", false) != true && return false
    cfg.mode == "formal" && get(monitor, "time_unavailable", true) == true && return false
    config_path = joinpath(run_dir, "run_config.json")
    isfile(config_path) || return false
    run_cfg = read_json_dict(config_path)
    expected = expected_run_shape(cfg, cost, implementation, repeat)
    for key in ("mode", "cost", "implementation", "repeat", "work_size", "queue_size")
        get(run_cfg, key, nothing) == expected[key] || return false
    end
    if implementation == "julia"
        get(run_cfg, "threads", nothing) == cfg.threads || return false
    else
        get(run_cfg, "nproc", nothing) == cfg.nproc || return false
    end
    paths = metadata_paths(run_dir, implementation)
    meta = read_json_dict(paths.metadata)
    get(meta, "nlive", nothing) == expected["nlive"] || return false
    _same_number(get(meta, "dlogz", nothing), expected["dlogz"]) || return false
    get(meta, "work_size", nothing) == expected["work_size"] || return false
    isfile(paths.samples) || return false
    return true
end

function median_or_nothing(values)
    clean = Float64[]
    for value in values
        if !isnothing(value)
            parsed = tryparse(Float64, string(value))
            if !isnothing(parsed) && isfinite(parsed)
                push!(clean, parsed)
            end
        end
    end
    isempty(clean) && return nothing
    return median(clean)
end

function min_or_nothing(values)
    clean = [Float64(v) for v in values if !isnothing(v)]
    isempty(clean) && return nothing
    return minimum(clean)
end

function max_or_nothing(values)
    clean = [Float64(v) for v in values if !isnothing(v)]
    isempty(clean) && return nothing
    return maximum(clean)
end

function aggregate_rows(rows)
    groups = Dict{Tuple{String, String}, Vector{Dict{String, Any}}}()
    for row in rows
        row["status"] == "ok" || continue
        key = (String(row["cost"]), String(row["implementation"]))
        push!(get!(groups, key, Dict{String, Any}[]), row)
    end
    aggs = Dict{String, Any}[]
    for key in sort(collect(keys(groups)))
        group = groups[key]
        wall_values = [get(row, "wall_time_seconds", nothing) for row in group]
        cpu_values = [get(row, "cpu_utilization", nothing) for row in group]
        rss_values = [get(row, "process_tree_peak_rss_kb", nothing) for row in group]
        pss_values = [get(row, "process_tree_peak_pss_kb", nothing) for row in group]
        push!(
            aggs,
            Dict{String, Any}(
                "cost" => key[1],
                "implementation" => key[2],
                "successful_runs" => length(group),
                "median_wall_time_seconds" => median_or_nothing(wall_values),
                "min_wall_time_seconds" => min_or_nothing(wall_values),
                "max_wall_time_seconds" => max_or_nothing(wall_values),
                "median_cpu_utilization" => median_or_nothing(cpu_values),
                "median_process_tree_peak_rss_kb" => median_or_nothing(rss_values),
                "median_process_tree_peak_pss_kb" => median_or_nothing(pss_values),
            ),
        )
    end
    return aggs
end

function write_outputs(cfg::RunConfig, rows, plot_rows)
    summary_columns = [
        "mode",
        "cost",
        "implementation",
        "repeat",
        "run_id",
        "status",
        "exit_code",
        "used_usr_bin_time",
        "time_unavailable",
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
        "nlive",
        "dlogz",
        "queue_size",
        "threads",
        "nproc",
        "pool",
        "proposal_scheduler",
        "worker_label",
        "work_size",
        "sleep_ms",
        "seed",
        "nsamples",
        "logz",
        "logzerr",
        "mean_abs_max_delta_from_truth",
        "mean_l2_delta_from_truth",
        "python_executable",
        "python_version",
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
        "cost",
        "implementation",
        "repeat",
        "status",
        "method",
        "plot_file",
        "message",
        "summary_file",
    ]
    summary_csv = joinpath(cfg.output_dir, "summary.csv")
    plot_csv = joinpath(cfg.output_dir, "plot_index.csv")
    write_csv(summary_csv, rows, summary_columns)
    write_csv(plot_csv, plot_rows, plot_columns)
    payload = Dict{String, Any}(
        "created_at" => string(now()),
        "mode" => cfg.mode,
        "comparison_label" => "Julia $(cfg.threads) threads vs Python $(cfg.nproc) multiprocessing worker processes",
        "output_dir" => cfg.output_dir,
        "python_dynesty_path" => PYTHON_DYNESTY_PATH,
        "environment" => Dict(
            "OPENBLAS_NUM_THREADS" => "1",
            "OMP_NUM_THREADS" => "1",
            "MKL_NUM_THREADS" => "1",
        ),
        "configuration" => Dict(
            "queue_size" => cfg.queue_size,
            "threads" => cfg.threads,
            "nproc" => cfg.nproc,
            "nlive" => cfg.mode == "smoke" ? cfg.smoke_nlive : cfg.nlive,
            "dlogz" => cfg.mode == "smoke" ? cfg.smoke_dlogz : cfg.dlogz,
            "cost_work_sizes" => Dict(cost => work_size_for(cost, cfg) for cost in cfg.costs),
            "sleep_ms" => 0,
            "julia_proposal_scheduler" => "auto",
            "python_pool" => "multiprocessing.Pool",
            "used_usr_bin_time" => any(get(row, "used_usr_bin_time", false) == true for row in rows),
            "time_command" => TIME_COMMAND,
            "time_command_available" => time_command_available(),
        ),
        "runs" => rows,
        "aggregates" => aggregate_rows(rows),
        "plots" => plot_rows,
    )
    summary_json = joinpath(cfg.output_dir, "summary.json")
    write_json(summary_json, payload)
    return (summary_csv=summary_csv, summary_json=summary_json, plot_csv=plot_csv)
end

function run_one!(cfg::RunConfig, cost::String, implementation::String, repeat::Int)
    id = run_id(cost, implementation, repeat)
    run_dir = joinpath(cfg.output_dir, "runs", id)
    monitor_path = joinpath(run_dir, "monitor_metadata.json")
    if cfg.resume && isfile(monitor_path)
        monitor = read_json_dict(monitor_path)
        if reusable_existing_run(cfg, cost, implementation, repeat, run_dir, monitor)
            @info "Skipping existing successful run" id
            return row_from_run(cfg, cost, implementation, repeat, run_dir, monitor)
        else
            @info "Existing run is not reusable for requested benchmark; rerunning" id
        end
    end
    mkpath(run_dir)
    cmd = command_for(cfg, cost, implementation, repeat, run_dir)
    expected = expected_run_shape(cfg, cost, implementation, repeat)
    write_json(
        joinpath(run_dir, "run_config.json"),
        Dict{String, Any}(
            expected...,
            "command" => cmd,
            "python_dynesty_path" => PYTHON_DYNESTY_PATH,
            "comparison_label" => "Julia $(cfg.threads) threads vs Python $(cfg.nproc) multiprocessing worker processes",
        ),
    )
    @info "Starting benchmark run" id command = join(cmd, " ")
    monitor = run_monitored!(
        cmd,
        base_env_pairs(cfg, implementation),
        run_dir;
        allow_missing_usr_time=cfg.allow_missing_usr_time,
    )
    row = row_from_run(cfg, cost, implementation, repeat, run_dir, monitor)
    row["status"] == "ok" || @warn "Benchmark run failed" id exit_code = row["exit_code"]
    return row
end

function main(args=ARGS)
    cfg = parse_cli(args)
    mkpath(cfg.output_dir)
    if !isdir(PYTHON_DYNESTY_PATH)
        error("expected read-only Python dynesty source at $PYTHON_DYNESTY_PATH")
    end
    if !time_command_available() && (cfg.mode == "formal" || !cfg.allow_missing_usr_time)
        error(
            "required /usr/bin/time -v is missing. This benchmark intentionally fails early because the goal requires /usr/bin/time -v metrics.",
        )
    elseif !time_command_available()
        @warn "/usr/bin/time is missing; smoke/debug run will record time_unavailable=true and cannot satisfy formal benchmark requirements"
    end
    rows = Dict{String, Any}[]
    plot_rows = Dict{String, Any}[]
    try
        for item in run_matrix(cfg)
            row = run_one!(cfg, item.cost, item.implementation, item.repeat)
            push!(rows, row)
            plot_summary = maybe_plot_run(cfg, row)
            push!(
                plot_rows,
                Dict{String, Any}(
                    "cost" => row["cost"],
                    "implementation" => row["implementation"],
                    "repeat" => row["repeat"],
                    "status" => get(plot_summary, "status", "unknown"),
                    "method" => get(plot_summary, "method", nothing),
                    "plot_file" => get(plot_summary, "plot_file", nothing),
                    "message" => get(plot_summary, "message", ""),
                    "summary_file" => joinpath(String(row["run_dir"]), "plot_summary.json"),
                ),
            )
            outputs = write_outputs(cfg, rows, plot_rows)
            @info "Updated benchmark summaries" summary_csv = outputs.summary_csv summary_json = outputs.summary_json
            if row["status"] != "ok"
                error("benchmark run $(row["run_id"]) failed; see $(row["stderr_file"]) and $(row["stdout_file"])")
            end
        end
    catch err
        outputs = write_outputs(cfg, rows, plot_rows)
        @error "Benchmark stopped before completing all requested runs" error = err summary_json = outputs.summary_json
        rethrow()
    end
    outputs = write_outputs(cfg, rows, plot_rows)
    println("Wrote summary CSV: $(outputs.summary_csv)")
    println("Wrote summary JSON: $(outputs.summary_json)")
    println("Wrote plot index CSV: $(outputs.plot_csv)")
    println("Comparison: Julia $(cfg.threads) threads vs Python $(cfg.nproc) multiprocessing worker processes")
    return rows
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
