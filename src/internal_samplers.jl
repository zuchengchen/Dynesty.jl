using LinearAlgebra
using Random

abstract type AbstractInternalSampler end

struct SamplerArgument{P, L, K}
    u::Vector{Float64}
    loglstar::Float64
    axes::Matrix{Float64}
    scale::Float64
    prior_transform::P
    loglikelihood::L
    rng::AbstractRNG
    kwargs::K
end

struct SamplerReturn
    u::Vector{Float64}
    v::Vector{Float64}
    logl::Float64
    ncalls::Int
    evaluation_history::Vector{EvaluationHistoryItem}
    tuning_info::Dict{Symbol, Any}
    proposal_stats::Dict{Symbol, Any}
end

mutable struct UniformBoundSampler <: AbstractInternalSampler
    scale::Float64
    sampler_kwargs::Dict{Symbol, Any}
end

mutable struct UnitCubeSampler <: AbstractInternalSampler
    scale::Float64
    ndim::Int
    sampler_kwargs::Dict{Symbol, Any}
end

mutable struct RWalkSampler <: AbstractInternalSampler
    scale::Float64
    walks::Int
    facc::Float64
    ncdim::Union{Nothing, Int}
    rwalk_history::Dict{Symbol, Int}
    sampler_kwargs::Dict{Symbol, Any}
end

mutable struct SliceSampler <: AbstractInternalSampler
    scale::Float64
    slices::Int
    slice_history::Dict{Symbol, Int}
    sampler_kwargs::Dict{Symbol, Any}
end

mutable struct RSliceSampler <: AbstractInternalSampler
    scale::Float64
    slices::Int
    slice_history::Dict{Symbol, Int}
    sampler_kwargs::Dict{Symbol, Any}
end

function _sampler_kwargs(kwargs)
    out = Dict{Symbol, Any}()
    for key in (:nonbounded, :periodic, :reflective, :nonperiodic, :slice_doubling)
        if haskey(kwargs, key)
            out[key] = kwargs[key]
        end
    end
    return out
end

UniformBoundSampler(; kwargs...) = UniformBoundSampler(1.0, _sampler_kwargs(kwargs))

function UnitCubeSampler(; ndim::Integer, kwargs...)
    ndim > 0 || throw(ArgumentError("ndim must be positive; got $ndim"))
    return UnitCubeSampler(
        1.0, Int(ndim), merge(_sampler_kwargs(kwargs), Dict(:ndim => Int(ndim)))
    )
end

function RWalkSampler(; walks::Integer=25, facc::Real=0.5, ncdim=nothing, kwargs...)
    walks_i = max(2, Int(walks))
    facc_f = min(1.0, max(1.0 / walks_i, Float64(facc)))
    sampler_kwargs = merge(
        _sampler_kwargs(kwargs),
        Dict{Symbol, Any}(
            :walks => walks_i, :ncdim => isnothing(ncdim) ? nothing : Int(ncdim)
        ),
    )
    return RWalkSampler(
        1.0,
        walks_i,
        facc_f,
        isnothing(ncdim) ? nothing : Int(ncdim),
        Dict(:n_accept => 0, :n_reject => 0),
        sampler_kwargs,
    )
end

function SliceSampler(; slices::Integer=5, kwargs...)
    slices_i = Int(slices)
    slices_i > 0 || throw(ArgumentError("slices must be positive; got $slices"))
    return SliceSampler(
        1.0,
        slices_i,
        Dict(:n_contract => 0, :n_expand => 0),
        merge(_sampler_kwargs(kwargs), Dict{Symbol, Any}(:slices => slices_i)),
    )
end

function RSliceSampler(; slices::Integer=5, kwargs...)
    slices_i = Int(slices)
    slices_i > 0 || throw(ArgumentError("slices must be positive; got $slices"))
    return RSliceSampler(
        1.0,
        slices_i,
        Dict(:n_contract => 0, :n_expand => 0),
        merge(_sampler_kwargs(kwargs), Dict{Symbol, Any}(:slices => slices_i)),
    )
end

update_bound_interval_ratio(::UniformBoundSampler) = 1
update_bound_interval_ratio(sampler::UnitCubeSampler) = 1
update_bound_interval_ratio(sampler::RWalkSampler) = sampler.walks
update_bound_interval_ratio(sampler::SliceSampler) =
    sampler.slices * get(sampler.sampler_kwargs, :ndim, 1)
update_bound_interval_ratio(sampler::RSliceSampler) = sampler.slices

