using LinearAlgebra
using Printf
using Random
using SpecialFunctions
using Statistics

const SQRTEPS = sqrt(eps(Float64))

"""
    DelayTimer(delay; now=time())

Small wall-clock timer used to decide whether a delayed action, such as a
checkpoint or progress update, should run.
"""
mutable struct DelayTimer
    delay::Float64
    last_time::Float64
end

function DelayTimer(delay::Real; now::Real=time())
    delay >= 0 || throw(ArgumentError("delay must be nonnegative; got $delay"))
    return DelayTimer(Float64(delay), Float64(now))
end

function is_time!(timer::DelayTimer; now::Real=time())
    current = Float64(now)
    if current - timer.last_time > timer.delay
        timer.last_time = current
        return true
    end
    return false
end

is_time(timer::DelayTimer; now::Real=time()) = is_time!(timer; now)

struct PrintFnArgs
    niter::Int
    short_str::Vector{String}
    mid_str::Vector{String}
    long_str::Vector{String}
end

function _progress_get(record, key::Symbol)
    if record isa AbstractDict
        haskey(record, key) && return record[key]
        haskey(record, String(key)) && return record[String(key)]
    end
    return getproperty(record, key)
end

function _finite_or(value::Real, threshold::Real, replacement::Real, cmp)
    vf = Float64(value)
    return cmp(vf, Float64(threshold)) ? Float64(replacement) : vf
end

"""
    get_print_fn_args(itresult, niter, ncall; ...)

Build backend-neutral progress/status strings from a sampler iteration result.
The returned `PrintFnArgs` mirrors Python dynesty's short, medium, and long
status variants.
"""
function get_print_fn_args(
    itresult,
    niter::Integer,
    ncall::Integer;
    add_live_it=nothing,
    dlogz=nothing,
    stop_val=nothing,
    nbatch=nothing,
    logl_min::Real=(-Inf),
    logl_max::Real=Inf,
)
    loglstar_raw = Float64(_progress_get(itresult, :loglstar))
    logz_raw = Float64(_progress_get(itresult, :logz))
    delta_logz_raw = Float64(_progress_get(itresult, :delta_logz))
    logzvar = Float64(_progress_get(itresult, :logzvar))
    loglstar = _finite_or(loglstar_raw, -1.0e6, -Inf, <=)
    logz = _finite_or(logz_raw, -1.0e6, -Inf, <=)
    delta_logz = _finite_or(delta_logz_raw, 1.0e6, Inf, >)
    logzerr = 0.0 <= logzvar <= 1.0e6 ? sqrt(logzvar) : NaN

    long_str = String[]
    short_str = String[]
    if !isnothing(add_live_it)
        live = @sprintf("+%d", Int(add_live_it))
        push!(long_str, live)
        push!(short_str, live)
    end
    !isnothing(nbatch) && push!(long_str, @sprintf("batch: %d", Int(nbatch)))
    push!(long_str, @sprintf("bound: %d", Int(_progress_get(itresult, :bounditer))))
    push!(long_str, @sprintf("nc: %d", Int(_progress_get(itresult, :nc))))
    push!(long_str, @sprintf("ncall: %d", Int(ncall)))
    eff_str = @sprintf("eff(%%): %6.3f", Float64(_progress_get(itresult, :eff)))
    push!(long_str, eff_str)
    push!(short_str, eff_str)

    long_logl = if isfinite(logl_min)
        @sprintf("loglstar: %6.3f < %6.3f", Float64(logl_min), loglstar)
    else
        @sprintf("loglstar: %6.3f", loglstar)
    end
    short_logl = if isfinite(logl_min)
        @sprintf("logl*: %6.1f<%6.1f", Float64(logl_min), loglstar)
    else
        @sprintf("logl*: %6.1f", loglstar)
    end
    if isfinite(logl_max)
        long_logl *= @sprintf(" < %6.3f", Float64(logl_max))
        short_logl *= @sprintf("<%6.1f", Float64(logl_max))
    end
    push!(long_str, long_logl)
    push!(short_str, short_logl)

    long_logz = @sprintf("logz: %6.3f", logz)
    short_logz = @sprintf("logz: %6.1f", logz)
    if !isnan(logzerr)
        long_logz *= @sprintf(" +/- %6.3f", logzerr)
        short_logz *= @sprintf("+/-%.1f", logzerr)
    end
    push!(long_str, long_logz)
    push!(short_str, short_logz)

    show_dlogz =
        !isnothing(dlogz) && (isnothing(nbatch) || Int(nbatch) == 0 || isnothing(stop_val))
    if show_dlogz
        long_tail = @sprintf("dlogz: %6.3f > %6.3f", delta_logz, Float64(dlogz))
        mid_tail = @sprintf("dlogz: %6.1f>%6.1f", delta_logz, Float64(dlogz))
    else
        stop = isnothing(stop_val) ? NaN : Float64(stop_val)
        long_tail = @sprintf("stop: %6.3f", stop)
        mid_tail = @sprintf("stop: %6.3f", stop)
    end
    push!(long_str, long_tail)
    mid_str = vcat(short_str, [mid_tail])
    return PrintFnArgs(Int(niter), short_str, mid_str, long_str)
