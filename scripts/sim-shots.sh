#!/usr/bin/env bash
# App Store screenshots from an iOS simulator. Run after building the app for the simulator into build/sim.
# Usage: sim-shots.sh "<device name>" <out dir> [display id] [inner|outer]
#   iPhone 17 Pro → 1206x2622, iPad Pro 13-inch (M5) → 2064x2752,
#   iPhone Duo: display 1 + outer = folded outer display 1398x2034, display 3 + inner = inner display 2853x2007.
# The app's tour (Pleats/ShotsTour.swift) writes each screen's name to Documents/shots/ready; this script takes
# the screenshot and answers in Documents/shots/next. On the Duo inner display a name like "2-flight@100" means:
# set the hinge to 100° first (tools/duo-hinge.m, vendored and reviewed); other screens are taken open flat.
set -euo pipefail
NAME_DEV=$1; OUT=$2; DISPLAY_ID=${3:-}; MODE=${4:-}
BUNDLE=com.heyobi.pleats
mkdir -p "$OUT" build
DEV=$(bash scripts/sim-device.sh "$NAME_DEV")
echo "simulator $NAME_DEV $DEV"
xcrun simctl boot "$DEV" || true
xcrun simctl bootstatus "$DEV" -b
HINGE=""
if [ "$MODE" = "inner" ]; then
  clang -fobjc-arc -framework Foundation -o build/duo-hinge tools/duo-hinge.m
  HINGE=build/duo-hinge
  "$HINGE" -d "$DEV" flat
  sleep 8
fi
[ -n "${APPEARANCE:-}" ] && xcrun simctl ui "$DEV" appearance "$APPEARANCE" || true
xcrun simctl status_bar "$DEV" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
APP=$(find build/sim/Build/Products -name "Pleats.app" -path "*iphonesimulator*" | head -1)
xcrun simctl uninstall "$DEV" "$BUNDLE" || true
xcrun simctl install "$DEV" "$APP"
ARGS=(-shots); [ "$MODE" = "outer" ] && ARGS+=(-shotsOuter)
xcrun simctl launch "$DEV" "$BUNDLE" "${ARGS[@]}"
DATA=$(xcrun simctl get_app_container "$DEV" "$BUNDLE" data)
DARG=(); [ -n "$DISPLAY_ID" ] && DARG=(--display="$DISPLAY_ID")
POSE=flat
for i in $(seq 1 900); do
  if [ -f "$DATA/Documents/shots/ready" ]; then
    NAME=$(cat "$DATA/Documents/shots/ready")
    [ "$NAME" = "done" ] && { echo "tour finished"; break; }
    FILE=${NAME%%@*}
    if [ ! -f "$OUT/$FILE.png" ]; then
      if [ -n "$HINGE" ]; then
        WANT=flat; [ "$NAME" != "$FILE" ] && WANT=${NAME##*@}
        if [ "$WANT" = "sweep" ]; then
          # Smooth hinge motion for the hinge-rate probe: open, close, open again.
          "$HINGE" -d "$DEV" 90; sleep 3
          "$HINGE" -d "$DEV" sweep 90 170 1.5 8
          "$HINGE" -d "$DEV" sweep 170 70 1.2 8
          "$HINGE" -d "$DEV" sweep 70 150 0.8 4
          POSE=150; sleep 2
        elif [ "$WANT" != "$POSE" ]; then "$HINGE" -d "$DEV" "$WANT"; POSE=$WANT; sleep 5; fi
      fi
      sleep 1
      xcrun simctl io "$DEV" screenshot ${DARG[@]+"${DARG[@]}"} "$OUT/$FILE.png" || echo "screenshot failed for $NAME"
      echo "saved $FILE (pose $POSE)"
    fi
    printf '%s' "$NAME" > "$DATA/Documents/shots/next"
  fi
  sleep 1
done
cp "$DATA/Documents/shots/"hinge-*.json "$OUT"/ 2>/dev/null || true
for f in "$OUT"/hinge-*.json; do [ -f "$f" ] && echo "$(basename "$f"): $(cat "$f")"; done
rm -f "$OUT/0-probe.png"
sips -g pixelWidth -g pixelHeight "$OUT"/*.png | grep pixel | paste - - || true
xcrun simctl shutdown "$DEV" || true
