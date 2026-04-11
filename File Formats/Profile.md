# Deer Hunter 2005 `.pro` Profile File Format

Reverse-engineered from `DH2005.exe` (functions at `0x407EA0`, `0x5A0710`, `0x5A10A0`).

## Overview

`.pro` files are player save-game profiles. The entire file is XOR-encrypted
with a keystream produced by a Linear Congruential Generator (LCG). Once
decrypted, the file contains a sequential binary structure of mixed
fixed-size and length-prefixed fields, terminated by a 4-byte checksum.

Typical file size: **857 bytes** (varies with string lengths).

---

## 1. Encryption Layer

The cipher is **symmetric** -- the same operation encrypts and decrypts.

### LCG Seed

```
state = (fileSize * 7 + 0x04A0C70C) & 0xFFFFFFFF
```

`fileSize` is the total byte length of the encrypted file.

### Keystream Generation (per byte)

Each byte is XOR'd with the low byte of the LCG state after stepping:

```c
// C-equivalent (from FUN_00407ea0)
int16_t lo = state & 0xFFFF;
int16_t hi = (int32_t)state >> 16;   // arithmetic right shift
state = (lo * 0x6054 + hi) & 0xFFFFFFFF;
key_byte = state & 0xFF;
```

The arithmetic (signed) right shift is critical: when bit 31 of `state` is
set, `hi` is negative, which produces a different keystream than a logical
shift would.

### Decryption

```
decrypted[i] = encrypted[i] ^ key_byte[i]
```

---

## 2. Checksum

The **last 4 bytes** of the decrypted file are a little-endian `uint32`
equal to the sum of all preceding bytes (validated in `FUN_005a0710`):

```
checksum = SUM(decrypted[0 .. N-5]) & 0xFFFFFFFF
```

Where `N` is the total file length. The game writes this checksum when
saving; modifying any byte requires recomputing it.

---

## 3. Decrypted Binary Layout

All multi-byte integers are **little-endian**. Strings use **Windows-1252**
encoding. Two string encodings appear:

| Notation   | Format                                         |
|------------|-------------------------------------------------|
| `pstring`  | `uint8 length` + `char[length]`  (no terminator)|
| `pstringZ` | `uint8 length` + `char[length]` + `0x00` null   |

### 3.1 Header

| Offset | Type     | Field       | Notes                           |
|--------|----------|-------------|---------------------------------|
| 0x00   | uint8    | Version     | Always `0x0A` (10)              |
| 0x01   | pstring  | GameTitle   | `"Deer Hunter 2005"` (16 chars) |
| varies | uint32   | Reserved    | Always 0                        |

### 3.2 Player Info

| Offset | Type     | Field       | Notes                              |
|--------|----------|-------------|------------------------------------|
| varies | pstringZ | PlayerName  | e.g. `"John"`                      |
| varies | float32  | Money       | Cash balance (~$146.53 fresh, ~$15705 advanced) |

### 3.3 Region Block

The region block is a count followed by an array of per-region entries.
The number of entries equals the number of unlocked regions in the
profile (1 for a fresh profile, up to 5 for a fully-unlocked profile).

| Offset | Type     | Field       | Notes                                       |
|--------|----------|-------------|---------------------------------------------|
| varies | uint32   | RegionCount | 1 fresh, 5 fully unlocked                   |
| varies | Region[] | Regions     | RegionCount entries                         |

Each `Region` entry:

| Type     | Field   | Notes                                                       |
|----------|---------|-------------------------------------------------------------|
| pstring  | Name    | e.g. `"Oregon"`, `"Black Forest"`, `"Australia"` (no null)  |
| float32  | Float1  | Per-region progress / score (0-1 range observed)            |
| float32  | Float2  | Per-region progress / score (0-1 range observed)            |

### 3.4 Post-Region Constants

Following the region table is a small block of bytes that has been
constant across every observed profile. They are preserved verbatim for
round-trip safety.

| Offset | Type   | Field         | Observed value |
|--------|--------|---------------|----------------|
| varies | uint8  | PostRegionSep | 0              |
| varies | uint32 | PostRegionU32 | 250            |
| varies | uint8  | PostRegionB1  | 2              |
| varies | uint8  | PostRegionB2  | 31             |

### 3.5 Trophy Table

| Type      | Count   | Notes                            |
|-----------|---------|----------------------------------|
| int32[63] | (fixed) | `-1` (`0xFFFFFFFF`) = empty slot |

The trophy table is fixed at **63 entries** in version 10 profiles.
There is no in-file count.

Trophy IDs and scores appear to be interleaved or indexed. Values range
from small animal/zone IDs to scores in the hundreds.

### 3.6 Active Hunter

The active hunter is the player-character model selected for play. The
game ships with several hunter models (e.g. `Ben`, `Bill`, `Mildred`),
each with its own 3D mesh and one or more selectable skins.

| Type     | Field       | Notes                              |
|----------|-------------|------------------------------------|
| uint8    | HunterFlag  | Section flag, 1 observed           |
| pstringZ | HunterName  | Active hunter model, e.g. `"Ben"`  |

### 3.7 Inventory

The inventory holds all owned items: equipment (rifles, scopes, calls,
blinds, etc.) and unlocked hunter skins.

| Type   | Field     | Notes                                          |
|--------|-----------|------------------------------------------------|
| uint32 | ItemCount | Total entries (equipment + skins)               |

Each entry (repeated `ItemCount` times):

