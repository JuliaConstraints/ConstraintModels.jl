module ValidationCases
include(joinpath(@__DIR__, "..", "src", "benchmarks", "Benchmarks.jl"))
using .Benchmarks

allocated(state) = validate_solution(state.instance, state.routes)
buffered(state) = validate_solution(state.instance, state.routes, state.workspace)

function validation(parameters)
    path = get(parameters, "instance", get(ENV, "JULIACONSTRAINTS_LILIM_INSTANCE", ""))
    isempty(path) && error("set JULIACONSTRAINTS_LILIM_INSTANCE to an original Li-Lim text file")
    instance = read_benchmark(path, :li_lim)
    original = [[pickup, delivery] for (pickup, delivery) in instance.data.pairs]
    expected = validate_solution(instance, original)
    function prepare()
        routes = deepcopy(original)
        workspace = PDPTWValidationWorkspace()
        # Buffer growth and first compilation are preparation, not warm validation.
        validate_solution(instance, routes, workspace)
        return (; instance, routes, workspace)
    end
    operation = get(parameters, "method", "workspace") == "allocated" ? allocated : buffered
    return (; prepare, operation,
        verify = (state, result) -> result == expected && state.routes == original)
end
end
