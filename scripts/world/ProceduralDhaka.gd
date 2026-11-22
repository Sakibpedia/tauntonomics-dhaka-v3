class_name ProceduralDhaka
extends Node3D
const Districts = preload("res://scripts/world/DhakaDistricts.gd")
## The city, generated from the photo survey of Sontek and Kajla (Jatrabari) and tuned per district.
##
## Layout   A grid of 56 m blocks. Every third street is a main road (14 m), the rest are lanes.
##          Each block is cut into street-facing lots of 7–13 m with zero gaps between them, plus
##          interior buildings or a lane. Layouts for the whole map are computed up front (cheap);
##          detailed geometry streams in around the player, one block per frame, and distant blocks
##          are drawn as a skyline of instanced boxes.
## Facades  Pastel cement plaster (vertex-tinted) or weathered brick; per bay a window with an
##          aluminium frame, a steel box grill painted black, green or white and a concrete chajja
##          sunshade; balconies with railings and drying clothes; AC units; ground-floor shops with
##          rolling shutters, warm interiors and Bengali signboards; steel gates.
## Roofs    Parapets, the stair tower with its green tin canopy, black water tanks on stands, dish
##          antennas. Each building's gate has stairs to the roof (E) and back down. Ladders join
##          roofs of different heights, so you can run whole blocks over the rooftops.
## Streets  Asphalt, raised paver footpaths, concrete poles with tangled sagging wires, sodium
##          street lamps (some broken, which makes dark pockets at night), trees, parked rickshaws,
##          brick piles you can throw, posters on every wall, cross-street banners.
## Districts residential, commercial, old_dhaka (brick), riverside (Buriganga ghats), market,
##          plaza, commercial_hi, cbd, hospital, slum (tin), industrial, posh, government, campus,
##          newtown (half-built frames), tower (the nine-storey Sarbangin Bhaban with real floors).
## It also answers the questions other systems ask: POIs, street paths (A*), sidewalk points,
## doors, roof points, light level and ghost-safe light.

const P := 56.0
const STOREY := 3.0
const GROUND := 3.4
const BUILD_R := 2
const FREE_R := 3

const PASTELS: Array[Color] = [Color("#f1d6cf"), Color("#efe3c4"), Color("#d8e6dc"), Color("#d6e2ee"), Color("#f2efe6"),
	Color("#e8cfa8"), Color("#d9c9e3"), Color("#f0dcc0"), Color("#cfd9c6"), Color("#e6e1d6"), Color("#f3c9b5"), Color("#c9dde6"),
	Color("#f6c9a0"), Color("#bcd8c0"), Color("#e5c4d8"), Color("#c7d6e8"), Color("#efe0a8"), Color("#dcc6b0")]
const SHOP_NAMES: Array[String] = ["মায়ের দোয়া স্টোর", "বিসমিল্লাহ হোটেল", "ঢাকা ফটোকপি", "সততা মেডিকেল হল", "নিউ বাবুল টেলিকম",
	"মডেল টেস্ট কোচিং", "সাত দিনে ক্যাডার কোচিং", "পুষ্টি ডেস্ক (অনুমোদনহীন)", "আল-মদিনা ক্লথ স্টোর", "রহমান হার্ডওয়্যার",
	"জননী ফার্মেসি", "নীলক্ষেত বুক কর্নার", "গাইড বই ঘর", "ভাই ভাই ভ্যারাইটিজ", "স্বপ্ন ফাস্ট ফুড", "চা-চক্র", "ইলেকট্রো বাজার",
	"মডার্ন টেইলার্স", "জিরাপানি ডায়েট সেন্টার", "চাকরির খবর পত্রিকা", "শাহজালাল সিরামিক", "কম্পিউটার ট্রেনিং সেন্টার",
	"নিউ মার্কেট বস্ত্রালয়", "সোনালী ব্যাংক এটিএম", "মোবাইল সার্ভিসিং", "হাজী বিরিয়ানি", "সিটি ডায়াগনস্টিক"]
const BANNERS: Array[String] = ["প্রশ্নফাঁস বন্ধ করো!", "বিসিএস প্রস্তুতি: নিজের মেধায়", "ভুয়া পদবি ব্যবহার দণ্ডনীয় অপরাধ",
	"সাত দিনে ক্যাডার! (শর্ত প্রযোজ্য)", "পদবি চাই! (অধিভুক্ত)", "রাতের রাস্তায় মোমবাতি রাখুন", "চাকরি মেলা: পদ শূন্য নেই"]

var s: Services
var level: Dictionary = {}
var style := "residential"
var seed_base := 1000
var R := 7
var st: Dictionary = {}
var layouts: Dictionary = {}       # Vector2i -> Array[Dictionary] buildings
var specials: Dictionary = {}      # Vector2i -> String
var pois: Dictionary = {}          # name -> Vector3
var blocks: Dictionary = {}        # Vector2i -> Node3D (detailed)
var lamps: Array = []              # [Vector3, working] of built blocks
var _lamp_by_block: Dictionary = {}
var astar := AStar3D.new()
var river_z := 1e9
var _queue: Array[Vector2i] = []
var _stream_t := 0.0
var _skyline: MultiMeshInstance3D
var _sky_index: Dictionary = {}    # Vector2i -> Array[int] instance ids
var _mats: Dictionary = {}
var _units: Dictionary = {}
var _night := 0.0
var lightpool: Array[OmniLight3D] = []
var tower_info: Dictionary = {}
var safehouse_room := Rect2()
var build_r := BUILD_R
var free_r := FREE_R
var _low := false
var _shop_names: Array[String] = []
var _district := ""

# ============================================================================ styles
func _style(name: String) -> Dictionary:
	var d := {"floors": Vector2i(4, 7), "shop": 0.35, "main_shop": 0.85, "brick": 0.08, "tin": 0.0, "glass": 0.0, "lane": 7.0,
		"main": 14.0, "trees": 0.05, "unfinished": 0.04, "balcony": 0.3, "posters": 4, "stalls": 0.0, "open": 0.0, "lot": Vector2(7.5, 12.5)}
	match name:
		"commercial": d.merge({"floors": Vector2i(4, 8), "shop": 0.9, "balcony": 0.15}, true)
		"old_dhaka": d.merge({"floors": Vector2i(2, 5), "brick": 0.7, "lane": 5.0, "main": 10.0, "balcony": 0.4, "lot": Vector2(5.5, 9.0)}, true)
		"riverside": d.merge({"floors": Vector2i(2, 4), "brick": 0.4, "shop": 0.5, "lot": Vector2(9.0, 16.0)}, true)
		"market": d.merge({"floors": Vector2i(2, 5), "shop": 0.95, "stalls": 0.8}, true)
		"plaza": d.merge({"floors": Vector2i(4, 9), "shop": 0.7, "trees": 0.2}, true)
		"commercial_hi": d.merge({"floors": Vector2i(6, 14), "shop": 0.95, "glass": 0.25, "balcony": 0.05}, true)
		"cbd": d.merge({"floors": Vector2i(8, 18), "shop": 0.6, "glass": 0.6, "balcony": 0.0, "lot": Vector2(12.0, 20.0)}, true)
		"hospital": d.merge({"floors": Vector2i(4, 8), "shop": 0.6}, true)
		"slum": d.merge({"floors": Vector2i(1, 2), "tin": 0.85, "lane": 4.0, "main": 9.0, "shop": 0.3, "lot": Vector2(3.5, 6.0), "balcony": 0.0, "unfinished": 0.0}, true)
		"industrial": d.merge({"floors": Vector2i(1, 3), "brick": 0.6, "lot": Vector2(14.0, 24.0), "shop": 0.1, "balcony": 0.0}, true)
		"posh": d.merge({"floors": Vector2i(5, 11), "glass": 0.45, "trees": 0.4, "shop": 0.2, "lot": Vector2(12.0, 18.0)}, true)
		"government": d.merge({"floors": Vector2i(3, 6), "brick": 0.3, "trees": 0.5, "shop": 0.05, "lot": Vector2(14.0, 22.0), "balcony": 0.1}, true)
		"campus": d.merge({"floors": Vector2i(2, 5), "brick": 0.35, "trees": 0.6, "shop": 0.1, "open": 0.25, "lot": Vector2(14.0, 22.0)}, true)
		"newtown": d.merge({"floors": Vector2i(3, 10), "unfinished": 0.55, "open": 0.3, "shop": 0.05, "lot": Vector2(12.0, 20.0)}, true)
		# --- Authentic southern-Dhaka districts (real urban planning / architecture) ---
		"jurain", "flooded", "waterlogged":
			# East Jurain: dense unplanned housing on low-lying floodplain; narrow raised lanes,
			# half-buried ground floors, tin sheds, abandoned homes, blocked canals.
			d.merge({"floors": Vector2i(1, 4), "brick": 0.45, "tin": 0.45, "lane": 4.5, "main": 9.0,
				"shop": 0.3, "lot": Vector2(4.5, 8.0), "balcony": 0.15, "unfinished": 0.2, "trees": 0.02}, true)
		"kajla", "cattle", "powerhouse":
			# Kajla: dense brick neighbourhood, cattle-market yards, vertical livestock farms,
			# the potholed Kazla Power House Road linking Demra Rd to Jatrabari Biswa Rd.
			d.merge({"floors": Vector2i(2, 5), "brick": 0.55, "tin": 0.25, "lane": 5.5, "main": 10.0,
				"shop": 0.55, "stalls": 0.35, "lot": Vector2(5.5, 9.5), "balcony": 0.2}, true)
		"sontek", "housing", "apartment":
			# Sontek (Dania): planned housing development—mid-rise apartments, villas and
			# supermarket/school frontages on more orderly roads.
			d.merge({"floors": Vector2i(4, 8), "brick": 0.35, "shop": 0.5, "trees": 0.18, "lane": 8.0,
				"main": 15.0, "lot": Vector2(9.0, 14.0), "balcony": 0.45, "glass": 0.15}, true)
		"jatrabari", "flyover", "terminal":
			# Jatrabari gateway: steel-furniture workshops, wholesale markets, flyover piers.
			d.merge({"floors": Vector2i(2, 6), "brick": 0.5, "shop": 0.8, "stalls": 0.4, "lane": 7.5,
				"main": 16.0, "lot": Vector2(7.0, 12.0), "balcony": 0.2}, true)
	return d

# ============================================================================ setup
func setup(services: Services, lvl: Dictionary) -> void:
	s = services
	level = lvl
	_low = services.quality <= 0
	build_r = 1 if _low else BUILD_R
	free_r = 2 if _low else FREE_R
	style = str(lvl.get("style", "residential"))
	var base_style := style
	if style in ["tower", "tower_roof"]:
		base_style = "residential"
	st = _style(base_style)
	_district = Districts.district_for_style(style)
	# Authentic local shop/landmark names for the four researched districts, with the
	# original generic names as filler so small districts still feel lived-in.
	_shop_names = SHOP_NAMES.duplicate()
	if _district != "":
		for nm in Districts.signage(style):
			_shop_names.append(nm)
	seed_base = int(lvl.get("seed", 1000))
	R = int(lvl.get("size", 14)) / 2
	if bool(lvl.get("river", false)):
		river_z = float(R - 1) * P
	_make_materials()
	_place_specials()
	for i in range(-R, R):
		for j in range(-R, R):
			layouts[Vector2i(i, j)] = _layout(i, j)
	_build_graph()
	_build_skyline()
	_build_lightpool()
	if river_z < 1e8:
		_build_river()
	_build_district_ground()

## District-wide ground treatment based on real southern-Dhaka urban planning.
func _build_district_ground() -> void:
	if _district == "jurain":
		# East Jurain is a low-lying basin: lanes stay under dark water while footpaths/roads
		# are raised, so the water plane sits just below the raised pavers (top y = 0.15).
		var w := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(R * 2 * P + 400.0, R * 2 * P + 400.0)
		w.mesh = pm
		w.material_override = _mats["water"]
		w.position = Vector3(0, 0.06, 0)
		add_child(w)

func _rng(i: int, j: int, salt: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector3i(i * 73 + seed_base, j * 37 - seed_base, salt))
	return r

func street_w(line: int) -> float:
	return float(st["main"]) if posmod(line, 3) == 0 else float(st["lane"])

