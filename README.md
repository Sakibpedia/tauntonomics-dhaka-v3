# ট্যান্ট-ও-নমিক্স: ঢাকা (Taunt-o-Nomics: Dhaka)

A 3D, open-city satire game in Bengali, made with Godot 4.6.
**নির্মাতা ও স্বত্বাধিকারী: এস এম নাজমুয সাকিব** (Developed and copyrighted by S M Nazmuz Sakib).

## Play
| Platform | File | How |
|---|---|---|
| Windows | `build/windows/TauntONomics_Dhaka.exe` | Double-click. Everything is embedded in the one file. |
| Web | `build/web/index.html` | Serve the folder over HTTP (for example `python -m http.server` inside `build/web`), then open `http://localhost:8000`. Browsers block `file://` loading. It uses the single-threaded build, so no special server headers are needed. |
| Android | `build/android/TauntONomics_Dhaka.apk` | Copy to the phone and install (allow "install unknown apps"). Android 7+, arm64. |

**Voice:** dialogue is spoken through the system text-to-speech if a Bengali voice is installed (Windows: add the Bangla language pack with speech; Android: Google TTS → install Bengali). Otherwise you get subtitles only.

## Edit / build
1. Open the folder in Godot 4.6 (Forward+).
2. Regenerate content (optional; Python 3 with numpy, Pillow and cryptography):
   - `python tools/generate_textures.py --out assets/textures --size 1024` then `python tools/fix_imports.py assets/textures`
   - `python tools/generate_questions.py` → `data/questions/questions.json` (3,214 questions)
   - `python tools/make_story.py` → `data/story/*.json` (20 levels, 77 missions, cast, debates, posters)
3. Export with the presets in `export_presets.cfg` (Windows, Web, Android).
   For Android, export unsigned, then sign with `python tools/sign_apk.py unsigned.apk signed.apk` (APK Signature Scheme v2). The key is in `tools/android_signing/`; keep it, because updates must use the same key. For the Play Store, re-sign with your own upload key using Google's `apksigner`.

## Folder map
- `scripts/core`: Main, Services (dependency injection), EventBus, SaveData, GameClock, Heat, QuestionDB, TauntBank, StoryDB, Sfx, Fx, Speech, TestBot
- `scripts/actors`: Humanoid, Actor, ActorAI, ActorHealth, ActorVisuals, Player, PlayerCamera, Ghost, Ragdoll, Projectile
- `scripts/world`: ProceduralDhaka, Poster, Pickup, Usable, Candle, window shader
- `scripts/systems`: MissionDirector, GhostDirector, PedestrianSpawner, Traffic, Vehicle, BossBrain
- `scripts/ui`: UIRoot (HUD), Minimap, ExamPanel, ConversationPanel, DialogueBrain, DebatePanel, PhonePanel, MainMenu, TouchControls, UiKit
- `scripts/render`: DhakaAtmosphere, LookdevAlley (Phase 1 look-dev)
- `docs/DESIGN.md`: the design document and full story

## Credits and licences
Code, story and generated assets © S M Nazmuz Sakib. Fonts: Noto Sans Bengali (SIL Open Font License, `assets/fonts/LICENSE-NotoSansBengali-OFL.txt`), GNU FreeFont (GPL with font exception). Engine: Godot (MIT).
Statute section titles come from the official English texts on bdlaws.minlaw.gov.bd. Past BCS questions are cited by exam and question number. All characters, colleges, hospitals and organisations are fictional.
