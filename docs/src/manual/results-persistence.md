# Results and Persistence

Use `results` to convert sampler state into a user-facing
[`Results`](@ref) object. `Results` supports property access and dictionary-like
access:

```@example results
using Dynesty
using Random

prior_transform(u) = [u[1]]
loglikelihood(v) = -0.5 * ((v[1] - 0.4) / 0.08)^2

sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    1;
    nlive=35,
    bound=:none,
    sample=:unif,
    rng=MersenneTwister(33),
)
run_nested!(sampler; maxiter=35, dlogz=nothing, print_progress=false)
res = results(sampler)
(neff=n_effective(sampler), logz=res[:logz][end])
```

Post-processing helpers include `importance_weights`, `samples_equal`,
`jitter_run`, `resample_run`, `reweight_run`, `merge_runs`, and `kld_error`.

Result archives and sampler checkpoints use separate paths:

```julia
save_results("run.jld2", res)
checkpoint!(sampler, "sampler.jls")
restored = restore_sampler(
    "sampler.jls";
    loglikelihood=loglikelihood,
    prior_transform=prior_transform,
)
```

See [`Persistence`](../persistence.md) for the storage policy and compatibility
limits.
