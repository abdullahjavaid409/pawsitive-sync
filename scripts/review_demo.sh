#!/usr/bin/env bash
# Records the App Review demo from the booted simulator.
# Needs the QA backend on :3100 and the local pawsitive_qa database
# (never production).
#   scripts/review_demo.sh [simulator-udid] [out.mp4]
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${1:-$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -1)}"
OUT="${2:-marketing/app-review/gave-it-review-demo.mp4}"
RAW="$(mktemp -d)/raw.mov"
BUNDLE=com.pawsitivesync.app
REC_PID=""

cleanup() {
  [[ -n "$REC_PID" ]] && kill -INT "$REC_PID" 2>/dev/null || true
  xcrun simctl status_bar "$SIM" clear || true
}
trap cleanup EXIT

curl -sf http://127.0.0.1:3100/health >/dev/null ||
  { echo "QA backend is not running on :3100" >&2; exit 1; }

# Fail fast if the simulator is still busy with an old recording (a killed
# recorder can leave it stuck; `xcrun simctl shutdown` + `boot` clears it).
probe="$(dirname "$RAW")/probe.mov"
xcrun simctl io "$SIM" recordVideo --codec=h264 --force "$probe" >/dev/null 2>&1 &
probe_pid=$!
sleep 1.5
kill -INT "$probe_pid" 2>/dev/null || true
wait "$probe_pid" 2>/dev/null || true
[[ -s "$probe" ]] || {
  echo "Simulator can't record (busy?). Reboot it: xcrun simctl shutdown $SIM && xcrun simctl boot $SIM" >&2
  exit 1
}

# Apple's marketing status bar: 9:41, full battery, full signal.
xcrun simctl status_bar "$SIM" override --time "9:41" --dataNetwork wifi \
  --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 \
  --batteryState charged --batteryLevel 100

flutter test integration_test/review_demo_test.dart -d "$SIM" \
  --dart-define=API_BASE_URL=http://127.0.0.1:3100 2>&1 |
while IFS= read -r line; do
  echo "$line"
  case "$line" in
    *"[demo] start"*)
      xcrun simctl io "$SIM" recordVideo --codec=h264 --force "$RAW" &
      REC_PID=$!
      ;;
    *"[demo] server-pro"*)
      # Server-checked Pro for the sitter link, in the local QA DB only.
      psql -q -d pawsitive_qa -c "UPDATE members SET rc_is_pro = true WHERE role = 'owner' AND created_at > now() - interval '15 minutes';"
      ;;
    *"[demo] open-url "*)
      url="${line##*\[demo\] open-url }"
      xcrun simctl openurl "$SIM" "$url"
      sleep 9
      xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
      ;;
    *"[demo] end"*)
      sleep 1.5
      kill -INT "$REC_PID" 2>/dev/null || true
      wait "$REC_PID" 2>/dev/null || true
      REC_PID=""
      ;;
  esac
done

# App Review accepts mp4/mov; H.264 at the simulator's native size.
ffmpeg -v error -y -i "$RAW" -c:v libx264 -pix_fmt yuv420p -crf 20 \
  -movflags +faststart -an "$OUT"
echo "saved $OUT"
