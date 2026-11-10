@echo off
rem ST-AAZeus stop background model service (Windows wrapper -^> WSL)
rem Usage: stop.bat [model-id]
setlocal

set "MODEL_ID=%~1"
if "%MODEL_ID%"=="" set "MODEL_ID=spark-x2.5-1.7b"

for /f "usebackq delims=" %%i in (`wsl -e wslpath -a "%~dp0."`) do set "WSL_SCRIPTS=%%i"
wsl -e bash -lc "%WSL_SCRIPTS%/scripts/stop.sh %MODEL_ID%"

endlocal