## Building footprint of block (i, j): Rect2 in XZ.
func footprint(i: int, j: int) -> Rect2:
	var x0 := i * P + street_w(i) * 0.5
	var x1 := (i + 1) * P - street_w(i + 1) * 0.5
	var z0 := j * P + street_w(j) * 0.5
	var z1 := (j + 1) * P - street_w(j + 1) * 0.5
	var sx := maxf(0.0, x1 - x0)
	var sz := maxf(0.0, z1 - z0)
	return Rect2(x0, z0, sx, sz)

func block_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / P)), int(floor(p.z / P)))

# ============================================================================ POIs and special blocks
func _place_specials() -> void:
	var need: Dictionary = {}
	for m in level.get("missions", []):
		for stp in (m as Dictionary).get("steps", []):
			var sd: Dictionary = stp
			for key in ["poi", "from", "to"]:
				if sd.has(key):
					need[str(sd[key])] = true
	need["safehouse"] = true
	need["tea_stall"] = true
	need["square"] = true
	var spots: Array[Vector2i] = [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, -1),
		Vector2i(-2, 0), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(2, 0), Vector2i(0, -2), Vector2i(-2, -1), Vector2i(2, -1), Vector2i(0, 2), Vector2i(-2, 1)]
	var used := {}
	var order := ["tower_gate", "square", "den", "market", "ghat", "hospital", "printing", "coaching", "bank", "safehouse", "tea_stall", "bus_stand", "alley", "roof_extract"]
	if style in ["tower", "tower_roof"]:
		specials[Vector2i(0, 0)] = "tower"
		used[Vector2i(0, 0)] = true
		var f := footprint(0, 0)
		var c := f.get_center()
		tower_info = {"rect": Rect2(c.x - 13.0, c.y - 10.0, 26.0, 20.0), "floors": 9}
		pois["tower_gate"] = Vector3(c.x, 0.15, c.y + 13.5)
		for n in range(1, 10):
			pois["floor%d" % n] = Vector3(c.x + 4.0, (n - 1) * 3.4 + 0.2, c.y + 2.0)
		pois["tower_roof"] = Vector3(c.x + 4.0, 9 * 3.4 + 0.2, c.y)
	var k := 0
	for name in order:
		if not need.has(name) and not (name in ["safehouse", "tea_stall", "square"]):
			continue
		if pois.has(name):
			continue
		if name == "roof_extract":
			continue
		while k < spots.size() and used.has(spots[k]):
			k += 1
		var b: Vector2i = spots[mini(k, spots.size() - 1)]
		var f2 := footprint(b.x, b.y)
		var c2 := f2.get_center()
		match name:
			"square", "market", "den":
				specials[b] = name
				used[b] = true
				pois[name] = Vector3(c2.x, 0.15, c2.y)
				k += 1
			"ghat":
				var bz := R - 2
				var gb := Vector2i(0, bz)
				specials[gb] = "ghat"
				var fg := footprint(0, bz)
				pois["ghat"] = Vector3(fg.get_center().x, 0.15, fg.end.y + 4.0)
			"alley":
				specials[b] = "alley"
				used[b] = true
				pois["alley"] = Vector3(c2.x, 0.15, c2.y)
				k += 1
			_:
				# building-front POIs share blocks: placed on the south footpath, different offsets
				var slot := int(pois.size()) % 3
				pois[name] = Vector3(f2.position.x + f2.size.x * (0.2 + 0.3 * slot), 0.15, f2.end.y + 1.6)
				if not specials.has(b):
					specials[b] = "front"
				if slot == 2:
					used[b] = true
					k += 1
	# rooftop extraction: a 6-storey roof a few blocks away
	var rb := Vector2i(-2 if R > 3 else -1, 2 if R > 3 else 1)
	specials[rb] = specials.get(rb, "") if specials.has(rb) else "roofx"
	var fr := footprint(rb.x, rb.y)
	pois["roof_extract"] = Vector3(fr.position.x + 5.5, GROUND + 5 * STOREY + 0.1, fr.end.y - 6.0)
	var sh: Vector3 = pois["safehouse"]
	safehouse_room = Rect2(sh.x - 3.0, sh.z - 1.6 - 7.0, 6.0, 6.5)

func poi(name: String) -> Vector3:
	if pois.has(name):
		return pois[name]
	return Vector3(0, 0.15, P * 0.5)

# ============================================================================ layout (cheap, whole map)
func _layout(i: int, j: int) -> Array:
	var key := Vector2i(i, j)
	var kind := str(specials.get(key, ""))
	if kind in ["square", "market", "den", "tower"]:
		return []
	var r := _rng(i, j)
	var f := footprint(i, j)
	var out: Array = []
	if r.randf() < float(st["open"]) and kind == "":
		return out
	var _room := safehouse_room.grow(0.3)
	var lot_min: float = (st["lot"] as Vector2).x
	var lot_max: float = (st["lot"] as Vector2).y
	var depth := minf(16.0, f.size.y * 0.42)
	var alley := kind == "alley"
	# north and south rows (full width), then east and west between them
	for side in ["s", "n"]:
		var x := f.position.x
		while x < f.end.x - 0.5:
			var w := minf(r.randf_range(lot_min, lot_max), f.end.x - x)
			if f.end.x - (x + w) < lot_min * 0.6:
				w = f.end.x - x
			var z0 := f.end.y - depth if side == "s" else f.position.y
			var faces: Array = [Vector3(0, 0, 1) if side == "s" else Vector3(0, 0, -1)]
			if x <= f.position.x + 0.1:
				faces.append(Vector3(-1, 0, 0))
			if x + w >= f.end.x - 0.1:
				faces.append(Vector3(1, 0, 0))
			out.append(_bld(r, Rect2(x, z0, w, depth), faces, i, j))
			x += w
	var mid0 := f.position.y + depth
	var mid1 := f.end.y - depth
	if mid1 - mid0 > 4.0:
		for side2 in ["w", "e"]:
			var z := mid0
			var dep := minf(depth, (f.size.x - (6.0 if alley else 0.0)) * 0.5)
			while z < mid1 - 0.5:
				var w2 := minf(r.randf_range(lot_min, lot_max), mid1 - z)
				if mid1 - (z + w2) < lot_min * 0.6:
					w2 = mid1 - z
				var x0 := f.position.x if side2 == "w" else f.end.x - dep
				out.append(_bld(r, Rect2(x0, z, dep, w2), [Vector3(-1, 0, 0) if side2 == "w" else Vector3(1, 0, 0)], i, j))
				z += w2
			# interior
		var ix0 := f.position.x + depth
		var ix1 := f.end.x - depth
		if ix1 - ix0 > 4.0 and not alley:
			out.append(_bld(r, Rect2(ix0, mid0, ix1 - ix0, mid1 - mid0), [], i, j))
	if safehouse_room.size.x > 0.0:
		var keep: Array = []
		for b0 in out:
			if not ((b0 as Dictionary)["rect"] as Rect2).intersects(_room):
				keep.append(b0)
		out = keep
	# forced roof-extraction building
	if specials.get(key, "") == "roofx" and not out.is_empty():
		for b in out:
			var bd: Dictionary = b
			var rc: Rect2 = bd["rect"]
			if rc.has_point(Vector2(f.position.x + 5.5, f.end.y - 6.0)):
				bd["floors"] = 6
				bd["h"] = GROUND + 5 * STOREY
				bd["tin"] = false
				bd["unfinished"] = false
	return out

func _bld(r: RandomNumberGenerator, rect: Rect2, faces: Array, i: int, j: int) -> Dictionary:
	var fr: Vector2i = st["floors"]
	var floors := r.randi_range(fr.x, fr.y)
	var main_face := false
	for fc in faces:
		var fv: Vector3 = fc
		if (fv.z > 0.5 and posmod(j + 1, 3) == 0) or (fv.z < -0.5 and posmod(j, 3) == 0) or (fv.x > 0.5 and posmod(i + 1, 3) == 0) or (fv.x < -0.5 and posmod(i, 3) == 0):
			main_face = true
	var shop := not faces.is_empty() and r.randf() < (float(st["main_shop"]) if main_face else float(st["shop"]))
	var tin := r.randf() < float(st["tin"])
	var unfinished := not tin and r.randf() < float(st["unfinished"])
	var glass := not tin and r.randf() < float(st["glass"])
	if tin:
		floors = mini(floors, 2)
	var h := (GROUND if shop else STOREY) + (floors - 1) * STOREY
	if faces.is_empty():
		floors = maxi(1, floors - 1)
		h = STOREY * floors
	return {"rect": rect, "faces": faces, "floors": floors, "h": h, "shop": shop, "tin": tin, "unfinished": unfinished, "glass": glass,
		"brick": r.randf() < float(st["brick"]), "color": PASTELS[r.randi() % PASTELS.size()], "seed": r.randi(), "main": main_face}

# ============================================================================ materials and unit meshes
func _make_materials() -> void:
	var plaster: StandardMaterial3D = (load("res://assets/textures/plaster_white/plaster_white.tres") as StandardMaterial3D).duplicate()
	plaster.vertex_color_use_as_albedo = true
	plaster.uv1_scale = Vector3(0.4, 0.33, 0.4)
	_mats["plaster"] = plaster
	var brick: StandardMaterial3D = (load("res://assets/textures/brick_weathered/brick_weathered.tres") as StandardMaterial3D).duplicate()
	brick.uv1_scale = Vector3(0.4, 0.4, 0.4)
	_mats["brick"] = brick
	# painted cement for slabs, chajjas and balconies (tinted per building); mossy raw concrete for frames
	var conc: StandardMaterial3D = plaster.duplicate()
	conc.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_mats["concrete"] = conc
	var raw: StandardMaterial3D = (load("res://assets/textures/concrete_mossy/concrete_mossy.tres") as StandardMaterial3D).duplicate()
	raw.vertex_color_use_as_albedo = true
	raw.uv1_scale = Vector3(0.45, 0.45, 0.45)
	_mats["raw"] = raw
	_mats["asphalt"] = load("res://assets/textures/asphalt_cracked/asphalt_cracked.tres")
	var asp: StandardMaterial3D = (load("res://assets/textures/asphalt_cracked/asphalt_cracked.tres") as StandardMaterial3D).duplicate()
	asp.uv1_scale = Vector3(0.18, 0.18, 0.18)
	_mats["asphalt"] = asp
	var fp: StandardMaterial3D = (load("res://assets/textures/pavers_footpath/pavers_footpath.tres") as StandardMaterial3D).duplicate()
	fp.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_mats["footpath"] = fp
	var chk: StandardMaterial3D = (load("res://assets/textures/pavers_checker/pavers_checker.tres") as StandardMaterial3D).duplicate()
	chk.uv1_scale = Vector3(0.5, 0.5, 0.5)
	_mats["checker"] = chk
	var tin: StandardMaterial3D = (load("res://assets/textures/tin_galvanized/tin_galvanized.tres") as StandardMaterial3D).duplicate()
	tin.vertex_color_use_as_albedo = true
	_mats["tin"] = tin
	_mats["tin_green"] = load("res://assets/textures/tin_painted_green/tin_painted_green.tres")
	_mats["tarp"] = load("res://assets/textures/awning_tarp_blue/awning_tarp_blue.tres")
	_mats["awning"] = load("res://assets/textures/awning_stripes_red/awning_stripes_red.tres")
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.roughness = 0.55
	paint.metallic = 0.35
	_mats["paint"] = paint
	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	plain.roughness = 0.8
	_mats["plain"] = plain
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.04, 0.04, 0.04)
	wire.roughness = 0.6
	_mats["wire"] = wire
	var glow := ShaderMaterial.new()
	glow.shader = load("res://scripts/world/window.gdshader")
	_mats["glass"] = glow
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.2, 0.24, 0.22)
	water.roughness = 0.08
	water.metallic = 0.2
	water.normal_enabled = true
	water.normal_texture = load("res://assets/textures/concrete_mossy/concrete_mossy_normal.png")
	water.normal_scale = 0.25
	water.uv1_scale = Vector3(30, 30, 1)
	_mats["water"] = water

