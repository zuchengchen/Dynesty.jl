using Dynesty
using JSON3
using LinearAlgebra
using Random
using RecipesBase
using Test

plotting_matrix_from_json(rows) =
    reduce(vcat, [reshape(Vector{Float64}(row), 1, :) for row in rows])

function plotting_results_fixture()
    samples = [
        0.10 1.00 -0.40
        0.25 0.80 -0.15
        0.40 0.65 0.10
        0.55 0.45 0.30
        0.70 0.30 0.55
        0.85 0.12 0.80
    ]
    logz = [-4.5, -3.3, -2.4, -1.7, -1.25, -1.0]
    return Results(;
        samples=samples,
        samples_u=copy(samples),
        samples_id=[1, 2, 1, 2, 1, 2],
        logl=[-6.0, -4.8, -3.7, -2.4, -1.3, -0.6],
        logvol=[-0.1, -0.6, -1.1, -1.8, -2.6, -3.4],
        logwt=[-5.2, -4.0, -3.1, -2.0, -1.45, -1.2],
        logz=logz,
        logzerr=[0.55, 0.45, 0.35, 0.25, 0.18, 0.12],
        nlive=2,
        niter=4,
    )
end

function plotting_bound_results_fixture()
    samples_u = [
        0.20 0.20 0.30
        0.80 0.20 0.40
        0.20 0.80 0.50
        0.80 0.80 0.60
        0.35 0.35 0.45
        0.65 0.35 0.55
        0.35 0.65 0.50
        0.65 0.65 0.60
    ]
    samples = copy(samples_u)
    bounds = Any[
        UnitCube(3), Ellipsoid(3; ctr=[0.5, 0.5, 0.5], cov=Diagonal([0.04, 0.05, 0.03]))
    ]
    return Results(;
        samples,
        samples_u,
        samples_id=[1, 2, 3, 4, 1, 2, 3, 4],
        samples_it=[1, 2, 3, 4, 5, 6, 7, 8],
        logl=collect(-8.0:-1.0),
        logvol=collect(range(-0.2, -2.0; length=8)),
        logwt=collect(range(-8.0, -1.0; length=8)),
        logz=collect(range(-7.5, -0.5; length=8)),
        logzerr=fill(0.1, 8),
        nlive=4,
        niter=4,
        bound=bounds,
        bound_iter=[0, 1, 1, 1, 1, 1, 1, 1],
        samples_bound=[0, 0, 1, 1, 1, 1, 1, 1],
    )
end

@testset "Plotting span helper" begin
    fixture = JSON3.read(
        read(
            joinpath(@__DIR__, "reference", "python", "fixtures", "plotting_core.json"),
            String,
        ),
    )
    entry = fixture["check_span"]
    samples = plotting_matrix_from_json(entry["samples"])
    weights = Vector{Float64}(entry["weights"])
    span = Any[Float64(entry["span"][1]), Vector{Float64}(entry["span"][2])]
    checked = check_span(span, samples; weights)
    expected = [Tuple(Vector{Float64}(value)) for value in entry["value"]]

    @test first.(checked) ≈ first.(expected) rtol = entry["rtol"] atol = entry["atol"]
    @test last.(checked) ≈ last.(expected) rtol = entry["rtol"] atol = entry["atol"]
    @test span[1] == entry["span"][1]
    @test_throws DimensionMismatch check_span([0.9], samples; weights)
    @test_throws ArgumentError check_span([1.2, [0.0, 1.0]], samples; weights)
    @test plot_truth(0.5; vertical=true) == [0.5]
    @test plot_truth([0.1, 0.2]; horizontal=true) == [0.1, 0.2]
    @test_throws ArgumentError plot_truth(0.5)
end

