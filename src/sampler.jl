using Random

const LOWL_VAL = -1.0e300
const BOUND_OPTIONS = (:none, :single, :multi, :balls, :cubes)
const SAMPLE_OPTIONS = (:auto, :unif, :rwalk, :slice, :rslice)

"""
    NestedSampler(loglikelihood, prior_transform, ndim; kwargs...)

Static nested sampler. Public sample arrays in [`results`](@ref) use dynesty's
row-major convention (`nsamples x ndim`), while Julia callables receive
one-dimensional `Vector{Float64}` inputs.
"""
mutable struct NestedSampler{L, P}
    loglikelihood::L
    prior_transform::P
    ndim::Int
    nlive::Int
    ncdim::Int
    blob::Bool
    copy_inputs::Bool
    rng::AbstractRNG
    bound_kind::Symbol
    sample_kind::Symbol
    bound::AbstractBound
    bound_next::AbstractBound
    internal_sampler::AbstractInternalSampler
    internal_sampler_next::AbstractInternalSampler
    live_u::Matrix{Float64}
    live_v::Matrix{Float64}
    live_logl::Vector{Float64}
    live_blobs::Union{Nothing, Vector{Any}}
    live_bound::Vector{Int}
    live_it::Vector{Int}
    saved_run::RunRecord
    ncall::Int
    it::Int
    eff::Float64
    added_live::Bool
    logvol_init::Float64
    dlv::Float64
    unit_cube_sampling::Bool
    bound_list::Vector{Any}
    nbound::Int
    bound_update_interval::Int
    first_bound_update::Dict{Symbol, Any}
    first_bound_update_ncall::Int
    first_bound_update_eff::Float64
    logl_first_update::Union{Nothing, Float64}
    ncall_at_last_update::Int
    bound_bootstrap::Int
    bound_enlarge::Float64
    save_bounds::Bool
    plateau_mode::Bool
    plateau_counter::Int
    plateau_logdvol::Float64
end

function _option_symbol(value, allowed, kind::AbstractString)
    value isa Symbol && (sym = value)
    value isa AbstractString && (sym = Symbol(value))
    if !(value isa Union{Symbol, AbstractString})
        throw(ArgumentError("$kind must be one of $(collect(allowed)); got $(repr(value))"))
    end
    sym in allowed || throw(
        ArgumentError(
            "unsupported $kind $(repr(value)); expected one of $(collect(allowed))"
        ),
    )
    return sym
end

function _get_bound(bounding, ndim::Integer)
    bounding isa AbstractBound && return bounding
    kind = _option_symbol(bounding, BOUND_OPTIONS, "bounding type")
    ndim_i = Int(ndim)
    if kind === :none
        return UnitCube(ndim_i)
    elseif kind === :single
        return Ellipsoid(ndim_i)
    elseif kind === :multi
        return MultiEllipsoid(ndim_i)
    elseif kind === :balls
        return RadFriends(ndim_i)
    elseif kind === :cubes
        return SupFriends(ndim_i)
    end
end

_bound_kind(bound::AbstractBound) = :custom
_bound_kind(::UnitCube) = :none
_bound_kind(::Ellipsoid) = :single
_bound_kind(::MultiEllipsoid) = :multi
_bound_kind(::RadFriends) = :balls
_bound_kind(::SupFriends) = :cubes

function _mask_from_sampler_indices(indices, ndim::Int, name::Symbol)
    isnothing(indices) && return nothing
    if indices isa AbstractVector{Bool}
        length(indices) == ndim ||
            throw(DimensionMismatch("$name mask length $(length(indices)) != ndim $ndim"))
        return collect(indices)
    end
    mask = falses(ndim)
    for raw in indices
        idx = Int(raw)
        1 <= idx <= ndim || throw(BoundsError("$name index $idx outside 1:$ndim"))
        mask[idx] = true
    end
    return mask
end

_nonbounded_mask(ndim::Int, periodic, reflective) =
    get_nonbounded(ndim, periodic, reflective)

function _internal_sampler_kind(sampler::AbstractInternalSampler)
    sampler isa UniformBoundSampler && return :unif
    sampler isa UnitCubeSampler && return :unitcube
    sampler isa RWalkSampler && return :rwalk
    sampler isa SliceSampler && return :slice
    sampler isa RSliceSampler && return :rslice
    return :custom
end

