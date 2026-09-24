#!/usr/bin/env python3
"""Check localized keys used by Swift and format arguments across all languages."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP = ROOT / "Currency Tracker"
LOCALIZATION_FILES = sorted(APP.glob("*.lproj/Localizable.strings"))
REFERENCE_FILE = APP / "zh-Hans.lproj" / "Localizable.strings"
ENTRY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.MULTILINE)
SWIFT_REFERENCES = [
    re.compile(r'\b(?:Text|Button|Label|Picker|TextField|Toggle|sectionTitle|displayPreferencePicker)\s*\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'String\s*\(\s*localized:\s*"((?:[^"\\]|\\.)*)"'),
]
FORMAT = re.compile(r'(?<!%)%(?:\d+\$)?[-+0 #]*\d*(?:\.\d+)?(?:hh|h|ll|l|z|t|j)?([@diuoxXfFeEgGaAcCsSp])')


def entries_for(path: pathlib.Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    entries: dict[str, str] = {}
    for key, value in ENTRY.findall(text):
        if key in entries:
            raise ValueError(f"Duplicate localization key {key!r} in {path}")
        entries[key] = value
    return entries


def arguments(value: str) -> list[str]:
    return FORMAT.findall(value.replace('%%', ''))


def referenced_keys() -> set[str]:
    result: set[str] = set()
    for path in APP.glob('*.swift'):
        code = path.read_text(encoding='utf-8')
        for pattern in SWIFT_REFERENCES:
            for key in pattern.findall(code):
                if '\\(' not in key and (any(ch.isalpha() for ch in key) or any(ord(ch) > 127 for ch in key)):
                    result.add(key)
    welcome = (APP / 'SettingsView.swift').read_text(encoding='utf-8').split('struct FirstRunWelcomeView: View', 1)[1]
    for key in re.findall(r'"((?:[^"\\]|\\.)*)"', welcome):
        if '\\(' not in key and any('\u4e00' <= ch <= '\u9fff' for ch in key):
            result.add(key)
    settings = (APP / 'SettingsView.swift').read_text(encoding='utf-8')
    native_language_names = {'简体中文', '繁體中文', '日本語'}
    for key in re.findall(r'"((?:[^"\\]|\\.)*)"', settings):
        if key not in native_language_names and '\\(' not in key and any('\u4e00' <= ch <= '\u9fff' for ch in key):
            result.add(key)
    return result


def main() -> int:
    if len(LOCALIZATION_FILES) != 11:
        print(f"Expected 11 languages, found {len(LOCALIZATION_FILES)}")
        return 1
    try:
        entries = {path: entries_for(path) for path in LOCALIZATION_FILES}
    except ValueError as error:
        print(error)
        return 1
    reference = entries[REFERENCE_FILE]
    failed = False
    missing_references = sorted(referenced_keys() - reference.keys())
    if missing_references:
        failed = True
        print(f"Swift references {len(missing_references)} missing localization key(s):")
        for key in missing_references:
            print(f"  - {key}")
    for path, translations in entries.items():
        missing = sorted(reference.keys() - translations.keys())
        extra = sorted(translations.keys() - reference.keys())
        mismatched = [key for key in reference.keys() & translations.keys()
                      if sorted(arguments(reference[key])) != sorted(arguments(translations[key]))]
        if missing or extra or mismatched:
            failed = True
            print(f"{path.relative_to(ROOT)}: {len(missing)} missing, {len(extra)} extra, {len(mismatched)} format mismatch")
            for key in missing:
                print(f"  missing: {key}")
            for key in extra:
                print(f"  extra: {key}")
            for key in mismatched:
                print(f"  format: {key} -> {arguments(translations[key])}, expected {arguments(reference[key])}")
    if failed:
        return 1
    print(f"All {len(reference)} keys, Swift references, and format arguments match across 11 languages.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
