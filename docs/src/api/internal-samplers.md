# Internal Samplers

The internal sampler API is exported for advanced users and mirrors the
proposal mechanisms used by `NestedSampler`.

Public types:

- `SamplerArgument`
- `SamplerReturn`
- `UnitCubeSampler`
- `UniformBoundSampler`
- `RWalkSampler`
- `SliceSampler`
- `RSliceSampler`

Public operations:

- `sample`
- `propose_ball_point`
- `generic_random_walk`
- `generic_slice_step`
- `tune_slice`
