extends Control
## Phase 1 UI showcase: HUD cluster, markers, title card and the exam window, all built from
## UiKit and the SVG set. Press Space to cycle answer states, 1–4 to animate the bars.

var _bars: Array = []
var _ring: TextureProgressBar
var _opts: Array = []
var _state := 0
var _t := 0.0

func _ready() -> void:
	theme = UiKit.build_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.33, 0.29)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_hud()
	_build_exam()

func _build_hud() -> void:
	var p := PanelContainer.new()
	p.position = Vector2(28, 24)
	add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	var name_l := Label.new()
	name_l.text = "এস এম নাজমুয সাকিব"
	name_l.theme_type_variation = &"HeaderLabel"
	name_l.add_theme_font_size_override("font_size", 22)
	v.add_child(name_l)
	for row in [["স্বাস্থ্য", "health", 70.0], ["মানসিক", "sanity", 48.0], ["নীরবতা", "stealth", 88.0]]:
		var h := HBoxContainer.new()
		v.add_child(h)
		var l := Label.new()
		l.text = row[0]
		l.custom_minimum_size = Vector2(96, 0)
		h.add_child(l)
		var b := UiKit.make_bar(row[1])
		b.value = row[2]
		h.add_child(b)
		_bars.append(b)
	for i in 4:
		var m := UiKit.make_marker(["objective", "exam", "intel", "danger"][i])
		m.position = Vector2(700 + i * 130, 40)
		add_child(m)
	var title := UiKit.make_title("অধ্যায় ১ — পুরান ঢাকা")
	title.position = Vector2(860, 860)
	add_child(title)
	var kp := UiKit.make_key_prompt("E", "কথা বলুন")
	kp.position = Vector2(60, 980)
	add_child(kp)

func _build_exam() -> void:
	var win := Control.new()
	win.position = Vector2(560, 180)
	win.scale = Vector2(0.62, 0.62)
	add_child(win)
	var bg := TextureRect.new()
	bg.texture = UiKit.tex("exam_panel_bg")
	win.add_child(bg)
	var h := Label.new()
	h.text = "চা-দোকানির প্রশ্ন • ৩৫তম বিসিএস"
	h.theme_type_variation = &"HeaderLabel"
	h.position = Vector2(128, 36)
	win.add_child(h)
	_ring = UiKit.make_ring(80)
	_ring.position = Vector2(1148, 28)
	win.add_child(_ring)
	var q := Label.new()
	q.text = "নিচের কোন বানানটি শুদ্ধ?"
	q.add_theme_font_size_override("font_size", 38)
	q.position = Vector2(96, 196)
	win.add_child(q)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(56, 380)
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 24)
	win.add_child(grid)
	var letters := ["ক", "খ", "গ", "ঘ"]
	var words := ["মনীষী", "মনিষি", "মনীষি", "মনিষী"]
	for i in 4:
		var b := Button.new()
		b.text = letters[i] + "     " + words[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(560, 76)
		b.focus_mode = Control.FOCUS_NONE
		grid.add_child(b)
		_opts.append(b)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_state = (_state + 1) % 3
			for i in 4:
				var st := "normal"
				if _state == 1:
					st = "correct" if i == 0 else "disabled"
				elif _state == 2:
					st = "correct" if i == 0 else ("wrong" if i == 1 else "disabled")
				UiKit.set_option_state(_opts[i], st)
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			for b in _bars:
				create_tween().tween_property(b, "value", randf_range(10, 100), 0.6).set_trans(Tween.TRANS_QUART)

func _process(delta: float) -> void:
	_t += delta
	_ring.value = 1.0 - fmod(_t / 20.0, 1.0)
