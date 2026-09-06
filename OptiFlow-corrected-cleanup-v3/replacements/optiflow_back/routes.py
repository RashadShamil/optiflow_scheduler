"""HTTP API routes for the complete OptiFlow workflow.

This module is the application/service layer between Flutter and Supabase. It
contains validation and workflow transitions, while the mathematical schedule is
kept in `optimizer.py`. Manager desktop and mobile role screens all call these
same routes, so there is one source of truth for jobs, workers, bookings and the
Gantt schedule.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query

from auth import CurrentUser, current_user, require_external, require_manager
from database import supabase
from models import (
    BookingDecision,
    CapabilityCreate,
    CapabilityUpdate,
    JobCreate,
    MachineBookingCreate,
    OperationTypeCreate,
    OperationTypeUpdate,
    ResourceCreate,
    ResourceUpdate,
    ScheduleLockRequest,
    ScheduleMoveRequest,
    WorkOfferCreate,
)
from optimizer import (
    SHOP_CLOSE_HOUR,
    SHOP_OPEN_HOUR,
    SHOP_TIMEZONE,
    SHOP_WORK_DAYS,
    _inside_shop_hours,
    _parse_timestamp,
    manual_move_task,
    run_optimization_engine,
)

router = APIRouter()


# -----------------------------------------------------------------------------
# Small route helpers
# -----------------------------------------------------------------------------

def _one(rows: list[dict], message: str):
    """Return the first row or raise a normal API 404."""
    if not rows:
        raise HTTPException(status_code=404, detail=message)
    return rows[0]


def _user_resource_id(user: CurrentUser, create_external: bool = False) -> str | None:
    """Resolve the HUMAN resource linked to an authenticated user.

    Internal workers normally carry `resource_id` in Supabase Auth metadata.
    External users get a lightweight HUMAN resource on first marketplace claim.
    """
    if user.resource_id:
        return user.resource_id

    rows = (
        supabase.table('resources')
        .select('id')
        .eq('auth_user_id', user.id)
        .eq('type', 'HUMAN')
        .execute()
        .data
        or []
    )
    if rows:
        return rows[0]['id']

    if not create_external:
        return None

    resource_id = str(uuid.uuid4())
    supabase.table('resources').insert(
        {
            'id': resource_id,
            'name': user.display_name,
            'type': 'HUMAN',
            'status': 'ACTIVE',
            'auth_user_id': user.id,
            'is_external': True,
            'bookable': False,
        }
    ).execute()
    return resource_id


def _task_row(task_id: str) -> dict:
    """Fetch one task row for workflow validation."""
    rows = supabase.table('tasks').select('*').eq('id', task_id).execute().data or []
    return _one(rows, 'Task not found')


def _resource_row(resource_id: str) -> dict:
    """Fetch one machine/worker resource."""
    rows = supabase.table('resources').select('*').eq('id', resource_id).execute().data or []
    return _one(rows, 'Resource not found')


def _overlaps(start: datetime, end: datetime, other_start, other_end) -> bool:
    """Return True when two half-open time intervals overlap."""
    return start < _parse_timestamp(other_end) and end > _parse_timestamp(other_start)


def _validate_machine_slot(machine_id: str, start: datetime, end: datetime, ignore_booking_id: str | None = None):
    """Ensure a machine reservation is inside shop hours and has no conflicts."""
    start = _parse_timestamp(start)
    end = _parse_timestamp(end)
    if not _inside_shop_hours(start, end):
        raise HTTPException(status_code=409, detail='Booking must fit completely inside shop hours')

    task_rows = (
        supabase.table('tasks')
        .select('id,scheduled_start_time,scheduled_end_time,status')
        .eq('assigned_machine_id', machine_id)
        .not_.is_('scheduled_start_time', 'null')
        .not_.is_('scheduled_end_time', 'null')
        .execute()
        .data
        or []
    )
    for task in task_rows:
        if str(task.get('status') or '').upper() == 'COMPLETED':
            continue
        if _overlaps(start, end, task['scheduled_start_time'], task['scheduled_end_time']):
            raise HTTPException(status_code=409, detail='Machine is already scheduled for production in that slot')

    booking_rows = (
        supabase.table('machine_bookings')
        .select('id,start_time,end_time,status')
        .eq('machine_id', machine_id)
        .eq('status', 'APPROVED')
        .execute()
        .data
        or []
    )
    for booking in booking_rows:
        if ignore_booking_id and booking['id'] == ignore_booking_id:
            continue
        if _overlaps(start, end, booking['start_time'], booking['end_time']):
            raise HTTPException(status_code=409, detail='Machine already has an approved booking in that slot')


# -----------------------------------------------------------------------------
# Operation types and resource capabilities
# -----------------------------------------------------------------------------

@router.get('/operation-types')
def list_operation_types(user: CurrentUser = Depends(current_user)):
    """List the print-shop operation catalogue used by job DAGs."""
    return supabase.table('operation_types').select('*').order('name').execute().data or []


@router.post('/operation-types', status_code=201)
def create_operation_type(body: OperationTypeCreate, manager: CurrentUser = Depends(require_manager)):
    """Manager creates a new operation type such as Folding or Offset Printing."""
    name = body.name.strip()
    existing = supabase.table('operation_types').select('id').eq('name', name).execute().data or []
    if existing:
        raise HTTPException(status_code=409, detail='Operation type already exists')
    row = {'id': str(uuid.uuid4()), 'name': name}
    return supabase.table('operation_types').insert(row).execute().data[0]


@router.patch('/operation-types/{operation_type_id}')
def update_operation_type(
    operation_type_id: str,
    body: OperationTypeUpdate,
    manager: CurrentUser = Depends(require_manager),
):
    """Manager renames an operation type."""
    data = body.model_dump(exclude_none=True)
    if 'name' in data:
        data['name'] = data['name'].strip()
    rows = supabase.table('operation_types').update(data).eq('id', operation_type_id).execute().data or []
    return _one(rows, 'Operation type not found')


@router.delete('/operation-types/{operation_type_id}', status_code=204)
def delete_operation_type(operation_type_id: str, manager: CurrentUser = Depends(require_manager)):
    """Manager deletes an unused operation type."""
    supabase.table('operation_types').delete().eq('id', operation_type_id).execute()


@router.get('/resources')
def list_resources(
    resource_type: str | None = Query(default=None, alias='type'),
    include_external: bool = False,
    user: CurrentUser = Depends(current_user),
):
    """List machines/workers; manager can optionally include external workers."""
    query = supabase.table('resources').select('*').order('name')
    if resource_type:
        resource_type = resource_type.upper()
        if resource_type not in {'MACHINE', 'HUMAN'}:
            raise HTTPException(status_code=400, detail='type must be MACHINE or HUMAN')
        query = query.eq('type', resource_type)
    if not include_external:
        query = query.eq('is_external', False)
    return query.execute().data or []


@router.get('/machines/bookable')
def list_bookable_machines(user: CurrentUser = Depends(current_user)):
    """Customer-facing list of machines that the shop allows outsiders to request."""
    return (
        supabase.table('resources')
        .select('*')
        .eq('type', 'MACHINE')
        .eq('bookable', True)
        .in_('status', ['ACTIVE', 'IDLE'])
        .order('name')
        .execute()
        .data
        or []
    )


@router.post('/resources', status_code=201)
def create_resource(body: ResourceCreate, manager: CurrentUser = Depends(require_manager)):
    """Manager registers a machine or internal worker."""
    row = body.model_dump()
    row.update({'id': str(uuid.uuid4()), 'name': body.name.strip(), 'is_external': False})
    return supabase.table('resources').insert(row).execute().data[0]


@router.patch('/resources/{resource_id}')
def update_resource(
    resource_id: str,
    body: ResourceUpdate,
    manager: CurrentUser = Depends(require_manager),
):
    """Manager updates availability, rental price, image or bookable flag."""
    data = body.model_dump(exclude_none=True)
    if 'name' in data:
        data['name'] = data['name'].strip()
    rows = supabase.table('resources').update(data).eq('id', resource_id).execute().data or []
    return _one(rows, 'Resource not found')


@router.delete('/resources/{resource_id}', status_code=204)
def delete_resource(resource_id: str, manager: CurrentUser = Depends(require_manager)):
    """Manager removes a resource that is no longer used."""
    supabase.table('resources').delete().eq('id', resource_id).execute()


@router.get('/capabilities')
def list_capabilities(user: CurrentUser = Depends(current_user)):
    """Return the skills/capability matrix used by the optimizer."""
    return (
        supabase.table('resource_capabilities')
        .select('*, resources(id,name,type,status,is_external), operation_types(id,name)')
        .execute()
        .data
        or []
    )


@router.post('/capabilities', status_code=201)
def create_capability(body: CapabilityCreate, manager: CurrentUser = Depends(require_manager)):
    """Manager states that a resource can perform an operation at a given rate/cost."""
    existing = (
        supabase.table('resource_capabilities')
        .select('id')
        .eq('resource_id', body.resource_id)
        .eq('operation_type_id', body.operation_type_id)
        .execute()
        .data
        or []
    )
    if existing:
        raise HTTPException(status_code=409, detail='Capability already exists for this resource')
    row = body.model_dump()
    row['id'] = str(uuid.uuid4())
    return supabase.table('resource_capabilities').insert(row).execute().data[0]


@router.patch('/capabilities/{capability_id}')
def update_capability(
    capability_id: str,
    body: CapabilityUpdate,
    manager: CurrentUser = Depends(require_manager),
):
    """Manager changes processing speed/setup/cost for a capability."""
    rows = (
        supabase.table('resource_capabilities')
        .update(body.model_dump(exclude_none=True))
        .eq('id', capability_id)
        .execute()
        .data
        or []
    )
    return _one(rows, 'Capability not found')


@router.delete('/capabilities/{capability_id}', status_code=204)
def delete_capability(capability_id: str, manager: CurrentUser = Depends(require_manager)):
    """Manager removes one resource-operation capability."""
    supabase.table('resource_capabilities').delete().eq('id', capability_id).execute()


# -----------------------------------------------------------------------------
# Jobs and DAG creation
# -----------------------------------------------------------------------------

@router.get('/jobs')
def list_jobs(status: str | None = None, manager: CurrentUser = Depends(require_manager)):
    """Manager list of jobs with their task DAG nodes and current assignments."""
    query = supabase.table('jobs').select(
        '''
        id,title,client_name,total_quantity,priority,status,deadline,created_at,
        tasks(
            id,name,status,quantity_to_process,operation_type_id,
            machine_required,human_required,processing_time_minutes,break_after_minutes,
            assigned_resource_id,assigned_machine_id,assigned_human_id,
            scheduled_start_time,scheduled_end_time,schedule_locked,
            operation_types(id,name)
        )
        '''
    ).order('created_at', desc=True)
    if status:
        query = query.eq('status', status.upper())
    return query.execute().data or []


@router.post('/jobs', status_code=201)
def create_job(body: JobCreate, manager: CurrentUser = Depends(require_manager)):
    """Create a complete print job and its production-process DAG before scheduling."""
    task_count = len(body.tasks)
    for dependency in body.dependencies:
        if dependency.predecessor_index >= task_count or dependency.successor_index >= task_count:
            raise HTTPException(status_code=422, detail='Dependency references an unknown task index')
        if dependency.predecessor_index == dependency.successor_index:
            raise HTTPException(status_code=422, detail='A task cannot depend on itself')

    job_id = str(uuid.uuid4())
    job_row = {
        'id': job_id,
        'title': body.title.strip(),
        'client_name': body.client_name.strip() if body.client_name else None,
        'total_quantity': body.total_quantity,
        'priority': body.priority,
        'deadline': body.deadline.astimezone(timezone.utc).isoformat(),
        'created_by': manager.id,
        'status': 'DRAFT',
    }

    task_ids: list[str] = []
    try:
        supabase.table('jobs').insert(job_row).execute()
        for task in body.tasks:
            task_id = str(uuid.uuid4())
            task_ids.append(task_id)
            task_row = {
                'id': task_id,
                'job_id': job_id,
                'operation_type_id': task.operation_type_id,
                'name': task.name.strip(),
                'quantity_to_process': task.quantity_to_process,
                'processing_time_minutes': task.processing_time_minutes,
                'machine_required': task.machine_required,
                'human_required': task.human_required,
                'break_after_minutes': task.break_after_minutes,
                'schedule_locked': False,
                'status': 'PENDING',
            }
            supabase.table('tasks').insert(task_row).execute()

            if task.allowed_resource_ids:
                supabase.table('task_allowed_resources').insert(
                    [
                        {'task_id': task_id, 'resource_id': resource_id}
                        for resource_id in task.allowed_resource_ids
                    ]
                ).execute()

        if body.dependencies:
            supabase.table('task_dependencies').insert(
                [
                    {
                        'predecessor_task_id': task_ids[item.predecessor_index],
                        'successor_task_id': task_ids[item.successor_index],
                        'mandatory_wait_minutes': item.mandatory_wait_minutes,
                    }
                    for item in body.dependencies
                ]
            ).execute()
        return {'id': job_id, 'message': 'Job and process DAG created'}
    except Exception:
        # Foreign-key cascades remove child task/dependency rows if a later insert fails.
        supabase.table('jobs').delete().eq('id', job_id).execute()
        raise


@router.post('/optimize/{job_id}')
def optimize_job(job_id: str, manager: CurrentUser = Depends(require_manager)):
    """Manager explicitly runs the multi-day CP-SAT scheduler for a selected job."""
    try:
        result = run_optimization_engine(job_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    if result['status'] != 'success':
        raise HTTPException(status_code=409, detail=result['message'])
    return result


# -----------------------------------------------------------------------------
# Global Gantt schedule and manual manager overrides
# -----------------------------------------------------------------------------

@router.get('/schedule')
def get_schedule(manager: CurrentUser = Depends(require_manager)):
    """Return all scheduled task blocks plus approved machine-booking blocks."""
    resources = supabase.table('resources').select('id,name,type,status').execute().data or []
    resource_by_id = {row['id']: row for row in resources}
    tasks = (
        supabase.table('tasks')
        .select('*, jobs(id,title,priority,deadline), operation_types(id,name)')
        .not_.is_('scheduled_start_time', 'null')
        .not_.is_('scheduled_end_time', 'null')
        .order('scheduled_start_time')
        .execute()
        .data
        or []
    )

    for task in tasks:
        task['assigned_machine'] = resource_by_id.get(task.get('assigned_machine_id'))
        task['assigned_human'] = resource_by_id.get(task.get('assigned_human_id'))

    bookings = (
        supabase.table('machine_bookings')
        .select('*')
        .eq('status', 'APPROVED')
        .order('start_time')
        .execute()
        .data
        or []
    )
    for booking in bookings:
        booking['machine'] = resource_by_id.get(booking.get('machine_id'))

    return {
        'resources': resources,
        'tasks': tasks,
        'bookings': bookings,
        'shop': {
            'timezone': str(SHOP_TIMEZONE),
            'open_hour': SHOP_OPEN_HOUR,
            'close_hour': SHOP_CLOSE_HOUR,
            'work_days': sorted(SHOP_WORK_DAYS),
        },
    }


@router.patch('/schedule/tasks/{task_id}')
def move_schedule_task(
    task_id: str,
    body: ScheduleMoveRequest,
    manager: CurrentUser = Depends(require_manager),
):
    """Persist a Gantt drag/drop after capability, conflict and DAG validation."""
    try:
        return manual_move_task(task_id, body.resource_id, body.start_time, body.lock)
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.patch('/schedule/tasks/{task_id}/lock')
def set_schedule_lock(
    task_id: str,
    body: ScheduleLockRequest,
    manager: CurrentUser = Depends(require_manager),
):
    """Lock/unlock a scheduled task for future optimizer runs."""
    task = _task_row(task_id)
    if str(task.get('status') or '').upper() in {'IN_PROGRESS', 'COMPLETED'}:
        raise HTTPException(status_code=409, detail='Started/completed work cannot be unlocked for rescheduling')
    rows = (
        supabase.table('tasks')
        .update({'schedule_locked': body.locked})
        .eq('id', task_id)
        .execute()
        .data
        or []
    )
    return _one(rows, 'Task not found')


# -----------------------------------------------------------------------------
# Internal/external task execution workflow
# -----------------------------------------------------------------------------

@router.get('/me/tasks')
def my_tasks(user: CurrentUser = Depends(current_user)):
    """Return only human tasks assigned to the logged-in worker/external user."""
    resource_id = _user_resource_id(user)
    if not resource_id:
        return []
    return (
        supabase.table('tasks')
        .select('*, jobs(id,title,priority,deadline), operation_types(id,name)')
        .eq('assigned_human_id', resource_id)
        .in_('status', ['OFFERED', 'SCHEDULED', 'ACCEPTED', 'IN_PROGRESS', 'COMPLETED'])
        .order('scheduled_start_time')
        .execute()
        .data
        or []
    )


@router.post('/tasks/{task_id}/dispatch')
def dispatch_task(task_id: str, manager: CurrentUser = Depends(require_manager)):
    """Manager sends an internally assigned human task to that worker's mobile app."""
    task = _task_row(task_id)
    if not task.get('assigned_human_id'):
        raise HTTPException(status_code=409, detail='Task has no assigned human worker')
    if str(task.get('status') or '').upper() != 'SCHEDULED':
        raise HTTPException(status_code=409, detail='Only scheduled tasks can be dispatched')
    rows = (
        supabase.table('tasks')
        .update({'status': 'OFFERED', 'schedule_locked': True})
        .eq('id', task_id)
        .execute()
        .data
        or []
    )
    return rows[0]


