function scheduling(processing_times, due_dates, ::Val{:JuMP})
    model = JuMP.Model(CBLS.Optimizer)
    n = length(processing_times) # number of jobs
    max_time = sum(processing_times)

    minus_eq_param(param) = x -> x[1] - x[2] == param
    less_than_param(param) = x -> x[1] ≤ param
    sequential_tasks(x) = x[1] ≤ x[2] || x[3] ≤ x[4]


    @variable(model, 0 ≤ C[1:n] ≤ max_time, Int) # completion
    @variable(model, 0 ≤ S[1:n] ≤ max_time, Int) # start

    @constraint(model, C in AllDifferent())
    @constraint(model, S in AllDifferent())

    for i in 1:n
        @constraint(model, [C[i], S[i]] in Predicate(minus_eq_param(processing_times[i])))
        # @constraint(model, [C[i]] in Predicate(less_than_param(due_dates[i])))
    end
    # for i in 1:n, j in 1:n
    #     i == j && continue
    #     @constraint(model, [C[i], S[j], C[j], S[i]] in Predicate(sequential_tasks))
    # end

    return model, C, S
end

"""
    scheduling(processing_time, due_date; modeler=:JuMP)

Create a model for the n-queens problem with `n` queens. The `modeler` argument accepts :JuMP (default), which refer to the JuMP model.
"""
scheduling(processing_times, due_dates; modeler=:JuMP) = scheduling(processing_times, due_dates, Val(modeler))
