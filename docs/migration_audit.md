# Dynesty.jl Migration Completeness Audit

Audit date: 2026-06-30

Goal file: `2026-06-30-dynesty-migration-audit-goal.md`

Python baseline: local read-only `../dynesty` checkout only.

## Executive Conclusion

Final judgment: **No**

The current Julia package has strong evidence for a broad core migration:

- All 10 Python core module files under `../dynesty/py/dynesty/*.py` have Julia
  implementation or Julia-native replacement coverage.
- All Python top-level classes and functions discovered by AST are represented
  directly in `docs/migration_matrix.md`; class methods are covered indirectly
  by class-level matrix rows.
- The default Julia test suite passed: 929/929 checks.
- Extended Julia test commands for slow, plot, extended, distributed, and
  combined flags all exited successfully.
- Distributed backend tests ran and passed.
- Documentation can build successfully after the docs environment is
  instantiated in a temporary copy.

However, the migration cannot be declared complete under the full
`CODEX_GOAL_PROMPT.md` contract because the evidence also shows blocking gaps:

- Several Python demo/notebook topics do not have clear one-to-one Julia
  example or documentation coverage, even though the migration contract says
  docs, demos, and notebooks must be covered by final deliverables.
- Python docs pages for FAQ and references/changelog are only partially
  represented in Julia docs.
- Several Python slow/regression behavior references, especially the
  Rosenbrock statistical test and full notebook execution, do not have direct
  Julia test or fixture evidence.
- The specified docs build command failed in the current checkout because the
  docs environment was not instantiated.
- Optional HDF5 evaluation-history verification was skipped in the Julia
  extended test run because HDF5.jl was unavailable in the test environment.
- Python pytest collection/execution from a temporary source copy could not run
  because the active Python environment lacks `pytest`.

The result is best summarized as: **core package migration appears mostly
implemented and well tested, but complete migration-contract closure is not
proven and is contradicted by docs/demo/test evidence gaps.**

## Audit Inputs

Primary contract and local evidence:

- `CODEX_GOAL_PROMPT.md`
- `AGENTS.md`
- `Project.toml`
- `README.md`
- `src/*.jl`
- `ext/*.jl`
- `test/*.jl`
- `test/reference/python/*`
- `docs/migration_matrix.md`
- `docs/compatibility.md`
- `docs/source_snapshot.md`
- `docs/src/**/*.md`
- `docs/*.md`
- `examples/*.jl`
- `benchmark/*`
- `../dynesty/py/dynesty/*.py`
- `../dynesty/tests/*.py`
- `../dynesty/docs`
- `../dynesty/demos`

The original `../dynesty` checkout was not modified. A copy was made under
`/tmp/dynesty_jl_migration_audit/python_dynesty_copy` for Python-side probes.

## Inventory Summary

| Category | Count | Notes |
| --- | ---: | --- |
| Python core modules | 10 | `../dynesty/py/dynesty/*.py` |
| Python tests/support files | 26 | `../dynesty/tests/*.py`, including `conftest.py` and `utils.py` |
| Python docs pages | 10 | `../dynesty/docs/source/*.rst` |
| Python notebooks/demos | 14 | `../dynesty/demos/*.ipynb` |
| Julia source/ext files | 11 | `src/*.jl`, `ext/*.jl` |
| Julia test entry/files | 15 | `test/test_*.jl` plus `test/runtests.jl` |
| Julia docs pages | 31 | `docs/*.md`, `docs/src/**/*.md` |
| Julia examples | 10 | `examples/*.jl`, excluding generated output |
| Python fixture files | 6 | `test/reference/python/fixtures/*` |
| Migration matrix rows | 104 | 90 implemented, 14 replacement |

## Gap Severity

### Blocking

| ID | Area | Evidence | Why it blocks completion |
| --- | --- | --- | --- |
| B1 | Python demos/notebooks are not fully covered by Julia examples/docs | Python has 14 notebooks. Julia has 7 smoke-tested examples plus 3 PE comparison scripts. No clear Julia coverage was found for Exponential Wave, Hyper-Pyramid, Linear Regression, LogGamma, Noisy Likelihoods, and a dedicated "What's new in 3.0" demo. | The migration contract explicitly says docs, demos, and notebooks must be covered by final deliverables, not marked as future work. |
| B2 | Python docs pages are not fully represented | No obvious Julia FAQ page was found. References/changelog coverage is partial: citations exist through `get_citations`, but there is no dedicated references/changelog page equivalent to Python `docs/source/index.rst` and `docs/source/references.rst`. | The contract requires docs coverage, not only core API coverage. |
| B3 | Python slow/regression behavior references are not fully evidenced | `test_rosenbrock.py` performs a slow repeated Rosenbrock posterior validation. `test_notebooks.py` executes every Python notebook. Several `test_misc.py` regression paths, including dynamic batch edge cases and HDF5 evaluation-history completeness, have partial or environment-limited Julia evidence. | The contract requires every migrated function/type to have appropriate tests and Python cross-checks wherever meaningful. These behaviors are not all directly evidenced. |

