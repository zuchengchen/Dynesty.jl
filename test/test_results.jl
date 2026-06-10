using Dynesty
using Random
using Test

function fixture_results()
    return Results(;
        samples=[1.0 2.0; 3.0 4.0; 5.0 6.0],
        samples_u=[0.1 0.2; 0.3 0.4; 0.5 0.6],
        samples_id=[1, 2, 3],
        logl=[-3.0, -2.0, -1.0],
        logwt=log.([0.1, 0.3, 0.6]),
        logz=[log(0.1), log(0.4), log(1.0)],
        logzerr=[0.3, 0.2, 0.1],
        nlive=3,
        niter=3,
        ncall=[1, 2, 3],
        eff=50.0,
    )
end

@testset "Results container" begin
    res = fixture_results()
    @test !Dynesty.isdynamic(res)
    @test res.samples == res[:samples]
    @test :proposal_stats in keys(res)
    @test res.proposal_stats === nothing
    @test importance_weights(res) ≈ [0.1, 0.3, 0.6]
    @test size(samples_equal(res; rng=MersenneTwister(1))) == (3, 2)

    updated = results_substitute(res, Dict(:logl => [-1.0, -2.0, -3.0]))
    @test updated.logl == [-1.0, -2.0, -3.0]
    @test res.logl == [-3.0, -2.0, -1.0]
    ignored = results_substitute(res, Dict(:h => zeros(3), :nope => 1))
    @test ignored.logl == res.logl
    @test_throws ArgumentError Results(
        samples=[1.0 2.0], samples_u=[0.1 0.2], samples_id=[1]
    )
    @test_throws ArgumentError Results(
        samples=[1.0], samples_u=[0.1], samples_id=[1], logl=[0.0], nope=1
    )

    aliased = Results(;
        samples=res.samples,
        samples_u=res.samples_u,
        samples_id=res.samples_id,
        logl=res.logl,
        nlive=res.nlive,
        niter=res.niter,
        ncall=res.ncall,
        eff=res.eff,
        blob=["a", "b", "c"],
        samples_bound=[0, 1, 1],
        batch=[0, 0, 1],
    )
    @test aliased.blobs == ["a", "b", "c"]
    @test aliased.blob == aliased.blobs
    @test aliased[:blob] == aliased.blobs
    @test haskey(aliased, :blob)
    @test aliased.boundidx == [0, 1, 1]
    @test aliased.samples_bound == aliased.boundidx
    @test aliased[:samples_bound] == aliased.boundidx
    @test aliased.samples_batch == [0, 0, 1]
    @test aliased.batch == aliased.samples_batch
    @test aliased[:batch] == aliased.samples_batch
end

@testset "RunRecord" begin
    record = RunRecord()
    append!(record, Dict(:id => 7, :logl => -1.0))
    @test record[:id] == [7]
    @test record[:logl] == [-1.0]
    @test_throws KeyError append!(record, Dict(:unknown => 1))

    dyn = RunRecord(dynamic=true)
    @test :batch in collect(keys(dyn))
end
