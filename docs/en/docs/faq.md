# ParrotClaw FAQ

> Covers common questions about OpenClaw configuration, Flutter development and the ComfyUI integration.
> Continuously updated.

## Contents

- [Gateway & connections](#gateway-connections)
- [Flutter development](#flutter-development)
- [TTS & voice](#tts-voice)
- [ComfyUI & image generation](#comfyui-image-generation)
- [Deployment & builds](#deployment-builds)

## Gateway & connections {#gateway-connections}

### Q: I cannot reach the Gateway from the LAN. What now?

**Check in this order:**

1. Is the Gateway configured with `bind: "lan"`? It defaults to `loopback`, which only allows local connections
2. Has the firewall allowed port 18789?
3. Is the address right? Use `ifconfig` or `ip addr` on the Gateway host to find its LAN IP
4. Does the token match?

```bash
# Check the Gateway listen address
openclaw status | grep -i dashboard

# Test from the same machine
curl http://localhost:18789/

# Test from another device on the LAN
curl http://192.168.x.x:18789/
```

### Q: Tailscale fails with "connection refused"?

1. Make sure Tailscale is running: `tailscale status`
2. Make sure every device is signed in to the same account
3. In Serve mode, check that `gateway.tailscale.mode: "serve"` is set correctly
4. In tailnet-IP mode, check `gateway.bind: "tailnet"` — `127.0.0.1` is not available in that mode

### Q: Ngrok starts but connections fail?

1. Check that the Gateway uses `bind: "lan"` (`loopback` rejects Ngrok forwarding)
2. Check that the config contains `trustedProxies: ["127.0.0.1/32"]`
3. Check that `allowedOrigins: ["*"]` is set
4. Ngrok's free plan caps concurrent connections; beyond that it refuses new ones

### Q: How do I change the Gateway token?

```bash
openclaw config set gateway.auth.token "your-new-token"
openclaw gateway restart
```

### Q: Where can I see the Gateway logs?

```bash
openclaw logs --follow
```

## Flutter development {#flutter-development}

### Q: Which Flutter version does the project use?

Flutter 3.47.1. We recommend managing versions with fvm:

```bash
# Install fvm
brew install fvm

# Install and pin the project's Flutter version
fvm install 3.47.1
fvm use 3.47.1 --force
```

### Q: How do I run code generation (freezed)?

```bash
dart run build_runner watch
```

After editing `model/*.dart`, the matching `*.freezed.dart` files are regenerated.

### Q: sherpa-onnx fails to build?

`sherpa_onnx: 1.12.39` depends on native libraries. Common issues:

- **iOS**: make sure `platform :ios` in the Podfile is at least 15.0
- **Android**: make sure minSdkVersion is at least 24
- **macOS**: requires Xcode 15+ and macOS 14+

### Q: The Live2D model does not show up in the WebView?

1. Make sure the assets under `assets/live2d/` are all present
2. Make sure `flutter_inappwebview` is a compatible version (currently `^6.1.5`)
3. On macOS, check the sandbox entitlement: `com.apple.security.network.server` must allow localhost access
4. In debug builds you can enable WebView inspection:

```dart
isInspectable: kDebugMode,
```

Then open Safari → Develop → your device → localhost:10327 to see the console.

### Q: Recording permission fails on Android?

```yaml
# Make sure android/app/src/main/AndroidManifest.xml contains:
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

`permission_handler` requires the permission to be declared in AndroidManifest.

### Q: TTS is silent on iOS?

Check the `AVAudioSessionCategory` configuration. In `flutter_tts_util.dart`:

```dart
await flutterTts.setIosAudioCategory(
  IosTextToSpeechAudioCategory.playback,
  [
    IosTextToSpeechAudioCategoryOptions.allowBluetooth,
    IosTextToSpeechAudioCategoryOptions.mixWithOthers,
  ],
  IosTextToSpeechAudioMode.voicePrompt,
);
```

### Q: The macOS build will not open?

It needs code signing and sandbox entitlements. Check `macos/Runner/*.entitlements`:

```xml
<!-- Network access is required -->
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

## TTS & voice {#tts-voice}

### Q: edge-tts is installed but the command is not found?

```bash
# Where is it installed?
which edge-tts
pip3 show edge-tts

# It usually lives at ~/.local/bin/edge-tts
# Make sure ~/.local/bin is on your PATH
```

### Q: Edge TTS synthesis is too slow?

- Check the network: edge-tts depends on Microsoft's online service
- Shorten the text; split very long text into chunks
- Raise `timeoutMs` in the Talk provider config (default 120000 ms)

### Q: What is the difference between offline and online TTS?

| | sherpa-onnx (offline) | Edge TTS (online) |
|----|----|----|
| Network | Not required | Required |
| Latency | Low (local inference) | Moderate (network round-trip) |
| Quality | Noticeably synthetic | Natural |
| Cost | Free | Free |
| Best for | Playback inside the local app | Server-side generation |

The ParrotClaw app supports both, configured differently.

### Q: Offline speech recognition (ASR) does nothing?

**Check in this order:**

1. **Are the model files present?**

```bash
ls -la assets/senseVoice/
# should contain model.int8.onnx and tokens.txt
```

The model files need to be downloaded from HuggingFace:
[https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09](https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/tree/main)

2. **Has recording permission been granted?**

- iOS/macOS: check microphone permission in System Settings
- Android: check that `RECORD_AUDIO` is declared in AndroidManifest.xml and that the runtime prompt appears

3. **Is recording actually working?**

```dart
// Add logging in voice_screen.dart to inspect the recording state
_asrUtil.setCallbacks(
  onStateChanged: (RecordState state) {
    print('record state: $state');  // confirm it reaches the recording state
  },
);
```

4. **Is the VAD model present?**

`assets/silero_vad.onnx` performs voice activity detection (when speech starts and stops). Without it, ASR will not work.

5. **Other common causes:**

- **ASR paused by TTS** — check the `isTTSAbort` setting; outside barge-in mode, ASR pauses while TTS is playing
- **Device performance** — ASR initialises slowly on older devices; wait 2–3 seconds and try again
- **Corrupted model** — download `model.int8.onnx` again and replace it

## ComfyUI & image generation {#comfyui-image-generation}

### Q: Image generation fails with "connection refused"?

Check that the ComfyUI service is running:

```bash
# Is ComfyUI reachable?
curl http://<comfyui-ip>:8188/
```

Common causes:
- The ComfyUI process is not running
- Wrong address or port (check `baseUrl` in `openclaw.json`)
- The firewall has not allowed port 8188

### Q: Image quality is not what I want?

- Refine the prompt
- Switch ComfyUI workflows (different models behave very differently)
- Check the model configuration inside the ComfyUI workflow

See the [ComfyUI guide](comfyui-usage.md) for the full configuration.

## Deployment & builds {#deployment-builds}

### Q: How do I build for macOS?

```bash
flutter build macos --release
```

The output lands in `build/macos/Build/Products/Release/ParrotClaw.app`.

### Q: How do I build for Android?

```bash
flutter build apk --release
# or
flutter build appbundle --release
```

### Q: How do I build for iOS?

```bash
flutter build ios --release
```

Requires macOS + Xcode and a valid Apple Developer certificate.

### Q: How do I build for Windows?

```bash
flutter build windows --release
```

The output lands in `build\windows\x64\runner\Release\`, with `parrotClaw.exe` as the executable.

You need **Visual Studio** installed on Windows (with the "Desktop development with C++" workload).
