# FAQ

This page mirrors the user-facing questions covered by Python dynesty's FAQ
and answers them in Dynesty.jl terms.

## Which Sampling Method Should I Use?

Use `sample=:auto` unless you already know the geometry of the target. The
heuristic follows the Python guidance: low-dimensional problems usually do well
with uniform proposals from the current bound, moderate dimensions often
benefit from random walks, and higher-dimensional or curved targets usually
need slice-style proposals.

The explicit Julia options are `:unif`, `:rwalk`, `:slice`, and `:rslice`.
Python strings such as `"rwalk"` are accepted for compatibility.

## Why Does Sampling Slow Down Near The First Bound Update?

The sampler starts in the unit cube before switching to the configured bound
and proposal method. The `first_update` keyword controls when that switch is
allowed:

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    first_update=Dict(:min_eff => 15.0, :min_ncall => 2 * nlive),
)
```

Increasing `update_interval` can reduce bound-construction overhead, while
using more live points can make multimodal or narrow targets easier to track.

## How Do I Add More Samples?

For static runs, start another independent `NestedSampler` run and combine the
results with `merge_runs`. For dynamic runs, continue with `add_batch!`:

```julia
run_nested!(sampler; maxiter_init=100, maxbatch=0)
add_batch!(sampler; mode=:full, nlive=100)
```

`mode=:manual` accepts explicit `logl_bounds=(lower, upper)` when you want to
concentrate a batch in a likelihood range.

## What Should I Do For Many Modes?

Use more live points and `bound=:multi` for ellipsoidal decomposition, or try
friends bounds with `bound=:balls`/`:cubes`. Dynamic runs can add posterior
batches with `add_batch!(sampler; mode=:full)` to improve the chance of
recovering narrow modes.

## Are Infinite Likelihood Bounds A Problem?

No, `-Inf` and `Inf` are ordinary sentinel values for an unconstrained lower or
upper likelihood range. They are only suspicious when your model itself returns
`NaN` or positive `Inf`; Dynesty.jl rejects those values.

## Why Can Evidence Errors Look Odd Early In A Run?

Real-time evidence errors are approximate while prior volume is still being
compressed. Use `jitter_run`, `resample_run`, and `kld_error` on the final
`Results` object for error-analysis workflows.

## Why Do Iteration Or Call Limits Not Stop Exactly At The Number I Set?

Nested sampling checks stopping criteria after proposals are accepted, and
dynamic batches must allocate live points before a batch can be judged. This
matches the Python behavior: limits are caps on the run loop, not a guarantee
that no in-flight proposal work is counted.

## How Many Walks Or Slices Should I Use?

`RWalkSampler` defaults to `ndim + 20` walks, following the same broad rule as
Python dynesty. For higher dimensions or stronger curvature, increase `walks`,
switch to `sample=:rslice`, or tune `slices`.

## How Do I Handle Slow Likelihoods?

Use `parallel=:threads` or an explicit `ThreadedMapBackend`. `queue_size`
controls how many proposal tasks are submitted at once. For process-based
parallelism, use `DistributedMapBackend` and ensure the likelihood and prior
transform are available on every worker.

## How Do I Save Progress?

Use `.jls` checkpoints for sampler state and `.jld2` archives for results:

```julia
checkpoint!(sampler, "sampler.jls")
restored = restore_sampler("sampler.jls"; loglikelihood, prior_transform)
save_results("results.jld2", results(restored))
```

Evaluation history files use HDF5 through the optional `DynestyHDF5Ext`
extension. Load HDF5.jl and wrap the likelihood with `LogLikelihood` to enable
that path.
