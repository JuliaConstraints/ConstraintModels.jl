function _academic_mask(values, name)
    iterator = values isa Integer ? (values,) : values
    mask = zero(UInt64)
    for value in iterator
        value isa Integer || throw(ArgumentError("$name entries must be integers"))
        1 <= value <= 64 || throw(ArgumentError("$name entries must be between 1 and 64"))
        mask |= one(UInt64) << (Int(value) - 1)
    end
    iszero(mask) && throw(ArgumentError("$name cannot be empty"))
    return mask
end

@inline _first_academic_index(mask::UInt64) = trailing_zeros(mask) + 1

@inline function _legacy_academic_day_mask(day::Integer)
    day > 0 || throw(ArgumentError("an academic day must be positive"))
    return day <= 64 ? one(UInt64) << (Int(day) - 1) : zero(UInt64)
end

"""
    AcademicPlacement(day, start, room[, penalty])
    AcademicPlacement(start, room; days, weeks=1, penalty=0)

One complete placement decision for an academic activity. Time is expressed in an
application-defined integer unit. Day and week sets are stored as allocation-free `UInt64`
masks; the positional constructor remains the single-day, first-week compatibility path.
"""
struct AcademicPlacement
    day::Int
    start::Int
    room::Int
    penalty::Float64
    days::UInt64
    weeks::UInt64
    duration::Int

    function AcademicPlacement(
        day::Integer,
        start::Integer,
        room::Integer,
        penalty::Real = 0.0,
        ;
        duration::Union{Nothing,Integer} = nothing,
    )
        days = _legacy_academic_day_mask(day)
        weeks = one(UInt64)
        start >= 0 || throw(ArgumentError("a placement start must be non-negative"))
        room > 0 || throw(ArgumentError("a placement room must be positive"))
        return new(
            Int(day),
            Int(start),
            Int(room),
            _academic_penalty(penalty),
            days,
            weeks,
            _academic_duration_override(duration),
        )
    end

    function AcademicPlacement(
        start::Integer,
        room::Integer;
        days,
        weeks = 1,
        penalty::Real = 0.0,
        duration::Union{Nothing,Integer} = nothing,
    )
        day_mask = _academic_mask(days, "placement days")
        week_mask = _academic_mask(weeks, "placement weeks")
        start >= 0 || throw(ArgumentError("a placement start must be non-negative"))
        room > 0 || throw(ArgumentError("a placement room must be positive"))
        return new(
            _first_academic_index(day_mask),
            Int(start),
            Int(room),
            _academic_penalty(penalty),
            day_mask,
            week_mask,
            _academic_duration_override(duration),
        )
    end
end

function _academic_duration_override(duration)
    isnothing(duration) && return 0
    duration > 0 || throw(ArgumentError("a placement duration must be positive"))
    return Int(duration)
end

function _academic_penalty(penalty)
    isfinite(penalty) && penalty >= 0 ||
        throw(ArgumentError("a placement penalty must be finite and non-negative"))
    return Float64(penalty)
end

"""
    AcademicActivity(id, duration, placements; demand=0, instructors=(), groups=())

An activity and its finite placement domain. Instructor and group identifiers are dense
integers compiled by the application adapter before search; this keeps the candidate loop
independent of external identifier types and hashing.
"""
struct AcademicActivity{I}
    id::I
    duration::Int
    demand::Int
    instructors::Vector{Int}
    groups::Vector{Int}
    placements::Vector{AcademicPlacement}
end

function AcademicActivity(
    id,
    duration::Integer,
    placements;
    demand::Integer = 0,
    instructors = (),
    groups = (),
)
    duration > 0 || throw(ArgumentError("an activity duration must be positive"))
    demand >= 0 || throw(ArgumentError("an activity demand must be non-negative"))
    local_placements = AcademicPlacement[placement for placement in placements]
    isempty(local_placements) &&
        throw(ArgumentError("an activity must have at least one placement"))
    coordinates = [(placement.day, placement.days, placement.weeks, placement.start,
                    placement.room, placement.duration)
                   for placement in local_placements]
    allunique(coordinates) || throw(
        ArgumentError("an activity placement domain cannot contain duplicate coordinates"),
    )
    local_instructors = unique!(Int[instructor for instructor in instructors])
    local_groups = unique!(Int[group for group in groups])
    all(>(0), local_instructors) ||
        throw(ArgumentError("instructor identifiers must be positive"))
    all(>(0), local_groups) || throw(ArgumentError("group identifiers must be positive"))
    return AcademicActivity(
        id,
        Int(duration),
        Int(demand),
        local_instructors,
        local_groups,
        local_placements,
    )
end

abstract type AcademicDistributionConstraint end

function _academic_distribution_ids(ids, name)
    local_ids = collect(ids)
    length(local_ids) >= 2 ||
        throw(ArgumentError("$name requires at least two activity identifiers"))
    allunique(local_ids) ||
        throw(ArgumentError("$name activity identifiers must be unique"))
    return local_ids
end

"""Classes must occur in the listed order; all earlier/later pairs are constrained."""
struct AcademicPrecedence{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicPrecedence{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicPrecedence")
        return new{I}(ids)
    end
end

function AcademicPrecedence(activities)
    ids = collect(activities)
    return AcademicPrecedence{eltype(ids)}(ids)
end

"""Each pair of classes must use nested time-of-day intervals (ITC `SameTime`)."""
struct AcademicSameTime{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicSameTime{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicSameTime")
        return new{I}(ids)
    end
end

function AcademicSameTime(activities)
    ids = collect(activities)
    return AcademicSameTime{eltype(ids)}(ids)
end

"""Each pair of classes must use disjoint time-of-day intervals (ITC `DifferentTime`)."""
struct AcademicDifferentTime{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicDifferentTime{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicDifferentTime")
        return new{I}(ids)
    end
end

function AcademicDifferentTime(activities)
    ids = collect(activities)
    return AcademicDifferentTime{eltype(ids)}(ids)
end

"""Each pair of classes must be assigned to the same room."""
struct AcademicSameRoom{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicSameRoom{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicSameRoom")
        return new{I}(ids)
    end
end

function AcademicSameRoom(activities)
    ids = collect(activities)
    return AcademicSameRoom{eltype(ids)}(ids)
end

"""Each pair of classes must be assigned to different rooms."""
struct AcademicDifferentRoom{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicDifferentRoom{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicDifferentRoom")
        return new{I}(ids)
    end
end

function AcademicDifferentRoom(activities)
    ids = collect(activities)
    return AcademicDifferentRoom{eltype(ids)}(ids)
end

"""Each pair of classes must start at the same time of day."""
struct AcademicSameStart{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicSameStart{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicSameStart")
        return new{I}(ids)
    end
end

function AcademicSameStart(activities)
    ids = collect(activities)
    return AcademicSameStart{eltype(ids)}(ids)
end

"""The day set of either class in each pair must be a subset of the other."""
struct AcademicSameDays{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicSameDays{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicSameDays")
        return new{I}(ids)
    end
end

function AcademicSameDays(activities)
    ids = collect(activities)
    return AcademicSameDays{eltype(ids)}(ids)
end

"""Each pair of classes must use disjoint day sets."""
struct AcademicDifferentDays{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicDifferentDays{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicDifferentDays")
        return new{I}(ids)
    end
end

function AcademicDifferentDays(activities)
    ids = collect(activities)
    return AcademicDifferentDays{eltype(ids)}(ids)
end

"""The week set of either class in each pair must be a subset of the other."""
struct AcademicSameWeeks{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicSameWeeks{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicSameWeeks")
        return new{I}(ids)
    end
end

function AcademicSameWeeks(activities)
    ids = collect(activities)
    return AcademicSameWeeks{eltype(ids)}(ids)
end

"""Each pair of classes must use disjoint week sets."""
struct AcademicDifferentWeeks{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicDifferentWeeks{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicDifferentWeeks")
        return new{I}(ids)
    end
end

function AcademicDifferentWeeks(activities)
    ids = collect(activities)
    return AcademicDifferentWeeks{eltype(ids)}(ids)
end

"""Each pair of classes must overlap in time, days and weeks."""
struct AcademicOverlap{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicOverlap{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicOverlap")
        return new{I}(ids)
    end
end

function AcademicOverlap(activities)
    ids = collect(activities)
    return AcademicOverlap{eltype(ids)}(ids)
end

"""Each pair of classes must not overlap simultaneously in time, days and weeks."""
struct AcademicNotOverlap{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicNotOverlap{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicNotOverlap")
        return new{I}(ids)
    end
end

function AcademicNotOverlap(activities)
    ids = collect(activities)
    return AcademicNotOverlap{eltype(ids)}(ids)
end

"""Each pair must be reachable without overlap, accounting for room travel time."""
struct AcademicSameAttendees{I} <: AcademicDistributionConstraint
    activities::Vector{I}

    function AcademicSameAttendees{I}(activities::Vector{I}) where {I}
        ids = _academic_distribution_ids(activities, "AcademicSameAttendees")
        return new{I}(ids)
    end
end

function AcademicSameAttendees(activities)
    ids = collect(activities)
    return AcademicSameAttendees{eltype(ids)}(ids)
end

"""Each pair sharing a day and week must fit inside a span of at most `slots`."""
struct AcademicWorkDay{I} <: AcademicDistributionConstraint
    activities::Vector{I}
    slots::Int
end

function AcademicWorkDay(activities, slots::Integer)
    slots >= 0 || throw(ArgumentError("AcademicWorkDay slots must be non-negative"))
    ids = _academic_distribution_ids(activities, "AcademicWorkDay")
    return AcademicWorkDay{eltype(ids)}(ids, Int(slots))
end

"""Each pair sharing a day and week must have at least `slots` free slots between it."""
struct AcademicMinGap{I} <: AcademicDistributionConstraint
    activities::Vector{I}
    slots::Int
end

function AcademicMinGap(activities, slots::Integer)
    slots >= 0 || throw(ArgumentError("AcademicMinGap slots must be non-negative"))
    ids = _academic_distribution_ids(activities, "AcademicMinGap")
    return AcademicMinGap{eltype(ids)}(ids, Int(slots))
end

"""The union of class meeting days must contain at most `days` weekdays."""
struct AcademicMaxDays{I} <: AcademicDistributionConstraint
    activities::Vector{I}
    days::Int
end

function AcademicMaxDays(activities, days::Integer)
    days >= 0 || throw(ArgumentError("AcademicMaxDays days must be non-negative"))
    ids = _academic_distribution_ids(activities, "AcademicMaxDays")
    return AcademicMaxDays{eltype(ids)}(ids, Int(days))
end

"""The total duration on each day and week must not exceed `slots`."""
struct AcademicMaxDayLoad{I} <: AcademicDistributionConstraint
    activities::Vector{I}
    slots::Int
end

function AcademicMaxDayLoad(activities, slots::Integer)
    slots >= 0 || throw(ArgumentError("AcademicMaxDayLoad slots must be non-negative"))
    ids = _academic_distribution_ids(activities, "AcademicMaxDayLoad")
    return AcademicMaxDayLoad{eltype(ids)}(ids, Int(slots))
end

"""Each day and week may contain at most `breaks` gaps longer than `gap` slots."""
struct AcademicMaxBreaks{I} <: AcademicDistributionConstraint
    activities::Vector{I}
    breaks::Int
    gap::Int
end


function AcademicMaxBreaks(activities, breaks::Integer, gap::Integer)
    breaks >= 0 || throw(ArgumentError("AcademicMaxBreaks breaks must be non-negative"))
    gap >= 0 || throw(ArgumentError("AcademicMaxBreaks gap must be non-negative"))
    ids = _academic_distribution_ids(activities, "AcademicMaxBreaks")
    return AcademicMaxBreaks{eltype(ids)}(ids, Int(breaks), Int(gap))
end

"""Blocks of at least two classes, linked across gaps up to `gap`, may span at most `slots`."""
struct AcademicMaxBlock{I} <: AcademicDistributionConstraint
    activities::Vector{I}
    slots::Int
    gap::Int
end

function AcademicMaxBlock(activities, slots::Integer, gap::Integer)
    slots >= 0 || throw(ArgumentError("AcademicMaxBlock slots must be non-negative"))
    gap >= 0 || throw(ArgumentError("AcademicMaxBlock gap must be non-negative"))
    ids = _academic_distribution_ids(activities, "AcademicMaxBlock")
    return AcademicMaxBlock{eltype(ids)}(ids, Int(slots), Int(gap))
end

"""
    AcademicDistributionSpec(constraint; required=true, penalty=0)

Attach ITC hard/soft semantics to a distribution constraint. Bare constraints remain hard for
backward compatibility. A soft specification requires a strictly positive integer penalty.
"""
struct AcademicDistributionSpec{C<:AcademicDistributionConstraint}
    constraint::C
    required::Bool
    penalty::Int
end

function AcademicDistributionSpec(
    constraint::AcademicDistributionConstraint;
    required::Bool = true,
    penalty::Integer = 0,
)
    penalty >= 0 || throw(ArgumentError("a distribution penalty must be non-negative"))
    required || penalty > 0 ||
        throw(ArgumentError("a soft distribution requires a positive penalty"))
    return AcademicDistributionSpec(constraint, required, Int(penalty))
end

"""
    AcademicRoomUnavailable(room, day, start, duration)
    AcademicRoomUnavailable(room, start, duration; days, weeks=1)

A hard room-unavailability interval over compact day and week masks. The positional
constructor remains the single-day, first-week compatibility path.
"""
struct AcademicRoomUnavailable
    room::Int
    day::Int
    start::Int
    duration::Int
    days::UInt64
    weeks::UInt64

