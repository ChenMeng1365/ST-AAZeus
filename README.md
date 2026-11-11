# ST-AAZeus — 本地多模型推理服务

本地大模型部署与调用服务仓库：模型可插拔，通过 llama-server 提供 **OpenAI 兼容 API**（`/v1/chat/completions`），任何 OpenAI 客户端/SDK 可直接对接。

## 快速开始（交互四通道）

```bat
start-zeus.cmd                        :: ① 拉起模型（默认 1.7B，等就绪后打印访问地址）
chat-zeus.cmd "你好"                 :: ② 命令行单发直问直答
chat-zeus.cmd                         ::    或交互式多轮对话（/exit 退出）
ui-zeus.cmd                           :: ③ Web 对话台 http://127.0.0.1:8890/（页内可选模型/变体启停）
curl http://<WSL-IP>:8801/v1/chat/completions ...   :: ④ API 直连（OpenAI 兼容）
```

| 通道 | 入口 | 适用 |
|---|---|---|
| ① 服务拉起 | `start-zeus.cmd [model] [port] [ctx] [variant]` / `stop-zeus.cmd` | 一键启停，自动健康等待 |
| ② 命令行 | `chat-zeus.cmd ["问题"] [-NoThink] [-Port N]` | 免浏览器快问快答 / 集成进批处理 |
| ③ Web 对话台 | `ui-zeus.cmd`（零依赖 Python） | 页内选模型/变体、启停服务、流式对话 |
| ④ API 直连 | `POST /v1/chat/completions` + `/v1/models` `/health` `/props` | 任何 OpenAI 客户端/SDK/agent 接入 |

详细用法、请求参数、SSE 流式、错误速查见 **[docs/api.md](docs/api.md)**；可运行示例见 `examples/chat_api.py`。

## 目录结构

```
ST-AAZeus/
├── README.md                 # 本文档
├── LICENSE                   # Apache-2.0
├── start-zeus.cmd            # 一键拉起：启服务+健康等待+打印访问地址
├── stop-zeus.cmd             # 停止（无参数=停全部）
├── chat-zeus.cmd             # 命令行对话入口（→ scripts/chat.ps1）
├── ui-zeus.cmd               # Web 对话台入口（→ web/webui.py）
├── models/                   # 模型仓库：每个模型一个自包含目录
│   ├── spark-x2.5-1.7b/
│   │   ├── model.json        #   模型自描述元数据（唯一事实源）
│   │   ├── *.gguf            #   部署权重（q4_k_m 默认 + fp16 变体；.gitignore 忽略）
│   │   └── hf/               #   HF 源格式：safetensors + 分词器 + modeling_spark.py（微调/转 GGUF 原料）
│   └── spark-x2.5-4b/        #   （同构）
├── engines/                  # 推理引擎：每个引擎一个自包含目录
│   └── llama-cpp-spark/
│       ├── ENGINE.md         #   引擎来源、编译环境、重新编译方法
│       ├── bin/              #   编译产物（.gitignore 忽略，不入库）
│       └── src-archive/      #   版本锁定源码包（35MB，随仓库分发——入库例外）
├── scripts/                  # 服务脚本（WSL bash 为主）
│   ├── start.sh / stop.sh    # 启停（model.json 驱动，支持 VARIANT 变体、后台模式；被 start-zeus.cmd 调用）
│   ├── list-models.sh        # 列出全部已注册模型/变体/运行状态
│   ├── test.sh               # 冒烟测试（拉起→健康检查→对话→自动关闭）
│   └── chat.ps1              # 命令行对话实现（PowerShell 5.1，UTF-8 BOM；被 chat-zeus.cmd 调用）
├── web/                      # Web 对话台（Python 标准库零依赖）
│   ├── webui.py              #   静态页 + /api/chat SSE 流式转发 + 模型启停管家
│   └── index.html            #   对话页（流式渲染、思考过程折叠、页内启停）
├── examples/
│   └── chat_api.py           # OpenAI 兼容 API 调用示例（单发/多轮/流式，零依赖）
├── docs/
│   ├── spark-x2.5-deploy.md  # 不入库文件清单 + 重建指南（含字节数校验表）
│   └── api.md                # 交互全指南：启停/CLI/Web/API + 错误速查
├── logs/                     # 后台模式日志（运行时生成，不入库）
└── .run/                     # PID 文件（运行时生成，不入库）
```

## WSL 内启动（等价方式）

引擎二进制为 **WSL/Linux 编译产物**（含 CUDA 支持）。Windows 侧统一走根目录 `start-zeus.cmd` 等入口（内部自动转入 WSL 执行）；已在 WSL 会话内时也可直接：

```bash
cd /mnt/e/workspace/numeron/ST-AAZeus
bash scripts/start.sh spark-x2.5-1.7b          # 前台运行，Ctrl+C 停止（默认 q4_k_m）
bash scripts/start.sh spark-x2.5-1.7b 8801 4096 -d   # 后台运行
VARIANT=fp16 bash scripts/start.sh spark-x2.5-1.7b 8802 -d   # 指定变体，可另开端口并行跑
bash scripts/stop.sh  spark-x2.5-1.7b          # 停止后台服务
bash scripts/list-models.sh                    # 查看已注册模型/变体/状态
bash scripts/test.sh   spark-x2.5-1.7b         # 冒烟测试（VARIANT=fp16 同样适用）
```

## API 调用

服务启动后即暴露 OpenAI 兼容接口（详解见 [docs/api.md](docs/api.md)）：