@testset "Plotting hist2d helper and recipe" begin
    fixture = JSON3.read(
        read(
            joinpath(@__DIR__, "reference", "python", "fixtures", "plotting_core.json"),
            String,
        ),
    )
    entry = fixture["hist2d"]
    hist = Dynesty._hist2d(
        Vector{Float64}(entry["x"]),
        Vector{Float64}(entry["y"]);
        weights=Vector{Float64}(entry["weights"]),
        span=[Vector{Float64}(value) for value in entry["span"]],
        smooth=Vector{Int}(entry["smooth"]),
        levels=Vector{Float64}(entry["levels"]),
    )

    @test hist.xcenters ≈ Vector{Float64}(entry["xcenters"]) rtol = entry["rtol"] atol = entry["atol"]
    @test hist.ycenters ≈ Vector{Float64}(entry["ycenters"]) rtol = entry["rtol"] atol = entry["atol"]
    @test hist.density ≈ plotting_matrix_from_json(entry["density"]) rtol = entry["rtol"] atol = entry["atol"]
    @test hist.levels ≈ Vector{Float64}(entry["thresholds"]) rtol = entry["rtol"] atol = entry["atol"]
    @test size(hist.density_extended) == size(hist.density) .+ (4, 4)
    @test length(hist.xextended) == length(hist.xcenters) + 4
    @test length(hist.yextended) == length(hist.ycenters) + 4

    smoothed = Dynesty._hist2d(
        Vector{Float64}(entry["x"]),
        Vector{Float64}(entry["y"]);
        weights=Vector{Float64}(entry["weights"]),
        span=[Vector{Float64}(value) for value in entry["span"]],
        smooth=[0.5, 0.4],
        levels=Vector{Float64}(entry["levels"]),
    )
    @test size(smoothed.density) == (4, 5)
    @test sum(smoothed.density) ≈ sum(Vector{Float64}(entry["weights"])) rtol = 1e-8 atol =
        1e-10

    recipes = RecipesBase.apply_recipe(Dict{Symbol, Any}(), hist)
    @test length(recipes) == 1
    @test recipes[1].args[1] == hist.xcenters
    @test recipes[1].args[2] == hist.ycenters
    @test recipes[1].args[3] == transpose(hist.density)

    @test_throws DimensionMismatch Dynesty._hist2d([1.0], [1.0, 2.0])
    @test_throws ArgumentError Dynesty._hist2d(
        [1.0, 1.0], [2.0, 2.0]; span=[[0.0, 0.0], [1.0, 2.0]]
    )
end

