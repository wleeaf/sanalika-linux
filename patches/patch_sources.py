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
        "ENCRYPTED_SWF_URL = params.cs;",
        'ENCRYPTED_SWF_URL = "app:/core-patched.swf";',
        "preloader core URL",
    )
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


def patch_core(root: Path) -> None:
    init_path = source_file(root, "InitParamsCommand.as")
    text, newline = read_source(init_path)
    start_marker = "         _loc1_ = _params.d;"
    end_marker = "         Sanalika.instance.gameModel.serverName = _loc2_.serverName;"
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise RuntimeError("core parameter initialization block was not found")
    replacement = """         _loc1_ = _params.d;
         // AIR supplies the instance parameters through LoaderContext.
         // Wine may report a non-desktop player type, so do not use the
         // browser-only ExternalInterface fallback here.
         _loc2_ = _params;
         if(_loc2_ == null)
         {
            _loc2_ = {};
         }
         if(_loc2_.serverName == null)
         {
            _loc2_.serverName = "turkey";
         }
"""
    text = text[:start] + replacement + text[end:]
    write_source(init_path, text, newline)

    youtube_path = source_file(root, "YoutubePlayer.as")
    text, newline = read_source(youtube_path)
    start_marker = "      public function YoutubePlayer()"
    end_marker = "      public function loadVideoById"
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise RuntimeError("YouTube player constructor was not found")
    replacement = """      public function YoutubePlayer()
      {
         super();
         // StageWebView is not functional in the Wine-hosted AIR runtime.
         // Keep the player object available, but disable optional video playback
         // so it cannot block the main game bootstrap.
         stageWebView = null;
         return;
         Sanalika.instance.stage.addEventListener("enterFrame",onEnterFrame);
         if(!Sanalika.instance.loaderInfo.applicationDomain.hasDefinition("flash.media.StageWebView"))
         {
            stageWebView = null;
            return;
         }
         var _loc1_:Class = Sanalika.instance.loaderInfo.applicationDomain.getDefinition("flash.media.StageWebView") as Class;
         stageWebView = new _loc1_(false);
         stageWebView.stage = Sanalika.instance.stage;
         stageWebView.mediaPlaybackRequiresUserAction = false;
         Sanalika.instance.layerModel.youtubeLayer.addChildAt(this,0);
      }

"""
    text = text[:start] + replacement + text[end:]
    write_source(youtube_path, text, newline)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=("main", "preloader", "core"), required=True)
    parser.add_argument("source_root", type=Path)
    args = parser.parse_args()
    try:
        {"main": patch_main, "preloader": patch_preloader, "core": patch_core}[args.kind](args.source_root)
    except (OSError, RuntimeError) as exc:
        print(f"patch-sources: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
