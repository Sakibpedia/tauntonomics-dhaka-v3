# ট্যান্ট-ও-নমিক্স: ঢাকা — Game Design Document

**Developed and copyrighted by S M Nazmuz Sakib (এস এম নাজমুয সাকিব).** Engine: Godot 4.6 (Forward+, Jolt Physics). Language: Bengali throughout. All people, colleges, hospitals and the Syndicate are fictional. Real place names (Sontek, Kajla, Jatrabari, Sadarghat, Nilkhet, Shahbag, Farmgate…) are settings only.

## 1. Premise
An unemployed lawyer who has reached the BCS viva three times and been told "পদ শূন্য নেই" (no vacancy) every time learns why. A coaching syndicate run by the unseen **মহাপরীক্ষক** (Grand Examiner) sells leaked questions. The same people sell fake "clinical nutrition" certificates to Home Economics graduates and bankroll the protests that demand those titles. Sakib fights back with the only weapons an unemployed lawyer has: three thousand answers, a law book, his fists and his tongue.

**Satire target:** title inflation ("Clinical Nutritionist" printed on a Home Economics degree), affiliated colleges calling themselves university departments, unaccredited certificates, influencer diet charts that harm patients, the coaching-and-leak economy, and unemployment. Home Economics as a subject is treated with respect in the script. The villains are the people who sell false titles and leaked questions.

## 2. Pillars
1. **Questions are the weapon.** Every gate, poster, NPC, ghost, dying goon and boss lectern uses the same exam system and the same no-repeat bank of 3,214 questions.
2. **A GTA-style city that answers back.** Open streets and rooftops, crowds, traffic, Heat stars, a CNG you can drive, conversations with anyone.
3. **Choices that haunt you.** Downed Syndicate members can be arrested, spared, or finished. Finish one and he asks a last question. Fail it and he returns every night as a question-ghost until you answer.
4. **Night is dangerous (the Minecraft rule).** After dusk, sanity drains in the dark. Ghosts rise away from lamps. Roofs, lamp light and candles keep you safe, and the sun burns ghosts at dawn.

## 3. Story — three acts, twenty districts
| Act | Levels | Arc |
|---|---|---|
| ১ সনদ (The Certificate) | 1–6 | Sontek tea-stall rumours → Jatrabari courier → Old Dhaka printing press (fake "clinical" certificates) → Sadarghat (the leak's river route) → Nilkhet guide-book market and the first protest → Shahbag mega-rally (it's funded by the coaching account) |
| ২ প্রশ্নফাঁস (The Leak) | 7–14 | Farmgate "সাত দিনে ক্যাডার" coaching → Motijheel coded posters → Karwan Bazar night press → Sontek City General (the "nutrition desk" trays) → Mirpur slum (defrauded graduates) → Kamrangirchar tannery trap → Gulshan tender party → Kakrail insider |
| ৩ ভাইভা (The Viva) | 15–20 | Revenge night at Jurain → TSC unity debate → Purbachal ghost town → Sarbangin Bhaban floors 1–9 → rooftop "মহাভাইভা" boss |

**Endings** (from your choices; see `SaveData.ending()`): **ন্যায়ের ভাইভা** (mostly arrests: the cases hold), **প্রতিশোধের রায়** (more executions than arrests), **প্রশ্নভূতের শহর** (four or more unanswered ghosts still walk).

