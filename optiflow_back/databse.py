"""Backward-compatible import for the old misspelled module name.

New backend code imports :mod:`database`. The optimizer still imports this file,
so this tiny shim preserves the existing scheduling engine without duplicating a
Supabase client. It can be removed after optimizer.py is renamed/import-cleaned
in a later isolated optimizer refactor.
"""

from database import supabase

__all__ = ["supabase"]
