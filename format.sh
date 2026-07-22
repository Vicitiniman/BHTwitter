#!/usr/bin/env bash
set -Eeuo pipefail

# clang-format wrapper that understands Logos. Plain sources go straight through
# clang-format; .x files first get their %-directives swapped for parseable ObjC
# placeholders and restored afterwards, so hook bodies format like normal methods.
# Usage: format.sh [--check] [files...]   (defaults to everything under src/)

cd "$(dirname "$0")"
style="file:$(pwd)/.clang-format"

check=0
if [[ "${1:-}" == "--check" ]]; then check=1; shift; fi

protect() {
  sed -E \
    -e 's|^([[:space:]]*)%hook[[:space:]]+(.*)$|\1@implementation LOGOSHOOK_\2|' \
    -e 's|^([[:space:]]*)%subclass[[:space:]]+(.*)$|\1@implementation LOGOSSUBCLASS_\2|' \
    -e 's|^([[:space:]]*)%end[[:space:]]*$|\1@end //LOGOSEND|' \
    -e 's|^([[:space:]]*)%group[[:space:]]+(.*)$|\1//LOGOSGROUP \2|' \
    -e 's|^([[:space:]]*)%new[[:space:]]+([+-])|\1/*LOGOSNEW*/\n\1\2|' \
    -e 's|^([[:space:]]*)%new[[:space:]]*$|\1/*LOGOSNEW*/|' \
    -e 's|^([[:space:]]*)%property\b(.*)$|\1@property\2 //LOGOSPROP|' \
    -e 's|^([[:space:]]*)%ctor\b|\1static void LOGOSCTOR(void)|' \
    -e 's|^([[:space:]]*)%dtor\b|\1static void LOGOSDTOR(void)|' \
    -e 's|%orig\b|LOGOSORIG|g' \
    -e 's|%c\(|LOGOSC(|g' \
    -e 's|%init\b|LOGOSINIT|g'
}

restore() {
  sed -E \
    -e 's|@implementation LOGOSHOOK_|%hook |' \
    -e 's|@implementation LOGOSSUBCLASS_|%subclass |' \
    -e 's|@end[[:space:]]*//[[:space:]]*LOGOSEND|%end|' \
    -e 's|//[[:space:]]*LOGOSGROUP |%group |' \
    -e 's|^([[:space:]]*)/\*LOGOSNEW\*/[[:space:]]*$|\1%new|' \
    -e 's|@property(.*;)[[:space:]]*//[[:space:]]*LOGOSPROP|%property\1|' \
    -e 's|static void LOGOSCTOR\(void\)|%ctor|' \
    -e 's|static void LOGOSDTOR\(void\)|%dtor|' \
    -e 's|LOGOSORIG|%orig|g' \
    -e 's|LOGOSC\(|%c(|g' \
    -e 's|LOGOSINIT|%init|g' \
    -e 's|[[:space:]]+$||'
}

format_to() {
  local f="$1" out="$2"
  case "$f" in
    *.x|*.xm)
      protect < "$f" | clang-format --style="$style" --assume-filename="${f%.*}.m" | restore > "$out"
      if grep -qE 'LOGOS(HOOK_|SUBCLASS_|END|GROUP|NEW|PROP|CTOR|DTOR|ORIG|C\(|INIT)' "$out"; then
        echo "error: leftover Logos placeholder after formatting $f" >&2
        return 1
      fi
      ;;
    *)
      clang-format --style="$style" "$f" > "$out"
      ;;
  esac
}

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  mapfile -t files < <(find src -type f \( -name '*.m' -o -name '*.h' -o -name '*.x' \) -print | sort)
fi

dirty=0
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

for f in "${files[@]}"; do
  format_to "$f" "$tmp"
  if ! cmp -s "$f" "$tmp"; then
    dirty=1
    if [[ "$check" -eq 1 ]]; then
      echo "would reformat: $f"
    else
      cat "$tmp" > "$f"
      echo "reformatted: $f"
    fi
  fi
done

if [[ "$check" -eq 1 && "$dirty" -eq 1 ]]; then exit 1; fi
