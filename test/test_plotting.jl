using Dynesty
using JSON3
using RecipesBase
using Test

plotting_matrix_from_json(rows) =
    reduce(vcat, [reshape(Vector{Float64}(row), 1, :) for row in rows])

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
