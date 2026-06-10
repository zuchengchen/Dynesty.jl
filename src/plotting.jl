using RecipesBase

"""
    check_span(span, samples; weights=nothing)

Normalize plotting spans. Entries that are two-element iterables are preserved
as bounds. Scalar entries are interpreted as equal-tailed credible fractions
and converted with [`quantile`](@ref), matching Python dynesty's plotting
helper. Unlike Python, this returns a new vector instead of mutating `span`.
"""
function check_span(span, samples; weights=nothing)
    spans = collect(span)
    data = _span_sample_vectors(samples)
    length(spans) == length(data) || throw(
        DimensionMismatch(
            "span length $(length(spans)) != number of sample dimensions $(length(data))",
        ),
    )
    out = Vector{Tuple{Float64, Float64}}(undef, length(spans))
    for i in eachindex(spans)
        value = spans[i]
        if value isa Number
            frac = Float64(value)
            0.0 < frac <= 1.0 ||
                throw(ArgumentError("span fractions must be in (0, 1]; got $frac"))
            q = quantile(data[i], [0.5 - 0.5 * frac, 0.5 + 0.5 * frac]; weights)
            out[i] = (Float64(q[1]), Float64(q[2]))
        else
            vals = Float64.(collect(value))
            length(vals) == 2 ||
                throw(ArgumentError("span entries must be scalars or length-2 bounds"))
            out[i] = (vals[1], vals[2])
        end
    end
    return out
end

function _span_sample_vectors(samples)
    if samples isa AbstractMatrix
        if size(samples, 1) <= size(samples, 2)
            return [vec(samples[i, :]) for i in axes(samples, 1)]
        else
            return [vec(samples[:, i]) for i in axes(samples, 2)]
        end
    elseif samples isa AbstractVector
        if isempty(samples)
            throw(ArgumentError("samples must not be empty"))
        elseif first(samples) isa AbstractVector
            return [Float64.(collect(s)) for s in samples]
        else
            return [Float64.(samples)]
        end
    else
        throw(ArgumentError("samples must be a vector or matrix"))
    end
end

"""
    Hist2DResult

Data returned by [`_hist2d`](@ref): bin centers, raw/smoothed density, contour
thresholds, padded contour grids, and the resolved plotting spans.
"""
struct Hist2DResult
    xcenters::Vector{Float64}
    ycenters::Vector{Float64}
    density::Matrix{Float64}
    levels::Vector{Float64}
    xextended::Vector{Float64}
    yextended::Vector{Float64}
    density_extended::Matrix{Float64}
    span::Vector{Tuple{Float64, Float64}}
end

"""
    _hist2d(x, y; smooth=0.02, span=nothing, weights=nothing, levels=nothing)

Prepare a weighted 2-D histogram and contour thresholds for corner-style plots.
This is the numerical core of Python dynesty's `_hist2d`; rendering is exposed
through a RecipesBase recipe on `Hist2DResult`.
"""
function _hist2d(
    x::AbstractVector{<:Real},
    y::AbstractVector{<:Real};
    smooth=0.02,
    span=nothing,
    weights=nothing,
    levels=nothing,
)
    length(x) == length(y) ||
        throw(DimensionMismatch("x length $(length(x)) != y length $(length(y))"))
    isempty(x) && throw(ArgumentError("x and y must contain at least one sample"))
    weights_v = isnothing(weights) ? ones(Float64, length(x)) : Float64.(weights)
    length(weights_v) == length(x) || throw(
        DimensionMismatch(
            "weights length $(length(weights_v)) != sample length $(length(x))"
        ),
    )
    all(>=(0.0), weights_v) || throw(ArgumentError("weights must be nonnegative"))
    sum(weights_v) > 0 || throw(ArgumentError("weights must have positive sum"))

    resolved_span = if isnothing(span)
        check_span(
            [0.999999426697, 0.999999426697],
            [Float64.(x), Float64.(y)];
            weights=weights_v,
        )
    else
        check_span(span, [Float64.(x), Float64.(y)]; weights=weights_v)
    end
    bins, svalues = _hist2d_bins_smoothing(smooth)
    xedges = _hist_edges(resolved_span[1], bins[1])
    yedges = _hist_edges(resolved_span[2], bins[2])
    density = _histogram2d(Float64.(x), Float64.(y), xedges, yedges, weights_v)
    if any(!iszero, svalues)
        density = _smooth2d(density, svalues)
    end
    if !any(>(0.0), density)
        throw(ArgumentError("no histogram mass inside the requested span"))
    end
    probs = if isnothing(levels)
        (1.0 .- exp.(-0.5 .* (0.5:0.5:2.0) .^ 2))
    else
        Float64.(collect(levels))
    end
    all(0 .< probs .< 1) || throw(ArgumentError("levels must be probabilities in (0, 1)"))
    thresholds = _density_thresholds(density, probs)
    xcenters = _bin_centers(xedges)
    ycenters = _bin_centers(yedges)
    xext, yext, dext = _extend_histogram_edges(xcenters, ycenters, density)
    return Hist2DResult(
        xcenters, ycenters, density, thresholds, xext, yext, dext, resolved_span
    )