@testset "Plotting data APIs and recipes" begin
    res = plotting_results_fixture()

    run = runplot(res; kde=false, lnz_truth=-0.5)
    @test run isa RunPlotData
    @test run.yseries[1] == [2.0, 2.0, 2.0, 2.0, 2.0, 1.0]
    @test run.final_live_index == 5
    @test run.final_live_x == -res.logvol[5]
    @test run.truth_y ≈ exp(-0.5)
    @test length(run.evidence_error_bands) == 3
    run_recipes = RecipesBase.apply_recipe(Dict{Symbol, Any}(), run)
    @test length(run_recipes) == 12
    @test run_recipes[1].args == (run.xseries[1], run.yseries[1])

    run_kde = runplot(res; kde=true, nkde=8, lnz_error=false, logplot=true)
    @test length(run_kde.xseries[3]) == 8
    @test length(run_kde.yseries[3]) == 8
    @test isempty(run_kde.evidence_error_bands)
    @test run_kde.labels[4] == "log(Evidence)"

    trace = traceplot(
        res;
        dims=[1, 3],
        smooth=(4, 0.5),
        thin=2,
        kde=false,
        labels=["alpha", "gamma"],
        truths=[0.5, nothing],
    )
    @test trace isa TracePlotData
    @test size(trace.samples) == (2, 6)
    @test trace.dims == [1, 3]
    @test trace.labels == ["alpha", "gamma"]
    @test trace.smooth == Union{Int, Float64}[4, 0.5]
    @test length(trace.marginals[1].density) == 4
    @test length(trace.quantiles[1]) == 3
    @test trace.truths == Union{Nothing, Float64}[0.5, nothing]
    trace_recipes = RecipesBase.apply_recipe(Dict{Symbol, Any}(), trace)
    @test length(trace_recipes) == 10
    @test length(trace_recipes[1].args[1]) == 3

    points = cornerpoints(
        res;
        dims=[1, 2, 3],
        span=[1.0, 1.0, 1.0],
        thin=2,
        kde=false,
        labels=["alpha", "beta", "gamma"],
    )
    @test points isa CornerPointsData
    @test size(points.samples) == (3, 6)
    @test !isnothing(points.span)
    points_recipes = RecipesBase.apply_recipe(Dict{Symbol, Any}(), points)
    @test length(points_recipes) == 3
    @test length(points_recipes[1].args[1]) == 3

    corner = cornerplot(
        res;
        dims=[1, 2],
        span=[1.0, 1.0],
        smooth=[4, 4],
        quantiles=[0.25, 0.5, 0.75],
        labels=["alpha", "beta"],
    )
    @test corner isa CornerPlotData
    @test size(corner.hist2d) == (2, 2)
    @test isnothing(corner.hist2d[1, 2])
    @test corner.hist2d[2, 1] isa Hist2DResult
    corner_recipes = RecipesBase.apply_recipe(Dict{Symbol, Any}(), corner)
    @test length(corner_recipes) == 9
    heatmap_recipe = only(filter(recipe -> length(recipe.args) == 3, corner_recipes))
    @test heatmap_recipe.args[3] == transpose(corner.hist2d[2, 1].density)

    one_dim = Results(;
        samples=res.samples[:, 1],
        samples_u=res.samples_u[:, 1],
        samples_id=res.samples_id,
        logl=res.logl,
        logvol=res.logvol,
        logwt=res.logwt,
        logz=res.logz,
        logzerr=res.logzerr,
        nlive=res.nlive,
        niter=res.niter,
    )
    @test_throws ArgumentError cornerpoints(one_dim)
    @test_throws ArgumentError traceplot(res; thin=0)
    @test_throws ArgumentError traceplot(res; dims=[0])
    @test_throws DimensionMismatch cornerplot(res; dims=[1, 2], labels=["only one"])
end

