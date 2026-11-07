# Which R packages do my repos use (ALL remote branches) that this machine
# doesn't have yet? Run it in a cloud session to find what R-setup.sh misses.
#
#   Rscript claude-code/cloud/scan-repo-deps.R ../sc-nts-frame ../rr-tests
#
# renv::dependencies() finds library()/require()/pkg::/box::use()/
# tar_option_set(packages =)/DESCRIPTION/Rmd+qmd chunks. Base + recommended
# pkgs are dropped. Output: 1 row per repo x missing pkg, with the top-level
# folders and branches using it, so you can tell "needed to run/test the code"
# from "a pkg I was trying out" (eg rr-tests/dplyr-backends).

suppressMessages(library(tidyverse))

git <- \(repo, ...) system2("git", c("-C", repo, ...), stdout = TRUE)

scan_ref <- \(repo, ref) {
  dir <- tempfile("scan-")
  dir.create(dir)
  system2("bash", c("-c", shQuote(sprintf("git -C %s archive %s | tar -x -C %s", repo, ref, dir))))
  renv::dependencies(dir, quiet = TRUE, progress = FALSE) |>
    as_tibble() |>
    transmute(repo = basename(repo), branch = str_remove(ref, "^origin/"),
              folder = str_extract(str_remove(Source, fixed(paste0(dir, "/"))), "^[^/]+"),
              pkg = Package)
}

skip <- c("R", rownames(installed.packages(priority = c("base", "recommended"))))
have <- rownames(installed.packages())
cran <- rownames(available.packages())

commandArgs(trailingOnly = TRUE) |>
  map(\(repo) {
    git(repo, "fetch", "-q", "origin", shQuote("+refs/heads/*:refs/remotes/origin/*"))
    git(repo, "branch", "-r", shQuote("--format=%(refname:short)")) |>
      setdiff(c("origin/HEAD", "origin")) |>
      map(\(ref) scan_ref(repo, ref)) |>
      list_rbind()
  }) |>
  list_rbind() |>
  filter(!pkg %in% c(skip, have)) |>
  summarise(on_cran = first(pkg %in% cran),
            folders = str_flatten(sort(unique(folder)), " "),
            branches = str_flatten(sort(unique(branch)), " "),
            .by = c(repo, pkg)) |>
  arrange(repo, !on_cran, pkg) |>
  knitr::kable(format = "pipe") |>
  print()
