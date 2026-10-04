# Installing yowu-headset

Back to the [main README](../README.md). Run the commands below from the
repository root.

- [Requirements](#requirements)
- [Install](#install)
  - [Arch Linux](#arch-linux)
  - [Other distributions](#other-distributions)
  - [Per-user install (no package)](#per-user-install-no-package)
- [Uninstall](#uninstall)

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
cd ../..
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
