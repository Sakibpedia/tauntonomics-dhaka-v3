class_name Minimap
extends Control
## GTA-style radar: rotates with the camera, draws block footprints, the objective (with an edge
## arrow when off the map), Syndicate hunters, ghosts, story characters, lamps at night, and the
## player arrow. `big` mode is the phone's full map (north-up).

var s: Services
var big := false
var meters := 150.0        # radius shown
var _frame: Texture2D
var _t := 0.0

func setup(services: Services, is_big: bool = false) -> void:
	s = services
	big = is_big
	meters = 420.0 if big else 150.0
	_frame = UiKit.tex("minimap_frame")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	# A radar at 12 Hz is indistinguishable from per-frame drawing but far cheaper on the CPU.
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0 / (8.0 if s != null and s.quality <= 0 else 12.0)
	queue_redraw()

func _to_map(world: Vector3, origin: Vector3, yaw: float, radius_px: float) -> Vector2:
	var rel := Vector2(world.x - origin.x, world.z - origin.z)
	if not big:
		rel = rel.rotated(yaw)
	return size * 0.5 + rel * (radius_px / meters)

func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_map()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if ms > 6.0 and OS.get_environment("DHAKA_LOG_SLOW") != "":
		print("SLOW minimap %.1f ms" % ms)

func _draw_map() -> void:
	if s == null or s.player == null or not is_instance_valid(s.player) or s.world == null:
		return
	var w := s.world as ProceduralDhaka
	var pl := s.player as Node3D
	var origin := pl.global_position
	var yaw := 0.0
	if s.camera and not big:
		yaw = (s.camera as PlayerCamera).yaw
	var rpx := minf(size.x, size.y) * 0.5 - 6.0
	var c := size * 0.5
	if big:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.12, 0.95))
	else:
		draw_circle(c, rpx, Color(0.08, 0.1, 0.12, 0.88))
	var circle := PackedVector2Array()
	var csegs := 24 if not big else 40
	for i in csegs:
		circle.append(c + Vector2(rpx, 0).rotated(TAU * i / csegs))
	var night := s.clock.is_night() if s.clock else false
	var b := w.block_of(origin)
	var span := int(ceil(meters / ProceduralDhaka.P)) + 1
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var k := Vector2i(b.x + dx, b.y + dz)
			if not w.layouts.has(k):
				continue
			var f := w.footprint(k.x, k.y)
			var kind := str(w.specials.get(k, ""))
			var col := Color(0.55, 0.53, 0.5, 0.9)
			if kind == "square" or kind == "market":
				col = Color(0.45, 0.5, 0.38, 0.9)
			elif kind == "den":
				col = Color(0.5, 0.35, 0.3, 0.9)
			var pts := PackedVector2Array([_to_map(Vector3(f.position.x, 0, f.position.y), origin, yaw, rpx), _to_map(Vector3(f.end.x, 0, f.position.y), origin, yaw, rpx),
				_to_map(Vector3(f.end.x, 0, f.end.y), origin, yaw, rpx), _to_map(Vector3(f.position.x, 0, f.end.y), origin, yaw, rpx)])
			if big:
				draw_colored_polygon(pts, col)
			else:
				# Clipping is the expensive part, so only edge blocks go through Geometry2D.
				var any_in := false
				var all_in := true
				for p in pts:
					if p.distance_squared_to(c) < rpx * rpx:
						any_in = true
					else:
						all_in = false
				if not any_in:
					continue
				if all_in:
					draw_colored_polygon(pts, col)
				else:
					for clip in Geometry2D.intersect_polygons(pts, circle):
						draw_colored_polygon(clip, col)
	if w.river_z < 1e8:
		var rp := PackedVector2Array([_to_map(Vector3(-2000, 0, w.river_z), origin, yaw, rpx), _to_map(Vector3(2000, 0, w.river_z), origin, yaw, rpx),
			_to_map(Vector3(2000, 0, w.river_z + 400), origin, yaw, rpx), _to_map(Vector3(-2000, 0, w.river_z + 400), origin, yaw, rpx)])
		if big:
			draw_colored_polygon(rp, Color(0.2, 0.35, 0.5, 0.9))
		else:
			for clip2 in Geometry2D.intersect_polygons(rp, circle):
				draw_colored_polygon(clip2, Color(0.2, 0.35, 0.5, 0.9))
	if night:
		for l in w.lamps:
			var la: Array = l
			if bool(la[1]):
				var lw: Vector3 = la[0]
				# Cheap world-space cull before doing any mapping.
				if absf(lw.x - origin.x) > meters or absf(lw.z - origin.z) > meters:
					continue
				var lp := _to_map(lw, origin, yaw, rpx)
				if lp.distance_to(c) < rpx:
					draw_circle(lp, 2.5, Color(1.0, 0.75, 0.3, 0.8))
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a == null or a.dead:
			continue
		var ap := _to_map(a.global_position, origin, yaw, rpx)
		if ap.distance_to(c) > rpx and not big:
			continue
		if a.faction == "syndicate" and (a.ai.aggro or a.hostile and a.ai.state == ActorAI.State.FIGHT):
			draw_circle(ap, 5.0, Color(0.95, 0.2, 0.2))
		elif a.story_char:
			draw_circle(ap, 5.0, Color(0.3, 0.9, 0.45))
		elif a.mission_tag != "":
			draw_circle(ap, 4.0, Color(1.0, 0.8, 0.3))
	for g in get_tree().get_nodes_in_group("ghosts"):
		var gp := _to_map((g as Node3D).global_position, origin, yaw, rpx)
		if gp.distance_to(c) < rpx or big:
			draw_circle(gp, 5.0, Color(0.5, 0.85, 1.0))
	# objective
	if s.missions and s.missions.has_method("marker_pos"):
		var mp: Variant = s.missions.call("marker_pos")
		if mp != null:
			var op := _to_map(mp as Vector3, origin, yaw, rpx)
			var d := op - c
			if d.length() > rpx - 8.0 and not big:
				op = c + d.normalized() * (rpx - 8.0)
				var ang := d.angle()
				var tri := PackedVector2Array([op + Vector2(10, 0).rotated(ang), op + Vector2(-6, 7).rotated(ang), op + Vector2(-6, -7).rotated(ang)])
				draw_colored_polygon(tri, UiKit.SAFFRON)
			else:
				draw_circle(op, 8.0, Color(0, 0, 0, 0.6))
				draw_circle(op, 6.0, UiKit.SAFFRON)
	# player arrow
	var pyaw := pl.global_rotation.y
	var rel_ang := (-pyaw + yaw) if not big else -pyaw
	var arrow := PackedVector2Array([c + Vector2(0, -11).rotated(rel_ang), c + Vector2(7, 8).rotated(rel_ang), c + Vector2(0, 4).rotated(rel_ang), c + Vector2(-7, 8).rotated(rel_ang)])
	if big:
		arrow = PackedVector2Array([_to_map(origin, origin, 0, rpx) + Vector2(0, -11).rotated(rel_ang), _to_map(origin, origin, 0, rpx) + Vector2(7, 8).rotated(rel_ang), _to_map(origin, origin, 0, rpx) + Vector2(0, 4).rotated(rel_ang), _to_map(origin, origin, 0, rpx) + Vector2(-7, 8).rotated(rel_ang)])
	draw_colored_polygon(arrow, Color(1, 1, 1))
	if not big:
		draw_arc(c, rpx, 0, TAU, 64, Color(0.95, 0.85, 0.6, 0.9), 3.0)
		if s.quality > 0:
			draw_string(BnText.font(true), c + Vector2(-8, -rpx + 18).rotated(yaw), "উ", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.85, 0.5))

func _inside_any(pts: PackedVector2Array, c: Vector2, r: float) -> bool:
	if big:
		return true
	for p in pts:
		if p.distance_to(c) < r + 40.0:
			return true
	return false
