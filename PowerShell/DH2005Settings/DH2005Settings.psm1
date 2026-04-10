Set-StrictMode -Version Latest

# --- Constants ---

$script:FIELD_COUNT = 31
$script:FILE_SIZE   = 2 + $script:FIELD_COUNT * 4

$script:FieldNames = @(
    "Video HRes"          # 0
    "Video VRes"          # 1
    "Video Bits"          # 2
    "Texture Detail"      # 3
    "Texture Filtering"   # 4
    "Texture Bits"        # 5
    "Compress Textures"   # 6
    "Shadows Quality"     # 7
    "FSAA"                # 8
    "Reflections"         # 9
    "Water Reflection"    # 10
    "VSync"               # 11
    "Gamma"               # 12
    "Draw Background"     # 13
    "Terrain Detail"      # 14
    "Sky Quality"         # 15
    "Weather FX"          # 16
    "Day/Night FX"        # 17
    "Ground Objects"      # 18
    "Bending Grass"       # 19
    "Max View Distance"   # 20
    "Trees Density"       # 21
    "Models Detail"       # 22
    "Morph Targets"       # 23
    "Audio Quality"       # 24
    "Master Vol"          # 25
    "Wind Vol"            # 26
    "Environment Vol"     # 27
    "Music Vol"           # 28
    "Interface Vol"       # 29
    "Distance Unit"       # 30
)

# Presets: each row = [Low, Medium, High, Ultra]
$script:Presets = @(
    ,@(640, 800, 1024, 1280)   # Video HRes
    ,@(480, 600,  768,  960)   # Video VRes
    ,@( 16,  16,   32,   32)   # Video Bits
    ,@(  0,   1,    2,    3)   # Texture Detail
    ,@(  0,   0,    1,    2)   # Texture Filtering
    ,@( 16,  16,   16,   32)   # Texture Bits
    ,@(  1,   1,    1,    1)   # Compress Textures
    ,@(  0,   1,    2,    3)   # Shadows Quality
    ,@(  0,   0,    0,    1)   # FSAA
    ,@(  0,   1,    1,    1)   # Reflections
    ,@(  0,   1,    2,    2)   # Water Reflection
    ,@(  0,   0,    0,    1)   # VSync
    ,@( 50,  50,   50,   50)   # Gamma
    ,@(  0,   1,    1,    1)   # Draw Background
    ,@(  0,   1,    2,    3)   # Terrain Detail
    ,@(  0,   1,    2,    3)   # Sky Quality
    ,@(  0,   1,    2,    3)   # Weather FX
    ,@(  0,   1,    2,    3)   # Day/Night FX
    ,@(  0,   1,    2,    3)   # Ground Objects
    ,@(  0,   0,    1,    1)   # Bending Grass
    ,@(  0,  50,  100,  100)   # Max View Distance
    ,@(  0,  50,  100,  100)   # Trees Density
    ,@(  0,   1,    2,    3)   # Models Detail
    ,@(  0,   1,    1,    1)   # Morph Targets
    ,@(  0,   1,    2,    3)   # Audio Quality
    ,@(100, 100,  100,  100)   # Master Vol
    ,@(100, 100,  100,  100)   # Wind Vol
    ,@(100, 100,  100,  100)   # Environment Vol
    ,@(100, 100,  100,  100)   # Music Vol
    ,@(100, 100,  100,  100)   # Interface Vol
    ,@(  2,   2,    2,    2)   # Distance Unit
)

# --- Enum-like lookup tables ---

$script:TextureFilteringNames = @{ 0="Bilinear"; 1="Trilinear"; 2="Anisotropic" }
$script:DistanceUnitNames     = @{ 0="Feet"; 1="Meters"; 2="Yards" }
$script:WaterReflectionNames  = @{ 0="Off"; 1="Low"; 2="High" }
$script:Quality4Names         = @{ 0="Low"; 1="Medium"; 2="High"; 3="Ultra" }
$script:BoolNames             = @{ 0="Off"; 1="On" }

$script:Quality4Fields = @(
    "Texture Detail","Shadows Quality","Terrain Detail",
    "Sky Quality","Weather FX","Day/Night FX",
    "Ground Objects","Models Detail","Audio Quality"
)
$script:BoolFields = @(
    "Compress Textures","FSAA","Reflections","VSync",
    "Draw Background","Bending Grass","Morph Targets"
)

# --- Internal helpers ---

function Format-FieldValue {
    param([int]$Index, [int]$Value)
    $name = $script:FieldNames[$Index]

    switch ($name) {
        "Texture Filtering" {
            if ($script:TextureFilteringNames.ContainsKey($Value)) { return $script:TextureFilteringNames[$Value] }
            return "? ($Value)"
        }
        "Distance Unit" {
            if ($script:DistanceUnitNames.ContainsKey($Value)) { return $script:DistanceUnitNames[$Value] }
            return "? ($Value)"
        }
        "Water Reflection" {
            if ($script:WaterReflectionNames.ContainsKey($Value)) { return $script:WaterReflectionNames[$Value] }
            return "? ($Value)"
        }
    }

    if ($script:Quality4Fields -contains $name) {
        if ($script:Quality4Names.ContainsKey($Value)) { return $script:Quality4Names[$Value] }
        return "? ($Value)"
    }

    if ($script:BoolFields -contains $name) {
        if ($script:BoolNames.ContainsKey($Value)) { return $script:BoolNames[$Value] }
        return "? ($Value)"
    }

    return "$Value"
}

