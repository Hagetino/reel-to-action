#!/usr/bin/env bash
# fetch_reel.sh: turn a short-form video into something an LLM can "watch".
#
# Downloads a reel / TikTok / YouTube Short / X video (or takes a local file),
# then writes, all locally:
#   transcript.txt / .srt / .vtt   speech-to-text via whisper.cpp
#   frames/                        key frames (scene changes, interval fallback)
#   contact.jpg                    every frame on one grid image
#   caption.txt, meta.json         caption, uploader, duration, file paths
#
# Run with --help for options.
set -euo pipefail

VERSION="1.0.0"
MODEL="base"
LANG_CODE="auto"
MAX_FRAMES=24
SCENE=0.3
OUT=""
KEEP_VIDEO=0
COOKIES_BROWSER=""
DO_FRAMES=1
DO_TRANSCRIPT=1
QUIET=0
INPUT=""
MODEL_DIR="${WHISPER_MODEL_DIR:-$HOME/.cache/whisper-cpp}"

usage() {
  cat <<EOF
fetch_reel.sh $VERSION: download, transcribe and sample frames from a short video.

Usage: fetch_reel.sh [options] <url | local-video-file>

Options:
  -o, --out DIR                  output directory (default: \$TMPDIR/reel-<id>)
  -m, --model NAME               whisper model: tiny | base | small | medium | large-v3-turbo
                                 (default: base; .en variants such as base.en also work)
  -l, --lang CODE                spoken language, e.g. en, de, pt (default: auto)
  -n, --max-frames N             max key frames per video (default: 24)
  -s, --scene T                  scene-change threshold 0..1 (default: 0.3, lower = more frames)
  -k, --keep-video               keep the downloaded media (deleted by default)
  -c, --cookies-from-browser B   use your browser login, for private posts or login walls
                                 (chrome, firefox, safari, brave, edge, ...)
      --no-frames                skip frame extraction
      --no-transcript            skip transcription
  -q, --quiet                    print only the output directory
  -h, --help                     show this help
  -V, --version                  show version

Supports anything yt-dlp supports: Instagram reels/posts/carousels, TikTok,
YouTube Shorts, X/Twitter, and more. Everything runs on your machine.
EOF
}

die()  { echo "error: $*" >&2; exit 1; }
log()  { [ "$QUIET" = 1 ] || echo "$*" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out)                  OUT="${2:?--out needs a value}"; shift 2 ;;
    -m|--model)                MODEL="${2:?--model needs a value}"; shift 2 ;;
    -l|--lang)                 LANG_CODE="${2:?--lang needs a value}"; shift 2 ;;
    -n|--max-frames)           MAX_FRAMES="${2:?--max-frames needs a value}"; shift 2 ;;
    -s|--scene)                SCENE="${2:?--scene needs a value}"; shift 2 ;;
    -k|--keep-video)           KEEP_VIDEO=1; shift ;;
    -c|--cookies-from-browser) COOKIES_BROWSER="${2:?--cookies-from-browser needs a value}"; shift 2 ;;
    --no-frames)               DO_FRAMES=0; shift ;;
    --no-transcript)           DO_TRANSCRIPT=0; shift ;;
    -q|--quiet)                QUIET=1; shift ;;
    -h|--help)                 usage; exit 0 ;;
    -V|--version)              echo "$VERSION"; exit 0 ;;
    --)                        shift; INPUT="${1:-}"; shift || true ;;
    -*)                        die "unknown option: $1 (see --help)" ;;
    *)                         [ -z "$INPUT" ] || die "only one input allowed"; INPUT="$1"; shift ;;
  esac
done
[ -n "$INPUT" ] || { usage >&2; exit 2; }
case "$MAX_FRAMES" in ''|*[!0-9]*) die "--max-frames must be a number" ;; esac
[ "$MAX_FRAMES" -ge 1 ] || die "--max-frames must be at least 1"

# ---------------------------------------------------------------- dependencies
hint() { # tool brew-pkg apt-pkg
  if [ "$(uname)" = Darwin ]; then echo "brew install $2"
  elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt-get install $3"
  else echo "install $1 with your package manager"; fi
}
missing=()
LOCAL=0; [ -f "$INPUT" ] && LOCAL=1
[ "$LOCAL" = 1 ] || command -v yt-dlp >/dev/null 2>&1 || missing+=("yt-dlp  ->  $(hint yt-dlp yt-dlp yt-dlp)  (or: pipx install yt-dlp)")
command -v ffmpeg  >/dev/null 2>&1 || missing+=("ffmpeg  ->  $(hint ffmpeg ffmpeg ffmpeg)")
command -v ffprobe >/dev/null 2>&1 || missing+=("ffprobe ->  $(hint ffprobe ffmpeg ffmpeg)")
command -v python3 >/dev/null 2>&1 || missing+=("python3 ->  $(hint python3 python python3)")
WHISPER=""
if [ "$DO_TRANSCRIPT" = 1 ]; then
  for b in whisper-cli whisper-cpp whisper.cpp; do
    if command -v "$b" >/dev/null 2>&1; then WHISPER="$b"; break; fi
  done
  [ -n "$WHISPER" ] || missing+=("whisper-cli -> $( [ "$(uname)" = Darwin ] && echo 'brew install whisper-cpp' || echo 'build from https://github.com/ggml-org/whisper.cpp')  (or use --no-transcript)")