function _mask_from_indices(indices, ndim::Int)
    isnothing(indices) && return nothing
    if indices isa AbstractVector{Bool}
        length(indices) == ndim ||
            throw(DimensionMismatch("mask length $(length(indices)) != ndim $ndim"))
        return collect(indices)
    end
    mask = falses(ndim)
    for raw in indices
        idx = Int(raw)
        1 <= idx <= ndim || throw(BoundsError("dimension index $idx outside 1:$ndim"))
        mask[idx] = true
    end
    return mask
end

function _kwargs_with_masks(kwargs::AbstractDict, ndim::Int)
    out = Dict{Symbol, Any}(kwargs)
    for key in (:nonbounded, :periodic, :reflective, :nonperiodic)
        if haskey(out, key)
            out[key] = _mask_from_indices(out[key], ndim)
        end
    end
    return out
end

function _record_eval!(history::Vector{EvaluationHistoryItem}, u, v, logl)
    push!(
        history,
        EvaluationHistoryItem(Vector{Float64}(u), Vector{Float64}(v), Float64(logl)),
    )
    return history
end

function _eval_point(prior_transform, loglikelihood, u)
    v_raw = prior_transform(Vector{Float64}(u))
    v = Vector{Float64}(v_raw)
    logl_out = LoglOutput(loglikelihood(v))
    return v, logl_out.logl
end

function _sampler_argument(
    sampler::AbstractInternalSampler,
    u;
    loglstar::Real,
    axes,
    prior_transform,
    loglikelihood,
    rng::AbstractRNG=Random.default_rng(),
    kwargs=Dict{Symbol, Any}(),
)
    u_v = Vector{Float64}(u)
    axes_m = Matrix{Float64}(axes)
    ndim = length(u_v)
    merged = merge(getfield(sampler, :sampler_kwargs), Dict{Symbol, Any}(kwargs))
    merged = _kwargs_with_masks(merged, ndim)
    return SamplerArgument(
        u_v,
        Float64(loglstar),
        axes_m,
        getfield(sampler, :scale),
        prior_transform,
        loglikelihood,
        rng,
        merged,
    )
end

function sample(
    sampler::UnitCubeSampler;
    loglstar::Real,
    prior_transform,
    loglikelihood,
    rng::AbstractRNG=Random.default_rng(),
)
    kwargs = _kwargs_with_masks(sampler.sampler_kwargs, sampler.ndim)
    ncalls = 0
    history = EvaluationHistoryItem[]
    while true
        u = rand(rng, sampler.ndim)
        v, logl = _eval_point(prior_transform, loglikelihood, u)
        ncalls += 1
        _record_eval!(history, u, v, logl)
        if logl > loglstar
            return SamplerReturn(
                u,
                v,
                logl,
                ncalls,
                history,
                Dict{Symbol, Any}(),
                Dict{Symbol, Any}(:n_proposals => ncalls),
            )
        end
    end
end

function sample(
    sampler::UniformBoundSampler;
    bound::AbstractBound,
    loglstar::Real,
    prior_transform,
    loglikelihood,
    ndim::Integer,
    n_cluster::Integer=ndim,
    rng::AbstractRNG=Random.default_rng(),
)
    ndim_i = Int(ndim)
    n_cluster_i = Int(n_cluster)
    kwargs = _kwargs_with_masks(sampler.sampler_kwargs, ndim_i)
    nonbounded = get(kwargs, :nonbounded, nothing)
    ncalls = 0
    ntries = 0
    history = EvaluationHistoryItem[]
    while true
        u_cluster = samples(bound, 1; rng=rng)[1, :]
        if !unitcheck(
            u_cluster;
            nonbounded=isnothing(nonbounded) ? nothing : nonbounded[1:n_cluster_i],
        )
            ntries += 1
            continue
        end
        u = if n_cluster_i == ndim_i
            Vector{Float64}(u_cluster)
        else
            vcat(Vector{Float64}(u_cluster), rand(rng, ndim_i - n_cluster_i))
        end
        v, logl = _eval_point(prior_transform, loglikelihood, u)
        ncalls += 1
        _record_eval!(history, u, v, logl)
        if logl > loglstar
            return SamplerReturn(
                u,
                v,
                logl,
                ncalls,
                history,
                Dict{Symbol, Any}(),
                Dict{Symbol, Any}(:n_proposals => ntries),
            )
        end
    end
end

