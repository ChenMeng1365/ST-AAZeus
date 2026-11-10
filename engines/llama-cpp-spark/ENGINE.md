# llama-cpp-spark

支持 Spark-X2.5 自定义架构的 llama.cpp 推理引擎（XHToken 官方 fork），同时兼容标准 GGUF 模型。

## 来源

- 上游仓库：https://github.com/XHToken/llama.cpp （官方 fork，master 分支）
- fork 版本：commit `4a3635c`（XHToken-llama.cpp-4a3635c）
- 后端版本：libllama 0.1.2 / ggml 0.20.2
- 版本锁定源码包：`src-archive/llama-cpp-spark-full.tar.gz`（随仓库分发，重建/重新编译首选，含 .git 历史）

## 编译环境

| 项目 | 版本 |
|------|------|
| OS | WSL2 Ubuntu-22.04 |
| 编译器 | gcc 11.4 |
| 构建 | cmake 3.22, `-DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release` |
| CUDA | 12.6 toolkit |

## 重要说明

- **bin/ 下是 Linux ELF 二进制**（无 `.exe`），只能在 WSL/Linux 下运行；含若干 Linux 相对符号链接（`lib*.so -> lib*.so.x.y`），拷贝时须保留（`cp -a`），不可用 Windows 直接复制。
- 运行时需将 bin 目录加入动态库搜索路径：`export LD_LIBRARY_PATH=<engine>/bin:$LD_LIBRARY_PATH`（scripts/start.sh 已自动处理）。

## 产物清单（bin/）

| 文件 | 说明 |
|------|------|
| llama-server | OpenAI 兼容 API 服务（核心） |
| llama-cli | 命令行推理 |
| llama-quantize | GGUF 量化工具 |
| libggml-cuda.so.0.20.2 | CUDA 后端（约 517MB） |
| libggml-base / libggml-cpu / libggml / libllama* / libmtmd | 其余运行库 |

## 重新编译（如需）

```bash
# 首选：解压仓库内版本锁定包（与现有产物完全同源）
tar xzf engines/llama-cpp-spark/src-archive/llama-cpp-spark-full.tar.gz
cd XHToken-llama.cpp-4a3635c && mkdir build && cd build
# 后备：git clone https://github.com/XHToken/llama.cpp（注意 master 可能已演进）
cmake .. -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release --target llama-server llama-cli llama-quantize -j 16
# 产物用 cp -a 拷入 bin/（保留符号链接）
```
