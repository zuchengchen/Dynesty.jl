# Testing Strategy

Default tests must pass with:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
```

Default CI must not require a live Python installation or the adjacent
`../dynesty` repository. Python behavior checks use committed fixtures generated
from `../dynesty`.

## Test Grades

| Grade | Scope | Required coverage |
| --- | --- | --- |
| A | Public API and core numerical functions | Direct Julia tests and Python fixture cross-checks wherever meaningful |
| B | Internal helpers that affect algorithm behavior | Direct or indirect Julia tests; fixtures when inputs and outputs are stable |
| C | Thin wrappers, display, printing, compatibility aliases, plotting helpers, demo/doc helpers | Caller tests, smoke tests, snapshots, or migration-matrix notes |

## Extended Test Flags

| Environment variable | Purpose |
| --- | --- |
| `DYNESTY_RUN_SLOW_TESTS=true` | Slow integration and Monte Carlo checks |
| `DYNESTY_RUN_PLOT_TESTS=true` | Optional plotting smoke tests |
| `DYNESTY_RUN_EXTENDED_TESTS=true` | Live or heavyweight reference checks |
| `DYNESTY_RUN_DISTRIBUTED_TESTS=true` | Distributed backend tests |
| `DYNESTY_RUN_JET_TESTS=true` | Optional JET.jl checks |
| `DYNESTY_REGENERATE_FIXTURES=true` | Regenerate Python reference fixtures |

## Fixture Policy

Fixtures use JSON for metadata, scalars, tolerances, exception expectations,
descriptions, and statistical summaries. NPZ stores arrays, matrices, and sample
sets. Fixture metadata records the source commit, dirty status, Python version,
NumPy version, SciPy version, fixture generation date, and tolerance rationale.

Deterministic numerical functions default to `rtol=1e-10` and `atol=1e-12`.
Matrix decomposition, covariance, log-determinant, or clustering-order cases may
use `rtol=1e-8` and `atol=1e-10` when justified.

Stage 1 fixtures cover `get_neff_from_logwt`, `get_nonbounded`, `unitcheck`,
`apply_reflect`, `mean_and_cov`, `resample_equal`, `quantile`,
`compute_integrals`, and `progress_integration`. Stage 2 fixtures cover
`UnitCube`, `Ellipsoid`, `MultiEllipsoid`, `RadFriends`, `SupFriends`,
`improve_covar_mat`, `bounding_ellipsoid`, `bounding_ellipsoids`,
`randsphere`, `rand_choice`, determinant guards, recursive multi-ellipsoid
splitting, bootstrap point selection, ellipsoid bootstrap expansion, and
friends radius helpers.
The fixture generator is `test/reference/python/generate_reference.py`;
default tests read JSON files in `test/reference/python/fixtures/`.

Stage 4 internal samplers are tested by invariants and deterministic Julia
seeds rather than Python same-seed fixtures. The migration does not require
cross-language trajectory equality for random proposal kernels.

Stage 5 static sampler tests follow the same randomness policy. They cover
factory defaults, live-point initialization, a Gaussian static run, final live
point handling, blob storage, bound updates, 1-based periodic/reflective
settings, and `.jls` checkpoint restore using deterministic Julia seeds.

Stage 6 results post-processing fixtures cover deterministic `reweight_run`,
`unravel_run`, `merge_runs`, `check_result_static`, `_get_nsamps_samples_n`, and
`_find_decrease` behavior. Random post-processing helpers (`jitter_run`,
`resample_run`, and `kld_error`) are checked by invariants with deterministic
Julia seeds because cross-language trajectory equality is intentionally out of
scope.

Stage 7 dynamic sampler tests cover `DynamicSamplerState`, `compute_weights`,
`weight_function`, the deterministic `n_mc=0` branch of `stopping_function`,
baseline dynamic sampler runs, adaptive batch execution, manual `add_batch!`
runs, dynamic result merging, blobs, saved bounds, and `.jls` checkpoint
restore. The Monte Carlo stopping branch depends on language-specific random
realizations and is checked by Julia reproducibility/invariant coverage rather
than same-seed Python trajectory equality.

Plotting fixtures cover backend-neutral `check_span` and `_hist2d` numerical
preparation. Full rendered plot smoke tests remain optional behind
`DYNESTY_RUN_PLOT_TESTS=true` so Plots.jl is not part of the default test
environment.
