# Settings Persistence Bug

Deer Hunter 2005 does not save in-game settings changes. Any modifications made through the settings screen are lost when the game exits, with `Settings.cfg` reverting to the values it had at startup.

## Root Cause

The game maintains settings in three locations during runtime:

| Location | Address | Purpose |
|----------|---------|---------|
| Global settings struct | `DAT_005e5344` | 128-byte struct (4-byte vtable + 31 int32 values). Loaded from `Settings.cfg` at startup, serialized back to disk on exit. |
| Engine runtime mirror | `DAT_005e3630 + 0x0C` | Copy of the 31 settings values inside the engine/renderer object. This is what the engine actually reads during gameplay. |
| Settings screen copy | `ESI + 0x13C` | Temporary copy used by the in-game settings UI. Exists only while the settings dialog is open. |

### Startup flow (correct)

1. `FUN_00592e70` allocates the global struct and applies the High preset as a default
2. `FUN_00595850` reads `Settings.cfg` and copies the parsed values into the global struct via `rep movsd` at `0x59592D`
3. `FUN_00447220` copies the 31 values from the global struct into the engine runtime mirror

### In-game settings change (partially correct)

1. The settings screen loads values from the engine mirror into a screen-local copy at `ESI + 0x13C`
2. The user adjusts settings through the UI
3. On "Apply", `FUN_00447220` copies the screen-local values into the engine runtime mirror (`DAT_005e3630 + 0x0C`)
4. The engine immediately uses the new values (resolution changes, quality updates, etc.)

### Exit flow (the bug)

