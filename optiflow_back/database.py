"""Shared Supabase connection used by every backend module.

Keep database setup in one place so routes, authentication, and the optimizer do
not create competing clients or hard-code credentials. Local development loads
`.env` first and then `.env.local` if it exists.
"""

import os

from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv()
load_dotenv('.env.local', override=False)

SUPABASE_URL = os.getenv('SUPABASE_URL')
SUPABASE_KEY = os.getenv('SUPABASE_KEY')

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError('SUPABASE_URL and SUPABASE_KEY must be configured')

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
