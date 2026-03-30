#!/usr/bin/env python3
"""Validate config.yaml for duplicate ip, mac, and vnc_port in nodes."""

import sys
import yaml


def check_duplicates(config_path):
    with open(config_path) as f:
        config = yaml.safe_load(f)

    nodes = config.get("nodes", [])
    errors = []

    def find_dupes(values, label):
        seen = set()
        for v in values:
            if v in seen:
                errors.append(f"Duplicate {label}: {v}")
            seen.add(v)

    find_dupes([n["ip"] for n in nodes], "ip")
    find_dupes([n["vnc_port"] for n in nodes], "vnc_port")
    find_dupes(
        [iface["mac"] for n in nodes for iface in n.get("interfaces", [])],
        "mac",
    )

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"OK: No duplicates found in {config_path}")


if __name__ == "__main__":
    config_path = sys.argv[1] if len(sys.argv) > 1 else "config.yaml"
    check_duplicates(config_path)
