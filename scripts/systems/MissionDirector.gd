class_name MissionDirector
extends Node
## Runs the 20 levels × 4–5 missions from data/story/levels.json. Each mission is a list of steps:
## cutscene, goto, talk, exam, collect, posters, defeat, survive, eliminate, escape_roof, debate,
## tail, sneak, deliver, survive_night, advise, swap, drive, buy, boss. The director spawns
## what a step needs (story characters, goons, crowds, items, trays, the CNG, the boss), shows the
## objective and marker, checks completion, pays rewards, saves, and moves on. Dying restarts the
## current step. Story characters are spawned once per level and reused.

var s: Services
var level: Dictionary = {}
var mi := 0
var si := 0
var step: Dictionary = {}
var mission: Dictionary = {}
var chars: Dictionary = {}          # id -> Actor
var spawned: Array = []             # step-scoped nodes
var counter := 0
var need := 0
var timer := 0.0
var wave := 0
var target: Actor
var tail_actor: Actor
var _lost_t := 0.0
var _done_level := false
var _step_live := false
var _debate_cool := 0.0
var _ghosts_at_start := 0
var _was_night := false
var _advised: Dictionary = {}
var _vehicle: Node3D
var _boss: Actor
var _lecterns_done := 0

const GOON_LOOKS := [
	{"sex": "m", "outfit": "goon", "hair": "short", "beard": "stubble", "colors": ["#141414", "#a61b1b"]},
	{"sex": "m", "outfit": "goon", "hair": "short", "beard": "full", "colors": ["#1b1b22", "#c0262d"]},
	{"sex": "m", "outfit": "tshirt_jeans", "hair": "short", "beard": "moustache", "colors": ["#222222", "#a61b1b"]},
	{"sex": "m", "outfit": "shirt_pants", "hair": "short", "beard": "stubble", "colors": ["#3a1010", "#141414"]},
]

func setup(services: Services, lvl: Dictionary) -> void:
	s = services
	level = lvl
	s.bus.item_collected.connect(_on_item)
	s.bus.poster_answered.connect(_on_poster)
	s.bus.ghost_banished.connect(func(_g: Node) -> void: _check_night())
	s.bus.actor_downed.connect(_on_downed)

func start(from_mission: int = 0) -> void:
	mi = clampi(from_mission, 0, (level.get("missions", []) as Array).size())
	var intro: Array = level.get("intro", [])
	var act := s.story.act_of(int(level["id"]))
	var lines: Array = []
	if mi == 0:
		lines.append("[b][color=#ffd27a]%s[/color][/b]\nলেভেল %s: %s — %s" % [str(act.get("name", "")), BnText.num(int(level["id"])), str(level["name"]), str(level["subtitle"])])
		lines.append_array(intro)
	else:
		lines.append("[b]%s[/b] — আগের জায়গা থেকে চালিয়ে যাচ্ছেন" % str(level["name"]))
	s.ui.call("cutscene", lines, func() -> void: _start_mission())

func level_label() -> String:
	return "লেভেল %s • %s" % [BnText.num(int(level.get("id", 1))), str(level.get("name", ""))]

func current_title() -> String:
	if _done_level or mission.is_empty():
		return "মুক্ত বিচরণ"
	return "মিশন %s/%s: %s" % [BnText.num(mi + 1), BnText.num((level["missions"] as Array).size()), str(mission.get("title", ""))]

func objective_text() -> String:
	if step.is_empty():
		return "পোস্টারের প্রশ্ন, পথচারীদের চ্যালেঞ্জ আর শহর ঘুরে দেখুন।"
	var t := str(step.get("text", ""))
	match str(step.get("type", "")):
		"collect", "posters", "defeat", "swap", "advise":
			t += "  (%s/%s)" % [BnText.num(counter), BnText.num(need)]
		"survive":
			t += "  (%s সেকেন্ড)" % BnText.num(int(ceil(maxf(timer, 0.0))))
		"survive_night":
			if need > 0:
				t += "  (মুক্ত: %s/%s)" % [BnText.num(counter), BnText.num(need)]
			else:
				t += "  (ভোর পর্যন্ত %s ঘণ্টা)" % BnText.num(int(ceil(s.clock.hours_to_dawn())))
	return t

