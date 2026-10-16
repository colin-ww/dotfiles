#!/bin/bash

# see: https://claude.ai/chat/1540efcf-491e-4344-b536-f47f11156400

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
# r-base      = R plus "recommended" pkgs (Matrix, MASS, survival, ...)
# r-base-dev  = compilers/headers, so a package with no binary can still
#               build from source as a fallback
# lib*-dev    = system libraries tidyverse-type packages link to at runtime:
#   curl/ssl -> httr, curl     xml2 -> xml2, rvest     uv -> fs
#   fontconfig/harfbuzz/fribidi/freetype/png/tiff/jpeg -> ragg, textshaping
#   (ggplot2 graphics)
# WATCH OUT: if a package later says "cannot open shared object libXYZ.so",
#   a system lib is missing. Add its -dev package to this list.
# ----------------------------------------------------------------------------
apt-get update -qq || { echo "FAIL: apt update"; exit 1; }
apt-get install -y -qq --no-install-recommends \
  r-base r-base-dev \
  libcurl4-openssl-dev libssl-dev libxml2-dev libuv1-dev \
  libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
  libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev \
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
# NOT useful here: odbc/ROracle. The cloud VM can't reach StatCan DBs anyway.
# ----------------------------------------------------------------------------
Rscript -e '
pkgs <- c(
  "janitor",     # clean_names, tabyl
  "testthat",    # unit tests
  "styler",      # auto-format code
  "lintr",       # lint / style checks
  "arrow",       # parquet
  "duckdb",      # fast local SQL on files
  "data.table",  # fast fread/fwrite
  "targets",     # pipelines
  "here"         # project-relative paths
)
install.packages(pkgs)
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) message("EXTRAS FAILED: ", paste(missing, collapse = ", "))
' || echo "WARN: extras step errored (see above)"

# ----------------------------------------------------------------------------
# STEP 5: Tell Claude what's set up  (instant)
# ~/.claude/CLAUDE.md is loaded as personal instructions in EVERY cloud
# session, whatever repo. Stops Claude reinstalling R or compiling things.
# It combines with any repo CLAUDE.md, it doesn't replace it.
# ----------------------------------------------------------------------------
mkdir -p ~/.claude
cat > ~/.claude/CLAUDE.md <<'EOF'
# Environment notes (written by the cloud setup script)
- R (current, from CRAN's Ubuntu repo) and tidyverse + common packages are preinstalled. Run R with Rscript.
- CRAN is set to Posit Package Manager Linux binaries, so install.packages() is fast for anything missing.
- Never reinstall R or packages that are already installed. Never build R from source.
- If R or packages seem broken, read /var/log/cc-setup.log before trying fixes.
EOF

# ----------------------------------------------------------------------------
# STEP 6: Self-check  (~5 s)
# Fails setup (= no broken snapshot cached) if R can't load tidyverse.
# ----------------------------------------------------------------------------
Rscript -e 'suppressMessages(library(tidyverse)); cat("R", as.character(getRversion()), "OK\n")' \
  || { echo "FAIL: self-check"; exit 1; }

echo "=== setup done: $(date) ==="
exit 0
