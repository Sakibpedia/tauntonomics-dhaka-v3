class_name ActorAI
extends Node
## The brain of an Actor: a finite-state machine with perception (sight cone with line of sight,
## hearing through EventBus.noise), a stealth detection meter, daily schedules (go home at night),
## crowd reactions (flee, cower, film it on the phone), protest behaviour, and melee combat with
## attack tokens so that only two goons swing at once, plus wind-up tells, blocking and brick throws.

enum State { IDLE, WANDER, GOTO, STAND, TALK, FLEE, COWER, FILM, FIGHT, PATROL, PROTEST, DOWNED, FOLLOW, GO_HOME, WATCH, TAIL, GUARD, CHALLENGE }

static var attack_tokens: Dictionary = {}     # actor instance id -> true
const MAX_ATTACKERS := 2

var actor: Actor
var s: Services
var state: State = State.IDLE
var state_t := 0.0
var home := Vector3.ZERO
var path: PackedVector3Array = PackedVector3Array()
var path_i := 0
var dest := Vector3.ZERO
var brave := 0.5
var chatty := 0.5
var sight := 24.0
var fov_cos := 0.45
var sees_player := false
var detect := 0.0
var aggro := false
var _think := 0.0
var _bark_t := 0.0
var _attack_cd := 1.5
var _windup := 0.0
var _strafe := 1.0
var _guard_post := Vector3.ZERO
var patrol: Array = []
var _patrol_i := 0
var protest_center := Vector3.ZERO
var follow_target: Node3D
var tail_route: PackedVector3Array = PackedVector3Array()
var on_spot: Callable          # tail/sneak missions: called once when this actor spots the player
var on_arrive: Callable
var _greeted := false
var _ranged_cd := 4.0
var block_chance := 0.25
var damage := 9.0
var _night_checked := false

func setup(a: Actor, services: Services, d: Dictionary) -> void:
	actor = a
	s = services
	home = a.global_position
	brave = float(d.get("brave", randf()))
	chatty = float(d.get("chatty", randf()))
	damage = float(d.get("damage", 9.0 if a.faction == "syndicate" else 5.0))
	block_chance = float(d.get("block", 0.25 if a.faction == "syndicate" else 0.05))
	var start := str(d.get("state", "wander"))
	match start:
		"stand": state = State.STAND
		"guard": state = State.GUARD
		"protest": state = State.PROTEST
		"fight": state = State.FIGHT
		"patrol": state = State.PATROL
		"idle": state = State.IDLE
		_: state = State.WANDER
	s.bus.noise.connect(_on_noise)
	s.bus.crime.connect(_on_crime)
	call_deferred("_init_home")

func _init_home() -> void:
	if is_instance_valid(actor):
		home = actor.global_position
		_guard_post = home
		if protest_center == Vector3.ZERO:
			protest_center = home

func _exit_tree() -> void:
	_release_token()

func set_state(st: State) -> void:
	if state == st:
		return
	if state == State.FIGHT:
		_release_token()
	state = st
	state_t = 0.0
	path = PackedVector3Array()
	actor.face_target = null
	actor.body.set_sustain("march", false)
	actor.body.set_sustain("cower", false)
	actor.body.set_sustain("phone", false)
	actor.body.set_sustain("block", false)
	if st != State.TALK:
		actor.body.look_target = null

func _player() -> Node3D:
	if s.player != null and is_instance_valid(s.player):
		return s.player as Node3D
	return null

