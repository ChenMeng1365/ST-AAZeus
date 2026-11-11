# Spark-X2.5 部署文档（不入库文件清单与重建指南）

> 本仓库设计原则：**代码、脚本、配置元数据入库；大文件（模型权重、引擎二进制）不入库**（见 `.gitignore`）。
> 本文档列出 Spark-X2.5 双模型（`spark-x2.5-1.7b` / `spark-x2.5-4b`）全部不入库文件及其**精确字节数**，
> 用于新环境重建：克隆仓库后按本文档逐一下载/生成即可完整复原。
>
> 小文件（`model.json`、`hf/` 下的 config/分词器/模型代码）**已在 git 内**，克隆即有，无需单独获取。

## 1. 不入库文件总览

| 类别 | 路径模式 | 获取方式 |
|------|----------|----------|
| HF 源权重分片 | `models/*/hf/model-*.safetensors` | **从 ModelScope 下载**（第 3 节） |
| fp16 GGUF（量化原料） | `models/*/Spark-X2.5-*-fp16.gguf` | 从 hf/ **转换生成**（第 4.2 节） |
| q4_k_m GGUF（部署版） | `models/*/Spark-X2.5-*-q4_k_m.gguf` | 从 fp16 **量化生成**（第 4.3 节） |
| 推理引擎二进制 | `engines/llama-cpp-spark/bin/*`（31 个文件，约 537MB） | 从源码**编译**（第 5 节，详见 engines/llama-cpp-spark/ENGINE.md） |

**入库例外**：`engines/llama-cpp-spark/src-archive/llama-cpp-spark-full.tar.gz`（35MB）随仓库分发、克隆即得——它是工具链版本锁定（commit `4a3635c`）的唯一载体，不入库则重建时无法保证与校验表同源。

## 2. 模型元信息

| 项 | spark-x2.5-1.7b | spark-x2.5-4b |
|----|-----------------|---------------|
| ModelScope 仓库 | `XHToken/Spark-X2.5-1.7B` | `XHToken/Spark-X2.5-4B` |
| 许可 | Apache-2.0 | Apache-2.0 |
| 架构 | 28 层 hidden 2048，8 头注意力（2 KV 头） | 36 层 hidden 2560，10 头注意力（2 KV 头） |
| 实测速度（RTX 4060 8GB，q4_k_m 全 GPU） | ~131 tok/s | ~66 tok/s |
| 引擎 | llama-cpp-spark | llama-cpp-spark |

## 3. 下载 HF 源权重（safetensors 分片）

国内可达，用 ModelScope API 逐文件下载（在仓库根目录执行）：

```bash
# --- spark-x2.5-1.7b ---
curl -sL -o models/spark-x2.5-1.7b/hf/model-00001-of-00002.safetensors "https://modelscope.cn/api/v1/models/XHToken/Spark-X2.5-1.7B/repo?Revision=master&FilePath=model-00001-of-00002.safetensors"
curl -sL -o models/spark-x2.5-1.7b/hf/model-00002-of-00002.safetensors "https://modelscope.cn/api/v1/models/XHToken/Spark-X2.5-1.7B/repo?Revision=master&FilePath=model-00002-of-00002.safetensors"

# --- spark-x2.5-4b ---
curl -sL -o models/spark-x2.5-4b/hf/model-00001-of-00005.safetensors "https://modelscope.cn/api/v1/models/XHToken/Spark-X2.5-4B/repo?Revision=master&FilePath=model-00001-of-00005.safetensors"
curl -sL -o models/spark-x2.5-4b/hf/model-00002-of-00005.safetensors "https://modelscope.cn/api/v1/models/XHToken/Spark-X2.5-4B/repo?Revision=master&FilePath=model-00002-of-00005.safetensors"
curl -sL -o models/spark-x2.5-4b/hf/model-00003-of-00005.safetensors "https://modelscope.cn/api/v1/models/XHToken/Spark-X2.5-4B/repo?Revision=master&FilePath=model-00003-of-00005.safetensors"
curl -sL -o models/spark-x2.5-4b/hf/model-00004-of-00005.safetensors "https://modelscope.cn/api/v1/models/XHToken/Spark-X2.5-4B/repo?Revision=master&FilePath=model-00004-of-00005.safetensors"
curl -sL -o models/spark-x2.5-4b/hf/model-00005-of-00005.safetensors "https://modelscope.cn/api/v1/models/XHToken/Spark-X2.5-4B/repo?Revision=master&FilePath=model-00005-of-00005.safetensors"
```

## 4. 生成 GGUF（转换 + 量化）

### 4.1 获取转换/量化工具（优先版本锁定包）

`convert_hf_to_gguf.py` 与 `llama-quantize` 均来自 XHToken 官方 fork（commit `4a3635c`）。

**首选：本地版本锁定包**（随仓库分发，克隆即有）：

```bash
tar xzf engines/llama-cpp-spark/src-archive/llama-cpp-spark-full.tar.gz
# 解压得 XHToken-llama.cpp-4a3635c/，与现有 GGUF/引擎完全同源，校验表字节数以此为准
```

**后备：GitHub master**（仅当锁定包不可用；注意 master 已演进时转换产物字节数可能与校验表不符）：

```bash
# GitHub（需代理：走 7890 端口）
curl.exe -sL -o llama.cpp-spark.tar.gz https://api.github.com/repos/XHToken/llama.cpp/tarball/master
tar xzf llama.cpp-spark.tar.gz   # 解压得 XHToken-llama.cpp-<commit>/
```

