#!/bin/bash
# Shared helpers for `speak` and `speakd`. Sourced, never executed.

speak_load_config() {
  local config="${XDG_CONFIG_HOME:-$HOME/.config}/speak/config"
  [[ -r $config ]] && . "$config"

  SPEAK_VOICE="${SPEAK_VOICE:-en_US-lessac-medium}"
  SPEAK_VOICES_DIR="${SPEAK_VOICES_DIR:-$HOME/.local/share/piper/voices}"
  SPEAK_LENGTH_SCALE="${SPEAK_LENGTH_SCALE:-1.0}"
  SPEAK_SPEAKER="${SPEAK_SPEAKER:-0}"
  SPEAK_NOISE_SCALE="${SPEAK_NOISE_SCALE:-0.667}"
  SPEAK_NOISE_W="${SPEAK_NOISE_W:-0.8}"
  SPEAK_SENTENCE_SILENCE="${SPEAK_SENTENCE_SILENCE:-0.2}"
  SPEAK_MAX_CHARS="${SPEAK_MAX_CHARS:-1200}"

  SPEAK_RUNTIME="${XDG_RUNTIME_DIR:-/tmp/speak-$UID}/speakd"
  SPEAK_SPOOL="$SPEAK_RUNTIME/spool"
  SPEAK_PIDFILE="$SPEAK_RUNTIME/playing.pid"
  mkdir -p "$SPEAK_SPOOL" "$SPEAK_RUNTIME/tmp"
}

# Prefer a system-packaged piper, fall back to the user-level copy.
speak_piper_bin() {
  local candidate
  for candidate in piper-tts piper; do
    command -v "$candidate" 2>/dev/null && return 0
  done
  if [[ -x $HOME/.local/share/piper/bin/piper ]]; then
    echo "$HOME/.local/share/piper/bin/piper"
    return 0
  fi
  return 1
}

speak_model() {
  local voice="${1:-$SPEAK_VOICE}"
  local model="$SPEAK_VOICES_DIR/$voice.onnx"
  [[ -r $model ]] || return 1
  echo "$model"
}

# Flatten text written for eyes into text that survives being read aloud.
speak_clean() {
  sed -e 's/```[^`]*```/ code block /g' \
      -e 's/`\([^`]*\)`/\1/g' \
      -e 's|https\?://[^ ]*| link |g' \
      -e 's/^[[:space:]]*[-*+][[:space:]]\+/ /' \
      -e 's/^[[:space:]]*#\+[[:space:]]*//' \
      -e 's/\*\*\([^*]*\)\*\*/\1/g' \
      -e 's/[*_#>|]//g' |
  tr '\n' ' ' |
  tr -s '[:space:]' ' ' |
  sed -e 's/^ *//' -e 's/ *$//' |
  cut -c "1-${SPEAK_MAX_CHARS}"
}

# How many voices a multi-speaker model carries (1 for a single-speaker model).
speak_speaker_count() {
  local model
  model="$(speak_model "${1:-$SPEAK_VOICE}")" || return 1
  jq -r '.num_speakers // 1' "$model.json" 2>/dev/null || echo 1
}

# Synthesize and play one utterance, blocking until it finishes.
# Runs in its own process group so `speak stop` can kill the whole pipeline.
speak_play() {
  local text="$1" voice="${2:-$SPEAK_VOICE}" speaker="${3:-$SPEAK_SPEAKER}"
  local piper model rate
  piper="$(speak_piper_bin)" || { echo "speak: piper not found" >&2; return 1; }
  model="$(speak_model "$voice")" || { echo "speak: voice '$voice' not installed" >&2; return 1; }
  rate="$(jq -r '.audio.sample_rate // 22050' "$model.json" 2>/dev/null || echo 22050)"

  setsid bash -c '
    printf "%s" "$1" | "$2" -m "$3" -q --output_raw \
      --speaker "$5" --length_scale "$6" --sentence_silence "$7" \
      --noise_scale "$8" --noise_w "$9" |
      pw-play --format=s16 --rate="$4" --channels=1 --raw -
  ' _ "$text" "$piper" "$model" "$rate" "$speaker" "$SPEAK_LENGTH_SCALE" \
    "$SPEAK_SENTENCE_SILENCE" "$SPEAK_NOISE_SCALE" "$SPEAK_NOISE_W" &

  local pid=$!
  echo "$pid" > "$SPEAK_PIDFILE"
  wait "$pid" 2>/dev/null
  local status=$?
  rm -f "$SPEAK_PIDFILE"
  return $status
}
