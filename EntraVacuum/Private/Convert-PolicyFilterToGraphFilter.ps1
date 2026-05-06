function Convert-PolicyFilterToGraphFilter {
    <#
    .SYNOPSIS
        Translates an Entra auto-assignment policy filter expression to a Graph OData filter string.

    .DESCRIPTION
        Auto-assignment policy filters use a syntax like:
            user.department -eq "Marketing"
            user.extensionAttribute1 -eq "Foo"
        This function converts them to Graph-compatible OData filter strings:
            department eq 'Marketing'
            onPremisesExtensionAttributes/extensionAttribute1 eq 'Foo'

    .PARAMETER PolicyFilter
        The filter string from the auto-assignment policy's specificAllowedTargets membershipRule.
    #>
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $PolicyFilter
    )

    if ([string]::IsNullOrWhiteSpace($PolicyFilter)) {
        return $null
    }

    # Strip 'user.' prefix from each clause
    $filter = $PolicyFilter -replace 'user\.', ''

    # extensionAttribute1..15 lives under onPremisesExtensionAttributes in Graph.
    # Ref: https://learn.microsoft.com/en-us/graph/api/resources/onpremisesextensionattributes?view=graph-rest-1.0
    $filter = $filter -replace 'extensionAttribute(\d+)', 'onPremisesExtensionAttributes/extensionAttribute$1'

    # Convert -eq to eq, -ne to ne, -and to and, -or to or
    $filter = $filter -replace ' -eq ',  " eq "
    $filter = $filter -replace ' -ne ',  " ne "
    $filter = $filter -replace ' -and ', " and "
    $filter = $filter -replace ' -or ',  " or "

    # Convert double quotes to single quotes (OData style)
    $filter = $filter -replace '"', "'"

    return $filter
}