### Important

| ID | Area | Evidence | Impact |
| --- | --- | --- | --- |
| I1 | Docs build command in the goal failed as written | `julia --project=docs docs/make.jl` failed because Documenter was not installed in the docs environment. A temporary copy succeeded after `Pkg.instantiate()`. | Completion cannot be judged `Yes` under the user's rule that Julia tests/docs build failures cap the result. The content appears buildable, but the specified command is not self-contained in the current environment. |
| I2 | HDF5 evaluation-history extended verification was skipped | `DYNESTY_RUN_EXTENDED_TESTS=true` passed, but logged "Skipping HDF5 evaluation-history extension test" because HDF5.jl was not available. | The HDF5 extension exists, but the optional path was not actually verified in this audit run. |
| I3 | Python pytest probe was environment-limited | Temporary-copy `python -m pytest --collect-only -q tests` failed with `No module named pytest`. | Python live test parity could not be used as evidence. Static inspection and committed fixtures remain available. |
| I4 | Migration matrix is top-level complete but not method-row complete | AST found 272 top-level/class/method symbols. Matrix has 104 rows and directly covers all top-level classes/functions; 168 class methods are only indirectly covered by class rows. | If "one row per Python symbol" is interpreted literally to include methods, the matrix is too coarse. This is not direct implementation evidence of missing behavior, but it is a tracking gap. |
| I5 | Extended flag documentation is broader than implemented flag handling | Source scan found test code consuming `DYNESTY_RUN_EXTENDED_TESTS` and `DYNESTY_RUN_DISTRIBUTED_TESTS`; `DYNESTY_RUN_SLOW_TESTS` and `DYNESTY_RUN_PLOT_TESTS` are documented but not consumed by tests. | The slow/plot verification commands passed, but they did not appear to activate extra test paths. |

### Minor

| ID | Area | Evidence | Impact |
| --- | --- | --- | --- |
| M1 | Python `tests/utils.py` has no Julia equivalent | It is a Python test helper file, not a user-facing dynesty module. | Fine as long as the audit treats it as support code, not migrated API. |
| M2 | Notebook image assets are not mirrored one-to-one | Python docs contain many generated images; Julia docs use local markdown/examples/test reports instead. | Usually acceptable for Julia-native docs, but it reduces one-to-one documentation parity. |
| M3 | Plotting tests are backend-neutral | Julia tests exercise RecipesBase/data objects, not a full Plots.jl visual rendering suite by default. | Consistent with the package design, but it is not identical to Python Matplotlib test coverage. |

## Recommended Repair Order

1. Add or document Julia coverage for the missing Python demo/notebook topics:
   Exponential Wave, Hyper-Pyramid, Linear Regression, LogGamma, Noisy
   Likelihoods, Importance Reweighting as an example, 25-D Correlated Normal,
   and the dynesty 3.0 feature overview where applicable to Julia.
2. Add Julia documentation pages or sections for FAQ, references/acknowledgements,
   and changelog/source-version context, or explicitly document why a Julia-native
   replacement is sufficient.
3. Add targeted Julia regression tests or fixtures for high-value Python
   behavior references not currently evidenced: Rosenbrock posterior validation,
   notebook/demo execution parity, HDF5 evaluation-history completeness, dynamic
   batch edge cases, and large negative log-likelihood behavior.
4. Ensure HDF5.jl is available in the appropriate extended test environment, or
   add a documented command that instantiates the optional dependency before
   running the HDF5 extension checks.
5. Make the docs build command self-contained in developer instructions, or
   update the required verification command to include `Pkg.instantiate()` for
   the docs environment.
6. Decide whether migration matrix rows should track class methods individually.
   If yes, expand `docs/migration_matrix.md`; if no, document the top-level/class
   granularity policy.
