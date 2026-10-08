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

ParrotClaw stands on top of OpenClaw — the underlying capabilities are the same as the official app; the difference is that **the experience has been made "simple"**.

The official app is powerful, but it puts up a few barriers for everyday users in China:

- **Technical installation** — you have to prepare the environment and configure OpenClaw yourself
- **Dependence on Google services** — most phones in China have no Google Services, so voice recognition does not work
- **Developer-oriented interaction** — it feels more like a tool than an app that works out of the box

What ParrotClaw improves:

| Aspect | Official OpenClaw app | ParrotClaw |
|------|------------------|------------|
| Getting started | Technical, needs configuration | **Simple and easy to use**, works out of the box |
| Installation | Install and configure OpenClaw yourself | **One-click install on desktop**; **scan to use on mobile** |
| Speech recognition | Relies on Google online services | **Offline Chinese ASR** (sherpa-onnx) — no network, no Google |
| Speech synthesis | Needs setup, mostly cloud-based | **Free TTS**, available out of the box |
| Digital human | None | **Live2D digital human** with lip-synced speech — more fun to talk to |
| Cross-platform | Mobile first | **Flutter cross-platform** — one experience on desktop and mobile |

In one sentence: **ParrotClaw turns "usable" into "easy to use".**

ParrotClaw is also open source under the **MIT license** — the code is fully open, and you are welcome to use and build on it. And like the official app, it supports **self-hosting**: everything runs on your own devices, so your privacy never leaves your network.

## 3. A modest contribution

ParrotClaw is only a beginning.

I hope more people will get involved — to suggest ideas for future versions, and if possible, to take part in building them.

One person can walk fast, but a group can walk far.
