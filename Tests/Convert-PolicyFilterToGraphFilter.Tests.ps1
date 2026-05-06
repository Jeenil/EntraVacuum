BeforeAll {
    Import-Module "$PSScriptRoot/../EntraVacuum/EntraVacuum.psd1" -Force
}

Describe 'Convert-PolicyFilterToGraphFilter (private)' {
    It 'strips user. prefix and converts -eq to eq' {
        $result = InModuleScope EntraVacuum { Convert-PolicyFilterToGraphFilter -PolicyFilter 'user.department -eq "Engineering"' }
        $result | Should -Be "department eq 'Engineering'"
    }

    It 'handles -and correctly' {
        $result = InModuleScope EntraVacuum { Convert-PolicyFilterToGraphFilter -PolicyFilter 'user.department -eq "Eng" -and user.country -eq "CA"' }
        $result | Should -Be "department eq 'Eng' and country eq 'CA'"
    }

    It 'maps extensionAttribute to onPremisesExtensionAttributes' {
        $result = InModuleScope EntraVacuum { Convert-PolicyFilterToGraphFilter -PolicyFilter 'user.extensionAttribute1 -eq "Contractor"' }
        $result | Should -Be "onPremisesExtensionAttributes/extensionAttribute1 eq 'Contractor'"
    }

    It 'returns null for empty filter' {
        $result = InModuleScope EntraVacuum { Convert-PolicyFilterToGraphFilter -PolicyFilter '' }
        $result | Should -BeNullOrEmpty
    }
}
