@echo off
rem ST-AAZeus local model service launcher (Windows wrapper -^> WSL)
rem Usage: start.bat [model-id] [port] [ctx] [-d]
rem   default model: spark-x2.5-1.7b, port 8801
setlocal

set "MODEL_ID=%~1"
if "%MODEL_ID%"=="" set "MODEL_ID=spark-x2.5-1.7b"
set "PORT=%~2"
if "%PORT%"=="" set "PORT=8801"
set "CTX=%~3"

for /f "usebackq delims=" %%i in (`wsl -e wslpath -a "%~dp0."`) do set "WSL_SCRIPTS=%%i"
wsl -e bash -lc "%WSL_SCRIPTS%/scripts/start.sh %MODEL_ID% %PORT% %CTX% -d"

endlocal
