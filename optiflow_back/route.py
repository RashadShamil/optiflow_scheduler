"""OptiFlow API routes.

The routes are grouped by domain in this file while shared business rules live in
small service modules. All endpoints are mounted under ``/api`` by ``main.py``.
"""

import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from auth import CurrentUser, get_current_user, is_manager, is_outsider, linked_human_resource
from booking_service import create_booking
from database import supabase
from models import (
    BookingRequest,
    CapabilityCreate,
    CapabilityUpdate,
    JobOrderInput,
    OperationTypeCreate,
    OperationTypeUpdate,
    ResourceCreate,
    ResourceUpdate,
    TaskCompletionRequest,
    TaskStatusUpdate,
    WorkOfferCreate,
)
from optimizer import run_optimization_engine

router = APIRouter()

VALID_RESOURCE_TYPES = {"MACHINE", "HUMAN"}
VALID_RESOURCE_STATUSES = {"ACTIVE", "IDLE", "OFFLINE", "MAINTENANCE"}
VALID_TASK_STATUSES = {"PENDING", "SCHEDULED", "IN_PROGRESS", "COMPLETED"}
PRIORITY_WEIGHTS = {
    "HIGH": (90, 10),
    "MEDIUM": (70, 30),
    "LOW": (55, 45),
}


def _first_or_404(response, detail: str) -> dict:
    if not response.data:
        raise HTTPException(status_code=404, detail=detail)
    return response.data[0]


def _resource_map() -> dict[str, dict]:
    rows = supabase.table("resources").select("*").execute().data or []
    return {str(row["id"]): row for row in rows}


def _job_map() -> dict[str, dict]:
    rows = supabase.table("jobs").select("*").execute().data or []
    return {str(row["id"]): row for row in rows}


def _operation_map() -> dict[str, dict]:
    rows = supabase.table("operation_types").select("*").execute().data or []
    return {str(row["id"]): row for row in rows}


# ---------------------------------------------------------------------------
# Operation types
# ---------------------------------------------------------------------------

@router.get("/operation-types")
def list_operation_types():
    return supabase.table("operation_types").select("*").order("name").execute().data or []


@router.post("/operation-types")
def create_operation_type(body: OperationTypeCreate):
    existing = supabase.table("operation_types").select("id").eq("name", body.name).execute()
    if existing.data:
        raise HTTPException(status_code=409, detail="Operation type already exists")
    row = {"id": str(uuid.uuid4()), "name": body.name.strip()}
    return _first_or_404(
        supabase.table("operation_types").insert(row).execute(),
        "Operation type could not be created",
    )


@router.patch("/operation-types/{operation_type_id}")
@router.put("/operation-types/{operation_type_id}")
def update_operation_type(operation_type_id: str, body: OperationTypeUpdate):
    data = body.model_dump(exclude_none=True)
    return _first_or_404(
        supabase.table("operation_types").update(data).eq("id", operation_type_id).execute(),
        "Operation type not found",
    )


@router.delete("/operation-types/{operation_type_id}")
def delete_operation_type(operation_type_id: str):
    supabase.table("operation_types").delete().eq("id", operation_type_id).execute()
    return {"message": "Operation type deleted"}


# ---------------------------------------------------------------------------
# Resources and capabilities
# ---------------------------------------------------------------------------

def _normalize_resource_data(data: dict) -> dict:
    if "type" in data and data["type"] is not None:
        data["type"] = str(data["type"]).upper()
        if data["type"] not in VALID_RESOURCE_TYPES:
            raise HTTPException(status_code=422, detail="Resource type must be MACHINE or HUMAN")
    if "status" in data and data["status"] is not None:
        data["status"] = str(data["status"]).upper()
        if data["status"] not in VALID_RESOURCE_STATUSES:
            raise HTTPException(
                status_code=422,
                detail="Resource status must be ACTIVE, IDLE, OFFLINE, or MAINTENANCE",
            )
    return data


@router.get("/resources")
def list_resources():
    return supabase.table("resources").select("*").order("name").execute().data or []


