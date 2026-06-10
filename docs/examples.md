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
| `examples/pe_parallel_julia.jl` | Threaded Dynesty.jl side of a 4-D parameter-estimation comparison; writes weighted posterior CSV/JSON. |
| `examples/pe_parallel_python.py` | Python dynesty `Pool` side of the same 4-D PE problem using `../dynesty/py`; writes weighted posterior CSV/JSON. |
| `examples/pe_parallel_corner.py` | Overlays the Julia and Python weighted posteriors in one corner plot. |

Each example defines `main(; kwargs...)` and only prints a compact summary when
executed directly as a script.

The PE parallel comparison is intentionally kept out of the default
`test/test_examples.jl` loop because the full run is longer and requires Python
plotting packages. A quick smoke run is:

```bash
OPENBLAS_NUM_THREADS=1 JULIA_NUM_THREADS=2 julia --project=. \
    examples/pe_parallel_julia.jl --quick --queue-size 2
OPENBLAS_NUM_THREADS=1 python examples/pe_parallel_python.py \
    --quick --nproc 2 --queue-size 2
python examples/pe_parallel_corner.py --quick
```

For denser posterior samples suitable for inspection, use the full settings:

```bash
OPENBLAS_NUM_THREADS=1 julia --threads=31 --project=. \
    examples/pe_parallel_julia.jl --nlive 3000 --dlogz 0.01 --queue-size 31
OPENBLAS_NUM_THREADS=1 python examples/pe_parallel_python.py \
    --nlive 3000 --dlogz 0.01 --nproc 31 --queue-size 31
python examples/pe_parallel_corner.py --nsamples-plot 15000
```

Outputs go to `examples/output/pe_parallel_compare/`, which should remain
uncommitted.
