#!/usr/bin/env bash
# Remove yowu-headset however it was installed: per-user (./install.sh),
# system-wide (make install), or as the Arch package. Run as your normal user;
# sudo is used only where needed.
#
#   ./uninstall.sh            show what will be removed, ask, then remove it
#   ./uninstall.sh -n         only show what would be removed
#   ./uninstall.sh -y         don't ask
#   ./uninstall.sh --purge    also remove config files (/etc and ~/.config)
#   ./uninstall.sh --only user|make|package
#                             remove just one install type, e.g. leftovers of a
#                             per-user install after switching to the package
set -euo pipefail

dry_run=0 assume_yes=0 purge=0 only=""
while (( $# )); do
    case $1 in
        -n|--dry-run) dry_run=1 ;;
        -y|--yes) assume_yes=1 ;;
        --purge) purge=1 ;;
        --only) only=${2:-}; shift ;;
        --only=*) only=${1#--only=} ;;
        -h|--help) sed -n '2,13s/^# \{0,1\}//p' "$0"; exit 0 ;;
        *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done
case $only in
    ""|user|make|package) ;;
    *) echo "--only takes user, make or package" >&2; exit 2 ;;
esac
want() { [[ -z $only || $only == "$1" ]]; }

user_conf=${XDG_CONFIG_HOME:-$HOME/.config}/yowu-headset
user_files=() root_files=() package=""

add_if_exists() {  # add_if_exists user|root PATH...
    local list=$1; shift
    for f in "$@"; do
        [[ -e $f ]] || continue
        if [[ $list == user ]]; then user_files+=("$f"); else root_files+=("$f"); fi
    done
}

# Per-user install (./install.sh)
if want user; then
    add_if_exists user ~/.local/bin/yowu-headsetd ~/.local/bin/yowu-led ~/.local/bin/yowu-toggle \
        ~/.config/systemd/user/yowu-headsetd.service
fi
# make install (default PREFIX=/usr/local)
if want make; then
    add_if_exists root /usr/local/bin/yowu-headsetd /usr/local/bin/yowu-led /usr/local/bin/yowu-toggle \
        /usr/local/lib/systemd/user/yowu-headsetd.service /usr/local/share/doc/yowu-headset
fi
# Arch package
if want package && command -v pacman >/dev/null && pacman -Q yowu-headset >/dev/null 2>&1; then
    package=yowu-headset
fi
# The /etc udev rule is shared by ./install.sh and make install (the package
# ships its own in /usr/lib). Keep it if an install that needs it stays behind
# and no packaged rule remains to cover it.
if want user || want make; then
    needs_rule=0
    { ! want user && [[ -e ~/.local/bin/yowu-headsetd ]]; } && needs_rule=1
    { ! want make && [[ -e /usr/local/bin/yowu-headsetd ]]; } && needs_rule=1
    pkg_rule=0
    [[ -z $package && -e /usr/lib/udev/rules.d/70-yowu-headset.rules ]] && pkg_rule=1
    if (( ! needs_rule || pkg_rule )); then
        add_if_exists root /etc/udev/rules.d/70-yowu-headset.rules
    fi
fi
if (( purge )); then
    want user && add_if_exists user "$user_conf"
    { want make || want package; } && add_if_exists root /etc/yowu-headset
fi

if (( ${#user_files[@]} + ${#root_files[@]} == 0 )) && [[ -z $package ]]; then
    echo "yowu-headset doesn't appear to be installed."
    exit 0
fi

# Keeping some other install: restart the service on it instead of disabling.
keep_service=0
if [[ -n $only ]]; then
    case $only in
        user) [[ -e /usr/lib/systemd/user/yowu-headsetd.service || -e /usr/local/lib/systemd/user/yowu-headsetd.service ]] && keep_service=1 ;;
        make) [[ -e /usr/lib/systemd/user/yowu-headsetd.service || -e ~/.config/systemd/user/yowu-headsetd.service ]] && keep_service=1 ;;
        package) [[ -e /usr/local/lib/systemd/user/yowu-headsetd.service || -e ~/.config/systemd/user/yowu-headsetd.service ]] && keep_service=1 ;;
    esac
fi

echo "This will:"
if (( keep_service )); then
    echo "  - restart the yowu-headsetd user service on the remaining install"
else
    echo "  - stop and disable the yowu-headsetd user service"
fi
[[ -n $package ]] && echo "  - remove the $package package (sudo pacman -R $package)"
for f in "${user_files[@]}"; do echo "  - delete $f"; done
for f in "${root_files[@]}"; do echo "  - delete $f (sudo)"; done
if (( ! purge )); then
    for f in "$user_conf" /etc/yowu-headset; do
        [[ -e $f ]] && echo "  - keep $f (use --purge to delete)"
    done
fi
(( dry_run )) && exit 0

if (( ! assume_yes )); then
    read -r -p "Continue? [y/N] " answer
    [[ $answer == [yY]* ]] || { echo "aborted"; exit 1; }
fi

# Disable first so the enablement symlink doesn't dangle once a unit file is
# gone; when another install stays, it's re-enabled below.
if (( keep_service )); then
    systemctl --user disable yowu-headsetd.service 2>/dev/null || true
else
    systemctl --user disable --now yowu-headsetd.service 2>/dev/null || true
fi

[[ -n $package ]] && sudo pacman -R --noconfirm "$package"
(( ${#user_files[@]} )) && rm -rf -- "${user_files[@]}"
(( ${#root_files[@]} )) && sudo rm -rf -- "${root_files[@]}"

systemctl --user daemon-reload
if (( keep_service )); then
    systemctl --user enable yowu-headsetd.service
    systemctl --user restart yowu-headsetd.service
fi
if [[ -n $package ]] || (( ${#root_files[@]} )); then
    sudo udevadm control --reload
fi
if (( keep_service )); then
    echo "done; yowu-headsetd now runs from: $(systemctl --user show -p FragmentPath --value yowu-headsetd.service)"
else
    echo "yowu-headset removed."
fi
if [[ -n $package && -e /etc/yowu-headset/headsetd.conf.pacsave ]]; then
    echo "pacman kept your edited system config as /etc/yowu-headset/headsetd.conf.pacsave"
fi
