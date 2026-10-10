#!/bin/zsh
# Captures the Mac app's screenshots into docs/screenshots/mac/ from the UI tests in mac/UITests.
# The app runs in demo mode (BGB_DEMO=1): made-up readings, no real Dexcom, Keychain, Discord or settings.
# The app appears on screen for about a minute while this runs.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/screenshots/mac"
EXPECTED=(01-sign-in 02-sign-in-filled 03-settings-signed-in 04-menu-bar 05-menu 06-menu-units
          07-menu-discord 08-settings-discord 09-menu-bar-low 10-menu-bar-high 11-menu-bar-mmol 12-about-maddie)
cd "$ROOT/mac"
xcodegen generate --quiet
RESULT="build/Screenshots.xcresult"
rm -rf "$RESULT" build/attachments
xcodebuild test -project BloodGlucoseBuddy.xcodeproj -scheme BloodGlucoseBuddyUITests -destination 'platform=macOS' \
  -derivedDataPath build -resultBundlePath "$RESULT" -quiet || { echo "UI tests failed: screenshots NOT updated"; exit 1; }
xcrun xcresulttool export attachments --path "$RESULT" --output-path build/attachments >/dev/null
mkdir -p "$OUT"
python3 - "$ROOT/mac/build/attachments" "$OUT" <<'PY'
import json, os, shutil, sys
src, out = sys.argv[1:]
for test in json.load(open(os.path.join(src, "manifest.json"))):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", "").split("_")[0]
        if name[:2].isdigit():
            shutil.copy(os.path.join(src, a["exportedFileName"]), os.path.join(out, name + ".png"))
PY
missing=()
for n in $EXPECTED; do [[ -s "$OUT/$n.png" ]] || missing+=$n; done
if (( ${#missing} )); then echo "MISSING screenshots: ${missing[*]}"; exit 1; fi
echo "Captured ${#EXPECTED} screenshots into $OUT"
