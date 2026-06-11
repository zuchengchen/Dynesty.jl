# Migration Guide

Dynesty.jl uses Python dynesty as the algorithm, behavior, workflow, and test
reference. It does not copy Python's public API shape. This guide shows the
main rewrites needed when moving Python dynesty code, or older Dynesty.jl
compatibility-style code, to the strict Julia-native API.

## Mutating Operations

Mutating sampler operations use bang names:

```julia
sampler = NestedSampler(loglikelihood, prior_transform, ndim; nlive=500)
run_nested!(sampler; dlogz=0.01)
res = results(sampler)
checkpoint!(sampler, "sampler.jls")
add_live_points!(sampler)
```

There is no public no-bang `run_nested` alias.

## Symbol Options

Enum-like options are Julia `Symbol`s, not strings:

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    bound=:multi,
    sample=:rwalk,
    parallel=:threads,
    proposal_scheduler=:auto,
)
```

Strings remain appropriate for real text, file paths, plot labels, dataset
names, and free-form metadata.

## Random Number Generators

Use `rng` for random state. It accepts an `AbstractRNG`, an integer seed, or
`nothing` for Julia's default RNG:

```julia
using Random

sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    rng=MersenneTwister(42),
)

seeded = DynamicSampler(loglikelihood, prior_transform, ndim; rng=42)
```

Python-style `rstate` and `random_state` keywords are intentionally rejected.
Same numeric seeds do not imply sample-by-sample equality with Python dynesty,
because Julia and NumPy use different random generators and proposal paths.

## User Function Arguments

Python dynesty often passes extra likelihood or prior-transform arguments
through `logl_args`, `logl_kwargs`, `ptform_args`, or `ptform_kwargs`. In Julia,
capture configuration in a closure or callable object:

```julia
data = (; y=[1.0, 1.5, 2.0], sigma=0.2)

function make_loglikelihood(data)
    return theta -> begin
        model = theta[1] .+ theta[2] .* eachindex(data.y)
        return -0.5 * sum(abs2, (data.y .- model) ./ data.sigma)
    end
end

loglikelihood = make_loglikelihood(data)
prior_transform(u) = [-10.0 + 20.0 * u[1], -5.0 + 10.0 * u[2]]
sampler = NestedSampler(loglikelihood, prior_transform, 2; nlive=300)
```

Callable structs are useful when the configuration is large or shared across
workers:

```julia
struct LinearLogLikelihood{T}
    y::Vector{T}
    sigma::T
end

function (ll::LinearLogLikelihood)(theta)
    model = theta[1] .+ theta[2] .* eachindex(ll.y)
    return -0.5 * sum(abs2, (ll.y .- model) ./ ll.sigma)
end
```

## Indices

Periodic and reflective dimensions are Julia 1-based:

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    3;
    periodic=[1],
    reflective=[3],
)
```

Python 0-based dimension lists are not accepted and there is no public Python
index-conversion helper.

## Results Fields

Public results use Julia-native field names:

```julia
res = results(sampler)
samples = res.samples
blobs = res.blobs
bound_indices = res.boundidx
batch_indices = res.samples_batch
```

Python fixture names such as `blob`, `samples_bound`, and `batch` are converted
only inside test fixture readers. They are not public `Results` aliases.

## Parallel Workflows

Python `Pool` and `use_pool` map to Julia-native map backends and
`ParallelPolicy`:

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    parallel=:threads,
    queue_size=8,
    parallel_policy=ParallelPolicy(
        initialization=true,
        proposals=true,
        bounds=false,
        stopping=false,
    ),
    proposal_scheduler=:auto,
)
```

Use `ThreadedMapBackend` for explicit thread configuration, or
`DistributedMapBackend` when worker processes are appropriate. Ordered map
outputs preserve input order. Reproducibility is guaranteed for the same Julia
seed, backend kind, backend configuration, thread count, `queue_size`,
`ParallelPolicy`, and proposal scheduler; trajectories are not required to
match Python or other backend configurations.

## Input Copying

Dynesty.jl defaults to `copy_inputs=false` for performance. Treat arrays passed
to user functions as read-only, short-lived views or scratch buffers. Set
`copy_inputs=true` when a likelihood or prior transform needs defensive copies:

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    copy_inputs=true,
)
```

## Persistence

Python pickle files are not a Dynesty.jl storage format. Dynesty.jl uses
separate Julia-native paths:

```julia
save_results("results.jld2", results(sampler))
checkpoint!(sampler, "sampler.jls")

restored = restore_sampler(
    "sampler.jls";
    loglikelihood=loglikelihood,
    prior_transform=prior_transform,
)
```

Checkpoints store sampler state and require user callables to be supplied again
when restoring. Old Dynesty.jl checkpoint/archive files from compatibility
stages are not guaranteed to load.

## Plotting

Plotting helpers return backend-neutral data objects with RecipesBase recipes:

```julia
run_data = runplot(res)
trace_data = traceplot(res)
corner_data = cornerplot(res)
bound_data = boundplot(res; dims=(1, 2))
```

The core package does not return Matplotlib figure or axes objects and does not
depend on Plots.jl. Load a plotting backend such as Plots.jl only in scripts or
notebooks that render the recipes.

## Where To Look Next

- `docs/compatibility.md` lists intentional public behavior differences.
- `docs/migration_matrix.md` maps Python dynesty symbols and workflows to
  Julia-native implementations or replacements.
- `docs/examples.md` lists smoke-tested Julia examples and benchmark helpers.
- `test/reference/python/README.md` documents Python fixture generation and
  tolerance rationale.
