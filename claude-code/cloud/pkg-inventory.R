# Which R pkgs does R-setup.sh install, and why? One csv row per pkg, alphabetical.
#   tidy-direct = tidyverse + its core/extended pkgs (what tidyverse itself imports)
#   oth-direct  = asked for in r-packages.txt, no other asked-for pkg needs it
#   both        = asked for in r-packages.txt AND a dependency of another asked-for pkg (eg data.table)
#   indirect    = only here because an asked-for pkg depends on it (any depth)
# Computed from CRAN metadata (Depends/Imports/LinkingTo = what install.packages()
# pulls in), so it doesn't matter what else happens to be installed. Base R left out.
# Then loads every pkg: exits 1 if one isn't installed or doesn't load (missing system lib).
# CI regenerates + commits r-packages-installed.csv when r-packages.txt changes.
#
#   Rscript claude-code/cloud/pkg-inventory.R [out.csv]

suppressMessages(library(tidyverse))

here <- commandArgs() |> str_subset("^--file=") |> str_remove("^--file=") |> dirname()
out <- c(commandArgs(trailingOnly = TRUE), file.path(here, "r-packages-installed.csv"))[1]  # arg or default

db <- available.packages()
deps_of <- \(pkgs, recursive = TRUE) {
  tools::package_dependencies(pkgs, db = db, which = c("Depends", "Imports", "LinkingTo"),
                              recursive = recursive)
}

listed <- scan(file.path(here, "r-packages.txt"), what = "", comment.char = "#", quiet = TRUE)
tidy <- c("tidyverse", deps_of("tidyverse", recursive = FALSE)[[1]])
asked <- union("tidyverse", listed)
needed <- deps_of(asked) |>
  imap(\(deps, pkg) setdiff(deps, pkg)) |>
  list_c() |>
  unique()

inventory <- tibble(package = union(asked, needed)) |>
  filter(package %in% rownames(db)) |>  # drops base R (stats, utils, ...): not on CRAN
  mutate(how = case_when(
    package %in% tidy ~ "tidy-direct",
    package %in% listed & package %in% needed ~ "both",
    package %in% listed ~ "oth-direct",
    .default = "indirect"
  )) |>
  arrange(str_to_lower(package))

write_csv(inventory, out)
cat(nrow(inventory), "pkgs ->", out, "\n")
print(count(inventory, how))

# DRY hint: listed pkgs that tidyverse brings anyway
if (length(dup <- intersect(listed, tidy))) cat("In r-packages.txt but already in tidyverse:", dup, "\n")

# After R-setup.sh, every pkg must be installed AND load. Loading is what
# catches a missing system lib ("cannot open shared object file", eg igraph
# without libglpk.so.40). Exit 1, so CI goes red.
problems <- inventory |>
  mutate(problem = map_chr(package, \(p) {
    tryCatch({ suppressMessages(loadNamespace(p)); NA_character_ }, error = conditionMessage)
  })) |>
  filter(!is.na(problem))
if (nrow(problems)) {
  cat("\nNOT INSTALLED OR DOESN'T LOAD:\n", paste0(" - ", problems$package, ": ", problems$problem, "\n"))
  quit(status = 1)
}
cat("All", nrow(inventory), "pkgs installed and load\n")