end

function _terminal_columns(io::IO)
    try
        return displaysize(io)[2]
    catch
        return 200
    end
end

"""
    print_fn_fallback(itresult, niter, ncall; io=stderr, columns=nothing, ...)

Write one progress/status line to `io` and return the emitted line.
"""
function print_fn_fallback(
    itresult, niter::Integer, ncall::Integer; io::IO=stderr, columns=nothing, kwargs...
)
    args = get_print_fn_args(itresult, niter, ncall; kwargs...)
    long_str = join(vcat([@sprintf("iter: %d", args.niter)], args.long_str), " | ")
    mid_str = join(args.mid_str, " | ")
    short_str = join(args.short_str, "|")
    width = isnothing(columns) ? _terminal_columns(io) : Int(columns)
    line = if width > length(long_str)
        long_str
    elseif width > length(mid_str)
        mid_str
    else
        short_str
    end
    print(io, "\r", line)
    return line
end

print_fn(itresult, niter::Integer, ncall::Integer; pbar=nothing, kwargs...) =
    print_fn_fallback(itresult, niter, ncall; kwargs...)

"""
    get_print_func(print_func=nothing, print_progress=true; io=stderr)

Return `(progress_backend, callback)` for sampler progress display. The backend
is currently `nothing`; tqdm-style progress bars are intentionally replaced by a
Julia IO callback.
"""
function get_print_func(
    print_func=nothing, print_progress::Bool=true; initial=0, io::IO=stderr
)
    _ = (print_progress, initial)
    callback = if isnothing(print_func)
        (itresult, niter, ncall; kwargs...) ->
            print_fn(itresult, niter, ncall; io=io, kwargs...)
    else
        print_func
    end
    return nothing, callback
end

"""
    LoglOutput(logl[, blob])
    LoglOutput(value, blob_flag::Bool)

Normalized likelihood output. A likelihood may return a real value, a
`(logl, blob)` tuple, or an existing `LoglOutput`.
"""
struct LoglOutput{B}
    logl::Float64
    blob::B
    has_blob::Bool
end

LoglOutput(logl::Real) = LoglOutput(Float64(logl), nothing, false)
LoglOutput(logl::Real, blob) = LoglOutput(Float64(logl), blob, true)
LoglOutput(value::LoglOutput) = value

LoglOutput(value::Real, blob_flag::Bool) =
    if blob_flag
        throw(ArgumentError("blob=true requires likelihood output `(logl, blob)`"))
    else
        LoglOutput(value)
    end

function LoglOutput(value, blob_flag::Bool)
    if blob_flag
        value isa Tuple ||
            throw(ArgumentError("blob=true requires likelihood output `(logl, blob)`"))
        length(value) == 2 ||
            throw(ArgumentError("blob output must contain exactly two values"))
        return LoglOutput(value[1], value[2])
    else
        return LoglOutput(value)
    end
end

function LoglOutput(value::Tuple)
    length(value) == 2 ||
        throw(ArgumentError("tuple likelihood output must be `(logl, blob)`"))
    return LoglOutput(value[1], value[2])
end

Base.Float64(value::LoglOutput) = value.logl
Base.float(value::LoglOutput) = value.logl
Base.isless(a::LoglOutput, b) = isless(a.logl, Float64(LoglOutput(b)))
Base.isless(a::Real, b::LoglOutput) = isless(Float64(a), b.logl)
Base.:(==)(a::LoglOutput, b) = a.logl == Float64(LoglOutput(b))
Base.:(==)(a::Real, b::LoglOutput) = Float64(a) == b.logl

function Base.getproperty(value::LoglOutput, name::Symbol)
    if name === :val
        return getfield(value, :logl)
    else
        return getfield(value, name)
    end
