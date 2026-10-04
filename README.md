# yowu-headset

Linux support tools for the YOWU-SELKIRK-4GS wireless headset and its USB
dongle (`1908:5566`, "GEMBIRD YOWU-4GS"):

- **`yowu-headsetd`**: user daemon that fixes the headset staying silent (or
  coming up with a skewed L/R balance) after it connects. It can also set
  the headset's LEDs, e.g. turn them off, each time the headset connects.
- **`yowu-toggle`**: switch the default audio output between the headset and
  another output (speakers, HDMI, …), meant for a hotkey.
- **`yowu-led`**: control the headset's LEDs over Bluetooth LE: on/off,
  colors, effects, and a smooth color cycle.

## Requirements

- Linux with systemd (user services) and udev
- Python 3.8+
- PipeWire, with its `pw-dump` and `pw-cli` tools, for the audio fix
- For LED control only: BlueZ, a Bluetooth adapter with LE support, and
  [bleak](https://github.com/hbldh/bleak). Tested with bleak 3.0.

## Install

### Arch Linux

```sh
cd packaging/arch
makepkg -si
sudo pacman -S --asdeps python-bleak     # for LED control
systemctl --user enable --now yowu-headsetd
```

Then unplug and replug the dongle once so the udev rule applies. The
PKGBUILD builds from this checkout; to publish it on the AUR, point `source=`
at a real repository (see the comment at the top of the PKGBUILD).

### Other distributions

Install the dependencies, then use the Makefile:

| Distribution | Dependencies |
|--------------|--------------|
| Debian 12+, Ubuntu 24.04+ | `sudo apt install python3 pipewire-bin python3-bleak` |
| Fedora | `sudo dnf install python3 pipewire-utils`, plus bleak from a venv (below) |
| openSUSE | `sudo zypper install python3 pipewire-tools`, plus bleak from a venv (below) |

These packages provide `pw-dump` and `pw-cli`. Debian and
Ubuntu ship bleak 0.20–0.22, which is older than the tested 3.0. If
`yowu-led` misbehaves there, use a venv with a current bleak instead.

```sh
sudo make install           # into /usr/local; the udev rule goes to /etc/udev/rules.d
sudo udevadm control --reload
systemctl --user daemon-reload
systemctl --user enable --now yowu-headsetd
```

Then replug the dongle. `sudo make uninstall` removes everything except
`/etc/yowu-headset/headsetd.conf`.

**bleak from a venv:** for distros without a bleak package, or to get a
newer one. The Makefile rewrites the scripts' interpreter line to use the
venv:

```sh
sudo python3 -m venv /opt/yowu-headset/venv
sudo /opt/yowu-headset/venv/bin/pip install bleak
sudo make clean install PYTHON=/opt/yowu-headset/venv/bin/python
```

The audio daemon doesn't need bleak, so skip this if you don't want LED
control.

**Packagers:** `make install DESTDIR=… PREFIX=/usr
UDEVRULESDIR=/usr/lib/udev/rules.d`. This installs the tools, the udev rule,
the systemd **user** unit (don't enable it globally on the user's behalf), a
default `/etc/yowu-headset/headsetd.conf` (mark it as a config file), and docs.

### Per-user install (no package)

```sh
./install.sh     # into ~/.local; sudo is used for the udev rule only
```

| File | Purpose |
|------|---------|
| `/etc/udev/rules.d/70-yowu-headset.rules` | lets your user read the dongle's HID nodes |
| `~/.local/bin/yowu-headsetd`, `~/.local/bin/yowu-led` | the tools |
| `~/.config/yowu-headset/headsetd.conf` | daemon config (only if it doesn't exist yet) |
| `~/.config/systemd/user/yowu-headsetd.service` | user service, enabled and started |

Don't combine this with a package or `make install`: the per-user unit in
`~/.config` would shadow the packaged one. If you switch, run
`./uninstall.sh --only user` afterwards (see below).
Otherwise the per-user unit in `~/.config` shadows the packaged one.

### After installing

If the service says it can't open the hidraw node, replug the dongle once so
the udev rule applies.

Logs: `journalctl --user -u yowu-headsetd -f`

## Uninstall

```sh
./uninstall.sh            # shows what it found and asks before removing anything
./uninstall.sh -n         # only show
./uninstall.sh --purge    # also delete /etc/yowu-headset and ~/.config/yowu-headset
./uninstall.sh --only user|make|package   # remove just one install type
```

It finds every install method this project supports: the per-user
`./install.sh`, `make install` into `/usr/local`, and the Arch package (removed
with `pacman -R`). It stops and disables the user service and reloads udev.
Configs are kept unless you pass `--purge`. With `--only`, the service is
restarted on whichever install remains, and the shared `/etc` udev rule is
kept if that install still needs it.

`sudo make uninstall` and `sudo pacman -R yowu-headset` still work on their
own; they just don't touch the user service.

## yowu-headsetd

### The problem

The dongle only forwards audio to the headset if the USB audio stream is
started **after** the headset's radio link is up. Under PipeWire, the stream is
often already running when the headset is switched on. The headset connects
(you hear the connect sound) but gets no audio, or audio with a skewed balance,
until the stream is restarted. If nothing happens to be playing when the
headset connects, the stream starts fresh on the next play and everything
works, which is why the problem seems random.

### The fix

The dongle reports link state on its vendor HID interface (interface 4, usage
page `0xff00`, 64-byte reports):

| Report | Meaning |
|--------|---------|
| `12 00 00 01 00 00 …` | headset disconnected |
| `12 00 00 01 01 00 …` | radio link up |
| `12 00 00 00 00 01 00 01 00 01 00 01 20 …` | link established, ~2.5 s after link up |

The daemon waits for "link established", then restarts the stream natively:
it sends the YOWU sink's PipeWire node a `Suspend` command (`pw-cli
send-command <id> Suspend {}`). PipeWire stops the ALSA stream and, with
clients still connected, restarts it within ~20 ms, so the dongle sees a
fresh stream start with the link already up. If the sink is already suspended
(nothing playing), it's left alone: the next playback starts a fresh stream
anyway. If the established report never arrives, the restart happens 5 s after
link up instead. The daemon survives the dongle being unplugged and replugged.

### Configuration

`/etc/yowu-headset/headsetd.conf` (system-wide), overridden setting by
setting by `~/.config/yowu-headset/headsetd.conf`. See
[`config/headsetd.conf.example`](config/headsetd.conf.example). The shipped
default leaves the LEDs alone. All settings, with the LEDs turned off on
connect:

```ini
[audio]
# wait after "link established" before restarting the stream
delay = 0.5

[led]
# yowu-led command to run when the headset connects; empty = leave LEDs alone
on_connect = off
# headset BLE address; empty = scan for YOWU-SELKIRK-4GS
address =
# seconds after "link established" before the first attempt
delay = 5
# seconds to keep retrying after that
timeout = 90
```

Comments must be on their own line. A `#` after a value is part of the
value, which is what lets `on_connect = color #ff8000` work.

`on_connect` takes any one-shot `yowu-led` command: `off`, `on`,
`color purple`, `effect breath -b 3`, … `cycle` isn't allowed here (see the
flash warning below).

The headset advertises right after joining the dongle, but only accepts BLE
connections about 15–20 s later, so the LEDs can't be changed any sooner than
that. So the command runs in the background `delay` seconds after "link
established", as `yowu-led -w <timeout>`, which keeps retrying every 2 s
(see below). It never delays the audio fix. If the headset disconnects first,
the attempt is cancelled. Output goes to the journal.

Apply changes with `systemctl --user restart yowu-headsetd`.

Command-line flags override the config: `--delay`,
`--led-on-connect CMD` (`''` disables), `-c FILE`, `--dry-run`, `-v` (log every
HID report), `--device /dev/hidrawN`.

## yowu-toggle

Flips the default audio output between the headset and one other output of
your choice. Bind it to a hotkey.

```sh
yowu-toggle set-other     # pick the non-headset output once (menu); saved to your config
yowu-toggle               # toggle; shows a desktop notification
yowu-toggle headset       # or switch explicitly
yowu-toggle other
yowu-toggle list          # all outputs, with the default/headset/other marked
```

- When the headset is the default, it switches to the other output; otherwise
  it switches to the headset.
- The choice is saved as `[toggle] other_sink` (a PipeWire `node.name`, which
  is stable across reboots) in `~/.config/yowu-headset/headsetd.conf`.
- Notifications use `notify-send` (libnotify). Turn them off with `-q` or
  `[toggle] notify = false`. Errors such as an unplugged dongle or a missing
  output are shown as notifications too, since a hotkey has no terminal.
- It works natively: it reads the default with `pw-dump` and sets it with
  `pw-metadata` (`default.configured.audio.sink`, the same key `wpctl
  set-default` uses). WirePlumber then moves the streams that follow the
  default output, and remembers the choice across restarts.

### Switching automatically

`yowu-headsetd` can switch the default for you:

```ini
[toggle]
# set with yowu-toggle set-other
other_sink = alsa_output.pci-0000_00_1f.3.analog-stereo
# headset becomes the default when it connects
switch_on_connect = true
# other_sink becomes the default when it disconnects
switch_on_disconnect = true
```

The connect switch happens at "link established", alongside the stream
restart. The disconnect switch also fires when the dongle is unplugged. It
only applies while the headset is the default (`yowu-toggle
--only-if-headset`), so if you had moved to another output yourself, it's left
alone. Both are off by default.

Switching away and back is also the manual fix for the skewed-balance problem
described above, so this doubles as a one-key workaround if it ever comes up
again.

Hotkey examples:

```
# Hyprland
bind = SUPER, F12, exec, yowu-toggle
# Sway / i3
bindsym $mod+F12 exec yowu-toggle
```

In GNOME or KDE, add a custom shortcut that runs `yowu-toggle`.

## yowu-led

The dongle can't control the LEDs. The headset itself takes LED commands over
Bluetooth LE, the same way the YOWU Android app does it. The headset must be
on but doesn't need to be paired, and this works while it's connected to the
dongle.

```sh
yowu-led on | off
yowu-led color purple             # blue red green peach orange wathet cyan white purple yellow
yowu-led color '#ff8000'          # or r,g,b
yowu-led color purple -b 3        # dimmed: brightness 1..8 scales the color
yowu-led effect breath -b 5 -s 8  # natural flash breath rhythm yowu; brightness 1..8, speed 1..13
yowu-led -n effect yowu           # print the frames without sending them
```

The headset ignores the brightness byte for solid colors and the Natural
effect, which just shows the current solid color. So `color -b` dims by
scaling the RGB values instead, and `effect natural -b` has no effect
(yowu-led says so).

Color and effect commands turn the lights on first, like the app requires
(`--no-on` skips this). After each command, `yowu-led` prints the state the
headset reports back. `-a ADDR` scans for that address instead of the name;
`-t SECONDS` sets how long to scan for the headset (default 10).

Each connection attempt is a single BlueZ `Connect` call made after a fresh
advertisement from the headset has been seen. bleak's own connect is
deliberately bypassed: when the headset doesn't answer (HCI error `0x3e`,
`le-connection-abort-by-local`), bleak re-dials immediately and indefinitely,
flooding the headset with connect/disconnect cycles. Each attempt gives up
after `--connect-timeout` seconds (default 4; a good connection takes under
2 s). By default `yowu-led` tries once. With `-w SECONDS` it retries every 2 s
until that many seconds have passed.

