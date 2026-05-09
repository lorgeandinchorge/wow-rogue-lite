param(
    [string]$ProjectRoot = $PSScriptRoot,
    [string]$OutputDir = (Join-Path $PSScriptRoot "dist")
)

$ErrorActionPreference = "Stop"

function Get-TocPath {
    param([string]$Root)

    $tocFiles = Get-ChildItem -LiteralPath $Root -Filter *.toc -File
    if ($tocFiles.Count -eq 0) {
        throw "No .toc file found in $Root"
    }
    if ($tocFiles.Count -gt 1) {
        throw "Multiple .toc files found. Keep one addon root per package directory."
    }
    return $tocFiles[0].FullName
}

function Get-VersionFromToc {
    param([string]$TocPath)

    $versionLine = Get-Content -LiteralPath $TocPath | Where-Object { $_ -match '^##\s*Version\s*:\s*(.+)$' } | Select-Object -First 1
    if (-not $versionLine) {
        return "dev"
    }
    return ($versionLine -replace '^##\s*Version\s*:\s*', '').Trim()
}

function Get-AddonFilesFromToc {
    param(
        [string]$TocPath,
        [string]$Root
    )

    $files = New-Object System.Collections.Generic.List[string]
    $tocDir = Split-Path -Parent $TocPath

    foreach ($line in Get-Content -LiteralPath $TocPath) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed.StartsWith("##")) { continue }
        if ($trimmed.StartsWith("#")) { continue }

        $candidate = Join-Path $tocDir $trimmed
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "TOC references a missing file: $trimmed"
        }

        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $rootResolved = (Resolve-Path -LiteralPath $Root).Path
        if (-not $resolved.StartsWith($rootResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to package file outside addon root: $resolved"
        }

        $files.Add($resolved)
    }

    return $files
}

function Get-ExtraReleaseFiles {
    param([string]$Root)

    $manifestPath = Join-Path $Root "release-extra-files.txt"
    $files = New-Object System.Collections.Generic.List[string]

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $files
    }

    foreach ($line in Get-Content -LiteralPath $manifestPath) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        if ($trimmed.StartsWith("#")) { continue }

        $candidate = Join-Path $Root $trimmed
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "release-extra-files.txt references a missing file: $trimmed"
        }

        $files.Add((Resolve-Path -LiteralPath $candidate).Path)
    }

    return $files
}

function Get-RelativePathCompat {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)

    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull += [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    return [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', '\')
}

$rootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
$addonName = Split-Path -Leaf $rootResolved
$tocPath = Get-TocPath -Root $rootResolved
$version = Get-VersionFromToc -TocPath $tocPath

$packageFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$null = $packageFiles.Add((Resolve-Path -LiteralPath $tocPath).Path)

foreach ($file in Get-AddonFilesFromToc -TocPath $tocPath -Root $rootResolved) {
    $null = $packageFiles.Add($file)
}

foreach ($file in Get-ExtraReleaseFiles -Root $rootResolved) {
    $null = $packageFiles.Add($file)
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$stageRoot = Join-Path $OutputDir "_stage"
$stageAddonRoot = Join-Path $stageRoot $addonName
$zipPath = Join-Path $OutputDir ("{0}-v{1}.zip" -f $addonName, $version)

if (Test-Path -LiteralPath $stageRoot) {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

New-Item -ItemType Directory -Path $stageAddonRoot -Force | Out-Null

foreach ($sourcePath in $packageFiles) {
    $relativePath = Get-RelativePathCompat -BasePath $rootResolved -TargetPath $sourcePath
    $destinationPath = Join-Path $stageAddonRoot $relativePath
    $destinationDir = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
}

Compress-Archive -Path (Join-Path $stageRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal

Write-Host ""
Write-Host "Created CurseForge package:" -ForegroundColor Green
Write-Host "  $zipPath"
Write-Host ""
Write-Host "Packaged files:" -ForegroundColor Green
foreach ($sourcePath in ($packageFiles | Sort-Object)) {
    $relativePath = Get-RelativePathCompat -BasePath $rootResolved -TargetPath $sourcePath
    Write-Host "  $relativePath"
}
