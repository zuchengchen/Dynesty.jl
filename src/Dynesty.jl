module Dynesty

export DelayTimer,
    DistributedMapBackend,
    DynamicSamplerBaseDone,
    DynamicSamplerBatchDone,
    DynamicSamplerInBase,
    DynamicSamplerInBaseAddLive,
    DynamicSamplerInBatch,
    DynamicSamplerInBatchAddLive,
    DynamicSamplerInit,
    DynamicSamplerLivePointsInit,
    DynamicSamplerRunDone,
    Ellipsoid,
    LogLikelihood,
    LoglOutput,
    MapTaskError,
    MultiEllipsoid,
    NestedSampler,
    PrintFnArgs,
    RadFriends,
    Results,
    RunRecord,
    RSliceSampler,
    RWalkSampler,
    SamplerArgument,
    SamplerReturn,
    SerialMapBackend,
    SliceSampler,
    SupFriends,
    ThreadedMapBackend,
    UnitCube,
    UnitCubeSampler,
    UniformBoundSampler,
    AbstractBound,
    apply_reflect,
    apply_reflect!,
    boundplot,
    BoundPlotData,
    bounding_ellipsoid,
    bounding_ellipsoids,
    checkpoint!,
    check_result_static,
    check_span,
    citations,
    CornerPlotData,
    CornerPointsData,
    cornerbound,
    CornerBoundData,
    compute_weights,
    compute_integrals,
    ConfiguredBatchSampler,
    cornerplot,
    cornerpoints,
    DynamicBatchFirstPoint,
    DynamicSamplerState,
    _configure_batch_sampler,
    from_python_indices,
    get_citations,
    get_neff_from_logwt,
    get_nonbounded,
    get_print_func,
    get_print_fn_args,
    get_random_axes,
    get_random_generator,
    Hist2DResult,
    generic_random_walk,
    generic_slice_step,
    improve_covar_mat,
    importance_weights,
    is_time,
    is_time!,
    jitter_run,
    kld_error,
    load_results,
    logvol_prefactor,
    map_ordered,
    map_with_rng,
    mean_and_cov,
    merge_runs,
    n_effective,
    progress_integration,
    RunPlotData,
    quantile,
    rand_choice,
    randsphere,
    resample_equal,
    resample_run,
    results,
    restore_sampler,
    results_substitute,
    reweight_run,
    runplot,
    run_nested,
    run_nested!,
    plot_truth,
    print_fn,
    print_fn_fallback,
    stopping_function,
    TracePlotData,
    traceplot,
    unravel_run,
    add_live_points!,
    samples_equal,
    scale_to_logvol!,
    save_results,
    save_sampler,
    sample,
    samples,
    propose_ball_point,
    task_seeds,
    tune_slice,
    unitcheck,
    weight_function

include("utils.jl")
include("results.jl")
include("persistence.jl")
include("parallel.jl")
include("bounding.jl")
include("internal_samplers.jl")
include("sampler.jl")
include("dynamic_sampler.jl")
include("plotting.jl")

"""
    get_citations(; format = :text)

Return citation information for Dynesty.jl and the Python dynesty sources that
this package migrates. `format = :text` returns a newline-separated string;
`format = :bibtex` returns BibTeX entries; `format = :records` returns named
tuples with citation metadata.
"""
function get_citations(; format::Symbol=:text)
    if format === :records
        return _CITATION_RECORDS
    elseif format === :bibtex
        return join((record.bibtex for record in _CITATION_RECORDS), "\n\n")
    elseif format === :text
        return join((record.text for record in _CITATION_RECORDS), "\n")
    else
        throw(
            ArgumentError(
                "format must be one of :text, :bibtex, or :records; got $(repr(format))"
            ),
        )
    end
end

"""
    citations()

Compatibility alias for [`get_citations`](@ref).
"""
citations() = get_citations()

const _CITATION_RECORDS = (
    (
        key="speagle2020dynesty",
        text="Speagle (2020), dynesty: a dynamic nested sampling package for estimating Bayesian posteriors and evidences.",
        bibtex="""
      @article{speagle2020dynesty,
        author = {Speagle, Joshua S.},
        title = {dynesty: a dynamic nested sampling package for estimating Bayesian posteriors and evidences},
        journal = {Monthly Notices of the Royal Astronomical Society},
        year = {2020},
        volume = {493},
        number = {3},
        pages = {3132--3158},
        doi = {10.1093/mnras/staa278}
      }""",
    ),
    (
        key="koposov2024dynesty",
        text="Koposov et al. (2024), dynesty 3 series development and sampler improvements.",
        bibtex="""
      @misc{koposov2024dynesty,
        author = {Koposov, Sergey E. and Speagle, Joshua S. and dynesty contributors},
        title = {dynesty 3 series development and sampler improvements},
        year = {2024}
      }""",
    ),
    (
        key="skilling2004nested",
        text="Skilling (2004), Nested Sampling.",
        bibtex="""
      @inproceedings{skilling2004nested,
        author = {Skilling, John},
        title = {Nested Sampling},
        booktitle = {AIP Conference Proceedings},
        year = {2004},
        volume = {735},
        pages = {395--405},
        doi = {10.1063/1.1835238}
      }""",
    ),
    (
        key="higson2019dynamic",
        text="Higson et al. (2019), Dynamic nested sampling.",
        bibtex="""
      @article{higson2019dynamic,
        author = {Higson, Edward and Handley, Will and Hobson, Michael and Lasenby, Anthony},
        title = {Dynamic nested sampling: an improved algorithm for parameter estimation and evidence calculation},
        journal = {Statistics and Computing},
        year = {2019},
        volume = {29},
        pages = {891--913},
        doi = {10.1007/s11222-018-9844-0}
      }""",
    ),
    (
        key="feroz2009multinest",
        text="Feroz et al. (2009), MultiNest ellipsoidal nested-sampling methods.",
        bibtex="""
      @article{feroz2009multinest,
        author = {Feroz, F. and Hobson, M. P. and Bridges, M.},
        title = {MultiNest: an efficient and robust Bayesian inference tool for cosmology and particle physics},
        journal = {Monthly Notices of the Royal Astronomical Society},
        year = {2009},
        volume = {398},
        number = {4},
        pages = {1601--1614},
        doi = {10.1111/j.1365-2966.2009.14548.x}
      }""",
    ),
)

end
