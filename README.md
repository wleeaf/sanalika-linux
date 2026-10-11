# Sanalika Linux

Run the Sanalika Windows desktop client on Linux with Wine.

This project applies the compatibility fixes the Adobe AIR client needs under Wine. It does not distribute Sanalika or any of its proprietary assets; you supply the official installer.

## Quick start

1. Download the official Windows installer from [sanalika.com](https://www.sanalika.com) (for example `Sanalika_1.0.1.2.exe`).
2. Clone this repository and run the installer script:

   ```bash
   git clone https://github.com/wleeaf/sanalika-linux.git
   cd sanalika-linux
   ./install.sh ~/Downloads/Sanalika_1.0.1.2.exe
   ```

3. Complete the official Windows installer when it opens.
4. Start **Sanalika (Wine)** from the application menu, or run `~/.local/bin/sanalika-linux`.

If exactly one `Sanalika*.exe` is in `~/Downloads`, the installer path can be omitted.

## What the installer does

- Installs the system dependencies: Wine, the 32-bit MinGW runtime DLLs, Java, unzip, curl, Python 3, and Perl.
- Creates an isolated Wine prefix at `~/.local/share/wineprefixes/sanalika` (override with `SANALIKA_WINEPREFIX`).
- Runs the official Sanalika installer inside that prefix. If the game is already installed, this step is skipped.
- Patches the installed client (see below) and creates the launcher and the menu entry.

Re-running `install.sh` on an existing installation is safe. It re-patches the client and recreates the launcher.

## What is patched

Without these fixes, the client stays on the loading screen under Wine.

- **Client (`Sanalika.swf`):** loads a locally patched preloader instead of the remote one.
- **Preloader:** fetched from the URL in Sanalika's live client configuration (`https://cf.sanalika.com/c.json`). The patch makes it always pass the launch parameters to the game core instead of relying on a player-type check that fails under Wine.
- **`application.xml`:** switches from GPU to CPU rendering.

The game core itself is not modified or stored locally. The patched preloader downloads the current core from Sanalika's servers at every launch, the same way the Windows client does.

The patch is built with [JPEXS Free Flash Decompiler](https://github.com/jindrapetrik/jpexs-decompiler), which is downloaded once from its official release, checked against a known hash, and cached in `~/.cache/sanalika-linux`. The original files are kept next to the patched ones with an `.original` suffix.

## After a Sanalika update

If the game stops connecting after Sanalika updates its servers, re-run the patcher:

```bash
./patch-sanalika.sh
```

It reads the current preloader from the live client configuration and rebuilds the local copy. If Sanalika changes the preloader's code so the patch no longer applies, the script stops with an error instead of modifying it blindly.

## Troubleshooting

- **Stuck on the loading screen or no server connection:** run `./patch-sanalika.sh`, then start the game again.
- **`unsupported Sanalika.swf hash`:** your client version is not supported yet. Supported versions are `1.0.1.1` and `1.0.1.2`, which ship the same `Sanalika.swf`.
- **Launcher or menu entry missing:** run `./install.sh` again.
- **Seeing logs:** start the game from a terminal with `~/.local/bin/sanalika-linux`. Wine's `fixme:` lines are normal.

## Uninstalling

```bash
./uninstall.sh
```

This removes the launcher and the menu entry. To also remove the game, delete `~/.local/share/wineprefixes/sanalika`. Delete `~/.cache/sanalika-linux` to remove the cached tools and preloader.

## Compatibility

Fedora is the primary tested platform. The installer also supports Debian/Ubuntu (`apt-get`) and Arch (`pacman`). On other distributions, install the dependencies listed above manually.

## Legal and attribution

Sanalika and its game files belong to their respective owners. This is an independent compatibility project and is not affiliated with or endorsed by Sanalika. Use the official installer and comply with its terms.

JPEXS Free Flash Decompiler remains subject to its own license.
