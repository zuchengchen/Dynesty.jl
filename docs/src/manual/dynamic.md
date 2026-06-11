# Dynamic Sampling

`DynamicSampler` runs an initial baseline nested-sampling pass and can add
adaptive batches.

```@example dynamic
using Dynesty
using Random

prior_transform(u) = [2.0 * u[1] - 1.0, 2.0 * u[2] - 1.0]
loglikelihood(v) = -0.5 * ((v[1] / 0.18)^2 + (v[2] / 0.32)^2)

sampler = DynamicSampler(
    loglikelihood,
    prior_transform,
    2;
    nlive=32,
    bound=:none,
    sample=:unif,
    rng=MersenneTwister(22),
)
run_nested!(
    sampler;
    maxiter_init=28,
    dlogz_init=nothing,
    nlive_batch=12,
    maxbatch=1,
    maxiter_batch=10,
    maxcall_batch=500,
    use_stop=false,
    print_progress=false,
)
res = results(sampler)
(nbatches=length(res.batch_nlive), batches=sort(unique(res.samples_batch)))
```

For explicit control, call `add_batch!` after an initial dynamic run:

```julia
run_nested!(sampler; maxiter_init=50, dlogz_init=nothing)
add_batch!(sampler; nlive=25, mode=:manual, logl_bounds=(-Inf, 0.0))
```

The default [`weight_function`](@ref) chooses likelihood bounds from posterior
and evidence weights, while [`stopping_function`](@ref) combines evidence error
and effective sample size criteria.
