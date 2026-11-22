class_name Vehicle
extends CharacterBody3D
const VModels = preload("res://scripts/systems/VehicleModels.gd")
## The green CNG auto-rickshaw, drivable GTA-style: E to get in or out, W/S throttle and brake,
## A/D steer, Shift for the "full CNG" boost, horn on Space. Arcade handling with weight transfer
## lean, an engine sound that follows the revs, and pedestrians diving out of the way.

var s: Services
var driven := false
var driver: Player
var speed := 0.0
var steer := 0.0
var interact_radius := 2.8
var _body: Node3D
var _engine: AudioStreamPlayer3D
var _horn_t := 0.0

func setup(services: Services) -> void:
	s = services
	add_to_group("interactable")
	add_to_group("vehicles")
	collision_layer = 32
	collision_mask = 1 | 4 | 32
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.45, 1.6, 2.7)
	cs.shape = bs
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)
	_body = Node3D.new()
	add_child(_body)
	# Authentic green CNG GLB model (single draw call) with a box fallback.
	var model: Node3D = VModels.make("cng")
	if model:
		VModels.no_shadows(model)
		_body.add_child(model)
	else:
		var green := Humanoid.plain_material(Color(0.12, 0.45, 0.22), 0.45, 0.2)
		var black := Humanoid.plain_material(Color(0.05, 0.05, 0.05), 0.7)
		_box(Vector3(0, 0.62, 0.05), Vector3(1.45, 0.55, 2.65), green)
		_box(Vector3(0, 1.92, 0.4), Vector3(1.5, 0.1, 1.95), black)
	var lab := Label3D.new()
	lab.text = "ঢাকা মেট্রো-থ ১১-২৩৪৫"
	lab.font = BnText.font(true)
	lab.font_size = 48
	lab.pixel_size = 0.003
	lab.position = Vector3(0, 0.55, 1.36)
	lab.modulate = Color(0.05, 0.05, 0.05)
	_body.add_child(lab)
	_engine = AudioStreamPlayer3D.new()
	add_child(_engine)

func _box(pos: Vector3, size: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	_body.add_child(mi)

func can_interact(_p: Node) -> bool:
	return not driven

func interact_prompt() -> String:
	return "সিএনজিতে উঠুন"

func interact(p: Node) -> void:
	var pl := p as Player
	if pl == null:
		return
	driven = true
	driver = pl
	pl.vehicle = self
	pl.visible = false
	pl.collision_layer = 0
	pl.collision_mask = 0
	var cam := s.camera as PlayerCamera
	cam.target = self
	cam.in_vehicle = true
	s.sfx.play("door", -4.0)
	s.bus.vehicle_entered.emit(self)

func _exit() -> void:
	if driver == null:
		return
	driver.vehicle = null
	driver.visible = true
	driver.collision_layer = Actor.LAYER_PLAYER
	driver.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ACTOR | Actor.LAYER_VEHICLE
	driver.global_position = global_position + global_transform.basis.x * -1.6 + Vector3(0, 0.3, 0)
	var cam := s.camera as PlayerCamera
	cam.target = driver
	cam.in_vehicle = false
	s.bus.vehicle_exited.emit(self)
	driven = false
	driver = null
	speed = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if driven and event.is_action_pressed("interact") and absf(speed) < 3.0:
		_exit()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var turn := 0.0
	if driven:
		throttle = Input.get_axis("move_back", "move_forward")
		turn = Input.get_axis("move_right", "move_left")
		if driver:
			throttle -= driver.touch_move.y
			turn -= driver.touch_move.x
		# Horn/engine loop removed by request — driving is silent.
	_horn_t -= delta
	var top := 15.0 if Input.is_action_pressed("sprint") and driven else 11.0
	if throttle > 0.0:
		speed = move_toward(speed, top * throttle, 5.5 * delta)
	elif throttle < 0.0:
		speed = move_toward(speed, -4.0, (12.0 if speed > 0.0 else 4.0) * delta)
	else:
		speed = move_toward(speed, 0.0, 3.0 * delta)
	steer = lerpf(steer, turn, 1.0 - exp(-delta * 6.0))
	rotation.y += steer * delta * clampf(absf(speed) / 4.0, 0.0, 1.0) * 1.6 * signf(speed if absf(speed) > 0.1 else 1.0)
	var fwd := -global_transform.basis.z
	var v := fwd * speed
	v.y = velocity.y - 14.0 * delta if not is_on_floor() else -0.5
	velocity = v
	move_and_slide()
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider()
		if col is Actor and absf(speed) > 4.0:
			(col as Actor).receive_hit(absf(speed) * 1.5, global_position, driver, "vehicle")
			speed *= 0.6
		elif absf(speed) > 6.0 and col is StaticBody3D:
			s.fx.shake(0.3)
			s.sfx.play_at("thwack", global_position, -4.0)
			speed *= -0.25
	_body.rotation.z = lerpf(_body.rotation.z, -steer * clampf(speed / 12.0, -1.0, 1.0) * 0.12, 0.1)
	_body.rotation.x = lerpf(_body.rotation.x, clampf(-throttle * 0.04, -0.05, 0.05), 0.1)
	if driven:
		# pedestrians dive away from a speeding CNG
		for n in get_tree().get_nodes_in_group("actors"):
			var a := n as Actor
			if a and a.global_position.distance_to(global_position + fwd * 3.0) < 3.5 and absf(speed) > 5.0 and a.ai.state in [ActorAI.State.WANDER, ActorAI.State.IDLE, ActorAI.State.STAND]:
				a.ai.dest = global_position
				a.ai.set_state(ActorAI.State.FLEE)
				a.say(["আরে আস্তে!", "চোখে দেখেন না?!", "সিএনজি না ট্যাংক?"][randi() % 3], 2.0)
