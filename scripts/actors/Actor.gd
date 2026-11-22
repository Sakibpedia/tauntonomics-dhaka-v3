class_name Actor
extends CharacterBody3D
## A person in the city. Composed of three components that are injected, not looked up:
##   ActorVisuals (rig, labels, icons), ActorHealth (HP and the down/death rules), ActorAI (brain).
## Every actor can talk (Conversation), can quiz the player (universal exam), remembers the
## player, and reacts to time of day, Heat and fights. Syndicate members can be finished, but only
## by the player's explicit choice, and they ask one last question first. Leave it unanswered and
## they come back at night as a question-ghost.

signal downed(actor: Actor)
signal died(actor: Actor)
signal spoke(actor: Actor, text: String)

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ACTOR := 4
const LAYER_VEHICLE := 32
const LAYER_INTERACTABLE := 64

var s: Services
var data: Dictionary = {}
var id := ""
var display_name := ""
var role := ""
var faction := "civilian"
var cats: Array = ["gk"]
var examiner := 0.5
var greet_lines: Array = []
var story_char := false
var informant := false
var hostile := false
var mission_tag := ""
var dead := false
var arrested := false
var finish_pending := false
var walk_speed := 1.35
var run_speed := 4.6
var exam_reward := 120
var quizzed := false

var visuals: ActorVisuals
var health: ActorHealth
var ai: ActorAI
var body: Humanoid

var move_dir := Vector3.ZERO
var move_speed := 0.0
var face_target: Variant = null
var _gravity := 9.8
var _lod_t := 0.0
var _anim_accum := 0.0
var far := false

func setup(services: Services, d: Dictionary) -> void:
	s = services
	data = d
	id = str(d.get("id", "npc_%d" % randi()))
	display_name = str(d.get("name", "পথচারী"))
	role = str(d.get("role", ""))
	faction = str(d.get("faction", "civilian"))
	cats = d.get("cats", ["gk"])
	examiner = float(d.get("examiner", 0.5))
	greet_lines = d.get("greet", [])
	story_char = bool(d.get("story", false))
	informant = bool(d.get("informant", false))
	hostile = faction == "syndicate" and bool(d.get("hostile", true))
	walk_speed = float(d.get("walk", randf_range(1.15, 1.5)))
	var look: Dictionary = d.get("look", {})
	if float(look.get("age", 0.3)) > 0.75:
		walk_speed *= 0.75
	collision_layer = LAYER_ACTOR
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ACTOR | LAYER_VEHICLE
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.75
	shape.shape = cap
	shape.position = Vector3(0, 0.875, 0)
	add_child(shape)
	visuals = ActorVisuals.new()
	visuals.name = "Visuals"
	add_child(visuals)
	visuals.build(look, display_name, role)
	body = visuals.body
	health = ActorHealth.new()
	health.name = "Health"
	add_child(health)
	var hp := float(d.get("hp", 60.0 if faction != "syndicate" else 90.0))
	health.setup(hp, float(d.get("armor", 0.0)))
	health.can_recover = faction != "syndicate"
	health.downed.connect(_on_downed)
	health.recovered.connect(_on_recovered)
	ai = ActorAI.new()
	ai.name = "AI"
	add_child(ai)
	ai.setup(self, s, d)
	add_to_group("actors")
	add_to_group("interactable")
	if faction == "syndicate":
		add_to_group("syndicate")
	if story_char:
		add_to_group("story")
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4

# ---------------------------------------------------------------- movement
func _physics_process(delta: float) -> void:
	if dead:
		return
	var v := velocity
	if not is_on_floor():
		v.y -= _gravity * delta
	else:
		v.y = maxf(v.y, -0.5)
	var want := move_dir * move_speed
	if health.is_down:
		want = Vector3.ZERO
	var acc := 10.0 if want.length() > 0.1 else 14.0
	v.x = move_toward(v.x, want.x, acc * delta)
	v.z = move_toward(v.z, want.z, acc * delta)
	velocity = v
	move_and_slide()
	# facing
	var look_dir := Vector3.ZERO
	if face_target != null:
		var ft: Vector3 = face_target
		look_dir = ft - global_position
	elif Vector2(velocity.x, velocity.z).length() > 0.3:
		look_dir = velocity
	look_dir.y = 0.0
	if look_dir.length() > 0.05 and not health.is_down:
		var yaw := atan2(-look_dir.x, -look_dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-delta * 8.0))
	# animation LOD: far actors animate at a lower rate
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.5
		var cam := get_viewport().get_camera_3d()
		if cam:
			var d2 := cam.global_position.distance_squared_to(global_position)
			far = d2 > 30.0 * 30.0
			visuals.set_lod(d2 > 16.0 * 16.0)
			visuals.visible = d2 < 160.0 * 160.0
	_anim_accum += delta
	var step := 0.1 if far else 0.0
	if _anim_accum >= step:
		body.animate(_anim_accum, velocity, is_on_floor())
		_anim_accum = 0.0

func go_toward(p: Vector3, speed: float) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() < 0.15:
		move_dir = Vector3.ZERO
		move_speed = 0.0
		return
	move_dir = d.normalized()
	move_speed = speed

func stop() -> void:
	move_dir = Vector3.ZERO
	move_speed = 0.0

