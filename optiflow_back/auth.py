"""Authentication and role helpers for mobile-facing API endpoints.

The Windows manager UI is currently not authenticated, so manager CRUD routes
remain backward compatible. Mobile worker/outsider routes require a valid
Supabase access token and derive role information from ``profiles``.
"""

from dataclasses import dataclass
from typing import Optional

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from database import supabase

_bearer = HTTPBearer(auto_error=False)

OUTSIDER_ROLES = {"OUTSIDER", "EXTERNAL", "CUSTOMER", "FREELANCER"}
MANAGER_ROLES = {"MANAGER", "ADMIN", "SUPER_ADMIN", "SUPERADMIN"}


@dataclass(frozen=True)
class CurrentUser:
    """Authenticated user plus the matching profile row."""

    id: str
    email: str
    full_name: str
    role: str


def _profile_for_user(user_id: str) -> dict:
    response = (
        supabase.table("profiles")
        .select("id,email,full_name,role")
        .eq("id", user_id)
        .execute()
    )
    return response.data[0] if response.data else {}


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
) -> CurrentUser:
    """Validate a Supabase JWT and return the user's application profile."""
    if credentials is None:
        raise HTTPException(status_code=401, detail="Authentication required")

    try:
        auth_response = supabase.auth.get_user(credentials.credentials)
        auth_user = auth_response.user
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired session") from exc

    if auth_user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired session")

    profile = _profile_for_user(str(auth_user.id))
    role = str(profile.get("role") or "WORKER").upper()
    full_name = (
        profile.get("full_name")
        or (auth_user.user_metadata or {}).get("full_name")
        or (auth_user.email or "Worker").split("@")[0]
    )

    return CurrentUser(
        id=str(auth_user.id),
        email=str(profile.get("email") or auth_user.email or ""),
        full_name=str(full_name),
        role=role,
    )


def is_outsider(user: CurrentUser) -> bool:
    """Recognize outsider roles and external resource links.

    The exact Supabase enum labels can differ between deployments, so the
    resource.is_external flag is also treated as authoritative.
    """
    if user.role in OUTSIDER_ROLES:
        return True
    for field in ("profile_id", "auth_user_id"):
        response = (
            supabase.table("resources")
            .select("id")
            .eq(field, user.id)
            .eq("is_external", True)
            .limit(1)
            .execute()
        )
        if response.data:
            return True
    return False


def is_manager(user: CurrentUser) -> bool:
    return user.role in MANAGER_ROLES


def linked_human_resource(user: CurrentUser) -> Optional[dict]:
    """Return the HUMAN resource linked to this profile/auth user, if any."""
    by_profile = (
        supabase.table("resources")
        .select("*")
        .eq("type", "HUMAN")
        .eq("profile_id", user.id)
        .limit(1)
        .execute()
    )
    if by_profile.data:
        return by_profile.data[0]

    by_auth = (
        supabase.table("resources")
        .select("*")
        .eq("type", "HUMAN")
        .eq("auth_user_id", user.id)
        .limit(1)
        .execute()
    )
    return by_auth.data[0] if by_auth.data else None
