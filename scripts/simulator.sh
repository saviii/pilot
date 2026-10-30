#!/bin/sh
# Prints the UDID of the simulator to use: $SIMULATOR if set, else a regular
# "iPhone NN Pro" on the newest iOS, else any iPhone.
set -eu
if [ -n "${SIMULATOR:-}" ]; then echo "$SIMULATOR"; exit 0; fi
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
phones = [d for runtime, ds in sorted(devices.items(), reverse=True) if "iOS" in runtime for d in ds if d["name"].startswith("iPhone")]
pros = [d for d in phones if re.fullmatch(r"iPhone \d+ Pro", d["name"])]
print((pros or phones)[0]["udid"] if phones else "")'