def _assigned_user_task(task_id: str, user: CurrentUser) -> tuple[dict, str]:
    """Validate that the caller owns the HUMAN assignment for a task."""
    resource_id = _user_resource_id(user)
    if not resource_id:
        raise HTTPException(status_code=409, detail='Your account is not linked to a worker resource')
    task = _task_row(task_id)
    if task.get('assigned_human_id') != resource_id:
        raise HTTPException(status_code=403, detail='This task is not assigned to you')
    return task, resource_id


@router.post('/tasks/{task_id}/accept')
def accept_task(task_id: str, user: CurrentUser = Depends(current_user)):
    """Internal/external worker accepts an offered or already-scheduled human task."""
    task, _ = _assigned_user_task(task_id, user)
    current = str(task.get('status') or '').upper()
    allowed = {'OFFERED', 'SCHEDULED'} if user.role == 'EXTERNAL' else {'OFFERED'}
    if current not in allowed:
        raise HTTPException(status_code=409, detail=f'{current} task cannot be accepted')
    rows = (
        supabase.table('tasks')
        .update({'status': 'ACCEPTED', 'schedule_locked': True})
        .eq('id', task_id)
        .execute()
        .data
        or []
    )
    return rows[0]


@router.post('/tasks/{task_id}/start')
def start_task(task_id: str, user: CurrentUser = Depends(current_user)):
    """Assigned worker starts an accepted task."""
    task, _ = _assigned_user_task(task_id, user)
    if str(task.get('status') or '').upper() != 'ACCEPTED':
        raise HTTPException(status_code=409, detail='Accept the task before starting it')
    rows = supabase.table('tasks').update({'status': 'IN_PROGRESS'}).eq('id', task_id).execute().data or []
    return rows[0]


