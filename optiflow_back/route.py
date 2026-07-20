# =====================================================================
# IMPORTS: Bringing in the tools we need
# =====================================================================
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional
from fastapi import APIRouter, HTTPException, Query

# Import the database connection Sulakshan built
from databse import supabase 

# Import all the Pydantic data models (validation rules) Sulakshan built
from models import * # Import Rashad's optimization engine
from optimizer import run_optimization_engine 

# Create the router object. This is like a mini-FastAPI app that we can 
# plug into the main.py file later.
router = APIRouter()

# =====================================================================
# SLICE 4: OPERATION TYPES (Sulakshan)
# What kind of work can this shop do? (e.g., "Print A4", "Fold", "Bind")
# =====================================================================

@router.get("/operation-types")
def get_all_operation_types():
    """Fetches all operation types from the database."""
    res = supabase.table("operation_types").select("*").execute()
    return res.data

@router.post("/operation-types")
def create_operation_type(body: OperationTypeCreate):
    """Creates a new operation type. Validates that the name doesn't already exist."""
    # 1. Check if it already exists
    existing = supabase.table("operation_types").select("id").eq("name", body.name).execute()
    if existing.data:
        raise HTTPException(status_code=400, detail="Operation type already exists")
    
    # 2. Convert the Pydantic model into a normal Python dictionary
    data = body.model_dump()
    
    # 3. Generate a unique ID (UUID) for this new operation
    data["id"] = str(uuid.uuid4())
    
    # 4. Save to PostgreSQL
    res = supabase.table("operation_types").insert(data).execute()
    return res.data[0]

