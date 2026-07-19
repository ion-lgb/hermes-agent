[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadRoot,

    [Parameter(Mandatory = $true)]
    [string]$Commit,

    [Parameter(Mandatory = $true)]
    [string]$PythonVersion,

    [Parameter(Mandatory = $true)]
    [string]$NodeVersion,

    [Parameter(Mandatory = $true)]
    [string]$GitVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][uri]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )

    $lastError = $null
    foreach ($attempt in 1..3) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
            return
        } catch {
            $lastError = $_
            Write-Warning "Download attempt $attempt failed for $Uri : $($_.Exception.Message)"
        }
    }
    throw "Download failed after 3 attempts for $Uri : $($lastError.Exception.Message)"
}

function Invoke-CommandWithRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Command,
        [Parameter(Mandatory = $true)][string]$Description
    )

    foreach ($attempt in 1..3) {
        & $Command
        if ($LASTEXITCODE -eq 0) {
            return
        }
        Write-Warning "$Description failed on attempt $attempt with exit code $LASTEXITCODE"
    }
    throw "$Description failed after 3 attempts"
}

if ($Commit -notmatch "^[0-9a-fA-F]{40}$") {
    throw "Commit must be a full 40-character Git SHA, received: $Commit"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$resolvedHead = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $resolvedHead -ne $Commit) {
    throw "Checked-out commit $resolvedHead does not match requested payload commit $Commit"
}

if (Test-Path -LiteralPath $PayloadRoot) {
    Remove-Item -LiteralPath $PayloadRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $PayloadRoot -Force | Out-Null
$resolvedPayloadRoot = (Resolve-Path -LiteralPath $PayloadRoot).Path

$sourceZip = Join-Path $resolvedPayloadRoot "hermes-agent.zip"
$sourceRoot = Join-Path $resolvedPayloadRoot "hermes-agent"
& git -C $repoRoot archive --format=zip --output=$sourceZip $Commit
if ($LASTEXITCODE -ne 0) {
    throw "git archive failed for commit $Commit with exit code $LASTEXITCODE"
}
Expand-Archive -LiteralPath $sourceZip -DestinationPath $sourceRoot -Force
Remove-Item -LiteralPath $sourceZip -Force

$pythonPayloadRoot = Join-Path $resolvedPayloadRoot "python"
Invoke-CommandWithRetry -Description "Managed Python download" -Command {
    & uv python install $PythonVersion --install-dir $pythonPayloadRoot --no-bin --reinstall
}

$wheelhouse = Join-Path $resolvedPayloadRoot "wheelhouse"
New-Item -ItemType Directory -Path $wheelhouse -Force | Out-Null
Push-Location $repoRoot
try {
    Invoke-CommandWithRetry -Description "Python wheelhouse build" -Command {
        & python -m pip wheel --wheel-dir $wheelhouse ".[all]"
    }
    Invoke-CommandWithRetry -Description "Python build-tool download" -Command {
        & python -m pip download --dest $wheelhouse --only-binary=:all: "setuptools>=77,<83" wheel pip
    }
} finally {
    Pop-Location
}

$nodeCommand = Get-Command node -ErrorAction Stop
$nodeRuntimeRoot = Split-Path -Parent $nodeCommand.Source
$resolvedNodeVersion = (& $nodeCommand.Source --version).Trim().TrimStart("v")
if (-not $resolvedNodeVersion.StartsWith("$NodeVersion.")) {
    throw "Expected Node.js $NodeVersion.x but found $resolvedNodeVersion at $($nodeCommand.Source)"
}
$nodePayloadRoot = Join-Path $resolvedPayloadRoot "node"
Copy-Item -LiteralPath $nodeRuntimeRoot -Destination $nodePayloadRoot -Recurse -Force

$nodeProject = Join-Path $resolvedPayloadRoot "node-project"
New-Item -ItemType Directory -Path $nodeProject -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot "package.json") -Destination $nodeProject
Copy-Item -LiteralPath (Join-Path $repoRoot "package-lock.json") -Destination $nodeProject
$agentBrowserSourceRoot = Join-Path $env:USERPROFILE ".agent-browser"
if (Test-Path -LiteralPath $agentBrowserSourceRoot) {
    Remove-Item -LiteralPath $agentBrowserSourceRoot -Recurse -Force
}
Push-Location $nodeProject
try {
    Invoke-CommandWithRetry -Description "Root Node dependency installation" -Command {
        & npm ci --workspaces=false --ignore-scripts --no-audit --no-fund
    }
    $agentBrowser = Join-Path $nodeProject "node_modules\.bin\agent-browser.cmd"
    if (-not (Test-Path -LiteralPath $agentBrowser -PathType Leaf)) {
        throw "agent-browser command was not installed at $agentBrowser"
    }
    Invoke-CommandWithRetry -Description "Playwright Chromium download" -Command {
        & $agentBrowser install
    }
} finally {
    Pop-Location
}
$agentBrowserPayloadRoot = Join-Path $resolvedPayloadRoot "agent-browser-home"
if (-not (Test-Path -LiteralPath $agentBrowserSourceRoot -PathType Container)) {
    throw "agent-browser did not create its browser home at $agentBrowserSourceRoot"
}
Copy-Item -LiteralPath $agentBrowserSourceRoot -Destination $agentBrowserPayloadRoot -Recurse -Force
$nodeDependenciesSourceRoot = Join-Path $nodeProject "node_modules"
$nodeDependenciesArchive = Join-Path $resolvedPayloadRoot "node-dependencies.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    $nodeDependenciesSourceRoot,
    $nodeDependenciesArchive,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)