func marker_pos() -> Variant:
	if step.is_empty() or not _step_live:
		return null
	var ty := str(step.get("type", ""))
	match ty:
		"talk", "exam", "deliver", "buy":
			var a := _char_if(str(step.get("npc", "")))
			if a:
				return a.global_position
		"eliminate":
			if target and is_instance_valid(target):
				return target.global_position
		"tail":
			if tail_actor and is_instance_valid(tail_actor):
				return tail_actor.global_position
		"collect":
			return _nearest_group(spawned, "pickups")
		"posters":
			return _nearest_poster()
		"swap":
			var best: Variant = null
			var bd := 1e9
			for n in spawned:
				if n is Usable and is_instance_valid(n) and (n as Usable).enabled:
					var d := (n as Node3D).global_position.distance_to((s.player as Node3D).global_position)
					if d < bd:
						bd = d
						best = (n as Node3D).global_position
			return best
		"advise":
			for n in spawned:
				if n is Actor and is_instance_valid(n) and not _advised.has((n as Actor).id):
					return (n as Actor).global_position
		"drive":
			if _vehicle and is_instance_valid(_vehicle) and not bool(_vehicle.get("driven")):
				return _vehicle.global_position
		"survive_night", "cutscene":
			return null
		"boss":
			for n in spawned:
				if n is Usable and is_instance_valid(n) and (n as Usable).enabled:
					return (n as Node3D).global_position
			if _boss and is_instance_valid(_boss):
				return _boss.global_position
			return null
	if step.has("poi"):
		return _poi(str(step["poi"]))
	return null

func _poi(name: String) -> Vector3:
	return (s.world as ProceduralDhaka).poi(name)

# ---------------------------------------------------------------- flow
func _start_mission() -> void:
	var ms: Array = level.get("missions", [])
	if mi >= ms.size():
		_finish_level()
		return
	mission = ms[mi]
	si = 0
	s.save.s("mission", mi)
	var tod: Variant = mission.get("time")
	if tod == "night" and not s.clock.is_night():
		s.clock.set_hour(20.0)
	elif tod == "dusk" and s.clock.hour < 17.5 and s.clock.hour > 6.0:
		s.clock.set_hour(18.2)
	s.bus.mission_started.emit(str(mission["id"]), str(mission["title"]))
	s.ui.call("banner_show", str(mission["title"]), str(mission.get("brief", "")), UiKit.SAFFRON, 4.5)
	s.sfx.play("news", -6.0)
	_start_step()

