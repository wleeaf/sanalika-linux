#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATCH_VERSION="0.1.0"
readonly FFDEC_VERSION="26.2.1"
readonly FFDEC_URL="https://github.com/jindrapetrik/jpexs-decompiler/releases/download/version26.2.1/ffdec_26.2.1.zip"
readonly EXPECTED_FFDEC_HASH="0333b56998a55bd83f4e0deb678a811fcdc45607582b4f5dd438309c8c3ad5ce"
readonly REMOTE_LOADER_URL="https://fs.sanalika.com/global/dynamic/core/ml.3"
readonly REMOTE_CORE_URL="https://fs.sanalika.com/global/dynamic/core/snl.770.swf"
readonly EXPECTED_MAIN_HASH="675e74272f4d0ec9dc9bb4f0bc41edbb832b31f2089287e274ac021f0301ae29"
readonly EXPECTED_LOADER_HASH="740a56a2abd02018d9cd9a79e58d9c258afcef6ddd629420bb4b3a7bf0c9ce7d"
readonly EXPECTED_CORE_HASH="ea3496429d3b428c73c5c8d9282fdc30a83bb358601c27f45f8b0e80988bcc72"

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
user_home=${HOME:?HOME is not set}
cache_root="${XDG_CACHE_HOME:-$user_home/.cache}/sanalika-linux"
default_prefix="${SANALIKA_WINEPREFIX:-${XDG_DATA_HOME:-$user_home/.local/share}/wineprefixes/sanalika}"
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

usage() {
    printf 'Usage: %s [Sanalika application directory]\n' "$(basename "$0")"
    printf '\nThe directory must contain Sanalika.exe and Sanalika.swf.\n'
}

