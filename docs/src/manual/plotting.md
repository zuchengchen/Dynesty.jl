# Plotting Data

The core package depends on RecipesBase but does not require Plots.jl.
Plotting helpers produce backend-neutral data objects with recipes:

- [`runplot`](@ref) / [`RunPlotData`](@ref)
- [`traceplot`](@ref) / [`TracePlotData`](@ref)
- [`cornerpoints`](@ref) / [`CornerPointsData`](@ref)
- [`cornerplot`](@ref) / [`CornerPlotData`](@ref)
- [`boundplot`](@ref) / [`BoundPlotData`](@ref)
- [`cornerbound`](@ref) / [`CornerBoundData`](@ref)

```julia
data = runplot(results(sampler))
```

Pass the returned object to a RecipesBase-compatible plotting backend such as
Plots.jl in user code. Default package tests validate the data preparation and
recipes without making Plots.jl a core dependency.

For `boundplot` and `cornerbound`, `show_live=true` reconstructs static live
points from static `Results`. Dynamic `Results` can draw saved bounds with
`show_live=false`.
