class_name UIRoot
extends CanvasLayer
## All on-screen UI, in Bengali. The HUD (radar, health, sanity and stamina, money, candles,
## Syndicate heat stars, clock and day, objective panel, world markers, prompts, subtitles, toasts,
## the night warning, the sanity vignette) plus modal panels (exam, conversation, fate, debate,
## phone), cutscene letterbox, mission banners, the "অকৃতকার্য" screen and fades. Opening a modal
## pauses the game.

var s: Services
var hud: Control
var minimap: Minimap
var bar_hp: TextureProgressBar
var bar_san: TextureProgressBar
var bar_sta: TextureProgressBar
var lbl_money: Label
var lbl_clock: Label
var lbl_stars: Label
var lbl_title: Label
var lbl_obj: Label
var lbl_level: Label
var prompt_box: HBoxContainer
var prompt_lbl: Label
var sub_panel: PanelContainer
var sub_lbl: RichTextLabel
var toasts: VBoxContainer
var marker: TextureRect
var marker_dist: Label
var night_lbl: Label
var vignette: ColorRect
var flash: ColorRect
var fader: ColorRect
var banner: VBoxContainer
var banner_t: Label
var banner_s: Label
var letterbox: Control
var cut_lbl: RichTextLabel
var touch: Control
var exam: ExamPanel
var convo: ConversationPanel
var debate: DebatePanel
var phone: PhonePanel
var modal_depth := 0
var pause_depth := 0
var _sub_t := 0.0
var _banner_t := 0.0
var _cut_lines: Array = []
var _cut_cb: Callable
var _cut_i := 0
var _cut_wait := 0.0
var mobile := false
# Text shaping is expensive (especially Bengali); only touch Labels when their values change.
var _last_money := -1
var _last_candles := -1
var _last_intel := -1
var _last_clock_key := ""
var _last_night_txt := "__unset__"
var _last_prompt := ""
var _last_level := ""
var _last_title := ""
var _last_obj := ""
var _last_marker_m := -1
var btn_interact: Button
var btn_pause: Button
var pause_menu: PanelContainer
var btn_resume: Button
var btn_main: Button
var btn_quit: Button
var _hud_t := 0.0
var _marker_pos: Variant = null
var _marker_off := false
# Dev-only FPS overlay (DHAKA_SHOW_FPS=1).
var lbl_fps: Label
var _fps_t := 0.0
var _fps := 0

func setup(services: Services) -> void:
	s = services
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.is_touchscreen_available()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.build_theme()
	add_child(root)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	_build_hud()
	exam = ExamPanel.new()
	root.add_child(exam)
	exam.setup(s, self)
	convo = ConversationPanel.new()
	root.add_child(convo)
	convo.setup(s, self)
	debate = DebatePanel.new()
	root.add_child(debate)
	debate.setup(s, self)
	phone = PhonePanel.new()
	root.add_child(phone)
	phone.setup(s, self)
	_build_overlays(root)
	if mobile:
		touch = TouchControls.new()
		root.add_child(touch)
		touch.call("setup", s)
	s.bus.toast.connect(toast)
	s.bus.subtitle.connect(subtitle)
	s.bus.heat_changed.connect(func(_n: int) -> void: _refresh_stars())
	s.bus.player_damaged.connect(func(a: float, _k: String) -> void:
		flash.color.a = clampf(a / 40.0, 0.15, 0.55))
	s.bus.night_changed.connect(func(n: bool) -> void:
		if n:
			banner_show("রাত নেমেছে", s.taunts.pick("night_warning"), Color(0.55, 0.8, 1.0))
		else:
			banner_show("ভোর হয়েছে", "সূর্যের আলোয় প্রশ্নভূতেরা পুড়ে যায়।", UiKit.SAFFRON))

