using Dynesty
using Random

const PLOTS_PKGID = Base.PkgId(Base.UUID("91a5bcdd-55d7-5caf-9e0b-520d859cae80"), "Plots")

function load_plots()
    try
        return Base.require(PLOTS_PKGID)
    catch err
        if !(err isa ArgumentError) &&
            !occursin("Package Plots", sprint(showerror, err))
            rethrow()
        end
        error(
            "Plots.jl is required to render the corner plot. Install it with " *
            "`using Pkg; Pkg.add(\"Plots\")` and run this example again.",
        )
    end
end

const TRUE_MEAN = [0.25, -0.35]
const TRUE_SIGMA = [0.12, 0.20]

prior_transform(u) = [-1.0 + 2.0 * u[1], -1.0 + 2.0 * u[2]]
loglikelihood(theta) = -0.5 * sum(((theta .- TRUE_MEAN) ./ TRUE_SIGMA) .^ 2)

function run_sampler(;
    rng=MersenneTwister(42),
    nlive=150,
    dlogz=0.05,
    parallel=:serial,
    queue_size=nothing,
    proposal_scheduler=:batch,
)
    sampler = NestedSampler(
        loglikelihood,
        prior_transform,
        2;
        nlive,
        bound=:multi,
        sample=:unif,
        rng,
        parallel,
        queue_size,
        proposal_scheduler,
        enlarge=1.1,
        bootstrap=0,
    )
    run_nested!(sampler; dlogz, print_progress=false)
    return (; sampler, res=results(sampler))
end

function backend_name(sampler)
    backend = sampler.map_backend
    return string(nameof(typeof(backend)))
end

function posterior_summary(fit)
    res = fit.res
    sampler = fit.sampler
    weights = importance_weights(res)
    mean = vec(sum(res.samples .* weights; dims=1))
    equal_weight_samples = samples_equal(res; rng=MersenneTwister(1234))
    return (
        logz=res.logz[end],
        logzerr=res.logzerr[end],
        nsamples=length(res.logl),
        mean=mean,
        equal_weight_samples=equal_weight_samples,
        backend=backend_name(sampler),
        queue_size=sampler.map_backend.queue_size,
        proposal_scheduler=sampler.proposal_scheduler,
        proposal_tasks_submitted=sampler.proposal_tasks_submitted,
        proposal_batches_submitted=sampler.proposal_batches_submitted,
        threads=Threads.nthreads(),
    )
end

function save_corner_plot(res; path=joinpath(@__DIR__, "output", "minimal_corner.png"))
    plots = load_plots()
    mkpath(dirname(path))
    fig = Base.invokelatest(
        plots.plot,
        cornerplot(
            res;
            dims=[1, 2],
            labels=["theta1", "theta2"],
            truths=TRUE_MEAN,
            smooth=[30, 30],
        );
        size=(720, 720),
    )
    Base.invokelatest(plots.savefig, fig, path)
    return path
end

function parse_cli(args)
    opts = Dict{Symbol, Any}(
        :make_plot => true,
        :plot_path => joinpath(@__DIR__, "output", "minimal_corner.png"),
        :parallel => "serial",
        :queue_size => nothing,
        :proposal_scheduler => "batch",
        :nlive => 150,
        :dlogz => 0.05,
        :seed => 42,
    )
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--no-plot"
            opts[:make_plot] = false
            i += 1
        elseif arg == "--plot-path"
            opts[:plot_path] = args[i + 1]
            i += 2
        elseif arg == "--parallel"
            opts[:parallel] = args[i + 1]
            i += 2
        elseif arg == "--queue-size"
            opts[:queue_size] = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--proposal-scheduler"
            opts[:proposal_scheduler] = args[i + 1]
            i += 2
        elseif arg == "--nlive"
            opts[:nlive] = parse(Int, args[i + 1])
            i += 2
        elseif arg == "--dlogz"
            opts[:dlogz] = parse(Float64, args[i + 1])
            i += 2
        elseif arg == "--seed"
            opts[:seed] = parse(Int, args[i + 1])
            i += 2
        else
            throw(ArgumentError("unknown argument $arg"))
        end
    end
    return opts
end

function main(;
    make_plot=false,
    plot_path=joinpath(@__DIR__, "output", "minimal_corner.png"),
    parallel=:serial,
    queue_size=nothing,
    proposal_scheduler=:batch,
    nlive=150,
    dlogz=0.05,
    seed=42,
)
    fit = run_sampler(;
        rng=MersenneTwister(Int(seed)),
        nlive=Int(nlive),
        dlogz=Float64(dlogz),
        parallel,
        queue_size,
        proposal_scheduler,
    )
    summary = posterior_summary(fit)
    saved_plot = make_plot ? save_corner_plot(fit.res; path=plot_path) : nothing
    return merge(summary, (plot=saved_plot,))
end

if abspath(PROGRAM_FILE) == @__FILE__
    opts = parse_cli(ARGS)
    summary = main(;
        make_plot=Bool(opts[:make_plot]),
        plot_path=String(opts[:plot_path]),
        parallel=String(opts[:parallel]),
        queue_size=opts[:queue_size],
        proposal_scheduler=String(opts[:proposal_scheduler]),
        nlive=Int(opts[:nlive]),
        dlogz=Float64(opts[:dlogz]),
        seed=Int(opts[:seed]),
    )
    println("logz=$(summary.logz) logzerr=$(summary.logzerr) nsamples=$(summary.nsamples)")
    println("posterior mean=$(summary.mean)")
    println(
        "backend=$(summary.backend) threads=$(summary.threads) " *
        "queue_size=$(summary.queue_size) proposal_scheduler=$(summary.proposal_scheduler)",
    )
    println(
        "proposal tasks=$(summary.proposal_tasks_submitted) " *
        "batches=$(summary.proposal_batches_submitted)",
    )
    println("corner plot=$(summary.plot)")
end
