#!/usr/bin/env python3
"""Python dynesty parallel PE side for the Julia/Python overlay example.

Full run:
    OPENBLAS_NUM_THREADS=1 python examples/pe_parallel_python.py \
        --nlive 1000 --nproc 4 --queue-size 4

Quick smoke:
    OPENBLAS_NUM_THREADS=1 python examples/pe_parallel_python.py \
        --quick --nproc 2 --queue-size 2

The script imports dynesty from ../dynesty/py and writes weighted posterior
samples plus JSON metadata under examples/output/pe_parallel_compare/ by
default.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PYTHON_DYNESTY = ROOT.parent / "dynesty" / "py"
if not PYTHON_DYNESTY.exists():
    raise RuntimeError(f"expected local Python dynesty source at {PYTHON_DYNESTY}")
sys.path.insert(0, str(PYTHON_DYNESTY))

import dynesty  # noqa: E402
import dynesty.pool as dypool  # noqa: E402


PARAM_NAMES = ["theta1", "theta2", "theta3", "theta4"]
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
POSTERIOR_INVCOV = np.linalg.inv(POSTERIOR_COV)
PRIOR_LOW = np.array([-3.0, -3.0, -3.0, -3.0], dtype=float)
PRIOR_HIGH = np.array([3.0, 3.0, 3.0, 3.0], dtype=float)
PRIOR_WIDTH = PRIOR_HIGH - PRIOR_LOW


def prior_transform(u: np.ndarray) -> np.ndarray:
    return PRIOR_LOW + PRIOR_WIDTH * np.asarray(u)


def loglikelihood(theta: np.ndarray) -> float:
    delta = np.asarray(theta) - TRUE_THETA
    return -0.5 * float(delta @ POSTERIOR_INVCOV @ delta)


def normalized_weights(logwt: np.ndarray, logz: np.ndarray) -> np.ndarray:
    weights = np.exp(np.asarray(logwt, dtype=float) - float(logz[-1]))
    total = np.sum(weights)
    if not np.isfinite(total) or total <= 0:
        raise RuntimeError("invalid posterior weights from Python dynesty")
    return weights / total


def weighted_mean_cov(samples: np.ndarray, weights: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    mean = np.sum(samples * weights[:, None], axis=0)
    centered = samples - mean
    cov = centered.T @ (centered * weights[:, None])
    return mean, cov


def write_weighted_samples(path: Path, samples: np.ndarray, weights: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.column_stack([samples, weights])
    header = ",".join(PARAM_NAMES + ["weight"])
    np.savetxt(path, data, delimiter=",", header=header, comments="", fmt="%.17g")


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def run_python_pe(args: argparse.Namespace):
    use_pool = {
        "prior_transform": True,
        "loglikelihood": True,
        "propose_point": True,
        "update_bound": True,
    }
    with dypool.Pool(args.nproc, loglikelihood, prior_transform) as pool:
        sampler = dynesty.NestedSampler(
            pool.loglike,
            pool.prior_transform,
            ndim=len(TRUE_THETA),
            nlive=args.nlive_effective,
            bound="single",
            sample="unif",
            pool=pool,
            queue_size=args.queue_size,
            use_pool=use_pool,
            rstate=np.random.default_rng(args.seed),
            enlarge=1.1,
            bootstrap=0,
        )
        sampler.run_nested(
            dlogz=args.dlogz_effective,
            print_progress=False,
            add_live=True,
        )
        res = sampler.results
        samples = np.asarray(res.samples, dtype=float)
        weights = normalized_weights(res.logwt, res.logz)
        mean, cov = weighted_mean_cov(samples, weights)
        return res, samples, weights, mean, cov


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        default=str(ROOT / "examples" / "output" / "pe_parallel_compare"),
    )
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--nlive", type=int, default=1000)
    parser.add_argument("--quick-nlive", type=int, default=180)
    parser.add_argument("--dlogz", type=float, default=0.01)
    parser.add_argument("--quick-dlogz", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=20240611)
    parser.add_argument("--nproc", type=int, default=4)
    parser.add_argument("--queue-size", type=int, default=4)
    args = parser.parse_args(argv)
    args.nlive_effective = args.quick_nlive if args.quick else args.nlive
    args.dlogz_effective = args.quick_dlogz if args.quick else args.dlogz
    if args.nproc < 1:
        parser.error("--nproc must be at least 1")
    if args.queue_size < 1:
        parser.error("--queue-size must be at least 1")
    return args


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    output_dir = Path(args.output_dir).resolve()
    samples_path = output_dir / "python_weighted_samples.csv"
    metadata_path = output_dir / "python_metadata.json"

    res, samples, weights, mean, cov = run_python_pe(args)
    write_weighted_samples(samples_path, samples, weights)
    write_json(
        metadata_path,
        {
            "implementation": "Python dynesty",
            "dynesty_file": str(Path(dynesty.__file__).resolve()),
            "dynesty_version": getattr(dynesty, "__version__", "unknown"),
            "pool": "dynesty.pool.Pool",
            "nproc": args.nproc,
            "queue_size": args.queue_size,
            "quick": bool(args.quick),
            "nlive": int(args.nlive_effective),
            "dlogz": float(args.dlogz_effective),
            "seed": int(args.seed),
            "ndim": len(TRUE_THETA),
            "nsamples": int(len(samples)),
            "logz": float(res.logz[-1]),
            "logzerr": float(res.logzerr[-1]),
            "mean": mean.tolist(),
            "cov": cov.tolist(),
            "param_names": PARAM_NAMES,
            "true_theta": TRUE_THETA.tolist(),
            "posterior_cov": POSTERIOR_COV.tolist(),
            "samples_file": str(samples_path),
        },
    )
    print(
        "Python dynesty parallel PE: "
        f"nlive={args.nlive_effective} nsamples={len(samples)} "
        f"logz={res.logz[-1]:.6f} logzerr={res.logzerr[-1]:.6f} "
        f"nproc={args.nproc} queue_size={args.queue_size} wrote {samples_path}"
    )


if __name__ == "__main__":
    main()
