#!/bin/bash
# Remove omarchy-speak. Voices are large, so they are kept unless --purge is given.
set -uo pipefail
PURGE=0
[[ ${1:-} == --purge ]] && PURGE=1

systemctl --user disable --now speakd 2>/dev/null
rm -f "$HOME/.config/systemd/user/speakd.service"
systemctl --user daemon-reload 2>/dev/null

rm -f "$HOME"/.local/bin/{speak,speakd,speak-selection,claude-speak-response}
rm -rf "$HOME/.local/share/speak"
rm -f "$HOME/.config/omarchy/hooks/battery-low.d/speak-battery-low"

# Leave the user's own edits alone; just drop the block this project appended.
BINDINGS="$HOME/.config/hypr/bindings.lua"
if [[ -w $BINDINGS ]] && grep -q 'speak-selection' "$BINDINGS"; then
  cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  sed -i '/^-- Text-to-speech (see `speak --help`/,+2d' "$BINDINGS"
  hyprctl reload >/dev/null 2>&1
fi

CLAUDE="$HOME/.claude/settings.json"
if [[ -f $CLAUDE ]] && command -v jq >/dev/null; then
  cp "$CLAUDE" "$CLAUDE.bak.$(date +%s)"
  jq '(.hooks.Stop // []) |= map(.hooks |= map(select(.command | test("claude-speak-response") | not)))
      | (.hooks.Stop // []) |= map(select(.hooks | length > 0))' "$CLAUDE" > "$CLAUDE.new" &&
    mv "$CLAUDE.new" "$CLAUDE"
fi

if (( PURGE )); then
  rm -rf "$HOME/.local/share/piper" "$HOME/.config/speak"
  echo "Removed omarchy-speak, piper, and all voices."
else
  echo "Removed omarchy-speak. Voices kept in ~/.local/share/piper (--purge removes them)."
fi
