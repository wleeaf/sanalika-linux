#!/usr/bin/env bash
set -Eeuo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
user_home=${HOME:?HOME is not set}
prefix="${SANALIKA_WINEPREFIX:-${XDG_DATA_HOME:-$user_home/.local/share}/wineprefixes/sanalika}"
installer=${1:-}

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'Usage: %s /path/to/Sanalika_1.0.1.1.exe\n' "$(basename "$0")"
}

[[ "${1:-}" != "--help" ]] || { usage; exit 0; }
[[ $# -le 1 ]] || { usage >&2; exit 2; }

if [[ -z "$installer" ]]; then
    mapfile -t installers < <(find "$user_home/Downloads" -maxdepth 1 -type f -iname 'Sanalika*.exe' -print 2>/dev/null | sort)
    [[ ${#installers[@]} -eq 1 ]] || fail "pass the official Sanalika installer path explicitly"
    installer=${installers[0]}
fi
[[ -f "$installer" ]] || fail "installer not found: $installer"
installer=$(cd -- "$(dirname -- "$installer")" && pwd)/$(basename -- "$installer")

install_packages() {
    local -a sudo_cmd=()
    [[ $EUID -eq 0 ]] || { command -v sudo >/dev/null 2>&1 || fail "sudo is required to install system dependencies"; sudo_cmd=(sudo); }
    if command -v dnf >/dev/null 2>&1; then
        local -a packages=(wine mingw32-libgcc mingw32-winpthreads java-17-openjdk-headless unzip curl python3 perl)
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
        "${sudo_cmd[@]}" apt-get install -y wine mingw-w64 default-jre-headless unzip curl python3 perl
    elif command -v pacman >/dev/null 2>&1; then
        "${sudo_cmd[@]}" pacman -Sy --needed wine mingw-w64-gcc jre17-openjdk unzip curl python perl
    else
        fail "unsupported package manager; install wine, MinGW runtime DLLs, Java, unzip, curl, Python 3, and Perl manually"
    fi
}

missing_command=0
for command in wine curl unzip java python3 sha256sum perl; do
    command -v "$command" >/dev/null 2>&1 || missing_command=1
done
runtime_missing=0
for dll in libgcc_s_dw2-1.dll libwinpthread-1.dll; do
    find /usr -type f -name "$dll" -path '*/i686-w64-mingw32/*' -print -quit 2>/dev/null | grep -q . || runtime_missing=1
done
if [[ "$missing_command" -eq 1 || "$runtime_missing" -eq 1 ]]; then
    install_packages
fi
for command in wine curl unzip java python3 sha256sum perl; do
    command -v "$command" >/dev/null 2>&1 || fail "'$command' is still unavailable after dependency installation"
done

mkdir -p "$prefix"
if [[ ! -d "$prefix/drive_c" ]]; then
    printf 'Initializing Wine prefix...\n'
    WINEPREFIX="$prefix" wineboot -u >/dev/null 2>&1
fi

find_mingw_dll() {
    local name=$1
    find /usr -type f -name "$name" -path '*/i686-w64-mingw32/*' -print -quit 2>/dev/null
}

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
    printf 'Opening the official Sanalika installer...\n'
    WINEPREFIX="$prefix" wine "$installer"
    mapfile -t installed_apps < <(find "$prefix/drive_c" -type f -iname 'Sanalika.exe' -printf '%h\n' 2>/dev/null | sort -u)
fi
[[ ${#installed_apps[@]} -eq 1 ]] || fail "could not uniquely locate the installed Sanalika application"
app_dir=${installed_apps[0]}

"$project_dir/patch-sanalika.sh" "$app_dir"

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
