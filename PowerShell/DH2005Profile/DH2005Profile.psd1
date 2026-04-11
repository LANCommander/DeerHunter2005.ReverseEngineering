@{
    RootModule        = 'DH2005Profile.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b7e3f4a1-8c2d-4e6f-9a1b-3d5c7e9f0a2b'
    Author            = 'Reverse-engineered from DH2005.exe'
    Description       = 'Read and write Deer Hunter 2005 .pro profile files (LCG-XOR encrypted save games).'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Read-DH2005Profile', 'Write-DH2005Profile')
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData        = @{ PSData = @{
        Tags       = @('DeerHunter', 'GameModding', 'ReverseEngineering')
        ProjectUri = $null
    }}
}
