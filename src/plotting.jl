using Random
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
    Marginal1D

Weighted one-dimensional marginal density prepared for plotting recipes.
"""
struct Marginal1D
    edges::Vector{Float64}
    centers::Vector{Float64}
    density::Vector{Float64}
    span::Tuple{Float64, Float64}
end

"""
    RunPlotData

Prepared data returned by [`runplot`](@ref). The four series track live points,
normalized likelihood, importance weight density/weights, and evidence against
`-log(prior volume)`.
"""
struct RunPlotData
    xseries::Vector{Vector{Float64}}
    yseries::Vector{Vector{Float64}}
    labels::Vector{String}
    span::Vector{Tuple{Float64, Float64}}
    xspan::Tuple{Float64, Float64}
    evidence_error_bands::Vector{
        Tuple{Int, Vector{Float64}, Vector{Float64}, Vector{Float64}}
    }
    final_live_index::Union{Nothing, Int}
    final_live_x::Union{Nothing, Float64}
    lnz_truth::Union{Nothing, Float64}
    truth_y::Union{Nothing, Float64}
    logplot::Bool
    kde::Bool
end

"""
    TracePlotData

Prepared trace and one-dimensional marginal posterior data returned by
[`traceplot`](@ref).
"""
struct TracePlotData
    samples::Matrix{Float64}
    logvol::Vector{Float64}
    weights::Vector{Float64}
    trace_weights::Vector{Float64}
    dims::Vector{Int}
    labels::Vector{String}
    span::Vector{Tuple{Float64, Float64}}
    smooth::Vector{Union{Int, Float64}}
    thin::Int
    marginals::Vector{Marginal1D}
    quantiles::Vector{Vector{Float64}}
    truths::Vector{Union{Nothing, Float64}}
end

"""
    CornerPointsData

Prepared lower-triangle weighted point-cloud data returned by
[`cornerpoints`](@ref).
"""
struct CornerPointsData
    samples::Matrix{Float64}
    weights::Vector{Float64}
    dims::Vector{Int}
    labels::Vector{String}
    span::Union{Nothing, Vector{Tuple{Float64, Float64}}}
    thin::Int
    truths::Vector{Union{Nothing, Float64}}
end

"""
    CornerPlotData

Prepared one- and two-dimensional marginal posterior data returned by
[`cornerplot`](@ref).
"""
struct CornerPlotData
    samples::Matrix{Float64}
    weights::Vector{Float64}
    dims::Vector{Int}
    labels::Vector{String}
    span::Vector{Tuple{Float64, Float64}}
    smooth::Vector{Union{Int, Float64}}
    marginals::Vector{Marginal1D}
    quantiles::Vector{Vector{Float64}}
    hist2d::Matrix{Union{Nothing, Hist2DResult}}
    truths::Vector{Union{Nothing, Float64}}
end

"""
    BoundPlotData

Prepared samples from a saved bound, projected onto two dimensions.
"""
struct BoundPlotData
    draws::Matrix{Float64}
    live::Union{Nothing, Matrix{Float64}}
    dims::Vector{Int}
    labels::Vector{String}
    span::Union{Nothing, Vector{Tuple{Float64, Float64}}}
    bound_index::Int
    selection_kind::Symbol
    selection_value::Int
end

"""
    CornerBoundData

