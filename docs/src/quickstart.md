# Quickstart

Run a static nested-sampling problem by defining a log-likelihood, a prior
transform from the unit cube, and the dimensionality:

```@example quickstart
using Dynesty
using Random

prior_transform(u) = [-5.0 + 10.0 * u[1], -5.0 + 10.0 * u[2]]
loglikelihood(v) = -0.5 * (v[1]^2 + v[2]^2)

sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    2;
    nlive=40,
    bound=:single,
    sample=:unif,
    rng=MersenneTwister(11),
)
run_nested!(sampler; maxiter=45, dlogz=nothing, print_progress=false)
res = results(sampler)
(logz=res.logz[end], nsamples=length(res.logl))
```

See [Getting Started](manual/getting-started.md) for more context and the
repository `examples/` directory for smoke-tested scripts.
