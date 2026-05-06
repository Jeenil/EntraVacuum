BeforeAll {
    Import-Module "$PSScriptRoot/../EntraVacuum/EntraVacuum.psd1" -Force
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

    It 'maps extensionAttribute to onPremisesExtensionAttributes' {
        InModuleScope EntraVacuum {
            $result = Convert-PolicyFilterToGraphFilter -PolicyFilter '(user.department -eq "Brand Identity") or (user.extensionAttribute1 -eq "441000")'
            $result | Should -Be "(department eq 'Brand Identity') or (onPremisesExtensionAttributes/extensionAttribute1 eq '441000')"
        }
    }

    It 'returns null for empty filter' {
        InModuleScope EntraVacuum {
            $result = Convert-PolicyFilterToGraphFilter -PolicyFilter ''
            $result | Should -BeNullOrEmpty
        }
    }
}