@router.post('/tasks/{task_id}/complete')
def complete_task(task_id: str, user: CurrentUser = Depends(current_user)):
    """Assigned worker completes the task and closes the job when all nodes are done."""
    task, _ = _assigned_user_task(task_id, user)
    if str(task.get('status') or '').upper() != 'IN_PROGRESS':
        raise HTTPException(status_code=409, detail='Only in-progress work can be completed')

    rows = (
        supabase.table('tasks')
        .update({'status': 'COMPLETED', 'completed_at': datetime.now(timezone.utc).isoformat()})
        .eq('id', task_id)
        .execute()
        .data
        or []
    )

    remaining = (
        supabase.table('tasks')
        .select('id')
        .eq('job_id', task['job_id'])
        .neq('status', 'COMPLETED')
        .execute()
        .data
        or []
    )
    if not remaining:
        supabase.table('jobs').update({'status': 'COMPLETED'}).eq('id', task['job_id']).execute()
    return rows[0]


# -----------------------------------------------------------------------------
# External machine marketplace with manager approval
# -----------------------------------------------------------------------------

@router.get('/machines/{machine_id}/availability')
def machine_availability(
    machine_id: str,
    day: date,
    user: CurrentUser = Depends(current_user),
):
    """Return busy intervals so an external user can choose a genuinely free slot."""
    machine = _resource_row(machine_id)
    if machine.get('type') != 'MACHINE' or not machine.get('bookable'):
        raise HTTPException(status_code=404, detail='Machine is not externally bookable')

    local_start = datetime.combine(day, datetime.min.time(), tzinfo=SHOP_TIMEZONE)
    local_end = local_start + timedelta(days=1)
    start_utc = local_start.astimezone(timezone.utc).isoformat()
    end_utc = local_end.astimezone(timezone.utc).isoformat()

    task_rows = (
        supabase.table('tasks')
        .select('id,name,scheduled_start_time,scheduled_end_time')
        .eq('assigned_machine_id', machine_id)
        .gte('scheduled_start_time', start_utc)
        .lt('scheduled_start_time', end_utc)
        .execute()
        .data
        or []
    )
    booking_rows = (
        supabase.table('machine_bookings')
        .select('id,start_time,end_time,status')
        .eq('machine_id', machine_id)
        .eq('status', 'APPROVED')
        .gte('start_time', start_utc)
        .lt('start_time', end_utc)
        .execute()
        .data
        or []
    )
    return {
        'machine': machine,
        'day': day.isoformat(),
        'shop_open_hour': SHOP_OPEN_HOUR,
        'shop_close_hour': SHOP_CLOSE_HOUR,
        'busy': [
            {'source': 'PRODUCTION', **row} for row in task_rows
        ] + [
            {'source': 'BOOKING', **row} for row in booking_rows
        ],
    }


