# Python Feature Gap Audit

Audit timestamp: 2026-06-12T00:05:54+08:00

This document is the Stage 0 audit record and rolling completion report for the
Python feature-gap completion goal. Python dynesty is treated as the read-only
algorithm, behavior, workflow, tests, docs, and benchmark reference. Dynesty.jl
uses a strictly Julia-native public API.

## Snapshots

Python source reference:

- Path: `../dynesty`
- Branch: `master`
- Commit: `3ec158de0d2bf12a56230faacd0c987b3d55d550`
- `git status --short`: clean
- Source handling: read-only; no pull, checkout, branch switch, or file
  modification was performed.

Julia repository at audit start:

- Branch at first check: `master`
- Initial HEAD: `95a40b31e446922594ae1991918e7fac2a5f8da3`
- Required work branch: `julia-native-feature-completion`

Initial worktree entries recorded before edits:

| Path | Initial status | Classification | Handling |
| --- | --- | --- | --- |
| `FULL_CHAIN_PARALLEL_GOAL_PROMPT.md` | untracked | historical planning prompt | obsolete after the corresponding branch work; delete before final clean worktree |
| `PARALLEL_COST_BENCHMARK_GOAL_PROMPT.md` | untracked | historical planning prompt | obsolete after benchmark runner implementation; delete before final clean worktree |
| `PARALLEL_REFINEMENT_GOAL_PROMPT.md` | untracked | historical planning prompt | obsolete after parallel refinement implementation; delete before final clean worktree |
| `PYTHON_FEATURE_GAP_COMPLETION_GOAL_PROMPT.md` | untracked | active goal prompt | submit with the audit so the continuation contract is recorded |
| `REALISTIC_AIR_QUALITY_PE_GOAL_PROMPT.md` | untracked | historical planning prompt | obsolete after air-quality benchmark implementation; delete before final clean worktree |
| `SAMPLER_PARALLEL_GOAL_PROMPT.md` | untracked | historical planning prompt | obsolete after sampler-level parallel implementation; delete before final clean worktree |
| `TEST_REPORT_GOAL_PROMPT.md` | untracked | historical planning prompt | obsolete after test-report implementation; delete before final clean worktree |
| `examples/pe_compare_julia.jl` | untracked | obsolete experimental helper | replaced by `examples/pe_parallel_julia.jl` and benchmark runners; delete before final clean worktree |
| `examples/pe_compare_python.py` | untracked | obsolete experimental helper | replaced by `examples/pe_parallel_python.py` and benchmark runners; delete before final clean worktree |

Current source snapshot references already matched the read-only Python source
commit in:

- `docs/source_snapshot.md`
- `docs/src/source_snapshot.md`
- `docs/migration_matrix.md`
- `docs/src/migration_matrix.md`
- `test/reference/python/README.md`

## Audit Method

- Read `AGENTS.md`, `CODEX_GOAL_PROMPT.md`, and
  `PYTHON_FEATURE_GAP_COMPLETION_GOAL_PROMPT.md`.
- Captured Python and Julia git snapshots.
- Enumerated core Julia source, tests, docs, examples, benchmark scripts, and CI.
- Searched for pure Julia-native API blockers: `run_nested`, `rstate`,
  `random_state`, `use_pool`, `PoolUsage`, `blob`, `samples_bound`,
  `from_python_indices`, `logl_args`, `kwargs`, `alias`, `compat`, `pending`,
  `partial`, `future work`, and related terms.
- Enumerated Python reference files under `../dynesty/py/dynesty`,
  `../dynesty/tests`, `../dynesty/docs/source`, and `../dynesty/demos`.
- Verified default package tests after API cleanup with `Pkg.test()`.

## Python Source Surface

Core Python modules audited:

- `py/dynesty/__init__.py`
- `py/dynesty/bounding.py`
- `py/dynesty/dynesty.py`
- `py/dynesty/dynamicsampler.py`
- `py/dynesty/internal_samplers.py`
- `py/dynesty/plotting.py`
- `py/dynesty/pool.py`
- `py/dynesty/results.py`
- `py/dynesty/sampler.py`
- `py/dynesty/utils.py`

Python tests mapped through migration matrix and Julia test files:

