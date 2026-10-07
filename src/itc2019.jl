"""Course-hierarchy metadata preserved by the ITC 2019 adapter."""
struct ITC2019ClassInfo
    id::String
    course::String
    configuration::String
    subpart::String
    parent::Union{Nothing,String}
    room_required::Bool
    limit::Int
end

"""
    ITC2019Instance

Lossless scheduling carrier for an ITC 2019 problem. `activities` contains the class
placement decisions consumed by CBLS. The course hierarchy and student requests remain
available explicitly for a separate sectioning layer; they are never silently converted to
fixed conflict groups.
"""
struct ITC2019Instance
    name::String
    day_count::Int
    week_count::Int
    slots_per_day::Int
    optimization_weights::NamedTuple{
        (:time, :room, :distribution, :student),
        NTuple{4,Int},
    }
    room_ids::Vector{String}
    room_capacities::Vector{Int}
    activities::Vector{AcademicActivity{String}}
    distributions::Vector{AcademicDistributionSpec}
    room_unavailable::Vector{AcademicRoomUnavailable}
    room_travel::Vector{AcademicRoomTravel}
    class_info::Vector{ITC2019ClassInfo}
    student_courses::Dict{String,Vector{String}}
end

student_sectioning_supported(::ITC2019Instance) = false

function _itc_attribute(node::EzXML.Node, name::AbstractString)
    haskey(node, name) || throw(
        ArgumentError("<$(EzXML.nodename(node))> requires attribute $name"),
    )
    return String(node[name])
end

function _itc_integer_attribute(node, name)
    value = tryparse(Int, _itc_attribute(node, name))
    isnothing(value) && throw(
        ArgumentError("<$(EzXML.nodename(node))> attribute $name must be an integer"),
    )
    return value
end

function _itc_optional_integer_attribute(node, name, default = 0)
    haskey(node, name) || return default
    value = tryparse(Int, String(node[name]))
    isnothing(value) && throw(
        ArgumentError("<$(EzXML.nodename(node))> attribute $name must be an integer"),
    )
    return value
end

function _itc_child(node::EzXML.Node, name::AbstractString; required = true)
    for child in EzXML.eachelement(node)
        EzXML.nodename(child) == name && return child
    end
    required && throw(ArgumentError("<$(EzXML.nodename(node))> requires a <$name> child"))
    return nothing
end

function _itc_children(node::EzXML.Node, name::AbstractString)
    return (child for child in EzXML.eachelement(node) if EzXML.nodename(child) == name)
end

function _itc_bits(text::AbstractString, expected::Int, name::AbstractString)
    length(text) == expected || throw(
        ArgumentError("$name must contain exactly $expected bits"),
    )
    indices = Int[]
    for (index, character) in enumerate(text)
        character == '1' && push!(indices, index)
        character in ('0', '1') || throw(ArgumentError("$name must be a binary string"))
    end
    isempty(indices) && throw(ArgumentError("$name cannot select no period"))
    return indices
end

