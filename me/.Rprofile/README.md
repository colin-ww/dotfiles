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

Startup order (✅ tested: `.Renviron` is read *before* `.Rprofile`, so the profile can already see env vars):
1. `Renviron.site`, `Rprofile.site` (install-wide, admin)
2. `.Renviron` (user/project env vars)
3. `.Rprofile` (user/project code)
4. `.First()` if defined, then packages in `R_DEFAULT_PACKAGES`

**Q: runs when? every time?** Every R start: RStudio, terminal `R`, `Rscript`, `quarto render`, Kubeflow/cron jobs. That's why "looks only" + `interactive()` guard matter.

**Q: wd? not per project?** Which file is read depends on the **working directory at startup** ✅:
- start in a folder with `.Rprofile` → that one is used, `~/.Rprofile` is **not** (tested: `zz_user` stayed unset)
- start anywhere else (e.g. `~`, a folder without one) → `~/.Rprofile`
- RStudio: wd at startup = project folder if you opened a project, else home (or whatever *Default working directory* says in Global Options)
- `Rscript ../script.R` from inside the folder → still that folder's `.Rprofile` (wd counts, not where the script lives)
- override: env var `R_PROFILE_USER=/path/file` (replaces both); skip all: `R --no-init-file` / `--vanilla`

**Q: other things I should know?**
- the profile runs **before** any package is loaded: `library(x)` there is a startup cost + hidden dependency (see below)
- a package's own `.onLoad` may set options too; most only set them `if (is.null(getOption(...)))`, so yours win. Not guaranteed
- objects created at top level land in the **global env** (visible in `ls()` if not dot-named, and `rm(list = ls())` deletes them). Wrap in `local({ ... })` to keep it clean; for functions you want to survive, `attach()` them (Option 2 does this: `tbl_cols`)
- RStudio *Restart R* re-runs it; `source("~/.Rprofile")` re-runs it by hand

**Q: if errors?** ✅ tested, and it depends *how* R was started:
- **interactive** (RStudio console, terminal `R`): prints `Error: ...`, **skips the rest of that file**, session still starts, half-configured. Easy to miss, it scrolls by
- **non-interactive** (`Rscript`, `R -f`, `quarto render`, Kubeflow, cron): `Error: ... Execution halted`, **the whole job dies before your script starts**

→ so one bad line in `.Rprofile` can kill a nightly job on another machine. That's the real reason to be careful.

**Q: wrap chunks in `tryCatch`?** Yes, but only the *fragile* ones, not everything:
- plain `options(foo = 1)`: can't fail, no wrap
- anything touching package internals (Option 2), files, network, `system2()` (GitLab check), or a package that might not be installed: wrap ✅ (tested: with `tryCatch` the failed chunk prints one message and the *later lines still run*)
- put the fragile chunks **last**, plain options first
- or guard with `if (interactive())` so jobs never run them (cheapest, do both for UI things)

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

#### Option 2: your picks (hack, tested ✅)

Picked in the PR comment:

| item | status |
|---|---|
| TRUE/FALSE colours | ✅ in: `TRUE` green, `FALSE` yellow (NA stays red, so all 3 states differ) |
| `0` in another colour, not dim | ✅ in: magenta (change `col_zero`) |
| int vs dbl colour | ❌ dropped (agree: ints are everywhere, colour only works when rare; the `<int>`/`<dbl>` header already tells) |
| shorter `# A tibble: 3 x 4` line | ✅ in: `# tbl: 3x4` (change `tbl_sum_short`) |
| footer link to column names | ✅ in: shows when ncol >= 10 **or** columns didn't fit. ⚠️ click not testable here |

Note on "shorten": I read it as "make the `# A tibble: 3 x 4` header shorter". If you meant something else (drop the line? shorten the `# i 16 more variables:` footer?) say so.

##### How the link works
- footer gets one extra line: `# ℹ column names: tbl_cols()`, where `tbl_cols()` is a cli `{.run}` link
- in RStudio that's a clickable link that runs `tbl_cols()` in the console ✅ (cli emits the RStudio/`x-r-run:` link, tested the escape code; ⚠️ not clicked)
- where links aren't supported (plain terminal, Quarto) it falls back to showing `tbl_cols()` as code, which you can type ✅ tested
- the link can't know the tibble's *variable name* (print methods only see the object), so it runs `tbl_cols()` = **names of the last tibble that showed the link**, not literally `colnames(my_df)`. Click soon after printing; a later tibble overwrites it
- `tbl_cols()` lives in an attached env (`rprofile_tools` in `search()`), so `rm(list = ls())` doesn't remove it ✅ tested

