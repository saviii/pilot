# Pilot

An iPhone remote for Savi's LG TV and the Sonos under it. SwiftUI, iOS 17+, one person's app,
changed often by agents. Public repo: nothing private goes in it.

## Done means `make verify`

Run `make verify` before you say a change works; CI runs the same thing on every PR. It
regenerates the Xcode project and checks it matches `project.yml`, checks formatting,
runs PilotKit's tests and builds the app. `make format` fixes formatting.

- UI change: `make shots` (demo-mode screenshots in `build/shots/`). Look at them; attach
  the ones that changed to the PR.
- Want it on the phone: `make phone` (Mac only, phone unlocked).

## Rules

- **Only the doors the devices open.** LG's own "connect apps" socket (the TV asks once
  on screen, you press OK) and Sonos's local control port. No exploits, no rooting, no
  developer mode, no cloud APIs, nothing that gets around the TV's prompt.
- **Nothing private in the repo.** No pairing keys, real IP or MAC addresses, Wi-Fi names
  or screenshots of the real TV. Tests and fixtures use made-up values.
- **Never hand-edit `TVRemote.xcodeproj`.** Change `project.yml`, run `make generate`,
  commit both.
- **Logic goes in PilotKit, with a test.** `PilotKit/` holds everything about the TV and
  Sonos that doesn't need a screen or a socket: messages, parsing, pairing storage,
  finding a TV that moved. It's Foundation only. The app (`TVRemote/`) keeps the socket,
  the views and state. A bug fix there starts with a failing test in `PilotKit/Tests`.
- **Ship through a PR into `main`.** Branch, `make verify`, push, open a PR with what
  changed and how you checked it (screenshots for UI). Savi merges. Never push to `main`.
- **Match the design.** Dots and Doto numbers, Martian Mono labels, one accent, every
  control visible, the Fire TV layout (wheel on top, grid under it, six apps at the
  bottom). Look at `docs/` and `Theme.swift` before adding UI. No explainer text.

## Where things are

| Path | What |
|---|---|
| `TVRemote/TVConnection.swift` | The TV socket: connect, pair, retry, find it again, every command |
| `TVRemote/Sonos.swift` | The Sonos: volume, EQ, sleep timer, now playing |
| `TVRemote/RemoteView.swift`, `Sheets.swift`, `Theme.swift` | The remote, its sheets, colors and type |
| `TVRemote/LiveRemote.swift`, `Shared/`, `Widgets/` | The Lock Screen panel (Live Activity) |
| `PilotKit/` | Tested logic, `swift test` (or `make test`) |
| `project.yml` | The Xcode project's source of truth (XcodeGen) |

Launch flags for the simulator (debug builds): `-demo` shows the remote with fake data and
no TV; add `-apps`, `-tvs`, `-kb`, `-sonos` to open a sheet, `-ps5` to show an HDMI input.

## Traps

Each one cost real time. Keep this list short: add one only if it fails quietly, isn't
visible from the code, and no test can catch it (otherwise write the test).

- **The router gives the TV a new address.** It looks "off" while it's on. Pilot scans the
  Wi-Fi and offers its key only to TVs it doesn't know (`Finding.moved`). Never offer it to a
  saved TV: a TV that doesn't know the key pops a pairing prompt on screen.
- **A TV that was just turned on can take a minute to join the Wi-Fi.** Pilot keeps retrying
  every 5s while it's open. Don't make retries stop on their own.
- **Newer LG firmware only answers `wss://…:3001`** with a self-signed certificate
  (`LocalTrust`); older firmware only `ws://…:3000`. Keep both.
- **iOS won't broadcast** without a special entitlement, so Wake-on-LAN goes straight to the
  TV's address with the MAC learned while it was on. No MAC yet, no waking.
- **Screenshots of Netflix, most HDMI video and other protected video come back black.** That's
  the TV's rule, not a bug.
- **YouTube's TV app ignores typed text.** Search goes through `searchYouTube`, which opens
  the results directly.
- **Newer Sonos bars (Arc Ultra) use `SpeechEnhanceEnabled`;** older ones only `DialogLevel`.
  Right after a change, a refresh reads the old value back: that's what `quietUntil` is for.

## Debugging on the phone

The app writes `Documents/*.log` (and raw replies as `*.json`). From the Mac, with the phone
connected:

```sh
xcrun devicectl device info files --device <phone> --domain-type appDataContainer --domain-identifier fyi.savi.tvremote --subdirectory Documents
xcrun devicectl device copy from --device <phone> --domain-type appDataContainer --domain-identifier fyi.savi.tvremote --source Documents/<file> --destination <local file>
```

Those files can hold the home's addresses: read them, never commit them.

## Cloud sessions

Claude Code in the cloud runs on Linux: no Xcode, no simulator, no phone. There, edit, run
`swift format` if it's installed, push a branch and open the PR; CI on macOS does the
building and testing. Say in the PR that you couldn't build it.
