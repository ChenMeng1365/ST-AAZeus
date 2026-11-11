# ST-AAZeus Web 控制台 — 静态页 + 对话转发 + 模型管家
# 零依赖：仅 Python 标准库（http.server + urllib + subprocess），Windows / WSL 均可运行
# 用法: python web\webui.py  (或仓库根 ui-zeus.cmd) → http://127.0.0.1:8890/
#
# 端点:
#   GET  /            控制台页面
#   GET  /api/models  已注册模型清单（扫描 models/*/model.json）
#   GET  /api/status  服务状态（运行中/启动中/停止 + 当前模型元信息）
#   POST /api/start   {model, variant} 后台拉起模型服务（先停现有）
#   POST /api/stop    停止所有运行中的模型服务
#   POST /api/chat    OpenAI /v1/chat/completions 流式透传（同源规避浏览器 CORS）
import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

LLAMA_PORT = int(os.environ.get("AAZEUS_LLAMA_PORT", "8801"))  # llama-server 端口（可用环境变量覆盖）
UI_PORT = int(os.environ.get("AAZEUS_UI_PORT", "8890"))        # Web 控制台端口（可用环境变量覆盖）
REPO = Path(__file__).resolve().parent.parent
IS_WIN = (os.name == "nt")
HTML = Path(__file__).resolve().parent / "index.html"


def wsl_root() -> str:
    r"""本仓库在 WSL 视角下的路径（E:\... → /mnt/e/...）"""
    p = str(REPO).replace("\\", "/")
    if len(p) > 1 and p[1] == ":":
        return "/mnt/" + p[0].lower() + p[2:]
    return "/mnt" + p


def run_bash(cmd: str, timeout: float = 120):
    """执行 bash 命令（Windows 经 wsl.exe，Linux 本机直执）。
    注: wsl.exe 的 stderr 会冒出 GBK 编码的代理警告，须 errors=replace 防 UTF-8 解码崩溃。"""
    argv = (["wsl", "-e", "bash", "-c", cmd] if IS_WIN else ["bash", "-c", cmd])
    return subprocess.run(argv, capture_output=True, timeout=timeout,
                          encoding="utf-8", errors="replace")


_llama_base = None


def llama_base() -> str:
    """llama-server 地址。WSL 部署时解析 WSL IP（本机 localhost 转发会被系统代理劫持）"""
    global _llama_base
    if _llama_base is None:
        ip = "127.0.0.1"
        if IS_WIN:
            try:
                # 注意: wsl.exe 的输出/警告含非 UTF-8 字节，中文 Locale 的 Python 默认
                # 用 GBK 解码会直接炸 reader 线程，必须显式 utf-8 + replace（与 run_bash 同理）
                out = subprocess.run(["wsl", "-e", "hostname", "-I"], capture_output=True,
                                     encoding="utf-8", errors="replace",
                                     timeout=10).stdout.strip()
                ip = out.split()[0] if out else "127.0.0.1"
            except Exception:
                pass
        _llama_base = f"http://{ip}:{LLAMA_PORT}"
    return _llama_base


# 与系统代理隔离：显式空代理，防止全局 HTTP_PROXY 劫持到 WSL 的直连
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))

STATE = {"gen": 0, "starting": None, "last_error": None}  # gen: 启停代计数，用于取消过期的启动线程


