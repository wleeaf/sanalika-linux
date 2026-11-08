#!/usr/bin/env bash
set -Eeuo pipefail

user_home=${HOME:?HOME is not set}
prefix="${SANALIKA_WINEPREFIX:-${XDG_DATA_HOME:-$user_home/.local/share}/wineprefixes/sanalika}"

case "${1:-}" in
    "") purge=0 ;;
    --purge) purge=1 ;;
    *) printf 'Usage: %s [--purge]\n' "$(basename "$0")" >&2; exit 2 ;;
esac

helper_dir="${XDG_DATA_HOME:-$user_home/.local/share}/sanalika-linux"

# Restore the original client file if the zoom fix is applied, so a kept
# installation is left unmodified.
if [[ "$purge" -eq 0 && -f "$helper_dir/zoom.state" ]]; then
    mapfile -t apps < <(find "$prefix/drive_c" -type f -iname 'Sanalika.exe' -printf '%h\n' 2>/dev/null | sort -u)
    for app in "${apps[@]}"; do
        if [[ -f "$app/Sanalika.swf.original" && "$(sha256sum "$app/Sanalika.swf" | awk '{print $1}')" == "$(cat "$helper_dir/zoom.state")" ]]; then
            cp -p -- "$app/Sanalika.swf.original" "$app/Sanalika.swf"
            printf 'Zoom fix removed.\n'
        fi
    done
fi

rm -f -- "$user_home/.local/bin/sanalika-linux" "$user_home/.local/share/applications/sanalika-linux.desktop"
rm -rf -- "$helper_dir"
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
