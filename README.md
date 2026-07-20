# feishu-clone

Clone Feishu **or** Lark into a second app that runs **simultaneously** with the original — independent login, independent lock, two accounts on one Mac.

```bash
bash clone-feishu.sh
open -n "/Applications/Feishu 测试.app"
```

## Why

Feishu/Lark is Chromium-based. Its `ProcessSingleton` lock lives at `~/Library/Application Support/LarkShell/` and is **not** moved by `--user-data-dir`, so launching a second copy just bounces off the running one. This script byte-patches the data-dir name `LarkShell` → `LarkClone` in every Mach-O that carries it, giving the clone a fully separate data tree and lock. Two instances coexist cleanly.

## What it does

1. Copy the source `.app` bundle.
2. Patch `Info.plist` (new bundle id + name).
3. Recolor the icon (hue rotation, so you can tell them apart in the Dock).
4. Byte-patch `LarkShell` → `LarkClone` in every binary that carries it. Hard assertion: zero files may still contain the old name.
5. Neuter self-update (the official updater would revert the patch — see [坑 3](#why) below).
6. Re-sign ad-hoc, bottom-up.
7. Register with LaunchServices.

Takes ~4 minutes. No brew, no root, no SIP waiver.

## Requirements

- macOS (Apple Silicon verified; Intel should work).
- Feishu or Lark installed at `/Applications/Lark.app`, `/Applications/飞书.app`, or `~/Applications/` variants. Auto-detected; override with `SRC=`.
- Optional: Xcode CLT for icon recoloring (`xcode-select --install`). Without it the icon stays default — cosmetic only.

## Options

| Arg | Env | Default | Purpose |
|---|---|---|---|
| `$1` | — | `Feishu 测试` | Clone display name |
| `$2` | — | `com.electron.lark.test` | Clone bundle id |
| `$3` | — | `2.4` | Icon hue (radians) |
| — | `SRC` | auto | Source `.app` path |
| — | `OLDDIR` | `LarkShell` | Source data-dir name |
| — | `NEWDIR` | `LarkClone` | Clone data-dir name (must equal `OLDDIR` length) |

## As an agent skill

This repo doubles as a cross-platform agent skill. Copy/symlink the directory into your agent's skills folder — the included `SKILL.md` has standard `name`+`description` frontmatter and works on:

- **WorkBuddy** → `~/.workbuddy/skills/feishu-clone/`
- **Claude Code** → `~/.claude/skills/feishu-clone/`
- **Codex** → `~/.codex/skills/feishu-clone/`
- **Grok** → `~/.grok/skills/feishu-clone/`

The agent then triggers on phrases like "克隆飞书", "飞书多开", "clone lark", "second feishu account" and runs the script for you. The agent does **not** need to know whether Feishu or Lark is installed — the script auto-detects.

## When it breaks

**Months later, clone can't log in** — the server enforced a min version and the frozen clone is too old. Re-run the script against the updated source app. By design: the clone is frozen so auto-update can't silently revert the byte-patch.

**`FATAL: no file contained 'LarkShell'`** — the app renamed its data dir in a new build. Find the new name under `~/Library/Application Support/` and re-run with `OLDDIR=<new> NEWDIR=<new-clone>` (equal length). Then please open an issue or PR.

## License

MIT
