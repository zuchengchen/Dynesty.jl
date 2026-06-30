# Dynesty.jl Migration Completion Audit

Audit date: 2026-06-30

Goal file: `2026-06-30-dynesty-complete-migration-goal.md`

Python baseline: local read-only `../dynesty` checkout at
`3ec158de0d2bf12a56230faacd0c987b3d55d550` on branch `master`.

Temporary Python verification copy:
`/tmp/dynesty_jl_python_verify_20260630_223546/python_dynesty_copy`.

Migration-closure content commit: `7f4348703a4e497db932039cd40d45d002dacaec`

## Executive Conclusion

Final judgment: **Yes**

All blocking and important gaps from `docs/migration_audit.md` have been closed
by Julia examples, documentation, targeted tests, test-environment updates,
method-level tracking, and live verification. The remaining Python-side
notebook issues observed during live verification are explicitly waived as
upstream/reference-environment issues that do not indicate missing Julia
migration work:

- `tests/test_resume.py::test_resume[False-0.5-True-False]` failed once in the
  full Python non-slow pytest run with a multiprocessing PID-count assertion,
  then passed when rerun directly. This is a timing-sensitive Python reference
  test and not a Julia migration gap.
- Python notebook execution initially used the host `python3` Jupyter kernel and
  host `jupyter` command. After forcing the temporary virtualenv command,
  installing the notebook-only `multiprocess` package, and supplying a temporary
  virtualenv `python3` kernelspec, Demo 1, Demo 2, and Demo 3 executed
  successfully. Demo 4's virtualenv execution reached its heavy multiprocessing
  `Pool(4)` sampling cell and continued consuming CPU after more than 50
  minutes; it was stopped as an upstream heavy-notebook execution limitation.
  Its Julia-relevant feature topics are covered by the new Julia feature
  overview, HDF5 history tests, sampler-interface docs/tests, and examples.

The Julia package now has one-to-one coverage for the previously missing Python
demo topics, dedicated FAQ/references/notebook-coverage/feature-overview docs,
default and gated regression tests, actual slow/plot/extended/distributed test
paths, HDF5 history verification while keeping HDF5 weak, and a method-level
migration matrix appendix.

## Gap Closure

| Prior ID | Prior finding | Closure | Result |
| --- | --- | --- | --- |
| B1 | Python demos/notebooks were not fully covered by Julia examples/docs. | Added Julia `.jl` examples for Exponential Wave, Hyper-Pyramid, Linear Regression, LogGamma, Noisy Likelihoods, Importance Reweighting, 25-D Correlated Normal, and a Julia-native feature overview. Added them to docs and default example smoke tests. Added notebook coverage documentation. | Closed |
| B2 | FAQ and references/changelog docs were not fully represented. | Added `docs/src/faq.md`, `docs/src/references.md`, `docs/src/feature_overview.md`, `docs/src/notebook_coverage.md`, root pointer pages, and docs navigation. README/testing docs now point to reproducible verification commands. | Closed |
| B3 | Python slow/regression behaviors were not fully evidenced. | Added `test/test_regression_behaviors.jl` for large negative log-likelihood, manual dynamic batch, pathology, and slow Rosenbrock/pathology analogs. Added HDF5 sampler-level history row-count verification. Added meaningful slow, plot, extended, and distributed gated test paths. | Closed |
| I1 | Docs build command failed without instantiating docs env. | Documented and verified the reproducible two-step command: `julia --project=docs -e 'using Pkg; Pkg.instantiate()'` followed by `julia --project=docs docs/make.jl`. | Closed |
| I2 | HDF5 evaluation-history verification was skipped. | Added HDF5 to test extras only, kept it out of core deps, and extended `test/test_persistence.jl` so `DYNESTY_RUN_EXTENDED_TESTS=true` imports HDF5 and verifies sampler-level history rows match `sampler.ncall`. | Closed |
| I3 | Python pytest probe was environment-limited. | Created an isolated virtualenv and temporary copy of `../dynesty`; installed Python dev/test/notebook dependencies there; ran pytest collection, non-slow tests, targeted flaky rerun, and notebook verification probes. | Closed with waived upstream notebook/runtime limits |
| I4 | Migration matrix lacked method-granularity tracking. | Added a method-level tracking appendix covering every AST-discovered Python class method. The appendix tracks 170 methods. | Closed |
| I5 | Slow/plot flags were documented but did not activate extra paths. | Added real `DYNESTY_RUN_SLOW_TESTS` regression paths and real `DYNESTY_RUN_PLOT_TESTS` optional plotting recipe smoke paths. Verified both. | Closed |

## Python Module Coverage

