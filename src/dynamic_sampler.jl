@enum DynamicSamplerState begin
    DynamicSamplerInit = 1
    DynamicSamplerLivePointsInit = 2
    DynamicSamplerInBase = 3
    DynamicSamplerBaseDone = 4
    DynamicSamplerInBatch = 5
    DynamicSamplerBatchDone = 6
    DynamicSamplerInBaseAddLive = 7
    DynamicSamplerInBatchAddLive = 8
    DynamicSamplerRunDone = 9
end

struct DynamicBatchFirstPoint
    worst::Int
    ustar::Vector{Float64}
    vstar::Vector{Float64}
    loglstar::Float64
    nc::Int
    worst_it::Int
    boundidx::Int
    bounditer::Int
    eff::Float64
    delta_logz::Float64
    proposal_stats::Any
end

struct ConfiguredBatchSampler{S}
    sampler::S
    first_points::Vector{DynamicBatchFirstPoint}
    ncall::Int
    niter::Int
    logl_min::Float64
    logl_max::Float64
    fresh_prior::Bool
    selected_indices::Vector{Int}
    join_index::Int
end

"""
    DynamicSampler(loglikelihood, prior_transform, ndim; kwargs...)

Julia-native dynamic nested sampler. The sampler runs an initial baseline pass,
can add adaptive batches, and returns dynamic-shaped [`Results`](@ref) with
batch metadata.
"""
mutable struct DynamicSampler{L, P}
    loglikelihood::L
    prior_transform::P
    ndim::Int
    ncdim::Int
    blob::Bool
    copy_inputs::Bool
    bounding::Any
    sampling::Any
    bound_update_interval_ratio::Float64
    first_bound_update::Dict{Symbol, Any}
    rng::AbstractRNG
    map_backend::AbstractMapBackend
    periodic::Any
    reflective::Any
    walks::Any
    slices::Any
    facc::Float64
    nlive0::Int
    bound_enlarge::Any
    bound_bootstrap::Any
    sampler::Any
    saved_run::RunRecord
    base_run::RunRecord
    new_run::Any
    batch::Int
    it::Int
    ncall::Int
    eff::Float64
    bound_list::Vector{Any}
    internal_state::DynamicSamplerState
    live_u::Any
    live_v::Any
    live_logl::Any
    live_blobs::Any
    live_bound::Any
    live_it::Any
    live_init::Any
    nlive_init::Any
    batch_sampler::Any
    new_logl_min::Float64
    new_logl_max::Float64
end

function DynamicSampler(
    loglikelihood,
    prior_transform,
    ndim::Integer;
    nlive::Integer=500,
    nlive0=nothing,
    bound=:multi,
    sample=:auto,
    bounding=nothing,
    sampling=nothing,
    periodic=nothing,
    reflective=nothing,
    update_interval=nothing,
    bound_update_interval_ratio=nothing,
    first_update=nothing,
    first_bound_update=nothing,
    rng=nothing,
    rstate=nothing,
    parallel=:serial,
    map_backend=nothing,
    queue_size=nothing,
    enlarge=nothing,
    bootstrap=nothing,
    bound_enlarge=nothing,
    bound_bootstrap=nothing,
    walks=nothing,
    facc::Real=0.5,
    slices=nothing,
    ncdim=nothing,
    blob::Bool=false,
    copy_inputs::Bool=false,
    kwargs...,
)
    isempty(kwargs) || throw(
        ArgumentError("unsupported DynamicSampler keyword(s): $(collect(keys(kwargs)))")
    )
    ndim_i = Int(ndim)
    ndim_i > 0 || throw(ArgumentError("ndim must be positive; got $ndim"))
    nlive_i = isnothing(nlive0) ? Int(nlive) : Int(nlive0)
    nlive_i > 0 || throw(ArgumentError("nlive must be positive; got $nlive_i"))
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
    backend = _get_map_backend(parallel, map_backend, queue_size)

    sampling_v = isnothing(sampling) ? sample : sampling
    bounding_v = isnothing(bounding) ? bound : bounding
    first_update_v = if isnothing(first_update)
        first_bound_update
    else
        first_update
    end
    first_update_d = if isnothing(first_update_v)
        Dict{Symbol, Any}()
    else
        _check_first_update(first_update_v)
    end
    bound_enlarge_v = isnothing(bound_enlarge) ? enlarge : bound_enlarge
    bound_bootstrap_v = isnothing(bound_bootstrap) ? bootstrap : bound_bootstrap
    facc_f = Float64(facc)

    interval_ratio = if isnothing(bound_update_interval_ratio)
        internal_sampler = _get_internal_sampler(
            sampling_v,
            ndim_i,
            ncdim_i;
            periodic,
            reflective,
            walks,
            slices,
            facc=facc_f,
        )
        _get_update_interval_ratio(update_interval, internal_sampler, nlive_i)
    else
        ratio = Float64(bound_update_interval_ratio)
        ratio > 0 ||
            throw(ArgumentError("bound_update_interval_ratio must be positive"))
        ratio
    end
    interval_ratio = Float64(interval_ratio)

    return DynamicSampler(
        loglikelihood,
        prior_transform,
        ndim_i,
        ncdim_i,
        blob,
        copy_inputs,
        bounding_v,
        sampling_v,
        interval_ratio,
        first_update_d,
        rng_obj,
        backend,
        periodic,
        reflective,
        walks,
        slices,
        facc_f,
        nlive_i,
        bound_enlarge_v,
        bound_bootstrap_v,
        nothing,
        RunRecord(; dynamic=true),
        RunRecord(; dynamic=true),
        nothing,
        0,
        1,
        0,
        1.0,
        Any[],
        DynamicSamplerInit,
        nothing,
        nothing,
        nothing,
        nothing,
        nothing,
        nothing,
        nothing,
        nothing,
        nothing,
        -Inf,
        Inf,
    )
end

const DynamicNestedSampler = DynamicSampler

function _dynamic_arg(args, key::Symbol, default)
    isnothing(args) && return default
    if args isa AbstractDict
        haskey(args, key) && return args[key]
        skey = String(key)
        haskey(args, skey) && return args[skey]
        return default
    end
    return hasproperty(args, key) ? getproperty(args, key) : default
end

function _dynamic_get(main_sampler, names; default=nothing, required::Bool=false)
    for raw in names
        key = Symbol(raw)
        if main_sampler isa AbstractDict
            haskey(main_sampler, key) && return main_sampler[key]
            skey = String(key)
            haskey(main_sampler, skey) && return main_sampler[skey]
        elseif hasproperty(main_sampler, key)
            return getproperty(main_sampler, key)
        end
    end
    required &&
        throw(ArgumentError("main_sampler must provide one of $(Tuple(Symbol.(names)))"))
    return default
end

