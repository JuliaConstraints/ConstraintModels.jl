module ConstraintModels

using CBLS
using Constraints
using Dictionaries
using JuMP
using LocalSearchSolvers

const LS = LocalSearchSolvers

import LocalSearchSolvers: Options

export chemical_equilibrium
export golomb
export qap
export magic_square
export mincut
export n_queens
# export scheduling
export sudoku

include("assignment.jl")
include("chemical_equilibrium.jl")
include("cut.jl")
include("golomb.jl")
include("magic_square.jl")
include("n_queens.jl")
# include("scheduling.jl")
include("sudoku.jl")

end
