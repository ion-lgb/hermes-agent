[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadRoot,

    [Parameter(Mandatory = $true)]
    [string]$HermesHome,

    [Parameter(Mandatory = $true)]
    [string]$BrowserRoot,

    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$logDirectory = Split-Path -Parent $LogPath
if (-not $logDirectory) {
    throw "LogPath must include a parent directory: $LogPath"
}
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
Start-Transcript -LiteralPath $LogPath -Force | Out-Null

try {

function Assert-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Offline payload directory is missing: $Path"
    }
}

function Assert-File {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Offline payload file is missing: $Path"
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
}

function Add-UserPathEntries {
    param([Parameter(Mandatory = $true)][string[]]$Entries)

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $items = if ($userPath) { @($userPath -split ";") } else { @() }
    foreach ($entry in $Entries) {
        if ($entry -and (Test-Path -LiteralPath $entry) -and $items -notcontains $entry) {
            $items += $entry
        }
    }
    [Environment]::SetEnvironmentVariable("Path", ($items -join ";"), "User")
}

$resolvedPayloadRoot = (Resolve-Path -LiteralPath $PayloadRoot).Path
$sourceRoot = Join-Path $resolvedPayloadRoot "hermes-agent"
$pythonPayloadRoot = Join-Path $resolvedPayloadRoot "python"
$nodePayloadRoot = Join-Path $resolvedPayloadRoot "node"
$gitPayloadRoot = Join-Path $resolvedPayloadRoot "git"
$nodeDependenciesPayloadRoot = Join-Path $resolvedPayloadRoot "node-dependencies"
$browserPayloadRoot = Join-Path $resolvedPayloadRoot "agent-browser-home"
$wheelhouse = Join-Path $resolvedPayloadRoot "wheelhouse"
$manifestPath = Join-Path $resolvedPayloadRoot "manifest.json"

foreach ($requiredDirectory in @(
    $sourceRoot,
    $pythonPayloadRoot,
    $nodePayloadRoot,
    $gitPayloadRoot,
    $nodeDependenciesPayloadRoot,
    $browserPayloadRoot,
    $wheelhouse
)) {
    Assert-Directory -Path $requiredDirectory
}
Assert-File -Path (Join-Path $sourceRoot "pyproject.toml")
Assert-File -Path (Join-Path $sourceRoot "hermes_cli\main.py")
Assert-File -Path (Join-Path $nodePayloadRoot "node.exe")
Assert-File -Path (Join-Path $gitPayloadRoot "cmd\git.exe")
Assert-File -Path $manifestPath

$browserCandidates = @(Get-ChildItem -LiteralPath $browserPayloadRoot -Filter "chrome.exe" -File -Recurse)
if ($browserCandidates.Count -ne 1) {
    throw "Expected exactly one offline chrome.exe in $browserPayloadRoot, found $($browserCandidates.Count)"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not $manifest.commit -or $manifest.commit -notmatch "^[0-9a-fA-F]{7,40}$") {
    throw "Offline payload manifest has an invalid commit: $manifestPath"
}

$pythonCandidates = @(
    Get-ChildItem -LiteralPath $pythonPayloadRoot -Filter "python.exe" -File -Recurse |
        Where-Object { $_.FullName -notmatch "\\Scripts\\" }
)
if ($pythonCandidates.Count -ne 1) {
    throw "Expected exactly one managed python.exe in $pythonPayloadRoot, found $($pythonCandidates.Count)"
}
$pythonDistributionRoot = Split-Path -Parent $pythonCandidates[0].FullName

$agentRoot = Join-Path $HermesHome "hermes-agent"
$venvRoot = Join-Path $agentRoot "venv"
$venvPython = Join-Path $venvRoot "Scripts\python.exe"
$pythonRoot = Join-Path $HermesHome "python"
$nodeRoot = Join-Path $HermesHome "node"
$gitRoot = Join-Path $HermesHome "git"
$backupRoot = "$agentRoot.offline-backup"