    function AcademicRoomUnavailable(
        room::Integer,
        day::Integer,
        start::Integer,
        duration::Integer,
    )
        room > 0 || throw(ArgumentError("an unavailable room must be positive"))
        day > 0 || throw(ArgumentError("an unavailable day must be positive"))
        start >= 0 || throw(ArgumentError("an unavailable start must be non-negative"))
        duration > 0 || throw(ArgumentError("an unavailable duration must be positive"))
        return new(
            Int(room),
            Int(day),
            Int(start),
            Int(duration),
            _legacy_academic_day_mask(day),
            one(UInt64),
        )
    end

    function AcademicRoomUnavailable(
        room::Integer,
        start::Integer,
        duration::Integer;
        days,
        weeks = 1,
    )
        room > 0 || throw(ArgumentError("an unavailable room must be positive"))
        start >= 0 || throw(ArgumentError("an unavailable start must be non-negative"))
        duration > 0 || throw(ArgumentError("an unavailable duration must be positive"))
        day_mask = _academic_mask(days, "unavailable days")
        week_mask = _academic_mask(weeks, "unavailable weeks")
        return new(
            Int(room),
            _first_academic_index(day_mask),
            Int(start),
            Int(duration),
            day_mask,
            week_mask,
        )
    end
end

"""Symmetric travel time, in timetable slots, between two rooms."""
struct AcademicRoomTravel
    first::Int
    second::Int
    duration::Int

    function AcademicRoomTravel(first::Integer, second::Integer, duration::Integer)
        first > 0 && second > 0 ||
            throw(ArgumentError("travel room identifiers must be positive"))
        first != second || throw(ArgumentError("travel rooms must be distinct"))
        duration >= 0 || throw(ArgumentError("travel duration must be non-negative"))
        return new(Int(first), Int(second), Int(duration))
    end
end

struct _AcademicUnavailablePeriod
    day::Int
    days::UInt64
    weeks::UInt64
    start::Int
    duration::Int
end

const _ACADEMIC_SAME_TIME = UInt16(0x0001)
const _ACADEMIC_DIFFERENT_TIME = UInt16(0x0002)
const _ACADEMIC_SAME_ROOM = UInt16(0x0004)
const _ACADEMIC_DIFFERENT_ROOM = UInt16(0x0008)
const _ACADEMIC_PRECEDENCE_FORWARD = UInt16(0x0010)
const _ACADEMIC_PRECEDENCE_REVERSE = UInt16(0x0020)
const _ACADEMIC_SAME_START = UInt16(0x0040)
const _ACADEMIC_SAME_DAYS = UInt16(0x0080)
const _ACADEMIC_DIFFERENT_DAYS = UInt16(0x0100)
const _ACADEMIC_SAME_WEEKS = UInt16(0x0200)
const _ACADEMIC_DIFFERENT_WEEKS = UInt16(0x0400)
const _ACADEMIC_OVERLAP = UInt16(0x0800)
const _ACADEMIC_NOT_OVERLAP = UInt16(0x1000)
const _ACADEMIC_SAME_ATTENDEES = UInt16(0x2000)

const _ACADEMIC_RESOURCE_ROOM = UInt8(0x01)
const _ACADEMIC_RESOURCE_INSTRUCTOR = UInt8(0x02)
const _ACADEMIC_RESOURCE_GROUP = UInt8(0x04)

const _DIST_SAME_START = UInt8(1)
const _DIST_SAME_TIME = UInt8(2)
const _DIST_DIFFERENT_TIME = UInt8(3)
const _DIST_SAME_DAYS = UInt8(4)
const _DIST_DIFFERENT_DAYS = UInt8(5)
const _DIST_SAME_WEEKS = UInt8(6)
const _DIST_DIFFERENT_WEEKS = UInt8(7)
const _DIST_SAME_ROOM = UInt8(8)
const _DIST_DIFFERENT_ROOM = UInt8(9)
const _DIST_OVERLAP = UInt8(10)
const _DIST_NOT_OVERLAP = UInt8(11)
const _DIST_SAME_ATTENDEES = UInt8(12)
const _DIST_PRECEDENCE = UInt8(13)
const _DIST_WORK_DAY = UInt8(14)
const _DIST_MIN_GAP = UInt8(15)
const _DIST_MAX_DAYS = UInt8(16)
const _DIST_MAX_DAY_LOAD = UInt8(17)
const _DIST_MAX_BREAKS = UInt8(18)
const _DIST_MAX_BLOCK = UInt8(19)

struct _CompiledAcademicDistribution
    kind::UInt8
    activities::Vector{Int}
    first_parameter::Int
    second_parameter::Int
    penalty::Int
end

function _distribution_kind(distribution)
    distribution isa AcademicSameStart && return _DIST_SAME_START
    distribution isa AcademicSameTime && return _DIST_SAME_TIME
    distribution isa AcademicDifferentTime && return _DIST_DIFFERENT_TIME
    distribution isa AcademicSameDays && return _DIST_SAME_DAYS
    distribution isa AcademicDifferentDays && return _DIST_DIFFERENT_DAYS
    distribution isa AcademicSameWeeks && return _DIST_SAME_WEEKS
    distribution isa AcademicDifferentWeeks && return _DIST_DIFFERENT_WEEKS
    distribution isa AcademicSameRoom && return _DIST_SAME_ROOM
    distribution isa AcademicDifferentRoom && return _DIST_DIFFERENT_ROOM
    distribution isa AcademicOverlap && return _DIST_OVERLAP
    distribution isa AcademicNotOverlap && return _DIST_NOT_OVERLAP
    distribution isa AcademicSameAttendees && return _DIST_SAME_ATTENDEES
    distribution isa AcademicPrecedence && return _DIST_PRECEDENCE
    distribution isa AcademicWorkDay && return _DIST_WORK_DAY
    distribution isa AcademicMinGap && return _DIST_MIN_GAP
    distribution isa AcademicMaxDays && return _DIST_MAX_DAYS
    distribution isa AcademicMaxDayLoad && return _DIST_MAX_DAY_LOAD
    distribution isa AcademicMaxBreaks && return _DIST_MAX_BREAKS
    distribution isa AcademicMaxBlock && return _DIST_MAX_BLOCK
    throw(ArgumentError("unsupported academic distribution $(typeof(distribution))"))
end

function _compile_academic_distribution(identifiers, distribution; penalty = 0)
    indices = [_activity_index(identifiers, id) for id in distribution.activities]
    first_parameter = if distribution isa Union{
        AcademicWorkDay,
        AcademicMinGap,
        AcademicMaxDayLoad,
        AcademicMaxBlock,
    }
        distribution.slots
    elseif distribution isa AcademicMaxDays
        distribution.days
    elseif distribution isa AcademicMaxBreaks
        distribution.breaks
    else
        0
    end
    second_parameter = if distribution isa Union{AcademicMaxBreaks,AcademicMaxBlock}
        distribution.gap
    else
        0
    end
    return _CompiledAcademicDistribution(
        _distribution_kind(distribution),
        indices,
        first_parameter,
        second_parameter,
        Int(penalty),
    )
end

"""Weights of exact hard-conflict quantities in an academic timetable."""
struct TimetableConflictWeights
    room::Float64
    instructor::Float64
    group::Float64
    capacity::Float64
    precedence::Float64
    same_time::Float64
    different_time::Float64
    same_room::Float64
    different_room::Float64
    same_start::Float64
    same_days::Float64
    different_days::Float64
    same_weeks::Float64
    different_weeks::Float64
    overlap::Float64
    not_overlap::Float64
    same_attendees::Float64
    work_day::Float64
    min_gap::Float64
    max_days::Float64
    max_day_load::Float64
    max_breaks::Float64
    max_block::Float64
    unavailable::Float64

