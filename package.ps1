param(
    [string]$OutDir = (Join-Path $PSScriptRoot "dist")
)

# Builds the CurseForge release zip: AutoSpellRanks-<version>.zip containing
# only the AutoSpellRanks folder (no tools, installer, README or git metadata).

$ErrorActionPreference = "Stop"

$addon = Join-Path $PSScriptRoot "AutoSpellRanks"
$toc   = Join-Path $addon "AutoSpellRanks.toc"
if (-not (Test-Path $toc)) { throw "TOC not found: $toc" }

$versionLine = Get-Content $toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | Select-Object -First 1
if (-not $versionLine) { throw "No ## Version line in $toc" }
$version = ($versionLine -replace '^## Version:\s*', '').Trim()

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }
$zip = Join-Path $OutDir "AutoSpellRanks-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }

# Stage a clean copy so the archive's top level is AutoSpellRanks/.
$stage = Join-Path $env:TEMP ("AutoSpellRanks-package-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $stage | Out-Null
try {
    Copy-Item -Recurse $addon (Join-Path $stage "AutoSpellRanks")
    Get-ChildItem -Recurse -Force (Join-Path $stage "AutoSpellRanks") -Include "*.bak", "Thumbs.db", ".DS_Store" | Remove-Item -Force
    Compress-Archive -Path (Join-Path $stage "AutoSpellRanks") -DestinationPath $zip -CompressionLevel Optimal
} finally {
    Remove-Item -Recurse -Force $stage
}

$size = [math]::Round((Get-Item $zip).Length / 1KB)
Write-Host "Built $zip ($size KB)"
