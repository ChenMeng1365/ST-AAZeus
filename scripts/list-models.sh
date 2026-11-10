#!/bin/bash
# 列出所有已注册的模型
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"

echo "已注册模型（models/*/model.json）"
echo
printf "%-22s %-30s %-18s %10s  %-32s  %s\n" "MODEL-ID" "DISPLAY-NAME" "ENGINE" "SIZE" "VARIANTS（可选变体:大小）" "STATE"
echo "--------------------------------------------------------------------------------------------------------------------"

for meta in "$BASE"/models/*/model.json; do
    [ -f "$meta" ] || continue
    python3 - "$meta" "$BASE" <<'PY'
import json, os, sys
meta, base = sys.argv[1], sys.argv[2]
m = json.load(open(meta, encoding='utf-8'))
f = os.path.join(os.path.dirname(meta), m['file'])
if os.path.exists(f):
    size = f"{os.path.getsize(f)/2**30:.2f}G"
else:
    size = "缺失!"
variants = m.get('variants', {})
if variants:
    vparts = []
    for k, v in variants.items():
        vf = os.path.join(os.path.dirname(meta), v['file'])
        vs = f"{os.path.getsize(vf)/2**30:.2f}G" if os.path.exists(vf) else "缺失"
        vparts.append(f"{k}:{vs}")
    vinfo = ' '.join(vparts)
else:
    vinfo = '-'
pid = os.path.join(base, '.run', f"{m['id']}.pid")
if os.path.exists(pid):
    try:
        pid_v = int(open(pid).read().strip())
        os.kill(pid_v, 0)
        state = "running"
    except (ValueError, ProcessLookupError, PermissionError):
        state = "stale-pid"
else:
    state = "-"
print(f"{m['id']:<22} {m.get('display_name',''):<30} {m.get('engine',''):<18} {size:>10}  {vinfo:<32}  {state}")
PY
done
echo "--------------------------------------------------------------------------------------------------------------------"
echo "启动: scripts/start.sh <model-id> [port] [ctx] [-d]    停止: scripts/stop.sh <model-id>    测试: scripts/test.sh <model-id>"
echo "变体: VARIANT=<变体名> scripts/start.sh ...（变体名见上表 VARIANTS 列，缺省用默认 file）"
