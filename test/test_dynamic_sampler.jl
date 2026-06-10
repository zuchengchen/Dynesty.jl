using Dynesty
using JSON3
using Random
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

dynamic_prior_identity(u) = copy(u)
dynamic_loglike(v) = -sum(abs2, v .- 0.5)

function dynamic_saved_record()
    record = RunRecord(; dynamic=true)
    samples_u = [
        0.10 0.20
        0.22 0.25
        0.35 0.40
        0.48 0.52
        0.62 0.58
        0.76 0.70
    ]
    samples_v = copy(samples_u)
    logl = [-3.0, -2.4, -1.8, -1.1, -0.6, -0.2]
    logvol = [-0.15, -0.35, -0.70, -1.10, -1.55, -2.05]
    for i in eachindex(logl)
        append!(
            record,
            Dict(
                :id => i,
                :u => vec(samples_u[i, :]),
                :v => vec(samples_v[i, :]),
                :logl => logl[i],
                :logvol => logvol[i],
                :logwt => logl[i] + logvol[i],
                :logz => -3.0 + 0.4 * i,
                :logzvar => 0.01,
                :h => 0.1 * i,
                :nc => 1,
                :boundidx => 0,
                :it => i,
                :n => 4,
                :bounditer => 0,
                :scale => 1.0 + 0.1 * i,
                :blobs => nothing,
                :proposal_stats => nothing,
                :batch => 0,
                :batch_nlive => 4,
                :batch_logl_bounds => (-Inf, Inf),
            ),
        )
    end
    return record
end

function dynamic_parent_fixture(; rng=MersenneTwister(1234))
    return Dict{Symbol, Any}(
        :loglikelihood => dynamic_loglike,
        :prior_transform => dynamic_prior_identity,
        :ndim => 2,
        :ncdim => 2,
        :blob => false,
        :copy_inputs => false,
        :rng => rng,
        :sampling => :unif,
        :bounding => :single,
        :first_update => Dict(:min_ncall => 1, :min_eff => 100.0),
        :bound_bootstrap => 0,
        :bound_enlarge => 1.0,
        :saved_run => dynamic_saved_record(),
        :it => 7,
        :eff => 44.0,
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

@testset "Dynamic batch sampler configuration" begin
    parent = dynamic_parent_fixture(; rng=MersenneTwister(202))

    fresh = _configure_batch_sampler(parent, 4, 3; logl_bounds=(-Inf, -0.5))
    @test fresh isa ConfiguredBatchSampler
    @test fresh.sampler isa NestedSampler
    @test fresh.fresh_prior
    @test fresh.ncall == 4
    @test fresh.niter == 4
    @test fresh.logl_min == -Inf
    @test fresh.logl_max == -0.5
    @test fresh.join_index == 0
    @test isempty(fresh.selected_indices)
    @test length(fresh.first_points) == 4
    @test all(point -> point.worst < 0, fresh.first_points)
    @test all(point -> point.worst_it == 7, fresh.first_points)
    @test fresh.sampler.nlive == 4
    @test size(fresh.sampler.live_u) == (4, 2)
    @test fresh.sampler.bound_update_interval == 3
    @test fresh.sampler.save_bounds
    @test fresh.sampler.bound isa Ellipsoid
    @test fresh.sampler.dlv ≈ log(5 / 4)
    @test isempty(fresh.sampler.saved_run[:logl])

    parent_resample = dynamic_parent_fixture(; rng=MersenneTwister(303))
    finite = _configure_batch_sampler(
        parent_resample, 3, 2; logl_bounds=(-1.2, 0.1), save_bounds=false
    )
    @test !finite.fresh_prior
    @test finite.niter == 3
    @test finite.ncall >= 3
    @test finite.logl_min == -1.2
    @test finite.logl_max == 0.1
    @test length(finite.selected_indices) == 3
    @test all(4 .<= finite.selected_indices .<= 6)
    @test length(finite.first_points) == 3
    @test all(>(finite.logl_min), finite.sampler.live_logl)
    @test finite.sampler.nlive == 3
    @test finite.sampler.bound_update_interval == 2
    @test !finite.sampler.save_bounds
    @test finite.join_index == 4
    @test length(finite.sampler.saved_run[:logl]) == finite.join_index
    @test finite.sampler.saved_run[:logl] == parent_resample[:saved_run][:logl][1:4]

    parent_adjust = dynamic_parent_fixture(; rng=MersenneTwister(404))
    adjusted = _configure_batch_sampler(parent_adjust, 5, 2; logl_bounds=(-0.7, 0.2))
    @test !adjusted.fresh_prior
    @test adjusted.logl_min == -3.0
    @test length(adjusted.selected_indices) == 5
    @test all(2 .<= adjusted.selected_indices .<= 6)

    @test_throws ArgumentError _configure_batch_sampler(
        parent, 1, 2; logl_bounds=(-Inf, 0.0)
    )
    @test_throws ArgumentError _configure_batch_sampler(
        parent, 4, 0; logl_bounds=(-Inf, 0.0)
    )
    @test_throws ArgumentError _configure_batch_sampler(
        parent, 4, 2; logl_bounds=(0.0, -1.0)
    )
    @test_throws ErrorException _configure_batch_sampler(
        parent, 3, 2; logl_bounds=(1.0, 2.0)
    )
end
