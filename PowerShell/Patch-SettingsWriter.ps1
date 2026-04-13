<#
.SYNOPSIS
    Deer Hunter 2005 - Settings.cfg persistence patch

.DESCRIPTION
    Patches DH2005.exe to fix a bug where in-game settings changes are lost
    on exit. The game applies settings to its engine runtime mirror but never
    copies them back to the global struct that gets serialized to disk.

    This patch inserts a trampoline before the settings writer call that
    copies 31 dwords from the engine mirror (DAT_005e3630+0xC) back to the
    global settings struct (DAT_005e5344+4) so that changes persist.

.PARAMETER Action
    check  - Report patch status without modifying the file
    apply  - Apply the patch (creates a .bak backup first)
    revert - Restore original bytes

.EXAMPLE
    .\Patch-SettingsWriter.ps1 apply
.EXAMPLE
    .\Patch-SettingsWriter.ps1 check
.EXAMPLE
    .\Patch-SettingsWriter.ps1 revert
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("check","apply","revert")]
    [string]$Action
)

Set-StrictMode -Version Latest

$ExeName    = "DH2005.exe"
$BackupName = "DH2005.exe.bak"
$ImageBase  = 0x400000

# --- Patch definitions ---

# Patch 1: Call site at VA 0x594E77 (file 0x194E77)
#   Original: push ecx; mov eax,0x5E243C; call FUN_00595790  (11 bytes)
#   Patched:  jmp 0x5AA4B0; nop*6

$Patch1Offset = 0x594E77 - $ImageBase
$Patch1Orig   = [byte[]]@(0x51, 0xB8, 0x3C, 0x24, 0x5E, 0x00, 0xE8, 0x0E, 0x09, 0x00, 0x00)
$Patch1New    = [byte[]]@(0xE9, 0x34, 0x56, 0x01, 0x00, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90)

# Patch 2: Trampoline at VA 0x5AA4B0 (file 0x1AA4B0), in .text section padding
#   push esi/edi/ecx
#   mov esi,[0x5E3630]; add esi,0x0C     - engine runtime settings source
#   mov edi,[0x5E5344]; add edi,4        - global settings struct dest
#   mov ecx,31; rep movsd                - copy 31 dwords
#   pop ecx/edi/esi
#   push ecx                             - (original) push DAT_005e5344
#   mov eax,0x5E243C                      - (original) filename string
#   call FUN_00595790                     - (original) write settings to disk
#   jmp 0x594E82                          - return to after original call

$Patch2Offset = 0x5AA4B0 - $ImageBase
$Patch2New    = [byte[]]@(
    0x56,                                     # push esi
    0x57,                                     # push edi
    0x51,                                     # push ecx
    0x8B, 0x35, 0x30, 0x36, 0x5E, 0x00,       # mov esi,[0x5E3630]
    0x83, 0xC6, 0x0C,                         # add esi,0x0C
    0x8B, 0x3D, 0x44, 0x53, 0x5E, 0x00,       # mov edi,[0x5E5344]
    0x83, 0xC7, 0x04,                         # add edi,4
    0xB9, 0x1F, 0x00, 0x00, 0x00,             # mov ecx,31
    0xF3, 0xA5,                               # rep movsd
    0x59,                                     # pop ecx
    0x5F,                                     # pop edi
    0x5E,                                     # pop esi
    0x51,                                     # push ecx
    0xB8, 0x3C, 0x24, 0x5E, 0x00,             # mov eax,0x5E243C
    0xE8, 0xB6, 0xB2, 0xFE, 0xFF,             # call FUN_00595790
    0xE9, 0xA3, 0xA9, 0xFE, 0xFF              # jmp 0x594E82
)
$Patch2Orig = [byte[]]::new($Patch2New.Length)   # expect all zeros (section padding)

$Patches = @(
    @{ Desc = "call site -> trampoline"; Offset = $Patch1Offset; Orig = $Patch1Orig; New = $Patch1New }
    @{ Desc = "trampoline: sync + write"; Offset = $Patch2Offset; Orig = $Patch2Orig; New = $Patch2New }
)

# --- Helpers ---

function Compare-Bytes([byte[]]$A, [byte[]]$B) {
    if ($A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i++) {
        if ($A[$i] -ne $B[$i]) { return $false }
    }
    return $true
}

