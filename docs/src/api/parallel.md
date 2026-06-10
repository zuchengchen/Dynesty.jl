# Parallelism

`NestedSampler` and `DynamicSampler` accept Julia-native sampler-level parallel
configuration:

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
backend is used according to a [`PoolUsage`](@ref) policy. By default, the
backend is enabled for initial live-point prior-transform/likelihood
evaluation and for the proposal/evolve queue. Bound updates and dynamic
stopping-function evaluation remain serial unless opted in by policy.

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    parallel=:threads,
    queue_size=4,
    pool_usage=PoolUsage(proposals=true, bounds=false, stopping=false),
)
```

For Python-adjacent migration code, `use_pool` dictionaries or named tuples are
accepted and parsed into `PoolUsage`:

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    parallel=:threads,
    queue_size=4,
    use_pool=Dict("propose_point" => true, "update_bound" => false),
)
```

`use_pool` recognizes `prior_transform`, `loglikelihood`/`logl`,
`propose_point`/`proposal`, `update_bound`, and `stop_function`. Passing both
`pool_usage` and `use_pool` raises `ArgumentError`.

When `queue_size > 1` and proposal use is enabled, `run_nested!` fills a
proposal/evolve queue through the backend, with one independent task RNG per
candidate. The main sampler consumes candidate results and updates live points,
evidence, bounds, counters, and tuning state serially.

Queued candidates are generated from a snapshot of the current bound,
internal-sampler configuration, and selected live point. If a later iteration
has a higher likelihood threshold, the candidate is still checked against that
new threshold before acceptance. Stage 1 pool usage policy records the
`bounds` and `stopping` switches; later parallel refinement stages use those
opt-in flags for bound-update bootstrap work and dynamic stopping Monte Carlo
work.

Reproducibility is guaranteed for the same Julia seed, backend kind, backend
configuration, thread count, `queue_size`, and `PoolUsage`. Trajectories are
not required to match across backends or with Python dynesty, and changing
`queue_size` or pool usage can change accepted proposals. Checkpoints save
backend configuration, pool usage policy, and proposal queue counters rather
than worker process objects; restored distributed backends only use worker IDs
that are live in the current Julia session and otherwise fall back to serial
ordered-map execution.

Distributed proposal/evolve queue coverage is available as an extended test:
set `DYNESTY_RUN_DISTRIBUTED_TESTS=true` before running the test suite.

```@docs
map_ordered
map_with_rng
task_seeds
PoolUsage
```

Public backend and error types:

- `SerialMapBackend`
- `ThreadedMapBackend`
- `DistributedMapBackend`
- `MapTaskError`
