# OpenClaw Talk 语音设置

> ParrotClaw 的 **Talk 对话模式**由 OpenClaw 的 `talk` 配置决定「用哪个引擎、什么音色」把回复读出来。
> 本文说明如何在 `openclaw.json` 中配置 Talk 语音，默认使用 **Microsoft（Edge TTS，免密钥）**。

---

## 概述

Talk 模式让数字员工"开口说话"：把模型的回复实时合成为语音播放。语音合成走 `talk` 配置；未配置时回落到客户端系统 TTS。

- `provider`：选择语音合成（TTS）引擎
- `providers.<id>`：对应引擎的参数（音色、输出格式等）

配置写入网关的 `~/.openclaw/openclaw.json`，修改后**需重启 Gateway 生效**。

---

## 快速配置（Microsoft / 免密钥）

编辑 `~/.openclaw/openclaw.json`，加入：

```json
"talk": {
  "provider": "microsoft",
  "providers": {
    "microsoft": {
      "speakerVoice": "zh-CN-YunjianNeural",
      "outputFormat": "audio-24khz-96kbitrate-mono-mp3"
    }
  }
}
```

- `provider: "microsoft"`：使用微软 Edge 在线语音（**无需 API Key**，联网即可）
- `speakerVoice`：音色 ID，如 `zh-CN-YunjianNeural`
- `outputFormat`：音频输出格式

---

## 参数说明

| 字段 | 说明 | 示例 |
| --- | --- | --- |
| `talk.provider` | 启用的 TTS 引擎 | `microsoft` |
| `talk.providers.microsoft.speakerVoice` | 微软音色 ID | `zh-CN-YunjianNeural` |
| `talk.providers.microsoft.outputFormat` | 音频输出格式 | `audio-24khz-96kbitrate-mono-mp3` |

### 常用中文音色

| 音色 ID | 名称 | 风格 |
| --- | --- | --- |
| `zh-CN-XiaoxiaoNeural` | 晓晓 | 女声，通用 |
| `zh-CN-YunxiNeural` | 云希 | 男声，通用 |
| `zh-CN-YunjianNeural` | 云健 | 男声，解说 / 播音 |
| `zh-CN-YunyangNeural` | 云扬 | 男声，新闻 |
| `zh-CN-XiaoyiNeural` | 晓伊 | 女声，活泼 |
| `zh-CN-liaoning-XiaobeiNeural` | 晓北 | 女声，辽宁方言 |
| `zh-CN-shaanxi-XiaoniNeural` | 晓妮 | 女声，陕西方言 |

> 音色 ID 大小写敏感，必须是合法的微软音色名称。

### 常用输出格式

| 格式 | 说明 |
| --- | --- |
| `audio-24khz-96kbitrate-mono-mp3` | 24kHz / 96kbps MP3（推荐：音质好、体积小） |
| `audio-24khz-48kbitrate-mono-mp3` | 24kHz / 48kbps MP3（体积更小） |
| `audio-16khz-32kbitrate-mono-mp3` | 16kHz / 32kbps MP3（低带宽） |

---

## 生效步骤

1. 保存 `~/.openclaw/openclaw.json`
2. **重启 Gateway**（聊天里发送 `/restart`，或重启 OpenClaw 服务）
3. 在支持 Talk 的客户端进入 Talk 模式说话，回复即用所选音色朗读

---

## 常见问题

- **没有声音 / 仍是系统语音**：确认 `talk.provider` 拼写正确，且已重启 Gateway。
- **音色不对**：`speakerVoice` 必须是合法的微软音色 ID，注意大小写。
- **离线环境**：Microsoft 音色为**在线**合成，需联网；纯离线场景请改用本地引擎（如 `mlx` / `system`）。

---

## 参考

- [OpenClaw Talk 模式](https://docs.openclaw.ai/zh-CN/nodes/talk)
- [OpenClaw TTS 配置](https://docs.openclaw.ai/zh-CN/tools/tts/configuration)
