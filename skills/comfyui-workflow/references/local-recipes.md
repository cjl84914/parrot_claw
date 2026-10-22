# Local Recipes — this machine

Concrete, verified recipes for Alex's setup. Update this file whenever a new workflow
is wired up or a new pitfall is found.

## Environment

| Item | Value |
|---|---|
| ComfyUI server | `http://100.101.37.96:8188` (LAN; no auth) |
| GPU | RTX 4060 Ti 16 GB |
| Workflow dir | `/Users/alexcai/.openclaw/workspace/workflows/` |
| Config | `scripts/config.json` (`comfy_host`, `workflow_dirs`) |

Run everything from the skill dir:
```bash
cd ~/.openclaw/workspace/skills/comfyui-workflow
```

---

## Recipe: LTX 2.3 image + audio → video (`video_ltx2_3_ia2v.json`)

Drives a talking/audio-driven video from **one image + one audio file**. The audio is
trimmed to the requested duration and packed into the output mp4 (the audio track is the
**input** audio, not generated).

### Node map

| Purpose | Node | Field |
|---|---|---|
| Reference image | `269` (LoadImage) | `image` |
| Input audio | `276` (LoadAudio) | `audio` |
| Main prompt | `340:319` (PrimitiveStringMultiline) | `value` |
| Duration (seconds) | `340:331` (PrimitiveFloat) | `value` — frames = duration × fps + 1 (`340:329`) |
| FPS | `340:323` (PrimitiveInt) | `value` (default 24) |
| Width / Height | `340:330` / `340:324` (PrimitiveInt) | `value` |
| Prompt-enhance switch | `340:349` (PrimitiveBoolean) | `value` — `true` = local LLM rewrites the prompt |
| Image→video switch | `340:305` (PrimitiveBoolean) | `value` — keep `false` |
| Output | `341` (SaveVideo) | — |

### Command

```bash
python3 scripts/comfy_run.py -w video_ltx2_3_ia2v \
  --image /abs/path/ref.png \
  --audio /abs/path/voice.mp3 \
  --override '{
    "340:319":{"value":"<PROMPT>"},
    "340:331":{"value":8},
    "340:330":{"value":736},
    "340:324":{"value":1280},
    "340:349":{"value":false}
  }' \
  -o /abs/output/dir --queue
```
Then, when done (auto-downloads outputs):
```bash
python3 scripts/comfy_run.py --status <PROMPT_ID> -o /abs/output/dir
```

### Pitfalls (learned the hard way)

1. **Never use `--prompt` on this workflow.** Auto-detection can't see the real prompt
   node (`340:319`, a frontend-only `PrimitiveStringMultiline`); `--prompt` writes to the
   **negative** `CLIPTextEncode` (`340:314`) instead. Always use `--override`.
2. **Dimensions must be multiples of 32.** LTX rounds down (720 → 704). For a "≥720p"
   deliverable use **736** or **768** on the short edge.
3. **Long jobs: `--queue` + `--status`.** The built-in WebSocket monitor times out at
   600 s; an LTX 22B run takes longer.
4. **Prompt-enhance off for digital-human footage.** `340:349=true` lets a local LLM
   rewrite the prompt and it tends to add camera moves/cuts. Set `false` and write the
   prompt yourself when you need a locked-off, single-shot talking head.
5. Duration is the **video** length; the audio is trimmed to it. Keep audio **longer**
   than the requested duration (e.g. 8.9 s audio → `duration: 8`) so the trim has margin.

### Known-good run (2026-09-22)

- In: woman portrait 512×1024 + `xiaoxiao_9s.mp3` (8.93 s), requested 720×1280 / 8 s
- Out: `704×1280`, 24 fps, `8.04 s`, H.264 + AAC 48 kHz stereo, ~8 min on the 4060 Ti
- ⚠️ An earlier 8 s / 720p **i2v** run had crashed ComfyUI on this box; the ia2v
  variant at 704×1280 / 8 s completed fine, so don't over-generalize that crash.

---

## Recipe: DUIX-ready talking-head clip

DUIX (digital-human modelling) requires this of its **input video**:

- ≥ 8 s, ≥ 720P, `mp4`/`mov`, **must have an audio track**, clear articulation,
- one person for the whole clip, face clearly visible & unobstructed,
- head upright (not tilted/turned), hands away from face/mouth/neck.

Use the ia2v recipe above with:

- `duration: 8` (→ 8.04 s at 24 fps) and audio **longer** than 8 s,
- short edge ≥ 720 → width `736`+ (portrait) so it isn't rounded below 720,
- `340:349: false`,
- a prompt that pins the constraints, e.g.:

> A young woman speaks directly to the camera with a warm natural expression, her mouth
> articulating clearly as she talks. She stays centered, head upright and facing forward,
> face fully visible and unobstructed, both hands out of frame. Subtle natural blinking
> and small head movement. Static locked-off camera, single continuous shot, no cuts.
> Soft studio lighting, sharp focus on the face, photorealistic.

Verify before handing off:
```bash
ffprobe -v error -show_entries format=duration,format_name \
  -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels \
  -of default=nw=1 out.mp4
```

---

## Other workflows in `workflow_dirs`

| Workflow | What it does |
|---|---|
| `video_ltx2_3_i2v.json` | LTX 2.3 image → video (no custom audio input) |
| `video_ltx2_3_i2v_480p.json` | Same, light 480p preset (safer on 16 GB VRAM) |
| `image_flux2_text_to_image_9b.json` | Flux text → image |
| `audio_ace_step_1_t2a_song.json` | AceStep text → song |