Prepared lower-triangle projections from a saved bound.
"""
struct CornerBoundData
    draws::Matrix{Float64}
    live::Union{Nothing, Matrix{Float64}}
    dims::Vector{Int}
    labels::Vector{String}
    span::Union{Nothing, Vector{Tuple{Float64, Float64}}}
    bound_index::Int
    selection_kind::Symbol
    selection_value::Int
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
    runplot(results; span=nothing, logplot=false, kde=true, nkde=1000,
            lnz_error=true, lnz_truth=nothing, mark_final_live=true)

Prepare the standard dynesty run summary plot as backend-neutral data. The
returned [`RunPlotData`](@ref) has a RecipesBase recipe; plotting packages can
render it without making Plots.jl a core dependency.
"""
function runplot(
    res::Results;
    span=nothing,
    logplot::Bool=false,
    kde::Bool=true,
    nkde::Integer=1000,
    lnz_error::Bool=true,
    lnz_truth=nothing,
    mark_final_live::Bool=true,
)
    logvol = _result_vector(res, :logvol)
    logl = _result_vector(res, :logl)
    logwt = _result_vector(res, :logwt)
    logz = _result_vector(res, :logz)
    logzerr = _result_vector(res, :logzerr)
    niter = Int(res.niter)
    nsamps = length(logwt)
    _check_same_length((:logvol, logvol), (:logl, logl), (:logwt, logwt), (:logz, logz))
    length(logzerr) == nsamps || throw(
        DimensionMismatch("logzerr length $(length(logzerr)) != sample length $nsamps")
    )
    logzerr = [isfinite(v) ? v : 0.0 for v in logzerr]

    live_counts, final_live_index = _runplot_live_counts(
        res, niter, nsamps, mark_final_live
    )
    norm_logl = logl .- maximum(logl)
    norm_logwt = logwt .- last(logz)
    x = -logvol
    weight_y = exp.(norm_logwt)
    weight_x = copy(x)
    if kde
        weight_x, weight_y = _weighted_density_on_logvol(logvol, weight_y, nkde)
    end
    evidence = logplot ? logz : exp.(logz)
    data = [live_counts, exp.(norm_logl), weight_y, evidence]
    xseries = [copy(x), copy(x), weight_x, copy(x)]
    labels = [
        "Live Points",
        "Likelihood (normalized)",
        kde ? "Importance Weight PDF" : "Importance Weight",
        logplot ? "log(Evidence)" : "Evidence",
    ]

    resolved_span = if isnothing(span)
        spans = [(0.0, 1.05 * maximum(d)) for d in data]
        if lnz_error
            spans[4] = if logplot
                (
                    last(logz) - 10.3 * 3.0 * last(logzerr),
                    last(logz) + 1.3 * 3.0 * last(logzerr),
                )
            else
                (0.0, 1.05 * exp(last(logz) + 3.0 * last(logzerr)))
            end
        end
        spans
    else
        spans = collect(span)
        length(spans) == 4 ||
            throw(DimensionMismatch("runplot span length $(length(spans)) != 4"))
        map(eachindex(spans)) do i
            value = spans[i]
            if value isa Number
                hi = maximum(data[i])
                (Float64(value) * hi, hi)
            else
                vals = Float64.(collect(value))
                length(vals) == 2 || throw(
                    ArgumentError("runplot span entries must be scalars or bounds")
                )
                (vals[1], vals[2])
            end
        end
    end

    bands = if lnz_error
        [
            (
                sigma,
                copy(x),
                logplot ? logz .- sigma .* logzerr : exp.(logz .- sigma .* logzerr),
                logplot ? logz .+ sigma .* logzerr : exp.(logz .+ sigma .* logzerr),
            ) for sigma in 1:3
        ]
    else
        Tuple{Int, Vector{Float64}, Vector{Float64}, Vector{Float64}}[]
    end
    final_live_x = isnothing(final_live_index) ? nothing : x[final_live_index]
    truth_y = if isnothing(lnz_truth)
        nothing
    else
        (logplot ? Float64(lnz_truth) : exp(Float64(lnz_truth)))
    end
    return RunPlotData(
        xseries,
        data,
        labels,
        resolved_span,
        (0.0, maximum(x)),
        bands,
        final_live_index,
        final_live_x,
        isnothing(lnz_truth) ? nothing : Float64(lnz_truth),
        truth_y,
        logplot,
        kde,
    )
end

"""
    traceplot(results; span=nothing, quantiles=(0.025, 0.5, 0.975),
              smooth=0.02, thin=1, dims=nothing, kde=true, nkde=1000,
              labels=nothing, truths=nothing)

Prepare trace and marginalized posterior data for each selected dimension.
"""
function traceplot(
    res::Results;
    span=nothing,
    quantiles=(0.025, 0.5, 0.975),
    smooth=0.02,
    thin::Integer=1,
    dims=nothing,
    kde::Bool=true,
    nkde::Integer=1000,
    labels=nothing,
    truths=nothing,
)
    thin > 0 || throw(ArgumentError("thin must be positive"))
    samples, dims_v, labels_v, weights = _posterior_plot_inputs(res; dims, labels)
    logvol = _result_vector(res, :logvol)
    size(samples, 2) == length(logvol) || throw(
        DimensionMismatch(
            "logvol length $(length(logvol)) != sample length $(size(samples, 2))"
        ),
    )
    trace_weights = kde ? _weighted_density_at_logvol(logvol, weights, nkde) : weights
    span_v = _resolve_posterior_span(span, samples, weights; default=0.999999426697)
    smooth_v = _resolve_smooth(smooth, size(samples, 1))
    quant_v = _resolve_quantiles(quantiles)
    marginals = [
        _marginal1d(samples[i, :], weights, span_v[i], smooth_v[i]) for
        i in axes(samples, 1)
    ]
    qvalues = [
        isempty(quant_v) ? Float64[] : quantile(vec(samples[i, :]), quant_v; weights) for
        i in axes(samples, 1)
    ]
    return TracePlotData(
        samples,
        logvol,
        weights,
        trace_weights,
        dims_v,
        labels_v,
        span_v,
        smooth_v,
        Int(thin),
        marginals,
        qvalues,
        _resolve_truths(truths, size(samples, 1)),
    )