func _start_step() -> void:
	_cleanup()
	var steps: Array = mission.get("steps", [])
	if si >= steps.size():
		_complete_mission()
		return
	step = steps[si]
	counter = 0
	need = 0
	timer = 0.0
	wave = 0
	_step_live = true
	var ty := str(step.get("type", ""))
	var poi := str(step.get("poi", ""))
	if poi != "":
		(s.world as ProceduralDhaka).ensure_built(_poi(poi), 1)
	s.bus.mission_step.emit(str(step.get("text", "")))
	match ty:
		"cutscene":
			s.ui.call("cutscene", step.get("lines", []), _advance)
		"goto":
			pass
		"talk", "deliver", "exam", "buy":
			var npc := str(step.get("npc", ""))
			_ensure_char(npc, _poi(poi))
		"collect":
			need = int(step.get("count", 1))
			for k in need:
				var p := Pickup.new()
				s.world.add_child(p)
				var at := _poi(poi) + Vector3(randf_range(-10, 10), 0.0, randf_range(-10, 10))
				if k == need - 1 and need >= 3:
					at = (s.world as ProceduralDhaka).random_roof_point(_poi(poi), 40.0)
					(s.world as ProceduralDhaka).ensure_built(at, 0)
				elif s.world.has_method("random_sidewalk_point") and k % 2 == 1:
					at = (s.world as ProceduralDhaka).random_sidewalk_point(_poi(poi), 25.0)
				p.global_position = at
				p.setup(s, str(step.get("item", "bundle")))
				spawned.append(p)
			if poi == "den" or poi == "coaching" or poi == "printing":
				for g in 2:
					_spawn_goon(_poi(poi) + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), false, "guard")
		"posters":
			need = int(step.get("count", 3))
			_spawn_poster_stands(str(step.get("kind", "bcs_quiz")), need + 2)
		"defeat":
			need = int(step.get("count", 3))
			for k in need:
				_spawn_goon(_poi(poi) + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), true, str(step.get("enemy", "goon")))
		"survive":
			timer = float(step.get("seconds", 60))
			var sw := maxi(1, int(step.get("waves", 3)) - int(level.get("id", 1)) / 2)
			step["waves"] = sw
			_spawn_wave()
		"eliminate":
			var tid := str(step.get("target", ""))
			target = _spawn_char(tid, _poi(poi), "guard")
			target.hostile = true
			target.faction = "syndicate"
			target.health.setup(160.0, 0.15)
			target.health.can_recover = false
			target.ai.damage = 14.0
			target.ai.block_chance = 0.35
			target.mission_tag = "target"
			spawned.append(target)
			var guard_count := maxi(1, int(step.get("guards", 2)) - int(level.get("id", 1)))
			for g in guard_count:
				_spawn_goon(_poi(poi) + Vector3(randf_range(-7, 7), 0, randf_range(-7, 7)), false, "guard")
		"escape_roof":
			s.heat.set_level(minf(3, 1 + float(level.get("id", 1)) * 0.4), true)
			var chase_count := maxi(1, int(step.get("chasers", 2)) - int(level.get("id", 1)) * 2)
			for k in chase_count:
				_spawn_goon(_near_player(14.0, 22.0), true, "goon")
		"debate":
			_spawn_protest(_poi(poi), str(step.get("debate", "")))
		"tail":
			var from := _poi(str(step.get("from", "bus_stand")))
			var to := _poi(str(step.get("to", "den")))
			(s.world as ProceduralDhaka).ensure_built(to, 1)
			tail_actor = _spawn_actor({"id": "courier", "name": "কুরিয়ার", "role": "সিন্ডিকেটের বাহক", "faction": "civilian", "cats": ["gk"],
				"look": {"sex": "m", "outfit": "goon", "hair": "short", "beard": "stubble", "gamchha": true, "colors": ["#101010", "#c0262d"]}, "state": "idle", "walk": 1.5}, from + Vector3(0, 0, 3))
			tail_actor.mission_tag = "courier"
			tail_actor.ai.on_spot = func() -> void: _fail_step("কুরিয়ার আপনাকে দেখে ফেলেছে!")
			tail_actor.ai.on_arrive = func() -> void:
				s.toast("কুরিয়ার আস্তানায় ঢুকল। জায়গাটা চিনে রাখলেন।", "good")
				_advance()
			var route := (s.world as ProceduralDhaka).street_path(from, to)
			tail_actor.ai.call_deferred("start_tail", route)
			spawned.append(tail_actor)
			_lost_t = 0.0
		"sneak":
			var sg := maxi(1, int(step.get("guards", 4)) - int(level.get("id", 1)))
			for k in sg:
				var ang := TAU * k / float(maxi(1, sg))
				var gp := _poi(poi) + Vector3(cos(ang), 0, sin(ang)) * 8.0
				var g := _spawn_goon(gp, false, "guard")
				g.ai.patrol = [gp, gp + Vector3(cos(ang + 1.2), 0, sin(ang + 1.2)) * 6.0, gp + Vector3(cos(ang - 1.2), 0, sin(ang - 1.2)) * 6.0]
				g.ai.set_state(ActorAI.State.PATROL)
		"survive_night":
			need = int(step.get("banish", 0))
			_ghosts_at_start = int(s.save.g("ghosts_banished", 0))
			if not s.clock.is_night():
				s.clock.set_hour(19.6)
			_was_night = true
			if s.ghosts:
				s.ghosts.call("ensure_minimum", maxi(need, 1))
		"advise":
			var pids: Array = step.get("patients", [])
			need = pids.size()
			_advised.clear()
			var base := _poi(poi)
			for k in pids.size():
				var pid := str(pids[k])
				var pd: Dictionary = s.story.patients.get(pid, {})
				var cd := s.story.character(pid)
				var a := _spawn_actor({"id": pid, "name": str(pd.get("name", "রোগী")), "role": "রোগী: " + str(pd.get("condition", "")), "faction": "patient",
					"cats": ["science"], "look": cd.get("look", {}), "state": "stand", "story": true}, base + Vector3(-3.0 + k * 3.0, 0.0, 2.4))
				a.body.set_sustain("sit", true)
				spawned.append(a)
		"swap":
			need = int(step.get("count", 3))
			var base2 := _poi(poi)
			for k in need:
				var u := Usable.new()
				u.prompt = "বিষাক্ত ট্রে বদলে দিন (E চেপে ধরে রাখুন)"
				u.hold_time = 2.5
				u.once = true
				s.world.add_child(u)
				u.global_position = base2 + Vector3(-4.0 + k * 4.0, 0.9, 3.5)
				var tray := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.5, 0.05, 0.35)
				tray.mesh = bm
				tray.material_override = Humanoid.plain_material(Color(0.75, 0.75, 0.78), 0.3, 0.6)
				u.add_child(tray)
				u.on_use = func(_p: Node) -> void:
					counter += 1
					tray.material_override = Humanoid.plain_material(Color(0.3, 0.8, 0.4), 0.4)
					s.sfx.play("click", -4.0)
					if counter >= need:
						_advance()
				spawned.append(u)
			for g2 in 2:
				var gg := _spawn_goon(base2 + Vector3(randf_range(-6, 6), 0, randf_range(4, 8)), false, "guard")
				gg.display_name = "পুষ্টি-ডেস্কের পাহারাদার"
		"drive":
			_vehicle = Vehicle.new()
			s.world.add_child(_vehicle)
			_vehicle.global_position = _near_player(5.0, 8.0)
			_vehicle.call("setup", s)
			spawned.append(_vehicle)
		"boss":
			_spawn_boss()
	if ty == "survive" or ty == "defeat":
		s.sfx.play("alarm", -8.0)

