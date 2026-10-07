"Independent benchmark semantics; no solver, rounding or dataset download on import."
module Benchmarks

export BenchmarkInstance, PickupDeliveryProblem, read_benchmark, validate_solution
export SEMANTICS_VERSION
const SEMANTICS_VERSION = "pdptw-semantics-rebuild/1"

struct BenchmarkInstance{D}
    id::String
    data::D
    provenance::Dict{String,Any}
end
BenchmarkInstance(id, data; provenance=Dict{String,Any}()) =
    BenchmarkInstance(String(id), data, Dict{String,Any}(deepcopy(provenance)))

struct PickupDeliveryProblem
    vehicles::Int
    capacity::Int
    coordinates::Matrix{Float64}
    demand::Vector{Int}
    earliest::Vector{Float64}
    latest::Vector{Float64}
    service::Vector{Float64}
    pairs::Vector{Tuple{Int,Int}}

    function PickupDeliveryProblem(vehicles, capacity, coordinates, demand,
            earliest, latest, service, pairs)
        vehicles isa Integer && vehicles > 0 || throw(ArgumentError("positive integer fleet required"))
        capacity isa Integer && capacity >= 0 || throw(ArgumentError("nonnegative integer capacity required"))
        n = length(demand)
        n >= 3 && size(coordinates) == (n, 2) || throw(DimensionMismatch("depot and paired visits required"))
        all(length(x) == n for x in (earliest, latest, service)) || throw(DimensionMismatch("visit arrays"))
        all(x -> x isa Real && isfinite(x) && isinteger(x), demand) ||
            throw(ArgumentError("demands must be finite integers"))
        all(x -> x isa Real && isfinite(x), Iterators.flatten((coordinates, earliest, latest, service))) ||
            throw(ArgumentError("finite geometry and times required"))
        coords = Matrix{Float64}(coordinates)
        early, late, duration = Float64.(earliest), Float64.(latest), Float64.(service)
        all(isfinite, coords) && all(isfinite, early) && all(isfinite, late) && all(isfinite, duration) ||
            throw(ArgumentError("values must be representable as finite Float64"))
        all(early .<= late) && all(>=(0), duration) || throw(ArgumentError("invalid windows or service times"))
        loads = Int.(demand)
        loads[1] == 0 || throw(ArgumentError("the depot has zero demand"))
        requests = Tuple{Int,Int}[]
        for pair in pairs
            length(pair) == 2 && all(x -> x isa Integer && 2 <= x <= n, pair) ||
                throw(ArgumentError("pair visits must be integer customer indices"))
            pickup, delivery = Int.(pair)
            loads[pickup] > 0 && loads[delivery] == -loads[pickup] ||
                throw(ArgumentError("a request has opposite pickup/delivery demands"))
            push!(requests, (pickup, delivery))
        end
        covered = sort!([i for pair in requests for i in pair])
        covered == collect(2:n) || throw(ArgumentError("each customer belongs to exactly one request"))
        new(Int(vehicles), Int(capacity), coords, loads, early, late, duration, requests)
    end
end

