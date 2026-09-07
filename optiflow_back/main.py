"""OptiFlow FastAPI application bootstrap.

This module intentionally contains only application setup. Business logic lives in
``route.py`` and service modules so a developer can understand the backend without
having to scan one giant file.
"""

import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from route import router

logger = logging.getLogger("optiflow")

app = FastAPI(
    title="OptiFlow API",
    description="Backend for print-shop scheduling, worker execution, bookings, and external work offers.",
    version="3.0.0",
)

# The Flutter app is used on web, Windows, and mobile. Keep CORS permissive for
# the university project; production should replace '*' with deployed origins.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """Log unexpected failures while returning a safe response to clients."""
    logger.exception("Unhandled backend error while serving %s", request.url.path)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error."},
    )


@app.get("/")
def health_check():
    """Simple deployment health check used by Render and developers."""
    return {"message": "OptiFlow API is online", "version": "3.0.0"}


# All application endpoints use one consistent /api prefix.
app.include_router(router, prefix="/api")