- `tests/test_blob.py`
- `tests/test_bound_interface.py`
- `tests/test_dyn.py`
- `tests/test_egg.py`
- `tests/test_ellipsoid.py`
- `tests/test_gau.py`
- `tests/test_highdim.py`
- `tests/test_misc.py`
- `tests/test_ncdim.py`
- `tests/test_notebooks.py`
- `tests/test_pathology.py`
- `tests/test_periodic.py`
- `tests/test_plateau.py`
- `tests/test_plot.py`
- `tests/test_pool.py`
- `tests/test_printing.py`
- `tests/test_proposal_stats.py`
- `tests/test_reflect.py`
- `tests/test_resume.py`
- `tests/test_rosenbrock.py`
- `tests/test_sampler_interface.py`
- `tests/test_sampling.py`
- `tests/test_saver.py`
- `tests/test_volume.py`

Grouped Python test behavior mapping:

| Python test file(s) | Main behavior scenarios | Julia coverage / mapping | Status |
| --- | --- | --- | --- |
| `test_blob.py` | Blob likelihood outputs, live-point blobs, restart/checkpoint, pool blob path, dynamic blobs. | `test/test_utils.jl` (`LoglOutput`), `test/test_static_sampler.jl` blob/checkpoint testset, `test/test_dynamic_sampler.jl` blob/checkpoint testset, `test/test_results.jl` public `blobs` schema checks. | implemented / replacement |
| `test_bound_interface.py`, `test_ellipsoid.py` | Bound constructors, sampling, containment, ellipsoid/multi-ellipsoid overlap, Monte Carlo log-volume, pathological/crazy dimensions. | `test/test_bounding_unitcube_ellipsoid.jl`, `test/test_bounding_friends.jl`, `test/test_crosscheck_fixtures.jl`; migration matrix maps Python-specific SciPy clustering details to Julia Clustering.jl replacement. | implemented / replacement |
| `test_gau.py`, `test_egg.py`, `test_highdim.py`, `test_rosenbrock.py`, `test_pathology.py`, `test_plateau.py` | Static/dynamic sampler statistical smoke tests across Gaussian, multimodal, high-dimensional, Rosenbrock/pathological, plateau, cake, edge, and uniform likelihoods. | `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl`, `test/test_internal_samplers.jl`, examples (`gaussian`, `eggbox`, `gaussian_shells`, `high_dimensional_gaussian`, `loggamma_mixture`, `hyper_pyramid`), and fixture/statistical checks. Julia keeps these as invariant/statistical smoke coverage rather than one-for-one same-seed trajectory tests. | implemented / replacement |
| `test_dyn.py`, `test_ncdim.py` | Dynamic sampler run flow, batch construction, non-clustering dimensions, periodic dynamic/static cases. | `test/test_dynamic_sampler.jl` dynamic run/adaptive batch/weighting/configuration, `test/test_static_sampler.jl` periodic/reflective dimensions, migration matrix dynamic rows. | implemented / replacement |
| `test_sampling.py`, `test_sampler_interface.py` | Internal sampler proposals, random walk/slice/rslice behavior, custom sampler interface, walks/slices configuration. | `test/test_internal_samplers.jl`, `test/test_static_sampler.jl`, `docs/src/api/internal-samplers.md`; Python internal class shape maps to Julia-native proposal sampler types and call paths. | implemented / replacement |
| `test_periodic.py`, `test_reflect.py` | Periodic/reflective wrapping and validation errors. | `test/test_static_sampler.jl` periodic/reflective testset, `test/test_utils.jl` `apply_reflect!` and `get_nonbounded`; compatibility docs record 1-based indices. | implemented / intentional difference |
| `test_pool.py` | Python `Pool`, `use_pool`, queue size, pool args, sampler pool behavior. | `test/test_parallel.jl`, `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl`, `test/test_api_surface.jl`; Python API is replaced by map backends and `ParallelPolicy`, with negative tests for `use_pool`. | replacement |
| `test_resume.py`, `test_saver.py`, `test_misc.py` persistence portions | Save/restore, checkpoint delay, queue-size resume, finished resume, pickle-like workflows, maxcall/maxiter and live points. | `test/test_persistence.jl`, sampler checkpoint testsets, `src/persistence.jl`; Julia uses `.jls`/`.jld2`/HDF5 extension rather than pickle. Some Python exact saver modes are not applicable. | implemented / replacement |
| `test_plot.py` | Run/trace/corner/bound plotting for static/dynamic, periodic, balls/cubes. | `test/test_plotting.jl`, `test/test_crosscheck_fixtures.jl`, `docs/src/api/plotting.md`; Matplotlib figure/axes plumbing is not applicable. | implemented / replacement |
| `test_printing.py` | Progress/status printing, tqdm/no-tqdm behavior, large terminal width. | `test/test_utils.jl` progress display helpers and `test/test_static_sampler.jl` callback plumbing; tqdm-specific behavior maps to Julia IO callback replacement. | replacement |
| `test_proposal_stats.py` | Proposal statistics presence, length consistency, content validity, blobs, static/dynamic comparison. | `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl`, `test/test_parallel.jl`; Julia stores proposal counters/stats and parallel instrumentation. | implemented / replacement |
| `test_misc.py` utility/results portions | Inf/large logl, unravel/reweight/merge/quantile/neff, transform tuple, deterministic behavior, update interval, sampling history, ncall. | `test/test_utils.jl`, `test/test_results_postprocess.jl`, `test/test_results.jl`, sampler tests, Python fixtures, and examples such as `noisy_likelihood.jl` for reweighting workflow coverage. | implemented / replacement |
| `test_notebooks.py` | Executes Python demo notebooks. | Julia maps notebooks to Documenter pages and smoke-tested scripts rather than notebook execution. | replacement; demos mapping below |