@router.post('/machine-bookings', status_code=201)
def request_machine_booking(
    body: MachineBookingCreate,
    external: CurrentUser = Depends(require_external),
):
    """External user requests a slot; nothing is blocked until manager approval."""
    machine = _resource_row(body.machine_id)
    if machine.get('type') != 'MACHINE' or not machine.get('bookable'):
        raise HTTPException(status_code=409, detail='Machine is not available for external booking')
    if not _inside_shop_hours(body.start_time, body.end_time):
        raise HTTPException(status_code=409, detail='Requested slot must be inside shop hours')

    duration_hours = (body.end_time - body.start_time).total_seconds() / 3600
    quoted_amount = duration_hours * float(machine.get('price_per_hour') or 0)
    row = {
        'id': str(uuid.uuid4()),
        'machine_id': body.machine_id,
        'requested_by_user_id': external.id,
        'requested_by_name': external.display_name,
        'start_time': body.start_time.astimezone(timezone.utc).isoformat(),
        'end_time': body.end_time.astimezone(timezone.utc).isoformat(),
        'notes': body.notes,
        'quoted_amount': round(quoted_amount, 2),
        'status': 'PENDING',
    }
    return supabase.table('machine_bookings').insert(row).execute().data[0]


@router.get('/machine-bookings/mine')
def my_machine_bookings(external: CurrentUser = Depends(require_external)):
    """External user sees pending/approved/rejected booking requests."""
    rows = (
        supabase.table('machine_bookings')
        .select('*')
        .eq('requested_by_user_id', external.id)
        .order('created_at', desc=True)
        .execute()
        .data
        or []
    )
    machines = supabase.table('resources').select('id,name,image_url,price_per_hour').eq('type', 'MACHINE').execute().data or []
    machine_by_id = {item['id']: item for item in machines}
    for row in rows:
        row['machine'] = machine_by_id.get(row.get('machine_id'))
    return rows


