# Settings.cfg — Deer Hunter: The 2005 Season

Binary configuration file storing video, audio, and gameplay settings. Located at `Game\Profiles\Settings.cfg` relative to the game installation directory.

## File Structure

| Offset | Size | Description |
|--------|------|-------------|
| 0x00 | 1 byte | Version — must be `0x01` |
| 0x01 | 1 byte | Field count — must be `0x1F` (31) |
| 0x02 | 124 bytes | 31 little-endian signed 32-bit integers |

**Total size**: 126 bytes

### Integrity Check

There is no checksum. The game validates the file by checking:
- Byte 0 equals `0x01` (version)
- Byte 1 equals `0x1F` (field count = 31)

If either check fails, the file is rejected and the game auto-detects settings based on hardware capabilities.

### Auto-Detection Logic

When no valid `Settings.cfg` exists, the game scores the system on four criteria:
- GPU memory >= 256 MB
- CPU speed >= 60 (internal benchmark units)
- Shader support present
- Available RAM > 2000 MB

The score (0–4) maps to a quality preset: 0–1 = Low, 2 = Medium, 3–4 = High. The Ultra preset is never auto-selected.

## Field Map

All values are signed 32-bit little-endian integers at offset `0x02 + (index * 4)`.

### Video Settings (Type 0)

| Index | Offset | Field | Values | Notes |
|-------|--------|-------|--------|-------|
| 0 | 0x02 | Video HRes | 640, 800, 1024, 1280, ... | Screen width in pixels |
| 1 | 0x06 | Video VRes | 480, 600, 768, 960, ... | Screen height in pixels |
| 2 | 0x0A | Video Bits | 16, 32 | Color depth |
| 3 | 0x0E | Texture Detail | 0–3 | Low / Medium / High / Ultra |
| 4 | 0x12 | Texture Filtering | 0–2 | 0 = Bilinear, 1 = Trilinear, 2 = Anisotropic |
| 5 | 0x16 | Texture Bits | 16, 32 | Texture color depth |
| 6 | 0x1A | Compress Textures | 0–1 | Boolean |
| 7 | 0x1E | Shadows Quality | 0–3 | Low / Medium / High / Ultra |
| 8 | 0x22 | FSAA | 0–1 | Full-scene anti-aliasing on/off |
| 9 | 0x26 | Reflections | 0–1 | Boolean |
| 10 | 0x2A | Water Reflection | 0–2 | 0 = Off, 1 = Low, 2 = High |
| 11 | 0x2E | VSync | 0–1 | Boolean |
| 12 | 0x32 | Gamma | 0–100 | Slider, default 50. Not affected by quality presets |
| 13 | 0x36 | Draw Background | 0–1 | Distant background rendering |
| 14 | 0x3A | Terrain Detail | 0–3 | Low / Medium / High / Ultra |
| 15 | 0x3E | Sky Quality | 0–3 | Low / Medium / High / Ultra |
| 16 | 0x42 | Weather FX | 0–3 | Low / Medium / High / Ultra |
| 17 | 0x46 | Day/Night FX | 0–3 | Low / Medium / High / Ultra |
| 18 | 0x4A | Ground Objects | 0–3 | Low / Medium / High / Ultra |
| 19 | 0x4E | Bending Grass | 0–1 | Boolean |
| 20 | 0x52 | Max View Distance | 0–100 | Slider |
| 21 | 0x56 | Trees Density | 0–100 | Slider |
| 22 | 0x5A | Models Detail | 0–3 | Low / Medium / High / Ultra |
| 23 | 0x5E | Morph Targets | 0–1 | Facial animations on/off |

### Audio Settings (Type 1)

| Index | Offset | Field | Values | Notes |
|-------|--------|-------|--------|-------|
| 24 | 0x62 | Audio Quality | 0–3 | Low / Medium / High / Ultra |
| 25 | 0x66 | Master Vol | 0–100 | Slider. Not affected by quality presets |
| 26 | 0x6A | Wind Vol | 0–100 | Slider. Not affected by quality presets |
| 27 | 0x6E | Environment Vol | 0–100 | Slider. Not affected by quality presets |
| 28 | 0x72 | Music Vol | 0–100 | Slider. Not affected by quality presets |
| 29 | 0x76 | Interface Vol | 0–100 | Slider. Not affected by quality presets |

### Gameplay Settings

| Index | Offset | Field | Values | Notes |
|-------|--------|-------|--------|-------|
| 30 | 0x7A | Distance Unit | 0–2 | 0 = Feet, 1 = Meters, 2 = Yards. Not affected by quality presets |

## Quality Presets

The game provides four presets selectable from the settings UI. Applying a preset overwrites all fields marked with Override = Yes. Fields with Override = No (Gamma, volume sliders, Distance Unit) retain their current values.

