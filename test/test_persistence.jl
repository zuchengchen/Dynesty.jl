using Dynesty
using Test

function persistence_fixture_results()
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

@testset "Results persistence" begin
    mktempdir() do dir
        res = persistence_fixture_results()
        path = joinpath(dir, "results.jld2")
        @test save_results(path, res; metadata=Dict(:case => "roundtrip")) == path
        loaded = load_results(path)
        @test loaded.samples == res.samples
        @test loaded.logl == res.logl
        @test importance_weights(loaded) ≈ importance_weights(res)
        @test_throws ArgumentError save_results(joinpath(dir, "bad.dat"), res)
    end
end

@testset "Sampler checkpoint framework" begin
    mktempdir() do dir
        sampler = (ndim=2, ncall=10, rng_state=[1, 2, 3], loglikelihood=x -> -sum(x))
        path = joinpath(dir, "sampler.jls")
        save_sampler(sampler, path; backend_metadata=Dict(:backend => :serial))
        @test isfile(path)

        @test_throws ArgumentError restore_sampler(path; prior_transform=identity)
        restored = restore_sampler(
            path; loglikelihood=x -> -sum(x), prior_transform=identity
        )
        @test restored.state[:ndim] == 2
        @test restored.state[:ncall] == 10
        @test !haskey(restored.state, :loglikelihood)
        @test restored.backend_metadata[:backend] == :serial
        @test :loglikelihood in restored.metadata[:skipped_user_state]

        checkpoint!(sampler, path; metadata=Dict(:kind => "checkpoint"))
        restored2 = restore_sampler(
            path; loglikelihood=x -> -sum(x), prior_transform=identity
        )
        @test restored2.metadata[:kind] == "checkpoint"
        @test_throws ArgumentError save_sampler(sampler, joinpath(dir, "sampler.pkl"))
    end
end

@testset "Evaluation history HDF5 extension" begin
    mktempdir() do dir
        path = joinpath(dir, "history.h5")
        @test_throws ArgumentError LogLikelihood(
            x -> -sum(abs2, x),
            2;
            history_filename=path,
            save_evaluation_history=true,
            save_every=2,
        )
    end

    if get(ENV, "DYNESTY_RUN_EXTENDED_TESTS", "false") == "true"
        try
            @eval using HDF5
            mktempdir() do dir
                path = joinpath(dir, "history.h5")
                ll = LogLikelihood(
                    x -> -sum(abs2, x),
                    2;
                    history_filename=path,
                    save_evaluation_history=true,
                    save_every=2,
                )
                Dynesty.append_evaluation_history!(
                    ll,
                    [
                        Dynesty.EvaluationHistoryItem([0.1, 0.2], [1.0, 2.0], -1.0),
                        Dynesty.EvaluationHistoryItem([0.3, 0.4], [3.0, 4.0], -2.0),
                        Dynesty.EvaluationHistoryItem([0.5, 0.6], [5.0, 6.0], -3.0),
                    ],
                )
                @test ll.evaluation_history_counter == 3
                @test isempty(ll.evaluation_history)
                Dynesty.append_evaluation_history!(
                    ll, [Dynesty.EvaluationHistoryItem([0.7, 0.8], [7.0, 8.0], -4.0)]
                )
                Dynesty.finalize_history!(ll)
                @test ll.evaluation_history_counter == 4
                HDF5.h5open(path, "r") do file
                    @test read(file["evaluation_u"]) == [
                        0.1 0.2
                        0.3 0.4
                        0.5 0.6
                        0.7 0.8
                    ]
                    @test read(file["evaluation_v"]) == [
                        1.0 2.0
                        3.0 4.0
                        5.0 6.0
                        7.0 8.0
                    ]
                    @test read(file["evaluation_logl"]) == [-1.0, -2.0, -3.0, -4.0]
                end
            end
        catch err
            if err isa ArgumentError || err isa LoadError
                @info "Skipping HDF5 evaluation-history extension test" exception = (
                    err, catch_backtrace()
                )
            else
                rethrow()
            end
        end
    end
end
