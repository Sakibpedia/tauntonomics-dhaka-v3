class_name Main
extends Node3D
## Root of the game. Builds the Services container once (dependency injection: every system gets
## `s` passed in), the UI, the input map, and swaps levels in and out. Handles the title screen,
## new game / continue / level select, death and respawn ("অকৃতকার্য"), sleeping until dawn,
## level completion, the three endings and saving.

var s: Services
var ui: UIRoot
var menu: MainMenu
var level_root: Node3D
var level_n := 1
var _menu_cam: Camera3D
var _menu_t := 0.0
var _orbit := false
var _bench_left := 0.0
var _bench_acc := 0.0
var _bench_frames := 0

func _ready() -> void:
	_setup_input()
	s = Services.new()
	s.name = "Services"
	add_child(s)
	s.build()
	s.main = self
	if OS.get_environment("DHAKA_VOICE_TEST") != "":
		var t := "কেমন আছেন? শহরের খবর কী?"
		var h := t.md5_text().substr(0, 16)
		print("VOICETEST key=", h, " file=", FileAccess.file_exists("res://assets/voice/" + h + ".mp3"),
			" bound=", Speech._player != null, " tts_setting=", s.save.setting("tts", true))
		Speech.speak(t)
		print("VOICETEST playing=", Speech._player != null and Speech._player.playing,
			" stream_len=", (Speech._player.stream.get_length() if Speech._player.stream else -1.0),
			" master_db=", AudioServer.get_bus_volume_db(0))
	s.save.load_game()
	s.quality = _resolve_quality()
	Humanoid.low_quality = s.quality <= 0
	s.qdb.sync_from_save()
	s.sfx.set_master(float(s.save.setting("volume", 0.8)))
	if OS.get_environment("DHAKA_WARM_AUDIO") != "":
		s.sfx.warm_all()
	s.sfx.world_root = self
	s.fx.world = self
	ThemeDB.fallback_font = BnText.font(false)
	ui = UIRoot.new()
	add_child(ui)
	ui.setup(s)
	s.ui = ui
	s.bus.player_died.connect(_on_player_died)
	# Dev-only benchmark: DHAKA_BENCH=<seconds> prints FPS once per second, then quits.
	var bench := OS.get_environment("DHAKA_BENCH")
	if bench != "":
		_bench_left = maxf(1.0, float(bench))
		print("BENCH adapter=\"%s\" renderer=%s quality=%d viewport=%s" % [
			RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(),
			s.quality, str(get_viewport().get_visible_rect().size)])
	if OS.get_environment("DHAKA_BOT") != "":
		var parts := OS.get_environment("DHAKA_BOT").split(",")
		var bot := TestBot.new()
		add_child(bot)
		bot.setup(s, self, int(parts[1]) if parts.size() > 1 else 20)
		s.save.new_game()
		start_level(int(parts[0]))
	elif OS.get_environment("DHAKA_AUTOSTART") != "":
		start_level(int(OS.get_environment("DHAKA_AUTOSTART")))
		if OS.get_environment("DHAKA_VIEW") != "":
			get_tree().create_timer(0.3, true).timeout.connect(_shot.bind(OS.get_environment("DHAKA_VIEW")))
	else:
		to_menu()