function _get_internal_sampler(
    sampling,
    ndim::Integer,
    ncdim::Integer=ndim;
    periodic=nothing,
    reflective=nothing,
    walks=nothing,
    slices=nothing,
    facc::Real=0.5,
)
    sampling isa AbstractInternalSampler && return sampling
    ndim_i = Int(ndim)
    ncdim_i = Int(ncdim)
    kind = _option_symbol(sampling, SAMPLE_OPTIONS, "sampling method")
    if kind === :auto
        kind = ndim_i < 10 ? :unif : (ndim_i <= 20 ? :rwalk : :rslice)
    end

    periodic_mask = _mask_from_sampler_indices(periodic, ndim_i, :periodic)
    reflective_mask = _mask_from_sampler_indices(reflective, ndim_i, :reflective)
    nonbounded = _nonbounded_mask(ndim_i, periodic, reflective)
    kwargs = Dict{Symbol, Any}(
        :periodic => periodic_mask,
        :reflective => reflective_mask,
        :nonbounded => nonbounded,
        :nonperiodic => nonbounded,
    )

    if kind === :unif
        return UniformBoundSampler(; kwargs...)
    elseif kind === :rwalk
        default_walks = ndim_i + 20
        return RWalkSampler(;
            walks=isnothing(walks) ? default_walks : walks, facc, ncdim=ncdim_i, kwargs...
        )
    elseif kind === :slice
        ncdim_i == ndim_i || throw(ArgumentError("ncdim is unsupported for slice sampling"))
        return SliceSampler(; slices=isnothing(slices) ? 3 : slices, kwargs...)
    elseif kind === :rslice
        ncdim_i == ndim_i ||
            throw(ArgumentError("ncdim is unsupported for random-slice sampling"))
        return RSliceSampler(; slices=isnothing(slices) ? ndim_i + 3 : slices, kwargs...)
    end
end

function _get_enlarge_bootstrap(sampler::AbstractInternalSampler, enlarge, bootstrap)
    default_enlarge = 1.25
    default_unif_bootstrap = 5
    if !isnothing(enlarge) && isnothing(bootstrap)
        enlarge >= 1 || throw(ArgumentError("enlarge must be >= 1"))
        return Float64(enlarge), 0
    elseif isnothing(enlarge) && !isnothing(bootstrap)
        bootstrap_i = Int(bootstrap)
        (bootstrap_i > 1 || bootstrap_i == 0) ||
            throw(ArgumentError("bootstrap must be 0 or greater than 1"))
        return 1.0, bootstrap_i
    elseif isnothing(enlarge) && isnothing(bootstrap)
        if sampler isa UniformBoundSampler
            return 1.0, default_unif_bootstrap
        else
            return default_enlarge, 0
        end
    else
        bootstrap_i = Int(bootstrap)
        if bootstrap_i == 0 || Float64(enlarge) == 1.0
            return Float64(enlarge), bootstrap_i
        else
            throw(
                ArgumentError(
                    "enlarge and bootstrap together require bootstrap=0 or enlarge=1"
                ),
            )
        end
    end
end

function _check_first_update(first_update)
    for raw_key in keys(first_update)
        key = Symbol(raw_key)
        key in (:min_ncall, :min_eff) ||
            throw(ArgumentError("unrecognized first_update key $(repr(key))"))
    end
    return Dict{Symbol, Any}(Symbol(key) => value for (key, value) in first_update)
end

function _get_update_interval_ratio(
    update_interval, sampler::AbstractInternalSampler, nlive::Integer
)
    if isnothing(update_interval)
        return update_bound_interval_ratio(sampler)
    elseif update_interval isa AbstractFloat
        update_interval > 0 || throw(ArgumentError("update_interval must be positive"))
        return Float64(update_interval)
    elseif update_interval isa Integer
        update_interval > 0 || throw(ArgumentError("update_interval must be positive"))
        return Float64(update_interval) / Int(nlive)
    else
        throw(ArgumentError("update_interval must be nothing, integer, or float"))
    end
end

function _normalize_prior_transform_output(value, ndim::Int)
    out = _float_vector(value)
    length(out) == ndim || throw(
        DimensionMismatch("prior_transform output length $(length(out)) != ndim $ndim")
    )
    return out
end

function _call_prior_transform(prior_transform, u, ndim::Int; copy_inputs::Bool=false)
    input = copy_inputs ? Vector{Float64}(u) : u
    return _normalize_prior_transform_output(prior_transform(input), ndim)
end

function _call_loglikelihood(loglikelihood, v; blob::Bool=false, copy_inputs::Bool=false)
    input = copy_inputs ? Vector{Float64}(v) : v
    raw = loglikelihood(input)
    out = raw isa LoglOutput ? LoglOutput(raw) : LoglOutput(raw, blob)
    blob &&
        !out.has_blob &&
        throw(ArgumentError("blob=true requires likelihood output `(logl, blob)`"))
    if isnan(out.logl) || out.logl == Inf
        throw(ArgumentError("The log-likelihood of live point is invalid."))
    end
    return out
end