function propose_ball_point(
    u,
    scale::Real,
    axes,
    n::Integer,
    n_cluster::Integer;
    rng::AbstractRNG=Random.default_rng(),
    periodic=nothing,
    reflective=nothing,
    nonbounded=nothing,
)
    n_i = Int(n)
    n_cluster_i = Int(n_cluster)
    u_v = Vector{Float64}(u)
    length(u_v) == n_i || throw(DimensionMismatch("length(u) $(length(u_v)) != n $n_i"))
    axes_m = Matrix{Float64}(axes)
    size(axes_m, 1) == n_cluster_i || throw(
        DimensionMismatch(
            "axes first dimension $(size(axes_m, 1)) != n_cluster $n_cluster_i"
        ),
    )
    periodic_mask = _mask_from_indices(periodic, n_i)
    reflective_mask = _mask_from_indices(reflective, n_i)
    nonbounded_mask = _mask_from_indices(nonbounded, n_i)

    u_prop = zeros(Float64, n_i)
    if n_i > n_cluster_i
        u_prop[(n_cluster_i + 1):end] .= rand(rng, n_i - n_cluster_i)
    end
    dr = randsphere(n_cluster_i; rng)
    du = axes_m * dr
    u_prop[1:n_cluster_i] .= u_v[1:n_cluster_i] .+ Float64(scale) .* du

    if !isnothing(periodic_mask)
        u_prop[periodic_mask] .= mod.(u_prop[periodic_mask], 1.0)
    end
    if !isnothing(reflective_mask)
        apply_reflect!(view(u_prop, reflective_mask))
    end
    if unitcheck(u_prop; nonbounded=nonbounded_mask)
        return u_prop, false
    else
        return nothing, true
    end
end

function generic_random_walk(
    u,
    loglstar::Real,
    axes,
    scale::Real,
    prior_transform,
    loglikelihood,
    rng::AbstractRNG,
    kwargs::AbstractDict,
)
    u_current = Vector{Float64}(u)
    n = length(u_current)
    n_cluster = get(kwargs, :ncdim, nothing)
    n_cluster = isnothing(n_cluster) ? size(axes, 1) : Int(n_cluster)
    walks = Int(kwargs[:walks])
    masked = _kwargs_with_masks(kwargs, n)
    history = EvaluationHistoryItem[]
    n_accept = 0
    n_reject = 0
    ncalls = 0
    v_current = nothing
    logl_current = -Inf
    while ncalls < walks
        u_prop, fail = propose_ball_point(
            u_current,
            scale,
            axes,
            n,
            n_cluster;
            rng,
            periodic=get(masked, :periodic, nothing),
            reflective=get(masked, :reflective, nothing),
            nonbounded=get(masked, :nonbounded, nothing),
        )
        if fail
            n_reject += 1
            ncalls += 1
            continue
        end
        v_prop, logl_prop = _eval_point(prior_transform, loglikelihood, u_prop)
        ncalls += 1
        _record_eval!(history, u_prop, v_prop, logl_prop)
        if logl_prop > loglstar
            u_current = u_prop
            v_current = v_prop
            logl_current = logl_prop
            n_accept += 1
        else
            n_reject += 1
        end
    end
    if n_accept == 0
        v_current, logl_current = _eval_point(prior_transform, loglikelihood, u_current)
    end
    return SamplerReturn(
        u_current,
        v_current,
        logl_current,
        ncalls,
        history,
        Dict{Symbol, Any}(
            :accept => n_accept, :reject => n_reject, :scale => Float64(scale)
        ),
        Dict{Symbol, Any}(:n_accept => n_accept, :n_reject => n_reject),
    )
end

function sample(
    sampler::RWalkSampler,
    u;
    loglstar::Real,
    axes,
    prior_transform,
    loglikelihood,
    rng::AbstractRNG=Random.default_rng(),
    kwargs=Dict{Symbol, Any}(),
)
    args = _sampler_argument(
        sampler, u; loglstar, axes, prior_transform, loglikelihood, rng, kwargs
    )
    return generic_random_walk(
        args.u,
        args.loglstar,
        args.axes,
        args.scale,
        args.prior_transform,
        args.loglikelihood,
        args.rng,
        args.kwargs,
    )
end

function tune!(sampler::RWalkSampler, tuning_info::AbstractDict; update::Bool=true)
    sampler.scale = Float64(tuning_info[:scale])
    sampler.rwalk_history[:n_accept] += Int(tuning_info[:accept])
    sampler.rwalk_history[:n_reject] += Int(tuning_info[:reject])
    update || return sampler
    accept = sampler.rwalk_history[:n_accept]
    reject = sampler.rwalk_history[:n_reject]
    total = accept + reject
    total == 0 && return sampler
    facc = accept / total
    ncdim = isnothing(sampler.ncdim) ? 1 : sampler.ncdim
    sampler.scale *= exp((facc - sampler.facc) / ncdim / sampler.facc)
    sampler.rwalk_history[:n_accept] = 0
    sampler.rwalk_history[:n_reject] = 0
    return sampler
