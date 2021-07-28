function scheduling(processing_times, due_dates, ::Val{:raw})
    m = model(; kind = :scheduling)
    n = length(processing_times) # number of jobs
    max_time = sum(processing_times)

    d = domain(0:max_time)
    foreach(_ -> variable!(m, d), 1:n) # C (1:n)
    foreach(_ -> variable!(m, d), 1:n) # S (n+1:2n)

    minus_eq_param(param) = x -> abs(x[1] - x[2] - param)
    less_than_param(param) = x -> abs(x[1] - param)
    sequential_tasks(x) = x[1] ≤ x[2] || x[3] ≤ x[4]

    for i in 1:n
        constraint!(m, minus_eq_param(processing_times[i]), [i, i + n])
        constraint!(m, less_than_param(due_dates[i]), [i])
    end
    for i in 1:n, j in 1:n
        i == j && continue
        constraint!(m, sequential_tasks, [i, j + n, j, i + n])
    end

    return m
end

function scheduling(processing_times, due_dates, ::Val{:JuMP})
    model = JuMP.Model(CBLS.Optimizer)
    n = length(processing_times) # number of jobs
    max_time = sum(processing_times)

    @variable(model, 0 ≤ C[1:n] ≤ max_time, Int) # completion
    @variable(model, 0 ≤ S[1:n] ≤ max_time, Int) # start

    for i in 1:n
        @constraint(model, [C[i], S[i]] in MinusEqualParam(processing_times[i]))
        @constraint(model, [C[i]] in LessThanParam(due_dates[i]))
    end
    for i in 1:n, j in 1:n
        i == j && continue
        @constraint(model, [C[i], S[j], C[j], S[i]] in SequentialTasks())
    end

    return model, C, S
end

"""
    scheduling(processing_time, due_date; modeler=:JuMP)

Create a model for the n-queens problem with `n` queens. The `modeler` argument accepts :JuMP (default), which refer to the JuMP model.

!!! warning

    The model seems to have a flaw. Needs to be investigated.

"""
scheduling(processing_times, due_dates; modeler=:JuMP) = scheduling(processing_times, due_dates, Val(modeler))