end

"""
    cornerpoints(results; dims=nothing, thin=1, span=nothing, kde=true,
                 nkde=1000, labels=nothing, truths=nothing)

Prepare weighted lower-triangle posterior point clouds.
"""
function cornerpoints(
    res::Results;
    dims=nothing,
    thin::Integer=1,
    span=nothing,
    kde::Bool=true,
    nkde::Integer=1000,
    labels=nothing,
    truths=nothing,
)
    thin > 0 || throw(ArgumentError("thin must be positive"))
    samples, dims_v, labels_v, weights = _posterior_plot_inputs(res; dims, labels)
    size(samples, 1) > 1 ||
        throw(ArgumentError("cornerpoints does not make sense for a 1-D posterior"))
    if kde
        logvol = _result_vector(res, :logvol)
        size(samples, 2) == length(logvol) || throw(
            DimensionMismatch(
                "logvol length $(length(logvol)) != sample length $(size(samples, 2))"
            ),
        )
        weights = _weighted_density_at_logvol(logvol, weights, nkde)
    end
    span_v = isnothing(span) ? nothing : _resolve_posterior_span(span, samples, weights)
    return CornerPointsData(
        samples,
        weights,
        dims_v,
        labels_v,
        span_v,
        Int(thin),
        _resolve_truths(truths, size(samples, 1)),
    )
end

"""
    cornerplot(results; dims=nothing, span=nothing, quantiles=(0.025, 0.5, 0.975),
               smooth=0.02, quantiles_2d=nothing, labels=nothing, truths=nothing)

Prepare one- and two-dimensional marginalized posterior data for a corner plot.
"""
function cornerplot(
    res::Results;
    dims=nothing,
    span=nothing,
    quantiles=(0.025, 0.5, 0.975),
    smooth=0.02,
    quantiles_2d=nothing,
    labels=nothing,
    truths=nothing,
)
    samples, dims_v, labels_v, weights = _posterior_plot_inputs(res; dims, labels)
    ndim = size(samples, 1)
    span_v = _resolve_posterior_span(span, samples, weights; default=0.999999426697)
    smooth_v = _resolve_smooth(smooth, ndim)
    quant_v = _resolve_quantiles(quantiles)
    marginals = [
        _marginal1d(samples[i, :], weights, span_v[i], smooth_v[i]) for
        i in axes(samples, 1)
    ]
    qvalues = [
        isempty(quant_v) ? Float64[] : quantile(vec(samples[i, :]), quant_v; weights) for
        i in axes(samples, 1)
    ]
    hist2d = Matrix{Union{Nothing, Hist2DResult}}(undef, ndim, ndim)
    fill!(hist2d, nothing)
    for i in 2:ndim, j in 1:(i - 1)
        hist2d[i, j] = _hist2d(
            vec(samples[j, :]),
            vec(samples[i, :]);
            weights,
            span=[span_v[j], span_v[i]],
            smooth=[smooth_v[j], smooth_v[i]],
            levels=quantiles_2d,
        )
    end
    return CornerPlotData(
        samples,
        weights,
        dims_v,
        labels_v,
        span_v,
        smooth_v,
        marginals,
        qvalues,
        hist2d,
        _resolve_truths(truths, ndim),
    )
end

