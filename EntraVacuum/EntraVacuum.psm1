Get-ChildItem "$PSScriptRoot/Private/*.ps1" | ForEach-Object { . $_.FullName }
Get-ChildItem "$PSScriptRoot/Public/*.ps1"  | ForEach-Object { . $_.FullName }
