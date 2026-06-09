using LinearAlgebra
using Random
using Statistics

import Base: contains

abstract type AbstractBound end

"""
    UnitCube(ndim)

N-dimensional unit-cube bound.
"""
struct UnitCube <: AbstractBound
    ndim::Int
    logvol::Float64
    funit::Float64
    need_centers::Bool
end

function UnitCube(ndim::Integer)
    ndim > 0 || throw(ArgumentError("ndim must be positive; got $ndim"))
    return UnitCube(Int(ndim), 0.0, 1.0, false)
end

"""
    Ellipsoid(ndim; ctr=nothing, cov=nothing, am=nothing, axes=nothing)

Ellipsoid defined by `(x - ctr)' * am * (x - ctr) <= 1`. `axes[:, i]` is the
`i`-th principal axis, matching Python dynesty's convention.
"""
mutable struct Ellipsoid <: AbstractBound
    ndim::Int
    ctr::Vector{Float64}
    cov::Matrix{Float64}
    am::Matrix{Float64}
    axes::Matrix{Float64}
    axlens::Vector{Float64}
    logvol::Float64
    funit::Float64
    need_centers::Bool
end

function Ellipsoid(ndim::Integer; ctr=nothing, cov=nothing, am=nothing, axes=nothing)
    ndim_i = Int(ndim)
    ndim_i > 0 || throw(ArgumentError("ndim must be positive; got $ndim"))
    ctr_v = isnothing(ctr) ? zeros(Float64, ndim_i) : Float64.(collect(ctr))
    length(ctr_v) == ndim_i ||
        throw(DimensionMismatch("center length $(length(ctr_v)) != ndim $ndim_i"))
    cov_m = if isnothing(cov)
        Matrix{Float64}(I, ndim_i, ndim_i) .* (ndim_i / 4)
    else
        Matrix{Float64}(cov)
    end
    size(cov_m) == (ndim_i, ndim_i) ||
        throw(DimensionMismatch("covariance shape $(size(cov_m)) != ($ndim_i, $ndim_i)"))

    eig = eigen(Symmetric(cov_m))
    eigenvalues = Float64.(eig.values)
    eigenvectors = Matrix{Float64}(eig.vectors)
    if !(all(isfinite, eigenvalues) && all(>(0.0), eigenvalues))
        throw(
            ArgumentError(
                "covariance matrix defining the ellipsoid is singular or not positive definite; eigenvalues=$(eigenvalues)",
            ),
        )
    end
    axlens = sqrt.(eigenvalues)
    logvol = logvol_prefactor(ndim_i) + 0.5 * sum(log, eigenvalues)
    axes_m = isnothing(axes) ? eigenvectors .* transpose(axlens) : Matrix{Float64}(axes)
    size(axes_m) == (ndim_i, ndim_i) ||
        throw(DimensionMismatch("axes shape $(size(axes_m)) != ($ndim_i, $ndim_i)"))
    am_m = if isnothing(am)
        eigenvectors * Diagonal(1.0 ./ eigenvalues) * transpose(eigenvectors)
    else
        Matrix{Float64}(am)
    end
    size(am_m) == (ndim_i, ndim_i) ||
        throw(DimensionMismatch("precision shape $(size(am_m)) != ($ndim_i, $ndim_i)"))
    return Ellipsoid(ndim_i, ctr_v, cov_m, am_m, axes_m, axlens, logvol, 1.0, false)
end

"""
    MultiEllipsoid(ndim; ells=nothing, ctrs=nothing, covs=nothing)

Union of ellipsoids. Sampling uses volume-weighted ellipsoid selection and the
standard `1/q` overlap correction.
"""
mutable struct MultiEllipsoid <: AbstractBound
    ndim::Int
    ells::Vector{Ellipsoid}
    nells::Int
    ctrs::Matrix{Float64}
    covs::Vector{Matrix{Float64}}
    ams::Vector{Matrix{Float64}}
    logvol_ells::Vector{Float64}
    logvol::Float64
    funit::Float64
    need_centers::Bool
end

