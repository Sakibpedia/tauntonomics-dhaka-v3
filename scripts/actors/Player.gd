class_name Player
extends CharacterBody3D
## এস এম নাজমুয সাকিব: unemployed lawyer, three-time viva survivor, carrier of 3,000 answers.
## GTA-style third-person controls: camera-relative run/sprint/crouch, jumping, ladder climbing,
## a three-hit punch combo with a heavy kick, block and parry, dodge roll, lock-on, pick up and throw
## bricks, the law-book shield (stops projectiles and halves ghost drain), taunts that make goons
## reckless, candles that make a ghost-free circle, and vehicles. Health, sanity (falls outdoors at
## night) and stamina. At zero health or sanity you are "অকৃতকার্য" and wake at the safehouse.

const LOOK := {"sex": "m", "outfit": "coat", "hair": "short", "beard": "full", "age": 0.25, "build": 0.5, "face": 1,
	"colors": ["#16171b", "#f2f2f2"], "skin": Color("#b07a5c"), "height": 1.0}

var s: Services
var body: Humanoid
var cam: PlayerCamera
var hp := 100.0
var sanity := 100.0
var stamina := 100.0
var walk_speed := 2.2
var run_speed := 4.8
var sprint_speed := 7.2
var crouch_speed := 1.4
var jump_v := 5.2
var crouching := false
var sprinting := false
var blocking := false
var shielding := false
var _block_t := 0.0
var _dodge_t := 0.0
var _combo := 0
var _combo_t := 0.0
var _attack_lock := 0.0
var _pending_hit := 0.0
var _pending_kind := ""
var carried := ""                # "brick" while holding something to throw
var dead := false
var controls_enabled := true
var vehicle: Node = null
var on_ladder: Node3D = null
var interact_target: Node = null
var _scan_t := 0.0
var _step_t := 0.0
var _was_floor := true
var _hurt_cd := 0.0
var _sheltered := false
var _shelter_t := 0.0
var taunt_cd := 0.0
var touch_move := Vector2.ZERO

func setup(services: Services) -> void:
	s = services
	add_to_group("player")
	collision_layer = Actor.LAYER_PLAYER
	collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ACTOR | Actor.LAYER_VEHICLE
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.78
	shape.shape = cap
	shape.position = Vector3(0, 0.89, 0)
	add_child(shape)
	body = Humanoid.new()
	body.name = "Body"
	add_child(body)
	body.setup(LOOK.duplicate())
	body.hold("book", false)
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(52.0)
	# Stair treads are paired with a low-slope ramp collider so the player climbs smoothly.
	hp = float(s.save.g("hp", 100.0))
	sanity = float(s.save.g("sanity", 100.0))

func is_sprinting() -> bool:
	return sprinting

func is_dead() -> bool:
	return dead

func is_sheltered() -> bool:
	return _sheltered

## Multiplier on how fast guards notice you.
func stealth_factor() -> float:
	var f := 1.0
	if crouching:
		f *= 0.4
	if sprinting:
		f *= 1.5
	if s.clock and s.clock.is_night() and s.world and s.world.has_method("light_level"):
		f *= lerpf(0.45, 1.0, float(s.world.call("light_level", global_position)))
	return f

# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if dead or not controls_enabled or vehicle != null:
		return
	# Mouse click on a friendly/neutral interactable under the crosshair triggers "E" (talk/use).
	# Combat punches still work normally against hostile actors or when no interactable is aimed at.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cam3d := get_viewport().get_camera_3d()
		if cam3d:
			var from := cam3d.global_position
			var to := from + (-cam3d.global_transform.basis.z) * 16.0
			var q := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD | Actor.LAYER_ACTOR | Actor.LAYER_VEHICLE | Actor.LAYER_INTERACTABLE)
			q.collide_with_areas = true
			q.exclude = [get_rid()]
			var res := get_world_3d().direct_space_state.intersect_ray(q)
			if not res.is_empty():
				var col: Object = res.get("collider")
				if col is Node:
					var node := col as Node
					if node.is_in_group("interactable"):
						var is_hostile := (node is Actor) and ((node as Actor).hostile or (node as Actor).ai.aggro)
						if not is_hostile and interact_target == node:
							_interact()
							return
		if carried != "":
			_throw()
		else:
			_attack(false)
	elif event.is_action_pressed("kick"):
		_attack(true)
	elif event.is_action_pressed("dodge"):
		_dodge()
	elif event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("pickup"):
		_pickup()
	elif event.is_action_pressed("taunt"):
		_taunt()
	elif event.is_action_pressed("candle"):
		_place_candle()
	elif event.is_action_pressed("lock_on"):
		_toggle_lock()
	elif event.is_action_pressed("crouch"):
		crouching = not crouching

