using Dynesty
using JSON3
using LinearAlgebra
using Random
using Test

friends_matrix(rows) = reduce(vcat, [reshape(Vector{Float64}(row), 1, :) for row in rows])

function check_friend_bound(bound, fixture, points)
    Dynesty.update!(bound, points; rng=MersenneTwister(11), use_clustering=false)
    @test bound.cov ≈ friends_matrix(fixture["cov"]) rtol = 1e-8 atol = 1e-10
    @test bound.am ≈ friends_matrix(fixture["am"]) rtol = 1e-8 atol = 1e-10
    @test bound.axes ≈ friends_matrix(fixture["axes"]) rtol = 1e-8 atol = 1e-10
    @test bound.axes_inv ≈ friends_matrix(fixture["axes_inv"]) rtol = 1e-8 atol = 1e-10
    @test bound.logvol ≈ fixture["logvol"] rtol = 1e-8 atol = 1e-10
    @test bound.ctrs ≈ friends_matrix(fixture["ctrs"])
    @test all(Base.contains(bound, vec(points[i, :])) for i in axes(points, 1))
    @test Dynesty.overlap(bound, vec(points[1, :])) == fixture["overlap_first"]
    @test Dynesty.within(bound, vec(points[1, :])) ==
        Vector{Int}(fixture["within_first_julia_1_based"])

    x = sample(bound; rng=MersenneTwister(21))
    @test length(x) == size(points, 2)
    @test Base.contains(bound, x)
    xs = samples(bound, 5; rng=MersenneTwister(22))
    @test size(xs) == (5, size(points, 2))

    original_logvol = bound.logvol
    scale_to_logvol!(bound, original_logvol + 0.25)
    @test bound.logvol ≈ fixture["scaled_logvol"] rtol = 1e-8 atol = 1e-10
    @test bound.cov ≈ friends_matrix(fixture["scaled_cov"]) rtol = 1e-8 atol = 1e-10
end

@testset "RadFriends and SupFriends bounds" begin
    fixture = JSON3.read(
        read(
            joinpath(@__DIR__, "reference", "python", "fixtures", "friends_core.json"),
            String,
        ),
    )
    points = friends_matrix(fixture["points"])

    rad = RadFriends(2)
    @test rad.need_centers
    check_friend_bound(rad, fixture["radfriends"], points)

    sup = SupFriends(2)
    @test sup.need_centers
    check_friend_bound(sup, fixture["supfriends"], points)
end

@testset "Friends radius helpers" begin
    fixture = JSON3.read(
        read(
            joinpath(@__DIR__, "reference", "python", "fixtures", "friends_core.json"),
            String,
        ),
    )
    points = friends_matrix(fixture["points"])

    rad = RadFriends(2)
    Dynesty.update!(rad, points; rng=MersenneTwister(11), use_clustering=false)
    rad_points_t = points * rad.axes_inv
    @test Dynesty._friends_leaveoneout_radius(rad_points_t, :balls) ≈
        Vector{Float64}(fixture["radfriends"]["loo_radius"]) rtol = 1e-8 atol = 1e-10

    sup = SupFriends(2)
    Dynesty.update!(sup, points; rng=MersenneTwister(11), use_clustering=false)
    sup_points_t = points * sup.axes_inv
    @test Dynesty._friends_leaveoneout_radius(sup_points_t, :cubes) ≈
        Vector{Float64}(fixture["supfriends"]["loo_radius"]) rtol = 1e-8 atol = 1e-10

    boot_ball = Dynesty._friends_bootstrap_radius(points, :balls; rng=MersenneTwister(1))
    boot_cube = Dynesty._friends_bootstrap_radius(points, :cubes; rng=MersenneTwister(1))
    @test boot_ball >= 0
    @test boot_cube >= 0
    @test_throws ArgumentError Dynesty._friends_leaveoneout_radius(points, :unknown)
end

@testset "Friends clustering covariance smoke" begin
    points = [0.10 0.10; 0.12 0.11; 0.80 0.80; 0.82 0.81; 0.50 0.20; 0.52 0.22]
    rad = RadFriends(2)
    Dynesty.update!(rad, points; rng=MersenneTwister(3), use_clustering=true)
    @test size(rad.ctrs) == size(points)
    @test all(Base.contains(rad, vec(points[i, :])) for i in axes(points, 1))

    sup = SupFriends(2)
    Dynesty.update!(sup, points; rng=MersenneTwister(4), use_clustering=true)
    @test size(sup.ctrs) == size(points)
    @test all(Base.contains(sup, vec(points[i, :])) for i in axes(points, 1))
end