function MultiEllipsoid(ndim::Integer; ells=nothing, ctrs=nothing, covs=nothing)
    ndim_i = Int(ndim)
    ndim_i > 0 || throw(ArgumentError("ndim must be positive; got $ndim"))
    ell_vec = if isnothing(ells) && isnothing(ctrs)
        [Ellipsoid(ndim_i)]
    elseif !isnothing(ells)
        (isnothing(ctrs) && isnothing(covs)) ||
            throw(ArgumentError("specify either ells or (ctrs, covs), not both"))
        Vector{Ellipsoid}(ells)
    else
        (!isnothing(ctrs) && !isnothing(covs)) ||
            throw(ArgumentError("ctrs and covs must be provided together"))
        ctr_m = Matrix{Float64}(ctrs)
        cov_v = [Matrix{Float64}(covs[i, :, :]) for i in axes(covs, 1)]
        [Ellipsoid(ndim_i; ctr=ctr_m[i, :], cov=cov_v[i]) for i in axes(ctr_m, 1)]
    end
    isempty(ell_vec) &&
        throw(ArgumentError("MultiEllipsoid requires at least one ellipsoid"))
    for ell in ell_vec
        ell.ndim == ndim_i ||
            throw(DimensionMismatch("ellipsoid ndim $(ell.ndim) != $ndim_i"))
    end
    ctrs_m, covs_v, ams_v, logvols = _ellipsoid_arrays(ell_vec, ndim_i)
    return MultiEllipsoid(
        ndim_i,
        ell_vec,
        length(ell_vec),
        ctrs_m,
        covs_v,
        ams_v,
        logvols,
        logsumexp(logvols),
        1.0,
        false,
    )
end

function _ellipsoid_arrays(ells::Vector{Ellipsoid}, ndim::Int)
    ctrs = Matrix{Float64}(undef, length(ells), ndim)
    covs = Matrix{Float64}[]
    ams = Matrix{Float64}[]
    logvols = Vector{Float64}(undef, length(ells))
    for (i, ell) in enumerate(ells)
        ctrs[i, :] .= ell.ctr
        push!(covs, copy(ell.cov))
        push!(ams, copy(ell.am))
        logvols[i] = ell.logvol
    end
    return ctrs, covs, ams, logvols
end

function _refresh_arrays!(multi::MultiEllipsoid)
    multi.ctrs, multi.covs, multi.ams, multi.logvol_ells = _ellipsoid_arrays(
        multi.ells, multi.ndim
    )
    multi.nells = length(multi.ells)
    multi.logvol = logsumexp(multi.logvol_ells)
    return multi
end

function logsumexp(values::AbstractVector{<:Real})
    isempty(values) && throw(ArgumentError("values must not be empty"))
    vmax = maximum(values)
    return vmax + log(sum(exp.(Float64.(values) .- vmax)))
end

function _slogdet_checked(matrix::AbstractMatrix{<:Real})
    sign, logabsdet = logabsdet(Matrix{Float64}(matrix))
    sign > 0 ||
        throw(ArgumentError("covariance matrix has non-positive determinant sign=$sign"))
    return logabsdet
end

contains(bound::UnitCube, x::AbstractVector{<:Real}) = unitcheck(x)

function sample(bound::UnitCube; rng::AbstractRNG=Random.default_rng())
    return rand(rng, bound.ndim)
end

function samples(bound::UnitCube, nsamples::Integer; rng::AbstractRNG=Random.default_rng())
    nsamples >= 0 || throw(ArgumentError("nsamples must be nonnegative; got $nsamples"))
    return rand(rng, Int(nsamples), bound.ndim)
end

get_random_axes(bound::UnitCube; rng::AbstractRNG=Random.default_rng()) =
    Matrix{Float64}(I, bound.ndim, bound.ndim)

scale_to_logvol!(bound::UnitCube, logvol::Real) = bound

"""
    randsphere(n; rng=Random.default_rng())

Draw a point uniformly inside the `n`-dimensional unit sphere.
"""
function randsphere(n::Integer; rng::AbstractRNG=Random.default_rng())
    n > 0 || throw(ArgumentError("n must be positive; got $n"))
    z = randn(rng, Int(n))
    norm_z = norm(z)
    while norm_z == 0
        z .= randn(rng, Int(n))
        norm_z = norm(z)
    end
    return z .* (rand(rng)^(1 / n) / norm_z)
end

"""
    rand_choice(probabilities; rng=Random.default_rng())

Return a 1-based index sampled from probabilities that sum to one.
"""
function rand_choice(
    probabilities::AbstractVector{<:Real}; rng::AbstractRNG=Random.default_rng()
)
    isempty(probabilities) && throw(ArgumentError("probabilities must not be empty"))
    probs = Float64.(probabilities)
    all(>=(0.0), probs) || throw(ArgumentError("probabilities must be nonnegative"))
    total = sum(probs)
    total > 0 || throw(ArgumentError("probabilities must have positive sum"))
    cdf = cumsum(probs ./ total)
    draw = rand(rng)
    return min(searchsortedfirst(cdf, draw), length(probs))
