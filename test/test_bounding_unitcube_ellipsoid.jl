using Dynesty
using JSON3
using LinearAlgebra
using Random
using Statistics
using Test

matrix_from_json(rows) = reduce(vcat, [reshape(Vector{Float64}(row), 1, :) for row in rows])

@testset "UnitCube bound" begin
    cube = UnitCube(3)
    @test cube.ndim == 3
    @test cube.logvol == 0
    @test Base.contains(cube, [0.1, 0.2, 0.3])
    @test !Base.contains(cube, [0.0, 0.2, 0.3])
    @test size(samples(cube, 5; rng=MersenneTwister(1))) == (5, 3)
    @test get_random_axes(cube) == I(3)
end

@testset "Ellipsoid construction and helpers" begin
    fixture = JSON3.read(
        read(
            joinpath(@__DIR__, "reference", "python", "fixtures", "bounding_core.json"),
            String,
        ),
    )
    points = matrix_from_json(fixture["points"])
    ell = bounding_ellipsoid(points)

    @test ell.ndim == 2
    @test ell.ctr ≈ Vector{Float64}(fixture["ellipsoid"]["ctr"]) rtol = 1e-12 atol = 1e-12
    @test ell.cov ≈ matrix_from_json(fixture["ellipsoid"]["cov"]) rtol = 1e-10 atol = 1e-12
    @test ell.am ≈ matrix_from_json(fixture["ellipsoid"]["am"]) rtol = 1e-8 atol = 1e-10
    @test ell.axes ≈ matrix_from_json(fixture["ellipsoid"]["axes"]) rtol = 1e-10 atol =
        1e-12
    @test ell.axlens ≈ Vector{Float64}(fixture["ellipsoid"]["axlens"]) rtol = 1e-10 atol =
        1e-12
    @test ell.logvol ≈ fixture["ellipsoid"]["logvol"] rtol = 1e-10 atol = 1e-12
    @test Dynesty.distance_many(ell, points) ≈
        Vector{Float64}(fixture["ellipsoid"]["distances"]) rtol = 1e-10 atol = 1e-12
    @test all(Base.contains(ell, vec(points[i, :])) for i in axes(points, 1))

    endpoints = Dynesty.major_axis_endpoints(ell)
    expected_endpoints = [
        Vector{Float64}(x) for x in fixture["ellipsoid"]["major_axis_endpoints"]
    ]
    @test endpoints[1] ≈ expected_endpoints[1] rtol = 1e-10 atol = 1e-12
    @test endpoints[2] ≈ expected_endpoints[2] rtol = 1e-10 atol = 1e-12

    sample_point = sample(ell; rng=MersenneTwister(4))
    @test length(sample_point) == 2
    @test Dynesty.distance(ell, sample_point) <= 1.0 + 1e-12
    @test size(samples(ell, 7; rng=MersenneTwister(5))) == (7, 2)

    scale_to_logvol!(ell, ell.logvol + 0.5)
    @test ell.logvol ≈ fixture["ellipsoid"]["scaled_logvol"] rtol = 1e-10 atol = 1e-12
    @test ell.cov ≈ matrix_from_json(fixture["ellipsoid"]["scaled_cov"]) rtol = 1e-10 atol =
        1e-12
    @test ell.axlens ≈ Vector{Float64}(fixture["ellipsoid"]["scaled_axlens"]) rtol = 1e-10 atol =
        1e-12

    updated = Ellipsoid(2)
    Dynesty.update!(updated, points; rng=MersenneTwister(11), bootstrap=4)
    @test updated.logvol >= bounding_ellipsoid(points).logvol - 1e-12
    @test all(Base.contains(updated, vec(points[i, :])) for i in axes(points, 1))
end

