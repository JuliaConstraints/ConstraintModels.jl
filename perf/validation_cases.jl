module ValidationCases
include(joinpath(@__DIR__, "..", "src", "benchmarks", "Benchmarks.jl"))
using .Benchmarks

# Isolate the former default inline metadata without a call-site barrier that
# also changes the keyword wrapper. Derive the identical current method body.
function workspace_definition(tree)
    tree isa Expr || return nothing
    if tree.head == :function
        signature = tree.args[1]
        if signature isa Expr && signature.head == :call &&
                signature.args[1] == :validate_solution &&
                any(arg -> arg isa Expr && arg.head == :(::) &&
                    last(arg.args) == :PDPTWValidationWorkspace, signature.args)
            return tree
        end
    end
    for child in tree.args
        definition = workspace_definition(child)
        definition === nothing || return definition
    end
    return nothing
end
definition = deepcopy(workspace_definition(Meta.parseall(read(
    joinpath(@__DIR__, "..", "src", "benchmarks", "Benchmarks.jl"), String))))
definition.args[1].args[1] = :validate_default
Core.eval(Benchmarks, definition)

# Original LC101 routes from deterministic Pilot insertion (five starts,
# seed 1), checked by the complete original validator before measurement.
const LC101_FEASIBLE_ROUTES = [
    [6, 4, 8, 9, 11, 12, 10, 7, 5, 3, 2, 76],
    [21, 25, 26, 28, 30, 31, 29, 27, 24, 104, 23, 22],
    [68, 66, 64, 63, 75, 73, 62, 65, 103, 69, 67, 70],
    [44, 43, 42, 41, 45, 47, 46, 49, 52, 102, 51, 53, 50, 48],
    [91, 88, 87, 84, 83, 85, 86, 89, 90, 92],
    [99, 97, 96, 95, 93, 94, 98, 107, 101, 100],
    [58, 56, 55, 54, 57, 59, 61, 60],
    [14, 18, 19, 20, 16, 17, 15, 13],
    [33, 34, 32, 36, 38, 39, 40, 37, 106, 35],
    [82, 79, 105, 77, 72, 71, 74, 78, 80, 81]
]

allocated(state) = validate_solution(state.instance, state.routes)
buffered(state) = validate_solution(state.instance, state.routes, state.workspace)
consumed(state) = validate_solution(state.instance, state.routes, state.workspace).valid
default_consumed(state) =
    Benchmarks.validate_default(state.instance, state.routes, state.workspace).valid

function validation(parameters)
    path = get(parameters, "instance", get(ENV, "JULIACONSTRAINTS_LILIM_INSTANCE", ""))
    isempty(path) && error("set JULIACONSTRAINTS_LILIM_INSTANCE to an original Li-Lim text file")
    instance = read_benchmark(path, :li_lim)
    feasible = get(parameters, "fixture", "") == "feasible-lc101"
    original = feasible ? deepcopy(LC101_FEASIBLE_ROUTES) :
               [[pickup, delivery] for (pickup, delivery) in instance.data.pairs]
    expected = validate_solution(instance, original)
    feasible && !expected.valid && error("LC101 fixture must be original-feasible")
    function prepare()
        routes = deepcopy(original)
        workspace = PDPTWValidationWorkspace()
        # Buffer growth and first compilation are preparation, not warm validation.
        validate_solution(instance, routes, workspace)
        return (; instance, routes, workspace)
    end
    method = get(parameters, "method", "workspace")
    operation = method == "allocated" ? allocated :
                method == "consumed" ? consumed :
                method == "default_consumed" ? default_consumed : buffered
    return (; prepare, operation,
        verify = (state, result) ->
            (result isa Bool ? result === expected.valid && state.workspace.errors == expected.errors :
                               result == expected) && state.routes == original)
end
end