The grouped mapping above is the current test-function audit proof: Python
tests that are API-shape- or ecosystem-specific are mapped to Julia-native
replacement tests, while stochastic sampler tests are mapped to invariant,
statistical, fixture, and smoke-workflow coverage instead of same-seed
trajectory equality.

Python docs and demos mapped as workflows:

- Docs: `api.rst`, `crashcourse.rst`, `dynamic.rst`, `errors.rst`,
  `examples.rst`, `faq.rst`, `index.rst`, `overview.rst`, `quickstart.rst`,
  `references.rst`
- Demos: overview, dynamic nested sampling, errors, new-in-3.0, 200-D normal,
  25-D correlated normal, eggbox, exponential wave, Gaussian shells,
  hyper-pyramid, importance reweighting, linear regression, loggamma, noisy
  likelihoods.

Docs/demos workflow mapping:

| Python docs/demo workflow | Julia workflow mapping | Status |
| --- | --- | --- |
| `README.md`, `quickstart.rst`, `overview.rst`, `crashcourse.rst` | `README.md`, `docs/src/index.md`, `docs/src/quickstart.md`, `docs/src/manual/getting-started.md`, `examples/overview.jl`. | implemented |
| `dynamic.rst`, Demo 2 | `docs/src/dynamic.md`, `docs/src/manual/dynamic.md`, `examples/dynamic_nested_sampling.jl`, dynamic sampler tests. | implemented |
| `errors.rst`, Demo 3 | `docs/src/errors.md`, `examples/errors.jl`, `test/test_results_postprocess.jl`. | implemented |
| `api.rst` | Documenter API pages under `docs/src/api/` with `checkdocs=:exports`. | implemented; continue exported-symbol audit before final |
| `examples.rst` and demos for Gaussian/eggbox/shells/high-dimensional normals | `docs/src/examples.md`, `examples/gaussian.jl`, `examples/eggbox.jl`, `examples/gaussian_shells.jl`, `examples/high_dimensional_gaussian.jl`, `test/test_examples.jl`. | implemented / replacement |
| Importance reweighting and error/post-processing demos | `docs/src/errors.md`, `docs/src/manual/results-persistence.md`, `test/test_results_postprocess.jl`. | implemented |
| Linear regression, exponential wave, loggamma, noisy likelihoods, hyper-pyramid notebooks | `examples/linear_regression.jl`, `examples/exponential_wave.jl`, `examples/loggamma_mixture.jl`, `examples/noisy_likelihood.jl`, `examples/hyper_pyramid.jl`, docs examples pages, and `test/test_examples.jl`. | implemented / replacement |
| `references.rst` | `get_citations`, README citation section, docs index/API utility docs. | implemented |
| `faq.rst` | Compatibility, migration guide, performance, persistence, and testing pages cover most operational guidance; a dedicated FAQ page has not been added. | remaining docs gap |
| Demo 4 / new in 3.0 | Dynamic/parallel/persistence docs cover relevant migrated behavior; no dedicated "new in Python dynesty 3.0" translation page. | replacement / not applicable for Julia versioning |

