function chemical_equilibrium(n, A, C)
    model = JuMP.Model(CBLS.Optimizer)

    # Add the number of moles per compound (continuous interval)
    @variable(model, X[1:n], DiscreteSet(1:n))

    return model, X
end