func head_pos() -> Vector3:
	return global_position + Vector3(0, 1.62 * body.h, 0)

# ---------------------------------------------------------------- talking
func say(text: String, seconds: float = 3.2, subtitle: bool = false) -> void:
	if text == "":
		return
	visuals.say(text, seconds)
	spoke.emit(self, text)
	if subtitle and s:
		s.bus.subtitle.emit(display_name, text, seconds)

func bark(group: String) -> void:
	if s:
		say(s.taunts.pick(group), 3.0)

# ---------------------------------------------------------------- interaction (duck-typed, used by Player)
func can_interact(_p: Node) -> bool:
	if dead or arrested:
		return false
	if health.is_down:
		return faction == "syndicate" and not finish_pending
	return not (hostile and ai.state == ActorAI.State.FIGHT)

func interact_prompt() -> String:
	if health.is_down and faction == "syndicate":
		return "সিদ্ধান্ত নিন: %s" % display_name
	return "কথা বলুন: %s" % display_name

func interact(p: Node) -> void:
	if health.is_down and faction == "syndicate":
		if s.ui:
			s.ui.call("open_fate", self)
		return
	if s.ui:
		s.ui.call("open_conversation", self, p)

# ---------------------------------------------------------------- combat
## Called by the player's fists, thrown bricks and books.
func receive_hit(amount: float, from: Vector3, attacker: Node, kind: String = "punch") -> void:
	if dead or health.is_down:
		return
	var local := global_transform.basis.inverse() * (global_position - from).normalized()
	if ai.try_block(attacker, kind):
		s.sfx.play_at("parry", head_pos(), -4.0)
		s.fx.sparkle(head_pos() - (global_position - from).normalized() * 0.3, Color(0.8, 0.9, 1.0))
		body.play("parry")
		return
	var stagger := health.damage(amount)
	body.hit_react(local, 1.4 if stagger else 0.8)
	body.play("hit_front" if local.z > 0.0 else "hit_back")
	body.expression = "angry" if faction == "syndicate" else "scared"
	s.sfx.play_at("punch", head_pos(), -2.0, randf_range(0.9, 1.15))
	s.fx.hit(head_pos() - Vector3(0, 0.3, 0), stagger)
	var push := (global_position - from)
	push.y = 0.0
	velocity += push.normalized() * (3.0 if stagger else 1.2)
	ai.on_hit(attacker)
	if attacker != null and attacker.is_in_group("player") and faction != "syndicate":
		s.bus.crime.emit(global_position, 1)
		if s.save:
			s.save.mem(id)["beaten"] = int(s.save.mem(id).get("beaten", 0)) + 1

func _on_downed() -> void:
	body.clear_sustains()
	body.set_sustain("down", true)
	body.expression = "sad"
	visuals.set_icon("")
	stop()
	collision_layer = 0
	s.sfx.play_at("thwack", global_position, 0.0)
	s.fx.dust(global_position, 14)
	if s.save:
		s.save.add("kos", 1)
	ai.set_state(ActorAI.State.DOWNED)
	downed.emit(self)
	s.bus.actor_downed.emit(self)
	if faction == "syndicate":
		say("আহ... আমাকে পুলিশে দিন, নাকি... শেষ?", 4.0)

func _on_recovered() -> void:
	body.set_sustain("down", false)
	body.play("getup")
	collision_layer = LAYER_ACTOR
	ai.set_state(ActorAI.State.FLEE)

## Fate of a downed Syndicate member, chosen by the player.
func arrest() -> void:
	arrested = true
	s.save.add("arrests", 1)
	say(s.taunts.pick("arrest"), 3.0)
	s.bus.actor_arrested.emit(self)
	s.toast("%s গ্রেপ্তার হলো। সাক্ষী জীবিত, মামলা শক্ত।" % display_name, "good")
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(visuals, "scale", Vector3(1, 0.01, 1), 0.6)
	tw.tween_callback(queue_free)

func spare() -> void:
	health.can_recover = true
	health.down_time = health.recover_after - 3.0
	hostile = false
	faction = "civilian"
	say("ধন্যবাদ... আমি আর সিন্ডিকেটে নেই।", 3.0)
	s.save.add("empathy", 1)

## Final question. passed = the player answered it; otherwise the actor becomes a ghost.
func die_after_question(q: Dictionary, passed: bool) -> void:
	dead = true
	s.save.add("kills", 1)
	if passed:
		say(s.taunts.pick("ghost_banished"), 3.0)
	else:
		var rec := {"id": "g_%s_%d" % [id, Time.get_ticks_msec()], "name": display_name, "q": str(q.get("id", "")),
			"look": data.get("look", {}), "level": int(s.save.g("level", 1)),
			"x": global_position.x, "z": global_position.z}
		s.save.add_ghost(rec)
		s.toast("%s উত্তর না পেয়ে মারা গেল। রাতে প্রশ্নভূত হয়ে ফিরবে।" % display_name, "danger")
	died.emit(self)
	s.bus.actor_died.emit(self, true)
	_ragdoll(Vector3.ZERO)

func _ragdoll(impulse: Vector3) -> void:
	var rd := Ragdoll.new()
	get_parent().add_child(rd)
	rd.global_transform = global_transform
	rd.build(body, impulse, velocity, 7.0)
	queue_free()
