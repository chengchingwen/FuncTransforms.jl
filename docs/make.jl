using FuncTransforms
using Documenter

DocMeta.setdocmeta!(FuncTransforms, :DocTestSetup, :(using FuncTransforms); recursive=true)

makedocs(;
    modules=[FuncTransforms],
    authors="chengchingwen <chengchingwen214@gmail.com> and contributors",
    sitename="FuncTransforms.jl",
    format=Documenter.HTML(;
        canonical="https://chengchingwen.github.io/FuncTransforms.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/chengchingwen/FuncTransforms.jl",
    devbranch="main",
)