@router.get("/resources/{resource_id}")
def get_resource(resource_id: str):
    return _first_or_404(
        supabase.table("resources").select("*").eq("id", resource_id).execute(),
        "Resource not found",
    )


@router.post("/resources")
def create_resource(body: ResourceCreate):
    data = _normalize_resource_data(body.model_dump())
    response = supabase.table("resources").insert(data).execute()
    return _first_or_404(response, "Resource could not be created")


@router.patch("/resources/{resource_id}")
@router.put("/resources/{resource_id}")
def update_resource(resource_id: str, body: ResourceUpdate):
    data = _normalize_resource_data(body.model_dump(exclude_none=True))
    return _first_or_404(
        supabase.table("resources").update(data).eq("id", resource_id).execute(),
        "Resource not found",
    )


@router.delete("/resources/{resource_id}")
def delete_resource(resource_id: str):
    supabase.table("resources").delete().eq("id", resource_id).execute()
    return {"message": "Resource deleted"}


@router.get("/capabilities")
def list_capabilities():
    return supabase.table("resource_capabilities").select("*").execute().data or []


@router.post("/capabilities")
def create_capability(body: CapabilityCreate):
    duplicate = (
        supabase.table("resource_capabilities")
        .select("id")
        .eq("resource_id", body.resource_id)
        .eq("operation_type_id", body.operation_type_id)
        .execute()
    )
    if duplicate.data:
        raise HTTPException(status_code=409, detail="Capability already exists for this resource")
    return _first_or_404(
        supabase.table("resource_capabilities").insert(body.model_dump()).execute(),
        "Capability could not be created",
    )


@router.patch("/capabilities/{capability_id}")
@router.put("/capabilities/{capability_id}")
def update_capability(capability_id: str, body: CapabilityUpdate):
    return _first_or_404(
        supabase.table("resource_capabilities")
        .update(body.model_dump(exclude_none=True))
        .eq("id", capability_id)
        .execute(),
        "Capability not found",
    )


@router.delete("/capabilities/{capability_id}")
def delete_capability(capability_id: str):
    supabase.table("resource_capabilities").delete().eq("id", capability_id).execute()
    return {"message": "Capability deleted"}


# ---------------------------------------------------------------------------
# Jobs, tasks, and optimization
# ---------------------------------------------------------------------------

@router.get("/jobs")
def list_jobs(status: Optional[str] = None):
    query = supabase.table("jobs").select("*")
    if status:
        query = query.eq("status", status.upper())
    rows = query.order("created_at", desc=True).execute().data or []
    return {"count": len(rows), "jobs": rows}


@router.post("/jobs/{job_id}/publish")
def publish_job(job_id: str):
    """Publish a DRAFT job to OPEN and mark its tasks visible on mobile."""
    job = _first_or_404(
        supabase.table("jobs").select("*").eq("id", job_id).execute(),
        "Job not found",
    )
    updated = _first_or_404(
        supabase.table("jobs").update({"status": "OPEN"}).eq("id", job_id).execute(),
        "Job could not be updated",
    )
    supabase.table("tasks").update({"show_in_mobile": True}).eq("job_id", job_id).execute()
    return {"message": "Job published successfully", "job": updated}


