# Environment notes (written by the cloud setup script, from dotfiles/claude-code/cloud/user-claude.md)

## What's installed
- R (current, from CRAN's Ubuntu repo), tidyverse and ~45 extras are preinstalled. Run R with `Rscript`.
- CRAN is set to Posit Package Manager Linux binaries (Rprofile.site), so `install.packages()` takes seconds for anything missing.
- Never reinstall R or packages that are already installed. Never build R from source.
- Installs done mid-session are NOT kept for the next session. If a package is needed regularly, tell the user to add it to `claude-code/cloud/r-packages.txt` in the dotfiles repo (system libs: `apt-packages.txt`).

## If something is broken
- Read `/var/log/cc-setup.log` first (full setup output). If setup failed, the session started without it.
- `cannot open shared object file: libXYZ.so` = missing system library. Fix for this session with `apt-get install -y <pkg>` (find it with `apt-file`/`apt-cache search`), then tell the user the exact `-dev` package name so it can go into `apt-packages.txt`. Don't guess names: check `apt-cache policy <pkg>` first (Ubuntu 24.04 "noble").
- Package from internal GitLab (zonetools, RDCI) or StatCan databases (Oracle/MSSQL): not reachable from here. Stub or skip, say so.

## Code style (R)
- tidyverse, native pipe `|>` (magrittr `%>%` only when `.` saves a lot of typing).
- DRY, short pipe chains over many intermediate objects, but keep it readable.
- No person-level data in the repo, ever.
