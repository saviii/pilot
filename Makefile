# Pilot. `make verify` is what "done" means: agents run it before saying a change works,
# and CI runs the same thing on every pull request.

PROJECT := TVRemote.xcodeproj
SCHEME  := TVRemote
BUNDLE  := fyi.savi.tvremote
DERIVED := build/dd
SOURCES := TVRemote Widgets Shared PilotKit scripts
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -quiet

.PHONY: verify setup generate drift format lint test build shots phone clean

## verify: everything CI checks. Run it before you say you're done.
verify: drift lint test build
	@echo "✓ verify passed"

## setup: one-time on a new Mac (XcodeGen, and the repo's git hooks).
setup:
	@command -v xcodegen >/dev/null || brew install xcodegen
	git config core.hooksPath .githooks

## generate: rebuild the Xcode project from project.yml. Never edit the .xcodeproj by hand.
generate:
	xcodegen generate --quiet

## drift: the committed Xcode project matches project.yml.
drift: generate
	@git diff --quiet -- $(PROJECT) || { git --no-pager diff --stat -- $(PROJECT); \
	  echo "✗ $(PROJECT) was out of date with project.yml. It's regenerated now: commit it."; exit 1; }

## format: rewrite Swift files in the house style.
format:
	swift format --in-place --recursive $(SOURCES)

## lint: fail if anything isn't formatted (fix with `make format`).
lint:
	swift format lint --strict --recursive $(SOURCES)

## test: PilotKit's tests (TV and Sonos logic, against a fake Wi-Fi). No TV, no simulator.
test:
	cd PilotKit && swift test --quiet

## build: the app and widgets, for the simulator, unsigned.
build:
	$(XCODEBUILD) -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

## shots: demo-mode screenshots (no TV needed) into build/shots.
shots:
	scripts/shots.sh

## phone: build, install and open on the iPhone plugged into (or paired with) this Mac.
phone:
	scripts/phone.sh

clean:
	rm -rf build PilotKit/.build
