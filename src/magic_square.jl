function magic_square(n, ::Val{:JuMP})
    N = n^2
    model = JuMP.Model(CBLS.Optimizer)
    magic_constant = n * (N + 1) / 2

    @variable(model, 1 ≤ X[1:n, 1:n] ≤ N, Int)
    @constraint(model, vec(X) in AllDifferent())

    for i in 1:n
        @constraint(model, X[i, :] in AllEqual(; val=magic_constant))
        @constraint(model, X[:, i] in AllEqual(; val=magic_constant))
    end
    @constraint(model, [X[i, i] for i in 1:n] in AllEqual(; val=magic_constant))
    @constraint(model, [X[i, n+1-i] for i in 1:n] in AllEqual(; val=magic_constant))

    return model, X
end

"""
    magic_square(n; modeler = :JuMP)

Create a model for the magic square problem of order `n`. The `modeler` argument accepts :JuMP (default), which refer to the solver the JuMP model.
"""
magic_square(n; modeler=:JuMP) = magic_square(n, Val(modeler))
