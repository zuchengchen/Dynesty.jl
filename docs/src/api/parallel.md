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
evaluation. When `queue_size > 1`, `run_nested!` also fills a proposal/evolve
queue through the same backend, with one independent task RNG per candidate.
The main sampler consumes candidate results and updates live points, evidence,
bounds, counters, and tuning state serially.

Queued candidates are generated from a snapshot of the current bound,
internal-sampler configuration, and selected live point. If a later iteration
has a higher likelihood threshold, the candidate is still checked against that
new threshold before acceptance. Bound updates remain serial in Julia; there is
no Python-style `use_pool["update_bound"]` switch.

Reproducibility is guaranteed for the same Julia seed, backend kind, backend
configuration, thread count, and `queue_size`. Trajectories are not required to
match across backends or with Python dynesty, and changing `queue_size` can
change accepted proposals. Checkpoints save backend configuration and proposal
queue counters rather than worker process objects; restored distributed
backends only use worker IDs that are live in the current Julia session and
otherwise fall back to serial ordered-map execution.

Distributed proposal/evolve queue coverage is available as an extended test:
set `DYNESTY_RUN_DISTRIBUTED_TESTS=true` before running the test suite.

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