function _dyn_logsumexp(values::AbstractVector{<:Real})
    isempty(values) && throw(ArgumentError("values must not be empty"))
    vals = Float64.(values)
    vmax = maximum(vals)
    isinf(vmax) && return vmax
    return vmax + log(sum(exp.(vals .- vmax)))
end

function _dyn_logsubexp(loga::Real, logb::Real)
    a = Float64(loga)
    b = Float64(logb)
    b == -Inf && return a
    b == a && return -Inf
    b < a || return NaN
    return a + log1p(-exp(b - a))
end

"""
    compute_weights(results)

Compute dynamic nested-sampling evidence and posterior allocation weights.
Returns `(zweight, pweight)`, matching Python dynesty's dynamic sampler helper.
"""
function compute_weights(res::Results)
    haskey(res, :samples_n) || throw(KeyError(:samples_n))
    logl = Float64.(res.logl)
    logz = Float64.(res.logz)
    logvol = Float64.(res.logvol)
    logwt = Float64.(res.logwt)
    samples_n = Float64.(res.samples_n)
    n = length(logl)
    length(logz) == n &&
    length(logvol) == n &&
    length(logwt) == n &&
    length(samples_n) == n ||
        throw(DimensionMismatch("dynamic result arrays must have matching lengths"))

    zweight = if maximum(logz) - minimum(logz) == 0.0
        fill(1.0 / n, n)
    else
        logz_remain = logl[end] + logvol[end]
        logz_tot = logaddexp(logz[end], logz_remain)
        logzin = [_dyn_logsubexp(logz_tot, lz) for lz in logz]
        logzweight = logzin .- log.(samples_n)
        logzweight .-= _dyn_logsumexp(logzweight)
        exp.(logzweight)
    end

    pweight = exp.(logwt .- logz[end])
    pweight ./= sum(pweight)
    return zweight, pweight
end

"""
    weight_function(results[, args]; return_weights=false, pfrac=0.8, maxfrac=0.8, pad=1)

Default dynamic nested-sampling batch-bound heuristic. Returns
`(logl_min, logl_max)` or, with `return_weights=true`,
`((logl_min, logl_max), (pweight, zweight, weight))`.
"""
function weight_function(
    res::Results,
    args=nothing;
    return_weights::Bool=false,
    pfrac=nothing,
    maxfrac=nothing,
    pad=nothing,
)
    pfrac_v = Float64(isnothing(pfrac) ? _dynamic_arg(args, :pfrac, 0.8) : pfrac)
    0.0 <= pfrac_v <= 1.0 ||
        throw(ArgumentError("pfrac must be between 0 and 1; got $pfrac_v"))
    maxfrac_v = Float64(isnothing(maxfrac) ? _dynamic_arg(args, :maxfrac, 0.8) : maxfrac)
    0.0 <= maxfrac_v <= 1.0 ||
        throw(ArgumentError("maxfrac must be between 0 and 1; got $maxfrac_v"))
    pad_v = Int(isnothing(pad) ? _dynamic_arg(args, :pad, 1) : pad)
    pad_v >= 0 || throw(ArgumentError("pad must be nonnegative; got $pad_v"))

    zweight, pweight = compute_weights(res)
    weight = (1.0 - pfrac_v) .* zweight .+ pfrac_v .* pweight
    nsamps = length(weight)
    max_weight = maximum(weight)
    active = findall(weight .> maxfrac_v * max_weight)
    isempty(active) &&
        throw(ArgumentError("no samples exceed the requested weight threshold"))

    lo = first(active) - pad_v
    hi = last(active) + pad_v
    if hi > nsamps
        lo -= hi - nsamps
        hi = nsamps
    end

    logl = Float64.(res.logl)
    if lo <= 1
        logl_min = -Inf
        logl_max = logl[min(hi - lo + 1, nsamps)]
    else
        logl_min = logl[lo]
        logl_max = logl[hi]
    end
    hi == nsamps && (logl_max = Inf)
    bounds = (logl_min, logl_max)
    return return_weights ? (bounds, (pweight, zweight, weight)) : bounds
end

"""
    stopping_function(results[, args]; rng=Random.default_rng(), return_vals=false, ...)

Default dynamic nested-sampling stopping heuristic. Returns a boolean stop flag
or, with `return_vals=true`, `(flag, (stop_post, stop_evid, stop))`.
"""
function stopping_function(
    res::Results,
    args=nothing;
    rng::AbstractRNG=Random.default_rng(),
    rstate=nothing,
    mapper=map,
    return_vals::Bool=false,
    pfrac=nothing,
    evid_thresh=nothing,
    target_n_effective=nothing,
    n_mc=nothing,
    error=nothing,
    approx=nothing,
)
    rng_eff = isnothing(rstate) ? rng : rstate
    pfrac_v = Float64(isnothing(pfrac) ? _dynamic_arg(args, :pfrac, 1.0) : pfrac)
    0.0 <= pfrac_v <= 1.0 ||
        throw(ArgumentError("pfrac must be between 0 and 1; got $pfrac_v"))
    evid_thresh_v = Float64(
        isnothing(evid_thresh) ? _dynamic_arg(args, :evid_thresh, 0.1) : evid_thresh
    )
    if pfrac_v < 1.0 && evid_thresh_v < 0.0
        throw(ArgumentError("evid_thresh must be nonnegative when pfrac < 1"))
    end
    target_v = Float64(
        if isnothing(target_n_effective)
            _dynamic_arg(args, :target_n_effective, 10_000)
        else
            target_n_effective
        end,
    )
    if pfrac_v > 0.0 && target_v < 0.0
        throw(ArgumentError("target_n_effective must be nonnegative when pfrac > 0"))
    end
    n_mc_v = Int(isnothing(n_mc) ? _dynamic_arg(args, :n_mc, 0) : n_mc)
    n_mc_v >= 0 || throw(ArgumentError("n_mc must be nonnegative; got $n_mc_v"))
    err = Symbol(isnothing(error) ? _dynamic_arg(args, :error, :jitter) : error)
    err in (:jitter, :resample) ||
        throw(ArgumentError("error must be :jitter or :resample; got $(repr(err))"))
    approx_v = Bool(isnothing(approx) ? _dynamic_arg(args, :approx, true) : approx)

    lnz_std = if n_mc_v > 1
        seeds = rand(rng_eff, 1:typemax(Int), n_mc_v)
        outputs = collect(
            mapper(
                args_i -> _kld_error(args_i),
                ((res, err, approx_v, seed) for seed in seeds),
            ),
        )
        lnz_arr = [out[2].logz[end] for out in outputs]
        std(lnz_arr; corrected=false)
    else
        Float64(res.logzerr[end])
    end

    stop_evid = lnz_std / evid_thresh_v
    n_eff = get_neff_from_logwt(res.logwt)
    stop_post = target_v / n_eff
    stop = pfrac_v * stop_post + (1.0 - pfrac_v) * stop_evid
    flag = stop <= 1.0
    return return_vals ? (flag, (stop_post, stop_evid, stop)) : flag