@router.get('/machine-bookings')
def manager_machine_bookings(
    status: str | None = None,
    manager: CurrentUser = Depends(require_manager),
):
    """Manager approval queue for external machine requests."""
    query = supabase.table('machine_bookings').select('*').order('created_at', desc=True)
    if status:
        query = query.eq('status', status.upper())
    rows = query.execute().data or []
    machines = supabase.table('resources').select('id,name').eq('type', 'MACHINE').execute().data or []
    names = {item['id']: item['name'] for item in machines}
    for row in rows:
        row['machine_name'] = names.get(row.get('machine_id'))
    return rows


@router.patch('/machine-bookings/{booking_id}')
def decide_machine_booking(
    booking_id: str,
    body: BookingDecision,
    manager: CurrentUser = Depends(require_manager),
):
    """Manager approves/rejects a request; approval becomes an optimizer blocker."""
    rows = supabase.table('machine_bookings').select('*').eq('id', booking_id).execute().data or []
    booking = _one(rows, 'Booking request not found')
    if booking.get('status') != 'PENDING':
        raise HTTPException(status_code=409, detail='Only pending booking requests can be decided')

    if body.status == 'APPROVED':
        _validate_machine_slot(
            booking['machine_id'],
            _parse_timestamp(booking['start_time']),
            _parse_timestamp(booking['end_time']),
            ignore_booking_id=booking_id,
        )

    update = {
        'status': body.status,
        'reviewed_by_user_id': manager.id,
        'reviewed_at': datetime.now(timezone.utc).isoformat(),
    }
    return supabase.table('machine_bookings').update(update).eq('id', booking_id).execute().data[0]


