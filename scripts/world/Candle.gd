class_name Candle
extends Node3D
## A lit candle: a warm circle of light that question-ghosts cannot enter, for 120 seconds.

const RADIUS := 6.0
var s: Services
var life := 120.0
var _light: OmniLight3D
var _flame: MeshInstance3D

func setup(services: Services) -> void:
	s = services
	add_to_group("candles")
	var wax := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.025
	cm.bottom_radius = 0.03
	cm.height = 0.14
	wax.mesh = cm
	wax.material_override = Humanoid.plain_material(Color(0.95, 0.92, 0.82), 0.5)
	wax.position.y = 0.07
	add_child(wax)
	_flame = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.06
	_flame.mesh = sm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.75, 0.3)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.6, 0.2)
	fm.emission_energy_multiplier = 6.0
	_flame.material_override = fm
	_flame.position.y = 0.17
	add_child(_flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.68, 0.35)
	_light.light_energy = 2.2
	_light.omni_range = RADIUS
	_light.shadow_enabled = false
	_light.position.y = 0.3
	add_child(_light)

func _process(delta: float) -> void:
	life -= delta
	var fl := 1.0 + sin(Time.get_ticks_msec() * 0.023) * 0.08 + sin(Time.get_ticks_msec() * 0.051) * 0.06
	_light.light_energy = 2.2 * fl * clampf(life / 10.0, 0.0, 1.0)
	_flame.scale = Vector3(1, fl, 1)
	if life <= 0.0:
		queue_free()