end

"""
    EvaluationHistoryItem(u, v, logl)

Record used by `LogLikelihood` to buffer evaluation history before optional
HDF5 extension flushing.
"""
struct EvaluationHistoryItem
    u::Vector{Float64}
    v::Vector{Float64}
    logl::Float64
end

"""
    LogLikelihood(f, ndim; blob=false, copy_inputs=false, ...)

Callable wrapper around a user likelihood. By default inputs are passed through
without copying for Julia performance. Set `copy_inputs=true` for Python-like
defensive input copying.
"""
mutable struct LogLikelihood{F}
    f::F
    ndim::Int
    blob::Bool
    copy_inputs::Bool
    history_filename::Union{Nothing, String}
    save_evaluation_history::Bool
    save_every::Int
    evaluation_history::Vector{EvaluationHistoryItem}
    evaluation_history_counter::Int
    failed_save::Bool
end

function LogLikelihood(
    f,
    ndim::Integer;
    blob::Bool=false,
    copy_inputs::Bool=false,
    history_filename::Union{Nothing, AbstractString}=nothing,
    save_evaluation_history::Bool=false,
    save_every::Integer=10_000,
)
    ndim > 0 || throw(ArgumentError("ndim must be positive; got $ndim"))
    save_every > 0 || throw(ArgumentError("save_every must be positive; got $save_every"))
    ll = LogLikelihood(
        f,
        Int(ndim),
        blob,
        copy_inputs,
        isnothing(history_filename) ? nothing : String(history_filename),
        save_evaluation_history,
        Int(save_every),
        EvaluationHistoryItem[],
        0,
        false,
    )
    if save_evaluation_history
        history_init!(ll)
    end
    return ll
end

function (ll::LogLikelihood)(x)
    input = ll.copy_inputs ? copy(x) : x
    return LoglOutput(ll.f(input), ll.blob)
end

function history_init!(ll::LogLikelihood)
    throw(ArgumentError("evaluation history HDF5 support requires loading HDF5.jl"))
end

function history_save!(ll::LogLikelihood)
    ll.save_evaluation_history || return ll
    throw(ArgumentError("evaluation history HDF5 support requires loading HDF5.jl"))
end

function append_evaluation_history!(
    ll::LogLikelihood, items::AbstractVector{EvaluationHistoryItem}
)
    ll.save_evaluation_history || return ll
    append!(ll.evaluation_history, items)
    if length(ll.evaluation_history) > ll.save_every
        history_save!(ll)
    end
    return ll
end

function finalize_history!(ll::LogLikelihood)
    if ll.save_evaluation_history && !isempty(ll.evaluation_history)
        history_save!(ll)
    end
    return ll
end

const RUN_RECORD_KEYS = (
    :id,
    :u,
    :v,
    :logl,
    :logvol,
    :logwt,
    :logz,
    :logzvar,
    :h,
    :nc,
    :boundidx,
    :it,
    :n,
    :bounditer,
    :scale,
    :blobs,
    :proposal_stats,
)

const DYNAMIC_RUN_RECORD_KEYS = (:batch, :batch_nlive, :batch_logl_bounds)

"""
    RunRecord(; dynamic=false)

Dictionary-like accumulator for nested-sampling run records.
"""
mutable struct RunRecord
    data::Dict{Symbol, Vector{Any}}
    dynamic::Bool
end

function RunRecord(; dynamic::Bool=false)
    keys = dynamic ? (RUN_RECORD_KEYS..., DYNAMIC_RUN_RECORD_KEYS...) : RUN_RECORD_KEYS
    return RunRecord(Dict(key => Any[] for key in keys), dynamic)
end

function Base.getindex(record::RunRecord, key::Symbol)
    return record.data[key]
end

function Base.setindex!(record::RunRecord, value, key::Symbol)
    record.data[key] = value
    return record
end

Base.keys(record::RunRecord) = keys(record.data)

function Base.append!(record::RunRecord, values::AbstractDict)
    for (key, value) in values
        haskey(record.data, key) || throw(
            KeyError(
                "RunRecord has no key $(repr(key)); available keys are $(collect(keys(record.data)))",
            ),
        )
        push!(record.data[key], value)
    end
    return record
end

logaddexp(a::Real, b::Real) = max(a, b) + log(exp(a - max(a, b)) + exp(b - max(a, b)))

