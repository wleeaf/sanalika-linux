# Sanalika Linux

Run the official Sanalika Windows desktop client on Linux with Wine.

This project only sets up Wine and a launcher. It does not modify, distribute, or download any Sanalika files; you supply the official installer.

## Quick start

1. Download the official Windows installer from [sanalika.com](https://www.sanalika.com) (for example `Sanalika_1.0.1.2.exe`).
2. Clone this repository and run the installer script:

   ```bash
   git clone https://github.com/wleeaf/sanalika-linux.git
   cd sanalika-linux
   ./install.sh ~/Downloads/Sanalika_1.0.1.2.exe
   ```

3. Start **Sanalika (Wine)** from the application menu, or run `~/.local/bin/sanalika-linux`.

Without a path, `install.sh` uses the newest `Sanalika*.exe` in `~/Downloads`.

## What the installer does

- Installs Wine and the 32-bit MinGW runtime DLLs the client needs, if they are missing.
- Creates an isolated Wine prefix at `~/.local/share/wineprefixes/sanalika` (override with `SANALIKA_WINEPREFIX`).
- Runs the official Sanalika installer silently inside that prefix. If the game is already installed, this step is skipped.
- Creates the `sanalika-linux` launcher and the application menu entry.

Re-running `install.sh` is safe. The game updates itself from Sanalika's servers like it does on Windows.

## Troubleshooting

- **Black, flickering, or glitchy game window:** switch to software rendering. To undo it, run `./uninstall.sh --purge` and install again.

  ```bash
  ./install.sh --cpu-rendering
  ```

- **Launcher or menu entry missing:** run `./install.sh` again.
- **Seeing logs:** start the game from a terminal with `~/.local/bin/sanalika-linux`. Wine's `fixme:` lines are normal.

## Uninstalling

```bash
./uninstall.sh          # remove the launcher and menu entry
./uninstall.sh --purge  # also remove the Wine prefix, game files, settings, and leftover menu entries
```

Wine and the MinGW packages are left installed, since other programs may use them.

## Compatibility

Tested on Fedora with Sanalika client `1.0.1.2`. The installer also supports Debian/Ubuntu (`apt-get`) and Arch (`pacman`). On other distributions, install Wine and the 32-bit MinGW runtime manually.

Earlier versions of this project patched the client's SWF files to get past a loading-screen hang under Wine. Sanalika's current game core no longer has that problem, so the patches were removed.

## Legal

Sanalika and its game files belong to their respective owners. This is an independent compatibility project and is not affiliated with or endorsed by Sanalika. Use the official installer and comply with its terms.
