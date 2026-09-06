"""FastAPI application entry point for OptiFlow.

This file intentionally contains only application bootstrapping. Business rules
live in `routes.py`, scheduling mathematics lives in `optimizer.py`, and the
Supabase client lives in `database.py`.
"""

import os
import traceback

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from routes import router

app = FastAPI(
    title='OptiFlow API',
    description='Print-shop scheduling, workforce, and resource-marketplace API.',
    version='3.0.0',
)

raw_origins = os.getenv('CORS_ORIGINS', '*')
allowed_origins = [item.strip() for item in raw_origins.split(',') if item.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins or ['*'],
    allow_credentials=False,
    allow_methods=['*'],
    allow_headers=['*'],
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """Log unexpected server errors without leaking stack traces to clients."""
    print(traceback.format_exc())
    return JSONResponse(status_code=500, content={'detail': 'Internal server error'})


app.include_router(router, prefix='/api')


@app.get('/')
def root():
    """Simple health endpoint used by deployment checks."""
    return {'message': 'OptiFlow API is online'}