end

"""
    _configure_batch_sampler(main_sampler, nlive_new, update_interval;
                             logl_bounds=nothing, save_bounds=true)

Construct and initialize a static [`NestedSampler`](@ref) for one dynamic
batch, following Python dynesty's `_configure_batch_sampler` logic. The parent
`main_sampler` may be a sampler-like object or dictionary exposing the fields
used by `DynamicSampler`: user functions, sampler/bound settings, RNG,
`saved_run`, and bookkeeping such as `it` and `eff`.
"""
function _configure_batch_sampler(
    main_sampler,
    nlive_new::Integer,
    update_interval::Integer;
    logl_bounds=nothing,
    save_bounds::Bool=true,
)
    nlive_i = Int(nlive_new)
    nlive_i > 1 || throw(ArgumentError("nlive_new must be greater than 1"))
    update_interval_i = Int(update_interval)
    update_interval_i > 0 ||
        throw(ArgumentError("update_interval must be positive; got $update_interval"))

    saved_run = _dynamic_get(main_sampler, (:saved_run,); required=true)
    saved_u = _dynamic_record_matrix(saved_run, :u)
    saved_v = _dynamic_record_matrix(saved_run, :v)
    saved_logl = _dynamic_record_vector(saved_run, :logl)
    saved_logvol = _dynamic_record_vector(saved_run, :logvol)
    saved_scale = _dynamic_record_vector(
        saved_run, :scale; default=ones(length(saved_logl))
    )
    saved_blobs = _dynamic_record_any(
        saved_run, :blobs; default=fill(nothing, length(saved_logl))
    )
    nsaved = length(saved_logl)
    nsaved > 0 || throw(ArgumentError("saved_run must contain at least one sample"))
    size(saved_u, 1) == nsaved &&
    size(saved_v, 1) == nsaved &&
    length(saved_logvol) == nsaved &&
    length(saved_scale) == nsaved ||
        throw(DimensionMismatch("saved_run arrays must have matching lengths"))

    loglikelihood = _dynamic_get(main_sampler, (:loglikelihood,); required=true)
    prior_transform = _dynamic_get(main_sampler, (:prior_transform,); required=true)
    ndim = Int(_dynamic_get(main_sampler, (:ndim,); required=true))
    ncdim = Int(_dynamic_get(main_sampler, (:ncdim,); default=ndim))
    blob = Bool(_dynamic_get(main_sampler, (:blob,); default=false))
    copy_inputs = Bool(_dynamic_get(main_sampler, (:copy_inputs,); default=false))
    rng = _dynamic_get(main_sampler, (:rng, :rstate); default=Random.default_rng())
    rng isa AbstractRNG ||
        throw(ArgumentError("main sampler rng/rstate must be an AbstractRNG"))
    backend_value = _dynamic_get(main_sampler, (:map_backend,); default=nothing)
    map_backend = if isnothing(backend_value)
        _map_backend_from_config(_dynamic_get(main_sampler, (:map_backend_config,); default=nothing))
    else
        backend_value
    end
    map_backend isa AbstractMapBackend ||
        throw(ArgumentError("main sampler map_backend must be an AbstractMapBackend"))
    sampling = _dynamic_get(main_sampler, (:sampling, :sample, :sample_kind); default=:auto)
    bounding = _dynamic_get(main_sampler, (:bounding, :bound, :bound_kind); default=:multi)
    periodic = _dynamic_get(main_sampler, (:periodic,); default=nothing)
    reflective = _dynamic_get(main_sampler, (:reflective,); default=nothing)
    walks = _dynamic_get(main_sampler, (:walks,); default=nothing)
    slices = _dynamic_get(main_sampler, (:slices,); default=nothing)
    facc = _dynamic_get(main_sampler, (:facc,); default=0.5)
    first_update = _dynamic_get(
        main_sampler, (:first_update, :first_bound_update); default=nothing
    )
    bound_bootstrap = _dynamic_get(
        main_sampler, (:bound_bootstrap, :bootstrap); default=nothing
    )
    bound_enlarge = _dynamic_get(main_sampler, (:bound_enlarge, :enlarge); default=nothing)
    parent_sampler = _dynamic_get(main_sampler, (:sampler,); default=nothing)
    logl_first_update = if isnothing(parent_sampler)
        _dynamic_get(main_sampler, (:logl_first_update,); default=nothing)
    else
        _dynamic_get(parent_sampler, (:logl_first_update,); default=nothing)
    end
    parent_it = Int(_dynamic_get(main_sampler, (:it,); default=1))
    parent_eff = Float64(_dynamic_get(main_sampler, (:eff,); default=1.0))

    logl_min, logl_max = _dynamic_batch_logl_bounds(
        logl_bounds, saved_logl, saved_logvol, nlive_i
    )
    fresh_prior = all(>(logl_min), saved_logl)
    first_points = DynamicBatchFirstPoint[]
    ncall = 0
    selected_indices = Int[]

    batch_sampler = if fresh_prior
        live, logvol0, init_ncalls = _initialize_live_points(
            nothing,
            prior_transform,
            loglikelihood;
            nlive=nlive_i,
            ndim,
            rng,
            map_backend=map_backend,
            blob,
            copy_inputs,
        )
        live_u, live_v, live_logl, live_blobs = live
        ncall += init_ncalls
        for i in 1:nlive_i
            push!(
                first_points,
                DynamicBatchFirstPoint(
                    -i,
                    vec(copy(live_u[i, :])),
                    vec(copy(live_v[i, :])),
                    live_logl[i],
                    1,
                    parent_it,
                    0,
                    0,
                    parent_eff,
                    NaN,
                    nothing,
                ),
            )
        end
        sampler = _dynamic_nested_sampler_for_batch(
            loglikelihood,
            prior_transform,
            ndim,
            nlive_i,
            sampling,
            bounding,
            update_interval_i,
            first_update,
            rng,
            live;
            periodic,
            reflective,
            walks,
            slices,
            facc,
            ncdim,
            blob,
            copy_inputs,
            map_backend,
            bound_enlarge,
            bound_bootstrap,
            save_bounds,
            logl_first_update,
        )
        sampler.logvol_init = logvol0
        _update_bound_if_needed!(sampler, logl_min; force=true)
        sampler
    else
        subset0, logl_min = _dynamic_batch_subset(saved_logl, logl_min, nlive_i)
        live_scale = saved_scale[first(subset0)]
        selected_indices = _dynamic_weighted_subset(subset0, saved_logvol, nlive_i; rng)
        length(selected_indices) > 1 ||
            throw(ErrorException("only one live point was selected for the batch"))
        warm_live = (
            copy(saved_u[selected_indices, :]),
            copy(saved_v[selected_indices, :]),
            copy(saved_logl[selected_indices]),
            blob ? Any[saved_blobs[i] for i in selected_indices] : nothing,
        )
        warm_sampler = _dynamic_nested_sampler_for_batch(
            loglikelihood,
            prior_transform,
            ndim,
            length(selected_indices),
            sampling,
            bounding,
            update_interval_i,
            first_update,
            rng,
            warm_live;
            periodic,
            reflective,
            walks,
            slices,
            facc,
            ncdim,
            blob,
            copy_inputs,
            map_backend,
            bound_enlarge,
            bound_bootstrap,
            save_bounds,
            logl_first_update,
        )
        warm_sampler.internal_sampler.scale = live_scale
        _update_bound_if_needed!(warm_sampler, logl_min; force=true)

        live_u = Matrix{Float64}(undef, nlive_i, ndim)
        live_v = Matrix{Float64}(undef, nlive_i, ndim)
        live_logl = Vector{Float64}(undef, nlive_i)
        live_nc = Vector{Int}(undef, nlive_i)
        live_blobs = blob ? Vector{Any}(undef, nlive_i) : nothing
        proposal_stats = Vector{Any}(undef, nlive_i)
        for i in 1:nlive_i
            ret, nc = _new_point!(warm_sampler, logl_min)
            live_u[i, :] .= ret.u
            live_v[i, :] .= ret.v
            live_logl[i] = ret.logl
            live_nc[i] = nc
            blob && (live_blobs[i] = ret.blob)
            proposal_stats[i] = ret.proposal_stats
            ncall += nc
            push!(
                first_points,
                DynamicBatchFirstPoint(
                    -i,
                    copy(ret.u),
                    copy(ret.v),
                    ret.logl,
                    nc,
                    parent_it,
                    0,
                    0,
                    parent_eff,
                    NaN,
                    ret.proposal_stats,
                ),
            )
        end
        live = (live_u, live_v, live_logl, live_blobs)
        _dynamic_nested_sampler_for_batch(
            loglikelihood,
            prior_transform,
            ndim,
            nlive_i,
            sampling,
            bounding,
            update_interval_i,
            first_update,
            rng,
            live;
            periodic,
            reflective,
            walks,
            slices,
            facc,
            ncdim,
            blob,
            copy_inputs,
            map_backend,
            bound_enlarge,
            bound_bootstrap,
            save_bounds,
            logl_first_update,
        )
    end

    batch_sampler.dlv = log((nlive_i + 1.0) / nlive_i)
    join_index = _dynamic_batch_join_index(saved_logl, logl_min)
    _dynamic_truncate_saved_run!(batch_sampler.saved_run, saved_run, join_index)
    return ConfiguredBatchSampler(
        batch_sampler,
        first_points,
        ncall,
        nlive_i,
        Float64(logl_min),
        Float64(logl_max),
        fresh_prior,
        selected_indices,
        join_index,
    )
