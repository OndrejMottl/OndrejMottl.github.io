# Helpers for the "VS Code for R" pages. Sourced from an R chunk at the top of
# each page (the chunk's working directory is this folder).
#
# - show_file(): print a published config file in full, folded, with a
#   download link.
# - check_documented(): stop the render when a setting / extension in the
#   exported key list is not mentioned on the page (as `key` in backticks), so
#   the reference cannot silently fall behind the real configuration.

show_file <- function(path, lang = "json", label = NULL) {
  full_path <- file.path("files", path)
  if (!file.exists(full_path)) {
    stop("File not exported: ", full_path, ". Run export_vscode_profile.ps1.")
  }
  if (is.null(label)) {
    label <- path
  }
  body <- readLines(full_path, warn = FALSE, encoding = "UTF-8")
  # Four backticks: the files themselves may contain ``` (e.g. a snippet).
  cat(
    "",
    "<details>",
    paste0("<summary>Show the full file: <code>", label, "</code></summary>"),
    "",
    paste0("````", lang),
    body,
    "````",
    "",
    "</details>",
    "",
    paste0("[Download `", basename(path), "`](files/", path, "){download=\"", basename(path), "\"}"),
    "",
    sep = "\n"
  )
  invisible(full_path)
}

check_documented <- function(keys_file, page = knitr::current_input()) {
  keys <- readLines(file.path("_data", keys_file), warn = FALSE, encoding = "UTF-8")
  keys <- keys[nzchar(keys)]
  page_text <- paste(readLines(page, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  missing <- keys[!vapply(
    keys,
    function(k) grepl(paste0("`", k, "`"), page_text, fixed = TRUE),
    logical(1)
  )]
  if (length(missing) > 0) {
    stop(
      "Not documented on ", basename(page), " (", length(missing), "): ",
      paste(missing, collapse = ", ")
    )
  }
  invisible(TRUE)
}