Julia workflow coverage is represented by Documenter pages under `docs/src`,
examples under `examples/`, tests under `test/`, fixtures under
`test/reference/python/fixtures`, and benchmark helpers under `benchmark/`.
Further turns must continue verifying every Python docs/demo workflow
requirement against the current Julia pages and examples; this stage did not
claim final full-project completion.

## Full Benchmark Suite

From Stage 1 onward, the full benchmark suite is:

| Entry | Classification | Command |
| --- | --- | --- |
| Core benchmark smoke | formal benchmark smoke gate | `julia --project=benchmark -e 'using Pkg; Pkg.instantiate(); include("benchmark/benchmarks.jl"); main()'` |
| Core BenchmarkTools suite | formal benchmark | `DYNESTY_RUN_BENCHMARKS=true julia --project=benchmark -e 'using Pkg; Pkg.instantiate(); include("benchmark/benchmarks.jl"); main()'` |
| Parallel cost smoke | formal comparison smoke | `julia --project=. benchmark/parallel_cost_compare.jl --mode smoke --allow-missing-usr-time --skip-plots` |
| Parallel cost formal | formal benchmark, output-producing | `julia --project=. benchmark/parallel_cost_compare.jl --mode formal --resume` |
| Parallel cost plots | plotting/overlay postprocessor | `python3 benchmark/parallel_cost_corner.py --help` for environment smoke; formal runs call it via the comparison script unless `--skip-plots` is used |
| Air-quality PE smoke | external-environment dependent benchmark smoke | `julia --project=. benchmark/air_quality_pe_compare.jl --mode smoke --allow-missing-usr-time --skip-plots` |
| Air-quality PE formal | external-environment dependent formal benchmark | `julia --project=. benchmark/air_quality_pe_compare.jl --mode formal --resume` |
| Air-quality corner overlay | plotting/overlay postprocessor | `python3 benchmark/air_quality_corner_overlay.py --help` for environment smoke; formal runs call it via the comparison script unless `--skip-plots` is used |
| Example smoke suite | compile/smoke helper | Covered by `julia --project=. -e 'using Pkg; Pkg.test()'` via `test/test_examples.jl` |
| Example scripts | user workflow smoke | `julia --project=. examples/overview.jl`; `julia --project=. examples/gaussian.jl`; `julia --project=. examples/dynamic_nested_sampling.jl`; `julia --project=. examples/eggbox.jl`; `julia --project=. examples/gaussian_shells.jl`; `julia --project=. examples/high_dimensional_gaussian.jl`; `julia --project=. examples/linear_regression.jl`; `julia --project=. examples/exponential_wave.jl`; `julia --project=. examples/loggamma_mixture.jl`; `julia --project=. examples/noisy_likelihood.jl`; `julia --project=. examples/hyper_pyramid.jl`; `julia --project=. examples/errors.jl` |
| Air-quality example | user workflow / benchmark helper | `julia --project=. examples/air_quality_pe_julia.jl --help`; Python counterpart `python3 examples/air_quality_pe_python.py --help` |
| PE parallel comparison helpers | benchmark helpers | `julia --project=. examples/pe_parallel_julia.jl --help`; `python3 examples/pe_parallel_python.py --help`; `python3 examples/pe_parallel_corner.py --help` |

Output directories such as `examples/output/**`, `docs/build/**`,
`docs/test_report/**`, and benchmark output directories are generated artifacts
and must not be committed unless explicitly promoted to documentation.

The comparison benchmark runners prefer GNU `/usr/bin/time -v` when available.
On hosts without that binary they now fall back to the Julia/Linux process-tree
monitor, recording wall time plus process-tree RSS/PSS metrics with
`monitor_kind="process_monitor"`. The `--allow-missing-usr-time` flag remains
accepted for older smoke commands but is no longer required for formal mode on
Linux.

## API Alias Removal Inventory

Removed or rejected in this stage:

- `run_nested(sampler)` no-bang mutating alias.
- `DynamicNestedSampler` constructor alias.
- `citations()` alias for `get_citations()`.
- String enum-like options for `bound`, `sample`, `parallel`, and
  `proposal_scheduler`.
- `rstate` and `random_state` sampler keywords.
- `PoolUsage` and `use_pool`; replaced with `ParallelPolicy`.
- Public `from_python_indices`.
- Public `Results` aliases `blob`, `samples_bound`, and `batch`.