func _advance() -> void:
	if not _step_live:
		return
	_step_live = false
	s.sfx.play("ding", -6.0)
	si += 1
	get_tree().create_timer(0.8).timeout.connect(_start_step)

func _fail_step(reason: String) -> void:
	if not _step_live:
		return
	_step_live = false
	s.ui.call("banner_show", "মিশন ব্যর্থ", reason, UiKit.SIGNAL_RED, 3.5)
	s.sfx.play("sting", -4.0)
	get_tree().create_timer(3.0).timeout.connect(_start_step)

func _complete_mission() -> void:
	var reward: Dictionary = mission.get("reward", {"money": 300})
	if reward == null:
		reward = {"money": 300}
	var parts: Array[String] = []
	for k in reward.keys():
		s.save.add(str(k), float(reward[k]))
		var nm := {"money": "টাকা", "intel": "ইন্টেল", "empathy": "সহমর্মিতা", "candles": "মোমবাতি"}.get(str(k), str(k)) as String
		parts.append("%s +%s" % [nm, BnText.num(int(reward[k]))])
	s.heat.clear()
	s.bus.mission_completed.emit(str(mission["id"]), reward)
	s.ui.call("banner_show", "মিশন সম্পন্ন!", "%s\n%s" % [str(mission["title"]), "  ".join(parts)], Color(0.5, 1.0, 0.6), 4.0)
	s.sfx.play("sting_win", -2.0)
	mi += 1
	s.save.s("mission", mi)
	if s.main:
		s.main.call("save_now")
	step = {}
	get_tree().create_timer(4.5).timeout.connect(_start_mission)

func _finish_level() -> void:
	_done_level = true
	step = {}
	mission = {}
	s.bus.level_completed.emit(int(level["id"]))
	if s.main:
		s.main.call("level_complete")

func on_player_respawn() -> void:
	if not step.is_empty():
		_step_live = false
		get_tree().create_timer(0.5).timeout.connect(_start_step)

func on_slept() -> void:
	if str(step.get("type", "")) == "survive_night" and need == 0:
		_advance()

