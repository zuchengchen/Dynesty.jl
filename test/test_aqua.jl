using Aqua

@testset "Aqua quality checks" begin
    Aqua.test_all(
        Dynesty;
        # Test-only dependencies live in [extras]/[targets] because this package
        # still uses the root-project test target rather than test/Project.toml.
        project_extras=false,
    )
end