**Cast:** 26 story characters, 7 patients and 13 pedestrian archetypes. Highlights: নাসিমা খালা (tea stall), বাবুল (rickshaw puller with a master's degree), হাকিম স্যার (retired maths teacher), তুম্পা (reporter), লিলি (CS student), রুমানা (a Home Economics graduate who was defrauded and becomes an ally), জিরাপানি জেসমিন (self-declared "nutritionist" influencer), the Syndicate (কামরুল 'কোর্সওয়ালা', মন্টু, হারুন, ছুরি জামাল, টেন্ডার তালুকদার, 'সিল' সামাদ), ইন্সপেক্টর মাহফুজ, ডা. ফারজানা, অধ্যক্ষ সিলেবাসউদ্দিন, মহাপরীক্ষক.

## 4. Missions — 77 missions, 20 step types
`cutscene, goto, talk, exam, collect, posters, defeat, survive, eliminate, escape_roof, debate, tail, sneak, deliver, survive_night, advise, swap, drive, buy, boss`. They are data-driven: `tools/make_story.py` writes `data/story/levels.json`, and `MissionDirector.gd` interprets it. Dying restarts the current step. Rewards: money, intel, empathy, candles.

## 5. The exam system
- 3,214 questions in 10 categories: past BCS papers (61, with exam and question number), statute sections (751, from bdlaws.minlaw.gov.bd: Penal Code, Evidence Act, CPC, CrPC), computed maths (632), mental ability (284), Bengali (756), English (307), international GK (280), Bangladesh (65), science (52), ICT (26).
- **No repeats:** each category keeps a shuffled deck; seen IDs are stored in the save; a category reshuffles only when it is exhausted.
- Countdown by difficulty, keys ১–৪, a ৫০:৫০ lifeline (call Hakim sir, ৳১৫০), and an explanation plus source after every answer.
- **A wrong answer alerts the Syndicate.** Hidden informants (about 15% of pedestrians) and Syndicate gatekeepers raise Heat when you fail.

## 6. People (Humanoid + Actor)
- **Humanoid:** lofted, anatomically shaped bodies (male pectorals and broader shoulders; female bust, waist and hip lobes), and a sculpted head. The head is a displacement field (eye sockets, brow ridge, cheekbones, nose, lips, chin, jaw) with painted vertex-colour make-up. Proportions and skin tones are calibrated from the two reference portraits; every NPC face is a randomised variant, so none copies a real person. Hair: short, long, bun, bald, hijab, tupi. Beards: full, stubble, moustache. Clothing: lungi and gamchha, panjabi, saree with pallu, salwar-kameez with dupatta, shirt and trousers, T-shirt and jeans, suit, lawyer's coat with bands, lab coat, police and guard uniforms, goon bandana.
- **Animation:** procedural walk/run with heel-toe and counter-rotation, age-dependent gait, lean, 30+ clips (punches, hook, kick, parry, dodge roll, throw, slogan, clap, taunt, facepalm, talk gestures…), 16 sustained poses, look-at with eye tracking, blinking almond eyelids, lip-sync, a hit spring, skirt and dupatta physics, and a Jolt ragdoll on death.
- **Actor = ActorVisuals + ActorHealth + ActorAI**, injected with `Services`. The AI is a state machine with a sight cone and hearing, a stealth meter, schedules (people go home at night), crowd reactions (flee, cower, film it for a live stream), protests, and melee with attack tokens, wind-up tells, blocks and brick throws.
- **Verbal interaction:** every person talks. There are scripted mission lines, choice menus, and a free-text box (Bengali, Banglish or English) whose intent the offline `DialogueBrain` classifies. Replies use the speaker's faction, role, memory of you, the time, Heat, ghosts and your objective (with real compass directions). Speech goes through the OS text-to-speech when a Bengali voice is installed.

## 7. Combat and fate
Three-hit combo, kick, block and parry, dodge roll, lock-on, bricks to throw, the law-book shield (Q: stops projectiles), and taunts (T: make goons reckless; near pseudo-nutritionists they become satire lines). Civilians, students and patients can only be knocked out. Protesters are beaten by debate. Downed Syndicate members get a fate choice: **গ্রেপ্তার / শেষ করুন / ছেড়ে দিন**.

## 8. Night and the question-ghosts
Dusk 19:00 to dawn 05:30. While you are outside and unprotected, sanity drains. Ghosts spawn in dark spots (light level from lamps, 28% of which are broken): first the recorded ghosts of the people you finished, then random "unanswered question" ghosts. They taunt you with their question, drain sanity and health, and throw homing question papers. Press E near one to answer it and set it free. Protection: under a roof, within 5 m of a working lamp, within 6 m of a candle, or in the safehouse. Sleeping in the safehouse bed skips to dawn and saves.

## 9. Debates (protests)
Each claim has a best card and acceptable cards: সনদ যাচাই, আইনের ধারা, পাঠ্যসূচি তুলনা, রোগীর সাক্ষ্য (strong only if you gave good advice in the hospital, Level 10), পাল্টা প্রশ্ন (a live BCS question), সহমর্মিতা, টাকার উৎস (costs intel), নীরবতা. Good answers lower conviction and protesters join you. Bad ones raise anger and slippers fly.

## 10. The city (ProceduralDhaka)
Based on the photo survey of Sontek and Kajla:
- 56 m blocks with 14 m main roads (every third street) and 7 m lanes; street-facing lots with zero gaps.
- Pastel plaster or brick walk-ups. Per bay: an aluminium window, a protruding steel box grill and a concrete chajja sunshade. Balconies with drying clothes, AC units.
- Shops with rolling shutters, warm interiors and Bengali signboards.
- Roofs with parapets, the stair tower and its green tin canopy, black water tanks, stairs from the gate to the roof, and ladders between roofs of different heights.
- Concrete poles with sagging wire tangles, sodium lamps, trees, parked rickshaws, brick piles, posters and banners.
- 16 district styles, including the riverside ghat, a tin-roofed slum, half-built frames in Purbachal and the nine-storey tower with real floors and switchback ramps.
- Streaming: detailed blocks are built within two blocks of the player (one per frame) and freed beyond three; distant blocks are an instanced skyline. Pedestrians path along an A* sidewalk graph.

## 11. Rendering ("URP" equivalent)
`DhakaAtmosphere`: SDFGI, SSAO, SSIL, SSR, volumetric fog and street smog FogVolumes, AgX tonemapping, colour grading, 4-split PSSM shadows, auto-exposure. `GameClock` blends four presets around a 24-minute day and swings the sun. Window glass uses a shader that lights rooms at night. A 14-light pool follows the nearest working street lamps. Web and Android builds use the Compatibility renderer automatically, at low quality.

## 12. Architecture (dependency injection)
`Main` builds one `Services` node (EventBus, SaveData, GameClock, Heat, QuestionDB, TauntBank, StoryDB, Sfx, Fx) and passes it to everything. There are no autoload singletons. Per-level systems are MissionDirector, GhostDirector, PedestrianSpawner, Traffic, ProceduralDhaka, Player and PlayerCamera. `UIRoot` holds the HUD, radar, exam, conversation, debate and phone panels, touch controls and cutscenes. All audio is synthesised at runtime and all textures are generated by `tools/generate_textures.py`.

## 13. Controls
WASD move • Shift sprint • Space jump • C crouch • E talk/use • LMB punch • MMB/X kick • F block/parry • V dodge • Q law-book shield • G pick up brick • RMB aim • T taunt • B candle • R lock-on • Tab/M/Esc phone • 1–4 answer. In the CNG: W/S, A/D, Shift boost, Space horn, E exit. Gamepad and touch (Android/mobile web) are supported.

## 14. QA
`DHAKA_BOT=1,20 godot --headless --path . --fixed-fps 30` plays all 77 missions automatically (`TestBot.gd`). `DHAKA_AUTOSTART=<level> DHAKA_VIEW=street|night|roof|exam|convo|tower` renders screenshots.
