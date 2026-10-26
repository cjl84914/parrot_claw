# Use Cases

> This page walks through real scenarios to show what ParrotClaw can do and how to use it.
> Every case follows the same shape: the scenario → the steps → the result → tips for going further.

---

## Case 1: Code walkthrough — have an unfamiliar project explained to you {#case-1}

### The scenario

You have inherited an unfamiliar project, picked up a colleague's code, or want to revisit logic you wrote six months ago. The traditional route: list the directories → read files one by one → run it to see → dig through the docs. Hours of work, and it is easy to miss the important parts.

With ParrotClaw: **say "read this project" and let it handle the rest.**

### Before you start

🟢 **Nothing to configure.** Code walkthrough is a native OpenClaw capability — once the app is connected to OpenClaw, it works. No plugins, models or toolchains required.

> Note: the AI reads **files on the machine where OpenClaw runs**. With self-hosting, your code is only read and analysed on your own machine or intranet and **never leaves the network** — which matters if you work with sensitive code.

### Steps

1. Open the ParrotClaw app and go to the chat screen
2. Just tell it the project path:

   > "Read /Users/xxx/my_project and explain its architecture"

3. The agent analyses and reports back: tech stack, directory structure, core modules, entry points and key logic
4. Keep asking to go deeper:

   > "How exactly does the login function in user_service.dart work?"
   >
   > "Does this project have any obvious bugs or security issues?"

5. You can also skip the path and tap **+** → **File** to send it a code file ✅

### The result

- **Speed of understanding**: an unfamiliar project goes from hours to minutes
- **Zero setup**: no tooling to install, works out of the box
- **Versatile**: taking over legacy code, code review, learning from open-source projects — just ask

### Going further

