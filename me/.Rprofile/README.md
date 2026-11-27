# .Rprofile

(context: 95% of time I use RStudio, occasionally terminal R console or RScript)

Tested with R 4.6.1 / pillar 1.11.1 / cli 3.6.6 (cloud sandbox, not RStudio, not The Zone).  
Code blocks below need **R >= 4.2** (native pipe `_` placeholder). 

**Legend:** ✅ tested here · ⚠️ not testable here, try it in RStudio

<br>


## What is .Rprofile

- plain R script, runs once at R startup, before anything else
- **only ONE is read**, first hit wins:
  1. `./.Rprofile` (project dir), else
  2. `~/.Rprofile` (user)
  - gotcha: a project `.Rprofile` (incl. the one `renv` creates) *silently hides* the user one
  - fix: put `source("~/.Rprofile")` as first line of the project one
- siblings (don't mix them up):

| file | for | note |
|---|---|---|
| `~/.Rprofile` | your R session UI/convenience | this README |
| `./.Rprofile` | project-specific setup | `renv/activate.R`, project options |
| `.Renviron` | env vars (`GITLAB_PAT`, proxy, `R_LIBS_USER`, `TZ`) | **secrets go here, never .Rprofile**, never in a repo |
| `Rprofile.site` | whole install (all users) | in The Zone probably image/admin owned, not ours (⚠️ guess) |
| `rstudio-prefs.json` | RStudio UI settings | separate dotfile |

<br>


#### Background

code in .rprofile runs anytime you start r or run r (rstudio/terminal/rscript)

wd? not per project?

other things should know?

if errors?

therefore wrap chunks in trycatch?!? not unless complex?

<br>


#### What to think about
(ie what should go in .Rprofile and what should stay far away)

**Rule of thumb: .Rprofile may change how R *looks and feels* for me. It must never change what code *computes*.**

If a script gives a different result because of my .Rprofile, it's broken for my team, for CI, for Kubeflow jobs and for future-me.

##### Goes in ✅
- print/display: tibble options, colours, `width`, `max.print`
- interactive-only nice-to-haves: startup checks, `options(menu.graphics = FALSE)`
- machine/site plumbing: `options(repos = ...)` (Artifactory mirror), `options(Ncpus = ...)`, `options(timeout = ...)`
- dev-time strictness that only *warns*: `warnPartialMatchDollar` etc.
- tiny helper functions, *if* they're also fine to lose (they live in the global env!)

##### Stays out ❌
- `library()` / `require()` of anything
  - slows every startup (esp. on the filers), and makes scripts "work on my machine" bc a pkg is secretly attached
  - exception: none. Use `pkg::fn()` or put `library()` in the script
- anything that alters results: `options(digits=)`, `scipen`, `stringsAsFactors`, `na.action`, `contrasts`, `set.seed()`, `Sys.setlocale()`, `Sys.setenv(TZ=)`
  - `scipen`/`digits` are the sneaky ones: only change *printing* but also change `as.character()`/`paste()` output (e.g. `paste(1e5)`)
- secrets / passwords / PATs → `.Renviron` (not committed) or the git credential helper
- anything slow or networked at startup (hits to GitLab, `available.packages()`, CRAN) → on-demand function instead
- `rm(list = ls())` etc.
- `install.packages()` / auto-update. Air-gapped + mirror → surprise installs are a bad time

##### Habits
- **guard** UI stuff with `if (interactive())` so `Rscript`, Kubeflow, `quarto render`, CI never see it
- **wrap** anything fragile in `tryCatch()`: an error in .Rprofile = R starts half-configured and the message scrolls by (tested: Option 2 below falls back to stock printing + one message)
- keep it **fast**: check with `system.time(source("~/.Rprofile"))`
- **reproducibility test:** run a script with `R --no-init-file` / `Rscript --no-init-file x.R`. If output differs, something in .Rprofile leaked in
- dotfiles repo is GitLab/GitHub → no person-level data, no paths with names, no tokens

<br>


## Tibble print options

#### What's already coloured by default ✅ (pillar 1.11.1, tested)

| thing | default |
|---|---|
| negative numbers | red (`pillar.neg`) |
| `NA` (any type) | red |
| `NA` string vs `"NA"` string | `NA` red, `"NA"` quoted |
| empty string / ambiguous strings | shown as `""`, quotes dim |
| col type row `<int> <dbl> <chr>` | dim italic |
| insignificant digits / sci-notation exponent | dim |
| big numbers | underlined thousands (`1 234 567`) |
| row numbers, `# A tibble` header | grey |

#### What's NOT coloured by default ✅ (tested)
- `TRUE` / `FALSE` → plain text
- `0` → plain
- integer vs double → same colour (only the dim `<int>`/`<dbl>` header differs)

#### Option 1: built-in options only (supported, zero risk)

These are real, documented pillar/tibble options (checked they exist in pillar 1.11.1).  
None touch TRUE/FALSE/0/int colours, only layout + the neg/subtle toggles.

```r
if (interactive()) {
  options(
    pillar.sigfig          = 4,    # default 3. 4 sig digits, 1.235 not 1.23
    pillar.min_title_chars = 12,   # don't squash long column names to "a~"
    pillar.min_chars       = 8,    # chr cols: show at least 8 chars before "…"
    tibble.print_max       = 20,   # rows printed if > print_min rows (default 20)
    tibble.print_min       = 10,   # rows printed otherwise (default 10)
    tibble.width           = Inf   # use full console width (cols wrap into footer otherwise)
    # pillar.neg    = FALSE,       # turn red negatives OFF
    # pillar.subtle = FALSE,       # turn dim/grey OFF (more contrast on dark themes?)
    # pillar.bold   = TRUE         # bold column headers
  )
}
```

#### Option 2: add TRUE/FALSE colours, dim zeros, blue integers (hack, tested ✅)

What you get:
- `TRUE` green, `FALSE` yellow (NA stays red: so all three logical states look different)
- `0` dim/grey (zeros fade into the background, non-zeros pop)
- integers blue, doubles default → int vs dbl visible *per value*, not only in the header
- works for tibbles / `dplyr` output, i.e. anything printed through pillar's column formatting. **Not** `glimpse()` (tested: it formats its own values, no colours)

How it works (so you can judge the risk):
- `pillar` has no public API for "colour my logicals"
- registering an S3 method the normal way does **not** work: pillar calls `pillar_shaft()` from inside its own namespace, where R finds pillar's own `pillar_shaft.logical` first. (tested, tried the clean way first, silently ignored)
- so this *replaces two functions inside the pillar namespace* (`assignInNamespace`) when pillar loads
- it's a hack: could break on a pillar update
- mitigation: wrapped in `tryCatch`, if pillar internals changed → one message at startup, stock printing ✅ (tested by sabotaging it)
- only touches printing, no computation
- skips classed numerics (Date, difftime, `pillar::num()` etc): they keep their own formatting

Colours are `cli::col_*`: swap them. Yellow is hard to read on a white RStudio theme, ⚠️ check yours (try `cli::col_magenta` / `cli::col_cyan` / `cli::col_br_green`).

```r
local({
  patch_pillar <- function(...) {
    tryCatch({
      ns <- asNamespace("pillar")
      pillar_shaft_numeric <- get("pillar_shaft.numeric", envir = ns)

      col_true  <- cli::col_green
      col_false <- cli::col_yellow
      col_int   <- cli::col_blue

      shaft_lgl <- function(x, ...) {
        out <- rep(NA_character_, length(x))
        out[x]  <- col_true("TRUE")
        out[!x] <- col_false("FALSE")
        pillar::new_pillar_shaft_simple(out, width = 5, align = "left")
      }

      shaft_num <- function(x, ...) {
        shaft <- pillar_shaft_numeric(x, ...)
        if (is.object(x)) return(shaft)
        attr(shaft, "colour_x") <- x
        class(shaft) <- c("colour_num_shaft", class(shaft))
        shaft
      }

      format_num <- function(x, width, ...) {
        out <- NextMethod()
        v <- attr(x, "colour_x")
        zero <- !is.na(v) & v == 0
        out[zero] <- pillar::style_subtle(cli::ansi_strip(out[zero]))
        if (is.integer(v)) out[!zero] <- col_int(out[!zero])
        out
      }

      utils::assignInNamespace("pillar_shaft.logical", shaft_lgl, ns = "pillar")
      utils::assignInNamespace("pillar_shaft.numeric", shaft_num, ns = "pillar")
      registerS3method("format", "colour_num_shaft", format_num)
    }, error = function(e) message("tibble colour patch skipped: ", conditionMessage(e)))
  }
  setHook(packageEvent("pillar", "onLoad"), patch_pillar)
})
```

Notes
- ✅ tested: loaded via `R_PROFILE_USER`, with `library(tibble)` and `library(dplyr)`, narrow width (column truncation), NA ints, sci-notation doubles, negative ints (red inside blue nests fine)
- ⚠️ not testable here: real RStudio console / RStudio Server. RStudio does render ANSI colours, so should work. (Not in `View()`, that's a different viewer.)
- ⚠️ the sandbox forced colours via `options(cli.num_colors = 256)`. In RStudio cli auto-detects. If you see no colour: `cli::num_ansi_colors()` should be > 1
- not in Quarto/R Markdown output, colour is off there by design (cli detects non-tty)
- nested-style quirk: pillar already embeds colour codes in numbers (red neg, dim exponent). For zeros I strip codes and restyle; for ints I wrap, which cli nests correctly. Looked right in the escape codes, ⚠️ eyeball it on screen

#### Which of these would I actually always want?

My take (challenge it!):
- **TRUE/FALSE colours**: yes, the only one I'd call "always". Logical cols are scanned for pattern a lot (filters, flags) and the default is the plainest thing on screen
- **dim zeros**: good for sparse / count data, mildly noisy for survey weights/flags where 0 is a real category. Nice, not essential
- **blue integers**: I'd be wary. Colour only carries meaning if it's rare. Ints are super common (counts, ids, years) so most of the screen goes blue and the signal is lost. The `<int>` header already says it. If your point is catching "this should have been int but is dbl" (Parquet schema hygiene!), a **`pillar.subtle`-style** hint on the *double* might help more, but doubles are 80% of columns, so same problem. → Probably start with Option 2 minus `col_int` (delete the `if (is.integer(v))` line) and see if you miss it.

#### Non-tibble printing (data.frame, vectors)? ✅ tested

You're right, not possible *cleanly*:
- `print(data.frame)` → base `format.data.frame()`, no pillar involved → no colour
- `print(c(TRUE, FALSE))` → plain base vector printing → no colour. No S3 hook, no option
- `data.table` has its own printer (header only)

Workarounds:
- **a)** (recommended) just work in tibbles, `as_tibble()` is one call, and you already use the tidyverse
- **b)** `dplyr::glimpse()` for wide data: no help for colours ✅ (tested, plain values apart from red `NA`)
- **c)** hack: re-register `print.data.frame` to go through `as_tibble()` ✅ it works:

  ```r
  registerS3method("print", "data.frame", function(x, ...) {
    print(tibble::as_tibble(x, rownames = if (.row_names_info(x) > 0) "row.names" else NULL), ...)
    invisible(x)
  })
  ```
  
  but **I'd not do this**:
  - prints a `# A tibble` header on every data.frame
  - truncates row names (`Mazda RX4 W~`)
  - changes `print()` for every package/test that prints data.frames (testthat snapshots, knitr, ...), the "looks only" rule from above gets blurry
  - the global-env/-namespace-patch count goes up
