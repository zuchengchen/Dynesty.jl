# Errors

Dynesty.jl uses Julia exception types while keeping messages focused on
parameter names, shapes, and expected ranges.

Common categories include:

- `ArgumentError` for invalid options such as unsupported `bound` or `sample`
  values.
- `DimensionMismatch` for arrays whose dimensions do not match `ndim` or the
  number of samples.
- `BoundsError` for 1-based dimension indices outside the valid range.
- `ErrorException` for rare sampler-state failures such as exhausted support.

Examples:

```@example errors
using Dynesty

try
    get_nonbounded(3, [0], nothing)
catch err
    typeof(err), sprint(showerror, err)
end
```

```@example errors
try
    NestedSampler(x -> -sum(abs2, x), identity, 2; bound=:unknown)
catch err
    typeof(err), occursin("bound", sprint(showerror, err))
end
```

Julia APIs use 1-based indices for periodic and reflective dimensions. Python
0-based index lists should be translated at the migration boundary before
calling Dynesty.jl.