function _itc_distribution(type, activities)
    matched = match(r"^([A-Za-z]+)(?:\(([^)]*)\))?$", type)
    isnothing(matched) && throw(ArgumentError("invalid ITC distribution type $type"))
    name = String(something(matched.captures[1]))
    parameter_text = matched.captures[2]
    parameters = if isnothing(parameter_text) || isempty(strip(parameter_text))
        Int[]
    else
        values = tryparse.(Int, strip.(split(parameter_text, ',')))
        any(isnothing, values) && throw(
            ArgumentError("ITC distribution parameters must be integers: $type"),
        )
        Int[something(value) for value in values]
    end
    constructors = Dict{String,Function}(
        "SameStart" => ids -> AcademicSameStart(ids),
        "SameTime" => ids -> AcademicSameTime(ids),
        "DifferentTime" => ids -> AcademicDifferentTime(ids),
        "SameDays" => ids -> AcademicSameDays(ids),
        "DifferentDays" => ids -> AcademicDifferentDays(ids),
        "SameWeeks" => ids -> AcademicSameWeeks(ids),
        "DifferentWeeks" => ids -> AcademicDifferentWeeks(ids),
        "SameRoom" => ids -> AcademicSameRoom(ids),
        "DifferentRoom" => ids -> AcademicDifferentRoom(ids),
        "Overlap" => ids -> AcademicOverlap(ids),
        "NotOverlap" => ids -> AcademicNotOverlap(ids),
        "SameAttendees" => ids -> AcademicSameAttendees(ids),
        "Precedence" => ids -> AcademicPrecedence(ids),
        "WorkDay" => ids -> AcademicWorkDay(ids, only(parameters)),
        "MinGap" => ids -> AcademicMinGap(ids, only(parameters)),
        "MaxDays" => ids -> AcademicMaxDays(ids, only(parameters)),
        "MaxDayLoad" => ids -> AcademicMaxDayLoad(ids, only(parameters)),
        "MaxBreaks" => ids -> AcademicMaxBreaks(ids, parameters...),
        "MaxBlock" => ids -> AcademicMaxBlock(ids, parameters...),
    )
    constructor = get(constructors, name, nothing)
    isnothing(constructor) && throw(ArgumentError("unsupported ITC distribution type $type"))
    expected = name in ("WorkDay", "MinGap", "MaxDays", "MaxDayLoad") ? 1 :
               name in ("MaxBreaks", "MaxBlock") ? 2 : 0
    length(parameters) == expected || throw(
        ArgumentError("ITC distribution $name requires $expected parameters"),
    )
    return constructor(activities)
end

function _itc_parse_rooms(root, day_count, week_count, slots_per_day)
    rooms_node = _itc_child(root, "rooms")
    room_nodes = collect(_itc_children(rooms_node, "room"))
    room_ids = String[_itc_attribute(room, "id") for room in room_nodes]
    allunique(room_ids) || throw(ArgumentError("ITC room identifiers must be unique"))
    room_index = Dict(id => index for (index, id) in pairs(room_ids))
    capacities = Int[_itc_integer_attribute(room, "capacity") for room in room_nodes]
    all(>=(0), capacities) || throw(ArgumentError("ITC room capacities must be non-negative"))
    unavailable = AcademicRoomUnavailable[]
    travel = AcademicRoomTravel[]
    for (index, room) in pairs(room_nodes)
        for child in EzXML.eachelement(room)
            tag = EzXML.nodename(child)
            if tag == "travel"
                target_id = _itc_attribute(child, "room")
                target = get(room_index, target_id, 0)
                iszero(target) && throw(ArgumentError("unknown ITC travel room $target_id"))
                push!(travel, AcademicRoomTravel(
                    index,
                    target,
                    _itc_integer_attribute(child, "value"),
                ))
            elseif tag == "unavailable"
                start = _itc_integer_attribute(child, "start")
                duration = _itc_integer_attribute(child, "length")
                start + duration <= slots_per_day || throw(
                    ArgumentError("ITC room unavailability exceeds slotsPerDay"),
                )
                push!(unavailable, AcademicRoomUnavailable(
                    index,
                    start,
                    duration;
                    days = _itc_bits(_itc_attribute(child, "days"), day_count,
                        "unavailable days"),
                    weeks = _itc_bits(_itc_attribute(child, "weeks"), week_count,
                        "unavailable weeks"),
                ))
            end
        end
    end
    return room_ids, room_index, capacities, unavailable, travel
end