function Format-Hex([byte[]]$Bytes) {
    return ($Bytes | ForEach-Object { '{0:x2}' -f $_ }) -join ' '
}

# --- Main ---

if (-not $Action) {
    Write-Host "Deer Hunter 2005 - Settings persistence fix (PowerShell)"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\Patch-SettingsWriter.ps1 check   - Verify patch status"
    Write-Host "  .\Patch-SettingsWriter.ps1 apply   - Apply patch (backs up EXE)"
    Write-Host "  .\Patch-SettingsWriter.ps1 revert  - Undo patch"
    Write-Host ""
    Write-Host "Bug: In-game settings changes are applied to the engine's runtime"
    Write-Host "mirror but never copied back to the global settings struct. On exit,"
    Write-Host "the writer serializes the stale global struct, overwriting the user's"
    Write-Host "changes with startup values."
    return
}

if (-not (Test-Path $ExeName)) {
    Write-Host "File not found: $ExeName"
    return
}

$data = [System.IO.File]::ReadAllBytes((Resolve-Path $ExeName))

switch ($Action) {
    "check" {
        Write-Host "$ExeName ($($data.Length) bytes)"
        foreach ($p in $Patches) {
            $current = [byte[]]::new($p.Orig.Length)
            [Array]::Copy($data, $p.Offset, $current, 0, $p.Orig.Length)

            if (Compare-Bytes $current $p.Orig) {
                Write-Host "  [$($p.Desc)] UNPATCHED (original bytes present)"
            }
            elseif (Compare-Bytes $current $p.New) {
                Write-Host "  [$($p.Desc)] ALREADY PATCHED"
            }
            else {
                Write-Host "  [$($p.Desc)] UNKNOWN bytes: $(Format-Hex $current)"
                Write-Host "    Expected orig: $(Format-Hex $p.Orig)"
                Write-Host "    Expected new:  $(Format-Hex $p.New)"
            }
        }
    }
    "apply" {
        # Verify original bytes
        foreach ($p in $Patches) {
            $current = [byte[]]::new($p.Orig.Length)
            [Array]::Copy($data, $p.Offset, $current, 0, $p.Orig.Length)

            if (Compare-Bytes $current $p.New) {
                Write-Host "Already patched: $($p.Desc)"
                return
            }
            if (-not (Compare-Bytes $current $p.Orig)) {
                Write-Host "ERROR: Unexpected bytes at $($p.Desc)"
                Write-Host "  Found:    $(Format-Hex $current)"
                Write-Host "  Expected: $(Format-Hex $p.Orig)"
                Write-Host "Aborting. Is this the right EXE version?"
                return
            }
        }

        # Backup
        Copy-Item $ExeName $BackupName -Force
        Write-Host "Backup: $BackupName"

        # Apply
        foreach ($p in $Patches) {
            [Array]::Copy($p.New, 0, $data, $p.Offset, $p.New.Length)
            Write-Host "  Patched: $($p.Desc)"
        }

        [System.IO.File]::WriteAllBytes((Join-Path $PWD $ExeName), $data)

        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hash = ($md5.ComputeHash($data) | ForEach-Object { '{0:x2}' -f $_ }) -join ''
        Write-Host "Done. MD5: $hash"
        Write-Host ""
        Write-Host "Before the settings writer runs at exit, the engine's current"
        Write-Host "runtime settings will now be copied back to the global struct,"
        Write-Host "so in-game changes are persisted to Settings.cfg."
    }
    "revert" {
        $changed = $false
        foreach ($p in $Patches) {
            $current = [byte[]]::new($p.New.Length)
            [Array]::Copy($data, $p.Offset, $current, 0, $p.New.Length)

            if (Compare-Bytes $current $p.New) {
                [Array]::Copy($p.Orig, 0, $data, $p.Offset, $p.Orig.Length)
                Write-Host "  Reverted: $($p.Desc)"
                $changed = $true
            }
            elseif (Compare-Bytes $current $p.Orig) {
                Write-Host "  Already original: $($p.Desc)"
            }
            else {
                Write-Host "  UNKNOWN bytes at $($p.Desc), skipping"
            }
        }
        if ($changed) {
            [System.IO.File]::WriteAllBytes((Join-Path $PWD $ExeName), $data)
            Write-Host "Revert complete."
        }
    }
}
