BeforeAll {
    Import-Module "$PSScriptRoot/../EntraVacuum/EntraVacuum.psd1" -Force
}

Describe 'Sync-EVAccessPackage' {
    Context 'when no auto-assignment policy exists' {
        BeforeEach {
            Mock Invoke-MgGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }

        It 'writes a warning and returns' {
            { Sync-EVAccessPackage -AccessPackageId 'fake-id' -WarningAction SilentlyContinue } |
                Should -Not -Throw
        }
    }
}

Describe 'Get-EVAccessPackageDrift' {
    Context 'when no auto-assignment policy exists' {
        BeforeEach {
            Mock Invoke-MgGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }

        It 'writes a warning and returns null' {
            $result = Get-EVAccessPackageDrift -AccessPackageId 'fake-id' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'Convert-PolicyFilterToGraphFilter (private)' {
    It 'strips user. prefix and converts -eq to eq' {
        InModuleScope EntraVacuum {
            $result = Convert-PolicyFilterToGraphFilter -PolicyFilter 'user.department -eq "Marketing"'
            $result | Should -Be "department eq 'Marketing'"
        }
    }

    It 'handles -and correctly' {
        InModuleScope EntraVacuum {
            $result = Convert-PolicyFilterToGraphFilter -PolicyFilter 'user.department -eq "HR" -and user.accountEnabled -eq "true"'
            $result | Should -Be "department eq 'HR' and accountEnabled eq 'true'"
        }
    }

    It 'returns null for empty filter' {
        InModuleScope EntraVacuum {
            $result = Convert-PolicyFilterToGraphFilter -PolicyFilter ''
            $result | Should -BeNullOrEmpty
        }
    }
}
