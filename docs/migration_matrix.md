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
| `dynesty.NestedSampler` | `NestedSampler` | A | planned | `test/test_static_sampler.jl` | planned | Public static sampler API. |
| `dynesty.DynamicNestedSampler` | `DynamicNestedSampler` | A | planned | `test/test_dynamic_sampler.jl` | planned | Public dynamic sampler API. |
| `dynesty.bounding.Bound` | `AbstractBound` | B | planned | `test/test_bounding_unitcube_ellipsoid.jl` | planned | Julia abstract interface replacement. |
| `dynesty.bounding.UnitCube` | `UnitCube` | A | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Unit-cube bound. |
| `dynesty.bounding.Ellipsoid` | `Ellipsoid` | A | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Ellipsoid bound. |
| `dynesty.bounding.MultiEllipsoid` | `MultiEllipsoid` | A | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Multi-ellipsoid bound; recursive splitting remains conservative single-ellipsoid in Stage 2. |
| `dynesty.bounding.RadFriends` | `RadFriends` | A | implemented | `test/test_bounding_friends.jl` | `test/reference/python/fixtures/friends_core.json` | RadFriends bound. |
| `dynesty.bounding.SupFriends` | `SupFriends` | A | implemented | `test/test_bounding_friends.jl` | `test/reference/python/fixtures/friends_core.json` | SupFriends bound. |
| `dynesty.bounding._slogdet_checked` | `_slogdet_checked` | B | planned | `test/test_bounding_unitcube_ellipsoid.jl` | planned | Internal determinant guard. |
| `dynesty.bounding.logvol_prefactor` | `logvol_prefactor` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/bounding_core.json` | Volume helper. |
| `dynesty.bounding.randsphere` | `randsphere` | B | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Statistical checks plus reference fixture metadata. |
| `dynesty.bounding.rand_choice` | `rand_choice` | B | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Weighted random choice; Julia returns 1-based indices. |
| `dynesty.bounding.improve_covar_mat` | `improve_covar_mat` | B | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Covariance conditioning. |
| `dynesty.bounding.bounding_ellipsoid` | `bounding_ellipsoid` | A | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Deterministic fixture and tolerance checks. |
| `dynesty.bounding._bounding_ellipsoids` | `_bounding_ellipsoids` | B | planned | `test/test_bounding_unitcube_ellipsoid.jl` | planned | Recursive clustering split helper remains for full multi-ellipsoid refinement. |
| `dynesty.bounding.bounding_ellipsoids` | `bounding_ellipsoids` | A | implemented | `test/test_bounding_unitcube_ellipsoid.jl` | `test/reference/python/fixtures/bounding_core.json` | Public multi-bound constructor; Stage 2 covers single-ellipsoid union. |
| `dynesty.bounding._bootstrap_points` | `_bootstrap_points` | B | planned | `test/test_bounding_unitcube_ellipsoid.jl` | planned | Internal bootstrap helper. |
| `dynesty.bounding._ellipsoid_bootstrap_expand` | `_ellipsoid_bootstrap_expand` | B | planned | `test/test_bounding_unitcube_ellipsoid.jl` | planned | Internal bootstrap expansion. |
| `dynesty.bounding._friends_bootstrap_radius` | `_friends_bootstrap_radius` | B | implemented | `test/test_bounding_friends.jl` | `test/reference/python/fixtures/friends_core.json` | Friends radius helper; random bootstrap checked by invariants. |
| `dynesty.bounding._friends_leaveoneout_radius` | `_friends_leaveoneout_radius` | B | implemented | `test/test_bounding_friends.jl` | `test/reference/python/fixtures/friends_core.json` | Leave-one-out radius helper. |
| `dynesty.dynamicsampler.DynamicSamplerStatesEnum` | `DynamicSamplerState` | B | planned | `test/test_dynamic_sampler.jl` | planned | Julia enum-like replacement. |
| `dynesty.dynamicsampler.compute_weights` | `compute_weights` | A | planned | `test/test_dynamic_sampler.jl` | planned | Dynamic weighting. |
| `dynesty.dynamicsampler.weight_function` | `weight_function` | A | planned | `test/test_dynamic_sampler.jl` | planned | Dynamic batch weighting. |
| `dynesty.dynamicsampler.stopping_function` | `stopping_function` | A | planned | `test/test_dynamic_sampler.jl` | planned | Stopping criteria. |
| `dynesty.dynamicsampler._configure_batch_sampler` | `_configure_batch_sampler` | B | planned | `test/test_dynamic_sampler.jl` | planned | Internal dynamic configuration. |
| `dynesty.dynamicsampler.DynamicSampler` | `DynamicSampler` | A | planned | `test/test_dynamic_sampler.jl` | planned | Dynamic sampler engine. |
| `dynesty.dynesty._get_citations` | `get_citations` | C | implemented | `test/runtests.jl` | not needed | Julia helper includes required citation set. |
| `dynesty.dynesty._get_internal_sampler` | `_get_internal_sampler` | B | planned | `test/test_static_sampler.jl` | planned | Sampler factory. |
| `dynesty.dynesty._get_enlarge_bootstrap` | `_get_enlarge_bootstrap` | B | planned | `test/test_static_sampler.jl` | planned | Bound defaults. |
| `dynesty.dynesty._check_first_update` | `_check_first_update` | B | planned | `test/test_static_sampler.jl` | planned | First-update validation. |
| `dynesty.dynesty._get_update_interval_ratio` | `_get_update_interval_ratio` | B | planned | `test/test_static_sampler.jl` | planned | Bound update heuristic. |
| `dynesty.dynesty._assemble_sampler_docstring` | documentation generation | C | replacement | docs build | not needed | Julia docs will be written directly. |
| `dynesty.dynesty._common_sampler_init` | `_common_sampler_init` | B | planned | `test/test_static_sampler.jl` | planned | Shared sampler initialization. |
| `dynesty.dynesty._function_wrapper` | callable wrappers | C | replacement | `test/test_static_sampler.jl` | not needed | Julia closures/callable objects replace arg/kwarg wrappers. |
| `dynesty.internal_samplers.InternalSampler` | `AbstractInternalSampler` | B | planned | `test/test_internal_samplers.jl` | planned | Julia abstract interface replacement. |
| `dynesty.internal_samplers.UniformBoundSampler` | `UniformBoundSampler` | A | planned | `test/test_internal_samplers.jl` | planned | Bound rejection sampler. |
| `dynesty.internal_samplers.UnitCubeSampler` | `UnitCubeSampler` | A | planned | `test/test_internal_samplers.jl` | planned | Unit-cube sampler. |
| `dynesty.internal_samplers.RWalkSampler` | `RWalkSampler` | A | planned | `test/test_internal_samplers.jl` | planned | Random-walk sampler. |
| `dynesty.internal_samplers.SliceSampler` | `SliceSampler` | A | planned | `test/test_internal_samplers.jl` | planned | Slice sampler. |
| `dynesty.internal_samplers.RSliceSampler` | `RSliceSampler` | A | planned | `test/test_internal_samplers.jl` | planned | Random-direction slice sampler. |
| `dynesty.internal_samplers.generic_random_walk` | `generic_random_walk` | A | planned | `test/test_internal_samplers.jl` | planned | Proposal kernel. |
| `dynesty.internal_samplers.propose_ball_point` | `propose_ball_point` | B | planned | `test/test_internal_samplers.jl` | planned | Ball proposal helper. |
| `dynesty.internal_samplers._slice_doubling_accept` | `_slice_doubling_accept` | B | planned | `test/test_internal_samplers.jl` | planned | Slice acceptance helper. |
| `dynesty.internal_samplers.generic_slice_step` | `generic_slice_step` | A | planned | `test/test_internal_samplers.jl` | planned | Slice kernel. |
| `dynesty.internal_samplers.tune_slice` | `tune_slice` | B | planned | `test/test_internal_samplers.jl` | planned | Tuning helper. |
| `dynesty.plotting._make_subplots` | plotting backend setup | C | replacement | `test/test_plotting.jl` | not needed | Recipes/Plots-compatible replacement. |
| `dynesty.plotting.rotate_ticks` | plotting backend setup | C | replacement | `test/test_plotting.jl` | not needed | Matplotlib-specific helper not directly exposed. |
| `dynesty.plotting.plot_thruth` | `plot_truth` | C | planned | `test/test_plotting.jl` | not needed | Name typo kept only if compatibility is useful. |
| `dynesty.plotting.check_span` | `check_span` | B | planned | `test/test_plotting.jl` | planned | Plot range helper. |
| `dynesty.plotting.runplot` | `runplot` | C | planned | `test/test_plotting.jl` | not needed | Plot smoke test. |
| `dynesty.plotting.traceplot` | `traceplot` | C | planned | `test/test_plotting.jl` | not needed | Plot smoke test. |
| `dynesty.plotting.cornerpoints` | `cornerpoints` | C | planned | `test/test_plotting.jl` | not needed | Plot smoke test. |
| `dynesty.plotting.cornerplot` | `cornerplot` | C | planned | `test/test_plotting.jl` | not needed | Plot smoke test. |
| `dynesty.plotting.boundplot` | `boundplot` | C | planned | `test/test_plotting.jl` | not needed | Plot smoke test. |
| `dynesty.plotting.cornerbound` | `cornerbound` | C | planned | `test/test_plotting.jl` | not needed | Plot smoke test. |
| `dynesty.plotting._hist2d` | `_hist2d` | B | planned | `test/test_plotting.jl` | planned | Numerical histogram helper. |
| `dynesty.pool.FunctionCache` | backend task closure | C | replacement | `test/test_parallel.jl` | not needed | Julia map backends replace Python multiprocessing cache. |
| `dynesty.pool.initializer` | backend initialization | C | replacement | `test/test_parallel.jl` | not needed | Julia backend setup. |
| `dynesty.pool.loglike_cache` | backend task closure | C | replacement | `test/test_parallel.jl` | not needed | Julia closures replace global cache. |
| `dynesty.pool.prior_transform_cache` | backend task closure | C | replacement | `test/test_parallel.jl` | not needed | Julia closures replace global cache. |
| `dynesty.pool.Pool` | `SerialMapBackend` / `ThreadedMapBackend` / `DistributedMapBackend` | A | implemented | `test/test_parallel.jl` | not needed | Ordered Julia-native map replacement with queue controls; Python Pool shape intentionally replaced. |
| `dynesty.sampler._get_bound` | `_get_bound` | B | planned | `test/test_static_sampler.jl` | planned | Bound factory. |
| `dynesty.sampler._initialize_live_points` | `_initialize_live_points` | A | planned | `test/test_static_sampler.jl` | planned | Live point initialization. |
| `dynesty.sampler.Sampler` | `NestedSampler` internals | A | planned | `test/test_static_sampler.jl` | planned | Static sampler engine. |
| `dynesty.utils.LoglOutput` | `LoglOutput` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Likelihood output with optional blob. |
| `dynesty.utils.LogLikelihood` | `LogLikelihood` | A | implemented | `test/test_utils.jl` | not needed | Callable wrapper implemented; HDF5 history flushing is extension-backed. |
| `dynesty.utils.RunRecord` | `RunRecord` | B | implemented | `test/test_results.jl` | not needed | Run accumulation. |
| `dynesty.utils.DelayTimer` | `DelayTimer` | C | planned | `test/test_utils.jl` | not needed | Progress-print helper. |
| `dynesty.utils._update_tqdm_eta_from_dlogz` | progress metadata | C | replacement | `test/test_utils.jl` | not needed | TQDM-specific behavior omitted. |
| `dynesty.utils.print_fn` | `print_fn` | C | planned | `test/test_utils.jl` | not needed | Display helper. |
| `dynesty.utils.get_print_fn_args` | `get_print_fn_args` | C | planned | `test/test_utils.jl` | not needed | Display helper. |
| `dynesty.utils.print_fn_tqdm` | progress backend | C | replacement | `test/test_utils.jl` | not needed | TQDM-specific behavior replaced. |
| `dynesty.utils.print_fn_fallback` | `print_fn_fallback` | C | planned | `test/test_utils.jl` | not needed | Display helper. |
| `dynesty.utils.Results` | `Results` | A | implemented | `test/test_results.jl` | planned | Public results container; postprocessing fixture expansion continues in Stage 6. |
| `dynesty.utils.results_substitute` | `results_substitute` | B | implemented | `test/test_results.jl` | planned | Results replacement helper. |
| `dynesty.utils.get_nonbounded` | `get_nonbounded` | B | planned | `test/test_utils.jl` | planned | Bound-type helper. |
| `dynesty.utils.get_print_func` | `get_print_func` | C | planned | `test/test_utils.jl` | not needed | Display helper. |
| `dynesty.utils.get_random_generator` | `get_random_generator` | B | planned | `test/test_utils.jl` | planned | RNG compatibility helper. |
| `dynesty.utils.get_seed_sequence` | `task_seeds` | A | implemented | `test/test_parallel.jl` | not needed | Julia-native deterministic seeds; no cross-language same-seed promise. |
| `dynesty.utils.get_neff_from_logwt` | `get_neff_from_logwt` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Effective sample size. |
| `dynesty.utils.unitcheck` | `unitcheck` | A | implemented | `test/test_utils.jl` | planned | Unit-cube validation. |
| `dynesty.utils.apply_reflect` | `apply_reflect` / `apply_reflect!` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Reflective dimension handling. |
| `dynesty.utils.mean_and_cov` | `mean_and_cov` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Weighted statistics. |
| `dynesty.utils.resample_equal` | `resample_equal` | A | implemented | `test/test_utils.jl` | planned | Equal-weight resampling; statistical fixture expansion remains. |
| `dynesty.utils.quantile` | `quantile` | A | implemented | `test/test_utils.jl` | planned | Weighted quantile. |
| `dynesty.utils._get_nsamps_samples_n` | `_get_nsamps_samples_n` | B | planned | `test/test_results_postprocess.jl` | planned | Post-processing helper. |
| `dynesty.utils._find_decrease` | `_find_decrease` | B | planned | `test/test_results_postprocess.jl` | planned | Post-processing helper. |
| `dynesty.utils.jitter_run` | `jitter_run` | A | planned | `test/test_results_postprocess.jl` | planned | Error estimate helper. |
| `dynesty.utils.compute_integrals` | `compute_integrals` | A | implemented | `test/test_utils.jl` | `test/reference/python/fixtures/utils_core.json` | Evidence integral baseline. |
| `dynesty.utils.progress_integration` | `progress_integration` | A | implemented | `test/test_utils.jl` | planned | Running evidence integration. |
| `dynesty.utils.resample_run` | `resample_run` | A | planned | `test/test_results_postprocess.jl` | planned | Run resampling. |
| `dynesty.utils.reweight_run` | `reweight_run` | A | planned | `test/test_results_postprocess.jl` | planned | Importance reweighting. |
| `dynesty.utils.unravel_run` | `unravel_run` | A | planned | `test/test_results_postprocess.jl` | planned | Run unraveling. |
| `dynesty.utils.merge_runs` | `merge_runs` | A | planned | `test/test_results_postprocess.jl` | planned | Run merge. |
| `dynesty.utils.check_result_static` | `check_result_static` | A | planned | `test/test_results_postprocess.jl` | planned | Result validator. |
| `dynesty.utils.kld_error` | `kld_error` | A | planned | `test/test_results_postprocess.jl` | planned | KLD error estimate. |
| `dynesty.utils._prepare_for_merge` | `_prepare_for_merge` | B | planned | `test/test_results_postprocess.jl` | planned | Merge helper. |
| `dynesty.utils._merge_two` | `_merge_two` | B | planned | `test/test_results_postprocess.jl` | planned | Merge helper. |
| `dynesty.utils._kld_error` | `_kld_error` | B | planned | `test/test_results_postprocess.jl` | planned | KLD helper. |
| `dynesty.utils.restore_sampler` | `restore_sampler` | A | implemented | `test/test_persistence.jl` | not needed | Julia Serialization checkpoint restore; requires user functions again. |
| `dynesty.utils.save_sampler` | `save_sampler` / `checkpoint!` | A | implemented | `test/test_persistence.jl` | not needed | Julia Serialization checkpoint save. |
| `dynesty.utils._parse_pool_queue` | `_normalize_queue_size` | B | implemented | `test/test_parallel.jl` | not needed | Julia backend queue parsing. |