New-Item -ItemType Directory -Path $HermesHome -Force | Out-Null
if (Test-Path -LiteralPath $backupRoot) {
    Remove-Item -LiteralPath $backupRoot -Recurse -Force
}
if (Test-Path -LiteralPath $agentRoot) {
    Move-Item -LiteralPath $agentRoot -Destination $backupRoot
}

try {
    Copy-DirectoryContents -Source $sourceRoot -Destination $agentRoot
    Copy-DirectoryContents -Source $nodeDependenciesPayloadRoot -Destination (Join-Path $agentRoot "node_modules")

    foreach ($runtimeRoot in @($pythonRoot, $nodeRoot, $gitRoot)) {
        if (Test-Path -LiteralPath $runtimeRoot) {
            Remove-Item -LiteralPath $runtimeRoot -Recurse -Force
        }
    }
    Copy-DirectoryContents -Source $pythonDistributionRoot -Destination $pythonRoot
    Copy-DirectoryContents -Source $nodePayloadRoot -Destination $nodeRoot
    Copy-DirectoryContents -Source $gitPayloadRoot -Destination $gitRoot

    if (Test-Path -LiteralPath $BrowserRoot) {
        Remove-Item -LiteralPath $BrowserRoot -Recurse -Force
    }
    Copy-DirectoryContents -Source $browserPayloadRoot -Destination $BrowserRoot
    $installedBrowserCandidates = @(
        Get-ChildItem -LiteralPath $BrowserRoot -Filter "chrome.exe" -File -Recurse
    )
    if ($installedBrowserCandidates.Count -ne 1) {
        throw "Expected exactly one installed chrome.exe in $BrowserRoot, found $($installedBrowserCandidates.Count)"
    }
    $browserExecutable = $installedBrowserCandidates[0].FullName

    $pythonExe = Join-Path $pythonRoot "python.exe"
    Assert-File -Path $pythonExe
    & $pythonExe -m venv $venvRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Creating the Hermes virtual environment failed with exit code $LASTEXITCODE"
    }

    & $venvPython -m pip install --no-index --find-links $wheelhouse pip setuptools wheel
    if ($LASTEXITCODE -ne 0) {
        throw "Installing the offline Python build tools failed with exit code $LASTEXITCODE"
    }
    & $venvPython -m pip install --no-index --find-links $wheelhouse --no-build-isolation -e "$agentRoot[all]"
    if ($LASTEXITCODE -ne 0) {
        throw "Installing Hermes from the offline wheelhouse failed with exit code $LASTEXITCODE"
    }

    $configHelper = Join-Path $agentRoot "scripts\offline\configure_offline.py"
    & $venvPython $configHelper `
        --config (Join-Path $HermesHome "config.yaml") `
        --marker (Join-Path $agentRoot ".hermes-bootstrap-complete") `
        --env-file (Join-Path $HermesHome ".env") `
        --browser-home $BrowserRoot `
        --browser-executable $browserExecutable `
        --commit ([string]$manifest.commit)
    if ($LASTEXITCODE -ne 0) {
        throw "Configuring offline runtime policy failed with exit code $LASTEXITCODE"
    }

    $env:PYTHONPATH = $agentRoot
    & $venvPython -c "import hermes_cli; print(hermes_cli.__file__)"
    if ($LASTEXITCODE -ne 0) {
        throw "Hermes import verification failed with exit code $LASTEXITCODE"
    }

    [Environment]::SetEnvironmentVariable("HERMES_HOME", $HermesHome, "User")
    Add-UserPathEntries -Entries @(
        (Join-Path $venvRoot "Scripts"),
        $nodeRoot,
        (Join-Path $nodeRoot "bin"),
        (Join-Path $gitRoot "cmd"),
        (Join-Path $gitRoot "bin"),
        (Join-Path $gitRoot "usr\bin")
    )

    if (Test-Path -LiteralPath $backupRoot) {
        Remove-Item -LiteralPath $backupRoot -Recurse -Force
    }
} catch {
    if (Test-Path -LiteralPath $agentRoot) {
        Remove-Item -LiteralPath $agentRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $backupRoot) {
        Move-Item -LiteralPath $backupRoot -Destination $agentRoot
    }
    throw
}
} finally {
    Stop-Transcript | Out-Null
}