| Field | Low | Medium | High | Ultra | Override |
|-------|-----|--------|------|-------|----------|
| Video HRes | 640 | 800 | 1024 | 1280 | Yes |
| Video VRes | 480 | 600 | 768 | 960 | Yes |
| Video Bits | 16 | 16 | 32 | 32 | Yes |
| Texture Detail | Low | Medium | High | Ultra | Yes |
| Texture Filtering | Bilinear | Bilinear | Trilinear | Anisotropic | Yes |
| Texture Bits | 16 | 16 | 16 | 32 | Yes |
| Compress Textures | On | On | On | On | Yes |
| Shadows Quality | Low | Medium | High | Ultra | Yes |
| FSAA | Off | Off | Off | On | Yes |
| Reflections | Off | On | On | On | Yes |
| Water Reflection | Off | Low | High | High | Yes |
| VSync | Off | Off | Off | On | Yes |
| Gamma | 50 | 50 | 50 | 50 | No |
| Draw Background | Off | On | On | On | Yes |
| Terrain Detail | Low | Medium | High | Ultra | Yes |
| Sky Quality | Low | Medium | High | Ultra | Yes |
| Weather FX | Low | Medium | High | Ultra | Yes |
| Day/Night FX | Low | Medium | High | Ultra | Yes |
| Ground Objects | Low | Medium | High | Ultra | Yes |
| Bending Grass | Off | Off | On | On | Yes |
| Max View Distance | 0 | 50 | 100 | 100 | Yes |
| Trees Density | 0 | 50 | 100 | 100 | Yes |
| Models Detail | Low | Medium | High | Ultra | Yes |
| Morph Targets | Off | On | On | On | Yes |
| Audio Quality | Low | Medium | High | Ultra | Yes |
| Master Vol | 100 | 100 | 100 | 100 | No |
| Wind Vol | 100 | 100 | 100 | 100 | No |
| Environment Vol | 100 | 100 | 100 | 100 | No |
| Music Vol | 100 | 100 | 100 | 100 | No |
| Interface Vol | 100 | 100 | 100 | 100 | No |
| Distance Unit | Yards | Yards | Yards | Yards | No |

## Runtime Representation

In memory, the settings are stored in a 128-byte structure:

| Offset | Size | Description |
|--------|------|-------------|
| 0x00 | 4 bytes | VTable pointer (`0x005B6FE0`) |
| 0x04 | 124 bytes | 31 int32 values (same order as the file, no header bytes) |

The global pointer to this structure is at `0x005E5344` in DH2005.exe.

## Hex Example

A "High" preset file with default volumes:

```
01 1F                                       ; version=1, count=31
00 04 00 00                                 ; 1024  Video HRes
00 03 00 00                                 ; 768   Video VRes
20 00 00 00                                 ; 32    Video Bits
02 00 00 00                                 ; 2     Texture Detail (High)
01 00 00 00                                 ; 1     Texture Filtering (Trilinear)
10 00 00 00                                 ; 16    Texture Bits
01 00 00 00                                 ; 1     Compress Textures (On)
02 00 00 00                                 ; 2     Shadows Quality (High)
00 00 00 00                                 ; 0     FSAA (Off)
01 00 00 00                                 ; 1     Reflections (On)
02 00 00 00                                 ; 2     Water Reflection (High)
00 00 00 00                                 ; 0     VSync (Off)
32 00 00 00                                 ; 50    Gamma
01 00 00 00                                 ; 1     Draw Background (On)
02 00 00 00                                 ; 2     Terrain Detail (High)
02 00 00 00                                 ; 2     Sky Quality (High)
02 00 00 00                                 ; 2     Weather FX (High)
02 00 00 00                                 ; 2     Day/Night FX (High)
02 00 00 00                                 ; 2     Ground Objects (High)
01 00 00 00                                 ; 1     Bending Grass (On)
64 00 00 00                                 ; 100   Max View Distance
64 00 00 00                                 ; 100   Trees Density
02 00 00 00                                 ; 2     Models Detail (High)
01 00 00 00                                 ; 1     Morph Targets (On)
02 00 00 00                                 ; 2     Audio Quality (High)
64 00 00 00                                 ; 100   Master Vol
64 00 00 00                                 ; 100   Wind Vol
64 00 00 00                                 ; 100   Environment Vol
64 00 00 00                                 ; 100   Music Vol
64 00 00 00                                 ; 100   Interface Vol
02 00 00 00                                 ; 2     Distance Unit (Yards)
```

## Tool

`settings_cfg.py` can dump, edit, and create Settings.cfg files:

```
py settings_cfg.py Settings.cfg                     # dump all fields
py settings_cfg.py Settings.cfg res 1920 1080 32    # set resolution
py settings_cfg.py Settings.cfg preset ultra         # apply quality preset
py settings_cfg.py Settings.cfg set "Gamma" 75       # set individual field
py settings_cfg.py Settings.cfg create high          # create new file from preset
```

## Source References

- **Parsing function**: `FUN_00454750` in DH2005.exe — reads version byte, field count byte, then loops 31 times reading int32s
- **Quality preset application**: `FUN_00454430` — copies from preset table at `0x005C4DB0`, filtered by type/override flags at `0x005C4D30` / `0x005C4FA0`
- **Field name string table**: 31 null-terminated strings starting at `0x005C4A68`, pointer array at `0x005C4C30`
- **Localization keys**: `[Settings_Desc_%s]` format in `data\languages\english\general.txt`
