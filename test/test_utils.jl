using Dynesty
using JSON3
using Random
using Test

utils_matrix_from_json(rows) =
    reduce(vcat, [reshape(Vector{Float64}(row), 1, :) for row in rows])

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
    fixture = JSON3.read(
        read(
            joinpath(@__DIR__, "reference", "python", "fixtures", "utils_core.json"), String
        ),
    )
    @test get_neff_from_logwt(log.([0.2, 0.3, 0.5])) ≈ 1 / sum(abs2, [0.2, 0.3, 0.5])
    @test unitcheck([0.1, 0.9])
    @test !unitcheck([0.0, 0.9])
    @test unitcheck([0.2, -0.25]; nonbounded=[true, false])
    @test !unitcheck([0.2, -0.75]; nonbounded=[true, false])

    unit = fixture["unitcheck"]
    @test unitcheck(Vector{Float64}(unit["inside"])) == unit["inside_value"]
    @test unitcheck(Vector{Float64}(unit["edge"])) == unit["edge_value"]
    @test unitcheck(
        Vector{Float64}(unit["nonbounded_u"]); nonbounded=Vector{Bool}(unit["nonbounded"])
    ) == unit["nonbounded_value"]
    @test unitcheck(
        Vector{Float64}(unit["nonbounded_bad_u"]);
        nonbounded=Vector{Bool}(unit["nonbounded"]),
    ) == unit["nonbounded_bad_value"]

    nonbounded = fixture["get_nonbounded"]
    @test get_nonbounded(
        nonbounded["ndim"],
        Vector{Int}(nonbounded["periodic_julia_1_based"]),
        Vector{Int}(nonbounded["reflective_julia_1_based"]),
    ) == Vector{Bool}(nonbounded["value"])
    @test get_nonbounded(3, nothing, nothing) === nothing
    @test get_nonbounded(3, [false, true, false], nothing) == [true, false, true]
    @test_throws ArgumentError get_nonbounded(3, [1], [1])
    @test_throws BoundsError get_nonbounded(3, [0], nothing)
    @test from_python_indices(nonbounded["periodic_python_0_based"]; ndim=4) ==
        Vector{Int}(nonbounded["periodic_julia_1_based"])

    rng = get_random_generator(123)
    @test rng isa MersenneTwister
    @test rand(get_random_generator(123), 3) == rand(get_random_generator(123), 3)
    existing_rng = MersenneTwister(321)
    @test get_random_generator(existing_rng) === existing_rng
    @test get_random_generator() isa AbstractRNG
    @test_throws ArgumentError get_random_generator("seed")

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

    resample_fixture = fixture["resample_equal"]
    resample_samples = utils_matrix_from_json(resample_fixture["samples"])
    resample_weights = Vector{Float64}(resample_fixture["weights"])
    equal_a = resample_equal(
        resample_samples, resample_weights; rng=MersenneTwister(resample_fixture["seed"])
    )
    equal_b = resample_equal(
        resample_samples, resample_weights; rng=MersenneTwister(resample_fixture["seed"])
    )
    @test equal_a == equal_b
    @test size(equal_a) == size(resample_samples)
    @test all(row -> row in eachrow(resample_samples), eachrow(equal_a))

    @test quantile([0.0, 10.0, 20.0], [0.0, 0.5, 1.0]) ≈ [0.0, 10.0, 20.0]
    @test quantile([0.0, 10.0, 20.0], 0.5; weights=[0.2, 0.3, 0.5]) ≈ 11.666666666666666
    quant = fixture["quantile"]
    @test quantile(Vector{Float64}(quant["x"]), Vector{Float64}(quant["q"])) ≈
        Vector{Float64}(quant["unweighted"]) rtol = quant["rtol"] atol = quant["atol"]
    @test quantile(
        Vector{Float64}(quant["x"]),
        Vector{Float64}(quant["q"]);
        weights=Vector{Float64}(quant["weights"]),
    ) ≈ Vector{Float64}(quant["weighted"]) rtol = quant["rtol"] atol = quant["atol"]
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

    fixture = JSON3.read(
        read(
            joinpath(@__DIR__, "reference", "python", "fixtures", "utils_core.json"), String
        ),
    )
    progress = fixture["progress_integration"]
    progress_args = Vector{Float64}(progress["args"])
    stepped_fixture = progress_integration(progress_args...)
    @test stepped_fixture.logwt ≈ progress["logwt"] rtol = progress["rtol"] atol = progress["atol"]
    @test stepped_fixture.logz ≈ progress["logz"] rtol = progress["rtol"] atol = progress["atol"]
    @test stepped_fixture.logzvar ≈ progress["logzvar"] rtol = progress["rtol"] atol = progress["atol"]
    @test stepped_fixture.h ≈ progress["h"] rtol = progress["rtol"] atol = progress["atol"]
end

@testset "Progress display helpers" begin
    timer = DelayTimer(2.0; now=10.0)
    @test !is_time!(timer; now=11.0)
    @test is_time!(timer; now=12.1)
    @test timer.last_time == 12.1
    @test_throws ArgumentError DelayTimer(-1)

    itresult = (;
        loglstar=-3.25,
        logz=-1.75,
        delta_logz=0.42,
        logzvar=0.09,
        bounditer=2,
        nc=7,
        eff=12.3456,
    )
    args = get_print_fn_args(itresult, 14, 99; dlogz=0.1, logl_min=-5.0, logl_max=1.0)
    @test args isa PrintFnArgs
    @test args.niter == 14
    @test any(contains("bound: 2"), args.long_str)
    @test any(contains("eff(%): 12.346"), args.long_str)
    @test any(contains("dlogz:"), args.long_str)

    io = IOBuffer()
    line = print_fn_fallback(itresult, 14, 99; dlogz=0.1, io, columns=200)
    @test String(take!(io)) == "\r" * line
    @test contains(line, "iter: 14")
    @test contains(line, "ncall: 99")

    _, default_cb = get_print_func(nothing, true; io=IOBuffer())
    @test default_cb isa Function
    called = Ref(false)
    custom = (args...; kwargs...) -> (called[] = true)
    _, custom_cb = get_print_func(custom, false)
    custom_cb(itresult, 1, 2)
    @test called[]
end