    function TimetableConflictWeights(;
        room::Real = 1.0,
        instructor::Real = 1.0,
        group::Real = 1.0,
        capacity::Real = 1.0,
        precedence::Real = 1.0,
        same_time::Real = 1.0,
        different_time::Real = 1.0,
        same_room::Real = 1.0,
        different_room::Real = 1.0,
        same_start::Real = 1.0,
        same_days::Real = 1.0,
        different_days::Real = 1.0,
        same_weeks::Real = 1.0,
        different_weeks::Real = 1.0,
        overlap::Real = 1.0,
        not_overlap::Real = 1.0,
        same_attendees::Real = 1.0,
        work_day::Real = 1.0,
        min_gap::Real = 1.0,
        max_days::Real = 1.0,
        max_day_load::Real = 1.0,
        max_breaks::Real = 1.0,
        max_block::Real = 1.0,
        unavailable::Real = 1.0,
    )
        values = (
            room,
            instructor,
            group,
            capacity,
            precedence,
            same_time,
            different_time,
            same_room,
            different_room,
            same_start,
            same_days,
            different_days,
            same_weeks,
            different_weeks,
            overlap,
            not_overlap,
            same_attendees,
            work_day,
            min_gap,
            max_days,
            max_day_load,
            max_breaks,
            max_block,
            unavailable,
        )
        all(value -> isfinite(value) && value > 0, values) ||
            throw(ArgumentError("timetable conflict weights must be finite and positive"))
        return new(Float64.(values)...)
    end
end

"""
    TimetableConflictError(activities, room_capacities;
        weights=TimetableConflictWeights(), distributions=(), room_unavailable=(),
        room_travel=())

Exact hard-constraint cost for complete activity placements. Zero means feasible. Positive
costs retain useful gradients by measuring overlap duration and capacity excess rather than
returning a single Boolean violation. Distribution identifiers are resolved once and resources
and relations are compiled into a sparse incident-pair graph before search.
"""
struct TimetableConflictError <: Function
    durations::Vector{Int}
    demands::Vector{Int}
    room_capacities::Vector{Int}
    pair_first::Vector{Int}
    pair_second::Vector{Int}
    pair_resources::Vector{UInt8}
    pair_relations::Vector{UInt16}
    incident_pairs::Vector{Vector{Int}}
    global_distributions::Vector{_CompiledAcademicDistribution}
    incident_distributions::Vector{Vector{Int}}
    travel_times::Matrix{Int}
    unavailable::Vector{Vector{_AcademicUnavailablePeriod}}
    day_stride::Int
    day_count::Int
    week_count::Int
    maximum_distribution_size::Int
    weights::TimetableConflictWeights
end

function _activity_index(identifiers, id)
    index = get(identifiers, id, 0)
    index != 0 || throw(ArgumentError("unknown academic activity identifier $(repr(id))"))
    return index
end

function _mark_symmetric_pairs!(matrix, identifiers, ids, flag)
    indices = [_activity_index(identifiers, id) for id in ids]
    @inbounds for first = 1:(length(indices)-1), second = (first+1):length(indices)
        left, right = minmax(indices[first], indices[second])
        matrix[left, right] |= flag
    end
    return nothing
end

function _compile_distribution!(
    relations,
    identifiers,
    distribution,
)
    if distribution isa AcademicPrecedence
        indices = [_activity_index(identifiers, id) for id in distribution.activities]
        @inbounds for first = 1:(length(indices)-1), second = (first+1):length(indices)
            left, right = minmax(indices[first], indices[second])
            flag = indices[first] == left ?
                   _ACADEMIC_PRECEDENCE_FORWARD : _ACADEMIC_PRECEDENCE_REVERSE
            relations[left, right] |= flag
        end
    elseif distribution isa AcademicSameTime
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_SAME_TIME,
        )
    elseif distribution isa AcademicDifferentTime
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_DIFFERENT_TIME,
        )
    elseif distribution isa AcademicSameRoom
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_SAME_ROOM,
        )
    elseif distribution isa AcademicDifferentRoom
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_DIFFERENT_ROOM,
        )
    elseif distribution isa AcademicSameStart
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_SAME_START,
        )
    elseif distribution isa AcademicSameDays
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_SAME_DAYS,
        )
    elseif distribution isa AcademicDifferentDays
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_DIFFERENT_DAYS,
        )
    elseif distribution isa AcademicSameWeeks
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_SAME_WEEKS,
        )
    elseif distribution isa AcademicDifferentWeeks
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_DIFFERENT_WEEKS,
        )
    elseif distribution isa AcademicOverlap
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_OVERLAP,
        )
    elseif distribution isa AcademicNotOverlap
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_NOT_OVERLAP,
        )
    elseif distribution isa AcademicSameAttendees
        _mark_symmetric_pairs!(
            relations,
            identifiers,
            distribution.activities,
            _ACADEMIC_SAME_ATTENDEES,
        )
    elseif distribution isa Union{
        AcademicWorkDay,
        AcademicMinGap,
        AcademicMaxDays,
        AcademicMaxDayLoad,
        AcademicMaxBreaks,
        AcademicMaxBlock,
    }
        nothing
    else
        throw(ArgumentError("unsupported academic distribution $(typeof(distribution))"))
    end
    return nothing
end

function TimetableConflictError(
    activities,
    room_capacities;
    weights = TimetableConflictWeights(),
    distributions = (),
    room_unavailable = (),
    room_travel = (),
    day_count = nothing,
    week_count = nothing,
)
    local_activities = collect(activities)
    local_distributions = AcademicDistributionConstraint[]
    for distribution in distributions
        if distribution isa AcademicDistributionSpec
            distribution.required && push!(local_distributions, distribution.constraint)
        elseif distribution isa AcademicDistributionConstraint
            push!(local_distributions, distribution)
        else
            throw(ArgumentError("unsupported academic distribution $(typeof(distribution))"))
        end
    end
    capacities = Int[capacity for capacity in room_capacities]
    isempty(capacities) && throw(ArgumentError("at least one room is required"))
    all(>=(0), capacities) || throw(ArgumentError("room capacities must be non-negative"))
    count = length(local_activities)
    count > 0 || throw(ArgumentError("at least one activity is required"))
    identifiers = Dict{Any,Int}()
    for (index, activity) in pairs(local_activities)
        haskey(identifiers, activity.id) && throw(
            ArgumentError("academic activity identifiers must be unique"),
        )
        identifiers[activity.id] = index
    end
    relations = zeros(UInt16, count, count)
    for distribution in local_distributions
        _compile_distribution!(
            relations,
            identifiers,
            distribution,
        )
    end
    global_distributions = _CompiledAcademicDistribution[]
    incident_distributions = [Int[] for _ = 1:count]
    for distribution in local_distributions
        kind = _distribution_kind(distribution)
        kind >= _DIST_WORK_DAY || continue
        compiled = _compile_academic_distribution(identifiers, distribution)
        push!(global_distributions, compiled)
        index = length(global_distributions)
        for activity in compiled.activities
            push!(incident_distributions[activity], index)
        end
    end
    travel_times = zeros(Int, length(capacities), length(capacities))
    travel_seen = falses(length(capacities), length(capacities))
    for travel in room_travel
        travel isa AcademicRoomTravel ||
            throw(ArgumentError("room_travel entries must be AcademicRoomTravel"))
        1 <= travel.first <= length(capacities) ||
            throw(BoundsError(capacities, travel.first))
        1 <= travel.second <= length(capacities) ||
            throw(BoundsError(capacities, travel.second))
        previous = travel_times[travel.first, travel.second]
        !travel_seen[travel.first, travel.second] || previous == travel.duration || throw(
            ArgumentError("conflicting travel durations for the same room pair"),
        )
        travel_times[travel.first, travel.second] = travel.duration
        travel_times[travel.second, travel.first] = travel.duration
        travel_seen[travel.first, travel.second] = true
        travel_seen[travel.second, travel.first] = true
    end
    unavailable = [_AcademicUnavailablePeriod[] for _ = 1:length(capacities)]
    for period in room_unavailable
        period isa AcademicRoomUnavailable || throw(
            ArgumentError("room_unavailable entries must be AcademicRoomUnavailable"),
        )
        1 <= period.room <= length(capacities) ||
            throw(BoundsError(capacities, period.room))
        push!(
            unavailable[period.room],
            _AcademicUnavailablePeriod(
                period.day,
                period.days,
                period.weeks,
                period.start,
                period.duration,
            ),
        )
    end
    activity_rooms = falses(count, length(capacities))
    for (activity_index, activity) in pairs(local_activities)
        for placement in activity.placements
            placement.room <= length(capacities) || continue
            activity_rooms[activity_index, placement.room] = true
        end
    end
    pair_first = Int[]
    pair_second = Int[]
    pair_resources = UInt8[]
    pair_relations = UInt16[]
    incident_pairs = [Int[] for _ = 1:count]
    @inbounds for first = 1:(count-1), second = (first+1):count
        resources = zero(UInt8)
        for room in eachindex(capacities)
            if activity_rooms[first, room] && activity_rooms[second, room]
                resources |= _ACADEMIC_RESOURCE_ROOM
                break
            end
        end
        !isdisjoint(
            local_activities[first].instructors,
            local_activities[second].instructors,
        ) && (resources |= _ACADEMIC_RESOURCE_INSTRUCTOR)
        !isdisjoint(local_activities[first].groups, local_activities[second].groups) &&
            (resources |= _ACADEMIC_RESOURCE_GROUP)
        relation = relations[first, second]
        iszero(resources) && iszero(relation) && continue
        push!(pair_first, first)
        push!(pair_second, second)
        push!(pair_resources, resources)
        push!(pair_relations, relation)
        pair = length(pair_first)
        push!(incident_pairs[first], pair)
        push!(incident_pairs[second], pair)
    end
    maximum_end = maximum(
        placement.start + (iszero(placement.duration) ? activity.duration : placement.duration)
        for activity in local_activities for
        placement in activity.placements
    )
    inferred_days = maximum(
        placement.day for activity in local_activities for placement in activity.placements
    )
    inferred_weeks = maximum(
        64 - leading_zeros(placement.weeks) for activity in local_activities for
        placement in activity.placements
    )
    actual_day_count = isnothing(day_count) ? max(64, inferred_days) : Int(day_count)
    actual_week_count = isnothing(week_count) ? inferred_weeks : Int(week_count)
    actual_day_count >= inferred_days ||
        throw(ArgumentError("day_count is smaller than an activity day index"))
    1 <= actual_week_count <= 64 ||
        throw(ArgumentError("week_count must be between 1 and 64"))
    actual_week_count >= inferred_weeks ||
        throw(ArgumentError("week_count is smaller than an activity week index"))
    maximum_distribution_size = maximum(
        (length(distribution.activities) for distribution in global_distributions);
        init = 0,
    )
    return TimetableConflictError(
        [activity.duration for activity in local_activities],
        [activity.demand for activity in local_activities],
        capacities,
        pair_first,
        pair_second,
        pair_resources,
        pair_relations,
        incident_pairs,
        global_distributions,
        incident_distributions,
        travel_times,
        unavailable,
        maximum_end + 1,
        actual_day_count,
        actual_week_count,
        maximum_distribution_size,
        weights,
    )
end

@inline function _academic_duration(
    error::TimetableConflictError,
    activity::Int,
    placement::AcademicPlacement,
)
    return iszero(placement.duration) ? error.durations[activity] : placement.duration
end

@inline function _common_academic_days(first, second)
    if iszero(first.days) || iszero(second.days)
        return first.day == second.day ? 1 : 0
    end
    return count_ones(first.days & second.days)
end

@inline function _academic_day_count(placement)
    return iszero(placement.days) ? 1 : count_ones(placement.days)
end

@inline function _overlap_duration(
    first::AcademicPlacement,
    first_duration,
    second::AcademicPlacement,
    second_duration,
)
    common_days = _common_academic_days(first, second)
    iszero(common_days) && return 0
    common_weeks = count_ones(first.weeks & second.weeks)
    iszero(common_weeks) && return 0
    return _time_overlap_duration(first, first_duration, second, second_duration) *
           common_days * common_weeks
end

@inline function _time_overlap_duration(
    first::AcademicPlacement,
    first_duration,
    second::AcademicPlacement,
    second_duration,
)
    return max(
        0,
        min(first.start + first_duration, second.start + second_duration) -
        max(first.start, second.start),
    )
end

@inline function _common_academic_meetings(first, second)
    return _common_academic_days(first, second) * count_ones(first.weeks & second.weeks)
end

@inline function _nested_mask_distance(first::UInt64, second::UInt64)
    first_only = count_ones(first & ~second)
    second_only = count_ones(second & ~first)
    return iszero(first_only) || iszero(second_only) ? 0 : min(first_only, second_only)
end

@inline function _nested_day_distance(first, second)
    if iszero(first.days) || iszero(second.days)
        return first.day == second.day ? 0 : 1
    end
    return _nested_mask_distance(first.days, second.days)
end

@inline function _overlap_distance(
    first::AcademicPlacement,
    first_duration,
    second::AcademicPlacement,
    second_duration,
)
    time_overlap = _time_overlap_duration(
        first,
        first_duration,
        second,
        second_duration,
    )
    time_deficit = if iszero(time_overlap)
        min(
            abs(second.start - (first.start + first_duration)),
            abs(first.start - (second.start + second_duration)),
        ) + 1
    else
        0
    end
    day_deficit = iszero(_common_academic_days(first, second)) ? 1 : 0
    week_deficit = iszero(first.weeks & second.weeks) ? 1 : 0
    return time_deficit + day_deficit + week_deficit
end

@inline function _same_time_distance(
    first::AcademicPlacement,
    first_duration,
    second::AcademicPlacement,
    second_duration,
)
    first_end = first.start + first_duration
    second_end = second.start + second_duration
    first_contains_second =
        max(0, first.start - second.start) + max(0, second_end - first_end)
    second_contains_first =
        max(0, second.start - first.start) + max(0, first_end - second_end)
    return min(first_contains_second, second_contains_first)
end

@inline function _precedence_distance(
    error,
    first,
    second,
    first_placement,
    second_placement,
)
    first_week = _first_academic_index(first_placement.weeks)
    second_week = _first_academic_index(second_placement.weeks)
    first_day = first_placement.day
    second_day = second_placement.day
    first_end = (
        ((first_week - 1) * error.day_count + first_day - 1) * error.day_stride +
        first_placement.start + _academic_duration(error, first, first_placement)
    )
    second_start =
        ((second_week - 1) * error.day_count + second_day - 1) * error.day_stride +
        second_placement.start
    return max(0, first_end - second_start)
end

@inline function _same_attendees_distance(
    error,
    first,
    second,
    first_placement,
    second_placement,
)
    common_meetings = _common_academic_meetings(first_placement, second_placement)
    iszero(common_meetings) && return 0
    travel = error.travel_times[first_placement.room, second_placement.room]
    forward = max(
        0,
        first_placement.start + _academic_duration(error, first, first_placement) + travel -
        second_placement.start,
    )
    reverse = max(
        0,
        second_placement.start + _academic_duration(error, second, second_placement) + travel -
        first_placement.start,
    )
    return min(forward, reverse) * common_meetings
end

@inline function _unary_cost(error::TimetableConflictError, activity, placement)
    room = placement.room
    1 <= room <= length(error.room_capacities) ||
        throw(BoundsError(error.room_capacities, room))
    excess = max(0, error.demands[activity] - error.room_capacities[room])
    meeting_count = _academic_day_count(placement) * count_ones(placement.weeks)
    duration = _academic_duration(error, activity, placement)
    cost = error.weights.capacity * duration * excess * meeting_count
    @inbounds for period in error.unavailable[room]
        common_days = _common_academic_days(placement, period)
        iszero(common_days) && continue
        common_weeks = count_ones(placement.weeks & period.weeks)
        iszero(common_weeks) && continue
        overlap = max(
            0,
            min(placement.start + duration, period.start + period.duration) -
            max(placement.start, period.start),
        )
        cost += error.weights.unavailable * overlap * common_days * common_weeks
    end
    return cost
end

@inline function _pair_cost(
    error::TimetableConflictError,
    pair,
    first_placement,
    second_placement,
)
    first = error.pair_first[pair]
    second = error.pair_second[pair]
    cost = 0.0
    resources = error.pair_resources[pair]
    relation = error.pair_relations[pair]
    needs_calendar_overlap =
        !iszero(resources) || relation & _ACADEMIC_NOT_OVERLAP != 0
    overlap = if needs_calendar_overlap
        _overlap_duration(
            first_placement,
            _academic_duration(error, first, first_placement),
            second_placement,
            _academic_duration(error, second, second_placement),
        )
    else
        0
    end
    if !iszero(overlap)
        resources & _ACADEMIC_RESOURCE_ROOM != 0 &&
            first_placement.room == second_placement.room &&
            (cost += error.weights.room * overlap)
        resources & _ACADEMIC_RESOURCE_INSTRUCTOR != 0 &&
            (cost += error.weights.instructor * overlap)
        resources & _ACADEMIC_RESOURCE_GROUP != 0 &&
            (cost += error.weights.group * overlap)
    end
    iszero(relation) && return cost
    if relation & _ACADEMIC_SAME_TIME != 0
        cost += error.weights.same_time * _same_time_distance(
            first_placement,
            _academic_duration(error, first, first_placement),
            second_placement,
            _academic_duration(error, second, second_placement),
        )
    end
    if relation & _ACADEMIC_DIFFERENT_TIME != 0
        cost += error.weights.different_time * _time_overlap_duration(
            first_placement,
            _academic_duration(error, first, first_placement),
            second_placement,
            _academic_duration(error, second, second_placement),
        )
    end
    if relation & _ACADEMIC_SAME_ROOM != 0 &&
       first_placement.room != second_placement.room
        cost += error.weights.same_room
    end
    if relation & _ACADEMIC_DIFFERENT_ROOM != 0 &&
       first_placement.room == second_placement.room
        cost += error.weights.different_room
    end
    if relation & _ACADEMIC_SAME_START != 0
        cost += error.weights.same_start * abs(first_placement.start - second_placement.start)
    end
    if relation & _ACADEMIC_SAME_DAYS != 0
        cost += error.weights.same_days *
                _nested_day_distance(first_placement, second_placement)
    end
    if relation & _ACADEMIC_DIFFERENT_DAYS != 0
        cost += error.weights.different_days *
                _common_academic_days(first_placement, second_placement)
    end
    if relation & _ACADEMIC_SAME_WEEKS != 0
        cost += error.weights.same_weeks *
                _nested_mask_distance(first_placement.weeks, second_placement.weeks)
    end
    if relation & _ACADEMIC_DIFFERENT_WEEKS != 0
        cost += error.weights.different_weeks *
                count_ones(first_placement.weeks & second_placement.weeks)
    end
    if relation & _ACADEMIC_OVERLAP != 0
        cost += error.weights.overlap * _overlap_distance(
            first_placement,
            _academic_duration(error, first, first_placement),
            second_placement,
            _academic_duration(error, second, second_placement),
        )
    end
    if relation & _ACADEMIC_NOT_OVERLAP != 0
        cost += error.weights.not_overlap * overlap
    end
    if relation & _ACADEMIC_SAME_ATTENDEES != 0
        cost += error.weights.same_attendees * _same_attendees_distance(
            error,
            first,
            second,
            first_placement,
            second_placement,
        )
    end
    relation & _ACADEMIC_PRECEDENCE_FORWARD != 0 &&
        (cost += error.weights.precedence * _precedence_distance(
            error,
            first,
            second,
            first_placement,
            second_placement,
        ))
    relation & _ACADEMIC_PRECEDENCE_REVERSE != 0 &&
        (cost += error.weights.precedence * _precedence_distance(
            error,
            second,
            first,
            second_placement,
            first_placement,
        ))
    return cost
end

@inline function _meets_academic_day(placement::AcademicPlacement, day::Int)
    return iszero(placement.days) ? placement.day == day :
           !iszero(placement.days & (one(UInt64) << (day - 1)))
end

@inline function _meets_academic_week(placement::AcademicPlacement, week::Int)
    return !iszero(placement.weeks & (one(UInt64) << (week - 1)))
end

@inline function _work_day_distance(
    error::E,
    first::Int,
    second::Int,
    first_placement::AcademicPlacement,
    second_placement::AcademicPlacement,
    slots::Int,
) where {E}
    common_meetings = _common_academic_meetings(first_placement, second_placement)
    iszero(common_meetings) && return 0
    span = max(
        first_placement.start + _academic_duration(error, first, first_placement),
        second_placement.start + _academic_duration(error, second, second_placement),
    ) - min(first_placement.start, second_placement.start)
    return max(0, span - slots) * common_meetings
end

@inline function _min_gap_distance(
    error::E,
    first::Int,
    second::Int,
    first_placement::AcademicPlacement,
    second_placement::AcademicPlacement,
    gap::Int,
) where {E}
    common_meetings = _common_academic_meetings(first_placement, second_placement)
    iszero(common_meetings) && return 0
    forward = max(
        0,
        first_placement.start + _academic_duration(error, first, first_placement) + gap -
        second_placement.start,
    )
    reverse = max(
        0,
        second_placement.start + _academic_duration(error, second, second_placement) + gap -
        first_placement.start,
    )
    return min(forward, reverse) * common_meetings
end

function _collect_academic_intervals!(
    starts::Vector{Int},
    ends::Vector{Int},
    error::E,
    distribution::_CompiledAcademicDistribution,
    placements::P,
    day::Int,
    week::Int,
) where {E,P}
    count = 0
    @inbounds for activity in distribution.activities
        placement = placements[activity]
        _meets_academic_day(placement, day) || continue
        _meets_academic_week(placement, week) || continue
        count += 1
        starts[count] = placement.start
        ends[count] = placement.start + _academic_duration(error, activity, placement)
    end
    @inbounds for index = 2:count
        start = starts[index]
        stop = ends[index]
        cursor = index - 1
        while cursor >= 1 && starts[cursor] > start
            starts[cursor+1] = starts[cursor]
            ends[cursor+1] = ends[cursor]
            cursor -= 1
        end
        starts[cursor+1] = start
        ends[cursor+1] = stop
    end
    return count
end

function _academic_block_units!(
    starts::Vector{Int},
    ends::Vector{Int},
    count::Int,
    limit::Int,
    gap::Int,
    count_breaks::Bool,
)
    count <= 1 && return 0
    blocks = 0
    overlong = 0
    current_start = starts[1]
    current_end = ends[1]
    members = 1
    @inbounds for index = 2:count
        if starts[index] <= current_end + gap
            current_end = max(current_end, ends[index])
            members += 1
        else
            blocks += 1
            members >= 2 && current_end - current_start > limit && (overlong += 1)
            current_start = starts[index]
            current_end = ends[index]
            members = 1
        end
    end
    blocks += 1
    members >= 2 && current_end - current_start > limit && (overlong += 1)
    return count_breaks ? max(0, blocks - 1 - limit) : overlong
end

function _global_distribution_units!(
    error::E,
    distribution::_CompiledAcademicDistribution,
    placements::P,
    starts::Vector{Int},
    ends::Vector{Int},
) where {E,P}
    kind = distribution.kind
    if kind == _DIST_WORK_DAY || kind == _DIST_MIN_GAP
        units = 0
        activities = distribution.activities
        @inbounds for first_index = 1:(length(activities)-1)
            first = activities[first_index]
            for second_index = (first_index+1):length(activities)
                second = activities[second_index]
                units += if kind == _DIST_WORK_DAY
                    _work_day_distance(
                        error,
                        first,
                        second,
                        placements[first],
                        placements[second],
                        distribution.first_parameter,
                    )
                else
                    _min_gap_distance(
                        error,
                        first,
                        second,
                        placements[first],
                        placements[second],
                        distribution.first_parameter,
                    )
                end
            end
        end
        return units
    elseif kind == _DIST_MAX_DAYS
        used_days = 0
        for day = 1:error.day_count
            any_meeting = false
            @inbounds for activity in distribution.activities
                if _meets_academic_day(placements[activity], day)
                    any_meeting = true
                    break
                end
            end
            used_days += any_meeting
        end
        return max(0, used_days - distribution.first_parameter)
    elseif kind == _DIST_MAX_DAY_LOAD
        excess = 0
        for week = 1:error.week_count, day = 1:error.day_count
            load = 0
            @inbounds for activity in distribution.activities
                placement = placements[activity]
                _meets_academic_day(placement, day) || continue
                _meets_academic_week(placement, week) || continue
                load += _academic_duration(error, activity, placement)
            end
            excess += max(0, load - distribution.first_parameter)
        end
        return excess
    elseif kind == _DIST_MAX_BREAKS || kind == _DIST_MAX_BLOCK
        units = 0
        for week = 1:error.week_count, day = 1:error.day_count
            count = _collect_academic_intervals!(
                starts,
                ends,
                error,
                distribution,
                placements,
                day,
                week,
            )
            units += if kind == _DIST_MAX_BREAKS
                _academic_block_units!(
                    starts,
                    ends,
                    count,
                    distribution.first_parameter,
                    distribution.second_parameter,
                    true,
                )
            else
                _academic_block_units!(
                    starts,
                    ends,
                    count,
                    distribution.first_parameter,
                    distribution.second_parameter,
                    false,
                )
            end
        end
        return units
    end
    throw(ArgumentError("distribution kind $kind is not a global hard distribution"))
end

@inline function _global_distribution_weight(weights, kind)
    kind == _DIST_WORK_DAY && return weights.work_day
    kind == _DIST_MIN_GAP && return weights.min_gap
    kind == _DIST_MAX_DAYS && return weights.max_days
    kind == _DIST_MAX_DAY_LOAD && return weights.max_day_load
    kind == _DIST_MAX_BREAKS && return weights.max_breaks
    kind == _DIST_MAX_BLOCK && return weights.max_block
    return 1.0
end

function _global_distribution_cost!(
    error::TimetableConflictError,
    index::Int,
    placements::AbstractVector{AcademicPlacement},
    starts::Vector{Int},
    ends::Vector{Int},
)
    distribution = error.global_distributions[index]
    return _global_distribution_weight(error.weights, distribution.kind) *
           _global_distribution_units!(error, distribution, placements, starts, ends)
end

function (error::TimetableConflictError)(values; X = nothing)
    count = length(error.durations)
    length(values) == count ||
        throw(DimensionMismatch("the assignment must contain one placement per activity"))
    cost = 0.0
    @inbounds for activity = 1:count
        cost += _unary_cost(error, activity, values[activity])
    end
    @inbounds for pair in eachindex(error.pair_first)
        first = error.pair_first[pair]
        second = error.pair_second[pair]
        cost += _pair_cost(error, pair, values[first], values[second])
    end
    starts = Vector{Int}(undef, error.maximum_distribution_size)
    ends = similar(starts)
    @inbounds for distribution in eachindex(error.global_distributions)
        cost += _global_distribution_cost!(error, distribution, values, starts, ends)
    end
    return cost
end

mutable struct TimetableConflictInvariant <: Constraints.AbstractInvariant
    error::TimetableConflictError
    placements::Vector{AcademicPlacement}
    current::Float64
    activity_marks::Vector{UInt32}
    pair_marks::Vector{UInt32}
    distribution_marks::Vector{UInt32}
    changed_activities::Vector{Int}
    affected_pairs::Vector{Int}
    affected_distributions::Vector{Int}
    scratch_starts::Vector{Int}
    scratch_ends::Vector{Int}
    generation::UInt32
end

Constraints.supports_incremental(::TimetableConflictError) = true

function Constraints.initialize_invariant(
    error::TimetableConflictError,
    values;
    X = nothing,
    parameters...,
)
    placements = AcademicPlacement[value for value in values]
    length(placements) == length(error.durations) ||
        throw(DimensionMismatch("the assignment must contain one placement per activity"))
    changed_activities = Int[]
    affected_pairs = Int[]
    affected_distributions = Int[]
    sizehint!(changed_activities, length(placements))
    sizehint!(affected_pairs, length(error.pair_first))
    sizehint!(affected_distributions, length(error.global_distributions))
    return TimetableConflictInvariant(
        error,
        placements,
        error(placements),
        zeros(UInt32, length(placements)),
        zeros(UInt32, length(error.pair_first)),
        zeros(UInt32, length(error.global_distributions)),
        changed_activities,
        affected_pairs,
        affected_distributions,
        Vector{Int}(undef, error.maximum_distribution_size),
        Vector{Int}(undef, error.maximum_distribution_size),
        zero(UInt32),
    )
end

Constraints.invariant_value(invariant::TimetableConflictInvariant) = invariant.current

function _next_timetable_generation!(invariant::TimetableConflictInvariant, changes)
    generation = if invariant.generation == typemax(UInt32)
        fill!(invariant.activity_marks, zero(UInt32))
        fill!(invariant.pair_marks, zero(UInt32))
        fill!(invariant.distribution_marks, zero(UInt32))
        one(UInt32)
    else
        invariant.generation + one(UInt32)
    end
    invariant.generation = generation
    empty!(invariant.changed_activities)
    empty!(invariant.affected_pairs)
    empty!(invariant.affected_distributions)
    @inbounds for change in changes
        1 <= change.position <= length(invariant.placements) ||
            throw(BoundsError(invariant.placements, change.position))
        invariant.activity_marks[change.position] == generation && continue
        invariant.activity_marks[change.position] = generation
        push!(invariant.changed_activities, change.position)
    end
    error = invariant.error
    @inbounds for activity in invariant.changed_activities
        for pair in error.incident_pairs[activity]
            invariant.pair_marks[pair] == generation && continue
            invariant.pair_marks[pair] = generation
            push!(invariant.affected_pairs, pair)
        end
        for distribution in error.incident_distributions[activity]
            invariant.distribution_marks[distribution] == generation && continue
            invariant.distribution_marks[distribution] = generation
            push!(invariant.affected_distributions, distribution)
        end
    end
    return generation
end

function _affected_timetable_cost(invariant::TimetableConflictInvariant)
    error = invariant.error
    placements = invariant.placements
    cost = 0.0
    @inbounds for activity in invariant.changed_activities
        cost += _unary_cost(error, activity, placements[activity])
    end
    @inbounds for pair in invariant.affected_pairs
        first = error.pair_first[pair]
        second = error.pair_second[pair]
        cost += _pair_cost(error, pair, placements[first], placements[second])
    end
    @inbounds for distribution in invariant.affected_distributions
        cost += _global_distribution_cost!(
            error,
            distribution,
            placements,
            invariant.scratch_starts,
            invariant.scratch_ends,
        )
    end
    return cost
end

@inline function _apply_timetable_changes!(invariant, changes)
    @inbounds for change in changes
        invariant.placements[change.position] = change.new_value
    end
    return nothing
end

@inline function _revert_timetable_changes!(invariant, changes)
    @inbounds for change in Iterators.reverse(changes)
        invariant.placements[change.position] = change.old_value
    end
    return nothing
end

function Constraints.candidate_value(
    invariant::TimetableConflictInvariant,
    changes::Union{Tuple,AbstractVector},
)
    isempty(changes) && return invariant.current
    _next_timetable_generation!(invariant, changes)
    previous = _affected_timetable_cost(invariant)
    _apply_timetable_changes!(invariant, changes)
    try
        return invariant.current - previous +
               _affected_timetable_cost(invariant)
    finally
        _revert_timetable_changes!(invariant, changes)
    end
end

function Constraints.commit_changes!(
    invariant::TimetableConflictInvariant,
    changes::Union{Tuple,AbstractVector},
)
    isempty(changes) && return invariant.current
    _next_timetable_generation!(invariant, changes)
    previous = _affected_timetable_cost(invariant)
    _apply_timetable_changes!(invariant, changes)
    invariant.current += _affected_timetable_cost(invariant) - previous
    return invariant.current
end

function Constraints.rollback_changes!(
    invariant::TimetableConflictInvariant,
    changes::Union{Tuple,AbstractVector},
)
    isempty(changes) && return invariant.current
    _next_timetable_generation!(invariant, changes)
    current = _affected_timetable_cost(invariant)
    _revert_timetable_changes!(invariant, changes)
    invariant.current += _affected_timetable_cost(invariant) - current
    return invariant.current
end

function Constraints.rebuild_invariant!(invariant::TimetableConflictInvariant, values)
    length(values) == length(invariant.placements) ||
        throw(DimensionMismatch("the assignment must contain one placement per activity"))
    copyto!(invariant.placements, values)
    invariant.current = invariant.error(invariant.placements)
    return invariant.current
end

struct _TimetableDistributionContext
    durations::Vector{Int}
    travel_times::Matrix{Int}
    day_stride::Int
    day_count::Int
    week_count::Int
end

@inline function _academic_duration(
    context::_TimetableDistributionContext,
    activity::Int,
    placement::AcademicPlacement,
)
    return iszero(placement.duration) ? context.durations[activity] : placement.duration
end

@inline function _soft_pair_violated(
    context,
    kind,
    first,
    second,
    first_placement,
    second_placement,
    parameter,
)
    kind == _DIST_SAME_START &&
        return first_placement.start != second_placement.start
    kind == _DIST_SAME_TIME && return !iszero(_same_time_distance(
        first_placement,
        _academic_duration(context, first, first_placement),
        second_placement,
        _academic_duration(context, second, second_placement),
    ))
    kind == _DIST_DIFFERENT_TIME && return !iszero(_time_overlap_duration(
        first_placement,
        _academic_duration(context, first, first_placement),
        second_placement,
        _academic_duration(context, second, second_placement),
    ))
    kind == _DIST_SAME_DAYS &&
        return !iszero(_nested_day_distance(first_placement, second_placement))
    kind == _DIST_DIFFERENT_DAYS &&
        return !iszero(_common_academic_days(first_placement, second_placement))
    kind == _DIST_SAME_WEEKS && return !iszero(_nested_mask_distance(
        first_placement.weeks,
        second_placement.weeks,
    ))
    kind == _DIST_DIFFERENT_WEEKS &&
        return !iszero(first_placement.weeks & second_placement.weeks)
    kind == _DIST_SAME_ROOM && return first_placement.room != second_placement.room
    kind == _DIST_DIFFERENT_ROOM && return first_placement.room == second_placement.room
    kind == _DIST_OVERLAP && return !iszero(_overlap_distance(
        first_placement,
        _academic_duration(context, first, first_placement),
        second_placement,
        _academic_duration(context, second, second_placement),
    ))
    kind == _DIST_NOT_OVERLAP && return !iszero(_overlap_duration(
        first_placement,
        _academic_duration(context, first, first_placement),
        second_placement,
        _academic_duration(context, second, second_placement),
    ))
    kind == _DIST_SAME_ATTENDEES && return !iszero(_same_attendees_distance(
        context,
        first,
        second,
        first_placement,
        second_placement,
    ))
    kind == _DIST_PRECEDENCE && return !iszero(_precedence_distance(
        context,
        first,
        second,
        first_placement,
        second_placement,
    ))
    kind == _DIST_WORK_DAY && return !iszero(_work_day_distance(
        context,
        first,
        second,
        first_placement,
        second_placement,
        parameter,
    ))
    kind == _DIST_MIN_GAP && return !iszero(_min_gap_distance(
        context,
        first,
        second,
        first_placement,
        second_placement,
        parameter,
    ))
    throw(ArgumentError("distribution kind $kind is not pairwise"))
end

function _soft_distribution_units!(context, distribution, placements, starts, ends)
    kind = distribution.kind
    if kind < _DIST_MAX_DAYS
        units = 0
        activities = distribution.activities
        @inbounds for first_index = 1:(length(activities)-1)
            first = activities[first_index]
            for second_index = (first_index+1):length(activities)
                second = activities[second_index]
                units += _soft_pair_violated(
                    context,
                    kind,
                    first,
                    second,
                    placements[first],
                    placements[second],
                    distribution.first_parameter,
                )
            end
        end
        return units
    end
    return _global_distribution_units!(context, distribution, placements, starts, ends)
end

mutable struct TimetablePreferenceObjective <: Function
    placement_weight::Float64
    distribution_weight::Float64
    context::_TimetableDistributionContext
    distributions::Vector{_CompiledAcademicDistribution}
    scratch_starts::Vector{Int}
    scratch_ends::Vector{Int}
end

function TimetablePreferenceObjective(
    context::_TimetableDistributionContext,
    distributions = _CompiledAcademicDistribution[];
    placement_weight::Real = 1.0,
    distribution_weight::Real = 1.0,
)
    placement_weight >= 0 && isfinite(placement_weight) ||
        throw(ArgumentError("placement_weight must be finite and non-negative"))
    distribution_weight >= 0 && isfinite(distribution_weight) ||
        throw(ArgumentError("distribution_weight must be finite and non-negative"))
    local_distributions = _CompiledAcademicDistribution[distribution for distribution in distributions]
    maximum_size = maximum(
        (length(distribution.activities) for distribution in local_distributions);
        init = 0,
    )
    return TimetablePreferenceObjective(
        Float64(placement_weight),
        Float64(distribution_weight),
        context,
        local_distributions,
        Vector{Int}(undef, maximum_size),
        Vector{Int}(undef, maximum_size),
    )
end

function (objective::TimetablePreferenceObjective)(values)
    cost = 0.0
    @inbounds for placement in values
        cost += objective.placement_weight * placement.penalty
    end
    for distribution in objective.distributions
        units = _soft_distribution_units!(
            objective.context,
            distribution,
            values,
            objective.scratch_starts,
            objective.scratch_ends,
        )
        contribution = distribution.penalty * units
        if distribution.kind in (_DIST_MAX_DAY_LOAD, _DIST_MAX_BREAKS, _DIST_MAX_BLOCK)
            contribution = div(contribution, objective.context.week_count)
        end
        cost += objective.distribution_weight * contribution
    end
    return cost
end

"""
    academic_timetable(activities, room_capacities;
        weights=TimetableConflictWeights(), distributions=(), room_unavailable=(),
        room_travel=(), day_count=nothing, week_count=nothing,
        placement_weight=1, distribution_weight=1)

Build a generic academic timetabling COP. Each activity becomes one compound decision
variable. Placements that cannot satisfy room capacity are removed before search, one global
incremental constraint handles resource and distribution conflicts, and soft placement
preferences form a separate objective. Room-unavailable placements are also removed from the
search domain while remaining represented by the exact error function.
"""
function academic_timetable(
    activities,
    room_capacities;
    weights = TimetableConflictWeights(),
    distributions = (),
    room_unavailable = (),
    room_travel = (),
    day_count = nothing,
    week_count = nothing,
    placement_weight::Real = 1.0,
    distribution_weight::Real = 1.0,
)
    local_activities = collect(activities)
    isempty(local_activities) && throw(ArgumentError("at least one activity is required"))
    capacities = Int[capacity for capacity in room_capacities]
    local_distributions = collect(distributions)
    local_unavailable = AcademicRoomUnavailable[period for period in room_unavailable]
    local_travel = AcademicRoomTravel[travel for travel in room_travel]
    error = TimetableConflictError(
        local_activities,
        capacities;
        weights,
        distributions = local_distributions,
        room_unavailable = local_unavailable,
        room_travel = local_travel,
        day_count,
        week_count,
    )
    identifiers = Dict{Any,Int}(
        activity.id => index for (index, activity) in pairs(local_activities)
    )
    soft_distributions = _CompiledAcademicDistribution[]
    for distribution in local_distributions
        distribution isa AcademicDistributionSpec || continue
        distribution.required && continue
        push!(
            soft_distributions,
            _compile_academic_distribution(
                identifiers,
                distribution.constraint;
                penalty = distribution.penalty,
            ),
        )
    end
    model = LS.model(kind = :academic_timetable)
    for (index, activity) in pairs(local_activities)
        placements = filter(activity.placements) do placement
            placement.room <= length(capacities) &&
                iszero(_unary_cost(error, index, placement))
        end
        isempty(placements) && throw(
            ArgumentError(
                "activity $(repr(activity.id)) has no capacity-compatible placement",
            ),
        )
        LS.variable!(model, ConstraintDomains.arbitrary_domain(placements))
    end
    LS.constraint!(model, error, collect(eachindex(local_activities)))
    context = _TimetableDistributionContext(
        error.durations,
        error.travel_times,
        error.day_stride,
        error.day_count,
        error.week_count,
    )
    LS.objective!(
        model,
        TimetablePreferenceObjective(
            context,
            soft_distributions;
            placement_weight,
            distribution_weight,
        ),
    )
    return model
end

@testitem "Academic timetabling invariant is exact and atomic" default_imports = false begin
    import ConstraintModels as CM
    import Constraints as C
    import Test: @test, @test_throws

