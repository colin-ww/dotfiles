#!/bin/bash

# see: https://claude.ai/chat/1540efcf-491e-4344-b536-f47f11156400

# SOURCE OF TRUTH: this file + apt-packages.txt, r-packages.txt, user-claude.md
# (same folder). The cloud env's "Setup script" field only
# downloads + runs it (bootstrap in README.md). After editing this file and
# merging to main, bump the version date in the env's field: the env cache
# only rebuilds when that field's text changes (or after ~7 days).

# time takes to run:
#   2026.10.16: 0m47 - first draft
#   2026.11.07: 0m42 - 31 extras (live env log)

# ============================================================================
# Claude Code cloud env: R + tidyverse-style stack
#
# WHY: Each cloud session is a fresh Ubuntu VM with no R. This script runs
# once, Anthropic snapshots the disk, and later sessions start with
# everything already installed (no waiting, no Claude installing things).
#
# CACHE RULES (from the docs):
#   - Snapshot only if the whole script finishes in ~5 min. Over that, it
#     reruns every session. Expected runtime here: ~2-4 min (rough guess).
#   - Rebuilds when you edit this script, change network settings, or ~7 days.
#   - Packages Claude installs mid-session are NOT kept. Add them here.
#
# NEEDS: Network access = Full (CRAN + Posit aren't on the Trusted list).
#
# FAILURE POLICY:
#   - Core (R itself, tidyverse): fail loudly with exit 1. The session won't
#     start, so you notice, and a broken setup doesn't get cached for 7 days.
#   - Extras: soft fail, logged, the session still starts.
#
# LOG: everything goes to /var/log/cc-setup.log. Ask Claude to read it if
# something seems off.
# ============================================================================

exec > >(tee -a /var/log/cc-setup.log) 2>&1
echo "=== setup start: $(date) ==="

export DEBIAN_FRONTEND=noninteractive  # stop apt from asking questions

# Ubuntu codename (docs say 24.04 = "noble"). Read it rather than hardcode,
# so this keeps working if Anthropic upgrades the base image.
. /etc/os-release
CODENAME="${VERSION_CODENAME:-noble}"
echo "Ubuntu codename: $CODENAME"

# Config (pkg lists + CLAUDE.md) lives in separate files next to this script.
# CFG_DIR set (CI, local test) = use that dir. Else download from main.
CFG_BASE="https://raw.githubusercontent.com/colin-ww/dotfiles/main/claude-code/cloud"
CFG_FILES="apt-packages.txt r-packages.txt user-claude.md"
if [ -z "${CFG_DIR:-}" ]; then
  CFG_DIR="$(mktemp -d)"
  for f in $CFG_FILES; do
    curl -fsSL "$CFG_BASE/$f" -o "$CFG_DIR/$f" || { echo "FAIL: download $f"; exit 1; }
  done
fi
echo "Config dir: $CFG_DIR"
# One word per line, "#" comments stripped.
words() { sed 's/#.*//' "$1" | tr -s ' \t' '\n' | grep . || true; }

# ----------------------------------------------------------------------------
# STEP 1: Add CRAN's own Ubuntu repo  (~5 s)
# WHY: Ubuntu's built-in R is older (4.3 on noble). CRAN's repo has current
#      R, which matters because Posit's prebuilt binaries (step 3) target
#      current R versions.
# WATCH OUT: don't apt-install Ubuntu's r-cran-* packages alongside this.
#      They're built for Ubuntu's older R and can clash with Posit packages.
# ----------------------------------------------------------------------------
curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
  > /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc || { echo "FAIL: CRAN key"; exit 1; }
echo "deb https://cloud.r-project.org/bin/linux/ubuntu ${CODENAME}-cran40/" \
  > /etc/apt/sources.list.d/cran-r.list

