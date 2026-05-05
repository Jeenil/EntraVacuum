# These settings match what CI enforces in lint.yml.
# If you change exclusions here, update the -ExcludeRule list in lint.yml to match.
@{
    IncludeDefaultRules = $true
    Severity            = @("Error", "Warning")
    ExcludeRules        = @(
        # We format files in Unix format (LF), so BOM is not expected.
        "PSUseBOMForUnicodeEncodedFile"

        # Individual function files don't have their own manifests.
        "PSMissingModuleManifestField"
    )
}
