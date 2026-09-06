-- OptiFlow Scheduler v3 schema additions.
-- Run once in the Supabase SQL Editor before using the cleaned backend.
-- Existing jobs/tasks/resources are kept; this migration only adds columns/tables.

alter table public.jobs
    add column if not exists priority text not null default 'MEDIUM';

alter table public.resources
    add column if not exists price_per_hour numeric,
    add column if not exists image_url text,
    add column if not exists bookable boolean not null default false,
    add column if not exists auth_user_id uuid,
    add column if not exists is_external boolean not null default false;

alter table public.tasks
    add column if not exists machine_required boolean not null default false,
    add column if not exists human_required boolean not null default false,
    add column if not exists processing_time_minutes integer,
    add column if not exists break_after_minutes integer not null default 0,
    add column if not exists schedule_locked boolean not null default false,
    add column if not exists assigned_machine_id uuid references public.resources(id),
    add column if not exists assigned_human_id uuid references public.resources(id);

-- Optional per-task resource restrictions (manager choice or claimed external worker).
create table if not exists public.task_allowed_resources (
    task_id uuid not null references public.tasks(id) on delete cascade,
    resource_id uuid not null references public.resources(id) on delete cascade,
    primary key (task_id, resource_id)
);

-- A user asks to rent a machine; only APPROVED rows block the production solver.
create table if not exists public.machine_bookings (
    id uuid primary key,
    machine_id uuid not null references public.resources(id) on delete cascade,
    requested_by_user_id uuid not null,
    requested_by_name text not null,
    start_time timestamptz not null,
    end_time timestamptz not null,
    notes text,
    quoted_amount numeric not null default 0,
    status text not null default 'PENDING',
    reviewed_by_user_id uuid,
    reviewed_at timestamptz,
    created_at timestamptz not null default now(),
    constraint machine_booking_valid_time check (end_time > start_time),
    constraint machine_booking_valid_status check (
        status in ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')
    )
);

-- Manager-approved individual HUMAN tasks shown to external workers.
create table if not exists public.work_offers (
    id uuid primary key,
    task_id uuid not null references public.tasks(id) on delete cascade,
    pay_amount numeric not null,
    estimated_minutes integer not null,
    notes text,
    status text not null default 'OPEN',
    approved_by_user_id uuid not null,
    claimed_by_user_id uuid,
    claimed_by_resource_id uuid references public.resources(id),
    claimed_at timestamptz,
    created_at timestamptz not null default now(),
    constraint work_offer_positive_pay check (pay_amount > 0),
    constraint work_offer_positive_time check (estimated_minutes > 0),
    constraint work_offer_valid_status check (
        status in ('OPEN', 'CLAIMED', 'CLOSED', 'CANCELLED')
    )
);

create index if not exists idx_tasks_assigned_machine
    on public.tasks(assigned_machine_id);
create index if not exists idx_tasks_assigned_human
    on public.tasks(assigned_human_id);
create index if not exists idx_tasks_schedule_time
    on public.tasks(scheduled_start_time, scheduled_end_time);
create index if not exists idx_machine_bookings_machine_status
    on public.machine_bookings(machine_id, status, start_time, end_time);
create index if not exists idx_work_offers_status
    on public.work_offers(status, created_at);
create unique index if not exists idx_resources_auth_user_unique
    on public.resources(auth_user_id)
    where auth_user_id is not null;
