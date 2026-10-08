# Flutter Development Notes

> The Flutter project structure behind the ParrotClaw app, and how its plugins are used.
>
> The project is written in **Flutter** — one codebase shipping iOS / Android / macOS / Windows.

## Project structure

### Directory layout

```
lib/
├── config/
│   └── app_theme.dart                 # Theme, colors, styles
├── data/
│   ├── model/                         # Data models
│   │   ├── message.dart               # Chat message (freezed)
│   │   ├── server_config.dart         # Server config (freezed)
│   │   ├── session_message.dart
│   │   ├── gateway_session_models.dart
│   │   ├── gateway_pairing_request.dart
│   │   ├── gateway_skill.dart
│   │   ├── gateway_cron.dart
│   │   └── openclaw_model.dart
│   ├── repository/                    # Data repositories
│   │   ├── gateway_repository.dart
│   │   ├── local_gateway_repository.dart
│   │   ├── server_repository.dart
│   │   └── setting_repository.dart
│   └── service/                       # Core services
│       ├── gateway_session.dart       # WebSocket session (protocol / auth / reconnect)
│       ├── gateway_connector.dart     # Session factory + reconnect backoff
│       ├── gateway_scope_store.dart
│       ├── openclaw_protocol.dart     # Gateway protocol constants and types
│       ├── openclaw_installer_service.dart  # Installer service interface
│       ├── openclaw_model_service.dart      # Model management interface
│       ├── local_gateway_service.dart       # Local Gateway state / credentials interface
│       ├── shared_preferences_service.dart
│       ├── storage_service.dart       # Hive storage
│       └── impl/                      # Platform implementations (wired per platform)
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
│   ├── screen/                        # Screens
│   │   ├── launch_screen.dart         # Launch screen
│   │   ├── index_screen.dart          # Home / session list
│   │   ├── chat_screen.dart           # Chat screen
│   │   ├── voice_screen.dart          # Voice conversation screen
│   │   ├── live2d_screen.dart         # Live2D digital human
│   │   ├── setup_screen.dart          # First-run setup
│   │   ├── setup_model_screen.dart    # Model setup wizard
│   │   ├── model_list_screen.dart     # Model list
│   │   ├── conn_gateway_screen.dart   # Connect to a Gateway
│   │   ├── gateway_pairing_screen.dart # Scan-to-pair
│   │   ├── qr_scan_screen.dart        # Scan a QR code
│   │   ├── qr_code_screen.dart        # Show a QR code
│   │   ├── server_list_screen.dart
│   │   ├── server_edit_screen.dart
│   │   ├── skill_screen.dart          # Skill management
│   │   ├── skill_search_screen.dart
│   │   ├── setting_screen.dart
│   │   ├── webview_screen.dart
│   │   ├── help_screen.dart
│   │   └── about_screen.dart
│   ├── view_model/                    # State management (Provider)
│   │   ├── chat_viewmodel.dart
│   │   ├── conn_viewmodel.dart
│   │   ├── cron_viewmodel.dart
│   │   ├── server_viewmodel.dart
│   │   ├── session_viewmodel.dart
│   │   ├── setting_viewmodel.dart
│   │   ├── setup_viewmodel.dart
│   │   ├── setup_model_viewmodel.dart
│   │   └── skill_viewmodel.dart
│   └── widget/                        # Shared widgets
│       ├── composer_action_bar.dart
│       ├── server_card.dart
│       ├── sidebar_widget.dart
│       ├── voice_input_button.dart
│       ├── mic_permission_dialog.dart
│       ├── hive_chat_controller.dart
│       ├── video_message.dart
│       ├── my_snack_bar.dart
│       └── ...
├── util/                              # Utilities
│   ├── asr_util.dart                  # Offline speech recognition (sherpa-onnx + SenseVoice + VAD)
│   ├── edge_tts_util.dart             # Online speech synthesis (flutter_edge_tts)
│   ├── tts_voice_util.dart            # Pure logic for resolving TTS voices
│   ├── tts_util.dart                  # Offline TTS (sherpa-onnx, currently unreferenced)
│   ├── flutter_tts_util.dart          # System TTS (flutter_tts, currently unreferenced)
│   ├── device_identity.dart           # Device identity (Ed25519) signed auth
│   ├── file_util.dart
│   ├── parse.dart
│   ├── command.dart
│   ├── result.dart
│   └── string_util.dart
└── main.dart                          # Entry point
```

### Layers

