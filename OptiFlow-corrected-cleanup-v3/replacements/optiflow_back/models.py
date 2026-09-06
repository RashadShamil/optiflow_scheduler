"""Pydantic request models shared by OptiFlow API routes.

The models keep validation at the API boundary so malformed quantities, invalid
statuses, impossible durations, or unsupported roles never reach the scheduler.
"""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

ResourceType = Literal['MACHINE', 'HUMAN']
ResourceStatus = Literal['ACTIVE', 'IDLE', 'MAINTENANCE', 'OFFLINE']
Priority = Literal['LOW', 'MEDIUM', 'HIGH', 'URGENT']
TaskStatus = Literal[
    'PENDING',
    'SCHEDULED',
    'OFFERED',
    'ACCEPTED',
    'IN_PROGRESS',
    'COMPLETED',
]
BookingStatus = Literal['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED']
OfferStatus = Literal['OPEN', 'CLAIMED', 'CLOSED', 'CANCELLED']


class OperationTypeCreate(BaseModel):
    """Create a named production operation such as Printing or Folding."""

    name: str = Field(min_length=1)


class OperationTypeUpdate(BaseModel):
    """Rename an existing production operation."""

    name: str | None = Field(default=None, min_length=1)


class ResourceCreate(BaseModel):
    """Register a machine or human resource in the shared resource pool."""

    name: str = Field(min_length=1)
    type: ResourceType
    status: ResourceStatus = 'ACTIVE'
    price_per_hour: float | None = Field(default=None, ge=0)
    image_url: str | None = None
    bookable: bool = False


class ResourceUpdate(BaseModel):
    """Change only the supplied resource fields."""

    name: str | None = Field(default=None, min_length=1)
    type: ResourceType | None = None
    status: ResourceStatus | None = None
    price_per_hour: float | None = Field(default=None, ge=0)
    image_url: str | None = None
    bookable: bool | None = None


class CapabilityCreate(BaseModel):
    """Describe how fast and how expensive a resource performs an operation."""

    resource_id: str
    operation_type_id: str
    processing_rate_per_hr: float = Field(gt=0)
    setup_time_minutes: int = Field(default=0, ge=0)
    cost_per_hour: float = Field(default=0, ge=0)


class CapabilityUpdate(BaseModel):
    """Update performance/cost values for one resource capability."""

    processing_rate_per_hr: float | None = Field(default=None, gt=0)
    setup_time_minutes: int | None = Field(default=None, ge=0)
    cost_per_hour: float | None = Field(default=None, ge=0)


class TaskDependencyInput(BaseModel):
    """Reference two tasks by their positions in a new-job request."""

    predecessor_index: int = Field(ge=0)
    successor_index: int = Field(ge=0)
    mandatory_wait_minutes: int = Field(default=0, ge=0)


class TaskInput(BaseModel):
    """Define one node in the production-process DAG.

    A task may require a machine, a human, or both simultaneously. If neither is
    selected the optimizer keeps backward compatibility and chooses one capable
    resource of either type.
    """

    name: str = Field(min_length=1)
    operation_type_id: str
    quantity_to_process: int = Field(gt=0)
    processing_time_minutes: int | None = Field(default=None, gt=0)
    machine_required: bool = False
    human_required: bool = False
    break_after_minutes: int = Field(default=0, ge=0)
    allowed_resource_ids: list[str] = Field(default_factory=list)

    @model_validator(mode='after')
    def validate_resource_requirement(self):
        """Every new DAG node must reserve a machine, a human, or both."""
        if not self.machine_required and not self.human_required:
            raise ValueError('Task must require a machine, a human, or both')
        return self


class JobCreate(BaseModel):
    """Create a complete print job with its DAG before optimization."""

    title: str = Field(min_length=1)
    client_name: str | None = None
    total_quantity: int = Field(gt=0)
    priority: Priority = 'MEDIUM'
    deadline: datetime
    created_by: str | None = None
    tasks: list[TaskInput] = Field(min_length=1)
    dependencies: list[TaskDependencyInput] = Field(default_factory=list)


class TaskStatusUpdate(BaseModel):
    """Request a legal task-workflow status transition."""

    status: TaskStatus


class ScheduleMoveRequest(BaseModel):
    """Manually move a scheduled task from the manager Gantt chart."""

    resource_id: str
    start_time: datetime
    lock: bool = True


class ScheduleLockRequest(BaseModel):
    """Lock or unlock a task so future optimizations respect manager intent."""

    locked: bool


class MachineBookingCreate(BaseModel):
    """External user's request to reserve a bookable machine."""

    machine_id: str
    start_time: datetime
    end_time: datetime
    notes: str | None = None

    @model_validator(mode='after')
    def validate_range(self):
        if self.end_time <= self.start_time:
            raise ValueError('end_time must be after start_time')
        return self


class BookingDecision(BaseModel):
    """Manager approval/rejection for a machine booking request."""

    status: Literal['APPROVED', 'REJECTED']


class WorkOfferCreate(BaseModel):
    """Manager-approved external paid offer for one human-only production task."""

    pay_amount: float = Field(gt=0)
    estimated_minutes: int = Field(gt=0)
    notes: str | None = None