end

function _dynamic_nested_sampler_for_batch(
    loglikelihood,
    prior_transform,
    ndim::Int,
    nlive::Int,
    sampling,
    bounding,
    update_interval::Int,
    first_update,
    rng::AbstractRNG,
    live;
    periodic,
    reflective,
    walks,
    slices,
    facc,
    ncdim,
    blob,
    copy_inputs,
    map_backend,
    bound_enlarge,
    bound_bootstrap,
    save_bounds,
    logl_first_update,
)
    sampler = NestedSampler(
        loglikelihood,
        prior_transform,
        ndim;
        nlive,
        bound=bounding,
        sample=sampling,
        periodic,
        reflective,
        update_interval,
        first_update,
        rng,
        live_points=live,
        enlarge=bound_enlarge,
        bootstrap=bound_bootstrap,
        walks,
        slices,
        facc,
        ncdim,
        blob,
        copy_inputs,
        map_backend,
    )
    sampler.save_bounds = save_bounds
    sampler.logl_first_update = logl_first_update
    return sampler
end

function _dynamic_batch_logl_bounds(logl_bounds, saved_logl, saved_logvol, nlive_new::Int)
    if isnothing(logl_bounds)
        positions = findall(saved_logvol .< (saved_logvol[end] + log(nlive_new)))
        pos = isempty(positions) ? length(saved_logl) : last(positions)
        return -Inf, saved_logl[pos]
    end
    bounds = Float64.(collect(logl_bounds))
    length(bounds) == 2 ||
        throw(ArgumentError("logl_bounds must be nothing or a length-2 iterable"))
    bounds[1] < bounds[2] || throw(ArgumentError("logl_bounds must satisfy lower < upper"))
    return bounds[1], bounds[2]
end

function _dynamic_batch_subset(saved_logl::AbstractVector{<:Real}, logl_min, nlive_new::Int)
    subset0 = findall(>(logl_min), saved_logl)
    isempty(subset0) && throw(
        ErrorException("could not find live points above requested logl_min=$logl_min")
    )
    if length(subset0) < nlive_new
        if length(saved_logl) < nlive_new
            subset0 = collect(eachindex(saved_logl))
        else
            subset0 = collect((last(subset0) - nlive_new + 1):last(subset0))
        end
        logl_min = first(subset0) > 1 ? Float64(saved_logl[first(subset0) - 1]) : -Inf
    end
    return subset0, logl_min
end

function _dynamic_weighted_subset(subset0, saved_logvol, nlive_new::Int; rng::AbstractRNG)
    logw = Float64.(saved_logvol[subset0])
    weights = exp.(logw .- maximum(logw))
    weights ./= sum(weights)
    positive = count(>(0.0), weights)
    nselect = min(nlive_new, positive)
    selected = Int[]
    available = collect(eachindex(subset0))
    local_weights = copy(weights)
    for _ in 1:nselect
        pick_local = rand_choice(local_weights[available]; rng)
        pos = available[pick_local]
        push!(selected, subset0[pos])
        deleteat!(available, pick_local)
    end
    return selected
end

function _dynamic_batch_join_index(saved_logl, logl_min)
    logl_min == -Inf && return 0
    return argmin(abs.(Float64.(saved_logl) .- Float64(logl_min)))
end

function _dynamic_record_matrix(record, key::Symbol)
    values = collect(record[key])
    isempty(values) && return zeros(Float64, 0, 0)
    first_value = first(values)
    if first_value isa AbstractVector
        rows = [Vector{Float64}(value) for value in values]
        return reduce(vcat, (reshape(row, 1, :) for row in rows))
    else
        matrix = Matrix{Float64}(values)
        ndims(matrix) == 2 || throw(ArgumentError("record key $key must be matrix-like"))
        return matrix
    end
end

