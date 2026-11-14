# Which R pkgs are installed, and why? One csv row per pkg, alphabetical.
#   direct   = asked for (tidyverse + r-packages.txt), nothing else needs it
#   indirect = only here because another asked-for pkg depends on it
#   both     = asked for AND a dependency of another asked-for pkg (eg data.table)
#   other    = neither (eg "recommended" pkgs that came with r-base, like MASS)
# Base R pkgs are left out.
#
#   Rscript claude-code/cloud/pkg-inventory.R [out.csv]     (run after R-setup.sh)

suppressMessages(library(tidyverse))

here <- commandArgs() |> str_subset("^--file=") |> str_remove("^--file=") |> dirname()
out <- commandArgs(trailingOnly = TRUE)[1] %||% "r-packages-installed.csv"

direct <- scan(file.path(here, "r-packages.txt"), what = "", comment.char = "#", quiet = TRUE) |>
  c("tidyverse") |>
  unique()

installed <- installed.packages() |>
  as_tibble() |>
  distinct(Package, .keep_all = TRUE)  # same pkg in 2 libs: first .libPaths() wins

# everything the direct pkgs pull in (Depends/Imports/LinkingTo, all levels),
# not counting a pkg as its own dependency
needed_by_direct <- tools::package_dependencies(
  direct, db = as.matrix(installed), which = c("Depends", "Imports", "LinkingTo"), recursive = TRUE
) |>
  imap(\(deps, pkg) setdiff(deps, pkg)) |>
  list_c() |>
  unique()

inventory <- installed |>
  filter(is.na(Priority) | Priority != "base") |>
  transmute(
    package = Package,
    version = Version,
    how = case_when(
      Package %in% direct & Package %in% needed_by_direct ~ "both",
      Package %in% direct ~ "direct",
      Package %in% needed_by_direct ~ "indirect",
      .default = "other"
    )
  ) |>
  arrange(str_to_lower(package))

write_csv(inventory, out)
cat(nrow(inventory), "pkgs ->", out, "\n")
print(count(inventory, how))

not_installed <- setdiff(direct, inventory$package)
if (length(not_installed)) cat("ASKED FOR BUT NOT INSTALLED:", not_installed, "\n")