# ---------------------------------------------------------------- input map (code-driven so every export has it)
func _key(action: String, keys: Array, mouse: Array = [], pad: Array = [], axis: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for m in mouse:
		var mb := InputEventMouseButton.new()
		mb.button_index = m
		InputMap.action_add_event(action, mb)
	for p in pad:
		var jb := InputEventJoypadButton.new()
		jb.button_index = p
		InputMap.action_add_event(action, jb)
	for a in axis:
		var ja := InputEventJoypadMotion.new()
		ja.axis = (a as Array)[0]
		ja.axis_value = (a as Array)[1]
		InputMap.action_add_event(action, ja)

func _setup_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP], [], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_key("move_back", [KEY_S, KEY_DOWN], [], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_key("move_left", [KEY_A, KEY_LEFT], [], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_key("move_right", [KEY_D, KEY_RIGHT], [], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_key("look_left", [], [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_key("look_right", [], [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_key("look_up", [], [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_key("look_down", [], [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_key("sprint", [KEY_SHIFT], [], [JOY_BUTTON_LEFT_STICK])
	_key("jump", [KEY_SPACE], [], [JOY_BUTTON_A])
	_key("crouch", [KEY_C, KEY_CTRL], [], [JOY_BUTTON_RIGHT_STICK])
	_key("interact", [KEY_E], [], [JOY_BUTTON_Y])
	_key("attack", [], [MOUSE_BUTTON_LEFT], [JOY_BUTTON_X])
	_key("kick", [KEY_X], [MOUSE_BUTTON_MIDDLE], [JOY_BUTTON_B])
	_key("aim", [], [MOUSE_BUTTON_RIGHT], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_key("block", [KEY_F], [], [JOY_BUTTON_LEFT_SHOULDER])
	_key("shield", [KEY_Q], [], [JOY_BUTTON_RIGHT_SHOULDER])
	_key("dodge", [KEY_V, KEY_ALT], [], [JOY_BUTTON_DPAD_DOWN])
	_key("pickup", [KEY_G], [], [JOY_BUTTON_DPAD_UP])
	_key("taunt", [KEY_T], [], [JOY_BUTTON_DPAD_LEFT])
	_key("candle", [KEY_B], [], [JOY_BUTTON_DPAD_RIGHT])
	_key("lock_on", [KEY_R], [], [])
	_key("phone", [KEY_TAB, KEY_M], [], [JOY_BUTTON_START])
	_key("pause", [KEY_P, KEY_ESCAPE], [], [JOY_BUTTON_BACK])

# ---------------------------------------------------------------- menu
func to_menu() -> void:
	get_tree().paused = false
	_unload()
	if menu == null:
		menu = MainMenu.new()
		ui.get_child(0).add_child(menu)
		menu.setup(s, self)
	menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# a live city at dusk behind the menu
	var lvl: Dictionary = s.story.level(1).duplicate(true)
	lvl["size"] = 6
	lvl["missions"] = []
	_build_world(lvl, 18.4)
	_menu_cam = Camera3D.new()
	level_root.add_child(_menu_cam)
	_menu_cam.current = true
	_menu_cam.fov = 60
	_orbit = true
	s.clock.frozen = true
	# Ambient street/vehicle noise removed by request — the city stays quiet.

func _process(delta: float) -> void:
	if _orbit and _menu_cam and is_instance_valid(_menu_cam):
		_menu_t += delta * 0.04
		var c := Vector3(0, 0, 0)
		_menu_cam.global_position = c + Vector3(cos(_menu_t) * 70.0, 34.0, sin(_menu_t) * 70.0)
		_menu_cam.look_at(c + Vector3(0, 6, 0), Vector3.UP)
	if OS.get_environment("DHAKA_LOG_HITCH") != "" and delta > 0.1:
		print("HITCH dt=%.0fms process=%.0fms phys=%.0fms" % [
			delta * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	if _bench_left > 0.0:
		_bench_acc += delta
		_bench_frames += 1
		if _bench_acc >= 1.0:
			var fps := Engine.get_frames_per_second()
			print("BENCH fps=%d frame_ms=%.1f cpu_ms=%.1f phys_ms=%.1f draws=%d objs=%d prims=%dk" % [
				fps, 1000.0 / maxf(float(fps), 1.0),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])
			_bench_acc = 0.0
			_bench_frames = 0
			_bench_left -= 1.0
			if _bench_left <= 0.0:
				get_tree().quit()

func new_game() -> void:
	s.save.new_game()
	s.qdb.sync_from_save()
	start_level(1)

func continue_game() -> void:
	s.save.load_game()
	s.qdb.sync_from_save()
	_load_level(int(s.save.g("level", 1)), int(s.save.g("mission", 0)), true)

func start_level(n: int) -> void:
	_load_level(n, 0, false)

# ---------------------------------------------------------------- levels
func _unload() -> void:
	_orbit = false
	s.sfx.stop_all_loops()
	s.heat.clear()
	for g in ["actors", "ghosts", "candles", "posters", "interactable", "pickups", "throwable", "vehicles"]:
		pass
	if level_root and is_instance_valid(level_root):
		level_root.queue_free()
	level_root = null
	s.world = null
	s.player = null
	s.camera = null
	s.missions = null
	s.ghosts = null
	s.crowd = null
	s.traffic = null
	s.ride = null
	s.atmo = null
	s.clock.atmo = null

# ---------------------------------------------------------------- graphics quality
## Pick a sensible default from the GPU name. Integrated / mobile GPUs get LOW.
func _auto_quality() -> int:
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	if gpu.contains("hd graphics") or gpu.contains("uhd graphics") or gpu.contains("gma") \
			or gpu.contains("mali") or gpu.contains("adreno") or gpu.contains("powervr") \
			or gpu.contains("vivante") or gpu.contains("swiftshader"):
		return 0
	if gpu.contains("rtx") or gpu.contains("gtx") or gpu.contains("radeon rx") \
			or gpu.contains("arc a") or gpu.contains("quadro"):
		return 2
	return 1

func _resolve_quality() -> int:
	if bool(s.save.setting("quality_auto", true)):
		return _auto_quality()
	return clampi(int(s.save.setting("quality", 1)), 0, 3)

## 3D render resolution per quality tier (UI stays at the full viewport resolution).
func _quality_scale(q: int) -> float:
	return [0.5, 0.67, 0.85, 1.0][clampi(q, 0, 3)]

func _apply_viewport_quality(q: int) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var scale := _quality_scale(q)
	# Dev override for profiling: DHAKA_SCALE=0.4
	var env_scale := OS.get_environment("DHAKA_SCALE")
	if env_scale != "":
		scale = clampf(float(env_scale), 0.2, 1.0)
	vp.scaling_3d_scale = scale

## Re-apply quality after the player changes it in the phone settings.
func apply_quality() -> void:
	var q := _resolve_quality()
	if OS.has_feature("web") or OS.has_feature("mobile"):
		q = 0
	s.quality = q
	Humanoid.low_quality = q <= 0
	_apply_viewport_quality(q)
	if s.atmo and is_instance_valid(s.atmo):
		s.atmo.quality = q as DhakaAtmosphere.Quality
	if s.world and is_instance_valid(s.world) and s.world.has_method("refresh_quality"):
		s.world.call("refresh_quality")

func _build_world(lvl: Dictionary, hour: float) -> void:
	level_root = Node3D.new()
	level_root.name = "Level"
	add_child(level_root)
	s.fx.world = level_root
	s.sfx.world_root = level_root
	var q := _resolve_quality()
	if OS.has_feature("web") or OS.has_feature("mobile"):
		q = 0
	s.quality = q
	Humanoid.low_quality = q <= 0
	_apply_viewport_quality(q)
	var atmo := DhakaAtmosphere.new()
	atmo.name = "Atmosphere"
	atmo.quality = q as DhakaAtmosphere.Quality
	atmo.street_smog_size = Vector3(500, 14, 500)
	level_root.add_child(atmo)
	s.atmo = atmo
	s.clock.atmo = atmo
	var world := ProceduralDhaka.new()
	world.name = "Dhaka"
	level_root.add_child(world)
	s.world = world
	world.setup(s, lvl)
	s.clock.set_hour(hour)
	world.ensure_built(Vector3.ZERO, 1)

func _load_level(n: int, mission: int, resume: bool) -> void:
	_unload()
	if menu:
		menu.visible = false
	level_n = n
	var lvl: Dictionary = s.story.level(n)
	if lvl.is_empty():
		_ending()
		return
	s.save.s("level", n)
	s.save.s("unlocked", maxi(int(s.save.g("unlocked", 1)), n))
	var hour := float(lvl.get("time", 9.0))
	if resume:
		hour = float(s.save.g("hour", hour))
		s.clock.day = int(s.save.g("day", 1))
	_build_world(lvl, hour)
	s.clock.frozen = false
	var world := s.world as ProceduralDhaka
	var spawn := world.poi("safehouse") + Vector3(0, 0.3, 1.5)
	if str(lvl.get("style", "")) in ["tower", "tower_roof"]:
		spawn = world.poi("tower_gate") + Vector3(0, 0.3, 4.0)
		if str(lvl.get("style", "")) == "tower_roof":
			spawn = world.poi("tower_roof") + Vector3(0, 0.3, 4.0)
	world.ensure_built(spawn, 1)
	# A fully walkable 4-storey Dhaka walk-up beside the safehouse: real stair physics,
	# two flats per floor, hinged doors/windows and a reachable roof.
	var walkup: Node = (preload("res://scripts/world/WalkableBuilding.gd") as GDScript).new()
	walkup.name = "WalkableBuilding"
	level_root.add_child(walkup)
	walkup.call("setup", s)
	var shp: Vector3 = (world.poi("safehouse") as Vector3)
	# Clear the procedural lot so the walkable building stands on its own plot.
	var wpos := shp + Vector3(112.0, 0.0, 112.0)
	var wb := world.block_of(wpos)
	world.layouts[wb] = []
	if world._sky_index.has(wb):
		world._sky_index[wb] = []
	if world.blocks.has(wb):
		var old: Node3D = world.blocks[wb]
		old.queue_free()
		world.blocks.erase(wb)
	walkup.global_position = wpos
	var p := Player.new()
	p.name = "Sakib"
	level_root.add_child(p)
	p.setup(s)
	p.global_position = spawn
	s.player = p
	var cam := PlayerCamera.new()
	level_root.add_child(cam)
	cam.setup(s, p)
	cam.global_position = spawn + Vector3(0, 1.6, 0)
	p.cam = cam
	s.camera = cam
	var crowd := PedestrianSpawner.new()
	level_root.add_child(crowd)
	crowd.setup(s)
	s.crowd = crowd
	var traffic := Traffic.new()
	level_root.add_child(traffic)
	traffic.setup(s)
	s.traffic = traffic
	var ride: Node = (preload("res://scripts/systems/RideService.gd") as GDScript).new()
	level_root.add_child(ride)
	ride.setup(s)
	s.ride = ride
	var ghosts := GhostDirector.new()
	level_root.add_child(ghosts)
	ghosts.setup(s)
	s.ghosts = ghosts
	var md := MissionDirector.new()
	level_root.add_child(md)
	md.setup(s, lvl)
	s.missions = md
	s.bus.level_started.emit(n)
	if not ui.mobile:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	md.start(mission if resume else 0)

func save_now() -> void:
	if s.player and is_instance_valid(s.player):
		var p := s.player as Player
		s.save.s("hp", p.hp)
		s.save.s("sanity", p.sanity)
	s.save.s("hour", s.clock.hour)
	s.save.s("day", s.clock.day)
	s.save.s("level", level_n)
	s.save.save_game()

func _on_player_died(reason: String) -> void:
	ui.wasted(reason, func() -> void:
		var lost := int(s.save.money() * 0.1)
		s.save.add("money", -lost)
		s.heat.clear()
		var p := s.player as Player
		if p and is_instance_valid(p):
			var at := (s.world as ProceduralDhaka).poi("safehouse") + Vector3(0, 0.3, 1.5)
			(s.world as ProceduralDhaka).ensure_built(at, 1)
			p.respawn(at)
			if s.clock.is_night():
				s.clock.skip_to(6.5)
		if s.missions:
			s.missions.call("on_player_respawn"))

func sleep_until_morning() -> void:
	if not s.clock.is_night() and s.clock.hour < 15.0:
		s.toast("এখন ঘুমানোর সময় না। রাতে বা বিকেলের পরে ঘুমাতে পারবেন।", "info")
		return
	var tw := ui.fade(true, 0.8)
	tw.tween_callback(func() -> void:
		s.clock.skip_to(6.5)
		for g in get_tree().get_nodes_in_group("ghosts"):
			g.call("burn")
		var p := s.player as Player
		if p:
			p.heal(100.0, 100.0)
		save_now()
		s.toast("ঘুম ভাঙল ভোরে। খেলা সংরক্ষিত।", "good")
		if s.missions:
			s.missions.call("on_slept"))
	tw.tween_interval(0.6)
	tw.tween_property(ui.fader, "color:a", 0.0, 0.8)

func level_complete() -> void:
	var next := level_n + 1
	s.save.s("unlocked", maxi(int(s.save.g("unlocked", 1)), next))
	s.save.s("mission", 0)
	ui.banner_show("লেভেল সম্পন্ন!", "%s শেষ। পরের অধ্যায় শুরু হচ্ছে..." % str(s.story.level(level_n).get("name", "")), Color(0.5, 1.0, 0.6), 5.0)
	s.save.s("level", next)
	save_now()
	s.save.s("level", next)
	s.save.save_game()
	get_tree().create_timer(5.5).timeout.connect(func() -> void:
		if next > s.story.level_count():
			_ending()
		else:
			_load_level(next, 0, false))

func _ending() -> void:
	var key := s.save.ending()
	var e: Dictionary = (s.story.story.get("endings", {}) as Dictionary).get(key, {})
	var lines: Array = ["[b][color=#ffd27a]সমাপ্তি: %s[/color][/b]" % str(e.get("title", "")), str(e.get("text", ""))]
	lines.append("গ্রেপ্তার: %s • শেষ করা: %s • মুক্ত প্রশ্নভূত: %s • উত্তর দেওয়া প্রশ্ন: %s" % [BnText.num(int(s.save.g("arrests", 0))), BnText.num(int(s.save.g("kills", 0))), BnText.num(int(s.save.g("ghosts_banished", 0))), BnText.num(int(s.save.g("answered", 0)))])
	for c in (s.story.story.get("credits", []) as Array):
		lines.append(str(c))
	ui.cutscene(lines, func() -> void: to_menu())

## QA screenshots (DHAKA_AUTOSTART=<level> DHAKA_VIEW=street|roof|night|exam|face|convo|tower).
func _shot(view: String) -> void:
	while ui.letterbox.visible:
		ui._cut_next()
	var w := s.world as ProceduralDhaka
	var p := s.player as Player
	var cam := s.camera as PlayerCamera
	s.clock.frozen = true
	match view:
		"street":
			s.clock.set_hour(9.5)
			var at := w.poi("tea_stall") + Vector3(-14.0, 0.3, 0.0)
			p.global_position = at
			cam.yaw = -PI * 0.5
			cam.pitch = -0.08
		"roof":
			s.clock.set_hour(16.8)
			var r := w.poi("roof_extract")
			w.ensure_built(r, 2)
			p.global_position = r + Vector3(0, 0.4, 0)
			cam.yaw = 0.6
			cam.pitch = -0.25
		"night":
			s.clock.set_hour(21.0)
			var at2 := w.poi("tea_stall") + Vector3(-10.0, 0.3, 0.0)
			p.global_position = at2
			cam.yaw = -PI * 0.5
			cam.pitch = -0.1
			s.ghosts.call("spawn_random_near", at2 + Vector3(5, 0, 0), true)
			s.ghosts.call("spawn_random_near", at2 + Vector3(7, 0, 2), true)
		"exam":
			s.clock.set_hour(11.0)
			ui.open_exam(s.qdb.draw_many(["law"], 1, 3), "পরীক্ষা: বার কাউন্সিল ধাঁচ", "হাকিম স্যার", 1, Callable(), "qa")
		"face", "convo":
			s.clock.set_hour(10.5)
			var at3 := w.poi("tea_stall") + Vector3(-6.0, 0.3, 1.5)
			p.global_position = at3
			var mdd := s.missions as MissionDirector
			var a := mdd._ensure_char("nasima", at3 + Vector3(-1.4, 0, 0))
			a.global_position = at3 + Vector3(-1.4, 0, 0)
			a.ai.set_state(ActorAI.State.STAND)
			var b := mdd._ensure_char("hakim", at3 + Vector3(-1.4, 0, 1.1))
			b.global_position = at3 + Vector3(-1.4, 0, 1.1)
			b.ai.set_state(ActorAI.State.STAND)
			cam.yaw = PI * 0.5
			cam.pitch = -0.05
			if view == "convo":
				ui.open_conversation(a, p)
			else:
				p.visible = false
				var fc := Camera3D.new()
				level_root.add_child(fc)
				fc.fov = 30.0
				fc.global_position = at3 + Vector3(1.4, 1.62, 0.9)
				fc.look_at(at3 + Vector3(-1.4, 1.48, 0.4), Vector3.UP)
				fc.current = true
				a.body.look_target = fc.global_position
				b.body.look_target = fc.global_position
				a.rotation.y = -PI * 0.5
				b.rotation.y = -PI * 0.5
		"walkup":
			# QA: stand in front of the fully walkable 4-storey Dhaka walk-up.
			s.clock.set_hour(10.0)
			var sh := (w.poi("safehouse") as Vector3)
			p.global_position = sh + Vector3(112.0, 0.3, 104.0)
			cam.yaw = PI
			cam.pitch = 0.12
		"tower":
			s.clock.set_hour(15.5)
			p.global_position = w.poi("tower_gate") + Vector3(0, 0.3, 18.0)
			cam.yaw = 0.0
			cam.pitch = 0.12
	# Save a real PNG after the view settles (DHAKA_SHOT=street|face|night|...).
	var shot := OS.get_environment("DHAKA_SHOT")
	if shot != "":
		get_tree().create_timer(1.2, true).timeout.connect(_save_shot.bind(shot))

func _save_shot(view: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_environment("DHAKA_SHOT_PATH")
	if path == "":
		path = "user://shot_%s.png" % view
	img.save_png(path)
	print("SHOT saved: ", path)
