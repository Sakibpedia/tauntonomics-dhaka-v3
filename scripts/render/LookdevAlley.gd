extends Node3D
## Look-development scene for Phase 1: a short Old-Dhaka style alley built only from the
## generated PBR materials, lit by DhakaAtmosphere. Use it to judge textures, fog and grading
## before the procedural city (Phase 2) exists.
##
## Controls: right mouse = look, WASD = fly, Q/E = down/up, Shift = fast,
##           1–4 = preset (noon haze, golden smog, monsoon, night sodium), Q-tier: F1–F4.

const TEX := "res://assets/textures/"

var atmo: DhakaAtmosphere
var cam: Camera3D
var _yaw := 0.0
var _pitch := -0.08
var _mats: Dictionary = {}
var _hud: Label

func _ready() -> void:
	atmo = DhakaAtmosphere.new()
	add_child(atmo)
	_build_alley()
	cam = Camera3D.new()
	cam.position = Vector3(0.4, 1.65, 13.0)
	cam.fov = 60.0
	add_child(cam)
	cam.current = true
	var cl := CanvasLayer.new()
	add_child(cl)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 6)
	cl.add_child(_hud)
	_update_hud()

func _m(name: String, uv_scale: float = 0.5) -> Material:
	var key := name + str(uv_scale)
	if _mats.has(key):
		return _mats[key]
	var path := TEX + name + "/" + name + ".tres"
	var m: StandardMaterial3D
	if ResourceLoader.exists(path):
		m = (load(path) as StandardMaterial3D).duplicate()
	else:
		m = StandardMaterial3D.new()
		m.albedo_color = Color(1, 0, 1)      # magenta = run tools/generate_textures.py first
	m.uv1_scale = Vector3.ONE * uv_scale
	_mats[key] = m
	return m

func _box(size: Vector3, pos: Vector3, mat: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	return mi

func _build_alley() -> void:
	# street and gutters
	_box(Vector3(9.0, 0.2, 60.0), Vector3(0, -0.1, -10.0), _m("asphalt_cracked", 0.35))
	_box(Vector3(0.5, 0.25, 60.0), Vector3(-3.6, 0.0, -10.0), _m("concrete_mossy", 0.6))
	_box(Vector3(0.5, 0.25, 60.0), Vector3(3.6, 0.0, -10.0), _m("concrete_mossy", 0.6))
	# building rows on both sides: brick walls, concrete frames, tin canopies
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for side: float in [-1.0, 1.0]:
		var z := 18.0
		while z > -38.0:
			var w := rng.randf_range(5.0, 8.5)
			var h := rng.randf_range(10.0, 24.0)
			var x := side * (4.0 + 3.0)
			var wall_mat := _m("brick_weathered", 0.45) if rng.randf() < 0.55 else _m("concrete_mossy", 0.35)
			_box(Vector3(6.0, h, w), Vector3(x, h * 0.5, z - w * 0.5), wall_mat)
			# concrete floor slabs / balconies every 3 m
			var fl := 3.0
			while fl < h - 1.0:
				_box(Vector3(0.9, 0.18, w - 0.4), Vector3(side * 3.55, fl, z - w * 0.5), _m("concrete_mossy", 0.8))
				# grilled window recess
				var win := _box(Vector3(0.12, 1.3, 1.5), Vector3(side * 3.95, fl + 1.3, z - w * 0.5 + rng.randf_range(-1.0, 1.0)), _glass())
				win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				fl += 3.0
			# shop shutter + awning at street level
			_box(Vector3(0.1, 2.6, w - 1.0), Vector3(side * 3.96, 1.3, z - w * 0.5), _m("tin_galvanized", 0.6))
			var aw: String = ["awning_stripes_red", "awning_stripes_blue", "awning_blockprint", "awning_tarp_blue"][rng.randi() % 4]
			var awning := _box(Vector3(1.8, 0.04, w - 0.6), Vector3(side * 3.0, 2.9, z - w * 0.5), _m(aw, 0.5))
			awning.rotation.z = side * 0.32
			if rng.randf() < 0.5:
				var tin := _box(Vector3(2.2, 0.05, w), Vector3(side * 3.5, h + 0.6, z - w * 0.5), _m("tin_painted_green", 0.5))
				tin.rotation.z = side * -0.18
			z -= w + 0.05
	# tangled overhead wires
	for i in 18:
		var y := 6.0 + (i % 6) * 0.35
		var zz := 12.0 - i * 2.6
		var wire := _box(Vector3(7.4, 0.025, 0.025), Vector3(0, y, zz), _wire_mat())
		wire.rotation = Vector3(0, (i % 3 - 1) * 0.25, ((i % 2) * 2 - 1) * 0.05)
	# warm shop lights spilling onto the street
	for k in 6:
		var l := OmniLight3D.new()
		l.position = Vector3((k % 2 * 2 - 1) * 2.8, 2.5, 10.0 - k * 8.0)
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 2.2
		l.omni_range = 7.0
		l.light_volumetric_fog_energy = 2.0
		l.shadow_enabled = k < 2
		add_child(l)
	atmo.call_deferred("add_smoke", Vector3(2.4, 0.2, 4.0), 1.0, 6.0)

func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.14, 0.15)
	m.metallic = 0.4
	m.roughness = 0.08
	return m

func _wire_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.03, 0.03)
	m.roughness = 0.6
	return m

func _update_hud() -> void:
	var names := ["দুপুরের ধোঁয়াশা (HAZE_NOON)", "সোনালি ধোঁয়া (GOLDEN_SMOG)", "বর্ষার মেঘলা (MONSOON_OVERCAST)", "সোডিয়াম রাত (NIGHT_SODIUM)"]
	var q := ["LOW", "MEDIUM", "HIGH", "ULTRA"]
	_hud.text = "Preset: %s   Quality: %s   FPS: %d\n1–4 preset • F1–F4 quality • RMB look • WASD/QE fly • Shift fast" % [names[atmo.preset], q[atmo.quality], Engine.get_frames_per_second()]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= event.relative.x * 0.004
		_pitch = clampf(_pitch - event.relative.y * 0.004, -1.4, 1.4)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: atmo.blend_to(DhakaAtmosphere.Preset.HAZE_NOON, 3.0)
			KEY_2: atmo.blend_to(DhakaAtmosphere.Preset.GOLDEN_SMOG, 3.0)
			KEY_3: atmo.blend_to(DhakaAtmosphere.Preset.MONSOON_OVERCAST, 3.0)
			KEY_4: atmo.blend_to(DhakaAtmosphere.Preset.NIGHT_SODIUM, 3.0)
			KEY_F1: atmo.quality = DhakaAtmosphere.Quality.LOW
			KEY_F2: atmo.quality = DhakaAtmosphere.Quality.MEDIUM
			KEY_F3: atmo.quality = DhakaAtmosphere.Quality.HIGH
			KEY_F4: atmo.quality = DhakaAtmosphere.Quality.ULTRA

func _process(delta: float) -> void:
	cam.rotation = Vector3(_pitch, _yaw, 0)
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): v.z -= 1
	if Input.is_key_pressed(KEY_S): v.z += 1
	if Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_D): v.x += 1
	if Input.is_key_pressed(KEY_E): v.y += 1
	if Input.is_key_pressed(KEY_Q): v.y -= 1
	var spd := 14.0 if Input.is_key_pressed(KEY_SHIFT) else 4.0
	cam.position += cam.global_basis * v.normalized() * spd * delta if v.length() > 0 else Vector3.ZERO
	if Engine.get_process_frames() % 30 == 0:
		_update_hud()
