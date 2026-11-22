class_name GhostDirector
extends Node
## The night rule, borrowed from Minecraft's zombies. After dusk question-ghosts rise in dark places
## away from lamps: first the ghosts of those you finished without answering their last question
## (saved, so they come back every night until answered), then the city's nameless unanswered
## questions. Shelter, lamp light and candles keep them back. At dawn the sun burns them.

var s: Services
var _t := 5.0
var _spawned_records: Dictionary = {}
var _was_night := false

func setup(services: Services) -> void:
	s = services

func _process(delta: float) -> void:
	var night := s.clock.is_night()
	if _was_night and not night:
		for g in get_tree().get_nodes_in_group("ghosts"):
			if not bool(g.get("banished")):
				g.call("burn")
		_spawned_records.clear()
	_was_night = night
	if not night or s.player == null or not is_instance_valid(s.player):
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = randf_range(10.0, 18.0)
	var p := s.player as Player
	var count := get_tree().get_nodes_in_group("ghosts").size()
	var lvl := int(s.save.g("level", 1))
	var cap := 2 + lvl / 5
	if count >= cap:
		return
	# recorded ghosts first
	for r in s.save.ghosts():
		var rec: Dictionary = r
		var gid := str(rec.get("id", ""))
		if _spawned_records.has(gid):
			continue
		_spawned_records[gid] = true
		_spawn(rec, s.qdb.get_by_id(str(rec.get("q", ""))), _dark_spot(p.global_position))
		return
	if not p.protected_from_ghosts() or randf() < 0.3:
		spawn_random_near(p.global_position, false)

func ensure_minimum(n: int) -> void:
	var have := get_tree().get_nodes_in_group("ghosts").size()
	for k in maxi(0, n - have):
		spawn_random_near((s.player as Node3D).global_position, false)

func spawn_random_near(at: Vector3, close: bool) -> void:
	var names := ["অনুত্তীর্ণ পরীক্ষার্থীর ভূত", "বয়সসীমা পেরোনো চাকরিপ্রার্থী", "ফাঁস হওয়া প্রশ্নের ভূত", "অপঠিত গাইড বইয়ের আত্মা", "ভাইভায় আটকে থাকা আত্মা", "ভুয়া সনদের ছায়া"]
	var rec := {"id": "r_%d" % randi(), "name": names[randi() % names.size()], "look": {}}
	var spot := at + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)) if close else _dark_spot(at)
	_spawn(rec, s.qdb.draw(["bcs", "job", "bar"], 2), spot)

func _dark_spot(near: Vector3) -> Vector3:
	var w := s.world as ProceduralDhaka
	var best := near + Vector3(20, 0, 0)
	var best_l := 2.0
	for k in 10:
		var ang := randf() * TAU
		var q := near + Vector3(cos(ang), 0, sin(ang)) * randf_range(16.0, 30.0)
		var l := w.light_level(q)
		if l < best_l:
			best_l = l
			best = q
	return best

func _spawn(rec: Dictionary, q: Dictionary, at: Vector3) -> void:
	if q.is_empty():
		q = s.qdb.draw(["bcs"], 2)
	var g := Ghost.new()
	s.world.add_child(g)
	g.global_position = at + Vector3(0, 0.3, 0)
	g.setup(s, rec, q)
	s.bus.ghost_spawned.emit(g)
	s.toast("একটি প্রশ্নভূত জেগেছে: %s" % str(rec.get("name", "")), "danger")