end

function _slice_doubling_accept(x1, F, loglstar, L, R, fL, fR)
    lhat = Float64(L)
    rhat = Float64(R)
    f_lhat = Float64(fL)
    f_rhat = Float64(fR)
    D = false
    while rhat - lhat > 1.1
        midpoint = (lhat + rhat) / 2
        if (0 < midpoint <= x1) || (x1 < midpoint <= 0)
            D = true
        end
        if x1 < midpoint
            rhat = midpoint
            f_rhat = F(rhat)[2]
        else
            lhat = midpoint
            f_lhat = F(lhat)[2]
        end
        if D && loglstar >= f_lhat && loglstar >= f_rhat
            return false
        end
    end
    return true
end

function generic_slice_step(
    u,
    direction,
    nonperiodic,
    loglstar::Real,
    loglikelihood,
    prior_transform,
    doubling::Bool,
    evaluation_history::Vector{EvaluationHistoryItem},
    rng::AbstractRNG,
)
    u0 = Vector{Float64}(u)
    dir = Vector{Float64}(direction)
    n = length(u0)
    length(dir) == n || throw(DimensionMismatch("direction length $(length(dir)) != $n"))
    nonperiodic_mask = _mask_from_indices(nonperiodic, n)
    ncalls = 0
    n_expand = 0
    n_contract = 0
    rand0 = rand(rng)
    dirlen = norm(dir)
    dirlen > 0 || throw(ArgumentError("slice direction must be nonzero"))
    maxlen = sqrt(n) / 2
    dirnorm = dirlen > maxlen ? dirlen / maxlen : 1.0
    dir ./= dirnorm

    function F(x)
        u_new = u0 .+ Float64(x) .* dir
        if unitcheck(u_new; nonbounded=nonperiodic_mask)
            v_new, logl = _eval_point(prior_transform, loglikelihood, u_new)
            _record_eval!(evaluation_history, u_new, v_new, logl)
        else
            logl = -Inf
        end
        ncalls += 1
        return u_new, logl
    end

    nstep_l = -rand0
    nstep_r = 1 - rand0
    logl_l = F(nstep_l)[2]
    logl_r = F(nstep_r)[2]
    expansion_warning = false
    L = nstep_l
    R = nstep_r
    fL = logl_l
    fR = logl_r
    if !doubling
        while logl_l > loglstar
            nstep_l -= 1
            logl_l = F(nstep_l)[2]
            n_expand += 1
            if n_expand > 1000
                expansion_warning = true
                break
            end
        end
        while logl_r > loglstar
            nstep_r += 1
            logl_r = F(nstep_r)[2]
            n_expand += 1
            if n_expand > 1000
                expansion_warning = true
                break
            end
        end
    else
        K = 1
        while logl_l > loglstar || logl_r > loglstar
            if rand(rng) < 0.5
                nstep_l -= nstep_r - nstep_l
                logl_l = F(nstep_l)[2]
            else
                nstep_r += nstep_r - nstep_l
                logl_r = F(nstep_r)[2]
            end
            n_expand += K
            K *= 2
        end
        L = nstep_l
        R = nstep_r
        fL = logl_l
        fR = logl_r
    end

    while true
        nstep_hat = nstep_r - nstep_l
        nstep_prop = nstep_l + rand(rng) * nstep_hat
        u_prop, logl_prop = F(nstep_prop)
        n_contract += 1
        if logl_prop > loglstar &&
            (!doubling || _slice_doubling_accept(nstep_prop, F, loglstar, L, R, fL, fR))
            v_prop, _ = _eval_point(prior_transform, loglikelihood, u_prop)
            return u_prop,
            v_prop, logl_prop, ncalls, n_expand, n_contract,
            expansion_warning
        elseif nstep_prop < 0
            nstep_l = nstep_prop
        elseif nstep_prop > 0
            nstep_r = nstep_prop
        else
            throw(ErrorException("Slice sampler failed to find a valid point"))
        end
    end
end

function _slice_axes(axes::AbstractMatrix{<:Real}, scale::Real)
    return Float64(scale) .* transpose(Matrix{Float64}(axes))
end

