# Examples

Julia examples live in `examples/` and are smoke-tested by
`test/test_examples.jl`. They are intentionally dependency-light and avoid
requiring plotting packages in the default test suite.

| Example | Coverage |
| --- | --- |
| `examples/overview.jl` | Static nested sampling overview with a two-dimensional Gaussian likelihood. |
| `examples/dynamic_nested_sampling.jl` | Dynamic nested sampling with one adaptive batch. |
| `examples/errors.jl` | Evidence-error post-processing with `jitter_run` and `resample_run`. |
| `examples/gaussian.jl` | Gaussian posterior summary using posterior importance weights. |
| `examples/eggbox.jl` | Multimodal eggbox likelihood smoke run. |
| `examples/gaussian_shells.jl` | Two-shell likelihood smoke run. |
| `examples/high_dimensional_gaussian.jl` | Higher-dimensional Gaussian smoke run. |

Each example defines `main(; kwargs...)` and only prints a compact summary when
executed directly as a script.
