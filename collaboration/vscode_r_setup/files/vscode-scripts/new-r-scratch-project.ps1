[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Name,

    # Default: the Rscript on PATH, i.e. rig's default R version
    # (`rig default <version>`). Pass a full path to use another one.
    [string] $RScriptPath = 'Rscript'
)

$ErrorActionPreference = 'Stop'

$projectName = $Name.Trim()

if ([string]::IsNullOrWhiteSpace($projectName)) {
    throw 'The project name cannot be empty.'
}

if ($projectName -in '.', '..') {
    throw "The project name '$projectName' is not allowed."
}

if ($projectName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw "The project name '$projectName' contains a character that is not allowed in a Windows folder name."
}

if ($projectName.EndsWith('.') -or $projectName.EndsWith(' ')) {
    throw 'The project name cannot end with a period or a space.'
}

$baseName = [System.IO.Path]::GetFileNameWithoutExtension($projectName)
if ($baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
    throw "The project name '$projectName' is reserved by Windows."
}

$rscriptCommand = Get-Command $RScriptPath -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $rscriptCommand) {
    throw "Rscript was not found ('$RScriptPath'). Install R with rig and check that 'C:\Program Files\R\bin' is on PATH, or pass -RScriptPath."
}
$RScriptPath = $rscriptCommand.Source

$codeCommand = Get-Command 'code.cmd' -ErrorAction SilentlyContinue
if (-not $codeCommand) {
    $fallbackCodePath = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
    if (Test-Path -LiteralPath $fallbackCodePath -PathType Leaf) {
        $codeCommand = Get-Item -LiteralPath $fallbackCodePath
    }
    else {
        throw "The VS Code command-line launcher 'code' was not found. Add it to PATH or update this script with its location."
    }
}

$documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
if ([string]::IsNullOrWhiteSpace($documentsPath)) {
    $documentsPath = Join-Path $env:USERPROFILE 'Documents'
}

$scratchRoot = Join-Path $documentsPath 'R-scratch'
$projectPath = Join-Path $scratchRoot $projectName

if (Test-Path -LiteralPath $projectPath) {
    throw "The destination '$projectPath' already exists. Choose a different project name."
}

if (-not (Test-Path -LiteralPath $scratchRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $scratchRoot | Out-Null
}

$rExpression = @'
project_path <- Sys.getenv(
  "VSCODE_R_SCRATCH_PROJECT_PATH",
  unset = NA_character_
)

if (is.na(project_path) || !nzchar(project_path)) {
  stop("The scratch project path was not provided.", call. = FALSE)
}

if (!requireNamespace("usethis", quietly = TRUE)) {
  stop(
    "The R package 'usethis' is not installed. Run install.packages('usethis').",
    call. = FALSE
  )
}

usethis::create_project(
  project_path,
  rstudio = TRUE,
  open = FALSE
)
'@

$localeVariableNames = @(
    'LANG',
    'LC_ALL',
    'LC_COLLATE',
    'LC_CTYPE',
    'LC_MONETARY',
    'LC_TIME'
)
$savedLocaleVariables = @{}

foreach ($localeVariableName in $localeVariableNames) {
    $localeValue = [Environment]::GetEnvironmentVariable($localeVariableName, 'Process')
    if ($null -ne $localeValue) {
        $savedLocaleVariables[$localeVariableName] = $localeValue
    }
    [Environment]::SetEnvironmentVariable($localeVariableName, $null, 'Process')
}

$projectPathVariableName = 'VSCODE_R_SCRATCH_PROJECT_PATH'
$savedProjectPathVariable = [Environment]::GetEnvironmentVariable($projectPathVariableName, 'Process')
$temporaryRScriptPath = Join-Path (
    [System.IO.Path]::GetTempPath()
) "vscode-r-scratch-$([guid]::NewGuid().ToString('N')).R"

try {
    [System.IO.File]::WriteAllText(
        $temporaryRScriptPath,
        $rExpression,
        [System.Text.UTF8Encoding]::new($false)
    )
    [Environment]::SetEnvironmentVariable($projectPathVariableName, $projectPath, 'Process')
    & $RScriptPath --vanilla $temporaryRScriptPath
    $rExitCode = $LASTEXITCODE
}
finally {
    if (Test-Path -LiteralPath $temporaryRScriptPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryRScriptPath -Force
    }

    [Environment]::SetEnvironmentVariable(
        $projectPathVariableName,
        $savedProjectPathVariable,
        'Process'
    )

    foreach ($localeVariableName in $localeVariableNames) {
        $savedLocaleValue = $savedLocaleVariables[$localeVariableName]
        [Environment]::SetEnvironmentVariable(
            $localeVariableName,
            $savedLocaleValue,
            'Process'
        )
    }
}

if ($rExitCode -ne 0) {
    throw "R could not create the project (exit code $rExitCode). Check '$projectPath' for any partially created files before trying again."
}

& $codeCommand.Source --new-window $projectPath
if ($LASTEXITCODE -ne 0) {
    throw "The project was created at '$projectPath', but VS Code could not open it."
}

Write-Host "Created and opened R scratch project: $projectPath"