function _dynamic_record_vector(record, key::Symbol; default=nothing)
    if !_dynamic_record_haskey(record, key) && !isnothing(default)
        return Float64.(default)
    end
    return Float64.(collect(record[key]))
end

function _dynamic_record_any(record, key::Symbol; default=nothing)
    if !_dynamic_record_haskey(record, key) && !isnothing(default)
        return Vector{Any}(default)
    end
    return Any[collect(record[key])...]
end

_dynamic_record_haskey(record::RunRecord, key::Symbol) = haskey(record.data, key)
_dynamic_record_haskey(record, key::Symbol) = haskey(record, key)

function _dynamic_truncate_saved_run!(target::RunRecord, source, join_index::Int)
    for key in keys(target)
        source_values = _dynamic_record_haskey(source, key) ? collect(source[key]) : Any[]
        target[key] = Any[source_values[1:min(join_index, length(source_values))]...]
    end
    return target
end

function _dynamic_update_interval(sampler::DynamicSampler, update_interval, nlive::Int)
    if isnothing(update_interval)
        return max(1, round(Int, sampler.bound_update_interval_ratio * nlive))
    elseif update_interval isa Integer
        update_interval > 0 || throw(ArgumentError("update_interval must be positive"))
        return Int(update_interval)
    elseif update_interval isa AbstractFloat
        update_interval > 0 || throw(ArgumentError("update_interval must be positive"))
        return max(1, round(Int, Float64(update_interval) * nlive))
    else
        throw(ArgumentError("update_interval must be nothing, integer, or float"))
    end
end

function _dynamic_batch_bounds_matrix(bounds)
    nbounds = length(bounds)
    out = Matrix{Float64}(undef, nbounds, 2)
    for (i, bound) in enumerate(bounds)
        vals = Float64.(collect(bound))
        length(vals) == 2 ||
            throw(ArgumentError("batch_logl_bounds entries must have length 2"))
        out[i, :] .= vals
    end
    return out
end

function _dynamic_run_from_nested(
    sampler::NestedSampler,
    samples_n::AbstractVector{<:Integer};
    batch_id::Integer=0,
    batch_nlive::Integer=sampler.nlive,
    batch_logl_bounds=(-Inf, Inf),
)
    record = sampler.saved_run
    n = length(record[:logl])
    length(samples_n) == n ||
        throw(DimensionMismatch("samples_n length $(length(samples_n)) != run length $n"))
    dyn = RunRecord(; dynamic=true)
    for i in 1:n
        for key in RUN_RECORD_KEYS
            value = key === :n ? Int(samples_n[i]) : record[key][i]
            push!(dyn[key], value)
        end
        push!(dyn[:batch], Int(batch_id))
    end
    push!(dyn[:batch_nlive], Int(batch_nlive))
    push!(
        dyn[:batch_logl_bounds],
        (Float64(batch_logl_bounds[1]), Float64(batch_logl_bounds[2])),
    )
    return dyn
end

function _dynamic_live_snapshot(static_sampler::NestedSampler)
    live_blobs = static_sampler.blob ? copy(static_sampler.live_blobs) : nothing
    return (
        copy(static_sampler.live_u),
        copy(static_sampler.live_v),
        copy(static_sampler.live_logl),
        live_blobs,
    )
end

function _dynamic_adaptive_requested(kwargs)
    for key in (
        :nlive_batch,
        :wt_function,
        :wt_kwargs,
        :maxiter_batch,
        :maxcall_batch,
        :n_effective,
        :stop_function,
        :stop_kwargs,
    )
        !isnothing(kwargs[key]) && return true
    end
    maxbatch = kwargs[:maxbatch]
    !isnothing(maxbatch) && Int(maxbatch) > 0 && return true
    kwargs[:use_stop] === false && return true
    return false
end

function _dynamic_kwargs_dict(args)
    isnothing(args) && return Dict{Symbol, Any}()
    if args isa AbstractDict
        return Dict{Symbol, Any}(Symbol(key) => value for (key, value) in pairs(args))
    end
    return Dict{Symbol, Any}(
        Symbol(key) => getproperty(args, key) for key in propertynames(args)
    )
end

function _dynamic_effective_limit(init_limit, global_limit)
    if isnothing(init_limit)
        return global_limit
    elseif isnothing(global_limit)
        return init_limit
    else
        return min(Int(init_limit), Int(global_limit))
    end
end

_dynamic_limit_value(limit) = isnothing(limit) ? typemax(Int) : Int(limit)

function _dynamic_remaining_limit(global_limit::Int, current::Int)
    global_limit == typemax(Int) && return typemax(Int)
    return max(global_limit - current, 0)
end

function _dynamic_new_run_from_batch(
    configured::ConfiguredBatchSampler,
    batch_id::Integer,
    id_offset::Integer,
    it_offset::Integer,
)
    batch_sampler = configured.sampler
    record = batch_sampler.saved_run
    start = configured.join_index + 1
    stop = length(record[:logl])
    new_run = RunRecord(; dynamic=true)
    if start > stop
        push!(new_run[:batch_nlive], configured.niter)
        push!(new_run[:batch_logl_bounds], (configured.logl_min, configured.logl_max))
        return new_run
    end

    nrows = stop - start + 1
    ndead = max(batch_sampler.it - 1, 0)
    samples_n = if ndead + batch_sampler.nlive == nrows
        vcat(fill(batch_sampler.nlive, ndead), collect(batch_sampler.nlive:-1:1))
    else
        Int.(record[:n][start:stop])
    end

    for (j, row) in enumerate(start:stop)
        for key in RUN_RECORD_KEYS
            value = if key === :id
                Int(record[key][row]) + Int(id_offset)
            elseif key === :n
                Int(samples_n[j])
            elseif key === :it
                Int(record[key][row]) + Int(it_offset)
            else
                record[key][row]
            end
            push!(new_run[key], value)
        end
        push!(new_run[:batch], Int(batch_id))
    end
    push!(new_run[:batch_nlive], configured.niter)
    push!(new_run[:batch_logl_bounds], (configured.logl_min, configured.logl_max))
    return new_run
end

