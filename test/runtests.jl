using CBLS
using ConstraintModels
using Dictionaries
using JuMP
using LocalSearchSolvers
using MathOptInterface
using Test
using TestItemRunner

@testset "ConstraintModels.jl" begin
    include("instances.jl")
    include("raw_solver.jl")
    include("MOI_wrapper.jl")
    include("JuMP.jl")
    include("pdptw_semantics.jl")
end

@run_package_tests