end

"""
    improve_covar_mat(covar; ntries=100, max_condition_number=1e12)

Return `(good_mat, covar, am, axes)` after conditioning a covariance matrix.
"""
function improve_covar_mat(
    covar0::AbstractMatrix{<:Real}; ntries::Integer=100, max_condition_number::Real=1.0e12
)
    covar = Matrix{Float64}(covar0)
    size(covar, 1) == size(covar, 2) ||
        throw(DimensionMismatch("covariance matrix must be square; got $(size(covar))"))
    ndim = size(covar, 1)
    coeffmin = 1.0e-10
    eig_mult = 10.0
    failed = 0
    trial = 0
    eigvalues = ones(Float64, ndim)
    eigvectors = Matrix{Float64}(I, ndim, ndim)
    axes = Matrix{Float64}(I, ndim, ndim)
    ntries_i = Int(ntries)
    ntries_i > 0 || throw(ArgumentError("ntries must be positive; got $ntries"))

    for current_trial in 0:(ntries_i - 1)
        trial = current_trial
        failed = 0
        try
            eig = eigen(Symmetric(covar))
            eigvalues = Float64.(eig.values)
            eigvectors = Matrix{Float64}(eig.vectors)
            maxval = maximum(eigvalues)
            minval = minimum(eigvalues)
            if all(isfinite, eigvalues)
                if maxval <= 0
                    failed = 2
                elseif minval < maxval / max_condition_number
                    failed = 1
                else
                    axes = eigvectors .* transpose(sqrt.(eigvalues))
                    break
                end
            else
                failed = 2
            end
        catch
            failed = 2
        end
        if failed > 0
            if failed == 1
                maxval = maximum(eigvalues)
                eigvalue_fix = max.(eigvalues, eig_mult * maxval / max_condition_number)
                covar = eigvectors * Diagonal(eigvalue_fix) * transpose(eigvectors)
            else
                coeff = if ntries_i == 1
                    1.0
                else
                    coeffmin * (1.0 / coeffmin)^(trial / (ntries_i - 1))
                end
                covar = (1.0 - coeff) .* covar .+ coeff .* Matrix{Float64}(I, ndim, ndim)
            end
        end
    end

    if failed > 0
        @warn "Failed to guarantee the ellipsoid axes will be non-singular. Defaulting to a sphere."
        covar = Matrix{Float64}(I, ndim, ndim)
        am = copy(covar)
        axes = copy(covar)
    else
        am = eigvectors * Diagonal(1.0 ./ eigvalues) * transpose(eigvectors)
    end
    good_mat = trial == 0
    return good_mat, covar, am, axes
end

function _mle_cov(points::AbstractMatrix{<:Real})
    npoints, ndim = size(points)
    npoints > 1 || throw(ArgumentError("at least two points are required"))
    ctr = vec(mean(points; dims=1))
    delta = Matrix{Float64}(points) .- reshape(ctr, 1, ndim)
    return transpose(delta) * delta / (npoints - 1)
end

"""
    bounding_ellipsoid(points)

Compute a bounding ellipsoid for public `npoints x ndim` points.
"""
function bounding_ellipsoid(points::AbstractMatrix{<:Real})
    npoints, ndim = size(points)
    npoints == 1 &&
        throw(ArgumentError("Cannot compute a bounding ellipsoid of a single point."))
    npoints > 1 || throw(ArgumentError("points must contain at least two rows"))
    pts = Matrix{Float64}(points)
    ctr = vec(mean(pts; dims=1))
    covar = _mle_cov(pts)
    delta = pts .- reshape(ctr, 1, ndim)
    one_minus_a_bit = 1.0 - 1.0e-3
    am = Matrix{Float64}(I, ndim, ndim)
    axes = Matrix{Float64}(I, ndim, ndim)

    for i in 1:2
        good_mat, covar, am, axes = improve_covar_mat(covar)
        q = vec(sum((delta * am) .* delta; dims=2))
        fmax = maximum(q)
        if i == 1 && fmax > one_minus_a_bit
            mult = fmax / one_minus_a_bit
            covar .*= mult
            am ./= mult
            axes .*= sqrt(mult)
        elseif i == 2 && fmax >= 1.0
            throw(
                ErrorException(
                    "Failed to initialize the ellipsoid to contain all the points"
                ),
            )
        end
        good_mat && break
    end
    return Ellipsoid(ndim; ctr, cov=covar, am, axes)
end

