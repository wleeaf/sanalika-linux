#!/usr/bin/env bash
set -Eeuo pipefail

user_home=${HOME:?HOME is not set}
prefix="${SANALIKA_WINEPREFIX:-${XDG_DATA_HOME:-$user_home/.local/share}/wineprefixes/sanalika}"
installer=""
cpu_rendering=""
fix_zoom=""
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
helper_dir="${XDG_DATA_HOME:-$user_home/.local/share}/sanalika-linux"

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'Usage: %s [options] [/path/to/Sanalika_1.0.2.6.exe]\n' "$(basename "$0")"
    printf '\nOptions are remembered and re-applied after Sanalika updates itself:\n'
    printf '  --cpu-rendering  use software rendering (smoother on some setups, fixes black windows)\n'
    printf '  --gpu-rendering  switch back to Sanalika'"'"'s default GPU rendering\n'
    printf '  --fix-zoom       keep the in-game zoom when the window is minimized or moved to another desktop\n'
    printf '  --no-fix-zoom    remove the zoom fix and restore the original client file\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help) usage; exit 0 ;;
        --cpu-rendering) cpu_rendering=1 ;;
        --gpu-rendering) cpu_rendering=0 ;;
        --fix-zoom) fix_zoom=1 ;;
        --no-fix-zoom) fix_zoom=0 ;;
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

install_zoom_packages() {
    local -a sudo_cmd=()
    [[ $EUID -eq 0 ]] || { command -v sudo >/dev/null 2>&1 || fail "sudo is required to install system dependencies"; sudo_cmd=(sudo); }
    if command -v dnf >/dev/null 2>&1; then
        "${sudo_cmd[@]}" dnf install -y java-17-openjdk-headless unzip curl python3
    elif command -v apt-get >/dev/null 2>&1; then
        "${sudo_cmd[@]}" apt-get install -y default-jre-headless unzip curl python3
    elif command -v pacman >/dev/null 2>&1; then
        "${sudo_cmd[@]}" pacman -S --needed jre17-openjdk unzip curl python
    else
        fail "unsupported package manager; install Java, unzip, curl, and Python 3 manually"
    fi
}

set_setting() {
    local file="$helper_dir/settings"
    { grep -v "^$1=" "$file" 2>/dev/null || true; printf '%s=%s\n' "$1" "$2"; } > "$file.new"
    mv -- "$file.new" "$file"
}

dependencies_missing=0
command -v wine >/dev/null 2>&1 || dependencies_missing=1
for dll in libgcc_s_dw2-1.dll libwinpthread-1.dll; do
    [[ -n "$(find_mingw_dll "$dll")" ]] || dependencies_missing=1
done
[[ "$dependencies_missing" -eq 0 ]] || install_packages
command -v wine >/dev/null 2>&1 || fail "Wine is still unavailable after dependency installation"
if [[ "$fix_zoom" == 1 ]]; then
    for command in java unzip curl python3; do
        command -v "$command" >/dev/null 2>&1 || { install_zoom_packages; break; }
    done
    for command in java unzip curl python3; do
        command -v "$command" >/dev/null 2>&1 || fail "'$command' is required for --fix-zoom"
    done
fi

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

mkdir -p "$helper_dir"
install -m 755 "$project_dir/prelaunch.sh" "$helper_dir/prelaunch.sh"
install -m 644 "$project_dir/patches/fix_zoom.py" "$helper_dir/fix_zoom.py"
touch "$helper_dir/settings"
[[ -z "$cpu_rendering" ]] || set_setting cpu_rendering "$cpu_rendering"
[[ -z "$fix_zoom" ]] || set_setting fix_zoom "$fix_zoom"
if [[ "$fix_zoom" == 1 ]]; then
    printf 'Applying the zoom fix (this can take up to a minute)...\n'
fi
"$helper_dir/prelaunch.sh" "$app_dir"
if grep -qsx 'fix_zoom=1' "$helper_dir/settings"; then
    [[ -f "$helper_dir/zoom.state" && "$(sha256sum "$app_dir/Sanalika.swf" | awk '{print $1}')" == "$(cat "$helper_dir/zoom.state")" ]] \
        || fail "the zoom fix could not be applied; run with --no-fix-zoom to install without it"
    printf 'Zoom fix enabled.\n'
fi
if grep -qsx 'cpu_rendering=1' "$helper_dir/settings"; then
    printf 'CPU rendering enabled.\n'
fi

launcher_dir="$user_home/.local/bin"
launcher="$launcher_dir/sanalika-linux"
desktop_dir="$user_home/.local/share/applications"
desktop_file="$desktop_dir/sanalika-linux.desktop"
mkdir -p "$launcher_dir" "$desktop_dir"
{
    printf '#!/usr/bin/env bash\n'
    printf '%q %q || true\n' "$helper_dir/prelaunch.sh" "$app_dir"
    printf 'exec env WINEPREFIX=%q wine %q "$@"\n' "$prefix" "$app_dir/Sanalika.exe"
} > "$launcher"
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
