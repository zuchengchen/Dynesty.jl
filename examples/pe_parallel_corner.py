#!/usr/bin/env python3
"""Overlay Julia Dynesty.jl and Python dynesty PE posterior samples in one corner plot.

Run after both sampler scripts:
    python examples/pe_parallel_corner.py

Or run all quick smoke steps:
    OPENBLAS_NUM_THREADS=1 JULIA_NUM_THREADS=2 julia --project=. \
        examples/pe_parallel_julia.jl --quick --queue-size 2
    OPENBLAS_NUM_THREADS=1 python examples/pe_parallel_python.py \
        --quick --nproc 2 --queue-size 2
    python examples/pe_parallel_corner.py --quick
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

try:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.lines as mlines
    import matplotlib.pyplot as plt
except Exception as exc:  # pragma: no cover - dependency guard for users
    raise SystemExit(
        "This plotting example needs matplotlib. Install it with, for example, "
        "`python -m pip install matplotlib`."
    ) from exc

try:
    import corner
except Exception as exc:  # pragma: no cover - dependency guard for users
    raise SystemExit(
        "This plotting example needs corner. Install it with, for example, "
        "`python -m pip install corner`."
    ) from exc


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = ROOT / "examples" / "output" / "pe_parallel_compare"
PARAM_NAMES = [r"$\theta_1$", r"$\theta_2$", r"$\theta_3$", r"$\theta_4$"]
TRUE_THETA = np.array([0.65, -0.35, 0.45, -0.10], dtype=float)
POSTERIOR_COV = np.array(
    [
        [0.20, 0.08, 0.03, 0.00],
        [0.08, 0.30, -0.04, 0.05],
        [0.03, -0.04, 0.16, 0.06],
        [0.00, 0.05, 0.06, 0.25],
    ],
    dtype=float,
)


def read_weighted_samples(path: Path) -> tuple[np.ndarray, np.ndarray]:
    if not path.exists():
        raise FileNotFoundError(
            f"missing {path}; run the corresponding sampler script first"
        )
    data = np.genfromtxt(path, delimiter=",", names=True)
    names = data.dtype.names
    if names is None or "weight" not in names:
        raise ValueError(f"{path} does not look like a weighted sample CSV")
    sample_names = [name for name in names if name != "weight"]
    samples = np.column_stack([np.asarray(data[name], dtype=float) for name in sample_names])
    weights = np.asarray(data["weight"], dtype=float)
    weights /= np.sum(weights)
    return samples, weights


def read_metadata(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def weighted_mean_cov(samples: np.ndarray, weights: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    mean = np.sum(samples * weights[:, None], axis=0)
    centered = samples - mean
    cov = centered.T @ (centered * weights[:, None])
    return mean, cov


def equal_weight_resample(
    samples: np.ndarray,
    weights: np.ndarray,
    nsamples: int,
    rng: np.random.Generator,
) -> np.ndarray:
    idx = rng.choice(len(samples), size=nsamples, replace=True, p=weights)
    return samples[idx]


def plot_overlay(
    output_png: Path,
    julia_samples: np.ndarray,
    julia_weights: np.ndarray,
    python_samples: np.ndarray,
    python_weights: np.ndarray,
    *,
    nsamples_plot: int,
) -> None:
    rng = np.random.default_rng(20240612)
    jplot = equal_weight_resample(julia_samples, julia_weights, nsamples_plot, rng)
    pplot = equal_weight_resample(python_samples, python_weights, nsamples_plot, rng)

    std = np.sqrt(np.diag(POSTERIOR_COV))
    ranges = [
        (TRUE_THETA[i] - 4.0 * std[i], TRUE_THETA[i] + 4.0 * std[i])
        for i in range(len(TRUE_THETA))
    ]
    fig = corner.corner(
        jplot,
        labels=PARAM_NAMES,
        truths=TRUE_THETA,
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
        pplot,
        fig=fig,
        labels=PARAM_NAMES,
        truths=TRUE_THETA,
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
        mlines.Line2D(
            [],
            [],
            color="black",
            marker="s",
            linestyle="None",
            markersize=6,
            label="injected value",
        ),
    ]
    fig.legend(handles=handles, loc="upper right", bbox_to_anchor=(0.98, 0.98))
    fig.suptitle("Parallel nested-sampling PE posterior overlay", y=0.995)
    output_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_png, dpi=180, bbox_inches="tight")
    plt.close(fig)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--nsamples-plot", type=int, default=15000)
    parser.add_argument("--quick-nsamples-plot", type=int, default=1200)
    parser.add_argument("--output-png", default=None)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    output_dir = Path(args.output_dir).resolve()
    output_png = (
        Path(args.output_png).resolve()
        if args.output_png
        else output_dir / "posterior_corner_overlay.png"
    )
    julia_samples, julia_weights = read_weighted_samples(
        output_dir / "julia_weighted_samples.csv"
    )
    python_samples, python_weights = read_weighted_samples(
        output_dir / "python_weighted_samples.csv"
    )
    nsamples_plot = args.quick_nsamples_plot if args.quick else args.nsamples_plot
    nsamples_plot = min(nsamples_plot, max(len(julia_samples), len(python_samples)))
    plot_overlay(
        output_png,
        julia_samples,
        julia_weights,
        python_samples,
        python_weights,
        nsamples_plot=nsamples_plot,
    )

    jmeta = read_metadata(output_dir / "julia_metadata.json")
    pmeta = read_metadata(output_dir / "python_metadata.json")
    jmean, jcov = weighted_mean_cov(julia_samples, julia_weights)
    pmean, pcov = weighted_mean_cov(python_samples, python_weights)
    summary = {
        "corner_file": str(output_png),
        "nsamples_plot": int(nsamples_plot),
        "julia": {
            "nsamples": int(len(julia_samples)),
            "logz": jmeta.get("logz"),
            "logzerr": jmeta.get("logzerr"),
            "mean": jmean.tolist(),
            "cov_diag": np.diag(jcov).tolist(),
        },
        "python": {
            "nsamples": int(len(python_samples)),
            "logz": pmeta.get("logz"),
            "logzerr": pmeta.get("logzerr"),
            "mean": pmean.tolist(),
            "cov_diag": np.diag(pcov).tolist(),
            "dynesty_file": pmeta.get("dynesty_file"),
        },
        "mean_abs_delta": np.abs(jmean - pmean).tolist(),
    }
    summary_path = output_dir / "corner_overlay_summary.json"
    with summary_path.open("w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(f"Wrote corner overlay: {output_png}")
    print(f"Wrote overlay summary: {summary_path}")
    print(f"Julia mean:  {jmean}")
    print(f"Python mean: {pmean}")
    print(f"abs delta:   {np.abs(jmean - pmean)}")


if __name__ == "__main__":
    main()
