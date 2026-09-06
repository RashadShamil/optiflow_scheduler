"""Authentication and role helpers for FastAPI routes.

Flutter signs users in with Supabase Auth. Every API request sends that Supabase
access token as a Bearer token. These helpers ask Supabase to validate the token
and expose the authenticated user's role to route handlers.

Expected user metadata:
    role: MANAGER | WORKER | EXTERNAL
    full_name: optional display name
    resource_id: HUMAN resource UUID for an internal worker, when already linked
"""

import os
from dataclasses import dataclass

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from database import supabase

bearer = HTTPBearer(auto_error=False)
ALLOW_DEV_AUTH = os.getenv('ALLOW_DEV_AUTH', 'false').lower() == 'true'


@dataclass(frozen=True)
class CurrentUser:
    """Small authenticated-user object used by the rest of the backend."""

    id: str
    email: str | None
    role: str
    display_name: str
    resource_id: str | None


def _metadata_value(user, key: str):
    """Read a value from either user_metadata or app_metadata."""
    user_metadata = getattr(user, 'user_metadata', None) or {}
    app_metadata = getattr(user, 'app_metadata', None) or {}
    return user_metadata.get(key, app_metadata.get(key))


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> CurrentUser:
    """Validate the Supabase JWT and return normalized user information."""
    if credentials is None:
        if ALLOW_DEV_AUTH:
            return CurrentUser(
                id='dev-manager',
                email='dev@local',
                role='MANAGER',
                display_name='Development Manager',
                resource_id=None,
            )
        raise HTTPException(status_code=401, detail='Authentication required')

    try:
        response = supabase.auth.get_user(credentials.credentials)
        user = response.user
    except Exception as exc:
        raise HTTPException(status_code=401, detail='Invalid or expired login') from exc

    if user is None:
        raise HTTPException(status_code=401, detail='Invalid or expired login')

    role = str(_metadata_value(user, 'role') or 'EXTERNAL').upper()
    if role not in {'MANAGER', 'WORKER', 'EXTERNAL'}:
        role = 'EXTERNAL'

    full_name = _metadata_value(user, 'full_name')
    email = getattr(user, 'email', None)
    display_name = str(full_name or (email.split('@')[0] if email else 'OptiFlow User'))
    resource_id = _metadata_value(user, 'resource_id')

    return CurrentUser(
        id=str(user.id),
        email=email,
        role=role,
        display_name=display_name,
        resource_id=str(resource_id) if resource_id else None,
    )


def require_manager(user: CurrentUser = Depends(current_user)) -> CurrentUser:
    """Allow a route only for manager accounts."""
    if user.role != 'MANAGER':
        raise HTTPException(status_code=403, detail='Manager access required')
    return user


def require_worker(user: CurrentUser = Depends(current_user)) -> CurrentUser:
    """Allow a route only for internal worker accounts."""
    if user.role != 'WORKER':
        raise HTTPException(status_code=403, detail='Worker access required')
    return user


def require_external(user: CurrentUser = Depends(current_user)) -> CurrentUser:
    """Allow a route only for external marketplace users."""
    if user.role != 'EXTERNAL':
        raise HTTPException(status_code=403, detail='External-user access required')
    return user
