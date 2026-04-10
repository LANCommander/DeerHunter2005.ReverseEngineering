@{
    RootModule        = 'DH2005Settings.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3f7c8e1-5d42-4b9a-8e6f-1c2d3e4f5a6b'
    Author            = 'Pat'
    Description       = 'Read, write, and manipulate Deer Hunter 2005 Settings.cfg files'
    FunctionsToExport = @(
        'Read-DH2005Settings'
        'Write-DH2005Settings'
        'New-DH2005Settings'
        'Show-DH2005Settings'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
}
