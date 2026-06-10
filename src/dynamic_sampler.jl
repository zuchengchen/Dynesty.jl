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