function _initialize_live_points(
    live_points,
    prior_transform,
    loglikelihood;
    nlive::Integer,
    ndim::Integer,
    rng::AbstractRNG=Random.default_rng(),
    blob::Bool=false,
    copy_inputs::Bool=false,
)
    nlive_i = Int(nlive)
    ndim_i = Int(ndim)
    nlive_i > 0 || throw(ArgumentError("nlive must be positive; got $nlive"))
    ndim_i > 0 || throw(ArgumentError("ndim must be positive; got $ndim"))
    logvol_init = 0.0
    ncalls = 0

    if isnothing(live_points)
        live_u = zeros(Float64, nlive_i, ndim_i)
        live_v = zeros(Float64, nlive_i, ndim_i)
        live_logl = zeros(Float64, nlive_i)
        live_blobs = blob ? Any[] : nothing
        ngoods = 0
        n_attempts = 1000
        min_npoints = min(nlive_i, max(ndim_i + 1, min(nlive_i - 20, 100)))
        min_npoints = max(1, min_npoints)
        for iattempt in 1:n_attempts
            cur_u = rand(rng, nlive_i, ndim_i)
            cur_v = zeros(Float64, nlive_i, ndim_i)
            cur_logl = zeros(Float64, nlive_i)
            cur_blobs = blob ? Vector{Any}(undef, nlive_i) : nothing
            for i in 1:nlive_i
                u = vec(cur_u[i, :])
                v = _call_prior_transform(prior_transform, u, ndim_i; copy_inputs)
                out = _call_loglikelihood(loglikelihood, v; blob, copy_inputs)
                cur_v[i, :] .= v
                cur_logl[i] = out.logl
                blob && (cur_blobs[i] = out.blob)
            end
            ncalls += nlive_i
            finite = isfinite.(cur_logl)
            neg_infinite = isinf.(cur_logl) .& (cur_logl .< 0)
            any((.!finite) .& (.!neg_infinite)) &&
                throw(ArgumentError("The log-likelihood of live point is invalid."))

            good_idxs = findall(finite)
            if !isempty(good_idxs)
                nextra = min(nlive_i - ngoods, length(good_idxs))
                for idx in good_idxs[1:nextra]
                    row = ngoods + 1
                    live_u[row, :] .= cur_u[idx, :]
                    live_v[row, :] .= cur_v[idx, :]
                    live_logl[row] = cur_logl[idx]
                    blob && push!(live_blobs, cur_blobs[idx])
                    ngoods += 1
                end
            end

            if ngoods >= min_npoints
                bad_idxs = findall(.!finite)
                nextra = nlive_i - ngoods
                length(bad_idxs) >= nextra || throw(
                    ErrorException(
                        "initialization could not fill the requested live point set"
                    ),
                )
                for idx in bad_idxs[1:nextra]
                    row = ngoods + 1
                    live_u[row, :] .= cur_u[idx, :]
                    live_v[row, :] .= cur_v[idx, :]
                    live_logl[row] = LOWL_VAL
                    blob && push!(live_blobs, cur_blobs[idx])
                    ngoods += 1
                end
                logvol_init = -log(iattempt)
                break
            elseif iattempt == n_attempts
                ngoods == 0 && throw(
                    ErrorException(
                        "after $n_attempts attempts, no valid initial live point was found",
                    ),
                )
                throw(
                    ErrorException(
                        "after $n_attempts attempts, fewer than $min_npoints valid initial live points were found",
                    ),
                )
            end
        end
        return (live_u, live_v, live_logl, live_blobs), logvol_init, ncalls
    else
        length(live_points) in (3, 4) ||
            throw(ArgumentError("live_points must contain (u, v, logl[, blobs])"))
        blob && length(live_points) == 4 ||
            !blob ||
            throw(ArgumentError("blob=true requires live_points to include blobs"))
        live_u = Matrix{Float64}(live_points[1])
        live_v = Matrix{Float64}(live_points[2])
        live_logl = Vector{Float64}(live_points[3])
        size(live_u) == (nlive_i, ndim_i) ||
            throw(DimensionMismatch("live_u shape $(size(live_u)) != ($nlive_i, $ndim_i)"))
        size(live_v) == (nlive_i, ndim_i) ||
            throw(DimensionMismatch("live_v shape $(size(live_v)) != ($nlive_i, $ndim_i)"))
        length(live_logl) == nlive_i || throw(
            DimensionMismatch("live_logl length $(length(live_logl)) != nlive $nlive_i")
        )
        for i in eachindex(live_logl)
            if !isfinite(live_logl[i])
                if isinf(live_logl[i]) && live_logl[i] < 0
                    live_logl[i] = LOWL_VAL
                else
                    throw(ArgumentError("The log-likelihood of live point $i is invalid."))
                end
            end
        end
        all(==(LOWL_VAL), live_logl) && throw(
            ArgumentError("not a single provided live point has a valid log-likelihood")
        )
        live_blobs = blob ? Vector{Any}(live_points[4]) : nothing
        return (live_u, live_v, live_logl, live_blobs), logvol_init, ncalls
    end
end

