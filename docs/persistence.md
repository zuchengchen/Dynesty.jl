# Persistence Design

Dynesty.jl separates persistence into three paths:

| Path | Extension | Backend | Purpose |
| --- | --- | --- | --- |
| Checkpoint/resume | `.jls` | Julia `Serialization` | High-performance sampler snapshots for continuing a Julia run |
| Results/archive | `.jld2` | JLD2 | Portable Julia result archives loaded by `save_results` and `load_results` |
| Evaluation history | `.h5` / `.hdf5` | HDF5.jl weak dependency | Appendable `evaluation_u`, `evaluation_v`, and `evaluation_logl` datasets |

Sampler checkpoints do not save user function bodies. `restore_sampler`
requires users to provide `loglikelihood`, `prior_transform`, and related
callable configuration again. Worker process objects are not serialized.

Checkpoint metadata includes package version, Julia version, backend kind,
configuration, RNG state, bound state, internal sampler state, results state,
live/dead points, proposal statistics, batch/dynamic state, and documented
options used to skip unserializable blobs or transformed samples.

## Status

Implemented:

- `save_results(path, res)` / `load_results(path)` using `.jld2`.
- `save_sampler(sampler, path)` / `checkpoint!(sampler, path)` using `.jls`.
- `restore_sampler(path; loglikelihood, prior_transform)` with required
  callable reattachment.
- Metadata for package version, Julia version, checkpoint format version, and
  skipped user-function fields.
- Native `NestedSampler` and `DynamicSampler` snapshots, including RNG state,
  bounds, live/dead samples, proposal statistics, batch metadata, and restored
  dynamic/static sampler objects with reattached callables.
- HDF5 evaluation-history flushing through the `DynestyHDF5Ext` weak-dependency
  extension when HDF5.jl is loaded. The extension appends
  `evaluation_u`, `evaluation_v`, and `evaluation_logl` datasets.