## Box with per-face normals, vertex colours and world UVs into arrays.
static func box(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, uv: PackedVector2Array, center: Vector3, size: Vector3, col: Color, basis: Basis = Basis()) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var faces := [
		[Vector3(1, 0, 0), [Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz)]],
		[Vector3(-1, 0, 0), [Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz)]],
		[Vector3(0, 1, 0), [Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz)]],
		[Vector3(0, -1, 0), [Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz)]],
		[Vector3(0, 0, 1), [Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, -hy, hz)]],
		[Vector3(0, 0, -1), [Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, -hy, -hz)]],
	]
	for f in faces:
		var fa: Array = f
		var nn: Vector3 = basis * (fa[0] as Vector3)
		var q: Array = fa[1]
		var p0: Vector3 = center + basis * (q[0] as Vector3)
		var p1: Vector3 = center + basis * (q[1] as Vector3)
		var p2: Vector3 = center + basis * (q[2] as Vector3)
		var p3: Vector3 = center + basis * (q[3] as Vector3)
		for p in [p0, p1, p2, p0, p2, p3]:
			v.append(p)
			n.append(nn)
			c.append(col)
			var pp: Vector3 = p
			uv.append(Vector2(pp.x + pp.z, -pp.y) * 0.5 if absf(nn.y) < 0.5 else Vector2(pp.x, pp.z) * 0.5)

static func commit(mesh: ArrayMesh, v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, uv: PackedVector2Array, mat: Material) -> void:
	if v.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

## Small reusable meshes for MultiMesh instancing, built once.
func _unit(name: String) -> Mesh:
	if _units.has(name):
		return _units[name]
	var m := ArrayMesh.new()
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var W := Color.WHITE
	match name:
		"frame":   # 1.2 × 1.4 aluminium window frame with a mullion
			box(v, n, c, uv, Vector3(0, 0.7, 0), Vector3(1.24, 0.06, 0.08), W)
			box(v, n, c, uv, Vector3(0, -0.7, 0), Vector3(1.24, 0.06, 0.08), W)
			box(v, n, c, uv, Vector3(-0.6, 0, 0), Vector3(0.06, 1.4, 0.08), W)
			box(v, n, c, uv, Vector3(0.6, 0, 0), Vector3(0.06, 1.4, 0.08), W)
			box(v, n, c, uv, Vector3(0, 0, 0), Vector3(0.04, 1.4, 0.06), W)
			commit(m, v, n, c, uv, _mats["paint"])
		"glass":
			box(v, n, c, uv, Vector3(0, 0, -0.03), Vector3(1.16, 1.36, 0.02), W)
			commit(m, v, n, c, uv, _mats["glass"])
		"grill":   # protruding steel box grill (bars + frame), depth 0.3
			for k in 7:
				box(v, n, c, uv, Vector3(-0.66 + k * 0.22, 0, 0.3), Vector3(0.025, 1.6, 0.025), W)
			for yy: float in [-0.8, -0.27, 0.27, 0.8]:
				box(v, n, c, uv, Vector3(0, yy, 0.3), Vector3(1.4, 0.03, 0.03), W)
				box(v, n, c, uv, Vector3(-0.7, yy, 0.15), Vector3(0.03, 0.03, 0.3), W)
				box(v, n, c, uv, Vector3(0.7, yy, 0.15), Vector3(0.03, 0.03, 0.3), W)
			box(v, n, c, uv, Vector3(0, 0.8, 0.15), Vector3(1.42, 0.03, 0.3), W)
			commit(m, v, n, c, uv, _mats["paint"])
		"chajja":
			box(v, n, c, uv, Vector3(0, 0, 0.25), Vector3(1.8, 0.09, 0.55), Color(0.9, 0.88, 0.84))
			commit(m, v, n, c, uv, _mats["concrete"])
		"balcony":  # slab + railing posts + top rail; 3.0 wide, 1.0 deep
			box(v, n, c, uv, Vector3(0, 0, 0.5), Vector3(3.0, 0.16, 1.0), Color(0.9, 0.88, 0.84))
			commit(m, v, n, c, uv, _mats["concrete"])
			var v2 := PackedVector3Array()
			var n2 := PackedVector3Array()
			var c2 := PackedColorArray()
			var u2 := PackedVector2Array()
			for k2 in 13:
				box(v2, n2, c2, u2, Vector3(-1.45 + k2 * 0.2417, 0.5, 0.97), Vector3(0.025, 0.9, 0.025), W)
			box(v2, n2, c2, u2, Vector3(0, 0.95, 0.97), Vector3(3.0, 0.05, 0.05), W)
			box(v2, n2, c2, u2, Vector3(-1.48, 0.5, 0.5), Vector3(0.04, 0.9, 1.0), W)
			box(v2, n2, c2, u2, Vector3(1.48, 0.5, 0.5), Vector3(0.04, 0.9, 1.0), W)
			commit(m, v2, n2, c2, u2, _mats["paint"])
		"clothes":   # three hanging garments on a line
			box(v, n, c, uv, Vector3(0, 0.0, 0), Vector3(2.6, 0.01, 0.01), Color(0.2, 0.2, 0.2))
			box(v, n, c, uv, Vector3(-0.8, -0.35, 0), Vector3(0.55, 0.7, 0.01), W)
			box(v, n, c, uv, Vector3(0.0, -0.5, 0), Vector3(0.4, 1.0, 0.01), Color(0.85, 0.85, 0.95))
			box(v, n, c, uv, Vector3(0.75, -0.3, 0), Vector3(0.7, 0.6, 0.01), Color(0.95, 0.9, 0.8))
			commit(m, v, n, c, uv, _mats["plain"])
		"ac":
			box(v, n, c, uv, Vector3(0, 0, 0.18), Vector3(0.82, 0.55, 0.32), Color(0.92, 0.92, 0.9))
			box(v, n, c, uv, Vector3(0.12, 0, 0.345), Vector3(0.42, 0.42, 0.01), Color(0.3, 0.3, 0.3))
			commit(m, v, n, c, uv, _mats["paint"])
		"tank":   # black plastic water tank on a stand
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.55
			cyl.bottom_radius = 0.58
			cyl.height = 1.35
			cyl.radial_segments = 14
			var t_arr := cyl.get_mesh_arrays()
			var verts: PackedVector3Array = t_arr[Mesh.ARRAY_VERTEX]
			for k3 in verts.size():
				verts[k3] += Vector3(0, 1.3, 0)
			t_arr[Mesh.ARRAY_VERTEX] = verts
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, t_arr)
			m.surface_set_material(0, Humanoid.plain_material(Color(0.06, 0.06, 0.07), 0.45))
			for sx: float in [-0.45, 0.45]:
				for sz: float in [-0.45, 0.45]:
					box(v, n, c, uv, Vector3(sx, 0.3, sz), Vector3(0.06, 0.6, 0.06), Color(0.3, 0.3, 0.3))
			box(v, n, c, uv, Vector3(0, 0.6, 0), Vector3(1.2, 0.05, 1.2), Color(0.35, 0.35, 0.35))
			commit(m, v, n, c, uv, _mats["paint"])
		"pole":   # concrete pole, lamp arm and head
			box(v, n, c, uv, Vector3(0, 4.5, 0), Vector3(0.22, 9.0, 0.22), Color(0.75, 0.74, 0.7))
			box(v, n, c, uv, Vector3(0, 7.6, 0.7), Vector3(0.06, 0.06, 1.4), Color(0.3, 0.3, 0.3))
			for yy2: float in [8.1, 8.5]:
				box(v, n, c, uv, Vector3(0, yy2, 0), Vector3(0.9, 0.08, 0.08), Color(0.6, 0.6, 0.58))
			commit(m, v, n, c, uv, _mats["concrete"])
		"lamphead":
			box(v, n, c, uv, Vector3(0, 7.55, 1.38), Vector3(0.28, 0.12, 0.5), W)
			commit(m, v, n, c, uv, _mats["glass"])
		"shutter":
			box(v, n, c, uv, Vector3(0, 0, 0), Vector3(1.0, 1.0, 0.04), W)
			commit(m, v, n, c, uv, _mats["tin"])
		"board":
			box(v, n, c, uv, Vector3(0, 0, 0), Vector3(1.0, 1.0, 0.1), W)
			commit(m, v, n, c, uv, _mats["paint"])
		"tree":
			box(v, n, c, uv, Vector3(0, 1.6, 0), Vector3(0.3, 3.2, 0.3), Color(0.32, 0.24, 0.17))
			commit(m, v, n, c, uv, _mats["plain"])
			var sph := SphereMesh.new()
			sph.radius = 1.0
			sph.height = 2.0
			sph.radial_segments = 10
			sph.rings = 6
			var sa := sph.get_mesh_arrays()
			var sv: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
			var out_v := PackedVector3Array()
			var out_n := PackedVector3Array()
			var sn: PackedVector3Array = sa[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = sa[Mesh.ARRAY_INDEX]
			for off: Vector3 in [Vector3(0, 4.0, 0), Vector3(0.9, 3.5, 0.3), Vector3(-0.7, 3.6, -0.5), Vector3(0.1, 4.7, 0.4)]:
				var sc := 1.6 if off.y < 4.5 else 1.2
				for id in idx:
					out_v.append(sv[id] * sc + off)
					out_n.append(sn[id])
			var ta := []
			ta.resize(Mesh.ARRAY_MAX)
			ta[Mesh.ARRAY_VERTEX] = out_v
			ta[Mesh.ARRAY_NORMAL] = out_n
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ta)
			m.surface_set_material(1, Humanoid.plain_material(Color(0.23, 0.36, 0.17), 0.85))
		"rickshaw":
			box(v, n, c, uv, Vector3(0, 0.75, 0.3), Vector3(1.0, 0.12, 0.6), Color(0.85, 0.15, 0.2))
			box(v, n, c, uv, Vector3(0, 1.05, 0.55), Vector3(1.0, 0.5, 0.1), Color(0.95, 0.75, 0.2))
			box(v, n, c, uv, Vector3(0, 1.55, 0.35), Vector3(1.05, 0.06, 0.8), Color(0.1, 0.1, 0.1))
			box(v, n, c, uv, Vector3(0, 0.6, -0.6), Vector3(0.08, 0.08, 1.4), Color(0.2, 0.2, 0.2))
			box(v, n, c, uv, Vector3(0, 0.95, -1.15), Vector3(0.25, 0.06, 0.3), Color(0.1, 0.1, 0.1))
			for wx: float in [-0.55, 0.55]:
				box(v, n, c, uv, Vector3(wx, 0.35, 0.3), Vector3(0.05, 0.7, 0.7), Color(0.15, 0.15, 0.15))
			box(v, n, c, uv, Vector3(0, 0.35, -1.25), Vector3(0.05, 0.7, 0.7), Color(0.15, 0.15, 0.15))
			commit(m, v, n, c, uv, _mats["paint"])
		"stall":   # market stall: table, posts, blue tarp roof
			box(v, n, c, uv, Vector3(0, 0.8, 0), Vector3(2.4, 0.08, 1.4), Color(0.45, 0.32, 0.2))
			for sx2: float in [-1.15, 1.15]:
				for sz2: float in [-0.65, 0.65]:
					box(v, n, c, uv, Vector3(sx2, 1.2, sz2), Vector3(0.07, 2.4, 0.07), Color(0.4, 0.3, 0.2))
			for k4 in 6:
				box(v, n, c, uv, Vector3(-0.9 + k4 * 0.36, 0.95, 0.0), Vector3(0.3, 0.22, 0.3), Color.from_hsv(randf(), 0.6, 0.85))
			commit(m, v, n, c, uv, _mats["plain"])
			var v3 := PackedVector3Array()
			var n3 := PackedVector3Array()
			var c3 := PackedColorArray()
			var u3 := PackedVector2Array()
			box(v3, n3, c3, u3, Vector3(0, 2.45, 0), Vector3(2.8, 0.04, 2.0), W, Basis(Vector3.RIGHT, 0.12))
			commit(m, v3, n3, c3, u3, _mats["tarp"])
	_units[name] = m
	return m