    p11 = CM.AcademicPlacement(1, 0, 1)
    p12 = CM.AcademicPlacement(1, 2, 1)
    p21 = CM.AcademicPlacement(1, 1, 2)
    p22 = CM.AcademicPlacement(2, 0, 1)
    activities = [
        CM.AcademicActivity(
            :a,
            2,
            [p11, p12, p22];
            demand = 12,
            instructors = [1],
            groups = [1],
        ),
        CM.AcademicActivity(
            :b,
            2,
            [p11, p21, p22];
            demand = 8,
            instructors = [1],
            groups = [2],
        ),
        CM.AcademicActivity(
            :c,
            2,
            [p11, p21, p22];
            demand = 8,
            instructors = [2],
            groups = [1],
        ),
    ]
    error = CM.TimetableConflictError(activities, [10, 20])
    values = [p11, p21, p22]
    invariant = C.initialize_invariant(error, values)
    @test C.supports_incremental(error)
    @test C.invariant_value(invariant) == error(values) == 5.0

    domains = getfield.(activities, :placements)
    for assignment in Iterators.product(domains...)
        local_values = collect(assignment)
        trial = C.initialize_invariant(error, local_values)
        @test C.invariant_value(trial) == error(local_values)
        for position in eachindex(local_values), placement in domains[position]
            change = C.InvariantChange(position, local_values[position], placement)
            candidate = copy(local_values)
            candidate[position] = placement
            @test C.candidate_value(trial, change) == error(candidate)
            @test trial.placements == local_values
        end
    end

