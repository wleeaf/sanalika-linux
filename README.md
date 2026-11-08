# Sanalika Linux

Run the official Sanalika Windows desktop client on Linux with Wine.

This project sets up Wine and a launcher for the official client. By default it does not modify, distribute, or download any Sanalika files; you supply the official installer. The optional `--fix-zoom` setting is the only one that changes a Sanalika file (see below).

## Quick start

1. Download the official Windows installer. The download page on [sanalika.com](https://www.sanalika.com) still links an older 1.0.1.1 build; the current one, which the game itself points to, is [`Sanalika_1.0.2.6.exe`](https://fs.sanalika.com/global/download/Sanalika_1.0.2.6.exe).
2. Clone this repository and run the installer script:

   ```bash
   git clone https://github.com/wleeaf/sanalika-linux.git
   cd sanalika-linux
   ./install.sh ~/Downloads/Sanalika_1.0.2.6.exe
   ```

3. Start **Sanalika (Wine)** from the application menu, or run `~/.local/bin/sanalika-linux`.

Without a path, `install.sh` uses the newest `Sanalika*.exe` in `~/Downloads`.

## What the installer does

- Installs Wine and the 32-bit MinGW runtime DLLs the client needs, if they are missing.
- Creates an isolated Wine prefix at `~/.local/share/wineprefixes/sanalika` (override with `SANALIKA_WINEPREFIX`).
- Runs the official Sanalika installer silently inside that prefix. If the game is already installed, this step is skipped.
- Creates the `sanalika-linux` launcher and the application menu entry.

Re-running `install.sh` is safe. The game updates itself from Sanalika's servers like it does on Windows.

## Options

Options are saved in `~/.local/share/sanalika-linux/settings`. Sanalika's updater replaces the client files, which undoes these changes, so the launcher re-applies them before each start. When nothing changed, this check takes a few milliseconds.

| Option | Effect | Undo |
|---|---|---|
| `--cpu-rendering` | Software rendering. Smoother on some setups (for example, no frame drops when switching desktops) and fixes black or glitchy windows. | `--gpu-rendering` |
| `--fix-zoom` | Keeps the in-game zoom when the window is minimized or moved to another desktop. | `--no-fix-zoom` |

Options can be combined and added later, for example:

```bash
./install.sh --cpu-rendering --fix-zoom
```

### About the zoom fix

Sanalika's camera resets the in-game zoom whenever the window changes size. On GNOME, switching desktops makes Wine minimize the game window and restore it later, which the game sees as two resizes, so the zoom is lost. Resizing the window yourself or toggling fullscreen also resets it, on Windows too; the fix does not change that.

`--fix-zoom` patches the local `Sanalika.swf` from the installer: it adds a resize filter that holds back the minimize/restore pair and passes real resizes through unchanged. The game code downloaded from Sanalika's servers is not modified. The original file is kept as `Sanalika.swf.original`.

The patch is built with [JPEXS Free Flash Decompiler](https://github.com/jindrapetrik/jpexs-decompiler), which is downloaded once from its official release, checked against a known hash, and cached in `~/.cache/sanalika-linux`. It needs Java, unzip, curl, and Python 3, which `install.sh` installs when you use the option. After a Sanalika update, re-applying the patch takes a few seconds. If it cannot be applied, the game starts without it and a notification says so.

## Troubleshooting

- **Black, flickering, or glitchy game window:** `./install.sh --cpu-rendering`.
- **In-game zoom resets after switching desktops:** `./install.sh --fix-zoom`.
- **Launcher or menu entry missing:** run `./install.sh` again.
- **Seeing logs:** start the game from a terminal with `~/.local/bin/sanalika-linux`. Wine's `fixme:` lines are normal.

## Uninstalling

```bash
./uninstall.sh          # remove the launcher, menu entry, and saved options; undo the zoom fix
./uninstall.sh --purge  # also remove the Wine prefix, game files, settings, and leftover menu entries
```

Wine, the MinGW packages, and Java are left installed, since other programs may use them.

## Compatibility

Tested on Fedora (GNOME on Wayland) with Sanalika client `1.0.2.6`. The installer also supports Debian/Ubuntu (`apt-get`) and Arch (`pacman`). On other distributions, install Wine and the 32-bit MinGW runtime manually.

## Legal

Sanalika and its game files belong to their respective owners. This is an independent compatibility project and is not affiliated with or endorsed by Sanalika. Use the official installer and comply with its terms. The optional zoom fix modifies your local copy of the client; it is off by default.

JPEXS Free Flash Decompiler is only downloaded when `--fix-zoom` is used and remains subject to its own license.