# ----------------------------------------------------------------------------
# STEP 2: Install R + system libraries  (~1-1.5 min)
# Package list + why each system lib is there: apt-packages.txt
# WATCH OUT: if a package later says "cannot open shared object libXYZ.so",
#   a system lib is missing. Add its -dev package to apt-packages.txt.
# ----------------------------------------------------------------------------
apt-get update -qq || { echo "FAIL: apt update"; exit 1; }
mapfile -t APT_PKGS < <(words "$CFG_DIR/apt-packages.txt")
apt-get install -y -qq --no-install-recommends "${APT_PKGS[@]}" \
  || { echo "FAIL: R install"; exit 1; }

# ----------------------------------------------------------------------------
# STEP 3: Point R at Posit Package Manager binaries  (instant)
# WHY: Plain CRAN gives Linux *source* code, so tidyverse would compile for
#      10-20+ min (blowing the 5-min cache limit). Posit serves prebuilt
#      Linux binaries of current CRAN, so installs take seconds per package.
# HTTPUserAgent: Posit decides binary vs source based on this header.
#      Without it you may silently get source again (= slow).
# Ncpus = 4: VM has 4 vCPUs; parallel builds if anything does compile.
# timeout = 600: R's default download timeout is 60 s, which can kill big
#      binaries (arrow, duckdb are tens of MB).
# Written to Rprofile.site, so it applies to EVERY R session later,
#      including when Claude runs Rscript mid-session.
# ----------------------------------------------------------------------------
cat >> "$(R RHOME)/etc/Rprofile.site" <<EOF
options(
  repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/${CODENAME}/latest"),
  HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(),
    paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])),
  Ncpus = 4,
  timeout = 600
)
EOF

# ----------------------------------------------------------------------------
# STEP 4a: Core R packages  (~1-1.5 min)
# tidyverse already includes dplyr, dbplyr, tidyr, purrr, readr, haven (SAS
# files), lubridate, stringr, forcats, ggplot2, DBI (via dbplyr), etc.
# Hard requirement: if it fails, stop.
# ----------------------------------------------------------------------------
Rscript -e 'install.packages("tidyverse")' || { echo "FAIL: tidyverse"; exit 1; }

# ----------------------------------------------------------------------------
# STEP 4b: Extra R packages  (~0.5-1 min). EDIT FREELY.
# Soft fail: a failure is logged but the session still starts.
# Biggest downloads: arrow, duckdb. Drop them if runtime creeps toward 5 min.
# List + notes on what is covered/left out: r-packages.txt
# ----------------------------------------------------------------------------
Rscript -e '
pkgs <- scan(commandArgs(TRUE)[1], what = "", comment.char = "#", quiet = TRUE)
install.packages(pkgs)
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) message("EXTRAS FAILED: ", paste(missing, collapse = ", "))
' "$CFG_DIR/r-packages.txt" || echo "WARN: extras step errored (see above)"

# ----------------------------------------------------------------------------
# STEP 5: Tell Claude what's set up  (instant)
# ~/.claude/CLAUDE.md is loaded as personal instructions in EVERY cloud
# session, whatever repo. Stops Claude reinstalling R or compiling things.
# It combines with any repo CLAUDE.md, it doesn't replace it.
# ----------------------------------------------------------------------------
install -D -m 644 "$CFG_DIR/user-claude.md" ~/.claude/CLAUDE.md

# ----------------------------------------------------------------------------
# STEP 6: Self-check  (~5 s)
# Fails setup (= no broken snapshot cached) if R can't load tidyverse.
# ----------------------------------------------------------------------------
Rscript -e 'suppressMessages(library(tidyverse)); cat("R", as.character(getRversion()), "OK\n")' \
  || { echo "FAIL: self-check"; exit 1; }

echo "=== setup done: $(date), took ${SECONDS}s ==="
# Snapshot is only cached if the whole script finishes in ~5 min.
[ "$SECONDS" -le 240 ] || echo "WARN: setup took over 4 min, close to the ~5 min cache limit"
exit 0