| Type   | Field  | Notes                                          |
|--------|--------|------------------------------------------------|
| pstring| Name   | Item or hunter-skin name                       |
| uint8  | Type   | `0xFF` = equipment, `0x00` = hunter skin       |
| uint8  | Status | `0x01` = equipped/selected, `0x00` = unequipped|

Example inventory:

```
Pump Rifle        Equipment  Equipped
Bolt Rifle Scoped Equipment  Equipped
Binoculars_10_25  Equipment  -
Map               Equipment  -
GPS               Equipment  -
Scent_Stomper     Equipment  -
Big_Buck_Scent    Equipment  -
Grunt_Call        Equipment  -
Blind             Equipment  -
Mildred           Skin       -
```

### 3.8 Hunter Stats

Immediately after the inventory:

| Offset | Size | Notes                                                           |
|--------|------|-----------------------------------------------------------------|
| +0     | 7    | Skill ratings (one byte per skill, values 0--4 observed)        |
| +7     | 10   | Reserved / unused (all zeros observed)                          |
| +17    | 4    | uint32 `HuntRecordCount` (number of recorded hunt sessions)     |

If `HuntRecordCount == 0`, the file is a **simple** profile and the
weapon section follows immediately. If `HuntRecordCount > 0`, the file
is an **advanced** profile and a variable-length hunt-record section
intervenes before the weapon section.

The hunt-record format is not fully decoded. Each record references a
deer species (or none for sessions without a kill), a region, one or
more weapon configurations (name + variant + ammo), and several float
values (likely position/orientation). Records are variable-size; record
boundaries are determined by the parser walking each record's contents.
The DH2005Profile PowerShell module preserves this section verbatim as
an opaque `AdvancedTail` blob, which is sufficient for round-trip
editing of any other field.

### 3.9 Weapon Configuration

| Type    | Field       | Notes                             |
|---------|-------------|-----------------------------------|
| uint8   | SectionFlag | Always 1                          |
| float32 | WeaponZoom  | Global zoom multiplier (1.0)      |
| uint8   | Separator   | Always 0                          |
| uint32  | WeaponCount | Number of weapon entries           |

Each weapon entry:

| Type    | Field | Notes                                         |
|---------|-------|-----------------------------------------------|
| pstring | Name  | Weapon ID string (no null terminator)         |
| float32 | Value | Weapon parameter (damage/range: 3.75, 1.0)   |

### 3.10 Network / Multiplayer

The bytes following the weapon section contain multiplayer configuration.
The exact field layout is not fully decoded, but the following strings are
present as length-prefixed values:

| Field      | Example            | Notes                    |
|------------|--------------------|--------------------------|
| ServerIP   | `192.168.1.86`     | Last-used server address |
| ServerName | `Vintage Gaming`   | Last-used server name    |

Additional observed values in this section include a `uint32` that may be
a port number (136 observed) and protocol/version bytes.

### 3.11 Hunt Level Paths

Following the network section, one or more hunt records appear. Each
contains:

| Type    | Field     | Notes                                         |
|---------|-----------|-----------------------------------------------|
| pstring | LevelPath | e.g. `Data\World\Levels\Oregon\Profile.txt`   |
| int32[] | Stats     | Variable-length array of hunt statistics       |

The stat array length varies per record (10--22 uint32 values observed).
Values include scores, kill counts, and `-1` sentinel values. The exact
field mapping is unknown.

---

## 4. Field Offset Calculation

Because strings and the region table are variable-length, field
positions are computed by walking the file sequentially. There are no
fixed offsets past the header. Use the DH2005Profile PowerShell module
(or replicate its logic) for any calculation that needs absolute
positions.

---

## 5. Editing Guide

### Changing the Player Name

Because strings are length-prefixed, changing the name requires rebuilding
the byte array:

```powershell
Import-Module .\DH2005Profile
$p = Read-DH2005Profile John.pro
$p.PlayerName = 'Alexander'
Write-DH2005Profile -Path Alexander.pro -Profile $p -FixChecksum
```

The module handles re-serialization and checksum recomputation.

### Editing Fixed-Size Fields

For in-place edits to numeric fields (trophies, scores, floats), modify
the `DecryptedBytes` array directly, then write with `-FromBytes`:

```powershell
$p = Read-DH2005Profile John.pro
# Zero out trophy slot 0 (offset depends on string lengths)
$off = <computed offset>
[BitConverter]::GetBytes([int32]0).CopyTo($p.DecryptedBytes, $off)
Write-DH2005Profile -Path Mod.pro -Profile $p -FromBytes -FixChecksum
```

### Round-Trip Verification

```powershell
$original = [IO.File]::ReadAllBytes('John.pro')
$p = Read-DH2005Profile John.pro
Write-DH2005Profile -Path Roundtrip.pro -Profile $p -FixChecksum
$result = [IO.File]::ReadAllBytes('Roundtrip.pro')
Compare-Object $original $result   # should be empty
```

---

## 6. Reference

| Item              | Value / Location                         |
|-------------------|------------------------------------------|
| Cipher function   | `FUN_00407ea0` in `DH2005.exe`           |
| Checksum function | `FUN_005a0710` in `DH2005.exe`           |
| Save/load logic   | `FUN_005a10a0` / `FUN_005a0200`          |
| LCG multiplier    | `0x6054`                                 |
| LCG seed constant | `0x04A0C70C`                             |
| File extension    | `.pro`                                   |
| Encoding          | Windows-1252                             |
| Byte order        | Little-endian                            |
