"""Shared Supabase connection for the OptiFlow backend.

Every backend module imports this single client. Credentials must come from
environment variables; secrets are never committed to Git.
"""

import os
from pathlib import Path

from dotenv import load_dotenv
from supabase import Client, create_client

# Load local environment variables (.env.local or .env in optiflow_back or repo root)
load_dotenv(Path(__file__).with_name(".env.local"), override=False)
load_dotenv(Path(__file__).with_name(".env"), override=False)
load_dotenv(Path(__file__).resolve().parent.parent / ".env.local", override=False)
load_dotenv(Path(__file__).resolve().parent.parent / ".env", override=False)
load_dotenv(override=False)

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError(
        "Missing SUPABASE_URL or SUPABASE_KEY. Copy .env.example to .env for local development."
    )

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