转换脚本依赖（Windows Anaconda Python）：`torch`、`transformers`、`safetensors`、`sentencepiece`。

### 4.2 转换 fp16 GGUF（确定性生成，字节数见第 6 节）

```bash
# Windows Anaconda Python 执行
set KMP_DUPLICATE_LIB_OK=TRUE
cd XHToken-llama.cpp-<commit>
python convert_hf_to_gguf.py <仓库根>/models/spark-x2.5-1.7b/hf --outfile <仓库根>/models/spark-x2.5-1.7b/Spark-X2.5-1.7B-fp16.gguf --outtype f16
python convert_hf_to_gguf.py <仓库根>/models/spark-x2.5-4b/hf   --outfile <仓库根>/models/spark-x2.5-4b/Spark-X2.5-4B-fp16.gguf   --outtype f16
```

### 4.3 量化 q4_k_m（确定性生成，字节数见第 6 节）

```bash
# WSL 内执行（llama-quantize 来自第 5 节编译产物）
export LD_LIBRARY_PATH=<llama.cpp>/build/bin:$LD_LIBRARY_PATH
./build/bin/llama-quantize <仓库根>/models/spark-x2.5-1.7b/Spark-X2.5-1.7B-fp16.gguf <仓库根>/models/spark-x2.5-1.7b/Spark-X2.5-1.7B-q4_k_m.gguf q4_k_m
./build/bin/llama-quantize <仓库根>/models/spark-x2.5-4b/Spark-X2.5-4B-fp16.gguf   <仓库根>/models/spark-x2.5-4b/Spark-X2.5-4B-q4_k_m.gguf   q4_k_m
```

## 5. 编译推理引擎（llama-cpp-spark）

详见 `engines/llama-cpp-spark/ENGINE.md`，要点：

```bash
# WSL Ubuntu-22.04，CUDA 12.6 toolkit，gcc 11.4，cmake 3.22
# 源码来自第 4.1 节解压的版本锁定包（XHToken-llama.cpp-4a3635c）
cd XHToken-llama.cpp-4a3635c && mkdir build && cd build
export CUDA_HOME=/usr/local/cuda && export PATH=$CUDA_HOME/bin:$PATH
cmake .. -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release --target llama-server llama-cli llama-quantize -j 16
# 编译产物用 cp -a 拷入 engines/llama-cpp-spark/bin/（必须 -a 保留 .so 符号链接）
```

## 6. 字节数校验表（重建后逐一核对）

GGUF 为确定性生成、safetensors 为原始下载，字节数应与本表**完全一致**；不一致则优先怀疑下载截断或工具版本差异。

| 文件 | 字节数 |
|------|--------|
| engines/llama-cpp-spark/src-archive/llama-cpp-spark-full.tar.gz | 36865674 |
| models/spark-x2.5-1.7b/Spark-X2.5-1.7B-q4_k_m.gguf | 1107457088 |
| models/spark-x2.5-1.7b/Spark-X2.5-1.7B-fp16.gguf | 3420931136 |
| models/spark-x2.5-1.7b/hf/model-00001-of-00002.safetensors | 1997108320 |
| models/spark-x2.5-1.7b/hf/model-00002-of-00002.safetensors | 1418232176 |
| models/spark-x2.5-4b/Spark-X2.5-4B-q4_k_m.gguf | 2600223584 |
| models/spark-x2.5-4b/Spark-X2.5-4B-fp16.gguf | 8229919584 |
| models/spark-x2.5-4b/hf/model-00001-of-00005.safetensors | 1982449560 |
| models/spark-x2.5-4b/hf/model-00002-of-00005.safetensors | 1993132424 |
| models/spark-x2.5-4b/hf/model-00003-of-00005.safetensors | 1993225080 |
| models/spark-x2.5-4b/hf/model-00004-of-00005.safetensors | 1993132448 |
| models/spark-x2.5-4b/hf/model-00005-of-00005.safetensors | 262252896 |

引擎二进制（`engines/llama-cpp-spark/bin/`，31 个文件合计 562960704 字节）：编译产物受工具链版本影响，**不做逐字节校验**，以能运行为准（下一节烟测验证）。

## 7. 重建后烟测

```bash
# WSL 内，仓库根目录
bash scripts/list-models.sh                # 应显示两模型四变体、无"缺失"
bash scripts/test.sh spark-x2.5-1.7b 8801  # 中文/英文对话通过，~131 tok/s
bash scripts/test.sh spark-x2.5-4b 8801     # 通过，~66 tok/s
```

```bat
:: Windows 侧等价（交互层验证）
start-zeus.cmd                :: 拉起 1.7B，等待就绪并打印访问地址
chat-zeus.cmd -NoThink "你好"  :: 命令行单发（应正常返回正文）
ui-zeus.cmd                   :: Web 控制台 http://127.0.0.1:8890/（页内启停+对话）
stop-zeus.cmd                 :: 停止
```

三层都通过后项目即完整复原。命令详解见 [api.md](api.md)。

## 8. 已知事项

- 引擎 fork 不接受显式 `--jinja` 参数（jinja 模板引擎默认启用，模板内嵌 GGUF），`model.json` 的 `extra_args` 保持为空；
- thinking 模式默认开启，API 请求传 `"chat_template_kwargs": {"enable_thinking": false}` 关闭；
- 4B fp16（7.66G）超出 8GB 显卡全卸载能力，仅适合部分卸载/CPU 混合，本机默认 q4_k_m；
- 历史勘误：旧项目记录 4B 为 3.4 tok/s 系当时 CPU 回退异常，复测为 ~66 tok/s（全 GPU）。