1. `FUN_00594510` calls `FUN_00595790(DAT_005e5344)` at `0x594E7D`
2. `FUN_00595790` serializes `DAT_005e5344 + 4` (the global struct's data) to `Profiles\Settings.cfg`

**The problem:** Step 3 of the in-game flow writes to the engine mirror only. The global struct at `DAT_005e5344` is never updated. When the exit flow serializes the global struct, it writes the original startup values, not the user's changes.

```
Startup:   Settings.cfg --> [Global Struct] --> [Engine Mirror]
In-game:   Settings UI  -------skip-------->  [Engine Mirror]
Exit:      [Global Struct] --> Settings.cfg
                  ^
                  |
          Still has startup values!
```

### Dead writeback code

`FUN_00599bc0` contains code that writes individual setting values back to `DAT_005e5344`:

```c
*(undefined4 *)(DAT_005e5344 + 4 + unaff_ESI * 4) = uVar6;
```

This function handles per-field updates including special cases for Gamma (`0x0C`), Master Volume (`0x19`), Music Volume (`0x1C`), Interface Volume (`0x1D`), and Distance Unit (`0x1E`). It is called from the settings UI code at `0x56F2DF`, but only for individual slider/toggle changes -- the bulk "Apply preset" path bypasses it entirely, going through `FUN_00447220` instead.

## Fix

Insert a `rep movsd` copy from the engine mirror to the global struct immediately before the settings writer call.

### Patch site

At VA `0x594E77` (file offset `0x194E77`), the exit path prepares and calls the writer:

```asm
; Original (11 bytes):
594E77:  51                  push ecx              ; DAT_005e5344 (param)
594E78:  B8 3C 24 5E 00      mov eax, 0x5E243C     ; filename (implicit param)
594E7D:  E8 0E 09 00 00      call FUN_00595790      ; write Settings.cfg
594E82:  EB 1B               jmp ...                ; continue exit
```

This is replaced with a jump to a trampoline:

```asm
; Patched:
594E77:  E9 34 56 01 00      jmp 0x5AA4B0          ; jump to trampoline
594E7C:  90 90 90 90 90 90   nop                    ; pad remaining bytes
```

### Trampoline

Written into unused padding at the end of the `.text` section (VA `0x5AA4B0`, file offset `0x1AA4B0`). The `.text` section's raw size exceeds its virtual size by `0xB50` bytes, all zeros, providing a safe code cave.

```asm
5AA4B0:  56                          push esi
5AA4B1:  57                          push edi
5AA4B2:  51                          push ecx

         ; Source: engine runtime settings
5AA4B3:  8B 35 30 36 5E 00           mov esi, [0x5E3630]
5AA4B9:  83 C6 0C                    add esi, 0x0C

         ; Dest: global settings struct (skip vtable)
5AA4BC:  8B 3D 44 53 5E 00           mov edi, [0x5E5344]
5AA4C2:  83 C7 04                    add edi, 4

         ; Copy 31 dwords (124 bytes)
5AA4C5:  B9 1F 00 00 00              mov ecx, 31
5AA4CA:  F3 A5                       rep movsd

         ; Restore registers
5AA4CC:  59                          pop ecx
5AA4CD:  5F                          pop edi
5AA4CE:  5E                          pop esi

         ; Reproduce original instructions
5AA4CF:  51                          push ecx
5AA4D0:  B8 3C 24 5E 00              mov eax, 0x5E243C
5AA4D5:  E8 B6 B2 FE FF              call FUN_00595790

         ; Return to exit path
5AA4DA:  E9 A3 A9 FE FF              jmp 0x594E82
```

### Applying the patch

PowerShell:

```powershell
.\Patch-SettingsWriter.ps1 apply     # apply (creates DH2005.exe.bak)
.\Patch-SettingsWriter.ps1 check     # verify status
.\Patch-SettingsWriter.ps1 revert    # restore original bytes
```

Python:

```
py patch_settings_writer.py apply
py patch_settings_writer.py check
py patch_settings_writer.py revert
```

## Ghidra decompilation caveat

Ghidra's decompilation of `FUN_00595850` (the settings reader) is misleading. It marks `FastFree` as a non-returning function, which causes the decompiler to omit the `rep movsd` copy loop at `0x59592D` that follows it. The decompiled output makes it appear that parsed values are written to a stack-local buffer and discarded:

```c
// Ghidra output (INCOMPLETE):
iVar1 = FUN_00454750(&local_88, local_7c);
if (-1 < iVar1) {
    /* WARNING: Subroutine does not return */
    FastFree(pvVar3);   // <-- Ghidra stops here
}
```

In reality, the code after `FastFree` loads the destination pointer from the stack, sets up a `rep movsd` of 31 dwords, and copies the parsed settings from the stack buffer to the caller-provided struct:

```asm
; Actual code after FastFree (missed by Ghidra):
595915:  call FastFree
59591A:  mov edi, [esp+0xA0]     ; destination pointer (from stack param)
595924:  add edi, 4              ; skip vtable
595928:  mov ecx, 0x1F           ; 31 dwords
59592D:  lea esi, [esp+0x18]     ; source = local_7c (stack buffer)
595931:  rep movsd                ; copy to destination
595935:  mov eax, 1              ; return success
```

The settings reader works correctly. The bug is exclusively in the exit-time write path.

## Source references

| Function | Address | Role |
|----------|---------|------|
| `FUN_00592e70` | `0x592E70` | Game initialization -- allocates global struct, reads settings, applies to engine |
| `FUN_00595850` | `0x595850` | Settings.cfg reader -- parses file into caller-provided struct |
| `FUN_00595790` | `0x595790` | Settings.cfg writer -- serializes global struct to disk |
| `FUN_00594510` | `0x594510` | Main game function -- calls writer at `0x594E7D` during exit |
| `FUN_00447220` | `0x447220` | Apply settings to engine -- copies 31 values to runtime mirror, no writeback |
| `FUN_00454750` | `0x454750` | Binary parser -- reads version, count, then 31 int32 values from stream |
| `FUN_004546a0` | `0x4546A0` | Binary serializer -- writes version, count, then 31 int32 values to buffer |
| `FUN_00454430` | `0x454430` | Preset applicator -- copies from preset table filtered by type/override flags |
| `FUN_00599bc0` | `0x599BC0` | Per-field settings writeback (partial, not used for bulk preset apply) |
| `DAT_005e5344` | `0x5E5344` | Pointer to global settings struct (128 bytes: vtable + 31 int32s) |
| `DAT_005e3630` | `0x5E3630` | Pointer to engine runtime object (settings data at offset `+0x0C`) |
