# OpenClaw Talk Voice Settings

> In ParrotClaw, **Talk mode** is driven by OpenClaw's `talk` config, which decides *which engine* and *which voice* reads the replies out loud.
> This page explains how to configure Talk voice in `openclaw.json`. The default is **Microsoft (Edge TTS, no API key required)**.

---

## Overview

Talk mode is what lets the digital employee "speak": the model's reply is synthesized into audio and played back in real time. Synthesis goes through the `talk` config; when it is not configured, the app falls back to the client's system TTS.

- `provider`: which text-to-speech (TTS) engine to use
- `providers.<id>`: settings for that engine (voice, output format, and so on)

The config lives in the gateway's `~/.openclaw/openclaw.json`, and **takes effect only after you restart the Gateway**.

---

## Quick setup (Microsoft / no key)

Edit `~/.openclaw/openclaw.json` and add:

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

- `provider: "microsoft"` — uses Microsoft Edge online voices (**no API key**, just an internet connection)
- `speakerVoice` — the voice ID, such as `zh-CN-YunjianNeural`
- `outputFormat` — the audio output format

---

## Parameters

| Field | Description | Example |
| --- | --- | --- |
| `talk.provider` | The TTS engine to enable | `microsoft` |
| `talk.providers.microsoft.speakerVoice` | Microsoft voice ID | `zh-CN-YunjianNeural` |
| `talk.providers.microsoft.outputFormat` | Audio output format | `audio-24khz-96kbitrate-mono-mp3` |

### Common Chinese voices

| Voice ID | Name | Style |
| --- | --- | --- |
| `zh-CN-XiaoxiaoNeural` | Xiaoxiao | Female, general purpose |
| `zh-CN-YunxiNeural` | Yunxi | Male, general purpose |
| `zh-CN-YunjianNeural` | Yunjian | Male, narration / broadcasting |
| `zh-CN-YunyangNeural` | Yunyang | Male, news |
| `zh-CN-XiaoyiNeural` | Xiaoyi | Female, lively |
| `zh-CN-liaoning-XiaobeiNeural` | Xiaobei | Female, Liaoning dialect |
| `zh-CN-shaanxi-XiaoniNeural` | Xiaoni | Female, Shaanxi dialect |

> Voice IDs are case-sensitive and must be a valid Microsoft voice name.

### Common output formats

| Format | Description |
| --- | --- |
| `audio-24khz-96kbitrate-mono-mp3` | 24 kHz / 96 kbps MP3 (recommended: good quality, small size) |
| `audio-24khz-48kbitrate-mono-mp3` | 24 kHz / 48 kbps MP3 (smaller) |
| `audio-16khz-32kbitrate-mono-mp3` | 16 kHz / 32 kbps MP3 (low bandwidth) |

---

## Applying the changes

1. Save `~/.openclaw/openclaw.json`
2. **Restart the Gateway** (send `/restart` in chat, or restart the OpenClaw service)
3. Enter Talk mode in a client that supports it and start speaking — replies are read in the selected voice

---

## Troubleshooting

- **No sound / still the system voice**: check that `talk.provider` is spelled correctly and that the Gateway has been restarted.
- **Wrong voice**: `speakerVoice` must be a valid Microsoft voice ID — mind the casing.
- **Offline environments**: Microsoft voices are synthesized **online** and need a network connection; for fully offline setups, switch to a local engine (such as `mlx` / `system`).

---

## References

- [OpenClaw Talk mode](https://docs.openclaw.ai/nodes/talk)
- [OpenClaw TTS configuration](https://docs.openclaw.ai/tools/tts/configuration)
