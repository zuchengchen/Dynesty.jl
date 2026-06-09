# Dynesty.jl

Dynesty.jl is a Julia-native migration of the adjacent Python
[`dynesty`](../dynesty) project. The migration target is a complete Julia
package named `Dynesty` whose behavior, algorithms, tests, examples,
documentation, and citations align with Python dynesty while using idiomatic
Julia APIs.

This repository is in an active staged migration. Stage 0 has initialized the
package skeleton, source snapshot, compatibility notes, migration matrix, CI
workflow, and a minimal load test. Numerical samplers, bounds, persistence,
parallel execution, plotting, examples, and full documentation are tracked in
[`docs/migration_matrix.md`](docs/migration_matrix.md) and will be implemented
stage by stage.

## Current API

The package currently exposes citation helpers:

```julia
using Dynesty

println(get_citations())
citations()
```

The intended Julia-native sampler API will prefer mutating forms such as
`run_nested!(sampler)`, `checkpoint!(sampler, path)`, and
`add_live_points!(sampler)`, with low-cost compatibility aliases where helpful.

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

