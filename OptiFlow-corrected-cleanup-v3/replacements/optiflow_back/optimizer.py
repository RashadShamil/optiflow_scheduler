"""CP-SAT production scheduler for OptiFlow.

The optimizer plans a manager-selected job together with other movable scheduled
work. It may rearrange not-started/unlocked tasks when an urgent job arrives,
but it never moves work that is in progress, already accepted/offered to a
worker, manually locked on the Gantt chart, or blocked by an approved external
machine reservation.

Important scheduling rules implemented here:
* Tasks form a DAG and may require a MACHINE, a HUMAN, or both simultaneously.
* Resource capabilities determine valid assignments, speed, setup time and cost.
* Jobs carry LOW/MEDIUM/HIGH/URGENT priority and deadlines.
* Work is placed only inside configurable shop hours and may spill into later days.
* Approved machine bookings and fixed tasks become CP-SAT no-overlap blockers.
* Manager Gantt overrides are persisted and respected by later optimizations.
"""

from __future__ import annotations

import math
import os
import uuid
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from ortools.sat.python import cp_model

from database import supabase

SHOP_TIMEZONE = ZoneInfo(os.getenv('SHOP_TIMEZONE', 'Asia/Colombo'))
SHOP_OPEN_HOUR = int(os.getenv('SHOP_OPEN_HOUR', '8'))
SHOP_CLOSE_HOUR = int(os.getenv('SHOP_CLOSE_HOUR', '18'))
SHOP_WORK_DAYS = {
    int(value)
    for value in os.getenv('SHOP_WORK_DAYS', '0,1,2,3,4,5').split(',')
    if value.strip()
}
MAX_PLANNING_DAYS = int(os.getenv('MAX_PLANNING_DAYS', '60'))

PRIORITY_WEIGHT = {
    'LOW': 1,
    'MEDIUM': 3,
    'HIGH': 8,
    'URGENT': 20,
}

MOVABLE_STATUSES = {'PENDING', 'SCHEDULED'}
FIXED_STATUSES = {'SCHEDULED', 'OFFERED', 'ACCEPTED', 'IN_PROGRESS'}


def _parse_timestamp(value: str | datetime) -> datetime:
    """Parse a timestamp and normalize it to an aware UTC datetime."""
    if isinstance(value, datetime):
        parsed = value
    else:
        parsed = datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _local_datetime(day: date, hour: int) -> datetime:
    """Create a timezone-aware shop-local datetime for a calendar day/hour."""
    return datetime.combine(day, time(hour=hour), tzinfo=SHOP_TIMEZONE)


def _next_shop_start(now: datetime | None = None) -> datetime:
    """Return the next minute in which production work may start."""
    local_now = (now or datetime.now(timezone.utc)).astimezone(SHOP_TIMEZONE)
    local_now = local_now.replace(second=0, microsecond=0)

    for day_offset in range(MAX_PLANNING_DAYS + 7):
        day = local_now.date() + timedelta(days=day_offset)
        if day.weekday() not in SHOP_WORK_DAYS:
            continue

        opening = _local_datetime(day, SHOP_OPEN_HOUR)
        closing = _local_datetime(day, SHOP_CLOSE_HOUR)
        if day_offset == 0:
            if local_now < opening:
                return opening
            if opening <= local_now < closing:
                return local_now
        else:
            return opening

    raise RuntimeError('No shop working day is configured')


def _inside_shop_hours(start: datetime, end: datetime) -> bool:
    """Check that a complete interval fits inside one configured working day."""
    local_start = _parse_timestamp(start).astimezone(SHOP_TIMEZONE)
    local_end = _parse_timestamp(end).astimezone(SHOP_TIMEZONE)
    if local_start.date() != local_end.date():
        return False
    if local_start.weekday() not in SHOP_WORK_DAYS:
        return False
    opening = _local_datetime(local_start.date(), SHOP_OPEN_HOUR)
    closing = _local_datetime(local_start.date(), SHOP_CLOSE_HOUR)
    return opening <= local_start and local_end <= closing


