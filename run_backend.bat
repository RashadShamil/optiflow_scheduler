@echo off
cd /d "%~dp0optiflow_back"
echo Starting OptiFlow FastAPI backend on http://127.0.0.1:8000 ...
python -m uvicorn main:app --reload --port 8000
pause
