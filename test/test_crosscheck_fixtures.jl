using Dynesty
using JSON3
using Test

@testset "Python reference fixtures" begin
    fixture_path = joinpath(@__DIR__, "reference", "python", "fixtures", "utils_core.json")
    fixture = JSON3.read(read(fixture_path, String))

    @test fixture["source"]["commit"] == "3ec158de0d2bf12a56230faacd0c987b3d55d550"
    @test get_neff_from_logwt(Vector{Float64}(fixture["get_neff_from_logwt"]["logwt"])) ≈
        fixture["get_neff_from_logwt"]["value"] rtol = 1e-12 atol = 1e-12

    reflected = Vector{Float64}(fixture["apply_reflect"]["input"])
    apply_reflect(reflected)
    @test reflected ≈ Vector{Float64}(fixture["apply_reflect"]["output"]) rtol = 1e-12 atol =
        1e-12

    samples = reduce(
        vcat,
        [reshape(Vector{Float64}(row), 1, :) for row in fixture["mean_and_cov"]["samples"]],
    )
    weights = Vector{Float64}(fixture["mean_and_cov"]["weights"])
    mean, cov = mean_and_cov(samples, weights)
    expected_mean = Vector{Float64}(fixture["mean_and_cov"]["mean"])
    expected_cov = reduce(
        vcat,
        [reshape(Vector{Float64}(row), 1, :) for row in fixture["mean_and_cov"]["cov"]],
    )
    @test mean ≈ expected_mean rtol = 1e-12 atol = 1e-12
    @test cov ≈ expected_cov rtol = 1e-12 atol = 1e-12

    ints = compute_integrals(
        logl=Vector{Float64}(fixture["compute_integrals"]["logl"]),
        logvol=Vector{Float64}(fixture["compute_integrals"]["logvol"]),
    )
    @test ints.logz ≈ Vector{Float64}(fixture["compute_integrals"]["logz"]) rtol = 1e-10 atol =
        1e-12
    @test ints.logzvar ≈ Vector{Float64}(fixture["compute_integrals"]["logzvar"]) rtol =
        1e-10 atol = 1e-12
    @test ints.h ≈ Vector{Float64}(fixture["compute_integrals"]["h"]) rtol = 1e-10 atol =
        1e-12
end
