# Phase 1 — Technical Art, Textures and Rendering

Taunt-o-Nomics: Dhaka overhaul • Godot 4.6 (Forward+) • Developed and copyrighted by S M Nazmuz Sakib

## Contents

```
project.godot                       Forward+ / Jolt / TAA + FSR2 / SDFGI, SSAO, SSIL, volumetric-fog quality settings
tools/generate_textures.py          procedural seamless PBR texture generator (numpy + Pillow)
assets/textures/<material>/         pre-generated 1024 px sets + .tres materials (re-run the script for 2048/4096)
assets/textures/_preview.png        lit, 2x2-tiled contact sheet
scripts/render/DhakaAtmosphere.gd   WorldEnvironment + sky + sun + fog volumes + presets + quality tiers (@tool)
scripts/render/LookdevAlley.gd      look-dev alley built only from the generated materials
scripts/ui/UiKit.gd                 SVG → Theme, bars, rings, markers, title cards, key prompts
scripts/ui/UiKitDemo.gd             UI showcase
scenes/lookdev_alley.tscn           main scene: walk the alley, switch weather and quality live
scenes/ui_kit_demo.tscn             HUD + exam window built from the SVG kit
scenes/dhaka_atmosphere.tscn        drop-in atmosphere node for any level
ui/svg/*.svg                        34 UI assets (raw SVG, no fonts or filters)
assets/fonts/                       FreeSans (has Bengali glyphs + shaping tables) as a fallback font
```

## 1. Texture generator

```
pip install numpy pillow
cd tools
python generate_textures.py --out ../assets/textures --size 2048 --preview
python generate_textures.py --only brick_weathered --size 4096 --seed 23
```

| Material | What is simulated |
|---|---|
| `brick_weathered` | running bond with jittered courses, chipped arrises, 8-colour brick palette, pitting, salt bloom (efflorescence) low on damp bricks, soot and rain streaks, moss in damp joints |
| `asphalt_cracked` | partly buried aggregate, alligator-crack patches, long cracks with tar sealant, dust in cracks, pothole with puddle, oil stains, tyre-polished lanes |
| `tin_galvanized` | sine-corrugation with wobble, galvanising spangle, white rust, lap seam, screws on the crests with rust halos and drips, rust runs that follow gravity |
| `tin_painted_green` | same sheet painted green (as on the Sontek rooftops), chalky fade, peeling to zinc, rust |
| `concrete_mossy` | board-formed pours with lift lines and tone shifts, tie holes with rust runs, pores, cracks, water streaks hanging below joints, moss with a damp halo, lichen |
| `awning_stripes_red` / `_blue` | canvas stripes, weave, sun-fade, folds and sag, dirt, water marks |
| `awning_blockprint` | green cotton with block-printed lotus medallions and uneven ink |
| `awning_tarp_blue` | woven HDPE tarp, white bands, taped orange repair patches, crinkles |

Each material gets:
- `_albedo`, `_normal` (OpenGL, +Y up, which is what Godot uses), `_roughness`, `_ao`
- `_height` (16-bit), plus `_metallic` for the two tin materials
- `_orm` (R = AO, G = roughness, B = metallic)
- two materials: `<name>.tres` uses world-space triplanar mapping, for the procedural boxes coming in Phase 2. `<name>_uv.tres` uses UV mapping with deep parallax from the height map, for modelled meshes. Godot cannot combine parallax with triplanar, which is why there are two.

**Seamless tiling.** All noise is spectral (FFT) or periodic cellular noise, and all blurs wrap around the edges. I measured every albedo, normal and roughness map: each tile edge sits within the normal range of interior differences. The three exceptions are designed edges that fall exactly on the boundary: a stripe border, a concrete pour line, and the tarp's weave.

**Timing.** At 1024 px, all nine sets take about 40 s. Expect about 2.5 min at 2048 px and about 10 min at 4096 px. Use 2048 for hero surfaces at street level and 1024 everywhere else.

## 2. Rendering (the URP equivalent in Godot)

`DhakaAtmosphere` is a `@tool` node, so the look appears in the editor as you build.

