using Dynesty
using Test

@testset "Dynesty package skeleton" begin
    @test Dynesty isa Module
    @test get_citations() isa String
    @test citations() == get_citations()
    @test occursin("Speagle", get_citations())
    @test occursin("Skilling", get_citations())
    @test get_citations(format=:records) isa Tuple
    @test occursin("@article", get_citations(format=:bibtex))
    @test_throws ArgumentError get_citations(format=:unknown)
end

include("test_utils.jl")
include("test_results.jl")
include("test_results_postprocess.jl")
include("test_persistence.jl")
include("test_parallel.jl")
include("test_bounding_unitcube_ellipsoid.jl")
include("test_bounding_friends.jl")
include("test_internal_samplers.jl")
include("test_static_sampler.jl")
include("test_dynamic_sampler.jl")
include("test_crosscheck_fixtures.jl")
