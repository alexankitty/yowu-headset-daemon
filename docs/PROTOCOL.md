# YOWU-4GS hardware and protocol notes

How the YOWU-SELKIRK-4GS headset and its USB dongle work, as far as this
project has worked them out, and why the tools do what they do. For using the
tools, see the [main README](../README.md).

- [USB dongle](#usb-dongle)
- [Why audio goes silent, and the fix](#why-audio-goes-silent-and-the-fix)
- [Vendor HID: link state](#vendor-hid-link-state)
- [Consumer-control HID: media keys](#consumer-control-hid-media-keys)
- [Kernel mixer quirk](#kernel-mixer-quirk)
- [Bluetooth LE: LED control](#bluetooth-le-led-control)

## USB dongle

`1908:5566`, reported as "GEMBIRD YOWU-4GS" / "YOWU YOWU-4GS", full speed
(USB 1.1), serial `20121120222026`. One configuration, five interfaces:

| Interface | Class | Contents |
|-----------|-------|----------|
| 0 | Audio control | Playback: USB streaming → feature unit 2 (mute, volume) → headphones. Capture: microphone → feature unit 5 (mute, volume) → USB streaming. |
| 1 | Audio streaming | Playback, alt 1: PCM S16_LE, 2 ch, 48 kHz, isochronous **adaptive** EP `0x02` OUT, 192-byte packets |
| 2 | Audio streaming | Capture, alt 1: PCM S16_LE, 1 ch, 48 kHz, isochronous asynchronous EP `0x82` IN |
| 3 | HID | Consumer control (media keys), interrupt EP `0x83` IN |
| 4 | HID | Vendor page `0xff00`, 64-byte input and output reports, interrupt EPs `0x81` IN / `0x01` OUT |

The kernel binds `snd-usb-audio` to 0–2 and `hid-generic` to 3 and 4. Under
`/dev/input/by-id/` they appear as
`usb-YOWU_YOWU-4GS_<serial>-if03-hidraw` and `…-if04-hidraw`.

## Why audio goes silent, and the fix

The dongle only forwards audio over the radio if the USB audio stream is
started **after** the headset's radio link is up. If the stream is already
running when the headset connects, the headset stays silent, or plays with a
skewed left/right balance, until the stream is restarted. PipeWire often keeps
the stream running (any app holding an output, EasyEffects, …), so the problem
looks random: it only happens if something is playing when the headset
connects.

What the dongle needs is a fresh stream start: endpoint stop, re-prepare,
start. Watching `/proc/asound/<card>/pcm0p/sub0/status` while forcing a
restart:

| Method | ALSA state sequence |
|--------|---------------------|
| `pactl suspend-sink <sink> 1; pactl suspend-sink <sink> 0` (the original manual workaround) | RUNNING → PREPARED → RUNNING |
| `pw-cli send-command <node> Suspend {}` (what `yowu-headsetd` uses) | RUNNING → SETUP/PREPARED → RUNNING, ~20 ms |

Neither closes the device. PipeWire stops the stream and, with clients still
linked, restarts it immediately, so no explicit resume is needed. A suspended
sink (nothing playing) needs nothing: the next playback starts a fresh stream.

Things that were considered and rejected:
- **Toggling the dongle's mute switch:** a USB control request without touching
  the stream, but the user would see the output mute.
- **USB reset or driver unbind:** the sound card disappears and reappears.
- **A kernel quirk:** the kernel can't see the radio link, so it can't time
  the restart.

## Vendor HID: link state

Interface 4 sends 64-byte reports when the headset's radio link changes. No
report ID; byte 0 is `0x12` for all of them:

| Report | Meaning |
|--------|---------|
| `12 00 00 01 00 00 …` | headset disconnected |
| `12 00 00 01 01 00 …` | radio link up |
| `12 00 00 00 00 01 00 01 00 01 00 01 20 00 00 00 23 30 25 11 00 04 23 30 …` | link established, ~2.5 s after link up (around the connect sound) |

The rest of the "established" report is probably a status or settings dump;
it was identical across connects and hasn't been decoded.

`yowu-headsetd` acts on "established". If only "link up" arrives, it falls back
to acting 5 s after link up. The dongle itself stays enumerated while the
headset is off, so these reports are the only connect/disconnect signal.

The output direction of this interface is unexplored. The LED commands don't go
through it: they go to the headset directly over Bluetooth LE, below.

`tools/hidmon.py` prints every report from both HID interfaces with
timestamps. It needs root or the project's udev rule.
[`captures/hidmon.log`](../captures/hidmon.log) is the capture the table above
came from: three off/on cycles plus key presses.

## Consumer-control HID: media keys

Interface 3 sends 3-byte reports `01 <bits> 00`, one bit per key, followed by
`01 00 00` on release:

| Bit | Usage | Key |
|-----|-------|-----|
| `0x01` | `0xe9` | volume up |
| `0x02` | `0xea` | volume down |
| `0x04` | `0xe2` | mute |
| `0x08` | `0xcd` | play/pause |

(The descriptor also declares `0xb5`/`0xb6`/`0xb3`/`0xb4`: next, previous,
fast-forward, rewind.) The kernel handles this as a normal input device; no
tool here touches it.

## Kernel mixer quirk

At probe, `snd-usb-audio` logs:

```
usb 1-6.4: 2:0: sticky mixer values (-128/0/1 => -38), disabling
usb 1-6.4: 5:0: sticky mixer values (-13824/-2305/256 => -4160), disabling
```

The dongle reports nonsensical volume ranges: playback −0.5…0 dB, capture
−54…−9 dB, with odd resolutions. The kernel disables both volume controls and
exposes only the mute switches (`PCM Playback Switch`, `Mic Capture Switch`).
Use software volume. This is unrelated to the silent-audio problem.

## Bluetooth LE: LED control

The headset's LEDs are controlled by the headset itself, over Bluetooth LE,
not through the dongle. This is how the YOWU Android app
(`com.yowu.yowumobile`) does it. The protocol below was decompiled from the
app (frame builder `adapter/s.g()`, constants in `a.java`). The frames
`yowu-led` builds match the app's own constants byte for byte.

### Advertising and GATT

- **Advertising:** the headset advertises as `YOWU-SELKIRK-4GS`, public address,
  connectable `ADV_IND`, with flags `0x01` (LE Limited Discoverable),
  service UUID `0x1802`, and manufacturer data `e4 a9 68 21`. It's dual-mode
  (classic Bluetooth as well); no pairing is needed for LE.
- **GATT:** it repurposes the standard **Immediate Alert** service `0x1802`.
  Its **Alert Level** characteristic `0x2a06` (value handle `0x005b`) has the
  properties **Write Without Response + Notify**. All commands and replies go
  through it.

### LED command

11 bytes:

```
FC 04 01 06  MODE  R  G  B  BRIGHTNESS  SPEED  CHECKSUM
```

| MODE | Meaning |
|------|---------|
| `00` | solid color R,G,B (brightness and speed 0) |
| `01` | effect Natural: shows the current solid color |
| `02` | effect Flash |
| `03` | effect Breath |
| `04` | effect Rhythm |
| `05` | effect Yowu: hard switches between red, green and blue |
| `06` | lights off |
| `07` | lights on |

- **Checksum:** makes all 11 bytes sum to `0x00` mod 256.
- **Effects (`01`–`05`):** R G B are 0. BRIGHTNESS is 1–8. SPEED is a period,
  1 = fastest … 13 = slowest. The app's slider is reversed: byte = 13 − slider
  position.
- **Brightness in solid-color mode and Natural:** ignored. Dim a solid
  color by scaling its RGB values instead.
- **Effect parameters:** none beyond mode, brightness and speed. The effects
  can't be tuned. A smooth fade has to be generated by streaming solid-color
  frames, which very likely costs a flash write per frame.

Examples:

| Command | Bytes |
|---------|-------|
| on | `fc 04 01 06 07 00 00 00 00 00 f2` |
| off | `fc 04 01 06 06 00 00 00 00 00 f3` |
| red | `fc 04 01 06 00 ff 00 00 00 00 fa` |
| Natural, brightness 8, speed 13 | `fc 04 01 06 01 00 00 00 08 0d e3` |

The app's default effect presets, all at brightness 8: Natural speed byte 13,
Flash 3, Breath 4, Rhythm 1, Yowu 1. Its built-in colors:

| Name | RGB |
|------|-----|
| blue | 0, 0, 255 |
| red | 255, 0, 0 |
| green | 0, 255, 0 |
| peach | 255, 10, 21 |
| orange | 255, 64, 0 |
| wathet | 0, 160, 255 |
| cyan | 0, 255, 112 |
| white | 255, 255, 255 |
| purple | 255, 0, 200 |
| yellow | 255, 150, 0 |

### Status notification

After every write, the headset notifies its state on the same characteristic:

```
FC 03 01 05  STATE  R  G  B  00  CHECKSUM
```

- **`STATE`:** the high nibble is lights on (1) or off (0); the low nibble is
  the current effect (1–5).
- **`R G B`:** the current solid color, kept separately from the effect. A
  solid-color command leaves the headset in effect 1, Natural.

For example, `fc 03 01 05 01 ff 0a 15 00 dc` means lights off, Natural, color
peach.

### Connection behavior

- **Classic vs LE:** BlueZ may try to connect over classic Bluetooth, which
  fails with `br-connection-key-missing` because the headset isn't paired.
  `yowu-led` sets the device's `PreferredBearer` to `le` before each connection.
  BlueZ forgets this whenever it drops the device from its cache.
- **Readiness:** after joining the dongle, the headset advertises right away
  but ignores LE connection requests for roughly 15–20 s. A connection attempt
  in that window either fails with HCI error `0x3e` (Connection Failed to be
  Established) or hangs.
- **bleak's retry loop:** on `le-connection-abort-by-local` (`0x3e`), bleak
  re-dials immediately and indefinitely. Against this headset that turns into
  a flood of connect/disconnect cycles, and it rarely gets through. `yowu-led`
  bypasses it. It makes one `org.bluez.Device1.Connect` call per attempt, and
  only after a fresh advertisement has been seen. Each attempt is capped at
  4 s, with 2 s between attempts. Once the link is up, bleak attaches to the
  existing connection without dialling.
- **Timing:** when the headset is ready, connect, service discovery and the
  write take under 2 s. In btmon, the LE connection completed 95 ms after the
  connect request.
- **Coexistence:** LE control works while the headset is connected to the
  dongle.
