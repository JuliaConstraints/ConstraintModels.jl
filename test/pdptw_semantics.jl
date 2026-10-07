# Standalone reader/validator tests: no package installation or solver import.
using Test
if !isdefined(@__MODULE__, :Benchmarks)
    include(joinpath(@__DIR__, "..", "src", "benchmarks", "Benchmarks.jl"))
end
using .Benchmarks

@testset "Reconstructed PDPTW semantics" begin
    coordinates = [0. 0.; 1 1; 2 1; -1 1; -2 1]
    demands = [0, 1, -1, 1, -1]
    data = PickupDeliveryProblem(2, 1, coordinates, demands, zeros(5), fill(30., 5), zeros(5), [(2,3), (4,5)])
    instance = BenchmarkInstance("fractional", data)
    expected = 2 * (sqrt(2) + 1 + sqrt(5))
    result = validate_solution(instance, [[2,3], [4,5]])
    @test result.valid && result.objective.vehicles == 2
    @test result.objective.distance ≈ expected
    @test !isinteger(result.objective.distance)
    @test !validate_solution(instance, [[3,2], [4,5]]).valid
    @test !validate_solution(instance, [[2,4,3,5]]).valid
    @test !validate_solution(instance, [[2,3], [4]]).valid
    @test !validate_solution(instance, [[2,3], [2,3,4,5]]).valid
    @test !validate_solution(instance, [[2,3], [4,5], Int[]]).valid
    @test !validate_solution(instance, [[2.1,3], [4,5]]).valid
    @test !validate_solution(instance, [[NaN,3], [4,5]]).valid
    @test !validate_solution(instance, [[0,3], [4,5]]).valid
    @test !validate_solution(instance, [[1,2,3], [4,5]]).valid
    split = PickupDeliveryProblem(2, 2, zeros(5,2), demands, zeros(5), fill(30.,5), zeros(5), [(2,3),(4,5)])
    @test :same_route in validate_solution(BenchmarkInstance("split",split), [[2,5],[4,3]]).errors
    restricted = PickupDeliveryProblem(1, 1, coordinates, demands, zeros(5), fill(30.,5), zeros(5), [(2,3),(4,5)])
    @test :fleet in validate_solution(BenchmarkInstance("fleet",restricted), [[2,3],[4,5]]).errors
    early = PickupDeliveryProblem(2, 1, coordinates, demands, [0.,10,0,0,0], fill(30.,5), zeros(5), [(2,3),(4,5)])
    @test validate_solution(BenchmarkInstance("waiting",early), [[2,3],[4,5]]).valid
    late = PickupDeliveryProblem(2, 1, coordinates, demands, zeros(5), [1.,30,30,30,30], zeros(5), [(2,3),(4,5)])
    @test :depot_return in validate_solution(BenchmarkInstance("return",late), [[2,3],[4,5]]).errors
    @test_throws ArgumentError PickupDeliveryProblem(2,1,coordinates,demands,zeros(5),fill(30.,5),zeros(5),[(2,3),(2,5)])
    @test_throws ArgumentError PickupDeliveryProblem(2,1,coordinates,Float64[0,1.1,-1.1,1,-1],zeros(5),fill(30.,5),zeros(5),[(2,3),(4,5)])
    coordinates[2,1] = 999
    demands[2] = 999
    @test validate_solution(instance, [[2,3],[4,5]]).objective.distance ≈ expected

    text = "2 1 1\n0 0 0 0 0 30 0 0 0\n42 1 1 1 0 30 0 0 7\n7 2 1 -1 0 30 0 42 0\n"
    parsed = read_benchmark(IOBuffer(text), :li_lim)
    @test parsed.data.pairs == [(2,3)]
    @test parsed.provenance["source_node_ids"] == [0,42,7]
    @test validate_solution(parsed, [[2,3]]).valid
    @test_throws ArgumentError read_benchmark(IOBuffer(replace(text,"42 0"=>"12 0")), :li_lim)
    changed_speed = read_benchmark(IOBuffer(replace(text,"2 1 1"=>"2 1 2"; count=1)), :li_lim)
    @test !changed_speed.provenance["speed_header_used"]
    @test validate_solution(changed_speed, [[2,3]]).objective.distance ==
        validate_solution(parsed, [[2,3]]).objective.distance
end