# ---------------------------------------------------------------- perception
func _perceive() -> void:
	var p := _player()
	sees_player = false
	if p == null:
		return
	var to := p.global_position - actor.global_position
	var dist := to.length()
	if dist > sight:
		return
	var fwd := -actor.global_transform.basis.z
	var flat := Vector3(to.x, 0, to.z).normalized()
	var in_cone := fwd.dot(flat) > fov_cos or dist < 2.0
	if not in_cone:
		return
	var space := actor.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(actor.head_pos(), p.global_position + Vector3(0, 1.4, 0), Actor.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	sees_player = hit.is_empty()

func _on_noise(pos: Vector3, radius: float, kind: String) -> void:
	if not is_instance_valid(actor) or actor.health.is_down or actor.dead:
		return
	if actor.global_position.distance_to(pos) > radius:
		return
	if actor.faction == "syndicate" and state in [State.GUARD, State.PATROL, State.STAND, State.IDLE, State.WANDER]:
		dest = pos
		set_state(State.WATCH)
		actor.say("কে ওখানে?", 2.0)
	elif actor.faction == "civilian" and kind == "fight" and state in [State.WANDER, State.STAND, State.IDLE]:
		_react_to_violence(pos)

func _on_crime(pos: Vector3, _sev: int) -> void:
	if not is_instance_valid(actor) or actor.health.is_down or actor.dead:
		return
	if actor.global_position.distance_to(pos) < 16.0 and actor.faction in ["civilian", "student", "patient"]:
		_react_to_violence(pos)

func _react_to_violence(pos: Vector3) -> void:
	if state in [State.FLEE, State.COWER, State.FILM, State.TALK, State.PROTEST]:
		return
	dest = pos
	var r := randf()
	if r < 0.22 + chatty * 0.2:
		set_state(State.FILM)
		actor.say(["লাইভে যাচ্ছি! মারামারি, লাইক দিন!", "ভিডিও করছি, ভাইরাল হবে!", "ভাই, আরেকবার মারেন, ক্যামেরা অন হয়নি!"][randi() % 3], 3.0)
	elif r < 0.55 and brave < 0.4:
		set_state(State.COWER)
		actor.say("আল্লাহ বাঁচাও!", 2.0)
	else:
		set_state(State.FLEE)

## Called by Actor when it takes a hit.
func on_hit(attacker: Node) -> void:
	if actor.faction == "syndicate" or actor.faction == "pseudo_hostile":
		aggro = true
		set_state(State.FIGHT)
		if s.heat:
			s.heat.spotted()
	elif actor.faction in ["civilian", "student", "patient"]:
		if brave > 0.8 and randf() < 0.3:
			aggro = true
			set_state(State.FIGHT)
			actor.say("আমাকে মারলেন কেন? দাঁড়ান!", 2.0)
		else:
			set_state(State.FLEE)
	if attacker is Node3D:
		dest = (attacker as Node3D).global_position

func try_block(_attacker: Node, kind: String) -> bool:
	if state != State.FIGHT or _windup > 0.0 or kind == "throw":
		return false
	return randf() < block_chance

# ---------------------------------------------------------------- main loop
func _physics_process(delta: float) -> void:
	if actor == null or actor.dead:
		return
	state_t += delta
	_think -= delta
	_bark_t -= delta
	if actor.health.is_down:
		if state != State.DOWNED:
			set_state(State.DOWNED)
		actor.stop()
		return
	if _think <= 0.0:
		_think = 0.2 if not actor.far else 0.6
		_perceive()
		_schedule()
		_detection(0.2 if not actor.far else 0.6)
	match state:
		State.IDLE, State.STAND:
			actor.stop()
			if state_t > randf_range(6.0, 14.0) and state == State.IDLE:
				set_state(State.WANDER)
			_ambient_greet()
		State.WANDER:
			_wander(delta)
			_ambient_greet()
		State.GOTO:
			if _follow_path(actor.walk_speed):
				actor.stop()
				set_state(State.STAND)
				if on_arrive.is_valid():
					on_arrive.call()
		State.GO_HOME:
			if _follow_path(actor.walk_speed * 1.2):
				actor.queue_free()
		State.FLEE:
			var away := actor.global_position - dest
			away.y = 0.0
			if away.length() < 0.1:
				away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			actor.go_toward(actor.global_position + away.normalized() * 5.0, actor.run_speed * 0.9)
			if state_t > 7.0:
				set_state(State.WANDER)
		State.COWER:
			actor.stop()
			actor.body.set_sustain("cower", true)
			actor.face_target = dest
			if state_t > 9.0:
				set_state(State.FLEE)
		State.FILM:
			actor.stop()
			actor.body.set_sustain("phone", true)
			actor.body.hold("phone")
			actor.face_target = dest
			if state_t > 10.0:
				actor.body.hold("")
				set_state(State.WANDER)
		State.TALK:
			actor.stop()
			var p := _player()
			if p:
				actor.face_target = p.global_position
				actor.body.look_target = p.global_position + Vector3(0, 1.55, 0)
		State.FIGHT:
			_fight(delta)
		State.PATROL:
			_patrol()
		State.GUARD:
			if actor.global_position.distance_to(_guard_post) > 1.0:
				actor.go_toward(_guard_post, actor.walk_speed)
			else:
				actor.stop()
			if state_t > 4.0:
				state_t = 0.0
				actor.rotation.y += randf_range(-1.2, 1.2)
		State.WATCH:
			actor.stop()
			actor.face_target = dest
			if state_t > 4.0:
				set_state(State.PATROL if not patrol.is_empty() else State.GUARD)
		State.PROTEST:
			_protest(delta)
		State.FOLLOW:
			if follow_target and is_instance_valid(follow_target):
				var d := actor.global_position.distance_to(follow_target.global_position)
				if d > 2.5:
					actor.go_toward(follow_target.global_position, actor.walk_speed if d < 6.0 else actor.run_speed)
				else:
					actor.stop()
		State.TAIL:
			_tail()
		State.CHALLENGE:
			var p2 := _player()
			if p2 == null:
				set_state(State.WANDER)
			else:
				var d2 := actor.global_position.distance_to(p2.global_position)
				if d2 > 2.2:
					actor.go_toward(p2.global_position, actor.walk_speed * 1.4)
				else:
					actor.stop()
					actor.face_target = p2.global_position
					actor.body.look_target = p2.global_position + Vector3(0, 1.55, 0)
				if state_t > 25.0:
					set_state(State.WANDER)
		State.DOWNED:
			actor.stop()

# ---------------------------------------------------------------- behaviours
func _schedule() -> void:
	if s.clock == null:
		return
	var night := s.clock.is_night()
	if night and actor.faction in ["civilian", "student"] and not actor.story_char and actor.mission_tag == "" \
			and state in [State.WANDER, State.IDLE, State.STAND] and not _night_checked:
		_night_checked = true
		if randf() < 0.85 and s.world and s.world.has_method("nearest_door"):
			dest = s.world.call("nearest_door", actor.global_position)
			_make_path(dest)
			set_state(State.GO_HOME)
			_make_path(dest)
			if randf() < 0.3:
				actor.say(["রাত হয়ে গেছে, বাসায় যাই। প্রশ্নভূত বের হবে।", "অন্ধকারে থাকলে মাথায় প্রশ্ন ঘোরে।", "মোমবাতি কিনতে হবে..."][randi() % 3], 3.0)
	if not night:
		_night_checked = false

func _ambient_greet() -> void:
	var p := _player()
	if p == null or _greeted or _bark_t > 0.0:
		return
	var d := actor.global_position.distance_to(p.global_position)
	if d < 4.5 and sees_player and randf() < 0.35 + chatty * 0.3:
		_greeted = true
		_bark_t = 20.0
		actor.body.look_target = p.global_position + Vector3(0, 1.55, 0)
		var line := ""
		if not actor.greet_lines.is_empty() and randf() < 0.5:
			line = str(actor.greet_lines[randi() % actor.greet_lines.size()])
		elif actor.faction == "pseudo":
			line = s.taunts.pick("protest_chant")
		elif s.heat and s.heat.stars > 0:
			line = ["উকিল সাহেব, আপনাকে খুঁজছে ওরা!", "পেছনে সিন্ডিকেটের লোক!", "লুকান, ভাই!"][randi() % 3]
		else:
			line = s.taunts.pick("civilian")
		actor.say(line, 4.0)
		if randf() < 0.4:
			actor.body.play("wave")
		get_tree().create_timer(6.0).timeout.connect(func() -> void:
			if is_instance_valid(actor):
				actor.body.look_target = null)
	elif d > 12.0:
		_greeted = false

func _wander(_delta: float) -> void:
	if path.is_empty() or path_i >= path.size():
		if state_t > 0.5 and randf() < 0.25:
			set_state(State.IDLE)
			return
		var target := home + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
		if s.world and s.world.has_method("random_sidewalk_point"):
			target = s.world.call("random_sidewalk_point", actor.global_position, 40.0)
		_make_path(target)
	_follow_path(actor.walk_speed)
	if actor.is_on_wall() and state_t > 1.0:
		path = PackedVector3Array()
		state_t = 0.0

func _make_path(target: Vector3) -> void:
	dest = target
	if s.world and s.world.has_method("street_path"):
		path = s.world.call("street_path", actor.global_position, target)
	else:
		path = PackedVector3Array([target])
	path_i = 0

## Returns true when the end of the path is reached.
func _follow_path(speed: float) -> bool:
	if path.is_empty():
		_make_path(dest)
		if path.is_empty():
			return true
	if path_i >= path.size():
		return true
	var p := path[path_i]
	var to := p - actor.global_position
	to.y = 0.0
	if to.length() < 0.8:
		path_i += 1
		return path_i >= path.size()
	actor.go_toward(p, speed)
	# light separation from nearby actors so crowds don't merge
	return false

func _patrol() -> void:
	if patrol.is_empty():
		set_state(State.GUARD)
		return
	var p: Vector3 = patrol[_patrol_i]
	if actor.global_position.distance_to(p) < 1.0:
		_patrol_i = (_patrol_i + 1) % patrol.size()
		actor.stop()
	else:
		actor.go_toward(p, actor.walk_speed * 0.8)

## Stealth meter: Syndicate guards fill it while they see the player (faster when close, slower
## when the player crouches in shadow). Full → alarm.
func _detection(dt: float) -> void:
	if actor.faction != "syndicate" or state == State.FIGHT or aggro:
		actor.visuals.alert_level = 0.0
		return
	var p := _player()
	if p == null:
		return
	if sees_player:
		var d := actor.global_position.distance_to(p.global_position)
		var rate := lerpf(1.6, 0.25, clampf(d / sight, 0.0, 1.0))
		if p.has_method("stealth_factor"):
			rate *= float(p.call("stealth_factor"))
		detect = minf(1.0, detect + rate * dt)
		if state in [State.GUARD, State.PATROL, State.IDLE, State.STAND]:
			dest = p.global_position
			if detect > 0.35:
				set_state(State.WATCH)
				actor.face_target = p.global_position
	else:
		detect = maxf(0.0, detect - 0.15 * dt)
	actor.visuals.alert_level = detect
	if detect >= 1.0:
		alarm()

func alarm() -> void:
	if aggro:
		return
	aggro = true
	actor.visuals.alert_level = 0.0
	actor.say(s.taunts.pick("syndicate_bark"), 2.5)
	s.sfx.play_at("alarm", actor.global_position, -6.0)
	if s.heat:
		s.heat.add(1.0, "পাহারাদার আপনাকে দেখে ফেলেছে")
	if on_spot.is_valid():
		on_spot.call()
	for n in get_tree().get_nodes_in_group("syndicate"):
		var other := n as Actor
		if other and other != actor and other.global_position.distance_to(actor.global_position) < 25.0 and other.ai and not other.health.is_down:
			other.ai.aggro = true
			other.ai.set_state(State.FIGHT)
	set_state(State.FIGHT)

func _take_token() -> bool:
	var key := actor.get_instance_id()
	if attack_tokens.has(key):
		return true
	var alive := 0
	for k in attack_tokens.keys():
		if is_instance_id_valid(int(k)):
			alive += 1
		else:
			attack_tokens.erase(k)
	if alive < MAX_ATTACKERS:
		attack_tokens[key] = true
		return true
	return false

func _release_token() -> void:
	if actor:
		attack_tokens.erase(actor.get_instance_id())

func _fight(delta: float) -> void:
	var p := _player()
	if p == null:
		set_state(State.WANDER)
		return
	if p.has_method("is_dead") and bool(p.call("is_dead")):
		actor.stop()
		actor.body.play("victory")
		set_state(State.GUARD)
		return
	actor.face_target = p.global_position
	actor.body.look_target = p.global_position + Vector3(0, 1.5, 0)
	actor.body.expression = "angry"
	if s.heat and sees_player:
		s.heat.spotted()
	var to := p.global_position - actor.global_position
	to.y = 0.0
	var d := to.length()
	_attack_cd -= delta
	_ranged_cd -= delta
	if _bark_t <= 0.0:
		_bark_t = randf_range(5.0, 10.0)
		actor.bark("syndicate_bark")
	if _windup > 0.0:
		_windup -= delta
		actor.stop()
		if _windup <= 0.0:
			_strike(p)
		return
	var has_token := _take_token()
	if d > 7.0 and _ranged_cd <= 0.0 and sees_player and randf() < 0.5:
		_ranged_cd = randf_range(4.0, 7.0)
		_throw_brick(p)
		return
	if has_token:
		if d > 1.5:
			actor.go_toward(p.global_position, actor.run_speed)
		else:
			actor.stop()
			if _attack_cd <= 0.0:
				_attack_cd = randf_range(1.1, 2.0)
				_windup = 0.38
				actor.body.play("punch_r" if randf() < 0.6 else "hook", Callable(), 0.75)
	else:
		# wait in a ring around the player, strafing
		var ring := 3.4
		if state_t > 2.0 and randf() < 0.01:
			_strafe = -_strafe
		var side := to.normalized().cross(Vector3.UP) * _strafe
		var target := p.global_position - to.normalized() * ring + side * 1.5
		actor.go_toward(target, actor.walk_speed * 1.3)
		if d < ring - 0.6:
			actor.go_toward(actor.global_position - to.normalized() * 2.0, actor.walk_speed)

func _strike(p: Node3D) -> void:
	var to := p.global_position - actor.global_position
	to.y = 0.0
	if to.length() < 1.9 and (-actor.global_transform.basis.z).dot(to.normalized()) > 0.4:
		if p.has_method("receive_hit"):
			p.call("receive_hit", damage, actor.global_position, actor, "punch")
	else:
		s.sfx.play_at("swing", actor.global_position, -6.0)

func _throw_brick(p: Node3D) -> void:
	actor.body.play("throw")
	var tw := get_tree().create_timer(0.3)
	tw.timeout.connect(func() -> void:
		if not is_instance_valid(actor) or not is_instance_valid(p) or actor.health.is_down:
			return
		var pr := Projectile.new()
		actor.get_parent().add_child(pr)
		var from := actor.global_position + Vector3(0, 1.6, 0) - actor.global_transform.basis.z * 0.4
		pr.launch(s, from, p.global_position + Vector3(0, 1.2, 0), actor, "brick", damage * 1.2))

func _protest(delta: float) -> void:
	actor.body.set_sustain("march", true)
	var to_c := protest_center - actor.global_position
	to_c.y = 0.0
	var mill := protest_center + Vector3(sin(state_t * 0.2 + actor.get_instance_id()) * 2.5, 0, cos(state_t * 0.17 + actor.get_instance_id() * 0.3) * 2.5)
	if to_c.length() > 6.0:
		actor.go_toward(protest_center, actor.walk_speed)
	else:
		actor.go_toward(mill, 0.5)
	var p := _player()
	if p:
		actor.face_target = protest_center + (p.global_position - protest_center) * 0.5
	_bark_t -= delta
	if _bark_t <= 0.0:
		_bark_t = randf_range(4.0, 12.0)
		actor.say(s.taunts.pick("protest_chant"), 2.5)
		actor.body.play("slogan")

func start_tail(route: PackedVector3Array) -> void:
	tail_route = route
	path = route
	path_i = 0
	set_state(State.TAIL)

func _tail() -> void:
	var p := _player()
	# every few seconds the courier stops and looks back over his shoulder
	var cycle := fmod(state_t, 9.0)
	if cycle > 7.0:
		actor.stop()
		if p:
			actor.face_target = p.global_position
		fov_cos = 0.6
		sight = 14.0
		if sees_player and p and p.global_position.distance_to(actor.global_position) < 14.0:
			detect = minf(1.0, detect + 0.06)
			actor.visuals.alert_level = detect
			if detect >= 1.0 and on_spot.is_valid():
				var cb := on_spot
				on_spot = Callable()
				actor.say("কে আমার পিছু নিচ্ছে?!", 2.5)
				cb.call()
		return
	actor.face_target = null
	if path_i >= path.size():
		actor.stop()
		if on_arrive.is_valid():
			var cb2 := on_arrive
			on_arrive = Callable()
			cb2.call()
		return
	_follow_path(actor.walk_speed * 1.1)