| Layer | Responsibility |
|----|------|
| **config** | Theme colors and global constants; no business logic |
| **data/model** | Data model definitions, mostly `freezed` immutable objects; Gateway protocol types are closer to plain POJOs |
| **data/repository** | Data access layer, wrapping local (Hive / SharedPreferences) and remote (Gateway) sources |
| **data/service** | Core services: WebSocket session, protocol, storage; `impl/` holds the per-platform (macOS / Windows) implementations |
| **ui/screen** | Screen-level widgets that combine ViewModels and Widgets |
| **ui/view_model** | State management (Provider); holds business logic and never touches UI directly |
| **ui/widget** | Reusable UI components |
| **util** | Stateless, pure-logic helper functions |

### State management

The project uses the **Provider** pattern, with ViewModels extending `ChangeNotifier`:

```dart
// ViewModel example
class ConnViewModel extends ChangeNotifier {
  ConnectionStatus _status = ConnectionStatus.disconnected;

  ConnectionStatus get status => _status;

  void connect(String url, String token) async {
    _status = ConnectionStatus.connecting;
    notifyListeners();
    // connection logic...
  }
}

// Listening from a widget
final viewModel = context.watch<ConnViewModel>();
```

`main.dart` injects everything through `MultiProvider`, and `OpenClawServiceFactory.create()` assembles the local Gateway / installer / model implementations for the current platform, so every ViewModel can use them.

## Core modules

### OpenClaw connection

- `GatewaySession` (`data/service/gateway_session.dart`) is the single source of truth for a connection: it owns the WebSocket connection, protocol handshake, auth, heartbeat and **backoff-based reconnection**.
- `gateway_connector.dart` defines the session factory and a more aggressive reconnect backoff (starting at 1s, doubling, capped at 30s), so the app recovers quickly after a Gateway restart.
- `openclaw_protocol.dart` holds the protocol version constants (currently `protocol = 4`, minimum compatible `3`) and the raw-JSON wrapper types that must stay strings.
- Auth sources are described by `GatewayAuthSource`: device token / shared token / bootstrap token / password.

### Local Gateway install (macOS / Windows)

The desktop app can install and start a local OpenClaw in one click:

- Interfaces: `openclaw_installer_service.dart` (download/install Node, install OpenClaw, verify), `openclaw_model_service.dart` (model management), `local_gateway_service.dart` (local process state and credentials).
- Implementations: `impl/` splits into `macos_*` / `windows_*`, assembled by `OpenClawServiceFactory`.
- Corresponding wizard screens: `setup_screen` (install) → `setup_model_screen` (model) → `model_list_screen` (model list).

### Scan-to-pair

The desktop shows a QR code and the mobile app scans it to pair:

- `qr_code_screen.dart` displays the QR code, `qr_scan_screen.dart` scans it (built on `mobile_scanner`).
- `gateway_pairing_screen.dart` + `gateway_pairing_request.dart` handle the pairing request and its result.

### Skill management

Browse, search and install Skills inside the app:

- `skill_screen.dart` / `skill_search_screen.dart` + `skill_viewmodel.dart`.
- Model definitions live in `gateway_skill.dart`.

### Cron

- `cron_viewmodel.dart` + `gateway_cron.dart`, wired to the Gateway's scheduled-task capability.

## Plugins

### By category

| Category | Plugin | Purpose |
|------|------|------|
| **Network** | `dio` | HTTP requests |
| | `http` | Lightweight HTTP requests |
| | `web_socket_channel` | OpenClaw Gateway WebSocket communication |
| **Audio** | `record` | Recording |
| | `audioplayers` | Audio playback (including playing Edge TTS output) |
| | `audio_session` | Audio session management (handles ASR vs TTS conflicts) |
| | `flutter_edge_tts` | Online speech synthesis (Edge TTS, **the current primary TTS**) |
| | `sherpa_onnx` | Offline speech recognition (ASR, SenseVoice) |
| **AI** | `sherpa_onnx` | Offline ASR / VAD |
| **OpenClaw** | `web_socket_channel` | Gateway WebSocket connection |
| | `ed25519_edwards` | Device identity signed auth |
| | `uuid` | Session / request IDs |
| **UI** | `flutter_chat_ui` / `flutter_chat_core` | Chat UI component library |
| | `flutter_link_previewer` | Link previews |
| | `pull_down_button` | Pull-down menu button |
| | `flutter_screenutil` | Screen adaptation |
| | `flutter_inappwebview` | WebView for the Live2D digital human |
| | `mobile_scanner` | Scan-to-pair |
| | `window_manager` | Desktop window management (macOS / Windows) |
| | `go_router` | Routing |
| | `flutter_easyloading` | Global loading / toast |
| | `flutter_spinkit` | Loading animations |
| **Storage** | `hive` + `hive_flutter` | Local database (server config, chat history) |
| | `shared_preferences` | Lightweight key-value storage |
| **Tooling** | `provider` | State management |
| | `freezed` / `json_serializable` | Immutable models / JSON serialization codegen |
| | `permission_handler` | Runtime permissions |
| | `file_picker` | File selection |
| | `image_picker` | Image selection |
| | `url_launcher` | Opening external links |
| | `package_info_plus` | App version info |
| | `path_provider` / `path` | Path handling |
| | `archive` | Archive extraction (installers / assets) |
| | `logging` | Logging |
| | `baidu_mob_stat` | Baidu mobile analytics (git dependency) |