func _lbl(text: String, size: int, col: Color = UiKit.PAPER, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", BnText.font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_hud() -> void:
	minimap = Minimap.new()
	minimap.position = Vector2(24, 24)
	minimap.size = Vector2(250, 250)
	minimap.setup(s)
	hud.add_child(minimap)
	if OS.get_environment("DHAKA_SHOW_FPS") != "":
		lbl_fps = _lbl("FPS --  |  -- ms", 20, Color(0.0, 1.0, 0.4), true)
		lbl_fps.position = Vector2(24, 560)
		hud.add_child(lbl_fps)
	lbl_clock = _lbl("", 22, Color(1, 0.92, 0.75), true)
	lbl_clock.position = Vector2(30, 280)
	hud.add_child(lbl_clock)
	lbl_stars = _lbl("", 34, UiKit.SIGNAL_RED, true)
	lbl_stars.position = Vector2(30, 310)
	hud.add_child(lbl_stars)
	var bars := VBoxContainer.new()
	UiKit.place(bars, Control.PRESET_BOTTOM_LEFT, Vector2(24, -210), Vector2(380, 190))
	bars.add_theme_constant_override("separation", 4)
	hud.add_child(bars)
	for kind in ["health", "sanity", "stamina"]:
		var row := HBoxContainer.new()
		var name_l := _lbl({"health": "স্বাস্থ্য", "sanity": "স্যানিটি", "stamina": "দম"}[kind], 18, UiKit.PAPER, true)
		name_l.custom_minimum_size = Vector2(70, 0)
		row.add_child(name_l)
		var b := UiKit.make_bar(kind)
		b.custom_minimum_size = Vector2(260, 26)
		b.nine_patch_stretch = true
		b.stretch_margin_left = 12
		b.stretch_margin_right = 12
		row.add_child(b)
		bars.add_child(row)
		match kind:
			"health": bar_hp = b
			"sanity": bar_san = b
			"stamina": bar_sta = b
	lbl_money = _lbl("", 26, Color(0.6, 1.0, 0.6), true)
	bars.add_child(lbl_money)
	# objective panel (top right)
	var obj := PanelContainer.new()
	UiKit.place(obj, Control.PRESET_TOP_RIGHT, Vector2(-560, 24), Vector2(530, 120))
	obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(obj)
	var ov := VBoxContainer.new()
	obj.add_child(ov)
	lbl_level = _lbl("", 18, Color(0.85, 0.8, 0.7))
	ov.add_child(lbl_level)
	lbl_title = _lbl("", 26, Color("ffd27a"), true)
	lbl_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ov.add_child(lbl_title)
	lbl_obj = _lbl("", 21, UiKit.PAPER)
	lbl_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_obj.custom_minimum_size = Vector2(490, 0)
	ov.add_child(lbl_obj)
	# interaction prompt (clickable so tapping/clicking [E] works without a physical keyboard)
	prompt_box = HBoxContainer.new()
	UiKit.place(prompt_box, Control.PRESET_CENTER_BOTTOM, Vector2(-260, -250), Vector2(620, 50))
	prompt_box.mouse_filter = Control.MOUSE_FILTER_PASS
	hud.add_child(prompt_box)
	var key_btn := Button.new()
	key_btn.custom_minimum_size = Vector2(48, 48)
	key_btn.flat = true
	key_btn.focus_mode = Control.FOCUS_NONE
	key_btn.button_down.connect(func() -> void: _fire_action("interact", true))
	key_btn.button_up.connect(func() -> void: _fire_action("interact", false))
	prompt_box.add_child(key_btn)
	var key := TextureRect.new()
	key.texture = UiKit.tex("keycap")
	key.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	key.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	key.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_btn.add_child(key)
	var kl := _lbl("E", 24, UiKit.INK, true)
	kl.position = Vector2(15, 7)
	key.add_child(kl)
	prompt_lbl = _lbl("", 24, UiKit.PAPER, true)
	prompt_box.add_child(prompt_lbl)
	# subtitles
	sub_panel = PanelContainer.new()
	UiKit.place(sub_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-560, -180), Vector2(1120, 60))
	sub_panel.add_theme_stylebox_override("panel", UiKit.slice("subtitle_backdrop", Vector4(30, 20, 30, 20), Vector4(30, 14, 30, 14)))
	sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.visible = false
	hud.add_child(sub_panel)
	sub_lbl = RichTextLabel.new()
	sub_lbl.bbcode_enabled = true
	sub_lbl.fit_content = true
	sub_lbl.scroll_active = false
	sub_lbl.add_theme_font_override("normal_font", BnText.font(false))
	sub_lbl.add_theme_font_override("bold_font", BnText.font(true))
	sub_lbl.add_theme_font_size_override("normal_font_size", 26)
	sub_lbl.add_theme_font_size_override("bold_font_size", 26)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.add_child(sub_lbl)
	toasts = VBoxContainer.new()
	UiKit.place(toasts, Control.PRESET_CENTER_RIGHT, Vector2(-520, -60), Vector2(490, 300))
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(toasts)
	marker = TextureRect.new()
	marker.texture = UiKit.tex("marker_objective")
	marker.custom_minimum_size = Vector2(44, 44)
	marker.size = Vector2(44, 44)
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(marker)
	marker_dist = _lbl("", 18, UiKit.SAFFRON, true)
	marker.add_child(marker_dist)
	marker_dist.position = Vector2(-10, 44)
	night_lbl = _lbl("", 20, Color(0.6, 0.85, 1.0), true)
	night_lbl.position = Vector2(30, 352)
	hud.add_child(night_lbl)

