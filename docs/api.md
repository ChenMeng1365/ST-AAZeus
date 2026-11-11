# ST-AAZeus 接口文档 — 命令行 / Web / API 交互指南

> 模型服务由 llama-server 提供 **OpenAI 兼容 API**（`/v1/chat/completions`），任何 OpenAI 客户端/SDK 可直接对接。
> 本文给全三种交互通道的用法与网络注意事项。服务拉起见 [spark-x2.5-deploy.md](spark-x2.5-deploy.md) 与根目录 `start-zeus.cmd`。

## 0. 前置：拉起模型

```bat
:: Windows（推荐入口）: 定位仓库 → 拉起 → 健康等待 → 打印访问地址
start-zeus.cmd                      :: 默认 spark-x2.5-1.7b (q4_k_m), 端口 8801
start-zeus.cmd spark-x2.5-4b        :: 4B 版本（Agent/工具调用优先选它）
start-zeus.cmd spark-x2.5-1.7b 8801 4096 fp16   :: 指定变体
stop-zeus.cmd [model-id]            :: 停止（无参数=停全部）

:: WSL 内等价
bash scripts/start.sh spark-x2.5-1.7b -d
bash scripts/stop.sh spark-x2.5-1.7b
```

加载约 20~60 秒（日志在 `logs/<model-id>[-variant].log`）。

## 1. 网络要点（Windows 侧必读）

llama-server 在 WSL 内监听 `0.0.0.0:8801`：

| 访问位置 | 地址 | 说明 |
|---|---|---|
| WSL 内 | `http://127.0.0.1:8801` | 直接可用 |
| **Windows 侧** | `http://<WSL-IP>:8801` | **本机 localhost 转发被系统代理劫持时 127.0.0.1 不可达，须用 WSL IP** |

获取 WSL IP：`wsl -e hostname -I`（每次启动会变化）。本项目所有 Windows 侧组件（chat-zeus、webui、examples）已内置自动解析，无需手动。

## 2. 通道一：命令行对话（chat-zeus.cmd）

```bat
chat-zeus.cmd                       :: 交互式多轮对话（/exit 退出）
chat-zeus.cmd "帮我写一条周报摘要"    :: 单发直问直答
chat-zeus.cmd -NoThink "你好"       :: 关闭思考模式（出正文更快）
chat-zeus.cmd -Port 8802            :: 连接其它端口的服务
```

交互命令：`/think 开|关`（切换思考模式）、`/clear`（清空上下文）、`/system <设定>`（注入系统提示）、`/exit`。
未启动服务时会提示先运行 `start-zeus.cmd`。

## 3. 通道二：Web 对话台（ui-zeus.cmd）

```bat
ui-zeus.cmd                         :: 打开 http://127.0.0.1:8890/
```

- 零依赖（Python 标准库），页面可：选择模型/变体 → **页面内启动/停止服务** → 流式对话（思考过程折叠显示）→ 思考模式开关
- `web/webui.py` 通过 `/api/*` 端点工作（同源转发规避 CORS），本身也可当 API 网关用（见第 4 节）

## 4. 通道三：API 直连（OpenAI 兼容）

### 4.1 端点

| 端点 | 方法 | 说明 |
|---|---|---|
| `/v1/chat/completions` | POST | 对话补全，支持 `stream: true`（SSE） |
| `/v1/models` | GET | 当前模型（含 `meta`: 参数量/量化/上下文） |
| `/health` | GET | `{"status":"ok"}` |
| `/props` | GET | 默认生成参数、模板能力等 |

### 4.2 请求要点（Spark-X2.5）

- **推荐参数**：`temperature: 1.0`, `top_p: 0.95`（官方口径）
- **思考模式**：默认开启，推理过程在 `message.reasoning_content`（流式为 `delta.reasoning_content`）；关闭：请求体加 `"chat_template_kwargs": {"enable_thinking": false}`
- `model` 字段可任意填
- 短对话建议 `max_tokens` 1024 起（thinking 会先消耗 token）

### 4.3 curl 示例

```bash
# WSL 内（BASE=http://127.0.0.1:8801）
# Windows cmd：先 set BASE=http://<WSL-IP>:8801（wsl -e hostname -I 获取）

# 单发（关思考，最快）
curl -s %BASE%/v1/chat/completions -H "Content-Type: application/json" -d "{\"messages\":[{\"role\":\"user\",\"content\":\"一句话介绍你自己\"}],\"max_tokens\":300,\"chat_template_kwargs\":{\"enable_thinking\":false}}"

# 流式
curl -N -s %BASE%/v1/chat/completions -H "Content-Type: application/json" -d "{\"messages\":[{\"role\":\"user\",\"content\":\"写一首关于海洋的诗\"}],\"max_tokens\":500,\"stream\":true}"
```

### 4.4 Python（零依赖示例，见 examples/chat_api.py）

```bash
python examples\chat_api.py "一句话介绍你自己"            # 单发（含思考过程展示）
python examples\chat_api.py --stream "讲个长笑话"         # 流式
python examples\chat_api.py --multi                      # 多轮对话
python examples\chat_api.py --no-think "你好"             # 关闭思考
```

### 4.5 OpenAI SDK（pip install openai）

```python
from openai import OpenAI
import subprocess
ip = subprocess.run(["wsl", "-e", "hostname", "-I"], capture_output=True, text=True).stdout.split()[0]
client = OpenAI(base_url=f"http://{ip}:8801/v1", api_key="none")
resp = client.chat.completions.create(
    model="spark", messages=[{"role": "user", "content": "你好"}],
    max_tokens=300, temperature=1.0, top_p=0.95,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}})
print(resp.choices[0].message.content)
```

### 4.6 经 WebUI 网关（同源免 CORS，浏览器/本机应用可直接用）

Web 控制台运行时（`ui-zeus.cmd`）暴露：

- `POST http://127.0.0.1:8890/api/chat` — 同 4.3 请求体（推荐 `stream: true`），SSE 流式转发
- `GET  http://127.0.0.1:8890/api/status` — 模型服务状态
- `GET  http://127.0.0.1:8890/api/models` — 可选模型清单
- `POST http://127.0.0.1:8890/api/start|/api/stop` — 网页化模型管家

## 5. 错误速查

| 症状 | 原因/处置 |
|---|---|
| Windows 侧 127.0.0.1:8801 连不上 | 系统代理劫持 localhost；用 WSL IP（本文组件已自动处理） |
| `chat-zeus` 提示服务未运行 | 先 `start-zeus.cmd` |
| Web 页发送后 502 | 模型未启动（顶部点「启动」） |
| 生成很慢 | ① fp16/4B 变体本身较慢（AC 电源 1.7B q4 ≈131、4B q4 ≈66、1.7B fp16 ≈60 tok/s）；② **电池模式**下 NVIDIA 把 GPU 钳在低频（实测可低至 210MHz/7 tok/s），插电即恢复；③ 显存被其它进程占用导致层回退 CPU |
| 启动失败且日志文件为空（0 字节） | WSL GPU 虚拟化层瞬时故障（dmesg 可见 `dxg: dxgkio_query_adapter_info: Ioctl failed: -22`），CUDA 进程启动即崩；**重新执行 start-zeus.cmd 即可**，与本仓库脚本无关 |
| 思考很长后才出正文 | thinking 模式特性；用 `-NoThink` 或页内关闭「思考模式」 |
