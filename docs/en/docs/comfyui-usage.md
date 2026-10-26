# ComfyUI Guide

> ParrotClaw's image, video and music generation is driven by **ComfyUI**.
> This page covers installing ComfyUI, configuring workflows, and wiring it up to OpenClaw.

---

## Overview

[ComfyUI](https://github.com/Comfy-Org/ComfyUI) is a node-based AI generation interface that supports images, video, audio and more. ParrotClaw calls its workflows through the ComfyUI plugin built into OpenClaw, closing the loop from "say one sentence in the app" to "AI generates the content".

**How the pieces connect:**

```
ParrotClaw App (chat UI)
    ↕ WebSocket
OpenClaw (agent orchestration)
    ↕ HTTP API
ComfyUI (workflow execution)
```

---

## Installing ComfyUI {#installing-comfyui}

### Prerequisites

- Python 3.10+ (3.10 – 3.12 recommended)
- An NVIDIA GPU (8 GB+ VRAM recommended; Flux models need 12 GB+)
- CUDA 12.x + cuDNN (for NVIDIA cards)

> Without an NVIDIA GPU you can still run on CPU (extremely slow) or use the [ComfyUI online version](https://comfy.work/).

### Installation steps

```bash
# 1. Clone the repository
git clone https://github.com/Comfy-Org/comfyui.git
cd comfyui

# 2. Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# 3. Install PyTorch (with a GPU)
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# 3a. Or the CPU build
# pip install torch torchvision torchaudio

# 4. Install the ComfyUI dependencies
pip install -r requirements.txt

# 5. Start it
python main.py --listen 0.0.0.0 --port 8188
```

Once it is running, open `http://<your-ip>:8188` — if you see the ComfyUI interface, the install worked.

### macOS / Apple Silicon

```bash
# Install PyTorch (MPS acceleration)
pip install torch torchvision torchaudio

# Start it (MPS is used by default)
python main.py --listen 0.0.0.0 --port 8188
```

> Apple Silicon Macs (M-series chips) get decent inference speed from the MPS backend, but VRAM is shared with system memory, so large models such as Flux will use a lot of RAM.

---

## Preparing models {#preparing-models}

ComfyUI is only a framework — you need to download model files before it can do anything. Models live in the `models/` subdirectories of the ComfyUI directory.

### Where the key models go

| Model type | Path | Notes |
|----------|----------|------|
| Base model (checkpoint) | `models/checkpoints/` | e.g. Flux.1, SDXL, SD3.5 |
| LoRA | `models/loras/` | Style fine-tuning |
| VAE | `models/vae/` | Image encoding / decoding |
| CLIP | `models/clip/` | Text understanding |
| ControlNet | `models/controlnet/` | Pose / depth control |
| Upscale | `models/upscale_models/` | Upscaling models |

### Models required by the bundled workflows

#### 1. Image generation (Flux text-to-image)

Workflow file: `workflows/image_flux2_text_to_image_9b.json`

Models to download:

| File | Where to get it | Size |
|------|----------|------|
| `flux1-dev-fp8.safetensors` | HuggingFace: black-forest-labs/FLUX.1-dev | ~10 GB |
| `ae.safetensors` | HuggingFace: black-forest-labs/FLUX.1-dev | ~335 MB |
| `clip_l.safetensors` | HuggingFace: comfyanonymous/flux_text_encoders | ~246 MB |
| `t5xxl_fp8_e4m3fn.safetensors` | HuggingFace: comfyanonymous/flux_text_encoders | ~4.9 GB |

> Flux is demanding on VRAM; 12 GB+ is recommended. If your card cannot keep up, use a smaller Flux variant (such as `flux1-schnell-fp8`) or switch to SDXL.

**Where they go:**

```
comfyui/models/
├── checkpoints/
│   └── flux1-dev-fp8.safetensors
├── vae/
│   └── ae.safetensors
├── clip/
│   ├── clip_l.safetensors
│   └── t5xxl_fp8_e4m3fn.safetensors
```

#### 2. Music generation (AceStep T2A) {#2-music-generation-acestep-t2a}

Workflow file: `workflows/audio_ace_step_1_t2a_song.json`

Models to download:

| File | Where to get it | Size |
|------|----------|------|
| `ace_step_v1_3.5b.safetensors` | HuggingFace: jjkramer/ace_step_v1 | ~1.4 GB |
| `chinese_hubert_base.safetensors` | HuggingFace: jjkramer/ace_step_v1 | ~350 MB |

**Where they go:**

```
comfyui/models/
├── checkpoints/
│   └── ace_step_v1_3.5b.safetensors
├── clip/
│   └── chinese_hubert_base.safetensors  # or loaded by the workflow
```

> Note: the AceStep workflow also needs auxiliary models such as `chinese_hubert_base`; see the AceStep custom-node documentation in ComfyUI Manager for the exact dependencies.

### Additional recommended models

- **SDXL** — lighter than Flux, much lower VRAM needs (6 GB+)
- **SD3.5 Medium** — a good balance of quality and performance
- **FLUX.1-schnell** — the fast Flux variant, generates quicker

---

## Installing custom nodes

ParrotClaw's Flux and AceStep workflows need the matching ComfyUI custom nodes.

### Option 1: ComfyUI Manager (recommended)

```bash
# Install Manager
cd comfyui/custom_nodes
git clone https://github.com/ltdrdata/ComfyUI-Manager.git
cd ComfyUI-Manager
pip install -r requirements.txt
```

After restarting ComfyUI a "Manager" button appears on the right of the interface. Click it to:

- **Install Missing Custom Nodes** — detect and install whatever is missing
- **Install Models** — download models from HuggingFace / GitHub

### Option 2: Manual install

For the Flux workflow you need:

```bash
cd comfyui/custom_nodes
git clone https://github.com/blepping/ComfyUI_KJNodes.git
# plus ComfyUI's built-in Flux support (included in recent ComfyUI versions)
```

For the AceStep audio workflow:

```bash
cd comfyui/custom_nodes
git clone https://github.com/jjkramer/ComfyUI-AceStep.git
cd ComfyUI-AceStep
pip install -r requirements.txt
```

Restart ComfyUI afterwards.

---

## Configuring the OpenClaw integration

Once ComfyUI is installed, configure the connection in OpenClaw.

### Edit `~/.openclaw/openclaw.json`

```json5
{
  plugins: {
    entries: {
      comfy: {
        enabled: true,
        config: {
          mode: "local",
          baseUrl: "http://<your-comfyui-ip>:8188",
          image: {
            workflowPath: "./workspace/workflows/image_flux2_text_to_image_9b.json",
            promptNodeId: "75:74",
            outputNodeId: "9"
          },
          music: {
            workflowPath: "./workspace/workflows/audio_ace_step_1_t2a_song.json",
            promptNodeId: "14",
            outputNodeId: "59",
            promptInputName: "tags"
          }
        }
      }
    }
  }
}
```

| Field | Description |
|------|------|
| `baseUrl` | ComfyUI's address, e.g. `http://192.168.1.100:8188` |
| `image.workflowPath` | Path to the image-generation workflow JSON (API format) |
| `image.promptNodeId` | ID of the node that receives the prompt |
| `image.outputNodeId` | ID of the node that outputs the image |
| `music.workflowPath` | Path to the music-generation workflow JSON |
| `music.promptNodeId` | ID of the node that receives the style description (tags) |
| `music.outputNodeId` | ID of the node that saves the audio |
| `music.promptInputName` | Name of the input field on that node that takes the prompt |

> The workflow JSON must be in **API format**, not ComfyUI's full UI format. Export it with "Save (API Format)" in the ComfyUI interface.

### Setting the default models

Point `agents.defaults` in `openclaw.json` at them:

```json5
{
  agents: {
    defaults: {
      imageGenerationModel: {
        primary: "comfy/workflow"
      },
      musicGenerationModel: {
        primary: "comfy/workflow"
      }
    }
  }
}
```

Restart the Gateway when you are done:

```bash
openclaw gateway restart
```

---

## Using it

### Image generation

In the ParrotClaw chat screen, say:

> "Generate an image of an orange cat sitting on a beach watching the sunset"
>
> "Paint a cyberpunk-style city at night"
>
> "Make a product promo image, minimalist, white background"

The agent calls ComfyUI, runs the workflow, and sends the generated image back to the app.

### Music generation

> "Generate a rock track for me"
>
> "Write a Chinese-style BGM, flowing, flute-led"
>
> "Generate an EDM track, 120 BPM, with a huge drop"

The agent runs the AceStep audio workflow and sends an MP3 back to the app.

### Image-to-image (img2img)

To generate from a reference image, first send an image in the app, then say:

> "Turn this into a watercolour"
>
> "Based on this photo, make an oil-painting version"

The img2img workflow needs extra configuration:

```json5
{
  comfy: {
    config: {
      image: {
        // use the img2img workflow
        workflowPath: "./workspace/workflows/img2img_api.json",
        promptNodeId: "6",
        outputNodeId: "9",
        inputImageNodeId: "10"
      }
    }
  }
}
```

---

## Advanced: custom workflows

Beyond the bundled Flux text-to-image and AceStep music workflows, you can plug in any ComfyUI workflow.

### Preparing the workflow JSON

1. Build the workflow in the ComfyUI interface
2. Click "Save (API Format)" to export it as JSON
3. Put the JSON file in the `workflows/` directory of the OpenClaw workspace
4. Configure the matching `promptNodeId` and `outputNodeId` in `openclaw.json`

### Finding node IDs

Open the workflow in ComfyUI — every node shows its ID in the top-left corner (such as `6`, `9`, `75:74`).

| Common node | Description |
|----------|------|
| CLIPTextEncode | The node that takes the prompt, ID such as `6` |
| SaveImage | The image output node, ID such as `9` |
| LoadImage | The reference-image input node (for img2img), ID such as `10` |
| SaveAudioMP3 | The audio output node, ID such as `59` |

### Workflow tips

- **Keep it lean** — avoid redundant nodes; every extra node adds latency
- **Fix the size** — set `width`/`height` explicitly on the scheduler or latent node so ComfyUI does not have to infer them
- **One output node** — the workflow should have exactly one output node (SaveImage / SaveAudioMP3)
- **API format** — always export with "Save (API Format)"

---

## Optimisation tips

### Two-machine setup (recommended)

Run **ComfyUI on a dedicated GPU machine**, with OpenClaw and ParrotClaw on another machine or in separate processes on the same one.

```
┌─────────────────────┐                       ┌────────────────┐
│  ParrotClaw App     │ ── LAN / Tailscale ─▶ │  OpenClaw      │
│  (laptop / phone)   │                       │  (light host)  │
└─────────────────────┘                       └───────┬────────┘
                                                      │ HTTP
                                              ┌───────┴────────┐
                                              │  ComfyUI       │
                                              │  (GPU server)  │
                                              └────────────────┘
```

That way the GPU box does nothing but inference and is not disturbed by other services.

### Performance tuning

- **Queue management** — ComfyUI does not queue jobs itself; manage concurrency in the layer above
- **Batching** — `batch_size > 1` in the workflow generates several images at once
- **Model caching** — the first load is slow; later calls hit the cache
- **FP8 / FP16** — quantised FP8 models cut VRAM usage (such as `flux1-dev-fp8`)

---

## FAQ

### Q: ComfyUI is unreachable and OpenClaw reports an error?

```bash
# Confirm the ComfyUI process is running
curl http://<comfyui-ip>:8188/

# Check the firewall
# macOS: System Settings → Privacy & Security → Firewall
# Linux: sudo ufw status

# Confirm baseUrl is correct
openclaw config get plugins.entries.comfy.config.baseUrl
```

### Q: Generation fails with "out of memory"?

- Use a model with lower VRAM needs (switch to FP8 or SDXL)
- Lower the resolution (e.g. 768×768 → 512×512)
- Reduce `batch_size`
- Close other programs that are using the GPU

### Q: Generated images are all black or noise?

- The model file is corrupted — download it again
- The VAE file is missing or the path is wrong
- A node connection in the workflow is wrong — re-import the JSON

### Q: Flux is too slow?

- Use an FP8 model instead of FP16
- Reduce the sampling steps (steps: 20 → 10 or 15)
- Use the schnell variant (4 steps is enough)
- Consider SDXL as a lightweight alternative

### Q: The music workflow produces nothing?

- Make sure the AceStep custom node is installed
- Make sure `ace_step_v1_3.5b.safetensors` has been downloaded
- Check that the lyrics are in Chinese pinyin and correctly formatted (the workflow ships with sample lyrics)

### Q: How do I change the lyrics in the workflow?

In the AceStep music workflow the lyrics live in the `inputs.lyrics` field of node `14` in the workflow JSON. To swap them:

1. Edit `workflows/audio_ace_step_1_t2a_song.json`
2. Find the `"inputs"."lyrics"` field of the `"14"` node
3. Replace it with your lyrics
4. Save the file

> Note: lyrics must use pinyin with tone numbers (such as `ni3 hao3`); Chinese and English can be mixed.

---

## References

- [ComfyUI repository](https://github.com/Comfy-Org/ComfyUI)
- [ComfyUI Manager](https://github.com/ltdrdata/ComfyUI-Manager)
- [FLUX.1 models](https://huggingface.co/black-forest-labs/FLUX.1-dev)
- [AceStep audio model](https://huggingface.co/jjkramer/ace_step_v1)
- [OpenClaw ComfyUI plugin docs](https://docs.openclaw.ai/plugins/comfy)
