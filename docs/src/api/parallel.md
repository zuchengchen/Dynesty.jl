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
    proposal_scheduler=:batch,
)
```

Use `parallel=:serial`, `parallel=:threads`/`:threaded`, or
`parallel=:distributed`. These options are Symbols; strings are rejected.
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
backend is used according to a [`ParallelPolicy`](@ref) policy. By default, the
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
    parallel_policy=ParallelPolicy(proposals=true, bounds=false, stopping=false),
)
```

`ParallelPolicy` accepts Julia-native field names: `initialization`,
`proposals`, `bounds`, and `stopping`. Python `use_pool` dictionaries are not
part of the Dynesty.jl API.

When `queue_size > 1` and proposal use is enabled, `run_nested!` fills a
proposal/evolve queue through the backend, with one independent task RNG per
candidate. The main sampler consumes candidate results and updates live points,
evidence, bounds, counters, and tuning state serially.

Queued candidates are generated from a snapshot of the current bound,
internal-sampler configuration, and selected live point. If a later iteration
has a higher likelihood threshold, the candidate is still checked against that
new threshold before acceptance.

The proposal scheduler defaults to `proposal_scheduler=:batch`, which maps a
full queue of candidates and then consumes that queue in order. Threaded runs
can opt into `proposal_scheduler=:async` to keep proposal tasks in flight while
the main sampler consumes completed ordered results. `proposal_scheduler=:auto`
currently uses the async path for threaded backends and the batch path for
serial, distributed, and custom backends. Async tasks are not serialized in
checkpoints; checkpointing drains outstanding threaded tasks before writing the
ordinary sampler snapshot.

Bound refreshes remain serial by default. With
`parallel_policy=ParallelPolicy(bounds=true)`, built-in ellipsoid and friends
bounds can use the configured backend for bootstrap tasks when `bootstrap > 0`.
The bound object itself is still mutated only on the main sampler task; backend
workers receive point-matrix snapshots and deterministic per-task RNGs. Custom
bounds and non-bootstrap bound refreshes continue to run serially.

Dynamic stopping checks also remain serial by default. With
`parallel_policy=ParallelPolicy(stopping=true)`, the default
[`stopping_function`](@ref) uses the configured backend for its Monte Carlo
error realizations when `n_mc > 1`. The results object is passed read-only to
each task, and custom stop functions keep the existing serial call path unless
they explicitly implement their own mapping behavior.

Reproducibility is guaranteed for the same Julia seed, backend kind, backend
configuration, thread count, `queue_size`, `ParallelPolicy`, and
`proposal_scheduler`. Trajectories are
not required to match across backends or with Python dynesty, and changing
`queue_size`, parallel policy, or scheduler can change accepted proposals.
Checkpoints save backend configuration, parallel policy, proposal scheduler,
and proposal queue counters rather than worker process objects; restored
distributed backends only use worker IDs that are live in the current Julia
session and otherwise fall back to serial ordered-map execution.

## Instrumentation

Samplers maintain lightweight [`ParallelStats`](@ref) counters in
`sampler.parallel_stats`, and `results(sampler)` includes the same information
as `res.parallel_stats`. Times are wall-clock seconds measured in the Julia
process. They are intended for within-run diagnostics, not precise
cross-machine benchmarks.

Key fields include:

- `initial_evaluation_count`, `initial_evaluation_tasks`, and
  `initial_evaluation_wall_time` for initial live-point setup.
- `proposal_tasks_submitted`, `proposal_batches_submitted`,
  `proposal_wall_time`, and `proposal_backend_wall_time` for proposal/evolve
  queue work.
- `proposal_queue_wait_wall_time` for time the async scheduler spends waiting
  for the next ordered threaded proposal task.
- `bound_update_count`, `bound_update_wall_time`, and
  `bound_update_backend_wall_time` for bound refreshes and opt-in bootstrap
  backend work.
- `stop_function_count` and `stop_function_wall_time` for dynamic stopping
  checks, plus `stop_function_backend_wall_time` for opt-in default
  stopping-function Monte Carlo backend work.
- `map_backend_calls` and `map_backend_wall_time` for backend calls visible to
  the sampler instrumentation.

Backend wall-time fields include the time spent inside the backend map call as
observed by the caller; threaded and distributed backends are not directly
comparable without considering worker count, serialization, and user-function
cost.

For very cheap likelihoods, parallel scheduling can dominate useful work.
Dynesty.jl does not silently change queue size or scheduler at runtime; instead
it records the timing fields above and may emit a one-time hint when observed
proposal tasks are extremely cheap. Compare `proposal_backend_wall_time`,
`proposal_queue_wait_wall_time`, and total sampler runtime before choosing
between serial execution, a smaller `queue_size`, `proposal_scheduler=:batch`,
and `proposal_scheduler=:async`.

## Distributed Workers

`DistributedMapBackend` uses Julia workers and `Distributed.pmap`. Start
workers with the same project, load `Dynesty` on each worker, and make
likelihood/prior callables available on every worker, usually as top-level
functions or serializable callable structs. Captured closures can work only
when all captured values are serializable and available to the worker process.

```julia
using Distributed
addprocs(4; exeflags=`--project=$(Base.active_project())`)
@everywhere using Dynesty
@everywhere prior_transform(u) = copy(u)
@everywhere loglikelihood(v) = -sum(abs2, v .- 0.5)

backend = DistributedMapBackend(workers=workers(), queue_size=4)
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    2;
    map_backend=backend,
)
```

If configured worker IDs are not live in the current session, ordered maps fall
back to serial execution. Checkpoints save only worker IDs and backend
configuration, not worker process objects or pending tasks. Restore a
distributed checkpoint after creating/loading compatible workers, or replace
the backend after restore if serial/threaded execution is desired. Distributed
task errors include the task index, compact input context, and a worker setup
hint.

Distributed proposal/evolve queue coverage is available as an extended test:
set `DYNESTY_RUN_DISTRIBUTED_TESTS=true` before running the test suite.

```@docs
map_ordered
map_with_rng
task_seeds
ParallelPolicy
ParallelStats
```

Public backend and error types:

- `SerialMapBackend`
- `ThreadedMapBackend`
- `DistributedMapBackend`
- `MapTaskError`
