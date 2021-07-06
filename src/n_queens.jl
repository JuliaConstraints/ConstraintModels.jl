function n_queens(n, ::Val{:JuMP})
    model = JuMP.Model(CBLS.Optimizer)

    @variable(model, 1 ≤ Q[1:n] ≤ n, Int)
    @constraint(model, Q in AllDifferent())

    for i in 1:n, j in i + 1:n
        @constraint(model, [Q[i],Q[j]] in Predicate(x -> x[1] != x[2] + i - j))
        @constraint(model, [Q[i],Q[j]] in Predicate(x -> x[1] != x[2] + j - i))
    end

    return model, Q
end

"""
    n_queens(n; modeler = :JuMP)

Create a model for the n-queens problem with `n` queens. The `modeler` argument accepts :JuMP (default), which refer to the JuMP model.
"""
n_queens(n; modeler=:JuMP) = n_queens(n, Val(modeler))