```bash
curl http://127.0.0.1:8801/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"你好，介绍一下你自己"}],"max_tokens":200}'
```

参数按模型 `model.json` 中记录的官方推荐值（temp/top_p）默认生效；`model` 字段可任意填。

## 更换 / 添加模型（3 步）

1. **放权重**：新建 `models/<new-model-id>/`，放入 GGUF 文件；
2. **写元数据**：复制 `models/spark-x2.5-1.7b/model.json` 改字段——`file`（权重文件名）、`engine`（所用引擎目录名）、`ctx_default`/`ngl`/`temp`/`top_p`/`extra_args`（推理参数）、`source_url`/`license`（溯源信息）；
3. **确认引擎**：标准架构模型（Qwen、Llama、GLM 等）直接用现有 `llama-cpp-spark` 引擎（其基于 upstream fork，兼容标准 GGUF）；全新自定义架构需在 `engines/<new-engine>/` 放编译产物并写 `ENGINE.md`，注意用 `cp -a` 保留符号链接。

完成后 `bash scripts/list-models.sh` 应显示新模型，`test.sh <new-model-id>` 验证通过即接入完成。**脚本零改动**——模型参数全部由各模型自己的 `model.json` 驱动。

## 当前模型

| model-id | 模型 | 默认 | 可选变体 | 引擎 | 实测（RTX 4060 8GB，q4_k_m 全 GPU） |
|----------|------|------|----------|------|----------------------|
| spark-x2.5-1.7b | Spark-X2.5-1.7B（科大讯飞·词元星火） | q4_k_m (1.03G) | fp16 (3.19G) | llama-cpp-spark | q4_k_m ≈131 tok/s；fp16 ≈60 tok/s |
| spark-x2.5-4b | Spark-X2.5-4B（科大讯飞·词元星火） | q4_k_m (2.42G) | fp16 (7.66G) | llama-cpp-spark | q4_k_m ≈66 tok/s |

- **选型**：日常对话/翻译用 1.7B（最快）；Agent 工具调用用 4B（function call 正确触发，1.7B 只识别不触发），66 tok/s 交互无压力
- 两模型均原生 1M 上下文，Apache-2.0，来源 ModelScope（`XHToken/Spark-X2.5-{1.7B,4B}`）
- thinking 模式默认开启（推理过程在 `reasoning_content` 字段，短回复场景会先消耗大量 token），API 请求传 `"chat_template_kwargs": {"enable_thinking": false}` 可关闭
- 4B fp16（7.66G）超出 8GB 显存全卸载能力，仅适合部分卸载/CPU 混合，本机默认用 q4_k_m
- 历史勘误：sspark-x25 原记录 4B 为 3.4 tok/s，系当时 CPU 回退异常，ST-AAZeus 复测为 66 tok/s（全 GPU）
- 引擎 fork 不接受显式 `--jinja` 参数（jinja 模板引擎默认已启用，模板内嵌 GGUF 自动生效），故 `model.json` 的 `extra_args` 为空

### 模型形态与转换链路

每个模型目录内含三种形态，分别对应不同用途，可从左到右逐级生成：

```
hf/（safetensors，HF 格式）──convert_hf_to_gguf──▶ fp16 GGUF ──llama-quantize──▶ q4_k_m GGUF
   │                                                │                            │
   微调原料（transformers + LoRA/QLoRA，            量化原料（出 q8_0/q5_k_m 等）   部署版（llama-server 直接加载）
   含 modeling_spark.py，Spark 自定义架构必需）
```

- 微调后：用 hf/ 新权重重新走转换链路，登记为新变体即可部署
- 纯部署场景可不关注 hf/，GGUF 自包含分词器与对话模板

### 再量化（从 fp16 变体生成新精度）

fp16 变体兼作量化原料，需要 q8_0 / q5_k_m 等精度时直接从它出，无需重新下载：

```bash
# WSL 内，输出到当前模型目录后，在 model.json 的 variants 里登记新变体即可
export LD_LIBRARY_PATH=/mnt/e/workspace/numeron/ST-AAZeus/engines/llama-cpp-spark/bin
/mnt/e/workspace/numeron/ST-AAZeus/engines/llama-cpp-spark/bin/llama-quantize \
    /mnt/e/workspace/numeron/ST-AAZeus/models/spark-x2.5-1.7b/Spark-X2.5-1.7B-fp16.gguf \
    /mnt/e/workspace/numeron/ST-AAZeus/models/spark-x2.5-1.7b/Spark-X2.5-1.7B-q8_0.gguf q8_0
```

## 设计约定

- **模型自描述**：`models/<id>/model.json` 是模型配置的唯一事实源，无中心注册表，加模型不改任何脚本；
- **引擎可插拔**：`engines/<id>/bin/` 自包含，`model.json` 的 `engine` 字段声明依赖，`LD_LIBRARY_PATH` 由启动脚本自动装配；
- **交互四通道共享同一后端**：CLI（PowerShell）、Web（零依赖 Python）、API（OpenAI 兼容）都落在 llama-server 的 `/v1/chat/completions`，自动解析 WSL IP 规避 localhost 代理劫持；
- **大文件不入库**：权重与编译产物被 `.gitignore` 忽略，仓库只保存结构、脚本与元数据；**新环境重建按 [docs/spark-x2.5-deploy.md](docs/spark-x2.5-deploy.md) 执行**（含精确字节数校验表），每个模型一份部署文档；
- **默认端口 8801（服务）/ 8890（Web 控制台）**：同时跑多模型时用不同端口启动（`start.sh <id> <port>`）。
