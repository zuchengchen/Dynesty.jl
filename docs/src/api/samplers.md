# Samplers

```@docs
NestedSampler
DynamicSampler
checkpoint!
restore_sampler
save_sampler
```

Additional public sampler operations:

- `DynamicNestedSampler`
- `run_nested!`
- `run_nested`
- `add_live_points!`
- `add_batch!`
- `combine_runs!`
- `results`
- `n_effective`

## Dynamic Helpers

```@docs
compute_weights
weight_function
stopping_function
_configure_batch_sampler
```

Additional dynamic helper types:

- `DynamicSamplerState`
- `DynamicBatchFirstPoint`
- `ConfiguredBatchSampler`
