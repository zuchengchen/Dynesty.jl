# Dynesty.jl

Dynesty.jl is a Julia-native migration of the adjacent Python
[`dynesty`](../dynesty) project. It provides a complete Julia package named
`Dynesty` whose behavior, algorithms, tests, examples, documentation, and
citations align with Python dynesty while using idiomatic Julia APIs.

The package includes Julia-native static and dynamic nested samplers, bounds,
internal proposal samplers, result post-processing, persistence, parallel map
backends, backend-neutral plotting data/recipes, smoke-tested examples, and
Documenter.jl documentation. The source migration is tracked in
[`docs/migration_matrix.md`](docs/migration_matrix.md), with intentional
Julia-native differences documented in [`docs/compatibility.md`](docs/compatibility.md).

## Installation and Development

Install the repository version with Julia 1.11 or newer:

```julia
using Pkg
Pkg.add(url="https://github.com/zuchengchen/Dynesty.jl")
```

The same installation can be run from Julia's `pkg>` mode:

```julia-repl
pkg> add https://github.com/zuchengchen/Dynesty.jl
```

The package name `Dynesty` is already registered in Julia's General registry
for another repository, so `pkg> add Dynesty` does not install this repository
version. Use the GitHub URL form above until this repository is registered
under the intended package entry.

For local development from a checkout, activate the repository environment:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
```

The repository does not commit `Manifest.toml`; development, docs, and
benchmark environments resolve their manifests locally.

## Quickstart

The public sampler API follows Julia conventions. Mutating operations use `!`
suffixes, and compatibility aliases such as `run_nested` are available for
low-cost Python-adjacent workflows.

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

## Dynamic Sampling

Dynamic nested sampling is available through `DynamicNestedSampler`, a public
alias for `DynamicSampler`. Adaptive batches are driven by `run_nested!` or by
explicit `add_batch!` calls:

```julia
dsampler = DynamicNestedSampler(
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
    dlogz_init=nothing,
    nlive_batch=50,
    maxbatch=1,
    maxiter_batch=50,
    use_stop=false,
)
dres = results(dsampler)
println(dres.logz[end])
```

## Results and Persistence

`results(sampler)` returns a stable `Results` object with Python-compatible
public array shapes: samples are stored as `nsamples x ndim`, and public live
point views use `nlive x ndim`. Python's `res.blob` field is represented as
`res.blobs` in Julia.

Persistence uses separate storage paths:

- `save_results(path, res)` / `load_results(path)` store result archives with
  JLD2, normally using `.jld2`.
- `checkpoint!(sampler, path)` / `save_sampler(sampler, path)` store sampler
  snapshots with Julia `Serialization`, normally using `.jls`.
- `restore_sampler(path; loglikelihood, prior_transform)` restores sampler
  state and requires user callables to be supplied again.
- HDF5 evaluation history is available through the weak-dependency
  `DynestyHDF5Ext` extension when HDF5.jl is loaded.

## Parallelism

Julia-native ordered map backends cover the Python `Pool` use case without
copying its multiprocessing API:

- `SerialMapBackend`
- `ThreadedMapBackend`
- `DistributedMapBackend`

`queue_size` controls backend task/batch limits, map outputs preserve input
order, and task failures report the failing index with input context.

## Plotting

The core package depends on RecipesBase and does not require Plots.jl. Helpers
such as `runplot`, `traceplot`, `cornerpoints`, `cornerplot`, `boundplot`, and
`cornerbound` return backend-neutral data objects with recipes. `boundplot` and
`cornerbound` draw saved bounds for static and dynamic results; `show_live=true`
is limited to static results with reconstructable live points.

## Examples

Runnable examples are in `examples/` and are covered by
`test/test_examples.jl`.

```sh
julia --project=. examples/overview.jl
julia --project=. examples/gaussian.jl
julia --project=. examples/dynamic_nested_sampling.jl
```

Additional examples cover an eggbox likelihood, Gaussian shells, a
high-dimensional Gaussian, 25-D correlated normal, exponential wave,
hyper-pyramid, linear regression, log-gamma, noisy likelihoods, importance
reweighting, Python 3.0 feature-overview coverage, and error handling.

`examples/minimal_corner.jl` writes a corner plot with Plots.jl using the
separate examples environment:

```sh
julia --project=examples -e 'using Pkg; Pkg.instantiate()'
julia --project=examples examples/minimal_corner.jl
```

Run the same example with Julia threads and the sampler's threaded map backend:

```sh
julia --threads=4 --project=examples examples/minimal_corner.jl \
    --parallel threads --queue-size 4
```

The companion notebook `examples/minimal_corner.ipynb` contains the same
serial and threaded workflows. Start its Julia kernel with multiple threads to
run the threaded notebook cell.

## Python Compatibility

Default tests use committed JSON fixtures generated from the adjacent
read-only `../dynesty` checkout; they do not call Python live. Fixture
generation details and tolerance rationale are documented in
`test/reference/python/README.md`.

Intentional Julia-native differences include 1-based periodic/reflective
dimension indices, `copy_inputs=false` by default for performance, Julia
closures instead of Python `logl_args`/`ptform_args` wrappers, and `.jls`/`.jld2`
persistence rather than pickle archives.

## Development Commands

Run the default test suite with:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Build the documentation with:

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Run the benchmark smoke check with:

```sh
julia --project=benchmark -e 'using Pkg; Pkg.instantiate(); include("benchmark/benchmarks.jl"); main()'
```

Run the full benchmark suite with:

```sh
DYNESTY_RUN_BENCHMARKS=true julia --project=benchmark -e 'using Pkg; Pkg.instantiate(); include("benchmark/benchmarks.jl"); main()'
```

Extended tests are controlled by environment variables such as
`DYNESTY_RUN_SLOW_TESTS=true`, `DYNESTY_RUN_PLOT_TESTS=true`,
`DYNESTY_RUN_DISTRIBUTED_TESTS=true`, and `DYNESTY_RUN_EXTENDED_TESTS=true`.
`DYNESTY_RUN_EXTENDED_TESTS=true` exercises the HDF5 weak-dependency extension
from the test environment without making HDF5 a core dependency.

## Citation

If this package contributes to published work, cite the original dynesty papers
and nested-sampling references. The `get_citations()` helper includes references
for Speagle (2020), Koposov et al. (2024), Skilling nested sampling, Higson
dynamic nested sampling, and bound/sampler method references.
