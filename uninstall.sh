#!/usr/bin/env bash
set -Eeuo pipefail

user_home=${HOME:?HOME is not set}
prefix="${SANALIKA_WINEPREFIX:-${XDG_DATA_HOME:-$user_home/.local/share}/wineprefixes/sanalika}"

case "${1:-}" in
    "") purge=0 ;;
    --purge) purge=1 ;;
    *) printf 'Usage: %s [--purge]\n' "$(basename "$0")" >&2; exit 2 ;;
esac

rm -f -- "$user_home/.local/bin/sanalika-linux" "$user_home/.local/share/applications/sanalika-linux.desktop"
printf 'Launcher removed.\n'

if [[ "$purge" -eq 1 ]]; then
    [[ -d "$prefix" ]] && WINEPREFIX="$prefix" wineserver -k >/dev/null 2>&1 || true
    rm -rf -- "$prefix" "${XDG_CACHE_HOME:-$user_home/.cache}/sanalika-linux"
    # Menu entries and icons Wine created for older installs.
    rm -f -- "$user_home/.local/share/applications/wine/Programs/Sanalika.desktop" \
        "$user_home/.config/menus/applications-merged/wine-Programs-Sanalika.menu" \
        "$user_home"/.local/share/icons/hicolor/*/apps/*_Sanalika.0.png
    printf 'Wine prefix and game files removed: %s\n' "$prefix"
else
    printf 'The Wine prefix and game files were preserved.\n'
    printf 'Run with --purge to also remove %s.\n' "$prefix"
fi
