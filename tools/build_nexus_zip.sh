#!/usr/bin/env bash
# Packs the mod for Nexus: every file of the last commit (HEAD), minus whatever the committed
# .nexusignore matches (same syntax as .gitignore). The repository is already laid out BAIN
# style, so every file keeps its path:
#
#   00 Core/                  the mod
#   01 Glass Glowset Patch/   an optional patch: any top-level "NN Name" folder
#   fomod/                    the installer mod organisers show, which explains the patches
#
# A file anywhere else would be shipped loose beside them, so that stops the packing instead.
# Uncommitted changes are left out, so a local build packs what a release of that commit
# would; a warning names the files whose working copy differs.
#
#   bash tools/build_nexus_zip.sh [output.zip]
#
# The output defaults to nexus-upload.zip in the repository root; a relative path is taken
# from where the script is run.
set -euo pipefail

out="${1:-}"
[ -z "$out" ] || out=$(realpath -m -- "$out")
cd "$(dirname "$0")/.."
out="${out:-$PWD/nexus-upload.zip}"
rm -f "$out"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
real_index=$(realpath -m "$(git rev-parse --git-path index)")

# HEAD gets an index of its own to list and check out from, leaving the real one alone.
GIT_INDEX_FILE="$tmp/index" git read-tree HEAD
git show HEAD:.nexusignore > "$tmp/nexusignore"

# The files of an index minus what .nexusignore matches, NUL-separated: any byte but NUL can
# be in a name.
shippable() {
    LC_ALL=C comm -z -23 \
        <(GIT_INDEX_FILE="$1" git ls-files -z | LC_ALL=C sort -z) \
        <(GIT_INDEX_FILE="$1" git ls-files -z --cached --ignored --exclude-from="$tmp/nexusignore" |
            LC_ALL=C sort -z)
}

mapfile -d '' files < <(shippable "$tmp/index")
if [ ${#files[@]} -eq 0 ]; then
    echo "Nothing to pack - check .nexusignore" >&2
    exit 1
fi

for f in "${files[@]}"; do
    case "$f" in
        fomod/* | [0-9][0-9]\ */*) ;;
        *)
            echo "$f is outside \"00 Core\", the patch folders and fomod/ - move it, or add it to .nexusignore" >&2
            exit 1
            ;;
    esac
done

printf '%s\0' "${files[@]}" | GIT_INDEX_FILE="$tmp/index" git checkout-index -z --stdin --prefix="$tmp/stage/"
(cd "$tmp/stage" && zip -q -X -r "$out" .)

# What the working tree has that the archive doesn't: packed files changed or deleted since
# HEAD, and files staged that HEAD lacks.
declare -A packed=() tracked=()
for f in "${files[@]}"; do packed["$f"]=1; done
mapfile -d '' now < <(shippable "$real_index")
for f in "${now[@]}"; do tracked["$f"]=1; done
differ=() unpacked=()
mapfile -d '' changed < <(git diff -z --name-only --no-renames HEAD --)
for f in "${changed[@]}"; do
    if [ -n "${packed[$f]+x}" ]; then
        differ+=("$f")
    elif [ -n "${tracked[$f]+x}" ]; then
        unpacked+=("$f")
    fi
done
if [ ${#differ[@]} -gt 0 ]; then
    echo "warning: packed as committed, which is not what the working tree has:" >&2
    printf '    %s\n' "${differ[@]}" >&2
fi
if [ ${#unpacked[@]} -gt 0 ]; then
    echo "warning: not committed yet, so not packed:" >&2
    printf '    %s\n' "${unpacked[@]}" >&2
fi
if ! git diff --quiet HEAD -- .nexusignore; then
    echo "warning: .nexusignore has uncommitted changes - the committed one was used" >&2
fi

echo "Packed ${#files[@]} files from $(git rev-parse --short HEAD) into $out"
