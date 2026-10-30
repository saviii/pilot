#!/bin/sh
# Demo-mode screenshots of the main screens, no TV needed: build/shots/*.png.
# Reuses the app `make build` makes; boots a simulator if none is (see simulator.sh).
set -eu
cd "$(dirname "$0")/.."
out=build/shots
app=build/dd/Build/Products/Debug-iphonesimulator/TVRemote.app
mkdir -p "$out"

sim=$(scripts/simulator.sh)
[ -n "$sim" ] || { echo "No iPhone simulator found. Add one in Xcode > Settings > Components."; exit 1; }
xcrun simctl boot "$sim" 2>/dev/null || true
make --no-print-directory build
xcrun simctl bootstatus "$sim" -b >/dev/null
xcrun simctl install "$sim" "$app"
xcrun simctl status_bar "$sim" override --time 9:41 --batteryLevel 100 --batteryState charged --wifiBars 3 --cellularBars 4 || true

# name, launch arguments, appearance
shoot() {
  xcrun simctl ui "$sim" appearance "$3"
  xcrun simctl terminate "$sim" fyi.savi.tvremote 2>/dev/null || true
  # shellcheck disable=SC2086
  xcrun simctl launch "$sim" fyi.savi.tvremote -demo $2 >/dev/null
  sleep "${SHOT_WAIT:-4}"
  xcrun simctl io "$sim" screenshot "$out/$1.png" >/dev/null 2>&1
  echo "$out/$1.png"
}
shoot remote-dark "" dark
shoot remote-light "" light
shoot apps "-apps" dark
shoot tvs "-tvs" dark
shoot keyboard "-kb" dark
shoot ps5 "-ps5" dark
