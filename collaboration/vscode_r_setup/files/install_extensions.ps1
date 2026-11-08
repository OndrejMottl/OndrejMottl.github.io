#Requires -Version 7.0
<#
.SYNOPSIS
    Install the VS Code extensions from a list file into a VS Code profile.

.DESCRIPTION
    Reads a text file with one extension id per line (as written by
    `code --list-extensions`), and installs every id that the profile does not
    have yet. Blank lines and lines starting with "#" are ignored. Failures are
    listed at the end and the script then exits with code 1.

    The VS Code CLI installs extensions only into a profile that already
    exists: `code --profile <name> --install-extension <id>` stops with
    "Profile '<name>' not found." The only CLI way to create a profile is to
    open a window with it (`code --profile <name>`), which creates an empty
    one. So when the profile is missing, the script does that once, waits until
    the CLI can see the profile, and then installs. If that does not work,
    create the profile in the Profiles editor (File > Preferences > Profiles)
    and run the script again.

    Use -Profile Default for the Default profile.

.EXAMPLE
    pwsh -File install_extensions.ps1
    Installs extensions-R.txt (next to the script) into the profile "R".

.EXAMPLE
    pwsh -File install_extensions.ps1 -Profile R -List extensions-R.txt

.EXAMPLE
    pwsh -File install_extensions.ps1 -Profile R-Lecturer
    Installs extensions-R-Lecturer.txt into the profile "R-Lecturer".
#>

[CmdletBinding()]
param(
    # Name of the VS Code profile. "Profile" is an alias so that the
    # automatic variable $PROFILE is not overwritten.
    [Alias('Profile')]
    [string] $ProfileName = 'R',

    # List of extension ids. Default: extensions-<Profile>.txt next to the
    # script.
    [string] $List,

    # Seconds to wait for a newly created profile to appear.
    [int] $CreateTimeout = 60
)

$ErrorActionPreference = 'Stop'

# --- Find the VS Code CLI ----------------------------------------------------
$codeCmd = Get-Command code -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $codeCmd) {
    Write-Error ("The VS Code command 'code' is not on PATH. On Windows, tick 'Add to PATH' " +
        "in the installer; on macOS, run 'Shell Command: Install code command in PATH' " +
        "from the Command Palette. Then open a new terminal.")
    exit 2
}

function Invoke-Code {
    # Runs the VS Code CLI and returns its exit code and output (stdout and
    # stderr as text), without letting stderr stop the script.
    param([string[]] $Arguments)
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $output = & $codeCmd.Source @Arguments 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = @($output | Where-Object { $_ -ne '' })
    }
}

# --- Find the list -----------------------------------------------------------
if (-not $List) {
    $List = Join-Path $PSScriptRoot "extensions-$ProfileName.txt"
} elseif (-not (Test-Path -LiteralPath $List) -and -not [System.IO.Path]::IsPathRooted($List)) {
    # A relative path that is not in the current folder: try next to the script.
    $nextToScript = Join-Path $PSScriptRoot $List
    if (Test-Path -LiteralPath $nextToScript) { $List = $nextToScript }
}
if (-not (Test-Path -LiteralPath $List -PathType Leaf)) {
    Write-Error "List not found: $List"
    exit 2
}

$ids = Get-Content -LiteralPath $List -Encoding utf8 |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    Sort-Object -Unique
if (-not $ids) {
    Write-Warning "No extension ids in $List."
    exit 0
}

# --- Make sure the profile exists ---------------------------------------------
# The Default profile is used when --profile is not given.
$profileArgs = if ($ProfileName -eq 'Default') { @() } else { @('--profile', $ProfileName) }

function Get-InstalledExtensions {
    $r = Invoke-Code (@('--list-extensions') + $profileArgs)
    if ($r.ExitCode -eq 0) { return , @($r.Output) }
    if ($r.Output -match 'not found') { return $null }   # profile does not exist
    throw "code --list-extensions failed (exit $($r.ExitCode)): $($r.Output -join ' ')"
}

$installed = Get-InstalledExtensions
if ($null -eq $installed) {
    Write-Host "Profile '$ProfileName' does not exist. Opening VS Code with it once to create it..."
    $null = Invoke-Code @('--new-window', '--profile', $ProfileName)
    $deadline = (Get-Date).AddSeconds($CreateTimeout)
    while ($null -eq $installed -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $installed = Get-InstalledExtensions
    }
    if ($null -eq $installed) {
        Write-Error ("Profile '$ProfileName' still does not exist. Create it in VS Code " +
            "(File > Preferences > Profiles > New Profile), then run this script again.")
        exit 2
    }
    Write-Host "Profile '$ProfileName' created."
}

# --- Install -------------------------------------------------------------------
Write-Host "Profile '$ProfileName': $($ids.Count) extension(s) in $(Split-Path $List -Leaf)."
$done = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$failed = [System.Collections.Generic.List[string]]::new()

foreach ($id in $ids) {
    # Extension ids are case-insensitive; -contains compares that way too.
    if ($installed -contains $id) {
        $skipped.Add($id)
        Write-Host "  skip     $id (already installed)"
        continue
    }
    $r = Invoke-Code (@('--install-extension', $id) + $profileArgs)
    $text = $r.Output -join ' '
    if ($text -match 'built-?in') {
        # E.g. GitHub Copilot Chat, which now ships with VS Code.
        $skipped.Add($id)
        Write-Host "  skip     $id (built into VS Code)"
    } elseif ($r.ExitCode -ne 0 -or $text -match 'Failed Installing|not found') {
        $failed.Add($id)
        Write-Host "  FAILED   $id : $text" -ForegroundColor Red
    } else {
        $done.Add($id)
        Write-Host "  install  $id"
    }
}

# --- Report ----------------------------------------------------------------------
Write-Host ''
Write-Host "Installed: $($done.Count). Skipped: $($skipped.Count). Failed: $($failed.Count)."
if ($failed.Count -gt 0) {
    Write-Host 'Failed extensions:' -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
exit 0
