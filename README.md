# SoundcoreBar

A macOS menu bar app that switches Anker Soundcore headphones between Noise Cancelling,
Transparency and Normal, like the AirPods mode switcher. It reads the real mode from the
headphones and follows changes made with their buttons.

Supported: Soundcore Q20i (A3004) and Soundcore R50i NC (A3959). macOS 13 or newer.

## Build and run

Needs only the Xcode Command Line Tools (Swift 6.2 or newer).

```bash
scripts/build-app.sh            # builds build/SoundcoreBar.app (release, ad-hoc signed)
open build/SoundcoreBar.app
```

To keep it, copy `build/SoundcoreBar.app` to `/Applications` and add it under
System Settings › General › Login Items. Quit it from its menu.

### Bluetooth permission

The first launch shows “SoundcoreBar would like to use Bluetooth”. Click **Allow**.

If you clicked Don’t Allow, the menu says “Bluetooth access is off for SoundcoreBar” and offers
to open the settings page. Turn SoundcoreBar on under Privacy & Security › Bluetooth, then quit
and reopen the app.

Rebuilding does not ask again: ad-hoc builds are signed with a designated requirement that
matches the bundle identifier (`com.fayizjr.SoundcoreBar`) rather than the code hash. To sign
with your developer certificate instead, run `SIGN_IDENTITY="Apple Development" scripts/build-app.sh`;
macOS will then ask once more, because the signature’s identity changed.

## Testing with each pair

With the app running and the headphones connected:

1. Click the headphones icon. The menu shows the headphones’ name, then the three modes with a
   checkmark on the current one. With both pairs connected, each gets its own section.
2. Pick another mode. You hear the change, and the checkmark moves once the headphones confirm.
3. Change the mode with the headphones (Q20i: the noise cancelling button; R50i NC: press and
   hold an earbud). Open the menu again: the checkmark follows.
4. Turn the headphones off or disconnect them in Bluetooth settings. Their section disappears;
   with nothing connected the menu says “No Soundcore headphones connected” and the modes are
   greyed out.
5. Connect them again. They reappear about two seconds later with the right checkmark.

To watch what happens on the wire:

```bash
/usr/bin/log stream --level debug --predicate 'subsystem == "com.fayizjr.SoundcoreBar"'
```

(`/usr/bin/log`, because zsh has its own `log` builtin.)

## Unit tests

```bash
scripts/test.sh
```

They use packets captured from both pairs and OpenSCQ30’s known-good set-sound-modes packets.

## Probe

`SoundcoreProbe` is the diagnostic tool used to work out the protocol. It runs as its own app,
so it has its own Bluetooth permission.

```bash
scripts/probe.sh                          # list paired devices and RFCOMM services, dump each pair's state
scripts/probe.sh --device Q20i --listen 30   # keep listening; press the mode button to see its packets
scripts/probe.sh --device R50i --set nc   # switch through the app's connection code (nc|transparency|normal)
```

## How it works

- `SoundcoreKit`: packet framing, stream reassembly and the per-model layouts. No Bluetooth.
- `SoundcoreBluetooth`: SDP lookup, the RFCOMM connection (request/acknowledge/resend) and the
  monitor that follows connects and disconnects. All on the main thread, where IOBluetooth
  delivers its callbacks.
- `SoundcoreBar`: the menu.

The app opens the Soundcore vendor RFCOMM service (`0cf12d31-fac3-4553-bd80-d6832e7xxxxx`, or
Serial Port if missing), sends Request State, and keeps the channel open for change pushes. To
switch, it sends back the last sound-modes block the headphones reported with only the mode byte
changed, and resends up to 3 times without an acknowledgement. It then sends nothing else until
the headphones report the change (the R50i NC does within about a second) or 2 seconds pass, after
which it reads the state to confirm (the Q20i never reports it). Clicks made meanwhile wait, and
only the latest one is sent.

What the real headphones do differently from OpenSCQ30’s description:

- **Q20i**: the sound-modes block is 6 bytes (OpenSCQ30 uses 4). With a 4-byte set packet the
  firmware stored the packet’s checksum and a 00 in the two bytes after the block. Button pushes
  are `[mode, ff ff ff ff ff]`. The state body is 61 bytes.
- **R50i NC**: byte 2 of the block stays `00` in every mode, so only byte 0 is changed
  (OpenSCQ30 also writes the mode into byte 2; on its sibling models that byte is the transparency
  mode). Asking for the state right after a switch makes the earbuds undo it, often leaving one
  bud on the old mode: 7 of 10 switches failed that way, against 0 of 10 when waiting. Its SDP record stores the service UUID
  as a bare UUID rather than a list.

### Adding a model

Add a type conforming to `HeadphoneModel` in `Sources/SoundcoreKit/Models/` (model number, name
keyword, state length, and where the sound-modes block sits), list it in `HeadphoneModels.all`,
and add a test with a captured state packet. Use the probe to capture one.

Protocol knowledge comes from [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30) (GPL-3.0); no
code was copied from it.
