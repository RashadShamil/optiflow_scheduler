# OptiFlow Developer Guide

## What OptiFlow is

OptiFlow is a print-shop production scheduler plus workforce/resource marketplace.

The manager defines each incoming print job as a DAG of production tasks. Each task says whether it needs a **machine**, a **human**, or **both simultaneously**. The CP-SAT optimizer chooses compatible resources, places work inside shop hours, respects dependencies/bookings/locks, and may move future unlocked work when a more urgent job is optimized.

The same backend also supports:

- internal worker dispatch and mobile execution,
- manager-approved external HUMAN-task work offers,
- external machine-booking requests that require manager approval,
- a shared editable Gantt chart for machines and humans.

## Clean architecture

```text
Flutter
├── Manager desktop
│   ├── Dashboard
│   ├── Machines
│   ├── Jobs + DAG + Optimize
│   ├── Editable Gantt
│   ├── Team
│   ├── Skills Matrix
│   └── Booking Approvals
│
├── Internal worker mobile
│   └── Offered -> Accepted -> In Progress -> Completed
│
└── External mobile
    ├── Human Work Market
    ├── Machine Shop + QR
    ├── My Work
    └── My Booking Requests
             │
             ▼
        FastAPI /api
             │
      ┌──────┴──────┐
      ▼             ▼
   Supabase      CP-SAT
```

Flutter uses Supabase only for authentication/session tokens. **Production CRUD goes through FastAPI.**

## Backend files

### `main.py`
Creates the FastAPI app, CORS middleware, error handler and `/api` router.

### `database.py`
Creates the single shared Supabase client. No other Python file should hard-code Supabase credentials.

### `auth.py`
Validates the Supabase access token and exposes `MANAGER`, `WORKER`, and `EXTERNAL` roles.

### `models.py`
Contains Pydantic request models and boundary validation.

### `routes.py`
Application/business workflow:

- operation types,
- machines/humans,
- skills matrix,
- jobs and DAG creation,
- explicit Optimize action,
- Gantt data/manual moves,
- worker task transitions,
- external machine booking requests/approval,
- external HUMAN work offers/claims,
- dashboard statistics.

### `optimizer.py`
The scheduling brain. Key rules:

- manager selects a job to optimize;
- requested job + already-scheduled movable work are solved together;
- unrelated DRAFT jobs are not automatically scheduled;
- HIGH/URGENT priority affects completion ordering;
- deadlines carry a strong lateness penalty;
- only active/idle capable resources are candidates;
- machine + human tasks reserve both at the same time;
- approved machine bookings become fixed machine intervals;
- manually locked, offered, accepted and in-progress work is fixed;
- work occurs only inside configured shop hours;
- scheduling can spill into later workdays.

### `migrations/001_scheduler_v3.sql`
Required schema additions for V3.

## Database setup

Before running the V3 backend, execute:

```text
optiflow_back/migrations/001_scheduler_v3.sql
```

in the Supabase SQL Editor.

The migration adds:

- `jobs.priority`
- `tasks.machine_required`
- `tasks.human_required`
- `tasks.assigned_machine_id`
- `tasks.assigned_human_id`
- `tasks.schedule_locked`
- `task_allowed_resources` for optional resource restrictions/external claims
- external rental fields on `resources`
- `machine_bookings`
- `work_offers`

The old `assigned_resource_id` remains temporarily for backward compatibility.

## Task resource model

Examples:

### Printing

```text
Operation: Offset Printing
Requires machine: YES
Requires human: YES
```

The solver might choose:

```text
Machine: Heidelberg Printer 1
Human:   Operator Rashad
```

Both are occupied during the same task interval.

### Automatic cutting

```text
Requires machine: YES
Requires human: NO
```

### Folding

```text
Requires machine: NO
Requires human: YES
```

A manager can publish this human-only task to the external work market.

## Priority / rescheduling behavior

When the manager optimizes a newly entered urgent job, OptiFlow may rearrange other scheduled tasks only when they are:

```text
not started
AND not offered/accepted
AND not manually locked
```

