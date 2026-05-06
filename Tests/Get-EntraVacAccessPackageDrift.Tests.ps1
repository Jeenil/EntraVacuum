BeforeAll {
    Import-Module "$PSScriptRoot/../EntraVacuum/EntraVacuum.psd1" -Force

    $script:ActivePolicy = @{
        id                       = 'policy-active-id'
        automaticRequestSettings = @{
            requestAccessForAllowedTargets             = $true
            gracePeriodBeforeAccessRemoval             = 'P7D'
            removeAccessWhenTargetLeavesAllowedTargets = $true
        }
        specificAllowedTargets   = @(
            @{
                '@odata.type'  = '#microsoft.graph.attributeRuleMembers'
                membershipRule = 'user.department -eq "Engineering"'
            }
        )
    }

    $script:InactivePolicy = @{
        id                       = 'policy-inactive-id'
        automaticRequestSettings = @{
            requestAccessForAllowedTargets = $false
        }
        specificAllowedTargets   = @()
    }

    $script:DummyPolicy = @{
        id                       = 'policy-dummy-id'
        automaticRequestSettings = @{
            requestAccessForAllowedTargets = $true
        }
        specificAllowedTargets   = @()
    }
}

Describe 'Get-EntraVacAccessPackageDrift' {
    Context 'when no auto-assignment policy exists' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }

        It 'writes a warning and returns null' {
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when the auto-assignment policy is inactive' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @($script:InactivePolicy) }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }

        It 'writes a warning and returns null' {
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when more than one active auto-assignment policy exists' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @($script:ActivePolicy, $script:ActivePolicy) }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }

        It 'writes an error and returns null' {
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue 2>$null
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when the active policy has no membershipRule' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @($script:DummyPolicy) }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }

            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignments*' }
        }

        It 'writes a warning and returns null' {
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when the membershipRule returns no users' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @($script:ActivePolicy) }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }

            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignments*' }

            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -like '*users*' }
        }

        It 'writes a warning and returns null' {
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }

    Context 'when there is drift' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @($script:ActivePolicy) }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }

            # user-b is assigned but no longer matches the filter
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @(
                    @{ id = 'assign-b'; assignmentPolicyId = 'policy-active-id'; target = @{ objectId = 'user-b'; displayName = 'User B' } }
                )}
            } -ParameterFilter { $Uri -like '*assignments*' }

            # user-a and user-c match the filter; user-b does not
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @(
                    @{ id = 'user-a'; displayName = 'User A'; userPrincipalName = 'a@contoso.com' }
                    @{ id = 'user-c'; displayName = 'User C'; userPrincipalName = 'c@contoso.com' }
                )}
            } -ParameterFilter { $Uri -like '*users*' }
        }

        It 'reports users that should be added' {
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id'
            $result.ShouldAdd | Should -HaveCount 2
            $result.ShouldAdd.id | Should -Contain 'user-a'
            $result.ShouldAdd.id | Should -Contain 'user-c'
        }

        It 'reports assignments that should be removed' {
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id'
            $result.ShouldRemove | Should -HaveCount 1
            $result.ShouldRemove.objectId | Should -Contain 'user-b'
        }
    }
}