function _itc_parse_courses!(
    root,
    room_ids,
    room_index,
    capacities,
    day_count,
    week_count,
    slots_per_day,
    time_weight,
    room_weight,
)
    activities = AcademicActivity{String}[]
    information = ITC2019ClassInfo[]
    courses_node = _itc_child(root, "courses")
    class_ids = Set{String}()
    for course in _itc_children(courses_node, "course")
        course_id = _itc_attribute(course, "id")
        for configuration in _itc_children(course, "config")
            configuration_id = _itc_attribute(configuration, "id")
            for subpart in _itc_children(configuration, "subpart")
                subpart_id = _itc_attribute(subpart, "id")
                for class_node in _itc_children(subpart, "class")
                    class_id = _itc_attribute(class_node, "id")
                    class_id in class_ids && throw(
                        ArgumentError("ITC class identifiers must be unique"),
                    )
                    push!(class_ids, class_id)
                    limit = _itc_optional_integer_attribute(class_node, "limit", 0)
                    limit >= 0 || throw(ArgumentError("ITC class limits must be non-negative"))
                    room_required = !haskey(class_node, "room") ||
                                    lowercase(String(class_node["room"])) != "false"
                    rooms = Tuple{Int,Int}[]
                    for room in _itc_children(class_node, "room")
                        id = _itc_attribute(room, "id")
                        index = get(room_index, id, 0)
                        iszero(index) && throw(ArgumentError("unknown ITC class room $id"))
                        push!(rooms, (index, _itc_optional_integer_attribute(room, "penalty")))
                    end
                    if room_required
                        isempty(rooms) && throw(
                            ArgumentError("ITC class $class_id requires at least one room"),
                        )
                    else
                        isempty(rooms) || throw(
                            ArgumentError("roomless ITC class $class_id cannot list rooms"),
                        )
                        push!(room_ids, "__roomless__$class_id")
                        push!(capacities, max(limit, 1))
                        room_index[room_ids[end]] = length(room_ids)
                        push!(rooms, (length(room_ids), 0))
                    end
                    times = collect(_itc_children(class_node, "time"))
                    isempty(times) && throw(
                        ArgumentError("ITC class $class_id requires at least one time"),
                    )
                    placements = AcademicPlacement[]
                    fallback_duration = _itc_integer_attribute(first(times), "length")
                    for time in times
                        start = _itc_integer_attribute(time, "start")
                        duration = _itc_integer_attribute(time, "length")
                        start + duration <= slots_per_day || throw(
                            ArgumentError("ITC class $class_id time exceeds slotsPerDay"),
                        )
                        time_penalty = _itc_optional_integer_attribute(time, "penalty")
                        days = _itc_bits(_itc_attribute(time, "days"), day_count, "class days")
                        weeks = _itc_bits(
                            _itc_attribute(time, "weeks"), week_count, "class weeks",
                        )
                        for (room, room_penalty) in rooms
                            penalty = time_weight * time_penalty + room_weight * room_penalty
                            push!(placements, AcademicPlacement(
                                start,
                                room;
                                days,
                                weeks,
                                penalty,
                                duration,
                            ))
                        end
                    end
                    push!(activities, AcademicActivity(
                        class_id,
                        fallback_duration,
                        placements;
                        demand = limit,
                    ))
                    parent = haskey(class_node, "parent") ? String(class_node["parent"]) : nothing
                    push!(information, ITC2019ClassInfo(
                        class_id,
                        course_id,
                        configuration_id,
                        subpart_id,
                        parent,
                        room_required,
                        limit,
                    ))
                end
            end
        end
    end
    isempty(activities) && throw(ArgumentError("ITC problem contains no classes"))
    return activities, information
end

function _validate_itc_references(information, distributions, students)
    class_ids = Set(info.id for info in information)
    course_ids = Set(info.course for info in information)
    for info in information
        isnothing(info.parent) || info.parent in class_ids || throw(
            ArgumentError("unknown ITC parent class $(info.parent)"),
        )
    end
    for specification in distributions, id in specification.constraint.activities
        id in class_ids || throw(ArgumentError("unknown ITC distribution class $id"))
    end
    for (student, requested_courses) in students, course in requested_courses
        course in course_ids || throw(
            ArgumentError("ITC student $student requests unknown course $course"),
        )
    end
    return nothing