    changes = (C.InvariantChange(1, p11, p12), C.InvariantChange(2, p21, p22))
    candidate = [p12, p22, p22]
    @test C.candidate_value(invariant, changes) == error(candidate)
    @test C.commit_changes!(invariant, changes) == error(candidate)
    @test invariant.placements == candidate
    @test C.rollback_changes!(invariant, changes) == error(values)
    @test invariant.placements == values
    @test C.rebuild_invariant!(invariant, candidate) == error(candidate)

    @test_throws ArgumentError CM.AcademicPlacement(0, 0, 1)
    @test_throws ArgumentError CM.AcademicActivity(:empty, 1, CM.AcademicPlacement[])
    @test_throws ArgumentError CM.AcademicActivity(
        :duplicate,
        1,
        [CM.AcademicPlacement(1, 0, 1, 0), CM.AcademicPlacement(1, 0, 1, 1)],
    )
    @test_throws DimensionMismatch C.rebuild_invariant!(invariant, [p11])
end

@testitem "Academic timetabling model separates feasibility and preferences" default_imports =
    false begin
    import ConstraintModels as CM
    import LocalSearchSolvers as LS
    import Test: @test, @test_throws

    a = CM.AcademicActivity(
        :a,
        2,
        [
            CM.AcademicPlacement(1, 0, 1, 8),
            CM.AcademicPlacement(1, 0, 2, 3),
            CM.AcademicPlacement(2, 0, 2, 1),
        ];
        demand = 12,
        instructors = [1],
    )
    b = CM.AcademicActivity(
        :b,
        2,
        [CM.AcademicPlacement(1, 0, 2, 2), CM.AcademicPlacement(2, 0, 2, 4)];
        demand = 8,
        instructors = [1],
    )
    model = CM.academic_timetable([a, b], [10, 20])
    @test LS.get_kind(model) == :academic_timetable
    @test LS.length_vars(model) == 2
    @test LS.length_cons(model) == 1
    @test length(LS.get_objectives(model)) == 1
    @test length(LS.get_domain(model, 1)) == 2
    @test all(placement -> placement.room == 2, LS.get_domain(model, 1))

