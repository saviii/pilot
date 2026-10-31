#!/bin/sh
# Build Pilot for a real iPhone, install it and open it. Needs this Mac's Xcode signed in
# to the Apple account in project.yml, and the phone unlocked. $PHONE picks one by name or id.
set -eu
cd "$(dirname "$0")/.."
derived=build/device

phone=${PHONE:-$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null | python3 -c '
import json, sys
text = sys.stdin.read()
data = json.loads(text[text.index("{"):])
for d in data["result"]["devices"]:
    if d["hardwareProperties"].get("reality") == "physical" and d["hardwareProperties"].get("platform") == "iOS" \
       and d.get("connectionProperties", {}).get("tunnelState") != "unavailable":
        print(d["identifier"]); break')}
[ -n "$phone" ] || { echo "No iPhone found. Plug it in (or pair it in Xcode > Devices) and unlock it."; exit 1; }

xcodebuild -project TVRemote.xcodeproj -scheme TVRemote -derivedDataPath "$derived" -quiet \
  -destination "id=$(xcrun devicectl device info details --device "$phone" --json-output /dev/stdout 2>/dev/null | python3 -c '
import json, sys
text = sys.stdin.read()
print(json.loads(text[text.index("{"):])["result"]["hardwareProperties"]["udid"])')" \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device "$phone" "$derived/Build/Products/Debug-iphoneos/TVRemote.app" >/dev/null
if xcrun devicectl device process launch --terminate-existing --device "$phone" fyi.savi.tvremote >/dev/null 2>&1; then
  echo "✓ Pilot is on the phone and open"
else
  echo "✓ Pilot is on the phone (couldn't open it: the phone is probably locked)"
fi
