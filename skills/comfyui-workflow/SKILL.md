---
name: comfyui-workflow
description: Run any ComfyUI workflow (API or LiteGraph JSON) on a local/LAN ComfyUI server. Auto-detects prompt/image/audio/video inputs and downloads outputs (image, video, audio). Use for text-to-video, image-to-video, audio-driven video, T2I, editing workflows.
---

# ComfyUI Workflows — Agent Usage Guide

Run *any* ComfyUI workflow JSON over the ComfyUI HTTP/WS API. Inputs are auto-detected
(text prompt, images, audio, video, resolution, sampler), so the same command works for
text-to-video, image-to-video, audio-driven video, text-to-image, and edit workflows.

> This is a **sanitized local fork** of `yiqiliu2/comfyui-workflow` (ClawHub).
> See `SANITIZATION.md` for exactly what was removed and why.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| **Python** | 3.9+ |
| **pip package** | `websocket-client` (required; used to track run progress) |
| **ComfyUI server** | Must already be running — this skill never starts it |

```bash
python3 -m pip install --user websocket-client
```

### Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `COMFY_HOST` | ComfyUI server address (`host:port`) | `127.0.0.1:8188` |
| `COMFY_WORKFLOW_DIRS` | Extra workflow directories (colon-separated) | (none) |

You can also pass `--server HOST:PORT` on any command, or set `comfy_host` /
`workflow_dirs` in `scripts/config.json`.

**Security note:** the client speaks plaintext `http://` + `ws://`. Only point it at a
loopback or trusted-LAN ComfyUI. Do not expose ComfyUI to untrusted networks. Token
auth is intentionally unsupported (see SANITIZATION.md).

---

## End-to-End Workflow

### Step 0 — Make sure ComfyUI is running

This skill does **not** start ComfyUI. Verify the server answers first.

### Step 1 — Find the workflow

```bash
python3 scripts/comfy_run.py --list
```

Workflows are discovered from `COMFY_WORKFLOW_DIRS` and this skill's `workflows/` dir.
Any absolute path also works: `-w /path/to/workflow.json`.

### Step 2 — Inspect it (discover inputs/outputs)

```bash
python3 scripts/comfy_run.py -w "workflow_name" --inspect
```

Prints detected prompt nodes, image/audio/video loader nodes, resolution and sampler
settings, so you know exactly what can be passed in.

### Step 3 — Run it

```bash
python3 scripts/comfy_run.py -w "workflow_name" \
  --prompt "your prompt" \
  --image /path/to/ref.png \
  --audio /path/to/speech.mp3 \
  -o /path/to/output
```

For a remote/LAN server add `--server 100.101.37.96:8188` (or export `COMFY_HOST`).

### Step 4 — Collect outputs

Every output file (image / video / audio) is written into the `-o` directory with an
auto-generated prefix. The script prints the saved absolute paths, one per line.

**Always deliver the produced media to the user** — parse the printed paths and attach
the file; never reply with only a filename.

---

## CLI Reference

```
Usage: comfy_run.py [-w WORKFLOW] [options]

Modes:
  --list              List discoverable workflows
  --inspect           Human-readable input/output inspection
  --inspect-json      Machine-readable JSON inspection
  --dry-run           Print the API JSON without executing
  --queue             Submit and return immediately (non-blocking)
  --status [IDs...]   Check queue / job state

Inputs:
  --prompt, -p TEXT        Positive prompt (written to detected text nodes)
  --negative, -n TEXT      Negative prompt
  --image, -i PATH [...]   Input image(s) -> LoadImage nodes
  --audio, -a PATH [...]   Input audio file(s) -> LoadAudio nodes
  --video, -v PATH [...]   Input video file(s) -> video loader nodes

Generation:
  --width, -W INT          Output width
  --height, -H INT         Output height
  --steps INT              Sampling steps
  --cfg FLOAT              CFG scale
  --seed INT               Random seed

Advanced:
  --override JSON          Node overrides: '{"node_id": {"input": value}}'
  --config PATH            JSON/YAML file with inputs
  --server HOST:PORT       ComfyUI server
  --output-dir, -o PATH    Output directory
  --output-prefix TEXT     Output filename prefix
  --no-validate            Skip input validation
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Workflow not found` | `--list`, or pass an absolute path with `-w` |
| `NO OUTPUTS generated` | Run `--inspect`; read the printed node errors |
| `ComfyUI is not reachable` | Start ComfyUI manually / fix `--server` |
| `ModuleNotFoundError: websocket` | `python3 -m pip install --user websocket-client` |
| GPU out of memory | Lower `--width/--height` or `--steps` |

---

## Reference Documents

| Document | Purpose |
|----------|---------|
| `references/local-recipes.md` | **Start here for this machine** — verified recipes (LTX ia2v, DUIX-ready clips) + node maps + pitfalls |
| `SANITIZATION.md` | What was removed from the upstream skill and why |
| `references/prompting-guide.md` | Prompt structure and model-specific tips |
| `references/architecture.md` | How LiteGraph→API conversion works |
