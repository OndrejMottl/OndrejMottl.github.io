# User .Rprofile. R reads it from R_USER (= OneDrive\Documents), so OneDrive
# shares it between machines: keep it machine-neutral (no user names, no
# paths that exist on only one machine; guard anything optional).

# VS Code: plots go to httpgd (vscode-R shows them in its viewer).
if (interactive() && Sys.getenv("TERM_PROGRAM") == "vscode") {
  if ("httpgd" %in% .packages(all.available = TRUE)) {
    options(vsc.rstudioapi = TRUE)
    options(vsc.use_httpgd = TRUE)
    options(vsc.plot = FALSE)
    options(device = function(...) {
      httpgd::hgd(silent = FALSE)
    })
  }
}

# Expose the session to coding assistants (MCP), when btw is installed for
# this R version (each R version has its own library).
if (interactive() && requireNamespace("btw", quietly = TRUE)) {
  btw::btw_mcp_session()
}

# radian: no automatic bracket matching or indentation.
options(radian.auto_match = FALSE)
options(radian.auto_indentation = FALSE)

local({
  # Pandoc bundled with RStudio, for rmarkdown outside RStudio.
  rstudio_pandoc <- "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools"
  if (dir.exists(rstudio_pandoc)) {
    Sys.setenv(RSTUDIO_PANDOC = rstudio_pandoc)
  }

  # Large temporary files on a second drive, where the machine has one.
  temp_dir <- "D:/Temp"
  if (dir.exists(temp_dir)) {
    Sys.setenv(TEMP = temp_dir, TMP = temp_dir)
  }

  # TinyTeX (LaTeX for PDF output), if installed and not already on PATH.
  tinytex_bin <- file.path(Sys.getenv("APPDATA"), "TinyTeX", "bin", "windows")
  path_entries <- normalizePath(
    strsplit(Sys.getenv("PATH"), ";", fixed = TRUE)[[1]],
    winslash = "/",
    mustWork = FALSE
  )
  if (
    dir.exists(tinytex_bin) &&
      !normalizePath(tinytex_bin, winslash = "/") %in% path_entries
  ) {
    Sys.setenv(PATH = paste(Sys.getenv("PATH"), tinytex_bin, sep = ";"))
  }
})
