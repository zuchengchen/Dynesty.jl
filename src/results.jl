using Random

const RESULTS_ALLOWED_KEYS = Set{Symbol}((
    :samples,
    :samples_u,
    :samples_id,
    :samples_it,
    :samples_n,
    :samples_batch,
    :live_points,
    :live_u,
    :live_v,
    :live_logl,
    :logl,
    :logvol,
    :logwt,
    :logz,
    :logzerr,
    :logzvar,
    :h,
    :nlive,
    :niter,
    :ncall,
    :eff,
    :information,
    :bound,
    :bound_iter,
    :samples_bound,
    :boundidx,
    :scale,
    :proposal_stats,
    :parallel_stats,
    :blobs,
    :batch,
    :batch_nlive,
    :batch_logl_bounds,
))

"""
    Results(pairs_or_dict)
    Results(; kwargs...)

Immutable user-facing results container. Public arrays follow Python dynesty's
shape convention: `samples`, `samples_u`, `live_u`, and `live_v` are
`nsamples x ndim`/`nlive x ndim`.
"""
struct Results
    data::Dict{Symbol, Any}
    order::Vector{Symbol}
    dynamic::Bool
end

Results(; kwargs...) = Results(Dict{Symbol, Any}(kwargs))

function _result_key_alias(key::Symbol)
    key === :blob && return :blobs
    key === :samples_bound && return :boundidx
    key === :batch && return :samples_batch
    return key
end

function Results(key_values)
    pairs_iter = key_values isa AbstractDict ? pairs(key_values) : key_values
    data = Dict{Symbol, Any}()
    order = Symbol[]
    for (raw_key, value) in pairs_iter
        key = _result_key_alias(Symbol(raw_key))
        key in RESULTS_ALLOWED_KEYS ||
            throw(ArgumentError("unknown Results key $(repr(key))"))
        haskey(data, key) && throw(ArgumentError("duplicate Results key $(repr(key))"))
        data[key] = _result_copy(value)
        push!(order, key)
    end
    for required in (:samples_u, :samples_id, :logl, :samples)
        haskey(data, required) ||
            throw(ArgumentError("Results key $(repr(required)) must be provided"))
    end
    if !haskey(data, :proposal_stats)
        data[:proposal_stats] = nothing
        push!(order, :proposal_stats)
    end
    dynamic = if haskey(data, :nlive)
        false
    elseif haskey(data, :samples_n)
        true
    else
        throw(ArgumentError("Results requires either :nlive or :samples_n"))
    end
    return Results(data, order, dynamic)
end

function Base.getproperty(res::Results, name::Symbol)
    if name in (:data, :order, :dynamic)
        return getfield(res, name)
    elseif haskey(getfield(res, :data), name)
        return getfield(res, :data)[name]
    elseif name === :blob && haskey(getfield(res, :data), :blobs)
        return getfield(res, :data)[:blobs]
    elseif name === :samples_bound && haskey(getfield(res, :data), :boundidx)
        return getfield(res, :data)[:boundidx]
    elseif name === :batch && haskey(getfield(res, :data), :samples_batch)
        return getfield(res, :data)[:samples_batch]
    else
        return getfield(res, name)
    end
end

function Base.getindex(res::Results, key::Symbol)
    key = _result_key_alias(key)
    haskey(res.data, key) || throw(KeyError(key))
    return res.data[key]
end

Base.getindex(res::Results, key::AbstractString) = getindex(res, Symbol(key))
Base.haskey(res::Results, key::Symbol) = haskey(res.data, _result_key_alias(key))
Base.haskey(res::Results, key::AbstractString) = haskey(res, Symbol(key))
Base.keys(res::Results) = copy(res.order)
Base.pairs(res::Results) = ((key, res.data[key]) for key in res.order)

_result_copy(value) = value
_result_copy(value::AbstractArray) = copy(value)
_result_copy(value::AbstractDict) = copy(value)

function asdict(res::Results)
    return Dict(key => _result_copy(res.data[key]) for key in res.order)
end

isdynamic(res::Results) = res.dynamic

function Base.show(io::IO, res::Results)
    print(io, "Results(")
    print(io, join(string.(res.order), ", "))
    print(io, ")")
end

function importance_weights(res::Results)
    haskey(res, :logwt) || throw(KeyError(:logwt))
    haskey(res, :logz) || throw(KeyError(:logz))
    logwt = Float64.(res[:logwt]) .- Float64(last(res[:logz]))
    weights = exp.(logwt)
    return weights ./ sum(weights)