"""
    boundplot(results, dims; it=nothing, idx=nothing, prior_transform=nothing,
              periodic=nothing, reflective=nothing, ndraws=5000,
              show_live=false, span=nothing, labels=nothing,
              rng=Random.default_rng())

Prepare draws from the saved bound associated with either iteration `it` or
sample index `idx`, projected onto two dimensions. `it`, `idx`, and `dims` use
Julia's 1-based indexing.
"""
function boundplot(
    res::Results,
    dims;
    it=nothing,
    idx=nothing,
    prior_transform=nothing,
    periodic=nothing,
    reflective=nothing,
    ndraws::Integer=5000,
    show_live::Bool=false,
    span=nothing,
    labels=nothing,
    rng::AbstractRNG=Random.default_rng(),
)
    dims_v = _resolve_dims(dims, _bound_result_ndim(res))
    length(dims_v) == 2 ||
        throw(DimensionMismatch("boundplot dims length $(length(dims_v)) != 2"))
    draws, live, bound_index, kind, value = _prepare_bound_draws(
        res; it, idx, prior_transform, periodic, reflective, ndraws, show_live, rng
    )
    plot_draws = draws[:, dims_v]
    plot_live = isnothing(live) ? nothing : live[:, dims_v]
    return BoundPlotData(
        plot_draws,
        plot_live,
        dims_v,
        _resolve_labels(labels, dims_v),
        _resolve_bound_span(span, length(dims_v)),
        bound_index,
        kind,
        value,
    )
end

"""
    cornerbound(results; it=nothing, idx=nothing, dims=nothing,
                prior_transform=nothing, periodic=nothing, reflective=nothing,
                ndraws=5000, show_live=false, span=nothing, labels=nothing,
                rng=Random.default_rng())

Prepare lower-triangle projections from the saved bound associated with either
iteration `it` or sample index `idx`. `it`, `idx`, and `dims` use Julia's
1-based indexing.
"""
function cornerbound(
    res::Results;
    it=nothing,
    idx=nothing,
    dims=nothing,
    prior_transform=nothing,
    periodic=nothing,
    reflective=nothing,
    ndraws::Integer=5000,
    show_live::Bool=false,
    span=nothing,
    labels=nothing,
    rng::AbstractRNG=Random.default_rng(),
)
    dims_v = _resolve_dims(dims, _bound_result_ndim(res))
    length(dims_v) > 1 ||
        throw(ArgumentError("cornerbound does not work for 1-D posteriors"))
    draws, live, bound_index, kind, value = _prepare_bound_draws(
        res; it, idx, prior_transform, periodic, reflective, ndraws, show_live, rng
    )
    return CornerBoundData(
        draws[:, dims_v],
        isnothing(live) ? nothing : live[:, dims_v],
        dims_v,
        _resolve_labels(labels, dims_v),
        _resolve_bound_span(span, length(dims_v)),
        bound_index,
        kind,
        value,
    )
end

function _result_vector(res::Results, key::Symbol)
    haskey(res, key) || throw(KeyError(key))
    values = Float64.(res[key])
    ndims(values) == 1 || throw(ArgumentError("$key must be one-dimensional"))
    return vec(values)
end

function _check_same_length(first_pair, rest_pairs...)
    name, values = first_pair
    n = length(values)
    for (other_name, other_values) in rest_pairs
        length(other_values) == n || throw(
            DimensionMismatch(
                "$other_name length $(length(other_values)) != $name length $n"
            ),
        )
    end
    return n
end

function _runplot_live_counts(res::Results, niter::Int, nsamps::Int, mark_final_live::Bool)
    if haskey(res, :samples_n)
        counts = Float64.(res.samples_n)
        length(counts) == nsamps || throw(
            DimensionMismatch(
                "samples_n length $(length(counts)) != sample length $nsamps"
            ),
        )
        return counts, nothing
    end
    nlive = Int(res.nlive)
    counts = fill(Float64(nlive), niter)
    final_live_index = nothing
    if nsamps - niter == nlive
        append!(counts, Float64.(collect(nlive:-1:1)))
        mark_final_live && (final_live_index = niter + 1)
    elseif nsamps != niter
        counts = fill(Float64(nlive), nsamps)
    end
    length(counts) == nsamps || throw(
        DimensionMismatch(
            "live point count length $(length(counts)) != sample length $nsamps"
        ),
    )
    return counts, final_live_index
end

