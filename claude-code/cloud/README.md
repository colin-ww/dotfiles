# claude-code/cloud

## R-setup.sh

Single source of truth for the cloud env. The env's "Setup script" field
holds only this bootstrap, which downloads + runs R-setup.sh from main:

    #!/bin/bash
    # v2026-11-07  <- bump after editing R-setup.sh (env cache only rebuilds when this text changes, or ~7 days)
    set -euo pipefail
    curl -fsSL https://raw.githubusercontent.com/colin-ww/dotfiles/main/claude-code/cloud/R-setup.sh -o /tmp/R-setup.sh
    bash /tmp/R-setup.sh

Workflow: edit R-setup.sh -> merge to main -> bump the date line in the env field.

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



