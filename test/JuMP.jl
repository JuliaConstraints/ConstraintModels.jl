@testset "JuMP: constraints" begin
    m = Model(CBLS.Optimizer)

    err = _ -> 1.0
    concept = _ -> true

    @variable(m, X[1:10], DiscreteSet(1:4))

    @constraint(m, X in Error(err))
    @constraint(m, X in Predicate(concept))

    @constraint(m, X in AllDifferent())
    @constraint(m, X in AllEqual())
    @constraint(m, X in AllEqualParam(2))
    @constraint(m, X in AlwaysTrue())
    @constraint(m, X[1:4] in DistDifferent())
    @constraint(m, X[1:2] in Eq())
    @constraint(m, X in Ordered())
end

@testset "JuMP: sudoku 9x9" begin
    m, X = sudoku(3)
    optimize!(m)
    solution_ = value.(X)
    @info solution_summary(m)
    display(solution_, Val(:sudoku))
end

@testset "JuMP: golomb(5)" begin
    m, X = golomb(5)
    optimize!(m)
    @info solution_summary(m)
    @info "JuMP: golomb(5)" value.(X)
end

@testset "JuMP: magic_square(3)" begin
    m, X = magic_square(3)
    optimize!(m)
    @info solution_summary(m)
    @info "JuMP: magic_square(3)" value.(X)
end

@testset "JuMP: n_queens(5)" begin
    m, X = n_queens(5)
    optimize!(m)
    @info solution_summary(m)
    @info "JuMP: n_queens(5)" value.(X)
end

@testset "JuMP: qap(12)" begin
    m, X = qap(12, qap_weights, qap_distances)
    optimize!(m)
    @info solution_summary(m)
    @info "JuMP: qap(12)" value.(X)
end

@testset "JuMP: basic opt" begin
    model = Model(CBLS.Optimizer)
    set_optimizer_attribute(model, "iteration", 100)
    @test get_optimizer_attribute(model, "iteration") == 100
    set_time_limit_sec(model, 5.0)
    @test time_limit_sec(model) == 5.0

    @variable(model, x in DiscreteSet(0:20))
    @variable(model, y in DiscreteSet(0:20))

    @constraint(model, [x,y] in Predicate(v -> 6v[1] + 8v[2] >= 100 ))
    @constraint(model, [x,y] in Predicate(v -> 7v[1] + 12v[2] >= 120 ))

    objFunc = v -> 12v[1] + 20v[2]
    @objective(model, Min, ScalarFunction(objFunc))

    optimize!(model)
    @info solution_summary(model)
    @info "JuMP: basic opt" value(x) value(y) (12*value(x)+20*value(y))
end

@testset "JuMP: Chemical equilibrium" begin
    m, X = chemical_equilibrium(atoms_compounds, elements_weights, standard_free_energy)
    # set_optimizer_attribute(m, "iteration", 10000)
    # set_time_limit_sec(m, 120.0)
    optimize!(m)
    @info solution_summary(m)
    @info "JuMP: $compounds_names ⟺ $mixture_name" value.(X)
end

@testset "JuMP: Scheduling" begin
    model, completion_times, start_times = scheduling(processing_times, due_times)
    optimize!(model)
    @info solution_summary(model)
    @info "JuMP: scheduling" value.(start_times) value.(completion_times) processing_times due_times
    @info (value.(start_times)+processing_times == value.(completion_times))
end
