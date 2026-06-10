#!/usr/bin/env python3
"""Generate one posterior corner/pair plot for a parallel cost benchmark run."""

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


def plot_run(args: argparse.Namespace) -> dict:
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


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", required=True)
    parser.add_argument("--metadata", default=None)
    parser.add_argument("--output-png", required=True)
    parser.add_argument("--summary-json", required=True)
    parser.add_argument("--implementation", required=True)
    parser.add_argument("--cost", required=True)
    parser.add_argument("--repeat", type=int, required=True)
    parser.add_argument("--title", default=None)
    parser.add_argument("--nsamples-plot", type=int, default=15000)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    summary_path = Path(args.summary_json).resolve()
    try:
        summary = plot_run(args)
    except Exception as exc:
        summary = {
            "status": "failed",
            "message": str(exc),
            "method": None,
            "plot_file": None,
            "samples_file": str(Path(args.samples).resolve()),
            "metadata_file": str(Path(args.metadata).resolve())
            if args.metadata
            else None,
            "implementation": args.implementation,
            "cost": args.cost,
            "repeat": int(args.repeat),
        }
    write_json(summary_path, summary)
    if summary["status"] == "ok":
        print(f"Wrote {summary['method']} plot: {summary['plot_file']}")
    else:
        print(summary["message"])


if __name__ == "__main__":
    main()
