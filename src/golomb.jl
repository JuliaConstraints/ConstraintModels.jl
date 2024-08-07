function golomb(n, L, ::Val{:raw})
    m = model(; kind=:golomb)

    # Add variables
    d = domain(0:L)
    foreach(_ -> variable!(m, d), 1:n)

    # Extract error function from usual_constraint
    e1 = (x; kargs...) -> error_f(USUAL_CONSTRAINTS[:all_different])(x; kargs...)
    e2 = (x; kargs...) -> error_f(USUAL_CONSTRAINTS[:all_equal])(x; kargs...)
    e3 = (x; kargs...) -> error_f(USUAL_CONSTRAINTS[:dist_different])(x; kargs...)

    # # Add constraints
    constraint!(m, e1, 1:n)
    constraint!(m, e2, 1:1)
    for i in 1:(n-1), j in (i+1):n, k in i:(n-1), l in (k+1):n
        (i, j) < (k, l) || continue
        constraint!(m, e3, [i, j, k, l])
    end

    # Add objective
    objective!(m, o_dist_extrema)

    return m
end

function golomb(n, L, ::Val{:JuMP})
    m = JuMP.Model(CBLS.Optimizer)

    @variable(m, 0 ≤ X[1:n] ≤ L, Int)

    @constraint(m, X in AllDifferent()) # different marks
    @constraint(m, X in Ordered()) # for output convenience, keep them ordered

    # No two pairs have the same length
    for i in 1:(n-1), j in (i+1):n, k in i:(n-1), l in (k+1):n
        (i, j) < (k, l) || continue
        @constraint(m, [X[i], X[j], X[k], X[l]] in DistDifferent())
    end

    # Add objective
    @objective(m, Min, ScalarFunction(maximum))

    return m, X
end

"""
    golomb(n, L=n²)

Model the Golomb problem of `n` marks on the ruler `0:L`. The `modeler` argument accepts :raw, and :JuMP (default), which refer respectively to the solver internal model, the MathOptInterface model, and the JuMP model.
"""
golomb(n, L=n^2; modeler=:JuMP) = golomb(n, L, Val(modeler))