function scale_to_logvol!(ell::Ellipsoid, logvol::Real)
    target = Float64(logvol)
    logf = target - ell.logvol
    max_log_axlen = log(sqrt(ell.ndim) / 2)
    log_axlen = log.(ell.axlens)
    if maximum(log_axlen) < max_log_axlen - logf / ell.ndim
        f = exp(logf / ell.ndim)
        ell.cov .*= f^2
        ell.am .*= 1.0 / f^2
        ell.axlens .*= f
        ell.axes .*= f
    else
        logfax = zeros(Float64, ell.ndim)
        curlogf = logf
        curn = ell.ndim
        eig = eigen(Symmetric(ell.cov))
        eigenvalues = Float64.(eig.values)
        eigenvectors = Matrix{Float64}(eig.vectors)
        for curi in reverse(sortperm(eigenvalues))
            delta = max(min(max_log_axlen - log_axlen[curi], curlogf / curn), 0.0)
            logfax[curi] = delta
            curlogf -= delta
            curn -= 1
        end
        fax = exp.(logfax)
        eigenvalues_new = eigenvalues .* fax .^ 2
        ell.cov = eigenvectors * Diagonal(eigenvalues_new) * transpose(eigenvectors)
        ell.am = eigenvectors * Diagonal(1.0 ./ eigenvalues_new) * transpose(eigenvectors)
        ell.axlens .*= fax
        ell.axes .*= transpose(fax)
    end
    ell.logvol = target
    return ell
end

function major_axis_endpoints(ell::Ellipsoid)
    i = argmax(ell.axlens)
    axis = ell.axes[:, i]
    return ell.ctr .- axis, ell.ctr .+ axis
end

function distance(ell::Ellipsoid, x::AbstractVector{<:Real})
    length(x) == ell.ndim ||
        throw(DimensionMismatch("point length $(length(x)) != ndim $(ell.ndim)"))
    delta = Float64.(x) .- ell.ctr
    return sqrt(dot(delta, ell.am * delta))
end

function distance_many(ell::Ellipsoid, x::AbstractMatrix{<:Real})
    size(x, 2) == ell.ndim || throw(
        DimensionMismatch(
            "point matrix second dimension $(size(x, 2)) != ndim $(ell.ndim)"
        ),
    )
    delta = Matrix{Float64}(x) .- reshape(ell.ctr, 1, ell.ndim)
    return sqrt.(vec(sum((delta * ell.am) .* delta; dims=2)))
end

contains(ell::Ellipsoid, x::AbstractVector{<:Real}) = distance(ell, x) <= 1.0

function sample(ell::Ellipsoid; rng::AbstractRNG=Random.default_rng())
    return ell.ctr .+ ell.axes * randsphere(ell.ndim; rng)
end

function samples(ell::Ellipsoid, nsamples::Integer; rng::AbstractRNG=Random.default_rng())
    nsamples >= 0 || throw(ArgumentError("nsamples must be nonnegative; got $nsamples"))
    out = Matrix{Float64}(undef, Int(nsamples), ell.ndim)
    for i in 1:Int(nsamples)
        out[i, :] .= sample(ell; rng)
    end
    return out
end

function unitcube_overlap(
    ell::Ellipsoid; ndraws::Integer=10_000, rng::AbstractRNG=Random.default_rng()
)
    ndraws > 0 || throw(ArgumentError("ndraws must be positive; got $ndraws"))
    nin = 0
    for _ in 1:Int(ndraws)
        nin += unitcheck(sample(ell; rng)) ? 1 : 0
    end
    return nin / ndraws
end

function update!(
    ell::Ellipsoid,
    points::AbstractMatrix{<:Real};
    rng::AbstractRNG=Random.default_rng(),
    bootstrap::Integer=0,
    mc_integrate::Bool=false,
)
    bootstrap == 0 || throw(
        ArgumentError(
            "ellipsoid bootstrap expansion is implemented in a later Stage 2 refinement"
        ),
    )
    new_ell = bounding_ellipsoid(points)
    ell.ndim = new_ell.ndim
    ell.ctr = new_ell.ctr
    ell.cov = new_ell.cov
    ell.am = new_ell.am
    ell.axes = new_ell.axes
    ell.axlens = new_ell.axlens
    ell.logvol = new_ell.logvol
    ell.funit = mc_integrate ? unitcube_overlap(ell; rng) : ell.funit
    return ell
end

get_random_axes(ell::Ellipsoid; rng::AbstractRNG=Random.default_rng()) = ell.axes