end

function _hist2d_bins_smoothing(smooth)
    values = smooth isa Number ? (smooth, smooth) : Tuple(collect(smooth))
    length(values) == 2 ||
        throw(ArgumentError("smooth must be a scalar or length-2 iterable"))
    bins = Vector{Int}(undef, 2)
    svalues = Vector{Float64}(undef, 2)
    for i in 1:2
        s = values[i]
        if s isa Integer
            bins[i] = Int(s)
            svalues[i] = 0.0
        elseif s isa Real
            sf = Float64(s)
            sf > 0 || throw(ArgumentError("smooth values must be positive"))
            bins[i] = max(1, Int(round(2.0 / sf)))
            svalues[i] = 2.0
        else
            throw(ArgumentError("smooth values must be numeric"))
        end
    end
    return bins, svalues
end

function _hist_edges(span::Tuple{Float64, Float64}, nbins::Int)
    nbins > 0 || throw(ArgumentError("number of bins must be positive"))
    lo, hi = minmax(span...)
    hi > lo || throw(ArgumentError("histogram span must have nonzero width"))
    return collect(range(lo, hi; length=nbins + 1))
end

_bin_centers(edges::AbstractVector{<:Real}) =
    0.5 .* (Float64.(edges[2:end]) .+ Float64.(edges[1:(end - 1)]))

function _histogram2d(x, y, xedges, yedges, weights)
    out = zeros(Float64, length(xedges) - 1, length(yedges) - 1)
    for i in eachindex(x)
        xi = searchsortedlast(xedges, x[i])
        yi = searchsortedlast(yedges, y[i])
        if xi == length(xedges) && x[i] == xedges[end]
            xi -= 1
        end
        if yi == length(yedges) && y[i] == yedges[end]
            yi -= 1
        end
        if 1 <= xi <= size(out, 1) && 1 <= yi <= size(out, 2)
            out[xi, yi] += weights[i]
        end
    end
    return out
end

function _smooth2d(values::AbstractMatrix{<:Real}, sigma::AbstractVector{<:Real})
    original_sum = sum(values)
    kernel_x = _gaussian_kernel(sigma[1])
    kernel_y = _gaussian_kernel(sigma[2])
    tmp = similar(Matrix{Float64}(values))
    out = similar(tmp)
    _convolve_axis!(tmp, Matrix{Float64}(values), kernel_x, 1)
    _convolve_axis!(out, tmp, kernel_y, 2)
    smoothed_sum = sum(out)
    if original_sum > 0 && smoothed_sum > 0
        out .*= original_sum / smoothed_sum
    end
    return out
end

function _gaussian_kernel(sigma::Real)
    sf = Float64(sigma)
    if sf <= 0
        return [1.0]
    end
    radius = max(1, Int(ceil(4 * sf)))
    offsets = collect((-radius):radius)
    kernel = exp.(-0.5 .* (offsets ./ sf) .^ 2)
    return kernel ./ sum(kernel)