function NestedSampler(
    loglikelihood,
    prior_transform,
    ndim::Integer;
    nlive::Integer=500,
    bound=:multi,
    sample=:auto,
    periodic=nothing,
    reflective=nothing,
    update_interval=nothing,
    first_update=nothing,
    rng=nothing,
    rstate=nothing,
    live_points=nothing,
    enlarge=nothing,
    bootstrap=nothing,
    walks=nothing,
    facc::Real=0.5,
    slices=nothing,
    ncdim=nothing,
    blob::Bool=false,
    copy_inputs::Bool=false,
    kwargs...,
)
    isempty(kwargs) || throw(
        ArgumentError("unsupported NestedSampler keyword(s): $(collect(keys(kwargs)))")
    )
    ndim_i = Int(ndim)
    nlive_i = Int(nlive)
    nlive_i > 0 || throw(ArgumentError("nlive must be positive; got $nlive"))
    ndim_i > 0 || throw(ArgumentError("ndim must be positive; got $ndim"))
    ncdim_i = isnothing(ncdim) ? ndim_i : Int(ncdim)
    1 <= ncdim_i <= ndim_i ||
        throw(ArgumentError("ncdim must be between 1 and ndim; got $ncdim_i"))
    if !isnothing(rng) && !isnothing(rstate)
        throw(ArgumentError("specify either rng or rstate, not both"))
    end
    rng_obj = if !isnothing(rng)
        rng
    elseif !isnothing(rstate)
        rstate
    else
        Random.default_rng()
    end
    rng_obj isa AbstractRNG || throw(ArgumentError("rng/rstate must be an AbstractRNG"))
    first_update_d =
        isnothing(first_update) ? Dict{Symbol, Any}() : _check_first_update(first_update)

    initial_sampler = _get_internal_sampler(
        sample, ndim_i, ncdim_i; periodic, reflective, walks, slices, facc
    )
    sample_kind = _internal_sampler_kind(initial_sampler)
    bound_obj_next = _get_bound(bound, ncdim_i)
    bound_kind = if bound isa AbstractBound
        _bound_kind(bound)
    else
        _option_symbol(bound, BOUND_OPTIONS, "bounding type")
    end
    enlarge_f, bootstrap_i = _get_enlarge_bootstrap(initial_sampler, enlarge, bootstrap)
    if bootstrap_i > 0
        if isnothing(bootstrap) && initial_sampler isa UniformBoundSampler
            enlarge_f, bootstrap_i = 1.25, 0
        end
    end
    ratio = _get_update_interval_ratio(update_interval, initial_sampler, nlive_i)
    bound_update_interval = max(1, round(Int, ratio * nlive_i))
    live, logvol_init, init_ncalls = _initialize_live_points(
        live_points,
        prior_transform,
        loglikelihood;
        nlive=nlive_i,
        ndim=ndim_i,
        rng=rng_obj,
        blob,
        copy_inputs,
    )
    live_u, live_v, live_logl, live_blobs = live
    bound_current = UnitCube(ncdim_i)
    unit_sampler = UnitCubeSampler(; ndim=ndim_i, periodic, reflective)
    return NestedSampler(
        loglikelihood,
        prior_transform,
        ndim_i,
        nlive_i,
        ncdim_i,
        blob,
        copy_inputs,
        rng_obj,
        bound_kind,
        sample_kind,
        bound_current,
        bound_obj_next,
        unit_sampler,
        initial_sampler,
        live_u,
        live_v,
        live_logl,
        live_blobs,
        zeros(Int, nlive_i),
        zeros(Int, nlive_i),
        RunRecord(),
        init_ncalls,
        1,
        0.0,
        false,
        logvol_init,
        log((nlive_i + 1.0) / nlive_i),
        true,
        Any[bound_current],
        1,
        bound_update_interval,
        first_update_d,
        Int(get(first_update_d, :min_ncall, 2 * nlive_i)),
        Float64(get(first_update_d, :min_eff, 10.0)),
        nothing,
        0,
        bootstrap_i,
        enlarge_f,
        true,
        false,
        0,
        -Inf,
    )
end

function _ptform_wrapper(sampler::NestedSampler)
    return u -> _call_prior_transform(
        sampler.prior_transform, u, sampler.ndim; copy_inputs=sampler.copy_inputs
    )
end

function _loglike_wrapper(sampler::NestedSampler)
    return v -> _call_loglikelihood(
        sampler.loglikelihood, v; blob=sampler.blob, copy_inputs=sampler.copy_inputs
    )
end

function _update_bound!(sampler::NestedSampler; subset=nothing)
    rows = isnothing(subset) ? collect(1:sampler.nlive) : collect(subset)
    isempty(rows) &&
        throw(ArgumentError("cannot update bound with an empty live-point subset"))
    points = sampler.live_u[rows, 1:sampler.ncdim]
    update!(sampler.bound, points; rng=sampler.rng, bootstrap=sampler.bound_bootstrap)
    if sampler.bound_enlarge != 1.0
        scale_to_logvol!(sampler.bound, sampler.bound.logvol + log(sampler.bound_enlarge))
    end
    return sampler.bound
end

function _update_bound_if_needed!(
    sampler::NestedSampler, loglstar::Real; ncall=sampler.ncall, force::Bool=false
)
    delta_bound = sampler.bound_update_interval
    call_check_first = ncall >= sampler.first_bound_update_ncall
    call_check = ncall >= delta_bound + sampler.ncall_at_last_update
    efficiency_check = sampler.eff < sampler.first_bound_update_eff
    first_logl_check =
        sampler.unit_cube_sampling &&
        !isnothing(sampler.logl_first_update) &&
        loglstar > sampler.logl_first_update
    should_update =
        (sampler.unit_cube_sampling && efficiency_check && call_check_first) ||
        (!sampler.unit_cube_sampling && call_check) ||
        first_logl_check ||
        force

    should_update || return false
    subset = if Float64(loglstar) == LOWL_VAL
        findall(>(Float64(loglstar)), sampler.live_logl)
    else
        collect(1:sampler.nlive)
    end
    if sampler.unit_cube_sampling
        sampler.unit_cube_sampling = false
        sampler.logl_first_update = Float64(loglstar)
        sampler.bound = sampler.bound_next
        sampler.internal_sampler = sampler.internal_sampler_next
    end
    _update_bound!(sampler; subset)
    sampler.save_bounds && push!(sampler.bound_list, deepcopy(sampler.bound))
    sampler.nbound += 1
    sampler.ncall_at_last_update = Int(ncall)
    return true
