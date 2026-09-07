"""Pydantic request models used by the OptiFlow API.

Database rows stay in Supabase; these models validate only data entering the API.
Keeping them in one file avoids duplicated validation rules across endpoints.
"""

from typing import List, Optional

from pydantic import BaseModel, Field, field_validator


class OperationTypeCreate(BaseModel):
    name: str = Field(min_length=1)


class OperationTypeUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1)


class ResourceCreate(BaseModel):
    name: str = Field(min_length=1)
    type: str
    status: str = "ACTIVE"
    profile_id: Optional[str] = None
    auth_user_id: Optional[str] = None
    price_per_hour: Optional[float] = Field(default=None, ge=0)
    image_url: Optional[str] = None
    bookable: bool = False
    is_external: bool = False


class ResourceUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1)
    type: Optional[str] = None
    status: Optional[str] = None
    profile_id: Optional[str] = None
    auth_user_id: Optional[str] = None
    price_per_hour: Optional[float] = Field(default=None, ge=0)
    image_url: Optional[str] = None
    bookable: Optional[bool] = None
    is_external: Optional[bool] = None


class CapabilityCreate(BaseModel):
    resource_id: str
    operation_type_id: str
    processing_rate_per_hr: float = Field(gt=0)
    setup_time_minutes: int = Field(default=0, ge=0)
    cost_per_hour: float = Field(gt=0)


class CapabilityUpdate(BaseModel):
    processing_rate_per_hr: Optional[float] = Field(default=None, gt=0)
    setup_time_minutes: Optional[int] = Field(default=None, ge=0)
    cost_per_hour: Optional[float] = Field(default=None, gt=0)


class TaskDependencyInput(BaseModel):
    predecessor_index: int = Field(ge=0)
    successor_index: int = Field(ge=0)
    mandatory_wait_minutes: int = Field(default=0, ge=0)


class TaskInput(BaseModel):
    operation_type_id: str
    name: str = Field(min_length=1)
    quantity_to_process: int = Field(gt=0)
    processing_time_minutes: Optional[int] = Field(default=None, gt=0)
    break_after_minutes: int = Field(default=0, ge=0)
    break_type: str = "NONE"
    show_in_mobile: bool = True
    machine_required: bool = False
    human_required: bool = False

    @field_validator("break_type")
    @classmethod
    def validate_break_type(cls, value: str) -> str:
        value = value.upper()
        if value not in {"NONE", "HUMAN", "MACHINE"}:
            raise ValueError("break_type must be NONE, HUMAN, or MACHINE")
        return value


class JobOrderInput(BaseModel):
    title: str = Field(min_length=1)
    client_name: Optional[str] = None
    total_quantity: int = Field(gt=0)
    deadline: str
    created_by: Optional[str] = None
    priority: str = "MEDIUM"
    tasks: List[TaskInput]
    dependencies: List[TaskDependencyInput] = []

    @field_validator("priority")
    @classmethod
    def validate_priority(cls, value: str) -> str:
        value = value.upper()
        if value not in {"HIGH", "MEDIUM", "LOW"}:
            raise ValueError("priority must be HIGH, MEDIUM, or LOW")
        return value


class TaskStatusUpdate(BaseModel):
    status: str


class TaskCompletionRequest(BaseModel):
    proof_url: Optional[str] = None
    notes: Optional[str] = None


class BookingRequest(BaseModel):
    machine_id: str
    user_name: Optional[str] = None
    start_time: str
    end_time: str
    notes: Optional[str] = None


class WorkOfferCreate(BaseModel):
    task_id: str
    pay_amount: float = Field(gt=0)
    estimated_minutes: int = Field(gt=0)
    approved_by_user_id: str
    notes: Optional[str] = None