# -----------------------------------------------------------------------------
# External human-work marketplace
# -----------------------------------------------------------------------------

@router.post('/tasks/{task_id}/work-offer', status_code=201)
def publish_work_offer(
    task_id: str,
    body: WorkOfferCreate,
    manager: CurrentUser = Depends(require_manager),
):
    """Manager publishes one human-only DAG task for paid external manpower."""
    task = _task_row(task_id)
    if not task.get('human_required') or task.get('machine_required'):
        raise HTTPException(
            status_code=409,
            detail='Only human-only tasks can be published to the external work market',
        )
    if str(task.get('status') or '').upper() not in {'PENDING', 'SCHEDULED'}:
        raise HTTPException(
            status_code=409,
            detail='Only pending or not-yet-started scheduled tasks can be published externally',
        )

    existing = (
        supabase.table('work_offers')
        .select('id,status')
        .eq('task_id', task_id)
        .in_('status', ['OPEN', 'CLAIMED'])
        .execute()
        .data
        or []
    )
    if existing:
        raise HTTPException(status_code=409, detail='This task already has an active work offer')

    row = {
        'id': str(uuid.uuid4()),
        'task_id': task_id,
        'pay_amount': body.pay_amount,
        'estimated_minutes': body.estimated_minutes,
        'notes': body.notes,
        'status': 'OPEN',
        'approved_by_user_id': manager.id,
    }
    return supabase.table('work_offers').insert(row).execute().data[0]


