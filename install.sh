#!/bin/bash
# omarchy-speak installer.
#
#   ./install.sh                      full user-level install, no root needed
#   ./install.sh --system             per-user setup only (binaries already in /usr)
#   ./install.sh --voice en_US-amy-medium
#
# Safe to re-run: an existing config, voice, or keybinding is left alone.
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEFAULT_VOICE=en_GB-northern_english_male-medium
SYSTEM=0 WITH_KEYS=1 WITH_BATTERY=1 WITH_CLAUDE=1

PIPER_VERSION=2023.11.14-2
declare -A PIPER_SHA=(
  [aarch64]=fea0fd2d87c54dbc7078d0f878289f404bd4d6eea6e7444a77835d1537ab88eb
  [x86_64]=a50cb45f355b7af1f6d758c1b360717877ba0a398cc8cbe6d2a7a3a26e225992
)
declare -A PIPER_ASSET=(
  [aarch64]=piper_linux_aarch64.tar.gz
  [x86_64]=piper_linux_x86_64.tar.gz
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system) SYSTEM=1; shift ;;
    --voice) DEFAULT_VOICE="${2:?}"; shift 2 ;;
    --no-keybindings) WITH_KEYS=0; shift ;;
    --no-battery-hook) WITH_BATTERY=0; shift ;;
    --no-claude-hook) WITH_CLAUDE=0; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

say() { printf '\033[32m==>\033[0m %s\n' "$*"; }

# Data files sit under the source tree when run from a checkout, and flat in
# /usr/share/speak when run as the package's setup step.
find_data() {
  local candidate
  for candidate in "$SRC/$1" "$SRC/$(basename "$1")" "/usr/share/speak/$(basename "$1")" "/usr/share/speak/$1"; do
    [[ -r $candidate ]] && { echo "$candidate"; return 0; }
  done
  echo "missing data file: $1" >&2
  return 1
}
warn() { printf '\033[33m==>\033[0m %s\n' "$*" >&2; }

BINDIR="$HOME/.local/bin"
LIBDIR="$HOME/.local/share/speak"
(( SYSTEM )) && { BINDIR=/usr/bin; LIBDIR=/usr/share/speak; }

VOICES="$HOME/.local/share/piper/voices"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/speak/config"

for tool in curl jq pw-play; do
  command -v "$tool" >/dev/null || { echo "missing dependency: $tool" >&2; exit 1; }
done

# --- engine -----------------------------------------------------------------
if command -v piper-tts >/dev/null || command -v piper >/dev/null; then
  say "Using the piper already on PATH"
elif [[ -x $HOME/.local/share/piper/bin/piper ]]; then
  say "Using the existing user-level piper"
else
  arch=$(uname -m)
  asset="${PIPER_ASSET[$arch]:-}"
  [[ -n $asset ]] || { echo "no piper build for $arch; install piper-tts yourself" >&2; exit 1; }
  say "Downloading piper for $arch"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fL# -o "$tmp/piper.tar.gz" \
    "https://github.com/rhasspy/piper/releases/download/$PIPER_VERSION/$asset"
  echo "${PIPER_SHA[$arch]}  $tmp/piper.tar.gz" | sha256sum -c - >/dev/null \
    || { echo "piper checksum mismatch; refusing to install" >&2; exit 1; }
  mkdir -p "$HOME/.local/share/piper/bin"
  tar xzf "$tmp/piper.tar.gz" -C "$tmp"
  cp -r "$tmp/piper/." "$HOME/.local/share/piper/bin/"
  chmod +x "$HOME/.local/share/piper/bin/piper"
  say "piper installed to ~/.local/share/piper/bin"
fi

