#!/usr/bin/env python3
"""Print every HID report the YOWU-4GS dongle sends, with timestamps.

Used to find out whether the dongle announces headset link up/down.

    sudo ./tools/hidmon.py | tee captures/hidmon.log

Then power the headset off, wait for it to drop, power it on, wait for the
connect sound, and repeat a couple of times. Press keys on the headset too.
Type a note + Enter at any time to drop a marker into the log.
"""
import os
import select
import sys
import time

BY_ID = "/dev/input/by-id"
SERIAL_PREFIX = "usb-YOWU_YOWU-4GS_"


def find_nodes():
    nodes = {}
    for name in sorted(os.listdir(BY_ID)):
        if name.startswith(SERIAL_PREFIX) and name.endswith("-hidraw"):
            iface = name.rsplit("-", 2)[-2]  # if03 / if04
            nodes[iface] = os.path.realpath(os.path.join(BY_ID, name))
    return nodes


def stamp():
    return time.strftime("%H:%M:%S") + f".{int(time.time() * 1000) % 1000:03d}"


def main():
    nodes = find_nodes()
    if not nodes:
        sys.exit("YOWU hidraw nodes not found - is the dongle plugged in?")

    fds = {}
    for iface, path in nodes.items():
        try:
            fds[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = iface
        except PermissionError:
            sys.exit(f"cannot open {path}: run with sudo")
        print(f"# {iface} = {path}", flush=True)
    print("# listening; type a note + Enter to add a marker, Ctrl-C to quit", flush=True)

    poll = select.poll()
    for fd in fds:
        poll.register(fd, select.POLLIN)
    poll.register(sys.stdin.fileno(), select.POLLIN)

    try:
        while True:
            for fd, _ in poll.poll():
                if fd == sys.stdin.fileno():
                    note = sys.stdin.readline().strip()
                    print(f"{stamp()} MARK {note}", flush=True)
                    continue
                data = os.read(fd, 64)
                print(f"{stamp()} {fds[fd]} [{len(data):2}] {data.hex(' ')}", flush=True)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
