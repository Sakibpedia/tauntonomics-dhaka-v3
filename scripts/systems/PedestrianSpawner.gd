class_name PedestrianSpawner
extends Node
## Keeps the streets alive around the player: archetypal Dhaka citizens (rickshaw pullers,
## shopkeepers, job seekers with guide books, students, office goers, housewives, hawkers, retired
## teachers who quiz everyone, delivery riders, coaching returnees, nurses, guards, and the
## occasional self-styled "nutritionist" filming a live). Many are hidden Syndicate informants:
## answer them wrong and Heat rises. A few walk up and challenge you to a question. At night the
## streets empty (people go home). Heat stars spawn Syndicate pursuers out of sight.

var s: Services
var _t := 0.0
var crowd: Array = []

const M_NAMES := ["রহিম", "করিম", "জামাল", "কামাল", "সুমন", "রাসেল", "তানভীর", "আরিফ", "মামুন", "শফিক", "হাবিব", "নাসির", "মিজান", "সোহেল", "বাবুল", "জসিম", "আনোয়ার", "রফিক"]
const F_NAMES := ["রুমা", "শিরিন", "নাজমা", "সালমা", "তানিয়া", "মিতু", "রিনা", "পারভীন", "শাহনাজ", "ফারহানা", "নুসরাত", "সুমাইয়া", "লাকী", "মৌসুমী"]
const TYPES := [
	["রিকশাচালক", "m", ["lungi_vest"], ["gk", "bd"], 0.6, 10],
	["দোকানদার", "m", ["lungi_vest", "panjabi"], ["math"], 0.5, 8],
	["চাকরিপ্রার্থী", "x", ["shirt_pants", "salwar"], ["bcs"], 0.95, 12],
	["ছাত্রী", "f", ["salwar", "tshirt_jeans"], ["bangla", "english"], 0.7, 10],
	["অফিসযাত্রী", "m", ["shirt_pants"], ["english", "ict"], 0.5, 10],
	["গৃহিণী", "f", ["saree", "salwar"], ["bangla", "science"], 0.5, 9],
	["হকার", "m", ["tshirt_jeans", "lungi_vest"], ["gk"], 0.4, 7],
	["অবসরপ্রাপ্ত শিক্ষক", "m", ["panjabi"], ["math", "bangla", "english"], 1.0, 4],
	["ডেলিভারিম্যান", "m", ["tshirt_jeans"], ["ict"], 0.5, 6],
	["কোচিং-ফেরত ছাত্র", "m", ["tshirt_jeans", "shirt_pants"], ["bcs", "mental"], 0.9, 8],
	["নার্স", "f", ["labcoat"], ["science"], 0.7, 3],
	["নিরাপত্তারক্ষী", "m", ["guard"], ["gk", "english"], 0.8, 3],
	["স্বঘোষিত 'নিউট্রিশনিস্ট'", "f", ["salwar"], ["science"], 0.6, 2],
]

static var _prewarmed := false

func setup(services: Services) -> void:
	s = services
	s.heat.pursue.connect(_pursue)
	if s.quality <= 0 and not _prewarmed:
		_prewarmed = true
		_prewarm_meshes()
	_spawn_cc0_bystanders()

## Real CC0-modelled people standing around the safehouse square (1 draw call each), so the
## crowd isn't only procedural low-poly rigs. They are ambient set dressing, not interactable.
func _spawn_cc0_bystanders() -> void:
	var w := s.world as ProceduralDhaka
	if w == null or s.player == null:
		return
	var names := CC0Assets.characters()
	var centre: Vector3 = w.poi("safehouse") + Vector3(6.0, 0.0, 4.0)
	for i in 8:
		var nm := names[i % names.size()]
		var n: Node3D = CC0Assets.make_character(nm)
		if n == null:
			continue
		CC0Assets.no_shadows(n)
		w.add_child(n)
		var ang := TAU * float(i) / 8.0
		n.global_position = centre + Vector3(cos(ang) * randf_range(3.0, 7.0), 0.0, sin(ang) * randf_range(3.0, 7.0))
		n.rotation.y = randf_range(0.0, TAU)

## Build the most common citizen rigs during loading, so the first few spawns don't hitch.
func _prewarm_meshes() -> void:
	var looks := [
		{"sex": "m", "outfit": "lungi_vest", "hair": "short", "age": 0.35},
		{"sex": "m", "outfit": "shirt_pants", "hair": "short", "age": 0.3},
		{"sex": "m", "outfit": "tshirt_jeans", "hair": "short", "age": 0.25},
		{"sex": "m", "outfit": "panjabi", "hair": "short", "age": 0.7},
		{"sex": "m", "outfit": "guard", "hair": "short", "age": 0.4},
		{"sex": "f", "outfit": "salwar", "hair": "long", "age": 0.3},
		{"sex": "f", "outfit": "saree", "hair": "long", "age": 0.45},
		{"sex": "f", "outfit": "tshirt_jeans", "hair": "long", "age": 0.2},
		{"sex": "f", "outfit": "labcoat", "hair": "long", "age": 0.35},
	]
	var tmp := Node3D.new()
	add_child(tmp)
	for l in looks:
		var h := Humanoid.new()
		tmp.add_child(h)
		h.setup(l)
		h.free()
	tmp.free()