# ---------------------------------------------------------------- per frame checks
func _process(delta: float) -> void:
	if step.is_empty() or not _step_live or s.player == null or not is_instance_valid(s.player):
		return
	var p := s.player as Player
	var pp := p.global_position
	match str(step.get("type", "")):
		"goto":
			if pp.distance_to(_poi(str(step["poi"]))) < float(step.get("radius", 6.0)):
				_advance()
		"defeat":
			counter = 0
			for n in spawned:
				if not is_instance_valid(n) or (n as Actor).health.is_down or (n as Actor).dead:
					counter += 1
			if counter >= need:
				_advance()
		"survive":
			timer -= delta
			var alive := 0
			for n in spawned:
				if is_instance_valid(n) and n is Actor and not (n as Actor).health.is_down:
					alive += 1
			if alive == 0 and wave < int(step.get("waves", 3)):
				_spawn_wave()
			if timer <= 0.0 or (alive == 0 and wave >= int(step.get("waves", 3))):
				_advance()
		"escape_roof":
			var rp := _poi(str(step["poi"]))
			if pp.distance_to(rp) < 5.0 and absf(pp.y - rp.y) < 2.5:
				s.heat.clear()
				_advance()
		"sneak":
			if pp.distance_to(_poi(str(step["poi"]))) < 3.5:
				var undetected := true
				for n in spawned:
					if n is Actor and is_instance_valid(n) and (n as Actor).ai.aggro:
						undetected = false
				if undetected:
					s.save.add("money", 200)
					s.toast("নিঃশব্দে ঢুকেছেন! বোনাস ৳২০০", "good")
				_advance()
		"tail":
			if tail_actor and is_instance_valid(tail_actor):
				var d := pp.distance_to(tail_actor.global_position)
				if d > 35.0:
					_lost_t += delta
					if _lost_t > 6.0:
						_fail_step("কুরিয়ারকে হারিয়ে ফেলেছেন।")
				else:
					_lost_t = 0.0
		"debate":
			_debate_cool -= delta
			var leader := _char_if(str(s.story.debate(str(step["debate"])).get("leader", "")))
			if leader and _debate_cool <= 0.0 and pp.distance_to(leader.global_position) < 4.5:
				_debate_cool = 9999.0
				var crowd: Array = []
				for n in spawned:
					if n is Actor and is_instance_valid(n):
						crowd.append(n)
				s.ui.call("open_debate", str(step["debate"]), crowd, func(won: bool) -> void:
					if won:
						_advance()
					else:
						_debate_cool = 6.0)
		"survive_night":
			_check_night()
		"drive":
			if pp.distance_to(_poi(str(step["poi"]))) < 10.0 or (_vehicle and is_instance_valid(_vehicle) and _vehicle.global_position.distance_to(_poi(str(step["poi"]))) < 10.0):
				_advance()

func _check_night() -> void:
	if str(step.get("type", "")) != "survive_night" or not _step_live:
		return
	counter = int(s.save.g("ghosts_banished", 0)) - _ghosts_at_start
	if need > 0 and counter >= need:
		_advance()
		return
	if not s.clock.is_night() and _was_night:
		if need > 0 and counter < need:
			s.toast("ভোর হয়ে গেছে। বাকি প্রশ্নভূতেরা পরের রাতে ফিরবে।", "info")
		_advance()

# ---------------------------------------------------------------- hooks from UI
func talk_script(a: Actor) -> Array:
	if step.is_empty() or not _step_live:
		return []
	var ty := str(step.get("type", ""))
	if a.id != str(step.get("npc", "")):
		return []
	if ty == "talk":
		return step.get("lines", [])
	if ty == "deliver":
		var item := str(Pickup.NAMES.get(str(step.get("item", "")), "জিনিস"))
		return [["sakib", "এই নিন, %s। সব প্রমাণ এখানে।" % item], [a.id, "দারুণ! এগুলো দিয়েই সিন্ডিকেটের মুখোশ খুলবে।"]]
	return []

func on_talk_done(a: Actor) -> void:
	if not step.is_empty() and str(step.get("type", "")) in ["talk", "deliver"] and a.id == str(step.get("npc", "")):
		s.bus.talked.emit(a.id)
		_advance()

func exam_for(a: Actor) -> Dictionary:
	if step.is_empty() or not _step_live or str(step.get("type", "")) != "exam" or a.id != str(step.get("npc", "")):
		return {}
	var lvl := int(level.get("id", 1))
	var ec := int(step.get("count", 3))
	var ep := int(step.get("pass", 2))
	# Scale exam difficulty down for early levels
	ec = maxi(1, ec - lvl / 2)
	ep = maxi(1, ep - lvl / 3)
	return {"text": step.get("text", ""), "count": ec, "pass": ep, "cats": step.get("cats", ["bcs"]),
		"alerts": a.faction in ["syndicate", "pseudo"] or a.id in ["guard", "receptionist"]}

func on_exam_result(a: Actor, passed: bool, _c: int, _t: int) -> void:
	if passed and str(step.get("type", "")) == "exam" and a.id == str(step.get("npc", "")):
		_advance()

func advice_for(a: Actor) -> Dictionary:
	if str(step.get("type", "")) == "advise" and _step_live and (step.get("patients", []) as Array).has(a.id) and not _advised.has(a.id):
		return {"pid": a.id}
	return {}

