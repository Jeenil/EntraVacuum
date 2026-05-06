function Get-EntraVacAccessPackageDrift {
    <#
    .SYNOPSIS
        Returns users who should be assigned to an access package but are not, and vice versa.

    .DESCRIPTION
        Compares the expected membership (derived from the active auto-assignment policy's
        membershipRule) against actual delivered assignments and returns a drift report without
        making any changes.

        Microsoft only permits one auto-assignment policy per access package. If more than one
        active policy is detected this indicates a misconfiguration and an error is emitted.
        Ref: https://learn.microsoft.com/en-us/entra/id-governance/entitlement-management-access-package-auto-assignment-policy

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

    # Ref: https://learn.microsoft.com/en-us/graph/api/entitlementmanagement-list-assignmentpolicies?view=graph-rest-1.0
    $policies = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq '$AccessPackageId'" |
        Select-Object -ExpandProperty value

    # Validate the auto-assignment policy state.
    # Ref: https://learn.microsoft.com/en-us/graph/api/resources/accesspackageautomaticrequestsettings?view=graph-rest-1.0
    $autoPolicies     = $policies | Where-Object { $null -ne $_.automaticRequestSettings }
    $activePolicies   = $autoPolicies | Where-Object { $_.automaticRequestSettings.requestAccessForAllowedTargets -eq $true }
    $inactivePolicies = $autoPolicies | Where-Object { $_.automaticRequestSettings.requestAccessForAllowedTargets -ne $true }

    if (-not $autoPolicies) {
        Write-Warning "No auto-assignment policy found for access package $AccessPackageId"
        return
    }

    if ($inactivePolicies) {
        Write-Warning "The auto-assignment policy for access package $AccessPackageId is inactive (requestAccessForAllowedTargets = false). Skipping."
        return
    }

    if (($activePolicies | Measure-Object).Count -gt 1) {
        Write-Error "Access package $AccessPackageId has more than one active auto-assignment policy. This is a misconfiguration - only one is supported. Resolve in the Entra portal before running this command."
        return
    }

    $activePolicy = $activePolicies | Select-Object -First 1

    # Get Delivered assignments.
    # Ref: https://learn.microsoft.com/en-us/graph/api/entitlementmanagement-list-assignments?view=graph-rest-1.0
    $assignments = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq '$AccessPackageId' and state eq 'Delivered'&`$expand=target" |
        Select-Object -ExpandProperty value

    $assignedUserIds = $assignments | ForEach-Object { $_.target.objectId }

    # Ref: https://learn.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0
    $membershipRule = $activePolicy.specificAllowedTargets |
        Where-Object { $_.'@odata.type' -eq '#microsoft.graph.attributeRuleMembers' } |
        Select-Object -First 1 -ExpandProperty membershipRule

    if ([string]::IsNullOrWhiteSpace($membershipRule)) {
        Write-Warning "The auto-assignment policy for access package $AccessPackageId has no membershipRule. Skipping to avoid unintended removals."
        return
    }

    $graphFilter = Convert-PolicyFilterToGraphFilter -PolicyFilter $membershipRule
    $targetUsers = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/users?`$filter=$graphFilter&`$select=id,displayName,userPrincipalName" |
        Select-Object -ExpandProperty value

    if (-not $targetUsers) {
        Write-Warning "The membershipRule for access package $AccessPackageId returned no users. Skipping to avoid unintended removals."
        return
    }

    $targetUserIds = $targetUsers | ForEach-Object { $_.id }

    [PSCustomObject]@{
        AccessPackageId = $AccessPackageId
        ShouldAdd       = $targetUsers | Where-Object { $_.id -notin $assignedUserIds }
        ShouldRemove    = $assignments | Where-Object { $_.target.objectId -notin $targetUserIds } | ForEach-Object { $_.target }
    }
}