def _allowed_start_intervals(
    baseline: datetime,
    duration_minutes: int,
    planning_days: int,
) -> list[list[int]]:
    """Build CP-SAT start domains that keep a task entirely inside shop hours."""
    baseline_local = baseline.astimezone(SHOP_TIMEZONE)
    intervals: list[list[int]] = []

    for offset in range(planning_days + 1):
        day = baseline_local.date() + timedelta(days=offset)
        if day.weekday() not in SHOP_WORK_DAYS:
            continue

        opening = _local_datetime(day, SHOP_OPEN_HOUR)
        closing = _local_datetime(day, SHOP_CLOSE_HOUR)
        earliest = max(opening, baseline_local)
        latest = closing - timedelta(minutes=duration_minutes)
        if earliest > latest:
            continue

        start_min = math.ceil((earliest - baseline_local).total_seconds() / 60)
        end_min = math.floor((latest - baseline_local).total_seconds() / 60)
        if end_min >= start_min:
            intervals.append([max(start_min, 0), max(end_min, 0)])

    return intervals


def _resource_meta(capability: dict) -> dict:
    """Return normalized resource metadata embedded in a capability row."""
    resource = capability.get('resources')
    if not isinstance(resource, dict):
        return {'id': capability.get('resource_id'), 'type': '', 'status': ''}
    return {
        'id': resource.get('id') or capability.get('resource_id'),
        'type': str(resource.get('type') or '').upper(),
        'status': str(resource.get('status') or '').upper(),
    }


def _duration_minutes(task: dict, capability: dict | None) -> int:
    """Calculate task duration for one resource capability."""
    manual = int(task.get('processing_time_minutes') or 0)
    setup = int((capability or {}).get('setup_time_minutes') or 0)
    if manual > 0:
        return max(manual + setup, 1)

    quantity = max(int(task.get('quantity_to_process') or 1), 1)
    rate = max(float((capability or {}).get('processing_rate_per_hr') or 0.001), 0.001)
    return max(math.ceil((quantity / rate) * 60 + setup), 1)


def _combination_duration(
    task: dict,
    machine_capability: dict | None,
    human_capability: dict | None,
) -> int:
    """Duration for a machine/human assignment pair.

    When a task needs both resource types, both are reserved for the slower of
    the two calculated durations so they remain synchronized.
    """
    durations = []
    if machine_capability is not None:
        durations.append(_duration_minutes(task, machine_capability))
    if human_capability is not None:
        durations.append(_duration_minutes(task, human_capability))
    if not durations:
        return max(int(task.get('processing_time_minutes') or 1), 1)
    return max(durations)


def _combination_cost(
    duration: int,
    machine_capability: dict | None,
    human_capability: dict | None,
) -> int:
    """Return integer operating cost for all resources reserved by a task."""
    hourly_cost = sum(
        float(cap.get('cost_per_hour') or 0)
        for cap in (machine_capability, human_capability)
        if cap is not None
    )
    return max(int(round((duration / 60.0) * hourly_cost)), 0)


def _candidate_combinations(
    task: dict,
    capabilities: list[dict],
    allowed_resources: dict[str, set[str]],
) -> list[tuple[dict | None, dict | None]]:
    """Return valid (machine capability, human capability) choices for a task."""
    operation_id = task.get('operation_type_id')
    eligible = [
        cap
        for cap in capabilities
        if cap.get('operation_type_id') == operation_id
        and _resource_meta(cap)['status'] in {'ACTIVE', 'IDLE'}
    ]

    restricted = allowed_resources.get(task['id'], set())
    if restricted:
        eligible = [cap for cap in eligible if cap.get('resource_id') in restricted]

    machines = [cap for cap in eligible if _resource_meta(cap)['type'] == 'MACHINE']
    humans = [cap for cap in eligible if _resource_meta(cap)['type'] == 'HUMAN']
    needs_machine = bool(task.get('machine_required'))
    needs_human = bool(task.get('human_required'))

    if needs_machine and needs_human:
        return [(machine, human) for machine in machines for human in humans]
    if needs_machine:
        return [(machine, None) for machine in machines]
    if needs_human:
        return [(None, human) for human in humans]

    # Backward compatibility for old rows created before explicit requirements.
    return [(machine, None) for machine in machines] + [(None, human) for human in humans]


