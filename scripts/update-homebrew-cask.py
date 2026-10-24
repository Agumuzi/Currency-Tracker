#!/usr/bin/env python3
"""Sync the Homebrew Cask with a verified GitHub Release ZIP."""

import argparse
import re
from pathlib import Path


CASK_PATH = Path("Casks/currency-tracker.rb")


def parse_version(version: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"Expected a numeric X.Y.Z release version, got: {version!r}")
    return tuple(int(part) for part in version.split("."))


def replace_one(contents: str, pattern: str, replacement: str) -> str:
    updated, count = re.subn(pattern, lambda _: replacement, contents, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(f"Expected one Cask field matching {pattern!r}; found {count}")
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="Published GitHub Release version, without v")
    parser.add_argument("sha256", help="SHA256 of the published ZIP")
    args = parser.parse_args()

    desired_version = parse_version(args.version)
    checksum = args.sha256.lower()
    if not re.fullmatch(r"[0-9a-f]{64}", checksum):
        parser.error("SHA256 must contain exactly 64 hexadecimal characters")

    contents = CASK_PATH.read_text(encoding="utf-8")
    matches = re.findall(r'^  version "([^"]+)"$', contents, flags=re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("Expected exactly one version field in the Cask")
    current_version = parse_version(matches[0])

    if current_version > desired_version:
        print(f"Skipping older release {args.version}; Cask already has {matches[0]}")
        return

    updated = replace_one(contents, r'^  version "[^"]+"$', f'  version "{args.version}"')
    updated = replace_one(updated, r'^  sha256 "[^"]+"$', f'  sha256 "{checksum}"')
    if updated == contents:
        print(f"Cask already matches Currency Tracker {args.version}")
        return

    CASK_PATH.write_text(updated, encoding="utf-8")
    print(f"Updated Cask to Currency Tracker {args.version} (sha256: {checksum})")


if __name__ == "__main__":
    main()
