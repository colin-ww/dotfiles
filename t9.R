source("checks.R")
Sys.setenv(NO_PROXY="127.0.0.1", no_proxy="127.0.0.1")
d <- tempfile(); dir.create(d); setwd(d); system2("git", "init -q", stdout=FALSE); system2("git", c("remote","add","origin","http://127.0.0.1:8766/g/p.git"))
t0 <- Sys.time(); check_gitlab(timeout = 2); cat("took", format(round(Sys.time()-t0,1)), "\n")
d <- tempfile(); dir.create(d); setwd(d); cat("no repo:"); print(check_gitlab()); 
system2("git", "init -q", stdout=FALSE); cat("repo, no remote:"); print(check_gitlab())
