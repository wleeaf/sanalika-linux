#!/usr/bin/env bash
set -Eeuo pipefail

readonly PATCH_VERSION="0.2.0"
readonly FFDEC_VERSION="26.2.1"
readonly FFDEC_URL="https://github.com/jindrapetrik/jpexs-decompiler/releases/download/version26.2.1/ffdec_26.2.1.zip"
readonly EXPECTED_FFDEC_HASH="0333b56998a55bd83f4e0deb678a811fcdc45607582b4f5dd438309c8c3ad5ce"
readonly CLIENT_CONFIG_URL="https://cf.sanalika.com/c.json"
readonly EXPECTED_MAIN_HASH="675e74272f4d0ec9dc9bb4f0bc41edbb832b31f2089287e274ac021f0301ae29"

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
    printf 'Run it again whenever Sanalika publishes a new loader.\n'
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

# Always rebuild from the official client so the script can be re-run after updates.
main_source="$main_swf"
if [[ "$(hash_file "$main_swf")" != "$EXPECTED_MAIN_HASH" && -f "$main_swf.original" ]]; then
    main_source="$main_swf.original"
fi
current_main_hash=$(hash_file "$main_source")
[[ "$current_main_hash" == "$EXPECTED_MAIN_HASH" ]] || fail "unsupported Sanalika.swf hash ($current_main_hash); this release targets clients 1.0.1.1 and 1.0.1.2"

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

# The preloader is published by Sanalika and changes with server updates, so
# always use the one the live client configuration points to. The game core is
# not stored locally: the patched preloader downloads the current one at launch.
client_config="$work_dir/c.json"
curl --fail --location --retry 3 --silent --show-error "$CLIENT_CONFIG_URL" -o "$client_config" || fail "could not download the Sanalika client configuration"
remote_loader_url=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["loader"])' "$client_config") || fail "the Sanalika client configuration has no loader URL"
[[ "$remote_loader_url" == https://*.sanalika.com/* ]] || fail "unexpected loader URL: $remote_loader_url"

remote_root="$cache_root/remote-swf"
mkdir -p "$remote_root"
remote_loader="$remote_root/$(basename -- "$remote_loader_url")"
if [[ ! -f "$remote_loader" ]]; then
    curl --fail --location --retry 3 --silent --show-error "$remote_loader_url" -o "$remote_loader.part"
    mv -- "$remote_loader.part" "$remote_loader"
fi

patch_swf() {
    local kind=$1
    local input=$2
    local output=$3
    local source_root="$work_dir/$kind-source"
    mkdir -p "$source_root"
    printf 'Exporting %s scripts...\n' "$kind"
    "$ffdec" -format script:as -export script "$source_root" "$input" >/dev/null || return 1
    python3 "$project_dir/patches/patch_sources.py" --kind "$kind" "$source_root" || return 1
    case "$kind" in
        main) target_script='scripts/com/oyunstudyosu/air/model/LoaderModel.as' ;;
        preloader) target_script='scripts/extensions/MainLoader.as' ;;
    esac
    find "$source_root" -type f -name '*.as' ! -path "$source_root/$target_script" -delete || return 1
    printf 'Rebuilding %s...\n' "$kind"
    "$ffdec" -importScript "$input" "$output" "$source_root" >/dev/null
}

main_output="$work_dir/Sanalika.swf"
loader_output="$work_dir/ml-patched.swf"
patch_swf main "$main_source" "$main_output"
patch_swf preloader "$remote_loader" "$loader_output" || fail "the current Sanalika preloader ($remote_loader_url) is not supported by this patch"

[[ -s "$main_output" && -s "$loader_output" ]] || fail "JPEXS produced an empty rebuilt SWF"

backup_once "$main_swf"
backup_once "$application_xml"

cp -p -- "$main_output" "$main_swf"
cp -p -- "$loader_output" "$app_dir/ml-patched.swf"
# Older releases shipped a pinned local core; the live one is used now.
rm -f -- "$app_dir/core-patched.swf"
perl -0pi -e 's#<renderMode>gpu</renderMode>#<renderMode>cpu</renderMode>#' "$application_xml"
grep -q '<renderMode>cpu</renderMode>' "$application_xml" || fail "could not enable CPU rendering in application.xml"
printf 'sanalika-linux=%s\nloader=%s\n' "$PATCH_VERSION" "$remote_loader_url" > "$app_dir/.sanalika-linux-version"

printf '\nSanalika patched successfully.\nApplication directory: %s\n' "$app_dir"