7. Either implement consumers for `DYNESTY_RUN_SLOW_TESTS` and
   `DYNESTY_RUN_PLOT_TESTS`, or revise the testing docs so those flags are not
   advertised as active test switches.

## Python Core Module Coverage

| Python file | Julia implementation/replacement | Julia tests | Julia docs | Status |
| --- | --- | --- | --- | --- |
| `py/dynesty/__init__.py` | `src/Dynesty.jl` | `test/runtests.jl` | `docs/src/api.md` | Covered for exports/citations/package API. |
| `py/dynesty/dynesty.py` | `src/Dynesty.jl`, `src/sampler.jl`, `src/dynamic_sampler.jl` | `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl` | `docs/src/api/samplers.md`, `README.md` | Covered by Julia-native `NestedSampler`, `DynamicNestedSampler`, factories, and citations. |
| `py/dynesty/sampler.py` | `src/sampler.jl`, `src/persistence.jl` | `test/test_static_sampler.jl`, `test/test_persistence.jl` | `docs/src/api/samplers.md`, `docs/src/manual/getting-started.md` | Covered for static sampler engine, live points, bound updates, result extraction, and checkpoint restore. |
| `py/dynesty/dynamicsampler.py` | `src/dynamic_sampler.jl`, `src/sampler.jl` | `test/test_dynamic_sampler.jl` | `docs/src/dynamic.md`, `docs/src/manual/dynamic.md` | Covered for baseline run, batch run, dynamic weighting/stopping, and result merging. |
| `py/dynesty/internal_samplers.py` | `src/internal_samplers.jl` | `test/test_internal_samplers.jl` | `docs/src/api/internal-samplers.md` | Covered for uniform, unit-cube, random-walk, slice, random-slice kernels. |
| `py/dynesty/bounding.py` | `src/bounding.jl` | `test/test_bounding_unitcube_ellipsoid.jl`, `test/test_bounding_friends.jl` | `docs/src/api/bounds.md` | Covered for UnitCube, Ellipsoid, MultiEllipsoid, RadFriends, SupFriends, and helper functions. |
| `py/dynesty/utils.py` | `src/utils.jl`, `src/results.jl`, `src/persistence.jl` | `test/test_utils.jl`, `test/test_results.jl`, `test/test_results_postprocess.jl`, `test/test_persistence.jl` | `docs/src/api/utilities.md`, `docs/src/api/results.md`, `docs/src/persistence.md` | Broadly covered; HDF5 optional path was environment-limited in this audit. |
| `py/dynesty/results.py` | `src/results.jl` | `test/test_results.jl`, `test/test_results_postprocess.jl` | `docs/src/api/results.md` | Covered through `Results` and post-processing APIs. |
| `py/dynesty/pool.py` | `src/parallel.jl`, sampler parallel hooks | `test/test_parallel.jl`, `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl` | `docs/src/api/parallel.md`, `docs/compatibility.md` | Covered by Julia-native backends; distributed tests passed. |
| `py/dynesty/plotting.py` | `src/plotting.jl` | `test/test_plotting.jl` | `docs/src/api/plotting.md`, `docs/src/manual/plotting.md` | Covered by backend-neutral RecipesBase/data replacement; not a Matplotlib clone. |

## Symbol Matrix Check

AST scan of `../dynesty/py/dynesty/*.py` found:

- 104 top-level classes/functions.
- 168 class methods.
- 272 total top-level/class/method symbols.

`docs/migration_matrix.md` contains 104 rows:

- 90 `implemented`
- 14 `replacement`
- Grade counts: 47 A, 34 B, 23 C
- 43 rows reference actual fixture files
- 18 rows use statistical/invariant fixture language
- 43 rows say fixtures are not needed

Result:

- Direct matrix coverage for all top-level Python classes/functions: **pass**.
- Direct matrix coverage for each class method: **not present**.
- Implementation coverage can still be valid through class-level rows, but this
  is a tracking granularity gap if the contract is read literally as "one row
  per Python symbol", including methods.

## Python Test Coverage Map