function _weighted_density_on_logvol(
    logvol::AbstractVector{<:Real}, weights::AbstractVector{<:Real}, nkde::Integer
)
    nkde >= 2 || throw(ArgumentError("nkde must be at least 2"))
    length(logvol) == length(weights) || throw(
        DimensionMismatch(
            "logvol length $(length(logvol)) != weights length $(length(weights))"
        ),
    )
    x = -Float64.(logvol)
    y = Float64.(weights)
    edges = collect(range(minimum(x), maximum(x); length=Int(nkde) + 1))
    centers = _bin_centers(edges)
    density = _histogram1d(x, edges, y)
    density = _smooth1d(density, 2.0)
    width = length(edges) > 1 ? edges[2] - edges[1] : 1.0
    area = sum(density) * width
    area > 0 && (density ./= area)
    return centers, density
end

function _weighted_density_at_logvol(
    logvol::AbstractVector{<:Real}, weights::AbstractVector{<:Real}, nkde::Integer
)
    centers, density = _weighted_density_on_logvol(logvol, weights, nkde)
    return [_interp_sorted(centers, density, -Float64(lv)) for lv in logvol]
end

function _posterior_plot_inputs(res::Results; dims=nothing, labels=nothing)
    samples = _samples_by_dimension(res.samples)
    weights = importance_weights(res)
    size(samples, 2) == length(weights) || throw(
        DimensionMismatch(
            "weights length $(length(weights)) != sample length $(size(samples, 2))"
        ),
    )
    dims_v = _resolve_dims(dims, size(samples, 1))
    samples = samples[dims_v, :]
    labels_v = _resolve_labels(labels, dims_v)
    return samples, dims_v, labels_v, weights
end

function _samples_by_dimension(samples)
    if samples isa AbstractMatrix
        matrix = Matrix{Float64}(samples)
        out = permutedims(matrix)
        size(out, 1) <= size(out, 2) ||
            throw(ArgumentError("there are more dimensions than samples"))
        return out
    elseif samples isa AbstractVector
        isempty(samples) && throw(ArgumentError("samples must not be empty"))
        return reshape(Float64.(samples), 1, :)
    else
        throw(ArgumentError("samples must be a vector or matrix"))
    end
end

function _bound_result_ndim(res::Results)
    samples_u = Matrix{Float64}(res.samples_u)
    ndims(samples_u) == 2 || throw(ArgumentError("samples_u must be two-dimensional"))
    return size(samples_u, 2)
end

function _resolve_dims(dims, ndim::Int)
    if isnothing(dims)
        return collect(1:ndim)
    end
    dims_v = Int.(collect(dims))
    isempty(dims_v) && throw(ArgumentError("dims must not be empty"))
    all(d -> 1 <= d <= ndim, dims_v) ||
        throw(ArgumentError("dims must contain 1-based indices in 1:$ndim"))
    return dims_v
end

function _resolve_labels(labels, dims::AbstractVector{<:Integer})
    if isnothing(labels)
        return ["x_$(d)" for d in dims]
    end
    values = string.(collect(labels))
    length(values) == length(dims) || throw(
        DimensionMismatch(
            "labels length $(length(values)) != dimension count $(length(dims))"
        ),
    )
    return values
end

function _resolve_truths(truths, ndim::Int)
    if isnothing(truths)
        return Union{Nothing, Float64}[nothing for _ in 1:ndim]
    elseif truths isa Number && ndim == 1
        return Union{Nothing, Float64}[Float64(truths)]
    end
    values = collect(truths)
    length(values) == ndim ||
        throw(DimensionMismatch("truths length $(length(values)) != dimension count $ndim"))
    return Union{Nothing, Float64}[
        (isnothing(value) || ismissing(value)) ? nothing : Float64(value) for
        value in values
    ]
end

function _resolve_bound_span(span, ndim::Int)
    isnothing(span) && return nothing
    values = collect(span)
    length(values) == ndim ||
        throw(DimensionMismatch("span length $(length(values)) != dimension count $ndim"))
    out = Vector{Tuple{Float64, Float64}}(undef, ndim)
    for i in eachindex(values)
        vals = Float64.(collect(values[i]))
        length(vals) == 2 ||
            throw(ArgumentError("bound plotting spans must be length-2 bounds"))
        out[i] = (vals[1], vals[2])
    end
    return out
end

