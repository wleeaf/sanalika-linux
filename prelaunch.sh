#!/usr/bin/env bash
# Re-applies the optional tweaks chosen with install.sh before each launch.
# Sanalika's self-updater replaces the client files, which undoes them, so
# this checks the installed files every time and only does work when needed.
# It never blocks the launch: on failure the game starts without the tweak.
set -Euo pipefail

readonly FFDEC_VERSION="26.2.1"
readonly FFDEC_URL="https://github.com/jindrapetrik/jpexs-decompiler/releases/download/version26.2.1/ffdec_26.2.1.zip"
readonly FFDEC_HASH="0333b56998a55bd83f4e0deb678a811fcdc45607582b4f5dd438309c8c3ad5ce"
readonly LOADER_CLASS="com.oyunstudyosu.air.model.LoaderModel"

helper_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
settings="$helper_dir/settings"
zoom_state="$helper_dir/zoom.state"
app_dir=${1:?usage: prelaunch.sh <Sanalika application directory>}
cache_root="${XDG_CACHE_HOME:-${HOME:?}/.cache}/sanalika-linux"

enabled() {
    grep -qsx "$1=1" "$settings"
}

notify() {
    printf 'sanalika-linux: %s\n' "$1" >&2
    command -v notify-send >/dev/null 2>&1 && notify-send -a "Sanalika" "Sanalika" "$1" >/dev/null 2>&1 || true
}

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

set_render_mode() {
    local mode=$1 xml="$app_dir/META-INF/AIR/application.xml"
    [[ -f "$xml" ]] || return 1
    if [[ "$mode" == cpu ]]; then
        grep -q '<renderMode>gpu</renderMode>' "$xml" || return 0
        # A GPU setting means a fresh file from Sanalika, so refresh the backup.
        cp -p -- "$xml" "$xml.original"
        sed -i 's#<renderMode>gpu</renderMode>#<renderMode>cpu</renderMode>#' "$xml"
    else
        grep -q '<renderMode>cpu</renderMode>' "$xml" || return 0
        sed -i 's#<renderMode>cpu</renderMode>#<renderMode>gpu</renderMode>#' "$xml"
    fi
}

ensure_ffdec() {
    local root="$cache_root/ffdec-$FFDEC_VERSION" archive="$cache_root/ffdec_$FFDEC_VERSION.zip"
    ffdec_jar="$root/ffdec.jar"
    [[ -f "$ffdec_jar" ]] && return 0
    mkdir -p "$cache_root" || return 1
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --retry 4 --retry-delay 5 --silent --show-error "$FFDEC_URL" -o "$archive.part" || return 1
        mv -- "$archive.part" "$archive" || return 1
    fi
    if [[ "$(hash_file "$archive")" != "$FFDEC_HASH" ]]; then
        rm -f -- "$archive"
        return 1
    fi
    rm -rf -- "$root"
    mkdir -p "$root" && unzip -q -o "$archive" -d "$root" && [[ -f "$ffdec_jar" ]]
}

ffdec() {
    java -Xmx1024m -jar "$ffdec_jar" "$@" >/dev/null 2>&1
}

apply_zoom_fix() {
    local swf="$app_dir/Sanalika.swf" work status=1
    [[ -f "$swf" ]] || return 1
    [[ -f "$zoom_state" && "$(hash_file "$swf")" == "$(cat -- "$zoom_state")" ]] && return 0

    # Anything else is an unmodified client, either new or freshly updated.
    notify "Applying the zoom fix to the Sanalika client, this can take up to a minute..."
    ensure_ffdec || return 1
    work=$(mktemp -d) || return 1
    if ffdec -format script:as -selectclass "$LOADER_CLASS" -export script "$work/src" "$swf" \
        && find "$work/src" -name '*.as' ! -path '*/com/oyunstudyosu/air/model/LoaderModel.as' -delete \
        && python3 -I "$helper_dir/fix_zoom.py" "$work/src/scripts/com/oyunstudyosu/air/model/LoaderModel.as" \
        && ffdec -importScript "$swf" "$work/Sanalika.swf" "$work/src" \
        && [[ -s "$work/Sanalika.swf" ]]; then
        cp -p -- "$swf" "$swf.original" \
            && cp -- "$work/Sanalika.swf" "$swf" \
            && hash_file "$swf" > "$zoom_state" \
            && status=0
    fi
    rm -rf -- "$work"
    return "$status"
}

remove_zoom_fix() {
    local swf="$app_dir/Sanalika.swf"
    [[ -f "$zoom_state" ]] || return 0
    if [[ -f "$swf.original" && "$(hash_file "$swf")" == "$(cat -- "$zoom_state")" ]]; then
        cp -p -- "$swf.original" "$swf" || return 1
    fi
    rm -f -- "$zoom_state"
}

if enabled cpu_rendering; then
    set_render_mode cpu || notify "Could not enable CPU rendering."
elif grep -qsx 'cpu_rendering=0' "$settings"; then
    set_render_mode gpu || notify "Could not restore GPU rendering."
fi
if enabled fix_zoom; then
    apply_zoom_fix || notify "The zoom fix could not be applied; starting Sanalika without it."
else
    remove_zoom_fix || notify "Could not remove the zoom fix."
fi
exit 0
