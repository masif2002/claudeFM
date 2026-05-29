#!/usr/bin/env bash
#
# claudeFM — uninstaller
#
# Removes the nowplaying-cli play/pause hooks from ~/.claude/settings.json.
# It only strips the exact commands this tool added; every other hook,
# permission, and setting is left exactly as it was.
#
# It does NOT uninstall nowplaying-cli / jq (other things may use them).
# Remove those yourself with: brew uninstall nowplaying-cli

set -euo pipefail

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
PLAY_CMD='case "$ENABLE_CLAUDE_FM" in 1|true|yes|on) nowplaying-cli play || true ;; esac'
PAUSE_CMD='case "$ENABLE_CLAUDE_FM" in 1|true|yes|on) nowplaying-cli pause || true ;; esac'

c_green() { printf '\033[32m%s\033[0m\n' "$1"; }
c_red() { printf '\033[31m%s\033[0m\n' "$1" >&2; }
die() { c_red "error: $1"; exit 1; }

[[ -s "$SETTINGS" ]] || { c_green "Nothing to do — $SETTINGS not found."; exit 0; }
command -v jq >/dev/null 2>&1 || die "jq is required to edit settings safely."
jq empty "$SETTINGS" 2>/dev/null || die "$SETTINGS is not valid JSON."

# Remove our commands, then drop any matcher blocks / event arrays left empty.
read -r -d '' JQ_FILTER <<'JQ' || true
def is_ours($c): $c == $play or $c == $pause;
if has("hooks") then
  .hooks |= (
      with_entries(
        .value |= (
            map(.hooks |= map(select(is_ours(.command) | not)))
          | map(select((.hooks | length) > 0))
        )
      )
    | with_entries(select((.value | length) > 0))
  )
  | if (.hooks == {}) then del(.hooks) else . end
else . end
JQ

TMP="$(mktemp "${SETTINGS}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

jq --arg play "$PLAY_CMD" --arg pause "$PAUSE_CMD" "$JQ_FILTER" "$SETTINGS" > "$TMP"

if diff -q "$SETTINGS" "$TMP" >/dev/null 2>&1; then
  c_green "No claudeFM hooks found — nothing to remove."
else
  BACKUP="${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS" "$BACKUP"
mv "$TMP" "$SETTINGS"
  trap - EXIT
  c_green "✓ Removed claudeFM hooks (backup saved to $BACKUP)."
fi