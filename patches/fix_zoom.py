#!/usr/bin/env python3
"""Keep Sanalika's in-game zoom when the window is minimized and restored.

The game camera resets its zoom on every stage resize. When GNOME hides a
window on another workspace, Wine minimizes it, which shows up in the game as
two resizes (shrink, then restore) and resets the zoom. This adds a
highest-priority resize listener to the local client's LoaderModel that
swallows the minimize/restore pair and passes real resizes through unchanged.
Only the local Sanalika.swf is modified; the downloaded game code is not.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

MARKER = "armResizeFilter"

FILTER = """      public var resizeArmed:Boolean = false;

      public var resizePassing:Boolean = false;

      public var resizeRestoring:Boolean = false;

      public var resizeTimer:uint = 0;

      public var resizeWidth:int = -1;

      public var resizeHeight:int = -1;

      public function armResizeFilter() : void
      {
         if(resizeArmed || stage == null)
         {
            return;
         }
         resizeArmed = true;
         resizeWidth = stage.stageWidth;
         resizeHeight = stage.stageHeight;
         stage.addEventListener(Event.RESIZE,holdResize,false,2147483647);
      }

      public function isMinimized() : Boolean
      {
         var _loc1_:Object = null;
         if(stage.stageWidth < 200 || stage.stageHeight < 150)
         {
            return true;
         }
         try
         {
            _loc1_ = stage["nativeWindow"];
            if(_loc1_ != null && _loc1_["displayState"] == "minimized")
            {
               return true;
            }
         }
         catch(_loc_e_:*)
         {
            return false;
         }
         return false;
      }

      public function holdResize(param1:Event) : void
      {
         if(resizePassing)
         {
            return;
         }
         if(isMinimized())
         {
            param1.stopImmediatePropagation();
            resizeRestoring = true;
            return;
         }
         if(resizeRestoring)
         {
            param1.stopImmediatePropagation();
            if(resizeTimer != 0)
            {
               clearTimeout(resizeTimer);
            }
            resizeTimer = setTimeout(releaseResize,250);
            return;
         }
         if(stage.stageWidth == resizeWidth && stage.stageHeight == resizeHeight)
         {
            param1.stopImmediatePropagation();
            return;
         }
         resizeWidth = stage.stageWidth;
         resizeHeight = stage.stageHeight;
      }

      public function releaseResize() : void
      {
         resizeTimer = 0;
         if(isMinimized())
         {
            return;
         }
         resizeRestoring = false;
         if(stage.stageWidth == resizeWidth && stage.stageHeight == resizeHeight)
         {
            return;
         }
         resizeWidth = stage.stageWidth;
         resizeHeight = stage.stageHeight;
         resizePassing = true;
         stage.dispatchEvent(new Event(Event.RESIZE));
         resizePassing = false;
      }
"""


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def patch(path: Path) -> None:
    raw = path.read_bytes().decode("utf-8")
    newline = "\r\n" if "\r\n" in raw else "\n"
    text = raw.replace("\r\n", "\n")
    if MARKER in text:
        raise RuntimeError("LoaderModel is already patched")
    text = replace_once(
        text,
        "   import flash.utils.ByteArray;\n",
        "   import flash.utils.ByteArray;\n   import flash.utils.clearTimeout;\n   import flash.utils.setTimeout;\n",
        "timer imports",
    )
    text = replace_once(
        text,
        "      public var binaryLoader:URLLoader;\n",
        "      public var binaryLoader:URLLoader;\n      \n" + FILTER,
        "resize filter",
    )
    text = replace_once(
        text,
        "      public function load() : void\n      {\n",
        "      public function load() : void\n      {\n         armResizeFilter();\n",
        "arm in load()",
    )
    path.write_bytes(text.replace("\n", newline).encode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("loader_model", type=Path, help="exported LoaderModel.as")
    args = parser.parse_args()
    try:
        patch(args.loader_model)
    except (OSError, RuntimeError, UnicodeDecodeError) as exc:
        print(f"fix_zoom: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
