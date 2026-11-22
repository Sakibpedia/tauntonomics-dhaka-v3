class_name WalkableBuilding
extends Node3D
## A fully walkable Dhaka walk-up building — real 3D geometry with complete static-body physics.
## Ground + 3 upper floors + accessible roof, a staircase with individual collision treads,
## two flats per floor, hinged doors and windows that open/close with animation, and a lobby.
## The player enters through the front door, climbs the stairs and visits every flat or the roof.

const W := 16.0          # width  (X)
const D := 12.0          # depth  (Z)
const FH := 3.2          # floor height
const FLOORS := 4        # ground + 3 upper
const STAIR_W := 3.0
const STAIR_X := -6.2    # stairwell centre X (west side)
const STEPS_PER := 16    # treads per storey (rise 0.2, run 0.3)

var s: Services
var _phys: StaticBody3D
var _mat: Dictionary = {}
var _doors: Array = []
var _windows: Array = []
var _floor_labels: Array = []

static func mat(key: String, c: Color, rough: float = 0.7) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func setup(services: Services) -> void:
	s = services

func _ready() -> void:
	_mat = {
		"wall": mat("wall", Color("#e8d9c0")),
		"floor": mat("floor", Color("#b9ada0")),
		"stair": mat("stair", Color("#9c9488")),
		"door": mat("door", Color("#6b4a2e"), 0.5),
		"frame": mat("frame", Color("#4a3524")),
		"glass": mat("glass", Color(0.55, 0.7, 0.78, 0.55), 0.15),
		"rail": mat("rail", Color(0.18, 0.2, 0.22), 0.4),
	}
	build()
	add_to_group("walkable_building")

