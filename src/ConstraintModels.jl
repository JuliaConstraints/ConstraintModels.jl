module ConstraintModels

using CBLS
using Constraints
using Dictionaries
using JuMP
using LocalSearchSolvers

const LS = LocalSearchSolvers

import LocalSearchSolvers: Options

export qap
export mincut
export golomb
export magic_square
export n_queens
export sudoku

include("assignment.jl")
include("cut.jl")
include("golomb.jl")
include("magic_square.jl")
include("n_queens.jl")
include("sudoku.jl")

end
