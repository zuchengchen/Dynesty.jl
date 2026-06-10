module DynestyHDF5Ext

using Dynesty
using HDF5

const HISTORY_DATASETS = (;
    evaluation_u="evaluation_u",
    evaluation_v="evaluation_v",
    evaluation_logl="evaluation_logl",
)

function _history_path(ll::Dynesty.LogLikelihood)
    isnothing(ll.history_filename) && throw(
        ArgumentError(
            "history_filename must be provided when save_evaluation_history=true"
        ),
    )
    return ll.history_filename
end

function _history_chunk(nrows::Int, ncols::Int)
    return (max(1, min(max(nrows, 1), 1024)), max(1, ncols))
end

function _ensure_history_datasets!(file, ndim::Int)
    if !haskey(file, HISTORY_DATASETS.evaluation_u)
        create_dataset(
            file,
            HISTORY_DATASETS.evaluation_u,
            Float64,
            ((0, ndim), (-1, ndim));
            chunk=_history_chunk(1, ndim),
        )
    end
    if !haskey(file, HISTORY_DATASETS.evaluation_v)
        create_dataset(
            file,
            HISTORY_DATASETS.evaluation_v,
            Float64,
            ((0, ndim), (-1, ndim));
            chunk=_history_chunk(1, ndim),
        )
    end
    if !haskey(file, HISTORY_DATASETS.evaluation_logl)
        create_dataset(
            file, HISTORY_DATASETS.evaluation_logl, Float64, ((0,), (-1,)); chunk=(1024,)
        )
    end

    size(file[HISTORY_DATASETS.evaluation_u], 2) == ndim || throw(
        DimensionMismatch(
            "existing evaluation_u dimension $(size(file[HISTORY_DATASETS.evaluation_u], 2)) != ndim $ndim",
        ),
    )
    size(file[HISTORY_DATASETS.evaluation_v], 2) == ndim || throw(
        DimensionMismatch(
            "existing evaluation_v dimension $(size(file[HISTORY_DATASETS.evaluation_v], 2)) != ndim $ndim",
        ),
    )
    return nothing
end

function _history_batch(items::AbstractVector{Dynesty.EvaluationHistoryItem}, ndim::Int)
    n = length(items)
    u = Matrix{Float64}(undef, n, ndim)
    v = Matrix{Float64}(undef, n, ndim)
    logl = Vector{Float64}(undef, n)
    for (row, item) in enumerate(items)
        length(item.u) == ndim ||
            throw(DimensionMismatch("evaluation_u length $(length(item.u)) != ndim $ndim"))
        length(item.v) == ndim ||
            throw(DimensionMismatch("evaluation_v length $(length(item.v)) != ndim $ndim"))
        u[row, :] .= item.u
        v[row, :] .= item.v
        logl[row] = item.logl
    end
    return u, v, logl
end

function _append_rows!(
    file, items::AbstractVector{Dynesty.EvaluationHistoryItem}, ndim::Int
)
    isempty(items) && return 0
    _ensure_history_datasets!(file, ndim)
    u, v, logl = _history_batch(items, ndim)
    nnew = length(items)

    d_u = file[HISTORY_DATASETS.evaluation_u]
    d_v = file[HISTORY_DATASETS.evaluation_v]
    d_logl = file[HISTORY_DATASETS.evaluation_logl]
    old_n = size(d_u, 1)
    size(d_v, 1) == old_n ||
        throw(DimensionMismatch("evaluation_v row count does not match evaluation_u"))
    size(d_logl, 1) == old_n ||
        throw(DimensionMismatch("evaluation_logl row count does not match evaluation_u"))
    new_n = old_n + nnew

    HDF5.set_extent_dims(d_u, (new_n, ndim))
    HDF5.set_extent_dims(d_v, (new_n, ndim))
    HDF5.set_extent_dims(d_logl, (new_n,))
    rows = (old_n + 1):new_n
    d_u[rows, :] = u
    d_v[rows, :] = v
    d_logl[rows] = logl
    return nnew
end

function Dynesty.history_init!(ll::Dynesty.LogLikelihood)
    path = _history_path(ll)
    h5open(path, "cw") do file
        _ensure_history_datasets!(file, ll.ndim)
        attrs(file)["format"] = "Dynesty.jl evaluation history"
        attrs(file)["ndim"] = ll.ndim
    end
    return ll
end

function Dynesty.history_save!(ll::Dynesty.LogLikelihood)
    ll.save_evaluation_history || return ll
    isempty(ll.evaluation_history) && return ll
    try
        path = _history_path(ll)
        written = h5open(path, "cw") do file
            _append_rows!(file, ll.evaluation_history, ll.ndim)
        end
        ll.evaluation_history_counter += written
        empty!(ll.evaluation_history)
        ll.failed_save = false
        return ll
    catch
        ll.failed_save = true
        rethrow()
    end
end

end
