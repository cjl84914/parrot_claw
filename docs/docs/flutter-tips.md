# Flutter 开发说明

> ParrotClaw App 的 Flutter 项目架构说明与插件使用方式。
>
> 项目使用 **Flutter** 编写，一套代码同时发布 iOS / Android / macOS / Windows。

## 项目架构

### 目录结构

```
lib/
├── config/
│   └── app_theme.dart                 # 主题、颜色、样式
├── data/
│   ├── model/                         # 数据模型
│   │   ├── message.dart               # 聊天消息（freezed）
│   │   ├── server_config.dart         # 服务器配置（freezed）
│   │   ├── session_message.dart
│   │   ├── gateway_session_models.dart
│   │   ├── gateway_pairing_request.dart
│   │   ├── gateway_skill.dart
│   │   ├── gateway_cron.dart
│   │   └── openclaw_model.dart
│   ├── repository/                    # 数据仓库
│   │   ├── gateway_repository.dart
│   │   ├── local_gateway_repository.dart
│   │   ├── server_repository.dart
│   │   └── setting_repository.dart
│   └── service/                       # 核心服务
│       ├── gateway_session.dart       # WebSocket 会话（协议 / 鉴权 / 重连）
│       ├── gateway_connector.dart     # 会话工厂 + 重连退避策略
│       ├── gateway_scope_store.dart
│       ├── openclaw_protocol.dart     # Gateway 协议常量与类型
│       ├── openclaw_installer_service.dart  # 安装服务接口
│       ├── openclaw_model_service.dart      # 模型管理接口
│       ├── local_gateway_service.dart       # 本机 Gateway 状态 / 凭据接口
│       ├── shared_preferences_service.dart
│       ├── storage_service.dart       # Hive 存储
│       └── impl/                      # 平台实现（按平台装配）
│           ├── openclaw_service_factory.dart
│           ├── macos_openclaw_installer_service.dart
│           ├── macos_openclaw_environment.dart
│           ├── macos_openclaw_model_service.dart
│           ├── macos_local_gateway_service.dart
│           ├── windows_openclaw_installer_service.dart
│           ├── windows_openclaw_environment.dart
│           ├── windows_openclaw_model_service.dart
│           ├── windows_local_gateway_service.dart
│           └── openclaw_model_service_impl.dart
├── ui/
│   ├── screen/                        # 页面
│   │   ├── launch_screen.dart         # 启动页
│   │   ├── index_screen.dart          # 首页 / 会话列表
│   │   ├── chat_screen.dart           # 聊天页
│   │   ├── voice_screen.dart          # 语音对话页
│   │   ├── live2d_screen.dart         # Live2D 数字人
│   │   ├── setup_screen.dart          # 首次安装引导
│   │   ├── setup_model_screen.dart    # 模型配置引导
│   │   ├── model_list_screen.dart     # 模型列表
│   │   ├── conn_gateway_screen.dart   # 连接 Gateway
│   │   ├── gateway_pairing_screen.dart # 扫码配对
│   │   ├── qr_scan_screen.dart        # 扫码
│   │   ├── qr_code_screen.dart        # 展示二维码
│   │   ├── server_list_screen.dart
│   │   ├── server_edit_screen.dart
│   │   ├── skill_screen.dart          # Skill 管理
│   │   ├── skill_search_screen.dart
│   │   ├── setting_screen.dart
│   │   ├── webview_screen.dart
│   │   ├── help_screen.dart
│   │   └── about_screen.dart
│   ├── view_model/                    # 状态管理（Provider）
│   │   ├── chat_viewmodel.dart
│   │   ├── conn_viewmodel.dart
│   │   ├── cron_viewmodel.dart
│   │   ├── server_viewmodel.dart
│   │   ├── session_viewmodel.dart
│   │   ├── setting_viewmodel.dart
│   │   ├── setup_viewmodel.dart
│   │   ├── setup_model_viewmodel.dart
│   │   └── skill_viewmodel.dart
│   └── widget/                        # 通用组件
│       ├── composer_action_bar.dart
│       ├── server_card.dart
│       ├── sidebar_widget.dart
│       ├── voice_input_button.dart
│       ├── mic_permission_dialog.dart
│       ├── hive_chat_controller.dart
│       ├── video_message.dart
│       ├── my_snack_bar.dart
│       └── ...
├── util/                              # 工具类
│   ├── asr_util.dart                  # 离线语音识别（sherpa-onnx + SenseVoice + VAD）
│   ├── edge_tts_util.dart             # 在线语音合成（flutter_edge_tts）
│   ├── tts_voice_util.dart            # TTS 音色解析纯逻辑
│   ├── tts_util.dart                  # 离线 TTS（sherpa-onnx，当前未被引用）
│   ├── flutter_tts_util.dart          # 系统 TTS（flutter_tts，当前未被引用）
│   ├── device_identity.dart           # 设备身份（Ed25519）签名认证
│   ├── file_util.dart
│   ├── parse.dart
│   ├── command.dart
│   ├── result.dart
│   └── string_util.dart
└── main.dart                          # 入口
```

