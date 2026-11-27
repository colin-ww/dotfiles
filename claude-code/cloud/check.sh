#!/bin/bash
# CI / local check for the cloud setup (any Ubuntu; release read from /etc/os-release).
#   bash claude-code/cloud/check.sh
# Catches the typos that break the cloud env: bash errors, apt names that don't
# exist (eg libglpk40-dev, 2026-11-13), R pkgs not on CRAN, system libs an R
# pkg needs that apt-packages.txt forgot (eg libpoppler-cpp-dev, 2026-11-23).
# Needs no R: runs in seconds, before R-setup.sh.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
fail=0
bad() { echo "FAIL: $*"; fail=1; }
# A missing tool skips its check locally, but FAILS in CI (GitHub sets CI=true):
# a silently skipped check is how shellcheck slipped past once.
have() {
  command -v "$1" >/dev/null && return 0
  if [ -n "${CI:-}" ]; then bad "$1 not installed (CI must run every check)"; else echo "($1 not installed, skipped)"; fi
  return 1
}
words() { sed 's/#.*//' "$1" | tr -s ' \t' '\n' | grep . || true; }
SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo"
. /etc/os-release  # ID=ubuntu, VERSION_ID=24.04, VERSION_CODENAME=noble
PPM="https://packagemanager.posit.co"
R_PKGS="tidyverse $(words r-packages.txt)"

echo "== bash syntax + shellcheck"
bash -n R-setup.sh check.sh || bad "bash syntax"
if have shellcheck; then shellcheck -S warning R-setup.sh check.sh || bad "shellcheck"; fi

echo "== spelling (codespell: pip install codespell)"
if have codespell; then codespell --skip="*.csv" . ../../.github || bad "codespell"; fi

echo "== config files present"
for f in apt-packages.txt r-packages.txt user-claude.md; do [ -s "$f" ] || bad "$f missing/empty"; done
for f in $(grep -o '[a-z-]*\.\(txt\|md\)' <<<"$(grep '^CFG_FILES=' R-setup.sh)"); do
  [ -f "$f" ] || bad "R-setup.sh downloads $f but it isn't in the repo"
done

echo "== apt names exist"
$SUDO apt-get update -qq || bad "apt update"
# r-base* come from CRAN's repo, which R-setup.sh adds at runtime: skip here.
for p in $(words apt-packages.txt | grep -v '^r-base'); do
  apt-cache show "$p" >/dev/null 2>&1 || bad "apt package '$p' not found (typo? virtual pkg? wrong Ubuntu release?)"
done

echo "== R packages exist on CRAN (Posit Package Manager)"
idx=$(mktemp)
curl -fsSL "$PPM/cran/__linux__/$VERSION_CODENAME/latest/src/contrib/PACKAGES" -o "$idx" \
  || bad "download CRAN index"
for p in $R_PKGS; do
  grep -q "^Package: $p\$" "$idx" || bad "R package '$p' not on CRAN"
done

echo "== system libs covered (Posit sysreqs: our R pkgs + all their deps)"
# Same idea as pak::pkg_sysreqs(), but via Posit's API: no R needed here.
# Each deb must be in apt-packages.txt: installed, or on a "# skip:" line.
if have jq; then
  q=$(printf '&pkgname=%s' $R_PKGS)  # unquoted on purpose: one per pkg
  if sr=$(curl -fsSL "$PPM/__api__/repos/cran/sysreqs?all=false&distribution=$ID&release=$VERSION_ID$q"); then
    covered=$({ words apt-packages.txt; sed -n 's/^# *skip: *//p' apt-packages.txt | sed 's/ --.*//' | tr -s ' \t' '\n'; } | sort -u)
    missing=$(jq -r '.requirements[] | .name as $p | .requirements.packages[] | "\(.)\t\($p)"' <<<"$sr" |
      awk -F'\t' 'NR == FNR {ok[$1]; next} !($1 in ok) {need[$1] = need[$1] " " $2} END {for (d in need) print "  " d " <-" need[d]}' \
        <(echo "$covered") - | sort)
    [ -z "$missing" ] || { echo "$missing"; bad "debs above not in apt-packages.txt: add them, or a '# skip: <deb> -- why' line"; }
  else
    bad "Posit sysreqs API"
  fi
fi

[ "$fail" = 0 ] && echo "ALL OK" || { echo "CHECKS FAILED"; exit 1; }