func _build_overlays(root: Control) -> void:
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform float amount = 0.0;\nuniform vec3 tint = vec3(0.1, 0.25, 0.4);\nvoid fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.25, 0.75, length(d) * 1.4); COLOR = vec4(tint, v * amount); }"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	vignette.material = sm
	root.add_child(vignette)
	root.move_child(vignette, 0)
	flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.8, 0.05, 0.05, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	letterbox = Control.new()
	letterbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	letterbox.mouse_filter = Control.MOUSE_FILTER_STOP
	letterbox.visible = false
	root.add_child(letterbox)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.92)
		if top:
			UiKit.place(bar, Control.PRESET_TOP_WIDE, Vector2(0, 0), Vector2(0, 150))
		else:
			UiKit.place(bar, Control.PRESET_BOTTOM_WIDE, Vector2(0, -150), Vector2(0, 150))
		letterbox.add_child(bar)
	cut_lbl = RichTextLabel.new()
	cut_lbl.bbcode_enabled = true
	UiKit.place(cut_lbl, Control.PRESET_CENTER_BOTTOM, Vector2(-760, -140), Vector2(1520, 130))
	cut_lbl.add_theme_font_override("normal_font", BnText.font(false))
	cut_lbl.add_theme_font_override("bold_font", BnText.font(true))
	cut_lbl.add_theme_font_size_override("normal_font_size", 28)
	cut_lbl.add_theme_font_size_override("bold_font_size", 28)
	letterbox.add_child(cut_lbl)
	banner = VBoxContainer.new()
	UiKit.place(banner, Control.PRESET_CENTER, Vector2(-600, -300), Vector2(1200, 220))
	banner.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	root.add_child(banner)
	banner_t = _lbl("", 64, UiKit.SAFFRON, true)
	banner_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_t)
	banner_s = _lbl("", 28, UiKit.PAPER)
	banner_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_s.custom_minimum_size = Vector2(1200, 0)
	banner.add_child(banner_s)
	fader = ColorRect.new()
	fader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fader.color = Color(0, 0, 0, 0)
	fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fader)
	# On-screen "কথা" (Talk/Interact) button — visible on every platform so mouse/touch
	# users can trigger "E" without a keyboard. Exams and typing still use the on-screen keyboard.
	btn_interact = Button.new()
	btn_interact.text = "কথা"
	btn_interact.custom_minimum_size = Vector2(120, 70)
	btn_interact.add_theme_font_size_override("font_size", 28)
	btn_interact.modulate.a = 0.85
	UiKit.place(btn_interact, Control.PRESET_BOTTOM_RIGHT, Vector2(-220, -200), Vector2(120, 70))
	btn_interact.pressed.connect(func() -> void:
		var p := s.player as Player
		if p and is_instance_valid(p):
			p._interact())
	root.add_child(btn_interact)

	# Pause button — pause the game and open the pause menu (resume / main menu / quit).
	btn_pause = Button.new()
	btn_pause.text = "স্থগিত"
	btn_pause.custom_minimum_size = Vector2(120, 70)
	btn_pause.add_theme_font_size_override("font_size", 28)
	btn_pause.modulate.a = 0.85
	UiKit.place(btn_pause, Control.PRESET_BOTTOM_RIGHT, Vector2(-220, -290), Vector2(120, 70))
	btn_pause.pressed.connect(_open_pause_menu)
	root.add_child(btn_pause)

	# Pause menu panel (hidden until opened).
	pause_menu = PanelContainer.new()
	UiKit.place(pause_menu, Control.PRESET_CENTER, Vector2(-320, -200), Vector2(640, 400))
	pause_menu.visible = false
	pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 16)
	pv.add_theme_constant_override("alignment", 1)  # center
	pause_menu.add_child(pv)
	var pt := Label.new()
	pt.text = "খেলা স্থগিত"
	pt.add_theme_font_override("font", BnText.font(true))
	pt.add_theme_font_size_override("font_size", 40)
	pt.add_theme_color_override("font_color", UiKit.SAFFRON)
	pt.add_theme_constant_override("alignment", 1)
	pv.add_child(pt)
	btn_resume = Button.new()
	btn_resume.text = "চালিয়ে যান (রেজুমে)"
	btn_resume.custom_minimum_size = Vector2(420, 66)
	btn_resume.add_theme_font_size_override("font_size", 26)
	btn_resume.pressed.connect(_close_pause_menu)
	pv.add_child(btn_resume)
	btn_main = Button.new()
	btn_main.text = "প্রচ্ছদে যান (মেইন মেনু)"
	btn_main.custom_minimum_size = Vector2(420, 66)
	btn_main.add_theme_font_size_override("font_size", 26)
	btn_main.pressed.connect(func() -> void: s.main.to_menu())
	pv.add_child(btn_main)
	btn_quit = Button.new()
	btn_quit.text = "প্রস্থান (ক्वিট)"
	btn_quit.custom_minimum_size = Vector2(420, 66)
	btn_quit.add_theme_font_size_override("font_size", 26)
	btn_quit.pressed.connect(func() -> void: get_tree().quit())
	pv.add_child(btn_quit)
	root.add_child(pause_menu)

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	flash.color.a = maxf(0.0, flash.color.a - delta * 1.5)
	if _sub_t > 0.0:
		_sub_t -= delta
		if _sub_t <= 0.0:
			sub_panel.visible = false
	if _banner_t > 0.0:
		_banner_t -= delta
		banner.modulate.a = clampf(_banner_t, 0.0, 1.0)
	_cutscene_tick(delta)
	var p := s.player as Player
	if p == null or not is_instance_valid(p):
		hud.visible = false
		return
	hud.visible = letterbox.visible == false and modal_depth == 0
	bar_hp.value = p.hp
	bar_san.value = p.sanity
	bar_sta.value = p.stamina
	var money := s.save.money()
	var candles := int(s.save.g("candles", 0))
	var intel := int(s.save.g("intel", 0))
	if money != _last_money or candles != _last_candles or intel != _last_intel:
		_last_money = money
		_last_candles = candles
		_last_intel = intel
		lbl_money.text = "%s   মোমবাতি: %s   ইন্টেল: %s" % [BnText.money(money), BnText.num(candles), BnText.num(intel)]
	var clock_key := "%d|%d" % [int(s.clock.hour * 60.0), s.clock.day]
	if clock_key != _last_clock_key:
		_last_clock_key = clock_key
		lbl_clock.text = "%s • দিন %s" % [BnText.clock(s.clock.hour), BnText.num(s.clock.day)]
	var night := s.clock.is_night()
	var night_txt := ""
	if night:
		night_txt = "আশ্রয়ে আছেন" if p.protected_from_ghosts() else "অন্ধকারে আছেন: স্যানিটি কমছে"
	if night_txt != _last_night_txt:
		_last_night_txt = night_txt
		night_lbl.text = night_txt
	(vignette.material as ShaderMaterial).set_shader_parameter("amount", clampf((60.0 - p.sanity) / 60.0, 0.0, 0.85) + (0.15 if night and not p.protected_from_ghosts() else 0.0))
	# prompt
	var has_prompt := p.interact_target != null and is_instance_valid(p.interact_target) and modal_depth == 0
	prompt_box.visible = has_prompt
	if has_prompt:
		var ptxt := str(p.interact_target.call("interact_prompt"))
		if ptxt != _last_prompt:
			_last_prompt = ptxt
			prompt_lbl.text = ptxt
	# objective (string shaping is costly, so refresh at 4 Hz and only assign on change)
	if s.missions:
		_hud_t -= delta
		if _hud_t <= 0.0:
			_hud_t = 0.25
			_marker_pos = s.missions.call("marker_pos")
			var lv := str(s.missions.call("level_label"))
			if lv != _last_level:
				_last_level = lv
				lbl_level.text = lv
			var ti := str(s.missions.call("current_title"))
			if ti != _last_title:
				_last_title = ti
				lbl_title.text = ti
			var ob := str(s.missions.call("objective_text"))
			if ob != _last_obj:
				_last_obj = ob
				lbl_obj.text = ob
		_place_marker(_marker_pos)
	# Dev-only FPS overlay: update once per second so the text shaping cost stays negligible.
	if lbl_fps:
		_fps_t += delta
		if _fps_t >= 1.0:
			_fps_t = 0.0
			_fps = Engine.get_frames_per_second()
			var ms := 1000.0 / maxf(float(_fps), 1.0)
			lbl_fps.text = "FPS %d  |  %.0f ms  |  %s" % [_fps, ms, RenderingServer.get_current_rendering_method()]

