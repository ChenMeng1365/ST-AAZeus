#!/bin/bash
# ST-AAZeus 停止后台运行的模型服务
# 用法: stop.sh <model-id>
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR="$BASE/.run"

MODEL_ID="${1:-}"
if [ -z "$MODEL_ID" ]; then
    echo "用法: $(basename "$0") <model-id>"
    echo "运行中的模型:"
    for p in "$RUN_DIR"/*.pid; do
        [ -f "$p" ] && echo "  - $(basename "$p" .pid)"
    done
    exit 1
fi

PID_FILE="$RUN_DIR/$MODEL_ID.pid"
if [ ! -f "$PID_FILE" ]; then
    echo "[提示] 没有找到 $MODEL_ID 的后台运行记录（可能以前台方式启动，Ctrl+C 即停）"
    exit 0
fi

PID="$(cat "$PID_FILE")"
if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    sleep 1
    kill -0 "$PID" 2>/dev/null && { kill -9 "$PID" 2>/dev/null || true; }
    echo "已停止 $MODEL_ID (PID $PID)"
else
    echo "[提示] PID $PID 已不在运行"
fi
rm -f "$PID_FILE"