@router.put("/operation-types/{id}")
def update_operation_type(id: str, body: OperationTypeUpdate):
    """Updates an existing operation type."""
    # exclude_none=True ensures we don't accidentally overwrite good data with "null"
    res = supabase.table("operation_types").update(body.model_dump(exclude_none=True)).eq("id", id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Operation type not found")
    return res.data[0]

@router.delete("/operation-types/{id}")
def delete_operation_type(id: str):
    """Deletes an operation type."""
    supabase.table("operation_types").delete().eq("id", id).execute()
    return {"message": "Deleted successfully"}


# =====================================================================
# SLICE 4: RESOURCES (Sulakshan)
# The physical machines and human workers in the shop.
# =====================================================================

@router.get("/resources")
def get_all_resources():
    """Gets every machine and worker in the shop."""
    res = supabase.table("resources").select("*").execute()
    return res.data

@router.get("/resources/{id}")
def get_resource(id: str):
    """Gets one specific machine or worker by their ID."""
    res = supabase.table("resources").select("*").eq("id", id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Resource not found")
    return res.data[0]

@router.post("/resources")
def create_resource(body: ResourceCreate):
    """Registers a new machine or worker into the system."""
    # Hardcoded safety checks to ensure bad data doesn't enter the database
    if body.type not in ["MACHINE", "HUMAN"]:
        raise HTTPException(status_code=400, detail="Type must be 'MACHINE' or 'HUMAN'")
    if body.status not in ["ACTIVE", "IDLE", "OFFLINE"]:
        raise HTTPException(status_code=400, detail="Status must be ACTIVE, IDLE, or OFFLINE")
    
    data = body.model_dump()
    data["id"] = str(uuid.uuid4())
    res = supabase.table("resources").insert(data).execute()
    return res.data[0]

@router.put("/resources/{id}")
def update_resource(id: str, body: ResourceUpdate):
    """Updates a machine/worker (e.g., changing status from ACTIVE to BROKEN)."""
    if body.type and body.type not in ["MACHINE", "HUMAN"]:
        raise HTTPException(status_code=400, detail="Type must be 'MACHINE' or 'HUMAN'")
    if body.status and body.status not in ["ACTIVE", "IDLE", "OFFLINE"]:
        raise HTTPException(status_code=400, detail="Status must be ACTIVE, IDLE, or OFFLINE")
        
    res = supabase.table("resources").update(body.model_dump(exclude_none=True)).eq("id", id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Resource not found")
    return res.data[0]

@router.delete("/resources/{id}")
def delete_resource(id: str):
    """Removes a resource from the database entirely."""
    supabase.table("resources").delete().eq("id", id).execute()
    return {"message": "Deleted successfully"}


# =====================================================================
# SLICE 4: RESOURCE CAPABILITIES / SKILLS MATRIX (Sulakshan)
# Connecting Resources to Operation Types (e.g., "Printer A" can "Print A4")
# =====================================================================

@router.get("/capabilities")
def get_all_capabilities():
    """Gets the entire skills matrix. Notice the nested query 'resources(*)' 
       which tells Supabase to fetch the linked resource data automatically."""
    res = supabase.table("resource_capabilities").select("*, resources(*), operation_types(*)").execute()
    return res.data

@router.get("/capabilities/resource/{resource_id}")
def get_capabilities_by_resource(resource_id: str):
    """Finds out everything a specific machine or worker is capable of doing."""
    res = supabase.table("resource_capabilities").select("*, operation_types(*)").eq("resource_id", resource_id).execute()
    return res.data

@router.post("/capabilities")
def create_capability(body: CapabilityCreate):
    """Assigns a new skill/capability to a resource."""
    # Safety Check: Prevent assigning the exact same skill twice to the same person/machine
    existing = supabase.table("resource_capabilities") \
        .select("id") \
        .eq("resource_id", body.resource_id) \
        .eq("operation_type_id", body.operation_type_id) \
        .execute()
        
    if existing.data:
        raise HTTPException(status_code=400, detail="This resource already has this capability assigned")
        
    res = supabase.table("resource_capabilities").insert(body.model_dump()).execute()
    return res.data[0]

@router.put("/capabilities/{id}")
def update_capability(id: str, body: CapabilityUpdate):
    """Updates the speed or cost of a specific capability."""
    res = supabase.table("resource_capabilities").update(body.model_dump(exclude_none=True)).eq("id", id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="Capability not found")
    return res.data[0]

@router.delete("/capabilities/{id}")
def delete_capability(id: str):
    """Removes a capability from a resource."""
    supabase.table("resource_capabilities").delete().eq("id", id).execute()
    return {"message": "Deleted successfully"}


# =====================================================================
# SLICE 1: RASHAD'S OPTIMIZATION ENGINE
# The brain of the operation. Triggered when the manager clicks "Optimize"
# =====================================================================

@router.post("/optimize/{job_id}")
def optimize_job(job_id: str):
    """
    Triggers the Google OR-Tools CP-SAT solver.
    Reads the DAG, calculates the optimal schedule, and saves it to Supabase.
    Returns quality: 'optimal' | 'feasible' so the frontend can inform the user.
    """
    try:
        project_start_time = datetime.now(timezone.utc)
        result = run_optimization_engine(job_id, project_start_time)

        if result["status"] == "success":
            quality = result.get("quality", "optimal")
            makespan = result.get("makespan_minutes", 0)
            skipped  = result.get("skipped_tasks", 0)

            message = f"Schedule optimized ({quality})! Makespan: {makespan} min."
            if skipped:
                message += f" Note: {skipped} task(s) skipped (no capable resource)."

            return {
                "message":          message,
                "quality":          quality,
                "makespan_minutes": makespan,
                "total_cost":       result.get("total_cost", 0),
                "skipped_tasks":    skipped,
            }
        else:
            # Return the engine's descriptive message, not a generic string
            raise HTTPException(
                status_code=400,
                detail=result.get("message", "Optimization failed — check task configuration.")
            )

    except HTTPException:
        raise
    except Exception as e:
        print(f"Engine Error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Optimization Engine Failed: {str(e)}")




# =====================================================================
# DASHBOARD STATS ENDPOINT
# =====================================================================

@router.get("/dashboard-stats")
def get_dashboard_stats():
    """Returns live stats for the dashboard: offline machines, overdue jobs, recent activity."""
    try:
        # Offline / Idle machines
        machines_res = supabase.table("resources").select("id, name, status, type").eq("type", "MACHINE").execute()
        machines = machines_res.data or []
        offline_machines = [m for m in machines if m.get("status") in ("OFFLINE", "IDLE")]

        # Overdue jobs: deadline < now and status != COMPLETED
        now_iso = datetime.now(timezone.utc).isoformat()
        jobs_res = supabase.table("jobs").select("id, title, deadline, status, created_at").execute()
        jobs = jobs_res.data or []
        overdue_jobs = [
            j for j in jobs
            if j.get("deadline") and j.get("deadline") < now_iso
            and j.get("status") not in ("COMPLETED", "REVIEW")
        ]

        # Recent activity: last 5 completed tasks with job & resource info
        recent_res = supabase.table("tasks") \
            .select("id, name, status, completed_at, jobs(title), resources(name)") \
            .eq("status", "COMPLETED") \
            .order("completed_at", desc=True) \
            .limit(5) \
            .execute()
        recent_tasks = recent_res.data or []

        # Recent jobs created in last 24h
        yesterday = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
        new_jobs_res = supabase.table("jobs") \
            .select("id, title, created_at, status") \
            .gt("created_at", yesterday) \
            .order("created_at", desc=True) \
            .limit(5) \
            .execute()
        new_jobs = new_jobs_res.data or []

        return {
            "offline_machines": offline_machines,
            "offline_count": len(offline_machines),
            "overdue_jobs": overdue_jobs,
            "overdue_count": len(overdue_jobs),
            "recent_tasks": recent_tasks,
            "new_jobs": new_jobs,
        }
    except Exception as e:
        print(f"ERROR dashboard-stats: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/analytics-jobs")
def get_analytics_jobs(days: int = Query(30, ge=1, le=365)):
    """Returns jobs created within the last N days for analytics filtering."""
    try:
        since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()
        res = supabase.table("jobs").select("*").gt("created_at", since).execute()
        return res.data or []
    except Exception as e:
        print(f"ERROR analytics-jobs: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# =====================================================================
# SLICE 3: VIKASHAN'S WORKER EXECUTION & SCHEDULE
# =====================================================================

@router.get("/jobs/{job_id}")
def get_single_job(job_id: str):
    """Fetches a single job with its tasks by ID."""
    job_res = supabase.table("jobs").select("*").eq("id", job_id).execute()
    if not job_res.data:
        raise HTTPException(status_code=404, detail="Job not found")
    job = job_res.data[0]
    # Fetch tasks for this job
    tasks_res = supabase.table("tasks").select(
        "*, operation_types(name), resources(name)"
    ).eq("job_id", job_id).execute()
    job["tasks"] = tasks_res.data or []
    return job


@router.patch("/jobs/{job_id}/publish")
def publish_job(job_id: str):
    """
    Called by the desktop manager app to publish a DRAFT job.
    Changes status from DRAFT → OPEN so workers can see and claim it in the
    mobile Job Market screen.
    """
    # Verify the job exists and is in DRAFT status
    job_res = supabase.table("jobs").select("id, status").eq("id", job_id).execute()
    if not job_res.data:
        raise HTTPException(status_code=404, detail="Job not found")

    current_status = job_res.data[0].get("status", "")
    if current_status == "OPEN":
        return {"message": "Job is already published (OPEN).", "job_id": job_id}
    if current_status in ("COMPLETED", "IN_PROGRESS"):
        raise HTTPException(
            status_code=400,
            detail=f"Cannot publish a job that is already {current_status}."
        )

    # Update status to OPEN
    res = supabase.table("jobs").update({"status": "OPEN"}).eq("id", job_id).execute()
    if not res.data:
        raise HTTPException(status_code=500, detail="Failed to publish job.")

    return {
        "message": "Job published successfully! Workers can now see it in the Job Market.",
        "job_id": job_id,
        "status": "OPEN"
    }


@router.get("/schedule")
def get_schedule():
    """
    Fetches all scheduled/in-progress tasks to display on the global Gantt chart.
    Returns tasks with status SCHEDULED or IN_PROGRESS so the frontend can render
    them as blocks mapped to resource rows by 'assigned_resource_id'.
    """
    res = (
        supabase.table("tasks")
        .select("id, name, status, quantity_to_process, assigned_resource_id, "
                "scheduled_start_time, scheduled_end_time, "
                "jobs(id, title), resources(id, name, type)")
        .in_("status", ["SCHEDULED", "IN_PROGRESS", "COMPLETED"])
        .execute()
    )
    return res.data

@router.get("/tasks")
def get_tasks(resource_id: Optional[str] = None):
    """Fetches tasks, optionally filtered by resource_id for worker dashboards."""
    query = supabase.table("tasks").select("*, jobs(title), resources(name)")
    if resource_id:
        query = query.eq("assigned_resource_id", resource_id)
    res = query.execute()
    return res.data


@router.patch("/tasks/{task_id}/status")
def update_task_status(task_id: str, body: dict):
    """
    Called by the Flutter mobile app when a worker taps "Start" or "Complete".
    Using a PATCH request because we are only updating ONE specific field (status), 
    not the entire row.
    """
    # Extract the new status from the incoming JSON payload
    status = body.get("status")
    valid_statuses = ["SCHEDULED", "IN_PROGRESS", "COMPLETED"]
    
    # Safety Check: Don't let the Flutter app send a made-up status like "DONE"
    if status not in valid_statuses:
        raise HTTPException(status_code=400, detail="Invalid status")
        
    # Ask Supabase to update just the status column for this specific task
    res = supabase.table("tasks").update({"status": status}).eq("id", task_id).execute()
    
    if not res.data:
        raise HTTPException(status_code=404, detail="Task not found")
        
    # Return success so the Flutter app knows it can update its UI
    return {"message": f"Task updated to {status}", "task": res.data[0]}
