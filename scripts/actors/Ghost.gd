class_name Ghost
extends Node3D
## প্রশ্নভূত: a question-ghost. Born from a Syndicate member who died without hearing an answer to
## his last question, or from the dark itself (the city's unanswered questions). Floats, passes
## through walls, taunts the player with its question, drains sanity and health, throws glowing
## question papers. It cannot enter shelter (under a roof), lamp light or a candle circle. Sunlight
## burns it back to the grave until the next night. Answer its question (E) and it is set free.

var s: Services
var record: Dictionary = {}
var question: Dictionary = {}
var body: Humanoid
var label: Label3D
var speed := 2.2
var power := 1.0
var _taunt_t := 3.0
var _throw_t := 6.0
var _hiss_t := 0.0
var burning := false
var interact_radius := 3.2
var banished := false
var _light: OmniLight3D

func setup(services: Services, rec: Dictionary, q: Dictionary) -> void:
	s = services
	record = rec
	question = q
	add_to_group("ghosts")
	add_to_group("interactable")
	var look: Dictionary = (rec.get("look", {}) as Dictionary).duplicate()
	if look.is_empty():
		look = {"sex": "m" if randf() < 0.6 else "f", "outfit": ["panjabi", "shirt_pants", "lungi_vest", "salwar"][randi() % 4], "hair": "short", "age": randf()}
		if str(look["sex"]) == "f":
			look["hair"] = "long"
			look["outfit"] = "salwar"
	look["ghost"] = true
	body = Humanoid.new()
	add_child(body)
	body.setup(look)
	body.set_sustain("float", true)
	body.expression = "sad"
	label = Label3D.new()
	label.font = BnText.font(true)
	label.font_size = 40
	label.pixel_size = 0.0021
	label.visibility_range_begin = 3.0
	label.outline_size = 12
	label.modulate = Color(0.75, 0.95, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = 1100
	label.position = Vector3(0, 2.5, 0)
	label.no_depth_test = true
	label.text = "%s\n“%s”" % [str(rec.get("name", "প্রশ্নভূত")), str(q.get("q", "?"))]
	add_child(label)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 0.8, 1.0)
	_light.light_energy = 1.2
	_light.omni_range = 4.0
	_light.position = Vector3(0, 1.3, 0)
	add_child(_light)
	s.sfx.play_at("ghost", global_position, -6.0)

func can_interact(_p: Node) -> bool:
	return not banished and not burning

func interact_prompt() -> String:
	return "উত্তর দিন: প্রশ্নভূতকে মুক্তি দিন"

func interact(_p: Node) -> void:
	if s.ui:
		s.ui.call("open_ghost_exam", self)

## Called by the exam UI.
func answered(correct: bool) -> void:
	if correct:
		banished = true
		s.save.add("ghosts_banished", 1)
		s.save.add("money", 150)
		if s.player:
			s.player.call("heal", 10.0, 25.0)
		if record.has("id") and str(record.get("id", "")).begins_with("g_"):
			s.save.remove_ghost(str(record["id"]))
		s.say(str(record.get("name", "প্রশ্নভূত")), s.taunts.pick("ghost_banished"), 4.0)
		s.fx.ghost_embers(global_position + Vector3(0, 1.2, 0))
		s.sfx.play("chime", -2.0)
		s.bus.ghost_banished.emit(self)
		var tw := create_tween()
		tw.tween_property(self, "global_position", global_position + Vector3(0, 6, 0), 2.5).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_method(func(a: float) -> void: body.set_alpha(a), 1.0, 0.0, 2.5)
		tw.tween_callback(queue_free)
	else:
		power += 0.4
		speed += 0.4
		s.say(str(record.get("name", "প্রশ্নভূত")), s.taunts.pick("ghost_wrong"), 3.5)
		if s.player:
			s.player.call("drain_sanity", 18.0)
		s.sfx.play("roar", -4.0)

func burn() -> void:
	if burning or banished:
		return
	burning = true
	s.fx.ghost_embers(global_position + Vector3(0, 1.2, 0), true)
	s.sfx.play_at("burn", global_position, -2.0)
	var tw := create_tween()
	tw.tween_method(func(a: float) -> void: body.set_alpha(a), 1.0, 0.0, 1.5)
	tw.tween_callback(queue_free)

func _blocked(pos: Vector3) -> bool:
	if s.world and s.world.has_method("is_lit_safe") and bool(s.world.call("is_lit_safe", pos)):
		return true
	return false

func _process(delta: float) -> void:
	if banished or burning:
		return
	var p := s.player as Player
	if p == null:
		return
	var to := p.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var protected := p.protected_from_ghosts()
	var want := global_position
	if protected:
		# hover at the edge of the light, hissing the question
		if d < 7.0:
			want = global_position - to.normalized() * 2.0
		_hiss_t -= delta
		if _hiss_t <= 0.0 and d < 14.0:
			_hiss_t = 9.0
			s.say(str(record.get("name", "প্রশ্নভূত")), s.taunts.pick("ghost", {"q": str(question.get("q", ""))}), 4.0)
	elif d > 2.4:
		want = p.global_position - to.normalized() * 2.2
	var step := (want - global_position)
	step.y = 0.0
	if step.length() > 0.05:
		var next := global_position + step.normalized() * minf(step.length(), speed * delta)
		if not _blocked(next):
			global_position = next
	global_position.y = lerpf(global_position.y, p.global_position.y + 0.25, delta * 2.0)
	if d > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), delta * 4.0)
	body.look_target = p.global_position + Vector3(0, 1.6, 0)
	body.talking = d < 6.0 and fmod(Time.get_ticks_msec() / 1000.0, 5.0) < 1.5
	body.animate(delta, Vector3.ZERO, false)
	_light.light_energy = 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.3
	if protected:
		return
	if d < 3.0:
		p.drain_sanity(delta * 6.0 * power)
		if fmod(Time.get_ticks_msec() / 1000.0, 2.0) < delta:
			p.call("receive_hit", 4.0 * power, global_position, self, "ghost")
	_taunt_t -= delta
	if _taunt_t <= 0.0 and d < 18.0:
		_taunt_t = randf_range(6.0, 10.0)
		s.say(str(record.get("name", "প্রশ্নভূত")), s.taunts.pick("ghost", {"q": str(question.get("q", ""))}), 4.5)
		body.play("cast")
	_throw_t -= delta
	if _throw_t <= 0.0 and d < 16.0 and d > 3.5:
		_throw_t = randf_range(5.0, 8.0) / power
		var pr := Projectile.new()
		get_parent().add_child(pr)
		pr.launch(s, global_position + Vector3(0, 1.6, 0), p.global_position + Vector3(0, 1.3, 0), self, "paper", 6.0 * power)
