@echo off
:: Navigate to the repository directory (optional if file is in root)
cd /d "%~dp0"

:: Check status
git status

:: Add all changes
git add .

:: Commit with a dynamic timestamp
set "msg=Routine update: %date% %time%"
git commit -m "%msg%"

:: Push to remote
:: Replace 'main' with your specific branch name if different
git push origin main

pause