@echo off
echo ========================================
echo   TES Idle - Server Manager
echo ========================================
echo.

echo [1/5] Checking for running processes...

REM Kill existing processes
taskkill /F /FI "WINDOWTITLE eq *TES Backend*" >nul 2>&1
taskkill /F /FI "WINDOWTITLE eq *TES Elixir*" >nul 2>&1
taskkill /F /FI "WINDOWTITLE eq *TES Frontend*" >nul 2>&1
timeout /t 1 /nobreak >nul

echo [2/5] Starting Elixir backend (port 4000)...
start "TES Elixir" cmd /c "cd /d C:\Projects\tes-godv\tes_idle_elixir && mix phx.server"
timeout /t 5 /nobreak >nul

echo [3/5] Starting frontend (port 5173)...
start "TES Frontend" cmd /c "cd /d C:\Projects\tes-godv\frontend && npm run dev"
timeout /t 2 /nobreak >nul

echo.
echo ========================================
echo   Servers started!
echo ========================================
echo   Elixir Backend: http://localhost:4000
echo   Frontend:       http://localhost:5173
echo   API:            http://localhost:4000/api/v1
echo ========================================
echo.
echo Press any key to close this window...
pause >nul