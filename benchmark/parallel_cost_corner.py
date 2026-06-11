#!/usr/bin/env python3
"""Generate posterior corner/pair plots for parallel cost benchmark runs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


DEFAULT_TRUE_THETA = np.array([0.65, -0.35, 0.45, -0.10], dtype=float)
DEFAULT_PARAM_NAMES = [r"$\theta_1$", r"$\theta_2$", r"$\theta_3$", r"$\theta_4$"]


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def read_metadata(path: Path | None) -> dict:
    if path is None or not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def read_weighted_samples(path: Path) -> tuple[np.ndarray, np.ndarray, list[str]]:
    data = np.genfromtxt(path, delimiter=",", names=True)
    if data.dtype.names is None or "weight" not in data.dtype.names:
        raise ValueError(f"{path} does not look like a weighted sample CSV")
    names = [name for name in data.dtype.names if name != "weight"]
    samples = np.column_stack([np.asarray(data[name], dtype=float) for name in names])
    weights = np.asarray(data["weight"], dtype=float)
    total = np.sum(weights)
    if not np.isfinite(total) or total <= 0:
        raise ValueError(f"{path} has invalid posterior weights")
    return samples, weights / total, names


def weighted_mean_cov(samples: np.ndarray, weights: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    mean = np.sum(samples * weights[:, None], axis=0)
    centered = samples - mean
    cov = centered.T @ (centered * weights[:, None])
    return mean, cov


def equal_weight_resample(
    samples: np.ndarray,
    weights: np.ndarray,
    nsamples: int,
    seed: int,
) -> np.ndarray:
    rng = np.random.default_rng(seed)
    idx = rng.choice(len(samples), size=nsamples, replace=True, p=weights)
    return samples[idx]


def finite_ranges(samples: np.ndarray, truths: np.ndarray) -> list[tuple[float, float]]:
    ranges: list[tuple[float, float]] = []
    for col, truth in zip(samples.T, truths):
        lo, hi = np.quantile(col[np.isfinite(col)], [0.002, 0.998])
        if np.isfinite(truth):
            lo = min(lo, truth)
            hi = max(hi, truth)
        pad = max(1.0e-6, 0.08 * (hi - lo))
        ranges.append((float(lo - pad), float(hi + pad)))
    return ranges


def posterior_cov_ranges(
    metadatas: list[dict],
    ndim: int,
    truths: np.ndarray,
) -> list[tuple[float, float]] | None:
    if len(truths) != ndim or not np.all(np.isfinite(truths)):
        return None
    for metadata in metadatas:
        cov = metadata.get("posterior_cov")
        if cov is None:
            continue
        arr = np.asarray(cov, dtype=float)
        if arr.shape != (ndim, ndim):
            continue
        diag = np.diag(arr)
        if np.any(~np.isfinite(diag)) or np.any(diag <= 0):
            continue
        std = np.sqrt(diag)
        return [
            (float(truths[i] - 4.0 * std[i]), float(truths[i] + 4.0 * std[i]))
            for i in range(ndim)
        ]
    return None


def merged_ranges(
    samples_by_impl: list[np.ndarray],
    metadatas: list[dict],
    truths: np.ndarray,
) -> list[tuple[float, float]]:
    ndim = samples_by_impl[0].shape[1]
    cov_ranges = posterior_cov_ranges(metadatas, ndim, truths)
    if cov_ranges is not None:
        return cov_ranges
    return finite_ranges(np.vstack(samples_by_impl), truths)


def labels_from_metadata(
    sample_names: list[str],
    metadatas: list[dict],
    ndim: int,
) -> list[str]:
    for metadata in metadatas:
        names = metadata.get("param_names")
        if names is not None and len(names) == ndim:
            return [str(name) for name in names]
    if len(sample_names) == ndim:
        return [str(name) for name in sample_names]
    return DEFAULT_PARAM_NAMES[:ndim]


def truths_from_metadata(metadatas: list[dict], ndim: int) -> np.ndarray:
    for metadata in metadatas:
        values = metadata.get("true_theta")
        if values is None:
            continue
        truths = np.asarray(values, dtype=float)
        if len(truths) == ndim:
            return truths
    if len(DEFAULT_TRUE_THETA) == ndim:
        return DEFAULT_TRUE_THETA
    return np.full(ndim, np.nan, dtype=float)


def plot_with_corner(
    samples: np.ndarray,
    weights: np.ndarray,
    labels: list[str],
    truths: np.ndarray,
    output_png: Path,
    title: str,
) -> str:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import corner

    fig = corner.corner(
        samples,
        weights=weights,
        labels=labels,
        truths=truths,
        range=finite_ranges(samples, truths),
        bins=36,
        smooth=0.7,
        color="#0072B2",
        plot_datapoints=False,
        fill_contours=True,
        show_titles=False,
        hist_kwargs={"density": True, "histtype": "stepfilled", "alpha": 0.55},
        contour_kwargs={"linewidths": 1.2},
    )
    fig.suptitle(title, y=0.995)
    output_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return "corner"


def plot_overlay_with_corner(
    julia_plot_samples: np.ndarray,
    python_plot_samples: np.ndarray,
    labels: list[str],
    truths: np.ndarray,
    ranges: list[tuple[float, float]],
    output_png: Path,
    title: str,
) -> str:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.lines as mlines
    import matplotlib.pyplot as plt
    import corner

    truth_values = truths if len(truths) == julia_plot_samples.shape[1] else None
    fig = corner.corner(
        julia_plot_samples,
        labels=labels,
        truths=truth_values,
        range=ranges,
        bins=36,
        smooth=0.7,
        color="#0072B2",
        plot_datapoints=False,
        fill_contours=False,
        show_titles=False,
        hist_kwargs={"density": True, "histtype": "step", "linewidth": 1.7},
        contour_kwargs={"linewidths": 1.5},
    )
    corner.corner(
        python_plot_samples,
        fig=fig,
        labels=labels,
        truths=truth_values,
        range=ranges,
        bins=36,
        smooth=0.7,
        color="#D55E00",
        plot_datapoints=False,
        fill_contours=False,
        show_titles=False,
        hist_kwargs={"density": True, "histtype": "step", "linewidth": 1.7},
        contour_kwargs={"linewidths": 1.5},
    )
    handles = [
        mlines.Line2D([], [], color="#0072B2", label="Dynesty.jl threaded"),
        mlines.Line2D([], [], color="#D55E00", label="Python dynesty pool"),
    ]
    if truth_values is not None and np.all(np.isfinite(truth_values)):
        handles.append(
            mlines.Line2D(
                [],
                [],
                color="black",
                marker="s",
                linestyle="None",
                markersize=6,
                label="true value",
            )
        )
    fig.legend(handles=handles, loc="upper right", bbox_to_anchor=(0.98, 0.98))
    fig.suptitle(title, y=0.995)
    output_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return "corner_overlay"


def plot_with_matplotlib_pair(
    samples: np.ndarray,
    weights: np.ndarray,
    labels: list[str],
    truths: np.ndarray,
    output_png: Path,
    title: str,
    nsamples_plot: int,
) -> str:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    plot_samples = equal_weight_resample(
        samples,
        weights,
        min(nsamples_plot, max(len(samples), 1)),
        seed=20240613,
    )
    ndim = samples.shape[1]
    fig, axes = plt.subplots(ndim, ndim, figsize=(2.2 * ndim, 2.2 * ndim))
    ranges = finite_ranges(plot_samples, truths)
    for row in range(ndim):
        for col in range(ndim):
            ax = axes[row, col]
            if row == col:
                ax.hist(
                    plot_samples[:, col],
                    bins=36,
                    range=ranges[col],
                    color="#0072B2",
                    alpha=0.72,
                    density=True,
                )
                ax.axvline(truths[col], color="black", linewidth=1.1)
            elif row > col:
                ax.hist2d(
                    plot_samples[:, col],
                    plot_samples[:, row],
                    bins=36,
                    range=[ranges[col], ranges[row]],
                    cmap="Blues",
                )
                ax.axvline(truths[col], color="black", linewidth=0.8)
                ax.axhline(truths[row], color="black", linewidth=0.8)
            else:
                ax.axis("off")
                continue
            if row == ndim - 1:
                ax.set_xlabel(labels[col])
            else:
                ax.set_xticklabels([])
            if col == 0 and row > 0:
                ax.set_ylabel(labels[row])
            elif col != 0:
                ax.set_yticklabels([])
    fig.suptitle(title, y=0.995)
    fig.tight_layout()
    output_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return "matplotlib_pair"


def plot_overlay_with_matplotlib_pair(
    julia_plot_samples: np.ndarray,
    python_plot_samples: np.ndarray,
    labels: list[str],
    truths: np.ndarray,
    ranges: list[tuple[float, float]],
    output_png: Path,
    title: str,
) -> str:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.lines as mlines
    import matplotlib.pyplot as plt

    ndim = julia_plot_samples.shape[1]
    fig, axes = plt.subplots(ndim, ndim, figsize=(2.2 * ndim, 2.2 * ndim))
    for row in range(ndim):
        for col in range(ndim):
            ax = axes[row, col]
            if row == col:
                ax.hist(
                    julia_plot_samples[:, col],
                    bins=36,
                    range=ranges[col],
                    color="#0072B2",
                    histtype="step",
                    linewidth=1.7,
                    density=True,
                )
                ax.hist(
                    python_plot_samples[:, col],
                    bins=36,
                    range=ranges[col],
                    color="#D55E00",
                    histtype="step",
                    linewidth=1.7,
                    density=True,
                )
                if len(truths) == ndim and np.isfinite(truths[col]):
                    ax.axvline(truths[col], color="black", linewidth=1.1)
            elif row > col:
                ax.scatter(
                    julia_plot_samples[:, col],
                    julia_plot_samples[:, row],
                    s=1.0,
                    color="#0072B2",
                    alpha=0.04,
                    rasterized=True,
                )
                ax.scatter(
                    python_plot_samples[:, col],
                    python_plot_samples[:, row],
                    s=1.0,
                    color="#D55E00",
                    alpha=0.04,
                    rasterized=True,
                )
                ax.set_xlim(ranges[col])
                ax.set_ylim(ranges[row])
                if len(truths) == ndim and np.isfinite(truths[col]):
                    ax.axvline(truths[col], color="black", linewidth=0.8)
                if len(truths) == ndim and np.isfinite(truths[row]):
                    ax.axhline(truths[row], color="black", linewidth=0.8)
            else:
                ax.axis("off")
                continue
            if row == ndim - 1:
                ax.set_xlabel(labels[col])
            else:
                ax.set_xticklabels([])
            if col == 0 and row > 0:
                ax.set_ylabel(labels[row])
            elif col != 0:
                ax.set_yticklabels([])
    handles = [
        mlines.Line2D([], [], color="#0072B2", label="Dynesty.jl threaded"),
        mlines.Line2D([], [], color="#D55E00", label="Python dynesty pool"),
        mlines.Line2D(
            [],
            [],
            color="black",
            marker="s",
            linestyle="None",
            markersize=6,
            label="true value",
        ),
    ]
    fig.legend(handles=handles, loc="upper right", bbox_to_anchor=(0.98, 0.98))
    fig.suptitle(title, y=0.995)
    fig.tight_layout()
    output_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return "matplotlib_pair_overlay"


def plot_run(args: argparse.Namespace) -> dict:
    if args.samples is None:
        raise ValueError("--samples is required for single-run plotting")
    if args.implementation is None:
        raise ValueError("--implementation is required for single-run plotting")
    samples_path = Path(args.samples).resolve()
    metadata_path = Path(args.metadata).resolve() if args.metadata else None
    output_png = Path(args.output_png).resolve()
    metadata = read_metadata(metadata_path)
    samples, weights, names = read_weighted_samples(samples_path)
    truths = np.asarray(metadata.get("true_theta", DEFAULT_TRUE_THETA), dtype=float)
    param_names = metadata.get("param_names") or names or DEFAULT_PARAM_NAMES
    labels = [str(name) for name in param_names]
    title = args.title or (
        f"{metadata.get('likelihood_cost', args.cost)} "
        f"{metadata.get('implementation', args.implementation)} repeat {args.repeat}"
    )
    nsamples_plot = min(int(args.nsamples_plot), len(samples))

    try:
        method = plot_with_corner(
            samples,
            weights,
            labels,
            truths,
            output_png,
            title,
        )
        status = "ok"
        message = ""
    except Exception as corner_exc:
        try:
            method = plot_with_matplotlib_pair(
                samples,
                weights,
                labels,
                truths,
                output_png,
                title,
                nsamples_plot,
            )
            status = "ok"
            message = f"corner unavailable or failed; used Matplotlib fallback: {corner_exc}"
        except Exception as mpl_exc:
            method = None
            status = "failed"
            message = (
                "plotting failed; performance summary remains valid. "
                f"corner error: {corner_exc}; matplotlib fallback error: {mpl_exc}"
            )

    return {
        "status": status,
        "message": message,
        "method": method,
        "plot_file": str(output_png) if status == "ok" else None,
        "samples_file": str(samples_path),
        "metadata_file": str(metadata_path) if metadata_path else None,
        "implementation": args.implementation,
        "cost": args.cost,
        "repeat": int(args.repeat),
        "nsamples": int(len(samples)),
        "nsamples_plot": int(nsamples_plot),
    }


def plot_overlay_run(args: argparse.Namespace) -> dict:
    if args.julia_samples is None or args.python_samples is None:
        raise ValueError("--julia-samples and --python-samples are required for overlay plotting")
    julia_samples_path = Path(args.julia_samples).resolve()
    python_samples_path = Path(args.python_samples).resolve()
    julia_metadata_path = Path(args.julia_metadata).resolve() if args.julia_metadata else None
    python_metadata_path = (
        Path(args.python_metadata).resolve() if args.python_metadata else None
    )
    output_png = Path(args.output_png).resolve()

    julia_metadata = read_metadata(julia_metadata_path)
    python_metadata = read_metadata(python_metadata_path)
    julia_samples, julia_weights, julia_names = read_weighted_samples(julia_samples_path)
    python_samples, python_weights, python_names = read_weighted_samples(python_samples_path)
    if julia_samples.shape[1] != python_samples.shape[1]:
        raise ValueError(
            "Julia and Python samples must have the same number of dimensions; "
            f"got {julia_samples.shape[1]} and {python_samples.shape[1]}"
        )

    ndim = julia_samples.shape[1]
    metadatas = [julia_metadata, python_metadata]
    truths = truths_from_metadata(metadatas, ndim)
    labels = labels_from_metadata(julia_names or python_names, metadatas, ndim)
    nsamples_plot = min(
        int(args.nsamples_plot),
        max(len(julia_samples), len(python_samples)),
    )
    julia_plot_samples = equal_weight_resample(
        julia_samples,
        julia_weights,
        nsamples_plot,
        seed=20240613 + int(args.repeat) * 2,
    )
    python_plot_samples = equal_weight_resample(
        python_samples,
        python_weights,
        nsamples_plot,
        seed=20240614 + int(args.repeat) * 2,
    )
    ranges = merged_ranges(
        [julia_plot_samples, python_plot_samples],
        metadatas,
        truths,
    )
    title = args.title or f"{args.cost} repeat {args.repeat}: Julia vs Python posterior"

    try:
        method = plot_overlay_with_corner(
            julia_plot_samples,
            python_plot_samples,
            labels,
            truths,
            ranges,
            output_png,
            title,
        )
        status = "ok"
        message = ""
    except Exception as corner_exc:
        try:
            method = plot_overlay_with_matplotlib_pair(
                julia_plot_samples,
                python_plot_samples,
                labels,
                truths,
                ranges,
                output_png,
                title,
            )
            status = "ok"
            message = f"corner unavailable or failed; used Matplotlib fallback: {corner_exc}"
        except Exception as mpl_exc:
            method = None
            status = "failed"
            message = (
                "overlay plotting failed; performance summary remains valid. "
                f"corner error: {corner_exc}; matplotlib fallback error: {mpl_exc}"
            )

    julia_mean, julia_cov = weighted_mean_cov(julia_samples, julia_weights)
    python_mean, python_cov = weighted_mean_cov(python_samples, python_weights)
    return {
        "status": status,
        "message": message,
        "method": method,
        "plot_file": str(output_png) if status == "ok" else None,
        "comparison": "julia_vs_python",
        "cost": args.cost,
        "repeat": int(args.repeat),
        "nsamples_plot": int(nsamples_plot),
        "julia": {
            "samples_file": str(julia_samples_path),
            "metadata_file": str(julia_metadata_path) if julia_metadata_path else None,
            "nsamples": int(len(julia_samples)),
            "logz": julia_metadata.get("logz"),
            "logzerr": julia_metadata.get("logzerr"),
            "mean": julia_mean.tolist(),
            "cov_diag": np.diag(julia_cov).tolist(),
        },
        "python": {
            "samples_file": str(python_samples_path),
            "metadata_file": str(python_metadata_path) if python_metadata_path else None,
            "nsamples": int(len(python_samples)),
            "logz": python_metadata.get("logz"),
            "logzerr": python_metadata.get("logzerr"),
            "mean": python_mean.tolist(),
            "cov_diag": np.diag(python_cov).tolist(),
            "dynesty_file": python_metadata.get("dynesty_file"),
        },
        "mean_abs_delta": np.abs(julia_mean - python_mean).tolist(),
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", default=None)
    parser.add_argument("--metadata", default=None)
    parser.add_argument("--julia-samples", default=None)
    parser.add_argument("--julia-metadata", default=None)
    parser.add_argument("--python-samples", default=None)
    parser.add_argument("--python-metadata", default=None)
    parser.add_argument("--output-png", required=True)
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--implementation", default=None)
    parser.add_argument("--cost", required=True)
    parser.add_argument("--repeat", type=int, required=True)
    parser.add_argument("--title", default=None)
    parser.add_argument("--nsamples-plot", type=int, default=15000)
    return parser.parse_args(argv)


def is_overlay_args(args: argparse.Namespace) -> bool:
    return args.julia_samples is not None or args.python_samples is not None


def failure_summary(args: argparse.Namespace, exc: Exception) -> dict:
    payload = {
        "status": "failed",
        "message": str(exc),
        "method": None,
        "plot_file": None,
        "cost": args.cost,
        "repeat": int(args.repeat),
    }
    if is_overlay_args(args):
        payload.update(
            {
                "comparison": "julia_vs_python",
                "julia": {
                    "samples_file": str(Path(args.julia_samples).resolve())
                    if args.julia_samples
                    else None,
                    "metadata_file": str(Path(args.julia_metadata).resolve())
                    if args.julia_metadata
                    else None,
                },
                "python": {
                    "samples_file": str(Path(args.python_samples).resolve())
                    if args.python_samples
                    else None,
                    "metadata_file": str(Path(args.python_metadata).resolve())
                    if args.python_metadata
                    else None,
                },
            }
        )
    else:
        payload.update(
            {
                "samples_file": str(Path(args.samples).resolve()) if args.samples else None,
                "metadata_file": str(Path(args.metadata).resolve()) if args.metadata else None,
                "implementation": args.implementation,
            }
        )
    return payload


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    summary_path = Path(args.summary_json).resolve()
    try:
        summary = plot_overlay_run(args) if is_overlay_args(args) else plot_run(args)
    except Exception as exc:
        summary = failure_summary(args, exc)
    write_json(summary_path, summary)
    if summary["status"] == "ok":
        print(f"Wrote {summary['method']} plot: {summary['plot_file']}")
    else:
        print(summary["message"])


if __name__ == "__main__":
    main()