func _physics_process(delta: float) -> void:
	if vehicle != null:
		return
	var v := velocity
	if not is_on_floor() and on_ladder == null:
		v.y -= 14.0 * delta
	var input := Vector2.ZERO
	if controls_enabled and not dead:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back") + touch_move
		input = input.limit_length(1.0)
	blocking = controls_enabled and not dead and Input.is_action_pressed("block")
	shielding = controls_enabled and not dead and Input.is_action_pressed("shield")
	if blocking:
		_block_t += delta
	else:
		_block_t = 0.0
	var aiming := controls_enabled and Input.is_action_pressed("aim") and carried != ""
	cam.aiming = aiming
	sprinting = controls_enabled and Input.is_action_pressed("sprint") and input.length() > 0.3 and stamina > 1.0 and not crouching and not blocking
	var speed := run_speed
	if crouching:
		speed = crouch_speed
	elif sprinting:
		speed = sprint_speed
	elif input.length() < 0.6:
		speed = walk_speed
	if blocking or shielding:
		speed = minf(speed, walk_speed * 0.7)
	if _attack_lock > 0.0:
		speed *= 0.25
	var dir := (cam.right_flat() * input.x - cam.forward_flat() * input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target_v := dir * speed
	if _dodge_t > 0.0:
		_dodge_t -= delta
		target_v = -global_transform.basis.z * 7.5
	# ladders
	if on_ladder != null:
		v.y = -input.y * 2.6
		if Input.is_action_pressed("jump"):
			v.y = 2.6
		target_v *= 0.3
		if is_on_floor() and input.y > 0.3:
			on_ladder = null
	var accel := 14.0 if is_on_floor() else 3.0
	v.x = move_toward(v.x, target_v.x, accel * delta * maxf(speed, 3.0))
	v.z = move_toward(v.z, target_v.z, accel * delta * maxf(speed, 3.0))
	if controls_enabled and not dead and Input.is_action_just_pressed("jump") and is_on_floor() and on_ladder == null:
		v.y = jump_v
		s.sfx.play("whoosh", -14.0)
	velocity = v
	move_and_slide()
	# landing
	if is_on_floor() and not _was_floor:
		body.land(clampf(-v.y / 8.0, 0.2, 1.2))
		if v.y < -9.0:
			_damage(( -v.y - 9.0) * 6.0, "fall")
	_was_floor = is_on_floor()
	# facing: lock target, aiming, attacking or movement
	var face := Vector3.ZERO
	if cam.lock_target != null and is_instance_valid(cam.lock_target):
		face = cam.lock_target.global_position - global_position
	elif aiming or blocking or _attack_lock > 0.0:
		face = cam.forward_flat()
	elif Vector2(velocity.x, velocity.z).length() > 0.4:
		face = velocity
	face.y = 0.0
	if face.length() > 0.05 and not dead:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-delta * (16.0 if _attack_lock > 0.0 else 10.0)))
	# stamina
	if sprinting:
		stamina = maxf(0.0, stamina - 16.0 * delta)
	else:
		stamina = minf(100.0, stamina + 22.0 * delta)
	# body sustains
	body.set_sustain("crouch", crouching)
	body.set_sustain("block", blocking)
	body.set_sustain("read", shielding)
	body.set_sustain("aim", aiming)
	body.set_sustain("carry", carried != "" and not aiming)
	if cam.lock_target != null and is_instance_valid(cam.lock_target):
		body.look_target = cam.lock_target.global_position + Vector3(0, 1.5, 0)
	else:
		body.look_target = null
	body.animate(delta, velocity, is_on_floor() or on_ladder != null)
	# footsteps make noise for AI hearing
	var hs := Vector2(velocity.x, velocity.z).length()
	_step_t -= delta * hs
	if _step_t <= 0.0 and is_on_floor() and hs > 0.5:
		_step_t = 1.3
		s.sfx.play("step", -22.0 if crouching else -14.0, randf_range(0.9, 1.1))
		if not crouching:
			s.bus.noise.emit(global_position, 3.0 if not sprinting else 9.0, "step")
	# combat timers
	_combo_t -= delta
	_attack_lock -= delta
	taunt_cd -= delta
	_hurt_cd -= delta
	if _pending_hit > 0.0:
		_pending_hit -= delta
		if _pending_hit <= 0.0:
			_resolve_hit(_pending_kind)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.12
		_scan_interactables()
		_update_shelter()
	_night_drain(delta)

# ---------------------------------------------------------------- combat
func _attack(heavy: bool) -> void:
	if _attack_lock > 0.0 or dead or blocking:
		return
	var clip: String = "kick" if heavy or sprinting else ["punch_r", "punch_l", "hook"][_combo % 3]
	if _combo_t <= 0.0:
		_combo = 0
		clip = "kick" if heavy or sprinting else "punch_r"
	_combo += 1
	_combo_t = 0.9
	_attack_lock = 0.32 if clip != "kick" and clip != "hook" else 0.48
	body.play(clip)
	_pending_hit = 0.15 if clip.begins_with("punch") else 0.22
	_pending_kind = clip
	s.sfx.play("swing", -10.0, randf_range(0.95, 1.1))
	_auto_face()