| Feature | Setting and purpose |
|---|---|
| Tonemapper | AgX when the engine has it (4.4+), otherwise ACES. White point 6. |
| SDFGI | 6 cascades, 0.25 m cells, occlusion on, reads sky light, bounce 0.55. Bounce light for a whole city block with nothing to bake. |
| SSAO | radius 1.4, intensity 2.2, power 1.6. Contact shadows where walls meet the street. |
| SSIL | radius 6, intensity 1.1. Red brick and blue tarp bleed colour into alleys. |
| SSR | 72 steps. Puddles, shop glass, steel shutters. |
| Depth fog | exponential, with aerial perspective and height fog, so distant towers fade into the brown haze. |
| Volumetric fog | 96 m long, GI and ambient injection, temporal reprojection. Sun shafts between buildings and halos round lamps. |
| Street smog | a 400 × 14 × 400 m FogVolume with a 3D noise density texture that hangs low in the alleys. |
| Glow | soft-light blend, levels 3–5, HDR threshold per preset. Neon signs, sodium lamps, sun bloom. |
| Sky | ProceduralSkyMaterial with a smog-brown horizon, a dimmed and widened sun disk, and FBM noise cloud cover. |
| Sun | 4-split PSSM over 220 m, blended splits, angular size 1.6° for soft shadows, scatters into the volumetric fog. |
| Camera | auto-exposure for walking out of dark alleys into glare, and a slight far depth of field. |
| Grading | contrast, saturation and a 1D LUT (warm highlights, olive-teal shadows). Assign `color_lut` to use your own LUT. |

**Presets.** `HAZE_NOON` matches your Sontek skyline photos. The others are `GOLDEN_SMOG`, `MONSOON_OVERCAST` and `NIGHT_SODIUM`. Call `blend_to(preset, seconds)` for weather and time-of-day transitions. The `smog` slider runs from 0 (a clear winter morning) to 1.5 (AQI 300+).

**Quality tiers.**
- LOW turns off SDFGI, SSIL, SSR and volumetrics and thickens the depth fog to compensate.
- MEDIUM keeps SSIL and volumetrics.
- HIGH is the default.
- ULTRA uses 8 SDFGI cascades, 160 m of volumetric fog and an 8K shadow atlas.

**Helpers.** `add_smoke(position)` creates a smoke column for tea stalls and braziers. `add_light_halo(position, colour)` adds a glowing halo for lamps at night.

**Version safety.** Settings that changed between Godot minor versions go through `_set_if()`, which skips any property the engine doesn't have.

## 3. SVG UI kit (`ui/svg`)

Style: dark smoked glass, a saffron `#f2a541` accent, signal red `#e5484d`, teal `#2ec4b6` for stealth. Borders use nakshi-kantha running stitches, and the exam header icon is an alpona lotus. The SVGs contain no `<text>`, filters or patterns, so Godot's ThorVG importer renders them exactly. I checked all 34 in two renderers (Chrome and librsvg).

| File | Use | 9-slice margins (L, T, R, B) |
|---|---|---|
| `panel_glass` | any panel (Theme: PanelContainer) | 40, 40, 40, 40 |
| `panel_header` | objective / section header | 56, 0, 72, 0 |
| `bar_under`, `bar_fill_{health,sanity,stealth,stamina}`, `bar_over` | TextureProgressBar, 420 × 40 | fixed size |
| `ammo_panel`, `ammo_pip_full`, `ammo_pip_empty` | throwables counter | fixed size |
| `marker_{objective,exam,intel,danger,offscreen_arrow}` | world and screen-edge markers (objective pivot 48,120) | fixed size |
| `exam_panel_bg` | exam window, 1280 × 760 (layout guide in the file's comment) | scale uniformly |
| `exam_option_{normal,hover,correct,wrong,disabled}` | answer buttons (Theme: Button) | 84, 20, 64, 20 |
| `ring_track`, `ring_fill` | exam countdown / hold-to-interact (radial fill) | fixed size |
| `bn_title_backdrop`, `bn_title_backdrop_red` | ink-brush Bengali title cards; the saffron rule is the matra line | fixed size |
| `bn_tag` | NPC name and title chip | 36, 0, 40, 0 |
| `subtitle_backdrop`, `toast_bg`, `keycap`, `reticle`, `stealth_eye`, `stealth_eye_closed`, `minimap_frame` | HUD furniture | see the comment in each file |

`UiKit.build_theme()` wires all of this into a Theme. See `UiKitDemo.gd` for usage.

**Fonts.** FreeSans is bundled as a fallback because it has Bengali glyphs and shaping tables. For release, add Noto Sans Bengali or Hind Siliguri (both under the free SIL OFL licence) and change `FONT_REGULAR` and `FONT_BOLD` in `UiKit.gd`.

## Honest limits

- **Not tested in Godot.** There is no Godot engine in my workspace, so the GDScript hasn't been run. The API was written against 4.4–4.6, and anything version-sensitive is guarded. If the editor reports an error, paste it and I'll fix it.
- **"As real as the photos" depends on more than this phase.** Procedural PBR maps on box geometry won't look like a photograph on their own. Realism will mostly come from Phase 2: dense geometry, chamfered edges, decals (posters, water stains, wiring), props, and the mess of a real street. This phase sets up the materials, light and atmosphere that all of that sits in.
- **Performance.** SDFGI, volumetric fog and SSIL together are expensive. Aim for a GTX 1660 or RX 5600 class GPU at HIGH with FSR2 at 0.77 scale, and use MEDIUM or LOW for older cards. Measure in the look-dev scene (FPS shows in the corner).
