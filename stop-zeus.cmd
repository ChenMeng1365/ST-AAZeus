@echo off
rem ST-AAZeus - stop model service
rem usage: stop-zeus.cmd [model-id]
rem        no argument = stop ALL running model services
setlocal

set "MODEL=%~1"

for /f "usebackq delims=" %%i in (`wsl -e wslpath -a "%~dp0."`) do set "WSLROOT=%%i"

if "%MODEL%"=="" (
  wsl -e bash -c "found=0; for f in %WSLROOT%/.run/*.pid; do [ -e $f ] || continue; found=1; bash %WSLROOT%/scripts/stop.sh $(basename $f .pid); done; [ $found -eq 0 ] && echo no running service found"
) else (
  wsl -e bash -c "bash %WSLROOT%/scripts/stop.sh %MODEL%"
)