function logaddexp_accumulate(values::AbstractVector{<:Real})
    out = Vector{Float64}(undef, length(values))
    isempty(values) && return out
    out[1] = Float64(values[1])
    for i in 2:length(values)
        out[i] = logaddexp(out[i - 1], values[i])
    end
    return out
end

"""
    get_neff_from_logwt(logwt)

Kish effective sample size for unnormalized log weights.
"""
function get_neff_from_logwt(logwt::AbstractVector{<:Real})
    isempty(logwt) && throw(ArgumentError("logwt must contain at least one value"))
    maxlogwt = maximum(logwt)
    weights = exp.(Float64.(logwt) .- maxlogwt)
    return sum(weights)^2 / sum(abs2, weights)
end

function _mask_from_dimension_indices(indices, ndim::Int, name::Symbol)
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

"""
    get_nonbounded(ndim, periodic, reflective)

Return a boolean mask where ordinary dimensions are `true` and periodic or
reflective dimensions are `false`. Indices are 1-based; use
`from_python_indices` to convert Python dynesty index lists explicitly.
"""
function get_nonbounded(ndim::Integer, periodic=nothing, reflective=nothing)
    ndim_i = Int(ndim)
    ndim_i > 0 || throw(ArgumentError("ndim must be positive; got $ndim"))
    periodic_mask = _mask_from_dimension_indices(periodic, ndim_i, :periodic)
    reflective_mask = _mask_from_dimension_indices(reflective, ndim_i, :reflective)
    if !isnothing(periodic_mask) &&
        !isnothing(reflective_mask) &&
        any(periodic_mask .& reflective_mask)
        throw(ArgumentError("a dimension cannot be both periodic and reflective"))
    end
    isnothing(periodic_mask) && isnothing(reflective_mask) && return nothing
    nonbounded = trues(ndim_i)
    !isnothing(periodic_mask) && (nonbounded[periodic_mask] .= false)
    !isnothing(reflective_mask) && (nonbounded[reflective_mask] .= false)
    return nonbounded
end

"""
    get_random_generator(seed=nothing)

Return a Julia random generator. Existing `AbstractRNG` objects are returned
unchanged; integer seeds create a `MersenneTwister`; `nothing` returns
`Random.default_rng()`.
"""
function get_random_generator(seed=nothing)
    isnothing(seed) && return Random.default_rng()
    seed isa AbstractRNG && return seed
    seed isa Integer && return MersenneTwister(Int(seed))
    throw(ArgumentError("seed must be nothing, an integer, or an AbstractRNG"))
end

"""
    unitcheck(u; nonbounded=nothing)

Check whether `u` is inside the open unit cube. When `nonbounded` is a boolean
mask, masked dimensions must lie in `(0, 1)` and unmasked dimensions may lie in
`(-0.5, 1.5)` for periodic/reflective proposal handling.
"""
function unitcheck(u::AbstractArray{<:Real}; nonbounded=nothing)
    values = vec(u)
    isempty(values) && throw(ArgumentError("u must contain at least one value"))
    if isnothing(nonbounded)
        return minimum(values) > 0 && maximum(values) < 1
    end
    mask = vec(Bool.(nonbounded))
    length(mask) == length(values) || throw(
        DimensionMismatch(
            "nonbounded mask length $(length(mask)) != u length $(length(values))"
        ),
    )
    strict_values = values[mask]
    loose_values = values[.!mask]
    strict_ok =
        isempty(strict_values) || (minimum(strict_values) > 0 && maximum(strict_values) < 1)
    loose_ok =
        isempty(loose_values) ||
        (minimum(loose_values) > -0.5 && maximum(loose_values) < 1.5)
    return strict_ok && loose_ok
end

"""
    apply_reflect!(u)
    apply_reflect(u)

Reflect values into `[0, 1]`. `apply_reflect!` mutates in place. The
compatibility spelling `apply_reflect` also mutates and returns `u`.
"""
function apply_reflect!(u::AbstractArray{<:Real})
    for index in eachindex(u)
        r2 = mod(Float64(u[index]), 2.0)
        u[index] =
            r2 < 1.0 ? mod(Float64(u[index]), 1.0) : 1.0 - mod(Float64(u[index]), 1.0)
    end
    return u
end

apply_reflect(u::AbstractArray{<:Real}) = apply_reflect!(u)