@router.post("/create_job")
def create_complex_job(order: JobOrderInput):
    """Create a job, all of its tasks, and DAG dependencies in one request."""
    task_count = len(order.tasks)
    for dependency in order.dependencies:
        if dependency.predecessor_index >= task_count or dependency.successor_index >= task_count:
            raise HTTPException(status_code=422, detail="Task dependency references an invalid task index")
        if dependency.predecessor_index == dependency.successor_index:
            raise HTTPException(status_code=422, detail="A task cannot depend on itself")

    job_row = {
        "title": order.title.strip(),
        "client_name": order.client_name,
        "total_quantity": order.total_quantity,
        "deadline": order.deadline,
        "created_by": order.created_by,
        "priority": order.priority,
        "status": "DRAFT",
    }
    job = _first_or_404(
        supabase.table("jobs").insert(job_row).execute(),
        "Job could not be created",
    )
    job_id = str(job["id"])

    task_ids: dict[int, str] = {}
    try:
        for index, task in enumerate(order.tasks):
            task_row = {
                "job_id": job_id,
                "operation_type_id": task.operation_type_id,
                "name": task.name.strip(),
                "quantity_to_process": task.quantity_to_process,
                "status": "PENDING",
                # Manager-created work is visible to the mobile workforce by default.
                "show_in_mobile": task.show_in_mobile,
                "processing_time_minutes": task.processing_time_minutes,
                "break_after_minutes": task.break_after_minutes,
                "break_type": task.break_type,
                "machine_required": task.machine_required,
                "human_required": task.human_required,
            }
            created = _first_or_404(
                supabase.table("tasks").insert(task_row).execute(),
                f"Task {index + 1} could not be created",
            )
            task_ids[index] = str(created["id"])

        dependency_rows = [
            {
                "predecessor_task_id": task_ids[item.predecessor_index],
                "successor_task_id": task_ids[item.successor_index],
                "mandatory_wait_minutes": item.mandatory_wait_minutes,
            }
            for item in order.dependencies
        ]
        if dependency_rows:
            supabase.table("task_dependencies").insert(dependency_rows).execute()
    except Exception:
        # Avoid leaving a half-created workflow when one of the child inserts fails.
        # The schema does not declare ON DELETE CASCADE, so children are removed first.
        for task_id in task_ids.values():
            supabase.table("task_dependencies").delete().eq("successor_task_id", task_id).execute()
            supabase.table("task_dependencies").delete().eq("predecessor_task_id", task_id).execute()
            supabase.table("tasks").delete().eq("id", task_id).execute()
        supabase.table("jobs").delete().eq("id", job_id).execute()
        raise

    return {"message": "Job workflow created", "job_id": job_id, "priority": order.priority}


@router.get("/tasks")
def list_tasks(resource_id: Optional[str] = None):
    query = supabase.table("tasks").select("*")
    if resource_id:
        query = query.eq("assigned_resource_id", resource_id)
    return query.execute().data or []


def _set_task_status(task_id: str, status: str) -> dict:
    status = status.upper()
    if status not in VALID_TASK_STATUSES:
        raise HTTPException(status_code=422, detail="Invalid task status")
    update = {"status": status}
    now = datetime.now(timezone.utc).isoformat()
    if status == "IN_PROGRESS":
        update["started_at"] = now
    elif status == "COMPLETED":
        update["completed_at"] = now
    return _first_or_404(
        supabase.table("tasks").update(update).eq("id", task_id).execute(),
        "Task not found",
    )


@router.patch("/tasks/{task_id}/status")
def update_task_status(task_id: str, body: TaskStatusUpdate):
    return {"message": "Task status updated", "task": _set_task_status(task_id, body.status)}


@router.post("/optimize/{job_id}")
def optimize_job(job_id: str):
    """Run CP-SAT using a time/cost balance derived from the job priority."""
    job = _first_or_404(
        supabase.table("jobs").select("id,priority").eq("id", job_id).execute(),
        "Job not found",
    )
    priority = str(job.get("priority") or "MEDIUM").upper()
    alpha, beta = PRIORITY_WEIGHTS.get(priority, PRIORITY_WEIGHTS["MEDIUM"])

    result = run_optimization_engine(
        job_id,
        datetime.now(timezone.utc),
        alpha=alpha,
        beta=beta,
    )
    if result.get("status") != "success":
        raise HTTPException(status_code=400, detail=result.get("message", "Optimization failed"))

    quality = result.get("quality", "optimal")
    return {
        "message": f"Schedule optimized ({quality}) using {priority} priority weights",
        "quality": quality,
        "priority": priority,
        "time_weight": alpha,
        "cost_weight": beta,
        "makespan_minutes": result.get("makespan_minutes", 0),
        "total_cost": result.get("total_cost", 0),
        "skipped_tasks": result.get("skipped_tasks", 0),
    }


