#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ST-AAZeus API 调用示例 — 零依赖（仅标准库 urllib）

演示 OpenAI 兼容接口的三种用法，可作业务集成的参考模板:

  1. 单发问答（非流式）      python examples\\chat_api.py "你好，介绍下你自己"
  2. 多轮对话（非流式）      python examples\\chat_api.py --multi
  3. 流式输出（SSE）         python examples\\chat_api.py --stream "讲个长一点的笑话"

选项:
  --base URL       服务地址，默认自动解析 WSL IP（http://<wsl-ip>:8801）
  --no-think       关闭思考模式（更快出正文）
  --max-tokens N   生成的最大 token 数（默认 1024）

Windows 注意: 本机 127.0.0.1 → WSL 的转发可能被系统代理劫持，
脚本默认通过 `wsl -e hostname -I` 解析 WSL IP 直连；如服务跑在本机，--base http://127.0.0.1:8801。
"""
import argparse
import json
import subprocess
import sys
import urllib.request


def resolve_base(explicit: str, port: int) -> str:
    if explicit:
        return explicit
    ip = "127.0.0.1"
    if sys.platform == "win32":
        try:
            out = subprocess.run(["wsl", "-e", "hostname", "-I"], capture_output=True,
                                 timeout=10, encoding="utf-8", errors="replace").stdout.strip()
            ip = out.split()[0] if out else "127.0.0.1"
        except Exception:
            pass
    return f"http://{ip}:{port}"


def chat(base, messages, stream=False, no_think=False, max_tokens=1024):
    """调用 /v1/chat/completions。stream=True 时逐行打印 SSE 增量。"""
    payload = {
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": 1.0,     # Spark-X2.5 官方推荐
        "top_p": 0.95,
        "stream": stream,
    }
    if no_think:
        payload["chat_template_kwargs"] = {"enable_thinking": False}

    req = urllib.request.Request(
        base + "/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # 绕过系统代理

    with opener.open(req, timeout=600) as resp:
        if not stream:
            data = json.loads(resp.read().decode("utf-8"))
            msg = data["choices"][0]["message"]
            if msg.get("reasoning_content"):
                print("--- 思考 ---")
                print(msg["reasoning_content"])
                print("--- 回答 ---")
            print(msg["content"])
            t = data.get("timings", {})
            if t.get("predicted_per_second"):
                print(f"\n[{t['predicted_per_second']:.0f} tok/s]", file=sys.stderr)
            return msg["content"]

        # SSE 流式:逐行读取 data: {...}，增量打印
        content, reasoning = "", ""
        buf = ""
        while True:
            chunk = resp.read(1024)
            if not chunk:
                break
            buf += chunk.decode("utf-8", errors="replace")
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                line = line.strip()
                if not line.startswith("data:"):
                    continue
                d = line[5:].strip()
                if d == "[DONE]":
                    print()
                    return content
                try:
                    delta = json.loads(d)["choices"][0].get("delta", {})
                except (KeyError, json.JSONDecodeError):
                    continue
                if delta.get("reasoning_content"):
                    reasoning += delta["reasoning_content"]
                    print(delta["reasoning_content"], end="", flush=True)
                if delta.get("content"):
                    if reasoning:
                        print("\n--- 回答 ---")
                        reasoning = ""
                    content += delta["content"]
                    print(delta["content"], end="", flush=True)


def main():
    ap = argparse.ArgumentParser(description="ST-AAZeus OpenAI 兼容接口示例")
    ap.add_argument("question", nargs="?", default="你好，请介绍一下你自己")
    ap.add_argument("--base", default="", help="服务地址（默认自动解析 WSL IP:8801）")
    ap.add_argument("--port", type=int, default=8801)
    ap.add_argument("--stream", action="store_true", help="流式输出")
    ap.add_argument("--multi", action="store_true", help="多轮对话演示")
    ap.add_argument("--no-think", action="store_true", help="关闭思考模式")
    ap.add_argument("--max-tokens", type=int, default=1024)
    args = ap.parse_args()

    base = resolve_base(args.base, args.port)
    print(f"[*] 服务地址: {base}", file=sys.stderr)

    try:
        with urllib.request.build_opener(
                urllib.request.ProxyHandler({})).open(base + "/health", timeout=3) as r:
            if json.loads(r.read()).get("status") != "ok":
                raise RuntimeError("health != ok")
    except Exception:
        sys.exit(f"[错误] 模型服务未运行（{base}）。先执行 start-zeus.cmd 启动。")

    if args.multi:
        history = []
        print("[*] 多轮对话演示（输入空行或 Ctrl+C 退出）")
        while True:
            try:
                q = input("你> ").strip()
            except (EOFError, KeyboardInterrupt):
                break
            if not q:
                break
            history.append({"role": "user", "content": q})
            print("AI> ", end="")
            a = chat(base, history, stream=True, no_think=args.no_think,
                     max_tokens=args.max_tokens)
            history.append({"role": "assistant", "content": a})
    else:
        chat(base, [{"role": "user", "content": args.question}],
             stream=args.stream, no_think=args.no_think, max_tokens=args.max_tokens)


if __name__ == "__main__":
    main()