## Fire a gameplay action from an on-screen button (mouse/touch without a keyboard).
func _fire_action(action: String, pressed: bool) -> void:
	var p := s.player as Player
	if p == null or not is_instance_valid(p):
		return
	if not pressed:
		return
	match action:
		"interact":
			p._interact()
		"pause":
			_open_pause_menu()

## Open the pause menu: pause the game, show resume / main menu / quit.
func _open_pause_menu() -> void:
	push_modal()
	pause_menu.visible = true
	btn_resume.grab_focus()

## Close the pause menu and resume gameplay.
func _close_pause_menu() -> void:
	pause_menu.visible = false
	pop_modal()

func _place_marker(mp: Variant) -> void:
	var cam := get_viewport().get_camera_3d()
	if mp == null or cam == null:
		marker.visible = false
		return
	var wp: Vector3 = mp
	wp.y += 2.2
	var vs := get_viewport().get_visible_rect().size
	var behind := cam.is_position_behind(wp)
	var sp := cam.unproject_position(wp)
	if behind:
		sp = vs - sp
	var margin := 40.0
	var inside := not behind and sp.x > margin and sp.y > margin and sp.x < vs.x - margin and sp.y < vs.y - margin
	if not inside:
		var c := vs * 0.5
		var d := (sp - c)
		if d.length() < 1.0:
			d = Vector2(0, -1)
		var k := minf((vs.x * 0.5 - margin) / maxf(absf(d.x), 0.001), (vs.y * 0.5 - margin) / maxf(absf(d.y), 0.001))
		sp = c + d * minf(k, 1.0) if not behind else c + d.normalized() * minf(vs.x, vs.y) * 0.45
		marker.texture = UiKit.tex("marker_offscreen_arrow")
		marker.pivot_offset = Vector2(22, 22)
		marker.rotation = d.angle() + PI * 0.5
	else:
		marker.texture = UiKit.tex("marker_objective")
		marker.rotation = 0.0
	marker.visible = true
	marker.position = sp - Vector2(22, 22)
	var p := s.player as Node3D
	var dist := p.global_position.distance_to(mp as Vector3)
	var metres := int(dist)
	if metres != _last_marker_m:
		_last_marker_m = metres
		marker_dist.text = BnText.num(metres) + " মি."
	marker_dist.rotation = -marker.rotation

