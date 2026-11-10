#!/bin/bash
# ST-AAZeus 本地模型服务启动脚本
# 用法: start.sh <model-id> [port] [ctx] [-d]
#   port  默认 8801；ctx 缺省用模型 model.json 的 ctx_default
#   -d    后台运行（PID 写入 .run/<model-id>.pid，日志写入 logs/<model-id>.log）
# 变体选择（可选）: VARIANT=fp16 start.sh ... ，默认用 model.json 的 file 字段
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DIR="$BASE/.run"

usage() {
    echo "用法: $(basename "$0") <model-id> [port] [ctx] [-d]"
    echo "可用模型（详见 list-models.sh）:"
    for d in "$BASE"/models/*/; do
        [ -f "$d/model.json" ] && echo "  - $(basename "$d")"
    done
    exit 1
}

MODEL_ID="${1:-}"
[ -n "$MODEL_ID" ] || usage

META="$BASE/models/$MODEL_ID/model.json"
if [ ! -f "$META" ]; then
    echo "[错误] 模型不存在: models/$MODEL_ID（缺少 model.json）"
    exit 1
fi

PORT="${2:-8801}"
CTX_ARG="${3:-}"
DETACH=0
[ "${4:-}" = "-d" ] && DETACH=1

# 从 model.json 提取启动配置（json.dumps 输出合法 shell 字面量，防注入）
# VARIANT 环境变量可选模型变体（见 model.json 的 variants 字段）
eval "$(python3 - "$META" "$CTX_ARG" <<'PY'
import json, os, sys
m = json.load(open(sys.argv[1], encoding='utf-8'))
ctx = int(sys.argv[2]) if sys.argv[2] else m.get('ctx_default', 4096)
variant = os.environ.get('VARIANT', '')
vmap = m.get('variants', {})
def emit(k, v):
    # 空列表须输出 ()（bash 空数组），json.dumps([]) 的 "[]" 会被当成字符串
    if isinstance(v, list) and not v:
        print(f'{k}=()')
    else:
        print(f'{k}={json.dumps(v)}')
if variant and variant not in vmap:
    emit('M_FILE', '')
    print(f"[错误] 模型 {m['id']} 无变体 {variant}，可选: {', '.join(vmap) or '（未定义 variants）'}", file=sys.stderr)
else:
    emit('M_FILE', vmap[variant]['file'] if variant else m['file'])
emit('M_ENGINE', m['engine'])
emit('M_CTX', ctx)
emit('M_NGL', m.get('ngl', 99))
emit('M_THREADS', m.get('threads', 8))
emit('M_TEMP', m.get('temp', 1.0))
emit('M_TOPP', m.get('top_p', 0.95))
emit('M_EXTRA', m.get('extra_args', []))
PY
)"

if [ -z "${M_FILE:-}" ]; then
    exit 1
fi

ENGINE_BIN="$BASE/engines/$M_ENGINE/bin/llama-server"
if [ ! -e "$ENGINE_BIN" ]; then
    echo "[错误] 引擎不存在: engines/$M_ENGINE（见 engines/$M_ENGINE/ENGINE.md）"
    exit 1
fi

MODEL_PATH="$BASE/models/$MODEL_ID/$M_FILE"
if [ ! -f "$MODEL_PATH" ]; then
    echo "[错误] 权重文件缺失: $MODEL_PATH"
    exit 1
fi

export LD_LIBRARY_PATH="$BASE/engines/$M_ENGINE/bin:${LD_LIBRARY_PATH:-}"

echo "启动 llama-server"
echo "  模型:   $MODEL_ID ($M_FILE)${VARIANT:+  [变体: $VARIANT]}"
echo "  引擎:   $M_ENGINE"
echo "  端口:   $PORT"
echo "  上下文: $M_CTX"
echo "  API:    http://127.0.0.1:$PORT/v1/chat/completions"

if [ "$DETACH" = "1" ]; then
    mkdir -p "$RUN_DIR" "$BASE/logs"
    nohup "$ENGINE_BIN" -m "$MODEL_PATH" \
        --host 0.0.0.0 --port "$PORT" \
        -ngl "$M_NGL" -c "$M_CTX" \
        --temp "$M_TEMP" --top-p "$M_TOPP" \
        -t "$M_THREADS" ${M_EXTRA[@]+"${M_EXTRA[@]}"} \
        > "$BASE/logs/$MODEL_ID${VARIANT:+-$VARIANT}.log" 2>&1 &
    echo $! > "$RUN_DIR/$MODEL_ID.pid"
    echo "  后台 PID: $(cat "$RUN_DIR/$MODEL_ID.pid")  日志: logs/$MODEL_ID${VARIANT:+-$VARIANT}.log"
    echo "  停止: stop.sh $MODEL_ID"
else
    exec "$ENGINE_BIN" -m "$MODEL_PATH" \
        --host 0.0.0.0 --port "$PORT" \
        -ngl "$M_NGL" -c "$M_CTX" \
        --temp "$M_TEMP" --top-p "$M_TOPP" \
        -t "$M_THREADS" ${M_EXTRA[@]+"${M_EXTRA[@]}"}
fi