def _minutes_from(baseline: datetime, value: str | datetime) -> int:
    """Convert an absolute timestamp into integer minutes from a planning baseline."""
    return int(round((_parse_timestamp(value) - baseline).total_seconds() / 60))


def _merge_intervals(intervals: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Merge overlapping fixed resource blockers before passing them to CP-SAT."""
    useful = sorted((max(0, start), end) for start, end in intervals if end > 0)
    merged: list[tuple[int, int]] = []
    for start, end in useful:
        start = max(start, 0)
        end = max(end, start + 1)
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged


def _load_planning_data(requested_job_id: str):
    """Load the small set of production tables needed for one optimization run."""
    jobs = supabase.table('jobs').select('*').execute().data or []
    tasks = supabase.table('tasks').select('*').execute().data or []
    job_by_id = {job['id']: job for job in jobs}

    if requested_job_id not in job_by_id:
        raise ValueError('Job not found')

    pool: list[dict] = []
    fixed: list[dict] = []

    for task in tasks:
        status = str(task.get('status') or 'PENDING').upper()
        locked = bool(task.get('schedule_locked'))
        job = job_by_id.get(task.get('job_id'), {})

        requested_movable = (
            task.get('job_id') == requested_job_id
            and status in MOVABLE_STATUSES
            and not locked
        )
        existing_movable = (
            task.get('job_id') != requested_job_id
            and str(job.get('status') or '').upper() == 'SCHEDULED'
            and status == 'SCHEDULED'
            and not locked
        )

        if requested_movable or existing_movable:
            pool.append(task)
        elif (
            status in FIXED_STATUSES
            and task.get('scheduled_start_time')
            and task.get('scheduled_end_time')
            and (task.get('assigned_machine_id') or task.get('assigned_human_id') or task.get('assigned_resource_id'))
        ):
            fixed.append(task)

    pool_ids = {task['id'] for task in pool}
    relevant_operation_ids = {
        task.get('operation_type_id')
        for task in pool
        if task.get('operation_type_id')
    }

    capabilities: list[dict] = []
    if relevant_operation_ids:
        capabilities = (
            supabase.table('resource_capabilities')
            .select('*, resources(id,name,type,status)')
            .in_('operation_type_id', list(relevant_operation_ids))
            .execute()
            .data
            or []
        )

    allowed_resources: dict[str, set[str]] = {}
    if pool_ids:
        try:
            rows = (
                supabase.table('task_allowed_resources')
                .select('task_id,resource_id')
                .in_('task_id', list(pool_ids))
                .execute()
                .data
                or []
            )
            for row in rows:
                allowed_resources.setdefault(row['task_id'], set()).add(row['resource_id'])
        except Exception as exc:
            print(f'[optimizer] task_allowed_resources unavailable: {exc}')

    dependencies = supabase.table('task_dependencies').select('*').execute().data or []
    bookings = (
        supabase.table('machine_bookings')
        .select('*')
        .eq('status', 'APPROVED')
        .execute()
        .data
        or []
    )

    return job_by_id, pool, fixed, capabilities, allowed_resources, dependencies, bookings


def _fixed_resource_ids(task: dict) -> list[str]:
    """Return every resource occupied by a fixed task, including legacy rows."""
    values = [task.get('assigned_machine_id'), task.get('assigned_human_id')]
    if not any(values) and task.get('assigned_resource_id'):
        values.append(task.get('assigned_resource_id'))
    return [str(value) for value in values if value]


def _planning_day_count(pool: list[dict], capabilities: list[dict]) -> int:
    """Estimate a safe multi-day horizon without building an unbounded model."""
    daily_minutes = max((SHOP_CLOSE_HOUR - SHOP_OPEN_HOUR) * 60, 1)
    rough_minutes = 0
    for task in pool:
        combos = _candidate_combinations(task, capabilities, {})
        if combos:
            rough_minutes += min(_combination_duration(task, machine, human) for machine, human in combos)
        else:
            rough_minutes += int(task.get('processing_time_minutes') or daily_minutes)

    days = max(7, math.ceil(rough_minutes / daily_minutes) + 7)
    return min(days, MAX_PLANNING_DAYS)


def run_optimization_engine(requested_job_id: str) -> dict:
    """Optimize one requested job plus all movable not-started scheduled work.

    Calling this function is the manager's explicit decision to optimize. Draft
    jobs other than `requested_job_id` are not pulled into the schedule. Existing
    scheduled work may move only while it remains unlocked and not started.
    """
    job_by_id, pool, fixed_tasks, capabilities, allowed, dependencies, bookings = _load_planning_data(
        requested_job_id
    )

    requested_tasks = [task for task in pool if task.get('job_id') == requested_job_id]
    if not requested_tasks:
        return {
            'status': 'error',
            'message': 'This job has no movable pending/scheduled tasks to optimize.',
        }

    for task in pool:
        if not task.get('operation_type_id'):
            return {
                'status': 'error',
                'message': f'Task "{task.get("name", task["id"])}" has no operation type.',
            }

    baseline_local = _next_shop_start()
    baseline = baseline_local.astimezone(timezone.utc)
    planning_days = _planning_day_count(pool, capabilities)
    horizon = (planning_days + 1) * 24 * 60

    model = cp_model.CpModel()
    task_vars: dict[str, dict] = {}
    choices: dict[str, list[dict]] = {}
    resource_intervals: dict[str, list] = {}
    cost_terms = []

    # Build fixed no-overlap blockers from immovable production tasks.
    blockers: dict[str, list[tuple[int, int]]] = {}
    for task in fixed_tasks:
        start = _minutes_from(baseline, task['scheduled_start_time'])
        end = _minutes_from(baseline, task['scheduled_end_time'])
        for resource_id in _fixed_resource_ids(task):
            blockers.setdefault(resource_id, []).append((start, end))

    # Approved external bookings block only their machine resource.
    for booking in bookings:
        start = _minutes_from(baseline, booking['start_time'])
        end = _minutes_from(baseline, booking['end_time'])
        blockers.setdefault(str(booking['machine_id']), []).append((start, end))

    for resource_id, intervals in blockers.items():
        resource_intervals.setdefault(resource_id, [])
        for start, end in _merge_intervals(intervals):
            if start >= horizon:
                continue
            end = min(end, horizon)
            duration = max(end - start, 1)
            resource_intervals[resource_id].append(
                model.new_fixed_size_interval_var(
                    model.new_constant(start),
                    duration,
                    f'fixed_{resource_id}_{start}',
                )
            )

    # Build one optional interval choice for each valid machine/human combination.
    for task in pool:
        task_id = task['id']
        combinations = _candidate_combinations(task, capabilities, allowed)
        if not combinations:
            return {
                'status': 'error',
                'message': f'Task "{task.get("name", task_id)}" has no valid active machine/worker combination.',
            }

        task_start = model.new_int_var(0, horizon, f'start_{task_id}')
        task_end = model.new_int_var(0, horizon, f'end_{task_id}')
        task_vars[task_id] = {'start': task_start, 'end': task_end}
        choices[task_id] = []
        selection_literals = []

        for index, (machine_cap, human_cap) in enumerate(combinations):
            duration = _combination_duration(task, machine_cap, human_cap)
            break_minutes = int(task.get('break_after_minutes') or 0)
            domains = _allowed_start_intervals(
                baseline,
                duration + break_minutes,
                planning_days,
            )
            if not domains:
                continue

            selected = model.new_bool_var(f'choose_{task_id}_{index}')
            local_start = model.new_int_var_from_domain(
                cp_model.Domain.from_intervals(domains),
                f'local_start_{task_id}_{index}',
            )
            local_end = model.new_int_var(0, horizon, f'local_end_{task_id}_{index}')
            interval = model.new_optional_interval_var(
                local_start,
                duration,
                local_end,
                selected,
                f'task_{task_id}_{index}',
            )

            model.add(task_start == local_start).only_enforce_if(selected)
            model.add(task_end == local_end).only_enforce_if(selected)

            machine_id = machine_cap.get('resource_id') if machine_cap else None
            human_id = human_cap.get('resource_id') if human_cap else None
            for resource_id in (machine_id, human_id):
                if resource_id:
                    resource_intervals.setdefault(resource_id, []).append(interval)

            if break_minutes > 0:
                for resource_id in (machine_id, human_id):
                    if not resource_id:
                        continue
                    break_end = model.new_int_var(0, horizon + break_minutes, f'break_end_{task_id}_{index}_{resource_id}')
                    break_interval = model.new_optional_interval_var(
                        local_end,
                        break_minutes,
                        break_end,
                        selected,
                        f'break_{task_id}_{index}_{resource_id}',
                    )
                    resource_intervals.setdefault(resource_id, []).append(break_interval)

            cost_terms.append(selected * _combination_cost(duration, machine_cap, human_cap))
            selection_literals.append(selected)
            choices[task_id].append(
                {
                    'selected': selected,
                    'machine_id': machine_id,
                    'human_id': human_id,
                    'duration': duration,
                }
            )

        if not selection_literals:
            return {
                'status': 'error',
                'message': (
                    f'Task "{task.get("name", task_id)}" cannot fit inside one shop workday. '
                    'Split this process into smaller DAG tasks or extend shop hours.'
                ),
            }
        model.add_exactly_one(selection_literals)

    # Dependency constraints work for movable/movable and movable/fixed pairs.
    pool_ids = set(task_vars)
    fixed_by_id = {task['id']: task for task in fixed_tasks}
    for dep in dependencies:
        predecessor = dep.get('predecessor_task_id')
        successor = dep.get('successor_task_id')
        wait = int(dep.get('mandatory_wait_minutes') or 0)

        if predecessor in pool_ids and successor in pool_ids:
            model.add(task_vars[successor]['start'] >= task_vars[predecessor]['end'] + wait)
        elif successor in pool_ids and predecessor in fixed_by_id:
            fixed_end = _minutes_from(baseline, fixed_by_id[predecessor]['scheduled_end_time'])
            model.add(task_vars[successor]['start'] >= fixed_end + wait)
        elif predecessor in pool_ids and successor in fixed_by_id:
            fixed_start = _minutes_from(baseline, fixed_by_id[successor]['scheduled_start_time'])
            model.add(task_vars[predecessor]['end'] + wait <= fixed_start)

    # No resource can execute two production/booking intervals at once.
    for intervals in resource_intervals.values():
        if len(intervals) > 1:
            model.add_no_overlap(intervals)

    # Priority/deadline objective: important jobs finish earlier, and lateness is
    # heavily penalized. Cost remains a secondary tie-breaker.
    objective_terms = list(cost_terms)
    job_end_vars = []
    for job_id in {task.get('job_id') for task in pool}:
        job_task_vars = [task_vars[task['id']]['end'] for task in pool if task.get('job_id') == job_id]
        if not job_task_vars:
            continue
        job_end = model.new_int_var(0, horizon, f'job_end_{job_id}')
        model.add_max_equality(job_end, job_task_vars)
        job_end_vars.append(job_end)

        job = job_by_id.get(job_id, {})
        priority = str(job.get('priority') or 'MEDIUM').upper()
        priority_weight = PRIORITY_WEIGHT.get(priority, PRIORITY_WEIGHT['MEDIUM'])
        objective_terms.append(priority_weight * job_end)

        deadline_raw = job.get('deadline')
        if deadline_raw:
            deadline_min = max(0, _minutes_from(baseline, deadline_raw))
            tardiness = model.new_int_var(0, horizon * 2, f'tardiness_{job_id}')
            model.add(tardiness >= job_end - deadline_min)
            objective_terms.append(priority_weight * 100 * tardiness)

    if job_end_vars:
        global_end = model.new_int_var(0, horizon, 'global_end')
        model.add_max_equality(global_end, job_end_vars)
        objective_terms.append(5 * global_end)

    model.minimize(sum(objective_terms))

    validation_error = model.validate()
    if validation_error:
        return {'status': 'error', 'message': f'Optimizer model is invalid: {validation_error}'}

    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = 60.0
    status = solver.solve(model)

    if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        status_name = solver.status_name(status)
        message = (
            'No valid schedule exists with the current DAG, shop hours, capabilities, locks and bookings.'
            if status_name == 'INFEASIBLE'
            else f'No schedule was found. Solver status: {status_name}.'
        )
        return {'status': 'error', 'message': message, 'solver_status': status_name}

    scheduled_job_ids: set[str] = set()
    for task in pool:
        task_id = task['id']
        chosen = next(item for item in choices[task_id] if solver.value(item['selected']) == 1)
        start = baseline + timedelta(minutes=solver.value(task_vars[task_id]['start']))
        end = baseline + timedelta(minutes=solver.value(task_vars[task_id]['end']))

        legacy_resource = chosen['human_id'] or chosen['machine_id']
        supabase.table('tasks').update(
            {
                'assigned_machine_id': chosen['machine_id'],
                'assigned_human_id': chosen['human_id'],
                'assigned_resource_id': legacy_resource,
                'scheduled_start_time': start.isoformat(),
                'scheduled_end_time': end.isoformat(),
                'status': 'SCHEDULED',
            }
        ).eq('id', task_id).execute()
        scheduled_job_ids.add(task['job_id'])

    for job_id in scheduled_job_ids:
        supabase.table('jobs').update({'status': 'SCHEDULED'}).eq('id', job_id).execute()

    return {
        'status': 'success',
        'quality': 'optimal' if status == cp_model.OPTIMAL else 'feasible',
        'scheduled_tasks': len(pool),
        'planning_days': planning_days,
        'shop_timezone': str(SHOP_TIMEZONE),
        'shop_hours': f'{SHOP_OPEN_HOUR:02d}:00-{SHOP_CLOSE_HOUR:02d}:00',
    }


def _capability_for(resource_id: str, operation_id: str) -> dict | None:
    """Fetch one capability row for manual Gantt validation/duration calculation."""
    rows = (
        supabase.table('resource_capabilities')
        .select('*, resources(id,name,type,status)')
        .eq('resource_id', resource_id)
        .eq('operation_type_id', operation_id)
        .execute()
        .data
        or []
    )
    return rows[0] if rows else None


def manual_move_task(task_id: str, target_resource_id: str, start_time: datetime, lock: bool = True) -> dict:
    """Validate and persist one manager drag/drop operation from the Gantt chart.

    Moving a machine-row block changes only the machine assignment; moving a
    human-row block changes only the human assignment. The other required
    resource remains attached and both resources move to the same new time.
    """
    task_rows = supabase.table('tasks').select('*').eq('id', task_id).execute().data or []
    if not task_rows:
        raise ValueError('Task not found')
    task = task_rows[0]

    status = str(task.get('status') or '').upper()
    if status in {'OFFERED', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED'}:
        raise ValueError(f'{status} tasks cannot be moved')

    resource_rows = supabase.table('resources').select('*').eq('id', target_resource_id).execute().data or []
    if not resource_rows:
        raise ValueError('Target resource not found')
    resource = resource_rows[0]
    if str(resource.get('status') or '').upper() not in {'ACTIVE', 'IDLE'}:
        raise ValueError('Target resource is not available')

    operation_id = task.get('operation_type_id')
    target_cap = _capability_for(target_resource_id, operation_id)
    if not target_cap:
        raise ValueError('Target resource does not have the required capability')

    target_type = str(resource.get('type') or '').upper()
    machine_id = target_resource_id if target_type == 'MACHINE' else task.get('assigned_machine_id')
    human_id = target_resource_id if target_type == 'HUMAN' else task.get('assigned_human_id')

    if task.get('machine_required') and not machine_id:
        raise ValueError('This task also requires a machine assignment')
    if task.get('human_required') and not human_id:
        raise ValueError('This task also requires a human assignment')

    machine_cap = _capability_for(machine_id, operation_id) if machine_id else None
    human_cap = _capability_for(human_id, operation_id) if human_id else None
    duration = _combination_duration(task, machine_cap, human_cap)

    start = _parse_timestamp(start_time)
    end = start + timedelta(minutes=duration)
    if not _inside_shop_hours(start, end):
        raise ValueError('Dragged task must fit completely inside shop hours')

    resource_ids = [value for value in (machine_id, human_id) if value]
    for resource_id in resource_ids:
        # Other fixed/movable scheduled tasks on this resource must not overlap.
        rows = (
            supabase.table('tasks')
            .select('id,scheduled_start_time,scheduled_end_time,status')
            .neq('id', task_id)
            .or_(f'assigned_machine_id.eq.{resource_id},assigned_human_id.eq.{resource_id},assigned_resource_id.eq.{resource_id}')
            .not_.is_('scheduled_start_time', 'null')
            .not_.is_('scheduled_end_time', 'null')
            .execute()
            .data
            or []
        )
        for row in rows:
            if str(row.get('status') or '').upper() == 'COMPLETED':
                continue
            other_start = _parse_timestamp(row['scheduled_start_time'])
            other_end = _parse_timestamp(row['scheduled_end_time'])
            if start < other_end and end > other_start:
                raise ValueError('Dragged task overlaps another scheduled task')

        # Approved external bookings also reserve machine time.
        if resource_id == machine_id:
            booking_rows = (
                supabase.table('machine_bookings')
                .select('start_time,end_time')
                .eq('machine_id', resource_id)
                .eq('status', 'APPROVED')
                .execute()
                .data
                or []
            )
            for booking in booking_rows:
                if start < _parse_timestamp(booking['end_time']) and end > _parse_timestamp(booking['start_time']):
                    raise ValueError('Dragged task overlaps an approved machine booking')

    # Preserve DAG chronology relative to currently scheduled predecessor/successor tasks.
    deps = supabase.table('task_dependencies').select('*').execute().data or []
    for dep in deps:
        wait = int(dep.get('mandatory_wait_minutes') or 0)
        if dep.get('successor_task_id') == task_id:
            pred_rows = supabase.table('tasks').select('scheduled_end_time').eq('id', dep['predecessor_task_id']).execute().data or []
            if pred_rows and pred_rows[0].get('scheduled_end_time'):
                required_start = _parse_timestamp(pred_rows[0]['scheduled_end_time']) + timedelta(minutes=wait)
                if start < required_start:
                    raise ValueError('Dragged task would start before its predecessor is finished')
        if dep.get('predecessor_task_id') == task_id:
            succ_rows = supabase.table('tasks').select('scheduled_start_time').eq('id', dep['successor_task_id']).execute().data or []
            if succ_rows and succ_rows[0].get('scheduled_start_time'):
                latest_end = _parse_timestamp(succ_rows[0]['scheduled_start_time']) - timedelta(minutes=wait)
                if end > latest_end:
                    raise ValueError('Dragged task would overlap its successor dependency')

    update = {
        'assigned_machine_id': machine_id,
        'assigned_human_id': human_id,
        'assigned_resource_id': human_id or machine_id,
        'scheduled_start_time': start.isoformat(),
        'scheduled_end_time': end.isoformat(),
        'schedule_locked': lock,
        'status': 'SCHEDULED',
    }
    rows = supabase.table('tasks').update(update).eq('id', task_id).execute().data or []
    return rows[0] if rows else update