end

function samples_equal(res::Results; rng::AbstractRNG=Random.default_rng())
    return resample_equal(res[:samples], importance_weights(res); rng)
end

function results_substitute(res::Results, replacements::AbstractDict)
    data = asdict(res)
    for (raw_key, value) in replacements
        key = _result_key_alias(Symbol(raw_key))
        haskey(data, key) && (data[key] = value)
    end
    return Results([(key, data[key]) for key in res.order])
end

function _get_nsamps_samples_n(res::Results)
    if isdynamic(res)
        samples_n = Int.(res.samples_n)
        return length(samples_n), samples_n
    end
    niter = Int(res.niter)
    nlive = Int(res.nlive)
    nsamps = length(res.logvol)
    if nsamps == niter
        samples_n = fill(nlive, niter)
    elseif nsamps == niter + nlive
        samples_n = min.(collect(nsamps:-1:1), nlive)
    else
        throw(
            ArgumentError(
                "final number of samples differs from niter and nlive: nsamps=$nsamps niter=$niter nlive=$nlive",
            ),
        )
    end
    return nsamps, samples_n
end

function _find_decrease(samples_n::AbstractVector{<:Integer})
    nsamps = length(samples_n)
    nlive_flag = falses(nsamps)
    nsamps > 1 && (nlive_flag[2:end] .= diff(samples_n) .< 0)
    nlive_start = Int[]
    bounds = Vector{Tuple{Int, Int}}()
    ids = findall(nlive_flag)
    if !isempty(ids)
        boundl = ids[1] - 1
        last = ids[1]
        push!(nlive_start, Int(samples_n[boundl]))
        for curi in ids[2:end]
            if curi == last + 1
                last += 1
            else
                push!(bounds, (boundl, last + 1))
                push!(nlive_start, Int(samples_n[curi - 1]))
                last = curi
                boundl = curi - 1
            end
        end
        push!(bounds, (boundl, last + 1))
    end
    return .!nlive_flag, nlive_start, bounds
end

function _replace_integrals(res::Results, logvol, logwt, logz, logzvar, h)
    replacements = Dict{Symbol, Any}(
        :logvol => Float64.(logvol),
        :logwt => Float64.(logwt),
        :logz => Float64.(logz),
        :logzerr => sqrt.(max.(Float64.(logzvar), 0.0)),
        :h => Float64.(h),
    )
    for key in collect(keys(replacements))
        if !haskey(res, key)
            pop!(replacements, key, nothing)
        end
    end
    return results_substitute(res, replacements)
end

function jitter_run(
    res::Results; rng::AbstractRNG=Random.default_rng(), rstate=nothing, approx::Bool=false
)
    rng_eff = isnothing(rstate) ? rng : rstate
    nsamps, samples_n = _get_nsamps_samples_n(res)
    nlive_flag, nlive_start, bounds = if approx
        trues(nsamps), Int[], Tuple{Int, Int}[]
    else
        _find_decrease(samples_n)
    end
    t_arr = zeros(Float64, nsamps)
    for i in 1:nsamps
        if nlive_flag[i]
            t_arr[i] = rand(rng_eff)^(1.0 / samples_n[i])
        end
    end
    for (nstart, bound) in zip(nlive_start, bounds)
        lo, hi_excl = bound
        sn = samples_n[lo:(hi_excl - 1)]
        y_arr = -log.(rand(rng_eff, nstart + 1))
        ycsum = cumsum(y_arr)
        ycsum ./= ycsum[end]
        uorder = ycsum[vcat(nstart + 1, sn)]
        rorder = uorder[2:end] ./ uorder[1:(end - 1)]
        t_arr[lo:(hi_excl - 1)] .= rorder
    end
    logvol = cumsum(log.(t_arr))
    ints = compute_integrals(; logl=Float64.(res.logl), logvol=logvol)
    return _replace_integrals(res, logvol, ints.logwt, ints.logz, ints.logzvar, ints.h)
end

function _select_rows(value, idxs::AbstractVector{<:Integer})
    value isa AbstractMatrix && return value[idxs, :]
    value isa AbstractVector && return value[idxs]
    return value
end

function _result_optional_vector(res::Results, key::Symbol, n::Int, default)
    haskey(res, key) && return res[key]
    return fill(default, n)
end

function _static_samples_n(res::Results)
    return _get_nsamps_samples_n(res)[2]
end