func _refresh_stars() -> void:
	var n := s.heat.stars if s.heat else 0
	lbl_stars.text = "★".repeat(n) + "☆".repeat(5 - n) if n > 0 else ""

# ---------------------------------------------------------------- messages
func toast(text: String, kind: String = "info") -> void:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := {"info": UiKit.PAPER, "good": Color(0.6, 1.0, 0.6), "danger": Color(1.0, 0.55, 0.5), "intel": Color(0.6, 0.85, 1.0)}.get(kind, UiKit.PAPER) as Color
	var l := _lbl(text, 21, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(450, 0)
	pc.add_child(l)
	toasts.add_child(pc)
	if toasts.get_child_count() > 4:
		toasts.get_child(0).queue_free()
	var tw := pc.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(pc, "modulate:a", 0.0, 0.6)
	tw.tween_callback(pc.queue_free)
	if kind == "danger":
		s.sfx.play("buzz", -10.0)
	else:
		s.sfx.play("notify", -14.0)

func subtitle(speaker: String, text: String, seconds: float) -> void:
	sub_lbl.text = "[b][color=#ffd27a]%s:[/color][/b] %s" % [speaker, text]
	sub_panel.visible = true
	_sub_t = seconds

func banner_show(title: String, sub: String, col: Color = UiKit.SAFFRON, seconds: float = 4.0) -> void:
	banner_t.text = title
	banner_t.add_theme_color_override("font_color", col)
	banner_s.text = sub
	banner.modulate.a = 1.0
	_banner_t = seconds

# ---------------------------------------------------------------- modals
func push_modal(pause: bool = true) -> void:
	modal_depth += 1
	_banner_t = 0.0
	banner.modulate.a = 0.0
	if pause:
		pause_depth += 1
	get_tree().paused = pause_depth > 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if s.player and is_instance_valid(s.player):
		(s.player as Player).controls_enabled = false

func pop_modal(pause: bool = true) -> void:
	modal_depth = maxi(0, modal_depth - 1)
	if pause:
		pause_depth = maxi(0, pause_depth - 1)
	get_tree().paused = pause_depth > 0 or letterbox.visible
	if modal_depth == 0:
		if s.player and is_instance_valid(s.player):
			(s.player as Player).controls_enabled = true
		if not mobile:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func open_conversation(actor: Actor, p: Node) -> void:
	convo.open(actor, p)

func open_fate(actor: Actor) -> void:
	convo.open_fate(actor)

func open_exam(questions: Array, title: String, examiner: String, need: int, cb: Callable, context: String = "") -> void:
	exam.open(questions, title, examiner, need, cb, context)

func open_ghost_exam(g: Ghost) -> void:
	var cb := func(passed: bool, _c: int, _t: int) -> void:
		if is_instance_valid(g):
			g.answered(passed)
	open_exam([g.question], "প্রশ্নভূতের প্রশ্ন", str(g.record.get("name", "প্রশ্নভূত")), 1, cb, "ghost")

func open_poster_exam(p: Poster) -> void:
	var q := p.question
	if q.is_empty():
		q = s.qdb.draw(["bcs"], 2)
	var cb := func(passed: bool, _c: int, _t: int) -> void:
		if is_instance_valid(p):
			p.answered(passed)
	open_exam([q], "দেয়ালের প্রশ্ন", "পোস্টার", 1, cb, "poster")

func open_debate(id: String, crowd: Array, cb: Callable) -> void:
	debate.open(id, crowd, cb)

func open_phone() -> void:
	if modal_depth == 0 and not letterbox.visible:
		phone.open()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("phone"):
		if phone.visible:
			phone.close()
		else:
			open_phone()
		get_viewport().set_input_as_handled()
	elif letterbox.visible and (event.is_action_pressed("interact") or event.is_action_pressed("jump") or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)):
		_cut_next()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- cutscenes
