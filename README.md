# yowu-headset

Linux tools for the YOWU-SELKIRK-4GS wireless headset and its USB dongle
(`1908:5566`, "GEMBIRD YOWU-4GS"):

- **`yowu-headsetd`**: background service that fixes the headset staying
  silent (or playing with a skewed left/right balance) after it connects.
  Optionally it also sets the LEDs and switches the default audio output on
  connect/disconnect.
- **`yowu-toggle`**: switch the default audio output between the headset and
  another output (speakers, HDMI, …). Made for a hotkey.
- **`yowu-led`**: control the headset's LEDs over Bluetooth LE: on/off,
  colors, effects, and a smooth color cycle.

How the hardware works, and why the tools do what they do, is in
[docs/PROTOCOL.md](docs/PROTOCOL.md).

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Uninstall](#uninstall)
- [yowu-headsetd](#yowu-headsetd)
- [yowu-toggle](#yowu-toggle)
- [yowu-led](#yowu-led)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Repository layout](#repository-layout)

## Requirements

- Linux with systemd (user services) and udev
- Python 3.8+
- PipeWire with its `pw-dump`, `pw-cli` and `pw-metadata` tools, and
  WirePlumber (for `yowu-toggle` moving playing streams)
- For LED control only: BlueZ, a Bluetooth adapter with LE support, and
  [bleak](https://github.com/hbldh/bleak). Tested with bleak 3.0.
- Optional: `notify-send` (libnotify) for `yowu-toggle` notifications

## Install

### Arch Linux

```sh
cd packaging/arch
makepkg -si
sudo pacman -S --asdeps python-bleak libnotify   # LED control, notifications
systemctl --user enable --now yowu-headsetd
```

Then unplug and replug the dongle once so the udev rule applies.

The PKGBUILD builds from this checkout. To publish it on the AUR, point
`source=` at a real repository (see the comment at the top of the PKGBUILD).

### Other distributions

Install the dependencies:

| Distribution | Dependencies |
|--------------|--------------|
| Debian 12+, Ubuntu 24.04+ | `sudo apt install python3 pipewire-bin python3-bleak libnotify-bin` |
| Fedora | `sudo dnf install python3 pipewire-utils libnotify`, plus bleak from a venv (below) |
| openSUSE | `sudo zypper install python3 pipewire-tools libnotify-tools`, plus bleak from a venv (below) |

Then install with the Makefile:

```sh
sudo make install           # into /usr/local; the udev rule goes to /etc/udev/rules.d
sudo udevadm control --reload
systemctl --user daemon-reload
systemctl --user enable --now yowu-headsetd
```

Then replug the dongle.

Debian and Ubuntu ship bleak 0.20–0.22, older than the tested 3.0. If
`yowu-led` misbehaves there, or your distro has no bleak package, use a venv.
The Makefile rewrites the scripts' interpreter line to point at it:

```sh
sudo python3 -m venv /opt/yowu-headset/venv
sudo /opt/yowu-headset/venv/bin/pip install bleak
sudo make clean install PYTHON=/opt/yowu-headset/venv/bin/python
```

Only `yowu-led` needs bleak. Skip this if you don't want LED control.

**Packagers:** `make install DESTDIR=… PREFIX=/usr
UDEVRULESDIR=/usr/lib/udev/rules.d` installs:
- the three tools;
- the udev rule;
- the systemd **user** unit (don't enable it globally on the user's behalf);
- a default `/etc/yowu-headset/headsetd.conf` (mark it as a config file);
- the docs.

### Per-user install (no package)

```sh
./install.sh     # into ~/.local; sudo is used only for the udev rule
```

| File | Purpose |
|------|---------|
| `/etc/udev/rules.d/70-yowu-headset.rules` | lets your user read the dongle's HID nodes |
| `~/.local/bin/yowu-headsetd`, `yowu-led`, `yowu-toggle` | the tools |
| `~/.config/yowu-headset/headsetd.conf` | config (only created if it doesn't exist) |
| `~/.config/systemd/user/yowu-headsetd.service` | user service, enabled and started |

Don't combine this with a package or `make install`: the per-user unit in
`~/.config` would shadow the packaged one. If you switch to a package, run
`./uninstall.sh --only user` afterwards.

## Uninstall

```sh
./uninstall.sh                            # shows what it found and asks first
./uninstall.sh -n                         # only show
./uninstall.sh --purge                    # also delete /etc/yowu-headset and ~/.config/yowu-headset
./uninstall.sh --only user|make|package   # remove just one install type
```

It finds all three install methods: the per-user `./install.sh`, `make install`
into `/usr/local`, and the Arch package (removed with `pacman -R`). It stops and
disables the user service and reloads udev. Configs are kept unless you pass
`--purge`.

With `--only`, the service is restarted on whichever install remains, and the
shared `/etc` udev rule is kept if that install still needs it.

`sudo make uninstall` and `sudo pacman -R yowu-headset` also work on their own;
they just don't touch the user service.

## yowu-headsetd

Runs as a systemd user service and watches the dongle. When the headset
connects, it restarts the audio stream if anything is playing, which fixes
the silent headset and the skewed balance. If nothing is playing, there's
nothing to fix and it does nothing.

Optionally, when the headset connects or disconnects, it also:
- **sets the LEDs**, e.g. turns them off: `[led] on_connect`;
- **makes the headset the default output** on connect:
  `[toggle] switch_on_connect`;
- **switches back to your other output** on disconnect or dongle unplug:
  `[toggle] switch_on_disconnect`. This only happens while the headset is the
  default, so an output you picked yourself stays.

The LEDs can only be changed about 15–20 s after the connect sound, because
the headset ignores Bluetooth LE connections until then. It survives the
dongle being unplugged and replugged.

```sh
journalctl --user -u yowu-headsetd -f       # watch what it does
systemctl --user restart yowu-headsetd      # after changing the config
```

Settings are under [Configuration](#configuration). Command-line flags
override the config:

| Flag | Effect |
|------|--------|
| `--delay SECONDS` | wait after the link is established before restarting the stream |
| `--led-on-connect CMD` | `''` disables |
| `-c FILE` | read only this config file |
| `--dry-run` | log what it would do instead of doing it |
| `-v` | log every HID report |
| `--device /dev/hidrawN` | use this HID node instead of autodetecting |

## yowu-toggle

Flips the default audio output between the headset and one other output of
your choice.

```sh
yowu-toggle set-other     # pick the non-headset output once (numbered menu)
yowu-toggle               # toggle; shows a desktop notification
yowu-toggle headset       # switch explicitly
yowu-toggle other
yowu-toggle list          # all outputs, with default/headset/other marked
```

- **Toggling:** if the headset is the default, it switches to your other
  output; otherwise it switches to the headset. Playing streams that follow
  the default output move along with it.
- **Your choice of other output** is saved as `[toggle] other_sink` in your
  config.
- **Notifications** appear only when the output actually changes. Errors (an
  unplugged dongle, an output that's gone) also show as notifications, since a
  hotkey has no terminal. Turn them off with `-q` or `[toggle] notify = false`.
- **Fixing a skewed balance:** switching away and back also does it, so the
  hotkey doubles as a one-key fix.

Hotkey examples:

```
# Hyprland
bind = SUPER, F12, exec, yowu-toggle
# Sway / i3
bindsym $mod+F12 exec yowu-toggle
```

In GNOME or KDE, add a custom keyboard shortcut that runs `yowu-toggle`.

## yowu-led

The headset must be on but doesn't need to be paired. This works while it's
connected to the dongle.

```sh
yowu-led on
yowu-led off
yowu-led color purple             # blue red green peach orange wathet cyan white purple yellow
yowu-led color '#ff8000'          # or r,g,b
yowu-led color purple -b 3        # dimmed; brightness 1..8
yowu-led effect breath -b 5 -s 8  # natural flash breath rhythm yowu; brightness 1..8, speed 1..13
yowu-led -n effect yowu           # print the bytes without sending them
```

- **Lights on first:** color and effect commands turn the lights on first,
  like the app requires (`--no-on` skips this).
- **Status:** after each command, `yowu-led` prints the state the headset
  reports back.
- **Natural ignores brightness:** it shows the current solid color, so use
  `color <color> -b N` for a dimmed solid color.
- **Retrying:** by default it makes one connection attempt. Use `-w SECONDS` to
  keep retrying, e.g. `-w 60` right after switching the headset on.
- **Other options:** `-a ADDR` targets a specific Bluetooth address, `-t` sets
  the scan time (default 10 s), and `--connect-timeout` caps each attempt
  (default 4 s).

### Smooth color cycle

The built-in effects can't be tuned; "yowu" hard-switches between red, green
and blue. `yowu-led cycle` generates a smooth rainbow on the PC instead,
streaming colors to the headset until you press Ctrl-C. It reconnects if the
headset drops and leaves the last color showing.

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

## Configuration

One file is shared by all three tools:
- **System-wide:** `/etc/yowu-headset/headsetd.conf`.
- **Per user:** `~/.config/yowu-headset/headsetd.conf`. Its settings override
  the system file's, setting by setting.

The shipped default changes nothing beyond the audio fix. All settings, with
example values:

```ini
[audio]
# seconds to wait after the link is established before restarting the stream
delay = 0.5

[led]
# yowu-led command to run when the headset connects; empty = leave the LEDs alone.
# Any one-shot command: off, on, color purple -b 3, effect breath, ... (not cycle)
on_connect = off
# headset Bluetooth address; empty = find it by name
address =
# seconds after the link is established before the first attempt
delay = 5
# seconds to keep retrying after that
timeout = 90

[toggle]
# the non-headset output; easiest to set with `yowu-toggle set-other`
other_sink = alsa_output.pci-0000_00_1f.3.analog-stereo
# desktop notification on each switch
notify = true
# make the headset the default output when it connects
switch_on_connect = true
# switch to other_sink when the headset disconnects or the dongle is unplugged
switch_on_disconnect = true
```

Comments must be on their own line. A `#` after a value is part of the value,
which is what lets `on_connect = color #ff8000` work. Restart the service
after editing: `systemctl --user restart yowu-headsetd`.
[`config/headsetd.conf.example`](config/headsetd.conf.example) is the
commented default.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Service log says it can't open the hidraw node | Replug the dongle once so the udev rule applies. |
| Headset still silent after connecting | Check `journalctl --user -u yowu-headsetd`. Try raising `[audio] delay`. `yowu-toggle` twice also restarts the stream. |
| LEDs take a while to change on connect | Expected: the headset ignores Bluetooth LE for ~15–20 s after connecting. |
| `yowu-led` can't connect | Run it with `-w 60`, or switch the headset off and on. |
| `yowu-toggle` says the other output isn't available | The saved output is gone (unplugged, renamed). Run `yowu-toggle set-other` again. |

## Repository layout

```
yowu-headsetd                  daemon
yowu-toggle                    default output toggle
yowu-led                       LED control
config/headsetd.conf.example   default config
systemd/, udev/                user service template and udev rule
Makefile                       system-wide install (PREFIX/DESTDIR)
packaging/arch/                PKGBUILD
install.sh                     per-user install into ~/.local
uninstall.sh                   removes any of the install methods
docs/PROTOCOL.md               hardware and protocol notes
tools/hidmon.py                dump the dongle's HID reports
captures/hidmon.log            HID capture behind the link-state table
```