function _batch_info(res::Results, samples_n)
    n = length(samples_n)
    samples_batch = if haskey(res, :samples_batch)
        Int.(res.samples_batch)
    else
        zeros(Int, n)
    end
    batch_logl_bounds = if haskey(res, :batch_logl_bounds)
        Matrix{Float64}(res.batch_logl_bounds)
    else
        reshape([-Inf, Inf], 1, 2)
    end
    return samples_batch, batch_logl_bounds
end

function resample_run(
    res::Results;
    rng::AbstractRNG=Random.default_rng(),
    rstate=nothing,
    return_idx::Bool=false,
)
    rng_eff = isnothing(rstate) ? rng : rstate
    nsamps = length(res.ncall)
    samples_n = _get_nsamps_samples_n(res)[2]
    added_final_live = isdynamic(res) ? true : nsamps == Int(res.niter) + Int(res.nlive)
    samples_batch, batch_logl_bounds = _batch_info(res, samples_n)
    batch_llmin = batch_logl_bounds[:, 1]
    ids = sort(unique(Int.(res.samples_id)))

    base_ids = Int[]
    addon_ids = Int[]
    for id in ids
        sbatch = samples_batch[Int.(res.samples_id) .== id]
        if any(batch_llmin[sbatch .+ 1] .== -Inf)
            push!(base_ids, id)
        else
            push!(addon_ids, id)
        end
    end
    live_idx = Int[]
    if !isempty(base_ids) && !isempty(addon_ids)
        append!(live_idx, base_ids[rand(rng_eff, 1:length(base_ids), length(base_ids))])
        append!(live_idx, addon_ids[rand(rng_eff, 1:length(addon_ids), length(addon_ids))])
    elseif !isempty(base_ids)
        append!(live_idx, base_ids[rand(rng_eff, 1:length(base_ids), length(base_ids))])
    elseif !isempty(addon_ids)
        throw(
            ArgumentError(
                "Results does not include any points initially sampled from the prior"
            ),
        )
    else
        throw(ArgumentError("Results does not appear to have any particles"))
    end

    all_idxs = collect(1:nsamps)
    samp_idx = reduce(vcat, (all_idxs[Int.(res.samples_id) .== id] for id in live_idx))
    sort_order = sortperm(Float64.(res.logl[samp_idx]))
    samp_idx = samp_idx[sort_order]
    logl = Float64.(res.logl[samp_idx])
    nsamps_new = length(samp_idx)
    if added_final_live
        samp_n = zeros(Int, nsamps_new)
        for uidx in unique(live_idx)
            uidx_n = count(==(uidx), live_idx)
            sel = Int.(res.samples_id) .== uidx
            sbatch = samples_batch[sel][1]
            lower = batch_llmin[sbatch + 1]
            upper = maximum(Float64.(res.logl[sel]))
            samp_n[(logl .> lower) .& (logl .< upper)] .+= uidx_n
            endsel = logl .== upper
            endsel_n = count(endsel)
            if endsel_n > 0
                chunk = endsel_n / uidx_n
                counters = floor.(Int, collect(0:(endsel_n - 1)) ./ chunk)
                samp_n[endsel] .+= reverse(counters) .+ 1
            end
        end
    else
        samp_n = samples_n[samp_idx]
    end
    logvol = cumsum(log.(samp_n ./ (samp_n .+ 1.0)))
    ints = compute_integrals(; logl=logl, logvol=logvol)
    ncall = Int.(res.ncall[samp_idx])
    data = Dict{Symbol, Any}(
        :niter => length(ncall),
        :ncall => ncall,
        :eff => 100.0 * length(ncall) / sum(ncall),
        :samples => _select_rows(res.samples, samp_idx),
        :samples_u => _select_rows(res.samples_u, samp_idx),
        :samples_id => Int.(res.samples_id[samp_idx]),
        :samples_it => if haskey(res, :samples_it)
            Int.(res.samples_it[samp_idx])
        else
            collect(1:length(ncall))
        end,
        :samples_n => samp_n,
        :logwt => ints.logwt,
        :logl => logl,
        :logvol => logvol,
        :logz => ints.logz,
        :logzerr => sqrt.(max.(ints.logzvar, 0.0)),
        :h => ints.h,
        :information => ints.h,
        :proposal_stats => _select_rows(
            _result_optional_vector(res, :proposal_stats, nsamps, nothing), samp_idx
        ),
    )
    haskey(res, :blobs) && (data[:blobs] = _select_rows(res.blobs, samp_idx))
    new_res = Results(data)
    return return_idx ? (new_res, samp_idx) : new_res
