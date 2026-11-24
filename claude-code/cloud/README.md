# claude-code/cloud

## Folder layout: feeding R-setup.sh

| File | What | Edit when |
|---|---|---|
| `apt-packages.txt` | system libs (+ why) | an R pkg says `cannot open shared object libXYZ.so` |
| `r-packages.txt` | extra R pkgs by category (extra to `tidyverse`) | you want a pkg preinstalled |
| `user-claude.md` | becomes `~/.claude/CLAUDE.md` in every cloud session | Claude needs to know something about the env |
| `R-setup.sh` | the code: reads the three files above | steps change (rare) |
| `pkg-inventory.R` -> `r-packages-installed.csv` | every R pkg the setup installs: tidy-direct / oth-direct / both / indirect. Also loads each one (fails on a missing system lib). CI regenerates + commits it | never by hand: edit `r-packages.txt` |
| `check.sh` | tests (bash syntax, shellcheck, apt/CRAN names exist) | - |

CI (`.github/workflows/cloud-setup.yml`) runs `check.sh`, then the whole
`R-setup.sh` on an Ubuntu 24.04 runner with `STRICT=1` (any `WARN:` = red; in
sessions they're soft so one flaky pkg doesn't cost you R), then loads every R pkg.
Run the quick part locally (as root or with sudo): `bash claude-code/cloud/check.sh`.

No build step: `R-setup.sh` downloads the three files from main at runtime
(or uses `CFG_DIR=<dir>` if set, which CI does).

## R-setup.sh

Single source of truth for the cloud env. The env's "Setup script" field
holds only this bootstrap, which downloads + runs R-setup.sh from main:

    #!/bin/bash
    # v2026-11-15  <- bump after editing R-setup.sh or the 3 config files (env cache only rebuilds when this text changes, or ~7 days; README etc. don't matter)
    set -euo pipefail
    curl -fsSL https://raw.githubusercontent.com/colin-ww/dotfiles/main/claude-code/cloud/R-setup.sh -o /tmp/R-setup.sh
    bash /tmp/R-setup.sh

Workflow: edit (branch) -> CI green -> merge to main -> bump the date line in the env field.

## Ideas, not done (yet)

- **If the cloud env breaks while CI is green: run CI in a bare `ubuntu:24.04`
  container.** CI's runner image and the cloud image are both noble, but each
  has its own pile of preinstalled debs. A system lib that's preinstalled on the
  runner but NOT in the cloud image (and not in `apt-packages.txt`) passes CI and
  breaks the cloud env. A bare container has almost nothing, so any lib we rely on
  without listing it turns CI red. Cost: more debs to install (slower), and a
  bootstrap for `curl` + `ca-certificates` before `R-setup.sh`. In the workflow:
  `full-run:` -> `container: ubuntu:24.04`, drop `sudo`.
- **Weekly scheduled CI run** (`on: schedule: - cron: ...`). CI only runs when
  this folder changes, but CRAN changes daily and the cloud env rebuilds ~weekly
  on whatever CRAN has then. A scheduled run catches a breaking CRAN release
  before a cloud build does.
- **pak instead of install.packages(): tested 2026-11-23, slower here.** Full list
  into an empty library, cold cache, in a cloud session: install.packages()
  1m17, `pak::pkg_install()` 1m51 (2m09 with pak's own sysreqs apt step on).
  pak also leaves a ~600 MB download cache (would need `pak::cache_clean()`).
  Its plus: upgrades deps when a pkg needs a newer version. `update.packages()`
  (step 3b) covers that for us.

## scan-repo-deps.R

What do my repos use (all branches) that the env doesn't install? Run in a
cloud session:

```
Rscript claude-code/cloud/scan-repo-deps.R ../sc-nts-frame ../rr-tests
```

-----

-----

<br>

```
https://code.claude.com/docs/en/cloud-environments

also instructions custom claude.md based on cat, as I'm doing

4 vCPUs
16 GB of RAM
30 GB of disk



components, drafts:

### pkgs

compute deps?
lookup cranwatch or r universe?
ask Claude via pak tree?

==for sure:
duckdb-cli
quarto?

tidyverse (dplyr rlang purrr stringr readr tibble ggplot2 tidyr...
           ... magrittr pillar vctrs lubridate forcats tidyselect)
testthat
cli
data.table

here
usethis
glue
stringi

assertthat

fs
ps
callr


https://github.com/hadley/data-diff
multiplyr

reshape2

httr
httr2
skimr

lintr
stylr
wrapr
curl


==maybe:
renv
use_tidy_... usethis?
devtools
config
box
waldo
withr
jsonlite
yaml
reticulate
scales
rvest
vroom
arsenal?

nanonext
ellmer
mcptools

bench
lobstr

dbplyr
DBI
odbc
targets
tarchetypes   # targets helpers (tar_hook_before...). rr-tests 04-targets.R uses it, its tests don't -> not in R-setup.sh yet (2026.11.07)
igraph
qs2

readxl
openxlsx2


==no:
zeallot
Rcpp RcppParallel
S7
doctest
tidytab
logr autometric
onetime
mutagen
bootstrapper
pak

arrow
duckdb duckplyr dtplyr multiplyr
RSQLite
nanoparquet
nanoarrow
digest

==non cran:
polars-r
polars0?
tidypolars-r



### CLAUDE.md

ping every 2h if ultra effort?


```