# ---------------------------------------------------------------------------
# Mobile worker execution
# ---------------------------------------------------------------------------

def _resource_is_human(resource_id: Optional[str], resources: dict[str, dict]) -> bool:
    if not resource_id:
        return False
    return str(resources.get(str(resource_id), {}).get("type") or "").upper() == "HUMAN"


def _worker_can_see(task: dict, human: Optional[dict], resources: dict[str, dict]) -> bool:
    if not bool(task.get("show_in_mobile")) or human is None:
        return False
    human_id = str(human["id"])
    assigned_human = task.get("assigned_human_id")
    if assigned_human and str(assigned_human) != human_id:
        return False
    assigned_resource = task.get("assigned_resource_id")
    if _resource_is_human(assigned_resource, resources) and str(assigned_resource) != human_id:
        return False
    return True


def _outsider_claimed_task_ids(user: CurrentUser) -> set[str]:
    offers = (
        supabase.table("work_offers")
        .select("task_id")
        .eq("claimed_by_user_id", user.id)
        .eq("status", "CLAIMED")
        .execute()
    ).data or []
    return {str(row["task_id"]) for row in offers}


@router.get("/mobile/tasks")
def mobile_tasks(user: CurrentUser = Depends(get_current_user)):
    resources = _resource_map()
    jobs = _job_map()
    operations = _operation_map()
    all_tasks = supabase.table("tasks").select("*").eq("show_in_mobile", True).execute().data or []

    if is_outsider(user):
        allowed_task_ids = _outsider_claimed_task_ids(user)
        visible = [task for task in all_tasks if str(task["id"]) in allowed_task_ids]
        human = linked_human_resource(user)
    else:
        human = linked_human_resource(user)
        visible = [task for task in all_tasks if _worker_can_see(task, human, resources)]

    result = []
    for task in visible:
        job = jobs.get(str(task.get("job_id")), {})
        operation = operations.get(str(task.get("operation_type_id")), {})
        machine_id = task.get("assigned_machine_id") or task.get("assigned_resource_id")
        machine = resources.get(str(machine_id), {})
        status = str(task.get("status") or "PENDING").upper()
        # The existing mobile UI uses SCHEDULED as its actionable "Start" state.
        if status == "PENDING":
            status = "SCHEDULED"
        result.append(
            {
                **task,
                "status": status,
                "job_title": job.get("title") or "Untitled Job",
                "resource_name": machine.get("name") or "Unassigned",
                "operation_type_name": operation.get("name") or task.get("operation_type_id"),
            }
        )
    return result


def _claim_for_worker(task: dict, user: CurrentUser) -> dict:
    human = linked_human_resource(user)
    if human is None:
        raise HTTPException(status_code=409, detail="Your profile is not linked to a HUMAN resource")

    human_id = str(human["id"])
    assigned = task.get("assigned_human_id")
    if assigned and str(assigned) != human_id:
        raise HTTPException(status_code=409, detail="Task has already been accepted by another worker")
    if assigned:
        return task

    response = (
        supabase.table("tasks")
        .update({"assigned_human_id": human_id})
        .eq("id", task["id"])
        .is_("assigned_human_id", "null")
        .execute()
    )
    if not response.data:
        latest = _first_or_404(
            supabase.table("tasks").select("*").eq("id", task["id"]).execute(),
            "Task not found",
        )
        if str(latest.get("assigned_human_id")) != human_id:
            raise HTTPException(status_code=409, detail="Task has just been accepted by another worker")
        return latest
    return response.data[0]


def _authorize_mobile_task(task_id: str, user: CurrentUser, claim_worker: bool = False) -> dict:
    task = _first_or_404(
        supabase.table("tasks").select("*").eq("id", task_id).execute(),
        "Task not found",
    )
    if is_outsider(user):
        if task_id not in _outsider_claimed_task_ids(user):
            raise HTTPException(status_code=403, detail="This work offer is not assigned to you")
        return task

    resources = _resource_map()
    human = linked_human_resource(user)
    if not _worker_can_see(task, human, resources):
        raise HTTPException(status_code=403, detail="Task is not assigned/available to this worker")
    return _claim_for_worker(task, user) if claim_worker else task