end

function _propose_live(sampler::NestedSampler, valid_indices)
    isempty(valid_indices) && throw(
        ErrorException(
            "no live points are above the likelihood constraint; likelihood plateau or exhausted support",
        ),
    )
    idx = valid_indices[rand(sampler.rng, 1:length(valid_indices))]
    u = vec(copy(sampler.live_u[idx, :]))
    axes = get_random_axes(sampler.bound; rng=sampler.rng)
    if sampler.bound.need_centers
        sampler.bound.ctrs = sampler.live_u[:, 1:sampler.ncdim]
    end
    u_fit = u[1:sampler.ncdim]
    if !contains(sampler.bound, u_fit)
        _update_bound_if_needed!(sampler, -Inf; force=true)
        contains(sampler.bound, u_fit) || throw(
            ErrorException("update of the sampling bound failed to contain a live point"),
        )
    end
    return u, axes
end

function _proposal_sample(sampler::NestedSampler, loglstar::Real)
    ptform = _ptform_wrapper(sampler)
    loglike = _loglike_wrapper(sampler)
    if sampler.internal_sampler isa UnitCubeSampler
        return sample(
            sampler.internal_sampler;
            loglstar,
            prior_transform=ptform,
            loglikelihood=loglike,
            rng=sampler.rng,
        )
    elseif sampler.internal_sampler isa UniformBoundSampler
        return sample(
            sampler.internal_sampler;
            bound=sampler.bound,
            loglstar,
            prior_transform=ptform,
            loglikelihood=loglike,
            ndim=sampler.ndim,
            n_cluster=sampler.ncdim,
            rng=sampler.rng,
        )
    elseif sampler.internal_sampler isa RWalkSampler
        valid = findall(>(Float64(loglstar)), sampler.live_logl)
        u, axes = _propose_live(sampler, valid)
        return sample(
            sampler.internal_sampler,
            u;
            loglstar,
            axes,
            prior_transform=ptform,
            loglikelihood=loglike,
            rng=sampler.rng,
        )
    elseif sampler.internal_sampler isa Union{SliceSampler, RSliceSampler}
        valid = findall(>(Float64(loglstar)), sampler.live_logl)
        u, axes = _propose_live(sampler, valid)
        return sample(
            sampler.internal_sampler,
            u;
            loglstar,
            axes,
            prior_transform=ptform,
            loglikelihood=loglike,
            rng=sampler.rng,
        )
    else
        throw(
            ArgumentError(
                "unsupported internal sampler $(typeof(sampler.internal_sampler))"
            ),
        )
    end
end

function _tune_internal_sampler!(sampler::NestedSampler, ret::SamplerReturn)
    sampler.unit_cube_sampling && return sampler
    if sampler.internal_sampler isa RWalkSampler
        tune!(sampler.internal_sampler, ret.tuning_info; update=true)
    elseif sampler.internal_sampler isa Union{SliceSampler, RSliceSampler}
        tune_slice(sampler.internal_sampler, ret.tuning_info; update=true)
    end
    return sampler
end

function _new_point!(sampler::NestedSampler, loglstar::Real)
    ncall_accum = 0
    while true
        _update_bound_if_needed!(sampler, loglstar; ncall=sampler.ncall + ncall_accum)
        ret = _proposal_sample(sampler, loglstar)
        ncall_accum += ret.ncalls
        _tune_internal_sampler!(sampler, ret)
        if ret.logl > loglstar
            return ret, ncall_accum
        end
    end
end

function _append_run!(
    sampler::NestedSampler;
    id,
    u,
    v,
    logl,
    logvol,
    logwt,
    logz,
    logzvar,
    h,
    nc,
    boundidx,
    it,
    bounditer,
    scale,
    blob,
    proposal_stats,
)
    append!(
        sampler.saved_run,
        Dict(
            :id => Int(id),
            :u => Vector{Float64}(u),
            :v => Vector{Float64}(v),
            :logl => Float64(logl),
            :logvol => Float64(logvol),
            :logwt => Float64(logwt),
            :logz => Float64(logz),
            :logzvar => Float64(logzvar),
            :h => Float64(h),
            :nc => Int(nc),
            :boundidx => Int(boundidx),
            :it => Int(it),
            :n => sampler.nlive,
            :bounditer => Int(bounditer),
            :scale => Float64(scale),
            :blobs => blob,
            :proposal_stats => proposal_stats,
        ),
    )
    return sampler
end

