@echo off
cd /d "%~dp0optiflow_front"
echo Starting OptiFlow Desktop App with .env configuration...
flutter run -d windows --dart-define-from-file=.env
pause