function _prepare_bound_draws(
    res::Results;
    it,
    idx,
    prior_transform,
    periodic,
    reflective,
    ndraws::Integer,
    show_live::Bool,
    rng::AbstractRNG,
)
    ndraws > 0 || throw(ArgumentError("ndraws must be positive"))
    bound, bound_index, kind, value = _select_result_bound(res; it, idx)
    draw_bound = deepcopy(bound)
    live_u = if show_live || draw_bound isa Union{RadFriends, SupFriends}
        _reconstruct_static_live_u(res, kind, value)
    else
        nothing
    end
    if draw_bound isa Union{RadFriends, SupFriends}
        draw_bound.ctrs = live_u[:, 1:draw_bound.ndim]
    end
    draws_u = samples(draw_bound, ndraws; rng)
    draws = _project_bound_samples(
        draws_u, prior_transform, periodic, reflective, draw_bound.ndim
    )
    live = if show_live
        _project_bound_samples(live_u, prior_transform, periodic, reflective, draw_bound.ndim)
    else
        nothing
    end
    return draws, live, bound_index, kind, value
end

function _select_result_bound(res::Results; it, idx)
    (isnothing(it) ⊻ isnothing(idx)) ||
        throw(ArgumentError("specify exactly one of it or idx"))
    haskey(res, :bound) || throw(ArgumentError("no bounds were saved in the results"))
    bounds = collect(res.bound)
    isempty(bounds) && throw(ArgumentError("results contain no saved bounds"))
    nsamps = size(Matrix{Float64}(res.samples_u), 1)
    if !isnothing(it)
        it_i = Int(it)
        1 <= it_i <= nsamps || throw(BoundsError("iteration index $it_i outside 1:$nsamps"))
        haskey(res, :bound_iter) || throw(
            ArgumentError(
                "cannot reconstruct the bound at an iteration without bound_iter"
            ),
        )
        raw = it_i == 1 ? 0 : Int(res.bound_iter[it_i])
        bound_index = _saved_bound_to_index(raw, length(bounds))
        return bounds[bound_index], bound_index, :it, it_i
    else
        idx_i = Int(idx)
        1 <= idx_i <= nsamps || throw(BoundsError("sample index $idx_i outside 1:$nsamps"))
        haskey(res, :boundidx) || throw(
            ArgumentError("cannot reconstruct the bound for a sample without boundidx")
        )
        raw = Int(res.boundidx[idx_i])
        bound_index = _saved_bound_to_index(raw, length(bounds))
        return bounds[bound_index], bound_index, :idx, idx_i
    end
end

function _saved_bound_to_index(saved::Int, nbounds::Int)
    idx = saved + 1
    1 <= idx <= nbounds ||
        throw(BoundsError("saved bound index $saved outside 0:$(nbounds - 1)"))
    return idx
end

function _reconstruct_static_live_u(res::Results, kind::Symbol, value::Int)
    haskey(res, :nlive) || throw(
        ArgumentError("live point reconstruction for dynamic results is not implemented"),
    )
    haskey(res, :samples_id) ||
        throw(ArgumentError("cannot reconstruct live points without samples_id"))
    samples_u = Matrix{Float64}(res.samples_u)
    samples_id = Int.(res.samples_id)
    nlive = Int(res.nlive)
    niter = Int(res.niter)
    nsamps, ndim = size(samples_u)
    nsamps - niter == nlive || throw(
        ArgumentError(
            "cannot reconstruct live points unless final live points are included"
        ),
    )
    length(samples_id) == nsamps || throw(
        DimensionMismatch(
            "samples_id length $(length(samples_id)) != sample length $nsamps"
        ),
    )
    live_u = Matrix{Float64}(undef, nlive, ndim)
    for row in (nsamps - nlive + 1):nsamps
        id = samples_id[row]
        1 <= id <= nlive || throw(BoundsError("samples_id $id outside 1:$nlive"))
        live_u[id, :] .= samples_u[row, :]
    end
    it_i = kind === :it ? value : _sample_iteration_for_live_reconstruction(res, value)
    1 <= it_i <= niter || throw(BoundsError("iteration index $it_i outside 1:$niter"))
    for row in reverse((it_i + 1):niter)
        id = samples_id[row]
        1 <= id <= nlive || throw(BoundsError("samples_id $id outside 1:$nlive"))
        live_u[id, :] .= samples_u[row, :]
    end
    return live_u
end

function _sample_iteration_for_live_reconstruction(res::Results, idx::Int)
    haskey(res, :samples_it) ||
        throw(ArgumentError("cannot reconstruct live points for idx without samples_it"))
    return Int(res.samples_it[idx])
end