function sample(
    sampler::SliceSampler,
    u;
    loglstar::Real,
    axes,
    prior_transform,
    loglikelihood,
    rng::AbstractRNG=Random.default_rng(),
    kwargs=Dict{Symbol, Any}(),
)
    args = _sampler_argument(
        sampler, u; loglstar, axes, prior_transform, loglikelihood, rng, kwargs
    )
    n = length(args.u)
    axes_scaled = _slice_axes(args.axes, args.scale)
    slices = Int(args.kwargs[:slices])
    nonperiodic = get(args.kwargs, :nonperiodic, nothing)
    doubling = Bool(get(args.kwargs, :slice_doubling, false))
    history = EvaluationHistoryItem[]
    u_current = copy(args.u)
    v_prop = Float64[]
    logl_prop = -Inf
    ncalls = 0
    n_expand = 0
    n_contract = 0
    expansion_warning_set = false
    for _ in 1:slices
        idxs = collect(1:n)
        shuffle!(rng, idxs)
        for idx in idxs
            axis = vec(axes_scaled[idx, :])
            step = generic_slice_step(
                u_current,
                axis,
                nonperiodic,
                args.loglstar,
                args.loglikelihood,
                args.prior_transform,
                doubling,
                history,
                rng,
            )
            u_current, v_prop, logl_prop = step[1], step[2], step[3]
            ncalls += step[4]
            n_expand += step[5]
            n_contract += step[6]
            if step[7] && !doubling
                expansion_warning_set = true
                doubling = true
            end
        end
    end
    tuning_info = Dict{Symbol, Any}(
        :n_expand => n_expand,
        :n_contract => n_contract,
        :expansion_warning_set => expansion_warning_set,
    )
    return SamplerReturn(
        u_current,
        v_prop,
        logl_prop,
        ncalls,
        history,
        tuning_info,
        Dict{Symbol, Any}(:n_expand => n_expand, :n_contract => n_contract),
    )
end

function sample(
    sampler::RSliceSampler,
    u;
    loglstar::Real,
    axes,
    prior_transform,
    loglikelihood,
    rng::AbstractRNG=Random.default_rng(),
    kwargs=Dict{Symbol, Any}(),
)
    args = _sampler_argument(
        sampler, u; loglstar, axes, prior_transform, loglikelihood, rng, kwargs
    )
    n = length(args.u)
    slices = Int(args.kwargs[:slices])
    nonperiodic = get(args.kwargs, :nonperiodic, nothing)
    doubling = Bool(get(args.kwargs, :slice_doubling, false))
    history = EvaluationHistoryItem[]
    u_current = copy(args.u)
    v_prop = Float64[]
    logl_prop = -Inf
    ncalls = 0
    n_expand = 0
    n_contract = 0
    expansion_warning_set = false
    for _ in 1:slices
        drhat = randn(rng, n)
        drhat ./= norm(drhat)
        direction = args.axes * drhat .* args.scale
        step = generic_slice_step(
            u_current,
            direction,
            nonperiodic,
            args.loglstar,
            args.loglikelihood,
            args.prior_transform,
            doubling,
            history,
            rng,
        )
        u_current, v_prop, logl_prop = step[1], step[2], step[3]
        ncalls += step[4]
        n_expand += step[5]
        n_contract += step[6]
        if step[7] && !doubling
            expansion_warning_set = true
            doubling = true
        end
    end
    tuning_info = Dict{Symbol, Any}(
        :n_expand => n_expand,
        :n_contract => n_contract,
        :expansion_warning_set => expansion_warning_set,
    )
    return SamplerReturn(
        u_current,
        v_prop,
        logl_prop,
        ncalls,
        history,
        tuning_info,
        Dict{Symbol, Any}(:n_expand => n_expand, :n_contract => n_contract),
    )
end

function tune_slice(
    sampler::Union{SliceSampler, RSliceSampler},
    tuning_info::AbstractDict;
    update::Bool=true,
)
    sampler.slice_history[:n_expand] += Int(tuning_info[:n_expand])
    sampler.slice_history[:n_contract] += Int(tuning_info[:n_contract])
    if get(tuning_info, :expansion_warning_set, false)
        sampler.sampler_kwargs[:slice_doubling] = true
    end
    update || return sampler
    n_expand = max(sampler.slice_history[:n_expand], 1)
    n_contract = sampler.slice_history[:n_contract]
    mult = clamp(n_expand * 2.0 / (n_expand + n_contract), 0.5, 2.0)
    sampler.scale *= mult
    sampler.slice_history[:n_expand] = 0
    sampler.slice_history[:n_contract] = 0
    return sampler
end