function combine_runs!(sampler::DynamicSampler)
    isnothing(sampler.new_run) && throw(ArgumentError("no new dynamic batch is saved"))
    isempty(sampler.new_run[:id]) && throw(ArgumentError("no new samples are saved"))

    saved = sampler.saved_run
    new = sampler.new_run
    nsaved = length(saved[:logl])
    nnew = length(new[:logl])
    old_batch_nlive = copy(saved[:batch_nlive])
    old_batch_logl_bounds = copy(saved[:batch_logl_bounds])
    combined = RunRecord(; dynamic=true)

    saved_idx = 1
    new_idx = 1
    for _ in 1:(nsaved + nnew)
        saved_logl = saved_idx <= nsaved ? Float64(saved[:logl][saved_idx]) : Inf
        saved_nlive = saved_idx <= nsaved ? Int(saved[:n][saved_idx]) : 0
        new_logl = new_idx <= nnew ? Float64(new[:logl][new_idx]) : Inf
        new_nlive = new_idx <= nnew ? Int(new[:n][new_idx]) : 0
        nlive = saved_logl > sampler.new_logl_min ? saved_nlive + new_nlive : saved_nlive

        source, row = if saved_logl <= new_logl
            current = saved_idx
            saved_idx += 1
            saved, current
        else
            current = new_idx
            new_idx += 1
            new, current
        end

        for key in RUN_RECORD_KEYS
            if key in (:logvol, :logwt, :logz, :logzvar, :h)
                continue
            elseif key === :n
                push!(combined[key], nlive)
            else
                push!(combined[key], source[key][row])
            end
        end
        push!(combined[:batch], source[:batch][row])
    end

    logl = Float64.(combined[:logl])
    nlive_array = Int.(combined[:n])
    logvol = Vector{Float64}(undef, length(logl))
    cur_logvol = if !isnothing(sampler.sampler)
        Float64(sampler.sampler.logvol_init)
    else
        0.0
    end
    plateau_mode = false
    plateau_counter = 0
    plateau_logdvol = 0.0
    for i in eachindex(logl)
        curl = logl[i]
        nlive = nlive_array[i]
        if !plateau_mode && i != lastindex(logl)
            nplateau = count(==(curl), @view logl[i:end])
            if nplateau > 1
                plateau_counter = nplateau
                plateau_logdvol = cur_logvol + log(1.0 / (nlive + 1))
                plateau_mode = true
            end
        end
        if !plateau_mode
            cur_logvol -= log((nlive + 1.0) / nlive)
        else
            cur_logvol += log1p(-exp(plateau_logdvol - cur_logvol))
        end
        logvol[i] = cur_logvol
        if plateau_mode
            plateau_counter -= 1
            plateau_counter == 0 && (plateau_mode = false)
        end
    end
    ints = compute_integrals(; logl, logvol)
    combined[:logvol] = Any[logvol...]
    combined[:logwt] = Any[ints.logwt...]
    combined[:logz] = Any[ints.logz...]
    combined[:logzvar] = Any[ints.logzvar...]
    combined[:h] = Any[ints.h...]
    combined[:batch_nlive] = Any[old_batch_nlive..., maximum(Int.(new[:n]))]
    combined[:batch_logl_bounds] = Any[
        old_batch_logl_bounds..., (sampler.new_logl_min, sampler.new_logl_max)
    ]

    sampler.saved_run = combined
    sampler.new_run = nothing
    sampler.new_logl_min = -Inf
    sampler.new_logl_max = Inf
    sampler.batch += 1
    sampler.it = length(sampler.saved_run[:logl]) + 1
    sampler.eff = 100.0 * max(sampler.it - 1, 0) / max(sampler.ncall, 1)
    return sampler
end

function add_batch!(
    sampler::DynamicSampler;
    nlive=nothing,
    nlive_new=nothing,
    update_interval=nothing,
    dlogz=0.01,
    mode=:weight,
    wt_function=nothing,
    wt_kwargs=nothing,
    logl_bounds=nothing,
    maxiter=nothing,
    maxcall=nothing,
    save_bounds::Bool=true,
    print_progress::Bool=false,
    print_func=nothing,
    resume::Bool=false,
    checkpoint_file=nothing,
    checkpoint_every=nothing,
    stop_val=nothing,
)
    _ = resume
    isempty(sampler.saved_run[:logl]) && throw(
        ArgumentError("run an initial dynamic sampler baseline before adding batches")
    )
    _ = checkpoint_file
    _ = checkpoint_every
    _ = stop_val

    nlive_i = if !isnothing(nlive_new)
        Int(nlive_new)
    elseif !isnothing(nlive)
        Int(nlive)
    else
        sampler.nlive0
    end
    nlive_i > 1 || throw(ArgumentError("nlive for a dynamic batch must be greater than 1"))
    update_interval_i = _dynamic_update_interval(sampler, update_interval, nlive_i)
    maxiter_i = _dynamic_limit_value(maxiter)
    maxcall_i = _dynamic_limit_value(maxcall)

    mode_sym = Symbol(mode)
    bounds = if mode_sym in (:auto, :weight)
        isnothing(logl_bounds) ||
            throw(ArgumentError("logl_bounds may only be supplied with mode=:manual"))
        wt = isnothing(wt_function) ? weight_function : wt_function
        wt(sampler |> results, wt_kwargs)
    elseif mode_sym === :full
        isnothing(logl_bounds) ||
            throw(ArgumentError("logl_bounds may only be supplied with mode=:manual"))
        (-Inf, Inf)
    elseif mode_sym === :manual
        isnothing(logl_bounds) &&
            throw(ArgumentError("mode=:manual requires explicit logl_bounds"))
        logl_bounds
    else
        throw(ArgumentError("mode must be :auto, :weight, :full, or :manual"))
    end

    configured = _configure_batch_sampler(
        sampler, nlive_i, update_interval_i; logl_bounds=bounds, save_bounds
    )
    sampler.batch_sampler = configured.sampler
    sampler.bound_list = configured.sampler.bound_list
    sampler.new_logl_min = configured.logl_min
    sampler.new_logl_max = configured.logl_max
    sampler.new_run = RunRecord(; dynamic=true)
    sampler.ncall += configured.ncall
    it_offset = sampler.it
    maxiter_left =
        maxiter_i == typemax(Int) ? typemax(Int) : max(maxiter_i - configured.niter, 0)
    maxcall_left =
        maxcall_i == typemax(Int) ? typemax(Int) : max(maxcall_i - configured.ncall, 0)

    sampler.internal_state = DynamicSamplerInBatch
    run_nested!(
        configured.sampler;
        maxiter=maxiter_left,
        maxcall=maxcall_left,
        dlogz,
        logl_max=configured.logl_max,
        add_live=true,
        save_bounds,
        print_progress,
        print_func,
    )
    sampler.internal_state = DynamicSamplerInBatchAddLive
    sampler.ncall += configured.sampler.ncall
    id_offset = isempty(sampler.saved_run[:id]) ? 0 : maximum(Int.(sampler.saved_run[:id]))
    sampler.new_run = _dynamic_new_run_from_batch(
        configured, sampler.batch + 1, id_offset, it_offset
    )
    combine_runs!(sampler)
    sampler.internal_state = DynamicSamplerBatchDone
    sampler.batch_sampler = nothing
    return sampler
end