### 分层说明

| 层 | 职责 |
|----|------|
| **config** | 主题配色、全局常量，不依赖业务逻辑 |
| **data/model** | 数据模型定义，主要使用 `freezed` 生成不可变对象；Gateway 协议相关的偏 POJO |
| **data/repository** | 数据访问层，封装本地（Hive / SharedPreferences）与远程（Gateway）数据来源 |
| **data/service** | 核心服务：WebSocket 会话、协议、存储；`impl/` 为按平台（macOS / Windows）装配的实现 |
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

`main.dart` 里通过 `MultiProvider` 统一注入，`OpenClawServiceFactory.create()` 会按当前平台装配出本地 Gateway / 安装 / 模型的实现，供各 ViewModel 使用。

## 核心模块

### OpenClaw 连接

- `GatewaySession`（`data/service/gateway_session.dart`）是连接的唯一真源：负责 WebSocket 建连、协议握手、鉴权、心跳与**自带退避重连**。
- `gateway_connector.dart` 定义了会话工厂与更激进的重连退避策略（1s 起、2 倍递增、上限 30s），网关重启后能较快恢复。
- `openclaw_protocol.dart` 放协议版本常量（当前 `protocol = 4`，最低兼容 `3`）与需要保持字符串形态的原始 JSON 包装类型。
- 鉴权来源见 `GatewayAuthSource`：设备 token / 共享 token / 引导 token / 密码。

### 本地 Gateway 安装（macOS / Windows）

桌面端支持一键安装并启动本机 OpenClaw：

- 接口：`openclaw_installer_service.dart`（下载/安装 Node、安装 OpenClaw、校验）、`openclaw_model_service.dart`（模型管理）、`local_gateway_service.dart`（本机进程状态与凭据）。
- 实现：`impl/` 下按平台分 `macos_*` / `windows_*`，由 `OpenClawServiceFactory` 统一装配。
- 对应的引导页：`setup_screen`（安装）→ `setup_model_screen`（模型）→ `model_list_screen`（模型列表）。

### 扫码配对

桌面端展示二维码、移动端扫码即可完成配对：

- `qr_code_screen.dart` 展示二维码，`qr_scan_screen.dart` 负责扫码（基于 `mobile_scanner`）。
- `gateway_pairing_screen.dart` + `gateway_pairing_request.dart` 处理配对请求与结果。

### Skill 管理

在 App 内浏览、搜索、安装 Skill：

- `skill_screen.dart` / `skill_search_screen.dart` + `skill_viewmodel.dart`。
- 模型定义见 `gateway_skill.dart`。

### Cron 定时任务

- `cron_viewmodel.dart` + `gateway_cron.dart`，对接 Gateway 的定时任务能力。

## 插件使用方式

### 分组说明

