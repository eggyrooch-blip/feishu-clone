---
name: feishu-clone
description: Clone Feishu OR Lark (auto-detected — the agent does NOT need to know which is installed) into a SECOND app that runs SIMULTANEOUSLY with the original, so the user can sign in with two accounts on the same Mac. Works across agent platforms (WorkBuddy, Claude Code, Codex, Grok) — standard SKILL.md format, no platform-specific code. Use when the user says "克隆飞书", "飞书多开", "Lark 多开", "双开飞书", "clone feishu", "clone lark", "second feishu account", "second lark account", "两个飞书", "两个 lark", "测试飞书" or otherwise wants a second Feishu/Lark instance side-by-side with the main one. Self-contained bash script; no brew/npm/root/SIP waiver needed.
---

# Clone Feishu / Lark (multi-instance on macOS)

Builds a second Feishu.app **or** Lark.app (default name `Feishu 测试.app`) that runs at the same time as the original, with its OWN login session and its OWN Chromium ProcessSingleton lock. The user signs into the main app with account A and into the clone with account B. Both icons sit in the Dock at once; the clone's icon is hue-rotated so they're visually distinct.

## The agent does NOT decide Feishu vs Lark — the script does

The script auto-detects whichever of these exists (first match wins):

1. `/Applications/Lark.app`
2. `/Applications/飞书.app`
3. `~/Applications/Lark.app`
4. `~/Applications/飞书.app`

If the agent finds none of the above, it asks the user for the path and re-runs with `SRC=/path/to/App.app`. **Never make the agent guess or ask which one** — just run the script; it knows. Both apps share the same Chromium codebase and the same `LarkShell` data-dir lock, so one script handles both.

## How it works (one paragraph)

Feishu/Lark is Chromium-based. Chromium's `ProcessSingleton` lock lives at `~/Library/Application Support/LarkShell/` and the app does NOT move it for `--user-data-dir`, so a second copy normally fights for the same lock and bounces off the running one. The script byte-patches the data-dir name `LarkShell` → `LarkClone` (equal 9-byte length, zero offset shift) in every Mach-O that carries it. The clone then computes a fully separate tree (`~/Library/Application Support/LarkClone/`) — data, login, and singleton lock — so both instances coexist. The clone's self-updater is also stubbed, because an official update silently reverts the byte-patch and turns the clone back into a same-lock competitor (this is exactly what killed the previous clone on 2026-07-20).

## Prerequisites

- macOS (Apple Silicon verified; Intel should work but untested).
- Feishu **or** Lark installed at one of the four auto-detected paths above (or pass `SRC=`).
- **Optional:** Xcode Command Line Tools (`xcode-select -p`). Without it, the icon is left un-recolored — purely cosmetic, does not affect function.
- No brew/npm/node/python. No root. No SIP waiver. No Gatekeeper dance.

## Cross-platform agent compatibility

This skill is a plain `SKILL.md` + bash script. To install on any agent platform:

| Platform | Skill location |
|---|---|
| **WorkBuddy** (preferred) | `~/.workbuddy/skills/feishu-clone/SKILL.md` |
| Claude Code | `~/.claude/skills/feishu-clone/SKILL.md` |
| Codex | `~/.codex/skills/feishu-clone/SKILL.md` |
| Grok | `~/.grok/skills/feishu-clone/SKILL.md` |

All four use the same `name` + `description` frontmatter format. Copy the whole `feishu-clone/` directory (this repo) into the platform's skills dir; no symlink dance required.

## The command

```bash
bash clone-feishu.sh
```

That's the whole thing. Takes ~4 minutes (mostly `cp` + ad-hoc re-sign). When it prints `DONE.`, launch the clone with:

```bash
open -n "/Applications/Feishu 测试.app"
```

It runs alongside the real Feishu/Lark. Sign in with the second account.

## Arguments / env vars (all optional)

| Positional | Env | Default | Purpose |
|---|---|---|---|
| `$1` | — | `Feishu 测试` | Display name of the clone (also the .app filename) |
| `$2` | — | `com.electron.lark.test` | New bundle id (must differ from original) |
| `$3` | — | `2.4` | Icon hue rotation in radians (~137°) |
| — | `SRC` | auto-detect | Path to source .app (override only if auto-detect fails) |
| — | `OLDDIR` | `LarkShell` | Original data-dir name (9 bytes) |
| — | `NEWDIR` | `LarkClone` | Clone data-dir name (MUST equal OLDDIR length) |

Example: build a third clone with a different name and a green icon:

```bash
bash clone-feishu.sh "Feishu 实验" com.electron.lark.exp 5.5
```

## What the script does, in order

1. **Copy bundle** — `cp -R` the source .app to `/Applications/<NAME>.app`.
2. **Patch Info.plist** — new bundle id, new name.
3. **Recolor icon** — hue-rotate every PNG inside `app.icns` via `recolor-icon.swift`. Skipped automatically if `swift` is missing (no CLT) or no icns at the expected path.
4. **Byte-patch** — `LarkShell` → `LarkClone` in every Mach-O that carries it, with a hard `verify: files still containing LarkShell = 0` assertion. If the app renames its data dir in a future build, this step `FATAL`s loud — never silently produces a broken clone.
5. **Neuter self-update** — replace `darwin_updater` with `exit 0` stub + `chflags uchg` lock the `update/` download dir. Two layers, because either alone is bypassable.
6. **Re-sign ad-hoc, bottom-up** — sign dylibs/helpers/frameworks BEFORE the outer .app (codesign `--deep` does not reseal nested helpers and the app will refuse to launch). Verify with `--strict --deep`.
7. **Register with LaunchServices** so Finder/LaunchPad pick it up.

## When something breaks

**Symptom: clone suddenly stopped being able to log in / "登录失败" months later.**
Root cause: the server started enforcing a minimum client version, and the frozen clone is now too old. Fix: just re-run the script against the updated source app. The clone rebuilds against the new version and is good for another stretch. This is by design — the clone is deliberately frozen so the byte-patch can't be reverted by an auto-update.

**Symptom: script exits with `FATAL: no file contained 'LarkShell'`.**
The app renamed its data dir in a new build. Find the new name (look at `~/Library/Application Support/` while the app is running for a matching dir) and re-run with `OLDDIR=<newname> NEWDIR=<newname-clone>` (both must be equal length). Then update this skill's defaults.

**Symptom: script exits with `FATAL: unpatched holders remain`.**
Same cause as above, partial. Inspect which file still has the old string and investigate. Don't try to override the assertion.

**Symptom: clone launches then immediately quits, no window.**
codesign didn't reseal something. Re-run the script (it always rebuilds from scratch). If it persists, run `codesign --verify --strict --deep "/Applications/<NAME>.app"` and look for the specific unsign nested artifact.

**Symptom: icon not recolored.**
No CLT installed. Install with `xcode-select --install` and re-run, or accept the default icon — function is unaffected.

**Symptom: on Intel Mac.**
Should work (byte-patch and ad-hoc signing are arch-independent) but untested. If you hit something, capture the exact step that failed.

## Files in this repo

- `clone-feishu.sh` — the script (the only thing that matters).
- `recolor-icon.swift` — icon hue rotation helper (invoked by the script, not standalone).
- `SKILL.md` — this file; makes the script discoverable by any agent platform.

## Notes

- The clone's data dir `~/Library/Application Support/LarkClone/` is safe to `rm -rf` to reset the clone's state; the script does not touch the real `LarkShell/`.
- The clone is a frozen snapshot. Accept that it will eventually drift behind the real app; the trade-off is that multi-instance cannot be silently broken by an auto-update again.