@router.get('/work-offers')
def list_open_work_offers(external: CurrentUser = Depends(require_external)):
    """External user sees manager-approved individual human tasks available to claim."""
    return (
        supabase.table('work_offers')
        .select('*, tasks(id,name,quantity_to_process,status,operation_type_id,jobs(id,title,priority,deadline),operation_types(id,name))')
        .eq('status', 'OPEN')
        .order('created_at')
        .execute()
        .data
        or []
    )


@router.get('/work-offers/mine')
def my_work_offers(external: CurrentUser = Depends(require_external)):
    """External user sees work they claimed and its execution status/time."""
    return (
        supabase.table('work_offers')
        .select('*, tasks(id,name,quantity_to_process,status,scheduled_start_time,scheduled_end_time,jobs(id,title,priority),operation_types(id,name))')
        .eq('claimed_by_user_id', external.id)
        .order('claimed_at', desc=True)
        .execute()
        .data
        or []
    )


@router.post('/work-offers/{offer_id}/claim')
def claim_work_offer(offer_id: str, external: CurrentUser = Depends(require_external)):
    """Claim an open human task and make this external worker its only scheduler candidate."""
    rows = (
        supabase.table('work_offers')
        .select('*, tasks(*)')
        .eq('id', offer_id)
        .eq('status', 'OPEN')
        .execute()
        .data
        or []
    )
    offer = _one(rows, 'Work offer is no longer available')
    task = offer.get('tasks') or {}
    if not task:
        raise HTTPException(status_code=409, detail='Work offer task no longer exists')
    if str(task.get('status') or '').upper() not in {'PENDING', 'SCHEDULED'}:
        raise HTTPException(
            status_code=409,
            detail='This work is no longer available because its task has already been dispatched or started',
        )

    resource_id = _user_resource_id(external, create_external=True)
    operation_id = task['operation_type_id']

    # Manager approval of the marketplace task is treated as qualification for
    # this one operation. Add a capability so the normal scheduler can use the
    # same resource-selection logic as internal workers.
    capability_rows = (
        supabase.table('resource_capabilities')
        .select('id')
        .eq('resource_id', resource_id)
        .eq('operation_type_id', operation_id)
        .execute()
        .data
        or []
    )
    if not capability_rows:
        hours = max(float(offer['estimated_minutes']) / 60.0, 1 / 60)
        rate = max(float(task.get('quantity_to_process') or 1) / hours, 0.001)
        cost_per_hour = float(offer['pay_amount']) / hours
        supabase.table('resource_capabilities').insert(
            {
                'id': str(uuid.uuid4()),
                'resource_id': resource_id,
                'operation_type_id': operation_id,
                'processing_rate_per_hr': rate,
                'setup_time_minutes': 0,
                'cost_per_hour': cost_per_hour,
            }
        ).execute()

    # Restrict this task to the claimant. The manager then re-optimizes the job
    # so the external person's work is inserted into the shared Gantt schedule.
    supabase.table('task_allowed_resources').delete().eq('task_id', task['id']).execute()
    supabase.table('task_allowed_resources').insert(
        {'task_id': task['id'], 'resource_id': resource_id}
    ).execute()

    supabase.table('tasks').update(
        {
            'assigned_machine_id': None,
            'assigned_human_id': resource_id,
            'assigned_resource_id': resource_id,
            'scheduled_start_time': None,
            'scheduled_end_time': None,
            'schedule_locked': False,
            'status': 'PENDING',
        }
    ).eq('id', task['id']).execute()
    supabase.table('jobs').update({'status': 'NEEDS_REOPTIMIZATION'}).eq('id', task['job_id']).execute()

    update = {
        'status': 'CLAIMED',
        'claimed_by_user_id': external.id,
        'claimed_by_resource_id': resource_id,
        'claimed_at': datetime.now(timezone.utc).isoformat(),
    }
    return supabase.table('work_offers').update(update).eq('id', offer_id).execute().data[0]