end

function _convolve_axis!(out, values, kernel, axis::Int)
    radius = length(kernel) ÷ 2
    fill!(out, 0.0)
    if axis == 1
        for j in axes(values, 2), i in axes(values, 1)
            acc = 0.0
            for (k, w) in enumerate(kernel)
                ii = clamp(i + k - radius - 1, firstindex(values, 1), lastindex(values, 1))
                acc += w * values[ii, j]
            end
            out[i, j] = acc
        end
    else
        for j in axes(values, 2), i in axes(values, 1)
            acc = 0.0
            for (k, w) in enumerate(kernel)
                jj = clamp(j + k - radius - 1, firstindex(values, 2), lastindex(values, 2))
                acc += w * values[i, jj]
            end
            out[i, j] = acc
        end
    end
    return out
end

function _density_thresholds(
    density::AbstractMatrix{<:Real}, levels::AbstractVector{<:Real}
)
    flat = sort(vec(Float64.(density)); rev=true)
    cumulative = cumsum(flat)
    cumulative ./= cumulative[end]
    thresholds = Vector{Float64}(undef, length(levels))
    for (i, level) in enumerate(levels)
        idx = findlast(<=(level + 10 * eps(Float64)), cumulative)
        thresholds[i] = isnothing(idx) ? flat[1] : flat[idx]
    end
    sort!(thresholds)
    while any(iszero, diff(thresholds)) && length(thresholds) > 1
        for i in 1:(length(thresholds) - 1)
            thresholds[i] == thresholds[i + 1] && (thresholds[i] *= 1.0 - 1.0e-4)
        end
        sort!(thresholds)
    end
    return thresholds
end

function _extend_histogram_edges(xcenters, ycenters, density)
    nx, ny = size(density)
    fill_value = minimum(density)
    extended = fill(fill_value, nx + 4, ny + 4)
    extended[3:(nx + 2), 3:(ny + 2)] .= density
    extended[3:(nx + 2), 2] .= density[:, 1]
    extended[3:(nx + 2), ny + 3] .= density[:, end]
    extended[2, 3:(ny + 2)] .= density[1, :]
    extended[nx + 3, 3:(ny + 2)] .= density[end, :]
    extended[2, 2] = density[1, 1]
    extended[2, ny + 3] = density[1, end]
    extended[nx + 3, 2] = density[end, 1]
    extended[nx + 3, ny + 3] = density[end, end]
    xstep_lo = length(xcenters) > 1 ? xcenters[2] - xcenters[1] : 1.0
    xstep_hi = length(xcenters) > 1 ? xcenters[end] - xcenters[end - 1] : 1.0
    ystep_lo = length(ycenters) > 1 ? ycenters[2] - ycenters[1] : 1.0
    ystep_hi = length(ycenters) > 1 ? ycenters[end] - ycenters[end - 1] : 1.0
    xext = vcat(
        xcenters[1] .+ [-2, -1] .* xstep_lo, xcenters, xcenters[end] .+ [1, 2] .* xstep_hi
    )
    yext = vcat(
        ycenters[1] .+ [-2, -1] .* ystep_lo, ycenters, ycenters[end] .+ [1, 2] .* ystep_hi
    )
    return xext, yext, extended
end

"""
    plot_truth(truths; vertical=false, horizontal=false)

Return finite truth-line coordinates as a lightweight backend-neutral helper.
"""
function plot_truth(truths; vertical::Bool=false, horizontal::Bool=false)
    vertical ⊻ horizontal ||
        throw(ArgumentError("specify exactly one of vertical or horizontal"))
    isnothing(truths) && return Float64[]
    values = truths isa Number ? [Float64(truths)] : Float64.(collect(skipmissing(truths)))
    return values
end

@recipe function f(hist::Hist2DResult)
    seriestype --> :heatmap
    xguide --> "x"
    yguide --> "y"
    hist.xcenters, hist.ycenters, transpose(hist.density)
end