[[ "${1:-}" != "--help" ]] || { usage; exit 0; }
[[ $# -le 1 ]] || { usage >&2; exit 2; }

for command in curl unzip java python3 sha256sum perl; do
    command -v "$command" >/dev/null 2>&1 || fail "'$command' is required; run install.sh first."
done

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

backup_once() {
    local source=$1
    local backup="$source.original"
    [[ -e "$backup" ]] || cp -p -- "$source" "$backup"
}

app_dir=${1:-}
if [[ -z "$app_dir" ]]; then
    mapfile -t candidates < <(find "$default_prefix/drive_c" -type f -iname 'Sanalika.exe' -printf '%h\n' 2>/dev/null | sort -u)
    [[ ${#candidates[@]} -eq 1 ]] || fail "could not uniquely locate Sanalika.exe; pass its application directory explicitly"
    app_dir=${candidates[0]}
fi
app_dir=$(cd -- "$app_dir" 2>/dev/null && pwd) || fail "application directory does not exist: $app_dir"

main_swf="$app_dir/Sanalika.swf"
application_xml="$app_dir/META-INF/AIR/application.xml"
[[ -f "$application_xml" ]] || application_xml="$app_dir/application.xml"
[[ -f "$main_swf" ]] || fail "missing $main_swf"
[[ -f "$application_xml" ]] || fail "missing $application_xml"

current_main_hash=$(hash_file "$main_swf")
if [[ -f "$app_dir/ml-patched.swf" ]] && [[ -f "$app_dir/core-patched.swf" ]] && grep -q '<renderMode>cpu</renderMode>' "$application_xml" && [[ "$current_main_hash" != "$EXPECTED_MAIN_HASH" ]]; then
    printf 'Sanalika is already patched (sanalika-linux %s).\n' "$PATCH_VERSION"
    exit 0
fi
[[ "$current_main_hash" == "$EXPECTED_MAIN_HASH" ]] || fail "unsupported Sanalika.swf hash ($current_main_hash); this release targets client 1.0.1.1"

mkdir -p "$cache_root"
ffdec_root="$cache_root/ffdec-$FFDEC_VERSION"
ffdec="$ffdec_root/ffdec"
if [[ ! -x "$ffdec" ]]; then
    archive="$cache_root/ffdec_$FFDEC_VERSION.zip"
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --retry 3 --silent --show-error "$FFDEC_URL" -o "$archive.part"
        mv -- "$archive.part" "$archive"
    fi
    [[ "$(hash_file "$archive")" == "$EXPECTED_FFDEC_HASH" ]] || fail "the JPEXS download did not match the tested release"
    rm -rf -- "$ffdec_root"
    mkdir -p "$ffdec_root"
    unzip -q -o "$archive" -d "$ffdec_root"
    chmod +x "$ffdec_root/ffdec"
fi
[[ -x "$ffdec" ]] || fail "JPEXS Free Flash Decompiler was not unpacked correctly"

remote_root="$cache_root/remote-swf"
mkdir -p "$remote_root"
remote_loader="$remote_root/ml.3"
remote_core="$remote_root/snl.770.swf"
if [[ ! -f "$remote_loader" ]]; then
    curl --fail --location --retry 3 --silent --show-error "$REMOTE_LOADER_URL" -o "$remote_loader.part"
    mv -- "$remote_loader.part" "$remote_loader"
fi
if [[ ! -f "$remote_core" ]]; then
    curl --fail --location --retry 3 --silent --show-error "$REMOTE_CORE_URL" -o "$remote_core.part"
    mv -- "$remote_core.part" "$remote_core"
fi
[[ "$(hash_file "$remote_loader")" == "$EXPECTED_LOADER_HASH" ]] || fail "the remote preloader version is not supported"
[[ "$(hash_file "$remote_core")" == "$EXPECTED_CORE_HASH" ]] || fail "the remote core version is not supported"

patch_swf() {
    local kind=$1
    local input=$2
    local output=$3
    local source_root="$work_dir/$kind-source"
    mkdir -p "$source_root"
    printf 'Exporting %s scripts...\n' "$kind"
    "$ffdec" -format script:as -export script "$source_root" "$input" >/dev/null
    python3 "$project_dir/patches/patch_sources.py" --kind "$kind" "$source_root"
    case "$kind" in
        main) target_script='scripts/com/oyunstudyosu/air/model/LoaderModel.as' ;;
        preloader) target_script='scripts/extensions/MainLoader.as' ;;
        core) target_script='scripts/com/oyunstudyosu/commands/InitParamsCommand.as' ;;
    esac
    if [[ "$kind" == core ]]; then
        find "$source_root" -type f -name '*.as' ! -path "$source_root/$target_script" ! -path '*/com/oyunstudyosu/video/youtube/YoutubePlayer.as' -delete
    else
        find "$source_root" -type f -name '*.as' ! -path "$source_root/$target_script" -delete
    fi
    printf 'Rebuilding %s...\n' "$kind"
    if [[ "$kind" == core ]]; then
        "$ffdec" -air -importScript "$input" "$output" "$source_root" >/dev/null
    else
        "$ffdec" -importScript "$input" "$output" "$source_root" >/dev/null
    fi
}

main_output="$work_dir/Sanalika.swf"
loader_output="$work_dir/ml-patched.swf"
core_output="$work_dir/core-patched.swf"
patch_swf main "$main_swf" "$main_output"
patch_swf preloader "$remote_loader" "$loader_output"
patch_swf core "$remote_core" "$core_output"

[[ -s "$main_output" && -s "$loader_output" && -s "$core_output" ]] || fail "JPEXS produced an empty rebuilt SWF"

backup_once "$main_swf"
backup_once "$application_xml"
[[ -f "$app_dir/ml-patched.swf" ]] && backup_once "$app_dir/ml-patched.swf"
[[ -f "$app_dir/core-patched.swf" ]] && backup_once "$app_dir/core-patched.swf"

cp -p -- "$main_output" "$main_swf"
cp -p -- "$loader_output" "$app_dir/ml-patched.swf"
cp -p -- "$core_output" "$app_dir/core-patched.swf"
perl -0pi -e 's#<renderMode>gpu</renderMode>#<renderMode>cpu</renderMode>#' "$application_xml"
grep -q '<renderMode>cpu</renderMode>' "$application_xml" || fail "could not enable CPU rendering in application.xml"
printf 'sanalika-linux=%s\nclient=1.0.1.1\n' "$PATCH_VERSION" > "$app_dir/.sanalika-linux-version"

printf '\nSanalika patched successfully.\nApplication directory: %s\n' "$app_dir"