@testset "Bounding helper functions" begin
    fixture = JSON3.read(
        read(
            joinpath(@__DIR__, "reference", "python", "fixtures", "bounding_core.json"),
            String,
        ),
    )

    @test logvol_prefactor(2) ≈ log(pi)
    rng = MersenneTwister(42)
    draws = reduce(vcat, [reshape(randsphere(3; rng), 1, :) for _ in 1:500])
    @test all(sqrt(sum(abs2, row)) <= 1.0 + 1e-12 for row in eachrow(draws))
    @test abs(mean(vec(draws))) < 0.08

    choice_rng = MersenneTwister(7)
    choices = [rand_choice([0.2, 0.3, 0.5]; rng=choice_rng) for _ in 1:2000]
    @test all(1 .<= choices .<= 3)
    freqs = [count(==(i), choices) / length(choices) for i in 1:3]
    @test freqs ≈ [0.2, 0.3, 0.5] atol = 0.04

    good, cov, am, axes = improve_covar_mat(
        matrix_from_json(fixture["improve_covar_mat"]["input"])
    )
    @test good == fixture["improve_covar_mat"]["good"]
    @test cov ≈ matrix_from_json(fixture["improve_covar_mat"]["cov"]) rtol = 1e-8 atol =
        1e-10
    @test am ≈ matrix_from_json(fixture["improve_covar_mat"]["am"]) rtol = 1e-6 atol = 1e-4
    @test axes ≈ matrix_from_json(fixture["improve_covar_mat"]["axes"]) rtol = 1e-8 atol =
        1e-10
    @test_throws ArgumentError bounding_ellipsoid(reshape([0.1, 0.2], 1, 2))

    slog = fixture["slogdet_checked"]
    @test Dynesty._slogdet_checked(matrix_from_json(slog["input"])) ≈ Float64(slog["value"]) rtol =
        1e-12 atol = 1e-12
    @test_throws ArgumentError Dynesty._slogdet_checked([1.0 0.0; 0.0 -1.0])

    boot_points = matrix_from_json(fixture["bootstrap_points"]["points"])
    points_in, points_out = Dynesty._bootstrap_points(boot_points, MersenneTwister(13579))
    @test size(points_in, 1) >= 2
    @test size(points_out, 1) >= 1
    @test size(points_in, 1) + size(points_out, 1) == size(boot_points, 1)

    expand_single = Dynesty._ellipsoid_bootstrap_expand(
        false, boot_points; rng=MersenneTwister(97531)
    )
    expand_multi = Dynesty._ellipsoid_bootstrap_expand(
        true, boot_points; rng=MersenneTwister(97531)
    )
    @test expand_single >= 1.0
    @test expand_multi >= 1.0
end

@testset "MultiEllipsoid basic union" begin
    fixture = JSON3.read(
        read(
            joinpath(@__DIR__, "reference", "python", "fixtures", "bounding_core.json"),
            String,
        ),
    )
    points = matrix_from_json(fixture["points"])
    multi = bounding_ellipsoids(points)

    @test multi.nells == fixture["multi"]["nells"]
    @test multi.logvol ≈ fixture["multi"]["logvol"] rtol = 1e-10 atol = 1e-12
    @test multi.logvol_ells ≈ Vector{Float64}(fixture["multi"]["logvol_ells"]) rtol = 1e-10 atol =
        1e-12
    @test all(Base.contains(multi, vec(points[i, :])) for i in axes(points, 1))
    @test Dynesty.within(multi, vec(points[1, :])) == [1]
    @test Dynesty.overlap(multi, vec(points[1, :])) == 1

    x, idx = sample(multi; rng=MersenneTwister(8))
    @test idx == 1
    @test Base.contains(multi, x)
    @test size(samples(multi, 4; rng=MersenneTwister(9))) == (4, 2)

    updated = MultiEllipsoid(2)
    Dynesty.update!(updated, points; rng=MersenneTwister(12), bootstrap=3)
    @test updated.logvol >= multi.logvol - 1e-12
    @test all(Base.contains(updated, vec(points[i, :])) for i in axes(points, 1))
end
