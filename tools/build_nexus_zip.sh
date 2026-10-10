#!/usr/bin/env bash
# Packs the mod for Nexus: every file committed to git, minus whatever .nexusignore
# matches (same syntax as .gitignore). The repository is already laid out BAIN style, so
# every file keeps its path:
#
#   00 Core/                  the mod
#   01 Glass Glowset Patch/   an optional patch: any top-level "NN Name" folder
#   fomod/                    the installer mod organisers show, which explains the patches
#
# A file anywhere else would be shipped loose beside them, so that stops the packing instead.
#
#   bash tools/build_nexus_zip.sh [output.zip]    (default: nexus-upload.zip)
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-nexus-upload.zip}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
rm -f "$out"

files=$(comm -23 \
    <(git -c core.quotePath=false ls-files | sort) \
    <(git -c core.quotePath=false ls-files --cached --ignored --exclude-from=.nexusignore | sort))

if [ -z "$files" ]; then
    echo "Nothing to pack - check .nexusignore" >&2
    exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
while IFS= read -r f; do
    case "$f" in
        fomod/* | [0-9][0-9]\ */*) ;;
        *)
            echo "$f is outside \"00 Core\", the patch folders and fomod/ - move it, or add it to .nexusignore" >&2
            exit 1
            ;;
    esac
    mkdir -p "$stage/$(dirname "$f")"
    cp -p "$f" "$stage/$f"
done <<< "$files"

(cd "$stage" && zip -q -X -r "$out" .)
echo "Packed $(printf '%s\n' "$files" | wc -l) files into $out"
