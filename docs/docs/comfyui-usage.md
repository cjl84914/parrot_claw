# ComfyUI 使用指南

> ParrotClaw 的图片、视频、音乐生成能力通过 **ComfyUI** 驱动。
> 本文介绍 ComfyUI 的安装、工作流配置、与 OpenClaw 的集成方式。

---

## 概述

[ComfyUI](https://github.com/Comfy-Org/ComfyUI) 是一个节点式 AI 生成界面，支持图像、视频、音频等多种模态的生成。ParrotClaw 通过 OpenClaw 内置的 ComfyUI 插件调用工作流，实现「在 App 里说一句话 → AI 生成内容」的闭环。

**架构链路：**

```
ParrotClaw App（聊天界面）
    ↕ WebSocket
OpenClaw（Agent 调度）
    ↕ HTTP API
ComfyUI（工作流执行）
```

---

## 安装 ComfyUI

### 前提条件

- Python 3.10+（推荐 3.10 ~ 3.12）
- NVIDIA GPU（推荐 8GB+ 显存，Flux 模型需 12GB+）
- CUDA 12.x + cuDNN（NVIDIA 显卡用户）

> 如果没有 NVIDIA GPU，也可以 CPU 运行（速度极慢）或使用 [ComfyUI 在线版](https://comfy.work/)。

### 安装步骤

```bash
# 1. 克隆仓库
git clone https://github.com/Comfy-Org/comfyui.git
cd comfyui

# 2. 创建 Python 虚拟环境
python3 -m venv venv
source venv/bin/activate

# 3. 安装 PyTorch（有 GPU）
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# 3a. 或 CPU 版本
# pip install torch torchvision torchaudio

# 4. 安装 ComfyUI 依赖
pip install -r requirements.txt

# 5. 启动
python main.py --listen 0.0.0.0 --port 8188
```

启动后访问 `http://<你的IP>:8188` 看到 ComfyUI 界面即安装成功。

### macOS / Apple Silicon 用户

```bash
# 安装 PyTorch（MPS 加速）
pip install torch torchvision torchaudio

# 启动（默认使用 MPS）
python main.py --listen 0.0.0.0 --port 8188
```

> Apple Silicon Mac（M 系列芯片）可以使用 MPS 后端获得不错的推理速度，但显存共享系统内存，大模型（如 Flux）会占用大量内存。

---

## 模型准备

ComfyUI 本身只是一个框架，需要下载模型文件才能工作。模型文件存放在 ComfyUI 目录下的 `models/` 子目录中。

### 关键模型存放位置

| 模型类型 | 存放路径 | 说明 |
|----------|----------|------|
| 基础模型（Checkpoint） | `models/checkpoints/` | 如 Flux.1, SDXL, SD3.5 |
| LoRA | `models/loras/` | 风格微调 |
| VAE | `models/vae/` | 图像编解码 |
| CLIP | `models/clip/` | 文本理解 |
| ControlNet | `models/controlnet/` | 姿态/深度控制 |
| Upscale | `models/upscale_models/` | 放大模型 |

### ParrotClaw 现有工作流所需模型

#### 1. 图像生成（Flux 文生图）

工作流文件：`workflows/image_flux2_text_to_image_9b.json`

需要下载的模型：

| 文件 | 下载位置 | 大小 |
|------|----------|------|
| `flux1-dev-fp8.safetensors` | HuggingFace: black-forest-labs/FLUX.1-dev | ~10GB |
| `ae.safetensors` | HuggingFace: black-forest-labs/FLUX.1-dev | ~335MB |
| `clip_l.safetensors` | HuggingFace: comfyanonymous/flux_text_encoders | ~246MB |
| `t5xxl_fp8_e4m3fn.safetensors` | HuggingFace: comfyanonymous/flux_text_encoders | ~4.9GB |

> Flux 模型对显存要求较高，推荐 12GB+ 显存。如果显卡不够，可以使用更小版本的 Flux 模型（如 `flux1-schnell-fp8`）或用 SDXL 替代。

**存放位置：**

```
comfyui/models/
├── checkpoints/
│   └── flux1-dev-fp8.safetensors
├── vae/
│   └── ae.safetensors
├── clip/
│   ├── clip_l.safetensors
│   └── t5xxl_fp8_e4m3fn.safetensors
```

#### 2. 音乐生成（AceStep T2A）

工作流文件：`workflows/audio_ace_step_1_t2a_song.json`

需要下载的模型：

| 文件 | 下载位置 | 大小 |
|------|----------|------|
| `ace_step_v1_3.5b.safetensors` | HuggingFace: jjkramer/ace_step_v1 | ~1.4GB |
| `chinese_hubert_base.safetensors` | HuggingFace: jjkramer/ace_step_v1 | ~350MB |

**存放位置：**

```
comfyui/models/
├── checkpoints/
│   └── ace_step_v1_3.5b.safetensors
├── clip/
│   └── chinese_hubert_base.safetensors  # 或由工作流加载
```

> 注意：AceStep 模型需要下载 `chinese_hubert_base` 等辅助模型，具体依赖见 ComfyUI Manager 中 AceStep 自定义节点的说明。

### 额外推荐模型

- **SDXL** — 比 Flux 轻量，显存需求低（6GB+）
- **SD3.5 Medium** — 质量和性能的平衡选择
- **FLUX.1-schnell** — Flux 的快速版，生成速度更快

---

## 安装自定义节点

ParrotClaw 的 Flux 和 AceStep 工作流需要安装对应的 ComfyUI 自定义节点。

### 方法一：ComfyUI Manager（推荐）

```bash
# 安装 Manager
cd comfyui/custom_nodes
git clone https://github.com/ltdrdata/ComfyUI-Manager.git
cd ComfyUI-Manager
pip install -r requirements.txt
```

重启 ComfyUI 后，界面右侧会出现「Manager」按钮。点击后：

- **Install Missing Custom Nodes** → 自动检测缺失节点并安装
- **Install Models** → 通过 HuggingFace/GitHub 下载模型

### 方法二：手动安装

对于 Flux 工作流，需要：

```bash
cd comfyui/custom_nodes
git clone https://github.com/blepping/ComfyUI_KJNodes.git
# 以及 ComfyUI 内置的 Flux 支持（ComfyUI 较新版本已内置）
```

对于 AceStep 音频工作流：

```bash
cd comfyui/custom_nodes
git clone https://github.com/jjkramer/ComfyUI-AceStep.git
cd ComfyUI-AceStep
pip install -r requirements.txt
```

安装后重启 ComfyUI。

---

## 配置 OpenClaw 集成

ComfyUI 安装好后，需要在 OpenClaw 中配置连接。

### 编辑 `~/.openclaw/openclaw.json`

```json5
{
  plugins: {
    entries: {
      comfy: {
        enabled: true,
        config: {
          mode: "local",
          baseUrl: "http://<你的ComfyUI IP>:8188",
          image: {
            workflowPath: "./workspace/workflows/image_flux2_text_to_image_9b.json",
            promptNodeId: "75:74",
            outputNodeId: "9"
          },
          music: {
            workflowPath: "./workspace/workflows/audio_ace_step_1_t2a_song.json",
            promptNodeId: "14",
            outputNodeId: "59",
            promptInputName: "tags"
          }
        }
      }
    }
  }
}
```

| 字段 | 说明 |
|------|------|
| `baseUrl` | ComfyUI 的访问地址，如 `http://192.168.1.100:8188` |
| `image.workflowPath` | 图像生成工作流 JSON 文件路径（API 格式） |
| `image.promptNodeId` | 工作流中接收 prompt 的节点 ID |
| `image.outputNodeId` | 工作流中输出图片的节点 ID |
| `music.workflowPath` | 音乐生成工作流 JSON 文件路径 |
| `music.promptNodeId` | 接收风格描述（tags）的节点 ID |
| `music.outputNodeId` | 保存音频的输出节点 ID |
| `music.promptInputName` | 节点中接收 prompt 的输入字段名 |

> 工作流 JSON 必须是 **API 格式**，不能是 ComfyUI 的完整 UI 格式。在 ComfyUI 界面中，通过「Save (API Format)」导出。

### 配置默认模型

在 `openclaw.json` 的 agents.defaults 中指定：

```json5
{
  agents: {
    defaults: {
      imageGenerationModel: {
        primary: "comfy/workflow"
      },
      musicGenerationModel: {
        primary: "comfy/workflow"
      }
    }
  }
}
```

配置完成后重启 Gateway：

```bash
openclaw gateway restart
```

---

## 使用方式

### 图片生成

在 ParrotClaw App 聊天界面中说：

> "帮我生成一张图片，一只橘猫坐在沙滩上看日落"
>
> "画一幅赛博朋克风格的城市夜景"
>
> "生成一张产品宣传图，极简风格，白底"

Agent 会自动调用 ComfyUI 执行工作流，把生成的图片发回 App。

### 音乐生成

> "帮我生成一首摇滚风格的音乐"
>
> "写一首古风BGM，悠扬、笛子为主"
>
> "生成一段电子舞曲，120BPM，Drop部分要炸"

Agent 会调用 AceStep 音频工作流，生成 MP3 发回 App。

### 图生图（img2img）

如果需要基于参考图生成，在 App 中先发送一张图片，然后说：

> "把这个图转成水彩风格"
>
> "基于这张照片，生成一副油画版本"

当前支持的图生图工作流需要额外配置：

```json5
{
  comfy: {
    config: {
      image: {
        // 使用图生图工作流
        workflowPath: "./workspace/workflows/img2img_api.json",
        promptNodeId: "6",
        outputNodeId: "9",
        inputImageNodeId: "10"
      }
    }
  }
}
```

---

## 高级：自定义工作流

除了 ParrotClaw 自带的 Flux 文生图和 AceStep 音乐工作流，你可以导入任意 ComfyUI 工作流。

### 准备工作流 JSON

1. 在 ComfyUI 界面中搭建好工作流
2. 点击「Save (API Format)」导出为 JSON
3. 把 JSON 文件放到 OpenClaw workspace 的 `workflows/` 目录下
4. 在 `openclaw.json` 中配置对应的 `promptNodeId` 和 `outputNodeId`

### 找到节点 ID

在 ComfyUI 中打开工作流，每个节点左上角有 ID 编号（如 `6`、`9`、`75:74`）。

| 常见节点 | 说明 |
|----------|------|
| CLIPTextEncode | prompt 输入的节点，ID 如 `6` |
| SaveImage | 图像输出的节点，ID 如 `9` |
| LoadImage | 参考图输入节点（图生图用），ID 如 `10` |
| SaveAudioMP3 | 音频输出的节点，ID 如 `59` |

### 工作流编写技巧

- **保持简洁** — 避免多余节点，减少推理延迟
- **固定尺寸** — 在调度器或 Latent 节点中固定 `width`/`height`，避免 ComfyUI 动态推算
- **输出节点唯一** — 工作流中只有一个输出节点（SaveImage / SaveAudioMP3）
- **API 格式** — 始终使用「Save (API Format)」导出

---

## 优化建议

### 双机部署（推荐）

建议 **ComfyUI 跑在专用 GPU 机器** 上，OpenClaw 和 ParrotClaw 跑在另一台机器或同一台机器的不同进程中。

```
┌─────────────────┐     LAN/Tailscale      ┌──────────────┐
│  ParrotClaw App  │ ────────────────────── │  OpenClaw    │
│  (你的笔记本/手机)│                       │  (轻量机器)   │
└─────────────────┘                         └──────┬───────┘
                                                    │ HTTP
                                            ┌───────┴───────┐
                                            │  ComfyUI       │
                                            │  (GPU 服务器)   │
                                            └───────────────┘
```

这样 GPU 服务器专门跑推理，不会被其他服务干扰。

### 性能调优

- **队列管理** — ComfyUI 本身不排队，多任务需在外层管理并发
- **批处理** — 工作流中 `batch_size > 1` 可一次生成多张
- **模型缓存** — ComfyUI 首次加载模型较慢，后续调用会缓存
- **FP8/FP16** — 使用 FP8 量化模型减少显存占用（如 `flux1-dev-fp8`）

---

## 常见问题

### Q：ComfyUI 连不上，OpenClaw 报错？

```bash
# 确认 ComfyUI 进程在运行
curl http://<comfyui-ip>:8188/

# 检查防火墙
# macOS: 系统设置 → 隐私与安全性 → 防火墙
# Linux: sudo ufw status

# 确认 baseUrl 配置正确
openclaw config get plugins.entries.comfy.config.baseUrl
```

### Q：生成提示「out of memory」？

- 使用更低显存需求的模型（切换 FP8 或 SDXL）
- 降低图片分辨率（如 768×768 → 512×512）
- 减少 `batch_size`
- 关闭其他占用 GPU 的程序

### Q：生成的图片全是黑色/噪点？

- 模型文件损坏，重新下载
- VAE 文件缺失或路径不对
- 工作流节点连接错误，重新导入 JSON

### Q：Flux 生成太慢？

- 使用 FP8 模型替代 FP16
- 减少采样步数（steps: 20 → 10 或 15）
- 使用 schnell 版本（4 步即可）
- 考虑使用 SDXL 作为轻量替代

### Q：音乐工作流不生成？

- 确认 AceStep 自定义节点已安装
- 确认 `ace_step_v1_3.5b.safetensors` 模型已下载
- 歌词包含中文拼音且格式正确（工作流已预置示例歌词）

### Q：如何更换工作流的歌词？

AceStep 音乐工作流中的歌词写在工作流 JSON 的节点 `14` 的 `inputs.lyrics` 字段中。如需换歌词：

1. 编辑 `workflows/audio_ace_step_1_t2a_song.json`
2. 找到 `"14"` 节点的 `"inputs"."lyrics"` 字段
3. 替换为你的歌词内容
4. 保存文件

> 注意：歌词需要使用带声调的拼音（如 `ni3 hao3`），支持中英文混合。

---

## 参考链接

- [ComfyUI 官方仓库](https://github.com/Comfy-Org/ComfyUI)
- [ComfyUI Manager](https://github.com/ltdrdata/ComfyUI-Manager)
- [FLUX.1 模型](https://huggingface.co/black-forest-labs/FLUX.1-dev)
- [AceStep 音频模型](https://huggingface.co/jjkramer/ace_step_v1)
- [OpenClaw ComfyUI 插件文档](https://docs.openclaw.ai/plugins/comfy)
