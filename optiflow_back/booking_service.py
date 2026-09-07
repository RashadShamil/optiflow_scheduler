"""Machine-booking business rules.

External reservations must not overlap another approved/pending reservation or
an internally scheduled production task. All timestamps are normalized to UTC
before comparison so Flutter ISO strings work consistently.
"""

import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import HTTPException

from database import supabase


ACTIVE_BOOKING_STATUSES = {"PENDING", "APPROVED"}
ACTIVE_TASK_STATUSES = {"PENDING", "SCHEDULED", "IN_PROGRESS"}


def parse_datetime(value: str) -> datetime:
    """Parse an ISO-8601 timestamp and return an aware UTC datetime."""
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=f"Invalid datetime: {value}") from exc

    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def overlaps(start_a: datetime, end_a: datetime, start_b: datetime, end_b: datetime) -> bool:
    """Return True when two half-open time intervals intersect."""
    return start_a < end_b and end_a > start_b


def _machine(machine_id: str) -> dict:
    response = (
        supabase.table("resources")
        .select("*")
        .eq("id", machine_id)
        .eq("type", "MACHINE")
        .execute()
    )
    if not response.data:
        raise HTTPException(status_code=404, detail="Machine not found")
    return response.data[0]


def _scheduled_tasks_for_machine(machine_id: str) -> list[dict]:
    """Read tasks using either the legacy or normalized machine assignment field."""
    by_resource = (
        supabase.table("tasks")
        .select("id,status,scheduled_start_time,scheduled_end_time")
        .eq("assigned_resource_id", machine_id)
        .execute()
    ).data or []
    by_machine = (
        supabase.table("tasks")
        .select("id,status,scheduled_start_time,scheduled_end_time")
        .eq("assigned_machine_id", machine_id)
        .execute()
    ).data or []

    deduped: dict[str, dict] = {}
    for task in [*by_resource, *by_machine]:
        deduped[str(task.get("id"))] = task
    return list(deduped.values())


def assert_available(machine_id: str, start_time: str, end_time: str, require_bookable: bool) -> tuple[dict, datetime, datetime]:
    """Validate machine state and reject any conflicting reservation/task."""
    machine = _machine(machine_id)
    if str(machine.get("status") or "").upper() != "ACTIVE":
        raise HTTPException(status_code=409, detail="Machine is not active")
    if require_bookable and not bool(machine.get("bookable")):
        raise HTTPException(status_code=403, detail="Machine is not available for external booking")

    start = parse_datetime(start_time)
    end = parse_datetime(end_time)
    if end <= start:
        raise HTTPException(status_code=422, detail="End time must be after start time")

    bookings = (
        supabase.table("machine_bookings")
        .select("id,start_time,end_time,status")
        .eq("machine_id", machine_id)
        .execute()
    ).data or []
    for booking in bookings:
        if str(booking.get("status") or "").upper() not in ACTIVE_BOOKING_STATUSES:
            continue
        if overlaps(start, end, parse_datetime(booking["start_time"]), parse_datetime(booking["end_time"])):
            raise HTTPException(status_code=409, detail="Requested slot overlaps an existing machine booking")

    for task in _scheduled_tasks_for_machine(machine_id):
        if str(task.get("status") or "").upper() not in ACTIVE_TASK_STATUSES:
            continue
        if not task.get("scheduled_start_time") or not task.get("scheduled_end_time"):
            continue
        if overlaps(start, end, parse_datetime(task["scheduled_start_time"]), parse_datetime(task["scheduled_end_time"])):
            raise HTTPException(status_code=409, detail="Requested slot overlaps scheduled production work")

    return machine, start, end


def create_booking(
    *,
    machine_id: str,
    requester_user_id: str,
    requester_name: str,
    start_time: str,
    end_time: str,
    notes: Optional[str] = None,
    require_bookable: bool = True,
) -> dict:
    """Create an approved booking after a final conflict check."""
    machine, start, end = assert_available(
        machine_id, start_time, end_time, require_bookable=require_bookable
    )

    duration_hours = (end - start).total_seconds() / 3600.0
    price_per_hour = float(machine.get("price_per_hour") or 0)
    quoted_amount = round(duration_hours * price_per_hour, 2)

    row = {
        "id": str(uuid.uuid4()),
        "machine_id": machine_id,
        "requested_by_user_id": requester_user_id,
        "requested_by_name": requester_name,
        "start_time": start.isoformat(),
        "end_time": end.isoformat(),
        "notes": notes,
        "quoted_amount": quoted_amount,
        # Availability is checked immediately, so the slot can be reserved safely.
        "status": "APPROVED",
    }
    response = supabase.table("machine_bookings").insert(row).execute()
    return response.data[0]