| Python test/support file | Julia/fixture coverage | Status |
| --- | --- | --- |
| `tests/conftest.py` | `test/reference/python/generate_reference.py`, `test/reference/python/README.md` | Support coverage; no direct Julia runtime equivalent needed. |
| `tests/test_blob.py` | `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl`, `test/test_utils.jl` | Covered for blob return paths and result propagation. |
| `tests/test_bound_interface.py` | `test/test_bounding_unitcube_ellipsoid.jl`, `test/test_bounding_friends.jl`, `test/test_static_sampler.jl` | Covered for built-in and abstract bound interface. |
| `tests/test_dyn.py` | `test/test_dynamic_sampler.jl`, `test/reference/python/fixtures/dynamic_core.json` | Covered for dynamic helpers and run loop. |
| `tests/test_egg.py` | `test/test_examples.jl`, `examples/eggbox.jl` | Covered by smoke example; not full notebook-level visual parity. |
| `tests/test_ellipsoid.py` | `test/test_bounding_unitcube_ellipsoid.jl`, `test/reference/python/fixtures/bounding_core.json` | Covered. |
| `tests/test_gau.py` | `test/test_examples.jl`, `examples/gaussian.jl`, `examples/high_dimensional_gaussian.jl` | Covered by examples and sampler invariants. |
| `tests/test_highdim.py` | `test/test_examples.jl`, `examples/high_dimensional_gaussian.jl` | Covered by smoke example. |
| `tests/test_misc.py` | `test/test_utils.jl`, `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl`, `test/test_results_postprocess.jl`, `test/test_persistence.jl` | Partially covered; some regression cases such as HDF5 history completeness and dynamic batch edge cases need stronger direct evidence. |
| `tests/test_ncdim.py` | `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl` | Covered for constructor and sampler behavior. |
| `tests/test_notebooks.py` | `test/test_examples.jl`, `docs/examples.md`, `examples/*.jl` | Not complete. Python executes every notebook; Julia smoke-tests only selected `.jl` examples. |
| `tests/test_pathology.py` | `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl`, `test/test_examples.jl` | Partial. No direct evidence for the exact Python `1/|x|` pathology matrix across static/dynamic and sample modes. |
| `tests/test_periodic.py` | `test/test_utils.jl`, `test/test_internal_samplers.jl`, `test/test_static_sampler.jl` | Covered with documented 1-based Julia index behavior. |
| `tests/test_plateau.py` | `test/test_static_sampler.jl`, `src/sampler.jl` | Covered by implementation/test references, but evidence is less direct than Python test naming. |
| `tests/test_plot.py` | `test/test_plotting.jl`, `test/reference/python/fixtures/plotting_core.json` | Covered by backend-neutral plotting data and recipes. |
| `tests/test_pool.py` | `test/test_parallel.jl`, `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl` | Covered by Julia map backends; distributed path passed. |
| `tests/test_printing.py` | `test/test_utils.jl`, `test/test_static_sampler.jl` | Covered for Julia console/progress callbacks. |
| `tests/test_proposal_stats.py` | `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl` | Covered for stored proposal stats and result propagation. |
| `tests/test_reflect.py` | `test/test_utils.jl`, `test/test_internal_samplers.jl`, `test/test_static_sampler.jl` | Covered with 1-based Julia index behavior. |
| `tests/test_resume.py` | `test/test_persistence.jl`, `test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl` | Covered for Julia Serialization checkpoint semantics. |
| `tests/test_rosenbrock.py` | No direct Julia test/example found | Blocking evidence gap for the slow repeated Rosenbrock posterior validation. |
| `tests/test_sampler_interface.py` | `test/test_static_sampler.jl`, `test/test_internal_samplers.jl` | Covered for factories/interfaces. |
| `tests/test_sampling.py` | `test/test_internal_samplers.jl`, `test/test_static_sampler.jl` | Covered for proposal kernels and static integration. |
| `tests/test_saver.py` | `test/test_persistence.jl` | Covered for Julia persistence replacement. |
| `tests/test_volume.py` | `test/test_utils.jl`, `test/test_results_postprocess.jl` | Covered for integrals/log-volume helpers. |
| `tests/utils.py` | No Julia artifact | Python test helper only; not a migrated API requirement. |

## Python Docs Coverage Map

