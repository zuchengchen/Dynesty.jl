# Migration Matrix

Source snapshot: `../dynesty` commit
`3ec158de0d2bf12a56230faacd0c987b3d55d550` on branch `master`.

Statuses:

- `implemented`: Julia equivalent exists and has the listed coverage.
- `planned`: not implemented yet.
- `replacement`: covered by a Julia-native replacement rather than a direct API.
- `internal`: implementation detail covered by caller behavior.

| Python symbol | Julia symbol | Grade | Status | Julia test file | Python fixture file | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `dynesty.NestedSampler` | `NestedSampler` | A | implemented | `test/test_static_sampler.jl` | statistical/invariant | Public static sampler API with Julia-native mutating `run_nested!`, result extraction, blobs, bounds, checkpoint restore, and progress callback plumbing. |
| `dynesty.DynamicNestedSampler` | `DynamicNestedSampler` | A | planned | `test/test_dynamic_sampler.jl` | planned | Public dynamic sampler API. |
| `dynesty.bounding.Bound` | `AbstractBound` | B | planned | `test/test_bounding_unitcube_ellipsoid.jl` | planned | Julia abstract interface replacement. |
| `dynesty.bounding.UnitCube` | `UnitCube` | A | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Unit-cube bound. |
| `dynesty.bounding.Ellipsoid` | `Ellipsoid` | A | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Ellipsoid bound. |
| `dynesty.bounding.MultiEllipsoid` | `MultiEllipsoid` | A | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Multi-ellipsoid bound with recursive clustering split support. |
| `dynesty.bounding.RadFriends` | `RadFriends` | A | implemented | `test/test_bounding_friends.jl` | `test/reference/python/fixtures/friends_core.json` | RadFriends bound. |
| `dynesty.bounding.SupFriends` | `SupFriends` | A | implemented | `test/test_bounding_friends.jl` | `test/reference/python/fixtures/friends_core.json` | SupFriends bound. |
| `dynesty.bounding._slogdet_checked` | `_slogdet_checked` | B | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Internal determinant guard. |
| `dynesty.bounding.logvol_prefactor` | `logvol_prefactor` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/bounding_core.json` | Volume helper. |
| `dynesty.bounding.randsphere` | `randsphere` | B | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Statistical checks plus reference fixture metadata. |
| `dynesty.bounding.rand_choice` | `rand_choice` | B | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Weighted random choice; Julia returns 1-based indices. |
| `dynesty.bounding.improve_covar_mat` | `improve_covar_mat` | B | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Covariance conditioning. |
| `dynesty.bounding.bounding_ellipsoid` | `bounding_ellipsoid` | A | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Deterministic fixture and tolerance checks. |
| `dynesty.bounding._bounding_ellipsoids` | `_bounding_ellipsoids` | B | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Recursive two-cluster split helper with BIC-like volume reduction test. |
| `dynesty.bounding.bounding_ellipsoids` | `bounding_ellipsoids` | A | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Public multi-bound constructor using recursive ellipsoid splitting. |
| `dynesty.bounding._bootstrap_points` | `_bootstrap_points` | B | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Internal bootstrap helper; Julia RNG path checked by invariants. |
| `dynesty.bounding._ellipsoid_bootstrap_expand` | `_ellipsoid_bootstrap_expand` | B | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Internal bootstrap expansion for single and multi ellipsoid bounds. |
| `dynesty.bounding._friends_bootstrap_radius` | `_friends_bootstrap_radius` | B | implemented | `test/test_bounding_friends.jl` | `test/reference/python/fixtures/friends_core.json` | Friends radius helper; random bootstrap checked by invariants. |
| `dynesty.bounding._friends_leaveoneout_radius` | `_friends_leaveoneout_radius` | B | implemented | `test/test_bounding_friends.jl` | `test/reference/python/fixtures/friends_core.json` | Leave-one-out radius helper. |
| `dynesty.dynamicsampler.DynamicSamplerStatesEnum` | `DynamicSamplerState` | B | implemented | `test/test_dynamic_sampler.jl` | `test/reference/python/fixtures/dynamic_core.json` | Julia enum replacement with matching state numeric values. |
| `dynesty.dynamicsampler.compute_weights` | `compute_weights` | A | implemented | `test/test_dynamic_sampler.jl` | `test/reference/python/fixtures/dynamic_core.json` | Dynamic evidence/posterior weighting. |
| `dynesty.dynamicsampler.weight_function` | `weight_function` | A | implemented | `test/test_dynamic_sampler.jl` | `test/reference/python/fixtures/dynamic_core.json` | Dynamic batch-bound weighting heuristic. |
| `dynesty.dynamicsampler.stopping_function` | `stopping_function` | A | implemented | `test/test_dynamic_sampler.jl` | `test/reference/python/fixtures/dynamic_core.json` | Default stopping criteria; deterministic fixture covers `n_mc=0`, Monte Carlo branch is checked by Julia invariants later. |
| `dynesty.dynamicsampler._configure_batch_sampler` | `_configure_batch_sampler` / `ConfiguredBatchSampler` | B | implemented | `test/test_dynamic_sampler.jl` | not needed | Internal dynamic batch configuration with fresh-prior and saved-sample branches; Julia returns a typed metadata wrapper around `NestedSampler`. |
| `dynesty.dynamicsampler.DynamicSampler` | `DynamicSampler` | A | planned | `test/test_dynamic_sampler.jl` | planned | Dynamic sampler engine. |
| `dynesty.dynesty._get_citations` | `get_citations` | C | implemented | `test/runtests.jl` | not needed | Julia helper includes required citation set. |
| `dynesty.dynesty._get_internal_sampler` | `_get_internal_sampler` | B | implemented | `test/test_static_sampler.jl` | not needed | Sampler factory; accepts Julia `Symbol`s and Python strings with 1-based dimension indices. |
| `dynesty.dynesty._get_enlarge_bootstrap` | `_get_enlarge_bootstrap` | B | implemented | `test/test_static_sampler.jl` | not needed | Bound defaults; explicit ellipsoid bootstrap is supported, while automatic uniform-bound bootstrap still maps to deterministic enlargement. |
| `dynesty.dynesty._check_first_update` | `_check_first_update` | B | implemented | `test/test_static_sampler.jl` | not needed | First-update validation. |
| `dynesty.dynesty._get_update_interval_ratio` | `_get_update_interval_ratio` | B | implemented | `test/test_static_sampler.jl` | not needed | Bound update heuristic. |
| `dynesty.dynesty._assemble_sampler_docstring` | documentation generation | C | replacement | docs build | not needed | Julia docs will be written directly. |
| `dynesty.dynesty._common_sampler_init` | `NestedSampler` constructor helpers | B | replacement | `test/test_static_sampler.jl` | not needed | Julia constructor composes wrappers, RNG, bounds, internal sampler, live-point initialization, and update defaults directly. |
| `dynesty.dynesty._function_wrapper` | callable wrappers | C | replacement | `test/test_static_sampler.jl` | not needed | Julia closures/callable objects replace arg/kwarg wrappers. |
| `dynesty.internal_samplers.InternalSampler` | `AbstractInternalSampler` | B | implemented | `test/test_internal_samplers.jl` | not needed | Julia abstract interface replacement. |
| `dynesty.internal_samplers.UniformBoundSampler` | `UniformBoundSampler` | A | implemented | `test/test_internal_samplers.jl` | statistical/invariant | Bound rejection sampler. |
| `dynesty.internal_samplers.UnitCubeSampler` | `UnitCubeSampler` | A | implemented | `test/test_internal_samplers.jl` | statistical/invariant | Unit-cube sampler. |
| `dynesty.internal_samplers.RWalkSampler` | `RWalkSampler` | A | implemented | `test/test_internal_samplers.jl` | statistical/invariant | Random-walk sampler. |
| `dynesty.internal_samplers.SliceSampler` | `SliceSampler` | A | implemented | `test/test_internal_samplers.jl` | statistical/invariant | Slice sampler. |
| `dynesty.internal_samplers.RSliceSampler` | `RSliceSampler` | A | implemented | `test/test_internal_samplers.jl` | statistical/invariant | Random-direction slice sampler. |
| `dynesty.internal_samplers.generic_random_walk` | `generic_random_walk` | A | implemented | `test/test_internal_samplers.jl` | statistical/invariant | Proposal kernel. |
| `dynesty.internal_samplers.propose_ball_point` | `propose_ball_point` | B | implemented | `test/test_internal_samplers.jl` | not needed | Ball proposal helper with 1-based periodic/reflective indices. |
| `dynesty.internal_samplers._slice_doubling_accept` | `_slice_doubling_accept` | B | implemented | `test/test_internal_samplers.jl` | not needed | Slice acceptance helper. |
| `dynesty.internal_samplers.generic_slice_step` | `generic_slice_step` | A | implemented | `test/test_internal_samplers.jl` | statistical/invariant | Slice kernel. |
| `dynesty.internal_samplers.tune_slice` | `tune_slice` | B | implemented | `test/test_internal_samplers.jl` | not needed | Tuning helper. |
| `dynesty.plotting._make_subplots` | plotting backend setup | C | replacement | `test/test_plotting.jl` | not needed | Recipes/Plots-compatible replacement. |
| `dynesty.plotting.rotate_ticks` | plotting backend setup | C | replacement | `test/test_plotting.jl` | not needed | Matplotlib-specific helper not directly exposed. |
| `dynesty.plotting.plot_thruth` | `plot_truth` | C | implemented | `test/test_plotting.jl` | not needed | Backend-neutral truth-line data helper; Python typo is not exported. |
| `dynesty.plotting.check_span` | `check_span` | B | implemented | `test/test_plotting.jl` | `test/reference/python/fixtures/plotting_core.json` | Plot range helper; Julia returns normalized spans instead of mutating input. |
| `dynesty.plotting.runplot` | `runplot` / `RunPlotData` | C | implemented | `test/test_plotting.jl` | not needed | Backend-neutral run summary data and RecipesBase recipe; Matplotlib figure setup is replaced. |
| `dynesty.plotting.traceplot` | `traceplot` / `TracePlotData` | C | implemented | `test/test_plotting.jl` | not needed | Backend-neutral trace and 1-D marginal data with RecipesBase recipe. |
| `dynesty.plotting.cornerpoints` | `cornerpoints` / `CornerPointsData` | C | implemented | `test/test_plotting.jl` | not needed | Backend-neutral lower-triangle point cloud data with RecipesBase recipe. |
| `dynesty.plotting.cornerplot` | `cornerplot` / `CornerPlotData` | C | implemented | `test/test_plotting.jl` | not needed | Backend-neutral corner marginal data using `_hist2d` and RecipesBase recipe. |
| `dynesty.plotting.boundplot` | `boundplot` / `BoundPlotData` | C | implemented | `test/test_plotting.jl` | not needed | Backend-neutral saved-bound draws with optional static live-point reconstruction and RecipesBase recipe. |
| `dynesty.plotting.cornerbound` | `cornerbound` / `CornerBoundData` | C | implemented | `test/test_plotting.jl` | not needed | Backend-neutral lower-triangle saved-bound draws with optional static live-point reconstruction and RecipesBase recipe. |
| `dynesty.plotting._hist2d` | `_hist2d` / `Hist2DResult` | B | implemented | `test/test_plotting.jl` | `test/reference/python/fixtures/plotting_core.json` | Numerical histogram/contour helper with RecipesBase recipe. |
| `dynesty.pool.FunctionCache` | backend task closure | C | replacement | `test/test_parallel.jl` | not needed | Julia map backends replace Python multiprocessing cache. |
| `dynesty.pool.initializer` | backend initialization | C | replacement | `test/test_parallel.jl` | not needed | Julia backend setup. |
| `dynesty.pool.loglike_cache` | backend task closure | C | replacement | `test/test_parallel.jl` | not needed | Julia closures replace global cache. |
| `dynesty.pool.prior_transform_cache` | backend task closure | C | replacement | `test/test_parallel.jl` | not needed | Julia closures replace global cache. |
| `dynesty.pool.Pool` | `SerialMapBackend` / `ThreadedMapBackend` / `DistributedMapBackend` | A | implemented | `test/test_parallel.jl` | not needed | Ordered Julia-native map replacement with queue controls; Python Pool shape intentionally replaced. |
| `dynesty.sampler._get_bound` | `_get_bound` | B | implemented | `test/test_static_sampler.jl` | not needed | Bound factory. |
| `dynesty.sampler._initialize_live_points` | `_initialize_live_points` | A | implemented | `test/test_static_sampler.jl` | statistical/invariant | Live point initialization with Real, tuple/blob, and `LoglOutput` normalization. |
| `dynesty.sampler.Sampler` | `NestedSampler` internals | A | implemented | `test/test_static_sampler.jl` | statistical/invariant | Static sampler engine including run loop, final live points, result conversion, bound updates, blobs, and checkpoint restore. |
| `dynesty.utils.LoglOutput` | `LoglOutput` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Likelihood output with optional blob. |
| `dynesty.utils.LogLikelihood` | `LogLikelihood` | A | implemented | `test/test_utils.jl` | not needed | Callable wrapper implemented; HDF5 history flushing is extension-backed. |
| `dynesty.utils.RunRecord` | `RunRecord` | B | implemented | `test/test_results.jl` | not needed | Run accumulation. |
| `dynesty.utils.DelayTimer` | `DelayTimer` | C | implemented | `test/test_utils.jl` | not needed | Progress/checkpoint delay helper. |
| `dynesty.utils._update_tqdm_eta_from_dlogz` | progress metadata | C | replacement | `test/test_utils.jl` | not needed | TQDM-specific behavior omitted. |
| `dynesty.utils.print_fn` | `print_fn` | C | implemented | `test/test_utils.jl`, `test/test_static_sampler.jl` | not needed | Julia IO display helper. |
| `dynesty.utils.get_print_fn_args` | `get_print_fn_args` / `PrintFnArgs` | C | implemented | `test/test_utils.jl` | not needed | Display string builder. |
| `dynesty.utils.print_fn_tqdm` | progress backend | C | replacement | `test/test_utils.jl` | not needed | TQDM-specific behavior replaced. |
| `dynesty.utils.print_fn_fallback` | `print_fn_fallback` | C | implemented | `test/test_utils.jl` | not needed | Console/IO display helper. |
| `dynesty.utils.Results` | `Results` | A | implemented | `test/test_results.jl`, `test/test_results_postprocess.jl` | `test/reference/python/fixtures/results_postprocess.json` | Public results container with Julia `blobs` plus compatibility aliases for Python `blob`, `samples_bound`, and `batch`. |
| `dynesty.utils.results_substitute` | `results_substitute` | B | implemented | `test/test_results.jl`, `test/test_results_postprocess.jl` | `test/reference/python/fixtures/results_postprocess.json` | Results replacement helper; missing replacement keys are ignored like Python. |
| `dynesty.utils.get_nonbounded` | `get_nonbounded` | B | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Bound-type helper; Julia uses 1-based indices and fixtures record Python/Julia pairs. |
| `dynesty.utils.get_print_func` | `get_print_func` | C | implemented | `test/test_utils.jl`, `test/test_static_sampler.jl` | not needed | Julia callback selection helper; tqdm backend intentionally replaced. |
| `dynesty.utils.get_random_generator` | `get_random_generator` | B | implemented | `test/test_utils.jl` | not needed | Julia-native RNG helper; existing RNGs are preserved and integer seeds create deterministic Julia RNGs. |
| `dynesty.utils.get_seed_sequence` | `task_seeds` | A | implemented | `test/test_parallel.jl` | not needed | Julia-native deterministic seeds; no cross-language same-seed promise. |
| `dynesty.utils.get_neff_from_logwt` | `get_neff_from_logwt` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Effective sample size. |
| `dynesty.utils.unitcheck` | `unitcheck` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Unit-cube validation. |
| `dynesty.utils.apply_reflect` | `apply_reflect` / `apply_reflect!` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Reflective dimension handling. |
| `dynesty.utils.mean_and_cov` | `mean_and_cov` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Weighted statistics. |
| `dynesty.utils.resample_equal` | `resample_equal` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Equal-weight resampling; fixture records Python seeded output, Julia tests deterministic replay and invariants. |
| `dynesty.utils.quantile` | `quantile` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Weighted quantile. |
| `dynesty.utils._get_nsamps_samples_n` | `_get_nsamps_samples_n` | B | implemented | `test/test_results_postprocess.jl` | `test/reference/python/fixtures/results_postprocess.json` | Post-processing helper for static/dynamic live-point counts. |
| `dynesty.utils._find_decrease` | `_find_decrease` | B | implemented | `test/test_results_postprocess.jl` | `test/reference/python/fixtures/results_postprocess.json` | Post-processing helper; fixtures record Python 0-based and Julia 1-based half-open bounds. |
| `dynesty.utils.jitter_run` | `jitter_run` | A | implemented | `test/test_results_postprocess.jl` | statistical/invariant | Prior-volume jitter error helper; stochastic checks use deterministic Julia seeds and invariants. |
| `dynesty.utils.compute_integrals` | `compute_integrals` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Evidence integral baseline. |
| `dynesty.utils.progress_integration` | `progress_integration` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Running evidence integration. |
| `dynesty.utils.resample_run` | `resample_run` | A | implemented | `test/test_results_postprocess.jl` | statistical/invariant | Run resampling and return-index behavior; random draws checked by invariants. |
| `dynesty.utils.reweight_run` | `reweight_run` | A | implemented | `test/test_results_postprocess.jl` | `test/reference/python/fixtures/results_postprocess.json` | Importance reweighting; deterministic fixture covers weights, evidence, errors, and `h`/`information` compatibility. |
| `dynesty.utils.unravel_run` | `unravel_run` | A | implemented | `test/test_results_postprocess.jl` | `test/reference/python/fixtures/results_postprocess.json` | Run unraveling into one-live-point strands. |
| `dynesty.utils.merge_runs` | `merge_runs` | A | implemented | `test/test_results_postprocess.jl` | `test/reference/python/fixtures/results_postprocess.json` | Run merge, including unraveled strand merge and single-result edge behavior. |
| `dynesty.utils.check_result_static` | `check_result_static` | A | implemented | `test/test_results_postprocess.jl` | `test/reference/python/fixtures/results_postprocess.json` | Static-result normalization for dynamic-like results with static live counts. |
| `dynesty.utils.kld_error` | `kld_error` | A | implemented | `test/test_results_postprocess.jl` | statistical/invariant | KLD error estimate over jitter/resample realizations. |
| `dynesty.utils._prepare_for_merge` | `_prepare_for_merge` | B | implemented | `test/test_results_postprocess.jl` | `test/reference/python/fixtures/results_postprocess.json` | Merge helper covered indirectly through `merge_runs`. |
| `dynesty.utils._merge_two` | `_merge_two` | B | implemented | `test/test_results_postprocess.jl` | `test/reference/python/fixtures/results_postprocess.json` | Pairwise merge helper covered indirectly through `merge_runs`. |
| `dynesty.utils._kld_error` | `_kld_error` | B | implemented | `test/test_results_postprocess.jl` | statistical/invariant | Map-friendly KLD helper. |
| `dynesty.utils.restore_sampler` | `restore_sampler` | A | implemented | `test/test_persistence.jl` | not needed | Julia Serialization checkpoint restore; requires user functions again. |
| `dynesty.utils.save_sampler` | `save_sampler` / `checkpoint!` | A | implemented | `test/test_persistence.jl` | not needed | Julia Serialization checkpoint save. |
| `dynesty.utils._parse_pool_queue` | `_normalize_queue_size` | B | implemented | `test/test_parallel.jl` | not needed | Julia backend queue parsing. |
