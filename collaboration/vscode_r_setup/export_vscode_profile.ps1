# Refresh the published copies of my VS Code environment in files/ from the
# live configuration on this machine, then check them for anything private.
#
#   pwsh -File collaboration/vscode_r_setup/export_vscode_profile.ps1
#
# Then re-render the site. files/ is a copy: the live files are the source.
# _data/ holds key lists used by the pages to check that every setting and
# extension is documented (Quarto does not publish folders starting with "_").

[CmdletBinding()]
param(
    [string[]] $Profiles = @('R', 'R-Lecturer')
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$files = Join-Path $root 'files'
$data = Join-Path $root '_data'
$user = Join-Path $env:APPDATA 'Code\User'

function Copy-Exported {
    param([string] $From, [string] $To)
    if (-not (Test-Path -LiteralPath $From)) {
        Write-Warning "Not found, skipped: $From"
        return
    }
    $dest = Join-Path $files $To
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    # Normalise to UTF-8 without BOM and LF line endings, so the diff only
    # shows real changes.
    $text = [System.IO.File]::ReadAllText($From) -replace "`r`n", "`n"
    # Redact SSH host names (keys of remote.SSH.remotePlatform): internal
    # servers do not belong on a public page.
    $script:hostCount = 0
    $text = [regex]::Replace($text, '"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+"(?=\s*:\s*"(linux|windows|macOS)")', {
            $script:hostCount++; "`"server-$($script:hostCount).example.org`""
        })
    [System.IO.File]::WriteAllText($dest, $text, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  $To"
}

function Get-TopLevelKeys {
    param([string] $JsonPath)
    # PowerShell 7 reads JSON with comments (JSONC), as VS Code writes it.
    $obj = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json -AsHashtable
    $obj.Keys | Sort-Object
}

Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $files, $data
New-Item -ItemType Directory -Force -Path $files, $data | Out-Null

# Profile name -> folder id, from VS Code's own registry of profiles.
$storage = Get-Content (Join-Path $user 'globalStorage\storage.json') -Raw | ConvertFrom-Json
$profileIds = @{}
foreach ($p in $storage.userDataProfiles) { $profileIds[$p.name] = $p.location }

Write-Host 'Default profile'
Copy-Exported (Join-Path $user 'settings.json') 'Default/settings.json'
Get-TopLevelKeys (Join-Path $user 'settings.json') | Set-Content (Join-Path $data 'keys-Default-settings.txt')

foreach ($name in $Profiles) {
    $id = $profileIds[$name]
    if (-not $id) { throw "Profile '$name' not found in storage.json." }
    $dir = Join-Path $user "profiles\$id"
    Write-Host "Profile $name"
    foreach ($f in 'settings.json', 'keybindings.json', 'tasks.json') {
        Copy-Exported (Join-Path $dir $f) "$name/$f"
    }
    Get-ChildItem (Join-Path $dir 'snippets') -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Exported $_.FullName "$name/snippets/$($_.Name)"
    }
    Get-TopLevelKeys (Join-Path $dir 'settings.json') | Set-Content (Join-Path $data "keys-$name-settings.txt")

    $ext = code --list-extensions --profile $name
    if ($LASTEXITCODE -ne 0) { throw "code --list-extensions failed for profile '$name'." }
    $ext | Sort-Object | Set-Content (Join-Path $files "extensions-$name.txt")
    Write-Host "  extensions-$name.txt ($($ext.Count))"

    # Commands bound in keybindings.json (without the "-" of a removed default).
    $kb = Get-Content (Join-Path $dir 'keybindings.json') -Raw | ConvertFrom-Json
    $kb | ForEach-Object { $_.command -replace '^-', '' } | Sort-Object -Unique |
        Set-Content (Join-Path $data "keys-$name-keybindings.txt")
}

# All extensions across the exported profiles, plus their name and
# description (from each installed extension's package.json), for the pages.
$allExt = Get-ChildItem $files -Filter 'extensions-*.txt' | Get-Content | Sort-Object -Unique
$allExt | Set-Content (Join-Path $data 'keys-extensions.txt')

$extRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
function Resolve-Nls([string] $dir, [string] $value) {
    if ($value -notmatch '^%(.+)%$') { return $value }
    $nlsFile = Join-Path $dir 'package.nls.json'
    if (-not (Test-Path $nlsFile)) { return $value }
    $entry = (Get-Content $nlsFile -Raw | ConvertFrom-Json -AsHashtable)[$Matches[1]]
    if ($entry -is [hashtable]) { $entry.message } else { $entry }
}
$allExt | ForEach-Object {
    $id = $_
    $extFolder = Get-ChildItem $extRoot -Directory | Where-Object { $_.Name -like "$id-*" } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($extFolder) {
        $pkg = Get-Content (Join-Path $extFolder.FullName 'package.json') -Raw | ConvertFrom-Json
        $displayName = Resolve-Nls $extFolder.FullName $pkg.displayName
        $description = (Resolve-Nls $extFolder.FullName $pkg.description) -replace '\s+', ' '
        "$id`t$displayName`t$description"
    } else {
        "$id`t`t(built into VS Code or not installed locally)"
    }
} | Set-Content (Join-Path $data 'extensions-meta.tsv')

Write-Host 'Helper scripts (~/.vscode-scripts)'
Get-ChildItem (Join-Path $env:USERPROFILE '.vscode-scripts') -Filter '*.ps1' -File | ForEach-Object {
    Copy-Exported $_.FullName "vscode-scripts/$($_.Name)"
}

Write-Host 'Install helper (kept next to this script)'
Copy-Exported (Join-Path $root 'install_extensions.ps1') 'install_extensions.ps1'

Write-Host 'Outside VS Code'
Copy-Exported (Join-Path ([Environment]::GetFolderPath('MyDocuments')) '.Rprofile') 'Rprofile.R'
$psDir = Split-Path $PROFILE.CurrentUserCurrentHost
Copy-Exported (Join-Path $psDir 'profile.ps1') 'powershell/profile.ps1'
Copy-Exported (Join-Path $psDir 'Microsoft.PowerShell_profile.ps1') 'powershell/Microsoft.PowerShell_profile.ps1'

# ---------------------------------------------------------------------------
# Leak check: nothing user- or machine-specific may be published.
# ---------------------------------------------------------------------------
$patterns = @(
    [regex]::Escape($env:USERPROFILE),
    [regex]::Escape($env:USERPROFILE.Replace('\', '/')),
    [regex]::Escape($env:USERPROFILE.Replace('\', '\\')),
    'C:[\\/]+Users[\\/]+(?!\$)',
    'uni-bayreuth\.de|cuni\.cz',
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
) + ($profileIds.Values | Where-Object { $_ -match '^-?[0-9a-f]{6,}$' } | ForEach-Object { [regex]::Escape($_) })

$hits = Get-ChildItem $files -Recurse -File | Select-String -Pattern $patterns
if ($hits) {
    $hits | ForEach-Object { Write-Host "LEAK $($_.Path.Replace($root, '.')):$($_.LineNumber): $($_.Line.Trim())" -ForegroundColor Red }
    throw "Leak check failed: $(@($hits).Count) line(s). Fix the live file (or this script), then re-run."
}
Write-Host 'Leak check passed.' -ForegroundColor Green
