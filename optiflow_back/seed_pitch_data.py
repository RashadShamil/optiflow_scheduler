"""DESTRUCTIVE DEVELOPMENT SEED.

This script deletes existing operational data before inserting demo/pitch data.
Run it only against a disposable development Supabase project.
"""

import os
import uuid
from datetime import datetime, timedelta
from supabase import create_client
from dotenv import load_dotenv

def seed_database():
    load_dotenv(".env.local")
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_KEY")
    
    if not url or not key:
        print("Missing Supabase credentials in .env.local")
        return
        
    client = create_client(url, key)
    print("Connected to Supabase. Clearing old data...")

    # Clear old data
    try:
        tables = ["incidents", "tasks", "jobs", "resource_capabilities", "resources", "operation_types"]
        for table in tables:
            try:
                client.table(table).delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
            except Exception as inner:
                print(f"Skipped clearing {table}: {inner}")
        print("Cleared old data successfully.")
    except Exception as e:
        print(f"Error clearing data: {e}")

    # =======================================================
    # 1. OPERATION TYPES
    # =======================================================
    op_print_bw = "11111111-1111-1111-1111-111111111111"
    op_print_color = "11111111-1111-1111-1111-111111111112"
    op_cut = "11111111-1111-1111-1111-111111111113"
    op_bind = "11111111-1111-1111-1111-111111111114"
    op_large = "11111111-1111-1111-1111-111111111115"

    operations = [
        {"id": op_print_bw, "name": "High-Speed B/W Printing"},
        {"id": op_print_color, "name": "Premium Color Printing"},
        {"id": op_cut, "name": "Guillotine Cutting & Trimming"},
        {"id": op_bind, "name": "Perfect Binding (Glue)"},
        {"id": op_large, "name": "Large Format Printing"},
    ]
    client.table("operation_types").insert(operations).execute()
    print("Inserted Operation Types.")

    # =======================================================
    # 2. RESOURCES (Machines & Humans)
    # =======================================================
    m1 = "22222222-2222-2222-2222-222222222221"
    m2 = "22222222-2222-2222-2222-222222222222"
    m3 = "22222222-2222-2222-2222-222222222223"
    m4 = "22222222-2222-2222-2222-222222222224"
    m5 = "22222222-2222-2222-2222-222222222225"
    
    h1 = "33333333-3333-3333-3333-333333333331"
    h2 = "33333333-3333-3333-3333-333333333332"
    h3 = "33333333-3333-3333-3333-333333333333"
    h4 = "33333333-3333-3333-3333-333333333334"

    resources = [
        # Machines
        {"id": m1, "name": "Heidelberg Speedmaster", "type": "MACHINE", "status": "ACTIVE"},
        {"id": m2, "name": "HP Indigo 12000", "type": "MACHINE", "status": "ACTIVE"},
        {"id": m3, "name": "Polar 115", "type": "MACHINE", "status": "MAINTENANCE"},
        {"id": m4, "name": "Horizon BQ-470", "type": "MACHINE", "status": "ACTIVE"},
        {"id": m5, "name": "Epson SureColor", "type": "MACHINE", "status": "OFFLINE"},
        
        # Humans
        {"id": h1, "name": "Sarah Chen (Supervisor)", "type": "HUMAN", "status": "ACTIVE"},
        {"id": h2, "name": "Marcus Johnson (Press Operator)", "type": "HUMAN", "status": "ACTIVE"},
        {"id": h3, "name": "Elena Rodriguez (Bindery Tech)", "type": "HUMAN", "status": "ACTIVE"},
        {"id": h4, "name": "David Kim (Pre-press)", "type": "HUMAN", "status": "OFFLINE"},
    ]
    client.table("resources").insert(resources).execute()
    print("Inserted Resources.")

    # =======================================================
    # 3. JOBS
    # =======================================================
    j1 = "44444444-4444-4444-4444-444444444441"
    j2 = "44444444-4444-4444-4444-444444444442"
    j3 = "44444444-4444-4444-4444-444444444443"
    j4 = "44444444-4444-4444-4444-444444444444"

    now = datetime.now()
    jobs = [
        {
            "id": j1,
            "title": "Spring Catalog 2026 - Nike",
            "client_name": "Nike Inc.",
            "total_quantity": 5000,
            "status": "IN_PROGRESS",
            "deadline": (now + timedelta(days=2)).isoformat(),
            "created_at": (now - timedelta(days=2)).isoformat()
        },
        {
            "id": j2,
            "title": "Q1 Annual Reports - TechCorp",
            "client_name": "TechCorp Solutions",
            "total_quantity": 1000,
            "status": "COMPLETED",
            "deadline": now.isoformat(),
            "created_at": (now - timedelta(days=5)).isoformat()
        },
        {
            "id": j3,
            "title": "Event Banners - City Marathon",
            "client_name": "City Sports Dept",
            "total_quantity": 200,
            "status": "DRAFT", # Changed PENDING to DRAFT
            "deadline": (now - timedelta(days=1)).isoformat(), # Intentionally overdue!
            "created_at": (now - timedelta(days=3)).isoformat()
        },
        {
            "id": j4,
            "title": "Rush Job - Local Business Flyers",
            "client_name": "Local Business",
            "total_quantity": 10000,
            "status": "IN_PROGRESS",
            "deadline": (now + timedelta(days=1)).isoformat(),
            "created_at": (now - timedelta(days=1)).isoformat()
        }
    ]
    client.table("jobs").insert(jobs).execute()
    print("Inserted Jobs.")

    # =======================================================
    # 4. TASKS (with Gantt Schedule data)
    # =======================================================
    def time_today(hour, minute=0):
        return now.replace(hour=hour, minute=minute, second=0, microsecond=0).isoformat()

    # Task UUIDs
    t1_1 = "55555555-5555-5555-5555-555555555551" # Nike Cover
    t1_2 = "55555555-5555-5555-5555-555555555552" # Nike Inner
    t1_3 = "55555555-5555-5555-5555-555555555553" # Nike Bind
    
    t2_1 = "55555555-5555-5555-5555-555555555554" # TechCorp Print
    t2_2 = "55555555-5555-5555-5555-555555555555" # TechCorp Cut
    t2_3 = "55555555-5555-5555-5555-555555555556" # TechCorp Bind
    
    t3_1 = "55555555-5555-5555-5555-555555555557" # Marathon Banner
    
    t4_1 = "55555555-5555-5555-5555-555555555558" # Rush Bind

    tasks = [
        # Job 1 Tasks
        {"id": t1_1, "job_id": j1, "operation_type_id": op_print_color, "assigned_resource_id": m2, "name": "Color Printing Cover", "status": "COMPLETED", "quantity_to_process": 5000, "scheduled_start_time": time_today(9, 0), "scheduled_end_time": time_today(11, 0), "completed_at": (now - timedelta(hours=2)).isoformat()},
        {"id": t1_2, "job_id": j1, "operation_type_id": op_print_bw, "assigned_resource_id": m1, "name": "B/W Printing Inner Pages", "status": "IN_PROGRESS", "quantity_to_process": 5000, "scheduled_start_time": time_today(12, 0), "scheduled_end_time": time_today(16, 0)},
        {"id": t1_3, "job_id": j1, "operation_type_id": op_bind, "assigned_resource_id": m4, "name": "Perfect Binding", "status": "PENDING", "quantity_to_process": 5000, "scheduled_start_time": time_today(13, 0), "scheduled_end_time": time_today(15, 0)},
        
        # Job 2 Tasks
        {"id": t2_1, "job_id": j2, "operation_type_id": op_print_color, "assigned_resource_id": m2, "name": "Report Printing", "status": "COMPLETED", "quantity_to_process": 1000, "scheduled_start_time": time_today(8, 0), "scheduled_end_time": time_today(9, 0), "completed_at": (now - timedelta(days=1)).isoformat()},
        {"id": t2_2, "job_id": j2, "operation_type_id": op_cut, "assigned_resource_id": m3, "name": "Trimming Edges", "status": "COMPLETED", "quantity_to_process": 1000, "scheduled_start_time": time_today(8, 30), "scheduled_end_time": time_today(9, 30), "completed_at": (now - timedelta(days=1, hours=-2)).isoformat()},
        {"id": t2_3, "job_id": j2, "operation_type_id": op_bind, "assigned_resource_id": m4, "name": "Final Binding", "status": "COMPLETED", "quantity_to_process": 1000, "scheduled_start_time": time_today(8, 0), "scheduled_end_time": time_today(10, 0), "completed_at": (now - timedelta(hours=5)).isoformat()},
        
        # Job 3 Task
        {"id": t3_1, "job_id": j3, "operation_type_id": op_large, "assigned_resource_id": m5, "name": "Banner Printing", "status": "PENDING", "quantity_to_process": 200},

        # Job 4 Task (Conflict! Overlaps with t1_3 on m4)
        {"id": t4_1, "job_id": j4, "operation_type_id": op_bind, "assigned_resource_id": m4, "name": "Rush Job Binding", "status": "PENDING", "quantity_to_process": 10000, "scheduled_start_time": time_today(14, 0), "scheduled_end_time": time_today(16, 0)},
    ]
    client.table("tasks").insert(tasks).execute()
    print("Inserted Tasks with schedule bookings.")

    # =======================================================
    # 6. RESOURCE CAPABILITIES
    # =======================================================
    c1 = str(uuid.uuid4())
    c2 = str(uuid.uuid4())
    c3 = str(uuid.uuid4())
    c4 = str(uuid.uuid4())
    c5 = str(uuid.uuid4())

    capabilities = [
        {"id": c1, "resource_id": m1, "operation_type_id": op_print_bw, "processing_rate_per_hr": 15000, "setup_time_minutes": 30, "cost_per_hour": 150.0},
        {"id": c2, "resource_id": m2, "operation_type_id": op_print_color, "processing_rate_per_hr": 3000, "setup_time_minutes": 15, "cost_per_hour": 80.0},
        {"id": c3, "resource_id": m3, "operation_type_id": op_cut, "processing_rate_per_hr": 5000, "setup_time_minutes": 10, "cost_per_hour": 40.0},
        {"id": c4, "resource_id": m4, "operation_type_id": op_bind, "processing_rate_per_hr": 2000, "setup_time_minutes": 45, "cost_per_hour": 120.0},
        {"id": c5, "resource_id": m5, "operation_type_id": op_large, "processing_rate_per_hr": 50, "setup_time_minutes": 15, "cost_per_hour": 200.0},
    ]
    client.table("resource_capabilities").insert(capabilities).execute()
    print("Inserted Resource Capabilities.")


    print("✅ Database successfully seeded with MVP Pitch Data!")

if __name__ == "__main__":
    seed_database()
