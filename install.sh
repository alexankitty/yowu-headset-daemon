#!/usr/bin/env bash
# Per-user install of yowu-headsetd and yowu-led into ~/.local. Run as your
# normal user; sudo is only used for the udev rule. For a system-wide install
# use the Makefile or your distro's package instead (see README.md).
set -euo pipefail
cd "$(dirname "$0")"

sudo install -Dm644 udev/70-yowu-headset.rules /etc/udev/rules.d/70-yowu-headset.rules
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=hidraw --action=change

install -Dm755 yowu-headsetd ~/.local/bin/yowu-headsetd
install -Dm755 yowu-led ~/.local/bin/yowu-led
install -Dm755 yowu-toggle ~/.local/bin/yowu-toggle
conf=${XDG_CONFIG_HOME:-$HOME/.config}/yowu-headset/headsetd.conf
if [[ ! -e $conf ]]; then
    install -Dm644 config/headsetd.conf.example "$conf"
    echo "installed default config: $conf"
else
    echo "keeping existing config: $conf (see config/headsetd.conf.example for new options)"
fi

python3 -c 'import bleak' 2>/dev/null ||
    echo "note: python-bleak is not installed; yowu-led needs it (sudo pacman -S python-bleak)"

mkdir -p ~/.config/systemd/user
sed 's|@BINDIR@|%h/.local/bin|g' systemd/yowu-headsetd.service.in \
    > ~/.config/systemd/user/yowu-headsetd.service
systemctl --user daemon-reload
systemctl --user enable yowu-headsetd.service
systemctl --user restart yowu-headsetd.service
sleep 1
systemctl --user --no-pager status yowu-headsetd.service || true
