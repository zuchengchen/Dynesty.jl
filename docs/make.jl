using Documenter
using Dynesty

makedocs(;
    modules=[Dynesty],
    sitename="Dynesty.jl",
    remotes=nothing,
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://github.com/dynesty-dev/dynesty.jl",
        edit_link=nothing,
        repolink="https://github.com/dynesty-dev/dynesty.jl",
    ),
    checkdocs=:exports,
    pages=[
        "Home" => "index.md",
        "Guides" => [
            "Quickstart" => "quickstart.md",
            "Dynamic Sampling" => "dynamic.md",
            "Errors" => "errors.md",
            "Plotting" => "plotting.md",
        ],
        "Manual" => [
            "Getting Started" => "manual/getting-started.md",
            "Dynamic Sampling" => "manual/dynamic.md",
            "Results and Persistence" => "manual/results-persistence.md",
            "Plotting Data" => "manual/plotting.md",
        ],
        "API Overview" => "api.md",
        "API" => [
            "Samplers" => "api/samplers.md",
            "Bounds" => "api/bounds.md",
            "Internal Samplers" => "api/internal-samplers.md",
            "Results" => "api/results.md",
            "Utilities" => "api/utilities.md",
            "Plotting" => "api/plotting.md",
            "Parallelism" => "api/parallel.md",
        ],
        "Migration Notes" => [
            "Examples" => "examples.md",
            "Compatibility" => "compatibility.md",
            "Persistence" => "persistence.md",
            "Testing" => "testing.md",
            "Performance" => "performance.md",
            "Source Snapshot" => "source_snapshot.md",
            "Migration Matrix" => "migration_matrix.md",
        ],
    ],
    warnonly=[:cross_references, :missing_docs],
)