func _auto_face() -> void:
	var best: Node3D = null
	var bd := 3.2
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a == null or a.dead or a.health.is_down:
			continue
		var d := a.global_position.distance_to(global_position)
		if d < bd:
			var to := (a.global_position - global_position).normalized()
			if cam.forward_flat().dot(to) > 0.2:
				bd = d
				best = a
	if best:
		var to2 := best.global_position - global_position
		rotation.y = atan2(-to2.x, -to2.z)

func _resolve_hit(kind: String) -> void:
	var dmg := 14.0
	var reach := 1.7
	match kind:
		"punch_l":
			dmg = 12.0
		"hook":
			dmg = 22.0
		"kick":
			dmg = 26.0
			reach = 2.0
	var fwd := -global_transform.basis.z
	var hit_any := false
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a == null or a.dead or a.health.is_down:
			continue
		var to := a.global_position - global_position
		to.y = 0.0
		if to.length() < reach and fwd.dot(to.normalized()) > 0.35:
			a.receive_hit(dmg, global_position, self, kind)
			hit_any = true
	for g in get_tree().get_nodes_in_group("boss"):
		var b := g as Node3D
		if b and b.global_position.distance_to(global_position) < reach + 1.2 and b.has_method("receive_hit"):
			b.call("receive_hit", dmg, global_position, self, kind)
			hit_any = true
	if hit_any:
		s.bus.noise.emit(global_position, 14.0, "fight")

func _dodge() -> void:
	if _dodge_t > 0.0 or stamina < 15.0 or dead:
		return
	stamina -= 15.0
	_dodge_t = 0.42
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + touch_move
	if input.length() > 0.2:
		var dir := (cam.right_flat() * input.x - cam.forward_flat() * input.y).normalized()
		rotation.y = atan2(-dir.x, -dir.z)
	body.play("dodge")
	s.sfx.play("whoosh", -6.0)

func _toggle_lock() -> void:
	if cam.lock_target != null:
		cam.lock_target = null
		return
	var best: Node3D = null
	var bd := 14.0
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a and not a.dead and not a.health.is_down and (a.hostile or a.ai.aggro):
			var d := a.global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = a
	cam.lock_target = best

func _taunt() -> void:
	if taunt_cd > 0.0:
		return
	taunt_cd = 6.0
	var group := "player_combat"
	var near_pseudo := false
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a and a.global_position.distance_to(global_position) < 10.0 and a.faction == "pseudo":
			near_pseudo = true
	if near_pseudo:
		group = "homeco"
	s.say("সাকিব", s.taunts.pick(group), 4.0)
	body.play("taunt")
	for n in get_tree().get_nodes_in_group("syndicate"):
		var a2 := n as Actor
		if a2 and a2.global_position.distance_to(global_position) < 12.0 and not a2.health.is_down:
			a2.ai.block_chance = 0.0
			a2.ai.damage *= 1.15
			a2.body.expression = "angry"
			a2.say(["কী বললি?!", "মুখ সামলে!", "তোর ধারা তোর কাছে রাখ!"][randi() % 3], 2.0)
			if not a2.ai.aggro and a2.ai.state != ActorAI.State.FIGHT:
				a2.ai.dest = global_position
				a2.ai.set_state(ActorAI.State.WATCH)

# ---------------------------------------------------------------- damage
func receive_hit(amount: float, from: Vector3, attacker: Node, kind: String = "punch") -> void:
	if dead or _dodge_t > 0.0:
		return
	var to_att := (from - global_position)
	to_att.y = 0.0
	var facing := (-global_transform.basis.z).dot(to_att.normalized()) > 0.3
	if shielding and facing and kind in ["throw", "paper", "brick"]:
		s.sfx.play("thwack", -6.0)
		s.fx.paper(global_position + Vector3(0, 1.3, 0) - global_transform.basis.z * 0.4, 6)
		return
	if blocking and facing:
		if _block_t < 0.22 and attacker is Actor:
			# parry: the attacker reels
			var a := attacker as Actor
			s.sfx.play("parry", -2.0)
			s.fx.sparkle(global_position + Vector3(0, 1.4, 0) - global_transform.basis.z * 0.4)
			a.body.play("hit_back")
			a.health.damage(8.0)
			a.ai._attack_cd = 2.0
			body.play("parry")
			return
		amount *= 0.2
		s.sfx.play("thwack", -8.0)
	_damage(amount, kind)
	body.hit_react(global_transform.basis.inverse() * (global_position - from).normalized(), 1.0)
	body.play("hit_front")
	s.fx.hit(global_position + Vector3(0, 1.3, 0), amount > 15.0)