end

function reweight_run(res::Results, logp_new, logp_old=nothing)
    logp_new_v = Float64.(logp_new)
    logp_old_v = isnothing(logp_old) ? Float64.(res.logl) : Float64.(logp_old)
    length(logp_new_v) == length(res.logl) ||
        throw(DimensionMismatch("length(logp_new) must match number of samples"))
    length(logp_old_v) == length(res.logl) ||
        throw(DimensionMismatch("length(logp_old) must match number of samples"))
    ints = compute_integrals(;
        logl=Float64.(res.logl),
        logvol=Float64.(res.logvol),
        reweight=logp_new_v .- logp_old_v,
    )
    return _replace_integrals(res, res.logvol, ints.logwt, ints.logz, ints.logzvar, ints.h)
end

function _result_slice_dict(res::Results, idxs)
    n = length(res.logl)
    data = Dict{Symbol, Any}(
        :ncall => Int.(res.ncall[idxs]),
        :eff => 100.0 * length(idxs) / sum(Int.(res.ncall[idxs])),
        :samples => _select_rows(res.samples, idxs),
        :samples_u => _select_rows(res.samples_u, idxs),
        :samples_id => Int.(res.samples_id[idxs]),
        :samples_it =>
            haskey(res, :samples_it) ? Int.(res.samples_it[idxs]) : collect(1:length(idxs)),
        :proposal_stats =>
            _select_rows(_result_optional_vector(res, :proposal_stats, n, nothing), idxs),
    )
    haskey(res, :blobs) && (data[:blobs] = _select_rows(res.blobs, idxs))
    return data
end

function unravel_run(res::Results; print_progress::Bool=false)
    ids = Int.(res.samples_id)
    added_live = haskey(res, :nlive) && length(ids) == Int(res.niter) + Int(res.nlive)
    strands = Results[]
    for id in sort(unique(ids))
        idxs = findall(==(id), ids)
        nsamps = length(idxs)
        logl = Float64.(res.logl[idxs])
        logvol = if added_live
            niter = nsamps - 1
            if niter > 0
                logvol_dead = .-log(2.0) .* collect(1:niter)
                vcat(logvol_dead, logvol_dead[end] + log(0.5))
            else
                [log(0.5)]
            end
        else
            .-log(2.0) .* collect(1:nsamps)
        end
        ints = compute_integrals(; logl=logl, logvol=logvol)
        data = _result_slice_dict(res, idxs)
        data[:nlive] = 1
        data[:niter] = added_live ? nsamps - 1 : nsamps
        data[:logwt] = ints.logwt
        data[:logl] = logl
        data[:logvol] = logvol
        data[:logz] = ints.logz
        data[:logzerr] = sqrt.(max.(ints.logzvar, 0.0))
        data[:h] = ints.h
        data[:information] = ints.h
        if haskey(res, :samples_batch)
            data[:samples_batch] = Int.(res.samples_batch[idxs])
            data[:batch_logl_bounds] = res.batch_logl_bounds
        end
        push!(strands, Results(data))
    end
    _ = print_progress
    return strands
end

function _prepare_for_merge(res::Results)
    nrun = length(res.samples_id)
    run_info = Dict{Symbol, Any}(
        :id => Int.(res.samples_id),
        :u => Matrix{Float64}(res.samples_u),
        :v => Matrix{Float64}(res.samples),
        :logl => Float64.(res.logl),
        :nc => Int.(res.ncall),
        :it => haskey(res, :samples_it) ? Int.(res.samples_it) : collect(1:nrun),
        :blobs => haskey(res, :blobs) ? res.blobs : fill(nothing, nrun),
        :proposal_stats =>
            if haskey(res, :proposal_stats) && !isnothing(res.proposal_stats)
                res.proposal_stats
            else
                fill(nothing, nrun)
            end,
    )
    run_nlive = _get_nsamps_samples_n(res)[2]
    if isdynamic(res) || haskey(res, :batch_logl_bounds)
        run_info[:batch] =
            haskey(res, :samples_batch) ? Int.(res.samples_batch) : zeros(Int, nrun)
        run_info[:batch_logl_bounds] = Matrix{Float64}(res.batch_logl_bounds)
    else
        run_info[:batch] = zeros(Int, nrun)
        run_info[:batch_logl_bounds] = reshape([-Inf, Inf], 1, 2)
    end
    return run_nlive, run_info
end

