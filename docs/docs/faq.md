# ParrotClaw 常见问题

> 覆盖 OpenClaw 配置、Flutter 开发、ComfyUI 集成等常见问题。
> 持续更新中。

---

## 目录

- [Gateway & 连接](#gateway--连接)
- [Flutter 开发](#flutter-开发)
- [TTS & 语音](#tts--语音)
- [ComfyUI & 生图](#comfyui--生图)
- [部署 & 构建](#部署--构建)

---

## Gateway & 连接

### Q：局域网连不上 Gateway，怎么办？

**检查顺序：**

1. Gateway 是否配置了 `bind: "lan"`？默认为 `loopback`，只允许本机连接
2. 防火墙是否放行了 18789 端口
3. 连接地址是否正确？用 `ifconfig` 或 `ip addr` 查 Gateway 主机的局域网 IP
4. token 是否匹配

```bash
# 确认 Gateway 监听地址
openclaw status | grep -i dashboard

# 本机测试连接
curl http://localhost:18789/

# 局域网其他设备测试
curl http://192.168.x.x:18789/
```

### Q：Tailscale 连不上，提示连接被拒绝？

1. 确认 Tailscale 已启动：`tailscale status`
2. 确认所有设备登录同一账号
3. 如果用 Serve 模式，检查 `gateway.tailscale.mode: "serve"` 是否配置正确
4. 如果用 tailnet IP 模式，检查 `gateway.bind: "tailnet"`，此模式下 `127.0.0.1` 不可用

### Q：Ngrok 启动了但连接不上？

1. 检查 Gateway 是否 `bind: "lan"`（`loopback` 会拒绝 Ngrok 转发）
2. 检查配置中是否有 `trustedProxies: ["127.0.0.1/32"]`
3. 检查 `allowedOrigins: ["*"]` 是否设置
4. Ngrok 免费版有连接数限制，超出会拒绝连接

### Q：如何更换 Gateway 的 token？

```bash
openclaw config set gateway.auth.token "新的token"
openclaw gateway restart
```

### Q：Gateway 日志在哪里看？

```bash
openclaw logs --follow
```

---

## Flutter 开发

### Q：项目用的 Flutter 版本？

Flutter 3.41.9+，SDK `^3.7.0`。建议使用 fvm 管理多版本：

```bash
# 安装 fvm
brew install fvm

# 安装并锁定项目 Flutter 版本
fvm install 3.41.9
fvm use 3.41.9 --force
```

### Q：代码生成（freezed）怎么运行？

```bash
dart run build_runner watch
```

修改 `model/*.dart` 后会自动生成 `*.freezed.dart`。

### Q：sherpa-onnx 编译报错？

`sherpa_onnx: 1.12.39` 依赖原生库，常见问题：

- **iOS**：确保 Podfile 中 `platform :ios` 版本不低于 15.0
- **Android**：确保 minSdkVersion 不低于 24
- **macOS**：需要 Xcode 15+ 和 macOS 14+

### Q：Live2D 在 WebView 中不显示？

1. 确认 `assets/live2d/` 目录下的资源文件齐全
2. 确认 `flutter_inappwebview` 版本兼容（当前 `^6.1.5`）
3. macOS 上检查沙盒权限：`com.apple.security.network.server` 需要允许 localhost 访问
4. 调试模式下可启用 WebView inspect：

```dart
isInspectable: kDebugMode,
```

然后在 Safari → 开发 → 设备名 → localhost:10327 查看控制台。

### Q：Android 上录音权限申请失败？

```yaml
# android/app/src/main/AndroidManifest.xml 中确认包含：
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

`permission_handler` 需要在 AndroidManifest 中声明对应权限。

### Q：iOS 上 TTS 不发声？

检查 `AVAudioSessionCategory` 配置是否正确。在 `flutter_tts_util.dart` 中：

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

### Q：macOS 构建的 App 打不开？

需要配置签名和沙盒权限。检查 `macos/Runner/*.entitlements` 文件：

```xml
<!-- 需要网络访问 -->
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

---

## TTS & 语音

### Q：Edge-TTS 安装了但找不到命令？

```bash
# 查看安装路径
which edge-tts
pip3 show edge-tts

# 通常位于 ~/.local/bin/edge-tts
# 确保 ~/.local/bin 在 PATH 中
```

### Q：Edge-TTS 合成速度太慢？

- 检查网络：edge-tts 依赖微软在线服务
- 缩短文本长度，超长文本建议分段
- 在 Talk provider 配置中调大 `timeoutMs`（默认 120000ms）

### Q：离线 TTS 和在线 TTS 有什么区别？

| | sherpa-onnx（离线） | Edge-TTS（在线） |
|----|----|----|
| 网络 | 不需要 | 需要 |
| 延迟 | 低（本地推理） | 中等（网络请求） |
| 音质 | 合成感较强 | 自然 |
| 成本 | 免费 | 免费 |
| 适用场景 | 本地 App 内播放 | 服务器端生成 |

ParrotClaw App 内两个都支持，配置方式不同。

### Q：离线语音识别（ASR）没有反应？

**检查顺序：**

1. **模型文件是否存在？**

```bash
ls -la assets/senseVoice/
# 应包含 model.int8.onnx 和 tokens.txt
```

模型文件需要从 HuggingFace 下载：
[https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09](https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/tree/main)

2. **录音权限是否授予？**

- iOS/macOS：系统设置中检查麦克风权限
- Android：检查 AndroidManifest.xml 中是否声明 `RECORD_AUDIO` 权限，运行时是否弹窗申请

3. **录音是否正常？**

```dart
// 在 voice_screen.dart 中可以加日志查看录音状态
_asrUtil.setCallbacks(
  onStateChanged: (RecordState state) {
    print('录音状态: $state');  // 确认是否进入 recording 状态
  },
);
```

4. **VAD 模型是否存在？**

`assets/silero_vad.onnx` 文件用于语音活动检测（检测什么时候说话、什么时候停止），缺失会导致 ASR 不工作。

5. **其他常见原因：**

- **ASR 被 TTS 暂停** — 检查 `isTTSAbort` 设置，非打断模式下 TTS 播放时会暂停 ASR
- **设备性能** — 旧设备上 ASR 初始化较慢，等待 2-3 秒后再试
- **模型损坏** — 重新下载 model.int8.onnx 文件替换

### Q：Live2D 朗读时没有声音或播放异常？

Live2D 的 WebView 播放音频只兼容 **44100Hz、16-bit、单声道 PCM WAV** 格式。不符合此格式的音频可能无法播放或出现杂音。

如果使用 Edge-TTS + `tts-wrapper.sh` 方案，wrapper 脚本已用 ffmpeg 做了转码，会自动满足要求。

如果直接使用 edge-tts 输出（绕过 wrapper），需要确认采样率：

```bash
# 查看音频信息
ffprobe /path/to/audio.wav
# 确认：Sample Rate = 44100 Hz, Channels = 1 (mono)
```

如格式不符，用 ffmpeg 转码：

```bash
ffmpeg -y -i input.wav -acodec pcm_s16le -ar 44100 -ac 1 output.wav
```

> 口型同步（lip sync）需要 Live2D 模型本身包含口型参数，音频格式正确只是前提条件。

---

## ComfyUI & 生图

### Q：生成图片提示连接被拒绝？

确认 ComfyUI 服务是否运行：

```bash
# 查看 ComfyUI 是否可访问
curl http://<comfyui-ip>:8188/
```

常见原因：
- ComfyUI 进程未启动
- 地址/端口配置错误（检查 `openclaw.json` 中的 `baseUrl`）
- 防火墙未放行 8188 端口

### Q：生成图片质量不理想？

- 调整 Prompt 描述
- 切换 ComfyUI 工作流（不同模型效果差异大）
- 检查 ComfyUI 工作流中的模型配置

详细配置见 [ComfyUI 使用指南](comfyui-usage.md)。

---

## 部署 & 构建

### Q：如何构建 macOS 版本？

```bash
flutter build macos --release
```

构建产物在 `build/macos/Build/Products/Release/parrot_app.app`。

### Q：如何构建 Android 版本？

```bash
flutter build apk --release
# 或
flutter build appbundle --release
```

### Q：如何构建 iOS 版本？

```bash
flutter build ios --release
```

需要 macOS + Xcode，以及有效的 Apple Developer 证书。

### Q：Windows 能构建吗？

项目依赖 `window_manager` 和 `flutter_inappwebview`，Windows 理论上支持，但未充分测试。

### Q：环境变量怎么配？

项目使用 `flutter_dotenv`，在项目根目录创建 `.env` 文件：

```env
DEBUG=false
# 其他配置...
```