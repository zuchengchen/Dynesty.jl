using Test

const EXAMPLE_FILES = [
    "overview.jl",
    "dynamic_nested_sampling.jl",
    "minimal_corner.jl",
    "errors.jl",
    "gaussian.jl",
    "eggbox.jl",
    "gaussian_shells.jl",
    "high_dimensional_gaussian.jl",
    "exponential_wave.jl",
    "hyper_pyramid.jl",
    "linear_regression.jl",
    "loggamma.jl",
    "noisy_likelihoods.jl",
    "importance_reweighting.jl",
    "correlated_normal_25d.jl",
    "feature_overview.jl",
]

@testset "Example scripts" begin
    for file in EXAMPLE_FILES
        path = joinpath(@__DIR__, "..", "examples", file)
        mod = Module(Symbol("Example_", replace(file, ".jl" => "")))
        Core.eval(mod, :(using Dynesty))
        Core.eval(mod, :(using Random))
        Core.eval(mod, :(using LinearAlgebra))
        Core.eval(mod, :(using SpecialFunctions))
        Base.include(mod, path)
        summary = Core.eval(mod, :(main()))
        @test summary isa NamedTuple
        @test haskey(summary, :logz)
        @test isfinite(summary.logz)
        @test haskey(summary, :nsamples)
        @test summary.nsamples > 0
    end
end