fi
if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing dependencies:" >&2
  for m in "${missing[@]}"; do echo "  $m" >&2; done
  exit 3
fi

# ---------------------------------------------------------------- output dir
if [ -z "$OUT" ]; then
  if [ "$LOCAL" = 1 ]; then id="$(basename "$INPUT")"; id="${id%.*}"
  else id="$(printf '%s' "$INPUT" | sed -E 's#[?#].*##; s#/+$##; s#.*/##')"; fi
  id="$(printf '%s' "$id" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-40)"
  OUT="${TMPDIR:-/tmp}"; OUT="${OUT%/}/reel-${id:-$(date +%s)}"
fi
mkdir -p "$OUT/media"
rm -rf "$OUT/frames"; mkdir -p "$OUT/frames"
rm -f "$OUT"/transcript*.txt "$OUT"/transcript*.srt "$OUT"/transcript*.vtt "$OUT/contact.jpg"

# ---------------------------------------------------------------- download
if [ "$LOCAL" = 1 ]; then
  ext="${INPUT##*.}"
  cp "$INPUT" "$OUT/media/01.$ext"
  log "Using local file $INPUT"
else
  rm -f "$OUT"/media/*
  log "Downloading $INPUT ..."
  ytargs=(--no-warnings --no-progress --yes-playlist --no-write-playlist-metafiles
          --write-info-json --restrict-filenames --playlist-items 1:20
          -f "bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b" --merge-output-format mp4
          -o "$OUT/media/%(autonumber)02d.%(ext)s")
  [ -n "$COOKIES_BROWSER" ] && ytargs+=(--cookies-from-browser "$COOKIES_BROWSER")
  [ "$QUIET" = 1 ] && ytargs+=(-q)
  if ! yt-dlp "${ytargs[@]}" "$INPUT" >&2; then
    echo >&2
    echo "Download failed. Common causes:" >&2
    echo "  - private post or login wall: retry with --cookies-from-browser chrome (or firefox/safari)" >&2
    echo "  - image-only post: yt-dlp can't fetch some photo posts; screenshot them instead" >&2
    echo "  - outdated yt-dlp: platforms change often, update it (brew upgrade yt-dlp / pipx upgrade yt-dlp)" >&2
    echo "  - no access: screen-record the video and pass the file path instead of the URL" >&2
    exit 4
  fi
fi

# ---------------------------------------------------------------- per item
has_audio()   { [ -n "$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$1" 2>/dev/null)" ]; }
has_video()   { ffprobe -v error -select_streams v -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null | grep -qvE '^(mjpeg|png|webp|bmp|gif)?$'; }
duration_of() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null | sed 's/N\/A//'; }

model_file() {
  local f="$MODEL_DIR/ggml-$MODEL.bin"
  if [ ! -s "$f" ]; then
    mkdir -p "$MODEL_DIR"
    log "Downloading whisper model '$MODEL' to $MODEL_DIR (one-time) ..."
    curl -fL --progress-bar -o "$f.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin" >&2 \
      || { rm -f "$f.part"; die "could not download model '$MODEL' (valid: tiny, base, small, medium, large-v3-turbo, *.en)"; }
    mv "$f.part" "$f"
  fi
  echo "$f"
}

# frames: scene changes (always incl. first frame); if too few, fixed interval; then cap evenly.
extract_frames() { # video prefix duration
  local v="$1" p="$2" dur="$3" tmp="$OUT/frames/.tmp" n
  rm -rf "$tmp"; mkdir -p "$tmp"
  ffmpeg -hide_banner -nostdin -y -i "$v" \
    -vf "select='eq(n\,0)+gt(scene\,$SCENE)',showinfo,scale=540:-2" -fps_mode vfr -q:v 3 \
    "$tmp/%04d.jpg" 2>"$tmp/log" || true
  n=$(find "$tmp" -name '*.jpg' | wc -l | tr -d ' ')
  local want=$(( MAX_FRAMES < 6 ? MAX_FRAMES : 6 ))
  if [ "$n" -lt "$want" ] && [ -n "$dur" ]; then
    rm -f "$tmp"/*.jpg
    local every
    every=$(python3 -c "import sys; d=float(sys.argv[1]); print(max(1.0, d/int(sys.argv[2])))" "$dur" "$MAX_FRAMES")
    ffmpeg -hide_banner -nostdin -y -i "$v" -vf "fps=1/$every,showinfo,scale=540:-2" -q:v 3 \
      "$tmp/%04d.jpg" 2>"$tmp/log" || true
  fi
  # pair files with timestamps, keep at most MAX_FRAMES spread evenly, rename to f_<prefix>NN_<t>s.jpg
  python3 - "$tmp" "$OUT/frames" "$p" "$MAX_FRAMES" <<'PY'
import os, re, sys, shutil
tmp, dst, prefix, cap = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
times = [float(m) for m in re.findall(r"pts_time:\s*([0-9.]+)", open(os.path.join(tmp, "log")).read())]
files = sorted(f for f in os.listdir(tmp) if f.endswith(".jpg"))
pairs = [(f, times[i] if i < len(times) else None) for i, f in enumerate(files)]
if len(pairs) > cap:
    step = (len(pairs) - 1) / (cap - 1) if cap > 1 else 0
    pairs = [pairs[round(i * step)] for i in range(cap)]
for i, (f, t) in enumerate(pairs, 1):
    stamp = f"_{t:06.1f}s" if t is not None else ""
    shutil.move(os.path.join(tmp, f), os.path.join(dst, f"f_{prefix}{i:02d}{stamp}.jpg"))
PY
  rm -rf "$tmp"
}

transcribe() { # media out-basename
  local wav="$OUT/.audio.wav" model
  model="$(model_file)"
  ffmpeg -hide_banner -nostdin -loglevel error -y -i "$1" -vn -ar 16000 -ac 1 "$wav"
  "$WHISPER" -m "$model" -l "$LANG_CODE" -np -otxt -osrt -ovtt -of "$2" -f "$wav" >/dev/null 2>"$OUT/.whisper.log" \
    || { echo "warning: transcription failed, see $OUT/.whisper.log" >&2; }
  rm -f "$wav"
}

shopt -s nullglob
items=()
for f in "$OUT"/media/*; do
  case "$f" in *.info.json|*.part|*.ytdl) continue ;; esac
  items+=("$f")
done
[ ${#items[@]} -gt 0 ] || die "nothing was downloaded"
multi=0; [ ${#items[@]} -gt 1 ] && multi=1

ITEMS_TSV="$OUT/.items.tsv"; : > "$ITEMS_TSV"
idx=0
for f in "${items[@]}"; do
  idx=$((idx + 1))
  num=$(printf '%02d' "$idx")
  prefix=""; [ "$multi" = 1 ] && prefix="${num}_"
  tbase="$OUT/transcript"; [ "$multi" = 1 ] && tbase="$OUT/transcript_$num"
  if has_video "$f"; then
    kind=video; dur="$(duration_of "$f")"; audio=no
    log "[$idx/${#items[@]}] video, ${dur%.*}s"
    [ "$DO_FRAMES" = 1 ] && extract_frames "$f" "$prefix" "$dur"
    if has_audio "$f"; then
      audio=yes
      if [ "$DO_TRANSCRIPT" = 1 ]; then log "    transcribing ($MODEL) ..."; transcribe "$f" "$tbase"; fi
    else
      log "    no audio track, skipping transcription"
    fi
  else
    kind=image; dur=""; audio=no
    log "[$idx/${#items[@]}] image"
    ffmpeg -hide_banner -nostdin -loglevel error -y -i "$f" -vf "scale=540:-2" -frames:v 1 "$OUT/frames/f_${prefix}01.jpg"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$kind" "$dur" "$audio" "$tbase" >> "$ITEMS_TSV"
done

# ---------------------------------------------------------------- contact sheet
frames=("$OUT"/frames/*.jpg)
if [ ${#frames[@]} -gt 0 ]; then
  # tile shape follows the first frame: portrait reels 240x426 in rows of 6, landscape 426x240 in rows of 4
  dims=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "${frames[0]}" 2>/dev/null || echo "9x16")
  if [ "${dims%x*}" -gt "${dims#*x}" ] 2>/dev/null; then tw=426; th=240; maxc=4; else tw=240; th=426; maxc=6; fi
  cols=$(( ${#frames[@]} < maxc ? ${#frames[@]} : maxc ))
  rows=$(( (${#frames[@]} + cols - 1) / cols ))
  # normalise every tile to one size so mixed aspect ratios still tile
  ffmpeg -hide_banner -nostdin -loglevel error -y -pattern_type glob -i "$OUT/frames/*.jpg" \
    -vf "scale=${tw}:${th}:force_original_aspect_ratio=decrease,pad=${tw}:${th}:(ow-iw)/2:(oh-ih)/2:color=black,tile=${cols}x${rows}:padding=4:margin=4" \
    -frames:v 1 -q:v 3 "$OUT/contact.jpg" || echo "warning: contact sheet failed" >&2
fi

# ---------------------------------------------------------------- meta.json + caption
python3 - "$OUT" "$INPUT" "$LOCAL" "$MODEL" "$KEEP_VIDEO" <<'PY'
import glob, json, os, re, sys
out, src, local, model, keep = sys.argv[1], sys.argv[2], sys.argv[3] == "1", sys.argv[4], sys.argv[5] == "1"
info = {}
for j in sorted(glob.glob(os.path.join(out, "media", "*.info.json"))):
    info = json.load(open(j)); break

def clean(t):  # drop whisper's non-speech markers like [Music] or (upbeat music)
    lines = [re.sub(r"\[[^\]]*\]|\([^)]*\)|♪", "", l).strip() for l in t.splitlines()]
    return "\n".join(l for l in lines if l)

items, speech = [], []
for line in open(os.path.join(out, ".items.tsv")):
    path, kind, dur, audio, tbase = line.rstrip("\n").split("\t")
    item = {"type": kind, "duration": float(dur) if dur else None, "has_audio": audio == "yes",
            "media": path if keep else None}
    if os.path.exists(tbase + ".txt"):
        text = open(tbase + ".txt").read()
        item["transcript"] = {ext: tbase + "." + ext for ext in ("txt", "srt", "vtt")}
        item["speech_detected"] = bool(clean(text))
        if clean(text): speech.append(clean(text))
    items.append(item)

frames = []
for f in sorted(glob.glob(os.path.join(out, "frames", "*.jpg"))):
    m = re.search(r"_(\d+\.\d)s\.jpg$", f)
    frames.append({"file": f, "t": float(m.group(1)) if m else None})

meta = {
    "source": src,
    "local_file": local,
    "url": info.get("webpage_url") or (None if local else src),
    "platform": info.get("extractor_key"),
    "id": info.get("id"),
    "uploader": info.get("uploader") or info.get("channel") or info.get("uploader_id"),
    "title": info.get("title"),
    "caption": info.get("description"),
    "upload_date": info.get("upload_date"),
    "duration": info.get("duration") or sum(i["duration"] or 0 for i in items) or None,
    "view_count": info.get("view_count"),
    "like_count": info.get("like_count"),
    "items": items,
    "speech_detected": bool(speech),
    "whisper_model": model,
    "frames": frames,
    "contact_sheet": os.path.join(out, "contact.jpg") if os.path.exists(os.path.join(out, "contact.jpg")) else None,
}
json.dump(meta, open(os.path.join(out, "meta.json"), "w"), indent=2, ensure_ascii=False)
with open(os.path.join(out, "caption.txt"), "w") as c:
    for k in ("platform", "uploader", "url", "upload_date", "duration"):
        c.write(f"{k}: {meta[k]}\n")
    c.write("caption:\n" + (meta["caption"] or "(none)") + "\n")
if len(items) > 1:  # combined transcript for multi-video posts
    parts = sorted(glob.glob(os.path.join(out, "transcript_*.txt")))
    if parts:
        with open(os.path.join(out, "transcript.txt"), "w") as t:
            for p in parts: t.write(f"=== {os.path.basename(p)}\n{open(p).read().strip()}\n\n")
PY

[ "$KEEP_VIDEO" = 1 ] || rm -f "$OUT"/media/*.mp4 "$OUT"/media/*.webm "$OUT"/media/*.mkv "$OUT"/media/*.mov "$OUT"/media/*.m4a "$OUT"/media/*.jpg "$OUT"/media/*.png "$OUT"/media/*.webp
rm -f "$ITEMS_TSV" "$OUT/.whisper.log"

# ---------------------------------------------------------------- summary
if [ "$QUIET" = 1 ]; then echo "$OUT"; exit 0; fi
echo "OUT=$OUT"
echo "--- caption"; cat "$OUT/caption.txt"
echo "--- transcript"
if [ -f "$OUT/transcript.txt" ]; then
  if python3 -c "import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))['speech_detected'] else 1)" "$OUT/meta.json"; then
    cat "$OUT/transcript.txt"; echo
  else
    echo "(no speech detected: music-only or silent video; rely on the frames and caption)"
  fi
elif [ "$DO_TRANSCRIPT" = 1 ]; then
  echo "(no audio to transcribe)"
else
  echo "(skipped)"
fi
echo "--- frames ($(find "$OUT/frames" -name '*.jpg' | wc -l | tr -d ' '))"
[ -f "$OUT/contact.jpg" ] && echo "contact sheet: $OUT/contact.jpg"
echo "meta: $OUT/meta.json"
