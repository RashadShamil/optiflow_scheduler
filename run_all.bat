@echo off
setlocal enabledelayedexpansion

set ROOT_DIR=%~dp0

echo ==========================================================
echo   Starting OptiFlow System (Backend + Desktop + Mobile)
echo ==========================================================
echo.
echo Launching services in separate terminal windows...
echo.

REM 1. Start Backend (FastAPI via Uvicorn)
echo [1/3] Starting Backend API on http://127.0.0.1:8000 ...
start "OptiFlow Backend (FastAPI)" cmd /k "cd /d %ROOT_DIR%optiflow_back && (if exist venv\Scripts\activate call venv\Scripts\activate) && python -m uvicorn main:app --reload --port 8000"

REM Short pause to give backend a head start
timeout /t 2 /nobreak >nul

REM 2. Start Frontend Windows App
echo [2/3] Starting Desktop App (Windows)...
start "OptiFlow Desktop (Windows)" cmd /k "cd /d %ROOT_DIR%optiflow_front && flutter run -d windows"

REM 3. Start Frontend Mobile App
echo [3/3] Starting Mobile App (Phone)...
start "OptiFlow Mobile" cmd /k "cd /d %ROOT_DIR%optiflow_front && flutter run"

echo.
echo ==========================================================
echo   All services launched!
echo   - Backend: Running in dedicated window
echo   - Desktop: Running in dedicated window
echo   - Mobile:  Running in dedicated window
echo ==========================================================
echo.
pause