# ---------------------------------------------------------------- construction
func _box(pos: Vector3, size: Vector3, m: Material, collide: bool = true, name: String = "", add_to_self: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.name = name
	if add_to_self:
		add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		_phys.add_child(cs)
	return mi

func build() -> void:
	_phys = StaticBody3D.new()
	_phys.name = "Structure"
	_phys.collision_layer = Actor.LAYER_WORLD
	add_child(_phys)

	var total_h := FLOORS * FH
	# ---- exterior walls, split so a front door and windows remain as openings
	var t := 0.24
	# back wall (solid)
	_box(Vector3(0, total_h * 0.5, D * 0.5), Vector3(W, total_h, t), _mat["wall"], true, "wall_back")
	# side walls
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(sx * W * 0.5, total_h * 0.5, 0), Vector3(t, total_h, D), _mat["wall"], true, "wall_side")
	# front wall in segments around the entrance (x in [-1.2, 1.2])
	for sx: float in [-1.0, 1.0]:
		var seg_w := W * 0.5 - 1.2
		_box(Vector3(sx * (1.2 + seg_w * 0.5), total_h * 0.5, -D * 0.5), Vector3(seg_w, total_h, t), _mat["wall"], true, "wall_front")
	_box(Vector3(0, total_h - 1.2, -D * 0.5), Vector3(2.4, 2.4, t), _mat["wall"], true, "lintel")

	# ---- floor slabs at each level (the roof is the top slab)
	for fl in range(FLOORS + 1):
		var y := fl * FH
		_box(Vector3(0, y - 0.12, 0), Vector3(W, 0.24, D), _mat["floor"], true, "slab_%d" % fl)
		# ceiling beams give the interior some depth
		if fl < FLOORS:
			for bx: float in [-4.0, 0.0, 4.0]:
				_box(Vector3(bx, y - 0.3, 0), Vector3(0.18, 0.24, D - 0.5), _mat["wall"], false, "beam")
	# ---- interior partition: two flats per upper floor
	for fl in range(1, FLOORS + 1):
		var y := fl * FH
		_box(Vector3(2.6, y + FH * 0.5, 0), Vector3(0.18, FH - 0.3, D - 0.6), _mat["wall"], true, "partition_%d" % fl)
		# flat entrance lintel + door
		for sx: float in [-1.0, 1.0]:
			var dx := sx * 5.0
			var dz := -1.0
			_box(Vector3(dx, y + 1.3, dz), Vector3(1.1, 2.6, 0.12), _mat["frame"], false, "door_frame")
			_make_door(Vector3(dx, y + 1.25, dz - 0.02), "ফ্ল্যাট %d%s" % [fl, "ক" if sx < 0 else "খ"])

	# ---- staircase: 16 individual treads per storey, with collision, plus hand rail
	for fl in range(FLOORS):
		var y0 := fl * FH
		for i in range(STEPS_PER):
			var rise := FH / float(STEPS_PER)
			var run := (D - 1.0) / float(STEPS_PER)
			var zz := -D * 0.5 + 0.5 + (i + 0.5) * run
			var yy := y0 + (i + 1) * rise - 0.12
			_box(Vector3(STAIR_X, yy, zz), Vector3(STAIR_W, 0.24, run + 0.02), _mat["stair"], true, "tread_%d_%d" % [fl, i])
		# invisible low-slope ramp collider (rise/run = 3.2/11 ≈ 16°) for smooth stair climbing
		var rc := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		rb.size = Vector3(STAIR_W, 0.2, sqrt((D - 1.0) * (D - 1.0) + FH * FH))
		rc.shape = rb
		rc.position = Vector3(STAIR_X, y0 + FH * 0.5, 0.0)
		rc.rotation.x = atan2(FH, D - 1.0)
		_phys.add_child(rc)
		# hand rail along the stair
		_box(Vector3(STAIR_X - STAIR_W * 0.5, y0 + FH * 0.55, 0), Vector3(0.07, 0.07, D - 1.0), _mat["rail"], false, "rail")

	# ---- front entrance door (ground floor)
	_make_door(Vector3(0, 1.25, -D * 0.5 - 0.03), "বাড়ির প্রবেশদ্বার", true)
	# ---- windows on every exterior wall, every floor
	for fl in range(1, FLOORS + 1):
		var y := fl * FH + 1.6
		for x: float in [-5.0, -2.5, 0.0, 2.5, 5.0]:
			if absf(x - STAIR_X) < 1.6:
				continue
			_make_window(Vector3(x, y, -D * 0.5 - 0.02), false)
		for x: float in [-5.0, 0.0, 5.0]:
			_make_window(Vector3(x, y, D * 0.5 + 0.02), true)
	# ---- roof: parapet, stair exit, water tank
	var rh := FLOORS * FH
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(sx * W * 0.5, rh + 0.45, 0), Vector3(0.25, 0.9, D), _mat["wall"], true, "parapet")
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(0, rh + 0.45, sz * D * 0.5), Vector3(W, 0.9, 0.25), _mat["wall"], true, "parapet")
	_box(Vector3(5.0, rh + 0.7, 3.0), Vector3(2.4, 1.4, 2.4), _mat["wall"], true, "water_tank")
	# roof exit hatch marker — Usable interactable to go back down to the ground floor.
	var roof_us := Usable.new()
	roof_us.prompt = "নামান (শেষ তলায় চলে যান)"
	roof_us.interact_radius = 3.0
	roof_us.on_use = Callable(self, "_on_roof_down")
	var roof_mark := _box(Vector3(STAIR_X, rh + 0.14, D * 0.5 - 1.0), Vector3(STAIR_W, 0.1, 1.4), _mat["rail"], false, "roof_hatch", false)
	roof_mark.name = "RoofAccess"
	roof_us.add_child(roof_mark)
	add_child(roof_us)
	# ---- fire escape ladder on the side — climb up to the roof from outside
	var ladder := Usable.new()
	ladder.prompt = "সিঁড়ি দিয়ে ছাদে ওঠুন"
	ladder.interact_radius = 2.5
	ladder.on_use = Callable(self, "_on_ladder_up")
	var ladder_mark := _box(Vector3(-W * 0.5 - 0.6, rh * 0.5, -D * 0.3), Vector3(0.15, rh, 0.15), _mat["rail"], false, "fire_escape", false)
	ladder_mark.name = "FireEscapeLadder"
	ladder.add_child(ladder_mark)
	add_child(ladder)
	# ---- roof-to-roof connection markers (nearby buildings can link via these)
	var roof_link := Usable.new()
	roof_link.prompt = "পাশের ছাদে পাড়ান (ছাদ–ছাদ সংযোগ)"
	roof_link.interact_radius = 3.0
	roof_link.on_use = Callable(self, "_on_roof_link")
	var link_mark := _box(Vector3(W * 0.5 + 0.6, rh + 0.5, 0), Vector3(0.15, 0.15, 2.0), _mat["rail"], false, "roof_link", false)
	link_mark.name = "RoofLink"
	roof_link.add_child(link_mark)
	add_child(roof_link)
	# Dhaka detailing: dentils under the roof cornice and jali lattice at the entrance verandah
	for i in 26:
		var dx := -W * 0.5 + 0.4 + i * (W - 0.8) / 25.0
		_box(Vector3(dx, rh - 0.45, -D * 0.5 - 0.12), Vector3(0.12, 0.26, 0.16), _mat["wall"], false, "dentil")
	for i in 6:
		var jy := 0.4 + i * 0.32
		_box(Vector3(-2.0, jy, -D * 0.5 - 0.16), Vector3(1.5, 0.06, 0.06), _mat["frame"], false, "jali_h")
	for i in 5:
		var jx := -2.6 + i * 0.3
		_box(Vector3(jx, 1.35, -D * 0.5 - 0.16), Vector3(0.06, 1.7, 0.06), _mat["frame"], false, "jali_v")
	# Warm interior lights so every floor/flat and the stairwell are visible at night.
	for fl in range(FLOORS):
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.86, 0.64)
		lamp.light_energy = 1.1
		lamp.omni_range = 11.0
		lamp.shadow_enabled = false
		lamp.position = Vector3(2.5, fl * FH + 2.4, 0.0)
		add_child(lamp)

