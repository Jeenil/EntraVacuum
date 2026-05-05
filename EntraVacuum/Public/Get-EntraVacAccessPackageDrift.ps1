function Get-EntraVacAccessPackageDrift {
    <#
    .SYNOPSIS
        Returns users who should be assigned to an access package but are not, and vice versa.

    .DESCRIPTION
        Compares the expected membership (derived from the auto-assignment policy filter) against
        actual delivered assignments and returns a drift report without making any changes.

    .PARAMETER AccessPackageId
        The object ID of the access package to inspect.

    .EXAMPLE
        Get-EntraVacAccessPackageDrift -AccessPackageId "ad524555-24ef-412a-8d20-e070c088a42d"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $AccessPackageId
    )

    $policies = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackageId eq '$AccessPackageId'" |
        Select-Object -ExpandProperty value

    $autoPolicy = $policies | Where-Object { $_.automaticRequestSettings -ne $null } | Select-Object -First 1

    if (-not $autoPolicy) {
        Write-Warning "No auto-assignment policy found for access package $AccessPackageId"
        return
    }

    $assignments = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignments?`$filter=accessPackageId eq '$AccessPackageId' and state eq 'Delivered'&`$expand=target" |
        Select-Object -ExpandProperty value

    $assignedUserIds = $assignments | ForEach-Object { $_.target.objectId }

    $graphFilter  = Convert-PolicyFilterToGraphFilter -PolicyFilter $autoPolicy.automaticRequestSettings.requestorFilter
    $targetUsers  = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/users?`$filter=$graphFilter&`$select=id,displayName,userPrincipalName" |
        Select-Object -ExpandProperty value

    $targetUserIds = $targetUsers | ForEach-Object { $_.id }

    [PSCustomObject]@{
        AccessPackageId = $AccessPackageId
        ShouldAdd       = $targetUsers | Where-Object { $_.id -notin $assignedUserIds }
        ShouldRemove    = $assignments | Where-Object { $_.target.objectId -notin $targetUserIds } | ForEach-Object { $_.target }
    }
}
