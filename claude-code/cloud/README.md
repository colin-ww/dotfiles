# Claude Code cloud env: R setup

## R-setup.sh

Copy into an env's (eg Default) setup/startup script field. Rationale and
runtime/caching notes are in the script's comments.

## Choosing packages

### Rules of thumb

- **tidyverse first.** `install.packages("tidyverse")` pulls ~99 hard deps
  (see below), so don't list anything that comes with it.
- **Popular = Claude reaches for it.** Download counts are a rough proxy for how
  much Claude has "seen" a package. Newer / niche (mirai, ellmer, mcptools,
  duckplyr, qs2: all < 800k downloads/yr in
  [cranwatch](https://github.com/colin-ww/cranwatch)) = less likely used, even
  if installed. Skip unless a project needs them.
- **Small data only**: no big-data stack (arrow, targets, db drivers). StatCan
  DBs aren't reachable from the cloud anyway.
- **Cheap = tiny dep tree + no system libs.** Check `deps_n`, `deps_compiled_n`,
  `sysreqs*` in cranwatch's `data/latest.csv`, or
  `tools::package_dependencies("pkg", recursive = TRUE)` for the exact set.
- Anything Claude installs mid-session is lost; anything here is cached.

### Already in tidyverse deps (don't list)

Verified against `tools::package_dependencies("tidyverse", recursive = TRUE)`:
same as the r-universe list of 98, plus `modelr`. Minus base/recommended pkgs.

Core: dplyr tidyr purrr readr stringr forcats tibble ggplot2 lubridate,
readxl haven, rvest xml2 httr jsonlite curl, DBI dbplyr, vroom, glue cli rlang
vctrs magrittr withr fs ps callr stringi scales hms, data.table (via dtplyr),
knitr rmarkdown, digest R6 memoise yaml.

### Installed on top (the `pkgs` list in R-setup.sh)

| pkg | why |
|---|---|
| devtools | brings usethis, roxygen2, pkgload, testthat, remotes, waldo; `load_all`/`document`/`check` |
| testthat | explicit, because it's the tests default |
| lintr, styler | lint / format |
| here | project-relative paths |
| janitor | `clean_names`, `tabyl` |
| skimr | quick data summaries |
| tictoc | tiny timing, 0 deps |
| httr2 | web API calls (httr is superseded) |
| writexl | write xlsx, 0 deps (readxl is in tidyverse) |
| duckdb | local SQL on csv/parquet, 1 dep; replaces arrow for parquet |

### Maybe (add per project, not by default)

- **Quarto CLI** (not an R pkg; ~150 MB download): add if sessions render sites
- survey, srvyr: survey weighting work
- renv: if a repo uses it
- openxlsx2: xlsx formatting beyond writexl
- bench, lobstr: profiling
- reticulate, igraph (libxml2/glpk), sf (GDAL/GEOS/PROJ: heavy), qs2 (cmake)
- box, config, logger

### No

- **arrow**: large download, not needed for small data; duckdb reads parquet
- targets (32 deps), mirai/crew, ellmer/mcptools: unused by default
- assertthat, zeallot, wrapr: Claude rarely reaches for them
  (`stopifnot` / `cli::cli_abort`)
- RSQLite, odbc/ROracle: DBs unreachable
- Rcpp, RcppParallel, S7, pak, digest (already installed anyway)
- Non-CRAN: polars-r, tidypolars

### Non-R

- duckdb-cli: single binary from GitHub releases; add to the script if wanted
  (the R duckdb package covers most uses)

## CLAUDE.md

Idea: ping every 2h if ultra effort?