Negative coverage:

- `test/test_api_surface.jl`
- `test/test_results.jl`
- `test/test_parallel.jl`
- `test/test_static_sampler.jl`

## Implementation Stages

Stage 0 / contract groundwork:

- Created branch `julia-native-feature-completion` from `master`.
- Updated `CODEX_GOAL_PROMPT.md` to define Python dynesty as the
  algorithm/workflow reference, not the public API surface reference.
- Added this audit document.
- Defined the full benchmark suite command list above.

Breaking API cleanup:

- Bumped package version to `0.2.0`.
- Added `CHANGELOG.md`.
- Added root and Documenter migration guides at `docs/migration_guide.md` and
  `docs/src/migration_guide.md`, linked from README and docs navigation.
- Replaced `PoolUsage` with `ParallelPolicy`.
- Removed no-bang mutating aliases and Python-compatible constructor/result
  aliases.
- Updated README, compatibility docs, API docs, migration matrix, and tests.
- Updated comparison benchmark runners so formal mode can use a Julia/Linux
  process-tree monitor when `/usr/bin/time -v` is unavailable.

## Validation Results

Completed in this stage:

- `julia --project=. -e 'using Pkg; Pkg.test()'` passed after the API cleanup,
  including examples, Python fixture readers, plotting helpers, and Aqua.
- `julia --project=. -e 'using Pkg; Pkg.test()'` passed again after adding the
  dedicated demo workflow scripts; the run included `Example scripts`: 60 pass,
  Python fixture readers, plotting helpers, and `Aqua quality checks`: 10 pass.
- `julia --project=. -e 'using Dynesty; include("test/test_examples.jl")'`
  passed after adding the dedicated linear-regression, exponential-wave,
  loggamma-mixture, noisy-likelihood, and hyper-pyramid demo scripts
  (`Example scripts`: 60 pass).
- `julia -e 'using Pkg; Pkg.activate(; temp=true); Pkg.add(Pkg.PackageSpec(name="JuliaFormatter", version="2.6.8")); using JuliaFormatter; format([...])'`
  formatted the new example scripts and `test/test_examples.jl`; the example
  smoke suite was rerun afterward and passed again (`Example scripts`: 60
  pass).
- `julia --project=docs docs/make.jl` passed after the API cleanup and after
  formatter normalization.
- `julia --project=docs -e 'using Pkg; Pkg.instantiate()' && julia --project=docs docs/make.jl`
  passed after updating the examples documentation.
- `julia -e 'using Pkg; Pkg.activate(temp=true); Pkg.add(PackageSpec(name="JuliaFormatter", version="2.6")); using JuliaFormatter; format(pwd(); verbose=true)'`
  completed and normalized Julia source formatting. A dry-run
  `overwrite=false` invocation was attempted first and reported format targets;
  the write-mode run was then used as the formatter gate.
- `julia -e 'using Pkg; Pkg.activate(temp=true); Pkg.develop(PackageSpec(path=pwd())); Pkg.add(PackageSpec(name="Aqua", version="0.8")); using Aqua, Dynesty; Aqua.test_all(Dynesty; project_extras=false)'`
  passed as an explicit Aqua check. Aqua also passed inside `Pkg.test()`.
- `julia --project=benchmark -e 'using Pkg; Pkg.instantiate(); include("benchmark/benchmarks.jl"); main()'`
  passed with benchmark smoke values `static=-2.543297456684836`,
  `dynamic=-3.058676219252836`, and `persistence=-3.5580368854155733`.
- `julia --project=benchmark -e 'using Pkg; Pkg.instantiate(); include("benchmark/benchmarks.jl"); using BenchmarkTools; tune!(SUITE); result = run(SUITE; seconds=0.1, samples=1, evals=1, verbose=false); ...'`
  passed as a bounded full BenchmarkTools suite construction/run check and
  returned benchmark groups `persistence` and `sampler`.
- `julia --project=. benchmark/parallel_cost_compare.jl --mode smoke --allow-missing-usr-time --skip-plots --output-dir examples/output/parallel_cost_compare_stage0_smoke`
  passed after converting CLI scheduler strings to Julia `Symbol` values at
  the helper-script boundary. The smoke summary recorded
  `cheap_julia_repeat1` and `cheap_python_repeat1` with `status=ok` and
  `exit_code=0`.
