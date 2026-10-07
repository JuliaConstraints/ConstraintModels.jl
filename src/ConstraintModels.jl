module ConstraintModels

using CBLS
using ConstraintDomains
using Constraints
using Dictionaries
using EzXML
using JuMP
using LocalSearchSolvers
using TestItems

const LS = LocalSearchSolvers

import LocalSearchSolvers: Options

export chemical_equilibrium
export golomb
export qap
export magic_square
export mincut
export n_queens
export AcademicActivity
export AcademicDifferentDays
export AcademicDifferentRoom
export AcademicDifferentTime
export AcademicDifferentWeeks
export AcademicDistributionSpec
export AcademicMaxBlock
export AcademicMaxBreaks
export AcademicMaxDayLoad
export AcademicMaxDays
export AcademicMinGap
export AcademicNotOverlap
export AcademicOverlap
export AcademicPlacement
export AcademicPrecedence
export AcademicRoomTravel
export AcademicRoomUnavailable
export AcademicSameAttendees
export AcademicSameDays
export AcademicSameRoom
export AcademicSameStart
export AcademicSameTime
export AcademicSameWeeks
export AcademicWorkDay
export ITC2019ClassInfo
export ITC2019Instance
export TimetableConflictError
export TimetableConflictWeights
export academic_timetable
export academic_meta_variables
export parse_itc2019
export read_itc2019
export student_sectioning_supported
# export scheduling
export sudoku
export Benchmarks

include("benchmarks/Benchmarks.jl")
include("academic_timetabling.jl")
include("academic_meta_variables.jl")
include("itc2019.jl")
include("assignment.jl")
include("chemical_equilibrium.jl")
include("cut.jl")
include("golomb.jl")
include("magic_square.jl")
include("n_queens.jl")
# include("scheduling.jl")
include("sudoku.jl")

end
