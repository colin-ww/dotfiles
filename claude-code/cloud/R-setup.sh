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
#   - Extras: soft fail, logged as "WARN:", the session still starts. A
#     failed setup = a session with NO R at all, so one flaky extra pkg
#     shouldn't cost you everything.
#   - STRICT=1 (CI sets it): any WARN makes the script exit 1 at the end, so
#     problems turn CI red before they reach main. Soft in sessions, strict in CI.
#
# LOG: everything goes to /var/log/cc-setup.log. Ask Claude to read it if
# something seems off.
# ============================================================================

exec > >(tee -a /var/log/cc-setup.log) 2>&1
echo "=== setup start: $(date) ==="

export DEBIAN_FRONTEND=noninteractive  # stop apt from asking questions

# Downloads retry + time out instead of hanging silently. 2026-11-17: CI sat
# 4 min with zero output right after "Config dir" (curl/apt have no timeout by
# default, apt -qq prints nothing while downloading) and got killed.
CURL=(curl -fsSL --retry 3 --connect-timeout 20 --max-time 300)
APT_NET=(-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)
# Elapsed time per step, so a slow/stuck step shows in the log.
step() { echo "--- $* (${SECONDS}s)"; }

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
    "${CURL[@]}" "$CFG_BASE/$f" -o "$CFG_DIR/$f" || { echo "FAIL: download $f"; exit 1; }
  done
fi
echo "Config dir: $CFG_DIR"
# One word per line, "#" comments stripped.
words() { sed 's/#.*//' "$1" | tr -s ' \t' '\n' | grep . || true; }
# Soft failure: log it, count it (STRICT=1 turns any into exit 1 at the end).
SOFT_FAILS=0
warn() { echo "WARN: $*"; SOFT_FAILS=$((SOFT_FAILS + 1)); }

# ----------------------------------------------------------------------------
# STEP 1: Add CRAN's own Ubuntu repo  (~5 s)
# WHY: Ubuntu's built-in R is older (4.3 on noble). CRAN's repo has current
#      R, which matters because Posit's prebuilt binaries (step 3) target
#      current R versions.
# WATCH OUT: don't apt-install Ubuntu's r-cran-* packages alongside this.
#      They're built for Ubuntu's older R and can clash with Posit packages.
# ----------------------------------------------------------------------------
step "1: CRAN apt repo"
"${CURL[@]}" https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
  > /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc || { echo "FAIL: CRAN key"; exit 1; }
echo "deb https://cloud.r-project.org/bin/linux/ubuntu ${CODENAME}-cran40/" \
  > /etc/apt/sources.list.d/cran-r.list

# ----------------------------------------------------------------------------
# STEP 2: Install R + system libraries  (~1-1.5 min)
# Package list + why each system lib is there: apt-packages.txt
# WATCH OUT: if a package later says "cannot open shared object libXYZ.so",
#   a system lib is missing. Add its -dev package to apt-packages.txt.
# ----------------------------------------------------------------------------
step "2: apt update + install"
apt-get update -q "${APT_NET[@]}" || { echo "FAIL: apt update"; exit 1; }
mapfile -t APT_PKGS < <(words "$CFG_DIR/apt-packages.txt")
apt-get install -y -q --no-install-recommends "${APT_NET[@]}" "${APT_PKGS[@]}" \
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
# UTF-8: the VM has no LANG, so R ran in the "C" locale: nchar("é") = 2,
#   toupper("é") = "é", regex "." doesn't match é, prints "Qu\303\251bec".
#   Bad for French data. C.UTF-8 is built into Ubuntu (no locales pkg needed).
#   ${LANG-...} = only if LANG isn't already set (R expands it, not bash).
echo 'LANG=${LANG-C.UTF-8}' >> "$(R RHOME)/etc/Renviron.site"

# ----------------------------------------------------------------------------
# STEP 3b: Bring what's already installed up to CRAN, BEFORE adding new pkgs.
#   Soft fail. (~3 s fresh)
# WHY: install.packages() installs MISSING deps but never upgrades an old one,
#   even when a new pkg needs a newer version (">= x.y") -> that pkg won't load.
#   Fresh build: only R's bundled "recommended" pkgs (Matrix, MASS, cluster...)
#   exist yet. They come from the r-recommended deb, which lags CRAN (apt can't
#   give newer), so update them from CRAN. Re-running setup in an old
#   container: also stale pkgs from last time (2026-11-23: shiny 1.14 stayed
#   while CRAN shiny 1.15 had added a new dep, watcher).
# ----------------------------------------------------------------------------
step "3b: update.packages"
Rscript -e 'update.packages(ask = FALSE, checkBuilt = TRUE)' || warn "update.packages failed"

# ----------------------------------------------------------------------------
# STEP 4a: Core R packages  (~1-1.5 min)
# tidyverse already includes dplyr, dbplyr, tidyr, purrr, readr, haven (SAS
# files), lubridate, stringr, forcats, ggplot2, DBI (via dbplyr), etc.
# Hard requirement: if it fails, stop.
# ----------------------------------------------------------------------------
step "4a: tidyverse"
Rscript -e 'install.packages("tidyverse")' || { echo "FAIL: tidyverse"; exit 1; }

