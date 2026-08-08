#!/usr/bin/env python3
"""Writes to Steam's configuration files.

Steam reads its configuration when it starts and rewrites it from the copy it
holds in memory when it exits: any change applied while it runs is lost with no
warning. This tool therefore assumes Steam is already closed; the calling
module is what guarantees that.

Two operations, independent of each other:

  --shortcut-name   add a non-Steam entry to shortcuts.vdf (binary format)
  --proton          set the global default compatibility tool in config.vdf
                    (text format)
"""

import argparse
import os
import shutil
import sys
import time
import zlib

try:
    import vdf
except ImportError:
    sys.exit("the Python 'vdf' module is missing: install it into a virtual "
             "environment with 'python3 -m venv <dir> && <dir>/bin/pip install vdf'")


def backup(path):
    """Copy the file next to the original, stamped with the time."""
    if not os.path.exists(path):
        return None
    copy = f"{path}.backup-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(path, copy)
    return copy


# ---------------------------------------------------------------------------
# Non-Steam entries
# ---------------------------------------------------------------------------

def compute_appid(exe, name):
    """The identifier Steam assigns to a non-Steam entry.

    It is the CRC-32 of the executable and the name concatenated, with the top
    bit forced to 1. Recomputing it with the same formula is what makes the
    operation repeatable: the same entry always yields the same value, so a
    second run recognises it instead of duplicating it.
    """
    key = f'"{exe}"{name}'.encode("utf-8")
    return zlib.crc32(key) | 0x80000000


def add_shortcut(path, name, exe, arguments, start_dir, icon):
    if os.path.exists(path):
        with open(path, "rb") as handle:
            try:
                data = vdf.binary_load(handle)
            except Exception:
                print("  shortcuts.vdf is unreadable: recreating it", file=sys.stderr)
                data = {"shortcuts": {}}
    else:
        data = {"shortcuts": {}}

    entries = data.setdefault("shortcuts", {})

    for _key, entry in entries.items():
        if entry.get("AppName") == name or entry.get("appname") == name:
            print(f"  entry already present: {name}")
            return False

    appid = compute_appid(exe, name)
    index = str(len(entries))
    entries[index] = {
        "appid": appid - 0x100000000 if appid > 0x7FFFFFFF else appid,
        "AppName": name,
        "Exe": f'"{exe}"',
        "StartDir": f'"{start_dir}"',
        "icon": icon,
        "ShortcutPath": "",
        "LaunchOptions": arguments,
        "IsHidden": 0,
        "AllowDesktopConfig": 1,
        "AllowOverlay": 1,
        "OpenVR": 0,
        "Devkit": 0,
        "DevkitGameID": "",
        "DevkitOverrideAppID": 0,
        "LastPlayTime": 0,
        "FlatpakAppID": "",
        "tags": {},
    }

    backup(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        vdf.binary_dump(data, handle)
    print(f"  entry added: {name}")
    return True


# ---------------------------------------------------------------------------
# Default compatibility tool
# ---------------------------------------------------------------------------

def find_branch(root, *names):
    """Walk config.vdf ignoring differences in key capitalisation.

    Steam builds do not agree on it: both 'Valve' and 'valve' appear depending
    on the build, and a literal lookup would fail on half the installations.
    """
    node = root
    for name in names:
        found = None
        for key in node:
            if key.lower() == name.lower():
                found = key
                break
        if found is None:
            node[name] = {}
            found = name
        node = node[found]
    return node


def set_default_proton(path, version):
    if not os.path.exists(path):
        print(f"  config.vdf is missing: {path}", file=sys.stderr)
        return False

    with open(path, encoding="utf-8") as handle:
        data = vdf.load(handle)

    steam = find_branch(data, "InstallConfigStore", "Software", "Valve", "Steam")
    mapping = steam.setdefault("CompatToolMapping", {})

    current = mapping.get("0", {}).get("name", "")
    if current == version:
        print(f"  default already set: {version}")
        return False

    # Only the "0" key, the global default, is touched: per-title choices stay
    # exactly as the user made them.
    mapping["0"] = {"name": version, "config": "", "priority": "250"}

    backup(path)
    with open(path, "w", encoding="utf-8") as handle:
        vdf.dump(data, handle, pretty=True)
    if current:
        print(f"  default updated: {current} -> {version}")
    else:
        print(f"  default set: {version}")
    return True


# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--userdata", required=True,
                        help="the Steam profile directory (userdata/<id>)")
    parser.add_argument("--config", required=True, help="path to config.vdf")

    parser.add_argument("--shortcut-name")
    parser.add_argument("--shortcut-exe")
    parser.add_argument("--shortcut-args", default="")
    parser.add_argument("--shortcut-dir", default="/usr/bin/")
    parser.add_argument("--shortcut-icon", default="")

    parser.add_argument("--proton", help="name of the default compatibility tool")

    args = parser.parse_args()

    if args.shortcut_name:
        path = os.path.join(args.userdata, "config", "shortcuts.vdf")
        print(f"Non-Steam entry in {path}")
        add_shortcut(path, args.shortcut_name, args.shortcut_exe,
                     args.shortcut_args, args.shortcut_dir, args.shortcut_icon)

    if args.proton:
        print(f"Default compatibility tool in {args.config}")
        set_default_proton(args.config, args.proton)

    # The functions return False when there was nothing to change, which is a
    # correct outcome: the exit status reports real errors only, and those
    # arrive here as exceptions.
    return 0


if __name__ == "__main__":
    sys.exit(main())
