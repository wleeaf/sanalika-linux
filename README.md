# Sanalika Linux

Run the Sanalika Windows desktop client on Linux with Wine.

This project applies the compatibility fix required by the AIR client under Wine. It does not distribute Sanalika or any of its proprietary assets.

## Quick start

On Fedora or another supported Linux distribution:

```bash
git clone https://github.com/wleeaf/sanalika-linux.git
cd sanalika-linux
./install.sh ~/Downloads/Sanalika_1.0.1.1.exe
```

Complete the official Windows installer when it opens. After patching, start **Sanalika (Wine)** from the application menu.

The installer creates an isolated prefix at `~/.local/share/wineprefixes/sanalika` and downloads JPEXS Free Flash Decompiler temporarily to rebuild the locally installed SWFs. The game installer and game files must be supplied by the user.

## What is fixed

The desktop client could remain at `PROGRESS_LOADING` because Wine's AIR runtime hangs while constructing the optional YouTube `StageWebView`. The patch also makes the AIR loader pass its instance parameters directly and uses local patched startup SWFs.

YouTube video playback is disabled in the Wine build; it is optional and does not affect normal gameplay.

## Compatibility

Fedora is the primary tested platform. The installer supports Fedora, Debian/Ubuntu, and Arch package managers when available. The current patch targets Sanalika client `1.0.1.1`; unknown client or server SWF versions are rejected rather than modified blindly.

## Legal and attribution

Sanalika and its game files belong to their respective owners. This is an independent compatibility project and is not affiliated with or endorsed by Sanalika. Use the official installer and comply with its terms.

JPEXS Free Flash Decompiler is downloaded from its official GitHub release at install time and remains subject to its own license.