function _last_integrator_state(sampler::NestedSampler)
    if isempty(sampler.saved_run[:logl])
        return 0.0, LOWL_VAL, 0.0, sampler.logvol_init, LOWL_VAL
    else
        return (
            Float64(sampler.saved_run[:h][end]),
            Float64(sampler.saved_run[:logz][end]),
            Float64(sampler.saved_run[:logzvar][end]),
            Float64(sampler.saved_run[:logvol][end]),
            Float64(sampler.saved_run[:logl][end]),
        )
    end
end

function _delta_logz(live_logl, logvol::Real, logz::Real)
    maxlive = maximum(live_logl)
    if !isfinite(logz)
        return Inf
    end
    return logaddexp(0.0, maxlive + Float64(logvol) - Float64(logz))
end

function _remove_added_live_points!(sampler::NestedSampler)
    sampler.added_live || return sampler
    for key in RUN_RECORD_KEYS
        resize!(sampler.saved_run[key], length(sampler.saved_run[key]) - sampler.nlive)
    end
    sampler.added_live = false
    return sampler
end

function add_live_points!(sampler::NestedSampler)
    sampler.added_live &&
        throw(ArgumentError("the remaining live points have already been added"))
    sampler.added_live = true
    h, logz, logzvar, logvol, loglstar = _last_integrator_state(sampler)
    logvol_offsets = [log1p(-(i / (sampler.nlive + 1.0))) for i in 1:sampler.nlive]
    dlvs = Vector{Float64}(undef, sampler.nlive)
    dlvs[1] = -logvol_offsets[1]
    for i in 2:sampler.nlive
        dlvs[i] = -(logvol_offsets[i] - logvol_offsets[i - 1])
    end
    logvols = logvol .+ logvol_offsets
    order = sortperm(sampler.live_logl)
    loglmax = maximum(sampler.live_logl)
    bounditer = sampler.unit_cube_sampling ? 0 : sampler.nbound - 1

    for (rank, idx) in enumerate(order)
        cur_logvol = logvols[rank]
        dlv = dlvs[rank]
        ustar = vec(copy(sampler.live_u[idx, :]))
        vstar = vec(copy(sampler.live_v[idx, :]))
        old_blob = sampler.blob ? sampler.live_blobs[idx] : nothing
        loglstar_new = sampler.live_logl[idx]
        integ = progress_integration(
            loglstar, loglstar_new, logz, logzvar, cur_logvol, dlv, h
        )
        logwt, logz, logzvar, h = integ.logwt, integ.logz, integ.logzvar, integ.h
        loglstar = loglstar_new
        _append_run!(
            sampler;
            id=idx,
            u=ustar,
            v=vstar,
            logl=loglstar,
            logvol=cur_logvol,
            logwt,
            logz,
            logzvar,
            h,
            nc=1,
            boundidx=sampler.live_bound[idx],
            it=sampler.live_it[idx],
            bounditer,
            scale=getfield(sampler.internal_sampler, :scale),
            blob=old_blob,
            proposal_stats=nothing,
        )
        sampler.eff = 100.0 * (sampler.it + rank - 1) / max(sampler.ncall, 1)
        _ = loglmax
    end
    return sampler
end

function _run_iteration!(sampler::NestedSampler, state; logl_max::Real=Inf)
    h, logz, logzvar, logvol, loglstar = state
    worst = argmin(sampler.live_logl)
    worst_it = sampler.live_it[worst]
    boundidx = sampler.live_bound[worst]

    if !sampler.plateau_mode
        nplateau = count(==(sampler.live_logl[worst]), sampler.live_logl)
        if nplateau > 1
            sampler.plateau_mode = true
            sampler.plateau_counter = nplateau
            sampler.plateau_logdvol = log(1.0 / (sampler.nlive + 1.0)) + logvol
        end
    end
    cur_dlv = if !sampler.plateau_mode
        sampler.dlv
    else
        -log1p(-exp(sampler.plateau_logdvol - logvol))
    end
    logvol -= cur_dlv
    ustar = vec(copy(sampler.live_u[worst, :]))
    vstar = vec(copy(sampler.live_v[worst, :]))
    loglstar_new = sampler.live_logl[worst]
    old_blob = sampler.blob ? sampler.live_blobs[worst] : nothing

    ret, nc = _new_point!(sampler, loglstar_new)
    sampler.ncall += nc
    integ = progress_integration(loglstar, loglstar_new, logz, logzvar, logvol, cur_dlv, h)
    logwt, logz, logzvar, h = integ.logwt, integ.logz, integ.logzvar, integ.h
    loglstar = loglstar_new
    bounditer = sampler.unit_cube_sampling ? 0 : sampler.nbound - 1

    _append_run!(
        sampler;
        id=worst,
        u=ustar,
        v=vstar,
        logl=loglstar,
        logvol,
        logwt,
        logz,
        logzvar,
        h,
        nc,
        boundidx,
        it=worst_it,
        bounditer,
        scale=getfield(sampler.internal_sampler, :scale),
        blob=old_blob,
        proposal_stats=ret.proposal_stats,
    )

    sampler.live_u[worst, :] .= ret.u
    sampler.live_v[worst, :] .= ret.v
    sampler.live_logl[worst] = ret.logl
    sampler.live_bound[worst] = bounditer
    sampler.live_it[worst] = sampler.it
    sampler.blob && (sampler.live_blobs[worst] = ret.blob)
    sampler.eff = 100.0 * sampler.it / max(sampler.ncall, 1)
    sampler.it += 1
    if sampler.plateau_mode
        sampler.plateau_counter -= 1
        sampler.plateau_counter == 0 && (sampler.plateau_mode = false)
    end
    return h, logz, logzvar, logvol, loglstar