- **d)** is `options(...)` for base printing? No such option

→ **Decision for you:** a) or c)? (I'd say a)

<br>


## Check packages are installed

Question was: *reads list from? description.txt? somewhere else if not a pkg? required_pkgs.txt?*

**Recommendation**: look in this order, first one found wins

1. `DESCRIPTION` (`Depends` + `Imports`), the standard place; works for R packages **and** for plain projects (`usethis::use_description()` makes one). One list, no drift, and `pak`/`renv::install()`/`devtools::install_deps()` can already install from it
2. `required_pkgs.txt` (one pkg per line, `#` comments ok): fallback for plain script folders
3. `renv.lock`: **skip**, `renv` already checks on activate; `renv::status()` is its job

Design choices:
- **never auto-installs**: air-gapped + Artifactory, and surprise installs mutate the env. Prints the `install.packages()` line to copy
- doesn't load packages: `system.file(package = p)` just looks for the folder (cheap; a few ms even on slow disks, hmm, ⚠️ filers: time it there)
- reads project dir only (`.`), so it's a no-op in `~` (no DESCRIPTION)
- doesn't check versions (`(>= 1.0)` is stripped). Easy to add, but `renv` does that better
- ignores `Suggests` (`fields = c("Depends","Imports","Suggests")` to include)
- `cli` is only loaded if something's missing

✅ tested: DESCRIPTION with multi-line `Imports`/version constraints/`R (>= 4.1)`; `required_pkgs.txt` with comments + blank lines + trailing comments; nothing missing; no file at all; and startup via `.First` in interactive `R`

```r
check_pkgs <- function(path = ".", fields = c("Depends", "Imports")) {
  desc <- file.path(path, "DESCRIPTION")
  txt  <- file.path(path, "required_pkgs.txt")

  pkgs <- if (file.exists(desc)) {
    read.dcf(desc, fields = fields) |>
      as.vector() |>
      strsplit(",") |>
      unlist() |>
      sub("\\(.*\\)", "", x = _) |>
      trimws()
  } else if (file.exists(txt)) {
    readLines(txt) |>
      sub("#.*", "", x = _) |>
      trimws()
  } else {
    return(invisible(NULL))
  }
  pkgs    <- setdiff(pkgs[!is.na(pkgs) & nzchar(pkgs)], "R")
  missing <- pkgs[!vapply(pkgs, \(p) nzchar(system.file(package = p)), logical(1))]

  if (length(missing)) {
    cli::cli_alert_warning("{length(missing)} of {length(pkgs)} package{?s} not installed: {.pkg {missing}}")
    cli::cli_text("{.code install.packages(c({paste0('\"', missing, '\"', collapse = ', ')}))}")
  }
  invisible(missing)
}

if (interactive()) {
  .First <- function() check_pkgs()
}
```

Example output ✅:
```
! 1 of 2 packages not installed: zzz_missing
`install.packages(c("zzz_missing"))`
```

⚠️ **Untested:** that the message shows up in the RStudio console when called from `.First` (it should). If it gets swallowed:

```r
setHook("rstudio.sessionInit", function(newSession) check_pkgs(), "append")
```

(`.First` defined here lives in the global env → shows in `ls(all.names = TRUE)`. Harmless; but a project `.Rprofile` that defines its own `.First` will override it.)

<br>


## Check Gitlab is connected/password works

**Idea:** instead of calling the GitLab API (needs the URL + a token + a client pkg), ask **git itself**: `git ls-remote origin HEAD`.

Why:
- tests exactly the thing that matters (can *git* talk to the remote with my stored credentials), whatever helper you use (store/cache/manager/SSH key)
- no URL hardcoded in the dotfiles (it reads the project's own `origin`) → also nothing StatCan-specific lands in the dotfiles repo
- no packages needed
- read-only, tiny

Safeguards:
- `GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS=true` → fails instead of hanging on a password prompt (RStudio otherwise pops its askpass dialog on every startup)
- `GIT_SSH_COMMAND` with `BatchMode=yes` → same for ssh remotes
- hard `timeout = 5` s → dead VPN can't freeze startup for a minute

It sorts the failure into something actionable:

| what happened | message |
|---|---|
| OK / reachable but empty repo | ✅ OK |
| timeout | timed out (VPN/proxy/network?) |
| `SSL` / `certificate` in msg | TLS certificate problem (corporate CA?) |
| DNS / refused / unreachable | can't reach server (VPN/proxy/network?) |
| 401 / 403 / auth failed / no creds | credentials missing/expired/rejected (new PAT?) |
| anything else | the raw git message |
| no `origin` / not a git repo | silent no-op |

✅ **tested against:** local bare repo (OK), empty repo (OK), nonexistent repo (raw message), HTTP server returning 401 (credentials), connection refused + DNS failure (network), a server that accepts and never answers (timeout after 2 s: `took 2.1 secs`), non-git dir and git dir w/o remote (silent)

⚠️ **NOT tested:** real GitLab, the TLS branch (no way to fake a cert error here), real PAT expiry. Plausible-but-unverified: StatCan's GitLab sits behind the corporate proxy/CA, so that branch may be the one you hit most.

**Run it on-demand, not at startup** (my recommendation): `check_gitlab()` when you sit down to push. A network call on every R start is exactly the "slow & networked at startup" thing from the top of this file; with a 5 s timeout worst case is a 5 s stall per RStudio restart. If you still want it automatic, add `check_gitlab()` inside the `.First` above (interactive only).

```r
check_gitlab <- function(remote = "origin", timeout = 5) {
  if (!remote %in% suppressWarnings(system2("git", "remote", stdout = TRUE, stderr = FALSE))) return(invisible(NA))  # not a git repo / no such remote
  out <- suppressWarnings(system2(
    "git", c("ls-remote", "--exit-code", remote, "HEAD"),
    stdout = TRUE, stderr = TRUE, timeout = timeout,
    env = c("GIT_TERMINAL_PROMPT=0", "GIT_ASKPASS=true", "GIT_SSH_COMMAND='ssh -o BatchMode=yes'")
  ))
  status <- attr(out, "status"); if (is.null(status)) status <- 0L
  msg <- paste(out, collapse = " ")

  problem <- if (status %in% c(0L, 2L)) NULL            # 2 = reachable, just no HEAD yet
    else if (status == 124L)                                      "timed out (VPN/proxy/network?)"
    else if (grepl("SSL|certificate", msg))                       "TLS certificate problem (corporate CA?)"
    else if (grepl("resolve host|Failed to connect|Connection (refused|timed out)|unable to access", msg) &&
             !grepl("401|403|denied|Authentication", msg))        "can't reach server (VPN/proxy/network?)"
    else if (grepl("Authentication failed|could not read (Username|Password)|Access denied|401|403", msg))
                                                                  "credentials missing/expired/rejected (new PAT?)"
    else                                                          paste("git said:", msg)

  if (is.null(problem)) cli::cli_alert_success("GitLab remote {.val {remote}} OK")
  else cli::cli_alert_danger("GitLab remote {.val {remote}}: {problem}")
  invisible(is.null(problem))
}
```

Example output ✅ (timeout case):
```
x GitLab remote "origin": timed out (VPN/proxy/network?)
```

Possible next step (not written, bc can't test without a GitLab): **PAT expiry warning**. GitLab has `GET /api/v4/personal_access_tokens/self` → returns `expires_at`; call it with `GITLAB_PAT` from `.Renviron`, warn if < 14 days. Needs the GitLab host + a http client. Say if you want it.

<br>


## Other sections could consider

My picks, roughly by value/risk. All are "looks & feel" or "warns only", none change results.

##### Quality-of-life
- ✅ **`options(repos = c(CRAN = "<artifactory url>"))`** if not already set image-wide. Check first: `getOption("repos")`. (the URL is StatCan-internal → keep it out of the dotfiles repo: set it in `Rprofile.site`/`.Renviron`, or read it from an env var)
- **`options(timeout = 600)`**: default 60 s kills big downloads over slow links
- **`options(Ncpus = parallel::detectCores() - 1)`** for faster `install.packages()`. (⚠️ k8s pods: `detectCores()` reports the *node*, not your CPU limit. Hardcode a number, or `parallelly::availableCores()`)
- **`options(menu.graphics = FALSE)`**: text menus instead of popup dialogs on package-install prompts
- **`options(warn = 1)`**: print warnings immediately instead of at the end of a long run. Debatable but I like it for interactive
- **`options(rlang_backtrace_on_error = "branch")`**: short backtrace on tidyverse errors

##### Strictness (warn only)
- `options(warnPartialMatchDollar = TRUE, warnPartialMatchArgs = TRUE, warnPartialMatchAttr = TRUE)`: warns on `df$na` accidentally matching `df$name`. Quiet if your code is clean, loud if *someone else's* package relies on it
- `options(warnPartialMatchDollar = TRUE)` alone is the least noisy

##### Maybe
- `.Last` to save history, or `options(history.size)` — RStudio already handles this
- `options(dplyr.summarise.inform = FALSE)`: hides the "`summarise()` has grouped output" message. Convenient, but that message has caught real grouping bugs. I'd leave it on
- `options(readr.show_col_types = FALSE)`: **I'd keep this ON**: given the CSV-vs-schema hygiene battles, the guessed col spec message is the feature
- `options(usethis.description = list(...))`: author fields for `use_description()` (name/email/ORCID). → `.Rprofile` OK, but it's person-level so mind the dotfiles repo's visibility
- `options(max.print = 500)`: stops a stray `print(big_df)` from flooding RStudio

##### No
- `options(stringsAsFactors = ...)`, `digits`, `scipen`, `set.seed`, `library(tidyverse)` — see top

<br>


## Open questions for you

1. **Option 2 colours**: do green/yellow/blue look OK on your RStudio theme? (⚠️ can't see it from here). Keep blue ints, or drop them?
2. **Non-tibble printing**: happy with "just use tibbles" (a), or do you want the `print.data.frame` hack (c)?
3. **GitLab check**: on-demand only, or also at startup? Want the PAT-expiry add-on (needs the GitLab host, which I didn't want to put in a public repo)?
4. **Should I assemble these into one ready-to-copy `Rprofile.R`** file in this repo (instead of copy-pasting out of the README)? I held back because the README said "R code to copy paste"
5. **The Zone**: what R version is it on? (the code assumes >= 4.2 for the `_` pipe placeholder; I can drop that if it's 4.1)
