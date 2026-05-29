# claudeFM 🎧

Plays your music (or podcasts, or any audio) while **Claude Code** is generating,
and pauses it the instant Claude stops or needs your input. Get in the zone while
the agent works; silence the moment it's your turn again.

It works with anything macOS's Now Playing controls can reach — Apple Music,
Spotify, Podcasts, YouTube in Safari, etc. — via
[`nowplaying-cli`](https://github.com/kirtan-shah/nowplaying-cli).

## Install

```bash
./install.sh
```

That's it. The installer will:

1. Install **`nowplaying-cli`** via Homebrew (if not already present).
2. Install **`jq`** via Homebrew (used to edit your settings safely).
3. Add play/pause hooks to `~/.claude/settings.json`.

## Enabling it (per session)

The hooks are **opt-in per session** via an environment variable. Launch Claude
with the flag to get the music behaviour:

```bash
ENABLE_CLAUDE_VIBE_MUSIC=1 claude
```

A plain `claude` does nothing — the hooks are present but stay silent. Accepted
truthy values are `1`, `true`, `yes`, `on`.

Tip — make a shortcut for sessions where you want it:

```bash
alias cvibe='ENABLE_CLAUDE_VIBE_MUSIC=1 claude'
```

> **Multiple sessions:** because there's one system audio player, only sessions
> you launch with the flag touch it — every other session is completely inert.
> If you run *two* flagged sessions at once they'll both drive playback and may
> fight; launch only one with the flag to avoid that.

Then start playing something and use Claude Code as usual.

> Requires [Homebrew](https://brew.sh). Re-running `install.sh` is safe.

## How it works

Claude Code fires [hooks](https://docs.claude.com/en/docs/claude-code/hooks) on
lifecycle events. We map them to playback:

| Event              | Action  | Meaning                                  |
| ------------------ | ------- | ---------------------------------------- |
| `UserPromptSubmit` | ▶️ play  | You sent a prompt — Claude starts working |
| `PostToolUse`      | ▶️ play  | A tool finished — Claude keeps going      |
| `Stop`             | ⏸️ pause | Claude finished its turn                  |
| `StopFailure`      | ⏸️ pause | Claude's turn ended in an error           |
| `Notification`     | ⏸️ pause | Claude is idle / wants your attention     |
| `PermissionRequest`| ⏸️ pause | Claude is waiting for you to approve       |

Each hook runs a small gated command:

```sh
case "$ENABLE_CLAUDE_VIBE_MUSIC" in 1|true|yes|on) nowplaying-cli play || true ;; esac
```

Hooks inherit the environment of the `claude` process they were launched from,
so the `case` only triggers `nowplaying-cli` when you started that session with
`ENABLE_CLAUDE_VIBE_MUSIC` set. Otherwise it matches nothing and exits `0` — a
silent no-op that never reports a hook failure.

## Idempotency & safety

- **Appends, never clobbers.** Existing hooks for these events are preserved; the
  play/pause command is added to the existing array. If it's already there,
  nothing changes.
- **Backups.** Any change writes a timestamped `settings.json.bak.<ts>` first.
- **Validates JSON.** A malformed `settings.json` aborts the run untouched.
- **Custom path.** Set `CLAUDE_SETTINGS=/path/to/settings.json` to target a
  different file.

## Uninstall

```bash
./uninstall.sh
```

Removes only the exact play/pause commands this tool added (cleaning up any
empty hook blocks it leaves behind) and backs up first. It does **not** remove
`nowplaying-cli` / `jq`, since other tools may rely on them:

```bash
brew uninstall nowplaying-cli   # optional
```

## Notes

- macOS only.
- If audio doesn't respond, confirm `nowplaying-cli play` / `nowplaying-cli pause`
  control your player from a terminal first.