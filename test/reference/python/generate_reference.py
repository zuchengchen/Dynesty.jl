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
from dynesty import dynamicsampler


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
    nonbounded_periodic = np.array([1])
    nonbounded_reflective = np.array([3])
    quantile_x = np.array([0.0, 10.0, 20.0])
    quantile_q = np.array([0.0, 0.25, 0.5, 0.75, 1.0])
    quantile_weights = np.array([0.2, 0.3, 0.5])
    progress_args = (-3.0, -2.0, -10.0, 0.2, 0.0, 0.25, 0.1)
    resample_samples = np.array([[1.0, 2.0], [3.0, 4.0], [5.0, 8.0], [7.0, 9.0]])
    resample_weights = np.array([0.5, 0.25, 0.15, 0.1])

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
        "get_nonbounded": {
            "ndim": 4,
            "periodic_python_0_based": nonbounded_periodic.tolist(),
            "reflective_python_0_based": nonbounded_reflective.tolist(),
            "periodic_julia_1_based": (nonbounded_periodic + 1).tolist(),
            "reflective_julia_1_based": (nonbounded_reflective + 1).tolist(),
            "value": utils.get_nonbounded(
                4, nonbounded_periodic, nonbounded_reflective
            ).tolist(),
        },
        "unitcheck": {
            "inside": [0.1, 0.9],
            "edge": [0.0, 0.9],
            "nonbounded_u": [0.2, -0.25],
            "nonbounded_bad_u": [0.2, -0.75],
            "nonbounded": [True, False],
            "inside_value": bool(utils.unitcheck(np.array([0.1, 0.9]))),
            "edge_value": bool(utils.unitcheck(np.array([0.0, 0.9]))),
            "nonbounded_value": bool(
                utils.unitcheck(np.array([0.2, -0.25]), np.array([True, False]))
            ),
            "nonbounded_bad_value": bool(
                utils.unitcheck(np.array([0.2, -0.75]), np.array([True, False]))
            ),
        },
        "resample_equal": {
            "samples": resample_samples.tolist(),
            "weights": resample_weights.tolist(),
            "seed": 2024,
            "python_value": utils.resample_equal(
                resample_samples, resample_weights, np.random.default_rng(2024)
            ).tolist(),
            "note": "Julia uses its own RNG; tests check deterministic Julia replay and resampling invariants.",
        },
        "quantile": {
            "x": quantile_x.tolist(),
            "q": quantile_q.tolist(),
            "weights": quantile_weights.tolist(),
            "unweighted": utils.quantile(quantile_x, quantile_q).tolist(),
            "weighted": utils.quantile(
                quantile_x, quantile_q, weights=quantile_weights
            ),
            "rtol": 1e-12,
            "atol": 1e-12,
        },
        "progress_integration": {
            "args": list(progress_args),
            "logwt": float(utils.progress_integration(*progress_args)[0]),
            "logz": float(utils.progress_integration(*progress_args)[1]),
            "logzvar": float(utils.progress_integration(*progress_args)[2]),
            "h": float(utils.progress_integration(*progress_args)[3]),
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
    boot_points = np.array(
        [
            [0.10, 0.20],
            [0.80, 0.20],
            [0.50, 0.90],
            [0.30, 0.70],
            [0.65, 0.55],
            [0.20, 0.35],
            [0.75, 0.85],
        ]
    )
    boot_in, boot_out = bounding._bootstrap_points(
        boot_points, np.random.SeedSequence(13579)
    )
    boot_single = bounding._ellipsoid_bootstrap_expand(
        (False, boot_points, np.random.SeedSequence(97531))
    )
    boot_multi = bounding._ellipsoid_bootstrap_expand(
        (True, boot_points, np.random.SeedSequence(97531))
    )
    slogdet_input = np.array([[2.0, 0.3], [0.3, 1.5]])
    split_points = np.array(
        [
            [0.08, 0.12],
            [0.12, 0.18],
            [0.18, 0.10],
            [0.16, 0.22],
            [0.22, 0.16],
            [0.10, 0.24],
            [0.72, 0.76],
            [0.78, 0.82],
            [0.84, 0.74],
            [0.88, 0.86],
            [0.76, 0.90],
            [0.92, 0.78],
        ]
    )
    split_first = bounding.bounding_ellipsoid(split_points)
    split_ells = bounding._bounding_ellipsoids(split_points, split_first)
    split_multi = bounding.bounding_ellipsoids(split_points)

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
        "slogdet_checked": {
            "input": slogdet_input.tolist(),
            "value": float(bounding._slogdet_checked(slogdet_input)),
        },
        "bootstrap_points": {
            "seed": 13579,
            "points": boot_points.tolist(),
            "points_in": boot_in.tolist(),
            "points_out": boot_out.tolist(),
        },
        "ellipsoid_bootstrap_expand": {
            "seed": 97531,
            "single": float(boot_single),
            "multi": float(boot_multi),
            "note": "Julia uses its own RNG; tests check geometry invariants instead of same-seed equality.",
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
        "recursive_split": {
            "points": split_points.tolist(),
            "first_logvol": float(split_first.logvol),
            "nells": int(split_multi.nells),
            "logvol": float(split_multi.logvol),
            "logvol_ells": split_multi.logvol_ells.tolist(),
            "ctrs": [ell.ctr.tolist() for ell in split_ells],
            "covs": [ell.cov.tolist() for ell in split_ells],
            "contains": [bool(split_multi.contains(row)) for row in split_points],
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

    post_samples = np.array(
        [
            [0.10, 0.20],
            [0.30, 0.40],
            [0.50, 0.60],
            [0.70, 0.80],
            [0.90, 1.00],
            [1.10, 1.20],
        ]
    )
    post_samples_u = post_samples / 2.0
    post_samples_id = np.array([0, 1, 0, 1, 0, 1])
    post_samples_it = np.arange(1, 7)
    post_logl = np.array([-5.0, -4.2, -3.1, -2.2, -1.3, -0.7])
    post_logvol = np.cumsum(np.log(np.ones(6) * 3.0 / 4.0))
    post_logwt, post_logz, post_logzvar, post_h = utils.compute_integrals(
        logl=post_logl, logvol=post_logvol
    )
    post_res = utils.Results(
        dict(
            nlive=3,
            niter=6,
            ncall=np.array([2, 3, 2, 3, 1, 1]),
            eff=50.0,
            samples=post_samples,
            samples_u=post_samples_u,
            samples_id=post_samples_id,
            samples_it=post_samples_it,
            logwt=post_logwt,
            logl=post_logl,
            logvol=post_logvol,
            logz=post_logz,
            logzerr=np.sqrt(np.maximum(post_logzvar, 0)),
            information=post_h,
            blob=np.array(["a", "b", "c", "d", "e", "f"], dtype=object),
            proposal_stats=np.array([None] * 6, dtype=object),
        )
    )
    reweighted = utils.reweight_run(post_res, post_logl - np.array([0.0, 0.1, 0.0, 0.2, 0.0, 0.3]))
    strands = utils.unravel_run(post_res, print_progress=False)
    merged = utils.merge_runs(strands, print_progress=False)
    dyn_static = utils.Results(
        dict(
            niter=6,
            ncall=np.array([1, 1, 1, 1, 1, 1]),
            eff=100.0,
            samples=post_samples,
            samples_u=post_samples_u,
            samples_id=post_samples_id,
            samples_it=post_samples_it,
            samples_n=np.array([3, 3, 3, 3, 3, 3]),
            logwt=post_logwt,
            logl=post_logl,
            logvol=post_logvol,
            logz=post_logz,
            logzerr=np.sqrt(np.maximum(post_logzvar, 0)),
            information=post_h,
            blob=np.array(["a", "b", "c", "d", "e", "f"], dtype=object),
            proposal_stats=np.array([None] * 6, dtype=object),
        )
    )
    checked = utils.check_result_static(dyn_static)
    fd_mask, fd_start, fd_bounds = utils._find_decrease(np.array([3, 2, 1, 4, 4, 3, 2]))

    def result_summary(res):
        out = {
            "isdynamic": bool(res.isdynamic()),
            "niter": int(res.niter),
            "ncall": np.asarray(res.ncall).tolist(),
            "samples": np.asarray(res.samples).tolist(),
            "samples_u": np.asarray(res.samples_u).tolist(),
            "samples_id_python_0_based": np.asarray(res.samples_id).astype(int).tolist(),
            "samples_id_julia_1_based": (np.asarray(res.samples_id).astype(int) + 1).tolist(),
            "samples_it": np.asarray(res.samples_it).astype(int).tolist(),
            "logl": np.asarray(res.logl).tolist(),
            "logvol": np.asarray(res.logvol).tolist(),
            "logwt": np.asarray(res.logwt).tolist(),
            "logz": np.asarray(res.logz).tolist(),
            "logzerr": np.asarray(res.logzerr).tolist(),
        }
        if "nlive" in res.keys():
            out["nlive"] = int(res.nlive)
        if "samples_n" in res.keys():
            out["samples_n"] = np.asarray(res.samples_n).astype(int).tolist()
        return out

    postprocess_fixture = {
        "source": fixture["source"],
        "input": result_summary(post_res),
        "reweight_logp_new": (post_logl - np.array([0.0, 0.1, 0.0, 0.2, 0.0, 0.3])).tolist(),
        "reweighted": {
            "logwt": np.asarray(reweighted.logwt).tolist(),
            "logz": np.asarray(reweighted.logz).tolist(),
            "logzerr": np.asarray(reweighted.logzerr).tolist(),
            "information": np.asarray(reweighted.information).tolist(),
        },
        "unravel": {
            "nstrands": len(strands),
            "strands": [result_summary(strand) for strand in strands],
        },
        "merged": result_summary(merged),
        "checked_static": result_summary(checked),
        "find_decrease": {
            "samples_n": [3, 2, 1, 4, 4, 3, 2],
            "mask": fd_mask.tolist(),
            "nlive_start": np.asarray(fd_start).astype(int).tolist(),
            "bounds_python_half_open": [list(map(int, bound)) for bound in fd_bounds],
            "bounds_julia_half_open": [[int(bound[0]) + 1, int(bound[1]) + 1] for bound in fd_bounds],
        },
        "rtol": 1e-10,
        "atol": 1e-12,
    }
    (FIXTURES / "results_postprocess.json").write_text(
        json.dumps(postprocess_fixture, indent=2, sort_keys=True) + "\n"
    )

    dyn_samples_n = np.array([6, 6, 5, 5, 4, 4, 3])
    dyn_logl = np.array([-6.0, -5.1, -4.2, -3.0, -2.4, -1.5, -0.8])
    dyn_logvol = np.cumsum(np.log(dyn_samples_n / (dyn_samples_n + 1.0)))
    dyn_logwt, dyn_logz, dyn_logzvar, dyn_h = utils.compute_integrals(
        logl=dyn_logl, logvol=dyn_logvol
    )
    dyn_res = utils.Results(
        dict(
            niter=len(dyn_logl),
            ncall=np.array([2, 2, 3, 2, 4, 3, 1]),
            eff=100.0 * len(dyn_logl) / np.sum([2, 2, 3, 2, 4, 3, 1]),
            samples=np.column_stack(
                (
                    np.linspace(0.1, 0.7, len(dyn_logl)),
                    np.linspace(0.2, 0.8, len(dyn_logl)),
                )
            ),
            samples_u=np.column_stack(
                (
                    np.linspace(0.05, 0.35, len(dyn_logl)),
                    np.linspace(0.15, 0.45, len(dyn_logl)),
                )
            ),
            samples_id=np.array([0, 1, 2, 0, 1, 2, 0]),
            samples_it=np.arange(1, len(dyn_logl) + 1),
            samples_n=dyn_samples_n,
            logwt=dyn_logwt,
            logl=dyn_logl,
            logvol=dyn_logvol,
            logz=dyn_logz,
            logzerr=np.sqrt(np.maximum(dyn_logzvar, 0)),
            information=dyn_h,
            blob=np.array([None] * len(dyn_logl), dtype=object),
            proposal_stats=np.array([None] * len(dyn_logl), dtype=object),
        )
    )
    zweight, pweight = dynamicsampler.compute_weights(dyn_res)
    weight_args = dict(pfrac=0.0, maxfrac=0.99, pad=1)
    weight_bounds, weights = dynamicsampler.weight_function(
        dyn_res, args=weight_args, return_weights=True
    )
    stop_args = dict(
        pfrac=0.35,
        evid_thresh=0.25,
        target_n_effective=4.0,
        n_mc=0,
        error="jitter",
        approx=True,
    )
    stop_flag, stop_vals = dynamicsampler.stopping_function(
        dyn_res, args=stop_args, return_vals=True
    )
    dynamic_fixture = {
        "source": fixture["source"],
        "input": result_summary(dyn_res),
        "compute_weights": {
            "zweight": np.asarray(zweight).tolist(),
            "pweight": np.asarray(pweight).tolist(),
        },
        "weight_function": {
            "args": weight_args,
            "bounds": list(map(float, weight_bounds)),
            "pweight": np.asarray(weights[0]).tolist(),
            "zweight": np.asarray(weights[1]).tolist(),
            "weight": np.asarray(weights[2]).tolist(),
        },
        "stopping_function": {
            "args": stop_args,
            "flag": bool(stop_flag),
            "stop_post": float(stop_vals[0]),
            "stop_evid": float(stop_vals[1]),
            "stop": float(stop_vals[2]),
        },
        "state_values": {
            "INIT": int(dynamicsampler.DynamicSamplerStatesEnum.INIT.value),
            "LIVEPOINTSINIT": int(
                dynamicsampler.DynamicSamplerStatesEnum.LIVEPOINTSINIT.value
            ),
            "INBASE": int(dynamicsampler.DynamicSamplerStatesEnum.INBASE.value),
            "BASE_DONE": int(dynamicsampler.DynamicSamplerStatesEnum.BASE_DONE.value),
            "INBATCH": int(dynamicsampler.DynamicSamplerStatesEnum.INBATCH.value),
            "BATCH_DONE": int(dynamicsampler.DynamicSamplerStatesEnum.BATCH_DONE.value),
            "INBASEADDLIVE": int(
                dynamicsampler.DynamicSamplerStatesEnum.INBASEADDLIVE.value
            ),
            "INBATCHADDLIVE": int(
                dynamicsampler.DynamicSamplerStatesEnum.INBATCHADDLIVE.value
            ),
            "RUN_DONE": int(dynamicsampler.DynamicSamplerStatesEnum.RUN_DONE.value),
        },
        "rtol": 1e-10,
        "atol": 1e-12,
    }
    (FIXTURES / "dynamic_core.json").write_text(
        json.dumps(dynamic_fixture, indent=2, sort_keys=True) + "\n"
    )


if __name__ == "__main__":
    main()
