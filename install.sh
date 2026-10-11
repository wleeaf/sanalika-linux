#!/usr/bin/env bash
set -Eeuo pipefail

user_home=${HOME:?HOME is not set}
prefix="${SANALIKA_WINEPREFIX:-${XDG_DATA_HOME:-$user_home/.local/share}/wineprefixes/sanalika}"
installer=""
cpu_rendering=0

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'Usage: %s [--cpu-rendering] [/path/to/Sanalika_1.0.1.2.exe]\n' "$(basename "$0")"
    printf '\n  --cpu-rendering  use software rendering if the game window is black or glitchy\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help) usage; exit 0 ;;
        --cpu-rendering) cpu_rendering=1 ;;
        -*) usage >&2; exit 2 ;;
        *) [[ -z "$installer" ]] || { usage >&2; exit 2; }; installer=$1 ;;
    esac
    shift
done

find_mingw_dll() {
    local name=$1
    # find exits non-zero on unreadable directories even when it found the file.
    find /usr -type f -name "$name" -path '*/i686-w64-mingw32/*' -print -quit 2>/dev/null || true
}

install_packages() {
    local -a sudo_cmd=()
    [[ $EUID -eq 0 ]] || { command -v sudo >/dev/null 2>&1 || fail "sudo is required to install system dependencies"; sudo_cmd=(sudo); }
    if command -v dnf >/dev/null 2>&1; then
        local -a packages=(wine mingw32-libgcc mingw32-winpthreads)
        local -a missing=()
        local package
        for package in "${packages[@]}"; do
            rpm -q "$package" >/dev/null 2>&1 || missing+=("$package")
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            "${sudo_cmd[@]}" dnf install -y "${missing[@]}"
        fi
    elif command -v apt-get >/dev/null 2>&1; then
        "${sudo_cmd[@]}" apt-get update
        "${sudo_cmd[@]}" apt-get install -y wine mingw-w64
    elif command -v pacman >/dev/null 2>&1; then
        "${sudo_cmd[@]}" pacman -Sy --needed wine mingw-w64-gcc
    else
        fail "unsupported package manager; install Wine and the 32-bit MinGW runtime DLLs manually"
    fi
}

dependencies_missing=0
command -v wine >/dev/null 2>&1 || dependencies_missing=1
for dll in libgcc_s_dw2-1.dll libwinpthread-1.dll; do
    [[ -n "$(find_mingw_dll "$dll")" ]] || dependencies_missing=1
done
[[ "$dependencies_missing" -eq 0 ]] || install_packages
command -v wine >/dev/null 2>&1 || fail "Wine is still unavailable after dependency installation"

mkdir -p "$prefix"
if [[ ! -d "$prefix/drive_c" ]]; then
    printf 'Initializing Wine prefix...\n'
    # Sanalika is an AIR app and needs neither Wine Mono nor Gecko; skipping
    # them avoids install prompts that can block or abort prefix creation.
    if ! WINEPREFIX="$prefix" WINEDLLOVERRIDES="mscoree,mshtml=" timeout 300 wineboot -u >/dev/null 2>&1; then
        WINEPREFIX="$prefix" wineserver -k >/dev/null 2>&1 || true
        rm -rf -- "$prefix"
        fail "Wine prefix initialization failed or timed out; run the installer again"
    fi
    WINEPREFIX="$prefix" wineserver -w
fi

for dll in libgcc_s_dw2-1.dll libwinpthread-1.dll; do
    dll_source=$(find_mingw_dll "$dll")
    [[ -n "$dll_source" ]] || fail "could not find $dll; install the 32-bit MinGW runtime package"
    for wine_system_dir in "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64"; do
        mkdir -p "$wine_system_dir"
        cp -f -- "$dll_source" "$wine_system_dir/$dll"
    done
done

mapfile -t installed_apps < <(find "$prefix/drive_c" -type f -iname 'Sanalika.exe' -printf '%h\n' 2>/dev/null | sort -u)
if [[ ${#installed_apps[@]} -eq 0 ]]; then
    if [[ -z "$installer" ]]; then
        mapfile -t installers < <(find "$user_home/Downloads" -maxdepth 1 -type f -iname 'Sanalika*.exe' -print 2>/dev/null | sort -V)
        [[ ${#installers[@]} -gt 0 ]] || fail "download the official Sanalika installer and pass its path"
        installer=${installers[-1]}
    fi
    [[ -f "$installer" ]] || fail "installer not found: $installer"
    printf 'Installing Sanalika silently from %s...\n' "$(basename -- "$installer")"
    # The NSIS installer can exit non-zero under Wine even after a complete
    # install, so success is judged by the installed files below.
    WINEPREFIX="$prefix" WINEDLLOVERRIDES="winemenubuilder.exe=d" timeout 600 wine "$installer" /S >/dev/null 2>&1 || true
    WINEPREFIX="$prefix" wineserver -w
    mapfile -t installed_apps < <(find "$prefix/drive_c" -type f -iname 'Sanalika.exe' -printf '%h\n' 2>/dev/null | sort -u)
fi
[[ ${#installed_apps[@]} -eq 1 ]] || fail "Sanalika was not installed; run the installer again or check that the .exe is the official one"
app_dir=${installed_apps[0]}

if [[ "$cpu_rendering" -eq 1 ]]; then
    application_xml="$app_dir/META-INF/AIR/application.xml"
    [[ -f "$application_xml" ]] || fail "missing $application_xml"
    [[ -e "$application_xml.original" ]] || cp -p -- "$application_xml" "$application_xml.original"
    sed -i 's#<renderMode>gpu</renderMode>#<renderMode>cpu</renderMode>#' "$application_xml"
    grep -q '<renderMode>cpu</renderMode>' "$application_xml" || fail "could not enable CPU rendering in application.xml"
    printf 'CPU rendering enabled.\n'
fi

launcher_dir="$user_home/.local/bin"
launcher="$launcher_dir/sanalika-linux"
desktop_dir="$user_home/.local/share/applications"
desktop_file="$desktop_dir/sanalika-linux.desktop"
mkdir -p "$launcher_dir" "$desktop_dir"
printf '#!/usr/bin/env bash\nexec env WINEPREFIX=%q wine %q "$@"\n' "$prefix" "$app_dir/Sanalika.exe" > "$launcher"
chmod 755 "$launcher"

desktop_exec=${launcher//\\/\\\\}
desktop_exec=${desktop_exec//"/\\"}
{
    printf '%s\n' '[Desktop Entry]'
    printf '%s\n' 'Name=Sanalika (Wine)'
    printf '%s\n' 'Comment=Play Sanalika on Linux'
    printf 'Exec="%s"\n' "$desktop_exec"
    printf '%s\n' 'Terminal=false'
    printf '%s\n' 'Type=Application'
    printf '%s\n' 'Categories=Game;'
    printf '%s\n' 'StartupNotify=true'
} > "$desktop_file"

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true

printf '\nInstallation complete.\nLaunch from the application menu or run: %s\n' "$launcher"
