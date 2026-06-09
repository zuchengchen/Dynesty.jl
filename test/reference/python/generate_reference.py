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
from dynesty import bounding


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

    points = np.array(
        [
            [0.10, 0.20],
            [0.80, 0.20],
            [0.50, 0.90],
            [0.30, 0.70],
            [0.65, 0.55],
        ]
    )
    ell = bounding.bounding_ellipsoid(points)
    multi = bounding.bounding_ellipsoids(points)
    scaled = bounding.Ellipsoid(
        2,
        ctr=ell.ctr.copy(),
        cov=ell.cov.copy(),
        am=ell.am.copy(),
        axes=ell.axes.copy(),
    )
    scaled.scale_to_logvol(ell.logvol + 0.5)
    rng = np.random.default_rng(12345)
    rand_sphere = bounding.randsphere(3, rstate=rng)
    choice_rng = np.random.default_rng(4321)
    choices = [int(bounding.rand_choice(np.array([0.2, 0.3, 0.5]), choice_rng)) for _ in range(8)]
    good, improved_cov, improved_am, improved_axes = bounding.improve_covar_mat(
        np.array([[1.0, 0.999999], [0.999999, 0.999998]])
    )

    bounding_fixture = {
        "source": fixture["source"],
        "points": points.tolist(),
        "unitcube": {
            "contains_inside": bool(bounding.UnitCube(2).contains(np.array([0.2, 0.8]))),
            "contains_edge": bool(bounding.UnitCube(2).contains(np.array([0.0, 0.5]))),
        },
        "randsphere": {
            "seed": 12345,
            "n": 3,
            "value": rand_sphere.tolist(),
        },
        "rand_choice": {
            "seed": 4321,
            "probabilities": [0.2, 0.3, 0.5],
            "values_python_0_based": choices,
            "values_julia_1_based": [v + 1 for v in choices],
        },
        "improve_covar_mat": {
            "input": [[1.0, 0.999999], [0.999999, 0.999998]],
            "good": bool(good),
            "cov": improved_cov.tolist(),
            "am": improved_am.tolist(),
            "axes": improved_axes.tolist(),
        },
        "ellipsoid": {
            "ctr": ell.ctr.tolist(),
            "cov": ell.cov.tolist(),
            "am": ell.am.tolist(),
            "axes": ell.axes.tolist(),
            "axlens": ell.axlens.tolist(),
            "logvol": float(ell.logvol),
            "distances": ell.distance_many(points).tolist(),
            "contains": [bool(ell.contains(row)) for row in points],
            "major_axis_endpoints": [x.tolist() for x in ell.major_axis_endpoints()],
            "scaled_logvol": float(scaled.logvol),
            "scaled_cov": scaled.cov.tolist(),
            "scaled_axlens": scaled.axlens.tolist(),
        },
        "multi": {
            "nells": int(multi.nells),
            "logvol": float(multi.logvol),
            "logvol_ells": multi.logvol_ells.tolist(),
            "contains": [bool(multi.contains(row)) for row in points],
        },
        "rtol": 1e-10,
        "atol": 1e-12,
    }
    (FIXTURES / "bounding_core.json").write_text(
        json.dumps(bounding_fixture, indent=2, sort_keys=True) + "\n"
    )

    friends_points = np.array(
        [
            [0.10, 0.20],
            [0.80, 0.20],
            [0.50, 0.90],
            [0.30, 0.70],
            [0.65, 0.55],
            [0.20, 0.35],
        ]
    )
    friends = {}
    for name, cls, ftype in [
        ("radfriends", bounding.RadFriends, "balls"),
        ("supfriends", bounding.SupFriends, "cubes"),
    ]:
        bound = cls(2)
        bound.update(
            friends_points,
            rstate=np.random.default_rng(111),
            bootstrap=0,
            mc_integrate=False,
            use_clustering=False,
        )
        bound.ctrs = friends_points
        points_t = np.dot(friends_points, bound.axes_inv)
        loo = bounding._friends_leaveoneout_radius(points_t, ftype)
        friends[name] = {
            "cov": bound.cov.tolist(),
            "am": bound.am.tolist(),
            "axes": bound.axes.tolist(),
            "axes_inv": bound.axes_inv.tolist(),
            "logvol": float(bound.logvol),
            "ctrs": bound.ctrs.tolist(),
            "loo_radius": loo.tolist(),
            "contains": [bool(bound.contains(row)) for row in friends_points],
            "overlap_first": int(bound.overlap(friends_points[0])),
            "within_first_python_0_based": bound.within(friends_points[0]).tolist(),
            "within_first_julia_1_based": (bound.within(friends_points[0]) + 1).tolist(),
        }
        scaled = cls(2, cov=bound.cov.copy())
        scaled.ctrs = friends_points
        scaled.scale_to_logvol(bound.logvol + 0.25)
        friends[name]["scaled_logvol"] = float(scaled.logvol)
        friends[name]["scaled_cov"] = scaled.cov.tolist()

    boot_seed = np.random.SeedSequence(2468)
    friends_fixture = {
        "source": fixture["source"],
        "points": friends_points.tolist(),
        "radfriends": friends["radfriends"],
        "supfriends": friends["supfriends"],
        "bootstrap": {
            "seed_note": "Julia bootstrap uses MersenneTwister and is checked by invariants, not same-seed equality.",
            "python_balls": float(
                bounding._friends_bootstrap_radius((friends_points, "balls", boot_seed))
            ),
            "python_cubes": float(
                bounding._friends_bootstrap_radius((friends_points, "cubes", boot_seed))
            ),
        },
        "rtol": 1e-8,
        "atol": 1e-10,
    }
    (FIXTURES / "friends_core.json").write_text(
        json.dumps(friends_fixture, indent=2, sort_keys=True) + "\n"
    )


if __name__ == "__main__":
    main()