@router.patch("/mobile/tasks/{task_id}/status")
def update_mobile_task_status(
    task_id: str,
    body: TaskStatusUpdate,
    user: CurrentUser = Depends(get_current_user),
):
    status = body.status.upper()
    task = _authorize_mobile_task(task_id, user, claim_worker=(status == "IN_PROGRESS"))
    return {"message": "Task status updated", "task": _set_task_status(str(task["id"]), status)}


def _mark_job_for_review_if_finished(job_id: str):
    tasks = supabase.table("tasks").select("status").eq("job_id", job_id).execute().data or []
    if tasks and all(str(task.get("status")).upper() == "COMPLETED" for task in tasks):
        supabase.table("jobs").update({"status": "REVIEW"}).eq("id", job_id).execute()


@router.post("/mobile/tasks/{task_id}/complete")
def complete_mobile_task(
    task_id: str,
    body: TaskCompletionRequest,
    user: CurrentUser = Depends(get_current_user),
):
    task = _authorize_mobile_task(task_id, user, claim_worker=not is_outsider(user))
    update = {
        "status": "COMPLETED",
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "proof_of_work_url": body.proof_url,
        "worker_notes": body.notes,
    }
    completed = _first_or_404(
        supabase.table("tasks").update(update).eq("id", task_id).execute(),
        "Task not found",
    )
    _mark_job_for_review_if_finished(str(completed["job_id"]))
    return {"message": "Task completed and manager review state updated", "task": completed}


# ---------------------------------------------------------------------------
# External paid work offers
# ---------------------------------------------------------------------------

@router.post("/work-offers")
def create_work_offer(body: WorkOfferCreate):
    _first_or_404(
        supabase.table("tasks").select("id").eq("id", body.task_id).execute(),
        "Task not found",
    )
    row = {
        "id": str(uuid.uuid4()),
        "task_id": body.task_id,
        "pay_amount": body.pay_amount,
        "estimated_minutes": body.estimated_minutes,
        "notes": body.notes,
        "status": "OPEN",
        "approved_by_user_id": body.approved_by_user_id,
    }
    return _first_or_404(
        supabase.table("work_offers").insert(row).execute(),
        "Work offer could not be created",
    )


@router.get("/mobile/work-offers")
def list_mobile_work_offers(user: CurrentUser = Depends(get_current_user)):
    """Only outsider accounts receive the paid external-work marketplace."""
    if not is_outsider(user):
        return []

    offers = supabase.table("work_offers").select("*").eq("status", "OPEN").execute().data or []
    if not offers:
        return []

    task_ids = [str(offer["task_id"]) for offer in offers]
    tasks = supabase.table("tasks").select("*").in_("id", task_ids).execute().data or []
    task_map = {str(task["id"]): task for task in tasks}
    jobs = _job_map()

    result = []
    for offer in offers:
        task = task_map.get(str(offer["task_id"]), {})
        job = jobs.get(str(task.get("job_id")), {})
        result.append(
            {
                "id": offer["id"],
                "task_id": offer["task_id"],
                "title": task.get("name") or job.get("title") or "External Work",
                "client_name": job.get("client_name") or "OptiFlow",
                "total_quantity": task.get("quantity_to_process") or 0,
                "status": "OPEN",
                "deadline": job.get("deadline"),
                "pay_amount": offer.get("pay_amount"),
                "estimated_minutes": offer.get("estimated_minutes"),
                "notes": offer.get("notes"),
            }
        )
    return result


