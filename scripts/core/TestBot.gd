class_name TestBot
extends Node
## Automated play-through for QA (run with DHAKA_BOT=<first level>[,<last level>]). Advances
## cutscenes, answers exams correctly, chooses best debate cards and "arrest" fates, and drives
## every mission step type by teleporting and interacting. Prints progress so a headless run shows
## exactly where something breaks.

var s: Services
var main: Main
var _t := 0.0
var last := ""
var last_level := 20
var _stuck := 0.0

func setup(services: Services, m: Main, until: int) -> void:
	s = services
	main = m
	last_level = until
	process_mode = Node.PROCESS_MODE_ALWAYS

func _log(t: String) -> void:
	if t != last:
		last = t
		print("[BOT] ", t)

func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	var ui := s.ui as UIRoot
	if ui == null:
		return
	if ui.letterbox.visible:
		ui._cut_next()
		return
	if ui.exam.visible:
		var ex := ui.exam
		if ex._done:
			ex._close()
		elif not ex._answered:
			var q: Dictionary = ex.questions[ex.idx]
			ex._answer(int(q.get("a", 0)))
		else:
			ex._next()
		return
	if ui.debate.visible:
		var d := ui.debate
		if d.ci < d.claims.size() and not d._wait:
			var c: Dictionary = d.claims[d.ci]
			var best := str(c.get("best", "empathy"))
			if best == "leak" and int(s.save.g("intel", 0)) <= 0:
				s.save.add("intel", 1)
			d._play(best)
		elif d.ci >= d.claims.size():
			for b in d.grid.get_children():
				if b is Button:
					(b as Button).pressed.emit()
		return
	if ui.phone.visible:
		ui.phone.close()
		return
	if ui.convo.visible:
		var opts := ui.convo.opts.get_children()
		if OS.get_environment("BOT_DEBUG") != "":
			print("[BOT] convo opts=", opts.size(), " line=", ui.convo.line_l.text.substr(0, 60))
		var pressed := false
		for o in opts:
			var b := o as Button
			if b and not b.is_queued_for_deletion() and (b.text.find("চালিয়ে যান") != -1 or b.text.find("পরীক্ষা দিন:") != -1 or (b.text.find("► মোমবাতি কিনুন") != -1 and _step_type() == "buy" and _step_live()) or ui.convo._open and not ui.convo.visible):
				b.pressed.emit()
				pressed = true
				break
		if not pressed:
			# patient advice: pick the first (good) answer
			for o2 in opts:
				var b2 := o2 as Button
				if b2 and not b2.is_queued_for_deletion() and md_advising():
					b2.pressed.emit()
					pressed = true
					break
		if not pressed:
			ui.convo.close()
		return
	var md := s.missions as MissionDirector
	var p := s.player as Player
	if md == null or p == null or not is_instance_valid(p):
		return
	if md._done_level:
		_log("level %d done" % main.level_n)
		if main.level_n >= last_level:
			print("[BOT] FINISHED through level ", last_level, " answered=", s.save.g("answered"), " kills=", s.save.g("kills"), " arrests=", s.save.g("arrests"))
			get_tree().quit()
		return
	if md.step.is_empty() or not md._step_live:
		return
	var ty := str(md.step.get("type", ""))
	_log("L%d M%d S%d %s: %s" % [main.level_n, md.mi + 1, md.si + 1, ty, str(md.step.get("text", ""))])
	if p.dead:
		return
	p.hp = 100.0
	p.sanity = 100.0
	var mp: Variant = md.marker_pos()
	match ty:
		"drive":
			var v := md._vehicle as Vehicle
			if v and is_instance_valid(v):
				if not v.driven:
					_tp(p, v.global_position + Vector3(2, 0, 0))
					v.interact(p)
				else:
					var dest := md._poi(str(md.step.get("poi", "safehouse")))
					(s.world as ProceduralDhaka).ensure_built(dest, 1)
					v.global_position = dest + Vector3(0, 0.5, 4.0)
		"goto", "escape_roof", "sneak":
			if mp != null:
				_tp(p, mp as Vector3)
		"talk", "exam", "deliver", "buy":
			var a := md._char_if(str(md.step.get("npc", "")))
			if a:
				_tp(p, a.global_position + Vector3(1.2, 0, 0))
				if ty == "buy":
					s.save.add("money", 200)
				if OS.get_environment("BOT_DEBUG") != "":
					print("[BOT] interact ", a.id, " can=", a.can_interact(p), " paused=", get_tree().paused)
				a.interact(p)
		"collect":
			if mp != null:
				_tp(p, mp as Vector3)
		"posters":
			var near: Variant = md._nearest_poster()
			if near != null:
				for n in get_tree().get_nodes_in_group("posters"):
					var po := n as Poster
					if po and not po.done and po.global_position.distance_to(near as Vector3) < 0.1:
						_tp(p, po.global_position + po.global_transform.basis.z * 1.2)
						po.interact(p)
						break
		"defeat", "survive":
			for n in md.spawned:
				if n is Actor and is_instance_valid(n) and not (n as Actor).health.is_down:
					(n as Actor).health.damage(500.0)
			md.timer -= 5.0
		"eliminate":
			var tg := md.target
			if tg and is_instance_valid(tg):
				_tp(p, tg.global_position + Vector3(1.5, 0, 0))
				if not tg.health.is_down:
					tg.health.armor = 0.0
					tg.health.damage(1000.0)
				elif not tg.arrested and not tg.dead:
					ui.convo.open_fate(tg)
					var opts2 := ui.convo.opts.get_children()
					# alternate arrest / finish to exercise both paths
					var pick := 0 if main.level_n % 2 == 0 else 1
					if opts2.size() > pick:
						(opts2[pick] as Button).pressed.emit()
		"debate":
			var dd := s.story.debate(str(md.step.get("debate", "")))
			var lead := md._char_if(str(dd.get("leader", "")))
			if lead:
				_tp(p, lead.global_position + Vector3(1.0, 0, 0))
		"tail":
			if md.tail_actor and is_instance_valid(md.tail_actor):
				md.tail_actor.ai.on_spot = Callable()
				_tp(p, md.tail_actor.global_position + Vector3(0, 0, 14.0))
		"survive_night":
			var gs := get_tree().get_nodes_in_group("ghosts")
			if gs.is_empty():
				s.ghosts.call("ensure_minimum", 1)
				s.clock.hour += 0.25
			else:
				var g := gs[0] as Ghost
				if g and not g.banished:
					_tp(p, g.global_position + Vector3(1.5, 0, 0))
					g.interact(p)
		"advise":
			for n in md.spawned:
				if n is Actor and is_instance_valid(n) and not md._advised.has((n as Actor).id):
					_tp(p, (n as Actor).global_position + Vector3(1.0, 0, 0))
					(n as Actor).interact(p)
					break
		"swap":
			for n in md.spawned:
				if n is Usable and is_instance_valid(n) and (n as Usable).enabled:
					_tp(p, (n as Usable).global_position)
					(n as Usable)._fire(p)
					break
		"boss":
			var used := false
			for n in md.spawned:
				if n is Usable and is_instance_valid(n) and (n as Usable).enabled:
					_tp(p, (n as Usable).global_position + Vector3(1, 0, 0))
					(n as Usable)._fire(p)
					used = true
					break
			if not used and md._boss and is_instance_valid(md._boss):
				if not md._boss.health.is_down:
					md._boss.health.damage(5000.0)
				else:
					ui.convo.open_fate(md._boss)
					var o3 := ui.convo.opts.get_children()
					if o3.size() > 0:
						(o3[0] as Button).pressed.emit()

func _step_type() -> String:
	var md := s.missions as MissionDirector
	return str(md.step.get("type", "")) if md else ""

func _step_live() -> bool:
	var md := s.missions as MissionDirector
	return md != null and md._step_live

func md_advising() -> bool:
	var md := s.missions as MissionDirector
	return md != null and str(md.step.get("type", "")) == "advise"

func _tp(p: Player, at: Vector3) -> void:
	(s.world as ProceduralDhaka).ensure_built(at, 1)
	p.global_position = at + Vector3(0, 0.4, 0)
	p.velocity = Vector3.ZERO
