function Convert-PolicyFilterToGraphFilter {
    <#
    .SYNOPSIS
        Translates an Entra auto-assignment policy filter expression to a Graph OData filter string.

    .DESCRIPTION
        Auto-assignment policy filters use a syntax like:
            user.department -eq "Marketing"
            user.extension_<guid>_someAttr -eq "Value"
        This function converts them to Graph-compatible OData filter strings:
            department eq 'Marketing'
            extension_<guid>_someAttr eq 'Value'

    .PARAMETER PolicyFilter
        The filter string from the auto-assignment policy's requestorFilter property.
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

    # Convert -eq to eq, -ne to ne, -and to and, -or to or
    $filter = $filter -replace ' -eq ',  " eq "
    $filter = $filter -replace ' -ne ',  " ne "
    $filter = $filter -replace ' -and ', " and "
    $filter = $filter -replace ' -or ',  " or "

    # Convert double quotes to single quotes (OData style)
    $filter = $filter -replace '"', "'"

    return $filter
}
