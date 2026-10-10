# SoundcoreBar

Switch your Soundcore headphones between **Noise Cancelling**, **Transparency** and **Normal**
from the Mac menu bar, like the AirPods mode switcher.

- A Liquid Glass panel with three round buttons per pair; the current mode is tinted.
- Shows the real mode, read from the headphones, and follows changes made with their own buttons.
- Picks up whichever supported pair connects, and handles two pairs at once.
- Your choice of menu bar icon: a rabbit by default, or any symbol, emoji or short text.
- No Dock icon, no account, no network: it only talks to your headphones over Bluetooth.

> SoundcoreBar is an independent, unofficial app. It is not affiliated with, endorsed by or
> sponsored by Anker Innovations. Soundcore and Anker are trademarks of Anker Innovations Limited.

## Supported headphones

| Headphones | Model | Tested on firmware |
| --- | --- | --- |
| Soundcore Q20i (over-ear) | A3004 | 00.26 |
| Soundcore R50i NC (earbuds) | A3959 | 01.65 |

Renamed headphones work too. Many other Soundcore models speak the same protocol and could be
added; see [Adding your headphones](#adding-your-headphones).

## Install

Built for macOS 13 or newer, on Apple silicon or Intel; so far tested on macOS 27 on Apple
silicon. The Liquid Glass look needs macOS 26 or newer; older systems get regular buttons.

1. Download `SoundcoreBar-<version>.zip` from [Releases](../../releases/latest), unzip it and move
   **SoundcoreBar** to your Applications folder.
2. Open it. Because SoundcoreBar is not notarized by Apple (that needs a paid developer account),
   macOS blocks the first launch. To allow it once:
   - open **System Settings › Privacy & Security**, scroll down to the message about SoundcoreBar
     and click **Open Anyway**, then confirm; or
   - in Terminal: `xattr -dr com.apple.quarantine /Applications/SoundcoreBar.app`
3. When macOS asks whether SoundcoreBar may use Bluetooth, click **Allow**. It needs Bluetooth
   to talk to your headphones.
4. Optional: add it under **System Settings › General › Login Items** to start it at login.

If you clicked Don’t Allow, the panel says Bluetooth access is off and offers to open the
settings page: turn SoundcoreBar on under Privacy & Security › Bluetooth and reopen the app.

## Use

Click the menu bar icon:

- Each connected pair has its name and three buttons. Click one to switch; the tint moves once the
  headphones confirm the change.
- Changes made on the headphones (the Q20i’s noise cancelling button, a long press on an R50i NC
  earbud) show up straight away.
- **Menu Bar Icon** picks a symbol, an emoji or your own text. **Clear Glass** swaps the regular
  Liquid Glass for the clearer variant.

Only one app on your Mac can control a pair at a time. If another one holds the headphones’
controls (SoundcoreProbe, for instance), the pair shows as unavailable; SoundcoreBar retries every
30 seconds, and **Try Again** retries at once.

## Build from source

Needs only the Xcode Command Line Tools (Swift 6.2 or newer).

```bash
git clone https://github.com/fayiz-jr/SoundCoreBar.git
cd SoundCoreBar
scripts/build-app.sh            # builds build/SoundcoreBar.app
open build/SoundcoreBar.app
scripts/test.sh                 # unit tests
scripts/package-release.sh      # universal .app zip for a release
```

Ad-hoc builds are signed with a designated requirement that matches the bundle identifier, so
macOS keeps the Bluetooth permission across rebuilds. To sign with your own certificate instead:
`SIGN_IDENTITY="Apple Development" scripts/build-app.sh`.

There are no SwiftUI previews without Xcode, so `PanelPreview` stands in:

```bash
swift run PanelPreview build/preview   # PNGs of the panel's states, light and dark (layout only)
swift run PanelPreview --live          # opens the real glass panel briefly and prints its geometry
```

To watch the packets while you use the app:

```bash
/usr/bin/log stream --level debug --predicate 'subsystem == "com.fayizjr.SoundcoreBar"'
```

## Adding your headphones

`SoundcoreProbe` is the tool used to work out each model. It runs as its own app, with its own
Bluetooth permission.

```bash
scripts/probe.sh                               # paired devices, their RFCOMM services, each pair's state
scripts/probe.sh --device Q20i --listen 30     # keep listening; press the noise button to see its packets
scripts/probe.sh --device R50i --set nc        # switch through the app's own code: nc | transparency | normal
```

A model is a small type in `Sources/SoundcoreKit/Models/`: its model number, a word from its
Bluetooth name, the length of its state reply and where the sound-modes block sits in it. Add it to
`HeadphoneModels.all` with a test built from a captured state packet. [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30)
documents the layouts of many more Soundcore models.

If you would rather open an issue, include the probe’s output for your headphones, but **remove
the serial number and Bluetooth address** from it first: the probe prints both.

## How it works

The app opens the headphones’ Soundcore RFCOMM service (`0cf12d31-fac3-4553-bd80-d6832e7…`, or
Serial Port if missing), asks for their state and keeps the channel open for change notices. To
switch, it sends back the last sound-modes block the headphones reported with only the mode byte
changed, resends up to three times without an acknowledgement, and then sends nothing else until
the headphones report the change or two seconds pass.

- `SoundcoreKit`: packet framing, stream reassembly and the per-model layouts. No Bluetooth.
- `SoundcoreBluetooth`: SDP lookup, the RFCOMM connection and connect/disconnect monitoring, all on
  the main thread, where IOBluetooth delivers its callbacks.
- `SoundcoreBarUI` and `SoundcoreBar`: the glass panel and the app.

Things the real headphones do that were worth writing down:

- **Q20i**: the sound-modes block is 6 bytes. With a 4-byte set packet the firmware stored the
  packet’s checksum and a 00 in the two bytes after the block. Button presses arrive as
  `[mode, ff ff ff ff ff]`, and a switch asked for by the app is never announced.
- **R50i NC**: byte 2 of the block stays `00` in every mode, so only byte 0 is changed. Asking for
  the state right after a switch makes the earbuds undo it, often leaving one bud on the old mode
  (7 of 10 switches failed that way, against 0 of 10 when waiting). Its SDP record stores the
  service UUID as a bare UUID rather than a list.

## Credits

SoundcoreBar is built on the protocol research of **[OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30)**
by Kyle Scheuing ([@Oppzippy](https://github.com/Oppzippy)), the open-source Soundcore controller
for Linux, Windows and Android. Its work on the packet format, commands and per-model layouts made
this app possible, and its tests supplied the known-good packets SoundcoreBar is checked against.
No code was copied: SoundcoreBar is an independent Swift implementation, and like OpenSCQ30 it is
licensed under the GPL.

## License

[GPL-3.0-or-later](LICENSE). Copyright © 2026 fayiz-jr.
