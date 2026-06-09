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
    @test_throws ArgumentError Results(
        samples=[1.0 2.0], samples_u=[0.1 0.2], samples_id=[1]
    )
    @test_throws ArgumentError Results(
        samples=[1.0], samples_u=[0.1], samples_id=[1], logl=[0.0], nope=1
    )
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
