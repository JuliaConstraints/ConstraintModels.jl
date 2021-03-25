function chemical_equilibrium(A, B, C)
    model = JuMP.Model(CBLS.Optimizer)

    n = length(C)
    m = length(B)

    # Add the number of moles per compound (continuous interval)
    @variable(model, 0 ≤ X[1:n] ≤ maximum(B))

    # mass_conservation function
    conserve = i -> (x -> sum(A[:, i] .* x) == B[i])

    for i in 1:m
        @constraint(model, X in Predicate(conserve(i)))
    end

    # computes the total energy freed by the reaction
    free_energy = x -> sum(j -> x[j] * (C[j] + log(x[j] / sum(x))))

    @objective(model, Min, ScalarFunction(free_energy))

    return model, X
end