$nodeDependenciesZip = [System.IO.Compression.ZipFile]::OpenRead($nodeDependenciesArchive)
try {
    $agentBrowserArchiveEntry = @(
        $nodeDependenciesZip.Entries |
            Where-Object { $_.FullName -eq ".bin/agent-browser.cmd" }
    )
    if ($agentBrowserArchiveEntry.Count -ne 1) {
        throw "Expected agent-browser in $nodeDependenciesArchive, found $($agentBrowserArchiveEntry.Count) entries"
    }
} finally {
    $nodeDependenciesZip.Dispose()
}
Remove-Item -LiteralPath $nodeProject -Recurse -Force

$gitTag = "v$GitVersion.windows.1"
$gitArchiveName = "PortableGit-$GitVersion-64-bit.7z.exe"
$gitArchive = Join-Path $resolvedPayloadRoot $gitArchiveName
$gitUri = [uri]"https://github.com/git-for-windows/git/releases/download/$gitTag/$gitArchiveName"
Invoke-Download -Uri $gitUri -OutFile $gitArchive
$gitPayloadRoot = Join-Path $resolvedPayloadRoot "git"
New-Item -ItemType Directory -Path $gitPayloadRoot -Force | Out-Null
$gitProcess = Start-Process -FilePath $gitArchive -ArgumentList "-o`"$gitPayloadRoot`"", "-y" -Wait -PassThru -NoNewWindow
if ($gitProcess.ExitCode -ne 0) {
    throw "PortableGit extraction failed with exit code $($gitProcess.ExitCode)"
}
Remove-Item -LiteralPath $gitArchive -Force

Copy-Item -LiteralPath (Join-Path $repoRoot "scripts\offline\install-offline.ps1") -Destination $resolvedPayloadRoot

$manifest = [ordered]@{
    schemaVersion = 1
    commit = $Commit.ToLowerInvariant()
    pythonVersion = $PythonVersion
    nodeVersion = $resolvedNodeVersion
    gitVersion = $GitVersion
    createdAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
}
$manifestJson = $manifest | ConvertTo-Json
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText(
    (Join-Path $resolvedPayloadRoot "manifest.json"),
    $manifestJson,
    $utf8NoBom
)

foreach ($requiredPath in @(
    (Join-Path $sourceRoot "pyproject.toml"),
    (Join-Path $pythonPayloadRoot "*"),
    (Join-Path $nodePayloadRoot "node.exe"),
    (Join-Path $gitPayloadRoot "cmd\git.exe"),
    (Join-Path $gitPayloadRoot "usr\bin\unzip.exe"),
    $nodeDependenciesArchive,
    (Join-Path $resolvedPayloadRoot "agent-browser-home"),
    (Join-Path $resolvedPayloadRoot "manifest.json")
)) {
    if (-not (Test-Path -Path $requiredPath)) {
        throw "Prepared payload is missing required path: $requiredPath"
    }
}