##### How it works (so you can judge the risk)
- `pillar` has no public API for "colour my logicals"
- registering an S3 method the normal way does **not** work for `pillar_shaft`: pillar calls it from inside its own namespace, where R finds pillar's own `pillar_shaft.logical` first. (tested, tried the clean way first, silently ignored)
- so this *replaces two functions inside the pillar namespace* (`assignInNamespace`) when pillar loads
- header + footer use normal S3 registration for `tbl_df` (supported way, works because pillar has no `*.tbl_df` function of its own)
- it's a hack: could break on a pillar update
- mitigation: each part wrapped in `tryCatch`, if pillar/tibble internals changed → one message at startup, stock printing ✅ (tested by sabotaging both hooks)
- only touches printing, no computation
- skips classed numerics (Date, difftime, `pillar::num()` etc): they keep their own formatting
- `grouped_df` still shows `# Groups: ...` under the short header ✅

Colours are `cli::col_*`: swap them. Yellow is hard to read on a white RStudio theme, ⚠️ check yours (try `cli::col_br_yellow` / `cli::col_cyan` / `cli::col_br_green`).

```r
local({
  col_true  <- cli::col_green
  col_false <- cli::col_yellow
  col_zero  <- cli::col_magenta
  link_min_cols <- 10   # footer link when >= this many columns (or when columns don't fit)

  # last printed tibble's column names, behind the clickable footer link
  last_names <- character()
  tbl_cols <- function() last_names
  attach(list(tbl_cols = tbl_cols), name = "rprofile_tools", warn.conflicts = FALSE)

  patch_pillar <- function(...) {
    tryCatch({
      ns <- asNamespace("pillar")
      pillar_shaft_numeric <- get("pillar_shaft.numeric", envir = ns)

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
        out[zero] <- col_zero(cli::ansi_strip(out[zero]))
        out
      }

      footer_tbl <- function(x, setup, ...) {
        out <- NextMethod()
        if (ncol(x) >= link_min_cols || setup$extra_cols_total > 0) {
          last_names <<- names(x)
          out <- c(out, pillar::style_subtle(cli::format_inline("# {cli::symbol$info} column names: {.run tbl_cols()}")))
        }
        out
      }

      utils::assignInNamespace("pillar_shaft.logical", shaft_lgl, ns = "pillar")
      utils::assignInNamespace("pillar_shaft.numeric", shaft_num, ns = "pillar")
      registerS3method("format", "colour_num_shaft", format_num)
      registerS3method("tbl_format_footer", "tbl_df", footer_tbl, envir = ns)
    }, error = function(e) message("tibble colour patch skipped: ", conditionMessage(e)))
  }

  patch_tibble <- function(...) {
    tryCatch({
      tbl_sum_short <- function(x, ...) c(tbl = paste0(nrow(x), "x", ncol(x)))
      registerS3method("tbl_sum", "tbl_df", tbl_sum_short, envir = asNamespace("pillar"))
    }, error = function(e) message("tibble header patch skipped: ", conditionMessage(e)))
  }

  setHook(packageEvent("pillar", "onLoad"), patch_pillar)
  setHook(packageEvent("tibble", "onLoad"), patch_tibble)
})
```

Example ✅ (colours stripped):
```
# tbl: 3x10
     V1    V2    V3    V4    V5    V6    V7    V8
  <int> <int> <int> <int> <int> <int> <int> <int>
1     1     4     7    10    13    16    19    22
# ℹ 2 more variables: V9 <int>, V10 <int>
# ℹ column names: `tbl_cols()`
```

Notes
- ✅ tested: loaded via `R_PROFILE_USER`, with `library(tibble)` and `library(dplyr)`, narrow width (column truncation), NA values, sci-notation doubles, negative numbers, `group_by()` output, 10-col and 20-col tibbles
- ⚠️ not testable here: real RStudio console / RStudio Server. RStudio does render ANSI colours and cli's links, so should work. (Not in `View()`, that's a different viewer.)
- ⚠️ the sandbox forced colours via `options(cli.num_colors = 256)`. In RStudio cli auto-detects. If you see no colour: `cli::num_ansi_colors()` should be > 1. If the footer shows plain `tbl_cols()` in RStudio: `cli::ansi_hyperlink_types()$run` should be `TRUE`
- not in Quarto/R Markdown output, colour is off there by design (cli detects non-tty)
- nested-style quirk: pillar already embeds colour codes in numbers (red neg, dim exponent). For zeros I strip codes and restyle (so a `0` is one clean magenta, even in sci-notation columns). ⚠️ eyeball it on screen
- the footer link shows even when all columns fit if ncol >= 10; change `link_min_cols`

##### Which would I always want? (my take, before your picks)
- **TRUE/FALSE colours**: yes, the only one I'd call "always"
- **coloured zeros**: good for sparse/count data, mildly noisy where 0 is a real category (flags, weights). Magenta is louder than dim: if it shouts too much, try `cli::col_silver`/`cli::style_dim` (back to "dim")
- **short header + link**: pure convenience, low risk
- **int/dbl colours**: dropped, see table

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

