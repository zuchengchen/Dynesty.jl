using Dynesty
using Random
using Test

@testset "LoglOutput and LogLikelihood" begin
    plain = LoglOutput(-2.5)
    @test plain.logl == -2.5
    @test !plain.has_blob
    @test Float64(plain) == -2.5
    @test plain < -2.0
    @test plain == -2.5

    with_blob = LoglOutput((-1.5, (; tag="ok")), true)
    @test with_blob.logl == -1.5
    @test with_blob.val == -1.5
    @test with_blob.has_blob
    @test with_blob.blob.tag == "ok"

    seen = Ref{Float64}(0)
    ll = LogLikelihood(2; copy_inputs=false) do x
        seen[] = x[1]
        return -sum(abs2, x)
    end
    x = [3.0, 4.0]
    @test ll(x).logl == -25.0
    @test seen[] == 3.0

    ll_blob = LogLikelihood(x -> (-sum(x), (:blob, copy(x))), 2; blob=true)
    out = ll_blob([1.0, 2.0])
    @test out.logl == -3.0
    @test out.blob[1] == :blob
end

@testset "Core utility functions" begin
    @test get_neff_from_logwt(log.([0.2, 0.3, 0.5])) ≈ 1 / sum(abs2, [0.2, 0.3, 0.5])
    @test unitcheck([0.1, 0.9])
    @test !unitcheck([0.0, 0.9])
    @test unitcheck([0.2, -0.25]; nonbounded=[true, false])
    @test !unitcheck([0.2, -0.75]; nonbounded=[true, false])

    u = [-0.9, 1.1, 2.9, 4.2]
    @test apply_reflect(u) ≈ [0.9, 0.9, 0.9, 0.2]

    samples = [1.0 2.0; 3.0 4.0; 5.0 8.0]
    weights = [0.2, 0.3, 0.5]
    mean, cov = mean_and_cov(samples, weights)
    @test mean ≈ [3.6, 5.6]
    @test cov ≈ [3.935483870967742 6.193548387096774; 6.193548387096774 10.06451612903226]

    rng = MersenneTwister(42)
    equal = resample_equal(samples, weights; rng)
    @test size(equal) == size(samples)
    @test all(row -> row in eachrow(samples), eachrow(equal))

    @test quantile([0.0, 10.0, 20.0], [0.0, 0.5, 1.0]) ≈ [0.0, 10.0, 20.0]
    @test quantile([0.0, 10.0, 20.0], 0.5; weights=[0.2, 0.3, 0.5]) ≈ 11.666666666666666
    @test_throws ArgumentError quantile([1.0], 1.5)

    @test logvol_prefactor(2) ≈ log(pi)
    @test from_python_indices([0, 2]; ndim=3) == [1, 3]
    @test_throws BoundsError from_python_indices(3; ndim=3)
end

@testset "Evidence integration" begin
    logl = [-3.0, -2.0, -1.0, -0.5]
    logvol = [-0.25, -0.75, -1.4, -2.3]
    ints = compute_integrals(; logl, logvol)
    @test length(ints.logwt) == 4
    @test ints.logz[end] ≈ -1.8203299158954742
    @test ints.logzvar[end] ≈ 0.5246688084315018
    @test ints.h[end] ≈ 0.5728020394911029

    stepped = progress_integration(-3.0, -2.0, -Inf, 0.0, 0.0, 0.25, 0.0)
    @test isfinite(stepped.logwt)
    @test isfinite(stepped.logz)
end