# ----------------------------------------------------------------------------
# STEP 4b: Extra R packages  (~0.5-1 min). EDIT FREELY.
# Soft fail: a failure is logged but the session still starts.
# Biggest downloads: arrow, duckdb. Drop them if runtime creeps toward 5 min.
# List + notes on what is covered/left out: r-packages.txt
# ----------------------------------------------------------------------------
step "4b: extra R pkgs"
Rscript -e '
pkgs <- scan(commandArgs(TRUE)[1], what = "", comment.char = "#", quiet = TRUE)
install.packages(pkgs)
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) { message("EXTRAS FAILED: ", paste(missing, collapse = ", ")); quit(status = 1) }
' "$CFG_DIR/r-packages.txt" || warn "extra R pkgs failed to install (EXTRAS FAILED above)"

# ----------------------------------------------------------------------------
# STEP 4c: duckdb CLI  (~5 s, 24 MB). Soft fail.
# Same DuckDB version as the engine inside the R duckdb pkg, so a .duckdb file
# written by one opens in the other. Not in Ubuntu's apt: official download
# (same URL as DuckDB's install script; v2+ ships a .tar.gz, v1 was .gz).
# ~/.duckdb: R duckdb 2.x otherwise keeps extensions in a temp dir (re-downloaded
#   every session) and prints a notice on every connect. With it, R and the
#   CLI share one home (same version -> same extensions).
# ----------------------------------------------------------------------------
step "4c: duckdb CLI"
mkdir -p ~/.duckdb
DUCKDB_V="$(Rscript -e 'con <- DBI::dbConnect(duckdb::duckdb()); cat(DBI::dbGetQuery(con, "select version() v")$v); DBI::dbDisconnect(con)' 2>/dev/null)"
case "$(uname -m)" in aarch64|arm64) DUCKDB_ARCH=arm64 ;; *) DUCKDB_ARCH=amd64 ;; esac
{ [ -n "$DUCKDB_V" ] \
  && "${CURL[@]}" "https://install.duckdb.org/${DUCKDB_V}/duckdb-cli-linux-${DUCKDB_ARCH}.tar.gz" \
     | tar -xzf - -C /usr/local/bin duckdb \
  && [ "$(duckdb --version | grep -oE '^v[0-9.]+')" = "$DUCKDB_V" ] \
  && echo "duckdb CLI $DUCKDB_V OK"; } \
  || warn "duckdb CLI install failed (wanted ${DUCKDB_V:-?}, same as R duckdb engine)"

# ----------------------------------------------------------------------------
# STEP 4d: Oracle Instant Client (Basic Lite)  (~8 s, 76 MB download, 171 MB
# on disk). Soft fail. OFF for now: uncomment the block below AND libaio1t64
# in apt-packages.txt to turn it on.
# WHY: ROracle loads without it, but dbDriver("Oracle")/dbConnect() need
#   libclntsh.so. StatCan DBs aren't reachable from here either way; with it,
#   ROracle code fails at connect (ORA-12262), not at driver load.
#   Tested 2026-11-22: dbDriver("Oracle") OK, connect -> ORA-12262 (expected).
# WATCH OUT: noble renamed libaio.so.1 -> libaio.so.1t64, so symlink the old
#   name. URL = Oracle's unpinned "latest" (no login), x64 only (ARM: -arm64).
# ----------------------------------------------------------------------------
# step "4d: Oracle Instant Client"
# OIC_ZIP="$(mktemp --suffix=.zip)"
# { "${CURL[@]}" -o "$OIC_ZIP" \
#     https://download.oracle.com/otn_software/linux/instantclient/instantclient-basiclite-linuxx64.zip \
#   && mkdir -p /opt/oracle && unzip -qo "$OIC_ZIP" -d /opt/oracle \
#   && OIC_DIR="$(ls -d /opt/oracle/instantclient_* | sort -V | tail -1)" \
#   && ln -sf /usr/lib/x86_64-linux-gnu/libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1 \
#   && echo "$OIC_DIR" > /etc/ld.so.conf.d/oracle-instantclient.conf && ldconfig \
#   && Rscript -e 'invisible(ROracle::Oracle())' \
#   && echo "Oracle Instant Client OK ($OIC_DIR)"; } \
#   || warn "Oracle Instant Client install failed"
# rm -f "$OIC_ZIP"

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
Rscript -e 'x <- "Québec"; stopifnot(l10n_info()[["UTF-8"]], nchar(x) == 6, toupper(x) == "QUÉBEC")' \
  || warn "R isn't in a UTF-8 locale (accents break)"

echo "=== setup done: $(date), took ${SECONDS}s, $SOFT_FAILS warning(s) ==="
# Snapshot is only cached if the whole script finishes in ~5 min.
[ "$SECONDS" -le 240 ] || warn "setup took over 4 min, close to the ~5 min cache limit"
if [ "${STRICT:-0}" = 1 ] && [ "$SOFT_FAILS" -gt 0 ]; then
  echo "STRICT: $SOFT_FAILS warning(s) -> exit 1"; exit 1
fi
exit 0
