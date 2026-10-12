---
name: reel-to-action
description: Watch a short-form video (Instagram reel or carousel, TikTok, YouTube Short, X video, or a local screen recording) the user sends, work out what it claims or teaches, and decide whether Claude can actually do it here with the tools available, then offer to execute it. Use whenever the user pastes an instagram.com/reel, instagram.com/p/, tiktok.com, youtube.com/shorts, x.com or twitter.com video link, or says "watch this reel", "can you do what this video says", "try this", "is this real", "can we build this".
---

# Reel to action

People scroll reels about AI, automation and tooling, and send them to find out: *what is this really saying, is it legit, and can you do it for me?*

## 1. Fetch and watch

Run the bundled script (in `scripts/` next to this file). Put the output in a temporary or scratch directory:

```bash
<skill-dir>/scripts/fetch_reel.sh -o "<scratch>/reel-<id>" "<url or local file>"
```

It downloads the media, transcribes it locally with whisper.cpp, samples key frames at scene changes, and prints the caption and transcript. It writes:

| File | What |
|---|---|
| `contact.jpg` | every key frame on one grid, in order |
| `frames/f_NN_<t>s.jpg` | individual frames with their timestamp |
| `transcript.txt` / `.srt` / `.vtt` | speech, plain and timestamped |
| `caption.txt`, `meta.json` | uploader, caption, duration, platform, paths |

Then:

- **Look at `contact.jpg` first.** On-screen text, prompts, code, terminal commands and UI screenshots often carry what the voice-over skips.
- Open single frames at full size only where you need to read a prompt, command or code exactly. The timestamp in the file name lines up with `transcript.srt`.
- The transcript is auto-generated. Fix obvious mishearings from context and the frames (for example "cloud" is often "Claude").
- If it says no speech was detected (music-only reel), work from the frames and the caption.

Useful options: `--lang de` when the language is known, `--model small` when the transcript looks garbled, `--max-frames 40` for dense tutorials, `--keep-video` if the user wants the file.

**If the download fails:**
1. Private post or login wall: retry with `--cookies-from-browser chrome` (or the browser the user is logged in with). Tell the user first, since it reads their browser cookies and may trigger a keychain prompt.
2. Still failing: update yt-dlp (`brew upgrade yt-dlp` or `pipx upgrade yt-dlp`).
3. Still failing: ask the user to screen-record the reel and give you the file, then run the script on the file path.

## 2. Distill

Write the reel's claim as a short, concrete recipe: goal, tools, steps, key prompts. Strip the engagement bait ("comment X and I'll DM you the guide") and say so when the substance is thin.

## 3. Feasibility check (actually check, don't guess)

For each step, check against this machine and session:
- CLI tools and packages: `which`, `npm ls -g`, `pip show`, the package manager.
- Claude Code capabilities: installed skills, MCP connectors, browser automation, subagents, scheduling.
- Accounts, API keys or paid services it needs that aren't set up.
- Hardware: RAM, GPU, disk, for anything that runs local models or renders video.

## 4. Report

Keep it short and in this shape:

```
**What the reel says:** 2–3 lines
**Verdict:** ✅ can do now / 🟡 can do after setup / ❌ can't (why)
**What it takes here:** installs, accounts, cost, time (bullets)
**Hype check:** what's overstated, missing or behind a "comment for the guide" wall
**Proposed first step:** one small concrete test, e.g. a 10-second render or a single automation run
```

Then ask whether to go ahead. Don't install packages, spend money, sign up for services or post anything before the user says yes. Once they agree, do it and show the actual result, not a description of it.

If the video describes a reusable workflow, offer to turn it into its own skill.

## 5. Clean up

The script deletes the downloaded media unless `--keep-video` was passed. Transcripts and frames are small; delete the output folder when done unless the user wants to keep them. Don't redistribute downloaded content.
