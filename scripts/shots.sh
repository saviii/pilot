#!/bin/sh
# Demo-mode screenshots of the main screens, no TV needed: build/shots/*.png.
# Uses the first available iPhone simulator (or $SIMULATOR, a name or UDID).
set -eu
cd "$(dirname "$0")/.."
derived=build/dd-sim
out=build/shots
mkdir -p "$out"

sim=${SIMULATOR:-$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
import re
phones = [d for runtime, ds in sorted(devices.items(), reverse=True) if "iOS" in runtime for d in ds if d["name"].startswith("iPhone")]
# A regular "iPhone NN Pro" first (the shape the app is designed for), newest iOS first.
pros = [d for d in phones if re.fullmatch(r"iPhone \d+ Pro", d["name"])]
print((pros or phones)[0]["udid"] if phones else "")')}
[ -n "$sim" ] || { echo "No iPhone simulator found. Add one in Xcode > Settings > Components."; exit 1; }

xcrun simctl boot "$sim" 2>/dev/null || true
xcrun simctl bootstatus "$sim" -b >/dev/null
xcodebuild -project TVRemote.xcodeproj -scheme TVRemote -derivedDataPath "$derived" -quiet \
  -destination "id=$sim" CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$sim" "$derived/Build/Products/Debug-iphonesimulator/TVRemote.app"
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
