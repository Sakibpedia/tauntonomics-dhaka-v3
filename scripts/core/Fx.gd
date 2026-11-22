class_name Fx
extends Node
## One-shot visual effects: hit sparks, dust, paper bursts, ghost embers, floating text, screen shake.

var world: Node3D
var camera_shake: Callable      # set by PlayerCamera: func(strength: float)
var _mats: Dictionary = {}

func _mat(c: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%.2f" % [c.to_html(), emissive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emissive > 0.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	_mats[key] = m
	return m

func _burst(pos: Vector3, amount: int, color: Color, size: float, speed: float, life: float, gravity: float, emissive: float = 0.0, spread: float = 180.0, dir: Vector3 = Vector3.UP) -> void:
	if world == null or not is_instance_valid(world):
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -gravity, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _mat(color, emissive)
	p.mesh = q
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad
	world.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)

func hit(pos: Vector3, strong: bool = false) -> void:
	_burst(pos, 10 if strong else 6, Color(1.0, 0.85, 0.5), 0.06, 4.0 if strong else 2.5, 0.25, 6.0, 4.0)
	_burst(pos, 6, Color(0.6, 0.55, 0.5, 0.6), 0.18, 1.0, 0.6, -0.3)
	shake(0.35 if strong else 0.18)

func dust(pos: Vector3, amount: int = 10) -> void:
	_burst(pos, amount, Color(0.62, 0.56, 0.48, 0.55), 0.35, 1.4, 1.0, -0.2, 0.0, 70.0)

func paper(pos: Vector3, amount: int = 14) -> void:
	_burst(pos, amount, Color(0.95, 0.93, 0.85), 0.12, 3.0, 1.6, 2.5, 0.0, 120.0)

func ghost_embers(pos: Vector3, burn: bool = false) -> void:
	var c := Color(1.0, 0.55, 0.2) if burn else Color(0.55, 0.85, 1.0)
	_burst(pos, 26, c, 0.08, 2.5, 1.4, -1.2, 5.0, 180.0)

func sparkle(pos: Vector3, c: Color = Color(1.0, 0.9, 0.4)) -> void:
	_burst(pos, 16, c, 0.07, 2.0, 0.8, -0.5, 4.0)

func float_text(pos: Vector3, text: String, c: Color = Color(1, 0.9, 0.4), size: int = 64) -> void:
	if world == null or not is_instance_valid(world):
		return
	var l := Label3D.new()
	l.text = text
	l.font = BnText.font(true)
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = c
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	world.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "global_position", pos + Vector3(0, 1.2, 0), 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.tween_callback(l.queue_free)

func shake(strength: float) -> void:
	if camera_shake.is_valid():
		camera_shake.call(strength)