- `julia --project=. benchmark/parallel_cost_compare.jl --mode smoke --skip-plots --output-dir examples/output/parallel_cost_compare_monitor_smoke`
  passed without `--allow-missing-usr-time`, using the process-monitor
  fallback. Summary rows recorded `monitor_kind=process_monitor`,
  `time_unavailable=true`, populated wall time, and populated process-tree RSS.
- `julia --project=. benchmark/parallel_cost_compare.jl --mode formal --costs cheap --repeats 1 --nlive 40 --dlogz 1.5 --queue-size 2 --threads 2 --nproc 2 --skip-plots --output-dir examples/output/parallel_cost_compare_formal_probe`
  passed as a low-cost formal-mode probe, confirming that formal mode no
  longer fails early when `/usr/bin/time` is absent.
- `julia --project=. benchmark/parallel_cost_compare.jl --mode formal --resume`
  completed the exact full formal command. The summary audit recorded
  `mode=formal`, 18/18 runs with `status=ok`, 9/9 overlay plots with
  `status=ok`, and `monitor_kind=process_monitor` /
  `time_unavailable=true` for all rows because `/usr/bin/time` is unavailable
  on this host.
- `julia --project=. benchmark/parallel_cost_compare.jl --mode formal --costs cheap --repeats 1 --nlive 40 --dlogz 1.5 --queue-size 2 --threads 2 --nproc 2 --skip-plots --output-dir examples/output/parallel_cost_compare_resume_probe`
  passed, and rerunning the same command with `--resume` skipped
  `cheap_julia_repeat1` and `cheap_python_repeat1`. The resumed summary
  recorded `monitor_kind=process_monitor`, `time_unavailable=true`, and
  successful process-tree RSS metrics for both rows.
- `julia --project=. benchmark/air_quality_pe_compare.jl --mode smoke --allow-missing-usr-time --skip-plots --skip-python --output-dir examples/output/air_quality_pe_compare_stage0_smoke`
  passed after the same scheduler CLI fix. The smoke summary recorded
  `julia_repeat1` with `status=ok` and `exit_code=0`.
- `julia --project=. benchmark/air_quality_pe_compare.jl --mode smoke --skip-plots --skip-python --output-dir examples/output/air_quality_pe_compare_monitor_smoke`
  passed without `--allow-missing-usr-time`, using the process-monitor
  fallback.
- `julia --project=. benchmark/air_quality_pe_compare.jl --mode formal --repeats 1 --nlive 40 --dlogz 1.5 --queue-size 2 --threads 2 --nproc 2 --work-repeats 1 --calibration-trials 1 --skip-plots --skip-python --output-dir examples/output/air_quality_pe_compare_formal_probe`
  passed as a low-cost formal-mode probe, confirming that air-quality formal
  mode can also run without `/usr/bin/time`.
- `julia --project=. benchmark/air_quality_pe_compare.jl --mode formal --resume`
  completed the exact full formal air-quality command. The summary audit
  recorded `mode=formal`, 4/4 runs with `status=ok`, 2/2 overlay plots with
  `status=ok`, `bridge_kind=pyjulia` for the Python-side runs,
  `work_repeats=64`, and `monitor_kind=process_monitor` /
  `time_unavailable=true` for all rows because `/usr/bin/time` is unavailable
  on this host.
- `julia --project=. benchmark/air_quality_pe_compare.jl --mode formal --repeats 1 --nlive 40 --dlogz 1.5 --queue-size 2 --threads 2 --nproc 2 --work-repeats 1 --calibration-trials 1 --skip-plots --skip-python --output-dir examples/output/air_quality_pe_compare_resume_probe`
  passed, and rerunning the same command with `--resume` skipped
  `julia_repeat1`. The resumed summary recorded
  `monitor_kind=process_monitor`, `time_unavailable=true`, and successful
  process-tree RSS metrics.
- `julia --project=. examples/pe_parallel_julia.jl --help` passed after adding
  a help path to that benchmark helper.
- `julia --project=. examples/air_quality_pe_julia.jl --help` passed.
- `python3 -m py_compile examples/pe_parallel_python.py examples/pe_parallel_corner.py examples/air_quality_pe_python.py benchmark/parallel_cost_corner.py benchmark/air_quality_corner_overlay.py test/reference/python/generate_reference.py`
  passed.
