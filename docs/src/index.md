# Dynesty.jl

Dynesty.jl is a Julia-native migration of Python
[`dynesty`](https://dynesty.readthedocs.io/) for static and dynamic nested
sampling. The package follows Julia conventions while preserving Python
dynesty's core algorithms, numerical semantics, result shapes, examples, and
testing strategy where practical.

The public API centers on mutating sampler operations:

```julia
using Dynesty
using Random

prior_transform(u) = [-5 + 10u[1], -5 + 10u[2]]
loglikelihood(v) = -0.5 * sum(abs2, v)

sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    2;
    nlive=100,
    bound=:multi,
    sample=:unif,
    rng=MersenneTwister(1),
)
run_nested!(sampler; maxiter=100, dlogz=nothing)
res = results(sampler)
```

Dynamic nested sampling uses the same conventions:

```julia
dsampler = DynamicSampler(
    loglikelihood,
    prior_transform,
    2;
    nlive=100,
    bound=:multi,
    sample=:unif,
    rng=MersenneTwister(2),
)
run_nested!(
    dsampler;
    maxiter_init=100,
    nlive_batch=50,
    maxbatch=1,
    maxiter_batch=50,
    use_stop=false,
)
dres = results(dsampler)
```

See the manual pages for runnable workflows and the API pages for exported
types and functions.

## Migration Guide

Use [`Migration Guide`](migration_guide.md) for Python-to-Julia and
compatibility-style rewrites. Intentional public behavior differences are
listed in [`Compatibility`](compatibility.md).

## Migration Matrix

The completed source migration is tracked in
[`Migration Matrix`](migration_matrix.md). Examples are in the repository
`examples/` directory and are smoke-tested in the default package test suite.
