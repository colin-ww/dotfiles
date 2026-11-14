# claude-code/cloud

## Layout: config separate from code

| File | What | Edit when |
|---|---|---|
| `apt-packages.txt` | system libs (+ why) | an R pkg says `cannot open shared object libXYZ.so` |
| `r-packages.txt` | extra R pkgs by category | you want a pkg preinstalled |
| `user-claude.md` | becomes `~/.claude/CLAUDE.md` in every cloud session | Claude needs to know something about the env |
| `R-setup.sh` | the code: reads the three files above | steps change (rare) |
| `check.sh` | tests (bash syntax, shellcheck, apt/CRAN names exist) | - |

CI (`.github/workflows/cloud-setup.yml`) runs `check.sh`, then the whole
`R-setup.sh` on an Ubuntu 24.04 runner, on every PR touching this folder.
Run the quick part locally (as root or with sudo): `bash claude-code/cloud/check.sh`.

No build step: `R-setup.sh` downloads the three files from main at runtime
(or uses `CFG_DIR=<dir>` if set, which CI does).

## R-setup.sh

Single source of truth for the cloud env. The env's "Setup script" field
holds only this bootstrap, which downloads + runs R-setup.sh from main:

    #!/bin/bash
    # v2026-11-14  <- bump after editing R-setup.sh or the 3 config files (env cache only rebuilds when this text changes, or ~7 days; README etc. don't matter)
    set -euo pipefail
    curl -fsSL https://raw.githubusercontent.com/colin-ww/dotfiles/main/claude-code/cloud/R-setup.sh -o /tmp/R-setup.sh
    bash /tmp/R-setup.sh

Workflow: edit (branch) -> CI green -> merge to main -> bump the date line in the env field.

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
bootstraper
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



