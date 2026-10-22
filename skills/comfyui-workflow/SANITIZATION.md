# SANITIZATION.md

This is a **local, sanitized fork** of the ClawHub skill
[`yiqiliu2/comfyui-workflow`](https://clawhub.ai/yiqiliu2/skills/comfyui-workflow)
(v1.1.0, which ClawHub flags as *suspicious* / "not clean").

Upstream files were pulled on 2026-09-22 via the ClawHub file API, edited locally, and
placed under `workspace/skills/comfyui-workflow/`. Changes below are the complete diff
in intent; no upstream logic that we rely on was altered.

## Removed / changed

### 1. Process spawning (was: High blast radius)
- Removed `import subprocess`.
- Removed `ensure_comfyui()`'s auto-start branch that ran
  `bash comfy_control.sh ensure` (and `STARTUP_TIMEOUT` / start-stop command config).
- `ensure_comfyui()` now **only probes** `http://<server>/` and prints a hint if the
  server is down. **The skill never starts or kills any process.**
- Removed `scripts/config.example.sh` (start/stop command templates, incl. PowerShell
  and `pkill` examples).

### 2. PowerShell / GPU host diagnostics
- Removed `_check_powershell_output()` (~100 lines) and the `--check-ps` flag.
  It invoked `powershell.exe` to enumerate processes, read the Windows event log and
  query `nvidia-smi` — far outside "run a ComfyUI workflow".
- Removed the pre-/post-execution hooks that called it.

### 3. Credentials sent in URL query strings
- Removed the `?token=...` / `&token=...` appends in `queue_prompt()`, `get_history()`,
  `download_file()` and the websocket URL in `run_workflow()`.
- The `token` argument is kept only for signature compatibility and is **ignored**.
  (We run against a loopback/LAN ComfyUI with no auth; a token-in-URL was never used.)

### 4. Unbounded directory walking
- Replaced three raw `os.walk()` loops with one bounded helper `_iter_workflow_files()`
  in `comfy_api.py`:
  - never leaves the given base directory,
  - skips hidden directories,
  - caps recursion depth at 4.
- Net effect: workflow discovery stays inside the configured `workflow_dirs`.

### 5. Instruction-level items (docs)
- Deleted `MODELS_INVENTORY.md` (persistent local model/path cache; also advertised
  "zero-shot voice cloning") and `WORKFLOWS_SUMMARY.md` (persistent workflow cache).
  The upstream SKILL.md explicitly told agents to write user environment data into
  these files across sessions — removed.
- Deleted packaging/marketing files: `README.md`, `skill-card.md`, `skill.json`.
- Deleted `GENERATION_RULES.md`, `PRACTICAL_GUIDE.md`, `references/maintenance.md`.
- Deleted the bundled example workflows (`workflows/*.json`, ~1.1 MB) and
  `workflows/format_json.py`; we point the skill at our own workflow directory.
- Rewrote `SKILL.md`: dropped the "scripts must not be modified" directive, the
  token/credentials sections, and the whole "Knowledge Cache Pattern" section; added
  an explicit file-access boundary and a pointer to this file.

## File-access boundary (post-sanitization)

The skill reads **only**:
- the workflow JSON you pass with `-w` (absolute path, or a name found under the
  configured `workflow_dirs`),
- the media files you pass with `--image` / `--audio` / `--video`,
- `scripts/config.json` (if present) and the `COMFY_HOST` / `COMFY_WORKFLOW_DIRS` env vars,
- optionally a JSON/YAML `--config` file that you pass.

The skill writes **only** into the `-o` output directory (outputs downloaded from the
ComfyUI server). It does not scan home directories, does not read credential files, and
makes network requests **only** to the configured ComfyUI server.

## Known residual notes (accepted)

- Plaintext `http://` / `ws://` to the ComfyUI server. Fine for loopback/LAN; do not
  expose ComfyUI to untrusted networks.
- Runtime dependency `websocket-client` is installed unpinned (`pip install --user`).
- Upstream `comfy_run.py` is ~2.3k lines; only the blocks above were touched.