> No longer used (commented out in `pubspec.yaml`): `flutter_dotenv`, `flutter_tts`, `video_player`.

### Notes on key plugins

#### Edge TTS (online speech synthesis)

The primary TTS today is **`flutter_edge_tts`** (Microsoft's Edge read-aloud service), wrapped in `edge_tts_util.dart`:

```dart
final tts = EdgeTTSUtil();
await tts.initSetting();
await tts.setVoice('zh-CN-YunyangNeural'); // the voice name must carry the locale prefix
await tts.speak('你好');
```

A few easy-to-miss points (all commented in `EdgeTTSUtil`):

1. **Synthesis is online**: the text goes to the Edge service over a WebSocket, so it fails when offline; retries are built in.
2. **You play the result yourself**: the plugin does not play audio, so `audioplayers` fills that gap here (Android uses in-memory bytes, other platforms write a temp file and play it).
3. **`pause()` only pauses playback** — synthesis requests already sent still run to completion; use `stop()` for a real interruption.
4. **There is no "engine" concept** — on the server a "voice" *is* the engine; switching language means using `pickVoice` / `setVoice`, while `setLanguage()` only changes the SSML `xml:lang`.
5. **Default output is 24 kHz / 96 kbps mono mp3** — do not change the format casually; in practice only three formats on the whitelist work, and mp3 is the one compatible with both iOS/macOS and the WebView lip-sync.

> `tts_voice_util.dart` normalizes the differences between each platform's `getVoices()` into one structure, which the settings screen uses to render the voice list.

#### sherpa-onnx (offline speech recognition)

Offline ASR is implemented in `asr_util.dart` on top of `sherpa_onnx`, combined with **VAD** (`assets/silero_vad.onnx`) for endpoint detection:

```dart
final recognizer = await createOfflineRecognizer();
// record → VAD segmentation → recognizer → text callback
```

> On first run, model files are copied from `assets/` into the app support directory; see `file_util.dart` for details.

#### Speech recognition model (SenseVoice)

ParrotClaw's offline speech recognition uses the **SenseVoice** model, covering Chinese, English, Japanese, Korean and Cantonese.

Model download:

[https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09](https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09/tree/main)

After downloading, place the files in `assets/senseVoice/`:

```
assets/senseVoice/
├── model.int8.onnx   # Model file (about 237MB)
└── tokens.txt        # Tokens file
```

> On the app's first run the model files are copied automatically from assets into the app support directory — no manual step needed.

#### Audio Session (handling audio conflicts)

Running ASR (recognition) and TTS (synthesis) at the same time causes conflicts. Configure them through `audio_session`:

```dart
final session = await AudioSession.instance;
await session.configure(AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
  // ...
));
```

While ASR is recording, TTS playback configures `audioFocus: AndroidAudioFocus.none` through `AudioContext` so the system does not terminate it.

#### flutter_chat_ui (chat UI)

`flutter_chat_ui` / `flutter_chat_core` plus the `flyer_chat_*` message widgets support multiple message types:

- Plain text → `flyer_chat_text_message`
- Streaming text → `flyer_chat_text_stream_message`
- Image → `flyer_chat_image_message`
- File → `flyer_chat_file_message`
- System message → `flyer_chat_system_message`

#### Hive (local storage)

Server configuration and chat history are stored in Hive:

```dart
// Initialization
final storageService = StorageService();
await storageService.init();

// Server config in a Hive box
var box = await Hive.openBox<ServerConfig>('servers');
await box.put('my-server', config);
```

#### Code generation (freezed)

Data models use `freezed` to generate immutable objects:

```bash
dart run build_runner watch
```

After editing `model/*.dart`, `*.freezed.dart` is regenerated automatically.
