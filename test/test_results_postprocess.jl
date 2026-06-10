using Dynesty
using JSON3
using Random
using Test

function matrix_from_fixture(rows)
    return reduce(vcat, [reshape(Vector{Float64}(row), 1, :) for row in rows])
end

function fixture_static_results_postprocess(fixture)
    input = fixture["input"]
    ints = compute_integrals(;
        logl=Vector{Float64}(input["logl"]), logvol=Vector{Float64}(input["logvol"])
    )
    return Results(;
        nlive=Int(input["nlive"]),
        niter=Int(input["niter"]),
        ncall=Vector{Int}(input["ncall"]),
        eff=50.0,
        samples=matrix_from_fixture(input["samples"]),
        samples_u=matrix_from_fixture(input["samples_u"]),
        samples_id=Vector{Int}(input["samples_id_julia_1_based"]),
        samples_it=Vector{Int}(input["samples_it"]),
        logwt=Vector{Float64}(input["logwt"]),
        logl=Vector{Float64}(input["logl"]),
        logvol=Vector{Float64}(input["logvol"]),
        logz=Vector{Float64}(input["logz"]),
        logzerr=Vector{Float64}(input["logzerr"]),
        h=ints.h,
        information=ints.h,
        blobs=["a", "b", "c", "d", "e", "f"],
        proposal_stats=fill(nothing, length(input["logl"])),
    )
end

function assert_summary_matches(res::Results, summary; rtol=1e-10, atol=1e-12)
    @test Dynesty.isdynamic(res) == Bool(summary["isdynamic"])
    @test res.niter == Int(summary["niter"])
    if haskey(summary, "nlive")
        @test res.nlive == Int(summary["nlive"])
    end
    @test res.ncall == Vector{Int}(summary["ncall"])
    @test res.samples ≈ matrix_from_fixture(summary["samples"]) rtol = rtol atol = atol
    @test res.samples_u ≈ matrix_from_fixture(summary["samples_u"]) rtol = rtol atol = atol
    @test res.samples_id == Vector{Int}(summary["samples_id_julia_1_based"])
    @test res.samples_it == Vector{Int}(summary["samples_it"])
    @test res.logl ≈ Vector{Float64}(summary["logl"]) rtol = rtol atol = atol
    @test res.logvol ≈ Vector{Float64}(summary["logvol"]) rtol = rtol atol = atol
    @test res.logwt ≈ Vector{Float64}(summary["logwt"]) rtol = rtol atol = atol
    @test res.logz ≈ Vector{Float64}(summary["logz"]) rtol = rtol atol = atol
    @test res.logzerr ≈ Vector{Float64}(summary["logzerr"]) rtol = rtol atol = atol
    if haskey(summary, "samples_n") && haskey(res, :samples_n)
        @test res.samples_n == Vector{Int}(summary["samples_n"])
    end
end

@testset "Results postprocessing fixtures" begin
    fixture_path = joinpath(
        @__DIR__, "reference", "python", "fixtures", "results_postprocess.json"
    )
    fixture = JSON3.read(read(fixture_path, String))
    rtol = Float64(fixture["rtol"])
    atol = Float64(fixture["atol"])
    res = fixture_static_results_postprocess(fixture)

    nsamps, samples_n = Dynesty._get_nsamps_samples_n(res)
    @test nsamps == length(res.logl)
    @test samples_n == fill(res.nlive, res.niter)

    fd = fixture["find_decrease"]
    mask, nlive_start, bounds = Dynesty._find_decrease(Vector{Int}(fd["samples_n"]))
    @test mask == Vector{Bool}(fd["mask"])
    @test nlive_start == Vector{Int}(fd["nlive_start"])
    @test [collect(bound) for bound in bounds] == [Vector{Int}(row) for row in fd["bounds_julia_half_open"]]

    logp_new = Vector{Float64}(fixture["reweight_logp_new"])
    reweighted = reweight_run(res, logp_new)
    @test reweighted.logwt ≈ Vector{Float64}(fixture["reweighted"]["logwt"]) rtol = rtol atol =
        atol
    @test reweighted.logz ≈ Vector{Float64}(fixture["reweighted"]["logz"]) rtol = rtol atol =
        atol
    @test reweighted.logzerr ≈ Vector{Float64}(fixture["reweighted"]["logzerr"]) rtol = rtol atol =
        atol
    @test reweighted.information ≈ Vector{Float64}(fixture["reweighted"]["information"]) rtol =
        rtol atol = atol
    rw_ints = compute_integrals(;
        logl=Float64.(res.logl), logvol=Float64.(res.logvol), reweight=logp_new .- res.logl
    )
    @test reweighted.h ≈ rw_ints.h rtol = rtol atol = atol
    @test reweighted.information ≈ res.information rtol = rtol atol = atol

    strands = unravel_run(res)
    @test length(strands) == Int(fixture["unravel"]["nstrands"])
    for (strand, expected) in zip(strands, fixture["unravel"]["strands"])
        assert_summary_matches(strand, expected; rtol, atol)
    end
    single_merged = merge_runs([strands[1]])
    @test !Dynesty.isdynamic(single_merged)
    @test single_merged.nlive == 1
    @test single_merged.niter == strands[1].niter - single_merged.nlive
    @test single_merged.logl ≈ strands[1].logl rtol = rtol atol = atol

    merged = merge_runs(strands)
    assert_summary_matches(merged, fixture["merged"]; rtol, atol)

    dynamic_static = Results(;
        niter=6,
        ncall=fill(1, 6),
        eff=100.0,
        samples=res.samples,
        samples_u=res.samples_u,
        samples_id=res.samples_id,
        samples_it=res.samples_it,
        samples_n=fill(3, 6),
        logwt=res.logwt,
        logl=res.logl,
        logvol=res.logvol,
        logz=res.logz,
        logzerr=res.logzerr,
        h=zeros(6),
        blobs=res.blobs,
        proposal_stats=res.proposal_stats,
    )
    checked = check_result_static(dynamic_static)
    assert_summary_matches(checked, fixture["checked_static"]; rtol, atol)
end

@testset "Results postprocessing stochastic invariants" begin
    logl(v) = -0.5 * sum(((v .- 0.5) ./ 0.1) .^ 2)
    sampler = NestedSampler(
        logl, identity, 2; nlive=20, bound=:none, sample=:unif, rng=MersenneTwister(1001)
    )
    run_nested!(sampler; maxiter=18, dlogz=nothing, add_live=true)
    res = results(sampler)

    jittered = jitter_run(res; rng=MersenneTwister(1002))
    @test length(jittered.logl) == length(res.logl)
    @test jittered.samples == res.samples
    @test all(diff(jittered.logvol) .< 0)
    @test all(isfinite, jittered.logz)

    resampled, idxs = resample_run(res; rng=MersenneTwister(1003), return_idx=true)
    @test length(idxs) == length(resampled.logl)
    @test size(resampled.samples, 2) == size(res.samples, 2)
    @test all(diff(resampled.logvol) .< 0)
    @test Dynesty.isdynamic(resampled)

    kld, realized = kld_error(res; rng=MersenneTwister(1004), return_new=true)
    @test length(kld) == length(res.logl)
    @test realized isa Results
    @test all(isfinite, kld)

    kld_resample = kld_error(res; error=:resample, rng=MersenneTwister(1005))
    @test !isempty(kld_resample)
    @test all(isfinite, kld_resample)

    @test_throws ArgumentError kld_error(res; error=:bad)
end
