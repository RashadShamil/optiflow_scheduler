"""Small request-validation tests; database and CP-SAT integration are separate."""

import pytest
from pydantic import ValidationError

from models import CapabilityCreate, JobCreate, MachineBookingCreate, ResourceCreate, TaskInput


def test_resource_type_is_validated():
    with pytest.raises(ValidationError):
        ResourceCreate(name='Printer', type='PRINTER')


def test_capability_requires_positive_rate():
    with pytest.raises(ValidationError):
        CapabilityCreate(
            resource_id='r1',
            operation_type_id='o1',
            processing_rate_per_hr=0,
            cost_per_hour=10,
        )


def test_job_requires_at_least_one_task():
    with pytest.raises(ValidationError):
        JobCreate(
            title='Order',
            total_quantity=10,
            deadline='2030-01-01T00:00:00Z',
            tasks=[],
        )


def test_booking_end_must_be_after_start():
    with pytest.raises(ValidationError):
        MachineBookingCreate(
            machine_id='m1',
            start_time='2030-01-01T10:00:00Z',
            end_time='2030-01-01T09:00:00Z',
        )


def test_task_requires_resource_type():
    with pytest.raises(ValidationError):
        TaskInput(
            name='Print',
            operation_type_id='o1',
            quantity_to_process=100,
            machine_required=False,
            human_required=False,
        )
