using Dynesty
using JSON3
using Test

function dynamic_matrix_from_fixture(rows)
    return reduce(vcat, [reshape(Vector{Float64}(row), 1, :) for row in rows])
end

function fixture_dynamic_results(fixture)
    input = fixture["input"]
    return Results(;
        niter=Int(input["niter"]),
        ncall=Vector{Int}(input["ncall"]),
        eff=100.0 * length(input["ncall"]) / sum(Vector{Int}(input["ncall"])),
        samples=dynamic_matrix_from_fixture(input["samples"]),
        samples_u=dynamic_matrix_from_fixture(input["samples_u"]),
        samples_id=Vector{Int}(input["samples_id_julia_1_based"]),
        samples_it=Vector{Int}(input["samples_it"]),
        samples_n=Vector{Int}(input["samples_n"]),
        logwt=Vector{Float64}(input["logwt"]),
        logl=Vector{Float64}(input["logl"]),
        logvol=Vector{Float64}(input["logvol"]),
        logz=Vector{Float64}(input["logz"]),
        logzerr=Vector{Float64}(input["logzerr"]),
        information=zeros(length(input["logl"])),
        blobs=fill(nothing, length(input["logl"])),
        proposal_stats=fill(nothing, length(input["logl"])),
    )
end

@testset "Dynamic sampler weighting fixtures" begin
    fixture_path = joinpath(
        @__DIR__, "reference", "python", "fixtures", "dynamic_core.json"
    )
    fixture = JSON3.read(read(fixture_path, String))
    rtol = Float64(fixture["rtol"])
    atol = Float64(fixture["atol"])
    res = fixture_dynamic_results(fixture)

    states = fixture["state_values"]
    @test Int(DynamicSamplerInit) == Int(states["INIT"])
    @test Int(DynamicSamplerLivePointsInit) == Int(states["LIVEPOINTSINIT"])
    @test Int(DynamicSamplerInBase) == Int(states["INBASE"])
    @test Int(DynamicSamplerBaseDone) == Int(states["BASE_DONE"])
    @test Int(DynamicSamplerInBatch) == Int(states["INBATCH"])
    @test Int(DynamicSamplerBatchDone) == Int(states["BATCH_DONE"])
    @test Int(DynamicSamplerInBaseAddLive) == Int(states["INBASEADDLIVE"])
    @test Int(DynamicSamplerInBatchAddLive) == Int(states["INBATCHADDLIVE"])
    @test Int(DynamicSamplerRunDone) == Int(states["RUN_DONE"])

    zweight, pweight = compute_weights(res)
    @test zweight ≈ Vector{Float64}(fixture["compute_weights"]["zweight"]) rtol = rtol atol =
        atol
    @test pweight ≈ Vector{Float64}(fixture["compute_weights"]["pweight"]) rtol = rtol atol =
        atol
    @test sum(zweight) ≈ 1.0 rtol = rtol atol = atol
    @test sum(pweight) ≈ 1.0 rtol = rtol atol = atol

    wargs = Dict(Symbol(k) => v for (k, v) in pairs(fixture["weight_function"]["args"]))
    bounds, weights = weight_function(res, wargs; return_weights=true)
    @test collect(bounds) ≈ Vector{Float64}(fixture["weight_function"]["bounds"]) rtol =
        rtol atol = atol
    @test weights[1] ≈ Vector{Float64}(fixture["weight_function"]["pweight"]) rtol = rtol atol =
        atol
    @test weights[2] ≈ Vector{Float64}(fixture["weight_function"]["zweight"]) rtol = rtol atol =
        atol
    @test weights[3] ≈ Vector{Float64}(fixture["weight_function"]["weight"]) rtol = rtol atol =
        atol
    @test weight_function(
        res; pfrac=wargs[:pfrac], maxfrac=wargs[:maxfrac], pad=wargs[:pad]
    ) == bounds

    sargs = Dict(Symbol(k) => v for (k, v) in pairs(fixture["stopping_function"]["args"]))
    flag, stop_vals = stopping_function(res, sargs; return_vals=true)
    @test flag == Bool(fixture["stopping_function"]["flag"])
    @test collect(stop_vals) ≈ [
        Float64(fixture["stopping_function"]["stop_post"]),
        Float64(fixture["stopping_function"]["stop_evid"]),
        Float64(fixture["stopping_function"]["stop"]),
    ] rtol = rtol atol = atol
    @test stopping_function(
        res;
        pfrac=sargs[:pfrac],
        evid_thresh=sargs[:evid_thresh],
        target_n_effective=sargs[:target_n_effective],
        n_mc=sargs[:n_mc],
        error=Symbol(sargs[:error]),
        approx=sargs[:approx],
    ) == flag

    @test_throws ArgumentError weight_function(res; pfrac=-0.1)
    @test_throws ArgumentError weight_function(res; maxfrac=1.1)
    @test_throws ArgumentError weight_function(res; pad=-1)
    @test_throws ArgumentError stopping_function(res; pfrac=1.2)
    @test_throws ArgumentError stopping_function(res; n_mc=-1)
    @test_throws ArgumentError stopping_function(res; error=:bad)
end