| Python docs page | Julia coverage | Status |
| --- | --- | --- |
| `docs/source/api.rst` | `docs/src/api.md`, `docs/src/api/*.md` | Covered. |
| `docs/source/crashcourse.rst` | `docs/src/quickstart.md`, `docs/src/manual/getting-started.md` | Covered conceptually. |
| `docs/source/dynamic.rst` | `docs/src/dynamic.md`, `docs/src/manual/dynamic.md` | Covered. |
| `docs/source/errors.rst` | `docs/src/errors.md`, `docs/src/manual/results-persistence.md` | Covered. |
| `docs/source/examples.rst` | `docs/src/examples.md`, `docs/examples.md`, `examples/*.jl` | Partial; not all listed Python examples have Julia counterparts. |
| `docs/source/faq.rst` | No obvious `docs/src/faq.md` or equivalent FAQ page | Blocking documentation gap. |
| `docs/source/index.rst` | `docs/src/index.md`, `README.md` | Partial; overview covered, Python changelog not mirrored. |
| `docs/source/overview.rst` | `README.md`, `docs/src/index.md`, `docs/src/quickstart.md` | Covered conceptually. |
| `docs/source/quickstart.rst` | `docs/src/quickstart.md`, `docs/src/manual/getting-started.md` | Covered for core usage; Python-specific multiprocessing/history sections are covered elsewhere or partially. |
| `docs/source/references.rst` | `get_citations`, `docs/src/index.md` | Partial; citations exist, but no dedicated references/acknowledgements page was found. |

## Python Demo/Notebook Coverage Map

| Python notebook | Static notebook contents | Julia coverage | Status |
| --- | --- | --- | --- |
| `demos/Demo 1 - Overview.ipynb` | 89 cells, overview, results, extending run, parallel, checkpointing | `examples/overview.jl`, quickstart/manual docs, parallel/persistence docs | Partial to covered; not a cell-by-cell replacement. |
| `demos/Demo 2 - Dynamic Nested Sampling.ipynb` | 52 cells, dynamic sampling, stop criteria, visualization | `examples/dynamic_nested_sampling.jl`, dynamic docs | Covered conceptually. |
| `demos/Demo 3 - Errors.ipynb` | 68 cells, error analysis, jitter/resample/bootstrap | `examples/errors.jl`, errors/results docs | Covered conceptually. |
| `demos/Demo 4 - What is new in 3.0.ipynb` | 26 cells, proposal stats, HDF5 history, sampler interface, custom bounds/samplers | No dedicated Julia demo found; pieces in tests/docs | Partial. Contract coverage is not clear. |
| `demos/Examples -- 200-D Multivariate Normal.ipynb` | 20 cells | `examples/high_dimensional_gaussian.jl` | Covered conceptually. |
| `demos/Examples -- 25-D Correlated Normal.ipynb` | 15 cells | `examples/gaussian.jl`, `examples/high_dimensional_gaussian.jl` | Partial; no explicit 25-D correlated normal example found. |
| `demos/Examples -- Eggbox.ipynb` | 19 cells | `examples/eggbox.jl` | Covered. |
| `demos/Examples -- Exponential Wave.ipynb` | 17 cells | No obvious Julia example | Blocking demo gap. |
| `demos/Examples -- Gaussian Shells.ipynb` | 47 cells | `examples/gaussian_shells.jl` | Covered conceptually. |
| `demos/Examples -- Hyper-Pyramid.ipynb` | 24 cells | No obvious Julia example | Blocking demo gap. |
| `demos/Examples -- Importance Reweighting.ipynb` | 27 cells | `reweight_run` tests/docs; no obvious example file | Important demo gap. |
| `demos/Examples -- Linear Regression.ipynb` | 15 cells | No obvious Julia example | Blocking demo gap. |
| `demos/Examples -- LogGamma.ipynb` | 18 cells | No obvious Julia example | Blocking demo gap. |
| `demos/Examples -- Noisy Likelihoods.ipynb` | 44 cells | No obvious Julia example | Blocking demo gap. |

## Compatibility Notes Check

`docs/compatibility.md` documents the major intentional Julia-native
differences found during the audit:

- Mutating `!` APIs such as `run_nested!`.
- 1-based periodic/reflective dimension indices.
- `copy_inputs=false` default.
- `res.blobs` instead of Python `res.blob`.
- Result alias behavior.
- Julia-native parallel map backends replacing Python `Pool`.
- Parallel reproducibility scope.
- RecipesBase plotting replacement.
- `.jls` checkpoints, `.jld2` result archives, optional HDF5 history.
- SupFriends center behavior.
- Bound/bootstrap and clustering differences.
- Random trajectory non-equivalence.
- Dynamic stopping Monte Carlo RNG differences.

The compatibility notes are broadly aligned with the implementation and tests.
The main missing compatibility discussion is not an API difference but an
artifact coverage issue: Python FAQ/changelog/notebook examples are not fully
represented in Julia deliverables.