func _damage(amount: float, kind: String) -> void:
	if dead:
		return
	hp = maxf(0.0, hp - amount)
	s.bus.player_damaged.emit(amount, kind)
	if hp <= 0.0:
		_die("আঘাতে অকৃতকার্য")

func drain_sanity(amount: float) -> void:
	if dead:
		return
	if shielding:
		amount *= 0.5
	sanity = maxf(0.0, sanity - amount)
	if sanity <= 0.0:
		_die("মাথা ঘুরে পড়ে গেলেন: প্রশ্নের ভারে স্যানিটি শূন্য")

func heal(hp_amount: float, sanity_amount: float = 0.0) -> void:
	hp = minf(100.0, hp + hp_amount)
	sanity = minf(100.0, sanity + sanity_amount)

func _die(reason: String) -> void:
	dead = true
	body.clear_sustains()
	body.set_sustain("down", true)
	body.expression = "dead"
	s.sfx.play("sting", -2.0)
	s.bus.player_died.emit(reason)

func respawn(at: Vector3) -> void:
	dead = false
	global_position = at
	velocity = Vector3.ZERO
	hp = 100.0
	sanity = maxf(sanity, 70.0)
	body.set_sustain("down", false)
	body.expression = "neutral"
	carried = ""
	body.hold("", true)

# ---------------------------------------------------------------- night: the minecraft-zombie rule
func _update_shelter() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.8, 0), global_position + Vector3(0, 40.0, 0), Actor.LAYER_WORLD)
	_sheltered = not space.intersect_ray(q).is_empty()

func protected_from_ghosts() -> bool:
	if _sheltered:
		return true
	if s.world and s.world.has_method("is_lit_safe"):
		return bool(s.world.call("is_lit_safe", global_position))
	return false

func _night_drain(delta: float) -> void:
	if s.clock == null or not s.clock.is_night() or dead:
		return
	if protected_from_ghosts():
		sanity = minf(100.0, sanity + delta * 1.5)
		return
	drain_sanity(delta * 0.45)

# ---------------------------------------------------------------- interaction
func _scan_interactables() -> void:
	var best: Node = null
	var bd := 2.6
	var fwd := cam.forward_flat()
	for n in get_tree().get_nodes_in_group("interactable"):
		var n3 := n as Node3D
		if n3 == null or not n3.is_inside_tree():
			continue
		var d := n3.global_position.distance_to(global_position)
		var r := float(n3.get("interact_radius")) if n3.get("interact_radius") != null else 2.6
		if d > maxf(r, 0.5) or d > bd + 0.5:
			continue
		if n.has_method("can_interact") and not bool(n.call("can_interact", self)):
			continue
		var to := (n3.global_position - global_position)
		to.y = 0.0
		var score := d - (fwd.dot(to.normalized()) * 0.8 if to.length() > 0.1 else 0.0)
		if score < bd:
			bd = score
			best = n
	interact_target = best

func _interact() -> void:
	if interact_target != null and is_instance_valid(interact_target):
		interact_target.call("interact", self)

func _pickup() -> void:
	if carried != "":
		return
	for n in get_tree().get_nodes_in_group("throwable"):
		var n3 := n as Node3D
		if n3 and n3.global_position.distance_to(global_position) < 2.0:
			carried = str(n3.get("kind")) if n3.get("kind") != null else "brick"
			body.play("pickup")
			body.hold(carried, true)
			n3.queue_free()
			s.sfx.play("click", -8.0)
			return
	s.toast("কাছে ছোড়ার মতো কিছু নেই (ইট খুঁজুন)", "info")

func _throw() -> void:
	var kind := carried
	carried = ""
	body.hold("", true)
	body.play("throw")
	var tw := get_tree().create_timer(0.28)
	tw.timeout.connect(func() -> void:
		var pr := Projectile.new()
		get_parent().add_child(pr)
		var from := global_position + Vector3(0, 1.65, 0) - global_transform.basis.z * 0.45
		var aim_to := cam.cam.global_position - cam.cam.global_transform.basis.z * 30.0
		if cam.lock_target != null and is_instance_valid(cam.lock_target):
			aim_to = cam.lock_target.global_position + Vector3(0, 1.2, 0)
		pr.launch(s, from, aim_to, self, kind, 30.0, 20.0))

func _place_candle() -> void:
	if int(s.save.g("candles", 0)) <= 0:
		s.toast("মোমবাতি নেই। দোকান থেকে কিনুন।", "info")
		return
	s.save.add("candles", -1)
	var c := Candle.new()
	get_parent().add_child(c)
	c.global_position = global_position - global_transform.basis.z * 0.8
	c.setup(s)
	s.sfx.play("candle", -4.0)
