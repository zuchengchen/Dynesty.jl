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

Major public behavior changes must be discussed before implementation.