func cutscene(lines: Array, cb: Callable = Callable()) -> void:
	_cut_lines = lines
	_cut_cb = cb
	_cut_i = -1
	letterbox.visible = true
	get_tree().paused = true
	_cut_next()

func _cut_next() -> void:
	_cut_i += 1
	if _cut_i >= _cut_lines.size():
		letterbox.visible = false
		Speech.stop()
		get_tree().paused = pause_depth > 0
		var cb := _cut_cb
		_cut_cb = Callable()
		if cb.is_valid():
			cb.call()
		return
	var line: Variant = _cut_lines[_cut_i]
	var spk := ""
	var txt := ""
	if line is Array:
		spk = s.story.char_name(str((line as Array)[0]))
		txt = str((line as Array)[1])
	else:
		txt = str(line)
	if spk != "":
		cut_lbl.text = "[b][color=#ffd27a]%s[/color][/b]\n%s\n[color=#a09a8a][font_size=18](চালিয়ে যেতে E / Space / ক্লিক)[/font_size][/color]" % [spk, txt]
	else:
		cut_lbl.text = "%s\n[color=#a09a8a][font_size=18](চালিয়ে যেতে E / Space / ক্লিক)[/font_size][/color]" % txt
	if bool(s.save.setting("tts", true)):
		Speech.speak(txt)
	_cut_wait = 0.25
	s.sfx.play("page", -16.0)

