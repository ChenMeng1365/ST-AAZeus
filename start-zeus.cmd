@echo off
rem ST-AAZeus - start model service (wrapper to scripts/start.sh in WSL, waits until healthy)
rem usage: start-zeus.cmd [model-id] [port] [ctx] [variant]
rem        defaults: model=spark-x2.5-1.7b  port=8801  ctx=4096  variant=(model default q4_k_m)
rem examples:
rem   start-zeus.cmd                        (1.7B q4_k_m on 8801)
rem   start-zeus.cmd spark-x2.5-4b          (4B q4_k_m on 8801)
rem   start-zeus.cmd spark-x2.5-1.7b 8801 4096 fp16   (1.7B fp16 variant)
setlocal

set "MODEL=%~1"
if "%MODEL%"=="" set "MODEL=spark-x2.5-1.7b"
set "PORT=%~2"
if "%PORT%"=="" set "PORT=8801"
set "CTX=%~3"
if "%CTX%"=="" set "CTX=4096"
set "VARIANT=%~4"

for /f "usebackq delims=" %%i in (`wsl -e wslpath -a "%~dp0."`) do set "WSLROOT=%%i"

if not "%VARIANT%"=="" (
  wsl -e bash -c "VARIANT=%VARIANT% bash %WSLROOT%/scripts/start.sh %MODEL% %PORT% %CTX% -d"
) else (
  wsl -e bash -c "bash %WSLROOT%/scripts/start.sh %MODEL% %PORT% %CTX% -d"
)
if errorlevel 1 goto :fail

rem ---- wait until healthy (model load 20-60s) ----
echo Waiting for %MODEL% on port %PORT% ...
wsl -e bash -c "for i in $(seq 1 60); do curl -sf -m 3 http://127.0.0.1:%PORT%/health > /dev/null 2>&1 && exit 0; sleep 2; done; exit 1"
if errorlevel 1 goto :fail2

echo.
echo [OK] %MODEL% is ready.
echo   WSL    : http://127.0.0.1:%PORT%/v1/chat/completions
for /f "usebackq delims=" %%i in (`wsl -e hostname -I`) do for /f "tokens=1" %%j in ("%%i") do (
  echo   Windows: http://%%j:%PORT%/v1/chat/completions
)
echo   CLI chat: chat-zeus.cmd        Web UI: ui-zeus.cmd
goto :eof

:fail
echo [FAIL] start script returned an error (see messages above / logs\%MODEL%.log)
exit /b 1

:fail2
echo [FAIL] service did not become healthy in 120s, check logs\%MODEL%.log
wsl -e bash -c "tail -n 20 %WSLROOT%/logs/%MODEL%*.log 2>/dev/null"
exit /b 1
