# Examples

Julia examples live in `examples/` and are smoke-tested by
`test/test_examples.jl`. They are intentionally dependency-light and avoid
requiring plotting packages in the default test suite.

| Example | Coverage |
| --- | --- |
| `examples/overview.jl` | Static nested sampling overview with a two-dimensional Gaussian likelihood. |
| `examples/dynamic_nested_sampling.jl` | Dynamic nested sampling with one adaptive batch. |
| `examples/minimal_corner.jl` | Minimal complete posterior run with equal-weight samples and an optional Plots.jl corner plot. |
| `examples/errors.jl` | Evidence-error post-processing with `jitter_run` and `resample_run`. |
| `examples/gaussian.jl` | Gaussian posterior summary using posterior importance weights. |
| `examples/eggbox.jl` | Multimodal eggbox likelihood smoke run. |
| `examples/gaussian_shells.jl` | Two-shell likelihood smoke run. |
| `examples/high_dimensional_gaussian.jl` | Higher-dimensional Gaussian smoke run. |
| `examples/exponential_wave.jl` | Dynamic seven-parameter exponential-wave demo with periodic phase dimensions. |
| `examples/hyper_pyramid.jl` | Hyper-pyramid likelihood demo. |
| `examples/linear_regression.jl` | Straight-line regression with fractional scatter. |
| `examples/loggamma.jl` | Log-gamma mixture likelihood. |
| `examples/noisy_likelihoods.jl` | Dynamic nested sampling with a deterministic noisy-likelihood correction. |
| `examples/importance_reweighting.jl` | Dynamic run reweighted from an independent Gaussian to a correlated Gaussian. |
| `examples/correlated_normal_25d.jl` | 25-D correlated normal with random-slice proposals. |
| `examples/feature_overview.jl` | Julia counterpart to the Python 3.0 feature overview: object samplers/bounds, proposal stats, and plotting data. |
| `examples/pe_parallel_julia.jl` | Threaded Dynesty.jl side of a 4-D parameter-estimation comparison using full-chain proposal/evolve queue parallelism; writes weighted posterior CSV/JSON. |
| `examples/pe_parallel_python.py` | Python dynesty `Pool` side of the same 4-D PE problem using `../dynesty/py`; writes weighted posterior CSV/JSON. |
| `examples/pe_parallel_corner.py` | Overlays the Julia and Python weighted posteriors in one corner plot. |

Each example defines `main(; kwargs...)` and only prints a compact summary when
executed directly as a script.

`examples/minimal_corner.jl` is the shortest complete posterior-and-corner
workflow. It uses the separate examples environment so Plots.jl remains an
example dependency rather than a core package dependency:

```bash
julia --project=examples -e 'using Pkg; Pkg.instantiate()'
julia --project=examples examples/minimal_corner.jl
```

Run the same example with Julia threads and the sampler's threaded map backend:

```bash
julia --threads=4 --project=examples examples/minimal_corner.jl \
    --parallel threads --queue-size 4
```

The companion notebook `examples/minimal_corner.ipynb` contains the same
serial and threaded workflows. Start its Julia kernel with multiple threads to
run the threaded notebook cell. The script writes
`examples/output/minimal_corner.png`; the threaded notebook cell writes
`examples/output/minimal_corner_parallel.png`.

The PE parallel comparison is intentionally kept out of the default
`test/test_examples.jl` loop because the full run is longer and requires Python
plotting packages. A quick smoke run is:

```bash
OPENBLAS_NUM_THREADS=1 JULIA_NUM_THREADS=2 julia --project=. \
    examples/pe_parallel_julia.jl --quick --queue-size 2 --likelihood-cost medium
OPENBLAS_NUM_THREADS=1 python examples/pe_parallel_python.py \
    --quick --nproc 2 --queue-size 2
python examples/pe_parallel_corner.py --quick
```

For denser posterior samples suitable for inspection, use the full settings:

```bash
OPENBLAS_NUM_THREADS=1 julia --threads=31 --project=. \
    examples/pe_parallel_julia.jl --nlive 3000 --dlogz 0.01 --queue-size 31 \
    --output-dir examples/output/pe_parallel_compare_fullchain
OPENBLAS_NUM_THREADS=1 python examples/pe_parallel_python.py \
    --nlive 3000 --dlogz 0.01 --nproc 31 --queue-size 31 \
    --output-dir examples/output/pe_parallel_compare_fullchain
python examples/pe_parallel_corner.py --nsamples-plot 15000 \
    --output-dir examples/output/pe_parallel_compare_fullchain
```

`examples/pe_parallel_julia.jl` records `proposal_evolve_parallel`,
`proposal_tasks_submitted`, `proposal_batches_submitted`, and `parallel_stats`
in its metadata and errors if a queued threaded run never submits
proposal/evolve work through the backend. Use
`--likelihood-cost cheap|medium|heavy`, `--work-size`, or `--sleep-ms` to
separate scheduling overhead from likelihood cost. For cheap likelihoods,
compare serial runs, smaller `queue_size` values, and
`proposal_scheduler=:async` while watching `proposal_backend_wall_time` and
`proposal_queue_wait_wall_time`. Outputs go to `examples/output/`, which should
remain uncommitted.
