# The Author's Letter

> The story behind the project, its journey, and its author.

## 1. Why ParrotClaw

I have lived through three eras: the internet, the mobile internet, and artificial intelligence.

Along the way, one feeling has stayed with me: **AI is changing the way all software is interacted with.** From graphical interfaces that require learning complex operations to an AI mode where you simply talk in natural language and the work gets done — this is not an incremental improvement, but a complete paradigm shift.

What will the world look like 100 years from now? Human productivity will be massively liberated — perhaps as full of imagination as WALL·E.

I hope that in this era, each of us can leave behind something valuable.

ParrotClaw is the thing I want to leave behind.

## 2. The ParrotClaw journey

The Parrot project goes back to 2023.

**2023 — parrot_app**

The first versions connected directly to large-model APIs through local configuration, delivering basic AI conversation. The idea was simple: put AI inside an app and make conversation reachable for everyone.

**2025 — parrot_desktop**

The desktop version introduced Spring AI as its backend, with more complete multi-turn conversation and tool calling. But the architecture was still too heavy — maintenance cost and flexibility were both less than ideal.

**2026 — OpenClaw arrives**

OpenClaw launched with force this year. I saw its agent orchestration capability — built-in Skills, Plugins, voice interaction, toolchain integration… exactly the backend I had always wanted.

Rather than building an architecture from scratch, why not put the energy into the front-end experience? **Build a real AI digital-employee app on top of OpenClaw** — that idea appeared naturally.

And so ParrotClaw was born.

### How it differs from the official OpenClaw app

The official OpenClaw app is powerful, but it puts up a few barriers for users in China:

- **Dependence on Google services** — most phones in China have no Google Services, so offline speech recognition does not work
- **Developer-oriented interaction** — it is better suited to developers

ParrotClaw addresses those pain points:

| Aspect | Official OpenClaw app | ParrotClaw |
|------|------------------|------------|
| Speech recognition | Relies on Google online services | Offline recognition on sherpa-onnx, supports Chinese, no Google, no network |
| Digital human | None | Live2D integration, making read-aloud conversation more fun |
| Message formats | Text only | **Image display, audio and video playback** — rich media messages supported natively |
| Multi-server configuration | Single server connection only | **Multi-server management** — one app connects to several OpenClaw or toolchain servers at once and switches freely |
| Cross-platform | Mobile only | **Flutter cross-platform** — one codebase covering mobile and desktop with a consistent experience |

Put simply: **ParrotClaw makes an AI digital employee workable in a Chinese environment — and more fun to use.**

Beyond localisation for China, ParrotClaw has some distinctive engineering choices:

**Multi-server configuration** — unlike the official app, which connects to a single backend, ParrotClaw can configure and manage several server connections at once. You can keep production and test environments apart, or deploy agents with different roles on different servers and manage them together. If you run a ComfyUI image workstation, a TTS server and an OpenClaw orchestration hub, one app handles all the switching.

**Cross-platform Flutter architecture** — built on Flutter, one codebase covers Android, iOS, Windows, macOS and Linux. Your data follows your account seamlessly across devices, and for developers the maintenance cost drops sharply: a new feature ships everywhere at once.

## 3. A modest contribution

ParrotClaw is only a beginning.

I hope more people will get involved — to suggest ideas for future versions, and if possible, to take part in building them.

One person can walk fast, but a group can walk far.
