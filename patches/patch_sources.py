#!/usr/bin/env python3
"""Apply the small source edits used to rebuild Sanalika's SWFs."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


def source_file(root: Path, name: str) -> Path:
    matches = list(root.rglob(name))
    if len(matches) != 1:
        raise RuntimeError(f"expected one {name} under {root}, found {len(matches)}")
    return matches[0]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def read_source(path: Path) -> tuple[str, str]:
    raw = path.read_bytes()
    newline = "\r\n" if b"\r\n" in raw else "\n"
    return raw.decode("utf-8"), newline


def write_source(path: Path, text: str, newline: str) -> None:
    text = text.replace("\r\n", "\n").replace("\n", newline)
    path.write_bytes(text.encode("utf-8"))


def patch_main(root: Path) -> None:
    path = source_file(root, "LoaderModel.as")
    text, newline = read_source(path)
    text = replace_once(
        text,
        "var _loc1_:String = SanalikaClient.instance.config.loader;",
        'var _loc1_:String = "app:/ml-patched.swf";',
        "main loader URL",
    )
    write_source(path, text, newline)


def patch_preloader(root: Path) -> None:
    path = source_file(root, "MainLoader.as")
    text, newline = read_source(path)
    text = replace_once(
        text,
        'if(Capabilities.playerType == "Desktop" || Capabilities.manufacturer == "Android Linux")',
        'if(params.serverName != null || Capabilities.playerType == "Desktop" || Capabilities.manufacturer == "Android Linux")',
        "preloader parameter forwarding",
    )
    if "var _loc4_:Number = NaN;" in text:
        text = replace_once(
            text,
            "var _loc4_:Number = NaN;",
            "var _loc4_:Number = Number(NaN);",
            "preloader NaN compatibility",
        )
    write_source(path, text, newline)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=("main", "preloader"), required=True)
    parser.add_argument("source_root", type=Path)
    args = parser.parse_args()
    try:
        {"main": patch_main, "preloader": patch_preloader}[args.kind](args.source_root)
    except (OSError, RuntimeError) as exc:
        print(f"patch-sources: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
