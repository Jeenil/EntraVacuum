# EntraVacuum

Entra ID desired-state management for access packages. Reconciles assignments against auto-assignment policy filters faster than the built-in 24-hour cycle.

[![Lint](https://github.com/Jeenil/EntraVacuum/actions/workflows/lint.yml/badge.svg)](https://github.com/Jeenil/EntraVacuum/actions/workflows/lint.yml)
[![Test](https://github.com/Jeenil/EntraVacuum/actions/workflows/test.yml/badge.svg)](https://github.com/Jeenil/EntraVacuum/actions/workflows/test.yml)

## Install

```powershell
Install-Module -Name EntraVacuum -Scope CurrentUser
```

## Requirements

- PowerShell 7.2+
- Microsoft.Graph.Authentication 2.0.0+
- Microsoft.Graph.Identity.Governance 2.0.0+

## Usage

```powershell
Connect-MgGraph -Scopes "User.Read.All", "EntitlementManagement.ReadWrite.All"

# Preview what would change
Get-EntraVacAccessPackageDrift -AccessPackageId "<package-id>"

# Sync assignments
Sync-EntraVacAccessPackage -AccessPackageId "<package-id>"

# Dry run
Sync-EntraVacAccessPackage -AccessPackageId "<package-id>" -WhatIf
```

## Development

```powershell
# Import locally
Import-Module ./EntraVacuum/EntraVacuum.psd1 -Force

# Lint
Invoke-ScriptAnalyzer -Path ./EntraVacuum -Recurse -Settings ./PSScriptAnalyzerSettings.psd1

# Test
Invoke-Pester ./Tests

# Validate manifest before publishing
Test-ModuleManifest -Path ./EntraVacuum/EntraVacuum.psd1
```

## License

MIT
