function qap(n, W, D, ::Val{:JuMP})
    model = JuMP.Model(CBLS.Optimizer)

    @variable(model, 1 ≤ X[1:n] ≤ n, Int)
    @constraint(model, X in AllDifferent())

    Σwd = p -> sum(sum(W[p[i], p[j]] * D[i, j] for j in 1:n) for i in 1:n)

    @objective(model, Min, ScalarFunction(Σwd))

    return model, X
end

"""
    qap(n, weigths, distances; modeler = :JuMP)

Modelize an instance of the Quadractic Assignment Problem with
- `n`: number of both facilities and locations
- `weights`: `Matrix` of the weights of each pair of facilities
- `distances`: `Matrix` of distances between locations
- `modeler`: Default to `:JuMP`. No other modeler available for now.

# From Wikipedia
There are a set of `n` facilities and a set of `n` locations. For each pair of locations, a distance is specified and for each pair of facilities a `weight` or flow is specified (e.g., the amount of supplies transported between the two facilities). The problem is to assign all facilities to different locations with the goal of minimizing the sum of the `distances` multiplied by the corresponding flows.
"""
qap(n, weigths, distances; modeler = :JuMP) = qap(n, weigths, distances, Val(modeler))