end

function _recompute_integrals!(sampler::NestedSampler)
    isempty(sampler.saved_run[:logl]) && return sampler
    ints = compute_integrals(;
        logl=Float64.(sampler.saved_run[:logl]), logvol=Float64.(sampler.saved_run[:logvol])
    )
    sampler.saved_run[:logwt] = Any[ints.logwt...]
    sampler.saved_run[:logz] = Any[ints.logz...]
    sampler.saved_run[:logzvar] = Any[ints.logzvar...]
    sampler.saved_run[:h] = Any[ints.h...]
    return sampler
end

function run_nested!(
    sampler::NestedSampler;
    maxiter=nothing,
    maxcall=nothing,
    dlogz=nothing,
    logl_max::Real=Inf,
    add_live::Bool=true,
    save_bounds::Bool=true,
    checkpoint_file=nothing,
    checkpoint_every=nothing,
    resume::Bool=false,
    print_progress::Bool=false,
    print_func=nothing,
    kwargs...,
)
    isempty(kwargs) ||
        throw(ArgumentError("unsupported run_nested! keyword(s): $(collect(keys(kwargs)))"))
    resume && sampler.added_live && return sampler
    sampler.save_bounds = save_bounds
    !resume && sampler.added_live && _remove_added_live_points!(sampler)
    dlogz_eff = if isnothing(dlogz)
        add_live ? 1.0e-3 * (sampler.nlive - 1.0) + 0.01 : 0.01
    else
        Float64(dlogz)
    end
    maxiter_i = isnothing(maxiter) ? typemax(Int) : Int(maxiter)
    maxcall_i = isnothing(maxcall) ? typemax(Int) : Int(maxcall)
    state = _last_integrator_state(sampler)
    ncall_at_start = sampler.ncall
    local_steps = 0
    checkpoint_interval = isnothing(checkpoint_every) ? Inf : Float64(checkpoint_every)
    checkpoint_interval > 0 || throw(ArgumentError("checkpoint_every must be positive"))
    last_checkpoint_time = time()
    _, progress_callback = get_print_func(print_func, print_progress)
    while true
        h, logz, logzvar, logvol, loglstar = state
        delta = _delta_logz(sampler.live_logl, logvol, logz)
        stop =
            local_steps >= maxiter_i ||
            (sampler.ncall - ncall_at_start) >= maxcall_i ||
            delta < dlogz_eff ||
            loglstar > logl_max ||
            maximum(sampler.live_logl) == minimum(sampler.live_logl)
        stop && break
        state = _run_iteration!(sampler, state; logl_max)
        local_steps += 1
        if print_progress
            h_new, logz_new, logzvar_new, logvol_new, loglstar_new = state
            progress_callback(
                (;
                    loglstar=loglstar_new,
                    logz=logz_new,
                    delta_logz=_delta_logz(sampler.live_logl, logvol_new, logz_new),
                    logzvar=logzvar_new,
                    bounditer=sampler.unit_cube_sampling ? 0 : sampler.nbound - 1,
                    nc=if isempty(sampler.saved_run[:nc])
                        0
                    else
                        Int(last(sampler.saved_run[:nc]))
                    end,
                    eff=sampler.eff,
                ),
                sampler.it,
                sampler.ncall;
                dlogz=dlogz_eff,
                logl_max,
            )
            _ = h_new
        end
        if !isnothing(checkpoint_file) &&
            time() - last_checkpoint_time >= checkpoint_interval
            checkpoint!(sampler, checkpoint_file)
            last_checkpoint_time = time()
        end
    end
    add_live && add_live_points!(sampler)
    _recompute_integrals!(sampler)
    if !isnothing(checkpoint_file)
        checkpoint!(sampler, checkpoint_file)
    end
    return sampler
end

run_nested(sampler::NestedSampler; kwargs...) = run_nested!(sampler; kwargs...)

function _matrix_from_record(record::RunRecord, key::Symbol, ndim::Int)
    n = length(record[key])
    out = Matrix{Float64}(undef, n, ndim)
    for i in 1:n
        out[i, :] .= Vector{Float64}(record[key][i])
    end
    return out
end

