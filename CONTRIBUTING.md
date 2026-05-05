# Contributing

## Setup

```powershell
# Import the module locally
Import-Module ./EntraVacuum/EntraVacuum.psd1 -Force

# Install dev dependencies
Install-Module PSScriptAnalyzer -Scope CurrentUser
Install-Module Pester -Scope CurrentUser
```

## Workflow

1. Branch off `main`
2. Add/modify functions in `EntraVacuum/Public/` (exported) or `EntraVacuum/Private/` (internal)
3. Update `FunctionsToExport` in `EntraVacuum.psd1` for any new public functions
4. Add tests in `Tests/`
5. Run lint and tests locally before opening a PR

```powershell
Invoke-ScriptAnalyzer -Path ./EntraVacuum -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-Pester ./Tests
```

## Publishing

Bump `ModuleVersion` in `EntraVacuum.psd1` before merging to `main`. The publish workflow runs automatically on merge.

PSGallery versions are immutable - once published a version cannot be overwritten.
