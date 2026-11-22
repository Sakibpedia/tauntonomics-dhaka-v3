class_name TouchControls
extends Control
## On-screen controls for Android and mobile browsers: a floating joystick on the left half,
## drag-to-look on the right half, and Bengali action buttons that fire the same input actions as
## the keyboard.

var s: Services
var _move_id := -1
var _look_id := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO
var _last_look := Vector2.ZERO

const BUTTONS := [["interact", "কথা", Vector2(-170, -330)], ["attack", "ঘুষি", Vector2(-170, -200)], ["jump", "লাফ", Vector2(-300, -140)],
	["sprint", "দৌড়", Vector2(-300, -270)], ["block", "ব্লক", Vector2(-430, -150)], ["dodge", "ডজ", Vector2(-430, -280)],
	["pickup", "ইট", Vector2(-170, -460)], ["candle", "মোম", Vector2(-300, -400)], ["phone", "ফোন", Vector2(-140, 40)], ["taunt", "খোঁচা", Vector2(-430, -410)]]

func setup(services: Services) -> void:
	s = services
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	for bd in BUTTONS:
		var b := Button.new()
		b.text = str(bd[1])
		b.custom_minimum_size = Vector2(118, 104)
		b.add_theme_font_size_override("font_size", 26)
		var pos: Vector2 = bd[2]
		UiKit.place(b, Control.PRESET_TOP_RIGHT if pos.y > 0 else Control.PRESET_BOTTOM_RIGHT, pos, Vector2(118, 104))
		b.modulate.a = 0.75
		var action := str(bd[0])
		b.button_down.connect(func() -> void: _press(action, true))
		b.button_up.connect(func() -> void: _press(action, false))
		add_child(b)

func _press(action: String, down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = down
	Input.parse_input_event(ev)

func _gui_input(event: InputEvent) -> void:
	var half := get_viewport_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if t.position.x < half and _move_id == -1:
				_move_id = t.index
				_origin = t.position
				_knob = t.position
			elif t.position.x >= half and _look_id == -1:
				_look_id = t.index
				_last_look = t.position
		else:
			if t.index == _move_id:
				_move_id = -1
				_set_move(Vector2.ZERO)
			elif t.index == _look_id:
				_look_id = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _move_id:
			_knob = d.position
			var v := (_knob - _origin) / 110.0
			_set_move(v.limit_length(1.0))
			queue_redraw()
		elif d.index == _look_id:
			var delta := d.position - _last_look
			_last_look = d.position
			if s.camera:
				var cam := s.camera as PlayerCamera
				cam.yaw -= delta.x * 0.006
				cam.pitch = clampf(cam.pitch - delta.y * 0.004, -1.2, 0.75)

func _set_move(v: Vector2) -> void:
	if s.player and is_instance_valid(s.player):
		(s.player as Player).touch_move = v

func _draw() -> void:
	if _move_id != -1:
		draw_circle(_origin, 110.0, Color(1, 1, 1, 0.12))
		draw_circle(_origin + (_knob - _origin).limit_length(110.0), 46.0, Color(1, 0.85, 0.5, 0.45))
