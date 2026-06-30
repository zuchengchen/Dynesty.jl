# Notebook And Demo Coverage

Python dynesty ships tutorial notebooks under `../dynesty/demos`. Dynesty.jl
covers those topics with dependency-light `.jl` scripts in `examples/` and
default smoke tests in `test/test_examples.jl`.

| Python notebook | Julia coverage | Test coverage |
| --- | --- | --- |
| `Demo 1 - Overview.ipynb` | `examples/overview.jl`, quickstart and persistence docs | default example smoke |
| `Demo 2 - Dynamic Nested Sampling.ipynb` | `examples/dynamic_nested_sampling.jl`, dynamic docs | default example smoke |
| `Demo 3 - Errors.ipynb` | `examples/errors.jl`, errors docs | default example smoke |
| `Demo 4 - What is new in 3.0.ipynb` | `examples/feature_overview.jl`, `feature_overview.md` | default example smoke plus persistence/parallel tests |
| `Examples -- 200-D Multivariate Normal.ipynb` | `examples/high_dimensional_gaussian.jl` with fast smoke dimensions | default example smoke |
| `Examples -- 25-D Correlated Normal.ipynb` | `examples/correlated_normal_25d.jl` | default example smoke |
| `Examples -- Eggbox.ipynb` | `examples/eggbox.jl` | default example smoke |
| `Examples -- Exponential Wave.ipynb` | `examples/exponential_wave.jl` | default example smoke |
| `Examples -- Gaussian Shells.ipynb` | `examples/gaussian_shells.jl` | default example smoke |
| `Examples -- Hyper-Pyramid.ipynb` | `examples/hyper_pyramid.jl` | default example smoke |
| `Examples -- Importance Reweighting.ipynb` | `examples/importance_reweighting.jl` | default example smoke |
| `Examples -- Linear Regression.ipynb` | `examples/linear_regression.jl` | default example smoke |
| `Examples -- LogGamma.ipynb` | `examples/loggamma.jl` | default example smoke |
| `Examples -- Noisy Likelihoods.ipynb` | `examples/noisy_likelihoods.jl` | default example smoke |

The example defaults are intentionally smaller than the Python notebooks so
default package tests remain fast and do not require plotting or notebook
execution dependencies. The longer Python-style behavior checks are covered by
fixtures, targeted Julia regression tests, and extended test flags.
