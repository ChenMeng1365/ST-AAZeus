@echo off
rem ST-AAZeus - web chat console (browser UI on port 8890)
rem zero-dependency python server: web\webui.py serves the page and proxies /api/chat
rem the web console can also start/stop model services itself (see page header)
start "" http://127.0.0.1:8890/
python "%~dp0web\webui.py"
