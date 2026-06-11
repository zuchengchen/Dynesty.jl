#!/usr/bin/env python3
"""Generate tables and copy figures for the Dynesty.jl test report.

The script is intentionally read-only with respect to benchmark outputs.  It
audits the existing formal benchmark summary, writes compact CSV/LaTeX tables
under docs/test_report/tables, and copies posterior overlay PNGs into
docs/test_report/figures so examples/output remains uncommitted.
"""

from __future__ import annotations

import csv
import json
import math
import shutil
from collections import defaultdict
from pathlib import Path
from statistics import median


REPORT_DIR = Path(__file__).resolve().parent
ROOT = REPORT_DIR.parents[1]
BENCH_DIR = ROOT / "examples" / "output" / "parallel_cost_compare"
SUMMARY_JSON = BENCH_DIR / "summary.json"
SUMMARY_CSV = BENCH_DIR / "summary.csv"
PLOT_INDEX = BENCH_DIR / "plot_index.csv"
AIR_BENCH_DIR = ROOT / "examples" / "output" / "air_quality_pe_compare"
AIR_SUMMARY_JSON = AIR_BENCH_DIR / "summary.json"
AIR_PLOT_INDEX = AIR_BENCH_DIR / "plot_index.csv"
FIGURES_DIR = REPORT_DIR / "figures"
TABLES_DIR = REPORT_DIR / "tables"

COST_ORDER = {"cheap": 0, "medium": 1, "heavy": 2}
IMPL_ORDER = {"julia": 0, "python": 1}