"""
    mean_and_cov(samples, weights)

Weighted mean and covariance for row-major public sample arrays with shape
`nsamples x ndim`.
"""
function mean_and_cov(samples::AbstractMatrix{<:Real}, weights::AbstractVector{<:Real})
    nsamples, ndim = size(samples)
    length(weights) == nsamples || throw(
        DimensionMismatch(
            "length(weights)=$(length(weights)) but samples has $nsamples rows"
        ),
    )
    nsamples > 1 || throw(ArgumentError("at least two samples are required"))
    w = Float64.(weights)
    x = Float64.(samples)
    wsum = sum(w)
    w2sum = sum(abs2, w)
    denom = wsum^2 - w2sum
    denom > 0 ||
        throw(ArgumentError("weights must include at least two nonzero effective samples"))
    mean = vec(sum(x .* w; dims=1)) ./ wsum
    cov = zeros(Float64, ndim, ndim)
    for i in 1:nsamples
        dx = @view x[i, :]
        cov .+= w[i] .* (dx .- mean) * transpose(dx .- mean)
    end
    cov .*= wsum / denom
    return mean, cov
end

function _normalize_weights(weights::AbstractVector{<:Real})
    isempty(weights) && throw(ArgumentError("weights must contain at least one value"))
    w = Float64.(weights)
    total = sum(w)
    isfinite(total) && total > 0 ||
        throw(ArgumentError("weights must have a positive finite sum"))
    if abs(total - 1.0) > SQRTEPS
        @warn "Weights do not sum to 1 and have been renormalized."
    end
    return w ./ total
end

"""
    resample_equal(samples, weights; rng=Random.default_rng())

Systematic resampling to produce equal-weight samples. Matrix inputs are treated
as public `nsamples x ndim` arrays and are resampled by row.
"""
function resample_equal(
    samples, weights::AbstractVector{<:Real}; rng::AbstractRNG=Random.default_rng()
)
    nsamples = length(weights)
    size(samples, 1) == nsamples || throw(
        DimensionMismatch(
            "samples first dimension $(size(samples, 1)) != length(weights) $nsamples"
        ),
    )
    w = _normalize_weights(weights)
    cumulative = cumsum(w)
    cumulative[end] = 1.0
    positions = (rand(rng) .+ collect(0:(nsamples - 1))) ./ nsamples
    indices = Vector{Int}(undef, nsamples)
    j = 1
    for i in 1:nsamples
        while positions[i] >= cumulative[j] && j < nsamples
            j += 1
        end
        indices[i] = j
    end
    indices = indices[randperm(rng, nsamples)]
    if samples isa AbstractMatrix
        return samples[indices, :]
    else
        return samples[indices]
    end
end

function _interp_sorted(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, xi::Real)
    xi <= x[1] && return Float64(y[1])
    xi >= x[end] && return Float64(y[end])
    hi = searchsortedfirst(x, xi)
    lo = hi - 1
    t = (Float64(xi) - Float64(x[lo])) / (Float64(x[hi]) - Float64(x[lo]))
    return (1 - t) * Float64(y[lo]) + t * Float64(y[hi])
end

"""
    quantile(x, q; weights=nothing)

Compute unweighted or weighted quantiles using the Python dynesty convention.
"""
function quantile(x::AbstractVector{<:Real}, q; weights=nothing)
    isempty(x) && throw(ArgumentError("x must contain at least one value"))
    qs = q isa Number ? [Float64(q)] : Float64.(collect(q))
    all(0 .<= qs .<= 1) || throw(ArgumentError("quantiles must be between 0 and 1"))
    if isnothing(weights)
        sx = sort(Float64.(x))
        n = length(sx)
        vals = [_interp_sorted(collect(range(0.0, 1.0; length=n)), sx, qi) for qi in qs]
    else
        w = Float64.(weights)
        length(w) == length(x) || throw(
            DimensionMismatch("length(weights)=$(length(w)) != length(x)=$(length(x))")
        )
        order = sortperm(x)
        sx = Float64.(x[order])
        sw = w[order]
        if length(sx) == 1
            vals = fill(sx[1], length(qs))
        else
            cdf = cumsum(sw)[1:(end - 1)]
            total = cdf[end]
            total > 0 || throw(ArgumentError("weights must have a positive partial CDF"))
            cdf ./= total
            cdf = vcat(0.0, cdf)
            vals = [_interp_sorted(cdf, sx, qi) for qi in qs]
        end
    end
    return q isa Number ? vals[1] : vals
end

