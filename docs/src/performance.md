# Performance Notes

Initial implementation stages prioritize correctness, reproducibility, and
type-stable Julia data structures. Core numerical arrays use `Float64`.

Performance guidelines:

- Keep public result arrays Python-compatible as `nsamples x ndim`.
- Use Julia-friendly internal storage such as `ndim x npoints` where it avoids
  repeated transposes or copies in hot paths.
- Keep conversions explicit, centralized, and tested.
- Avoid `Vector{Any}` and `Dict{String,Any}` in hot paths.
- Use scratch buffers and views where safe.
- Avoid JSON for large arrays.

Benchmarks live in `benchmark/benchmarks.jl` and are not run as part of default
`Pkg.test()`.

Run a quick smoke check with:

```sh
julia --project=benchmark -e 'using Pkg; Pkg.instantiate(); include("benchmark/benchmarks.jl"); main()'
```

Run the full BenchmarkTools suite with:

```sh
DYNESTY_RUN_BENCHMARKS=true julia --project=benchmark -e 'using Pkg; Pkg.instantiate(); include("benchmark/benchmarks.jl"); main()'
```

The suite currently covers a static Gaussian sampler path, a dynamic Gaussian
sampler path with one adaptive batch, and a `save_results`/`load_results`
persistence round trip.
