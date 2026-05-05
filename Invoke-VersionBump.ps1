<#
.SYNOPSIS
    Bumps the ModuleVersion in EntraVacuum.psd1.
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

$manifestPath = "$PSScriptRoot/EntraVacuum/EntraVacuum.psd1"
$manifest = Test-ModuleManifest -Path $manifestPath
$current = $manifest.Version

$major = $current.Major
$minor = $current.Minor
$patch = $current.Build

switch ($Part) {
    'Major' { $major++; $minor = 0; $patch = 0 }
    'Minor' { $minor++; $patch = 0 }
    'Patch' { $patch++ }
}

$newVersion = "$major.$minor.$patch"

(Get-Content $manifestPath) -replace "ModuleVersion = '$current'", "ModuleVersion = '$newVersion'" |
    Set-Content $manifestPath

Write-Host "$current -> $newVersion"
