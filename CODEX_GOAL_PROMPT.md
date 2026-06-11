# Codex Goal Prompt for Dynesty.jl Migration

Copy the section below into Codex Goal mode from `/home/czc/projects/working/dynesty.jl`.

```text
Migrate the adjacent Python dynesty project at ../dynesty into a complete Julia package in the current directory, /home/czc/projects/working/dynesty.jl. Treat ../dynesty as a read-only source reference. Do not modify it, do not git pull it, and do not switch its branch. Build a Julia package named Dynesty that is Julia-native in API design while aligning behavior, algorithms, tests, citations, examples, and documentation with the Python dynesty project.

This is a long-running Goal-mode migration. Work stage by stage. Keep the repository runnable, tested, reviewable, and committed after each completed stage. If an uncertainty affects public API, algorithm scope, dependency strategy, testing standards, persistence semantics, or compatibility behavior, ask exactly one focused question before proceeding. For smaller implementation choices, make a conservative decision consistent with this goal and document it.

Hard requirements:
- Initialize the current directory as a git repository in stage 0.
- Use Julia >= 1.11.
- Create a normal Julia package with module name Dynesty.
- Do not commit Manifest.toml.
- Do not modify ../dynesty.
- Use MIT license attribution from ../dynesty.
- API should be strictly Julia-native, not a mechanical Python signature clone
  and not a Python-compatible alias layer.
- Behavior, algorithms, numerical semantics, and edge cases should align with Python dynesty unless an intentional difference is documented.
- Final completion target is full-project migration, not only the core sampler.
- All Python py/dynesty modules must have Julia equivalents or documented Julia-native replacements.
- plotting.py, pool.py, docs, demos, and notebooks must be covered by final deliverables, not merely marked as future work.
- Every migrated symbol must be tracked in docs/migration_matrix.md.
- Every migrated function/type must have an appropriate test according to the A/B/C test policy below.
- Python cross-check fixtures are required wherever meaningful.
- Run relevant tests before every stage commit.
- Commit automatically after each stage that passes its defined checks.

Source project:
- Source path: ../dynesty
- Core Python modules:
  - ../dynesty/py/dynesty/__init__.py
  - ../dynesty/py/dynesty/dynesty.py
  - ../dynesty/py/dynesty/sampler.py
  - ../dynesty/py/dynesty/dynamicsampler.py
  - ../dynesty/py/dynesty/internal_samplers.py
  - ../dynesty/py/dynesty/bounding.py
  - ../dynesty/py/dynesty/utils.py
  - ../dynesty/py/dynesty/results.py
  - ../dynesty/py/dynesty/pool.py
  - ../dynesty/py/dynesty/plotting.py
- Tests and behavior references:
  - ../dynesty/tests/*.py
- Docs/examples references:
  - ../dynesty/README.md
  - ../dynesty/docs
  - ../dynesty/demos

Package structure target:
- Project.toml
- .gitignore
- .JuliaFormatter.toml
- AGENTS.md
- LICENSE
- README.md
- src/Dynesty.jl
- src/utils.jl
- src/results.jl
- src/persistence.jl
- src/parallel.jl
- src/bounding.jl
- src/internal_samplers.jl
- src/sampler.jl
- src/dynamic_sampler.jl
- src/plotting.jl
- ext/DynestyHDF5Ext.jl for evaluation-history HDF5 support
- test/runtests.jl
- test/test_utils.jl
- test/test_results.jl
- test/test_persistence.jl
- test/test_parallel.jl
- test/test_bounding_unitcube_ellipsoid.jl
- test/test_bounding_friends.jl
- test/test_internal_samplers.jl
- test/test_static_sampler.jl
- test/test_results_postprocess.jl
- test/test_dynamic_sampler.jl
- test/test_plotting.jl
- test/test_examples.jl
- test/test_crosscheck_fixtures.jl
- test/reference/python/generate_reference.py
- test/reference/python/README.md
- test/reference/python/fixtures/
- docs/migration_matrix.md
- docs/source_snapshot.md
- docs/compatibility.md
- docs/testing.md
- docs/persistence.md
- docs/performance.md
- docs/examples.md
- examples/*.jl
- benchmark/benchmarks.jl
- .github/workflows/test.yml
- final Documenter.jl docs in docs/Project.toml, docs/make.jl, docs/src/*.md

Core design decisions:
- Package/module name: Dynesty.
- Repository directory may remain dynesty.jl.
- Public API should prefer Julia conventions:
  - run_nested!(sampler)
  - checkpoint!(sampler, path)
  - add_live_points!(sampler)
  - results(sampler)
- Python dynesty is the algorithm, behavior, workflow, and test reference; it is
  not the public API surface reference.
- Do not provide Python-compatible public aliases:
  - mutating APIs use bang forms such as run_nested!, checkpoint!, add_live_points!, and combine_runs!.
  - enum-like public options accept Symbol values or Julia types only; strings are reserved for true text/path/label metadata.
  - random seeding uses rng only, accepting an AbstractRNG or integer seed.
  - rstate, random_state, use_pool, PoolUsage, no-bang mutating aliases, Python-style args/kwargs wrappers, and public Python index-conversion helpers are intentionally unsupported.
- Do not mechanically support Python logl_args/logl_kwargs/ptform_args/ptform_kwargs; Julia users should use closures or callable objects.
- Results core fields should be public and stable.
- Sampler internal fields are not all public API.
- Use Julia-native Results fields such as res.blobs, res.boundidx, and res.samples_batch. Python fixture schema conversion belongs in test helpers, not public Results aliases.
- Use 1-based Julia indices for periodic/reflective dimensions. Do not auto-accept Python 0-based indices and do not expose public Python index conversion helpers.
- Default parameters and :auto heuristics should align with Python dynesty unless an intentional difference is documented.
- First version core numerical type commitment is Float64.
- prior_transform outputs should support the same practical extent as Python dynesty: mainly real vectors and tuple/list-like outputs that can be normalized to Float64 vectors. Do not promise arbitrary complex/manifold object support as part of this migration. Users needing complex or non-Euclidean models should map them through real coordinates in prior_transform/loglikelihood.
- Support loglikelihood returns:
  - Real
  - (logl, blob)
  - LoglOutput(logl, blob)
- Support prior_transform styles:
  - prior_transform(u) -> v
  - prior_transform!(v, u) with an explicit inplace option or wrapper.
- Default user-function input behavior is performance-first:
  - copy_inputs=false by default.
  - User functions should treat inputs as read-only, short-lived views or scratch buffers.
  - copy_inputs=true must provide Python-like safe copy behavior.
  - Document this intentional difference from Python dynesty, which copies input arrays before calling user functions.
- Public Results and user-facing arrays use Python-compatible shape:
  - samples: nsamples x ndim
  - live_u/live_v public views: nlive x ndim
- Internal hot paths should use Julia-performance-friendly column-major storage where useful:
  - ndim x npoints for live-point/sampler internals.
  - All public/internal conversions must be explicit, centralized, and tested.
  - Do not repeatedly transpose/copy in inner loops.

Dependencies:
- Use mature Julia scientific dependencies where they reduce risk:
  - SpecialFunctions
  - StatsBase
  - Clustering
  - NearestNeighbors
  - Distances
  - JSON3
  - NPZ or NPY
  - JLD2
  - RecipesBase
  - BenchmarkTools for benchmarks
  - JuliaFormatter for formatting
  - Aqua for final package quality tests
- JLD2 is a core dependency for save_results/load_results.
- HDF5.jl should be a weak dependency/extension for evaluation history files.
- RecipesBase is a core dependency for plotting recipes.
- Plots.jl is not a core dependency; use only in examples/tests/optional plotting paths.
- Do not make Makie a core dependency. Makie support can be a future enhancement, not a hard requirement.
- Do not submit Manifest.toml. Add it to .gitignore.

Persistence:
- Stage 1 must implement the full core data-saving framework, not postpone it.
- checkpoint/resume path:
  - Use Julia Serialization.
  - Use .jls extension.
  - Optimize for high-performance sampler snapshots and restoration.
  - Do not promise cross-language compatibility.
  - Do not promise cross-Julia-major-version archival stability.
- Results/archive path:
  - Use JLD2.
  - Use .jld2 extension.
  - save_results/load_results must work out of the box.
- Evaluation history path:
  - Use HDF5.jl via weak dependency/extension.
  - Match Python h5py-style purpose for appendable evaluation_u, evaluation_v, evaluation_logl datasets.
- Restore semantics:
  - Do not save user function bodies.
  - restore_sampler(path; loglikelihood, prior_transform, ...) must require users to provide functions again.
  - Save all numeric state, RNG state, bound state, internal sampler state, results state, live/dead points, proposal stats, batch/dynamic state, checkpoint metadata, version metadata, and backend metadata.
  - Do not save worker process objects.
  - If blobs or transformed samples are not serializable, produce clear errors or provide documented options to skip them.

Parallelism:
- Stage 1 must create a full Julia-native parallel execution system.
- Do not copy the surface shape of Python Pool or expose use_pool. Cover the
  underlying queue-size and fine-grained workflow capabilities with Julia-native
  backends and ParallelPolicy.
- Implement:
  - SerialMapBackend
  - ThreadedMapBackend
  - DistributedMapBackend
- Threads should be the recommended parallel path.
- Distributed support must exist, but full distributed tests may be extended tests.
- queue_size is a public keyword:
  - Serial -> 1 or serial batching.
  - Threaded -> thread task/batch limit.
  - Distributed -> worker task/batch limit.
  - queue_size=nothing chooses backend defaults.
- Map outputs must preserve input order.
- Exceptions must include task index and useful input context.
- Do not share mutable RNGs across threads/workers.
- Use deterministic per-task seed splitting for random parallel work.
- Guarantee reproducibility for same seed + same backend + same backend config + same queue_size.
- Do not require identical trajectories across Serial/Threaded/Distributed.
- Do not require identical trajectories with Python.

Testing and Python cross-checks:
- Maintain docs/migration_matrix.md with one row per Python symbol:
  - Python symbol
  - Julia symbol
  - test grade A/B/C
  - status
  - Julia test file
  - Python fixture file
  - notes
- Test grades:
  - A: public API and core numerical functions. Must have direct Julia tests and Python fixture cross-checks.
  - B: internal helpers that affect algorithm behavior. Must have direct or indirect Julia tests. Use Python fixtures when inputs/outputs are stable.
  - C: thin wrappers, display, printing, plotting helpers, and demo/doc helpers. Cover by caller tests, smoke tests, snapshots, or migration-matrix notes.
- Python cross-check strategy:
  - Use reference fixtures generated from ../dynesty.
  - Default tests should read fixtures, not call Python live.
  - Live Python smoke cross-checks are optional/extended.
  - Use JSON + NPZ fixture format.
  - JSON stores metadata, scalar results, tolerances, exception expectations, descriptions, and statistical summaries.
  - NPZ stores large arrays/matrices/sample sets.
  - test/reference/python/README.md must document fixture generation commands, Python dynesty source snapshot, Python version, NumPy/SciPy versions, fixture contents, and tolerance rationale.
- Randomness:
  - Do not require same-seed cross-language sample-by-sample equality.
  - Julia random functions must be reproducible for fixed Julia seed.
  - Compare random and Monte Carlo functions by invariants, statistical properties, acceptance ranges, valid regions, and result tolerances.
- Tolerances:
  - Deterministic numerical functions default rtol=1e-10, atol=1e-12.
  - Matrix decomposition/covariance/logdet/clustering order cases may use rtol=1e-8, atol=1e-10 when justified.
  - NaN, Inf, -Inf, and exception paths must be explicitly tested.
  - Sampler integration tests compare logz/logzerr/posterior mean/cov/neff/ncall/eff/niter/proposal stats within justified tolerances.
- Index fixtures:
  - For periodic/reflective and other dimension-index inputs, fixtures must record both Python 0-based and Julia 1-based values explicitly.
  - Do not implicitly +1 in tests without fixture metadata.
- Test organization:
  - Use functional test files as listed above.
  - Use environment variables for extended tests:
    - DYNESTY_RUN_SLOW_TESTS=true
    - DYNESTY_RUN_PLOT_TESTS=true
    - DYNESTY_RUN_EXTENDED_TESTS=true
    - DYNESTY_RUN_DISTRIBUTED_TESTS=true
    - DYNESTY_RUN_JET_TESTS=true
    - DYNESTY_REGENERATE_FIXTURES=true
- Default CI should run Julia 1.11 Pkg.test without requiring adjacent ../dynesty or live Python.
- Distributed full tests should be controlled by DYNESTY_RUN_DISTRIBUTED_TESTS=true.
- Plot smoke tests should be controlled by DYNESTY_RUN_PLOT_TESTS=true.
- JET.jl is optional/extended, not default blocking.
- Aqua.jl should be added by final package-quality stage.

Source snapshot:
- In stage 0 create docs/source_snapshot.md.
- Record:
  - ../dynesty path
  - git commit hash
  - branch
  - git status --short
  - Python dynesty version if available
  - Python version
  - NumPy version
  - SciPy version
  - fixture generation date
  - whether source is dirty
- Fixture metadata must include source commit/dirty status and dependency versions.
- Do not update ../dynesty automatically.

Compatibility and intentional differences:
- Maintain docs/compatibility.md.
- Record any public behavior difference with:
  - Python behavior
  - Julia behavior
  - reason
  - affected tests
- Known intentional differences to document:
  - Julia uses 1-based indices for periodic/reflective.
  - Dynesty.jl defaults to copy_inputs=false for performance, unlike Python dynesty's defensive input copy.
  - Julia-native API uses run_nested! and related bang functions.
  - Results uses blobs instead of Python's blob field.
  - queue_size semantics are Julia-backend-native rather than Python Pool internals.
  - plotting is Plots/RecipesBase-compatible rather than Matplotlib.
- Major public behavior changes must be asked about before implementation.

Error handling:
- Align error behavior with Python dynesty where possible.
- Use Julia-idiomatic exceptions:
  - ArgumentError
  - DomainError
  - DimensionMismatch
  - BoundsError
  - ErrorException
  - custom exceptions only when useful.
- Error messages should include parameter names, shapes, expected ranges, and current values.
- Tests should check exception type/category and key message substrings, not exact Python text.

Plotting:
- Final F2 deliverable must include plotting.py equivalents:
  - runplot
  - traceplot
  - cornerpoints
  - cornerplot
  - boundplot
  - cornerbound
- Use RecipesBase/Plots-compatible design.
- Do not make Plots a core dependency.
- Do not require pixel-perfect Matplotlib replication.
- Test plotting with smoke tests when DYNESTY_RUN_PLOT_TESTS=true.
- Document plotting differences.

Examples, demos, and docs:
- Final F2 deliverable must migrate important Python demos/notebooks to Julia .jl examples and Markdown tutorials.
- Do not require .ipynb or Pluto notebooks.
- Provide examples such as:
  - examples/overview.jl
  - examples/dynamic_nested_sampling.jl
  - examples/errors.jl
  - examples/gaussian.jl
  - examples/eggbox.jl
  - examples/gaussian_shells.jl
  - examples/high_dimensional_gaussian.jl
- Examples should be smoke-testable where practical.
- Stage 1 only needs README and docs/*.md.
- Final stage must add Documenter.jl docs:
  - docs/Project.toml
  - docs/make.jl
  - docs/src/index.md
  - docs/src/quickstart.md
  - docs/src/api.md
  - docs/src/examples.md
  - docs/src/dynamic.md
  - docs/src/errors.md
  - docs/src/plotting.md
  - docs/src/persistence.md
  - docs/src/compatibility.md
- Final docs build must pass:
  - julia --project=docs docs/make.jl

Citation:
- Migrate citation functionality from Python dynesty.
- Provide citations or get_citations API.
- Include Speagle (2020), Koposov et al. (2024), Skilling nested sampling references, Higson dynamic nested sampling reference, and bound/sampler method references.
- README and docs must explain how to cite.
- Citation output need not be byte-for-byte identical to Python, but content must be complete.

Performance and quality:
- First stages must practice basic type stability and performance hygiene.
- Avoid unnecessary Vector{Any} and Dict{String,Any} in hot paths.
- Core arrays should use Float64.
- Avoid JSON for large arrays.
- Avoid repeated transpose/copy in inner loops.
- Use explicit scratch buffers/views where safe.
- Run @time or BenchmarkTools smoke benchmarks for at least one Gaussian sampler path and persistence path during relevant stages.
- Final deliverable must include benchmark/benchmarks.jl using BenchmarkTools, not run by default Pkg.test.
- Add JuliaFormatter configuration and format changed Julia files before commits.
- Add Aqua.jl quality tests by final stage.
- Do not require performance to exceed Python unless explicitly requested later.

Git workflow:
- Stage 0: git init, .gitignore, package skeleton, first runnable Pkg.test, commit.
- Commit after each stage passes its defined checks.
- Use clear English commit messages, e.g.:
  - init Julia package skeleton
  - add migration matrix and source snapshot
  - add persistence and fixture infrastructure
  - implement parallel map backends
  - port core utils with Python cross-checks
  - implement bounding primitives
  - add static nested sampler
  - add dynamic nested sampler
  - add plotting recipes and examples
  - add Documenter docs
- Before every stage commit, run a self-review checklist:
  - git diff --stat
  - confirm ../dynesty was not modified
  - update docs/migration_matrix.md
  - update docs/compatibility.md if behavior differs
  - update docs/source_snapshot.md or fixture metadata when fixtures change
  - confirm new public functions have tests
  - confirm A-grade functions have Python fixtures
  - confirm B-grade functions have direct or indirect tests
  - confirm C-grade coverage is recorded
  - run relevant tests
  - check Project.toml compat
  - check no unplanned heavy dependencies were introduced
  - check persistence and parallel metadata semantics remain valid

Local environment permissions:
- You may create/update Project.toml in the current repository.
- You may use Julia Pkg to install project/test/doc dependencies.
- You may create a local Python venv inside this repository, e.g. .venv-fixtures.
- You may pip install -e ../dynesty into that venv to generate fixtures.
- Do not install global system packages.
- If Julia >= 1.11 is unavailable, report it and ask the user.
- If a system dependency is required, ask the user first.

Stage plan:

Stage 0: Repository initialization and migration map
- git init
- Create .gitignore, Project.toml, src/Dynesty.jl, test/runtests.jl, LICENSE, README.md, AGENTS.md.
- Create docs/migration_matrix.md, docs/source_snapshot.md, docs/compatibility.md, docs/testing.md, docs/persistence.md.
- Read ../dynesty license/authors/readme/source/tests.
- Record source snapshot.
- Establish migration matrix with A/B/C test grades.
- Add GitHub Actions Julia 1.11 test workflow.
- Add JuliaFormatter config.
- Ensure julia --project=. -e 'using Pkg; Pkg.test()' runs.
- Commit.

Stage 1: Foundations, fixtures, persistence, and parallel framework
- Implement foundational types:
  - LoglOutput
  - LogLikelihood or Julia-equivalent wrapper
  - Results
  - RunRecord or equivalent
  - Iterator/state structs as needed.
- Implement foundational utilities:
  - unitcheck
  - apply_reflect
  - mean_and_cov
  - quantile
  - resample_equal
  - get_neff_from_logwt
  - logvol_prefactor
  - compute_integrals baseline
  - progress_integration baseline
- Implement fixture infrastructure:
  - test/reference/python/generate_reference.py
  - fixtures index JSON
  - JSON + NPZ reader helpers in tests
  - test/reference/python/README.md.
- Implement persistence:
  - save_results/load_results with JLD2
  - save_sampler/restore_sampler framework with Serialization
  - checkpoint! framework
  - metadata/version/config/RNG state/backends metadata
  - no user-function serialization.
- Implement parallel framework:
  - SerialMapBackend
  - ThreadedMapBackend
  - DistributedMapBackend
  - queue_size
  - ordered output
  - deterministic per-task RNG splitting
  - exception propagation.
- Add tests for foundations, persistence, fixtures, and parallel framework.
- Commit.

Stage 2: Bounding core
- Implement AbstractBound or equivalent interface.
- Implement UnitCube, Ellipsoid, MultiEllipsoid.
- Implement randsphere, rand_choice, improve_covar_mat, bounding_ellipsoid, bounding_ellipsoids, _bounding_ellipsoids or Julia equivalents.
- Implement contains/sample/samples/update/get_random_axes/scale_to_logvol.
- Add Python fixture cross-checks and statistical tests.
- Port core ellipsoid/volume/bound-interface tests.
- Commit.

Stage 3: Friends bounds and full bounding coverage
- Implement RadFriends and SupFriends.
- Implement friends bootstrap/leave-one-out radius helpers.
- Use NearestNeighbors/Distances/Clustering where appropriate.
- Cover :none, :single, :multi, :balls, :cubes.
- Add tests and Python statistical cross-checks.
- Commit.

Stage 4: Internal samplers
- Implement AbstractInternalSampler.
- Implement UniformBoundSampler, UnitCubeSampler, RWalkSampler, SliceSampler, RSliceSampler.
- Implement generic_random_walk, propose_ball_point, generic_slice_step, _slice_doubling_accept, tune_slice.
- Implement periodic/reflective support using 1-based Julia indices.
- Track proposal stats and evaluation history hooks.
- Add tests and Python statistical/reference cross-checks.
- Commit.

Stage 5: Static NestedSampler
- Implement NestedSampler and static nested sampling flow.
- Implement live point initialization.
- Implement _get_bound, _get_internal_sampler, _get_enlarge_bootstrap, _get_update_interval_ratio equivalents.
- Implement run_nested!, run_nested alias, sample/iterator behavior, add_live_points!, results access.
- Integrate checkpoint/restore for static sampler.
- Integrate parallel backend.
- Add Gaussian, Eggbox, plateau, deterministic, blob, periodic/reflective, large-logl, tuple-prior-transform tests.
- Compare with Python reference statistics.
- Commit.

Stage 6: Results postprocessing, merge, resampling, and error estimates
- Implement jitter_run, resample_run, reweight_run, unravel_run, merge_runs, check_result_static, kld_error, merge helpers, results_substitute or Julia equivalents.
- Ensure Results loaded from JLD2 can run postprocessing.
- Add Python fixture cross-checks.
- Commit.

Stage 7: DynamicSampler
- Implement DynamicSampler and dynamic sampler internals.
- Implement compute_weights, weight_function, stopping_function, batch configuration, dynamic run flow, batch metadata.
- Integrate checkpoint/restore for dynamic sampler.
- Add Gaussian/Eggbox dynamic tests and Python reference statistics.
- Commit.

Stage 8: Full-project completion, plotting, examples, docs, quality
- Implement plotting equivalents:
  - runplot
  - traceplot
  - cornerpoints
  - cornerplot
  - boundplot
  - cornerbound.
- Implement pool.py Julia-native replacement through parallel backends.
- Migrate demos/notebooks to Julia .jl examples and Markdown tutorials.
- Add final Documenter.jl docs and ensure docs build.
- Add citations API and docs.
- Add benchmark/benchmarks.jl.
- Add Aqua.jl tests.
- Finish migration_matrix with no pending symbols.
- Update compatibility docs for all intentional differences.
- Run full default tests and relevant extended tests where practical.
- Final self-review and commit.

Definition of done:
- The current directory is a git repository with staged, coherent commit history.
- Project.toml defines a Julia >= 1.11 package named Dynesty with appropriate compat.
- Manifest.toml is not committed.
- `using Dynesty` works.
- `julia --project=. -e 'using Pkg; Pkg.test()'` passes.
- Core static NestedSampler examples run.
- DynamicSampler examples run.
- Results, checkpoint, restore, evaluation history, and archive save/load work according to the persistence design.
- Serial, threaded, and distributed map backends exist and are tested according to default/extended policy.
- Python reference fixtures exist and are documented.
- All migrated A-grade functions have Python cross-checks.
- All migrated functions/types are represented in docs/migration_matrix.md.
- docs/compatibility.md documents every intentional public difference.
- plotting equivalents work through RecipesBase/Plots-compatible paths.
- examples cover the important Python demos/notebooks in Julia .jl or Markdown form.
- Documenter docs build locally.
- citation functionality is present.
- benchmark suite exists but is not part of default Pkg.test.
- README explains installation, quickstart, Python compatibility notes, persistence, parallelism, plotting, examples, and citation.
- ../dynesty remains unmodified.
```
