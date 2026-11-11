#!/usr/bin/env python3
"""Simulate NickelMenu's ':' split and the quiet: command prefix."""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "nm_kobosync").read_text().splitlines()


def split_once(line):
    if line is None or ":" not in line:
        return None, None
    left, right = line.split(":", 1)
    return left.strip(), right


def parse_action(line):
    action, rest = split_once(line)
    if rest is None:
        raise AssertionError(f"missing action: {line}")
    return action, rest.strip()


def commands(path_lines):
    found = []
    for raw in path_lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        kind, rest = split_once(line)
        if kind == "menu_item":
            _loc, rest = split_once(rest)
            _label, rest = split_once(rest)
            action, arg = parse_action(rest)
            found.append((action, arg))
        elif kind == "chain_always":
            action, arg = parse_action(rest)
            found.append((action, arg))
        else:
            raise AssertionError(f"unexpected line: {line}")
    return found


def shell_command(arg):
    if arg.startswith("quiet:"):
        return arg[len("quiet:") :]
    return arg


def main():
    items = commands(CONFIG)
    spawns = [shell_command(arg) for action, arg in items if action == "cmd_spawn"]
    outputs = [arg for action, arg in items if action == "cmd_output"]
    if spawns != [
        "sh /mnt/onboard/.adds/dogear/kobo-sync.sh manual",
        "sh /mnt/onboard/.adds/dogear/kobo-sync.sh manual",
    ]:
        raise SystemExit(f"spawn commands changed: {spawns}")
    if outputs != ["4000:sh /mnt/onboard/.adds/dogear/kobo-sync.sh status"]:
        raise SystemExit(f"status command changed: {outputs}")
    # The shipped 2024 config split "quiet" into the command name.
    old = "menu_item :main    :Sync highlights :cmd_spawn :quiet :sh /mnt/onboard/.adds/dogear/kobo-sync.sh"
    _kind, rest = split_once(old.strip())
    _loc, rest = split_once(rest)
    _label, rest = split_once(rest)
    _action, arg = parse_action(rest)
    if shell_command(arg) == "sh /mnt/onboard/.adds/dogear/kobo-sync.sh":
        raise SystemExit("old config unexpectedly parsed as the sync script")
    if not shell_command(arg).startswith("quiet"):
        raise SystemExit(f"old config regression fixture drifted: {arg}")
    text = CONFIG
    blob = "\n".join(text)
    if "service_role" in blob or "SUPABASE_" in blob:
        raise SystemExit("menu file should not contain credentials")
    print("nm config ok")


if __name__ == "__main__":
    main()
