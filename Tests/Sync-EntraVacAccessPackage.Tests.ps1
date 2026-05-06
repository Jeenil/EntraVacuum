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

Describe 'Sync-EntraVacAccessPackage' {
    Context 'when no auto-assignment policy exists' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }

        It 'writes a warning and returns' {
            Sync-EntraVacAccessPackage -AccessPackageId 'fake-id' -WarningAction SilentlyContinue -WarningVariable warnings
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when the auto-assignment policy is inactive' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @($script:InactivePolicy) }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }

        It 'writes a warning and returns' {
            Sync-EntraVacAccessPackage -AccessPackageId 'fake-id' -WarningAction SilentlyContinue -WarningVariable warnings
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'when more than one active auto-assignment policy exists' {
        BeforeEach {
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @($script:ActivePolicy, $script:ActivePolicy) }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }

        It 'writes an error and returns' {
            $null = Sync-EntraVacAccessPackage -AccessPackageId 'fake-id' -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable testErrors
            $testErrors | Should -Not -BeNullOrEmpty
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

        It 'writes a warning and returns' {
            Sync-EntraVacAccessPackage -AccessPackageId 'fake-id' -WarningAction SilentlyContinue -WarningVariable warnings
            $warnings | Should -Not -BeNullOrEmpty
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

        It 'writes a warning and returns without making changes' {
            Sync-EntraVacAccessPackage -AccessPackageId 'fake-id' -WarningAction SilentlyContinue -WarningVariable warnings
            $warnings | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName EntraVacuum Invoke-MgGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
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
                    @{ id = 'assign-b'; state = 'Delivered'; assignmentPolicyId = 'policy-active-id'; target = @{ objectId = 'user-b' } }
                )}
            } -ParameterFilter { $Uri -like '*assignments*' }

            # user-a and user-c match the filter; user-b does not
            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {
                @{ value = @(
                    @{ id = 'user-a'; userPrincipalName = 'a@example.com' }
                    @{ id = 'user-c'; userPrincipalName = 'c@example.com' }
                )}
            } -ParameterFilter { $Uri -like '*users*' }

            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {} -ParameterFilter { $Method -eq 'POST' }
        }

        It 'adminAdds missing users and adminRemoves stale assignments' {
            Sync-EntraVacAccessPackage -AccessPackageId 'fake-id'

            # user-a and user-c should be added (2 POSTs for adminAdd)
            Should -Invoke -ModuleName EntraVacuum Invoke-MgGraphRequest -Times 2 -ParameterFilter {
                $Method -eq 'POST' -and ($Body | ConvertFrom-Json).requestType -eq 'adminAdd'
            }
            # user-b assignment should be removed (1 POST for adminRemove)
            Should -Invoke -ModuleName EntraVacuum Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and ($Body | ConvertFrom-Json).requestType -eq 'adminRemove'
            }
        }
    }

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
                    @{ id = 'user-a'; userPrincipalName = 'a@example.com' }
                )}
            } -ParameterFilter { $Uri -like '*users*' }

            Mock -ModuleName EntraVacuum Invoke-MgGraphRequest {} -ParameterFilter { $Method -eq 'POST' }
        }

        It 'reprocesses the PartiallyDelivered assignment instead of removing and re-adding' {
            Sync-EntraVacAccessPackage -AccessPackageId 'fake-id'

            Should -Invoke -ModuleName EntraVacuum Invoke-MgGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -like '*/reprocess'
            }
            Should -Invoke -ModuleName EntraVacuum Invoke-MgGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'POST' -and $Uri -notlike '*/reprocess'
            }
        }
    }
}