@testset "Bound plotting data APIs and recipes" begin
    res = plotting_bound_results_fixture()

    bound = boundplot(
        res,
        [1, 3];
        idx=3,
        ndraws=12,
        show_live=true,
        labels=["u1", "u3"],
        rng=MersenneTwister(12),
    )
    @test bound isa BoundPlotData
    @test size(bound.draws) == (12, 2)
    @test size(bound.live) == (4, 2)
    @test bound.dims == [1, 3]
    @test bound.labels == ["u1", "u3"]
    @test bound.bound_index == 2
    @test bound.selection_kind == :idx
    @test bound.selection_value == 3
    @test all(isfinite, bound.draws)
    bound_recipes = RecipesBase.apply_recipe(Dict{Symbol, Any}(), bound)
    @test length(bound_recipes) == 2
    @test length(bound_recipes[1].args[1]) == 12
    @test length(bound_recipes[2].args[1]) == 4

    transformed = boundplot(
        res,
        [1, 2];
        it=2,
        ndraws=10,
        prior_transform=u -> 2 .* u .- 1,
        span=[[-1.0, 1.0], [-1.0, 1.0]],
        rng=MersenneTwister(13),
    )
    @test transformed.bound_index == 2
    @test transformed.selection_kind == :it
    @test transformed.span == [(-1.0, 1.0), (-1.0, 1.0)]
    @test size(transformed.draws, 2) == 2
    @test all(-1.0 .< transformed.draws .< 1.0)

    corner = cornerbound(
        res;
        idx=4,
        dims=[1, 2, 3],
        ndraws=9,
        show_live=true,
        labels=["u1", "u2", "u3"],
        rng=MersenneTwister(14),
    )
    @test corner isa CornerBoundData
    @test size(corner.draws) == (9, 3)
    @test size(corner.live) == (4, 3)
    @test corner.bound_index == 2
    corner_recipes = RecipesBase.apply_recipe(Dict{Symbol, Any}(), corner)
    @test length(corner_recipes) == 6
    @test length(corner_recipes[1].args[1]) == 9
    @test length(corner_recipes[2].args[1]) == 4

    one_dim = Results(;
        samples=res.samples[:, 1],
        samples_u=res.samples_u[:, 1:1],
        samples_id=res.samples_id,
        logl=res.logl,
        logvol=res.logvol,
        logwt=res.logwt,
        logz=res.logz,
        logzerr=res.logzerr,
        nlive=res.nlive,
        niter=res.niter,
        bound=[UnitCube(1)],
        bound_iter=fill(0, length(res.logl)),
        samples_bound=fill(0, length(res.logl)),
    )
    @test_throws ArgumentError cornerbound(one_dim; idx=1)
    @test_throws ArgumentError boundplot(res, [1, 2])
    @test_throws BoundsError boundplot(res, [1, 2]; idx=0)
    @test_throws DimensionMismatch boundplot(res, [1, 2, 3]; idx=1)
    @test_throws ArgumentError boundplot(
        Results(;
            samples=res.samples,
            samples_u=res.samples_u,
            samples_id=res.samples_id,
            logl=res.logl,
            logvol=res.logvol,
            logwt=res.logwt,
            logz=res.logz,
            logzerr=res.logzerr,
            nlive=res.nlive,
            niter=res.niter,
        ),
        [1, 2];
        idx=1,
    )
    dynamic_res = Results(;
        samples=res.samples,
        samples_u=res.samples_u,
        samples_id=res.samples_id,
        samples_it=res.samples_it,
        samples_n=fill(res.nlive, length(res.logl)),
        logl=res.logl,
        logvol=res.logvol,
        logwt=res.logwt,
        logz=res.logz,
        logzerr=res.logzerr,
        bound=res.bound,
        bound_iter=res.bound_iter,
        samples_bound=res.samples_bound,
    )
    dynamic_bound = boundplot(dynamic_res, [1, 2]; idx=1, ndraws=5, rng=MersenneTwister(15))
    @test size(dynamic_bound.draws) == (5, 2)
    @test isnothing(dynamic_bound.live)
    @test_throws ArgumentError boundplot(dynamic_res, [1, 2]; idx=1, show_live=true)
end

if get(ENV, "DYNESTY_RUN_PLOT_TESTS", "false") == "true"
    @testset "Optional plotting recipe smoke" begin
        res = plotting_bound_results_fixture()
        run_data = runplot(res; kde=true, nkde=12, lnz_truth=-0.3)
        trace_data = traceplot(
            res; dims=[1, 2], smooth=(4, 0.4), labels=["u1", "u2"], truths=[0.4, 0.5]
        )
        points_data = cornerpoints(res; dims=[1, 2, 3], thin=1, labels=["u1", "u2", "u3"])
        corner_data = cornerplot(res; dims=[1, 2, 3], smooth=[4, 4, 4])
        bound_data = boundplot(res, [1, 2]; idx=4, ndraws=16, rng=MersenneTwister(2401))
        cbound_data = cornerbound(
            res; idx=4, dims=[1, 2, 3], ndraws=16, rng=MersenneTwister(2402)
        )

        for data in (run_data, trace_data, points_data, corner_data, bound_data, cbound_data)
            recipes = RecipesBase.apply_recipe(Dict{Symbol, Any}(), data)
            @test !isempty(recipes)
            @test all(recipe -> !isempty(recipe.args), recipes)
        end

        one_dim = Results(;
            samples=res.samples[:, 1:1],
            samples_u=res.samples_u[:, 1:1],
            samples_id=res.samples_id,
            logl=res.logl,
            logvol=res.logvol,
            logwt=res.logwt,
            logz=res.logz,
            logzerr=res.logzerr,
            nlive=res.nlive,
            niter=res.niter,
        )
        one_trace = traceplot(one_dim; kde=true, smooth=5)
        @test !isempty(RecipesBase.apply_recipe(Dict{Symbol, Any}(), one_trace))
    end
end
