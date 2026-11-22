class_name Traffic
extends Node
const VModels = preload("res://scripts/systems/VehicleModels.gd")
## Ambient traffic on the main roads: green CNGs, colourful dented buses, white cars and pedal
## rickshaws. They drive in their lanes, brake and honk at anything in front of them (you included)
## and recycle around the player.

var s: Services
var cars: Array = []
var _t := 0.0
const MAX := 12

func setup(services: Services) -> void:
	s = services

func _max_cars() -> int:
	return 8 if (s != null and s.quality <= 0) else MAX

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_impl(delta)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if ms > 6.0 and OS.get_environment("DHAKA_LOG_SLOW") != "":
		print("SLOW traffic %.1f ms" % ms)

func _process_impl(delta: float) -> void:
	_t -= delta
	if s.player == null or not is_instance_valid(s.player):
		return
	var pp := (s.player as Node3D).global_position
	var w := s.world as ProceduralDhaka
	for i in range(cars.size() - 1, -1, -1):
		var car := cars[i] as AnimatableBody3D
		if not is_instance_valid(car):
			cars.remove_at(i)
			continue
		var dir: Vector3 = car.get_meta("dir")
		var spd: float = car.get_meta("speed")
		var cur: float = car.get_meta("cur")
		var target: float = car.get_meta("target", spd)
		# Raycasts are the expensive part: think at ~6 Hz instead of every frame.
		var think: float = float(car.get_meta("think", 0.0)) - delta
		if think <= 0.0:
			think = 0.15 + randf() * 0.1
			var ahead := car.global_position + dir * 2.0 + Vector3(0, 0.8, 0)
			var q := PhysicsRayQueryParameters3D.create(ahead, ahead + dir * 7.0, 2 | 4 | 32)
			q.exclude = [car.get_rid()]
			var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
			target = spd if hit.is_empty() else 0.0
			car.set_meta("target", target)
			# Honking removed by request — traffic is silent.
		car.set_meta("think", think)
		cur = move_toward(cur, target, (6.0 if target < cur else 2.5) * delta)
		car.set_meta("cur", cur)
		car.global_position += dir * cur * delta
		if car.global_position.distance_to(pp) > 140.0:
			car.queue_free()
			cars.remove_at(i)
	if _t <= 0.0 and cars.size() < _max_cars() and pp.y < 8.0:
		_t = 0.8
		_spawn(w, pp)

func _spawn(w: ProceduralDhaka, pp: Vector3) -> void:
	# pick a main-road line near the player
	var along_x := randf() < 0.5
	var b := w.block_of(pp)
	var line := (b.y if along_x else b.x) + randi_range(-2, 3)
	line = int(round(line / 3.0)) * 3
	var coord := line * ProceduralDhaka.P
	var sgn := 1.0 if randf() < 0.5 else -1.0
	var lane := coord + (2.4 if sgn > 0 else -2.4) * (1.0 if along_x else -1.0)
	var along := (pp.x if along_x else pp.z) - sgn * randf_range(70.0, 110.0)
	var pos := Vector3(along, 0.0, lane) if along_x else Vector3(lane, 0.0, along)
	var dir := Vector3(sgn, 0, 0) if along_x else Vector3(0, 0, sgn)
	var kind: String = ["cng", "cng", "bus", "car", "rickshaw", "cng"][randi() % 6]
	var car := AnimatableBody3D.new()
	car.sync_to_physics = false
	car.collision_layer = 32
	car.collision_mask = 0
	s.world.add_child(car)
	car.global_position = pos
	car.look_at(pos + dir, Vector3.UP)
	var size := {"cng": Vector3(1.4, 1.9, 2.6), "bus": Vector3(2.5, 3.0, 10.0), "car": Vector3(1.8, 1.45, 4.3), "rickshaw": Vector3(1.1, 1.8, 2.4)}[kind] as Vector3
	var col := {"cng": Color(0.12, 0.45, 0.22), "bus": Color.from_hsv(randf(), 0.7, 0.75), "car": [Color(0.92, 0.92, 0.9), Color(0.6, 0.6, 0.62), Color(0.1, 0.1, 0.12)][randi() % 3], "rickshaw": Color(0.85, 0.15, 0.2)}[kind] as Color
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	car.add_child(cs)
	# Authentic single-mesh 3D model (one draw call), with a coloured box fallback.
	var model: Node3D = VModels.make(kind)
	if model:
		VModels.no_shadows(model)
		car.add_child(model)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size * Vector3(1, 0.62, 1)
		mi.mesh = bm
		mi.material_override = Humanoid.plain_material(col, 0.35, 0.3)
		mi.position = Vector3(0, size.y * 0.38, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(mi)
	if kind == "bus":
		var lab := Label3D.new()
		lab.text = ["গুলিস্তান–যাত্রাবাড়ী–কাজলা", "সায়েদাবাদ–মতিঝিল", "সিটিং সার্ভিস (দাঁড়ানো যাবে)", "বিসিএস স্পেশাল: শাহবাগ"][randi() % 4]
		lab.font = BnText.font(true)
		lab.font_size = 96
		lab.pixel_size = 0.004
		lab.visibility_range_end = 80.0
		lab.position = Vector3(size.x * 0.5 + 0.02, size.y * 0.55, 0)
		lab.rotation.y = PI * 0.5
		car.add_child(lab)
	car.set_meta("dir", dir)
	car.set_meta("speed", {"cng": 8.0, "bus": 7.0, "car": 9.5, "rickshaw": 3.2}[kind])
	car.set_meta("cur", 0.0)
	car.set_meta("target", 0.0)
	car.set_meta("think", randf_range(0.0, 0.2))
	car.set_meta("honk", 1.0)
	cars.append(car)
