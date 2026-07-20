#!/bin/bash
# Clone Feishu/Lark into a SECOND app that runs SIMULTANEOUSLY with the original.
#
# How simultaneity is achieved: Feishu uses Chromium ProcessSingleton, whose lock
# lives in ~/Library/Application Support/LarkShell and is NOT moved by --user-data-dir
# (Feishu pins it deliberately). So we byte-patch the data-dir name "LarkShell" ->
# "LarkClone" (equal length, zero offset shift) in every bundle file that contains it.
# The clone then computes a completely separate tree (data + singleton lock) ->
# both instances coexist. Re-runnable; never touches the original.
# Self-update of the clone is NEUTERED (step 5): letting it update reverts the
# byte-patch and silently breaks multi-instance. Re-run this script to upgrade.
set -euo pipefail

# Source app: env SRC overrides; otherwise auto-detect common install locations.
SRC="${SRC:-}"
if [ -z "$SRC" ]; then
  for c in "/Applications/Lark.app" "/Applications/飞书.app" \
           "$HOME/Applications/Lark.app" "$HOME/Applications/飞书.app"; do
    [ -d "$c" ] && { SRC="$c"; break; }
  done
fi
[ -d "$SRC" ] || { echo "FATAL: no Lark/飞书 .app found in the usual locations; run with SRC=/path/to/App.app"; exit 1; }
echo "source: $SRC"
NAME="${1:-Feishu 测试}"                 # display name of the clone
NEWID="${2:-com.electron.lark.test}"     # new bundle id
HUE="${3:-2.4}"                          # icon hue rotation in radians (~137 deg)
# Data-dir names: env-overridable for future Lark builds or regional variants.
# MUST be equal length (byte patch keeps every offset intact).
OLDDIR="${OLDDIR:-LarkShell}"            # original data-dir name (9 bytes)
NEWDIR="${NEWDIR:-LarkClone}"            # clone data-dir name  (9 bytes, MUST match length)
DST="/Applications/${NAME}.app"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ ${#OLDDIR} -eq ${#NEWDIR} ] || { echo "FATAL: dir names must be equal length"; exit 1; }

echo ">>> [1/7] copy bundle (preserves symlinks)"
rm -rf "$DST"
cp -R "$SRC" "$DST"

echo ">>> [2/7] patch Info.plist (id=$NEWID, name=$NAME)"
PL="$DST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $NEWID" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $NAME" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $NAME" "$PL" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $NAME" "$PL"

echo ">>> [3/7] recolor icon (hue=$HUE rad)"
ICNS="$DST/Contents/Resources/app.icns"
if ! command -v swift >/dev/null 2>&1; then
  echo "    swift not found (no Xcode CLT) — keeping the original icon (cosmetic only)"
elif [ ! -f "$ICNS" ]; then
  echo "    no app.icns at the usual path — keeping the original icon"
else
  TMP="$(mktemp -d)"
  iconutil -c iconset "$ICNS" -o "$TMP/in.iconset"
  mkdir -p "$TMP/out.iconset"
  for f in "$TMP/in.iconset"/*.png; do
    swift "$HERE/recolor-icon.swift" "$f" "$TMP/out.iconset/$(basename "$f")" "$HUE"
  done
  iconutil -c icns "$TMP/out.iconset" -o "$ICNS"
  rm -rf "$TMP"
fi

echo ">>> [4/7] byte-patch data-dir name $OLDDIR -> $NEWDIR in EVERY Mach-O that carries it"
# NOTE: `grep` chokes on these multi-hundred-MB binaries (giant lines / NUL bytes), so we
# detect with `strings` and patch bytes with `perl -0777`. `find -type f` skips symlinks,
# so each hit is a real file — no realpath dance. set +e: a non-matching file is normal.
# IMPORTANT: disable pipefail here. `grep -q` short-circuits and SIGPIPEs `strings`,
# which under pipefail poisons the pipeline status to 141 -> the `if` reads false and
# every patch silently skips. Use `grep -c` (reads all input, no SIGPIPE) + a count test.
set +e +o pipefail
PATCHED=0
while IFS= read -r f; do
  if [ "$(strings -a "$f" 2>/dev/null | grep -c "$OLDDIR")" -gt 0 ]; then
    LC_ALL=C perl -0777 -i -pe "s/\Q$OLDDIR\E/$NEWDIR/g" "$f"
    PATCHED=$((PATCHED+1))
    echo "    [$PATCHED] ${f#$DST/}"
  fi
done < <(find "$DST" -type f)   # process substitution, NOT a pipe: keeps PATCHED in this shell
LEFT=$(find "$DST" -type f | while IFS= read -r f; do [ "$(strings -a "$f" 2>/dev/null | grep -c "$OLDDIR")" -gt 0 ] && echo x; done | wc -l | tr -d ' ')
set -e -o pipefail
echo "    verify: files still containing $OLDDIR = $LEFT (must be 0)"
[ "$LEFT" = "0" ] || { echo "FATAL: unpatched holders remain"; exit 1; }
[ "$PATCHED" -gt 0 ] || { echo "FATAL: no file contained '$OLDDIR' — wrong source app, or Lark renamed its data dir (override with OLDDIR= NEWDIR=)"; exit 1; }

echo ">>> [5/7] neuter self-update (applying the official update reverts the byte-patch -> clone breaks)"
# The app downloads the official update in the background into the data dir and has
# darwin_updater swap the bundle with it. The swapped-in build still says LarkShell,
# so the clone silently turns back into a second copy fighting for the SAME singleton
# lock (observed 2026-07-20: a fresh clone started downloading a ~500MB update zip
# minutes after launch; the previous clone died exactly this way). Two layers:
#   a) replace the updater agent with a no-op stub (it gets ad-hoc signed in [6/7])
#   b) freeze the data-dir download area with uchg so downloads can't even be written
UP="$(echo "$DST"/Contents/Frameworks/*.framework/Versions/Current/Libraries/darwin_updater)"
printf '#!/bin/sh\n# NEUTERED (feishu-clone): clone stays frozen; self-update would revert the\n# LarkShell->LarkClone byte-patch and break multi-instance.\n# To upgrade the clone, re-run clone-feishu.sh against the updated /Applications/Lark.app.\nexit 0\n' > "$UP"
chmod +x "$UP"
UDIR="$HOME/Library/Application Support/$NEWDIR/update"
[ -d "$UDIR" ] && chflags nouchg "$UDIR" 2>/dev/null || true
rm -rf "$UDIR"
mkdir -p "$UDIR"
chflags uchg "$UDIR"

echo ">>> [6/7] re-sign ad-hoc BOTTOM-UP (codesign --deep does NOT reseal nested helpers; must sign deepest first)"
# 1) every dylib + standalone exec under Frameworks
find "$DST/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "darwin_updater" \) -print0 \
  | xargs -0 -I{} codesign --force --sign - {} >/dev/null 2>&1
# 2) nested helper .apps (inside the versioned framework)
for h in "$DST"/Contents/Frameworks/*.framework/Versions/Current/Helpers/*.app; do
  [ -d "$h" ] && codesign --force --sign - "$h" >/dev/null 2>&1
done
# 3) any other nested .app (e.g. Notification.app)
for a in "$DST"/Contents/Frameworks/*.app; do
  [ -d "$a" ] && codesign --force --sign - "$a" >/dev/null 2>&1
done
# 4) the framework bundle(s)
for fw in "$DST"/Contents/Frameworks/*.framework; do
  [ -d "$fw" ] && codesign --force --sign - "$fw" >/dev/null 2>&1
done
# 5) the main app LAST (no --deep; inner code already sealed)
codesign --force --sign - "$DST"
codesign --verify --strict --deep "$DST" && echo "    signature valid (strict)"

echo ">>> [7/7] register with LaunchServices"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DST"

echo
echo "DONE."
echo "  clone:    $DST   (bundle id: $NEWID)"
echo "  data dir: ~/Library/Application Support/$NEWDIR  (independent login + singleton lock)"
echo "Launch:     open -n \"$DST\"   — runs alongside the real Feishu."
echo "Self-update: DISABLED (updater stubbed, download dir locked). To upgrade, re-run this script."
