#!/usr/bin/env python3
"""Generate Python dynesty reference fixtures for Dynesty.jl tests."""

from __future__ import annotations

import json
import platform
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import scipy

import dynesty
from dynesty import utils


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT.parent / "dynesty"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def git_output(args: list[str]) -> str:
    return subprocess.check_output(["git", "-C", str(SOURCE), *args], text=True).strip()


def main() -> None:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    logwt = np.log(np.array([0.2, 0.3, 0.5]))
    reflect_input = np.array([-0.9, 1.1, 2.9, 4.2])
    samples = np.array([[1.0, 2.0], [3.0, 4.0], [5.0, 8.0]])
    weights = np.array([0.2, 0.3, 0.5])
    logl = np.array([-3.0, -2.0, -1.0, -0.5])
    logvol = np.array([-0.25, -0.75, -1.4, -2.3])
    logwt_i, logz, logzvar, h = utils.compute_integrals(logl=logl, logvol=logvol)

    fixture = {
        "source": {
            "path": str(SOURCE),
            "commit": git_output(["rev-parse", "HEAD"]),
            "branch": git_output(["branch", "--show-current"]),
            "status_short": git_output(["status", "--short"]),
            "dynesty_version": getattr(dynesty, "__version__", "unknown"),
            "python_version": platform.python_version(),
            "numpy_version": np.__version__,
            "scipy_version": scipy.__version__,
            "generated_at": datetime.now(timezone.utc).isoformat(),
        },
        "get_neff_from_logwt": {
            "logwt": logwt.tolist(),
            "value": float(utils.get_neff_from_logwt(logwt)),
            "rtol": 1e-12,
            "atol": 1e-12,
        },
        "apply_reflect": {
            "input": reflect_input.tolist(),
            "output": utils.apply_reflect(reflect_input.copy()).tolist(),
            "rtol": 1e-12,
            "atol": 1e-12,
        },
        "mean_and_cov": {
            "samples": samples.tolist(),
            "weights": weights.tolist(),
            "mean": utils.mean_and_cov(samples, weights)[0].tolist(),
            "cov": utils.mean_and_cov(samples, weights)[1].tolist(),
            "rtol": 1e-12,
            "atol": 1e-12,
        },
        "compute_integrals": {
            "logl": logl.tolist(),
            "logvol": logvol.tolist(),
            "logwt": logwt_i.tolist(),
            "logz": logz.tolist(),
            "logzvar": logzvar.tolist(),
            "h": h.tolist(),
            "rtol": 1e-10,
            "atol": 1e-12,
        },
    }
    (FIXTURES / "utils_core.json").write_text(json.dumps(fixture, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()

