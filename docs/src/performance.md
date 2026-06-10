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

Benchmarks will live in `benchmark/benchmarks.jl` and will not run as part of
default `Pkg.test()`.

