Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  Internal: LCG XOR cipher (symmetric — same function encrypts and decrypts)
# ---------------------------------------------------------------------------
function Invoke-LcgCipher {
    [CmdletBinding()]
    param([byte[]] $Bytes)

    $len = $Bytes.Length
    [long] $state = ([long]$len * 7L + 0x4A0C70CL) -band 0xFFFFFFFFL
    [byte[]] $out = [byte[]]::new($len)

    for ($i = 0; $i -lt $len; $i++) {
        [long] $lo = $state -band 0xFFFFL
        [long] $hi = [int]([uint32]$state) -shr 16
        if (($state -band 0x80000000L) -ne 0) { $hi = $hi - 0x10000L }
        $state = ($lo * 0x6054L + $hi) -band 0xFFFFFFFFL
        $out[$i] = [byte]($Bytes[$i] -bxor ($state -band 0xFFL))
    }
    return , $out
}

# ---------------------------------------------------------------------------
#  Internal: Read a length-prefixed string (1-byte length, then N chars)
# ---------------------------------------------------------------------------
function Read-PString {
    [CmdletBinding()]
    param([byte[]] $Data, [ref] $Pos)

    $len = $Data[$Pos.Value]; $Pos.Value++
    if ($len -eq 0) { return '' }
    $str = [System.Text.Encoding]::GetEncoding(1252).GetString($Data, $Pos.Value, $len)
    $Pos.Value += $len
    return $str
}

# ---------------------------------------------------------------------------
#  Internal: Write a length-prefixed string to a stream
# ---------------------------------------------------------------------------
function Write-PString {
    [CmdletBinding()]
    param([System.IO.Stream] $Stream, [string] $Value)

    $bytes = [System.Text.Encoding]::GetEncoding(1252).GetBytes($Value)
    $Stream.WriteByte([byte]$bytes.Length)
    if ($bytes.Length -gt 0) { $Stream.Write($bytes, 0, $bytes.Length) }
}

# ---------------------------------------------------------------------------
#  Internal: helpers for reading binary primitives
# ---------------------------------------------------------------------------
function Read-Byte   { param([byte[]]$D,[ref]$P) $v = $D[$P.Value]; $P.Value++; $v }
function Read-UInt16 { param([byte[]]$D,[ref]$P) $v = [BitConverter]::ToUInt16($D,$P.Value); $P.Value+=2; $v }
function Read-Int32  { param([byte[]]$D,[ref]$P) $v = [BitConverter]::ToInt32($D,$P.Value);  $P.Value+=4; $v }
function Read-UInt32 { param([byte[]]$D,[ref]$P) $v = [BitConverter]::ToUInt32($D,$P.Value); $P.Value+=4; $v }
function Read-Float  { param([byte[]]$D,[ref]$P) $v = [BitConverter]::ToSingle($D,$P.Value); $P.Value+=4; $v }

# ---------------------------------------------------------------------------
#  Internal: helpers for writing binary primitives to a stream
# ---------------------------------------------------------------------------
function Write-ByteVal   { param([System.IO.Stream]$S,[byte]$V)   $S.WriteByte($V) }
function Write-UInt16Val { param([System.IO.Stream]$S,[uint16]$V) $b=[BitConverter]::GetBytes($V); $S.Write($b,0,2) }
function Write-Int32Val  { param([System.IO.Stream]$S,[int32]$V)  $b=[BitConverter]::GetBytes($V); $S.Write($b,0,4) }
function Write-UInt32Val { param([System.IO.Stream]$S,[uint32]$V) $b=[BitConverter]::GetBytes($V); $S.Write($b,0,4) }
function Write-FloatVal  { param([System.IO.Stream]$S,[float]$V)  $b=[BitConverter]::GetBytes($V); $S.Write($b,0,4) }

# ---------------------------------------------------------------------------
#  Internal: compute the trailing uint32 checksum (sum of all preceding bytes)
# ---------------------------------------------------------------------------
function Get-ProChecksum {
    [CmdletBinding()]
    param([byte[]] $Data, [int] $Count)

    [long] $sum = 0
    for ($i = 0; $i -lt $Count; $i++) { $sum += $Data[$i] }
    return [uint32]($sum -band 0xFFFFFFFFL)
}