    values = [first(LS.get_domain(model, 1)), first(LS.get_domain(model, 2))]
    @test LS.compute_costs(model, values, zeros(Float64, 0, 0)) > 0
    @test LS.compute_objective(model, values) ==
          sum(placement.penalty for placement in values)
    @test_throws ArgumentError CM.academic_timetable(
        [CM.AcademicActivity(:large, 1, [CM.AcademicPlacement(1, 0, 1)]; demand = 30)],
        [20],
    )
end

@testitem "Academic distribution semantics follow the bounded ITC slice" default_imports =
    false begin
    import ConstraintModels as CM
    import Test: @test, @test_throws

    function activity(id, duration, placements)
        return CM.AcademicActivity(id, duration, placements; demand = 1)
    end

    a_nested = CM.AcademicPlacement(1, 2, 1)
    b_nested_other_day = CM.AcademicPlacement(5, 3, 2)
    b_partial_other_day = CM.AcademicPlacement(5, 5, 2)
    a = activity(:a, 4, [a_nested])
    b = activity(:b, 2, [b_nested_other_day, b_partial_other_day])

    same_time = CM.TimetableConflictError(
        [a, b],
        [10, 10];
        distributions = [CM.AcademicSameTime([:a, :b])],
    )
    @test same_time([a_nested, b_nested_other_day]) == 0
    @test same_time([a_nested, b_partial_other_day]) > 0

    different_time = CM.TimetableConflictError(
        [a, b],
        [10, 10];
        distributions = [CM.AcademicDifferentTime([:a, :b])],
    )
    @test different_time([a_nested, b_partial_other_day]) > 0
    @test different_time([a_nested, CM.AcademicPlacement(5, 6, 2)]) == 0

    same_room = CM.TimetableConflictError(
        [a, b],
        [10, 10];
        distributions = [CM.AcademicSameRoom([:a, :b])],
    )
    @test same_room([a_nested, CM.AcademicPlacement(5, 3, 1)]) == 0
    @test same_room([a_nested, b_nested_other_day]) > 0

    different_room = CM.TimetableConflictError(
        [a, b],
        [10, 10];
        distributions = [CM.AcademicDifferentRoom([:a, :b])],
    )
    @test different_room([a_nested, b_nested_other_day]) == 0
    @test different_room([a_nested, CM.AcademicPlacement(5, 3, 1)]) > 0

    before = CM.AcademicPlacement(1, 0, 1)
    after = CM.AcademicPlacement(1, 4, 2)
    next_day = CM.AcademicPlacement(2, 0, 2)
    precedence_activities = [activity(:a, 4, [before]), activity(:b, 2, [after, next_day])]
    precedence = CM.TimetableConflictError(
        precedence_activities,
        [10, 10];
        distributions = [CM.AcademicPrecedence([:a, :b])],
    )
    @test precedence([before, after]) == 0
    @test precedence([before, next_day]) == 0
    @test precedence([CM.AcademicPlacement(2, 0, 1), after]) > 0

