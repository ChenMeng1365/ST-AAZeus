@echo off
rem ST-AAZeus - chat with the running model from cmd
rem usage: chat-zeus.cmd                    interactive multi-turn chat
rem        chat-zeus.cmd "your question"    one-shot Q&A
rem        chat-zeus.cmd -NoThink "..."     disable thinking mode
rem        chat-zeus.cmd -Port 8802         service on another port
rem input/output uses UTF-8 (chcp 65001) so Chinese works in one-shot args
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\chat.ps1" %*
