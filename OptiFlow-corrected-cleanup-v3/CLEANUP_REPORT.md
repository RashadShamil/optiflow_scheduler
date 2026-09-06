# OptiFlow Corrected Cleanup Report

This cleanup was rebuilt after the product workflow was clarified. The earlier cleanup incorrectly treated the Gantt, machine marketplace, work market and booking workflow as legacy. **V3 preserves those capabilities and removes only duplicate/fake/generated implementations.**

## Product contract implemented

1. Manager creates a job and its task-process DAG first.
2. Every task explicitly states whether it needs a machine, a human, or both simultaneously.
3. Manager decides when to run optimization.
4. CP-SAT can rearrange not-started, unlocked scheduled work when a higher-priority job arrives.
5. `OFFERED`, `ACCEPTED`, `IN_PROGRESS`, completed and manually locked work is not automatically rearranged.
6. Scheduling is limited to configurable shop hours and can continue across future workdays.
7. The Gantt includes machine and human rows and supports manager drag/drop to compatible resources/times.
8. A successful manual Gantt move is locked so later optimization respects it until the manager unlocks it.
9. Manager dispatches internal human work to mobile: Offered -> Accepted -> In Progress -> Completed.
10. Manager may approve/publish an individual human-only task to external workers for a specified payment.
11. External users may request available machine time. Manager approval is required and there is no online payment in this version.
12. Approved machine bookings become hard scheduler blockers.
13. One Flutter codebase uses role-based MANAGER, WORKER and EXTERNAL screens, all backed by the same FastAPI API.

## Important modeling correction

The original optimizer selected exactly one resource per task. That could not represent a printing step that needs both a printer and an operator. V3 selects a valid `(machine, human)` combination when both are required and reserves both resources over the same interval.

## Multi-day scheduling

Default calendar settings are in `.env.example`:

- timezone: `Asia/Colombo`
- hours: `08:00-18:00`
- work days: Monday-Saturday (`0,1,2,3,4,5`)
- planning horizon: up to 60 days

A single task must fit within one workday. If one process itself takes longer than the daily shop window, split it into smaller DAG tasks. This prevents the current non-preemptive task model from pretending a machine/worker operates overnight.

## Database migration required

Run `optiflow_back/migrations/001_scheduler_v3.sql` in the Supabase SQL editor. It preserves existing tables and adds priority, explicit task resource requirements, separate machine/human assignments, Gantt lock state, machine booking requests and external work offers.

## Security / repository cleanup

`.env.local` is removed from the tracked tree and replaced by `.env.example`. Removing it from the latest tree does **not** erase Git history. Rotate any private/service credentials that were ever committed.

## Validation performed here

- All replacement Python files pass `python -m py_compile`.
- A bracket/parenthesis structural pass was run across replacement Dart files.
- Flutter/Dart executables are not available in this execution environment, so `flutter analyze` and `flutter test` must be run on the user's local Flutter installation after applying the bundle.
- The GitHub connector still returns HTTP 403 for branch/file writes, so the repository itself was not modified from ChatGPT.