function run_nested!(
    sampler::DynamicSampler;
    nlive_init=nothing,
    update_interval=nothing,
    first_update=nothing,
    maxiter_init=nothing,
    maxcall_init=nothing,
    dlogz_init=0.01,
    logl_max_init::Real=Inf,
    nlive_batch=nothing,
    wt_function=nothing,
    wt_kwargs=nothing,
    maxiter_batch=nothing,
    maxcall_batch=nothing,
    maxiter=nothing,
    maxcall=nothing,
    maxbatch=nothing,
    n_effective=nothing,
    stop_function=nothing,
    stop_kwargs=nothing,
    use_stop::Bool=true,
    save_bounds::Bool=true,
    print_progress::Bool=false,
    print_func=nothing,
    live_points=nothing,
    resume::Bool=false,
    checkpoint_file=nothing,
    checkpoint_every=nothing,
    add_live::Bool=true,
    kwargs...,
)
    isempty(kwargs) ||
        throw(ArgumentError("unsupported run_nested! keyword(s): $(collect(keys(kwargs)))"))
    adaptive_kwargs = (;
        nlive_batch,
        wt_function,
        wt_kwargs,
        maxiter_batch,
        maxcall_batch,
        maxbatch,
        n_effective,
        stop_function,
        stop_kwargs,
        use_stop,
    )
    if sampler.internal_state != DynamicSamplerInit
        sampler.internal_state == DynamicSamplerRunDone || throw(
            ArgumentError(
                "run_nested! can start only from DynamicSamplerInit or an already completed run",
            ),
        )
    end
    if sampler.internal_state == DynamicSamplerRunDone &&
        !_dynamic_adaptive_requested(adaptive_kwargs)
        return sampler
    elseif sampler.internal_state == DynamicSamplerRunDone &&
        isempty(sampler.saved_run[:logl])
        throw(
            ArgumentError(
                "cannot add dynamic batches before an initial baseline run exists"
            ),
        )
    end
    _ = checkpoint_every
    _ = resume

    nlive_i = isnothing(nlive_init) ? sampler.nlive0 : Int(nlive_init)
    nlive_i > 0 || throw(ArgumentError("nlive_init must be positive; got $nlive_i"))
    update_interval_i = _dynamic_update_interval(sampler, update_interval, nlive_i)
    first_update_d = if isnothing(first_update)
        sampler.first_bound_update
    else
        _check_first_update(first_update)
    end
    maxiter_i = _dynamic_effective_limit(maxiter_init, maxiter)
    maxcall_i = _dynamic_effective_limit(maxcall_init, maxcall)

    if sampler.internal_state == DynamicSamplerInit
        static_sampler = NestedSampler(
            sampler.loglikelihood,
            sampler.prior_transform,
            sampler.ndim;
            nlive=nlive_i,
            bound=sampler.bounding,
            sample=sampler.sampling,
            periodic=sampler.periodic,
            reflective=sampler.reflective,
            update_interval=update_interval_i,
            first_update=first_update_d,
            rng=sampler.rng,
            map_backend=sampler.map_backend,
            live_points,
            enlarge=sampler.bound_enlarge,
            bootstrap=sampler.bound_bootstrap,
            walks=sampler.walks,
            facc=sampler.facc,
            slices=sampler.slices,
            ncdim=sampler.ncdim,
            blob=sampler.blob,
            copy_inputs=sampler.copy_inputs,
        )
        sampler.sampler = static_sampler
        sampler.nlive_init = static_sampler.nlive
        sampler.live_init = _dynamic_live_snapshot(static_sampler)
        sampler.live_u = copy(static_sampler.live_u)
        sampler.live_v = copy(static_sampler.live_v)
        sampler.live_logl = copy(static_sampler.live_logl)
        sampler.live_blobs = static_sampler.blob ? copy(static_sampler.live_blobs) : nothing
        sampler.live_bound = copy(static_sampler.live_bound)
        sampler.live_it = copy(static_sampler.live_it)
        sampler.ncall = static_sampler.ncall
        sampler.bound_list = static_sampler.bound_list
        sampler.internal_state = DynamicSamplerLivePointsInit

        sampler.internal_state = DynamicSamplerInBase
        run_nested!(
            static_sampler;
            maxiter=maxiter_i,
            maxcall=maxcall_i,
            dlogz=dlogz_init,
            logl_max=logl_max_init,
            add_live,
            save_bounds,
            print_progress,
            print_func,
        )
        add_live && (sampler.internal_state = DynamicSamplerInBaseAddLive)

        static_results = results(static_sampler)
        samples_n = _static_samples_n(static_results)
        sampler.base_run = _dynamic_run_from_nested(
            static_sampler,
            samples_n;
            batch_id=0,
            batch_nlive=static_sampler.nlive,
            batch_logl_bounds=(-Inf, Inf),
        )
        sampler.saved_run = _dynamic_run_from_nested(
            static_sampler,
            samples_n;
            batch_id=0,
            batch_nlive=static_sampler.nlive,
            batch_logl_bounds=(-Inf, Inf),
        )
        sampler.batch = 0
        sampler.it = length(sampler.saved_run[:logl]) + 1
        sampler.ncall = static_sampler.ncall
        sampler.eff = static_sampler.eff
        sampler.bound_list = static_sampler.bound_list
        sampler.live_u = copy(static_sampler.live_u)
        sampler.live_v = copy(static_sampler.live_v)
        sampler.live_logl = copy(static_sampler.live_logl)
        sampler.live_blobs = static_sampler.blob ? copy(static_sampler.live_blobs) : nothing
        sampler.live_bound = copy(static_sampler.live_bound)
        sampler.live_it = copy(static_sampler.live_it)
    end

    run_batches = _dynamic_adaptive_requested(adaptive_kwargs)
    maxbatch_i = isnothing(maxbatch) ? (run_batches ? typemax(Int) : 0) : Int(maxbatch)
    maxiter_total = _dynamic_limit_value(maxiter)
    maxcall_total = _dynamic_limit_value(maxcall)
    maxiter_batch_i = _dynamic_limit_value(maxiter_batch)
    maxcall_batch_i = _dynamic_limit_value(maxcall_batch)
    nlive_batch_i = isnothing(nlive_batch) ? sampler.nlive0 : Int(nlive_batch)
    wt = isnothing(wt_function) ? weight_function : wt_function
    stop = isnothing(stop_function) ? stopping_function : stop_function
    stop_args = _dynamic_kwargs_dict(stop_kwargs)
    if isnothing(stop_function) && !haskey(stop_args, :target_n_effective)
        stop_args[:target_n_effective] =
            isnothing(n_effective) ? max(sampler.ndim^2, 10_000) : n_effective
    end
    wt_args = isnothing(wt_kwargs) ? nothing : wt_kwargs

    while sampler.batch < maxbatch_i
        remaining_iter = _dynamic_remaining_limit(maxiter_total, sampler.it - 1)
        remaining_call = _dynamic_remaining_limit(maxcall_total, sampler.ncall)
        batch_iter = min(remaining_iter, maxiter_batch_i)
        batch_call = min(remaining_call, maxcall_batch_i)
        (batch_iter > 0 && batch_call > 0) || break
        if use_stop
            should_stop = stop(results(sampler), stop_args; rng=sampler.rng)
            should_stop && break
        end
        add_batch!(
            sampler;
            nlive=nlive_batch_i,
            update_interval,
            mode=:weight,
            wt_function=wt,
            wt_kwargs=wt_args,
            maxiter=batch_iter,
            maxcall=batch_call,
            save_bounds,
            print_progress,
            print_func,
        )
    end

    sampler.internal_state = DynamicSamplerRunDone
    !isnothing(checkpoint_file) && checkpoint!(sampler, checkpoint_file)
    return sampler