function results(sampler::NestedSampler)
    record = sampler.saved_run
    samples_u = _matrix_from_record(record, :u, sampler.ndim)
    samples_v = _matrix_from_record(record, :v, sampler.ndim)
    logzvar = Float64.(record[:logzvar])
    data = Any[
        :nlive => sampler.nlive,
        :niter => max(sampler.it - 1, 0),
        :ncall => Int.(record[:nc]),
        :eff => sampler.eff,
        :samples => samples_v,
        :samples_u => samples_u,
        :samples_id => Int.(record[:id]),
        :samples_it => Int.(record[:it]),
        :logl => Float64.(record[:logl]),
        :logvol => Float64.(record[:logvol]),
        :logwt => Float64.(record[:logwt]),
        :logz => Float64.(record[:logz]),
        :logzvar => logzvar,
        :logzerr => sqrt.(max.(logzvar, 0.0)),
        :h => Float64.(record[:h]),
        :information => Float64.(record[:h]),
        :proposal_stats => copy(record[:proposal_stats]),
    ]
    if sampler.blob
        push!(data, :blobs => copy(record[:blobs]))
    end
    if sampler.save_bounds
        push!(data, :bound => deepcopy(sampler.bound_list))
        push!(data, :bound_iter => Int.(record[:bounditer]))
        push!(data, :boundidx => Int.(record[:boundidx]))
    end
    return Results(data)
end

function n_effective(sampler::NestedSampler)
    isempty(sampler.saved_run[:logwt]) && return 0.0
    logwt = Float64.(sampler.saved_run[:logwt])
    all(isinf, logwt) && return 0.0
    return get_neff_from_logwt(logwt)
end

function sampler_snapshot(sampler::NestedSampler)
    return Dict{Symbol, Any}(
        :type => :NestedSampler,
        :ndim => sampler.ndim,
        :nlive => sampler.nlive,
        :ncdim => sampler.ncdim,
        :blob => sampler.blob,
        :copy_inputs => sampler.copy_inputs,
        :rng => sampler.rng,
        :bound_kind => sampler.bound_kind,
        :sample_kind => sampler.sample_kind,
        :bound => sampler.bound,
        :bound_next => sampler.bound_next,
        :internal_sampler => sampler.internal_sampler,
        :internal_sampler_next => sampler.internal_sampler_next,
        :live_u => sampler.live_u,
        :live_v => sampler.live_v,
        :live_logl => sampler.live_logl,
        :live_blobs => sampler.live_blobs,
        :live_bound => sampler.live_bound,
        :live_it => sampler.live_it,
        :saved_run => sampler.saved_run,
        :ncall => sampler.ncall,
        :it => sampler.it,
        :eff => sampler.eff,
        :added_live => sampler.added_live,
        :logvol_init => sampler.logvol_init,
        :dlv => sampler.dlv,
        :unit_cube_sampling => sampler.unit_cube_sampling,
        :bound_list => sampler.bound_list,
        :nbound => sampler.nbound,
        :bound_update_interval => sampler.bound_update_interval,
        :first_bound_update => sampler.first_bound_update,
        :first_bound_update_ncall => sampler.first_bound_update_ncall,
        :first_bound_update_eff => sampler.first_bound_update_eff,
        :logl_first_update => sampler.logl_first_update,
        :ncall_at_last_update => sampler.ncall_at_last_update,
        :bound_bootstrap => sampler.bound_bootstrap,
        :bound_enlarge => sampler.bound_enlarge,
        :save_bounds => sampler.save_bounds,
        :plateau_mode => sampler.plateau_mode,
        :plateau_counter => sampler.plateau_counter,
        :plateau_logdvol => sampler.plateau_logdvol,
    )
end

function _restore_nested_sampler(state::AbstractDict, loglikelihood, prior_transform)
    return NestedSampler(
        loglikelihood,
        prior_transform,
        Int(state[:ndim]),
        Int(state[:nlive]),
        Int(state[:ncdim]),
        Bool(state[:blob]),
        Bool(state[:copy_inputs]),
        state[:rng],
        Symbol(state[:bound_kind]),
        Symbol(state[:sample_kind]),
        state[:bound],
        state[:bound_next],
        state[:internal_sampler],
        state[:internal_sampler_next],
        Matrix{Float64}(state[:live_u]),
        Matrix{Float64}(state[:live_v]),
        Vector{Float64}(state[:live_logl]),
        state[:live_blobs],
        Vector{Int}(state[:live_bound]),
        Vector{Int}(state[:live_it]),
        state[:saved_run],
        Int(state[:ncall]),
        Int(state[:it]),
        Float64(state[:eff]),
        Bool(state[:added_live]),
        Float64(state[:logvol_init]),
        Float64(state[:dlv]),
        Bool(state[:unit_cube_sampling]),
        Vector{Any}(state[:bound_list]),
        Int(state[:nbound]),
        Int(state[:bound_update_interval]),
        Dict{Symbol, Any}(state[:first_bound_update]),
        Int(state[:first_bound_update_ncall]),
        Float64(state[:first_bound_update_eff]),
        state[:logl_first_update],
        Int(state[:ncall_at_last_update]),
        Int(state[:bound_bootstrap]),
        Float64(state[:bound_enlarge]),
        Bool(state[:save_bounds]),
        Bool(state[:plateau_mode]),
        Int(state[:plateau_counter]),
        Float64(state[:plateau_logdvol]),
    )
end
