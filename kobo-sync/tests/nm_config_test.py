#!/usr/bin/env python3
"""Simulate NickelMenu's ':' split, the Dogears label, and the quiet: prefix."""

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


def parse(path_lines):
    items = []
    experimental = []
    for raw in path_lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        kind, rest = split_once(line)
        if kind == "experimental":
            key, val = split_once(rest)
            experimental.append((key, (val or "").strip()))
        elif kind == "menu_item":
            loc, rest = split_once(rest)
            label, rest = split_once(rest)
            action, arg = parse_action(rest)
            items.append({"kind": "item", "loc": loc, "label": label, "action": action, "arg": arg})
        elif kind == "chain_always":
            action, arg = parse_action(rest)
            items.append({"kind": "chain", "loc": "", "label": "", "action": action, "arg": arg})
        else:
            raise AssertionError(f"unexpected line: {line}")
    return experimental, items


def shell_command(arg):
    if arg.startswith("quiet:"):
        return arg[len("quiet:"):]
    return arg


def main():
    experimental, items = parse(CONFIG)
    if experimental != [("menu_main_15505_label", "Dogears")]:
        raise SystemExit(f"button label key changed: {experimental}")

    main_items = [it for it in items if it["kind"] == "item" and it["loc"] == "main"]
    if [it["label"] for it in main_items] != ["Last sync", "Dogears"]:
        raise SystemExit(f"home menu is not Last sync then Dogears: {main_items}")
    if main_items[0]["action"] != "cmd_output" or not main_items[0]["arg"].endswith("kobo-sync.sh last"):
        raise SystemExit(f"Last sync command changed: {main_items[0]}")
    if any(it["action"] == "cmd_spawn" for it in main_items):
        raise SystemExit("home menu still launches a sync")

    for index, it in enumerate(items):
        if it["action"] == "nickel_browser":
            prev = items[index - 1]
            if prev.get("label") != "Dogears" or prev.get("action") != "nickel_wifi":
                raise SystemExit(f"library action is not chained from Dogears: {prev}")

    library = [it for it in items if it["action"] == "nickel_browser"]
    if len(library) != 1:
        raise SystemExit(f"expected one library browser action, got {library}")
    if not library[0]["arg"].startswith("modal:https://") or not library[0]["arg"].endswith("/library"):
        raise SystemExit(f"library URL action is wrong: {library[0]['arg']}")

    spawns = [shell_command(it["arg"]) for it in items if it["action"] == "cmd_spawn"]
    if not spawns or any(cmd != "sh /mnt/onboard/.adds/dogear/kobo-sync.sh manual" for cmd in spawns):
        raise SystemExit(f"sync command changed: {spawns}")
    outputs = {
        (it["loc"], it["label"], it["arg"])
        for it in items
        if it["kind"] == "item" and it["action"] == "cmd_output"
    }
    expected_outputs = {
        ("main", "Last sync", "4000:sh /mnt/onboard/.adds/dogear/kobo-sync.sh last"),
        ("reader", "Status", "4000:sh /mnt/onboard/.adds/dogear/kobo-sync.sh status"),
        ("library", "Status", "4000:sh /mnt/onboard/.adds/dogear/kobo-sync.sh status"),
    }
    if outputs != expected_outputs:
        raise SystemExit(f"status commands changed: {outputs}")

    visible = "\n".join(line for line in CONFIG if line.strip() and not line.strip().startswith("#"))
    if ":quiet :" in visible or "NickelMenu" in visible or "service_role" in visible:
        raise SystemExit("menu file still has the broken quiet prefix, the NickelMenu name, or a credential")
    if "menu_main_15505_label :Dogears" not in visible:
        raise SystemExit("Dogears tab label is missing")

    # The file found on the Kobo on 12 Nov 2026.
    old = "menu_item :main :DogEars :cmd_spawn :quiet :sh /mnt/onboard/.adds/dogear/kobo-sync.sh"
    _kind, rest = split_once(old.strip())
    _loc, rest = split_once(rest)
    _label, rest = split_once(rest)
    _action, arg = parse_action(rest)
    if shell_command(arg).startswith("sh "):
        raise SystemExit("device menu line unexpectedly parsed as the sync script")
    if not shell_command(arg).startswith("quiet"):
        raise SystemExit(f"device menu fixture drifted: {arg}")
    print("nm config ok")


if __name__ == "__main__":
    main()