# ============================================================================ skyline (distant blocks)
func _build_skyline() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	mm.mesh = cube
	var count := 0
	for k in layouts.keys():
		count += (layouts[k] as Array).size()
	mm.instance_count = count
	var idx := 0
	for k in layouts.keys():
		var ids: Array = []
		for b in layouts[k]:
			var bd: Dictionary = b
			var rc: Rect2 = bd["rect"]
			var h := float(bd["h"])
			mm.set_instance_transform(idx, Transform3D(Basis().scaled(Vector3(rc.size.x, h, rc.size.y)), Vector3(rc.get_center().x, h * 0.5, rc.get_center().y)))
			mm.set_instance_color(idx, (bd["color"] as Color).darkened(0.08))
			ids.append(idx)
			idx += 1
		_sky_index[k] = ids
	_skyline = MultiMeshInstance3D.new()
	_skyline.multimesh = mm
	_skyline.material_override = _mats["plaster"]
	_skyline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_skyline)
	# one big asphalt ground under everything
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(R * 2 * P + 400.0, R * 2 * P + 400.0)
	g.mesh = pm
	g.material_override = _mats["asphalt"]
	g.position = Vector3(0, -0.02, 0)
	add_child(g)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(R * 2 * P + 400.0, 1.0, R * 2 * P + 400.0)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

func _sky_visible(k: Vector2i, on: bool) -> void:
	var mm := _skyline.multimesh
	for id in _sky_index.get(k, []):
		var bd: Dictionary = (layouts[k] as Array)[(_sky_index[k] as Array).find(id)]
		var rc: Rect2 = bd["rect"]
		var h := float(bd["h"])
		var sc := Vector3(rc.size.x, h, rc.size.y) if on else Vector3(0.001, 0.001, 0.001)
		mm.set_instance_transform(int(id), Transform3D(Basis().scaled(sc), Vector3(rc.get_center().x, h * 0.5 if on else -50.0, rc.get_center().y)))

func _build_river() -> void:
	var w := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(R * 2 * P + 400.0, 300.0)
	w.mesh = pm
	w.material_override = _mats["water"]
	w.position = Vector3(0, 0.05, river_z + 150.0)
	add_child(w)

# ============================================================================ street graph
func _cid(i: int, j: int, c: int) -> int:
	return (((i + R) * (2 * R + 2)) + (j + R)) * 4 + c

func _build_graph() -> void:
	for i in range(-R, R):
		for j in range(-R, R):
			var f := footprint(i, j)
			var cs := [Vector3(f.position.x - 1.2, 0.15, f.position.y - 1.2), Vector3(f.end.x + 1.2, 0.15, f.position.y - 1.2),
				Vector3(f.end.x + 1.2, 0.15, f.end.y + 1.2), Vector3(f.position.x - 1.2, 0.15, f.end.y + 1.2)]
			for c in 4:
				astar.add_point(_cid(i, j, c), cs[c])
			for c in 4:
				astar.connect_points(_cid(i, j, c), _cid(i, j, (c + 1) % 4))
	for i in range(-R, R):
		for j in range(-R, R):
			if i + 1 < R:
				astar.connect_points(_cid(i, j, 1), _cid(i + 1, j, 0))
				astar.connect_points(_cid(i, j, 2), _cid(i + 1, j, 3))
			if j + 1 < R:
				astar.connect_points(_cid(i, j, 3), _cid(i, j + 1, 0))
				astar.connect_points(_cid(i, j, 2), _cid(i, j + 1, 1))

func street_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var a := astar.get_closest_point(from)
	var b := astar.get_closest_point(to)
	var path := astar.get_point_path(a, b)
	var out := PackedVector3Array()
	for p in path:
		out.append(p)
	out.append(Vector3(to.x, 0.15, to.z))
	return out

func random_sidewalk_point(near: Vector3, radius: float) -> Vector3:
	var b := block_of(near + Vector3(randf_range(-radius, radius), 0, randf_range(-radius, radius)))
	b.x = clampi(b.x, -R, R - 1)
	b.y = clampi(b.y, -R, R - 1)
	var f := footprint(b.x, b.y)
	var side := randi() % 4
	var u := randf()
	match side:
		0: return Vector3(lerpf(f.position.x, f.end.x, u), 0.15, f.position.y - 1.1)
		1: return Vector3(f.end.x + 1.1, 0.15, lerpf(f.position.y, f.end.y, u))
		2: return Vector3(lerpf(f.position.x, f.end.x, u), 0.15, f.end.y + 1.1)
	return Vector3(f.position.x - 1.1, 0.15, lerpf(f.position.y, f.end.y, u))

func nearest_door(p: Vector3) -> Vector3:
	var b := block_of(p)
	var best := random_sidewalk_point(p, 20.0)
	var bd := 1e9
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for bl in layouts.get(Vector2i(b.x + dx, b.y + dz), []):
				var bld: Dictionary = bl
				if bld.has("door"):
					var d: Vector3 = bld["door"]
					var dist := d.distance_to(p)
					if dist < bd:
						bd = dist
						best = d
	return best

func random_roof_point(near: Vector3, radius: float) -> Vector3:
	for attempt in 20:
		var b := block_of(near + Vector3(randf_range(-radius, radius), 0, randf_range(-radius, radius)))
		var arr: Array = layouts.get(b, [])
		if arr.is_empty():
			continue
		var bd: Dictionary = arr[randi() % arr.size()]
		if bool(bd.get("tin", false)) or bool(bd.get("unfinished", false)):
			continue
		var rc: Rect2 = bd["rect"]
		return Vector3(rc.get_center().x, float(bd["h"]) + 0.1, rc.get_center().y)
	return random_sidewalk_point(near, radius)

func ground_point_near(p: Vector3, radius: float) -> Vector3:
	var q := random_sidewalk_point(p, radius)
	return q

# ============================================================================ light, shelter
func light_level(p: Vector3) -> float:
	if s.clock and not s.clock.is_night():
		return 1.0
	var best := 0.15
	for l in lamps:
		var la: Array = l
		if not bool(la[1]):
			continue
		var d := Vector2(p.x - (la[0] as Vector3).x, p.z - (la[0] as Vector3).z).length()
		if d < 8.0:
			best = maxf(best, lerpf(1.0, 0.3, d / 8.0))
	return best

## Ghost-safe: inside lamp light, a candle circle or the safehouse room.
func is_lit_safe(p: Vector3) -> bool:
	if safehouse_room.has_point(Vector2(p.x, p.z)) and p.y < 3.0:
		return true
	for c in get_tree().get_nodes_in_group("candles"):
		var cn := c as Node3D
		if cn and cn.global_position.distance_to(p) < Candle.RADIUS:
			return true
	if s.clock and not s.clock.is_night():
		return true
	for l in lamps:
		var la: Array = l
		if bool(la[1]) and Vector2(p.x - (la[0] as Vector3).x, p.z - (la[0] as Vector3).z).length() < 5.0 and p.y < 9.0:
			return true
	return false

func _build_lightpool() -> void:
	var count := 6 if _low else 14
	for k in count:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.68, 0.36)
		l.light_energy = 2.6
		l.omni_range = 9.0 if _low else 11.0
		l.omni_attenuation = 1.4
		l.shadow_enabled = (not _low) and k < 4
		l.visible = false
		l.light_volumetric_fog_energy = 0.0 if _low else 2.0
		add_child(l)
		lightpool.append(l)

## Re-apply the parts of quality that can change at runtime (phone settings).
func refresh_quality() -> void:
	_low = s != null and s.quality <= 0
	build_r = 1 if _low else BUILD_R
	free_r = 2 if _low else FREE_R
	for i in lightpool.size():
		var lp := lightpool[i] as OmniLight3D
		if lp:
			lp.shadow_enabled = (not _low) and i < 4

# ============================================================================ streaming
func ensure_built(p: Vector3, radius: int = 1) -> void:
	var b := block_of(p)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var k := Vector2i(b.x + dx, b.y + dz)
			if layouts.has(k) and not blocks.has(k):
				_build_block(k)

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_night = 1.0 - (s.clock.daylight() if s.clock else 1.0)
	(_mats["glass"] as ShaderMaterial).set_shader_parameter("night", _night)
	_stream_t -= delta
	var focus := cam.global_position
	if s.player and is_instance_valid(s.player):
		focus = (s.player as Node3D).global_position
	if _stream_t <= 0.0:
		_stream_t = 0.4
		var b := block_of(focus)
		for dx in range(-build_r, build_r + 1):
			for dz in range(-build_r, build_r + 1):
				var k := Vector2i(b.x + dx, b.y + dz)
				if layouts.has(k) and not blocks.has(k) and not _queue.has(k):
					_queue.append(k)
		_queue.sort_custom(func(a: Vector2i, c: Vector2i) -> bool: return (a - b).length_squared() < (c - b).length_squared())
		for k2 in blocks.keys():
			var kk: Vector2i = k2
			if absi(kk.x - b.x) > free_r or absi(kk.y - b.y) > free_r:
				_free_block(kk)
		_update_lightpool(focus)
	if not _queue.is_empty():
		var k3: Vector2i = _queue.pop_front()
		if not blocks.has(k3):
			var t0 := Time.get_ticks_usec()
			_build_block(k3)
			if OS.get_environment("DHAKA_LOG_STREAM") != "":
				print("STREAM block %s built in %.1f ms" % [str(k3), (Time.get_ticks_usec() - t0) / 1000.0])

func _update_lightpool(focus: Vector3) -> void:
	var on := _night > 0.3
	var near: Array = []
	if on:
		for l in lamps:
			var la: Array = l
			if bool(la[1]):
				near.append([(la[0] as Vector3).distance_squared_to(focus), la[0]])
		near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in lightpool.size():
		var lp := lightpool[i]
		if on and i < near.size():
			lp.visible = true
			lp.global_position = (near[i][1] as Vector3) + Vector3(0, 7.3, 1.35)
			lp.light_energy = 2.6 * _night * (0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.01 + i))
		else:
			lp.visible = false

func _free_block(k: Vector2i) -> void:
	var n: Node3D = blocks[k]
	blocks.erase(k)
	n.queue_free()
	_sky_visible(k, true)
	if _lamp_by_block.has(k):
		for l in _lamp_by_block[k]:
			lamps.erase(l)
		_lamp_by_block.erase(k)

# ============================================================================ block construction
class Builder:
	var v := {}
	var n := {}
	var c := {}
	var uv := {}
	var mm := {}      # unit -> [transforms, colors]
	func arrays(mat: String) -> Array:
		if not v.has(mat):
			v[mat] = PackedVector3Array()
			n[mat] = PackedVector3Array()
			c[mat] = PackedColorArray()
			uv[mat] = PackedVector2Array()
		return [v[mat], n[mat], c[mat], uv[mat]]
	func inst(unit: String, t: Transform3D, col: Color = Color.WHITE) -> void:
		if not mm.has(unit):
			mm[unit] = [[], []]
		(mm[unit][0] as Array).append(t)
		(mm[unit][1] as Array).append(col)

func _b(bld: Builder, mat: String, center: Vector3, size: Vector3, col: Color = Color.WHITE, basis: Basis = Basis()) -> void:
	var a := bld.arrays(mat)
	var v: PackedVector3Array = a[0]
	var nn: PackedVector3Array = a[1]
	var cc: PackedColorArray = a[2]
	var uu: PackedVector2Array = a[3]
	box(v, nn, cc, uu, center, size, col, basis)
	bld.v[mat] = v
	bld.n[mat] = nn
	bld.c[mat] = cc
	bld.uv[mat] = uu

func _col(body: StaticBody3D, center: Vector3, size: Vector3, basis: Basis = Basis()) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, center)
	body.add_child(cs)

