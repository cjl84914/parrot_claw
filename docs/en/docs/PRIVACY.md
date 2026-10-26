# ParrotClaw Privacy Policy

> Last updated: July 9, 2026
> Effective: July 9, 2026

---

## 1. About this policy

ParrotClaw is an open-source AI digital-employee app (referred to below as "the app" or "we"), developed and maintained by Alex. The app is released under the **MIT license**, and its source code is hosted on GitHub.

This privacy policy explains how your information is collected, used and stored when you use ParrotClaw.

**Our key commitment: ParrotClaw is a self-hosted app. There is no cloud server, and we do not collect your personal information.**

---

## 2. Information we collect

### 2.1 What we do not collect

ParrotClaw has **no account system**. You do not need to register, sign in, or provide any personal information to use it. We **do not collect**:

- Personal identifiers such as your name, phone number or email address
- Passwords or login credentials
- Device identifiers (IMEI, IDFA, MAC address, and so on)
- Location data
- Contacts or social relationships
- Behavioural or usage profiling

### 2.2 Information processed locally on your device

The following information is processed only on your own device and is **never uploaded to any server of ours** (because we do not have one):

| Data type | How it is handled | Uploaded? |
|----------|----------|----------|
| Chat history | Stored locally on the device (Hive database) | ❌ Not uploaded |
| Server configuration | Stored locally, including the OpenClaw server address and token you configure | ❌ Not uploaded |
| Voice input | Recognised offline on the device by sherpa-onnx; never sent to the cloud | ❌ Not uploaded |
| Images / files you send | Sent directly to the OpenClaw server you configured | ❌ Never passes through us |
| App preferences | Stored locally on the device (SharedPreferences) | ❌ Not uploaded |


## 3. How information is stored and processed

### 3.1 Local storage

- **Chat history**: stored in a Hive database inside your device's private app directory
- **Server configuration**: stored on the device in a Hive database
- **Voice model files**: the SenseVoice ASR model (about 237 MB) and the Silero VAD model ship as app assets and are copied into the app support directory automatically on first run

You can clear all locally stored data under **Settings → Data management** in the app.

### 3.2 The server you configure yourself

ParrotClaw needs to connect to an OpenClaw server that you deploy yourself. When you use the app:

- Your messages, speech recognition results and selected files are sent over a **WebSocket connection** to the server address you configured
- Those servers are entirely under your control (they can run on a LAN, a Tailscale network, or your own public server)
- How data is processed depends on the OpenClaw server and Skills you configure
- We have no access to any data on those servers

### 3.3 Third-party cloud services

ParrotClaw can optionally talk to the following third-party services. **All of them are configured and controlled by you**:

- **Microsoft Edge TTS** (edge-tts): if you use edge-tts for speech synthesis, audio synthesis requests go to Microsoft's online service. That is outside our control — please refer to Microsoft's privacy policy
- **HuggingFace**: the ASR model files are downloaded from HuggingFace, which is only needed the first time; once downloaded, the app no longer contacts HuggingFace

---

## 4. Permissions

ParrotClaw needs the following system permissions to run fully:

| Permission | Purpose | Notes |
|------|------|------|
| **Microphone** | Voice input | Required for offline ASR. Only active while you hold the record button — it does not listen continuously |
| **Photo library / camera** | Sending images | Used when you pick or take a photo to send |
| **File storage** | Choosing and saving files | Choosing files to send, and saving generated images / audio to the device |
| **Network** | Connecting to your OpenClaw server | The app itself never connects to any third-party network service |
| **Local network** | Discovering services on the LAN | Used on macOS to reach an OpenClaw service on the local network |

All permissions are used only when you take an action; nothing is enabled behind your back. You can grant or revoke them at any time in system settings.

---

## 5. Data security

### 5.1 Security in transit

- The WebSocket connection between you and the OpenClaw server can be secured with **token authentication**
- Connections through Tailscale or an HTTPS proxy (such as Ngrok) are encrypted automatically
- For production use we recommend Tailscale Serve or an HTTPS proxy to secure the transport

### 5.2 Local security

- Chat history and server tokens are stored in the device's private directory, which other apps cannot read
- We recommend enabling a screen lock passcode / biometrics on your device to protect local data

---

## 6. Children's privacy

We do not knowingly collect personal information from children.

---

## 7. Changes to this policy

We may update this privacy policy from time to time. Updated versions are published inside the app (on the About page) and in the GitHub repository, with the update date noted. Continuing to use the app means you accept the updated policy.

---

## 8. Contact us

If you have any questions or concerns about this privacy policy, please get in touch:

- **Email**: 121237385@qq.com
- **QQ**: 121237385
- **GitHub**: [https://github.com/cjl84914/parrot_claw](https://github.com/cjl84914/parrot_claw)
- **Project issues**: [https://github.com/cjl84914/parrot_claw/issues](https://github.com/cjl84914/parrot_claw/issues)

---

## Appendix: permissions per platform

### Android

The following permissions are declared in `AndroidManifest.xml`:

| Permission | Purpose |
|------|------|
| `INTERNET` | Network communication |
| `RECORD_AUDIO` | Voice input |
| `READ_EXTERNAL_STORAGE` | Reading files |
| `WRITE_EXTERNAL_STORAGE` | Saving files |
| `MODIFY_AUDIO_SETTINGS` | Adjusting audio settings |
| `FOREGROUND_SERVICE` | Background recording service |
| `FOREGROUND_SERVICE_MICROPHONE` | Microphone foreground service |
| `POST_NOTIFICATIONS` | Recording status notifications |

### iOS / macOS

The following permissions are declared in `Info.plist` / `entitlements`:

| Permission | Purpose |
|------|------|
| Microphone | Voice input |
| Photo library | Sending images |
| Local network | Debugging and LAN connections |
| File access | File operations |

### A note on macOS

Release builds of the macOS app **do not enable the sandbox**, and therefore have:

- Read/write access to files you select and to the Downloads directory
- Permission to run external commands (used to call tools such as ffmpeg and edge-tts)
- Access to the Homebrew install directory (`/opt/homebrew`)
- Process execution and fork permissions

These permissions are required to run the TTS wrapper and similar scripts, and are never used to reach data you have not authorised.

---

*ParrotClaw is open-source software. The complete source code is at [https://github.com/cjl84914/parrot_claw](https://github.com/cjl84914/parrot_claw)*