function scale_to_logvol!(multi::MultiEllipsoid, logvol)
    if logvol isa Number
        scale = Float64(logvol) - multi.logvol
        new_logvols = multi.logvol_ells .+ scale
    else
        new_logvols = Float64.(collect(logvol))
        length(new_logvols) == multi.nells || throw(
            DimensionMismatch(
                "logvol length $(length(new_logvols)) != nells $(multi.nells)"
            ),
        )
    end
    for i in 1:multi.nells
        scale_to_logvol!(multi.ells[i], new_logvols[i])
    end
    return _refresh_arrays!(multi)
end

function major_axis_endpoints(multi::MultiEllipsoid)
    return [major_axis_endpoints(ell) for ell in multi.ells]
end

function within(multi::MultiEllipsoid, x::AbstractVector{<:Real}; j=nothing)
    length(x) == multi.ndim ||
        throw(DimensionMismatch("point length $(length(x)) != ndim $(multi.ndim)"))
    delta = reshape(Float64.(x), 1, multi.ndim) .- multi.ctrs
    mask = Bool[
        dot(view(delta, i, :), multi.ams[i] * collect(view(delta, i, :))) < 1.0 for
        i in 1:multi.nells
    ]
    if !isnothing(j)
        jj = Int(j)
        1 <= jj <= multi.nells || throw(BoundsError(multi.ells, jj))
        mask[jj] = false
    end
    return findall(mask)
end

overlap(multi::MultiEllipsoid, x::AbstractVector{<:Real}; j=nothing) =
    length(within(multi, x; j))

function contains(multi::MultiEllipsoid, x::AbstractVector{<:Real})
    return !isempty(within(multi, x))
end

function sample(
    multi::MultiEllipsoid; rng::AbstractRNG=Random.default_rng(), return_q::Bool=false
)
    if multi.nells == 1
        x = sample(multi.ells[1]; rng)
        return return_q ? (x, 1, 1) : (x, 1)
    end
    probs = exp.(multi.logvol_ells .- multi.logvol)
    while true
        idx = rand_choice(probs; rng)
        x = sample(multi.ells[idx]; rng)
        delta = reshape(x, 1, multi.ndim) .- multi.ctrs
        qs = [
            dot(view(delta, i, :), multi.ams[i] * collect(view(delta, i, :))) for
            i in 1:multi.nells
        ]
        q = count(<(1.0), qs)
        if q == 0
            one_plus_a_bit = 1.0 + 1.0e-3
            q = count(<=(one_plus_a_bit), qs)
            q == 0 &&
                throw(ErrorException("Ellipsoid check failed q=0, minimum=$(minimum(qs))"))
        end
        if return_q
            return x, idx, q
        elseif q == 1 || rand(rng) < 1.0 / q
            return x, idx
        end
    end
end

function samples(
    multi::MultiEllipsoid, nsamples::Integer; rng::AbstractRNG=Random.default_rng()
)
    nsamples >= 0 || throw(ArgumentError("nsamples must be nonnegative; got $nsamples"))
    out = Matrix{Float64}(undef, Int(nsamples), multi.ndim)
    for i in 1:Int(nsamples)
        x, _ = sample(multi; rng)
        out[i, :] .= x
    end
    return out
end

function monte_carlo_logvol(
    multi::MultiEllipsoid;
    ndraws::Integer=10_000,
    rng::AbstractRNG=Random.default_rng(),
    return_overlap::Bool=true,
)
    ndraws > 0 || throw(ArgumentError("ndraws must be positive; got $ndraws"))
    qsum = 0.0
    qin = 0.0
    for _ in 1:Int(ndraws)
        x, _, q = sample(multi; rng, return_q=true)
        weight = 1.0 / q
        qsum += weight
        qin += weight * unitcheck(x)
    end
    logvol = log(qsum / ndraws) + multi.logvol
    if return_overlap
        return logvol, qin / qsum
    else
        return logvol
    end
end

function get_random_axes(multi::MultiEllipsoid; rng::AbstractRNG=Random.default_rng())
    probs = exp.(multi.logvol_ells .- multi.logvol)
    ell_idx = rand_choice(probs; rng)
    return multi.ells[ell_idx].axes
end

"""
    bounding_ellipsoids(points)

Compute a `MultiEllipsoid` bounding the point set. Stage 2 returns a
single-ellipsoid union; recursive clustering split support is filled in during
the extended bounding stages.
"""
function bounding_ellipsoids(points::AbstractMatrix{<:Real})
    ell = bounding_ellipsoid(points)
    return MultiEllipsoid(size(points, 2); ells=[ell])
end

_bounding_ellipsoids(points::AbstractMatrix{<:Real}, ell::Ellipsoid; scale=nothing) = [ell]