def llama_get(path: str, timeout: float = 4):
    with OPENER.open(llama_base() + path, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def list_models():
    out = []
    for mj in sorted((REPO / "models").glob("*/model.json")):
        try:
            m = json.loads(mj.read_text(encoding="utf-8"))
        except Exception:
            continue
        variants = []
        for name, v in (m.get("variants") or {}).items():
            vf = mj.parent / v.get("file", "")
            size = round(vf.stat().st_size / 2**30, 2) if vf.exists() else None
            variants.append({"name": name, "size_gb": size})
        # 默认变体 = model.json 的 file 字段对应的变体名
        default = None
        for name, v in (m.get("variants") or {}).items():
            if v.get("file") == m.get("file"):
                default = name
                break
        out.append({
            "id": m.get("id", mj.parent.name),
            "display_name": m.get("display_name", mj.parent.name),
            "default_variant": default,
            "variants": variants,
        })
    return out


def build_status() -> dict:
    resp = {"status": "stopped", "model_id": None, "model_file": None,
            "n_ctx": None, "n_params": None, "quant": None,
            "starting": STATE["starting"], "last_error": STATE["last_error"],
            "llama_base": llama_base()}
    try:
        if llama_get("/health").get("status") == "ok":
            try:
                models = llama_get("/v1/models", timeout=6)
                d = (models.get("data") or [{}])[0]
                mid = d.get("id", "")
                if "/models/" in mid:
                    resp["model_id"] = mid.split("/models/", 1)[1].split("/")[0]
                meta = d.get("meta") or {}
                resp["n_ctx"] = meta.get("n_ctx")
                resp["n_params"] = meta.get("n_params")
                resp["quant"] = meta.get("ftype")
                resp["model_file"] = mid.rsplit("/", 1)[-1]
            except Exception:
                pass
            resp["status"] = "running"
            STATE["starting"] = None
            return resp
    except Exception:
        pass
    if STATE["starting"]:
        resp["status"] = "starting"
        resp["model_id"] = STATE["starting"]
    return resp


def start_model(model: str, variant: str = "") -> str:
    """校验后启动后台线程：停现有 → 拉起 → 等健康。返回错误文本（空=已受理）。"""
    ids = [m["id"] for m in list_models()]
    if model not in ids:
        return f"未知模型 {model}，可选: {', '.join(ids)}"
    root = wsl_root()
    gen = STATE["gen"]

    def work():
        try:
            run_bash(f"for f in {root}/.run/*.pid; do [ -e $f ] || continue; "
                     f"bash {root}/scripts/stop.sh $(basename $f .pid); done")
            cmd = f"bash {root}/scripts/start.sh {model} {LLAMA_PORT} 4096 -d"
            if variant:
                cmd = f"VARIANT={variant} " + cmd
            r = run_bash(cmd, timeout=60)
            if gen != STATE["gen"]:
                return  # 已被新的启停请求取代
            if r.returncode != 0:
                STATE["starting"] = None
                STATE["last_error"] = ((r.stdout or "") + (r.stderr or "")).strip()[:800] or "start.sh 退出非零"
                return
            deadline = time.time() + 180
            while time.time() < deadline:
                if gen != STATE["gen"]:
                    return
                try:
                    if llama_get("/health").get("status") == "ok":
                        STATE["starting"] = None
                        return
                except Exception:
                    pass
                time.sleep(3)
            STATE["starting"] = None
            STATE["last_error"] = "服务 180 秒内未就绪，请查看 logs/ 下最新日志"
        except Exception as e:  # noqa: BLE001
            STATE["starting"] = None
            STATE["last_error"] = f"启动线程异常: {e}"

    STATE["starting"] = model
    STATE["last_error"] = None
    threading.Thread(target=work, daemon=True).start()
    return ""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("[web] %s\n" % (fmt % args))

    # ---- 基础收发 ----
    def _send(self, code: int, body, ctype: str):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False), "application/json; charset=utf-8")

    def _body(self) -> bytes:
        n = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(n) if n else b""

    # ---- GET ----
    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self._send(200, HTML.read_bytes(), "text/html; charset=utf-8")
        elif self.path == "/api/models":
            self._json(200, {"models": list_models()})
        elif self.path == "/api/status":
            self._json(200, build_status())
        else:
            self._send(404, "not found", "text/plain")

    # ---- POST ----
    def do_POST(self):
        if self.path == "/api/chat":
            self._do_chat()
        elif self.path == "/api/start":
            try:
                req = json.loads(self._body().decode("utf-8"))
            except Exception:
                self._json(400, {"error": "请求体不是合法 JSON"})
                return
            st = build_status()
            if st["status"] == "starting":
                self._json(409, {"error": f"正在启动 {st['starting']}，请稍候"})
                return
            err = start_model(req.get("model", ""), req.get("variant", "") or "")
            if err:
                self._json(400, {"error": err})
            else:
                self._json(200, {"ok": True})
        elif self.path == "/api/stop":
            STATE["gen"] += 1
            STATE["starting"] = None
            root = wsl_root()
            threading.Thread(target=lambda: run_bash(
                f"for f in {root}/.run/*.pid; do [ -e $f ] || continue; "
                f"bash {root}/scripts/stop.sh $(basename $f .pid); done"), daemon=True).start()
            self._json(200, {"ok": True})
        else:
            self._send(404, "not found", "text/plain")

    def _do_chat(self):
        body = self._body()
        try:
            req = urllib.request.Request(
                llama_base() + "/v1/chat/completions", data=body, method="POST",
                headers={"Content-Type": "application/json"})
            upstream = OPENER.open(req, timeout=600)
        except urllib.error.HTTPError as e:
            self._send(e.code, e.read(), "application/json; charset=utf-8")
        except Exception as e:  # noqa: BLE001
            self._json(502, {"error": f"模型服务不可达: {e}",
                             "hint": "模型未启动？在页面顶部选择模型并点击「启动」"})
            return
        ct = upstream.headers.get("Content-Type", "")
        if "event-stream" in ct:  # SSE 流式透传
            self.send_response(200)
            self.send_header("Content-Type", ct)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            try:
                while True:
                    chunk = upstream.read(1024)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
            except Exception:
                pass  # 客户端中断等
            finally:
                try:
                    upstream.close()
                except Exception:
                    pass
        else:  # 非流式响应整体透传
            data = upstream.read()
            self._send(upstream.status, data, ct or "application/json; charset=utf-8")


def main() -> None:
    srv = ThreadingHTTPServer(("127.0.0.1", UI_PORT), Handler)
    print(f"[web] ST-AAZeus 控制台: http://127.0.0.1:{UI_PORT}/  (Ctrl+C 停止)")
    print(f"[web] 模型服务地址: {llama_base()}（自动解析 WSL IP）")
    print(f"[web] /api/chat → {llama_base()}/v1/chat/completions （流式透传）")
    srv.serve_forever()


if __name__ == "__main__":
    main()
