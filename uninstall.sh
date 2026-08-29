#!/usr/bin/env bash
set -Eeuo pipefail

user_home=${HOME:?HOME is not set}
rm -f -- "$user_home/.local/bin/sanalika-linux" "$user_home/.local/share/applications/sanalika-linux.desktop"
printf 'Launcher removed. The Wine prefix and game files were preserved.\n'
printf 'To remove them manually, delete ~/.local/share/wineprefixes/sanalika.\n'