function _unique_rows(matrix::AbstractMatrix{<:Real})
    rows = Tuple{Float64, Float64}[]
    for i in axes(matrix, 1)
        row = (Float64(matrix[i, 1]), Float64(matrix[i, 2]))
        row in rows || push!(rows, row)
    end
    return reduce(vcat, (reshape(collect(row), 1, 2) for row in rows))
end

function _row_index(matrix::AbstractMatrix{<:Real}, row)
    target = (Float64(row[1]), Float64(row[2]))
    for i in axes(matrix, 1)
        (Float64(matrix[i, 1]), Float64(matrix[i, 2])) == target && return i - 1
    end
    throw(ArgumentError("row not found in matrix"))
end

function _merge_two(res1::Results, res2::Results; compute_aux::Bool=false)
    base_nlive, base_info = _prepare_for_merge(res1)
    new_nlive, new_info = _prepare_for_merge(res2)
    base_nsamples = length(base_info[:id])
    new_nsamples = length(new_info[:id])
    combined_bounds = _unique_rows(
        vcat(base_info[:batch_logl_bounds], new_info[:batch_logl_bounds])
    )
    base_bound_map = Dict(
        i - 1 => _row_index(combined_bounds, base_info[:batch_logl_bounds][i, :]) for
        i in axes(base_info[:batch_logl_bounds], 1)
    )
    new_bound_map = Dict(
        i - 1 => _row_index(combined_bounds, new_info[:batch_logl_bounds][i, :]) for
        i in axes(new_info[:batch_logl_bounds], 1)
    )
    base_lowedge = minimum(
        combined_bounds[[base_bound_map[b] + 1 for b in base_info[:batch]], 1]
    )
    new_lowedge = minimum(
        combined_bounds[[new_bound_map[b] + 1 for b in new_info[:batch]], 1]
    )

    combined = Dict(
        key => Any[] for key in
        (:id, :u, :v, :logl, :logvol, :nc, :it, :n, :samples_batch, :blobs, :proposal_stats)
    )
    base_idx = 1
    new_idx = 1
    for _ in 1:(base_nsamples + new_nsamples)
        base_cur_logl = base_idx <= base_nsamples ? base_info[:logl][base_idx] : Inf
        base_cur_nlive = base_idx <= base_nsamples ? base_nlive[base_idx] : 0
        new_cur_logl = new_idx <= new_nsamples ? new_info[:logl][new_idx] : Inf
        new_cur_nlive = new_idx <= new_nsamples ? new_nlive[new_idx] : 0
        cur_nlive = if base_cur_logl > new_lowedge && new_cur_logl > base_lowedge
            base_cur_nlive + new_cur_nlive
        elseif base_cur_logl <= new_lowedge
            base_cur_nlive
        else
            new_cur_nlive
        end
        if base_cur_logl <= new_cur_logl
            add_idx = base_idx
            info = base_info
            bmap = base_bound_map
            base_idx += 1
        else
            add_idx = new_idx
            info = new_info
            bmap = new_bound_map
            new_idx += 1
        end
        push!(combined[:samples_batch], bmap[info[:batch][add_idx]])
        push!(combined[:id], info[:id][add_idx])
        push!(combined[:u], vec(info[:u][add_idx, :]))
        push!(combined[:v], vec(info[:v][add_idx, :]))
        push!(combined[:logl], info[:logl][add_idx])
        push!(combined[:nc], info[:nc][add_idx])
        push!(combined[:it], info[:it][add_idx])
        push!(combined[:blobs], info[:blobs][add_idx])
        push!(combined[:proposal_stats], info[:proposal_stats][add_idx])
        push!(combined[:n], cur_nlive)
    end

    logvol = Float64[]
    plateau_mode = false
    plateau_counter = 0
    plateau_logdvol = 0.0
    cur_logvol = 0.0
    logl_array = Float64.(combined[:logl])
    nlive_array = Int.(combined[:n])
    for i in eachindex(logl_array)
        curl = logl_array[i]
        nlive = nlive_array[i]
        if !plateau_mode
            nplateau = count(==(curl), @view logl_array[i:end])
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
        push!(logvol, cur_logvol)
        if plateau_mode
            plateau_counter -= 1
            plateau_counter == 0 && (plateau_mode = false)
        end
    end

    ns = length(logl_array)
    data = Dict{Symbol, Any}(
        :niter => ns,
        :ncall => Int.(combined[:nc]),
        :eff => 100.0 * ns / sum(Int.(combined[:nc])),
        :samples => reduce(vcat, (reshape(v, 1, :) for v in combined[:v])),
        :samples_u => reduce(vcat, (reshape(u, 1, :) for u in combined[:u])),
        :samples_id => Int.(combined[:id]),
        :samples_it => Int.(combined[:it]),
        :samples_n => nlive_array,
        :samples_batch => Int.(combined[:samples_batch]),
        :batch_logl_bounds => combined_bounds,
        :blobs => copy(combined[:blobs]),
        :proposal_stats => copy(combined[:proposal_stats]),
        :logl => logl_array,
        :logvol => logvol,
    )
    if compute_aux
        ints = compute_integrals(; logl=logl_array, logvol=logvol)
        data[:logwt] = ints.logwt
        data[:logz] = ints.logz
        data[:logzerr] = sqrt.(max.(ints.logzvar, 0.0))
        data[:h] = ints.h
        data[:information] = ints.h
        data[:batch_nlive] = [
            length(unique(Int.(combined[:id])[Int.(combined[:samples_batch]) .== batch]))
            for batch in sort(unique(Int.(combined[:samples_batch])))
        ]
    else
        ints = compute_integrals(; logl=logl_array, logvol=logvol)
        data[:logwt] = ints.logwt
        data[:logz] = ints.logz
        data[:logzerr] = sqrt.(max.(ints.logzvar, 0.0))
        data[:h] = ints.h
        data[:information] = ints.h
    end
    return Results(data)