func _make_door(pos: Vector3, label: String, entrance: bool = false) -> void:
	var bp := preload("res://scripts/world/BuildingPart.gd")
	var pivot: Node3D = bp.new()
	pivot.name = "Door_%s" % label
	add_child(pivot)
	pivot.global_position = pos
	var leaf := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.05, 2.5, 0.08)
	leaf.mesh = bm
	leaf.material_override = _mat["door"]
	leaf.position = Vector3(0.5, 0, 0)   # hinge at left edge
	pivot.add_child(leaf)
	# knob
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	knob.mesh = sm
	knob.material_override = _mat["rail"]
	knob.position = Vector3(0.9, 0, -0.06)
	leaf.add_child(knob)
	pivot.set_meta("open", false)
	pivot.set_meta("label", label)
	pivot.set_meta("entrance", entrance)
	pivot.add_to_group("building_door")
	pivot.call("setup", self, true)
	_doors.append(pivot)

func _make_window(pos: Vector3, back: bool) -> void:
	var bp := preload("res://scripts/world/BuildingPart.gd")
	var pivot: Node3D = bp.new()
	pivot.name = "Window"
	add_child(pivot)
	pivot.global_position = pos
	pivot.rotation.y = PI if back else 0.0
	var panel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 1.3, 0.06)
	panel.mesh = bm
	panel.material_override = _mat["glass"]
	panel.position = Vector3(0, -0.65, 0)  # hinge at top
	pivot.add_child(panel)
	# frame
	var fr := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(1.2, 1.4, 0.05)
	fr.mesh = fb
	fr.material_override = _mat["frame"]
	fr.position = Vector3(0, 0, 0.03)
	pivot.add_child(fr)
	pivot.set_meta("open", false)
	pivot.add_to_group("building_window")
	pivot.call("setup", self, false)
	_windows.append(pivot)

# ---------------------------------------------------------------- interaction
func door_prompt() -> String:
	return "দরজা খুলুন / বন্ধ করুন"

func toggle_door(d: Node3D) -> void:
	if not is_instance_valid(d):
		return
	var opening := not bool(d.get_meta("open"))
	d.set_meta("open", opening)
	var target := deg_to_rad(-95.0) if opening else 0.0
	var tw := create_tween()
	tw.tween_property(d, "rotation:y", target, 0.55).set_ease(Tween.EASE_OUT)
	if s and s.sfx:
		s.sfx.play("door", -8.0)

func toggle_window(w: Node3D) -> void:
	if not is_instance_valid(w):
		return
	var opening := not bool(w.get_meta("open"))
	w.set_meta("open", opening)
	var target := deg_to_rad(-70.0) if opening else 0.0
	var tw := create_tween()
	tw.tween_property(w, "rotation:x", target, 0.45).set_ease(Tween.EASE_OUT)

func nearest_interactable(from: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var bd := radius
	for d in _doors:
		if d is Node3D and d.global_position.distance_to(from) < bd:
			bd = d.global_position.distance_to(from)
			best = d
	for w in _windows:
		if w is Node3D and w.global_position.distance_to(from) < bd:
			bd = w.global_position.distance_to(from)
			best = w
	return best

## Interact prompt shown when looking at the roof hatch.
func interact_prompt() -> String:
	return "নামান (শেষ তলায় চলে যান)"

## Called when the player uses the roof hatch — teleport down to the ground floor near the entrance.
func _on_roof_down(from: Node) -> void:
	var p := from as Player
	if p == null or not is_instance_valid(p):
		return
	# Move player to ground floor near the front entrance.
	p.global_position = Vector3(0.0, 0.5, -D * 0.5 - 3.0)
	p.velocity = Vector3.ZERO
	p.on_ladder = null
	if s and s.sfx:
		s.sfx.play("door", -8.0)

## Called when the player uses the fire escape ladder — teleport up to the roof.
func _on_ladder_up(from: Node) -> void:
	var p := from as Player
	if p == null or not is_instance_valid(p):
		return
	var rh := FLOORS * FH
	p.global_position = Vector3(STAIR_X, rh + 0.5, D * 0.5 - 1.0)
	p.velocity = Vector3.ZERO
	p.on_ladder = null
	if s and s.sfx:
		s.sfx.play("door", -8.0)

## Called when the player uses the roof-to-roof link — teleport to a nearby building roof.
func _on_roof_link(from: Node) -> void:
	var p := from as Player
	if p == null or not is_instance_valid(p):
		return
	# Find another WalkableBuilding nearby and move player to its roof.
	var rh := FLOORS * FH
	for b in get_tree().get_nodes_in_group("walkable_building"):
		var wb := b as WalkableBuilding
		if wb == null or wb == self:
			continue
		var d := wb.global_position.distance_to(global_position)
		if d < 40.0 and d > 8.0:
			p.global_position = wb.global_position + Vector3(0.0, rh + 0.5, 0.0)
			p.velocity = Vector3.ZERO
			p.on_ladder = null
			if s and s.sfx:
				s.sfx.play("door", -8.0)
			return
	s.toast("কাছে আর কোনো ছাদ নেই।", "info")