"Validate original routes (1 is the implicit depot), independently from any internal score."
function validate_solution(instance::BenchmarkInstance{PickupDeliveryProblem}, routes; atol=1e-8)
    isfinite(atol) && 0 <= atol <= 1e-6 || throw(ArgumentError("invalid time tolerance"))
    d = instance.data
    n = length(d.demand)
    errors = Symbol[]
    normalized = Vector{Int}[]
    for route in routes
        if isempty(route) || !all(x -> x isa Real && isfinite(x) && isinteger(x) && 2 <= x <= n, route)
            push!(errors, :invalid_route)
            continue
        end
        push!(normalized, Int.(route))
    end
    length(normalized) <= d.vehicles || push!(errors, :fleet)
    route_of = zeros(Int, n)
    position = zeros(Int, n)
    counts = zeros(Int, n)
    distance = 0.0
    for (r, route) in enumerate(normalized)
        clock = d.earliest[1]
        load = big(0)
        previous = 1
        for (order, node) in enumerate(route)
            counts[node] += 1
            route_of[node], position[node] = r, order
            travel = hypot(d.coordinates[node, 1] - d.coordinates[previous, 1],
                d.coordinates[node, 2] - d.coordinates[previous, 2])
            distance += travel
            clock = max(d.earliest[node], clock + d.service[previous] + travel)
            clock <= d.latest[node] + atol || push!(errors, :time_window)
            load += d.demand[node]
            0 <= load <= d.capacity || push!(errors, :capacity)
            previous = node
        end
        travel = hypot(d.coordinates[previous, 1] - d.coordinates[1, 1],
            d.coordinates[previous, 2] - d.coordinates[1, 2])
        distance += travel
        clock + d.service[previous] + travel <= d.latest[1] + atol || push!(errors, :depot_return)
        iszero(load) || push!(errors, :nonzero_return_load)
    end
    all(==(1), counts[2:end]) || push!(errors, :service_uniqueness)
    for (pickup, delivery) in d.pairs
        route_of[pickup] == route_of[delivery] && route_of[pickup] != 0 || push!(errors, :same_route)
        position[pickup] < position[delivery] || push!(errors, :precedence)
    end
    isfinite(distance) || push!(errors, :nonfinite_distance)
    return (; valid=isempty(errors), objective=(vehicles=length(normalized), distance), errors=unique(errors))
end

"Strict SINTEF Li-Lim text reader; preserve source ids and use unrounded Euclidean distances."
function read_benchmark(io::IO, family::Symbol; id="li-lim")
    family === :li_lim || throw(ArgumentError("this reconstruction qualifies only :li_lim"))
    rows = [split(strip(line)) for line in eachline(io) if !isempty(strip(line))]
    !isempty(rows) && length(rows[1]) == 3 || throw(ArgumentError("expected fleet, capacity and speed header"))
    vehicles, capacity = parse.(Int, rows[1][1:2])
    speed = parse(Float64, rows[1][3])
    isfinite(speed) || throw(ArgumentError("finite speed header required"))
    nodes = rows[2:end]
    all(length(row) == 9 for row in nodes) || throw(ArgumentError("expected nine visit columns"))
    ids = [parse(Int, row[1]) for row in nodes]
    length(ids) >= 3 && first(ids) == 0 && allunique(ids) || throw(ArgumentError("unique source ids with depot 0 first"))
    indexes = Dict(node => index for (index, node) in enumerate(ids))
    coordinates = [parse(Float64, row[column]) for row in nodes, column in 2:3]
    demand = [parse(Int, row[4]) for row in nodes]
    earliest = [parse(Float64, row[5]) for row in nodes]
    latest = [parse(Float64, row[6]) for row in nodes]
    service = [parse(Float64, row[7]) for row in nodes]
    links = [(parse(Int, row[8]), parse(Int, row[9])) for row in nodes]
    links[1] == (0, 0) || throw(ArgumentError("depot links must be zero"))
    pairs = Tuple{Int,Int}[]
    for i in 2:length(nodes)
        pickup, delivery = links[i]
        if demand[i] > 0
            pickup == 0 && haskey(indexes, delivery) && delivery != 0 || throw(ArgumentError("invalid pickup links"))
            j = indexes[delivery]
            links[j] == (ids[i], 0) || throw(ArgumentError("nonreciprocal request links"))
            push!(pairs, (i, j))
        else
            delivery == 0 && haskey(indexes, pickup) && pickup != 0 || throw(ArgumentError("invalid delivery links"))
        end
    end
    data = PickupDeliveryProblem(vehicles, capacity, coordinates, demand, earliest, latest, service, pairs)
    BenchmarkInstance(id, data; provenance=Dict("semantics"=>SEMANTICS_VERSION,
        "source_node_ids"=>ids, "speed_header"=>speed, "speed_header_used"=>false,
        "travel"=>"travel time equals unrounded Euclidean Float64 distance"))
end

function read_benchmark(path::AbstractString, family::Symbol; id=splitext(basename(path))[1])
    open(io -> read_benchmark(io, family; id), path)
end

end