**Picked in the PR comment. Run it on-demand, not at startup** (my recommendation): `check_gitlab()` when you sit down to push. A network call on every R start is exactly the "slow & networked at startup" thing from the top of this file; with a 5 s timeout worst case is a 5 s stall per RStudio restart. If you still want it automatic, add `check_gitlab()` inside the `.First` above (interactive only).

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
- **`options(Ncpus = 2)`**, see the Ncpus box below
- **`options(menu.graphics = FALSE)`**: text menus instead of popup dialogs on package-install prompts
- **`options(warn = 1)`**: print warnings immediately instead of at the end of a long run. Debatable but I like it for interactive
- **`options(rlang_backtrace_on_error = "branch")`**: see the backtrace box below

##### Picked: rlang backtrace = "branch" ✅ tested

What it does: for errors raised through rlang (all of tidyverse: dplyr, tidyr, purrr, readr, ...), print the call chain *right away* instead of only a hint.

Same error, interactive R:

```
# default                                       # "branch"
Error in `mutate()`:                            Error in `mutate()`:
ℹ In argument: `z = nope + 1`.                  ℹ In argument: `z = nope + 1`.
Caused by error:                                Caused by error:
! object 'nope' not found                       ! object 'nope' not found
Run `rlang::last_trace()` to see                Backtrace:
where the error occurred.                        1. global foo(data.frame(a = 1))
                                                 2. global bar(d)
                                                 4. dplyr:::mutate.data.frame(d, z = nope + 1)
                                                 5. dplyr:::mutate_cols(...)
                                                 ...
```

- "branch" = only the path from top-level call to the error (no sibling noise), the readable middle option; other values: `"none"`, `"reminder"` (default when interactive), `"full"`
- only affects *rlang* errors; base `stop()` errors are unchanged
- cost: more lines on every error. If it's too chatty, back to the default; `rlang::last_trace()` still works either way
- non-interactive (`Rscript`) already prints a backtrace by default

```r
options(rlang_backtrace_on_error = "branch")
```

##### Ncpus: what does it affect? ✅ checked

**Q: "affects fcts from base and or other pkgs?"** Short answer: it's a *parallelism default*, mostly for installing. Not a global "use more cores" switch for your analysis code.

- **base R / utils**: `install.packages()` and `update.packages()` use it to compile/install several *source* packages in parallel. **Binary installs** (PPM / Artifactory binaries) aren't compiled, so little gain there; it helps when something builds from source
- **other packages**: I grepped every function of the ~530 installed pkgs in the sandbox for `getOption("Ncpus")`. Hits: `pak` (number of download/install workers), `testthat` (default number of parallel test processes), `ranger` (default threads), `zip` (threads), `RcppArmadillo` (on load), plus `tools`/`utils` internals. So a few real packages *do* read it as their default thread count
- **not** affected: `parallel::mclapply()`, `future`, `furrr`, `data.table`, `arrow`, `duckdb`... those use `mc.cores`, `future::plan()`, their own threads setting, etc.
- results don't change, only speed. But it's a "how many cores do I grab" setting, so see below

⚠️ on k8s: `parallel::detectCores()` can report the whole *node* rather than your pod's CPU limit, so `detectCores() - 1` may oversubscribe the pod. `parallelly::availableCores()` respects cgroup limits (here it equals `detectCores()`, 4 = 4, so I **couldn't reproduce the mismatch**, ⚠️ test it in the Zone). Safe default: a small hardcoded number.

```r
options(Ncpus = 2)
```

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

Done with your PR comment: tibble picks, GitLab check, rlang backtrace, Ncpus answer.

1. **"a tibble line shorten?"**: I read it as the `# A tibble: 3 x 4` header → `# tbl: 3x4`. Right? Alternatives: `# 3x4`, `# tbl 3x4`, or no header line at all
2. **Zero colour**: magenta OK on your theme? (⚠️ can't see it)
3. **Footer link**: runs `tbl_cols()` (names of the *last* tibble that showed the link), because a print method can't know your object's name. OK, or do you prefer a plain-text footer like `# names(): a, b, c, ...`?
4. **Not picked, so parked** (not deleted): package check, `warn = 1`, partial-match warnings, `timeout`, `menu.graphics`, ... say if any should move up
5. **Should I assemble the picks into one ready-to-copy `Rprofile.R`** in this folder? (tibble patch + `check_gitlab()` + the two `options()`) Not done yet, bc the README said "copy paste"
6. **The Zone**: R version? (code assumes >= 4.2 for the `_` pipe placeholder, can drop that for 4.1)
