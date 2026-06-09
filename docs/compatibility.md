# Compatibility Notes

Dynesty.jl aims to align behavior, algorithms, numerical semantics, and edge
cases with Python dynesty unless an intentional Julia-native difference is
documented here.

| Area | Python behavior | Julia behavior | Reason | Affected tests |
| --- | --- | --- | --- | --- |
| Mutating APIs | Methods such as `run_nested` mutate sampler state. | Public Julia API will prefer `run_nested!`, `checkpoint!`, and `add_live_points!`; compatibility aliases may call the bang forms. | Julia convention makes mutation explicit. | Stage 5 sampler tests |
| Dimension indices | Periodic and reflective dimensions use Python 0-based indices. | Julia APIs use 1-based indices. `from_python_indices` may be provided for explicit conversion. | Preserve Julia indexing semantics and avoid implicit off-by-one conversions. | Stage 4 periodic/reflective tests and fixtures |
| User input arrays | Python dynesty defensively copies arrays before calling user functions. | Dynesty.jl will default to `copy_inputs=false`; `copy_inputs=true` will request Python-like safety. | Performance-first Julia hot paths with documented read-only input contract. | Stage 5 likelihood/prior-transform tests |
| Result blob field | Python uses `res.blob`. | Julia results will use `res.blobs`. | Julia field should describe the collection of per-sample blobs. | Stage 1 results tests and Stage 5 blob tests |
| Pool semantics | Python exposes a `Pool` wrapper and `use_pool` controls. | Julia will expose `SerialMapBackend`, `ThreadedMapBackend`, and `DistributedMapBackend` with `queue_size`. | Match Julia execution models instead of copying Python multiprocessing surface shape. | Stage 1 parallel tests |
| Plotting | Python plotting targets Matplotlib. | Julia plotting will use RecipesBase-compatible recipes and optional Plots.jl smoke tests. | Avoid a heavy plotting dependency in the core package. | Stage 8 plot tests |
| Persistence | Python sampler save/restore uses pickle and h5py-style evaluation history. | Dynesty.jl checkpoints use Julia Serialization `.jls`, results use JLD2 `.jld2`, and HDF5 evaluation history is optional via extension. | Match Julia performance and package ecosystem while documenting archival limits. | Stage 1 persistence tests |
| SupFriends centers | Python sampler sets `ctrs` externally before sampling; `SupFriends.update` does not assign centers directly. | Julia `update!(::SupFriends, points)` stores centers, matching `RadFriends` and making the bound self-contained. | Julia bounds should be valid immediately after update and still align with sampler behavior. | `test/test_bounding_friends.jl` |
| Static sampler bootstrap defaults | Python uses bootstrap expansion automatically for uniform ellipsoidal bounds. | Stage 5 maps that automatic case to deterministic enlargement and rejects explicit `bootstrap > 0` with a clear error until ellipsoid bootstrap helpers are migrated. | Keep the static sampler runnable while the migration matrix still tracks `_bootstrap_points` and ellipsoid bootstrap expansion as planned work. | `test/test_static_sampler.jl` |
| Static sampler random trajectories | Python and Julia use different RNGs and proposal implementations. | Static sampler tests check invariants, result shapes, finite evidence traces, blobs, bound updates, and checkpoint restore rather than same-seed sample-by-sample equality. | Cross-language trajectory equality is not required by the migration policy. | `test/test_static_sampler.jl` |

Major public behavior changes must be discussed before implementation.