end

function _itc_parse_distributions(root)
    container = _itc_child(root, "distributions"; required = false)
    isnothing(container) && return AcademicDistributionSpec[]
    result = AcademicDistributionSpec[]
    for node in _itc_children(container, "distribution")
        activities = String[_itc_attribute(child, "id") for child in _itc_children(node, "class")]
        constraint = _itc_distribution(_itc_attribute(node, "type"), activities)
        required = haskey(node, "required") && lowercase(String(node["required"])) == "true"
        penalty = _itc_optional_integer_attribute(node, "penalty")
        required || penalty > 0 || throw(
            ArgumentError("a non-required ITC distribution needs a positive penalty"),
        )
        push!(result, AcademicDistributionSpec(constraint; required, penalty))
    end
    return result
end

function _itc_parse_students(root)
    container = _itc_child(root, "students"; required = false)
    isnothing(container) && return Dict{String,Vector{String}}()
    students = Dict{String,Vector{String}}()
    for student in _itc_children(container, "student")
        id = _itc_attribute(student, "id")
        haskey(students, id) && throw(ArgumentError("ITC student identifiers must be unique"))
        students[id] = String[
            _itc_attribute(course, "id") for course in _itc_children(student, "course")
        ]
    end
    return students
end

"""Parse one ITC 2019 problem XML string into a solver-independent scheduling carrier."""
function parse_itc2019(xml::AbstractString)
    document = EzXML.parsexml(xml)
    root = EzXML.root(document)::EzXML.Node
    EzXML.nodename(root) == "problem" || throw(ArgumentError("ITC root must be <problem>"))
    name = _itc_attribute(root, "name")
    day_count = _itc_integer_attribute(root, "nrDays")
    week_count = _itc_integer_attribute(root, "nrWeeks")
    slots_per_day = _itc_integer_attribute(root, "slotsPerDay")
    1 <= day_count <= 64 || throw(ArgumentError("ITC nrDays must be between 1 and 64"))
    1 <= week_count <= 64 || throw(ArgumentError("ITC nrWeeks must be between 1 and 64"))
    slots_per_day > 0 || throw(ArgumentError("ITC slotsPerDay must be positive"))
    optimization = _itc_child(root, "optimization")
    weights = (
        time = _itc_integer_attribute(optimization, "time"),
        room = _itc_integer_attribute(optimization, "room"),
        distribution = _itc_integer_attribute(optimization, "distribution"),
        student = _itc_integer_attribute(optimization, "student"),
    )
    all(>=(0), weights) || throw(ArgumentError("ITC optimization weights must be non-negative"))
    room_ids, room_index, capacities, unavailable, travel =
        _itc_parse_rooms(root, day_count, week_count, slots_per_day)
    activities, information = _itc_parse_courses!(
        root,
        room_ids,
        room_index,
        capacities,
        day_count,
        week_count,
        slots_per_day,
        weights.time,
        weights.room,
    )
    distributions = _itc_parse_distributions(root)
    students = _itc_parse_students(root)
    _validate_itc_references(information, distributions, students)
    return ITC2019Instance(
        name,
        day_count,
        week_count,
        slots_per_day,
        weights,
        room_ids,
        capacities,
        activities,
        distributions,
        unavailable,
        travel,
        information,
        students,
    )
end

"""Read and parse one ITC 2019 problem XML file."""
read_itc2019(path::AbstractString) = parse_itc2019(read(path, String))

function academic_timetable(
    instance::ITC2019Instance;
    enforce_student_sectioning::Bool = false,
    kwargs...,
)
    enforce_student_sectioning && !isempty(instance.student_courses) && throw(
        ArgumentError(
            "ITC student sectioning is preserved but not implemented by the placement model",
        ),
    )
    return academic_timetable(
        instance.activities,
        instance.room_capacities;
        distributions = instance.distributions,
        room_unavailable = instance.room_unavailable,
        room_travel = instance.room_travel,
        day_count = instance.day_count,
        week_count = instance.week_count,
        distribution_weight = instance.optimization_weights.distribution,
        kwargs...,
    )