func _cutscene_tick(delta: float) -> void:
	if letterbox.visible and _cut_wait > 0.0:
		_cut_wait -= delta

# ---------------------------------------------------------------- transitions
func fade_teleport(node: Node, to: Vector3) -> void:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(fader, "color:a", 1.0, 0.35)
	tw.tween_callback(func() -> void:
		if s.world:
			(s.world as ProceduralDhaka).ensure_built(to, 1)
		if node is Node3D:
			(node as Node3D).global_position = to
			if node is CharacterBody3D:
				(node as CharacterBody3D).velocity = Vector3.ZERO
		s.sfx.play("door", -6.0))
	tw.tween_interval(0.25)
	tw.tween_property(fader, "color:a", 0.0, 0.4)

func fade(to_black: bool, seconds: float = 0.6) -> Tween:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(fader, "color:a", 1.0 if to_black else 0.0, seconds)
	return tw

func wasted(reason: String, cb: Callable) -> void:
	banner_show("অকৃতকার্য", reason + "\nনেগেটিভ মার্কিং: চিকিৎসা ও ঘুষ বাবদ কিছু টাকা কাটা গেছে।", UiKit.SIGNAL_RED, 4.5)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	Engine.time_scale = 0.35
	tw.tween_interval(1.4)
	tw.tween_property(fader, "color:a", 1.0, 0.8)
	tw.tween_callback(func() -> void:
		Engine.time_scale = 1.0
		cb.call())
	tw.tween_interval(0.6)
	tw.tween_property(fader, "color:a", 0.0, 0.8)
