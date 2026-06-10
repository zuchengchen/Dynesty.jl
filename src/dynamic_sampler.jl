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
