function _academic_scope!(
    result,
    seen_ids,
    id,
    variables,
    minimum_size,
    provenance,
)
    scope = sort!(unique!(Int[variables...]))
    length(scope) >= minimum_size || return result
    local_id = Symbol(id)
    suffix = 1
    while local_id in seen_ids
        suffix += 1
        local_id = Symbol(id, '_', suffix)
    end
    push!(seen_ids, local_id)
    push!(result, LS.MetaVariable(local_id, scope; provenance))
    return result
end

"""
    academic_meta_variables(activities; distributions=(), learned=(), minimum_size=2)

Derive possibly overlapping repair scopes from instructor groups, student groups, distribution
constraints and learned scopes. The result contains only generic `LocalSearchSolvers.MetaVariable`
objects; all timetabling interpretation remains in ConstraintModels. Entries in `learned` are
`name => activity_identifiers` pairs.
"""
function academic_meta_variables(
    activities;
    distributions = (),
    learned = (),
    include_instructors::Bool = true,
    include_groups::Bool = true,
    include_distributions::Bool = true,
    minimum_size::Integer = 2,
)
    minimum_size > 0 || throw(ArgumentError("minimum_size must be positive"))
    local_activities = collect(activities)
    identifiers = Dict{Any,Int}(
        activity.id => index for (index, activity) in pairs(local_activities)
    )
    length(identifiers) == length(local_activities) || throw(
        ArgumentError("academic activity identifiers must be unique"),
    )
    result = LS.MetaVariable[]
    seen_ids = Set{Symbol}()
    if include_instructors
        scopes = Dict{Int,Vector{Int}}()
        for (activity, specification) in pairs(local_activities)
            for instructor in specification.instructors
                push!(get!(scopes, instructor, Int[]), activity)
            end
        end
        for instructor in sort!(collect(keys(scopes)))
            _academic_scope!(
                result,
                seen_ids,
                "instructor_$instructor",
                scopes[instructor],
                minimum_size,
                (source = :instructor, key = instructor),
            )
        end
    end
    if include_groups
        scopes = Dict{Int,Vector{Int}}()
        for (activity, specification) in pairs(local_activities)
            for group in specification.groups
                push!(get!(scopes, group, Int[]), activity)
            end
        end
        for group in sort!(collect(keys(scopes)))
            _academic_scope!(
                result,
                seen_ids,
                "group_$group",
                scopes[group],
                minimum_size,
                (source = :group, key = group),
            )
        end
    end
    if include_distributions
        for (index, specification) in enumerate(distributions)
            constraint = specification isa AcademicDistributionSpec ?
                         specification.constraint : specification
            constraint isa AcademicDistributionConstraint || throw(
                ArgumentError("unsupported academic distribution $(typeof(specification))"),
            )
            variables = [_activity_index(identifiers, id) for id in constraint.activities]
            _academic_scope!(
                result,
                seen_ids,
                "distribution_$index",
                variables,
                minimum_size,
                (source = :distribution, key = index, type = nameof(typeof(constraint))),
            )
        end
    end
    for learned_scope in learned
        learned_scope isa Pair || throw(
            ArgumentError("learned scopes must be name => activity_identifiers pairs"),
        )
        variables = [_activity_index(identifiers, id) for id in last(learned_scope)]
        _academic_scope!(
            result,
            seen_ids,
            "learned_$(first(learned_scope))",
            variables,
            minimum_size,
            (source = :learned, key = first(learned_scope)),
        )
    end
    return result
end

@testitem "Academic meta-variables preserve overlapping repair structure" default_imports =
    false begin
    import ConstraintModels as CM
    import LocalSearchSolvers as LS
    import Test: @test, @test_throws

    placement = CM.AcademicPlacement(1, 0, 1)
    activities = [
        CM.AcademicActivity(:a, 1, [placement]; instructors = [1], groups = [1]),
        CM.AcademicActivity(:b, 1, [placement]; instructors = [1], groups = [2]),
        CM.AcademicActivity(:c, 1, [placement]; instructors = [2], groups = [1]),
        CM.AcademicActivity(:d, 1, [placement]; instructors = [2], groups = [2]),
    ]
    distribution = CM.AcademicNotOverlap([:b, :c])
    variables = CM.academic_meta_variables(
        activities;
        distributions = [distribution],
        learned = [:community => [:a, :d]],
    )
    scopes = LS.scope.(variables)
    @test [1, 2] in scopes
    @test [1, 3] in scopes
    @test [2, 3] in scopes
    @test [1, 4] in scopes
    @test count(scope -> 1 in scope, scopes) >= 3

    learned = only(filter(variable -> variable.provenance.source == :learned, variables))
    move = LS.MetaMove(learned, [placement, placement])
    @test LS.affected_variables(move) == [1, 4]
    @test LS.move_depth(move) == 2
    @test_throws ArgumentError CM.academic_meta_variables(activities; minimum_size = 0)
    @test_throws ArgumentError CM.academic_meta_variables(
        activities; learned = [:bad => [:missing, :a]],
    )
end