func on_advice(a: Actor, _pid: String, _verdict: String) -> void:
	_advised[a.id] = true
	counter = _advised.size()
	if counter >= need:
		_advance()

func on_target_resolved(a: Actor, how: String) -> void:
	if (a == target or a == _boss) and _step_live:
		var msg := {"arrested": "গ্রেপ্তার হয়েছে। আদালতে সাক্ষী হবে।", "killed": "শেষ। তার প্রশ্নের দায় এখন আপনার।", "spared": "ছেড়ে দিলেন। দয়াও এক রকম রায়।"}.get(how, "") as String
		s.toast("%s: %s" % [a.display_name, msg], "info")
		_advance()

func _on_item(item: String, _total: int) -> void:
	if str(step.get("type", "")) == "buy" and item == str(step.get("item", "candle")):
		_advance()

func _on_poster(kind: String, correct: bool) -> void:
	if str(step.get("type", "")) == "posters" and _step_live:
		var want := str(step.get("kind", "bcs_quiz"))
		if kind == want and (correct or kind != "bcs_quiz"):
			counter += 1
			if counter >= need:
				_advance()

func _on_downed(a: Node) -> void:
	if a == target and target.faction == "syndicate":
		s.toast("%s পরাস্ত। তার কাছে গিয়ে E চাপুন: সিদ্ধান্ত আপনার।" % target.display_name, "intel")

func status_bbcode() -> String:
	# Clear, spoiler-light story journal: chapter, place, objective, rewards and progress.
	var t := "[b][color=#ffd27a]অধ্যায় %s — %s[/color][/b]\n" % [BnText.num(int(level.get("act", 1))), str(level.get("name", ""))]
	var sub := str(level.get("subtitle", ""))
	if sub != "":
		t += "[i][color=#b8ac96]%s[/color][/i]\n" % sub
	t += "\n[color=#9fe8ff][b]বর্তমান লক্ষ্য:[/b][/color] %s\n" % objective_text()
	if need > 1 or counter > 0:
		t += "[color=#a09a8a]অগ্রগতি: %s / %s\n[/color]" % [BnText.num(counter), BnText.num(need)]
	t += "\n[b]— মিশন তালিকা —[/b]\n"
	var ms: Array = level.get("missions", [])
	for k in ms.size():
		var m: Dictionary = ms[k]
		var mark := "✔" if k < mi else ("➤" if k == mi else "○")
		t += "\n%s [b]%s[/b]\n" % [mark, str(m["title"])]
		t += "   [color=#a09a8a]%s[/color]\n" % str(m.get("brief", ""))
		var rw: Dictionary = m.get("reward", {})
		if not rw.is_empty():
			var bits: Array[String] = []
			if rw.has("money"):
				bits.append("৳" + BnText.num(int(rw["money"])))
			if rw.has("intel"):
				bits.append("ইন্টেল " + BnText.num(int(rw["intel"])))
			t += "   [color=#7dff9a]পুরস্কার: %s[/color]\n" % ", ".join(bits)
	t += "\n[color=#a09a8a]পরের অধ্যায় খুলবে সব মিশন শেষ হলে। ফোনে মানচিত্র ও পরিসংখ্যান দেখুন।[/color]"
	return t

# ---------------------------------------------------------------- spawning
func _near_player(rmin: float, rmax: float) -> Vector3:
	var pp := (s.player as Node3D).global_position
	for k in 12:
		var ang := randf() * TAU
		var q := pp + Vector3(cos(ang), 0, sin(ang)) * randf_range(rmin, rmax)
		q = (s.world as ProceduralDhaka).random_sidewalk_point(q, 4.0)
		if q.distance_to(pp) > rmin * 0.7:
			return q
	return pp + Vector3(rmin, 0, 0)

func _char_if(id: String) -> Actor:
	if chars.has(id) and is_instance_valid(chars[id]):
		return chars[id]
	return null

func _ensure_char(id: String, at: Vector3) -> Actor:
	var a := _char_if(id)
	if a:
		if a.global_position.distance_to(at) > 25.0:
			a.global_position = at + Vector3(randf_range(-1.5, 1.5), 0.2, randf_range(-1.5, 1.5))
		return a
	return _spawn_char(id, at, "stand")

