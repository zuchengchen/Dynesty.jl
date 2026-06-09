# Persistence Design

Dynesty.jl separates persistence into three paths:

| Path | Extension | Backend | Purpose |
| --- | --- | --- | --- |
| Checkpoint/resume | `.jls` | Julia `Serialization` | High-performance sampler snapshots for continuing a Julia run |
| Results/archive | `.jld2` | JLD2 | Portable Julia result archives loaded by `save_results` and `load_results` |
| Evaluation history | `.h5` / `.hdf5` | HDF5.jl weak dependency | Appendable `evaluation_u`, `evaluation_v`, and `evaluation_logl` datasets |

Sampler checkpoints will not save user function bodies. `restore_sampler` must
require users to provide `loglikelihood`, `prior_transform`, and related callable
configuration again. Worker process objects are not serialized.

Checkpoint metadata will include package version, Julia version, backend kind,
configuration, RNG state, bound state, internal sampler state, results state,
live/dead points, proposal statistics, batch/dynamic state, and any documented
options used to skip unserializable blobs or transformed samples.

