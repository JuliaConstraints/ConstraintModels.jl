const MOI = MathOptInterface
const VI = MOI.VariableIndex

@testset "MOI: examples" begin
    m1 = CBLS.Optimizer()
    MOI.add_variable(m1)
    MOI.add_constraint(m1, VI(1), CBLS.DiscreteSet([1, 2, 3]))

    m2 = CBLS.Optimizer()
    MOI.add_constrained_variable(m2, CBLS.DiscreteSet([1, 2, 3]))
end