end

@testitem "ITC 2019 XML preserves scheduling semantics" default_imports = false begin
    import ConstraintModels as CM
    import LocalSearchSolvers as LS
    import Test: @test, @test_throws

    xml = """
    <problem name="fixture" nrDays="2" nrWeeks="2" slotsPerDay="12">
      <optimization time="2" room="3" distribution="5" student="7"/>
      <rooms>
        <room id="R1" capacity="20"/>
        <room id="R2" capacity="40">
          <travel room="R1" value="2"/>
          <unavailable days="10" start="0" length="2" weeks="10"/>
        </room>
      </rooms>
      <courses>
        <course id="C1"><config id="G1"><subpart id="S1">
          <class id="A" limit="10">
            <room id="R1" penalty="0"/><room id="R2" penalty="4"/>
            <time days="10" start="0" length="2" weeks="10" penalty="3"/>
            <time days="01" start="4" length="3" weeks="01" penalty="0"/>
          </class>
          <class id="B" parent="A" room="false" limit="5">
            <time days="10" start="4" length="1" weeks="10" penalty="1"/>
          </class>
        </subpart></config></course>
      </courses>
      <distributions>
        <distribution type="NotOverlap" required="true"><class id="A"/><class id="B"/></distribution>
        <distribution type="MaxDays(1)" penalty="2"><class id="A"/><class id="B"/></distribution>
      </distributions>
      <students><student id="U1"><course id="C1"/></student></students>
    </problem>
    """
    instance = CM.parse_itc2019(xml)
    @test instance.name == "fixture"
    @test instance.optimization_weights == (time = 2, room = 3, distribution = 5, student = 7)
    @test instance.room_ids == ["R1", "R2", "__roomless__B"]
    @test length(instance.activities) == 2
    @test length(instance.activities[1].placements) == 4
    @test Set(getfield.(instance.activities[1].placements, :duration)) == Set((2, 3))
    @test Set(getfield.(instance.activities[1].placements, :penalty)) == Set((0.0, 6.0, 12.0, 18.0))
    @test instance.class_info[2].parent == "A"
    @test instance.student_courses["U1"] == ["C1"]
    @test !CM.student_sectioning_supported(instance)

    model = CM.academic_timetable(instance)
    @test LS.get_kind(model) == :academic_timetable
    # One R2 placement is unavailable in week 1/day 1 and is filtered before search.
    @test length(LS.get_domain(model, 1)) == 3
    @test_throws ArgumentError CM.academic_timetable(
        instance; enforce_student_sectioning = true,
    )
    @test_throws ArgumentError CM.parse_itc2019(replace(xml, "days=\"10\"" => "days=\"100\""))
    @test_throws ArgumentError CM.parse_itc2019(replace(xml, "MaxDays(1)" => "Unknown(1)"))
    all_types = (
        "SameStart", "SameTime", "DifferentTime", "SameDays", "DifferentDays",
        "SameWeeks", "DifferentWeeks", "SameRoom", "DifferentRoom", "Overlap",
        "NotOverlap", "SameAttendees", "Precedence", "WorkDay(2)", "MinGap(1)",
        "MaxDays(1)", "MaxDayLoad(3)", "MaxBreaks(1,2)", "MaxBlock(3,1)",
    )
    @test length([CM._itc_distribution(type, ["A", "B"]) for type in all_types]) == 19
    @test_throws ArgumentError CM.parse_itc2019(replace(xml, "parent=\"A\"" => "parent=\"Z\""))
    @test_throws ArgumentError CM.parse_itc2019(replace(xml, "start=\"4\" length=\"3\"" =>
        "start=\"11\" length=\"3\""))
end
