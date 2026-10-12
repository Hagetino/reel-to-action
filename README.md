# reel-to-action

**Send Claude a reel. It watches it, tells you what it actually says, and whether it can do it for you.**

A [Claude Code](https://claude.com/claude-code) skill for the "I saw this AI hack on Instagram, can we do this?" moment. Paste an Instagram reel, TikTok, YouTube Short or X video link and Claude:

1. **downloads** it with [yt-dlp](https://github.com/yt-dlp/yt-dlp),
2. **transcribes** it locally with [whisper.cpp](https://github.com/ggml-org/whisper.cpp), with timestamps,
3. **looks at** key frames picked at scene changes, so it catches on-screen prompts, code and UI that the voice-over skips,
4. **distills** the claim into a concrete recipe and cuts the engagement bait,
5. **checks** your machine and its own tools to see what is really possible,
6. gives you a verdict (✅ can do now / 🟡 after setup / ❌ can't) plus a hype check, and **asks before doing anything**.

Everything runs on your machine. No API keys, no upload service.

The script also works on its own, without Claude, if you just want transcripts and frames from short videos.

## Demo

```
> https://www.instagram.com/reel/XXXXXXXX/

$ fetch_reel.sh -o /tmp/reel-XXXXXXXX https://www.instagram.com/reel/XXXXXXXX/
--- caption
platform: Instagram
uploader: some creator
duration: 54.7
caption:
How to make a motion design studio with Claude #ai #tech
--- transcript
Most people don't realize that the insane AI motion graphics videos all over your feed are not just one prompt.
...
Install node, ffmpeg, and playwright ...
--- frames (19)
contact sheet: /tmp/reel-XXXXXXXX/contact.jpg
meta: /tmp/reel-XXXXXXXX/meta.json
```

Claude then replies along these lines:

> **What the reel says:** Claude doesn't make video, it writes code that draws every frame; Playwright captures the frames, ffmpeg stitches them. Feed it real assets, spring physics, beat-locked cuts, and let it grade its own frames.
> **Verdict:** 🟡 can do after setup: Node and ffmpeg are here, Playwright isn't.
> **Hype check:** "$2–3k per video" is the hook, not shown; the actual guide is behind "comment MOTION".
> **Proposed first step:** install Playwright in a scratch folder and render a 10-second title card. Go ahead?

Output folder:

```
reel-XXXXXXXX/
├── caption.txt          uploader, url, date, duration, caption
├── meta.json            everything above + per-item info + frame list with timestamps
├── transcript.txt       plain text
├── transcript.srt       timestamped
├── transcript.vtt
├── contact.jpg          all key frames on one grid
└── frames/
    ├── f_01_0000.0s.jpg
    ├── f_02_0004.4s.jpg
    └── ...
```

## Install

### Requirements

| Tool | macOS | Debian/Ubuntu |
|---|---|---|
| yt-dlp | `brew install yt-dlp` | `pipx install yt-dlp` (apt's version is often too old) |
| ffmpeg (≥ 5.1) | `brew install ffmpeg` | `sudo apt install ffmpeg` |
| whisper.cpp | `brew install whisper-cpp` | [build from source](https://github.com/ggml-org/whisper.cpp#quick-start) and put `whisper-cli` on your PATH |
| python3 | preinstalled | `sudo apt install python3` |

The whisper model (`base`, 148 MB) downloads itself to `~/.cache/whisper-cpp/` on first run. Set `WHISPER_MODEL_DIR` to put it somewhere else.

### As a Claude Code plugin

```
/plugin marketplace add Hagetino/reel-to-action
/plugin install reel-to-action@reel-to-action
```

### As a plain skill

```bash
git clone https://github.com/Hagetino/reel-to-action
mkdir -p ~/.claude/skills
cp -r reel-to-action/skills/reel-to-action ~/.claude/skills/
```

Restart Claude Code, then just paste a link. You can also type `/reel-to-action <link>`.

## Using the script directly

```bash
skills/reel-to-action/scripts/fetch_reel.sh [options] <url | local-video-file>
```

| Option | Default | |
|---|---|---|
| `-o, --out DIR` | `$TMPDIR/reel-<id>` | output folder |
| `-m, --model NAME` | `base` | `tiny`, `base`, `small`, `medium`, `large-v3-turbo`, or `.en` variants |
| `-l, --lang CODE` | `auto` | spoken language (`en`, `de`, `pt`, ...) |
| `-n, --max-frames N` | `24` | cap on key frames per video |
| `-s, --scene T` | `0.3` | scene-change threshold; lower gives more frames |
| `-k, --keep-video` | off | keep the downloaded media |
| `-c, --cookies-from-browser B` | off | use your browser login (`chrome`, `firefox`, `safari`, ...) |
| `--no-frames`, `--no-transcript` | | skip a step |
| `-q, --quiet` | | print only the output folder |

What it handles:

- **Reels, Shorts, TikToks, X videos**, plus anything else yt-dlp supports.
- **Carousels and multi-video posts:** each item gets its own frames and transcript (`transcript_01.txt`, ...) plus a combined `transcript.txt`. Capped at 20 items.
- **Image posts:** images go straight into `frames/`; transcription is skipped.
- **Music-only or silent videos:** reported as "no speech detected" instead of a transcript full of `[Music]`.
- **Local files:** pass a screen recording or downloaded video instead of a URL.
- **Frame sampling:** scene changes first (always including the first frame). If a video has fewer than 6 cuts, it falls back to evenly spaced frames. The result is thinned evenly to `--max-frames`.

## Privacy and legal

- Everything runs locally. Media goes from the platform to your disk to whisper.cpp on your machine. Nothing is uploaded anywhere. Claude sees the transcript and frames in your session, as with any file you show it.
- Downloaded media is deleted after processing unless you pass `--keep-video`.
- Only download content you're allowed to access, and follow each platform's terms of service. This tool is for personal analysis of videos you were sent or found, not for re-uploading or redistributing other people's work.
- `--cookies-from-browser` reads your browser's cookies locally so yt-dlp can act as your logged-in session. Use it only on your own machine and account.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Download failed` on Instagram | Private post or login wall: `--cookies-from-browser chrome`. Instagram changes often, so also update yt-dlp. |
| `Requested format is not available` / extractor errors | `brew upgrade yt-dlp` or `pipx upgrade yt-dlp` |
| Photo post won't download | yt-dlp can't fetch some image-only posts. Screenshot them and give Claude the images. |
| Nothing works for that link | Screen-record the video and pass the file: `fetch_reel.sh ~/Desktop/recording.mov` |
| Garbled transcript | `--model small` (slower, better) or set `--lang` |
| Wrong language transcribed | `--lang <code>`; auto-detection can struggle on short clips with music |
| `Unrecognized option 'fps_mode'` | ffmpeg is older than 5.1, so upgrade it |
| macOS keychain prompt | Expected with `--cookies-from-browser chrome`, because Chrome encrypts its cookies |

## License

MIT © Lukas Hager