## Persistence, Parallelism, Plotting, Examples, Benchmarks

| Contract area | Evidence | Status |
| --- | --- | --- |
| Results archive persistence | `src/persistence.jl`, `test/test_persistence.jl` | Covered; default tests passed. |
| Sampler checkpoint/restore | `src/persistence.jl`, sampler snapshot/restore tests | Covered for Julia Serialization semantics. |
| HDF5 evaluation history | `ext/DynestyHDF5Ext.jl`, `test/test_persistence.jl` | Implemented, but extended runtime check skipped because HDF5.jl was missing. |
| Parallelism | `src/parallel.jl`, `test/test_parallel.jl`, sampler tests | Covered; distributed tests passed. |
| Plotting | `src/plotting.jl`, `test/test_plotting.jl` | Covered by backend-neutral data/recipe tests. |
| Examples | `examples/*.jl`, `test/test_examples.jl`, `docs/examples.md` | Core examples smoke-tested, but Python notebook topic coverage is incomplete. |
| Benchmarks/performance | `benchmark/*.jl`, `docs/performance.md`, `docs/test_report/*` | Deliverables exist; not exhaustively rerun in this audit. |

## Verification Results

| Command/probe | Result | Notes |
| --- | --- | --- |
| `julia --project=. -e 'using Pkg; Pkg.test()'` | Pass | 929/929 checks, `Dynesty tests passed`. |
| `julia --project=docs docs/make.jl` | Fail | Failed before build: Documenter not installed in docs environment. |
| Temporary copy: `julia --project=docs -e 'using Pkg; Pkg.instantiate()'` then `julia --project=docs docs/make.jl` | Pass | Built docs successfully in `/tmp/dynesty_docs_build_probe/Dynesty.jl`; this did not modify the repository checkout. |
| `DYNESTY_RUN_SLOW_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'` | Pass | 929/929 checks. Source scan found no test consumer for this flag. |
| `DYNESTY_RUN_PLOT_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'` | Pass | 929/929 checks. Source scan found no test consumer for this flag. |
| `DYNESTY_RUN_EXTENDED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'` | Pass with limitation | 929/929 checks, but HDF5 extension test logged a skip because HDF5.jl was unavailable. |
| `DYNESTY_RUN_DISTRIBUTED_TESTS=true julia --project=. -e 'using Pkg; Pkg.test()'` | Pass | 936/936 checks, including `Distributed proposal/evolve queue`. |
| Combined extended flags test | Pass with limitation | 936/936 checks, distributed path passed, HDF5 extension test skipped. |
| Python environment probe | Limited | Python 3.9.18, NumPy 1.21.5, SciPy 1.7.3, dynesty 2.1.2, matplotlib 3.5.1, nbformat 5.10.4 available; `pytest` missing. |
| Temporary-copy `python -m pytest --collect-only -q tests` | Fail/environment-limited | Failed with `/home/czc/opt/miniconda3/bin/python: No module named pytest`. |
| Python notebook static parse | Pass | All 14 notebooks parsed for cell counts/headings. Execution was not attempted because pytest/jupyter execution evidence was already environment-limited. |
| Original `../dynesty` status after probes | Clean | `git -C ../dynesty status --short` returned empty output. |
| Repository change scope | Pass | `git status --short` showed only the previously approved goal file and this audit report as untracked files. No tracked files were modified by the audit. |

## Assumptions and Unknowns

- The audit treats top-level classes/functions as the primary migration-matrix
  symbol granularity, while also noting that class methods are not individually
  row-tracked.
- The audit did not install missing Python or Julia optional dependencies in the
  active repository environment.
- The audit did not rerun benchmark suites, because the goal emphasized
  migration completeness and verification commands rather than performance
  reproduction.
- The audit did not execute Python notebooks because the Python pytest path was
  already blocked by missing `pytest`; static notebook parsing was used instead.

## Final Completion Assessment

`Dynesty.jl` is in a strong state for core package functionality: samplers,
dynamic sampling, bounds, internal samplers, results, persistence, parallelism,
plotting data APIs, examples, fixtures, and Aqua checks all have meaningful
evidence.

It is **not yet complete** under the full migration contract. The remaining
work is mostly closure work around docs/demo/notebook parity and targeted
regression evidence, plus making optional/docs verification reproducible in the
intended environments.