func _spawn_char(id: String, at: Vector3, state: String) -> Actor:
	var c := s.story.character(id)
	var d := {"id": id, "name": c.get("name", id), "role": c.get("role", ""), "faction": c.get("faction", "civilian"), "cats": c.get("cats", ["gk"]),
		"examiner": c.get("examiner", 0.7), "greet": c.get("greet", []), "look": (c.get("look", {}) as Dictionary).duplicate(), "state": state, "story": true}
	var a := _spawn_actor(d, at + Vector3(randf_range(-1.0, 1.0), 0.2, randf_range(-1.0, 1.0)))
	chars[id] = a
	return a

func _spawn_actor(d: Dictionary, at: Vector3) -> Actor:
	var a := Actor.new()
	s.world.add_child(a)
	a.global_position = at + Vector3(0, 0.2, 0)
	a.setup(s, d)
	return a

func _spawn_goon(at: Vector3, aggro: bool, kind: String) -> Actor:
	var names := ["স হারুন", "স পল্লবী", "বাবলু মাস্তান", "স শম্পা", "স র好吗", "স দীপা", "স সুচনா", "স মমতা"]
	var look: Dictionary = (GOON_LOOKS[randi() % GOON_LOOKS.size()] as Dictionary).duplicate()
	var role := "গার্হস্থ্য অর্থনীতি কলেজের সিন্ডিকেটএজেন্ট" if kind != "provocateur" else "গার্হস্থ্য অর্থনীতি কলেজের উসকানিদাতা"
	if kind == "guard":
		role = "গার্হস্থ্য অর্থনীতি কলেজের পাহারাদার"
	var a := _spawn_actor({"name": names[randi() % names.size()], "role": role, "faction": "syndicate", "cats": ["gk", "bd", "math", "bangla"],
		"look": look, "state": "fight" if aggro else "guard", "hp": 60.0, "hostile": true, "damage": 5.0 + float(level.get("id", 1)) * 0.2}, at)
	a.ai.aggro = aggro
	if randf() < 0.4:
		a.body.hold("stick")
	spawned.append(a)
	return a

func _spawn_wave() -> void:
	wave += 1
	var n := 2 + wave
	for k in n:
		_spawn_goon(_near_player(10.0, 18.0), true, "goon")
	s.toast("আক্রমণের ঢেউ %s!" % BnText.num(wave), "danger")

func _spawn_protest(at: Vector3, debate_id: String) -> void:
	var d := s.story.debate(debate_id)
	var leader_id := str(d.get("leader", "jasmine"))
	var leader := _ensure_char(leader_id, at)
	leader.ai.set_state(ActorAI.State.STAND)
	leader.body.hold("banner")
	var n := clampi(int(d.get("crowd", 40)) / 10, 6, 18)
	var outfits := ["salwar", "salwar", "saree", "tshirt_jeans", "salwar"]
	for k in n:
		var fem := randf() < 0.8
		var look := {"sex": "f" if fem else "m", "outfit": outfits[randi() % outfits.size()] if fem else "shirt_pants", "hair": ["long", "hijab", "bun"][randi() % 3] if fem else "short",
			"age": randf_range(0.12, 0.35), "colors": [Color.from_hsv(randf(), 0.5, 0.7).to_html(), Color.from_hsv(randf(), 0.3, 0.9).to_html()]}
		var a := _spawn_actor({"name": ["মিছিলকারী", "আন্দোলনকারী গ্র্যাজুয়েট", "ছাত্রী", "স্লোগানদাতা"][randi() % 4], "role": "গার্হস্থ্য অর্থনীতি গ্র্যাজুয়েট", "faction": "student",
			"cats": ["science", "bangla"], "look": look, "state": "protest"}, at + Vector3(randf_range(-5, 5), 0, randf_range(2, 9)))
		a.ai.protest_center = at + Vector3(0, 0, 5.0)
		if randf() < 0.35:
			a.body.hold("banner")
		spawned.append(a)
	_debate_cool = 0.0

