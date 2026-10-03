#!/usr/bin/env bash
# Captures App Store screenshots from the booted simulator.
# Needs the QA backend on :3100 (never production).
#   scripts/store_screenshots.sh [simulator-udid] [out-dir]
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${1:-$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -1)}"
OUT="${2:-marketing/screenshots/raw}"
mkdir -p "$OUT"

# Apple's marketing status bar: 9:41, full battery, full signal.
xcrun simctl status_bar "$SIM" override --time "9:41" --dataNetwork wifi \
  --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100

flutter test "${TEST:-integration_test/store_screenshots_test.dart}" -d "$SIM" \
  ${DART_DEFINES:---dart-define=API_BASE_URL=http://127.0.0.1:3100} 2>&1 |
while IFS= read -r line; do
  echo "$line"
  if [[ "$line" =~ \[shot\]\ ([a-z_0-9]+) ]]; then
    name="${BASH_REMATCH[1]}"
    sleep 0.6
    xcrun simctl io "$SIM" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1 &&
      echo "  -> saved $OUT/$name.png"
  fi
done
xcrun simctl status_bar "$SIM" clear
