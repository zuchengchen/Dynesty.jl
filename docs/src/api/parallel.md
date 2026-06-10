# Parallelism

`NestedSampler` accepts Julia-native sampler-level parallel configuration:

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    parallel=:threads,
    queue_size=4,
)
```

Use `parallel=:serial`, `parallel=:threads`/`:threaded`, or
`parallel=:distributed`; the matching strings (`"serial"`, `"threads"`,
`"threaded"`, and `"distributed"`) are accepted for Python-adjacent workflows.
Advanced users can pass an explicit backend:

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    map_backend=ThreadedMapBackend(queue_size=4),
)
```

When `map_backend` is explicit, configure `queue_size` on the backend itself;
passing both `map_backend` and `queue_size` raises `ArgumentError`. The sampler
backend is used for initial live-point prior-transform and likelihood
evaluation. Proposal kernels in `run_nested!` currently use the serial internal
sampler path.

Reproducibility is guaranteed for the same Julia seed, backend kind, backend
configuration, and `queue_size`. Trajectories are not required to match across
backends or with Python dynesty. Checkpoints save backend configuration rather
than worker process objects; restored distributed backends only use worker IDs
that are live in the current Julia session and otherwise fall back to serial
ordered-map execution.

```@docs
map_ordered
map_with_rng
task_seeds
```

Public backend and error types:

- `SerialMapBackend`
- `ThreadedMapBackend`
- `DistributedMapBackend`
- `MapTaskError`