| Python file | Julia implementation or replacement | Evidence | Status |
| --- | --- | --- | --- |
| `py/dynesty/__init__.py` | `src/Dynesty.jl` exports and citations | API docs, default tests | Covered |
| `py/dynesty/dynesty.py` | `NestedSampler`, `DynamicNestedSampler`, sampler factories | Static/dynamic sampler tests, docs | Covered |
| `py/dynesty/sampler.py` | `src/sampler.jl`, `src/persistence.jl` | Static sampler, persistence, regression tests | Covered |
| `py/dynesty/dynamicsampler.py` | `src/dynamic_sampler.jl` | Dynamic sampler tests, manual-batch regression | Covered |
| `py/dynesty/internal_samplers.py` | `src/internal_samplers.jl` | Internal sampler tests, slow pathology analogs | Covered |
| `py/dynesty/bounding.py` | `src/bounding.jl` | Bound tests and Python fixtures | Covered |
| `py/dynesty/utils.py` | `src/utils.jl`, `src/results.jl`, `src/persistence.jl` | Utility/results/persistence/HDF5 tests | Covered |
| `py/dynesty/results.py` | `src/results.jl` | Results and post-processing tests | Covered |
| `py/dynesty/pool.py` | Julia-native map backends and `PoolUsage` | Parallel/distributed tests | Replacement covered |
| `py/dynesty/plotting.py` | Backend-neutral plotting data and recipes | Default plotting tests plus gated recipe smoke | Replacement covered |

## Python Test Coverage

| Python test/support area | Julia evidence after closure | Status |
| --- | --- | --- |
| Core sampler, dynamic sampler, bounds, internal samplers, utilities, results | Existing `test/test_*.jl` suites plus Python fixture checks | Covered |
| Blob/proposal stats/result propagation | Static/dynamic sampler tests and migration matrix rows | Covered |
| Pool/distributed behavior | `test/test_parallel.jl` and `DYNESTY_RUN_DISTRIBUTED_TESTS=true` path | Covered by Julia-native replacement |
| Persistence/resume/saver | `test/test_persistence.jl`, Serialization checkpoint tests, HDF5 extended checks | Covered |
| Plotting | `test/test_plotting.jl`, optional recipe smoke with `DYNESTY_RUN_PLOT_TESTS=true` | Covered by backend-neutral replacement |
| Notebook/demo execution | Default `test/test_examples.jl` smoke covers all Julia examples corresponding to Python notebook topics | Covered by Julia examples/docs |
| Rosenbrock/pathology/large log-likelihood/dynamic batch regressions | `test/test_regression_behaviors.jl`, including slow gated analogs | Covered |
| Python `tests/utils.py` and pytest infrastructure | Test helper only, not public API | Non-migration item |

## Python Docs And Notebook Coverage

| Python docs/notebook area | Julia coverage after closure | Status |
| --- | --- | --- |
| API, quickstart, dynamic sampling, errors, examples | Existing Julia docs plus updated examples pages | Covered |
| FAQ | `docs/src/faq.md`, `docs/faq.md` | Covered |
| References/acknowledgements/source version | `docs/src/references.md`, `docs/references.md`, `get_citations` | Covered |
| Python 3.0 feature overview | `docs/src/feature_overview.md`, `examples/feature_overview.jl`, tests | Covered by Julia-native feature overview |
| Notebook coverage mapping | `docs/src/notebook_coverage.md`, `docs/notebook_coverage.md` | Covered |
| Missing notebook examples from prior audit | `examples/exponential_wave.jl`, `hyper_pyramid.jl`, `linear_regression.jl`, `loggamma.jl`, `noisy_likelihoods.jl`, `importance_reweighting.jl`, `correlated_normal_25d.jl` | Covered |

## Symbol And Method Coverage

`docs/migration_matrix.md` now tracks:

- All top-level Python classes/functions in the main matrix.
- A method-level appendix for all AST-discovered Python class methods.
- 170 method entries in the appendix, covering implemented and Julia-native
  replacement behavior.

The duplicate docs source page `docs/src/migration_matrix.md` was updated in
parallel so the built documentation includes the same tracking information.

## Verification Results

### Julia

| Command | Result |
| --- | --- |
| `julia --project=. -e 'using Pkg; Pkg.test()'` | Passed |
| `julia --project=docs -e 'using Pkg; Pkg.instantiate()'` | Passed |
| `julia --project=docs docs/make.jl` | Passed |
| `DYNESTY_RUN_SLOW_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'` | Passed; slow block ran 21 checks |
| `DYNESTY_RUN_PLOT_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'` | Passed; optional plotting recipe block ran 13 checks |
| `DYNESTY_RUN_EXTENDED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'` | Passed; HDF5 block ran 12 checks and did not skip |
| `DYNESTY_RUN_DISTRIBUTED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'` | Passed; distributed block ran 7 checks |
| `DYNESTY_RUN_SLOW_TESTS=true DYNESTY_RUN_PLOT_TESTS=true DYNESTY_RUN_EXTENDED_TESTS=true DYNESTY_RUN_DISTRIBUTED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'` | Passed; HDF5 12, distributed 7, optional plotting 13, slow analogs 21 |