| 分类 | 插件 | 用途 |
|------|------|------|
| **网络** | `dio` | HTTP 请求 |
| | `http` | 轻量 HTTP 请求 |
| | `web_socket_channel` | OpenClaw Gateway WebSocket 通信 |
| **音频** | `record` | 录音 |
| | `audioplayers` | 音频播放（含 Edge TTS 合成结果的播放） |
| | `audio_session` | 音频会话管理（处理 ASR 与 TTS 冲突） |
| | `flutter_edge_tts` | 在线语音合成（Edge TTS，**当前 TTS 主力**） |
| | `sherpa_onnx` | 离线语音识别（ASR，SenseVoice） |
| **AI** | `sherpa_onnx` | 离线 ASR / VAD |
| **OpenClaw** | `web_socket_channel` | Gateway WebSocket 连接 |
| | `ed25519_edwards` | 设备身份签名认证 |
| | `uuid` | 会话/请求 ID |
| **UI** | `flutter_chat_ui` / `flutter_chat_core` | 聊天界面组件库 |
| | `flutter_link_previewer` | 链接预览 |
| | `pull_down_button` | 下拉菜单按钮 |
| | `flutter_screenutil` | 屏幕适配 |
| | `flutter_inappwebview` | Live2D 数字人 WebView |
| | `mobile_scanner` | 扫码配对 |
| | `window_manager` | 桌面窗口管理（macOS / Windows） |
| | `go_router` | 路由管理 |
| | `flutter_easyloading` | 全局 Loading / Toast |
| | `flutter_spinkit` | Loading 动画 |
| **存储** | `hive` + `hive_flutter` | 本地数据库（服务器配置、聊天记录） |
| | `shared_preferences` | 轻量键值存储 |
| **工具** | `provider` | 状态管理 |
| | `freezed` / `json_serializable` | 不可变数据模型 / JSON 序列化代码生成 |
| | `permission_handler` | 权限申请 |
| | `file_picker` | 文件选择 |
| | `image_picker` | 图片选择 |
| | `url_launcher` | 打开外部链接 |
| | `package_info_plus` | App 版本信息 |
| | `path_provider` / `path` | 路径处理 |
| | `archive` | 压缩包解压（安装包/资源） |
| | `logging` | 日志 |
| | `baidu_mob_stat` | 百度移动统计（git 依赖） |

> 已停用（`pubspec.yaml` 中注释）：`flutter_dotenv`、`flutter_tts`、`video_player`。

### 关键插件使用说明

#### Edge TTS（在线语音合成）

当前 TTS 主力是 **`flutter_edge_tts`**（微软 Edge 朗读服务），封装在 `edge_tts_util.dart`：

```dart
final tts = EdgeTTSUtil();
await tts.initSetting();
await tts.setVoice('zh-CN-YunyangNeural'); // 音色名必须带 locale 前缀
await tts.speak('你好');
```

几个容易踩的点（`EdgeTTSUtil` 里都有注释）：

1. **在线合成**：文本经 WebSocket 发到 Edge 服务端，断网会失败，内置了失败重试。
2. **播放要自己来**：插件不负责播放，这里用 `audioplayers` 补上（Android 走内存字节，其余平台落临时文件再播）。
3. **`pause()` 只能暂停播放**，已发出的合成请求仍会跑完；要真正打断用 `stop()`。
4. **没有「引擎」概念**，服务端里「音色」就是引擎；换语言要配合 `pickVoice` / `setVoice`，`setLanguage()` 只改 SSML 的 `xml:lang`。
5. **默认输出为 24kHz / 96kbps 单声道 mp3**，不要随意改格式——实测只有白名单里的 3 种可用，且 mp3 是 iOS/macOS 与 WebView 口型同步都兼容的选择。

> `tts_voice_util.dart` 把各平台 `getVoices()` 的差异收敛成统一结构，供设置页渲染音色列表。

#### sherpa-onnx（离线语音识别）

离线 ASR 由 `asr_util.dart` 基于 `sherpa_onnx` 实现，配合 **VAD**（`assets/silero_vad.onnx`）做端点检测：

```dart
final recognizer = await createOfflineRecognizer();
// 录音 → VAD 切分 → recognizer 识别 → 回调文本
```

> 模型文件首次运行时会从 `assets/` 复制到应用支持目录，详见 `file_util.dart`。

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

#### flutter_chat_ui（聊天界面）

使用 `flutter_chat_ui` / `flutter_chat_core` + `flyer_chat_*` 系列消息组件支持多种消息类型：

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
