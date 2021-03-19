using CBLS
using ConstraintModels
using Dictionaries
using JuMP
using LocalSearchSolvers
using MathOptInterface
using Test

@testset "ConstraintModels.jl" begin
    include("raw_solver.jl")
    include("MOI_wrapper.jl")
    include("JuMP.jl")
end
