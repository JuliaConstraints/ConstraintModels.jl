using CBLS
using ConstraintModels
using Dictionaries
using JuMP
using LocalSearchSolvers
using MathOptInterface
using Test

@testset "ConstraintModels.jl" begin
    include("instances.jl")
    include("raw_solver.jl")
    include("MOI_wrapper.jl")
    include("JuMP.jl")
end
