# >>> rig: enable the 'R' command >>>
# Remove the built-in 'r' -> Invoke-History alias so that 'R' starts R.
if (Test-Path Alias:\r) { Remove-Item Alias:\r -Force }
# <<< rig: enable the 'R' command <<<