function _project_bound_samples(
    samples_u::AbstractMatrix{<:Real},
    prior_transform,
    periodic,
    reflective,
    bound_ndim::Int,
)
    samples_m = Matrix{Float64}(samples_u)
    if isnothing(prior_transform)
        return samples_m
    end
    nonbounded = get_nonbounded(bound_ndim, periodic, reflective)
    rows = findall(
        row -> unitcheck(view(samples_m, row, 1:bound_ndim); nonbounded), axes(samples_m, 1)
    )
    out = Matrix{Float64}(undef, length(rows), bound_ndim)
    for (j, row) in enumerate(rows)
        transformed = prior_transform(vec(samples_m[row, :]))
        values = Float64.(collect(transformed))
        length(values) >= bound_ndim || throw(
            DimensionMismatch(
                "prior_transform output length $(length(values)) < bound ndim $bound_ndim",
            ),
        )
        out[j, :] .= values[1:bound_ndim]
    end
    return out
end

function _resolve_posterior_span(span, samples, weights; default=1.0)
    ndim = size(samples, 1)
    values = isnothing(span) ? fill(default, ndim) : collect(span)
    length(values) == ndim ||
        throw(DimensionMismatch("span length $(length(values)) != dimension count $ndim"))
    return check_span(values, [vec(samples[i, :]) for i in axes(samples, 1)]; weights)
end

_resolve_quantiles(quantiles) =
    isnothing(quantiles) ? Float64[] : Float64.(collect(quantiles))

function _resolve_smooth(smooth, ndim::Int)
    values = smooth isa Number ? fill(smooth, ndim) : collect(smooth)
    length(values) == ndim ||
        throw(DimensionMismatch("smooth length $(length(values)) != dimension count $ndim"))
    out = Union{Int, Float64}[
        value isa Integer ? Int(value) : Float64(value) for value in values
    ]
    all(value -> value > 0, out) || throw(ArgumentError("smooth values must be positive"))
    return out
end

function _marginal1d(
    x::AbstractVector{<:Real},
    weights::AbstractVector{<:Real},
    span::Tuple{Float64, Float64},
    smooth::Union{Int, Float64},
)
    bins = smooth isa Integer ? Int(smooth) : max(1, Int(round(10.0 / smooth)))
    bins > 0 || throw(ArgumentError("histogram bins must be positive"))
    edges = _hist_edges(span, bins)
    density = _histogram1d(Float64.(x), edges, Float64.(weights))
    if !(smooth isa Integer)
        density = _smooth1d(density, 10.0)
    end
    return Marginal1D(edges, _bin_centers(edges), density, span)
end

function _histogram1d(
    x::AbstractVector{<:Real},
    edges::AbstractVector{<:Real},
    weights::AbstractVector{<:Real},
)
    length(x) == length(weights) || throw(
        DimensionMismatch(
            "weights length $(length(weights)) != sample length $(length(x))"
        ),
    )
    out = zeros(Float64, length(edges) - 1)
    for i in eachindex(x)
        idx = searchsortedlast(edges, x[i])
        if idx == length(edges) && x[i] == edges[end]
            idx -= 1
        end
        if 1 <= idx <= length(out)
            out[idx] += weights[i]
        end
    end
    return out
end

function _smooth1d(values::AbstractVector{<:Real}, sigma::Real)
    original_sum = sum(values)
    kernel = _gaussian_kernel(sigma)
    radius = length(kernel) ÷ 2
    out = zeros(Float64, length(values))
    for i in eachindex(values)
        acc = 0.0
        for (k, w) in enumerate(kernel)
            ii = clamp(i + k - radius - 1, firstindex(values), lastindex(values))
            acc += w * values[ii]
        end
        out[i] = acc
    end
    smoothed_sum = sum(out)
    if original_sum > 0 && smoothed_sum > 0
        out .*= original_sum / smoothed_sum
    end
    return out
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

@recipe function f(data::Marginal1D)
    seriestype --> :path
    data.centers, data.density
end

@recipe function f(data::RunPlotData)
    layout --> (4, 1)
    legend --> false
    for i in 1:4
        @series begin
            subplot := i
            seriestype := :path
            xguide := "-log X"
            yguide := data.labels[i]
            xlims := data.xspan
            ylims := data.span[i]
            data.xseries[i], data.yseries[i]
        end
    end
    for (sigma, x, lo, hi) in data.evidence_error_bands
        @series begin
            subplot := 4
            seriestype := :path
            label := "$(sigma)sigma lower"
            x, lo
        end
        @series begin
            subplot := 4
            seriestype := :path
            label := "$(sigma)sigma upper"
            x, hi
        end
    end
    if !isnothing(data.final_live_x)
        @series begin
            subplot := 1
            seriestype := :vline
            label := "final live"
            [data.final_live_x]
        end
    end
    if !isnothing(data.truth_y)
        @series begin
            subplot := 4
            seriestype := :hline
            label := "truth"
            [data.truth_y]
        end
    end