# -----------------------------------------------------------------------------
# Manager operational dashboard
# -----------------------------------------------------------------------------

@router.get('/dashboard-stats')
def dashboard_stats(manager: CurrentUser = Depends(require_manager)):
    """Real operational counts only; no fabricated OEE/defect/lead-time metrics."""
    machines = (
        supabase.table('resources')
        .select('id,name,status,type')
        .eq('type', 'MACHINE')
        .execute()
        .data
        or []
    )
    jobs = supabase.table('jobs').select('id,title,deadline,status,priority,created_at').execute().data or []
    tasks = (
        supabase.table('tasks')
        .select('id,name,status,completed_at,operation_types(name),jobs(title)')
        .execute()
        .data
        or []
    )
    pending_bookings = (
        supabase.table('machine_bookings').select('id').eq('status', 'PENDING').execute().data or []
    )
    open_offers = supabase.table('work_offers').select('id').eq('status', 'OPEN').execute().data or []

    now = datetime.now(timezone.utc)
    overdue = []
    for job in jobs:
        if not job.get('deadline') or job.get('status') == 'COMPLETED':
            continue
        try:
            if _parse_timestamp(job['deadline']) < now:
                overdue.append(job)
        except ValueError:
            pass

    tasks_by_operation: dict[str, int] = {}
    for task in tasks:
        operation = (task.get('operation_types') or {}).get('name') or 'Other'
        tasks_by_operation[operation] = tasks_by_operation.get(operation, 0) + 1

    completed = [task for task in tasks if task.get('status') == 'COMPLETED']
    completed.sort(key=lambda row: row.get('completed_at') or '', reverse=True)
    jobs.sort(key=lambda row: row.get('created_at') or '', reverse=True)

    return {
        'active_machines': sum(1 for row in machines if row.get('status') == 'ACTIVE'),
        'idle_machines': sum(1 for row in machines if row.get('status') == 'IDLE'),
        'offline_machines': [row for row in machines if row.get('status') in {'OFFLINE', 'MAINTENANCE'}],
        'total_machines': len(machines),
        'total_jobs': len(jobs),
        'total_tasks': len(tasks),
        'pending_tasks': sum(1 for row in tasks if row.get('status') == 'PENDING'),
        'in_progress_tasks': sum(1 for row in tasks if row.get('status') == 'IN_PROGRESS'),
        'completed_tasks': len(completed),
        'pending_booking_approvals': len(pending_bookings),
        'open_external_work_offers': len(open_offers),
        'tasks_by_op_type': tasks_by_operation,
        'recent_tasks': completed[:5],
        'new_jobs': jobs[:5],
        'overdue_jobs': overdue,
    }