### Smooth color cycle

The firmware's effects can't be tuned: the effect command only carries mode,
brightness and speed, and "yowu" hard-switches between red, green and blue.
`yowu-led cycle` generates a smooth rainbow on the PC instead, streaming
solid-color frames along a hue wheel. It holds the BLE connection while it
runs, reconnects if the headset drops, and stops on Ctrl-C, leaving the last
color showing.

> [!WARNING]
> **`cycle` will wear out the headset's flash memory if run for long.**
> The headset most likely saves its color to internal flash on every change,
> so every update is probably a flash write. At the default 10 updates/s
> that's ~36,000 writes per hour, and cheap flash is often rated for only
> 10k–100k erase cycles. Long or always-on use will likely kill the
> headset's storage and may brick it. Use it for short sessions only, with a
> low `--fps` and a long `--period`. Don't run it as a service.
>
> `cycle` refuses to start unless you pass `--i-know-this-wears-flash`.

```sh
yowu-led cycle --i-know-this-wears-flash              # 10 s per rotation, 10 updates/s
yowu-led cycle --i-know-this-wears-flash -p 30 -f 3   # slower, fewer writes
yowu-led cycle --i-know-this-wears-flash -b 4 --saturation 0.7
```

### Protocol

Decompiled from the YOWU Android app (`com.yowu.yowumobile`, frame builder
`adapter/s.g()`). The frames `yowu-led` builds match the app's own constants
byte for byte.