@router.post("/mobile/work-offers/{offer_id}/claim")
def claim_work_offer(offer_id: str, user: CurrentUser = Depends(get_current_user)):
    if not is_outsider(user):
        raise HTTPException(status_code=403, detail="Only outsider accounts can claim paid work offers")

    offer = _first_or_404(
        supabase.table("work_offers").select("*").eq("id", offer_id).eq("status", "OPEN").execute(),
        "Work offer is no longer available",
    )
    human = linked_human_resource(user)
    update = {
        "status": "CLAIMED",
        "claimed_by_user_id": user.id,
        "claimed_by_resource_id": str(human["id"]) if human else None,
        "claimed_at": datetime.now(timezone.utc).isoformat(),
    }
    claimed = (
        supabase.table("work_offers")
        .update(update)
        .eq("id", offer_id)
        .eq("status", "OPEN")
        .execute()
    )
    if not claimed.data:
        raise HTTPException(status_code=409, detail="Work offer was just claimed by someone else")

    task_update = {"show_in_mobile": True}
    if human:
        task_update["assigned_human_id"] = str(human["id"])
    supabase.table("tasks").update(task_update).eq("id", offer["task_id"]).execute()
    return {"message": "Work offer claimed", "offer": claimed.data[0]}


# ---------------------------------------------------------------------------
# Mobile machines and machine bookings
# ---------------------------------------------------------------------------

@router.get("/mobile/machines")
def mobile_machines(user: CurrentUser = Depends(get_current_user)):
    query = supabase.table("resources").select("*").eq("type", "MACHINE")
    if is_outsider(user):
        query = query.eq("bookable", True)
    return query.order("name").execute().data or []


@router.patch("/mobile/machines/{machine_id}/status")
def mobile_machine_status(
    machine_id: str,
    body: ResourceUpdate,
    user: CurrentUser = Depends(get_current_user),
):
    if is_outsider(user):
        raise HTTPException(status_code=403, detail="Outsider accounts cannot change machine status")
    if body.status is None:
        raise HTTPException(status_code=422, detail="status is required")
    data = _normalize_resource_data({"status": body.status})
    return _first_or_404(
        supabase.table("resources").update(data).eq("id", machine_id).eq("type", "MACHINE").execute(),
        "Machine not found",
    )


@router.post("/machine-bookings")
def create_mobile_machine_booking(
    body: BookingRequest,
    user: CurrentUser = Depends(get_current_user),
):
    if not (is_outsider(user) or is_manager(user)):
        raise HTTPException(status_code=403, detail="Your role cannot create external machine bookings")
    booking = create_booking(
        machine_id=body.machine_id,
        requester_user_id=user.id,
        requester_name=user.full_name,
        start_time=body.start_time,
        end_time=body.end_time,
        notes=body.notes,
        require_bookable=is_outsider(user),
    )
    return {"message": "Machine booked", "booking": booking}


def _profile_id_for_manual_booking(name: str) -> str:
    profile = supabase.table("profiles").select("id").eq("full_name", name).limit(1).execute()
    if profile.data:
        return str(profile.data[0]["id"])

    resource = supabase.table("resources").select("profile_id").eq("name", name).limit(1).execute()
    if resource.data and resource.data[0].get("profile_id"):
        return str(resource.data[0]["profile_id"])
    raise HTTPException(
        status_code=422,
        detail="Manual booking operator must match an existing profile or linked resource",
    )


@router.post("/machine-bookings/manual")
def create_manual_machine_booking(body: BookingRequest):
    if not body.user_name:
        raise HTTPException(status_code=422, detail="user_name is required for manager-created bookings")
    user_id = _profile_id_for_manual_booking(body.user_name)
    booking = create_booking(
        machine_id=body.machine_id,
        requester_user_id=user_id,
        requester_name=body.user_name,
        start_time=body.start_time,
        end_time=body.end_time,
        notes=body.notes,
        require_bookable=False,
    )
    return {"message": "Machine booked", "booking": booking}


@router.get("/machine-bookings")
def my_machine_bookings(user: CurrentUser = Depends(get_current_user)):
    query = supabase.table("machine_bookings").select("*")
    if not is_manager(user):
        query = query.eq("requested_by_user_id", user.id)
    return query.order("start_time").execute().data or []