end

run_nested(sampler::DynamicSampler; kwargs...) = run_nested!(sampler; kwargs...)

function results(sampler::DynamicSampler)
    record = sampler.saved_run
    samples_u = _matrix_from_record(record, :u, sampler.ndim)
    samples_v = _matrix_from_record(record, :v, sampler.ndim)
    logzvar = Float64.(record[:logzvar])
    data = Any[
        :niter => max(sampler.it - 1, 0),
        :ncall => Int.(record[:nc]),
        :eff => sampler.eff,
        :samples => samples_v,
        :samples_u => samples_u,
        :samples_id => Int.(record[:id]),
        :samples_it => Int.(record[:it]),
        :samples_n => Int.(record[:n]),
        :samples_batch => Int.(record[:batch]),
        :logl => Float64.(record[:logl]),
        :logvol => Float64.(record[:logvol]),
        :logwt => Float64.(record[:logwt]),
        :logz => Float64.(record[:logz]),
        :logzvar => logzvar,
        :logzerr => sqrt.(max.(logzvar, 0.0)),
        :h => Float64.(record[:h]),
        :information => Float64.(record[:h]),
        :batch_nlive => Int.(record[:batch_nlive]),
        :batch_logl_bounds => _dynamic_batch_bounds_matrix(record[:batch_logl_bounds]),
        :proposal_stats => copy(record[:proposal_stats]),
    ]
    sampler.blob && push!(data, :blobs => copy(record[:blobs]))
    if !isnothing(sampler.sampler) && sampler.sampler.save_bounds
        push!(data, :bound => deepcopy(sampler.bound_list))
        push!(data, :bound_iter => Int.(record[:bounditer]))
        push!(data, :boundidx => Int.(record[:boundidx]))
        push!(data, :scale => Float64.(record[:scale]))
    end
    return Results(data)
end

function n_effective(sampler::DynamicSampler)
    isempty(sampler.saved_run[:logwt]) && return 0.0
    logwt = Float64.(sampler.saved_run[:logwt])
    all(isinf, logwt) && return 0.0
    return get_neff_from_logwt(logwt)
end

function sampler_snapshot(sampler::DynamicSampler)
    return Dict{Symbol, Any}(
        :type => :DynamicSampler,
        :ndim => sampler.ndim,
        :ncdim => sampler.ncdim,
        :blob => sampler.blob,
        :copy_inputs => sampler.copy_inputs,
        :bounding => sampler.bounding,
        :sampling => sampler.sampling,
        :bound_update_interval_ratio => sampler.bound_update_interval_ratio,
        :first_bound_update => sampler.first_bound_update,
        :rng => sampler.rng,
        :map_backend_config => _backend_config(sampler.map_backend),
        :periodic => sampler.periodic,
        :reflective => sampler.reflective,
        :walks => sampler.walks,
        :slices => sampler.slices,
        :facc => sampler.facc,
        :nlive0 => sampler.nlive0,
        :bound_enlarge => sampler.bound_enlarge,
        :bound_bootstrap => sampler.bound_bootstrap,
        :sampler =>
            isnothing(sampler.sampler) ? nothing : sampler_snapshot(sampler.sampler),
        :saved_run => sampler.saved_run,
        :base_run => sampler.base_run,
        :new_run => sampler.new_run,
        :batch => sampler.batch,
        :it => sampler.it,
        :ncall => sampler.ncall,
        :eff => sampler.eff,
        :bound_list => sampler.bound_list,
        :internal_state => sampler.internal_state,
        :live_u => sampler.live_u,
        :live_v => sampler.live_v,
        :live_logl => sampler.live_logl,
        :live_blobs => sampler.live_blobs,
        :live_bound => sampler.live_bound,
        :live_it => sampler.live_it,
        :live_init => sampler.live_init,
        :nlive_init => sampler.nlive_init,
        :batch_sampler => sampler.batch_sampler,
        :new_logl_min => sampler.new_logl_min,
        :new_logl_max => sampler.new_logl_max,
    )
end

function _restore_dynamic_sampler(state::AbstractDict, loglikelihood, prior_transform)
    sampler = DynamicSampler(
        loglikelihood,
        prior_transform,
        Int(state[:ndim]);
        nlive=Int(state[:nlive0]),
        bound=state[:bounding],
        sample=state[:sampling],
        periodic=state[:periodic],
        reflective=state[:reflective],
        bound_update_interval_ratio=Float64(state[:bound_update_interval_ratio]),
        first_update=state[:first_bound_update],
        rng=state[:rng],
        map_backend=_map_backend_from_config(get(state, :map_backend_config, nothing)),
        enlarge=state[:bound_enlarge],
        bootstrap=state[:bound_bootstrap],
        walks=state[:walks],
        facc=Float64(state[:facc]),
        slices=state[:slices],
        ncdim=Int(state[:ncdim]),
        blob=Bool(state[:blob]),
        copy_inputs=Bool(state[:copy_inputs]),
    )
    sampler.sampler = if isnothing(state[:sampler])
        nothing
    else
        _restore_nested_sampler(state[:sampler], loglikelihood, prior_transform)
    end
    sampler.saved_run = state[:saved_run]
    sampler.base_run = state[:base_run]
    sampler.new_run = state[:new_run]
    sampler.batch = Int(state[:batch])
    sampler.it = Int(state[:it])
    sampler.ncall = Int(state[:ncall])
    sampler.eff = Float64(state[:eff])
    sampler.bound_list = Vector{Any}(state[:bound_list])
    sampler.internal_state = state[:internal_state]
    sampler.live_u = state[:live_u]
    sampler.live_v = state[:live_v]
    sampler.live_logl = state[:live_logl]
    sampler.live_blobs = state[:live_blobs]
    sampler.live_bound = state[:live_bound]
    sampler.live_it = state[:live_it]
    sampler.live_init = state[:live_init]
    sampler.nlive_init = state[:nlive_init]
    sampler.batch_sampler = state[:batch_sampler]
    sampler.new_logl_min = Float64(state[:new_logl_min])
    sampler.new_logl_max = Float64(state[:new_logl_max])
    return sampler
end
