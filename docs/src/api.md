# API

Dynesty.jl exports Julia-native sampler, result, bound, plotting, persistence,
and parallel helper APIs.

Common entry points include [`NestedSampler`](@ref), [`DynamicSampler`](@ref),
[`Results`](@ref), [`LogLikelihood`](@ref), [`LoglOutput`](@ref),
[`checkpoint!`](@ref), [`restore_sampler`](@ref), [`save_results`](@ref), and
[`load_results`](@ref).

Focused API pages are available for:

- [Samplers](api/samplers.md)
- [Bounds](api/bounds.md)
- [Internal Samplers](api/internal-samplers.md)
- [Results](api/results.md)
- [Utilities](api/utilities.md)
- [Plotting](api/plotting.md)
- [Parallelism](api/parallel.md)
