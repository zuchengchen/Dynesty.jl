# Getting Started

A static nested-sampling run needs a log-likelihood, a prior transform from the
unit cube, and the number of dimensions.

```@example getting-started
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

Public sample matrices use Python dynesty's row-major result convention:
`res.samples` and `res.samples_u` are `nsamples x ndim` matrices. Julia user
functions receive one-dimensional vectors.

For longer examples, see the repository `examples/` directory:

- `overview.jl`
- `gaussian.jl`
- `eggbox.jl`
- `gaussian_shells.jl`
- `high_dimensional_gaussian.jl`
