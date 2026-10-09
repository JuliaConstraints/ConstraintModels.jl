using Test
if !isdefined(@__MODULE__, :Benchmarks)
    include(joinpath(@__DIR__, "..", "src", "benchmarks", "Benchmarks.jl"))
end
using .Benchmarks

@testset "PDPTW workspace preserves complete validator results" begin
    data = PickupDeliveryProblem(2, 2, [0. 0.; 1 1; 2 1; -1 1; -2 1],
        [0, 1, -1, 1, -1], [0., 1, 2, 3, 4], [10., 3, 5, 6, 8],
        [0., 1, 1, 1, 1], [(2, 3), (4, 5)])
    instance = BenchmarkInstance("workspace", data)
    workspace = PDPTWValidationWorkspace()
    for n in 0:5, assignment in Iterators.product(ntuple(_ -> 2:5, n)...),
            split in 0:n
        values = collect(assignment)
        routes = [values[1:split], values[(split + 1):end]]
        expected = validate_solution(instance, routes)
        @test validate_solution(instance, routes, workspace) == expected
    end
    for routes in (
            Vector{Int}[], [[2, 3], [4, 5]], [[2.0, 3.0], [4, 5]],
            [[NaN, 3], [4, 5]], [[Inf, 3], [4, 5]], [[2.1, 3], [4, 5]],
            [[0, 3], [4, 5]], [[1, 3], [4, 5]], [[6, 3], [4, 5]],
            (2:3, 4:5),
        )
        saved = deepcopy(routes)
        for atol in (0.0, 1e-8, 1e-6)
            @test validate_solution(instance, routes, workspace; atol) ==
                  validate_solution(instance, routes; atol)
        end
        @test isequal(routes, saved)
    end
    for atol in (-1.0, 1e-5, NaN, Inf)
        @test_throws ArgumentError validate_solution(instance, [[2, 3]], workspace; atol)
    end
    @test_throws MethodError validate_solution(instance, ((2, 3), (4, 5)))
    @test_throws MethodError validate_solution(instance, ((2, 3), (4, 5)), workspace)

    previous = validate_solution(instance, [[3, 2], [4]], workspace)
    saved = deepcopy(previous)
    validate_solution(instance, [[2, 3], [4, 5]], workspace)
    @test previous == saved
    push!(previous.errors, :caller_owned)
    @test :caller_owned ∉ validate_solution(instance, [[3, 2], [4]], workspace).errors

    amount = typemax(Int)
    extreme = BenchmarkInstance("extreme", PickupDeliveryProblem(2, amount, zeros(5, 2),
        [0, amount, -amount, amount, -amount], zeros(5), ones(5), zeros(5),
        [(2, 3), (4, 5)]))
    for routes in ([[2, 3], [4, 5]], [[2, 4, 3, 5]], [[2, 2, 3, 4, 5]])
        @test validate_solution(extreme, routes, workspace) == validate_solution(extreme, routes)
    end
    @test validate_solution(instance, [[2, 3]], workspace) ==
          validate_solution(instance, [[2, 3]])

    consumed_valid(instance, routes, workspace) =
        validate_solution(instance, routes, workspace).valid
    function consumed_allocations(instance, routes, workspace)
        consumed_valid(instance, routes, workspace)
        return @allocated consumed_valid(instance, routes, workspace)
    end
    for routes in ([[2, 3], [4, 5]], [[3, 2], [4]])
        expected = validate_solution(instance, routes)
        @test consumed_valid(instance, routes, workspace) === expected.valid
        @test workspace.errors == expected.errors
        if expected.valid
            @test consumed_allocations(instance, routes, workspace) == 0
        end
        # Full results still own their diagnostics after a consumed call.
        retained = validate_solution(instance, routes, workspace)
        saved = deepcopy(retained)
        consumed_valid(instance, [[2, 3], [4, 5]], workspace)
        @test retained == saved
        @test retained.errors !== workspace.errors
    end
end