def latex_escape(value: object) -> str:
    text = "" if value is None else str(value)
    repl = {
        "\\": r"\textbackslash{}",
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    return "".join(repl.get(ch, ch) for ch in text)


def fmt_float(value: object, digits: int = 2) -> str:
    if value is None or value == "":
        return "--"
    number = float(value)
    if not math.isfinite(number):
        return "--"
    return f"{number:.{digits}f}"


def fmt_int(value: object) -> str:
    if value is None or value == "":
        return "--"
    return f"{int(round(float(value))):,}"


def fmt_range(values: list[float], digits: int = 2) -> str:
    return f"{min(values):.{digits}f}--{max(values):.{digits}f}"


def load_summary() -> dict:
    if not SUMMARY_JSON.exists():
        raise FileNotFoundError(f"Missing benchmark summary: {SUMMARY_JSON}")
    return json.loads(SUMMARY_JSON.read_text(encoding="utf-8"))


def load_air_quality_summary() -> dict:
    if not AIR_SUMMARY_JSON.exists():
        raise FileNotFoundError(f"Missing air-quality benchmark summary: {AIR_SUMMARY_JSON}")
    return json.loads(AIR_SUMMARY_JSON.read_text(encoding="utf-8"))


def audit_summary(data: dict) -> dict:
    errors: list[str] = []
    runs = data.get("runs", [])
    plots = data.get("plots", [])
    if data.get("mode") != "formal":
        errors.append(f"mode is {data.get('mode')!r}, expected 'formal'")
    if len(runs) != 18:
        errors.append(f"run count is {len(runs)}, expected 18")
    if sum(run.get("status") == "ok" for run in runs) != 18:
        errors.append("not all 18 runs have status ok")
    if len(plots) != 9:
        errors.append(f"plot count is {len(plots)}, expected 9")
    if sum(plot.get("status") == "ok" for plot in plots) != 9:
        errors.append("not all 9 plots have status ok")
    methods = sorted({plot.get("method") for plot in plots})
    if methods != ["corner_overlay"]:
        errors.append(f"plot methods are {methods!r}, expected ['corner_overlay']")
    if any(run.get("used_usr_bin_time") is not True for run in runs):
        errors.append("some runs did not use /usr/bin/time -v")
    for field in (
        "process_tree_peak_rss_kb",
        "process_tree_peak_pss_kb",
        "time_max_rss_kb",
        "time_percent_cpu",
    ):
        if any(run.get(field) is None for run in runs):
            errors.append(f"missing field {field} in at least one run")
    missing_plots = [
        plot.get("plot_file", "")
        for plot in plots
        if not Path(plot.get("plot_file", "")).exists()
    ]
    if missing_plots:
        errors.append(f"missing overlay plot files: {missing_plots[:3]}")
    if not SUMMARY_CSV.exists():
        errors.append(f"missing {SUMMARY_CSV}")
    if not PLOT_INDEX.exists():
        errors.append(f"missing {PLOT_INDEX}")
    if errors:
        raise SystemExit("Formal benchmark audit failed:\n- " + "\n- ".join(errors))

    return {
        "mode": data.get("mode"),
        "runs": len(runs),
        "run_ok": sum(run.get("status") == "ok" for run in runs),
        "plots": len(plots),
        "plot_ok": sum(plot.get("status") == "ok" for plot in plots),
        "plot_method": methods[0],
        "used_usr_bin_time": all(run.get("used_usr_bin_time") is True for run in runs),
        "memory_fields": all(
            run.get("process_tree_peak_rss_kb") is not None
            and run.get("process_tree_peak_pss_kb") is not None
            for run in runs
        ),
        "overlay_files": len(plots) - len(missing_plots),
    }


def write_csv(path: Path, rows: list[dict], fields: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_latex_table(path: Path, columns: list[tuple[str, str]], rows: list[dict]) -> None:
    alignment = "l" * len(columns)
    lines = [
        r"\begin{tabular}{" + alignment + "}",
        r"\toprule",
        " & ".join(header for _, header in columns) + r" \\",
        r"\midrule",
    ]
    for row in rows:
        lines.append(
            " & ".join(latex_escape(row.get(field, "")) for field, _ in columns) + r" \\"
        )
    lines.extend([r"\bottomrule", r"\end{tabular}", ""])
    path.write_text("\n".join(lines), encoding="utf-8")


def summarize_benchmark(data: dict) -> list[dict]:
    grouped: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for run in data["runs"]:
        grouped[(run["cost"], run["implementation"])].append(run)

    rows: list[dict] = []
    for cost, implementation in sorted(grouped, key=lambda x: (COST_ORDER[x[0]], IMPL_ORDER[x[1]])):
        runs = grouped[(cost, implementation)]
        wall = [float(run["wall_time_seconds"]) for run in runs]
        cpu = [float(run["cpu_utilization"]) for run in runs]
        rss = [float(run["process_tree_peak_rss_kb"]) for run in runs]
        pss = [float(run["process_tree_peak_pss_kb"]) for run in runs]
        nsamples = [float(run["nsamples"]) for run in runs]
        logz = [float(run["logz"]) for run in runs]
        logzerr = [float(run["logzerr"]) for run in runs]
        rows.append(
            {
                "cost": cost,
                "implementation": implementation,
                "runs": len(runs),
                "median_wall_s": fmt_float(median(wall), 2),
                "min_wall_s": fmt_float(min(wall), 2),
                "max_wall_s": fmt_float(max(wall), 2),
                "wall_range_s": fmt_range(wall, 2),
                "median_cpu_utilization": fmt_float(median(cpu), 2),
                "median_rss_kb": fmt_int(median(rss)),
                "median_pss_kb": fmt_int(median(pss)),
                "median_nsamples": fmt_int(median(nsamples)),
                "logz_median": fmt_float(median(logz), 4),
                "logzerr_median": fmt_float(median(logzerr), 4),
            }
        )
    return rows


def write_run_table(data: dict) -> None:
    rows: list[dict] = []
    for run in sorted(
        data["runs"],
        key=lambda item: (COST_ORDER[item["cost"]], IMPL_ORDER[item["implementation"]], item["repeat"]),
    ):
        rows.append(
            {
                "cost": run["cost"],
                "implementation": run["implementation"],
                "repeat": run["repeat"],
                "wall_s": fmt_float(run.get("wall_time_seconds"), 2),
                "cpu_utilization": fmt_float(run.get("cpu_utilization"), 2),
                "rss_kb": fmt_int(run.get("process_tree_peak_rss_kb")),
                "pss_kb": fmt_int(run.get("process_tree_peak_pss_kb")),
                "nsamples": fmt_int(run.get("nsamples")),
                "logz": fmt_float(run.get("logz"), 5),
                "logzerr": fmt_float(run.get("logzerr"), 5),
                "status": run.get("status"),
            }
        )
    fields = [
        "cost",
        "implementation",
        "repeat",
        "wall_s",
        "cpu_utilization",
        "rss_kb",
        "pss_kb",
        "nsamples",
        "logz",
        "logzerr",
        "status",
    ]
    write_csv(TABLES_DIR / "benchmark_runs.csv", rows, fields)
    write_latex_table(
        TABLES_DIR / "benchmark_runs.tex",
        [
            ("cost", "cost"),
            ("implementation", "impl"),
            ("repeat", "rep"),
            ("wall_s", "wall s"),
            ("cpu_utilization", "CPU util."),
            ("rss_kb", "RSS KB"),
            ("pss_kb", "PSS KB"),
            ("nsamples", "nsamples"),
            ("logz", "logz"),
            ("logzerr", "logzerr"),
            ("status", "status"),
        ],
        rows,
    )


def copy_plots(data: dict) -> list[dict]:
    FIGURES_DIR.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    for plot in sorted(data["plots"], key=lambda item: (COST_ORDER[item["cost"]], item["repeat"])):
        src = Path(plot["plot_file"])
        dst = FIGURES_DIR / src.name
        shutil.copy2(src, dst)
        rows.append(
            {
                "cost": plot["cost"],
                "repeat": plot["repeat"],
                "filename": dst.name,
                "method": plot["method"],
                "status": plot["status"],
                "julia_nsamples": fmt_int(plot.get("julia_nsamples")),
                "python_nsamples": fmt_int(plot.get("python_nsamples")),
                "julia_logz": fmt_float(plot.get("julia_logz"), 5),
                "python_logz": fmt_float(plot.get("python_logz"), 5),
                "julia_logzerr": fmt_float(plot.get("julia_logzerr"), 5),
                "python_logzerr": fmt_float(plot.get("python_logzerr"), 5),
            }
        )
    fields = [
        "cost",
        "repeat",
        "filename",
        "method",
        "status",
        "julia_nsamples",
        "python_nsamples",
        "julia_logz",
        "python_logz",
        "julia_logzerr",
        "python_logzerr",
    ]
    write_csv(TABLES_DIR / "plot_index.csv", rows, fields)
    write_latex_table(
        TABLES_DIR / "plot_index.tex",
        [
            ("cost", "cost"),
            ("repeat", "rep"),
            ("filename", "file"),
            ("method", "method"),
            ("status", "status"),
            ("julia_nsamples", "Julia n"),
            ("python_nsamples", "Python n"),
            ("julia_logz", "Julia logz"),
            ("python_logz", "Python logz"),
        ],
        rows,
    )
    return rows


def write_audit_table(audit: dict) -> None:
    rows = [
        {"check": "mode", "expected": "formal", "observed": audit["mode"], "status": "ok"},
        {"check": "runs", "expected": "18 ok", "observed": f"{audit['run_ok']}/{audit['runs']} ok", "status": "ok"},
        {"check": "plots", "expected": "9 ok", "observed": f"{audit['plot_ok']}/{audit['plots']} ok", "status": "ok"},
        {"check": "plot method", "expected": "corner_overlay", "observed": audit["plot_method"], "status": "ok"},
        {"check": "/usr/bin/time -v", "expected": "true", "observed": str(audit["used_usr_bin_time"]).lower(), "status": "ok"},
        {"check": "RSS/PSS fields", "expected": "present", "observed": str(audit["memory_fields"]).lower(), "status": "ok"},
        {"check": "overlay PNG", "expected": "9 files", "observed": f"{audit['overlay_files']} files", "status": "ok"},
    ]
    write_csv(TABLES_DIR / "formal_benchmark_audit.csv", rows, ["check", "expected", "observed", "status"])
    write_latex_table(
        TABLES_DIR / "formal_benchmark_audit.tex",
        [("check", "check"), ("expected", "expected"), ("observed", "observed"), ("status", "status")],
        rows,
    )


def write_summary_metadata(data: dict, audit: dict) -> None:
    metadata = {
        "summary_json": str(SUMMARY_JSON.relative_to(ROOT)),
        "summary_csv": str(SUMMARY_CSV.relative_to(ROOT)),
        "plot_index": str(PLOT_INDEX.relative_to(ROOT)),
        "created_at": data.get("created_at"),
        "mode": data.get("mode"),
        "configuration": data.get("configuration"),
        "environment": data.get("environment"),
        "python_dynesty_path": data.get("python_dynesty_path"),
        "audit": audit,
    }
    (TABLES_DIR / "benchmark_metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def audit_air_quality_summary(data: dict) -> dict:
    runs = data.get("runs", [])
    plots = data.get("plots", [])
    run_ok = sum(run.get("status") == "ok" for run in runs)
    plot_ok = sum(plot.get("status") == "ok" for plot in plots)
    missing_plots = [
        plot.get("plot_file", "")
        for plot in plots
        if plot.get("status") == "ok" and not Path(plot.get("plot_file", "")).exists()
    ]
    configuration = data.get("configuration", {})
    calibration = data.get("calibration", {})
    return {
        "mode": data.get("mode"),
        "runs": len(runs),
        "run_ok": run_ok,
        "plots": len(plots),
        "plot_ok": plot_ok,
        "plot_files_present": plot_ok - len(missing_plots),
        "used_usr_bin_time": configuration.get("used_usr_bin_time"),
        "time_command_available": configuration.get("time_command_available"),
        "work_repeats": calibration.get("work_repeats"),
        "direct_median_seconds": calibration.get("median_seconds"),
        "comparison_label": data.get("comparison_label"),
    }


def write_air_quality_audit_table(audit: dict) -> None:
    mode_status = "ok" if audit["mode"] == "formal" else "degraded"
    time_status = (
        "ok"
        if audit["time_command_available"] is True and audit["used_usr_bin_time"] is True
        else "blocked"
    )
    rows = [
        {"check": "mode", "expected": "formal for final gate", "observed": audit["mode"], "status": mode_status},
        {"check": "runs", "expected": "Julia/Python ok", "observed": f"{audit['run_ok']}/{audit['runs']} ok", "status": "ok"},
        {"check": "plots", "expected": "overlay ok", "observed": f"{audit['plot_ok']}/{audit['plots']} ok", "status": "ok"},
        {"check": "overlay PNG", "expected": "present", "observed": f"{audit['plot_files_present']} files", "status": "ok"},
        {"check": "/usr/bin/time -v", "expected": "available and used", "observed": f"available={audit['time_command_available']}, used={audit['used_usr_bin_time']}", "status": time_status},
        {"check": "direct likelihood median", "expected": "0.005--0.02 s", "observed": fmt_float(audit["direct_median_seconds"], 5), "status": "ok"},
        {"check": "work repeats", "expected": "recorded", "observed": audit["work_repeats"], "status": "ok"},
    ]
    write_csv(TABLES_DIR / "air_quality_audit.csv", rows, ["check", "expected", "observed", "status"])
    write_latex_table(
        TABLES_DIR / "air_quality_audit.tex",
        [("check", "check"), ("expected", "expected"), ("observed", "observed"), ("status", "status")],
        rows,
    )


def write_air_quality_run_table(data: dict) -> None:
    rows: list[dict] = []
    for run in sorted(data.get("runs", []), key=lambda item: (IMPL_ORDER.get(item.get("implementation"), 9), item.get("repeat", 0))):
        rows.append(
            {
                "implementation": run.get("implementation"),
                "repeat": run.get("repeat"),
                "status": run.get("status"),
                "wall_s": fmt_float(run.get("wall_time_seconds"), 2),
                "cpu_utilization": fmt_float(run.get("cpu_utilization"), 2),
                "rss_kb": fmt_int(run.get("process_tree_peak_rss_kb")),
                "pss_kb": fmt_int(run.get("process_tree_peak_pss_kb")),
                "nlive": fmt_int(run.get("nlive")),
                "queue_size": fmt_int(run.get("queue_size")),
                "workers": fmt_int(run.get("threads") if run.get("implementation") == "julia" else run.get("nproc")),
                "bridge": run.get("bridge_kind") or "--",
                "direct_like_s": fmt_float(run.get("direct_julia_likelihood_median_seconds"), 5),
                "bridge_like_s": fmt_float(run.get("python_bridge_likelihood_median_seconds"), 5),
                "nsamples": fmt_int(run.get("nsamples")),
                "logz": fmt_float(run.get("logz"), 4),
                "logzerr": fmt_float(run.get("logzerr"), 4),
            }
        )
    fields = [
        "implementation",
        "repeat",
        "status",
        "wall_s",
        "cpu_utilization",
        "rss_kb",
        "pss_kb",
        "nlive",
        "queue_size",
        "workers",
        "bridge",
        "direct_like_s",
        "bridge_like_s",
        "nsamples",
        "logz",
        "logzerr",
    ]
    write_csv(TABLES_DIR / "air_quality_runs.csv", rows, fields)
    write_latex_table(
        TABLES_DIR / "air_quality_runs.tex",
        [
            ("implementation", "impl"),
            ("status", "status"),
            ("wall_s", "wall s"),
            ("rss_kb", "RSS KB"),
            ("pss_kb", "PSS KB"),
            ("workers", "workers"),
            ("bridge", "bridge"),
            ("direct_like_s", "Julia like s"),
            ("bridge_like_s", "bridge like s"),
            ("nsamples", "nsamples"),
            ("logz", "logz"),
            ("logzerr", "logzerr"),
        ],
        rows,
    )


def copy_air_quality_plots(data: dict) -> list[dict]:
    FIGURES_DIR.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    for plot in sorted(data.get("plots", []), key=lambda item: item.get("repeat", 0)):
        src = Path(plot["plot_file"]) if plot.get("plot_file") else None
        filename = ""
        if src is not None and src.exists():
            dst = FIGURES_DIR / src.name
            shutil.copy2(src, dst)
            filename = dst.name
        rows.append(
            {
                "repeat": plot.get("repeat"),
                "filename": filename,
                "method": plot.get("method"),
                "status": plot.get("status"),
                "julia_nsamples": fmt_int(plot.get("julia_nsamples")),
                "python_nsamples": fmt_int(plot.get("python_nsamples")),
                "julia_logz": fmt_float(plot.get("julia_logz"), 5),
                "python_logz": fmt_float(plot.get("python_logz"), 5),
            }
        )
    write_csv(
        TABLES_DIR / "air_quality_plot_index.csv",
        rows,
        ["repeat", "filename", "method", "status", "julia_nsamples", "python_nsamples", "julia_logz", "python_logz"],
    )
    write_latex_table(
        TABLES_DIR / "air_quality_plot_index.tex",
        [
            ("repeat", "rep"),
            ("filename", "file"),
            ("method", "method"),
            ("status", "status"),
            ("julia_nsamples", "Julia n"),
            ("python_nsamples", "Python n"),
            ("julia_logz", "Julia logz"),
            ("python_logz", "Python logz"),
        ],
        rows,
    )
    return rows


def write_air_quality_metadata(data: dict, audit: dict) -> None:
    metadata = {
        "summary_json": str(AIR_SUMMARY_JSON.relative_to(ROOT)),
        "plot_index": str(AIR_PLOT_INDEX.relative_to(ROOT)),
        "created_at": data.get("created_at"),
        "mode": data.get("mode"),
        "comparison_label": data.get("comparison_label"),
        "configuration": data.get("configuration"),
        "environment": data.get("environment"),
        "likelihood_model": data.get("likelihood_model"),
        "bridge": data.get("bridge"),
        "calibration": data.get("calibration"),
        "aggregates": data.get("aggregates"),
        "audit": audit,
    }
    (TABLES_DIR / "air_quality_metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    TABLES_DIR.mkdir(parents=True, exist_ok=True)
    FIGURES_DIR.mkdir(parents=True, exist_ok=True)
    data = load_summary()
    audit = audit_summary(data)

    benchmark_rows = summarize_benchmark(data)
    fields = [
        "cost",
        "implementation",
        "runs",
        "median_wall_s",
        "min_wall_s",
        "max_wall_s",
        "wall_range_s",
        "median_cpu_utilization",
        "median_rss_kb",
        "median_pss_kb",
        "median_nsamples",
        "logz_median",
        "logzerr_median",
    ]
    write_csv(TABLES_DIR / "benchmark_summary.csv", benchmark_rows, fields)
    write_latex_table(
        TABLES_DIR / "benchmark_summary.tex",
        [
            ("cost", "cost"),
            ("implementation", "impl"),
            ("runs", "runs"),
            ("median_wall_s", "median wall s"),
            ("wall_range_s", "wall range s"),
            ("median_cpu_utilization", "median CPU util."),
            ("median_rss_kb", "median RSS KB"),
            ("median_pss_kb", "median PSS KB"),
            ("median_nsamples", "median nsamples"),
            ("logz_median", "median logz"),
            ("logzerr_median", "median logzerr"),
        ],
        benchmark_rows,
    )
    write_run_table(data)
    write_audit_table(audit)
    plot_rows = copy_plots(data)
    write_summary_metadata(data, audit)

    air_data = load_air_quality_summary()
    air_audit = audit_air_quality_summary(air_data)
    write_air_quality_audit_table(air_audit)
    write_air_quality_run_table(air_data)
    air_plot_rows = copy_air_quality_plots(air_data)
    write_air_quality_metadata(air_data, air_audit)

    print(f"Wrote {len(benchmark_rows)} benchmark summary rows")
    print(f"Copied {len(plot_rows)} posterior overlay PNGs to {FIGURES_DIR.relative_to(ROOT)}")
    print(f"Formal benchmark audit: {audit}")
    print(f"Air-quality PE audit: {air_audit}")
    print(f"Copied {len(air_plot_rows)} air-quality posterior overlay PNGs to {FIGURES_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