- `python3 benchmark/parallel_cost_corner.py --help` passed.
- `python3 benchmark/air_quality_corner_overlay.py --help` passed.
- `python3 examples/pe_parallel_python.py --help`,
  `python3 examples/pe_parallel_corner.py --help`, and
  `python3 examples/air_quality_pe_python.py --help` passed. The corner helper
  emitted a third-party ArviZ/pkg_resources deprecation warning during import;
  it did not fail the command.
- The same Python `py_compile` and helper `--help` checks were rerun after the
  dedicated demo workflow additions and passed again; the ArviZ/pkg_resources
  deprecation warning on `examples/pe_parallel_corner.py --help` remains
  non-fatal.
- `OPENBLAS_NUM_THREADS=1 PYTHONPATH=/home/czc/projects/working/dynesty/py python3 examples/air_quality_pe_python.py --bridge-smoke-only --output-dir examples/output/air_quality_bridge_smoke --work-repeats 1 --calibration-trials 1`
  passed. The metadata recorded `status=ok`, `bridge_kind=pyjulia`,
  `likelihood_call_count=1`, and a finite Julia likelihood value
  (`-10624.004050122414`). PyJulia emitted startup import-conflict warnings for
  `eval`/`include`; they did not fail the bridge check.
- `git diff --check` passed after formatter normalization.

Still required before a future full-project completion commit:

- Continue any later feature-gap work from a clean worktree and repeat the
  validation gates before committing.

## Commit List

- `1026552` `Complete Julia-native feature gap pass`

## Cleanup Log

- Removed accidental temporary file `docs/api_parallel.tmp`.
- Removed generated smoke output directories
  `examples/output/parallel_cost_compare_stage0_smoke` and
  `examples/output/air_quality_pe_compare_stage0_smoke` after recording their
  pass/fail summaries.
- Removed generated process-monitor probe output directories
  `examples/output/parallel_cost_compare_monitor_smoke`,
  `examples/output/parallel_cost_compare_formal_probe`,
  `examples/output/air_quality_pe_compare_monitor_smoke`, and
  `examples/output/air_quality_pe_compare_formal_probe` after recording their
  pass/fail summaries.
- Removed generated `Manifest.toml`, `benchmark/Manifest.toml`, and
  `docs/Manifest.toml` after package, benchmark, and docs validation. These
  remain intentionally uncommitted.
- Removed generated `docs/build` after docs validation.
- Removed Python `__pycache__` directories generated by helper `py_compile`
  checks under `benchmark/`, `examples/`, and `test/reference/python/`.
- Removed full formal benchmark output directories under `examples/output/`
  after recording the exact summary audits. The formal output directories were
  35M for `parallel_cost_compare` and 8.7M for `air_quality_pe_compare`; they
  remain intentionally uncommitted.
- Deleted obsolete pre-existing untracked planning prompts:
  `FULL_CHAIN_PARALLEL_GOAL_PROMPT.md`,
  `PARALLEL_COST_BENCHMARK_GOAL_PROMPT.md`,
  `PARALLEL_REFINEMENT_GOAL_PROMPT.md`,
  `REALISTIC_AIR_QUALITY_PE_GOAL_PROMPT.md`,
  `SAMPLER_PARALLEL_GOAL_PROMPT.md`, and `TEST_REPORT_GOAL_PROMPT.md`.
- Deleted obsolete pre-existing experimental helper files
  `examples/pe_compare_julia.jl` and `examples/pe_compare_python.py`; the
  maintained replacements are `examples/pe_parallel_julia.jl`,
  `examples/pe_parallel_python.py`, and the formal benchmark runners.
- Submitted `PYTHON_FEATURE_GAP_COMPLETION_GOAL_PROMPT.md` with the audit as
  the active continuation contract.

## Current Summary

The pure Julia-native API cleanup is implemented; dedicated Python demo
workflow examples for linear regression, exponential wave, loggamma mixtures,
noisy-likelihood reweighting, and the hyper-pyramid diagnostic are now present
and smoke-tested. Default package tests, docs build, helper script checks, core
benchmark smoke, bounded BenchmarkTools suite execution, low-cost formal
benchmark resume probes, and the exact full formal benchmark commands pass. The
validated stage is committed, generated artifacts are cleaned, and the
post-commit worktree check is clean.
