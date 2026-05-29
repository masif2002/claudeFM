#!/usr/bin/env bash
#
# claudeFM — installer
#
# Plays your currently-playing audio (Music, Spotify, podcasts, etc.) while
# Claude Code is working, and pauses it the moment Claude stops or needs you.
#
# It does three things:
#   1. Installs the `nowplaying-cli` dependency (via Homebrew) if missing.
#   2. Installs `jq` (used to safely merge JSON) if missing.
#   3. Idempotently adds the play/pause hooks to ~/.claude/settings.json,
#      appending to existing hook arrays instead of clobbering them.
#
# Re-running is safe: hooks that already exist are left untouched.

set -euo pipefail

# --- config ---------------------------------------------------------------

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

# Hook commands are gated: they only act when the Claude session was launched
# with ENABLE_CLAUDE_FM set to a truthy value (1/true/yes/on), e.g.
#   ENABLE_CLAUDE_FM=1 claude
# Otherwise the `case` matches nothing and exits 0 — a silent no-op. The
# $ENABLE_CLAUDE_FM reference must stay LITERAL in settings.json so the
# shell expands it at hook-run time, not now — hence the single quotes.
PLAY_CMD='case "$ENABLE_CLAUDE_FM" in 1|true|yes|on) nowplaying-cli play || true ;; esac'
PAUSE_CMD='case "$ENABLE_CLAUDE_FM" in 1|true|yes|on) nowplaying-cli pause || true ;; esac'

# event -> command. "play" while Claude works, "pause" when it stops/waits.
PLAY_EVENTS=(UserPromptSubmit PostToolUse)
PAUSE_EVENTS=(Stop StopFailure Notification PermissionRequest)

# --- helpers --------------------------------------------------------------

c_green() { printf '\033[32m%s\033[0m\n' "$1"; }
c_yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
c_red() { printf '\033[31m%s\033[0m\n' "$1" >&2; }
step() { printf '\033[1m▸ %s\033[0m\n' "$1"; }

die() { c_red "error: $1"; exit 1; }

# --- 1. dependencies ------------------------------------------------------

step "Checking dependencies"

command -v brew >/dev/null 2>&1 || die \
  "Homebrew is required. Install it from https://brew.sh and re-run."

if ! command -v nowplaying-cli >/dev/null 2>&1; then
  c_yellow "  nowplaying-cli not found — installing via Homebrew…"
  brew install nowplaying-cli
else
  c_green "  nowplaying-cli already installed"
fi

if ! command -v jq >/dev/null 2>&1; then
  c_yellow "  jq not found — installing via Homebrew…"
  brew install jq
else
  c_green "  jq already installed"
fi

# --- 2. load settings -----------------------------------------------------

step "Updating $SETTINGS"

mkdir -p "$(dirname "$SETTINGS")"

if [[ ! -s "$SETTINGS" ]]; then
  # Missing or empty file -> start from an empty object.
  echo '{}' > "$SETTINGS"
  c_yellow "  created a new settings file"
fi

# Reject malformed JSON up front so we never overwrite a broken file blindly.
jq empty "$SETTINGS" 2>/dev/null \
  || die "$SETTINGS is not valid JSON. Fix or remove it, then re-run."

# --- 3. merge hooks idempotently -----------------------------------------

# jq function: ensure ($cmd) is registered under hooks.$event.
#   - if the command is already present anywhere under that event -> no-op
#   - else append it to the first matcher=="" block, or create one
read -r -d '' JQ_FILTER <<'JQ' || true
def ensure_hook($event; $cmd):
  .hooks      //= {}
  | .hooks[$event] //= []
  | if ([.hooks[$event][]?.hooks[]?.command] | any(. == $cmd))
    then .
    else
      (.hooks[$event] | map(.matcher == "") | index(true)) as $i
      | if $i == null
        then .hooks[$event] += [{matcher: "", hooks: [{type: "command", command: $cmd}]}]
        else .hooks[$event][$i].hooks += [{type: "command", command: $cmd}]
        end
    end;
JQ

# Build the chained calls: ensure_hook(...) | ensure_hook(...) | ...
PROGRAM="$JQ_FILTER"$'\n'
first=1
for ev in "${PLAY_EVENTS[@]}"; do
  [[ $first -eq 1 ]] && first=0 || PROGRAM+=" | "
  PROGRAM+="ensure_hook(\"$ev\"; \$play)"
done
for ev in "${PAUSE_EVENTS[@]}"; do
  PROGRAM+=" | ensure_hook(\"$ev\"; \$pause)"
done

TMP="$(mktemp "${SETTINGS}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

jq --arg play "$PLAY_CMD" --arg pause "$PAUSE_CMD" "$PROGRAM" "$SETTINGS" > "$TMP"

# Only touch the real file if something actually changed.
if diff -q "$SETTINGS" "$TMP" >/dev/null 2>&1; then
  c_green "  hooks already present — no changes needed"
else
  BACKUP="${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS" "$BACKUP"
  mv "$TMP" "$SETTINGS"
  trap - EXIT
  c_green "  hooks installed (backup saved to $BACKUP)"
fi

# --- done -----------------------------------------------------------------

echo
c_green "✓ claudeFM is set up."
cat <<'EOF'

  Start playing something (Music, Spotify, a podcast…), then use Claude Code:
    • audio plays   while Claude is generating
    • audio pauses  when Claude stops or needs your input

  To remove it later, run ./uninstall.sh
EOF