@router.delete("/machine-bookings/{booking_id}")
def cancel_machine_booking(booking_id: str):
    response = (
        supabase.table("machine_bookings")
        .update({"status": "CANCELLED"})
        .eq("id", booking_id)
        .execute()
    )
    _first_or_404(response, "Machine booking not found")
    return {"message": "Machine booking cancelled"}


# ---------------------------------------------------------------------------
# Unified schedule, dashboard, and analytics
# ---------------------------------------------------------------------------

@router.get("/schedule")
def unified_schedule():
    """Return internal scheduled tasks and external bookings in one timeline shape."""
    resources = _resource_map()
    jobs = _job_map()
    items = []

    tasks = supabase.table("tasks").select("*").execute().data or []
    for task in tasks:
        if not task.get("scheduled_start_time") or not task.get("scheduled_end_time"):
            continue
        candidate = task.get("assigned_machine_id") or task.get("assigned_resource_id")
        resource = resources.get(str(candidate), {})
        if str(resource.get("type") or "").upper() != "MACHINE":
            continue
        job = jobs.get(str(task.get("job_id")), {})
        items.append(
            {
                "id": task["id"],
                "source": "INTERNAL_TASK",
                "machine_id": candidate,
                "machine_name": resource.get("name") or "Unknown Machine",
                "title": job.get("title") or task.get("name") or "Internal Task",
                "user_name": "Internal production",
                "start_time": task["scheduled_start_time"],
                "end_time": task["scheduled_end_time"],
                "priority": job.get("priority") or "MEDIUM",
                "status": task.get("status") or "SCHEDULED",
            }
        )

    bookings = supabase.table("machine_bookings").select("*").execute().data or []
    for booking in bookings:
        if str(booking.get("status") or "").upper() == "CANCELLED":
            continue
        machine = resources.get(str(booking.get("machine_id")), {})
        items.append(
            {
                "id": booking["id"],
                "source": "MACHINE_BOOKING",
                "machine_id": booking["machine_id"],
                "machine_name": machine.get("name") or "Unknown Machine",
                "title": "External Machine Booking",
                "user_name": booking.get("requested_by_name") or "External user",
                "start_time": booking["start_time"],
                "end_time": booking["end_time"],
                "priority": "MEDIUM",
                "status": booking.get("status") or "APPROVED",
            }
        )

    items.sort(key=lambda item: str(item.get("start_time") or ""))
    return items


@router.get("/dashboard-stats")
def dashboard_stats():
    resources = supabase.table("resources").select("*").execute().data or []
    jobs = supabase.table("jobs").select("*").execute().data or []
    tasks = supabase.table("tasks").select("*").execute().data or []

    machines = [row for row in resources if str(row.get("type")).upper() == "MACHINE"]
    offline = [row for row in machines if str(row.get("status")).upper() in {"OFFLINE", "MAINTENANCE"}]
    now = datetime.now(timezone.utc)

    overdue = []
    for job in jobs:
        if str(job.get("status")).upper() in {"COMPLETED", "REVIEW"} or not job.get("deadline"):
            continue
        try:
            deadline = datetime.fromisoformat(str(job["deadline"]).replace("Z", "+00:00"))
            if deadline < now:
                overdue.append(job)
        except ValueError:
            continue

    completed = [task for task in tasks if str(task.get("status")).upper() == "COMPLETED"]
    completed.sort(key=lambda task: str(task.get("completed_at") or ""), reverse=True)
    jobs_sorted = sorted(jobs, key=lambda job: str(job.get("created_at") or ""), reverse=True)

    return {
        "offline_machines": offline,
        "offline_count": len(offline),
        "overdue_jobs": overdue,
        "overdue_count": len(overdue),
        "recent_tasks": completed[:5],
        "new_jobs": jobs_sorted[:5],
    }


@router.get("/analytics-jobs")
def analytics_jobs(days: int = Query(default=30, ge=1, le=365)):
    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
    return (
        supabase.table("jobs")
        .select("*")
        .gt("created_at", since)
        .order("created_at", desc=True)
        .execute()
        .data
        or []
    )
