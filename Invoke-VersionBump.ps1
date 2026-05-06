<#
.SYNOPSIS
    Bumps the ModuleVersion in EntraVacuum.psd1 and stubs a new entry in CHANGELOG.md.
.PARAMETER Part
    Which part of the version to bump: Major, Minor, or Patch (default).
.EXAMPLE
    ./Invoke-VersionBump.ps1
    ./Invoke-VersionBump.ps1 -Part Minor
    ./Invoke-VersionBump.ps1 -Part Major
#>
param (
    [ValidateSet('Major', 'Minor', 'Patch')]
    [string] $Part = 'Patch'
)

$manifestPath  = "$PSScriptRoot/EntraVacuum/EntraVacuum.psd1"
$changelogPath = "$PSScriptRoot/CHANGELOG.md"

$manifest = Test-ModuleManifest -Path $manifestPath
$current  = $manifest.Version

$major = $current.Major
$minor = $current.Minor
$patch = $current.Build

switch ($Part) {
    'Major' { $major++; $minor = 0; $patch = 0 }
    'Minor' { $minor++; $patch = 0 }
    'Patch' { $patch++ }
}

$newVersion = "$major.$minor.$patch"

# Bump manifest
(Get-Content $manifestPath) -replace "ModuleVersion = '$current'", "ModuleVersion = '$newVersion'" |
    Set-Content $manifestPath

# Prepend new changelog section
$today     = Get-Date -Format 'yyyy-MM-dd'
$newEntry  = "## [$newVersion] - $today`n`n### Added`n`n### Changed`n`n### Fixed`n"
$changelog = Get-Content $changelogPath -Raw
$changelog = $changelog -replace '(# Changelog\r?\n)', "`$1`n$newEntry`n"
Set-Content $changelogPath $changelog

Write-Host "$current -> $newVersion"
Write-Host "CHANGELOG.md updated - fill in the [$newVersion] section before merging."
