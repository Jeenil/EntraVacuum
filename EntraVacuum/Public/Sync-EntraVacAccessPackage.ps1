function Sync-EntraVacAccessPackage {
    <#
    .SYNOPSIS
        Syncs membership for an Entra ID access package based on its auto-assignment policy filter.

    .DESCRIPTION
        Reads the auto-assignment policy filter for the given access package, evaluates it against
        all users in the tenant, and performs adminAdd/adminRemove to reconcile actual assignments.

    .PARAMETER AccessPackageId
        The object ID of the access package to sync.

    .PARAMETER WhatIf
        Preview changes without applying them.

    .EXAMPLE
        Sync-EntraVacAccessPackage -AccessPackageId "ad524555-24ef-412a-8d20-e070c088a42d"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string] $AccessPackageId
    )

    # Get the auto-assignment policy for this package
    $policies = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq '$AccessPackageId'" |
        Select-Object -ExpandProperty value

    $autoPolicy = $policies | Where-Object { $_.requestorSettings.scopeType -eq 'AllExistingDirectoryMemberUsers' -or $null -ne $_.automaticRequestSettings } |
        Select-Object -First 1

    if (-not $autoPolicy) {
        Write-Warning "No auto-assignment policy found for access package $AccessPackageId"
        return
    }

    # Get current assignments
    $assignments = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq '$AccessPackageId' and state eq 'Delivered'&`$expand=target" |
        Select-Object -ExpandProperty value

    $assignedUserIds = $assignments | ForEach-Object { $_.target.objectId }

    # Translate policy filter to Graph OData filter and fetch target users
    $graphFilter = Convert-PolicyFilterToGraphFilter -PolicyFilter $autoPolicy.automaticRequestSettings.requestorFilter
    $targetUsers  = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/users?`$filter=$graphFilter&`$select=id" |
        Select-Object -ExpandProperty value

    $targetUserIds = $targetUsers | ForEach-Object { $_.id }

    # Diff
    $toAdd    = $targetUserIds | Where-Object { $_ -notin $assignedUserIds }
    $toRemove = $assignedUserIds | Where-Object { $_ -notin $targetUserIds }

    Write-Verbose "Access package $AccessPackageId - adding $($toAdd.Count), removing $($toRemove.Count)"

    foreach ($userId in $toAdd) {
        if ($PSCmdlet.ShouldProcess($userId, "adminAdd to access package $AccessPackageId")) {
            Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentRequests" `
                -Body (@{
                    requestType   = 'adminAdd'
                    accessPackageAssignment = @{
                        targetId      = $userId
                        assignmentPolicyId = $autoPolicy.id
                        accessPackageId    = $AccessPackageId
                    }
                } | ConvertTo-Json -Depth 5) | Out-Null
        }
    }

    foreach ($assignment in ($assignments | Where-Object { $_.target.objectId -in $toRemove })) {
        if ($PSCmdlet.ShouldProcess($assignment.target.objectId, "adminRemove from access package $AccessPackageId")) {
            Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentRequests" `
                -Body (@{
                    requestType              = 'adminRemove'
                    accessPackageAssignmentId = $assignment.id
                } | ConvertTo-Json -Depth 3) | Out-Null
        }
    }
}