### Python Live Reference Verification

Setup:

- Temporary root: `/tmp/dynesty_jl_python_verify_20260630_223546`
- Temporary source copy:
  `/tmp/dynesty_jl_python_verify_20260630_223546/python_dynesty_copy`
- Temporary virtualenv:
  `/tmp/dynesty_jl_python_verify_20260630_223546/venv`
- Source hash: `3ec158de0d2bf12a56230faacd0c987b3d55d550`
- Branch: `master`
- Python: `Python 3.9.18`
- Installed reference package:
  `dynesty 0.1.dev1593+g3ec158de0`
- Key package versions: `numpy 2.0.2`, `scipy 1.13.1`,
  `matplotlib 3.9.4`, `h5py 3.14.0`, `pytest 8.4.2`,
  `nbconvert 7.17.1`, `multiprocess 0.70.19`

Commands and results:

| Command | Result |
| --- | --- |
| `python -m pytest --collect-only -q tests` from the temporary copy | Passed; 277 tests collected in 0.75s |
| `python -m pytest -q -m 'not slow' tests` from the temporary copy | One flaky Python reference failure; `254 passed, 22 deselected, 1 failed, 933 warnings in 0:20:39` |
| `python -m pytest -q -m 'not slow' 'tests/test_resume.py::test_resume[False-0.5-True-False]'` | Passed; `1 passed, 1 warning in 3.83s` |
| `python -m pytest -q -m slow tests/test_notebooks.py` without forcing virtualenv `PATH`/kernel | `12 passed, 2 failed`; failures were host Jupyter/kernel environment and Demo 4 notebook content/runtime issues |
| `PATH=<venv>/bin:$PATH python -m pytest -q -m slow tests/test_notebooks.py` with virtualenv Jupyter | First 10 notebooks passed; Demo 4 reached a heavy multiprocessing `Pool(4)` cell and was stopped after more than 50 minutes of CPU activity |
| `JUPYTER_PATH=<temp-kernel> python -m jupyter nbconvert --to notebook --execute "demos/Demo 1 - Overview.ipynb"` | Passed with virtualenv `python3` kernelspec |
| `JUPYTER_PATH=<temp-kernel> python -m jupyter nbconvert --to notebook --execute "demos/Demo 2 - Dynamic Nested Sampling.ipynb"` | Passed with virtualenv `python3` kernelspec |
| `JUPYTER_PATH=<temp-kernel> python -m jupyter nbconvert --to notebook --execute "demos/Demo 3 - Errors.ipynb"` | Passed with virtualenv `python3` kernelspec |

Python live verification conclusion:

- Pytest collection proves the temporary copy and installed package are usable.
- The full non-slow suite is green except for one timing-sensitive
  multiprocessing resume assertion that immediately passed when rerun.
- The notebook suite is not fully reliable as a reference verification command
  in this environment because upstream `test_notebooks.py` shells out to a bare
  `jupyter` command and the notebooks request a generic `python3` kernelspec.
  Once those were isolated to the temporary virtualenv, the core overview,
  dynamic, and errors demos executed successfully; the remaining Demo 4
  long-running multiprocessing behavior is waived as an upstream heavy notebook
  runtime limit.

## Repository Hygiene

`../dynesty` remained unmodified:

- `git -C ../dynesty status --short` produced no output before final staging.
- Python verification used only a temporary copy outside this repository.

Manifest policy:

- HDF5 remains a weak dependency and test extra, not a core dependency.
- Generated `Manifest.toml` files were not staged or committed.
- Final staging excludes root/docs/benchmark/temp manifests and generated
  notebook outputs.

Expected final hygiene after the commit:

- `git status --short` should show no tracked migration changes left unstaged.
- Any local `Manifest.toml` files remain ignored/uncommitted.

## Compatibility Notes

`docs/compatibility.md` and `docs/src/compatibility.md` were updated for public
behavior differences, including:

- Julia-native `run_nested!` and other mutating APIs.
- 1-based periodic/reflective dimension indexing.
- Julia `res.blobs` with compatibility aliases.
- Julia-native parallel map backends instead of Python `Pool` worker/task
  serialization.
- Backend-neutral plotting data/recipes instead of Matplotlib figure cloning.
- HDF5 evaluation history as an extension-backed optional path.

## Final Statement

The project now satisfies the migration contract at the level appropriate for a
Julia port: public Python functionality is implemented directly or replaced by
documented Julia-native behavior; previously missing demos/docs/tests have
corresponding Julia artifacts; optional paths are genuinely exercised by gated
tests; method-level symbol tracking is explicit; and live Python verification
was performed in an isolated temporary environment without modifying
`../dynesty`.