function ConvertTo-SettingsObject {
    param([int[]]$Values)

    $resolution = [PSCustomObject]@{
        PSTypeName = 'DH2005.Settings.Resolution'
        Horizontal = $Values[0]
        Vertical   = $Values[1]
        BitDepth   = $Values[2]
    }

    $texture = [PSCustomObject]@{
        PSTypeName = 'DH2005.Settings.Texture'
        Detail     = $Values[3]
        Filtering  = $Values[4]
        BitDepth   = $Values[5]
        Compress   = [bool]$Values[6]
    }

    $video = [PSCustomObject]@{
        PSTypeName      = 'DH2005.Settings.Video'
        Resolution      = $resolution
        Texture         = $texture
        ShadowsQuality  = $Values[7]
        FSAA            = [bool]$Values[8]
        Reflections     = [bool]$Values[9]
        WaterReflection = $Values[10]
        VSync           = [bool]$Values[11]
        Gamma           = $Values[12]
        DrawBackground  = [bool]$Values[13]
        TerrainDetail   = $Values[14]
        SkyQuality      = $Values[15]
        WeatherFX       = $Values[16]
        DayNightFX      = $Values[17]
        GroundObjects   = $Values[18]
        BendingGrass    = [bool]$Values[19]
        MaxViewDistance  = $Values[20]
        TreesDensity    = $Values[21]
        ModelsDetail    = $Values[22]
        MorphTargets    = [bool]$Values[23]
    }

    $audio = [PSCustomObject]@{
        PSTypeName        = 'DH2005.Settings.Audio'
        Quality           = $Values[24]
        MasterVolume      = $Values[25]
        WindVolume         = $Values[26]
        EnvironmentVolume = $Values[27]
        MusicVolume       = $Values[28]
        InterfaceVolume   = $Values[29]
    }

    $general = [PSCustomObject]@{
        PSTypeName   = 'DH2005.Settings.General'
        DistanceUnit = $Values[30]
    }

    return [PSCustomObject]@{
        PSTypeName = 'DH2005.Settings'
        Video      = $video
        Audio      = $audio
        General    = $general
    }
}

function ConvertFrom-SettingsObject {
    param([PSCustomObject]$Settings)

    $v = $Settings.Video
    $a = $Settings.Audio

    return [int[]]@(
        $v.Resolution.Horizontal   # 0
        $v.Resolution.Vertical     # 1
        $v.Resolution.BitDepth     # 2
        $v.Texture.Detail          # 3
        $v.Texture.Filtering       # 4
        $v.Texture.BitDepth        # 5
        [int]$v.Texture.Compress   # 6
        $v.ShadowsQuality          # 7
        [int]$v.FSAA               # 8
        [int]$v.Reflections        # 9
        $v.WaterReflection         # 10
        [int]$v.VSync              # 11
        $v.Gamma                   # 12
        [int]$v.DrawBackground     # 13
        $v.TerrainDetail           # 14
        $v.SkyQuality              # 15
        $v.WeatherFX               # 16
        $v.DayNightFX              # 17
        $v.GroundObjects           # 18
        [int]$v.BendingGrass       # 19
        $v.MaxViewDistance          # 20
        $v.TreesDensity            # 21
        $v.ModelsDetail            # 22
        [int]$v.MorphTargets       # 23
        $a.Quality                 # 24
        $a.MasterVolume            # 25
        $a.WindVolume              # 26
        $a.EnvironmentVolume       # 27
        $a.MusicVolume             # 28
        $a.InterfaceVolume         # 29
        $Settings.General.DistanceUnit  # 30
    )
}

function Get-PresetValues {
    param([string]$Level)
    $map = @{ "low"=0; "medium"=1; "high"=2; "ultra"=3 }
    $q = $map[$Level.ToLower()]
    if ($null -eq $q) {
        throw "Unknown preset: $Level. Use: Low, Medium, High, Ultra"
    }
    $values = [int[]]::new($script:FIELD_COUNT)
    for ($i = 0; $i -lt $script:FIELD_COUNT; $i++) {
        $values[$i] = $script:Presets[$i][$q]
    }
    return ,$values
}

function Get-DetectedPreset {
    param([int[]]$Values)
    $names = @("Low","Medium","High","Ultra")
    for ($q = 0; $q -lt 4; $q++) {
        $match = $true
        for ($i = 0; $i -lt $script:FIELD_COUNT; $i++) {
            if ($script:Presets[$i][$q] -ne $Values[$i]) {
                $match = $false
                break
            }
        }
        if ($match) { return $names[$q] }
    }
    return $null
}

# --- Exported functions ---