# ═══════════════════════════════════════════════════════════════════════════
#  Read-DH2005Profile
# ═══════════════════════════════════════════════════════════════════════════
function Read-DH2005Profile {
    <#
    .SYNOPSIS
        Decrypt and parse a Deer Hunter 2005 .pro profile file.
    .DESCRIPTION
        Reads an XOR-encrypted .pro file, decrypts it using the game's LCG
        cipher, and returns a structured object with all parsed fields plus
        the full decrypted byte array for direct editing.

        The format has two flavors:
          * Simple — fresh profile with one unlocked region and no recorded
            hunt sessions. Weapons and tail data are fully parsed.
          * Advanced — profile with multiple unlocked regions and one or
            more recorded hunt sessions (e.g. DoctorDalek.pro). The hunt
            session records have a variable, partially-decoded layout, so
            everything from the hunt-record count onwards is preserved as
            an opaque AdvancedTail blob.

        Both flavors round-trip byte-for-byte through Write-DH2005Profile.
    .PARAMETER Path
        Path to the encrypted .pro file.
    .OUTPUTS
        PSCustomObject (TypeName: DH2005.Profile)
    .EXAMPLE
        $p = Read-DH2005Profile John.pro
        $p.PlayerName     # "John"
        $p.Hunter         # active hunter model, e.g. "Ben"
        $p.Regions[0]     # first unlocked region
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string] $Path
    )

    process {
        $resolved = (Resolve-Path $Path).Path
        [byte[]] $raw = [System.IO.File]::ReadAllBytes($resolved)
        [byte[]] $dec = Invoke-LcgCipher -Bytes $raw

        # --- Checksum validation ---
        $ckOff    = $dec.Length - 4
        $stored   = [BitConverter]::ToUInt32($dec, $ckOff)
        $computed = Get-ProChecksum $dec $ckOff
        $ckValid  = ($stored -eq $computed)

        # --- Sequential parse ---
        $p = [ref] 0

        # Header
        $version   = Read-Byte    $dec $p
        $gameTitle = Read-PString $dec $p
        $reserved  = Read-UInt32  $dec $p

        # Player (pstringZ — length-prefixed + null terminator)
        $playerName = Read-PString $dec $p
        $p.Value++

        # Money / cumulative score (in fresh profiles this is ~$146.53)
        $money = Read-Float $dec $p

        # Region table: count + N entries.
        # Each entry is a pstring (no null terminator) followed by 8 bytes of
        # per-region data — empirically two float32 progress values.
        $regionCount = Read-UInt32 $dec $p
        $regions = [System.Collections.Generic.List[PSCustomObject]]::new()
        for ($i = 0; $i -lt $regionCount; $i++) {
            $rName = Read-PString $dec $p
            $rData = [byte[]]::new(8)
            [Array]::Copy($dec, $p.Value, $rData, 0, 8)
            $p.Value += 8
            $f1 = [BitConverter]::ToSingle($rData, 0)
            $f2 = [BitConverter]::ToSingle($rData, 4)
            $regions.Add([PSCustomObject]@{
                Name    = $rName
                Float1  = $f1
                Float2  = $f2
                RawData = $rData
            })
        }

        # Post-region block: 1-byte separator + uint32 + 2 bytes.
        # Empirically constant (00 / 250 / 02 / 31) across all observed
        # profiles, but preserved verbatim for round-trip safety.
        $postRegionSep = Read-Byte   $dec $p
        $postRegionU32 = Read-UInt32 $dec $p
        $postRegionB1  = Read-Byte   $dec $p
        $postRegionB2  = Read-Byte   $dec $p

        # Trophy table — fixed at 63 int32 entries in version 10 profiles
        $trophyCnt = 63
        $trophies = [int32[]]::new($trophyCnt)
        for ($i = 0; $i -lt $trophyCnt; $i++) {
            $trophies[$i] = Read-Int32 $dec $p
        }

        # Active hunter (player character model)
        $hunterFlag = Read-Byte    $dec $p
        $hunterName = Read-PString $dec $p
        $p.Value++                              # null terminator

        # Inventory (equipment + hunter skins)
        $itemCount = Read-UInt32 $dec $p
        $inventory = [System.Collections.Generic.List[PSCustomObject]]::new()
        for ($i = 0; $i -lt $itemCount; $i++) {
            $iName   = Read-PString $dec $p
            $iType   = Read-Byte $dec $p        # 0xFF = equipment, 0x00 = hunter skin
            $iStatus = Read-Byte $dec $p        # 0x01 = equipped/active
            $inventory.Add([PSCustomObject]@{
                Name     = $iName
                Type     = if ($iType -eq 0xFF) { 'Equipment' } else { 'Skin' }
                Equipped = ($iStatus -eq 0x01)
            })
        }

        # Hunter attributes: 7 skill bytes + 10 reserved bytes (always zero
        # in observed profiles) + uint32 hunt-record count
        $hunterStats = [byte[]]::new(7)
        [Array]::Copy($dec, $p.Value, $hunterStats, 0, 7)
        $p.Value += 7
        $hunterStatsReserved = [byte[]]::new(10)
        [Array]::Copy($dec, $p.Value, $hunterStatsReserved, 0, 10)
        $p.Value += 10
        $huntRecordCount = Read-UInt32 $dec $p

        # Branching: simple vs. advanced layout
        if ($huntRecordCount -eq 0) {
            # --- Simple profile: weapon section follows immediately ---
            $weaponFlag = Read-Byte  $dec $p
            $weaponZoom = Read-Float $dec $p
            $weaponSep  = Read-Byte  $dec $p

            $weaponCount = Read-UInt32 $dec $p
            $weapons = [System.Collections.Generic.List[PSCustomObject]]::new()
            for ($i = 0; $i -lt $weaponCount; $i++) {
                $wName  = Read-PString $dec $p
                $wValue = Read-Float   $dec $p
                $weapons.Add([PSCustomObject]@{
                    Name  = $wName
                    Value = $wValue
                })
            }

            # Tail: network config + hunt level paths (raw, scanned for strings)
            $tailStart = $p.Value
            $tailLen   = $ckOff - $tailStart
            $tailData  = [byte[]]::new($tailLen)
            [Array]::Copy($dec, $tailStart, $tailData, 0, $tailLen)
            $advancedTail = $null
        }
        else {
            # --- Advanced profile: hunt records have a variable, partially
            #     decoded layout. Preserve everything from this point through
            #     the checksum as an opaque blob.
            $advancedStart = $p.Value
            $advancedLen   = $ckOff - $advancedStart
            $advancedTail  = [byte[]]::new($advancedLen)
            [Array]::Copy($dec, $advancedStart, $advancedTail, 0, $advancedLen)

            $weaponFlag  = $null
            $weaponZoom  = $null
            $weaponSep   = $null
            $weapons     = [System.Collections.Generic.List[PSCustomObject]]::new()
            $tailData    = $advancedTail
        }

        # Scan tail (or advanced blob) for known strings: server IP, server
        # name, hunt-level paths.
        $serverIP   = $null
        $serverName = $null
        $huntPaths  = [System.Collections.Generic.List[string]]::new()
        $scanBuf    = $tailData
        $scanLen    = $scanBuf.Length

        $seenPaths = [System.Collections.Generic.HashSet[string]]::new()
        for ($t = 0; $t -lt $scanLen - 1; $t++) {
            $tLen = $scanBuf[$t]
            if ($tLen -lt 4 -or $tLen -gt 64) { continue }
            if (($t + 1 + $tLen) -gt $scanLen) { continue }
            $candidate = [System.Text.Encoding]::ASCII.GetString($scanBuf, $t + 1, $tLen)
            if ($candidate -notmatch '^[\x20-\x7E]+$') { continue }

            if ($null -eq $serverIP -and $candidate -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?$') {
                $serverIP = $candidate
                continue
            }
            if ($tLen -ge 20 -and $candidate -match '\\[Ll]evels\\.+\.txt$') {
                if ($seenPaths.Add($candidate)) { $huntPaths.Add($candidate) }
                continue
            }
            if ($null -ne $serverIP -and $null -eq $serverName -and
                $tLen -ge 4 -and $tLen -le 32 -and
                $candidate -notmatch '[\\/.]' -and $candidate -match '[A-Za-z]') {
                $serverName = $candidate
                continue
            }
        }

        $obj = [PSCustomObject]@{
            PSTypeName            = 'DH2005.Profile'
            # Header
            Version               = $version
            GameTitle             = $gameTitle
            PlayerName            = $playerName
            # Money / score
            Money                 = $money
            # Regions: array of { Name, Float1, Float2, RawData }
            Regions               = $regions.ToArray()
            # Post-region constants (preserved verbatim)
            PostRegionSep         = $postRegionSep
            PostRegionU32         = $postRegionU32
            PostRegionB1          = $postRegionB1
            PostRegionB2          = $postRegionB2
            # Trophies (always 63 entries in version 10)
            TrophyTable           = $trophies
            # Hunter & inventory
            HunterFlag            = $hunterFlag
            Hunter                = $hunterName
            Inventory             = $inventory.ToArray()
            HunterStats           = $hunterStats
            HunterStatsReserved   = $hunterStatsReserved
            HuntRecordCount       = $huntRecordCount
            IsAdvanced            = ($huntRecordCount -gt 0)
            # Weapons (simple profiles only — $null on advanced profiles)
            WeaponFlag            = $weaponFlag
            WeaponZoom            = $weaponZoom
            WeaponSep             = $weaponSep
            Weapons               = $weapons.ToArray()
            # Network (extracted from tail)
            ServerIP              = $serverIP
            ServerName            = $serverName
            # Hunt records (extracted paths)
            HuntLevelPaths        = $huntPaths.ToArray()
            # Raw payloads
            TailData              = $tailData
            AdvancedTail          = $advancedTail
            DecryptedBytes        = $dec
            ChecksumValid         = $ckValid
            Checksum              = $stored
            SourcePath            = $resolved
        }

        # Skin: live view of the equipped inventory item with Type='Skin'.
        # Getter returns its Name; setter equips that skin (and unequips others).
        Add-Member -InputObject $obj -MemberType ScriptProperty -Name Skin -Value {
            $eq = @($this.Inventory | Where-Object { $_.Type -eq 'Skin' -and $_.Equipped })
            if ($eq.Count -gt 0) { $eq[0].Name } else { $null }
        } -SecondValue {
            $newSkin = $args[0]
            foreach ($item in $this.Inventory) {
                if ($item.Type -eq 'Skin') {
                    $item.Equipped = ($item.Name -eq $newSkin)
                }
            }
        }

        # Region: name of the first (active) region — convenience accessor
        Add-Member -InputObject $obj -MemberType ScriptProperty -Name Region -Value {
            if ($this.Regions.Length -gt 0) { $this.Regions[0].Name } else { $null }
        }

        $obj
    }
}

