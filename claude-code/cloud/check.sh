#!/bin/bash
# CI / local check for the cloud setup (run on Ubuntu 24.04 = noble).
#   bash claude-code/cloud/check.sh
# Catches the typos that break the cloud env: bash errors, apt names that don't
# exist (eg libglpk40-dev, 2026-11-13), R pkgs not on CRAN.
set -uo pipefail
cd "$(dirname "$0")"
fail=0
bad() { echo "FAIL: $*"; fail=1; }
words() { sed 's/#.*//' "$1" | tr -s ' \t' '\n' | grep . || true; }
SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo"

echo "== bash syntax + shellcheck"
bash -n R-setup.sh check.sh || bad "bash syntax"
if command -v shellcheck >/dev/null; then
  shellcheck -S warning R-setup.sh check.sh || bad "shellcheck"
else echo "(shellcheck not installed, skipped)"; fi

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
curl -fsSL "https://packagemanager.posit.co/cran/__linux__/noble/latest/src/contrib/PACKAGES" -o "$idx" \
  || bad "download CRAN index"
for p in tidyverse $(words r-packages.txt); do
  grep -q "^Package: $p\$" "$idx" || bad "R package '$p' not on CRAN"
done

[ "$fail" = 0 ] && echo "ALL OK" || { echo "CHECKS FAILED"; exit 1; }
