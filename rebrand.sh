#!/usr/bin/env bash
set -Eeuo pipefail

# NeoFreeBird rebrander: applies name/icon branding to an already built IPA.
# Usage: rebrand.sh [-t | --twitter-branding] [--twitter-icon PNG] [--resource-pack ZIP] [-o OUTPUT] IPA

is_tty=0
if [[ -t 1 ]]; then is_tty=1; fi
bold='' green='' reset=''
if [[ "$is_tty" -eq 1 ]]; then
  if command -v tput >/dev/null 2>&1; then
    bold="$(tput bold || true)"
    green="$(tput setaf 2 || true)"
    reset="$(tput sgr0 || true)"
  else
    bold='\033[1m'; green='\033[32m'; reset='\033[0m'
  fi
fi

say() { if [[ -n "${bold}${green}${reset}" ]]; then printf "%b%s%b\n" "${bold}${green}" "$1" "${reset}"; else printf "%s\n" "$1"; fi; }
err() { printf "Error: %s\n" "$1" >&2; }
die() { err "$1"; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [-t | --twitter-branding] [--twitter-icon PNG] [--resource-pack ZIP] [-o OUTPUT] IPA
TL;DR: You need to select at least one branding option and a built .ipa/.tipa.

Branding (at least one required):
  -t, --twitter-branding  Set the app's display name to Twitter
  --twitter-icon PNG      Add a selectable alternate app icon from a square PNG
  --resource-pack ZIP     (macOS only) Apply a theme pack ZIP

Options:
  -o, --output PATH       Write a rebranded copy to PATH instead of rebranding in place
  -h, --help              Show this help
EOF
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH"; }

require_cmd python3

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TWITTER_BRANDING=0
TWITTER_APP_ICON=""
RESOURCE_PACK=""
OUTPUT=""
IPA=""

set_ipa() {
  if [[ -n "$IPA" ]]; then die "Multiple IPA paths provided."; fi
  IPA="$1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--twitter-branding)
      TWITTER_BRANDING=1; shift
      ;;
    --twitter-icon)
      [[ $# -ge 2 ]] || die "--twitter-icon requires a path argument."
      TWITTER_APP_ICON="$2"; shift 2
      ;;
    --twitter-icon=*)
      TWITTER_APP_ICON="${1#*=}"; shift
      ;;
    --resource-pack)
      [[ $# -ge 2 ]] || die "--resource-pack requires a path argument."
      RESOURCE_PACK="$2"; shift 2
      ;;
    --resource-pack=*)
      RESOURCE_PACK="${1#*=}"; shift
      ;;
    -o|--output)
      [[ $# -ge 2 ]] || die "--output requires a path argument."
      OUTPUT="$2"; shift 2
      ;;
    --output=*)
      OUTPUT="${1#*=}"; shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do set_ipa "$1"; shift; done
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      set_ipa "$1"; shift
      ;;
  esac
done

if [[ -z "$IPA" || ( "$TWITTER_BRANDING" -eq 0 && -z "$TWITTER_APP_ICON" && -z "$RESOURCE_PACK" ) ]]; then
  usage
  exit 2
fi

if [[ ! -f "$IPA" ]]; then
  die "IPA not found: $IPA"
fi

if [[ -n "$RESOURCE_PACK" && ! -f "$RESOURCE_PACK" ]]; then
  die "--resource-pack file not found: $RESOURCE_PACK"
fi
if [[ -n "$TWITTER_APP_ICON" && ! -f "$TWITTER_APP_ICON" ]]; then
  die "--twitter-icon file not found: $TWITTER_APP_ICON"
fi

if [[ -n "$OUTPUT" ]]; then
  cp -f "$IPA" "$OUTPUT"
  IPA="$OUTPUT"
fi

say "Rebranding $(basename "$IPA")."
TWITTER_BRANDING="$TWITTER_BRANDING" TWITTER_APP_ICON="$TWITTER_APP_ICON" \
  RESOURCE_PACK="$RESOURCE_PACK" \
  python3 "$SCRIPT_DIR/branding/ipa_branding.py" "$IPA"
say "$(basename "$IPA") has been successfully rebranded. Enjoy!"
