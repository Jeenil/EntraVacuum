BeforeAll {
    Import-Module "$PSScriptRoot/../EntraVacuum/EntraVacuum.psd1" -Force

    # Reusable policy stubs
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
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue -WarningVariable warnings
            $warnings | Should -Not -BeNullOrEmpty
            $result   | Should -BeNullOrEmpty
        }
    }

    Context 'when the auto-assignment policy is inactive' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @($script:InactivePolicy) }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }

        It 'writes a warning and returns null' {
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue -WarningVariable warnings
            $warnings | Should -Not -BeNullOrEmpty
            $result   | Should -BeNullOrEmpty
        }
    }

    Context 'when more than one active auto-assignment policy exists' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @($script:ActivePolicy, $script:ActivePolicy) }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }

        It 'writes an error and returns null' {
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue 2>&1
            $result | Should -Not -BeNullOrEmpty
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
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue -WarningVariable warnings
            $warnings | Should -Not -BeNullOrEmpty
            $result   | Should -BeNullOrEmpty
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
            $result = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue -WarningVariable warnings
            $warnings | Should -Not -BeNullOrEmpty
            $result   | Should -BeNullOrEmpty
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
                    @{ id = 'assign-b'; state = 'Delivered'; target = @{ objectId = 'user-b' } }
                )}
            } -ParameterFilter { $Uri -like '*assignments*' }

            # user-a and user-c match the filter; user-b does not
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @(
                    @{ id = 'user-a'; displayName = 'User A'; userPrincipalName = 'a@example.com' }
                    @{ id = 'user-c'; displayName = 'User C'; userPrincipalName = 'c@example.com' }
                )}
            } -ParameterFilter { $Uri -like '*users*' }
        }

        It 'reports users that should be added' {
            $drift = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id'
            ($drift.ShouldAdd | Measure-Object).Count | Should -Be 2
        }

        It 'reports assignments that should be removed' {
            $drift = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id'
            $drift.ShouldRemove.objectId | Should -Contain 'user-b'
        }
    }
<<<<<<< HEAD
=======

    Context 'when a PartiallyDelivered assignment exists for a user still in target' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @($script:ActivePolicy) }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }

            # user-a has a PartiallyDelivered assignment and still matches the filter
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @(
                    @{ id = 'assign-a'; state = 'PartiallyDelivered'; target = @{ objectId = 'user-a'; displayName = 'User A' } }
                )}
            } -ParameterFilter { $Uri -like '*assignments*' }

            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @(
                    @{ id = 'user-a'; displayName = 'User A'; userPrincipalName = 'a@example.com' }
                )}
            } -ParameterFilter { $Uri -like '*users*' }
        }

        It 'reports the assignment in ShouldReprocess not ShouldAdd or ShouldRemove' {
            $drift = Get-EntraVacAccessPackageDrift -AccessPackageId 'fake-id'
            ($drift.ShouldReprocess | Measure-Object).Count | Should -Be 1
            ($drift.ShouldAdd       | Measure-Object).Count | Should -Be 0
            ($drift.ShouldRemove    | Measure-Object).Count | Should -Be 0
        }
    }
>>>>>>> 9a51128 (chore: squashed 2 commits)
}
