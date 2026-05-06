function Sync-EntraVacAccessPackage {
    <#
    .SYNOPSIS
        Syncs membership for an Entra ID access package based on its auto-assignment policy filter.

    .DESCRIPTION
        Reads the active auto-assignment policy's membershipRule for the given access package,
        evaluates it against all users in the tenant, and performs adminAdd/reprocess/adminRemove
        to reconcile actual assignments.

        Assignment states handled:
          Delivered         - user in target: keep. Not in target: adminRemove.
          PartiallyDelivered - user in target: reprocess. Not in target: adminRemove.

        Microsoft only permits one auto-assignment policy per access package. If more than one
        active policy is detected this indicates a misconfiguration and an error is emitted.
        Ref: https://learn.microsoft.com/en-us/entra/id-governance/entitlement-management-access-package-auto-assignment-policy

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

    # Get all policies for this package
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

    # Get Delivered and PartiallyDelivered assignments.
    # PartiallyDelivered = provisioning started but at least one resource role failed.
    # Ref: https://learn.microsoft.com/en-us/graph/api/entitlementmanagement-list-assignments?view=graph-rest-1.0
    $assignments = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq '$AccessPackageId' and (state eq 'Delivered' or state eq 'PartiallyDelivered')&`$expand=target" |
        Select-Object -ExpandProperty value

    $partialAssignments = $assignments | Where-Object { $_.state -eq 'PartiallyDelivered' }
    $assignedUserIds    = $assignments | ForEach-Object { $_.target.objectId }

    # Translate the active policy membershipRule to a Graph OData filter and fetch target users
    # Ref: https://learn.microsoft.com/en-us/graph/api/user-list?view=graph-rest-1.0
    $membershipRule = $activePolicy.specificAllowedTargets |
        Where-Object { $_.'@odata.type' -eq '#microsoft.graph.attributeRuleMembers' } |
        Select-Object -First 1 -ExpandProperty membershipRule

    if ([string]::IsNullOrWhiteSpace($membershipRule)) {
        Write-Warning "The auto-assignment policy for access package $AccessPackageId has no membershipRule. Skipping to avoid unintended removals."
        return
    }

    # ConsistencyLevel + $count=true required for advanced filter properties such as
    # onPremisesExtensionAttributes. Safe to use for all filter expressions.
    # Ref: https://learn.microsoft.com/en-us/graph/aad-advanced-queries?tabs=http
    $graphFilter = Convert-PolicyFilterToGraphFilter -PolicyFilter $membershipRule
    $targetUsers = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/users?`$filter=$graphFilter&`$select=id,displayName,userPrincipalName&`$count=true" `
        -Headers @{ ConsistencyLevel = 'eventual' } |
        Select-Object -ExpandProperty value

    if (-not $targetUsers) {
        Write-Warning "The membershipRule for access package $AccessPackageId returned no users. Skipping to avoid unintended removals."
        return
    }

    $targetUserIds = $targetUsers | ForEach-Object { $_.id }
    $targetUserMap = @{}
    foreach ($u in $targetUsers) { $targetUserMap[$u.id] = $u }

    $toAdd       = $targetUserIds | Where-Object { $_ -notin $assignedUserIds }
    $toReprocess = $partialAssignments | Where-Object { $_.target.objectId -in $targetUserIds }
    $toRemove    = $assignments | Where-Object { $_.target.objectId -notin $targetUserIds }

    Write-Verbose "Access package $AccessPackageId - adding $($toAdd.Count), reprocessing $($toReprocess.Count), removing $($toRemove.Count)"

    # Ref: https://learn.microsoft.com/en-us/graph/api/entitlementmanagement-post-assignmentrequests?view=graph-rest-1.0
    foreach ($userId in $toAdd) {
        $upn = $targetUserMap[$userId].userPrincipalName
        if ($PSCmdlet.ShouldProcess("$upn ($userId)", "adminAdd to access package $AccessPackageId")) {
            Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentRequests" `
                -Body (@{
                    requestType             = 'adminAdd'
                    accessPackageAssignment = @{
                        targetId           = $userId
                        assignmentPolicyId = $activePolicy.id
                        accessPackageId    = $AccessPackageId
                    }
                } | ConvertTo-Json -Depth 5) | Out-Null
        }
    }

    # Reprocess PartiallyDelivered assignments where the user still belongs.
    # Ref: https://learn.microsoft.com/en-us/graph/api/accesspackageassignment-reprocess?view=graph-rest-1.0
    foreach ($assignment in $toReprocess) {
        $upn = $assignment.target.displayName ?? $assignment.target.objectId
        if ($PSCmdlet.ShouldProcess("$upn ($($assignment.target.objectId))", "reprocess PartiallyDelivered assignment in access package $AccessPackageId")) {
            Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignments/$($assignment.id)/reprocess" | Out-Null
        }
    }

    foreach ($assignment in $toRemove) {
        $upn = $assignment.target.displayName ?? $assignment.target.objectId
        if ($PSCmdlet.ShouldProcess("$upn ($($assignment.target.objectId))", "adminRemove from access package $AccessPackageId")) {
            Invoke-MgGraphRequest -Method POST `
                -Uri "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignmentRequests" `
                -Body (@{
                    requestType               = 'adminRemove'
                    accessPackageAssignmentId = $assignment.id
                } | ConvertTo-Json -Depth 3) | Out-Null
        }
    }
}
