function chemical_equilibrium(A, B, C, ::Val{:JuMP})
    model = JuMP.Model(CBLS.Optimizer)

    n = length(C)
    m = length(B)

    # Add the number of moles per compound (continuous interval)
    @variable(model, 0 ≤ X[1:n] ≤ maximum(B))

    # mass_conservation function
    conserve = i -> (x ->
        begin
            δ = abs(sum(A[:, i] .* x) - B[i])
            return δ ≤ 1.e-6 ? 0. : δ
        end
    )

    for i in 1:m
        @constraint(model, X in Error(conserve(i)))
    end

    # computes the total energy freed by the reaction
    free_energy = x -> sum(j -> x[j] * (C[j] + log(x[j] / sum(x))))

    @objective(model, Min, ScalarFunction(free_energy))

    return model, X
end

"""
    chemical_equilibrium(atoms_compounds, elements_weights, standard_free_energy; modeler = :JuMP)

!!! warning

    Even the structure to model problems with continuous domains is available, the default solver is not yet equiped to solve such problems efficiently.

# From Wikipedia

In a chemical reaction, chemical equilibrium is the state in which both the reactants and products are present in concentrations which have no further tendency to change with time, so that there is no observable change in the properties of the system. This state results when the forward reaction proceeds at the same rate as the reverse reaction. The reaction rates of the forward and backward reactions are generally not zero, but they are equal. Thus, there are no net changes in the concentrations of the reactants and products. Such a state is known as dynamic equilibrium.
"""
function chemical_equilibrium(
    atoms_compounds,
    elements_weights,
    standard_free_energy;
    modeler = :JuMP,
)
    return chemical_equilibrium(
        atoms_compounds,
        elements_weights,
        standard_free_energy,
        Val(modeler)
    )
end