# ═══════════════════════════════════════════════════════════════════════════
#  Write-DH2005Profile
# ═══════════════════════════════════════════════════════════════════════════
function Write-DH2005Profile {
    <#
    .SYNOPSIS
        Encrypt and write a Deer Hunter 2005 .pro profile file.
    .DESCRIPTION
        Takes a profile object (from Read-DH2005Profile) or raw decrypted
        bytes, recomputes the checksum, then XOR-encrypts and writes the
        result to disk.

        By default the profile is serialized from its parsed fields, which
        allows modifying properties like PlayerName before writing. Use
        -FromBytes to write the DecryptedBytes array directly instead
        (useful when you have modified the raw bytes yourself).

        For advanced profiles, the hunt-record blob is written verbatim
        from AdvancedTail, since its internal structure is not fully
        decoded.
    .PARAMETER Profile
        A profile object returned by Read-DH2005Profile.
    .PARAMETER Path
        Output file path for the encrypted .pro file.
    .PARAMETER Bytes
        Raw decrypted byte array to encrypt and write. Mutually exclusive
        with -Profile.
    .PARAMETER FromBytes
        When used with -Profile, skip serialization and write the profile's
        DecryptedBytes property directly.
    .PARAMETER SkipChecksum
        Suppress automatic checksum recomputation.
    .EXAMPLE
        $p = Read-DH2005Profile John.pro
        $p.PlayerName = 'Alex'
        Write-DH2005Profile $p Alex.pro
    .EXAMPLE
        $p = Read-DH2005Profile DoctorDalek.pro
        $p.PlayerName = 'Doctor'
        Write-DH2005Profile $p Doctor.pro   # round-trips advanced profile
    #>
    [CmdletBinding(DefaultParameterSetName = 'FromProfile')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'FromProfile', ValueFromPipeline)]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'FromProfileRaw', ValueFromPipeline)]
        [PSCustomObject] $Profile,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'FromRawBytes')]
        [byte[]] $Bytes,

        [Parameter(Mandatory, Position = 1)]
        [string] $Path,

        [Parameter(ParameterSetName = 'FromProfileRaw')]
        [switch] $FromBytes,

        [switch] $SkipChecksum
    )

    process {
        # --- Obtain the decrypted byte array ---
        if ($PSCmdlet.ParameterSetName -eq 'FromRawBytes') {
            $data = $Bytes.Clone()
        }
        elseif ($FromBytes) {
            $data = ([byte[]]$Profile.DecryptedBytes).Clone()
        }
        else {
            # Serialize from parsed fields + tail
            $ms = [System.IO.MemoryStream]::new()
            try {
                # Header
                Write-ByteVal   $ms ([byte]$Profile.Version)
                Write-PString   $ms $Profile.GameTitle
                Write-UInt32Val $ms 0                           # reserved

                # Player name + null
                Write-PString   $ms $Profile.PlayerName
                Write-ByteVal   $ms 0

                # Money
                Write-FloatVal  $ms ([float]$Profile.Money)

                # Region table
                Write-UInt32Val $ms ([uint32]$Profile.Regions.Length)
                foreach ($r in $Profile.Regions) {
                    Write-PString $ms $r.Name
                    $ms.Write($r.RawData, 0, 8)
                }

                # Post-region block (verbatim)
                Write-ByteVal   $ms ([byte]$Profile.PostRegionSep)
                Write-UInt32Val $ms ([uint32]$Profile.PostRegionU32)
                Write-ByteVal   $ms ([byte]$Profile.PostRegionB1)
                Write-ByteVal   $ms ([byte]$Profile.PostRegionB2)

                # Trophy table
                foreach ($t in $Profile.TrophyTable) {
                    Write-Int32Val $ms $t
                }

                # Active hunter
                Write-ByteVal $ms ([byte]$Profile.HunterFlag)
                Write-PString $ms $Profile.Hunter
                Write-ByteVal $ms 0                              # null

                # Inventory
                $inv = $Profile.Inventory
                Write-UInt32Val $ms ([uint32]$inv.Length)
                foreach ($item in $inv) {
                    Write-PString $ms $item.Name
                    Write-ByteVal $ms $(if ($item.Type -eq 'Equipment') { 0xFF } else { 0x00 })
                    Write-ByteVal $ms $(if ($item.Equipped) { 0x01 } else { 0x00 })
                }

                # Hunter stats: 7 skill bytes + 10 reserved + uint32 hunt count
                $ms.Write($Profile.HunterStats, 0, [Math]::Min($Profile.HunterStats.Length, 7))
                for ($pad = $Profile.HunterStats.Length; $pad -lt 7; $pad++) {
                    Write-ByteVal $ms 0
                }
                $reservedLen = [Math]::Min($Profile.HunterStatsReserved.Length, 10)
                $ms.Write($Profile.HunterStatsReserved, 0, $reservedLen)
                for ($pad = $reservedLen; $pad -lt 10; $pad++) {
                    Write-ByteVal $ms 0
                }
                Write-UInt32Val $ms ([uint32]$Profile.HuntRecordCount)

                if ($Profile.IsAdvanced) {
                    # Advanced profile: write the opaque hunt-record / weapon
                    # / tail blob verbatim. The blob already excludes the
                    # huntRecordCount uint32 (which we just wrote above).
                    $ms.Write($Profile.AdvancedTail, 0, $Profile.AdvancedTail.Length)
                }
                else {
                    # Simple profile: weapon preamble + weapons + tail
                    Write-ByteVal  $ms ([byte]$Profile.WeaponFlag)
                    Write-FloatVal $ms ([float]$Profile.WeaponZoom)
                    Write-ByteVal  $ms ([byte]$Profile.WeaponSep)

                    Write-UInt32Val $ms ([uint32]$Profile.Weapons.Length)
                    foreach ($w in $Profile.Weapons) {
                        Write-PString  $ms $w.Name
                        Write-FloatVal $ms ([float]$w.Value)
                    }

                    # Network/tail (verbatim)
                    $ms.Write($Profile.TailData, 0, $Profile.TailData.Length)
                }

                # Placeholder checksum
                Write-UInt32Val $ms 0

                $data = $ms.ToArray()
            }
            finally {
                $ms.Dispose()
            }
        }

        # --- Fix checksum (default on; -SkipChecksum to suppress) ---
        if (-not $SkipChecksum) {
            $ckOff = $data.Length - 4
            $cksum = Get-ProChecksum $data $ckOff
            $ckBytes = [BitConverter]::GetBytes($cksum)
            [Array]::Copy($ckBytes, 0, $data, $ckOff, 4)
        }

        # --- Encrypt and write ---
        $encrypted = Invoke-LcgCipher -Bytes $data
        $outPath = [System.IO.Path]::GetFullPath($Path)
        [System.IO.File]::WriteAllBytes($outPath, $encrypted)

        Write-Verbose ("Wrote {0} bytes to {1}" -f $encrypted.Length, $outPath)
    }
}

# ═══════════════════════════════════════════════════════════════════════════
#  Exports
# ═══════════════════════════════════════════════════════════════════════════
Export-ModuleMember -Function Read-DH2005Profile, Write-DH2005Profile