"""
    logvol_prefactor(n, p=2)

Logarithm of the volume constant for an `n`-dimensional L^p sphere.
"""
function logvol_prefactor(n::Integer, p::Real=2.0)
    n > 0 || throw(ArgumentError("n must be positive; got $n"))
    p > 0 || throw(ArgumentError("p must be positive; got $p"))
    pf = Float64(p)
    return n * log(2.0) + n * loggamma(1.0 / pf + 1.0) - loggamma(n / pf + 1.0)
end

function _diff_prepend_zero(values::AbstractVector{<:Real})
    out = Vector{Float64}(undef, length(values))
    isempty(values) && return out
    out[1] = Float64(values[1])
    for i in 2:length(values)
        out[i] = Float64(values[i]) - Float64(values[i - 1])
    end
    return out
end

"""
    compute_integrals(; logl, logvol, reweight=nothing)

Quadratic nested-sampling evidence estimator. Returns a named tuple with
`logwt`, `logz`, `logzvar`, and `h`.
"""
function compute_integrals(;
    logl::AbstractVector{<:Real}, logvol::AbstractVector{<:Real}, reweight=nothing
)
    length(logl) == length(logvol) || throw(
        DimensionMismatch(
            "length(logl)=$(length(logl)) != length(logvol)=$(length(logvol))"
        ),
    )
    n = length(logl)
    n > 0 || throw(ArgumentError("logl/logvol must contain at least one value"))
    logl_f = Float64.(logl)
    logvol_f = Float64.(logvol)
    loglstar_pad = vcat(-1.0e300, logl_f)
    dlogvol_raw = _diff_prepend_zero(logvol_f)
    logdvol = logvol_f .- dlogvol_raw .+ log1p.(-exp.(dlogvol_raw))
    logdvol2 = logdvol .+ log(0.5)
    dlogvol = .-dlogvol_raw
    logwt = [logaddexp(loglstar_pad[i + 1], loglstar_pad[i]) + logdvol2[i] for i in 1:n]
    if !isnothing(reweight)
        length(reweight) == n || throw(
            DimensionMismatch("length(reweight)=$(length(reweight)) != length(logl)=$n")
        )
        logwt .+= Float64.(reweight)
    end
    logz = logaddexp_accumulate(logwt)
    logzmax = logz[end]
    h_part1 = cumsum(
        exp.(loglstar_pad[2:end] .- logzmax .+ logdvol2) .* loglstar_pad[2:end] .+
        exp.(loglstar_pad[1:(end - 1)] .- logzmax .+ logdvol2) .* loglstar_pad[1:(end - 1)],
    )
    h = h_part1 .- logzmax .* exp.(logz .- logzmax)
    dh = _diff_prepend_zero(h)
    logzvar = abs.(cumsum(dh .* dlogvol))
    return (; logwt, logz, logzvar, h)
end

"""
    progress_integration(loglstar, loglstar_new, logz, logzvar, logvol, dlogvol, h)

One-step nested-sampling evidence update.
"""
function progress_integration(
    loglstar::Real,
    loglstar_new::Real,
    logz::Real,
    logzvar::Real,
    logvol::Real,
    dlogvol::Real,
    h::Real,
)
    delta = 0.5 * (exp(Float64(logvol) + Float64(dlogvol)) - exp(Float64(logvol)))
    logdvol = delta > 0 ? log(delta) : NaN
    logwt = logaddexp(loglstar_new, loglstar) + logdvol
    logz_new = logaddexp(logz, logwt)
    lzterm =
        exp(loglstar - logz_new + logdvol) * loglstar +
        exp(loglstar_new - logz_new + logdvol) * loglstar_new
    h_new = lzterm + exp(logz - logz_new) * (h + logz) - logz_new
    dh = h_new - h
    logzvar_new = logzvar + dh * dlogvol
    return (; logwt, logz=logz_new, logzvar=logzvar_new, h=h_new)
end

"""
    from_python_indices(indices; ndim)

Explicitly convert Python 0-based dimension indices to Julia 1-based indices.
"""
function from_python_indices(indices; ndim::Integer)
    ndim > 0 || throw(ArgumentError("ndim must be positive; got $ndim"))
    convert_one(i) = begin
        ii = Int(i)
        0 <= ii < ndim ||
            throw(BoundsError("Python index $ii is outside valid range 0:$(ndim - 1)"))
        ii + 1
    end
    if indices isa Integer
        return convert_one(indices)
    else
        return [convert_one(i) for i in indices]
    end
end