end

function merge_runs(res_list; print_progress::Bool=false)
    isempty(res_list) && throw(ArgumentError("res_list must not be empty"))
    rlist_base = Results[]
    rlist_add = Results[]
    for res in res_list
        if haskey(res, :samples_batch) && any(Int.(res.samples_batch) .== 0)
            push!(rlist_base, res)
        elseif haskey(res, :samples_batch)
            push!(rlist_add, res)
        else
            push!(rlist_base, res)
        end
    end
    if length(rlist_base) == 1 && length(rlist_add) == 1
        rlist_base = Results[res_list...]
        empty!(rlist_add)
    end
    res = if length(rlist_base) > 1
        current = copy(rlist_base)
        while length(current) > 2
            next = Results[]
            i = 1
            while i <= length(current)
                if i < length(current)
                    push!(next, _merge_two(current[i], current[i + 1]; compute_aux=false))
                    i += 2
                else
                    push!(next, current[i])
                    i += 1
                end
            end
            current = next
        end
        _merge_two(current[1], current[2]; compute_aux=true)
    else
        rlist_base[1]
    end
    for (i, run) in enumerate(rlist_add)
        res = _merge_two(res, run; compute_aux=i == length(rlist_add))
    end
    _ = print_progress
    return check_result_static(res)
end

function check_result_static(res::Results)
    samples_n = _get_nsamps_samples_n(res)[2]
    nlive = maximum(samples_n)
    niter = Int(res.niter)
    standard_run = false
    if length(samples_n) == niter && all(samples_n .== nlive)
        standard_run = true
    end
    nlive_test = min.(collect(niter:-1:1), nlive)
    if length(samples_n) == niter && all(samples_n .== nlive_test)
        standard_run = true
    end
    if standard_run
        data = asdict(res)
        data[:nlive] = nlive
        data[:niter] = niter - nlive
        delete!(data, :samples_n)
        return Results(data)
    end
    return res
end

function kld_error(
    res::Results;
    error::Union{Symbol, AbstractString}=:jitter,
    rng::AbstractRNG=Random.default_rng(),
    rstate=nothing,
    return_new::Bool=false,
    approx::Bool=false,
)
    rng_eff = isnothing(rstate) ? rng : rstate
    logp2 = Float64.(res.logwt) .- Float64(res.logz[end])
    err = Symbol(error)
    if err === :jitter
        new_res = jitter_run(res; rng=rng_eff, approx)
    elseif err === :resample
        new_res, samp_idx = resample_run(res; rng=rng_eff, return_idx=true)
        logp2 = logp2[samp_idx]
    else
        throw(ArgumentError("error must be :jitter or :resample"))
    end
    logp1 = Float64.(new_res.logwt) .- Float64(new_res.logz[end])
    kld = cumsum(exp.(logp1) .* (logp1 .- logp2))
    return return_new ? (kld, new_res) : kld
end

function _kld_error(args)
    res, error, approx, seed = args
    return kld_error(
        res;
        error=Symbol(error),
        rng=MersenneTwister(seed),
        return_new=true,
        approx=Bool(approx),
    )
end
