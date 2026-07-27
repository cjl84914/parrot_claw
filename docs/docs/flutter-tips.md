# Flutter 开发说明

> ParrotClaw App 的 Flutter 项目架构说明与插件使用方式。

---

## 项目架构

### 目录结构

```
lib/
├── config/              # 配置文件
│   └── app_theme.dart   # 主题、颜色、样式
├── data/
│   ├── model/           # 数据模型（freezed）
│   │   ├── message.dart
│   │   └── server_config.dart
│   ├── repository/      # 数据仓库（本地 + 远程）
│   │   ├── server_repository.dart
│   │   └── setting_repository.dart
│   └── service/         # 核心服务
│       ├── gateway_channel.dart      # OpenClaw WebSocket 通道
│       ├── gateway_connection.dart   # 连接管理
│       ├── shared_preferences_service.dart
│       └── storage_service.dart      # Hive 存储
├── ui/
│   ├── screen/          # 页面
│   │   ├── chat_screen.dart
│   │   ├── index_screen.dart
│   │   ├── live2d_screen.dart        # Live2D 数字人
│   │   ├── server_list/edit_screen   # 服务器配置
│   │   ├── setting_screen.dart
│   │   ├── voice_screen.dart         # 语音对话页
│   │   └── about_screen.dart
│   ├── view_model/      # 状态管理（Provider）
│   │   ├── conn_viewmodel.dart       # 连接状态
│   │   ├── hive_chat_controller.dart # 聊天记录
│   │   ├── server_viewmodel.dart
│   │   └── setting_viewmodel.dart
│   └── widget/          # 通用组件
│       ├── composer_action_bar.dart
│       ├── server_card.dart
│       ├── video_message.dart
│       └── web_view.dart
├── util/                # 工具类
│   ├── asr_util.dart          # 离线语音识别（sherpa-onnx）
│   ├── tts_util.dart          # 离线语音合成（sherpa-onnx）
│   ├── flutter_tts_util.dart  # 系统 TTS
│   ├── parse.dart             # 消息解析
│   ├── string_util.dart
│   ├── file_util.dart
│   ├── device_identity.dart   # 设备身份认证
│   ├── command.dart
│   └── result.dart
└── main.dart            # 入口
```

### 分层说明

| 层 | 职责 |
|----|------|
| **config** | 主题配色、全局常量，不依赖业务逻辑 |
| **data/model** | 数据模型定义，使用 `freezed` 生成不可变对象 |
| **data/repository** | 数据访问层，封装本地（Hive/SharedPreferences）和网络数据来源 |
| **data/service** | 核心服务：WebSocket 连接管理、存储服务 |
| **ui/screen** | 页面级组件，组合 ViewModel 和 Widget |
| **ui/view_model** | 状态管理（Provider），处理业务逻辑，不直接操作 UI |
| **ui/widget** | 可复用 UI 组件 |
| **util** | 工具函数，无状态，纯逻辑 |

### 状态管理

使用 **Provider** 模式，ViewModel 通过 `ChangeNotifier` 管理状态：

```dart
// ViewModel 示例
class ConnViewModel extends ChangeNotifier {
  ConnectionStatus _status = ConnectionStatus.disconnected;

  ConnectionStatus get status => _status;

  void connect(String url, String token) async {
    _status = ConnectionStatus.connecting;
    notifyListeners();
    // 连接逻辑...
  }
}

// 在 Widget 中监听
final viewModel = context.watch<ConnViewModel>();
```

---

## 插件使用方式

### 分组说明

| 分类 | 插件 | 用途 |
|------|------|------|
| **网络** | `dio` | HTTP 请求 |
| | `web_socket_channel` | OpenClaw WebSocket 通信 |
| | `http` | 轻量 HTTP 请求 |
| **音频** | `record` | 录音 |
| | `audioplayers` | 音频播放 |
| | `flutter_tts` | 系统 TTS（iOS/Android 原生） |
| | `audio_session` | 音频会话管理（处理 ASR 与 TTS 冲突） |
| **AI** | `sherpa_onnx` | 离线语音识别（ASR）与离线语音合成（TTS） |
| **OpenClaw** | `web_socket_channel` | Gateway WebSocket 连接 |
| | `ed25519_edwards` | 设备身份签名认证 |
| **UI** | `flutter_chat_ui` | 聊天界面组件库 |
| | `flutter_screenutil` | 屏幕适配 |
| | `flutter_inappwebview` | Live2D 数字人 WebView |
| | `window_manager` | 桌面窗口管理（macOS/Windows） |
| | `go_router` | 路由管理 |
| **存储** | `hive` + `hive_flutter` | 本地数据库（服务器配置、聊天记录） |
| | `shared_preferences` | 轻量键值存储 |
| | `flutter_dotenv` | 环境变量配置 |
| **工具** | `provider` | 状态管理 |
| | `freezed` | 不可变数据模型代码生成 |
| | `permission_handler` | 权限申请 |
| | `file_picker` | 文件选择 |
| | `image_picker` | 图片选择 |
| | `share_plus` | 分享 |
| | `url_launcher` | 打开外部链接 |
| | `package_info_plus` | App 版本信息 |

### 关键插件使用说明

#### Audio Session（音频冲突处理）

ASR（语音识别）和 TTS（语音合成）同时运行时会产生音频冲突。通过 `audio_session` 配置：

```dart
final session = await AudioSession.instance;
await session.configure(AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
  // ...
));
```

ASR 录音时，TTS 播放会通过 `AudioContext` 配置 `audioFocus: AndroidAudioFocus.none` 来避免被系统终止。

#### sherpa-onnx（离线语音）

离线 ASR 和 TTS 都通过 `sherpa_onnx` 实现，模型文件存放在 `assets/` 目录下：

```dart
// ASR 初始化
sherpa_onnx.initBindings();
final recognizer = sherpa_onnx.OfflineRecognizer(config);

// TTS 生成
final tts = sherpa_onnx.OfflineTts(config);
final audio = tts.generateWithConfig(text: text, config: genConfig);
sherpa_onnx.writeWave(filename: filename, samples: audio.samples, sampleRate: audio.sampleRate);
```

> 模型文件首次运行时会从 assets 复制到应用支持目录，详见 `file_util.dart`。

#### 语音识别模型（SenseVoice）

ParrotClaw 的离线语音识别使用 **SenseVoice** 模型，支持中文、英文、日语、韩语、粤语。

模型文件下载地址：

[https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09](https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/tree/main)

下载后放入 `assets/senseVoice/` 目录：

```
assets/senseVoice/
├── model.int8.onnx   # 模型文件（约 237MB）
└── tokens.txt        # 词表文件
```

> 首次运行 App 时，模型文件会自动从 assets 复制到应用支持目录，无需手动处理。

#### flutter_chat_ui（聊天界面）

使用 `flyer_chat_*` 系列消息组件支持多种消息类型：

- 纯文本 → `flyer_chat_text_message`
- 流式文本 → `flyer_chat_text_stream_message`
- 图片 → `flyer_chat_image_message`
- 文件 → `flyer_chat_file_message`
- 系统消息 → `flyer_chat_system_message`

#### Hive（本地存储）

服务器配置和聊天记录使用 Hive 存储：

```dart
// 初始化
final storageService = StorageService();
await storageService.init();

// 服务器配置存 Hive Box
var box = await Hive.openBox<ServerConfig>('servers');
await box.put('my-server', config);
```

#### 代码生成（freezed）

数据模型使用 `freezed` 生成不可变对象：

```bash
dart run build_runner watch
```

修改 `model/*.dart` 后自动生成 `*.freezed.dart`。