function Read-DH2005Settings {
    <#
    .SYNOPSIS
        Reads a Deer Hunter 2005 Settings.cfg file and returns a settings object.
    .DESCRIPTION
        Parses the binary Settings.cfg file (126 bytes: version byte, count byte,
        31 little-endian int32 values) and returns a structured PSCustomObject with
        Video, Audio, and General sub-objects.
    .PARAMETER Path
        Path to the Settings.cfg file.
    .EXAMPLE
        $s = Read-DH2005Settings Settings.cfg
        $s.Video.Resolution.Horizontal   # 1024
        $s.Audio.MasterVolume            # 100
    .EXAMPLE
        $s = Read-DH2005Settings Settings.cfg
        $s.Video.Resolution.Horizontal = 1920
        $s.Video.Resolution.Vertical = 1080
        $s | Write-DH2005Settings -Path Settings.cfg
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Path
    )

    $resolvedPath = Resolve-Path $Path -ErrorAction Stop
    $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)

    if ($bytes.Length -ne $script:FILE_SIZE) {
        Write-Warning "Expected $($script:FILE_SIZE) bytes, got $($bytes.Length)"
    }
    if ($bytes[0] -ne 0x01) {
        Write-Warning ("Version byte = 0x{0:X2}, expected 0x01" -f $bytes[0])
    }
    if ($bytes[1] -ne $script:FIELD_COUNT) {
        Write-Warning "Field count = $($bytes[1]), expected $($script:FIELD_COUNT)"
    }

    $values = [int[]]::new($script:FIELD_COUNT)
    for ($i = 0; $i -lt $script:FIELD_COUNT; $i++) {
        $values[$i] = [BitConverter]::ToInt32($bytes, 2 + $i * 4)
    }

    return ConvertTo-SettingsObject $values
}

function Write-DH2005Settings {
    <#
    .SYNOPSIS
        Writes a settings object to a Deer Hunter 2005 Settings.cfg file.
    .DESCRIPTION
        Serializes the structured settings object back to the 126-byte binary format.
    .PARAMETER Path
        Output file path.
    .PARAMETER Settings
        The settings object (from Read-DH2005Settings or New-DH2005Settings).
        Also accepts pipeline input.
    .EXAMPLE
        $s = Read-DH2005Settings Settings.cfg
        $s.Video.Resolution.Horizontal = 1920
        Write-DH2005Settings -Path Settings.cfg -Settings $s
    .EXAMPLE
        $s | Write-DH2005Settings -Path Settings.cfg
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$Path,

        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Settings
    )

    $values = ConvertFrom-SettingsObject $Settings

    $bytes = [byte[]]::new($script:FILE_SIZE)
    $bytes[0] = 0x01
    $bytes[1] = [byte]$script:FIELD_COUNT
    for ($i = 0; $i -lt $script:FIELD_COUNT; $i++) {
        $le = [BitConverter]::GetBytes([int]$values[$i])
        [Array]::Copy($le, 0, $bytes, 2 + $i * 4, 4)
    }
    [System.IO.File]::WriteAllBytes($Path, $bytes)
    Write-Verbose "Wrote $($script:FILE_SIZE) bytes to $Path"
}

function New-DH2005Settings {
    <#
    .SYNOPSIS
        Creates a new settings object from a quality preset.
    .DESCRIPTION
        Returns a settings object initialized to one of the built-in presets.
    .PARAMETER Preset
        Quality preset: Low, Medium, High, or Ultra. Defaults to High.
    .EXAMPLE
        $s = New-DH2005Settings -Preset Ultra
        $s | Write-DH2005Settings -Path Settings.cfg
    .EXAMPLE
        New-DH2005Settings High | Write-DH2005Settings Settings.cfg
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [ValidateSet("Low","Medium","High","Ultra")]
        [string]$Preset = "High"
    )

    $values = Get-PresetValues $Preset
    return ConvertTo-SettingsObject $values
}

function Show-DH2005Settings {
    <#
    .SYNOPSIS
        Displays a formatted table of settings values.
    .DESCRIPTION
        Prints all 31 fields with index, name, raw value, and human-readable description.
        Also detects if the settings match a known preset.
    .PARAMETER Settings
        The settings object to display. Accepts pipeline input.
    .EXAMPLE
        Read-DH2005Settings Settings.cfg | Show-DH2005Settings
    .EXAMPLE
        Show-DH2005Settings (New-DH2005Settings Ultra)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline)]
        [PSCustomObject]$Settings
    )

    $values = ConvertFrom-SettingsObject $Settings
    $preset = Get-DetectedPreset $values

    if ($preset) { Write-Host "Detected preset: $preset`n" }
    Write-Host ("{0,-4} {1,-24} {2,8}  {3}" -f "#","Field","Value","Description")
    Write-Host ("-" * 70)
    for ($i = 0; $i -lt $script:FIELD_COUNT; $i++) {
        $desc = Format-FieldValue $i $values[$i]
        Write-Host ("{0,-4} {1,-24} {2,8}  {3}" -f $i, $script:FieldNames[$i], $values[$i], $desc)
    }
}

Export-ModuleMember -Function Read-DH2005Settings, Write-DH2005Settings, New-DH2005Settings, Show-DH2005Settings
