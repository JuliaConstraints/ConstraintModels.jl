function qap(n, W, D, ::Val{:JuMP})
    model = JuMP.Model(CBLS.Optimizer)

    @variable(model, 1 ≤ X[1:n] ≤ n, Int)
    @constraint(model, X in AllDifferent())

    Σwd = p -> sum(sum(W[p[i], p[j]] * D[i, j] for j in 1:n) for i in 1:n)

    @objective(model, Min, ScalarFunction(Σwd))

    return model, X
end

qap(n, weigths, distances; modeler = :JuMP) = qap(n, weigths, distances, Val(modeler))
