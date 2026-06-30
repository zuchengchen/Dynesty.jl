# References And Acknowledgements

Dynesty.jl migrates the algorithms, tests, examples, and documentation of the
local Python dynesty snapshot while keeping a Julia-native API. The package
keeps citation data available at runtime:

```julia
get_citations()
get_citations(format=:bibtex)
get_citations(format=:records)
```

The default citation set includes:

- Speagle (2020), the dynesty release paper.
- Koposov et al., dynesty 3 series development and sampler improvements.
- Skilling (2004), nested sampling.
- Higson et al. (2019), dynamic nested sampling.
- Feroz, Hobson, and Bridges (2009), MultiNest-style ellipsoidal bounds.

Python dynesty's references page also points users to method-specific work for
single ellipsoid bounds, friends bounds, random walks, slice sampling,
PolyChord-style random slice sampling, and nested-sampling error estimates.
Dynesty.jl implements or documents Julia-native replacements for those method
families in the migration matrix and compatibility notes.

Acknowledgements from the Python project carry over: dynesty follows the line
of nested-sampling tools including `nestle`, draws API inspiration from
Bayesian computation packages such as `emcee`, and its plotting concepts are
related to corner-plot workflows. Dynesty.jl replaces the Python Matplotlib
implementation with RecipesBase-compatible plotting data and recipes so the
core package stays lightweight.

## Source Version Context

The local source snapshot used for this migration is recorded in
[`Source Snapshot`](source_snapshot.md). The Python documentation snapshot
contains a dynesty 3.0 changelog noting:

- a refactor that makes sampler implementations easier to extend,
- faster uniform-sampler parallel execution,
- object-style sampler and bound configuration,
- per-iteration proposal statistics,
- optional HDF5 evaluation history for all likelihood calls, and
- removal of the Hamiltonian slice sampler.

Dynesty.jl's matching coverage is documented in
[`Feature Overview`](feature_overview.md), tested in
`test/test_static_sampler.jl`, `test/test_dynamic_sampler.jl`,
`test/test_persistence.jl`, `test/test_plotting.jl`, and smoke-tested through
`examples/feature_overview.jl`.