end

@recipe function f(data::TracePlotData)
    ndim = size(data.samples, 1)
    layout --> (ndim, 2)
    legend --> false
    x = -data.logvol
    idx = 1:data.thin:length(x)
    for i in 1:ndim
        @series begin
            subplot := 2 * i - 1
            seriestype := :scatter
            xguide := "-log X"
            yguide := data.labels[i]
            xlims := (0.0, -minimum(data.logvol))
            ylims := data.span[i]
            marker_z := data.trace_weights[idx]
            x[idx], vec(data.samples[i, idx])
        end
        @series begin
            subplot := 2 * i
            seriestype := :path
            xguide := data.labels[i]
            xlims := data.span[i]
            data.marginals[i].centers, data.marginals[i].density
        end
        for q in data.quantiles[i]
            @series begin
                subplot := 2 * i
                seriestype := :vline
                [q]
            end
        end
    end
end

@recipe function f(data::CornerPointsData)
    ndim = size(data.samples, 1)
    layout --> (ndim - 1, ndim - 1)
    legend --> false
    idx = 1:data.thin:size(data.samples, 2)
    series_count = 0
    for i in 2:ndim, j in 1:(ndim - 1)
        if j < i
            series_count += 1
            @series begin
                subplot := series_count
                seriestype := :scatter
                xguide := data.labels[j]
                yguide := data.labels[i]
                if !isnothing(data.span)
                    xlims := data.span[j]
                    ylims := data.span[i]
                end
                marker_z := data.weights[idx]
                vec(data.samples[j, idx]), vec(data.samples[i, idx])
            end
        elseif j < ndim
            series_count += 1
        end
    end
end

@recipe function f(data::CornerPlotData)
    ndim = size(data.samples, 1)
    layout --> (ndim, ndim)
    legend --> false
    for i in 1:ndim, j in 1:ndim
        subplot_idx = (i - 1) * ndim + j
        if i == j
            @series begin
                subplot := subplot_idx
                seriestype := :path
                xguide := data.labels[i]
                xlims := data.span[i]
                data.marginals[i].centers, data.marginals[i].density
            end
            for q in data.quantiles[i]
                @series begin
                    subplot := subplot_idx
                    seriestype := :vline
                    [q]
                end
            end
        elseif j < i
            hist = data.hist2d[i, j]
            if !isnothing(hist)
                @series begin
                    subplot := subplot_idx
                    seriestype := :heatmap
                    xguide := data.labels[j]
                    yguide := data.labels[i]
                    xlims := data.span[j]
                    ylims := data.span[i]
                    hist.xcenters, hist.ycenters, transpose(hist.density)
                end
            end
        end
    end
end

@recipe function f(data::BoundPlotData)
    legend --> false
    seriestype --> :scatter
    xguide --> data.labels[1]
    yguide --> data.labels[2]
    if !isnothing(data.span)
        xlims --> data.span[1]
        ylims --> data.span[2]
    end
    @series begin
        seriestype := :scatter
        data.draws[:, 1], data.draws[:, 2]
    end
    if !isnothing(data.live)
        @series begin
            seriestype := :scatter
            markercolor := :darkviolet
            data.live[:, 1], data.live[:, 2]
        end
    end
end

@recipe function f(data::CornerBoundData)
    ndim = size(data.draws, 2)
    layout --> (ndim - 1, ndim - 1)
    legend --> false
    series_count = 0
    for i in 2:ndim, j in 1:(ndim - 1)
        if j < i
            series_count += 1
            @series begin
                subplot := series_count
                seriestype := :scatter
                xguide := data.labels[j]
                yguide := data.labels[i]
                if !isnothing(data.span)
                    xlims := data.span[j]
                    ylims := data.span[i]
                end
                data.draws[:, j], data.draws[:, i]
            end
            if !isnothing(data.live)
                @series begin
                    subplot := series_count
                    seriestype := :scatter
                    markercolor := :darkviolet
                    data.live[:, j], data.live[:, i]
                end
            end
        elseif j < ndim
            series_count += 1
        end
    end
end