The headset advertises as `YOWU-SELKIRK-4GS` (public address, connectable
`ADV_IND`). It repurposes the standard Immediate Alert service `0x1802`: the
Alert Level characteristic `0x2a06` is Write Without Response + Notify. LED
commands are 11 bytes:

```
FC 04 01 06  MODE  R  G  B  BRIGHTNESS  SPEED  CHECKSUM
```

| MODE | Meaning |
|------|---------|
| `00` | solid color R,G,B |
| `01`–`05` | effects Natural, Flash, Breath, Rhythm, Yowu; brightness 1–8 (ignored by Natural), speed byte 1 = fastest … 13 = slowest |
| `06` / `07` | lights off / on |

The checksum byte makes all bytes sum to `0x00` mod 256. After every write, the
headset notifies its state:

```
FC 03 01 05  STATE  R  G  B  00  CHECKSUM
```

The high nibble of `STATE` is lights on (1) or off (0), the low nibble is the
current effect (1–5), and `R G B` is the current solid color.

## Other notes

- Dongle interface 3 is a standard consumer-control HID (`01 01` vol+, `01 02`
  vol−, `01 04` mute, `01 08` play/pause). The kernel already handles it as an
  input device.
- At probe, the kernel logs `sticky mixer values … disabling` for both feature
  units. The dongle reports nonsensical volume ranges (playback −0.5…0 dB), so
  only the mute switches are exposed. This doesn't affect the no-audio
  problem; use software volume.

## Repository layout

```
yowu-headsetd                  daemon
yowu-led                       LED control CLI
yowu-toggle                    default output toggle
config/headsetd.conf.example   default daemon config
systemd/, udev/                service unit template and udev rule
Makefile                       system-wide install (PREFIX/DESTDIR)
packaging/arch/                PKGBUILD
install.sh                     per-user install into ~/.local
uninstall.sh                   removes any of the install methods
tools/hidmon.py                dump the dongle's HID reports (root, or the udev rule)
captures/hidmon.log            the HID capture the link-state table came from
```