    ordered = [
        activity(:a, 1, [CM.AcademicPlacement(1, 0, 1)]),
        activity(:b, 1, [CM.AcademicPlacement(2, 0, 2)]),
        activity(:c, 1, [CM.AcademicPlacement(3, 0, 3)]),
    ]
    ordered_precedence = CM.TimetableConflictError(
        ordered,
        [10, 10, 10];
        distributions = [CM.AcademicPrecedence([:a, :b, :c])],
    )
    @test ordered_precedence([only(item.placements) for item in ordered]) == 0
    @test ordered_precedence([
        CM.AcademicPlacement(1, 0, 1),
        CM.AcademicPlacement(2, 0, 2),
        CM.AcademicPlacement(1, 1, 3),
    ]) > 0

    unavailable = CM.AcademicRoomUnavailable(1, 1, 3, 3)
    unavailable_error = CM.TimetableConflictError(
        [activity(:a, 2, [CM.AcademicPlacement(1, 2, 1)])],
        [10];
        room_unavailable = [unavailable],
    )
    @test unavailable_error([CM.AcademicPlacement(1, 0, 1)]) == 0
    @test unavailable_error([CM.AcademicPlacement(1, 2, 1)]) > 0

    @test_throws ArgumentError CM.AcademicSameTime([:a])
    @test_throws ArgumentError CM.AcademicPrecedence([:a, :a])
    @test_throws ArgumentError CM.TimetableConflictError(
        [a, activity(:a, 2, [b_nested_other_day])],
        [10, 10],
    )
    @test_throws ArgumentError CM.TimetableConflictError(
        [a, b],
        [10, 10];
        distributions = [CM.AcademicSameRoom([:a, :missing])],
    )
    @test_throws ArgumentError CM.TimetableConflictError(
        [a, b],
        [10, 10];
        distributions = [:unsupported],
    )
    @test_throws BoundsError CM.TimetableConflictError(
        [a],
        [10];
        room_unavailable = [CM.AcademicRoomUnavailable(2, 1, 0, 1)],
    )
end

@testitem "Academic multi-pattern placements preserve exact resource quantities" default_imports =
    false begin
    import ConstraintModels as CM
    import Test: @test, @test_throws

    first = CM.AcademicPlacement(0, 1; days = [1, 3], weeks = [1, 2], penalty = 2)
    second = CM.AcademicPlacement(1, 1; days = [1, 3], weeks = [2, 3])
    @test first.day == 1
    @test count_ones(first.days) == 2
    @test count_ones(first.weeks) == 2
    @test first.penalty == 2
    @test CM.AcademicPlacement(3, 0, 1).days == UInt64(0x04)

    short = CM.AcademicPlacement(1, 0, 1; duration = 2)
    long = CM.AcademicPlacement(1, 0, 1; duration = 3)
    adjacent = CM.AcademicPlacement(1, 2, 1; duration = 1)
    duration_activities = [
        CM.AcademicActivity(:duration, 2, [short, long]),
        CM.AcademicActivity(:adjacent, 1, [adjacent]),
    ]
    duration_error = CM.TimetableConflictError(duration_activities, [10])
    @test duration_error([short, adjacent]) == 0
    @test duration_error([long, adjacent]) == 1

    # The pre-existing single-day constructor remains valid beyond the compact-mask range.
    legacy_day = CM.AcademicPlacement(65, 0, 1)
    next_legacy_day = CM.AcademicPlacement(66, 0, 1)
    @test legacy_day.day == 65
    @test iszero(legacy_day.days)
    legacy_activities = [
        CM.AcademicActivity(:legacy_a, 2, [legacy_day]),
        CM.AcademicActivity(:legacy_b, 2, [legacy_day, next_legacy_day]),
    ]
    legacy_unavailable = CM.AcademicRoomUnavailable(1, 65, 0, 1)
    legacy_error = CM.TimetableConflictError(
        legacy_activities,
        [10];
        room_unavailable = [legacy_unavailable],
    )
    @test legacy_error([legacy_day, legacy_day]) == 4.0
    @test legacy_error([legacy_day, next_legacy_day]) == 1.0

    activities = [
        CM.AcademicActivity(:a, 2, [first]),
        CM.AcademicActivity(:b, 2, [second]),
    ]
    resource_error = CM.TimetableConflictError(activities, [10])
    @test resource_error([first, second]) == 2.0
    @test length(resource_error.pair_first) == 1

    capacity_activity = CM.AcademicActivity(:capacity, 2, [first]; demand = 2)
    capacity_error = CM.TimetableConflictError([capacity_activity], [1])
    @test capacity_error([first]) == 8.0

    unavailable = CM.AcademicRoomUnavailable(
        1,
        1,
        1;
        days = [3],
        weeks = [2],
    )
    unavailable_error = CM.TimetableConflictError(
        [CM.AcademicActivity(:a, 2, [first])],
        [10];
        room_unavailable = [unavailable],
    )
    @test unavailable_error([first]) == 1.0

    distinct_patterns = CM.AcademicActivity(
        :patterns,
        1,
        [
            CM.AcademicPlacement(0, 1; days = [1], weeks = [1]),
            CM.AcademicPlacement(0, 1; days = [1], weeks = [2]),
        ],
    )
    @test length(distinct_patterns.placements) == 2

    sparse = [
        CM.AcademicActivity(
            id,
            1,
            [CM.AcademicPlacement(1, 0, id)];
            instructors = [id],
            groups = [id],
        ) for id = 1:4
    ]
    @test isempty(CM.TimetableConflictError(sparse, fill(10, 4)).pair_first)
    linked = CM.TimetableConflictError(
        sparse,
        fill(10, 4);
        distributions = [CM.AcademicSameStart([1, 4])],
    )
    @test length(linked.pair_first) == 1

    @test_throws ArgumentError CM.AcademicPlacement(0, 1; days = Int[])
    @test_throws ArgumentError CM.AcademicPlacement(0, 1; days = [65])
    @test_throws ArgumentError CM.AcademicRoomTravel(1, 1, 2)
    @test_throws ArgumentError CM.AcademicRoomTravel(1, 2, -1)
    @test_throws ArgumentError CM.TimetableConflictError(
        sparse[1:2],
        [10, 10];
        room_travel = [
            CM.AcademicRoomTravel(1, 2, 0),
            CM.AcademicRoomTravel(2, 1, 1),
        ],
    )
end

@testitem "Academic calendar distributions follow detailed ITC semantics" default_imports =
    false begin
    import ConstraintModels as CM
    import Test: @test

    a_domain = CM.AcademicPlacement(0, 1; days = [1], weeks = [1])
    b_domain = CM.AcademicPlacement(0, 2; days = [2], weeks = [2])
    activities = [
        CM.AcademicActivity(:a, 2, [a_domain]),
        CM.AcademicActivity(:b, 2, [b_domain]),
    ]

    function relation_cost(relation, first, second; travel = ())
        error = CM.TimetableConflictError(
            activities,
            [10, 10];
            distributions = [relation],
            room_travel = travel,
        )
        return error([first, second])
    end

    a = CM.AcademicPlacement(2, 1; days = [1, 3], weeks = [1, 3])
    same_start = CM.AcademicPlacement(2, 2; days = [2], weeks = [2])
    later_start = CM.AcademicPlacement(3, 2; days = [2], weeks = [2])
    @test relation_cost(CM.AcademicSameStart([:a, :b]), a, same_start) == 0
    @test relation_cost(CM.AcademicSameStart([:a, :b]), a, later_start) > 0

    subset_days = CM.AcademicPlacement(2, 2; days = [1], weeks = [2])
    crossing_days = CM.AcademicPlacement(2, 2; days = [1, 2], weeks = [2])
    disjoint_days = CM.AcademicPlacement(2, 2; days = [2], weeks = [2])
    @test relation_cost(CM.AcademicSameDays([:a, :b]), a, subset_days) == 0
    @test relation_cost(CM.AcademicSameDays([:a, :b]), a, crossing_days) > 0
    @test relation_cost(CM.AcademicDifferentDays([:a, :b]), a, disjoint_days) == 0
    @test relation_cost(CM.AcademicDifferentDays([:a, :b]), a, subset_days) > 0

    subset_weeks = CM.AcademicPlacement(2, 2; days = [2], weeks = [1])
    crossing_weeks = CM.AcademicPlacement(2, 2; days = [2], weeks = [1, 2])
    disjoint_weeks = CM.AcademicPlacement(2, 2; days = [2], weeks = [2])
    @test relation_cost(CM.AcademicSameWeeks([:a, :b]), a, subset_weeks) == 0
    @test relation_cost(CM.AcademicSameWeeks([:a, :b]), a, crossing_weeks) > 0
    @test relation_cost(CM.AcademicDifferentWeeks([:a, :b]), a, disjoint_weeks) == 0
    @test relation_cost(CM.AcademicDifferentWeeks([:a, :b]), a, subset_weeks) > 0

    overlapping = CM.AcademicPlacement(3, 2; days = [3], weeks = [3])
    touching = CM.AcademicPlacement(4, 2; days = [3], weeks = [3])
    alternate_week = CM.AcademicPlacement(3, 2; days = [3], weeks = [2])
    @test relation_cost(CM.AcademicOverlap([:a, :b]), a, overlapping) == 0
    @test relation_cost(CM.AcademicOverlap([:a, :b]), a, touching) > 0
    @test relation_cost(CM.AcademicOverlap([:a, :b]), a, alternate_week) > 0
    @test relation_cost(CM.AcademicNotOverlap([:a, :b]), a, overlapping) > 0
    @test relation_cost(CM.AcademicNotOverlap([:a, :b]), a, touching) == 0
    @test relation_cost(CM.AcademicNotOverlap([:a, :b]), a, alternate_week) == 0

    travel = [CM.AcademicRoomTravel(1, 2, 2)]
    reachable = CM.AcademicPlacement(6, 2; days = [1], weeks = [1])
    too_close = CM.AcademicPlacement(5, 2; days = [1], weeks = [1])
    other_week = CM.AcademicPlacement(2, 2; days = [1], weeks = [2])
    relation = CM.AcademicSameAttendees([:a, :b])
    @test relation_cost(relation, a, reachable; travel) == 0
    @test relation_cost(relation, a, too_close; travel) > 0
    @test relation_cost(relation, a, other_week; travel) == 0

    earlier_week = CM.AcademicPlacement(8, 1; days = [5], weeks = [1])
    later_week = CM.AcademicPlacement(0, 2; days = [1], weeks = [2])
    precedence = CM.AcademicPrecedence([:a, :b])
    @test relation_cost(precedence, earlier_week, later_week) == 0
    @test relation_cost(precedence, later_week, earlier_week) > 0

