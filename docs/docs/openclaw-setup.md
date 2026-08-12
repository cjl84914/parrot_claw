# OpenClaw 配置指南

> 针对 ParrotClaw 用户的 OpenClaw 安装、配置与连接方式。
> 目标读者：有一定技术基础的专业用户（一人公司、自媒体、企业媒体技术负责人）。

---

## 安装 OpenClaw

```bash
npm install -g openclaw
openclaw onboard   # 交互式初始化
```

更多安装方式详见 [OpenClaw 官方文档](https://docs.openclaw.ai/install)。

---

## 目录

- [Gateway 连接方式](#gateway-连接方式)
  - [1. LAN 局域网连接](#1-lan-局域网连接)
  - [2. Tailscale 连接](#2-tailscale-连接)
  - [3. Ngrok 公网隧道连接](#3-ngrok-公网隧道连接)
- [Skills（技能）配置](#skills技能配置)
- [Talk（语音交互）配置](#talk语音交互配置)
- [Plugins（插件）配置](#plugins插件配置)

---

## Gateway 连接方式

### 1. LAN 局域网连接

同一局域网内的设备（手机、另一台电脑）直接连接 Gateway。

**配置 `~/.openclaw/openclaw.json`：**

```json5
{
  gateway: {
    mode: "local",
    bind: "lan",         // 监听局域网接口，默认是 loopback（仅本机）
    port: 18789,         // 默认端口
    auth: {
      mode: "token",
      token: "your-token-here"  // 替换成你自己的 token
    }
  }
}
```

**说明：**
- `bind: "lan"` 让 Gateway 监听 `0.0.0.0:18789`，局域网内设备可访问
- 默认为 `bind: "loopback"`，仅本机能连
- 认证方式推荐 `token` 模式

**重启 Gateway：**

```bash
openclaw gateway restart
```

**连接方式：**

| 类型 | 地址 |
|------|------|
| Dashboard（管理面板） | `http://192.168.x.x:18789/` |
| WebSocket（ParrotClaw App） | `ws://192.168.x.x:18789` |

> `192.168.x.x` 替换为 Gateway 主机的局域网 IP，可通过 `ifconfig` 或 `ip addr` 查看。

**与 ParrotClaw App 连接：**
1. 打开 ParrotClaw App → 设置 → 服务器配置
2. 填入 `ws://192.168.x.x:18789` 和对应的 token
3. 连接测试通过即可使用

---

### 2. Tailscale 连接

通过 [Tailscale](https://tailscale.com) 组建虚拟局域网（tailnet），实现跨网络的安全连接。

#### 安装 Tailscale

**macOS：**

```bash
brew install --cask tailscale
```

安装后在系统设置中启用 Tailscale，或通过菜单栏图标登录。

**Linux：**

```bash
# 一键安装脚本（推荐）
curl -fsSL https://tailscale.com/install.sh | sh

# 启动并登录
sudo tailscale up
```

> Linux 下 `tailscale up` 需要 root 权限，首次会打开浏览器授权。

**验证安装：**

```bash
tailscale status
# 输出示例：
# 100.x.x.x    my-device          username@       linux   idle
# 100.x.x.x    my-phone           username@       iOS     active
```

所有设备状态应为 `active` 或 `idle`。

#### 配置

#### 方式 A：Tailscale Serve（推荐）

Gateway 保持 loopback 绑定，Tailscale 自动提供 HTTPS 和路由。

**配置：**

```json5
{
  gateway: {
    mode: "local",
    bind: "loopback",      // 保持本机监听，不暴露到局域网
    port: 18789,
    tailscale: {
      mode: "serve"        // Tailscale Serve 模式
    },
    auth: {
      mode: "token",
      token: "your-token-here"
    }
  }
}
```

**连接地址：** `https://<你的tailscale设备名>.ts.net/`

Tailscale Serve 会自动注入身份头，可以使用 Tailscale 用户身份免 token 认证（需 `auth.allowTailscale: true`，默认开启）。

---

### 3. Ngrok 公网隧道连接

通过 [Ngrok](https://ngrok.com) 将本地 Gateway 暴露到公网，适合没有 Tailscale 或需要外网访问的场景。

#### 安装 Ngrok

**macOS：**

```bash
brew install ngrok
```

**Linux：**

```bash
# 或通过 apt（Ubuntu / Debian）
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null

# 添加 ngrok apt 源
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
  | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null

sudo apt update && sudo apt install ngrok
```

**配置认证 token：**（从 https://dashboard.ngrok.com 获取）

```bash
ngrok config add-authtoken <你的ngrok-token>
```

**Gateway 配置：**

```json5
{
  gateway: {
    mode: "local",
    bind: "lan",                     // 必须 lan，loopback 会拒绝 ngrok 转发进来的请求
    port: 18789,
    trustedProxies: ["127.0.0.1/32"], // ngrok 走本地转发，保留此信任代理设置
    controlUi: {
      allowedOrigins: ["*"]          // 跨域，否则浏览器/App 连接不上
    },
    auth: {
      mode: "token",
      token: "your-token-here"
    }
  }
}
```

**启动 Ngrok 隧道：**

```bash
ngrok http 18789 --region ap
```

> `--region ap` 指定亚太节点，降低延迟。其他可选：`us`、`eu`、`au` 等。

**连接方式：**

Ngrok 启动后会生成一个公网 URL，如 `https://xxxx.ap.ngrok.io`。

| 类型 | 地址 |
|------|------|
| Dashboard | `https://xxxx.ap.ngrok.io/` |
| WebSocket | `wss://xxxx.ap.ngrok.io` |

> Ngrok 免费版有连接数限制和速率限制，仅适合测试和小规模使用。
> 生产环境建议升级 Ngrok 付费计划或用 Tailscale 替代。

---

## Skills（技能）配置

Skills 是 OpenClaw 的能力插件，通过自然语言触发。比如让 AI 帮你发布掘金文章、查询天气、搜索 GitHub 等，都由 Skills 提供。

### 在 ClawHub 找到需要的 Skill

[ClawHub](https://clawhub.ai) 是 OpenClaw 的官方技能市场。打开后在搜索框输入关键词（如 "juejin"），浏览搜索结果并记下技能名（slug），即可用于安装。

### 安装技能

在终端执行：

```bash
openclaw skills install <slug>
```

例如安装掘金技能：

```bash
openclaw skills install juejin-skills
```

安装后在工作区的 `skills/` 目录下会生成对应的技能文件夹。

### 查看已安装技能

```bash
openclaw skills list
```

### 示例：掘金技能配置

以掘金（juejin-skills）为例：

**1. 安装**

```bash
openclaw skills install juejin-skills
```

**2. 登录凭证**

安装后让 AI 执行一次掘金相关操作（比如说"查一下掘金热门文章"），AI 会自动启动 Playwright 浏览器，打开掘金登录页。扫码登录后，Cookie 自动保存到本地，后续无需重复登录。

**3. 使用**

登录完成后即可对话发布文章，示例见 [使用案例 - 案例二：文章发布到掘金](use-cases.md#case-2)。

---

## Talk（语音交互）配置

OpenClaw 的 Talk 能力通过配置 TTS provider 实现。Agent 需要语音输出时，调用 `talk.speak`，Gateway 将文本发给配置好的命令行工具合成音频，再推送给客户端播放。


### 小米 Mimo TTS （推荐）

小米 MiMo TTS 提供高质量的中文语音合成，基于 OpenAI 协议兼容 API（`/v1/audio/speech`），目前 TTS 服务**限时免费**。

> 官网：[https://mimo.mi.com/](https://mimo.mi.com/) | API Key 从控制台获取

OpenClaw 原生不支持 HTTP API 类的 TTS provider，需要写一个包装脚本调用小米 API，再配置到 `talk.providers` 中。

**参考配置（`openclaw.json`）：**

```json
{
  "talk": {
    "enable": true,
    "provider": "xiaomi",
    "providers": {
      "xiaomi": {
        "apiKey": "sk-...",
        "model": "mimo-v2.5-tts",
        "speakerVoice": "苏打",
        "format": "wav"
      }
    }
  }
}
```

**包装脚本示例（参考，需自行创建）：**

```bash
#!/bin/bash
API_KEY="sk-..."   # 替换为你的 API Key
curl -s -X POST "https://api.mimo.mi.com/v1/audio/speech" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"mimo-v2.5-tts\",\"input\":\"$1\",\"voice\":\"苏打\",\"response_format\":\"wav\"}" \
  --output "$2"
```

**参数说明：**

| 参数 | 说明 |
|------|------|
| `apiKey` | 小米 MiMo API Key，从控制台获取 |
| `model` | TTS 模型，当前为 `mimo-v2.5-tts` |
| `speakerVoice` | 音色，如 `苏打`、`晓晓`、`云希` |
| `format` | 输出格式，建议 `wav` |
| `style` | 音色风格描述（如 "Warm, natural male voice..."） |

其他TTS方案: https://docs.openclaw.ai/tools/tts/

---
### 直接使用 edge-tts（适合专业人士）

### 安装 edge-tts

**macOS：**

```bash
pip3 install edge-tts
```

> edge-tts 依赖 Python 3，macOS 自带 Python 3 或通过 `brew install python@3` 安装。

**Linux：**

```bash
# Debian / Ubuntu
sudo apt install python3-pip
pip3 install edge-tts
```

> Linux 下确保服务器有外网访问权限（edge-tts 调用 Microsoft Edge 在线 TTS 服务）。

安装后通过 `which edge-tts` 确认路径，配置时要用到。

### 中文音色参考

通过 `edge-tts --list-voices` 可列出所有可用音色：

| 音色 | 说明 |
|------|------|
| `zh-CN-XiaoxiaoNeural` | 女声，自然亲切 |
| `zh-CN-YunxiNeural` | 男声，阳光 |
| `zh-CN-YunyangNeural` | 男声，沉稳 |
| `zh-CN-XiaoyiNeural` | 女声，活泼 |

修改命令中的 `--voice` 参数即可切换音色。

### 测试

```bash
# 测试直接使用 edge-tts
~/.local/bin/edge-tts --voice zh-CN-YunxiNeural --text "你好" --write-media /tmp/test.wav

# 或测试 wrapper 脚本
bash /path/to/tts-wrapper.sh "你好" /tmp/test.wav
```

没有报错且 `/tmp/test.wav` 已生成，说明配置正确。

最简单的方式是让 OpenClaw 直接调用 edge-tts 命令行，不经过中间脚本。编辑 `~/.openclaw/openclaw.json`：

```json5
{
  "talk": {
    "enable": true,
    "provider": "edge-tts",
    "providers": {
      "edge-tts": {
        "command": "~/.local/bin/edge-tts",
        "args": [
          "--voice", "zh-CN-YunxiNeural",
          "--text", "{{Text}}",
          "--write-media", "{{OutputPath}}"
        ],
        "outputFormat": "wav",
        "timeoutMs": 120000
      }
    }
  }
}
```

> `edge-tts` 的路径通过 `which edge-tts` 或 `pip3 show edge-tts` 查看，通常是 `~/.local/bin/edge-tts`。

### TTS兼容 Live2D

Live2D 数字人要求音频格式为 **44100Hz、16-bit、单声道 PCM WAV**，而 edge-tts 默认输出采样率不固定。此时需要通过 `tts-wrapper.sh` 脚本包装，用 ffmpeg 转码。

**脚本 `tts-wrapper.sh`（放在 workspace 目录下）：**

```bash
#!/bin/bash
# tts-wrapper.sh — edge-tts + ffmpeg 转码为 44100Hz 16-bit mono PCM WAV

TEXT="$1"
OUTPUT="$2"
TEMP="${OUTPUT}.tmp"

~/.local/bin/edge-tts \
  --voice zh-CN-YunxiNeural \
  --text "$TEXT" \
  --write-media "$TEMP" \
  --rate +0% \
  --pitch +0Hz

ffmpeg -y -i "$TEMP" \
  -acodec pcm_s16le -ar 44100 -ac 1 \
  "$OUTPUT" 2>/dev/null

rm -f "$TEMP"
```

注意：需要执行权限：chmod +x tts-wrapper.sh

**配置：**

```json5
{
  talk: {
    provider: "tts-local-cli",
    providers: {
      "tts-local-cli": {
        command: "/home/ubuntu/.openclaw/workspace/tts-wrapper.sh",
        args: ["{{Text}}", "{{OutputPath}}"],
        outputFormat: "wav",
        timeoutMs: 120000
      }
    }
  }
}
```

### 配置说明

| 字段 | 说明 |
|------|------|
| `talk.provider` | 选择使用的 provider 名称 |
| `providers.<name>.command` | 命令的绝对路径 |
| `args` | 命令参数。`{{Text}}` 和 `{{OutputPath}}` 是模板变量，Gateway 自动替换为实际文本和临时文件路径 |
| `outputFormat` | 输出音频格式，设置为 `wav` |
| `timeoutMs` | 超时时间（毫秒），防止合成超长文本时卡住 |

配置完成后重启 Gateway：

```bash
openclaw gateway restart
```

之后 Agent 说"讲出来"或需要语音回复时，会自动调用 edge-tts 合成语音。


---

## Plugins（插件）配置

视频和音频合成依赖 [ffmpeg](https://ffmpeg.org)。OpenClaw 的视频生成、音频转码等功能都通过 ffmpeg 处理。

### 安装满血版 ffmpeg

#### macOS

Homebrew 默认的 `ffmpeg` 公式只包含基础编码器，缺少很多关键功能（如 whisper 语音识别、libass 字幕渲染、libplacebo 高级滤镜等）。需要安装 `ffmpeg-full` 才能获得完整能力。

```bash
# 1. 添加 tap（如尚未添加）
brew tap homebrew-ffmpeg/ffmpeg

# 2. 安装满血版（耗时较长，约 5-30 分钟）
brew install ffmpeg-full

# 3. 确认 Xcode Command Line Tools 已安装
xcode-select --install
```

安装完成后检查关键特性：

```bash
ffmpeg -version
# 输出应包含（看 --enable-* 列表）：
#   --enable-libwhisper       # 语音识别
#   --enable-libass           # 字幕渲染
#   --enable-libplacebo       # 高级滤镜
#   --enable-libx264/libx265  # H.264/H.265 编码
#   --enable-videotoolbox     # macOS 硬件加速
#   --enable-audiotoolbox     # macOS 音频加速
#   --enable-libaom           # AV1 编码
```

> 完整特性列表可通过 `ffmpeg -buildconf` 查看。

#### Linux（Ubuntu / Debian）

通过 apt 安装（但 apt 官方源的 ffmpeg 特性不全，不推荐）：

```bash
sudo apt update
sudo apt install ffmpeg
```

**验证安装：**

```bash
ffmpeg -version
```

应确认包含 `--enable-libx264`、`--enable-libx265`、`--enable-libass`、`--enable-libwhisper` 等关键特性。

> 注意：apt 官方源的 ffmpeg 版本通常较旧且缺少大量编码器，强烈建议使用 johnvansickle 的静态编译包。

### 测试验证（通用）

安装完成后测试基础转码（生成测试视频并转 GIF），验证命令示例见 [使用案例 - 案例三：音视频处理](use-cases.md#case-3)。

没有报错说明 ffmpeg 安装正常。

### 日常使用

安装完成后即可在对话中直接让 Agent 处理音视频（转格式、转 GIF、提取音频等），使用示例见 [使用案例 - 案例三：音视频处理](use-cases.md#case-3)。

### 图片 / 视频 / 音频生成

ParrotClaw 的内容生成能力通过 **OpenClaw + ComfyUI** 实现。

| 能力 | 说明 |
|------|------|
| 图片生成（文生图 / 图生图） | ComfyUI 工作流驱动 |
| 视频生成 | 通过 ComfyUI 视频工作流 |
| 音频生成 | Edge-TTS 语音合成 + ffmpeg 转码 |

详细配置请参考：[ComfyUI 使用指南](comfyui-usage.md)
