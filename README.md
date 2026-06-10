# Dynesty.jl

Dynesty.jl is a Julia-native migration of the adjacent Python
[`dynesty`](../dynesty) project. The migration target is a complete Julia
package named `Dynesty` whose behavior, algorithms, tests, examples,
documentation, and citations align with Python dynesty while using idiomatic
Julia APIs.

This repository is in an active staged migration. The package now includes
Julia-native static and dynamic nested samplers, bounds, internal proposal
samplers, result post-processing, persistence, parallel map backends,
backend-neutral plotting data/recipes, and smoke-tested examples. Remaining
final deliverables are tracked in [`docs/migration_matrix.md`](docs/migration_matrix.md)
and the docs under `docs/`.

## Current API

The package exposes sampler and result APIs using Julia conventions:

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
println(res.logz[end])
```

Dynamic nested sampling is available through `DynamicNestedSampler`/
`DynamicSampler`, with adaptive batches driven by `run_nested!` or explicit
`add_batch!` calls. Citation helpers are available through `get_citations()`
and `citations()`.

Runnable examples are in `examples/` and are covered by
`test/test_examples.jl`.

## Development

Run the default test suite with:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Default CI must not require the adjacent Python repository or a live Python
environment. Python cross-checks will use committed JSON/NPZ fixtures generated
from `../dynesty`.

## Citation

If this package contributes to published work, cite the original dynesty papers
and nested-sampling references. The `get_citations()` helper includes references
for Speagle (2020), Koposov et al. (2024), Skilling nested sampling, Higson
dynamic nested sampling, and bound/sampler method references.
