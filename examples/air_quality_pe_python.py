#!/usr/bin/env python3
"""Python dynesty air-quality PE runner using the canonical Julia likelihood.

The PM2.5 likelihood is implemented only in examples/air_quality_likelihood.jl.
This script imports Python dynesty from ../dynesty/py, initializes a Python-Julia
bridge, and calls the Julia likelihood from Python dynesty.  It intentionally
does not contain a duplicate Python implementation of the physical model.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import multiprocessing
import os
import platform
import sys
import time
import traceback
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
PYTHON_DYNESTY = ROOT.parent / "dynesty" / "py"
LIKELIHOOD_FILE = ROOT / "examples" / "air_quality_likelihood.jl"
DEFAULT_OUTPUT_DIR = ROOT / "examples" / "output" / "air_quality_pe_compare"

if not PYTHON_DYNESTY.exists():
    raise RuntimeError(f"expected local Python dynesty source at {PYTHON_DYNESTY}")
sys.path.insert(0, str(PYTHON_DYNESTY))


BRIDGE_MAIN = None
BRIDGE_KIND: str | None = None
BRIDGE_COMPILED_MODULES: bool | None = None
BRIDGE_INIT_SECONDS: float | None = None
BRIDGE_INIT_STATUS = "not_initialized"
BRIDGE_INIT_ERROR: str | None = None
WORK_REPEATS = 1
SLEEP_MS = 0.0
np = None
dynesty = None


def import_numpy():
    global np
    if np is None:
        import numpy as numpy_module

        np = numpy_module
    return np


def import_dynesty():
    global dynesty
    if dynesty is None:
        import dynesty as dynesty_module

        dynesty = dynesty_module
    return dynesty


def module_available(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


def module_version(name: str) -> str | None:
    try:
        module = __import__(name)
    except Exception:
        return None
    return getattr(module, "__version__", "unknown")


def _bridge_eval(expr: str) -> Any:
    if BRIDGE_MAIN is None:
        raise RuntimeError("Julia bridge has not been initialized")
    return BRIDGE_MAIN.eval(expr)


def initialize_julia_bridge(
    work_repeats: int,
    sleep_ms: float,
    *,
    force_reinitialize: bool = False,
) -> dict[str, Any]:
    global BRIDGE_MAIN
    global BRIDGE_KIND
    global BRIDGE_COMPILED_MODULES
    global BRIDGE_INIT_SECONDS
    global BRIDGE_INIT_STATUS
    global BRIDGE_INIT_ERROR
    global WORK_REPEATS
    global SLEEP_MS

    WORK_REPEATS = int(work_repeats)
    SLEEP_MS = float(sleep_ms)
    if BRIDGE_MAIN is not None and not force_reinitialize:
        return {
            "kind": BRIDGE_KIND,
            "status": BRIDGE_INIT_STATUS,
            "init_seconds": BRIDGE_INIT_SECONDS,
            "compiled_modules": BRIDGE_COMPILED_MODULES,
            "error": BRIDGE_INIT_ERROR,
        }

    start = time.time()
    BRIDGE_INIT_ERROR = None
    if module_available("juliacall"):
        try:
            from juliacall import Main as jl_main  # type: ignore

            jl_main.include(str(LIKELIHOOD_FILE))
            jl_main.eval("using .AirQualityPE")
            BRIDGE_MAIN = jl_main
            BRIDGE_KIND = "juliacall"
            BRIDGE_COMPILED_MODULES = None
            BRIDGE_INIT_STATUS = "ok"
        except Exception as exc:
            BRIDGE_INIT_ERROR = "".join(
                traceback.format_exception_only(type(exc), exc)
            ).strip()
            BRIDGE_MAIN = None

    if BRIDGE_MAIN is None:
        try:
            from julia.api import Julia  # type: ignore

            Julia(compiled_modules=False)
            from julia import Main as jl_main  # type: ignore

            jl_main.include(str(LIKELIHOOD_FILE))
            jl_main.eval("using .AirQualityPE")
            BRIDGE_MAIN = jl_main
            BRIDGE_KIND = "pyjulia"
            BRIDGE_COMPILED_MODULES = False
            BRIDGE_INIT_STATUS = "ok"
        except Exception as exc:
            prior_error = BRIDGE_INIT_ERROR
            pyjulia_error = "".join(
                traceback.format_exception_only(type(exc), exc)
            ).strip()
            BRIDGE_INIT_ERROR = (
                f"juliacall error: {prior_error}; PyJulia error: {pyjulia_error}"
                if prior_error
                else pyjulia_error
            )
            BRIDGE_MAIN = None
            BRIDGE_KIND = None
            BRIDGE_COMPILED_MODULES = None
            BRIDGE_INIT_STATUS = "failed"

    BRIDGE_INIT_SECONDS = time.time() - start
    if BRIDGE_MAIN is None:
        return {
            "kind": BRIDGE_KIND,
            "status": BRIDGE_INIT_STATUS,
            "init_seconds": BRIDGE_INIT_SECONDS,
            "compiled_modules": BRIDGE_COMPILED_MODULES,
            "error": BRIDGE_INIT_ERROR,
        }

    _bridge_eval("AirQualityPE.reset_air_quality_call_count!()")
    return {
        "kind": BRIDGE_KIND,
        "status": BRIDGE_INIT_STATUS,
        "init_seconds": BRIDGE_INIT_SECONDS,
        "compiled_modules": BRIDGE_COMPILED_MODULES,
        "error": BRIDGE_INIT_ERROR,
    }


def julia_prior_transform(u: np.ndarray) -> np.ndarray:
    numpy = import_numpy()
    values = _bridge_eval("AirQualityPE.air_quality_prior_transform")(list(map(float, u)))
    return numpy.asarray(values, dtype=float)


def julia_loglikelihood(theta: np.ndarray) -> float:
    value = _bridge_eval("AirQualityPE.air_quality_loglikelihood")(
        list(map(float, theta)),
        int(WORK_REPEATS),
        float(SLEEP_MS),
    )
    return float(value)


def worker_initializer(work_repeats: int, sleep_ms: float) -> None:
    initialize_julia_bridge(work_repeats, sleep_ms)
    import_numpy()


def normalized_weights(logwt: np.ndarray, logz: np.ndarray) -> np.ndarray:
    numpy = import_numpy()
    weights = numpy.exp(numpy.asarray(logwt, dtype=float) - float(logz[-1]))
    total = numpy.sum(weights)
    if not numpy.isfinite(total) or total <= 0:
        raise RuntimeError("invalid posterior weights from Python dynesty")
    return weights / total


def weighted_mean_cov(
    samples: np.ndarray,
    weights: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    numpy = import_numpy()
    mean = numpy.sum(samples * weights[:, None], axis=0)
    centered = samples - mean
    cov = centered.T @ (centered * weights[:, None])
    return mean, cov


def write_weighted_samples(path: Path, samples: np.ndarray, weights: np.ndarray, names: list[str]) -> None:
    numpy = import_numpy()
    path.parent.mkdir(parents=True, exist_ok=True)
    data = numpy.column_stack([samples, weights])
    header = ",".join(names + ["weight"])
    numpy.savetxt(path, data, delimiter=",", header=header, comments="", fmt="%.17g")


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def jsonable(value: Any) -> Any:
    numpy = import_numpy()
    if isinstance(value, numpy.ndarray):
        return value.tolist()
    if isinstance(value, (numpy.floating, numpy.integer)):
        return value.item()
    if isinstance(value, dict):
        return {str(k): jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [jsonable(v) for v in value]
    return value


def bridge_calibration(work_repeats: int, ntrial: int, sleep_ms: float) -> dict[str, Any]:
    result = _bridge_eval("AirQualityPE.calibrate_air_quality_likelihood")(
        work_repeats=int(work_repeats),
        ntrial=int(ntrial),
        sleep_ms=float(sleep_ms),
    )
    payload = jsonable(dict(result))
    payload["kind"] = "python_bridge"
    payload["bridge_kind"] = BRIDGE_KIND
    return payload


def call_count() -> int:
    try:
        return int(_bridge_eval("AirQualityPE.air_quality_call_count")())
    except Exception:
        return -1


def dataset_metadata(work_repeats: int, sleep_ms: float) -> dict[str, Any]:
    meta = _bridge_eval("AirQualityPE.air_quality_dataset_metadata")(
        work_repeats=int(work_repeats),
        sleep_ms=float(sleep_ms),
    )
    return jsonable(dict(meta))


def parameter_names() -> list[str]:
    return [str(x) for x in list(_bridge_eval("AirQualityPE.air_quality_parameter_names")())]


def truth_vector() -> list[float]:
    return [float(x) for x in list(_bridge_eval("AirQualityPE.air_quality_truth")())]


def ndim() -> int:
    return int(_bridge_eval("AirQualityPE.AIR_QUALITY_NDIM"))


def run_python_air_quality_pe(args: argparse.Namespace):
    bridge_info = initialize_julia_bridge(args.work_repeats, args.sleep_ms)
    if bridge_info["status"] != "ok":
        raise RuntimeError(f"Julia bridge failed: {bridge_info}")

    numpy = import_numpy()
    dynesty_module = import_dynesty()
    py_bridge_calibration = bridge_calibration(
        args.work_repeats,
        args.calibration_trials,
        args.sleep_ms,
    )
    names = parameter_names()
    truth = truth_vector()
    n_dim = ndim()
    use_pool = {
        "prior_transform": True,
        "loglikelihood": True,
        "propose_point": True,
        "update_bound": True,
    }
    context = multiprocessing.get_context(args.multiprocessing_start_method)
    pool = context.Pool(
        args.nproc,
        initializer=worker_initializer,
        initargs=(args.work_repeats, args.sleep_ms),
    )
    try:
        start_wall = time.time()
        sampler = dynesty_module.NestedSampler(
            julia_loglikelihood,
            julia_prior_transform,
            ndim=n_dim,
            nlive=args.nlive_effective,
            bound="single",
            sample="unif",
            pool=pool,
            queue_size=args.queue_size,
            use_pool=use_pool,
            rstate=numpy.random.default_rng(args.seed),
            enlarge=1.1,
            bootstrap=0,
        )
        sampler.run_nested(
            dlogz=args.dlogz_effective,
            print_progress=False,
            add_live=True,
        )
        sampler_wall = time.time() - start_wall
    finally:
        pool.close()
        pool.join()

    res = sampler.results
    samples = numpy.asarray(res.samples, dtype=float)
    weights = normalized_weights(res.logwt, res.logz)
    mean, cov = weighted_mean_cov(samples, weights)
    return {
        "res": res,
        "samples": samples,
        "weights": weights,
        "mean": mean,
        "cov": cov,
        "names": names,
        "truth": truth,
        "bridge_info": bridge_info,
        "bridge_calibration": py_bridge_calibration,
        "sampler_wall": sampler_wall,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--nlive", type=int, default=800)
    parser.add_argument("--quick-nlive", type=int, default=120)
    parser.add_argument("--dlogz", type=float, default=0.08)
    parser.add_argument("--quick-dlogz", type=float, default=0.5)
    parser.add_argument("--seed", type=int, default=20240622)
    parser.add_argument("--nproc", type=int, default=31)
    parser.add_argument("--queue-size", type=int, default=31)
    parser.add_argument("--work-repeats", type=int, default=1)
    parser.add_argument("--sleep-ms", type=float, default=0.0)
    parser.add_argument("--calibration-trials", type=int, default=9)
    parser.add_argument("--bridge-smoke-only", action="store_true")
    parser.add_argument(
        "--multiprocessing-start-method",
        choices=("spawn", "forkserver", "fork"),
        default="spawn",
        help="Default spawn avoids forking an initialized Julia runtime.",
    )
    args = parser.parse_args(argv)
    args.nlive_effective = args.quick_nlive if args.quick else args.nlive
    args.dlogz_effective = args.quick_dlogz if args.quick else args.dlogz
    if args.nproc < 1:
        parser.error("--nproc must be at least 1")
    if args.queue_size < 1:
        parser.error("--queue-size must be at least 1")
    if args.work_repeats < 0:
        parser.error("--work-repeats must be nonnegative")
    if args.sleep_ms < 0:
        parser.error("--sleep-ms must be nonnegative")
    return args


def environment_summary() -> dict[str, Any]:
    return {
        "OPENBLAS_NUM_THREADS": os.environ.get("OPENBLAS_NUM_THREADS"),
        "OMP_NUM_THREADS": os.environ.get("OMP_NUM_THREADS"),
        "MKL_NUM_THREADS": os.environ.get("MKL_NUM_THREADS"),
        "PYTHONPATH": os.environ.get("PYTHONPATH"),
    }


def dynesty_info_safe() -> dict[str, Any]:
    try:
        module = import_dynesty()
        return {
            "dynesty_file": str(Path(module.__file__).resolve()),
            "dynesty_version": getattr(module, "__version__", "unknown"),
        }
    except Exception as exc:
        return {
            "dynesty_file": None,
            "dynesty_version": None,
            "dynesty_import_error": f"{type(exc).__name__}: {exc}",
        }


def numpy_version_safe() -> str | None:
    try:
        return str(import_numpy().__version__)
    except Exception:
        return None


def failure_metadata(args: argparse.Namespace, error: BaseException, bridge_info: dict[str, Any]) -> dict[str, Any]:
    dynesty_info = dynesty_info_safe()
    payload = {
        "implementation": "Python dynesty",
        "run_kind": "air_quality_pe",
        "status": "failed",
        "exit_error_type": type(error).__name__,
        "exit_error_message": str(error),
        "traceback": traceback.format_exc(),
        "canonical_likelihood": str(LIKELIHOOD_FILE),
        "likelihood_language": "Julia",
        "likelihood_call_path": "Python dynesty -> Python-Julia bridge -> Julia likelihood",
        "bridge_kind": bridge_info.get("kind"),
        "bridge_init_status": bridge_info.get("status"),
        "bridge_init_seconds": bridge_info.get("init_seconds"),
        "bridge_compiled_modules": bridge_info.get("compiled_modules"),
        "bridge_error": bridge_info.get("error"),
        "quick": bool(args.quick),
        "nlive": int(args.nlive_effective),
        "dlogz": float(args.dlogz_effective),
        "queue_size": int(args.queue_size),
        "nproc": int(args.nproc),
        "multiprocessing_start_method": args.multiprocessing_start_method,
        "work_repeats": int(args.work_repeats),
        "sleep_ms": float(args.sleep_ms),
        "environment_variables": environment_summary(),
        "python_executable": sys.executable,
        "python_version": sys.version,
        "platform": platform.platform(),
        "numpy_version": numpy_version_safe(),
        "scipy_version": module_version("scipy"),
        "corner_available": module_available("corner"),
        "matplotlib_available": module_available("matplotlib"),
    }
    payload.update(dynesty_info)
    return payload


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    output_dir = Path(args.output_dir).resolve()
    samples_path = output_dir / "python_weighted_samples.csv"
    metadata_path = output_dir / "python_metadata.json"

    bridge_info: dict[str, Any] = {
        "kind": None,
        "status": "not_initialized",
        "init_seconds": None,
        "compiled_modules": None,
        "error": None,
    }
    try:
        bridge_info = initialize_julia_bridge(args.work_repeats, args.sleep_ms)
        if bridge_info["status"] != "ok":
            raise RuntimeError(f"Julia bridge failed: {bridge_info}")
        if args.bridge_smoke_only:
            numpy = import_numpy()
            value = julia_loglikelihood(julia_prior_transform(numpy.full(ndim(), 0.5)))
            metadata = {
                "implementation": "Python dynesty",
                "run_kind": "air_quality_bridge_smoke",
                "status": "ok",
                "bridge_kind": bridge_info.get("kind"),
                "bridge_init_status": bridge_info.get("status"),
                "bridge_init_seconds": bridge_info.get("init_seconds"),
                "bridge_compiled_modules": bridge_info.get("compiled_modules"),
                "smoke_loglikelihood": float(value),
                "canonical_likelihood": str(LIKELIHOOD_FILE),
                "likelihood_language": "Julia",
                "likelihood_call_count": call_count(),
                "dataset": dataset_metadata(args.work_repeats, args.sleep_ms),
            }
            write_json(metadata_path, metadata)
            print(f"Python-Julia bridge smoke ok: logl={value:.6f}")
            return

        fit = run_python_air_quality_pe(args)
    except Exception as exc:
        write_json(metadata_path, failure_metadata(args, exc, bridge_info))
        raise

    write_weighted_samples(samples_path, fit["samples"], fit["weights"], fit["names"])
    metadata = {
        "implementation": "Python dynesty",
        "run_kind": "air_quality_pe",
        "status": "ok",
        "canonical_likelihood": str(LIKELIHOOD_FILE),
        "likelihood_language": "Julia",
        "likelihood_call_path": "Python dynesty -> Python-Julia bridge -> Julia likelihood",
        "bridge_kind": fit["bridge_info"].get("kind"),
        "bridge_init_status": fit["bridge_info"].get("status"),
        "bridge_init_seconds": fit["bridge_info"].get("init_seconds"),
        "bridge_compiled_modules": fit["bridge_info"].get("compiled_modules"),
        "bridge_error": fit["bridge_info"].get("error"),
        "pool": "multiprocessing.Pool",
        "pool_kind": "multiprocessing",
        "multiprocessing_start_method": args.multiprocessing_start_method,
        "worker_label": f"Python {args.nproc} worker processes",
        "nproc": int(args.nproc),
        "queue_size": int(args.queue_size),
        "quick": bool(args.quick),
        "nlive": int(args.nlive_effective),
        "dlogz": float(args.dlogz_effective),
        "seed": int(args.seed),
        "ndim": len(fit["truth"]),
        "work_repeats": int(args.work_repeats),
        "sleep_ms": float(args.sleep_ms),
        "likelihood_call_count": call_count(),
        "direct_julia_likelihood_median_seconds": None,
        "python_bridge_likelihood_median_seconds": fit["bridge_calibration"].get(
            "median_seconds"
        ),
        "python_bridge_likelihood_calibration": fit["bridge_calibration"],
        "sampler_wall_time_seconds_internal": float(fit["sampler_wall"]),
        "nsamples": int(len(fit["samples"])),
        "ncall": int(import_numpy().sum(fit["res"].ncall)) if hasattr(fit["res"], "ncall") else None,
        "logz": float(fit["res"].logz[-1]),
        "logzerr": float(fit["res"].logzerr[-1]),
        "posterior_weighted_mean": fit["mean"].tolist(),
        "posterior_weighted_covariance_diagonal": import_numpy().diag(fit["cov"]).tolist(),
        "cov": fit["cov"].tolist(),
        "param_names": fit["names"],
        "true_theta": fit["truth"],
        "truth": dataset_metadata(args.work_repeats, args.sleep_ms).get("truth"),
        "dataset": dataset_metadata(args.work_repeats, args.sleep_ms),
        "environment_variables": environment_summary(),
        "python_executable": sys.executable,
        "python_version": sys.version,
        "platform": platform.platform(),
        "dynesty_file": str(Path(import_dynesty().__file__).resolve()),
        "dynesty_version": getattr(import_dynesty(), "__version__", "unknown"),
        "numpy_version": import_numpy().__version__,
        "scipy_version": module_version("scipy"),
        "corner_available": module_available("corner"),
        "matplotlib_available": module_available("matplotlib"),
        "samples_file": str(samples_path),
        "metadata_file": str(metadata_path),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    write_json(metadata_path, metadata)
    print(
        "Python dynesty air-quality PE: "
        f"bridge={metadata['bridge_kind']} nlive={args.nlive_effective} "
        f"nsamples={len(fit['samples'])} logz={fit['res'].logz[-1]:.6f} "
        f"logzerr={fit['res'].logzerr[-1]:.6f} nproc={args.nproc} "
        f"queue_size={args.queue_size} wrote {samples_path}"
    )


if __name__ == "__main__":
    main()