It does not move:

- `OFFERED`
- `ACCEPTED`
- `IN_PROGRESS`
- completed work
- approved machine bookings
- manual Gantt locks

## Gantt manual moves

Dragging a task can:

- change its start time,
- move its machine portion to another compatible machine,
- move its human portion to another compatible worker.

FastAPI checks:

- capability,
- shop hours,
- production overlaps,
- approved bookings,
- DAG predecessor/successor order.

A successful manual move sets `schedule_locked=true`. Use **Unlock for Optimizer** if the manager later wants CP-SAT to move it again.

## Shop hours

Configured in `.env`:

```env
SHOP_TIMEZONE=Asia/Colombo
SHOP_OPEN_HOUR=8
SHOP_CLOSE_HOUR=18
SHOP_WORK_DAYS=0,1,2,3,4,5
MAX_PLANNING_DAYS=60
```

Python weekday values are Monday=0 through Sunday=6.

A task must fit completely inside one shop day. If a single process takes longer than one day, split it into smaller DAG tasks. The scheduler will naturally put later DAG tasks on following workdays.

## Internal mobile workflow

After optimization a HUMAN task is `SCHEDULED`.

The manager presses **Send to worker mobile app**:

```text
SCHEDULED
   ↓ manager dispatches
OFFERED
   ↓ worker accepts
ACCEPTED
   ↓ worker starts
IN_PROGRESS
   ↓ worker completes
COMPLETED
```

Dispatch/acceptance locks the scheduled task so a later optimizer does not silently move work already promised to a person.

## External human work

Only a manager can publish an individual **human-only** task.

```text
Manager approves task + pay + estimated time
                ↓
              OPEN
                ↓ external user claims
             CLAIMED
                ↓
job becomes NEEDS_REOPTIMIZATION
                ↓
manager runs Optimize again
                ↓
external person's HUMAN resource receives a schedule
```

Claiming does not automatically re-run the optimizer; scheduling remains a manager decision.

## External machine booking

```text
External user sees bookable machine + busy periods
                     ↓
                Requests slot
                     ↓
                  PENDING
                     ↓
            Manager approves/rejects
                     ↓
 APPROVED booking becomes a hard CP-SAT machine blocker
```

There is no online payment. `quoted_amount` is calculated and stored only.

## Supabase Auth roles

Set `role` in user metadata:

```text
MANAGER
WORKER
EXTERNAL
```

For an internal worker, also set:

```text
resource_id = UUID of their HUMAN resource row
```

External worker resources are created automatically the first time they claim approved external work.

## Local environment

Copy:

```cmd
copy optiflow_back\.env.example optiflow_back\.env
```

Then fill in your values.

Flutter is started with:

```cmd
flutter run ^
  --dart-define=SUPABASE_URL=YOUR_URL ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY ^
  --dart-define=API_BASE_URL=http://localhost:8000
```

Use the deployed Render URL instead of localhost when testing on a physical phone unless the phone can reach the development computer over the network.

## Backend verification

```cmd
cd optiflow_back
pip install -r requirements-dev.txt
python -m compileall .
pytest -q
uvicorn main:app --reload
```

## Flutter verification

```cmd
cd optiflow_front
flutter pub get
dart format lib test
flutter analyze
flutter test
```

## Files intentionally removed

Do not recreate these architectures:

- `booking_manager.py` — booking now belongs to canonical FastAPI routes.
- `databse.py` — typo/duplicate; use `database.py`.
- `route.py` — duplicate; use `routes.py`.
- `SupabaseService` for production CRUD — Flutter should call FastAPI.
- separate mobile API service — use the shared `core/services/api_service.dart`.
- `slices/worker` — duplicate worker application; `lib/mobile` is canonical.
- fake Settings/Analytics values.
- seed scripts that wipe/replace production tables.
- tracked `.env.local`, caches, build output and IDE state.

## Security note

If `.env.local` previously contained any private/service-role credential and was committed to this public repository, deleting the current file does not remove it from Git history. Rotate that credential.
```
