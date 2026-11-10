#!/bin/bash
# 冒烟测试: 拉起模型服务 -> 等待健康检查 -> 基础对话测试 -> 自动关闭
# 用法: test.sh <model-id> [port]
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$BASE/scripts"

MODEL_ID="${1:-}"
PORT="${2:-8801}"
[ -n "$MODEL_ID" ] || { echo "用法: $(basename "$0") <model-id> [port]"; bash "$SCRIPTS/list-models.sh"; exit 1; }

# 启动（后台模式，结束自动清理）
bash "$SCRIPTS/start.sh" "$MODEL_ID" "$PORT" "" -d
cleanup() { bash "$SCRIPTS/stop.sh" "$MODEL_ID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "等待服务就绪..."
READY=0
for i in $(seq 1 60); do
    if curl -sf "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q "ok"; then
        READY=1
        echo "服务就绪 (${i} 次探测)"
        break
    fi
    sleep 2
done
if [ "$READY" != "1" ]; then
    echo "[失败] 服务 120 秒内未就绪，最近日志："
    tail -n 20 "$BASE/logs/$MODEL_ID${VARIANT:+-$VARIANT}.log" 2>/dev/null || true
    exit 1
fi

echo
echo "=== Test 1: 中文对话 ==="
curl -s http://127.0.0.1:$PORT/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"你好，请用一句话介绍你自己"}],"max_tokens":200,"temperature":1.0,"top_p":0.95}'
echo
echo
echo "=== Test 2: 英文对话（关闭 thinking）==="
curl -s http://127.0.0.1:$PORT/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Introduce yourself in one sentence."}],"max_tokens":200,"temperature":1.0,"top_p":0.95,"chat_template_kwargs":{"enable_thinking":false}}'
echo
echo
echo "=== 测试完成，正在关闭服务 ==="