# --- program files ----------------------------------------------------------
if (( ! SYSTEM )); then
  mkdir -p "$BINDIR" "$LIBDIR"
  install -m755 "$SRC"/bin/* "$BINDIR/"
  install -m644 "$SRC/lib/speak-lib.sh" "$LIBDIR/lib.sh"
  say "Installed speak, speakd, speak-selection, claude-speak-response to $BINDIR"
  case ":$PATH:" in
    *":$BINDIR:"*) ;;
    *) warn "$BINDIR is not on your PATH; add it to your shell profile" ;;
  esac
fi

# --- config (never clobber an existing one) ---------------------------------
mkdir -p "$(dirname "$CONFIG")"
if [[ -e $CONFIG ]]; then
  say "Keeping your existing config at $CONFIG"
  DEFAULT_VOICE=$(bash -c ". '$CONFIG' >/dev/null 2>&1; echo \"\${SPEAK_VOICE:-$DEFAULT_VOICE}\"")
else
  sed "s|@DEFAULT_VOICE@|$DEFAULT_VOICE|" "$(find_data config/config.example)" > "$CONFIG"
  say "Wrote $CONFIG"
fi

# --- voice ------------------------------------------------------------------
mkdir -p "$VOICES"
if [[ -r $VOICES/$DEFAULT_VOICE.onnx ]]; then
  say "Voice $DEFAULT_VOICE already present"
else
  say "Downloading voice $DEFAULT_VOICE (~60MB)"
  locale="${DEFAULT_VOICE%%-*}"; rest="${DEFAULT_VOICE#*-}"
  short="${rest%-*}"; quality="${rest##*-}"
  base="https://huggingface.co/rhasspy/piper-voices/resolve/main/${locale%%_*}/$locale/$short/$quality/$DEFAULT_VOICE"
  curl -fL# -o "$VOICES/$DEFAULT_VOICE.onnx" "$base.onnx"
  curl -fsL -o "$VOICES/$DEFAULT_VOICE.onnx.json" "$base.onnx.json"
fi

# --- service ----------------------------------------------------------------
if (( SYSTEM )) && [[ -r /usr/lib/systemd/user/speakd.service ]]; then
  say "Using the packaged systemd unit"
else
  UNIT="$HOME/.config/systemd/user/speakd.service"
  mkdir -p "$(dirname "$UNIT")"
  sed "s|@BINDIR@|$BINDIR|" "$(find_data systemd/speakd.service.in)" > "$UNIT"
fi
systemctl --user daemon-reload
systemctl --user enable --now speakd
say "speakd enabled and running"

# --- optional: Hyprland keybindings ----------------------------------------
BINDINGS="$HOME/.config/hypr/bindings.lua"
if (( WITH_KEYS )) && [[ -w $BINDINGS ]]; then
  if grep -q 'speak-selection' "$BINDINGS"; then
    say "Keybindings already present"
  elif command -v omarchy >/dev/null &&
       omarchy menu keybindings --print 2>/dev/null | grep -qE '^SUPER ALT \+ (V|X)\b'; then
    warn "SUPER+ALT+V or +X is already bound; skipping keybindings"
  else
    cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
    cat >> "$BINDINGS" <<EOF

-- Text-to-speech (see \`speak --help\`; daemon is the speakd user service).
o.bind("SUPER + ALT + V", "Speak selection", "$BINDIR/speak-selection")
o.bind("SUPER + ALT + X", "Stop speaking", "$BINDIR/speak stop")
EOF
    hyprctl reload >/dev/null 2>&1 || true
    say "Bound SUPER+ALT+V (speak selection) and SUPER+ALT+X (stop)"
  fi
fi

# --- optional: Omarchy battery-low hook -------------------------------------
if (( WITH_BATTERY )) && command -v omarchy-hook-install >/dev/null; then
  omarchy-hook-install battery-low "$(find_data hooks/battery-low/speak-battery-low)" >/dev/null
  say "Low-battery warnings will be spoken"
fi

# --- optional: Claude Code Stop hook ----------------------------------------
CLAUDE="$HOME/.claude/settings.json"
if (( WITH_CLAUDE )) && [[ -f $CLAUDE ]]; then
  if jq -e '[.hooks.Stop[]?.hooks[]?.command] | any(. | test("claude-speak-response"))' \
       "$CLAUDE" >/dev/null 2>&1; then
    say "Claude Code hook already installed"
  else
    cp "$CLAUDE" "$CLAUDE.bak.$(date +%s)"
    jq --arg cmd "$BINDIR/claude-speak-response" \
       '.hooks.Stop = ((.hooks.Stop // []) + [{
          "hooks": [{"type":"command","command":$cmd,"async":true,"timeout":15}]
        }])' "$CLAUDE" > "$CLAUDE.new" && mv "$CLAUDE.new" "$CLAUDE"
    say "Claude Code will speak its final response"
  fi
fi

say "Done. Try: speak 'hello from omarchy speak'"
