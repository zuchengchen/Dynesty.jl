#!/usr/bin/env python3
"""Generate Julia/Python posterior overlay plots for the air-quality PE benchmark."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def read_json(path: Path | None) -> dict:
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


def equal_weight_resample(samples: np.ndarray, weights: np.ndarray, nsamples: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    idx = rng.choice(len(samples), size=nsamples, replace=True, p=weights)
    return samples[idx]


def metadata_truth(metadatas: list[dict], ndim: int) -> np.ndarray:
    for metadata in metadatas:
        truth = metadata.get("true_theta")
        if truth is not None and len(truth) == ndim:
            return np.asarray(truth, dtype=float)
    return np.full(ndim, np.nan)


def metadata_labels(names: list[str], metadatas: list[dict], ndim: int) -> list[str]:
    for metadata in metadatas:
        labels = metadata.get("param_names")
        if labels is not None and len(labels) == ndim:
            return [str(item) for item in labels]
    if len(names) == ndim:
        return [str(item) for item in names]
    return [f"theta{i + 1}" for i in range(ndim)]


def finite_ranges(samples_by_impl: list[np.ndarray], truths: np.ndarray) -> list[tuple[float, float]]:
    merged = np.vstack(samples_by_impl)
    ranges: list[tuple[float, float]] = []
    for i, col in enumerate(merged.T):
        finite = col[np.isfinite(col)]
        if len(finite) == 0:
            ranges.append((0.0, 1.0))
            continue
        lo, hi = np.quantile(finite, [0.003, 0.997])
        if i < len(truths) and np.isfinite(truths[i]):
            lo = min(float(lo), float(truths[i]))
            hi = max(float(hi), float(truths[i]))
        pad = max(1.0e-6, 0.08 * (float(hi) - float(lo)))
        ranges.append((float(lo - pad), float(hi + pad)))
    return ranges


def plot_corner_overlay(
    julia_samples: np.ndarray,
    python_samples: np.ndarray,
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

    truth_values = truths if len(truths) == julia_samples.shape[1] else None
    fig = corner.corner(
        julia_samples,
        labels=labels,
        truths=truth_values,
        range=ranges,
        bins=32,
        smooth=0.7,
        color="#0072B2",
        plot_datapoints=False,
        fill_contours=False,
        show_titles=False,
        hist_kwargs={"density": True, "histtype": "step", "linewidth": 1.6},
        contour_kwargs={"linewidths": 1.4},
    )
    corner.corner(
        python_samples,
        fig=fig,
        labels=labels,
        truths=truth_values,
        range=ranges,
        bins=32,
        smooth=0.7,
        color="#D55E00",
        plot_datapoints=False,
        fill_contours=False,
        show_titles=False,
        hist_kwargs={"density": True, "histtype": "step", "linewidth": 1.6},
        contour_kwargs={"linewidths": 1.4},
    )
    handles = [
        mlines.Line2D([], [], color="#0072B2", label="Dynesty.jl threaded direct Julia likelihood"),
        mlines.Line2D([], [], color="#D55E00", label="Python dynesty pool through Julia bridge"),
        mlines.Line2D([], [], color="black", marker="s", linestyle="None", markersize=5, label="synthetic truth"),
    ]
    fig.legend(handles=handles, loc="upper right", bbox_to_anchor=(0.98, 0.98), fontsize=8)
    fig.suptitle(title, y=0.995)
    output_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return "corner_overlay"


def plot_matplotlib_pair_overlay(
    julia_samples: np.ndarray,
    python_samples: np.ndarray,
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

    ndim = julia_samples.shape[1]
    fig, axes = plt.subplots(ndim, ndim, figsize=(2.0 * ndim, 2.0 * ndim))
    for row in range(ndim):
        for col in range(ndim):
            ax = axes[row, col]
            if row == col:
                ax.hist(julia_samples[:, col], bins=32, range=ranges[col], color="#0072B2", histtype="step", density=True)
                ax.hist(python_samples[:, col], bins=32, range=ranges[col], color="#D55E00", histtype="step", density=True)
                if len(truths) == ndim and np.isfinite(truths[col]):
                    ax.axvline(truths[col], color="black", linewidth=0.9)
            elif row > col:
                ax.scatter(julia_samples[:, col], julia_samples[:, row], s=0.8, color="#0072B2", alpha=0.04, rasterized=True)
                ax.scatter(python_samples[:, col], python_samples[:, row], s=0.8, color="#D55E00", alpha=0.04, rasterized=True)
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
                ax.set_xlabel(labels[col], fontsize=8)
            else:
                ax.set_xticklabels([])
            if col == 0 and row > 0:
                ax.set_ylabel(labels[row], fontsize=8)
            elif col != 0:
                ax.set_yticklabels([])
    handles = [
        mlines.Line2D([], [], color="#0072B2", label="Dynesty.jl threaded direct Julia likelihood"),
        mlines.Line2D([], [], color="#D55E00", label="Python dynesty pool through Julia bridge"),
        mlines.Line2D([], [], color="black", marker="s", linestyle="None", markersize=5, label="synthetic truth"),
    ]
    fig.legend(handles=handles, loc="upper right", bbox_to_anchor=(0.98, 0.98), fontsize=8)
    fig.suptitle(title, y=0.995)
    fig.tight_layout()
    output_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_png, dpi=180, bbox_inches="tight")
    plt.close(fig)
    return "matplotlib_pair_overlay"


def plot_overlay(args: argparse.Namespace) -> dict:
    julia_samples, julia_weights, julia_names = read_weighted_samples(args.julia_samples)
    python_samples, python_weights, python_names = read_weighted_samples(args.python_samples)
    if julia_samples.shape[1] != python_samples.shape[1]:
        raise ValueError("Julia and Python sample dimensions differ")
    ndim = julia_samples.shape[1]
    metadatas = [read_json(args.julia_metadata), read_json(args.python_metadata)]
    truths = metadata_truth(metadatas, ndim)
    labels = metadata_labels(julia_names or python_names, metadatas, ndim)
    nsamples_plot = min(int(args.nsamples_plot), max(len(julia_samples), len(python_samples)))
    julia_plot = equal_weight_resample(julia_samples, julia_weights, nsamples_plot, 20240631 + args.repeat)
    python_plot = equal_weight_resample(python_samples, python_weights, nsamples_plot, 20240701 + args.repeat)
    ranges = finite_ranges([julia_plot, python_plot], truths)
    title = args.title or f"Air-quality PE repeat {args.repeat}: Julia vs Python"

    try:
        method = plot_corner_overlay(julia_plot, python_plot, labels, truths, ranges, args.output_png, title)
        status = "ok"
        message = ""
    except Exception as corner_exc:
        try:
            method = plot_matplotlib_pair_overlay(julia_plot, python_plot, labels, truths, ranges, args.output_png, title)
            status = "ok"
            message = f"corner unavailable or failed; used Matplotlib fallback: {corner_exc}"
        except Exception as mpl_exc:
            method = None
            status = "failed"
            message = (
                "plotting failed; benchmark summary remains valid. "
                f"corner error: {corner_exc}; matplotlib fallback error: {mpl_exc}"
            )
    return {
        "status": status,
        "message": message,
        "method": method,
        "plot_file": str(args.output_png) if status == "ok" else None,
        "comparison": "air_quality_julia_vs_python",
        "repeat": int(args.repeat),
        "julia_samples_file": str(args.julia_samples),
        "python_samples_file": str(args.python_samples),
        "julia_metadata_file": str(args.julia_metadata),
        "python_metadata_file": str(args.python_metadata),
        "julia_nsamples": int(len(julia_samples)),
        "python_nsamples": int(len(python_samples)),
        "nsamples_plot": int(nsamples_plot),
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--julia-samples", type=Path, required=True)
    parser.add_argument("--julia-metadata", type=Path, required=True)
    parser.add_argument("--python-samples", type=Path, required=True)
    parser.add_argument("--python-metadata", type=Path, required=True)
    parser.add_argument("--output-png", type=Path, required=True)
    parser.add_argument("--summary-json", type=Path, required=True)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--title", default=None)
    parser.add_argument("--nsamples-plot", type=int, default=4000)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    try:
        payload = plot_overlay(args)
    except Exception as exc:
        payload = {
            "status": "failed",
            "message": str(exc),
            "method": None,
            "plot_file": None,
            "comparison": "air_quality_julia_vs_python",
            "repeat": int(args.repeat),
        }
    write_json(args.summary_json, payload)
    if payload["status"] != "ok":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