func _build_block(k: Vector2i) -> void:
	var node := Node3D.new()
	node.name = "B_%d_%d" % [k.x, k.y]
	add_child(node)
	blocks[k] = node
	_sky_visible(k, false)
	var r := _rng(k.x, k.y, 7)
	var bld := Builder.new()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	node.add_child(body)
	var f := footprint(k.x, k.y)
	var kind := str(specials.get(k, ""))
	# footpaths (raised pavers) around the footprint
	var fw := clampf(minf(street_w(k.x), street_w(k.y)) * 0.25, 1.4, 2.6)
	for side in 4:
		var c := Vector3.ZERO
		var sz := Vector3.ZERO
		match side:
			0:
				c = Vector3(f.get_center().x, 0.075, f.position.y - fw * 0.5)
				sz = Vector3(f.size.x + fw * 2.0, 0.15, fw)
			1:
				c = Vector3(f.get_center().x, 0.075, f.end.y + fw * 0.5)
				sz = Vector3(f.size.x + fw * 2.0, 0.15, fw)
			2:
				c = Vector3(f.position.x - fw * 0.5, 0.075, f.get_center().y)
				sz = Vector3(fw, 0.15, f.size.y)
			3:
				c = Vector3(f.end.x + fw * 0.5, 0.075, f.get_center().y)
				sz = Vector3(fw, 0.15, f.size.y)
		_b(bld, "footpath", c, sz, Color(1, 1, 1))
		_col(body, c, sz)
	_build_district_features(bld, body, node, k, f, r)
	var lamp_list: Array = []
	match kind:
		"square":
			_build_square(bld, body, node, f, r)
		"market":
			_build_market(bld, body, node, f, r)
		"den":
			_build_den(bld, body, node, f, r)
		"tower":
			_build_tower(bld, body, node, f, r)
	for b in layouts.get(k, []):
		_build_building(bld, body, node, b as Dictionary, r)
	if kind == "alley":
		_b(bld, "checker", Vector3(f.get_center().x, 0.03, f.get_center().y), Vector3(6.0, 0.06, f.size.y * 0.3), Color.WHITE)
	_street_furniture(bld, body, node, k, f, r, lamp_list)
	# Open CC0 street furniture and greenery (single-draw-call baked models).
	if r.randf() < 0.25:
		var pn := CC0Assets.props()
		var nm2 := pn[r.randi() % pn.size()]
		var prop: Node3D = CC0Assets.make(nm2)
		if prop:
			CC0Assets.no_shadows(prop)
			node.add_child(prop)
			prop.position = Vector3(f.get_center().x + r.randf_range(-f.size.x * 0.3, f.size.x * 0.3),
				0.0, f.position.y - 2.4)
	_special_fronts(bld, body, node, k, f, r)
	# commit merged geometry
	var mesh := ArrayMesh.new()
	for mat in bld.v.keys():
		commit(mesh, bld.v[mat], bld.n[mat], bld.c[mat], bld.uv[mat], _mats[mat])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	node.add_child(mi)
	for unit in bld.mm.keys():
		var data: Array = bld.mm[unit]
		var ts: Array = data[0]
		var cols: Array = data[1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _unit(str(unit))
		mm.instance_count = ts.size()
		for i in ts.size():
			mm.set_instance_transform(i, ts[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if str(unit) in ["clothes", "grill", "ac", "frame", "shutter", "board", "chajja"]:
			mmi.visibility_range_end = 80.0 if _low else 120.0
		node.add_child(mmi)
	_lamp_by_block[k] = lamp_list
	for l in lamp_list:
		lamps.append(l)

## Per-block details that make each researched district look like the real place.
func _build_district_features(bld: Builder, body: StaticBody3D, node: Node3D, k: Vector2i, f: Rect2, r: RandomNumberGenerator) -> void:
	match _district:
		"jurain":
			# Half-buried, abandoned look: dark stained water line at the base of buildings,
			# clogged drain channels down the lanes, broken boundary walls and rubble.
			var cx := f.get_center().x
			var cz := f.get_center().y
			var dark := Color(0.14, 0.17, 0.13)
			for s in 2:
				var px := cx + r.randf_range(-f.size.x * 0.3, f.size.x * 0.3)
				var pz := cz + r.randf_range(-f.size.y * 0.3, f.size.y * 0.3)
				_b(bld, "plain", Vector3(px, 0.07, pz), Vector3(r.randf_range(2.0, 4.5), 0.04, r.randf_range(0.4, 0.9)), dark)
			# collapsed / half wall
			if r.randf() < 0.45:
				var wx := f.position.x + 0.4
				_b(bld, "brick", Vector3(wx, 0.55, cz), Vector3(0.3, 1.1, r.randf_range(2.0, 4.0)), Color(0.6, 0.5, 0.44))
		"kajla":
			# Cattle-market holding pens and the potholed power-house road.
			if r.randf() < 0.5:
				var px := f.get_center().x + r.randf_range(-f.size.x * 0.25, f.size.x * 0.25)
				var pz := f.get_center().y + r.randf_range(-f.size.y * 0.25, f.size.y * 0.25)
				var wood := Color(0.42, 0.29, 0.17)
				for s in 4:
					var ang := TAU * s / 4.0
					var off := Vector3(cos(ang) * 2.2, 0.0, sin(ang) * 2.2)
					_b(bld, "plain", Vector3(px + off.x, 0.55, pz + off.z), Vector3(0.12, 1.1, 0.12), wood)
				for s in 4:
					var ang2 := TAU * s / 4.0
					var mid := Vector3(cos(ang2 + PI / 4.0) * 2.2, 0.85, sin(ang2 + PI / 4.0) * 2.2)
					_b(bld, "plain", Vector3(px + mid.x, mid.y, pz + mid.z), Vector3(2.6, 0.1, 0.1), wood, Basis(Vector3.UP, ang2))
			# pothole patch
			_b(bld, "raw", Vector3(f.get_center().x, 0.045, f.get_center().y), Vector3(r.randf_range(1.5, 3.5), 0.02, r.randf_range(1.0, 2.5)), Color(0.16, 0.15, 0.14))
		"jatrabari":
			# Mayor Mohammad Hanif flyover piers along the main road edge.
			if k.x % 3 == 0:
				var px := f.position.x + 1.5
				var pz := f.get_center().y
				_b(bld, "concrete", Vector3(px, 5.0, pz), Vector3(1.6, 10.0, 1.6), Color(0.72, 0.71, 0.68))
				_col(body, Vector3(px, 5.0, pz), Vector3(1.6, 10.0, 1.6))
				_b(bld, "concrete", Vector3(px, 10.2, pz), Vector3(4.5, 0.5, 3.0), Color(0.72, 0.71, 0.68))
		"sontek":
			# Planned housing: landscaped median planter and tidy hedge.
			if r.randf() < 0.6:
				var px := f.get_center().x
				var pz := f.get_center().y
				_b(bld, "concrete", Vector3(px, 0.2, pz), Vector3(2.4, 0.4, 1.2), Color(0.8, 0.8, 0.78))
				_b(bld, "plain", Vector3(px, 0.55, pz), Vector3(2.2, 0.4, 1.0), Color(0.2, 0.42, 0.18))

# ---------------------------------------------------------------- one building
func _build_building(bld: Builder, body: StaticBody3D, node: Node3D, b: Dictionary, _r: RandomNumberGenerator) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(b["seed"])
	var rc: Rect2 = b["rect"]
	var h := float(b["h"])
	var floors := int(b["floors"])
	var col: Color = b["color"]
	var center := Vector3(rc.get_center().x, h * 0.5, rc.get_center().y)
	var tin := bool(b["tin"])
	var unfinished := bool(b["unfinished"])
	var mat := "brick" if bool(b["brick"]) else "plaster"
	if tin:
		mat = "tin"
		col = Color.from_hsv(r.randf(), 0.15, r.randf_range(0.55, 0.85))
	if unfinished:
		_build_frame(bld, body, rc, floors, r)
		return
	var size := Vector3(rc.size.x - 0.04, h, rc.size.y - 0.04)
	# Open CC0 3D buildings (real modelled facades) replace a share of the procedural boxes.
	# Each model is a single vertex-coloured mesh, so it costs one draw call like our own geometry.
	if r.randf() < 0.25:
		var names := CC0Assets.buildings()
		var nm := names[r.randi() % names.size()]
		var model: Node3D = CC0Assets.make(nm)
		if model:
			var ground := Vector3(rc.get_center().x, 0.0, rc.get_center().y)
			CC0Assets.place_building(model, ground, size.x, size.z)
			CC0Assets.no_shadows(model)
			node.add_child(model)
			# collision matches the lot footprint up to the building height
			_col(body, ground + Vector3(0, size.y * 0.5, 0), Vector3(size.x, size.y, size.z))
			return
	_b(bld, mat, center, size, col)
	_col(body, center, size)
	var shop := bool(b["shop"])
	# floor bands (slab edges) read as horizontal lines on every walk-up
	if not tin:
		for fl in range(1, floors + 1):
			var y := (GROUND if shop else STOREY) + (fl - 1) * STOREY
			if y < h - 0.1:
				_b(bld, "concrete", Vector3(center.x, y, center.z), Vector3(size.x + 0.08, 0.14, size.z + 0.08), col.darkened(0.06))
		# roof cornice / parapet — the projecting band that gives Dhaka walk-ups their silhouette
		var parapet_col := col.darkened(0.12)
		_b(bld, "concrete", Vector3(center.x, h - 0.16, center.z), Vector3(size.x + 0.34, 0.32, size.z + 0.34), parapet_col)
		# corner pilasters break up the flat box and catch the light (front two only on LOW)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				if _low and sz > 0.0:
					continue
				_b(bld, "plaster", Vector3(center.x + sx * (size.x * 0.5 - 0.06), h * 0.5, center.z + sz * (size.z * 0.5 - 0.06)), Vector3(0.22, h, 0.22), col.lightened(0.08))
		# a coloured fascia band over the ground-floor shops
		if shop:
			_b(bld, "paint", Vector3(center.x, GROUND - 0.05, center.z), Vector3(size.x + 0.1, 0.3, size.z + 0.1), Color.from_hsv(_r.randf(), 0.55, 0.6))
	# facades
	var faces: Array = b["faces"]
	var door_set := false
	for fc in faces:
		var nrm: Vector3 = fc
		var along := Vector3(-nrm.z, 0, nrm.x)
		var L := absf(along.x) * rc.size.x + absf(along.z) * rc.size.y
		var face_c := Vector3(rc.get_center().x + nrm.x * rc.size.x * 0.5, 0, rc.get_center().y + nrm.z * rc.size.y * 0.5)
		var bas := Basis.looking_at(-nrm, Vector3.UP)   # local +Z points out of the facade
		var bays := maxi(1, int(L / (4.6 if _low else 3.0)))
		var bay_w := L / bays
		var g0 := GROUND if shop else STOREY
		for bay in bays:
			var off := (bay + 0.5) * bay_w - L * 0.5
			var base := face_c + along * off
			# ground floor
			if shop and not tin:
				var sw := bay_w - 0.3
				var open := r.randf()
				var shut_h := 2.7 * (0.35 if open < 0.65 else 1.0)
				bld.inst("shutter", Transform3D(bas.scaled(Vector3(sw, shut_h, 1.0)), base + Vector3(0, 2.75 - shut_h * 0.5, 0) + nrm * 0.03), Color(0.8, 0.8, 0.82))
				bld.inst("glass", Transform3D(bas.scaled(Vector3(sw / 1.16, (2.75 - shut_h) / 1.36, 1.0)), base + Vector3(0, (2.75 - shut_h) * 0.5, 0) + nrm * 0.0), Color(1.0, 0.85, 0.6, 0.45))
			elif not door_set and not tin and bay == bays / 2:
				door_set = true
				_door(bld, node, b, base, nrm, bas)
			elif not tin:
				_window(bld, base + Vector3(0, 1.6, 0), nrm, bas, r, col)
			elif tin and bay == 0:
				bld.inst("board", Transform3D(bas.scaled(Vector3(0.9, 1.9, 0.5)), base + Vector3(0, 0.95, 0) + nrm * 0.02), Color(0.3, 0.22, 0.15))
			# upper floors
			if tin:
				continue
			for fl2 in range(1, floors):
				# LOW draws windows on alternate floors only; from the street the rhythm reads the same.
				if _low and fl2 % 2 == 0:
					continue
				var y0 := g0 + (fl2 - 1) * STOREY
				if r.randf() < float(st["balcony"]) and bay_w >= 2.9:
					bld.inst("balcony", Transform3D(bas, base + Vector3(0, y0 + 0.08, 0)), Color(0.9, 0.9, 0.9) if r.randf() < 0.6 else Color(0.15, 0.3, 0.2))
					bld.inst("glass", Transform3D(bas.scaled(Vector3(1.0, 1.6, 1.0)), base + Vector3(0, y0 + 1.25, 0) + nrm * 0.01), Color(0.9, 0.7, 0.5, 1.0 if r.randf() < 0.35 else 0.0))
					if r.randf() < 0.6:
						bld.inst("clothes", Transform3D(bas, base + Vector3(0, y0 + 2.2, 0) + nrm * 0.75), Color.from_hsv(r.randf(), r.randf_range(0.3, 0.8), r.randf_range(0.5, 0.95)))
				elif bool(b["glass"]):
					bld.inst("glass", Transform3D(bas.scaled(Vector3(bay_w / 1.16, 2.4 / 1.36, 1.0)), base + Vector3(0, y0 + 1.5, 0) + nrm * 0.05), Color(0.5, 0.6, 0.7, 1.0 if r.randf() < 0.25 else 0.0))
				else:
					_window(bld, base + Vector3(0, y0 + 1.55, 0), nrm, bas, r, col)
					# chajja (small concrete sun-shade) and sill — signature of Dhaka walk-ups.
					if not _low or r.randf() < 0.25:
						_b(bld, "concrete", base + Vector3(0, y0 + 2.42, 0) + nrm * 0.2, Vector3(bay_w * 0.78, 0.1, 0.44), col.darkened(0.12), bas)
						_b(bld, "concrete", base + Vector3(0, y0 + 0.68, 0) + nrm * 0.13, Vector3(bay_w * 0.78, 0.09, 0.32), col.darkened(0.04), bas)
		# shop signboard across the facade
		if shop and not tin:
			var board_col := Color.from_hsv(r.randf(), r.randf_range(0.5, 0.9), r.randf_range(0.45, 0.85))
			var bpos := face_c + Vector3(0, 3.05, 0) + nrm * 0.12
			bld.inst("board", Transform3D(bas.scaled(Vector3(L - 0.6, 0.62, 1.0)), bpos), board_col)
			if _labels_on():
				var lab := Label3D.new()
				lab.text = _shop_names[r.randi() % _shop_names.size()]
				lab.font = BnText.font(true)
				lab.font_size = 96
				lab.pixel_size = 0.0045
				lab.modulate = Color(1, 1, 0.95) if board_col.get_luminance() < 0.55 else Color(0.08, 0.08, 0.1)
				lab.outline_size = 0
				lab.visibility_range_end = 70.0
				node.add_child(lab)
				lab.global_transform = Transform3D(bas, bpos + nrm * 0.06)
			if r.randf() < 0.4:
				# striped canvas awning over the shop row
				_b(bld, "awning", face_c + Vector3(0, 2.62, 0) + nrm * 0.75, Vector3(L - 0.8, 0.04, 1.4), Color.WHITE, bas * Basis(Vector3.RIGHT, 0.28))
		# posters on the ground floor wall
		if r.randf() < 0.5 and not shop:
			_poster(node, face_c + along * r.randf_range(-L * 0.3, L * 0.3) + Vector3(0, 1.7, 0) + nrm * 0.02, bas)
		elif r.randf() < 0.35:
			_poster(node, face_c + along * (L * 0.5 - 0.6) + Vector3(0, 1.7, 0) + nrm * 0.02, bas)
	if tin:
		# tin roof, slightly sloped
		_b(bld, "tin", Vector3(center.x, h + 0.08, center.z), Vector3(rc.size.x + 0.5, 0.06, rc.size.y + 0.5), col, Basis(Vector3.RIGHT, 0.06))
		return
	# roof: parapet, stair tower with green tin canopy, water tanks
	var ph := 0.75
	var t := 0.15
	for side in 4:
		var c2 := Vector3.ZERO
		var sz2 := Vector3.ZERO
		match side:
			0:
				c2 = Vector3(center.x, h + ph * 0.5, rc.position.y + t * 0.5)
				sz2 = Vector3(rc.size.x, ph, t)
			1:
				c2 = Vector3(center.x, h + ph * 0.5, rc.end.y - t * 0.5)
				sz2 = Vector3(rc.size.x, ph, t)
			2:
				c2 = Vector3(rc.position.x + t * 0.5, h + ph * 0.5, center.z)
				sz2 = Vector3(t, ph, rc.size.y)
			3:
				c2 = Vector3(rc.end.x - t * 0.5, h + ph * 0.5, center.z)
				sz2 = Vector3(t, ph, rc.size.y)
		_b(bld, mat, c2, sz2, col)
		_col(body, c2, sz2)
	if rc.size.x > 5.0 and rc.size.y > 5.0:
		var back := Vector3.ZERO
		if not faces.is_empty():
			back = -(faces[0] as Vector3)
		var tower := Vector3(center.x + back.x * (rc.size.x * 0.5 - 1.8), h + 1.3, center.z + back.z * (rc.size.y * 0.5 - 1.8))
		_b(bld, mat, tower, Vector3(2.8, 2.6, 2.8), col)
		_col(body, tower, Vector3(2.8, 2.6, 2.8))
		_b(bld, "tin_green" if r.randf() < 0.7 else "tin", tower + Vector3(0, 1.38, 0), Vector3(3.4, 0.07, 3.4), Color(1, 1, 1), Basis(Vector3.RIGHT, 0.08))
		var roof_spawn := tower - back * 2.4 + Vector3(0, -1.2, 0)
		b["roof"] = roof_spawn
		var down := Usable.new()
		down.prompt = "সিঁড়ি দিয়ে নিচে নামুন"
		node.add_child(down)
		down.global_position = tower - back * 1.5 + Vector3(0, -1.3, 0)
		down.on_use = func(p: Node) -> void: _teleport(p, b.get("door", roof_spawn) as Vector3 + (faces[0] as Vector3 if not faces.is_empty() else Vector3.ZERO) * 1.2)
		for kt in r.randi_range(1, 3):
			var tp := Vector3(center.x + r.randf_range(-rc.size.x * 0.3, rc.size.x * 0.3), h, center.z + r.randf_range(-rc.size.y * 0.3, rc.size.y * 0.3))
			if tp.distance_to(Vector3(tower.x, h, tower.z)) > 2.6:
				bld.inst("tank", Transform3D(Basis(), tp), Color.WHITE)
				_col(body, tp + Vector3(0, 1.0, 0), Vector3(1.1, 2.0, 1.1))
	b["roof_y"] = h

func _window(bld: Builder, pos: Vector3, nrm: Vector3, bas: Basis, r: RandomNumberGenerator, wall: Color) -> void:
	bld.inst("glass", Transform3D(bas, pos + nrm * 0.02), Color(r.randf_range(0.6, 1.0), r.randf_range(0.5, 0.8), r.randf_range(0.3, 0.6), 1.0 if r.randf() < 0.3 else 0.0))
	bld.inst("frame", Transform3D(bas, pos + nrm * 0.02), Color(0.85, 0.85, 0.86) if r.randf() < 0.7 else Color(0.3, 0.25, 0.2))
	if _low:
		return
	if r.randf() < 0.85:
		var gc: Color = [Color(0.08, 0.08, 0.09), Color(0.15, 0.32, 0.22), Color(0.9, 0.9, 0.88), Color(0.4, 0.15, 0.1)][r.randi() % 4]
		bld.inst("grill", Transform3D(bas, pos + nrm * 0.02), gc)
	bld.inst("chajja", Transform3D(bas, pos + Vector3(0, 1.0, 0) + nrm * 0.02), wall.darkened(0.04))
	if r.randf() < 0.12:
		bld.inst("ac", Transform3D(bas, pos + Vector3(1.0 if r.randf() < 0.5 else -1.0, -0.75, 0) + nrm * 0.02), Color.WHITE)

func _door(bld: Builder, node: Node3D, b: Dictionary, base: Vector3, nrm: Vector3, bas: Basis) -> void:
	# steel gate into the stairwell: dark recess, grill gate, and stairs to the roof
	bld.inst("glass", Transform3D(bas.scaled(Vector3(1.5 / 1.16, 2.4 / 1.36, 1.0)), base + Vector3(0, 1.2, 0) + nrm * 0.01), Color(0.1, 0.1, 0.1, 0.0))
	bld.inst("grill", Transform3D(bas.scaled(Vector3(1.1, 1.5, 0.2)), base + Vector3(0, 1.2, 0) + nrm * 0.02), Color(0.12, 0.14, 0.15))
	var door := base + nrm * 1.0 + Vector3(0, 0.15, 0)
	b["door"] = door
	var up := Usable.new()
	up.prompt = "সিঁড়ি দিয়ে ছাদে উঠুন"
	node.add_child(up)
	up.global_position = base + nrm * 0.6 + Vector3(0, 0.2, 0)
	up.on_use = func(p: Node) -> void:
		if b.has("roof"):
			_teleport(p, b["roof"] as Vector3)
		else:
			s.toast("এই ভবনের ছাদের দরজা তালাবদ্ধ", "info")

func _teleport(p: Node, to: Vector3) -> void:
	if s.ui and s.ui.has_method("fade_teleport"):
		s.ui.call("fade_teleport", p, to)
	elif p is Node3D:
		(p as Node3D).global_position = to

func _poster(node: Node3D, pos: Vector3, bas: Basis) -> void:
	var kinds := ["bcs_quiz", "bcs_quiz", "bcs_quiz", "coaching_ad", "home_eco_ad", "govt_notice", "syndicate_code", "missing"]
	var kind: String = kinds[randi() % kinds.size()]
	var p := Poster.new()
	node.add_child(p)
	p.global_transform = Transform3D(bas, pos)
	var texts: Array = s.story.poster_texts(kind)
	var t := str(texts[randi() % texts.size()]) if not texts.is_empty() else ""
	var q: Dictionary = {}
	if kind == "bcs_quiz":
		q = s.qdb.draw(["bcs", "job", "bar"], 2)
	p.setup(s, kind, t, q)

## Half-built concrete frame: columns, slabs and rebar, typical of the city's edges.
func _build_frame(bld: Builder, body: StaticBody3D, rc: Rect2, floors: int, r: RandomNumberGenerator) -> void:
	var built := r.randi_range(1, floors)
	var nx := maxi(2, int(rc.size.x / 4.0) + 1)
	var nz := maxi(2, int(rc.size.y / 4.0) + 1)
	for fl in built:
		var y := fl * STOREY
		_b(bld, "raw", Vector3(rc.get_center().x, y + 0.1, rc.get_center().y), Vector3(rc.size.x, 0.2, rc.size.y), Color(0.82, 0.8, 0.76))
		_col(body, Vector3(rc.get_center().x, y + 0.1, rc.get_center().y), Vector3(rc.size.x, 0.2, rc.size.y))
		for ix in nx:
			for iz in nz:
				var px := lerpf(rc.position.x + 0.3, rc.end.x - 0.3, float(ix) / (nx - 1))
				var pz := lerpf(rc.position.y + 0.3, rc.end.y - 0.3, float(iz) / (nz - 1))
				_b(bld, "raw", Vector3(px, y - STOREY * 0.5, pz), Vector3(0.35, STOREY, 0.35), Color(0.78, 0.76, 0.72))
				_col(body, Vector3(px, y - STOREY * 0.5, pz), Vector3(0.35, STOREY, 0.35))
				if fl == built - 1:
					for rb in 3:
						_b(bld, "plain", Vector3(px + rb * 0.08 - 0.08, y + 1.0, pz), Vector3(0.02, 1.6, 0.02), Color(0.35, 0.2, 0.12))
	# stairs ramp to the first slab
	var ramp_len := sqrt(STOREY * STOREY + 6.0 * 6.0)
	var ang := atan2(STOREY, 6.0)
	var rb2 := Basis(Vector3.RIGHT, ang)
	var rp := Vector3(rc.position.x + 1.2, STOREY * 0.5, rc.get_center().y)
	_b(bld, "raw", rp, Vector3(1.4, 0.2, ramp_len), Color(0.8, 0.78, 0.74), rb2)
	_col(body, rp, Vector3(1.4, 0.2, ramp_len), rb2)

# ---------------------------------------------------------------- street furniture
func _street_furniture(bld: Builder, body: StaticBody3D, node: Node3D, k: Vector2i, f: Rect2, r: RandomNumberGenerator, lamp_list: Array) -> void:
	# poles with lamps along each side, wires between them
	var poles: Array[Vector3] = []
	var step := 24.0
	for side in 4:
		var a := Vector3.ZERO
		var b := Vector3.ZERO
		var out := Vector3.ZERO
		match side:
			0:
				a = Vector3(f.position.x, 0, f.position.y)
				b = Vector3(f.end.x, 0, f.position.y)
				out = Vector3(0, 0, -1)
			1:
				a = Vector3(f.end.x, 0, f.position.y)
				b = Vector3(f.end.x, 0, f.end.y)
				out = Vector3(1, 0, 0)
			2:
				a = Vector3(f.end.x, 0, f.end.y)
				b = Vector3(f.position.x, 0, f.end.y)
				out = Vector3(0, 0, 1)
			3:
				a = Vector3(f.position.x, 0, f.end.y)
				b = Vector3(f.position.x, 0, f.position.y)
				out = Vector3(-1, 0, 0)
		var L := a.distance_to(b)
		var n := maxi(1, int(L / step))
		var side_poles: Array[Vector3] = []
		for q in n + 1:
			var p := a.lerp(b, float(q) / n) + out * 1.6
			p.y = 0.15
			side_poles.append(p)
			if q < n or side == 3:
				var bas := Basis.looking_at(-out, Vector3.UP)
				bld.inst("pole", Transform3D(bas, p), Color.WHITE)
				_col(body, p + Vector3(0, 4.5, 0), Vector3(0.25, 9.0, 0.25))
				var working := r.randf() < 0.72
				bld.inst("lamphead", Transform3D(bas, p), Color(1.0, 0.7, 0.4, 1.0 if working else 0.0))
				lamp_list.append([p + out * 1.35, working])
		# sagging wires between consecutive poles: 3–6 lines each, a tangle near poles
		for q2 in (0 if _low else side_poles.size() - 1):
			var p0 := side_poles[q2]
			var p1 := side_poles[q2 + 1]
			for w in r.randi_range(3, 6):
				var h0 := 7.0 + w * 0.22 + r.randf_range(-0.1, 0.1)
				var h1 := 7.0 + w * 0.22 + r.randf_range(-0.1, 0.1)
				var sag := r.randf_range(0.5, 1.4)
				var lat := r.randf_range(-0.35, 0.35)
				var prev := p0 + Vector3(0, h0, 0) + out.cross(Vector3.UP) * 0.0 + out * lat
				for sgm in range(1, 11):
					var u := float(sgm) / 10.0
					var cur := p0.lerp(p1, u) + out * lat
					cur.y = lerpf(h0, h1, u) - sag * 4.0 * u * (1.0 - u)
					var mid := (prev + cur) * 0.5
					var d := cur - prev
					var bas2 := Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
					_b(bld, "wire", mid, Vector3(0.025, 0.025, d.length() + 0.02), Color.BLACK, bas2)
					prev = cur
		poles.append_array(side_poles)
	# cross-street banner on main roads
	if posmod(k.y, 3) == 0 and r.randf() < 0.5:
		var bx := f.get_center().x
		var z0 := f.position.y - 1.6
		var z1 := z0 - street_w(k.y) + 3.2
		var bc := Vector3(bx, 5.2, (z0 + z1) * 0.5)
		_b(bld, "plain", bc, Vector3(4.8, 0.9, 0.03), Color(0.95, 0.92, 0.85))
		if _labels_on():
			var lab := Label3D.new()
			lab.text = BANNERS[r.randi() % BANNERS.size()]
			lab.font = BnText.font(true)
			lab.font_size = 110
			lab.pixel_size = 0.0035
			lab.modulate = Color(0.75, 0.08, 0.08)
			lab.double_sided = true
			lab.visibility_range_end = 90.0
			node.add_child(lab)
			lab.global_position = bc + Vector3(0, 0, 0.03)
	# trees, rickshaws, brick piles
	if r.randf() < float(st["trees"]) * 3.0:
		for t in r.randi_range(1, 3):
			var tp := Vector3(lerpf(f.position.x, f.end.x, r.randf()), 0.15, f.end.y + 1.0)
			bld.inst("tree", Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * r.randf_range(0.8, 1.3)), tp))
			_col(body, tp + Vector3(0, 1.5, 0), Vector3(0.35, 3.0, 0.35))
	for rk in r.randi_range(0, 3):
		var rp := Vector3(lerpf(f.position.x + 3, f.end.x - 3, r.randf()), 0.0, f.position.y - 3.2 - r.randf() * 0.6)
		bld.inst("rickshaw", Transform3D(Basis(Vector3.UP, PI * 0.5 + r.randf_range(-0.3, 0.3)), rp), Color.WHITE)
		_col(body, rp + Vector3(0, 0.8, 0), Vector3(1.6, 1.6, 1.1))
	for bp in r.randi_range(1, 1 if _low else 2):
		var pp := Vector3(f.position.x - 1.0, 0.15, lerpf(f.position.y + 4, f.end.y - 4, r.randf()))
		for bk in (2 if _low else 4):
			var pk := Pickup.new()
			node.add_child(pk)
			pk.global_position = pp + Vector3(r.randf_range(-0.4, 0.4), 0.0, r.randf_range(-0.4, 0.4))
			pk.setup(s, "brick", true)

# ---------------------------------------------------------------- special fronts (POIs placed on footpaths)
func _special_fronts(bld: Builder, body: StaticBody3D, node: Node3D, k: Vector2i, f: Rect2, _r: RandomNumberGenerator) -> void:
	for name in pois.keys():
		var p: Vector3 = pois[name]
		if block_of(p) != k:
			continue
		match str(name):
			"tea_stall":
				_b(bld, "plain", p + Vector3(0, 0.55, -0.6), Vector3(2.2, 1.1, 0.8), Color(0.35, 0.22, 0.12))
				_col(body, p + Vector3(0, 0.55, -0.6), Vector3(2.2, 1.1, 0.8))
				_b(bld, "awning", p + Vector3(0, 2.5, -0.2), Vector3(3.0, 0.05, 2.0), Color.WHITE, Basis(Vector3.RIGHT, -0.15))
				for bx: float in [-1.2, 1.2]:
					_b(bld, "plain", p + Vector3(bx, 0.25, 1.2), Vector3(1.4, 0.08, 0.35), Color(0.4, 0.28, 0.15))
				_b(bld, "plain", p + Vector3(0.6, 1.25, -0.6), Vector3(0.25, 0.3, 0.25), Color(0.6, 0.6, 0.62))
				if s.atmo:
					s.atmo.add_smoke(p + Vector3(0.6, 1.4, -0.6), 0.4, 3.0)
			"bus_stand":
				_b(bld, "plain", p + Vector3(0, 1.3, -0.4), Vector3(3.0, 2.6, 1.4), Color(0.85, 0.75, 0.2))
				_col(body, p + Vector3(0, 1.3, -0.4), Vector3(3.0, 2.6, 1.4))
				_label(node, "বাস কাউন্টার: যাত্রাবাড়ী–কাজলা–চট্টগ্রাম রোড", p + Vector3(0, 2.8, 0.31), Color(0.1, 0.1, 0.1))
			"safehouse":
				_build_safehouse(bld, body, node, p)
			"printing", "coaching", "bank", "hospital":
				var title := {"printing": "রহমান প্রিন্টিং প্রেস (স্থাপিত ১৯৭৪)", "coaching": "সাত দিনে ক্যাডার কোচিং সেন্টার",
					"bank": "প্রথম জনতা ব্যাংক লিমিটেড", "hospital": "সনটেক সিটি জেনারেল হাসপাতাল"}
				_b(bld, "paint", p + Vector3(0, 4.2, -1.75), Vector3(6.5, 1.0, 0.2), Color(0.1, 0.25, 0.5) if name != "hospital" else Color(0.85, 0.1, 0.1))
				_label(node, str(title[name]), p + Vector3(0, 4.2, -1.6), Color(1, 1, 1))
				if name == "hospital":
					for bi in 3:
						var bed := p + Vector3(-3.0 + bi * 3.0, 0.15, 2.4)
						_b(bld, "plain", bed + Vector3(0, 0.45, 0), Vector3(0.9, 0.12, 2.0), Color(0.9, 0.92, 0.95))
						_b(bld, "plain", bed + Vector3(0, 0.22, 0), Vector3(0.85, 0.44, 1.9), Color(0.5, 0.55, 0.6))

## Shop/banner text is a lot of extra draw calls; LOW skips it and keeps the painted boards.
func _labels_on() -> bool:
	return not _low

func _label(node: Node3D, text: String, pos: Vector3, c: Color) -> Label3D:
	if not _labels_on():
		return null
	var l := Label3D.new()
	l.text = text
	l.font = BnText.font(true)
	l.font_size = 96
	l.pixel_size = 0.004
	l.modulate = c
	l.visibility_range_end = 90.0
	node.add_child(l)
	l.global_position = pos
	return l

## Sakib's ground-floor room: open doorway, bed (sleep until dawn), desk, books, a fan.
func _build_safehouse(bld: Builder, body: StaticBody3D, node: Node3D, door: Vector3) -> void:
	var rc := safehouse_room
	var c := Vector3(rc.get_center().x, 0, rc.get_center().y)
	var wall := Color("#efe3c4")
	var H := 3.0
	_b(bld, "checker", Vector3(c.x, 0.17, c.z), Vector3(rc.size.x, 0.04, rc.size.y), Color.WHITE)
	_b(bld, "plaster", Vector3(c.x, H + 0.1, c.z), Vector3(rc.size.x + 0.4, 0.2, rc.size.y + 0.4), wall)
	_col(body, Vector3(c.x, H + 0.1, c.z), Vector3(rc.size.x + 0.4, 0.2, rc.size.y + 0.4))
	var walls := [[Vector3(c.x, H * 0.5, rc.position.y), Vector3(rc.size.x, H, 0.2)], [Vector3(rc.position.x, H * 0.5, c.z), Vector3(0.2, H, rc.size.y)],
		[Vector3(rc.end.x, H * 0.5, c.z), Vector3(0.2, H, rc.size.y)],
		[Vector3(rc.position.x + 1.25, H * 0.5, rc.end.y), Vector3(2.5, H, 0.2)], [Vector3(rc.end.x - 1.25, H * 0.5, rc.end.y), Vector3(2.5, H, 0.2)],
		[Vector3(c.x, H - 0.4, rc.end.y), Vector3(1.0, 0.8, 0.2)]]
	for w in walls:
		var wa: Array = w
		_b(bld, "plaster", wa[0], wa[1], wall)
		_col(body, wa[0], wa[1])
	var bed := Vector3(rc.position.x + 1.1, 0.15, rc.position.y + 1.4)
	_b(bld, "plain", bed + Vector3(0, 0.3, 0), Vector3(1.6, 0.4, 2.1), Color(0.4, 0.28, 0.18))
	_b(bld, "plain", bed + Vector3(0, 0.55, 0.1), Vector3(1.5, 0.12, 1.9), Color(0.75, 0.82, 0.92))
	_b(bld, "plain", bed + Vector3(0, 0.66, -0.75), Vector3(1.2, 0.12, 0.4), Color(0.95, 0.95, 0.95))
	var desk := Vector3(rc.end.x - 1.0, 0.15, rc.position.y + 1.2)
	_b(bld, "plain", desk + Vector3(0, 0.75, 0), Vector3(1.4, 0.06, 0.8), Color(0.45, 0.3, 0.18))
	for bi in 6:
		_b(bld, "plain", desk + Vector3(-0.5 + bi * 0.17, 0.92, -0.2), Vector3(0.12, 0.3, 0.22), Color.from_hsv(bi * 0.15, 0.6, 0.6))
	var desk_label := _label(node, "সংবিধান • দণ্ডবিধি • সাক্ষ্য আইন • বিসিএস ডাইজেস্ট", desk + Vector3(0, 1.25, -0.39), Color(0.1, 0.1, 0.1))
	if desk_label:
		desk_label.pixel_size = 0.0015
	var sleep := Usable.new()
	sleep.prompt = "ঘুমান (ভোর পর্যন্ত, সংরক্ষণ হবে)"
	node.add_child(sleep)
	sleep.global_position = bed + Vector3(0.9, 0.3, 0)
	sleep.on_use = func(_p: Node) -> void:
		if s.main:
			s.main.call("sleep_until_morning")
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.light_energy = 1.4
	lamp.omni_range = 6.0
	node.add_child(lamp)
	lamp.global_position = c + Vector3(0, 2.6, 0)

func _build_square(bld: Builder, body: StaticBody3D, node: Node3D, f: Rect2, r: RandomNumberGenerator) -> void:
	_b(bld, "footpath", Vector3(f.get_center().x, 0.075, f.get_center().y), Vector3(f.size.x, 0.15, f.size.y), Color.WHITE)
	_col(body, Vector3(f.get_center().x, 0.075, f.get_center().y), Vector3(f.size.x, 0.15, f.size.y))
	var stage := Vector3(f.get_center().x, 0.6, f.position.y + 6.0)
	_b(bld, "plain", stage, Vector3(10.0, 0.9, 4.0), Color(0.5, 0.3, 0.2))
	_col(body, stage, Vector3(10.0, 0.9, 4.0))
	_b(bld, "plain", stage + Vector3(0, 2.8, -1.8), Vector3(10.0, 3.6, 0.1), Color(0.9, 0.85, 0.75))
	_label(node, "শাহবাগ–টিএসসি গণমঞ্চ: যুক্তির লড়াই", stage + Vector3(0, 3.2, -1.7), Color(0.6, 0.05, 0.05))
	for t in 8:
		var tp := Vector3(lerpf(f.position.x + 3, f.end.x - 3, r.randf()), 0.15, lerpf(f.position.y + 12, f.end.y - 3, r.randf()))
		bld.inst("tree", Transform3D(Basis(Vector3.UP, r.randf() * TAU), tp))
		_col(body, tp + Vector3(0, 1.5, 0), Vector3(0.35, 3.0, 0.35))
	_poster(node, stage + Vector3(-4.0, 1.4, -1.74), Basis())
	_poster(node, stage + Vector3(4.0, 1.4, -1.74), Basis())

func _build_market(bld: Builder, body: StaticBody3D, node: Node3D, f: Rect2, r: RandomNumberGenerator) -> void:
	_b(bld, "footpath", Vector3(f.get_center().x, 0.075, f.get_center().y), Vector3(f.size.x, 0.15, f.size.y), Color(0.85, 0.82, 0.78))
	_col(body, Vector3(f.get_center().x, 0.075, f.get_center().y), Vector3(f.size.x, 0.15, f.size.y))
	for row in 4:
		for col in 5:
			var p := Vector3(f.position.x + 6 + col * (f.size.x - 12) / 4.0, 0.15, f.position.y + 8 + row * (f.size.y - 16) / 3.0)
			bld.inst("stall", Transform3D(Basis(Vector3.UP, (PI if row % 2 else 0.0)), p))
			_col(body, p + Vector3(0, 0.45, 0), Vector3(2.4, 0.9, 1.4))
	_label(node, "নীলক্ষেত বই ও গাইড বাজার", Vector3(f.get_center().x, 4.0, f.end.y + 0.5), Color(0.9, 0.85, 0.2))

func _build_den(bld: Builder, body: StaticBody3D, node: Node3D, f: Rect2, _r: RandomNumberGenerator) -> void:
	# walled godown compound with a gate on the south side and an open-fronted shed
	var wall := Color(0.62, 0.58, 0.52)
	var H := 3.2
	var c := f.get_center()
	_b(bld, "concrete", Vector3(c.x, 0.05, c.y), Vector3(f.size.x, 0.1, f.size.y), Color(0.7, 0.68, 0.62))
	var segs := [[Vector3(c.x, H * 0.5, f.position.y), Vector3(f.size.x, H, 0.3)], [Vector3(f.position.x, H * 0.5, c.y), Vector3(0.3, H, f.size.y)],
		[Vector3(f.end.x, H * 0.5, c.y), Vector3(0.3, H, f.size.y)],
		[Vector3(f.position.x + (f.size.x * 0.5 - 2.5) * 0.5, H * 0.5, f.end.y), Vector3(f.size.x * 0.5 - 2.5, H, 0.3)],
		[Vector3(f.end.x - (f.size.x * 0.5 - 2.5) * 0.5, H * 0.5, f.end.y), Vector3(f.size.x * 0.5 - 2.5, H, 0.3)]]
	for sgm in segs:
		var sa: Array = sgm
		_b(bld, "brick", sa[0], sa[1], wall)
		_col(body, sa[0], sa[1])
	var shed := Vector3(c.x, 0, f.position.y + 9.0)
	_b(bld, "tin", shed + Vector3(0, 6.2, 0), Vector3(f.size.x - 6.0, 0.1, 14.0), Color(0.7, 0.7, 0.72), Basis(Vector3.RIGHT, 0.05))
	for px in 5:
		var pp := shed + Vector3(-(f.size.x - 8.0) * 0.5 + px * (f.size.x - 8.0) / 4.0, 3.1, 6.5)
		_b(bld, "concrete", pp, Vector3(0.4, 6.2, 0.4), Color(0.7, 0.7, 0.68))
		_col(body, pp, Vector3(0.4, 6.2, 0.4))
	_b(bld, "brick", shed + Vector3(0, 3.1, -7.0), Vector3(f.size.x - 6.0, 6.2, 0.3), wall)
	_col(body, shed + Vector3(0, 3.1, -7.0), Vector3(f.size.x - 6.0, 6.2, 0.3))
	for cr in 10:
		var cp := shed + Vector3(randf_range(-12, 12), 0.6, randf_range(-5, 4))
		_b(bld, "plain", cp, Vector3(1.2, 1.2, 1.2), Color(0.55, 0.42, 0.28))
		_col(body, cp, Vector3(1.2, 1.2, 1.2))
	_label(node, "মেসার্স 'ম' ট্রেডার্স (গুদাম)", Vector3(c.x, 3.8, f.end.y + 0.2), Color(0.9, 0.9, 0.9))

## Sarbangin Bhaban: nine storeys with real floors, a stair ramp core and an open roof for the finale.
func _build_tower(bld: Builder, body: StaticBody3D, node: Node3D, _f: Rect2, _r: RandomNumberGenerator) -> void:
	var rc: Rect2 = tower_info["rect"]
	var floors := int(tower_info["floors"])
	var fh := 3.4
	var c := Vector3(rc.get_center().x, 0, rc.get_center().y)
	var col := Color("#e8dcc6")
	var t := 0.3
	var top := floors * fh
	# outer walls with a ground-floor door gap on the south face
	_b(bld, "plaster", Vector3(c.x, top * 0.5, rc.position.y), Vector3(rc.size.x, top, t), col)
	_col(body, Vector3(c.x, top * 0.5, rc.position.y), Vector3(rc.size.x, top, t))
	for sx: float in [-1.0, 1.0]:
		_b(bld, "plaster", Vector3(c.x + sx * rc.size.x * 0.5, top * 0.5, c.z), Vector3(t, top, rc.size.y), col)
		_col(body, Vector3(c.x + sx * rc.size.x * 0.5, top * 0.5, c.z), Vector3(t, top, rc.size.y))
		var seg_w := rc.size.x * 0.5 - 1.5
		_b(bld, "plaster", Vector3(c.x + sx * (1.5 + seg_w * 0.5), top * 0.5, rc.end.y), Vector3(seg_w, top, t), col)
		_col(body, Vector3(c.x + sx * (1.5 + seg_w * 0.5), top * 0.5, rc.end.y), Vector3(seg_w, top, t))
	_b(bld, "plaster", Vector3(c.x, (top + 3.0) * 0.5, rc.end.y), Vector3(3.0, top - 3.0, t), col)
	_col(body, Vector3(c.x, (top + 3.0) * 0.5, rc.end.y), Vector3(3.0, top - 3.0, t))
	# floors with a stairwell opening on the west side, and ramps zig-zagging up the core
	var well := Rect2(rc.position.x + 0.4, rc.position.y + 0.4, 4.0, 12.0)
	for fl in range(1, floors + 1):
		var y := fl * fh
		var sm_w := maxf(0.0, rc.end.x - well.end.x)
		var slab_main := Rect2(well.end.x, rc.position.y, sm_w, rc.size.y)
		_b(bld, "concrete", Vector3(slab_main.get_center().x, y, slab_main.get_center().y), Vector3(slab_main.size.x, 0.25, slab_main.size.y), Color(0.85, 0.83, 0.8))
		_col(body, Vector3(slab_main.get_center().x, y, slab_main.get_center().y), Vector3(slab_main.size.x, 0.25, slab_main.size.y))
		var rest_w := maxf(0.0, well.end.x - rc.position.x)
		var rest_h := maxf(0.0, rc.end.y - well.end.y)
		var rest := Rect2(rc.position.x, well.end.y, rest_w, rest_h)
		_b(bld, "concrete", Vector3(rest.get_center().x, y, rest.get_center().y), Vector3(rest.size.x, 0.25, rest.size.y), Color(0.85, 0.83, 0.8))
		_col(body, Vector3(rest.get_center().x, y, rest.get_center().y), Vector3(rest.size.x, 0.25, rest.size.y))
		# ramp from the floor below up to this floor, alternating direction
		var y0 := y - fh
		var dir := 1.0 if fl % 2 == 1 else -1.0
		var L := well.size.y - 1.0
		var ang := atan2(fh, L) * dir
		var rb := Basis(Vector3.RIGHT, -ang)
		var rp := Vector3(well.get_center().x, y0 + fh * 0.5 + 0.05, well.get_center().y)
		_b(bld, "concrete", rp, Vector3(well.size.x - 0.4, 0.2, sqrt(L * L + fh * fh)), Color(0.7, 0.68, 0.64), rb)
		_col(body, rp, Vector3(well.size.x - 0.4, 0.2, sqrt(L * L + fh * fh)), rb)
		# windows on the outside and a per-floor sign
		for wx in 6:
			var wp := Vector3(rc.position.x + 3.0 + wx * 4.0, y0 + 1.7, rc.end.y + 0.16)
			bld.inst("glass", Transform3D(Basis(), wp), Color(1.0, 0.8, 0.5, 1.0 if fl % 3 == 0 else 0.0))
			bld.inst("frame", Transform3D(Basis(), wp), Color(0.85, 0.85, 0.85))
		var names := ["", "ভর্তি অফিস", "সার্টিফিকেট প্রিন্টিং কক্ষ", "'ক্লিনিক্যাল' ফটোশুট স্টুডিও", "মক-ওয়ার্ড (ডামি রোগী)", "ডায়েট চার্ট কল সেন্টার", "ক্যাফে 'জিরা পানি'", "বোর্ডরুম", "অপঠিত লাইব্রেরি", "অধ্যক্ষের কক্ষ"]
		if _labels_on():
			_label(node, "%s তলা: %s" % [BnText.num(fl), names[fl]], Vector3(c.x + 4.0, y0 + 2.7, c.z - rc.size.y * 0.5 + 0.4), Color(0.1, 0.1, 0.1))
		for d in 4:
			var dp := Vector3(c.x + randf_range(-6, 8), y0 + 0.6, c.z + randf_range(-6, 6))
			_b(bld, "plain", dp, Vector3(1.4, 0.8, 0.7), Color(0.45, 0.32, 0.2))
			_col(body, dp, Vector3(1.4, 0.8, 0.7))
	# roof: parapet, green tin canopy, tanks
	for side in 4:
		var cc: Vector3 = [Vector3(c.x, top + 0.45, rc.position.y), Vector3(c.x, top + 0.45, rc.end.y), Vector3(rc.position.x, top + 0.45, c.z), Vector3(rc.end.x, top + 0.45, c.z)][side]
		var sz: Vector3 = [Vector3(rc.size.x, 0.9, 0.2), Vector3(rc.size.x, 0.9, 0.2), Vector3(0.2, 0.9, rc.size.y), Vector3(0.2, 0.9, rc.size.y)][side]
		_b(bld, "plaster", cc, sz, col)
		_col(body, cc, sz)
	_b(bld, "tin_green", Vector3(well.get_center().x, top + 2.8, well.get_center().y), Vector3(5.0, 0.08, 13.0), Color.WHITE, Basis(Vector3.RIGHT, 0.06))
	for tk in 3:
		bld.inst("tank", Transform3D(Basis(), Vector3(rc.end.x - 2.0, top, rc.position.y + 3 + tk * 2.2)), Color.WHITE)
	_label(node, "সর্বাঙ্গীণ ভবন • আমরাই ঢাবি (অধিভুক্ত)", Vector3(c.x, 5.0, rc.end.y + 0.25), Color(0.6, 0.05, 0.05))
