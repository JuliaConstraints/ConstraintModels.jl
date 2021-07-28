function mincut(graph, source, sink, interdiction, ::Val{:raw})
    m = model(; kind=:cut)
    n = size(graph, 1)

    d = domain(0:n)

    separator = n + 1 # value that separate the two sides of the cut

    # Add variables:
    foreach(_ -> variable!(m, d), 0:n)

    # Extract error function from usual_constraint
    e1 = (x; param=nothing, dom_size=n + 1) -> error_f(
        usual_constraints[:ordered])(x; param, dom_size
    )
    e2 = (x; param=nothing, dom_size=n + 1) -> error_f(
        usual_constraints[:all_different])(x; param, dom_size
    )

    # Add constraint
    constraint!(m, e1, [source, separator, sink])
    constraint!(m, e2, 1:(n + 1))

    # Add objective
    objective!(m, (x...) -> o_mincut(graph, x...; interdiction))

    return m
end

function mincut(graph, source, sink, interdiction, ::Val{:JuMP})
    m = JuMP.Model(CBLS.Optimizer)
    n = size(graph, 1)
    separator = n + 1

    @variable(m, 0 ≤ X[1:separator] ≤ n, Int)

    @constraint(m, [X[source], X[separator], X[sink]] in Ordered())
    @constraint(m, X in AllDifferent())


    obj(x...) = o_mincut(graph, x...; interdiction)
    @objective(m, Min, ScalarFunction(obj))

    return m, X
end

"""
    mincut(graph; source, sink, interdiction =0, modeler = :JuMP)

Compute the minimum cut of a graph.

# Arguments:
- `graph`: Any matrix <: AbstractMatrix that describes the capacities of the graph
- `source`: Id of the source node; must be set
- `sink`: Id of the sink node; must be set
- `interdiction`: indicates the number of forbidden links
- `modeler`: Default to `:JuMP`.
"""
function mincut(graph; source, sink, interdiction =0, modeler = :JuMP)
    return mincut(graph, source, sink, interdiction, Val(modeler))
end
