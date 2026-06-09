using Dynesty
using Test

@testset "Dynesty package skeleton" begin
    @test Dynesty isa Module
    @test get_citations() isa String
    @test citations() == get_citations()
    @test occursin("Speagle", get_citations())
    @test occursin("Skilling", get_citations())
    @test get_citations(format = :records) isa Tuple
    @test occursin("@article", get_citations(format = :bibtex))
    @test_throws ArgumentError get_citations(format = :unknown)
end