func _spawn_poster_stands(kind: String, n: int) -> void:
	var w := s.world as ProceduralDhaka
	var pp := (s.player as Node3D).global_position
	var texts: Array = s.story.poster_texts(kind)
	for k in n:
		var at := w.random_sidewalk_point(pp, 45.0)
		var stand := Node3D.new()
		s.world.add_child(stand)
		stand.global_position = at
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.1, 1.5, 0.06)
		post.mesh = bm
		post.material_override = Humanoid.plain_material(Color(0.35, 0.26, 0.18), 0.8)
		post.position = Vector3(0, 1.55, 0)
		stand.add_child(post)
		var leg := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.08, 1.0, 0.08)
		leg.mesh = lm
		leg.material_override = post.material_override
		leg.position = Vector3(0, 0.5, 0)
		stand.add_child(leg)
		var p := Poster.new()
		stand.add_child(p)
		p.position = Vector3(0, 1.55, 0.04)
		var q: Dictionary = {}
		if kind == "bcs_quiz":
			q = s.qdb.draw(["bcs", "job", "bar"], 2)
		p.setup(s, kind, str(texts[k % maxi(1, texts.size())]) if not texts.is_empty() else "", q)
		stand.look_at(pp, Vector3.UP)
		stand.rotation.x = 0.0
		stand.rotation.z = 0.0
		stand.rotate_y(PI)
		spawned.append(stand)

func _nearest_poster() -> Variant:
	var best: Variant = null
	var bd := 1e9
	var pp := (s.player as Node3D).global_position
	var want := str(step.get("kind", "bcs_quiz"))
	for n in get_tree().get_nodes_in_group("posters"):
		var p := n as Poster
		if p and not p.done and p.kind == want:
			var d := p.global_position.distance_to(pp)
			if d < bd:
				bd = d
				best = p.global_position
	return best

func _nearest_group(list: Array, group: String) -> Variant:
	var best: Variant = null
	var bd := 1e9
	var pp := (s.player as Node3D).global_position
	counter = need
	for n in list:
		if is_instance_valid(n) and (n as Node).is_in_group(group):
			counter -= 1
			var d := (n as Node3D).global_position.distance_to(pp)
			if d < bd:
				bd = d
				best = (n as Node3D).global_position
	if best == null and _step_live and str(step.get("type", "")) == "collect":
		call_deferred("_advance")
	return best

func _cleanup() -> void:
	for n in spawned:
		if is_instance_valid(n) and not (n is Actor and (n as Actor).story_char and (n as Actor).faction != "patient"):
			if n is Actor and ((n as Actor).health.is_down or (n as Actor).arrested):
				continue
			(n as Node).queue_free()
	spawned.clear()
	target = null
	tail_actor = null
	_vehicle = null

# ---------------------------------------------------------------- finale
func _spawn_boss() -> void:
	var roof := _poi("tower_roof")
	(s.world as ProceduralDhaka).ensure_built(roof, 1)
	_boss = _spawn_char("examiner", roof + Vector3(0, 0, -3.0), "fight")
	_boss.faction = "syndicate"
	_boss.hostile = true
	_boss.health.setup(320.0, 0.92)
	_boss.health.can_recover = false
	_boss.ai.aggro = true
	_boss.ai.damage = 16.0
	_boss.mission_tag = "boss"
	_boss.body.set_sustain("float", true)
	target = _boss
	spawned.append(_boss)
	var brain := BossBrain.new()
	_boss.add_child(brain)
	brain.setup(s, _boss)
	_lecterns_done = 0
	for k in 3:
		var u := Usable.new()
		u.prompt = "লেকটার্নে পরীক্ষা দিন (মহাপরীক্ষকের বর্ম ভাঙুন)"
		u.once = true
		s.world.add_child(u)
		var ang := TAU * k / 3.0
		u.global_position = roof + Vector3(cos(ang) * 7.0, 0.0, sin(ang) * 5.5)
		var desk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.8, 1.15, 0.6)
		desk.mesh = bm
		desk.material_override = Humanoid.plain_material(Color(0.4, 0.25, 0.15), 0.6)
		desk.position = Vector3(0, 0.58, 0)
		u.add_child(desk)
		var cats: Array = [["law", "bangla"], ["math", "mental"], ["english", "gk", "bd"]][k]
		u.on_use = func(_p: Node) -> void:
			var done := func(passed: bool, _c: int, _t: int) -> void:
				if passed:
					_lecterns_done += 1
					desk.material_override = Humanoid.plain_material(Color(0.3, 0.8, 0.4), 0.5)
					brain.crack(_lecterns_done)
				else:
					u.enabled = true
					s.toast("লেকটার্নের পরীক্ষায় ফেল। আবার চেষ্টা করুন।", "danger")
			s.ui.call("open_exam", s.qdb.draw_many(cats, 3, 3), "মহাভাইভা: লেকটার্ন %s" % BnText.num(k + 1), "মহাপরীক্ষক", 2, done, "boss")
		spawned.append(u)
