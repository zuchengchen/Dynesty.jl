# Feature Overview

This page is the Julia-native counterpart to Python dynesty's "What is new in
3.0" demo notebook.

## Proposal Statistics

`results(sampler)` preserves per-sample `proposal_stats` where proposal
samplers provide them. Random-walk and slice-family samplers populate counts
such as proposals, accepts/rejects, expansions, or contractions depending on
the kernel.

`examples/feature_overview.jl` runs an `RWalkSampler` and reports how many
dead points carried proposal statistics.

## Evaluation History

Dynesty.jl keeps HDF5 history support as an optional weak-dependency extension:

```julia
using Dynesty
using HDF5

ll = LogLikelihood(
    v -> -sum(abs2, v),
    2;
    history_filename="history.h5",
    save_evaluation_history=true,
    save_every=100,
)
sampler = NestedSampler(ll, identity, 2)
run_nested!(sampler; maxiter=100)
```

The extension writes `evaluation_u`, `evaluation_v`, and `evaluation_logl`.
Extended tests verify both manual append behavior and sampler-level
completeness: when enabled, HDF5 row counts match `sampler.ncall`.

## Object-Style Sampler And Bound Configuration

Python dynesty 3.0 accepts sampler and bound objects directly. Dynesty.jl does
the same with Julia types:

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    bound=Ellipsoid(ndim),
    sample=RWalkSampler(; walks=25),
)
```

Strings and symbols remain accepted for compatibility:
`bound=:multi`, `sample=:rslice`, `bound="balls"`.

## Parallel Proposal Queues

The Python 3.0 demo emphasizes faster parallel uniform sampling. Dynesty.jl
covers that use case through ordered Julia map backends and sampler-level
proposal queues:

```julia
sampler = NestedSampler(
    loglikelihood,
    prior_transform,
    ndim;
    parallel=:threads,
    queue_size=4,
    proposal_scheduler=:async,
)
```

`ParallelStats` records submitted proposal tasks, backend wall time, queue
wait time, bound-update backend time, and dynamic stopping-function backend
time. Distributed coverage is gated behind `DYNESTY_RUN_DISTRIBUTED_TESTS`.

## Custom Interfaces

Custom bounds subtype `AbstractBound`; custom proposal samplers subtype
`AbstractInternalSampler`. The Julia API keeps the same extension points while
using multiple dispatch and mutating `!` functions instead of Python subclass
hooks such as `prepare_sampler`.

## Removed Or Intentionally Replaced Python Features

The Hamiltonian slice sampler removed from Python dynesty 3.0 is not recreated
in Dynesty.jl. Python multiprocessing `Pool` objects are replaced by
`SerialMapBackend`, `ThreadedMapBackend`, and `DistributedMapBackend`. Python
Matplotlib figures are replaced by RecipesBase-compatible data objects and
recipes.