func _target_pop() -> int:
	var base := 22
	if s.clock.is_night():
		base = 3
	else:
		match str((s.world as ProceduralDhaka).style):
			"slum", "market", "plaza", "commercial", "commercial_hi": base = 30
			"newtown", "industrial": base = 10
			"tower_roof": base = 0
	if s.quality <= 0:
		base = int(ceil(base * 0.4))
	return base

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_impl(delta)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if ms > 6.0 and OS.get_environment("DHAKA_LOG_SLOW") != "":
		print("SLOW crowd %.1f ms" % ms)

func _process_impl(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or s.player == null or not is_instance_valid(s.player):
		return
	_t = 0.9 if s.quality <= 0 else 0.7
	var pp := (s.player as Node3D).global_position
	var keep: Array = []
	for a in crowd:
		if not is_instance_valid(a):
			continue
		var ac := a as Actor
		if ac.global_position.distance_to(pp) > 80.0 and ac.mission_tag == "" and not ac.story_char:
			ac.queue_free()
			continue
		keep.append(ac)
	crowd = keep
	if pp.y > 6.0:
		return
	if crowd.size() < _target_pop():
		# LOW spawns one at a time: each citizen builds a rig, so batches cause visible hitches.
		var batch := 1 if s.quality <= 0 else 3
		for k in mini(batch, _target_pop() - crowd.size()):
			_spawn(pp)

func _spawn(pp: Vector3) -> void:
	var w := s.world as ProceduralDhaka
	var at := w.random_sidewalk_point(pp, 50.0)
	if at.distance_to(pp) < 18.0:
		return
	var total := 0
	for t in TYPES:
		total += int((t as Array)[5])
	var r := randi() % total
	var ty: Array = TYPES[0]
	for t in TYPES:
		r -= int((t as Array)[5])
		if r < 0:
			ty = t
			break
	var sex := str(ty[1])
	if sex == "x":
		sex = "f" if randf() < 0.45 else "m"
	var outfits: Array = ty[2]
	var outfit := str(outfits[randi() % outfits.size()])
	if sex == "f" and outfit in ["shirt_pants", "lungi_vest", "panjabi"]:
		outfit = "salwar"
	if sex == "m" and outfit in ["salwar", "saree"]:
		outfit = "shirt_pants"
	var age := randf_range(0.12, 0.6)
	if str(ty[0]) == "অবসরপ্রাপ্ত শিক্ষক":
		age = randf_range(0.8, 1.0)
	var hair := "short"
	if sex == "f":
		hair = ["long", "bun", "hijab", "long"][randi() % 4]
	elif age > 0.8 and randf() < 0.5:
		hair = "cap_white"
	elif randf() < 0.1:
		hair = "bald"
	var beard := "none"
	if sex == "m":
		beard = ["none", "stubble", "full", "moustache", "none"][randi() % 5]
	var look := {"sex": sex, "outfit": outfit, "hair": hair, "beard": beard, "age": age, "glasses": randf() < 0.2, "gamchha": outfit == "lungi_vest" and randf() < 0.6,
		"colors": [Color.from_hsv(randf(), randf_range(0.25, 0.7), randf_range(0.35, 0.85)).to_html(), Color.from_hsv(randf(), randf_range(0.1, 0.5), randf_range(0.15, 0.6)).to_html()]}
	var nm: String = (F_NAMES[randi() % F_NAMES.size()] if sex == "f" else M_NAMES[randi() % M_NAMES.size()])
	var faction := "pseudo" if str(ty[0]).begins_with("স্বঘোষিত") else "civilian"
	var t0 := Time.get_ticks_usec()
	var a := Actor.new()
	s.world.add_child(a)
	a.global_position = at + Vector3(0, 0.2, 0)
	a.setup(s, {"id": "p_%d" % randi(), "name": nm, "role": str(ty[0]), "faction": faction, "cats": ty[3], "examiner": ty[4], "look": look,
		"informant": randf() < 0.15, "state": "wander" if randf() < 0.8 else "stand"})
	if str(ty[0]) == "চাকরিপ্রার্থী" or str(ty[0]) == "কোচিং-ফেরত ছাত্র":
		a.body.hold("book")
		if randf() < 0.4:
			a.body.set_sustain("read", true)
	elif faction == "pseudo":
		a.body.hold("phone")
		a.body.set_sustain("phone", true)
	elif str(ty[0]) == "দোকানদার" and randf() < 0.5:
		a.ai.set_state(ActorAI.State.STAND)
	if randf() < 0.06 and not s.clock.is_night():
		a.ai.set_state(ActorAI.State.CHALLENGE)
		a.say(s.taunts.pick("challenge"), 4.0)
		a.visuals.set_icon("exam")
	crowd.append(a)
	if OS.get_environment("DHAKA_LOG_STREAM") != "":
		print("STREAM actor built in %.1f ms (crowd %d)" % [(Time.get_ticks_usec() - t0) / 1000.0, crowd.size()])

func _pursue(stars: int) -> void:
	if s.player == null or not is_instance_valid(s.player) or s.missions == null:
		return
	var pp := (s.player as Node3D).global_position
	var cam := s.camera as PlayerCamera
	var behind := -cam.forward_flat() if cam else Vector3(1, 0, 0)
	var n := mini(stars, 3)
	for k in n:
		var at := (s.world as ProceduralDhaka).random_sidewalk_point(pp + behind * 28.0, 8.0)
		if pp.y > 6.0:
			at = (s.world as ProceduralDhaka).random_roof_point(pp, 20.0)
		var g := (s.missions as MissionDirector)._spawn_goon(at, true, "goon")
		(s.missions as MissionDirector).spawned.erase(g)
		crowd.append(g)
		g.mission_tag = "pursuer"
	# Police siren removed by request — no background vehicle noise.