    # Calendar relations depend on relative positions, not on the absolute time origin.
    original_first = CM.AcademicPlacement(2, 1; days = [1, 3], weeks = [1, 2])
    original_second = CM.AcademicPlacement(3, 2; days = [1], weeks = [2])
    shifted_first = CM.AcademicPlacement(9, 1; days = [1, 3], weeks = [1, 2])
    shifted_second = CM.AcademicPlacement(10, 2; days = [1], weeks = [2])
    relations = [
        CM.AcademicPrecedence([:a, :b]),
        CM.AcademicSameTime([:a, :b]),
        CM.AcademicDifferentTime([:a, :b]),
        CM.AcademicSameRoom([:a, :b]),
        CM.AcademicDifferentRoom([:a, :b]),
        CM.AcademicSameStart([:a, :b]),
        CM.AcademicSameDays([:a, :b]),
        CM.AcademicDifferentDays([:a, :b]),
        CM.AcademicSameWeeks([:a, :b]),
        CM.AcademicDifferentWeeks([:a, :b]),
        CM.AcademicOverlap([:a, :b]),
        CM.AcademicNotOverlap([:a, :b]),
        CM.AcademicSameAttendees([:a, :b]),
    ]
    for relation in relations
        @test relation_cost(relation, original_first, original_second; travel) ==
              relation_cost(relation, shifted_first, shifted_second; travel)
    end
end

@testitem "Academic distribution batch invariant matches exhaustive recomputation" default_imports =
    false begin
    import ConstraintModels as CM
    import Constraints as C
    import LocalSearchSolvers as LS
    import Test: @test

    domains = [
        [
            CM.AcademicPlacement(0, 1; days = [1, 3], weeks = [1, 2]),
            CM.AcademicPlacement(3, 2; days = [1], weeks = [2]),
            CM.AcademicPlacement(0, 1; days = [2], weeks = [1, 3]),
            CM.AcademicPlacement(4, 2; days = [2, 3], weeks = [3]),
        ],
        [
            CM.AcademicPlacement(1, 2; days = [1], weeks = [1, 2]),
            CM.AcademicPlacement(4, 1; days = [1, 3], weeks = [2]),
            CM.AcademicPlacement(1, 1; days = [2], weeks = [1, 3]),
            CM.AcademicPlacement(0, 2; days = [3], weeks = [3]),
        ],
        [
            CM.AcademicPlacement(2, 1; days = [1, 2], weeks = [1]),
            CM.AcademicPlacement(6, 2; days = [1], weeks = [2, 3]),
            CM.AcademicPlacement(2, 2; days = [2], weeks = [2]),
            CM.AcademicPlacement(2, 1; days = [3], weeks = [3]),
        ],
    ]
    activities = [
        CM.AcademicActivity(:a, 3, domains[1]; demand = 2),
        CM.AcademicActivity(:b, 2, domains[2]; demand = 2),
        CM.AcademicActivity(:c, 1, domains[3]; demand = 2),
    ]
    distributions = [
        CM.AcademicPrecedence([:a, :b, :c]),
        CM.AcademicSameTime([:a, :b]),
        CM.AcademicDifferentTime([:b, :c]),
        CM.AcademicSameRoom([:a, :c]),
        CM.AcademicDifferentRoom([:a, :b]),
        CM.AcademicSameStart([:a, :c]),
        CM.AcademicSameDays([:a, :b]),
        CM.AcademicDifferentDays([:b, :c]),
        CM.AcademicSameWeeks([:a, :c]),
        CM.AcademicDifferentWeeks([:a, :b]),
        CM.AcademicOverlap([:a, :b]),
        CM.AcademicNotOverlap([:b, :c]),
        CM.AcademicSameAttendees([:a, :c]),
    ]
    unavailable = [CM.AcademicRoomUnavailable(2, 1, 3; days = [2], weeks = [2])]
    travel = [CM.AcademicRoomTravel(1, 2, 2)]
    error = CM.TimetableConflictError(
        activities,
        [10, 10];
        distributions,
        room_unavailable = unavailable,
        room_travel = travel,
    )

    for assignment in Iterators.product(domains...)
        values = collect(assignment)
        invariant = C.initialize_invariant(error, values)
        @test C.invariant_value(invariant) == error(values)
        for position in eachindex(values), replacement in domains[position]
            change = C.InvariantChange(position, values[position], replacement)
            candidate = copy(values)
            candidate[position] = replacement
            @test C.candidate_value(invariant, change) == error(candidate)
            @test invariant.placements == values
        end

        changes = (
            C.InvariantChange(1, values[1], domains[1][end]),
            C.InvariantChange(2, values[2], domains[2][end]),
        )
        candidate = copy(values)
        candidate[1] = domains[1][end]
        candidate[2] = domains[2][end]
        @test C.candidate_value(invariant, changes) == error(candidate)
        @test C.commit_changes!(invariant, changes) == error(candidate)
        @test C.rollback_changes!(invariant, changes) == error(values)
        @test invariant.placements == values
    end

    model = CM.academic_timetable(
        activities,
        [10, 10];
        distributions,
        room_unavailable = unavailable,
        room_travel = travel,
    )
    @test length(LS.get_domain(model, 3)) == 3
    @test CM.AcademicPlacement(2, 2; days = [2], weeks = [2]) ∉ LS.get_domain(model, 3)
end

@testitem "Academic global ITC distributions are exact and incremental" default_imports =
    false begin
    import ConstraintModels as CM
    import Constraints as C
    import Test: @test

    a_early = CM.AcademicPlacement(0, 1; days = [1], weeks = [1])
    a_late = CM.AcademicPlacement(4, 1; days = [2], weeks = [2])
    b_close = CM.AcademicPlacement(3, 2; days = [1], weeks = [1])
    b_far = CM.AcademicPlacement(5, 2; days = [2], weeks = [2])
    activities = [
        CM.AcademicActivity(:a, 3, [a_early, a_late]),
        CM.AcademicActivity(:b, 3, [b_close, b_far]),
    ]

    function hard_cost(distribution, first, second)
        error = CM.TimetableConflictError(
            activities,
            [10, 10];
            distributions = [distribution],
            day_count = 2,
            week_count = 2,
        )
        return error([first, second])
    end

    @test hard_cost(CM.AcademicWorkDay([:a, :b], 5), a_early, b_close) == 1
    @test hard_cost(CM.AcademicWorkDay([:a, :b], 5), a_early, b_far) == 0
    @test hard_cost(CM.AcademicMinGap([:a, :b], 1), a_early, b_close) == 1
    @test hard_cost(CM.AcademicMinGap([:a, :b], 1), a_early,
        CM.AcademicPlacement(4, 2; days = [1], weeks = [1])) == 0
    @test hard_cost(CM.AcademicMaxDays([:a, :b], 1), a_early, b_far) == 1
    @test hard_cost(CM.AcademicMaxDays([:a, :b], 1), a_early, b_close) == 0
    @test hard_cost(CM.AcademicMaxDayLoad([:a, :b], 5), a_early, b_close) == 1
    @test hard_cost(CM.AcademicMaxDayLoad([:a, :b], 5), a_early, b_far) == 0

    separated = CM.AcademicPlacement(5, 2; days = [1], weeks = [1])
    linked = CM.AcademicPlacement(4, 2; days = [1], weeks = [1])
    @test hard_cost(CM.AcademicMaxBreaks([:a, :b], 0, 1), a_early, separated) == 1
    @test hard_cost(CM.AcademicMaxBreaks([:a, :b], 0, 1), a_early, linked) == 0
    @test hard_cost(CM.AcademicMaxBlock([:a, :b], 5, 1), a_early, linked) == 1
    # ITC MaxBlock ignores a block containing only one class, even if that class is long.
    @test hard_cost(CM.AcademicMaxBlock([:a, :b], 2, 1), a_early, b_far) == 0

    distributions = [
        CM.AcademicWorkDay([:a, :b], 5),
        CM.AcademicMinGap([:a, :b], 1),
        CM.AcademicMaxDays([:a, :b], 1),
        CM.AcademicMaxDayLoad([:a, :b], 5),
        CM.AcademicMaxBreaks([:a, :b], 0, 1),
        CM.AcademicMaxBlock([:a, :b], 5, 1),
    ]
    error = CM.TimetableConflictError(
        activities,
        [10, 10];
        distributions,
        day_count = 2,
        week_count = 2,
    )
    domains = getfield.(activities, :placements)
    for assignment in Iterators.product(domains...)
        values = collect(assignment)
        invariant = C.initialize_invariant(error, values)
        @test C.invariant_value(invariant) == error(values)
        for position in eachindex(values), replacement in domains[position]
            change = C.InvariantChange(position, values[position], replacement)
            candidate = copy(values)
            candidate[position] = replacement
            @test C.candidate_value(invariant, change) == error(candidate)
            @test invariant.placements == values
        end
        changes = (
            C.InvariantChange(1, values[1], domains[1][end]),
            C.InvariantChange(2, values[2], domains[2][end]),
        )
        candidate = [domains[1][end], domains[2][end]]
        @test C.candidate_value(invariant, changes) == error(candidate)
        @test C.commit_changes!(invariant, changes) == error(candidate)
        @test C.rollback_changes!(invariant, changes) == error(values)
    end
end

@testitem "Academic soft distributions remain objective-only" default_imports = false begin
    import ConstraintModels as CM
    import LocalSearchSolvers as LS
    import Test: @test, @test_throws

    placements = [
        CM.AcademicPlacement(0, 1; days = [1], weeks = [1], penalty = 1),
        CM.AcademicPlacement(4, 2; days = [2], weeks = [1], penalty = 2),
        CM.AcademicPlacement(7, 3; days = [2], weeks = [2], penalty = 3),
    ]
    activities = [
        CM.AcademicActivity(:a, 2, [placements[1]]),
        CM.AcademicActivity(:b, 2, [placements[2]]),
        CM.AcademicActivity(:c, 2, [placements[3]]),
    ]
    soft = [
        CM.AcademicDistributionSpec(CM.AcademicSameStart([:a, :b, :c]);
            required = false, penalty = 2),
        CM.AcademicDistributionSpec(CM.AcademicMaxDays([:a, :b, :c], 1);
            required = false, penalty = 5),
        CM.AcademicDistributionSpec(CM.AcademicMaxDayLoad([:a, :b, :c], 1);
            required = false, penalty = 3),
    ]
    model = CM.academic_timetable(
        activities,
        [10, 10, 10];
        distributions = soft,
        day_count = 2,
        week_count = 2,
    )
    @test LS.compute_costs(model, placements, zeros(Float64, 0, 0)) == 0
    # placements 6 + SameStart 3*2 + MaxDays 1*5 + div(MaxDayLoad 3*3, 2) = 21
    @test LS.compute_objective(model, placements) == 21

    break_activities = [
        CM.AcademicActivity(:a, 1,
            [CM.AcademicPlacement(0, 1; days = [1], weeks = [1])]),
        CM.AcademicActivity(:b, 1,
            [CM.AcademicPlacement(4, 2; days = [1], weeks = [1])]),
    ]
    block_soft = [
        CM.AcademicDistributionSpec(CM.AcademicMaxBreaks([:a, :b], 0, 1);
            required = false, penalty = 5),
        CM.AcademicDistributionSpec(CM.AcademicMaxBlock([:a, :b], 3, 3);
            required = false, penalty = 5),
    ]
    block_values = only.(getfield.(break_activities, :placements))
    block_model = CM.academic_timetable(
        break_activities,
        [10, 10];
        distributions = block_soft,
        day_count = 1,
        week_count = 2,
    )
    @test LS.compute_costs(block_model, block_values, zeros(Float64, 0, 0)) == 0
    @test LS.compute_objective(block_model, block_values) == 4

    required_model = CM.academic_timetable(
        activities,
        [10, 10, 10];
        distributions = [CM.AcademicDistributionSpec(
            CM.AcademicSameStart([:a, :b]); required = true,
        )],
        day_count = 2,
        week_count = 2,
    )
    @test LS.compute_costs(required_model, placements, zeros(Float64, 0, 0)) > 0
    @test_throws ArgumentError CM.AcademicDistributionSpec(
        CM.AcademicSameStart([:a, :b]); required = false,
    )
end
