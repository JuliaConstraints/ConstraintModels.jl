using ConstraintModels
using Documenter

DocMeta.setdocmeta!(ConstraintModels, :DocTestSetup, :(using ConstraintModels); recursive=true)

makedocs(;
    modules=[ConstraintModels],
    authors="Jean-Francois Baffier",
    repo="https://github.com/JuliaConstraints/ConstraintModels.jl/blob/{commit}{path}#{line}",
    sitename="ConstraintModels.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaConstraints.github.io/ConstraintModels.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaConstraints/ConstraintModels.jl",
    devbranch="main",
)