- **Turn the walkthrough into a document**: have the AI write the architecture notes and save them to Youdao Note for later reference (see [Case 2](#case-2))
- **Code review**: ask the AI to look for performance problems, security issues and potential bugs — a free code review
- **Draw the architecture**: ask the AI to diagram the module relationships so you can see the whole project at a glance
- **Compare**: ask the AI to diff two similar projects or two versions to find what changed

---

## Case 2: Writing — from one sentence to a finished note {#case-2}

### The scenario

You are a content creator (independent media, product manager, indie developer) with an idea, and you want it turned into a well-structured article quickly — and **filed automatically into your own note system**, such as Youdao Note.

The traditional route: open the editor → outline → research → draft → format → copy and paste into the cloud note. At least half an hour.

With ParrotClaw: **say one sentence and let it handle the rest.**

### Before you start

Saving to Youdao Note requires the **Youdao Note CLI** and an API key (one-time setup):

**1. Install the CLI** (one-line install on macOS / Linux, no Node.js needed)

```bash
curl -fsSL https://artifact.lx.netease.com/download/youdaonote-cli/install.sh | bash
```

> On Windows, download the archive for your architecture from the [installation guide](https://note.youdao.com/help-center/cli-install-guide.html) and add it to your PATH.

**2. Get an API key**

Visit the [Youdao Note MCP console](https://mopen.163.com/#/dashboard) to get an API key (your account must have a phone number linked first).

**3. Configure the API key**

```bash
youdaonote config set apiKey YOUR_API_KEY
```

**4. Verify**

```bash
youdaonote list
```

If it lists your note folders, the setup worked.

**5. Install the skill**

```bash
openclaw skills install youdaonote
```

> Full instructions are in the [Youdao Note CLI installation guide](https://note.youdao.com/help-center/cli-install-guide.html).

### Steps

1. Open the ParrotClaw app and go to the chat screen
2. Describe what you want, for example:

   > "Write a 1,500-word article on how one-person companies use AI digital employees to work more efficiently. Audience: indie developers. Make it feel real, not fluffy."

3. Once the article is generated, tell it to file it:

   > "Save that article to Youdao Note, titled 'AI Digital Employees in Practice for One-Person Companies'"

4. Open Youdao Note — the article is already there ✅

### The result

- **Writing time**: from 30+ minutes to about 3
- **Everything is kept**: the article lands straight in your note library — searchable, reusable, editable
- **Easy to revise later**: say "change the second paragraph of that article" and it is done

### Going further

- **Batch output**: have the agent draft five topics at once and save each to a separate note
- **Style constraints**: tell the agent your house style, such as "always end with a call to action" or "use short sentences"
- **Publish in the same flow**: hand the finished article to the agent and publish it to Juejin as a draft, then make it public after review — see [Case 3](#case-3)

---

## Case 3: Publishing to Juejin {#case-3}

### The scenario

The article is written and you do not want to copy-paste it into the Juejin editor and format it again. Juejin supports Markdown, but doing it by hand is still tedious: open the editor → new post → paste → upload a cover → set tags…

With ParrotClaw: **publish with one sentence, saved as a draft by default, made public after you review it.**

### Before you start

Install the Juejin skill on the OpenClaw side (one-time):

```bash
openclaw skills install juejin-skills
```

The first time you use it, the AI opens a browser and takes you to the Juejin login page. **Scan the QR code once** and the cookie is stored locally, so you do not need to sign in again.

> See the [OpenClaw setup guide](openclaw-setup.md) for details.

### Steps

1. Open the ParrotClaw app and go to the chat screen
2. Just say:

   > "Publish article.md from the workspace to Juejin"

3. The agent does the rest: read the article → open the browser → sign in (first time) → upload the content → **save as a draft**
4. Check it in the Juejin dashboard and hit publish when you are happy ✅

### Useful commands

| Command | Effect |
|------|------|
| "Publish xxx.md from the workspace to Juejin" | Publishes that file as a draft |
| "Show me the trending posts on Juejin" | Browse popular Juejin content for ideas and reference |
| "Download this Juejin post: https://juejin.cn/post/xxx" | Saves someone else's post as Markdown for study |

### Going further

- **Write and publish in one go**: have the agent write the article, save it locally, then publish it — all through conversation
- **Extend to other platforms**: the same approach works for any platform with Skills support (blogs, official accounts, and more)

---

## Case 4: Audio and video processing (ffmpeg) {#case-4}

### The scenario

You have a video to turn into a GIF, an audio file to convert, or a clip to extract from a video — everyday content work. In the past that meant installing editing software or memorising ffmpeg commands; now you just ask the agent.

ParrotClaw's audio/video processing comes from the **ffmpeg** integration built into OpenClaw, and supports:

| Capability | Description |
|------|------|
| Format conversion | Video ↔ audio (mp4, mov, gif, mp3, wav, and more) |
| Video to GIF | Turn a clip into an animated GIF for demos or stickers |
| Audio extraction | Pull the audio track out of a video (mp3 / wav) |
| Trim / concatenate | Cut a segment, or merge several videos |
| Audio processing | Transcode, change sample rate, mono / stereo conversion |

### Before you start

Audio and video processing depends on **ffmpeg**, which must be installed on the machine running OpenClaw (one-time):

**macOS (the full build is recommended — includes speech recognition, subtitles and advanced codecs):**

```bash
brew tap homebrew-ffmpeg/ffmpeg
brew install ffmpeg-full
```

**Linux (Ubuntu / Debian):**

```bash
sudo apt update && sudo apt install ffmpeg
```

> Note: the ffmpeg in the official apt repositories is built without many features. The static builds from johnvansickle are a better choice — see the [OpenClaw setup guide](openclaw-setup.md).

Verify once it is installed:

```bash
ffmpeg -version
```

### Steps

1. Open the ParrotClaw app and go to the chat screen
2. Tap **+** → **File** and send the audio or video file
3. Say what you need:

   > "Turn this video into a GIF, first 5 seconds"
   >
   > "Extract the audio from this video and convert it to mp3"
   >
   > "Convert this recording to 44100 Hz mono wav"

4. The agent runs ffmpeg and sends the result back into the chat — tap to preview or save ✅

### Going further

- **Batch processing**: send several files at once and have the agent transcode them in a batch
- **Live2D audio format**: the digital human needs 44100 Hz / 16-bit / mono PCM WAV — ask the agent to transcode with ffmpeg before using it for read-aloud
- **Video generation**: pair it with a ComfyUI video workflow to generate video through conversation — see the [ComfyUI guide](comfyui-usage.md)

---

## Case 5: Text-to-image / image-to-image — a picture from one sentence {#case-5}

### The scenario

You need a product promo image, a cover, or an illustration — but you do not use Photoshop and do not want to hire a designer.

With ParrotClaw: **describe the picture and the AI produces it.** If you have a reference image, you can do image-to-image and change the style or the content from there.

### Before you start

Image generation is driven by **ComfyUI**, so first install ComfyUI on the machine running OpenClaw and prepare the image models (one-time):

- **Install ComfyUI** — clone the repo, install PyTorch, start the service
- **Prepare models** — the Flux text-to-image models (plus whatever image-to-image needs)
- **Configure the OpenClaw integration** — set up the ComfyUI workflow in `openclaw.json`

> Full instructions: [ComfyUI guide — installing](comfyui-usage.md#installing-comfyui) and [preparing models](comfyui-usage.md#preparing-models).

### Steps

**Option A: text-to-image (generate from scratch)**

1. Open the ParrotClaw app and go to the chat screen
2. Describe what you want:

   > "Draw an orange cat sitting on a windowsill, digital art style"

3. The agent calls the local ComfyUI to generate the image
4. The image appears in the chat — tap to enlarge ✅

**Option B: image-to-image (from a reference image)**

1. Tap **+** → **Album / Camera** and send a reference image
2. Describe the change:

   > "Give this person a beard and change the background to a window"

3. The agent generates a new image based on the reference, keeping the composition and style and applying your changes ✅

### What it can do

| Item | Description |
|------|------|
| Engine | ComfyUI (runs locally, never leaves your network) |
| Modes | Text-to-image / image-to-image |
| Hardware | 16 GB VRAM recommended (on the machine running ComfyUI) |
| How it is called | `image_generate` with `model="comfy/workflow"`, passing a prompt (plus an optional reference image) |

### Going further

- **Iterate**: if the result is not right, keep refining the prompt in conversation ("more photorealistic", "change the palette") until you are happy
- **Batch output**: describe several variants at once and pick the best
- **Build a pipeline**: generate → [process with ffmpeg](#case-4) to convert format or size → use it in articles, posters or video covers

---

## Case 6: Text-to-song — write a song with words {#case-6}

### The scenario

You need background music, a demo track, or a jingle, but you do not compose. In the past that meant hiring an arranger, buying a licence, or wrestling with a DAW.

With ParrotClaw: **describe the style in words and the AI generates a song.**

### Before you start

Music generation is driven by **ComfyUI + the AceStep model**, so complete the following first (one-time):

- **Install ComfyUI** — clone the repo, install PyTorch, start the service
- **Prepare the AceStep model** — the T2A model files for text-to-song
- **Configure the OpenClaw integration** — set up the music workflow in `openclaw.json`

> Full instructions: [ComfyUI guide — installing](comfyui-usage.md#installing-comfyui) and [preparing models — music generation](comfyui-usage.md#2-music-generation-acestep-t2a).

### Steps

1. Open the ParrotClaw app and go to the chat screen
2. Describe the music you want:

   > "Generate a song, rock style, something like Beyond, electric guitar driven, upbeat"

3. The agent runs ComfyUI's AceStep text-to-song workflow
4. When it finishes, the audio comes back into the chat — tap to play or save ✅

### What it can do

| Item | Description |
|------|------|
| Model | AceStep (text to audio song) |
| Input | A style description (genre, instruments, mood, reference style) |
| Output | MP3 audio |
| Example style | "Rock, Beyond style, electric guitar..." |

### Current limitations

- **Lyrics must be configured in advance**: the lyrics live in the ComfyUI workflow file, so changing them currently means editing that file outside the conversation. Sending new lyrics from the chat is not supported yet — to change them, edit the workflow JSON.

### Going further

- **The more specific the style, the better**: genre + reference band + instruments + tempo gets you closer to what you want
- **Combine tools**: run the generated track through [ffmpeg](#case-4) to convert or trim it, then use it for video scoring, podcast intros, and so on

---

## Case 7: Meeting notes — recording in, minutes out {#case-7}

> 🧪 This case is written from the feature design; the full walkthrough will be updated once the author has tested it end to end.

### The scenario

You have just finished a one-hour meeting and there is a recording on your phone — or you are in the meeting right now. In the past you would:

1. Listen back to the recording (1 hour)
2. Write up the key points by hand (30 minutes)
3. Turn it into minutes and send it to colleagues (15 minutes)

With ParrotClaw: **say "start meeting notes" and let it handle the rest** — recording, transcription, summarising and filing, all automatic.

### Before you start

Filing to Feishu Docs requires the Feishu plugin (one-time):

```bash
openclaw plugins install npm:@openclaw/feishu
```

Then fill in your Feishu app's **App ID / App Secret** in the OpenClaw configuration. Once the plugin is enabled you can create Feishu docs through conversation.

> See the [OpenClaw setup guide](openclaw-setup.md) for details.

### Steps

1. Open the ParrotClaw app and go to the chat screen
2. Say:

   > "Start meeting notes"

3. The agent starts recording — just run your meeting as usual
4. When it ends, say:

   > "End the meeting and turn it into minutes"

5. The agent does the rest: speech to text → structured summary → minutes ✅
6. To file it, add:

   > "Save the minutes to Feishu Docs, titled 'Project XX weekly sync — Aug 10'"

7. The minutes are in Feishu, ready to share with the people who were there ✅

### What the minutes look like

An example of the structured output:

```markdown
# Project XX weekly sync (2026-08-10)

## Attendees
Alex, Xiao Lin, Wang

## Topics
1. ParrotClaw 1.0 launch metrics review
2. Prioritising the use-case documentation

## Key decisions
- App Store listing is live; the website and GitHub open-source release are both done
- Shipping scenarios takes priority over internationalisation — finish the "writing + meeting notes" loop first

## Action items
| Item | Owner | Due |
|------|--------|----------|
| Finish the use-case documentation | Alex | This week |
| Validate the Feishu doc sharing flow | Alex | This week |

## Next meeting
Aug 17, 10:00
```

### The result

- **Summarising time**: from 1.5 hours to 5 minutes
- **Nothing missed**: the AI does not lose focus while listening back
- **Filed automatically**: minutes go straight into Feishu or your knowledge base and become company assets

### Going further

- **Use a template**: tell the agent the minutes format you like once, and it will follow it for every meeting
- **Knowledge base integration**: once filed, just ask "what were the action items from last meeting?" and the AI will look them up
- **Multiple recordings**: several meetings in a day? Send them one at a time and the agent will produce separate minutes for each

---

## Case 8: Text-to-video / image-to-video {#case-8}

> 🚧 **Coming soon** — this feature is in development and will ship shortly.
> Generate video from text or an image: promo clips, animated wallpapers and short-video footage in one step.

---

## Planned cases

These cases are on the roadmap; the full setup, steps and results will be added once they have been validated:

- [ ] **Digital human case** — showing voice interaction and conversation with the Live2D digital human
- [ ] **FaceFusion case** — showing how FaceFusion is used for face swapping and face merging

## More scenarios

- **Knowledge Q&A assistant** — ask questions against your company's knowledge base
- **Content creation** — text-to-image, image-to-image, speech synthesis, video generation

### 🚧 More features in progress…

Digital-human conversation, multi-model switching, deeper knowledge-base Q&A, video generation… more capabilities are on the way.

### 💡 We would love to hear what you find

ParrotClaw can do far more than what is listed here — you may well discover uses we never thought of. If you find something interesting, or there is a feature you want, tell us: your idea could be in the next release.

---

**Contact us:**

- QQ: 121237385
- Email: 121237385@qq.com
- Project: [https://github.com/cjl84914/parrot_claw](https://github.com/cjl84914/parrot_claw)
