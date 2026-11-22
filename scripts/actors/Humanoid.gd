class_name Humanoid
extends Node3D
## Procedural Dhaka citizen: sculpted body, face, hair, clothing and a layered animator.
## No imported models or animation files.
##
## Body   Every limb, the torso and the head are lofted meshes: elliptical cross-sections with
##        tapering, calf and chest bulges and UVs. Geometry is merged per joint (one mesh, one
##        surface per material slot) and cached by body type, so a crowd of 40 shares about
##        a dozen meshes.
## Face   Eye whites, irises and pupils that track targets, eyelids that blink and narrow,
##        brows for expressions, a lofted nose, a jaw-driven lower lip for lip-sync, ears.
## Hair   Short, side-part, long, bun, bald with fringe, hijab, white tupi; beard, stubble,
##        moustache; greying with age.
## Cloth  Lungi with a gamchha, panjabi and pajama, shirt and trousers, T-shirt and jeans, suit,
##        lawyer's coat and bands, lab coat, police and guard uniforms, saree with pallu,
##        salwar-kameez with dupatta, Syndicate goon with a bandana. Textured with the procedural
##        fabric sets and tinted per character.
## Motion Velocity-matched walk/run with heel-toe, pelvis tilt, counter-rotation and head
##        stabilisation. Age changes the gait. Acceleration lean, turn banking. Keyframed
##        clips with anticipation and overshoot. Weighted sustained poses. Talk gestures,
##        look-at, a hit spring, landing squash, skirt sway and a verlet dupatta/gamchha.
## Faces −Z. Height is a uniform scale.

## Albedo skin tones calibrated from the two reference portraits (lit photo values brought down to
## albedo), plus neighbours for variety across the city.
const SKIN_TONES: Array[Color] = [Color("#c49a80"), Color("#b98e74"), Color("#b07a5c"), Color("#a46d50"), Color("#94603f"), Color("#c8a084"), Color("#8a5838"), Color("#d0a78a"), Color("#a87358")]
const SUSTAINS: Array[String] = ["crouch", "block", "sit", "phone", "down", "kneel", "cower", "aim", "carry", "float", "read", "march", "hands_up", "type", "lean_wall", "beg"]
const TEX := "res://assets/textures/%s/%s_%s.png"

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}
## LOW quality: fewer face parts, no cast shadows, and a much smaller mesh-cache key space
## (beards/glasses/gamchha/face variants are dropped) so crowds share geometry.
static var low_quality := false

var look: Dictionary = {}
var h := 1.0
var female := false
var age := 0.3
var build := 0.5
var ghost := false

# joints
var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var sh_l: Node3D
var sh_r: Node3D
var el_l: Node3D
var el_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var foot_l: Node3D
var foot_r: Node3D
var skirt: Node3D
var joints: Dictionary = {}
var mesh_nodes: Array[MeshInstance3D] = []

# face
var eye_l: Node3D
var eye_r: Node3D
var lid_l: MeshInstance3D
var lid_r: MeshInstance3D
var brow_l: MeshInstance3D
var brow_r: MeshInstance3D
var lower_lip: MeshInstance3D      # mouth opening (lip-sync)
var _brow_base := -1.0
var prop_r: Node3D           # held item in right hand (book, brick, phone)
var prop_l: Node3D

# animation state
var t := 0.0
var phase := 0.0
var clip := ""
var clip_t := 0.0
var _clip_keys: Array = []
var _clip_len := 0.0
var _clip_speed := 1.0
var _clip_done: Callable
var sustain: Dictionary = {}
var _w: Dictionary = {}
var look_target: Variant = null
var talking := false
var expression := "neutral"
var _blink_t := 2.0
var _blink := 0.0
var _gesture_t := 1.0
var _gesture := ""
var _hit := Vector3.ZERO
var _hit_v := Vector3.ZERO
var _squash := 0.0
var _squash_v := 0.0
var _skirt_rot := Vector3.ZERO
var _skirt_v := Vector3.ZERO
var _last_vel := Vector3.ZERO
var _lean := Vector3.ZERO
var _yaw_rate := 0.0
var _last_yaw := 0.0
var roll_angle := 0.0
var _rest_hips_y := 0.93
var _scarf: Array[MeshInstance3D] = []
var _scarf_pts: Array[Vector3] = []
var _scarf_prev: Array[Vector3] = []
var _ghost_mat: StandardMaterial3D
var lod_far := false

# ============================================================================ build
func setup(cfg: Dictionary) -> void:
	look = cfg
	female = str(cfg.get("sex", "m")) == "f"
	age = float(cfg.get("age", 0.3))
	build = round(float(cfg.get("build", randf_range(0.2, 0.8))) * 2.0) / 2.0
	if low_quality:
		build = 0.5      # one body shape means far fewer generated meshes / spawn hitches
	h = float(cfg.get("height", (0.94 if female else 1.0) * randf_range(0.96, 1.04) * lerpf(1.0, 0.97, age)))
	ghost = bool(cfg.get("ghost", false))
	if not cfg.has("face"):
		look["face"] = randi() % 4
	if low_quality:
		# Two skull variants and some facial hair keep the crowd from looking like identical
		# bald masks, while the mesh cache stays tiny (hair is still one mesh per sex).
		look["face"] = randi() % 2
		look["beard"] = ("moustache" if randf() < 0.4 else "none") if not female else "none"
		look["glasses"] = false
		look["gamchha"] = false
		look["hair"] = "long" if female else "short"
	scale = Vector3.ONE * h
	for s in SUSTAINS:
		sustain[s] = 0.0
		_w[s] = 0.0
	_build()
	_blink_t = randf_range(1.0, 4.0)
	phase = randf() * TAU

func _j(parent: Node3D, nm: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = nm
	j.position = pos
	parent.add_child(j)
	joints[nm] = j
	return j

func _build() -> void:
	_rest_hips_y = 0.93
	hips = _j(self, "hips", Vector3(0, _rest_hips_y, 0))
	spine = _j(hips, "spine", Vector3(0, 0.1, 0))
	chest = _j(spine, "chest", Vector3(0, 0.2, 0))
	neck = _j(chest, "neck", Vector3(0, 0.235, 0))
	head = _j(neck, "head", Vector3(0, 0.045, 0))
	var shw := 0.158 if female else 0.178
	sh_l = _j(chest, "sh_l", Vector3(-shw, 0.205, 0.008))
	sh_r = _j(chest, "sh_r", Vector3(shw, 0.205, 0.008))
	el_l = _j(sh_l, "el_l", Vector3(0, -0.28, 0))
	el_r = _j(sh_r, "el_r", Vector3(0, -0.28, 0))
	hand_l = _j(el_l, "hand_l", Vector3(0, -0.255, 0))
	hand_r = _j(el_r, "hand_r", Vector3(0, -0.255, 0))
	var hpw := 0.095 if female else 0.088
	hip_l = _j(hips, "hip_l", Vector3(-hpw, -0.06, 0))
	hip_r = _j(hips, "hip_r", Vector3(hpw, -0.06, 0))
	knee_l = _j(hip_l, "knee_l", Vector3(0, -0.43, 0))
	knee_r = _j(hip_r, "knee_r", Vector3(0, -0.43, 0))
	foot_l = _j(knee_l, "foot_l", Vector3(0, -0.38, 0))
	foot_r = _j(knee_r, "foot_r", Vector3(0, -0.38, 0))
	skirt = _j(hips, "skirt", Vector3(0, 0.04, 0))
	var mats := _slot_materials()
	var parts := _geometry_key()
	for jn: String in ["hips", "spine", "chest", "neck", "head", "sh_l", "sh_r", "el_l", "el_r", "hand_l", "hand_r", "hip_l", "hip_r", "knee_l", "knee_r", "foot_l", "foot_r", "skirt"]:
		var key := parts + "|" + jn
		var entry: Dictionary
		if _mesh_cache.has(key):
			entry = _mesh_cache[key]
		else:
			entry = _build_joint_mesh(jn)
			_mesh_cache[key] = entry
		var mesh: ArrayMesh = entry.get("mesh")
		if mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "m_" + jn
		var slots: Array = entry["slots"]
		for i in slots.size():
			mi.set_surface_override_material(i, _ghost_or(mats.get(str(slots[i]), mats["skin"])))
		if jn == "head" or low_quality:
			# the nose would otherwise self-shadow into a dark blotch at shadow-map resolution
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(joints[jn] as Node3D).add_child(mi)
		mesh_nodes.append(mi)
	_build_face(mats)
	if not low_quality and (bool(look.get("gamchha", false)) or str(look.get("outfit", "")) == "salwar"):
		_build_scarf(mats["gamchha" if bool(look.get("gamchha", false)) else "accent"])
	prop_r = Node3D.new()
	prop_r.position = Vector3(0, -0.075, -0.02)
	hand_r.add_child(prop_r)
	prop_l = Node3D.new()
	prop_l.position = Vector3(0, -0.075, -0.02)
	hand_l.add_child(prop_l)

func _geometry_key() -> String:
	return ("L" if low_quality else "H") + "%s%d%d_%s_%s_%s_%d%d" % ["f" if female else "m", int(round(build * 2.0)), int(look.get("face", 0)), str(look.get("outfit", "shirt_pants")), str(look.get("hair", "short")), str(look.get("beard", "none")), int(bool(look.get("glasses", false))), int(bool(look.get("gamchha", false)))]

# ---------------------------------------------------------------- materials
static func _tex(name: String, kind: String) -> Texture2D:
	var path := TEX % [name, name, kind]
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tx: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex_cache[path] = tx
	return tx

static func cloth_material(tex_name: String, tint: Color, uv: float = 3.0, rough: float = 0.9) -> StandardMaterial3D:
	var key := "%s|%s|%.2f" % [tex_name, tint.to_html(), uv]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	if tex_name != "":
		m.albedo_texture = _tex(tex_name, "albedo")
		var n := _tex(tex_name, "normal")
		if n:
			m.normal_enabled = true
			m.normal_texture = n
			m.normal_scale = 0.8
		m.uv1_scale = Vector3(uv, uv, 1.0)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
	return m

## Hair: dark, slightly glossy, with strand-direction noise from the denim twill normal map.
static func hair_material(c: Color) -> StandardMaterial3D:
	var key := "hair|%s" % c.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.42
	m.normal_enabled = true
	m.normal_texture = _tex("cloth_denim", "normal")
	m.normal_scale = 1.2
	m.uv1_scale = Vector3(6, 14, 1)
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.3
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_mat_cache[key] = m
	return m

## Skin with the painted vertex-colour make-up (lips, cheeks, sockets, brows, stubble), a soft
## sheen and subsurface-like rim so faces read warm rather than plastic.
static func face_material(skin_c: Color) -> StandardMaterial3D:
	var key := "face|%s" % skin_c.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = skin_c
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _tex("skin_detail", "albedo")
	var n := _tex("skin_detail", "normal")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = 0.32
	# Real skin varies in shininess (T-zone vs cheeks); the ORM map supplies that variation.
	var orm := _tex("skin_detail", "orm")
	if orm:
		m.metallic_texture = orm
		m.roughness_texture = orm
		m.metallic = 0.0
		m.roughness = 0.62
	else:
		m.roughness = 0.55
	var ao := _tex("skin_detail", "ao")
	if ao:
		m.ao_enabled = true
		m.ao_texture = ao
		m.ao_light_affect = 0.5
	m.uv1_scale = Vector3(3, 3, 1)
	# A faint rim approximates subsurface scattering on the ears/nose at back-light angles.
	m.rim_enabled = true
	m.rim = 0.22
	m.rim_tint = 0.72
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
	return m

static func plain_material(c: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var key := "plain|%s|%.2f|%.2f" % [c.to_html(), rough, metal]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mat_cache[key] = m
	return m

func _ghost_or(m: Material) -> Material:
	if not ghost:
		return m
	if _ghost_mat == null:
		_ghost_mat = StandardMaterial3D.new()
		_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_mat.albedo_color = Color(0.55, 0.85, 1.0, 0.38)
		_ghost_mat.emission_enabled = true
		_ghost_mat.emission = Color(0.35, 0.75, 1.0)
		_ghost_mat.emission_energy_multiplier = 1.4
		_ghost_mat.rim_enabled = true
		_ghost_mat.rim = 1.0
		_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _ghost_mat

func _c(i: int, fallback: Color) -> Color:
	var cs: Array = look.get("colors", [])
	if i < cs.size():
		return Color(str(cs[i]))
	return fallback

func _slot_materials() -> Dictionary:
	var skin_c: Color = look.get("skin", SKIN_TONES[randi() % SKIN_TONES.size()])
	look["skin"] = skin_c
	var hair_c: Color = Color(0.05, 0.04, 0.035)
	if age > 0.75:
		hair_c = Color(0.78, 0.76, 0.72) if randf() < 0.7 else Color(0.62, 0.25, 0.08)   # grey or henna
	elif age > 0.55:
		hair_c = Color(0.35, 0.33, 0.31)
	look["hair_color"] = hair_c
	var main := _c(0, Color(0.3, 0.35, 0.5))
	var second := _c(1, Color(0.15, 0.15, 0.17))
	var m := {
		"skin": cloth_material("skin_detail", skin_c, 2.0, 0.55),
		"face": face_material(skin_c),
		"hair": hair_material(hair_c),
		"beard": hair_material(hair_c.lerp(Color(0.16, 0.1, 0.08), 0.35)),
		"lip": plain_material(skin_c.darkened(0.25).lerp(Color("#a8504f"), 0.45 if female else 0.2), 0.45),
		"white": cloth_material("cloth_plain", Color(0.96, 0.96, 0.95), 3.0),
		"shoe": plain_material(Color(0.07, 0.06, 0.06), 0.35),
		"sandal": plain_material(Color(0.32, 0.2, 0.12), 0.6),
		"metal": plain_material(Color(0.1, 0.1, 0.1), 0.25, 0.8),
		"gold": plain_material(Color(0.85, 0.65, 0.2), 0.3, 1.0),
		"belt": plain_material(Color(0.12, 0.08, 0.06), 0.45),
		"gamchha": cloth_material("cloth_gamchha", Color.WHITE, 2.0),
		"accent": cloth_material("cloth_plain", second, 3.0),
		"tie": cloth_material("cloth_stripe", second, 4.0),
	}
	var outfit := str(look.get("outfit", "shirt_pants"))
	match outfit:
		"lungi_vest":
			m["top"] = cloth_material("cloth_plain", Color(0.93, 0.92, 0.88), 3.0)
			m["sleeve"] = m["skin"]
			m["skirt"] = cloth_material("cloth_lungi", main.lerp(Color.WHITE, 0.5), 2.0)
			m["pants"] = m["skin"]
			m["shoe"] = m["sandal"]
		"panjabi":
			m["top"] = cloth_material("cloth_plain", main, 3.0)
			m["sleeve"] = m["top"]
			m["skirt"] = m["top"]
			m["pants"] = cloth_material("cloth_plain", Color(0.94, 0.93, 0.9), 3.0)
			m["shoe"] = m["sandal"]
		"tshirt_jeans":
			m["top"] = cloth_material("cloth_plain", main, 3.0)
			m["sleeve"] = m["top"]
			m["pants"] = cloth_material("cloth_denim", Color.WHITE, 2.0)
			m["shoe"] = plain_material(Color(0.85, 0.85, 0.82), 0.6)
		"suit", "coat":
			m["top"] = cloth_material("cloth_wool", main, 3.0, 0.7)
			m["sleeve"] = m["top"]
			m["skirt"] = m["top"]
			m["pants"] = cloth_material("cloth_wool", main.lightened(0.04), 3.0, 0.7)
		"labcoat":
			m["top"] = cloth_material("cloth_plain", Color(0.97, 0.97, 0.98), 3.0)
			m["sleeve"] = m["top"]
			m["skirt"] = m["top"]
			m["pants"] = cloth_material("cloth_plain", second, 3.0)
			m["accent"] = cloth_material("cloth_plain", main, 3.0)
		"uniform_police", "guard":
			m["top"] = cloth_material("cloth_plain", main, 3.0)
			m["sleeve"] = m["top"]
			m["pants"] = cloth_material("cloth_plain", main.darkened(0.15) if outfit == "uniform_police" else second, 3.0)
			m["cap"] = cloth_material("cloth_plain", main.darkened(0.2), 3.0)
		"goon":
			m["top"] = cloth_material("cloth_plain", main, 3.0)
			m["sleeve"] = m["top"]
			m["pants"] = cloth_material("cloth_denim", Color(0.55, 0.55, 0.6), 2.0)
			m["accent"] = cloth_material("cloth_gamchha", second.lerp(Color.WHITE, 0.3), 2.0)
		"saree":
			m["top"] = cloth_material("cloth_plain", second, 3.0)
			m["sleeve"] = m["top"]
			m["skirt"] = cloth_material("cloth_print", main, 2.0)
			m["accent"] = m["skirt"]
			m["pants"] = m["skin"]
			m["shoe"] = m["sandal"]
		"salwar":
			m["top"] = cloth_material("cloth_print", main, 2.5)
			m["sleeve"] = m["top"]
			m["skirt"] = m["top"]
			m["pants"] = cloth_material("cloth_plain", second, 3.0)
			m["accent"] = cloth_material("cloth_plain", second.lightened(0.15), 3.0)
			m["shoe"] = m["sandal"]
		_:
			m["top"] = cloth_material("cloth_check" if randf() < 0.5 else "cloth_stripe", main, 3.0)
			m["sleeve"] = m["top"]
			m["pants"] = cloth_material("cloth_plain", second, 3.0)
	if not m.has("skirt"):
		m["skirt"] = m["top"]
	if not m.has("cap"):
		m["cap"] = m["white"]
	if str(look.get("hair", "")) == "hijab":
		m["hijab"] = cloth_material("cloth_plain", _c(1, Color(0.2, 0.2, 0.3)).lerp(Color.WHITE, 0.15), 3.0)
	else:
		m["hijab"] = m["hair"]
	return m

# ---------------------------------------------------------------- loft geometry
## rings: [[y, rx, rz, zoff=0, xoff=0], ...] along local Y. Elliptical cross-sections from angle
## a0 to a1. Normals from neighbours (outward), UVs tile around and along. Returns one surface.
static func loft(rings: Array, segs: int = 14, cap_lo: bool = true, cap_hi: bool = true, a0: float = 0.0, a1: float = TAU, uvs: float = 5.0) -> ArrayMesh:
	if low_quality:
		segs = mini(segs, 9)
	var closed := absf(a1 - a0 - TAU) < 0.001
	var nr := rings.size()
	var cols := segs + 1
	var pts: Array[Vector3] = []
	var centers: Array[Vector3] = []
	var vlen: Array[float] = []
	var acc := 0.0
	for i in nr:
		var r: Array = rings[i]
		var y := float(r[0])
		var rx := float(r[1])
		var rz := float(r[2])
		var zo := float(r[3]) if r.size() > 3 else 0.0
		var xo := float(r[4]) if r.size() > 4 else 0.0
		var lobe_f := float(r[5]) if r.size() > 5 else 0.0
		var lobe_b := float(r[6]) if r.size() > 6 else 0.0
		centers.append(Vector3(xo, y, zo))
		if i > 0:
			acc += absf(y - float((rings[i - 1] as Array)[0])) + 0.5 * absf(rx - float((rings[i - 1] as Array)[1]))
		vlen.append(acc)
		for j in cols:
			var a := lerpf(a0, a1, float(j) / segs)
			var pz := zo + rz * sin(a)
			if lobe_f != 0.0:
				pz -= lobe_f * (_lobe(a, 1.5 * PI - 0.42, 0.42) + _lobe(a, 1.5 * PI + 0.42, 0.42))
			if lobe_b != 0.0:
				pz += lobe_b * (_lobe(a, 0.5 * PI - 0.5, 0.45) + _lobe(a, 0.5 * PI + 0.5, 0.45))
			pts.append(Vector3(xo + rx * cos(a), y, pz))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var perim := 0.0
	for i in nr:
		var r2: Array = rings[i]
		perim = maxf(perim, PI * (float(r2[1]) + float(r2[2])))
	var urep := maxf(1.0, round(perim * uvs))
	var normals: Array[Vector3] = []
	for i in nr:
		for j in cols:
			var p := pts[i * cols + j]
			var jm := j - 1
			var jp := j + 1
			if closed:
				if jm < 0:
					jm = segs - 1
				if jp > segs:
					jp = 1
			else:
				jm = maxi(jm, 0)
				jp = mini(jp, segs)
			var im := maxi(i - 1, 0)
			var ip := mini(i + 1, nr - 1)
			var du := pts[i * cols + jp] - pts[i * cols + jm]
			var dv := pts[ip * cols + j] - pts[im * cols + j]
			var n := dv.cross(du)
			var radial := p - centers[i]
			radial.y = 0.0
			if n.length() < 1e-6:
				n = radial
			if n.dot(radial) < 0.0:
				n = -n
			normals.append(n.normalized() if n.length() > 1e-6 else Vector3.UP)
	for i in nr:
		for j in cols:
			st.set_normal(normals[i * cols + j])
			st.set_uv(Vector2(float(j) / segs * urep, vlen[i] * uvs))
			st.add_vertex(pts[i * cols + j])
	for i in nr - 1:
		for j in segs:
			var a := i * cols + j
			var b := a + 1
			var c := a + cols
			var d := c + 1
			_tri(st, pts, normals, a, b, c)
			_tri(st, pts, normals, b, d, c)
	var base := nr * cols
	var extra := 0
	if cap_lo:
		_cap(st, rings[0], pts, 0, cols, -1.0 if float((rings[1] as Array)[0]) > float((rings[0] as Array)[0]) else 1.0, base + extra, centers[0])
		extra += 1
	if cap_hi:
		_cap(st, rings[nr - 1], pts, (nr - 1) * cols, cols, 1.0 if float((rings[nr - 1] as Array)[0]) > float((rings[nr - 2] as Array)[0]) else -1.0, base + extra, centers[nr - 1])
	st.generate_tangents()
	return st.commit()

static func _lobe(a: float, centre: float, width: float) -> float:
	var d := wrapf(a - centre, -PI, PI) / width
	return exp(-d * d)

static func _tri(st: SurfaceTool, pts: Array[Vector3], normals: Array[Vector3], a: int, b: int, c: int) -> void:
	var g := (pts[b] - pts[a]).cross(pts[c] - pts[a])
	var n := normals[a] + normals[b] + normals[c]
	if g.length() < 1e-9:
		return
	# Godot treats clockwise triangles as front faces: the right-hand normal must point inward.
	if g.dot(n) > 0.0:
		st.add_index(a)
		st.add_index(c)
		st.add_index(b)
	else:
		st.add_index(a)
		st.add_index(b)
		st.add_index(c)

static func _cap(st: SurfaceTool, _ring: Array, pts: Array[Vector3], start: int, cols: int, dir: float, center_index: int, center: Vector3) -> void:
	var nrm := Vector3(0, dir, 0)
	st.set_normal(nrm)
	st.set_uv(Vector2(0.5, 0.5))
	st.add_vertex(center)
	for j in cols - 1:
		var a := start + j
		var b := start + j + 1
		var g := (pts[a] - center).cross(pts[b] - center)
		if g.dot(nrm) > 0.0:
			st.add_index(center_index)
			st.add_index(b)
			st.add_index(a)
		else:
			st.add_index(center_index)
			st.add_index(a)
			st.add_index(b)

# ---------------------------------------------------------------- sculpted head
## The head is a deformed ellipsoid sampled on a grid, with an anatomical displacement field:
## eye sockets, brow ridge, cheekbones, nose bridge, tip and wings, philtrum, lips, mouth crease,
## nasolabial folds, chin, jaw taper and a cranial bulge. Female and male skulls differ (jaw,
## brow ridge, lip fullness, nose size). Skin shading is painted into vertex colours: lip colour,
## cheek warmth, eye-socket shadow, eyebrow shadow and an optional stubble shadow. Hair, hijab,
## bandana and beard shells are generated from the same surface, so they always sit on the skull.
## face: 0..3 selects small variations of nose width, jaw and cheek fullness.
static var _cur_fem := false
static var _cur_face := 0

const HEAD_CY := 0.119
const HEAD_RY := 0.121

static func _g(x: float, y: float, cx: float, cy: float, sx: float, sy: float) -> float:
	var dx := (x - cx) / sx
	var dy := (y - cy) / sy
	return exp(-(dx * dx + dy * dy))

## Point on the skin surface at angle a (front is a = 1.5 PI) and height y. Returns [point, colour-weights].
static func head_point(a: float, y: float, fem: bool, face: int = 0) -> Vector3:
	var rx := 0.076 if fem else 0.081
	var rz := 0.096 if fem else 0.1
	var u := clampf((y - HEAD_CY) / HEAD_RY, -0.999, 0.999)
	var k := sqrt(1.0 - u * u)
	var x := cos(a) * rx * k
	var z := sin(a) * rz * k
	var fwd := maxf(0.0, -sin(a))
	var back := maxf(0.0, sin(a))
	var jaw_w := (0.8 if fem else 0.82) - 0.03 * float(face % 2)
	# lower face: chin a little forward, jaw tapering, tucked under at the back (neck)
	var low := smoothstep(0.1, -0.005, y)
	x *= 1.0 - low * (1.0 - jaw_w)
	z -= low * fwd * (0.004 if fem else 0.013)
	z *= 1.0 - low * back * 0.3
	# cranium: fuller at the back-top, flatter sides at the temples
	z += back * smoothstep(0.08, 0.22, y) * 0.009
	x *= 1.0 - smoothstep(0.13, 0.2, y) * fwd * 0.06
	# displacement field (outward = towards -Z on the face)
	var ax := absf(x)
	var d := 0.0
	d -= (0.0068 if fem else 0.0085) * _g(ax, y, 0.032, 0.127, 0.016, 0.011)  # eye sockets
	d += (0.0025 if fem else 0.0065) * _g(ax, y, 0.03, 0.149, 0.032, 0.0075)  # brow ridge
	var nose := 1.08 + 0.1 * float(face % 3) - (0.12 if fem else 0.0)
	d += 0.007 * _g(x, y, 0.0, 0.132, 0.006, 0.015) * nose                   # bridge
	d += (0.012 if fem else 0.017) * _g(x, y, 0.0, 0.103, 0.0095 * nose, 0.0105) * nose  # tip
	d += 0.006 * _g(ax, y, 0.0115 * nose, 0.096, 0.0065, 0.0055)              # nostril wings
	d += (0.007 + 0.002 * float(face / 2)) * _g(ax, y, 0.05, 0.108, 0.02, 0.02)   # cheekbones
	d += (0.003 if fem else 0.0035) * _g(x, y, 0.0, 0.0775, 0.019, 0.0045)    # upper lip
	d += (0.0038 if fem else 0.0042) * _g(x, y, 0.0, 0.0625, 0.0165, 0.0055)  # lower lip
	d -= 0.003 * _g(x, y, 0.0, 0.0697, 0.022, 0.002)                         # mouth line
	d -= 0.0025 * _g(ax, y, 0.026, 0.085, 0.006, 0.018)                       # nasolabial folds
	d -= 0.002 * _g(x, y, 0.0, 0.087, 0.004, 0.005)                          # philtrum
	# South Asian epicanthic fold: a small skin fold covering the inner eye corner.
	d += 0.0022 * _g(ax, y, 0.019, 0.131, 0.009, 0.006) * (1.0 - smoothstep(0.022, 0.034, ax))
	# Lower eyelid / eye bag and the tear trough just beneath it.
	d += 0.0016 * _g(ax, y, 0.032, 0.1185, 0.016, 0.004)
	d -= 0.0014 * _g(ax, y, 0.031, 0.112, 0.013, 0.0045)
	# Alar crease curving around the nostril wings, and a temple hollow.
	d -= 0.0016 * _g(ax, y, 0.018, 0.099, 0.006, 0.007)
	d -= 0.0018 * _g(ax, y, 0.062, 0.16, 0.012, 0.024)
	# Mentolabial sulcus (the crease between lower lip and chin).
	d -= 0.0018 * _g(x, y, 0.0, 0.0505, 0.018, 0.0035)
	d += (0.0015 if fem else 0.005) * _g(x, y, 0.0, 0.026, 0.02, 0.012)        # chin
	z -= d * pow(fwd, 1.4)
	return Vector3(x, y, z)

static func _head_colour(p: Vector3, fem: bool, stubble: bool) -> Color:
	var ax := absf(p.x)
	var fwd := clampf(-p.z / 0.09, 0.0, 1.0)
	var c := Color(1, 1, 1)
	var lips_raw := maxf(_g(p.x, p.y, 0.0, 0.0772, 0.0185, 0.0048), _g(p.x, p.y, 0.0, 0.0628, 0.0165, 0.0058)) * fwd
	var lips := smoothstep(0.32, 0.62, lips_raw)
	c = c.lerp(Color(0.74, 0.42, 0.42) if fem else Color(0.74, 0.52, 0.5), lips)
	# crisp shading accents that read at game distance (hand-painted cartoon look)
	c = c.lerp(Color(0.36, 0.2, 0.2), smoothstep(0.45, 0.8, _g(p.x, p.y, 0.0, 0.0697, 0.021, 0.0016) * fwd) * 0.85)    # lip line
	c = c.lerp(Color(0.3, 0.2, 0.18), smoothstep(0.4, 0.75, _g(ax, p.y, 0.0085, 0.0925, 0.0042, 0.0028) * fwd) * 0.8)  # nostrils
	c = c.lerp(Color(0.62, 0.5, 0.46), _g(p.x, p.y, 0.0, 0.088, 0.012, 0.004) * fwd * 0.45)                           # under-nose shadow
	c = c.lerp(Color(0.55, 0.42, 0.4), smoothstep(0.4, 0.8, _g(ax, p.y, 0.033, 0.1385, 0.016, 0.0018) * fwd) * 0.5)    # lid crease
	c = c.lerp(Color(0.7, 0.58, 0.56), _g(ax, p.y, 0.033, 0.116, 0.014, 0.004) * fwd * 0.4)                           # under-eye
	var cheek := _g(ax, p.y, 0.048, 0.095, 0.02, 0.018) * fwd
	c = c.lerp(Color(1.0, 0.82, 0.8), cheek * (0.45 if fem else 0.25))
	var socket := _g(ax, p.y, 0.033, 0.13, 0.02, 0.014) * fwd
	c = c.lerp(Color(0.78, 0.7, 0.68), socket * 0.6)
	var brow := _g(ax, p.y, 0.033, 0.151, 0.022, 0.0042) * fwd
	c = c.lerp(Color(0.28, 0.22, 0.2), brow * (0.55 if fem else 0.75))
	# --- subtle realism: soft T-zone sheen, temple shading and fine skin mottling ---
	c = c.lerp(Color(1.06, 1.02, 0.98), _g(p.x, p.y, 0.0, 0.178, 0.028, 0.022) * fwd * 0.35)  # forehead
	c = c.lerp(Color(0.82, 0.72, 0.7), _g(ax, p.y, 0.062, 0.16, 0.014, 0.026) * fwd * 0.4)      # temples
	c = c.lerp(Color(0.78, 0.66, 0.62), _g(p.x, p.y, 0.0, 0.087, 0.004, 0.005) * fwd * 0.5)      # philtrum
	c = c.lerp(Color(0.74, 0.62, 0.58), _g(ax, p.y, 0.027, 0.083, 0.006, 0.019) * fwd * 0.45)   # nasolabial shadow
	# deterministic micro-variation so large crowds do not look like identical plastic masks
	var mottle := sin(p.x * 731.0 + p.y * 419.0) * sin(p.y * 613.0 - p.x * 227.0)
	c = c.lerp(Color(1.0, 0.97, 0.94), (mottle * 0.5 + 0.5) * 0.06 * fwd)
	if stubble:
		var beard := smoothstep(0.1, 0.07, p.y) * clampf(1.0 - lips * 2.5, 0.0, 1.0) * clampf(fwd + 0.4, 0.0, 1.0)
		beard *= 1.0 - _g(p.x, p.y, 0.0, 0.026, 0.01, 0.01) * 0.3
		c = c.lerp(Color(0.42, 0.4, 0.42), beard * 0.6)
	return c

## Finds the skin point on the face at a given x and height (used to seat eyes, brows, mouth).
static func face_anchor(x_target: float, y: float, fem: bool, face: int) -> Vector3:
	var best := head_point(1.5 * PI, y, fem, face)
	var bd := 1e9
	for i in 61:
		var a := lerpf(PI + 0.2, TAU - 0.2, float(i) / 60.0)
		var p := head_point(a, y, fem, face)
		var d := absf(p.x - x_target)
		if d < bd:
			bd = d
			best = p
	return best

static func head_mesh(fem: bool, face: int, stubble: bool, cols: int = 46, rows: int = 40) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	var nrms: Array[Vector3] = []
	var y0 := HEAD_CY - HEAD_RY * 0.999
	var y1 := HEAD_CY + HEAD_RY * 0.999
	var c1 := cols + 1
	for i in rows:
		var v := float(i) / (rows - 1)
		var y := lerpf(y0, y1, 0.5 - 0.5 * cos(v * PI))   # denser rows near the poles
		for j in c1:
			var a := TAU * float(j) / cols
			pts.append(head_point(a, y, fem, face))
	for i in rows:
		for j in c1:
			var jm := j - 1 if j > 0 else cols - 1
			var jp := j + 1 if j < cols else 1
			var im := maxi(i - 1, 0)
			var ip := mini(i + 1, rows - 1)
			var du := pts[i * c1 + jp] - pts[i * c1 + jm]
			var dv := pts[ip * c1 + j] - pts[im * c1 + j]
			var n := dv.cross(du)
			var radial := pts[i * c1 + j] - Vector3(0, HEAD_CY, 0)
			if n.length() < 1e-7:
				n = radial
			if n.dot(radial) < 0.0:
				n = -n
			nrms.append(n.normalized())
	for i in rows:
		for j in c1:
			var p := pts[i * c1 + j]
			st.set_normal(nrms[i * c1 + j])
			st.set_uv(Vector2(float(j) / cols * 2.0, float(i) / (rows - 1) * 2.0))
			st.set_color(_head_colour(p, fem, stubble))
			st.add_vertex(p)
	for i in rows - 1:
		for j in cols:
			var a := i * c1 + j
			_tri(st, pts, nrms, a, a + 1, a + c1)
			_tri(st, pts, nrms, a + 1, a + c1 + 1, a + c1)
	st.generate_tangents()
	return st.commit()

## Shell over the skull: starts lower at the back (y_back), higher at the front (y_front), puffed
## out by `grow`. Hair, hijab, bandana and beard are all built with it.
static func head_shell(y_front: float, y_back: float, y_top: float, grow: float, segs: int = 22, rows: int = 11, a0: float = 0.0, a1: float = TAU, beard: bool = false, fexp: float = 1.5) -> ArrayMesh:
	if low_quality:
		segs = mini(segs, 14)
		rows = mini(rows, 7)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := segs + 1
	var pts: Array[Vector3] = []
	var nrms: Array[Vector3] = []
	var top := minf(y_top, HEAD_CY + HEAD_RY * 0.995)
	for i in rows:
		var v := float(i) / (rows - 1)
		for j in cols:
			var a := lerpf(a0, a1, float(j) / segs)
			var front := maxf(0.0, -sin(a))
			var yb := lerpf(y_back, y_front, pow(front, fexp))
			var y := lerpf(yb, top, v) if not beard else lerpf(top, yb, v)
			var sp := head_point(a, y, _cur_fem, _cur_face)
			var g := grow * (1.0 - 0.55 * v * v) if not beard else grow * (0.55 + 0.45 * front)
			var c := Vector3(0, HEAD_CY, 0.0)
			var off := sp - c
			off.y *= 0.6
			var p := sp + off.normalized() * g * 0.11
			pts.append(p)
			nrms.append(off.normalized())
	for i in rows:
		for j in cols:
			st.set_normal(nrms[i * cols + j])
			st.set_uv(Vector2(float(j) / segs * 3.0, float(i) / (rows - 1)))
			st.add_vertex(pts[i * cols + j])
	for i in rows - 1:
		for j in segs:
			var a := i * cols + j
			_tri(st, pts, nrms, a, a + 1, a + cols)
			_tri(st, pts, nrms, a + 1, a + cols + 1, a + cols)
	st.generate_tangents()
	return st.commit()

## A draped band (saree pallu, dupatta) around the torso: angle a sweeps left (a=PI) across the front
## (a=1.5PI) to the right (a=2PI); the band's centre height runs from y_left to y_right and sags by
## `sag` at the front.
static func sash(y_left: float, y_right: float, width: float, rx: float, rz: float, zoff: float, a0: float, a1: float, sag: float, segs: int = 16) -> ArrayMesh:
	if low_quality:
		segs = mini(segs, 10)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	var nrms: Array[Vector3] = []
	var cols := segs + 1
	for i in 2:
		for j in cols:
			var a := lerpf(a0, a1, float(j) / segs)
			var u := (cos(a) + 1.0) * 0.5
			var front := maxf(0.0, -sin(a))
			var yc := lerpf(y_left, y_right, u) - sag * front
			var y := yc + (width * 0.5 if i == 1 else -width * 0.5)
			var grow := 1.0 + 0.04 * float(i)
			var p := Vector3(rx * cos(a) * grow, y, zoff + rz * sin(a) * grow)
			pts.append(p)
			nrms.append(Vector3(cos(a), 0.0, sin(a)).normalized())
	for i in 2:
		for j in cols:
			st.set_normal(nrms[i * cols + j])
			st.set_uv(Vector2(float(j) / segs * 2.0, float(i)))
			st.add_vertex(pts[i * cols + j])
	for j in segs:
		_tri(st, pts, nrms, j, j + 1, j + cols)
		_tri(st, pts, nrms, j + 1, j + cols + 1, j + cols)
	st.generate_tangents()
	return st.commit()

static func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)

## Builds the merged mesh for one joint: Array of [slot, mesh, xform] → one ArrayMesh with a
## surface per slot (slots sorted so the order is the same for every character of this type).
func _build_joint_mesh(jn: String) -> Dictionary:
	_cur_fem = female
	_cur_face = int(look.get("face", 0))
	var parts := _parts_for(jn)
	if parts.is_empty():
		return {"mesh": null, "slots": []}
	var groups: Dictionary = {}
	for p in parts:
		var pa: Array = p
		var slot := str(pa[0])
		if not groups.has(slot):
			groups[slot] = []
		(groups[slot] as Array).append(pa)
	var slots := groups.keys()
	slots.sort()
	var out := ArrayMesh.new()
	for slot in slots:
		var st := SurfaceTool.new()
		for pa2 in groups[slot]:
			var arr: Array = pa2
			st.append_from(arr[1] as Mesh, 0, arr[2] as Transform3D)
		st.commit(out)
	return {"mesh": out, "slots": slots}

## Body plan: which lofts go on which joint, in which material slot.
func _parts_for(jn: String) -> Array:
	var P: Array = []
	var outfit := str(look.get("outfit", "shirt_pants"))
	var b := build
	var bw := lerpf(0.9, 1.18, b)            # girth
	var belly := lerpf(0.0, 0.035, clampf((b - 0.5) * 2.0, 0.0, 1.0)) * (0.5 if female else 1.0)
	var long_sleeve := outfit in ["panjabi", "suit", "coat", "labcoat", "uniform_police", "guard", "salwar", "shirt_pants"]
	var bare_arms := outfit == "lungi_vest"
	var skirt_len := 0.0
	var skirt_flare := 1.0
	match outfit:
		"lungi_vest": skirt_len = 0.74
		"panjabi": skirt_len = 0.5
		"labcoat": skirt_len = 0.52
		"salwar": skirt_len = 0.5
		"saree": skirt_len = 0.95
		"suit", "coat": skirt_len = 0.2
	if outfit == "saree":
		skirt_flare = 1.12
	var hair := str(look.get("hair", "short"))
	var beard := str(look.get("beard", "none"))
	match jn:
		"hips":
			var hw := (0.172 if female else 0.148) * bw
			var glute := (0.024 if female else 0.012) * lerpf(0.85, 1.2, b)
			P.append(["skirt" if outfit in ["lungi_vest", "saree"] else "pants",
				loft([[-0.14, hw * 0.78, 0.09 * bw, 0.0, 0.0, 0.0, glute * 0.5], [-0.07, hw, 0.104 * bw, 0.005, 0.0, 0.0, glute], [0.0, hw * 0.98, 0.102 * bw + belly * 0.5, -belly * 0.4, 0.0, 0.0, glute * 0.6], [0.11, hw * 0.86, 0.098 * bw + belly, -belly]], 20), _xf(Vector3.ZERO)])
			if outfit in ["shirt_pants", "uniform_police", "guard", "suit", "coat", "tshirt_jeans", "goon", "labcoat"]:
				P.append(["belt", loft([[0.085, hw * 0.9 + 0.004, 0.1 * bw + belly + 0.004, -belly], [0.115, hw * 0.88 + 0.004, 0.098 * bw + belly + 0.004, -belly]], 16, false, false), _xf(Vector3.ZERO)])
		"spine":
			var ww := (0.118 if female else 0.142) * bw
			P.append(["top", loft([[-0.02, ww * 1.02, 0.096 * bw + belly, -belly], [0.08, ww, 0.094 * bw + belly * 1.2, -belly * 1.2], [0.2, ww * 1.06, 0.1 * bw + belly * 0.6, -belly * 0.5]], 16, false, false), _xf(Vector3.ZERO)])
		"chest":
			var cw := (0.15 if female else 0.172) * lerpf(0.94, 1.1, b)
			var bust := 0.012 if female else 0.0
			var pec := 0.0 if female else 0.007 * lerpf(0.8, 1.3, b)
			var bl := 0.034 * lerpf(0.85, 1.25, b) if female else 0.0
			P.append(["top", loft([[-0.03, cw * 0.84, 0.098 * bw, -0.002], [0.04, cw * 0.93, 0.1 * bw, 0.0, 0.0, bl * 0.35 + pec * 0.3],
				[0.085, cw * 0.99, 0.104 * bw, 0.0, 0.0, bl + pec], [0.13, cw * 1.03, 0.106 * bw, 0.002, 0.0, bl * 0.55 + pec * 0.9],
				[0.18, cw * 1.0, 0.098 * bw, 0.008, 0.0, pec * 0.3], [0.225, cw * 0.78, 0.082, 0.01], [0.255, 0.07, 0.058, 0.01]], 22, false, true), _xf(Vector3.ZERO)])
			# shoulders (deltoid caps) bridge chest and arms
			for sx: float in [-1.0, 1.0]:
				var shw := 0.158 if female else 0.178
				P.append(["sleeve" if not bare_arms else "skin", loft([[-0.07, 0.046, 0.045], [-0.02, 0.05, 0.048], [0.015, 0.042, 0.042], [0.035, 0.012, 0.012]], 12), _xf(Vector3(sx * (shw - 0.012), 0.2, 0.008), Vector3(0, 0, sx * -0.35))])
			if outfit == "lungi_vest":
				for sx2: float in [-1.0, 1.0]:
					P.append(["top", loft([[0.0, 0.013, 0.003], [0.15, 0.011, 0.003]], 6), _xf(Vector3(sx2 * 0.072, 0.075, -0.104 * bw), Vector3(-0.15, 0.0, sx2 * 0.12))])
			if outfit in ["suit", "coat", "labcoat"]:
				# shirt front and lapels
				P.append(["white", loft([[0.12, 0.045, 0.01], [0.27, 0.02, 0.01]], 8), _xf(Vector3(0, 0, -0.106 * bw - 0.004))])
				P.append(["top", loft([[0.08, 0.03, 0.008], [0.27, 0.012, 0.008]], 6), _xf(Vector3(-0.05, 0, -0.108 * bw - 0.006), Vector3(0, 0, -0.25))])
				P.append(["top", loft([[0.08, 0.03, 0.008], [0.27, 0.012, 0.008]], 6), _xf(Vector3(0.05, 0, -0.108 * bw - 0.006), Vector3(0, 0, 0.25))])
				if outfit == "coat":
					for sx3: float in [-1.0, 1.0]:
						P.append(["white", loft([[0.17, 0.008, 0.004], [0.25, 0.012, 0.004]], 6), _xf(Vector3(sx3 * 0.012, 0, -0.112 * bw - 0.006))])
				elif outfit == "suit":
					P.append(["tie", loft([[0.05, 0.022, 0.006], [0.12, 0.018, 0.006], [0.25, 0.01, 0.006]], 6), _xf(Vector3(0, 0, -0.112 * bw - 0.006))])
			if outfit in ["uniform_police", "guard"]:
				for sx4: float in [-1.0, 1.0]:
					P.append(["metal", loft([[0.17, 0.018, 0.004], [0.19, 0.018, 0.004]], 6), _xf(Vector3(sx4 * 0.07, 0, -0.112 * bw))])
			if outfit == "saree":
				# pallu: across the chest from the right waist to the left shoulder, then down the back
				P.append(["accent", sash(0.25, -0.12, 0.15, cw * 1.06, 0.118 * bw + bust * 0.5, -bust * 0.4, PI - 0.15, TAU + 0.1, 0.0), _xf(Vector3.ZERO)])
				P.append(["accent", loft([[-0.45, 0.075, 0.012], [0.24, 0.08, 0.012]], 8), _xf(Vector3(-0.1, 0.0, 0.105 * bw + 0.012))])
			if outfit == "salwar":
				P.append(["accent", sash(0.235, 0.235, 0.075, cw * 1.04, 0.112 * bw + bust * 0.5, -bust * 0.3, PI - 0.4, TAU + 0.4, 0.09), _xf(Vector3.ZERO)])
			if hair == "hijab":
				P.append(["hijab", loft([[0.2, 0.2, 0.13], [0.3, 0.12, 0.1], [0.37, 0.07, 0.075]], 16, false, false), _xf(Vector3(0, 0, 0.005))])
			if bool(look.get("gamchha", false)):
				P.append(["gamchha", loft([[0.0, 0.03, 0.02], [0.08, 0.028, 0.02]], 8), _xf(Vector3(-0.13, 0.27, 0.0), Vector3(0, 0, 0.6))])
		"neck":
			P.append(["skin", loft([[-0.03, 0.05, 0.052, 0.008], [0.03, 0.045, 0.047, 0.006], [0.075, 0.041, 0.045, 0.002]], 12, false, false), _xf(Vector3.ZERO)])
			if long_sleeve and not outfit in ["panjabi", "salwar"]:
				P.append(["white" if outfit in ["suit", "coat"] else "top", loft([[-0.01, 0.058, 0.06, 0.006], [0.035, 0.054, 0.055, 0.006]], 12, false, false), _xf(Vector3.ZERO)])
			if hair == "hijab":
				P.append(["hijab", loft([[-0.04, 0.075, 0.075, 0.005], [0.1, 0.064, 0.07, 0.005]], 14, false, false), _xf(Vector3.ZERO)])
		"head":
			P.append(["face", head_mesh(female, _cur_face, beard == "stubble"), _xf(Vector3.ZERO)])
			# ears: helix rim, lobe and a concave bowl, angled back
			for sx: float in [-1.0, 1.0]:
				var ep := head_point(PI if sx < 0.0 else 0.0, 0.12, female, _cur_face)
				P.append(["skin", loft([[-0.024, 0.005, 0.009, 0.002], [-0.012, 0.007, 0.014], [0.006, 0.009, 0.018], [0.022, 0.008, 0.015, 0.002], [0.03, 0.003, 0.006, 0.004]], 10), _xf(ep + Vector3(sx * 0.004, 0.0, 0.008), Vector3(0.0, sx * 0.25, sx * 0.12))])
			# hair
			match hair:
				"short", "side":
					P.append(["hair", head_shell(0.183, 0.055, 0.263, 0.1 if not female else 0.06), _xf(Vector3.ZERO)])
					if not female:
						P.append(["hair", head_shell(0.2, 0.17, 0.25, 0.16, 22, 6, PI + 0.4, TAU - 0.4), _xf(Vector3(0, 0.004, -0.002))])
				"long":
					P.append(["hair", head_shell(0.19, 0.04, 0.263, 0.08), _xf(Vector3.ZERO)])
					P.append(["hair", loft([[0.17, 0.075, 0.03], [0.0, 0.08, 0.032], [-0.2, 0.07, 0.025], [-0.24, 0.05, 0.015]], 12), _xf(Vector3(0, 0, 0.075))])
				"bun":
					P.append(["hair", head_shell(0.19, 0.05, 0.263, 0.075), _xf(Vector3.ZERO)])
					P.append(["hair", head_shell(0.16, 0.1, 0.2, 0.13, 22, 5, 0.25, PI - 0.25), _xf(Vector3.ZERO)])
					P.append(["hair", loft([[-0.035, 0.02, 0.02], [-0.02, 0.038, 0.035], [0.015, 0.04, 0.036], [0.035, 0.015, 0.015]], 12), _xf(Vector3(0, 0.15, 0.11), Vector3(PI * 0.45, 0, 0))])
				"bald":
					P.append(["hair", head_shell(0.12, 0.06, 0.13, 0.05, 18, 3, 0.15, PI - 0.15), _xf(Vector3.ZERO)])
				"hijab":
					P.append(["hijab", head_shell(0.215, -0.02, 0.265, 0.16), _xf(Vector3.ZERO)])
					P.append(["hijab", head_shell(0.0, -0.02, 0.06, 0.14, 18, 4, 0.35, PI - 0.35), _xf(Vector3.ZERO)])
				"cap_white":
					P.append(["hair", head_shell(0.18, 0.08, 0.2, 0.05), _xf(Vector3.ZERO)])
					P.append(["white", loft([[0.18, 0.084, 0.106, 0.008], [0.23, 0.08, 0.1, 0.01], [0.245, 0.06, 0.08, 0.012]], 18, false, true), _xf(Vector3.ZERO)])
			if outfit in ["uniform_police", "guard"]:
				P.append(["cap", loft([[0.17, 0.086, 0.108, 0.008], [0.25, 0.092, 0.116, 0.01], [0.27, 0.088, 0.112, 0.01]], 18, false, true), _xf(Vector3.ZERO)])
				P.append(["metal", loft([[0.0, 0.08, 0.055], [0.006, 0.08, 0.055]], 14, true, true, PI, TAU), _xf(Vector3(0, 0.172, -0.04))])
			if outfit == "goon":
				P.append(["accent", head_shell(0.2, 0.17, 0.235, 0.09), _xf(Vector3.ZERO)])
			# beard
			match beard:
				"full":
					# full beard as in the male reference: jaw, chin and lower cheeks, lips left clear
					P.append(["beard", head_shell(0.053, 0.135, -0.004, 0.11, 24, 8, PI + 0.12, TAU - 0.12, true, 3.0), _xf(Vector3.ZERO)])
					P.append(["beard", loft([[-0.027, 0.0045, 0.005, 0.0, 0.0], [-0.012, 0.007, 0.007], [0.0, 0.0075, 0.0075], [0.012, 0.007, 0.007], [0.027, 0.0045, 0.005]], 10), _xf(face_anchor(0.0, 0.0835, female, _cur_face) + Vector3(0, 0, -0.003), Vector3(0, 0, PI * 0.5))])
				"moustache":
					P.append(["beard", loft([[-0.025, 0.004, 0.005], [0.0, 0.0065, 0.008], [0.025, 0.004, 0.005]], 8), _xf(face_anchor(0.0, 0.0835, female, _cur_face) + Vector3(0, 0, -0.003), Vector3(0, 0, PI * 0.5))])
			if bool(look.get("glasses", false)):
				for sx: float in [-1.0, 1.0]:
					P.append(["metal", loft([[0.0, 0.019, 0.016], [0.003, 0.019, 0.016]], 14, false, false), _xf(Vector3(sx * 0.034, 0.128, -0.104), Vector3(PI * 0.5, 0, 0))])
					P.append(["metal", loft([[0.0, 0.0025, 0.0025], [0.09, 0.0025, 0.0025]], 5, false, false), _xf(Vector3(sx * 0.074, 0.13, -0.1), Vector3(PI * 0.5, 0, 0))])
				P.append(["metal", loft([[-0.008, 0.002, 0.002], [0.008, 0.002, 0.002]], 5, false, false), _xf(Vector3(0, 0.131, -0.108), Vector3(0, 0, PI * 0.5))])
		"sh_l", "sh_r":
			var aw := (0.046 if female else 0.052) * lerpf(0.9, 1.15, b)
			var slot := "skin" if bare_arms else "sleeve"
			P.append([slot, loft([[0.02, aw * 1.05, aw], [-0.04, aw, aw * 0.96], [-0.15, aw * 0.88, aw * 0.84], [-0.27, aw * 0.74, aw * 0.72], [-0.3, aw * 0.7, aw * 0.68]], 12, false, true), _xf(Vector3.ZERO)])
		"el_l", "el_r":
			var fw := (0.036 if female else 0.04) * lerpf(0.92, 1.12, b)
			var fslot := "sleeve" if long_sleeve else "skin"
			P.append([fslot, loft([[0.03, fw * 0.95, fw * 0.9], [-0.06, fw, fw * 0.92], [-0.2, fw * 0.74, fw * 0.66], [-0.25, fw * 0.62, fw * 0.55]], 12), _xf(Vector3.ZERO)])
			if long_sleeve:
				P.append(["skin", loft([[-0.22, fw * 0.6, fw * 0.52], [-0.26, fw * 0.6, fw * 0.52]], 10, false, true), _xf(Vector3.ZERO)])
		"hand_l", "hand_r":
			var sx := -1.0 if jn == "hand_l" else 1.0
			P.append(["skin", loft([[0.01, 0.022, 0.012], [-0.03, 0.032, 0.014], [-0.07, 0.033, 0.012], [-0.095, 0.027, 0.01], [-0.11, 0.016, 0.008]], 10), _xf(Vector3.ZERO)])
			P.append(["skin", loft([[0.0, 0.011, 0.011], [-0.045, 0.009, 0.009], [-0.06, 0.006, 0.006]], 8), _xf(Vector3(sx * -0.022, -0.02, -0.012), Vector3(-0.5, 0, sx * 0.6))])
		"hip_l", "hip_r":
			var tw := (0.088 if female else 0.082) * lerpf(0.9, 1.18, b)
			var lslot := "skin" if outfit in ["lungi_vest", "saree"] else "pants"
			P.append([lslot, loft([[0.06, tw, tw], [-0.05, tw * 0.98, tw * 0.95], [-0.2, tw * 0.84, tw * 0.8], [-0.38, tw * 0.62, tw * 0.6], [-0.45, tw * 0.56, tw * 0.56]], 12, false, true), _xf(Vector3.ZERO)])
		"knee_l", "knee_r":
			var kw := 0.05 * lerpf(0.92, 1.12, b)
			var loose := 1.25 if outfit in ["panjabi", "salwar"] else 1.0
			var sslot := "skin" if outfit in ["lungi_vest", "saree"] else "pants"
			P.append([sslot, loft([[0.03, kw * loose, kw * loose], [-0.08, kw * 1.02 * loose, kw * 1.06 * loose, 0.008], [-0.19, kw * 0.86 * loose, kw * 0.86 * loose, 0.006], [-0.34, kw * 0.66 * loose, kw * 0.64 * loose], [-0.37, kw * 0.62 * loose, kw * 0.6 * loose]], 12), _xf(Vector3.ZERO)])
		"foot_l", "foot_r":
			var shoe := "shoe"
			P.append([shoe, loft([[-0.055, 0.032, 0.034, 0.0], [0.0, 0.042, 0.044, 0.006], [0.1, 0.046, 0.032, -0.006], [0.18, 0.04, 0.022, -0.014], [0.215, 0.026, 0.014, -0.018]], 12), _xf(Vector3(0, -0.022, 0.0), Vector3(-PI * 0.5, 0, 0))])
		"skirt":
			if skirt_len > 0.0:
				var sw := (0.17 if female else 0.16) * bw * skirt_flare
				var rings: Array = [[0.06, sw * 0.95, 0.11 * bw + belly, -belly]]
				var steps := 4
				for k in range(1, steps + 1):
					var u := float(k) / steps
					var flare := lerpf(1.02, 1.28 if outfit in ["labcoat", "panjabi", "salwar"] else 1.14, u)
					rings.append([0.06 - skirt_len * u, sw * flare, (0.115 * bw + belly * (1.0 - u)) * flare, -belly * (1.0 - u)])
				P.append(["skirt", loft(rings, 18, false, false), _xf(Vector3.ZERO)])
				# inner face so the skirt reads from below
				var inner: Array = []
				for r in rings:
					var ra: Array = r
					inner.append([ra[0], float(ra[1]) * 0.97, float(ra[2]) * 0.97, ra[3]])
				var im := loft(inner, 18, false, false)
				P.append(["skirt", _flip(im), _xf(Vector3.ZERO)])
	return P

static func _flip(m: ArrayMesh) -> ArrayMesh:
	var arrays := m.surface_get_arrays(0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0, idx.size(), 3):
		var tmp := idx[i + 1]
		idx[i + 1] = idx[i + 2]
		idx[i + 2] = tmp
	arrays[Mesh.ARRAY_INDEX] = idx
	var nr: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in nr.size():
		nr[i] = -nr[i]
	arrays[Mesh.ARRAY_NORMAL] = nr
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out

# ---------------------------------------------------------------- face rig
func _sphere(r: float, segs: int = 12, hemi: bool = false) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * (1.0 if hemi else 2.0)
	sm.is_hemisphere = hemi
	sm.radial_segments = segs
	sm.rings = maxi(4, segs / 2)
	return sm

func _detail(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _ghost_or(mat)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 13.0 if low_quality else 22.0
	mi.visibility_range_end_margin = 2.0
	parent.add_child(mi)
	return mi

func _build_face(mats: Dictionary) -> void:
	var white := plain_material(Color(0.93, 0.91, 0.88), 0.25)
	# Bangladeshi eyes are overwhelmingly deep brown; a few carry warm amber/olive tones.
	var iris_pick := randf()
	var iris_c := Color(0.13, 0.075, 0.04)
	if iris_pick > 0.94:
		iris_c = Color(0.34, 0.24, 0.11)   # amber
	elif iris_pick > 0.84:
		iris_c = Color(0.24, 0.16, 0.07)   # warm hazel-brown
	elif iris_pick > 0.72:
		iris_c = Color(0.18, 0.11, 0.055)  # medium brown
	var iris := plain_material(iris_c, 0.2)
	var limbus := plain_material(iris_c.darkened(0.5), 0.35)   # dark outer iris ring
	var pupil := plain_material(Color(0.01, 0.01, 0.01), 0.1)
	var skin: Material = mats["skin"]
	var hair_m: Material = mats["hair"]
	var eyes: Array[Node3D] = []
	var lids: Array[MeshInstance3D] = []
	var brows: Array[MeshInstance3D] = []
	var face := int(look.get("face", 0))
	for sx: float in [-1.0, 1.0]:
		var e := Node3D.new()
		var socket := face_anchor(sx * 0.032, 0.127, female, face)
		e.position = socket + Vector3(0, 0, 0.0088)
		head.add_child(e)
		_detail(e, _sphere(0.0122, 14), white, Vector3.ZERO)
		_detail(e, _sphere(0.0068, 12), iris, Vector3(0, 0, -0.0085), Vector3.ZERO, Vector3(1, 1, 0.42))
		_detail(e, _sphere(0.0033, 8), pupil, Vector3(0, 0, -0.0114), Vector3.ZERO, Vector3(1, 1, 0.3))
		if not low_quality:
			# Limbal ring gives the iris a crisp, lifelike edge instead of a flat disc.
			var ring := _detail(e, _sphere(0.0071, 14, true), limbus, Vector3(0, 0, -0.0083), Vector3.ZERO, Vector3(1, 1, 0.42))
			ring.visible = true
			var hl := _detail(e, _sphere(0.0016, 6), plain_material(Color(1, 1, 1), 0.0), Vector3(sx * 0.002 + 0.002, 0.003, -0.0122))
			hl.material_override = _ghost_or(_spec_material())
		eyes.append(e)
		var lid := _detail(head, _sphere(0.0134, 10 if low_quality else 14, true), mats["face"], e.position, Vector3(0.45, 0, 0))
		lids.append(lid)
		if not low_quality:
			_detail(head, _sphere(0.0131, 14, true), mats["face"], e.position, Vector3(PI - 0.32, 0, 0))   # lower lid: almond shape
			var lash := _detail(lid, _sphere(0.0137, 14, true), plain_material(Color(0.04, 0.03, 0.03), 0.6), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.18, 1.0))
			lash.visible = female
		var bm := BoxMesh.new()
		bm.size = Vector3(0.034, 0.0045 if female else 0.0072, 0.006)
		var bp := face_anchor(sx * 0.034, 0.152, female, face) + Vector3(0, 0, -0.0015)
		var br := _detail(head, bm, hair_m, bp, Vector3(0, 0, sx * -0.1))
		brows.append(br)
	eye_l = eyes[0]
	eye_r = eyes[1]
	lid_l = lids[0]
	lid_r = lids[1]
	brow_l = brows[0]
	brow_r = brows[1]
	# mouth opening: a dark lens on the mouth line that opens for lip-sync
	var mouth_p := face_anchor(0.0, 0.0697, female, face)
	lower_lip = _detail(head, _sphere(0.012, 12), plain_material(Color(0.16, 0.05, 0.05), 0.7), mouth_p + Vector3(0, 0, 0.0025), Vector3.ZERO, Vector3(1.55, 0.05, 0.35))
	if not low_quality:
		var teeth := _detail(lower_lip, _sphere(0.011, 10), plain_material(Color(0.92, 0.9, 0.84), 0.3), Vector3(0, 0.004, -0.001), Vector3.ZERO, Vector3(0.9, 0.35, 0.9))
		teeth.visible = true

static func _spec_material() -> StandardMaterial3D:
	var key := "eye_spec"
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m

# ---------------------------------------------------------------- verlet cloth tail (gamchha / dupatta)
func _build_scarf(mat: Material) -> void:
	var n := 6
	for i in n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.012, 0.11)
		mi.mesh = bm
		mi.material_override = _ghost_or(mat)
		mi.top_level = true
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_scarf.append(mi)
	for i in n + 1:
		_scarf_pts.append(Vector3.ZERO)
		_scarf_prev.append(Vector3.ZERO)
	call_deferred("_scarf_reset")

func _scarf_anchor() -> Vector3:
	return chest.global_transform * Vector3(-0.08, 0.27, 0.09)

func _scarf_reset() -> void:
	if not is_inside_tree() or _scarf.is_empty():
		return
	var a := _scarf_anchor()
	for i in _scarf_pts.size():
		_scarf_pts[i] = a + Vector3(0, -0.1 * i * h, 0.03 * i)
		_scarf_prev[i] = _scarf_pts[i]

# ============================================================================ public API
func set_sustain(nm: String, on: bool) -> void:
	sustain[nm] = 1.0 if on else 0.0

func set_sustain_w(nm: String, w: float) -> void:
	sustain[nm] = clampf(w, 0.0, 1.0)

func clear_sustains() -> void:
	for s in SUSTAINS:
		sustain[s] = 0.0

func play(nm: String, done: Callable = Callable(), speed: float = 1.0) -> void:
	var keys := _clip_data(nm)
	if keys.is_empty():
		return
	clip = nm
	clip_t = 0.0
	_clip_speed = speed
	_clip_keys = keys
	_clip_len = float((keys[keys.size() - 1] as Array)[0])
	_clip_done = done

func is_playing(nm: String = "") -> bool:
	return clip != "" and (nm == "" or clip == nm)

func hit_react(dir_local: Vector3, strength: float = 1.0) -> void:
	_hit_v += Vector3(dir_local.z * 9.0, -dir_local.x * 6.0, dir_local.x * 7.0) * strength
	_squash_v -= 2.0 * strength

func land(strength: float = 1.0) -> void:
	_squash_v -= 3.0 * strength

## Puts a simple prop in a hand: "book", "brick", "stone", "phone", "candle", "paper", "slipper", "banner".
func hold(kind: String, right: bool = true) -> void:
	var p := prop_r if right else prop_l
	for c in p.get_children():
		c.queue_free()
	if kind == "":
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	match kind:
		"book":
			bm.size = Vector3(0.15, 0.21, 0.04)
			mi.material_override = plain_material(Color(0.42, 0.08, 0.08), 0.6)
			mi.rotation = Vector3(0.0, 0.0, 0.2)
		"brick":
			bm.size = Vector3(0.1, 0.06, 0.2)
			mi.material_override = plain_material(Color(0.55, 0.25, 0.17), 0.95)
		"stone":
			bm.size = Vector3(0.08, 0.08, 0.08)
			mi.material_override = plain_material(Color(0.5, 0.5, 0.5), 0.95)
		"phone":
			bm.size = Vector3(0.07, 0.14, 0.01)
			mi.material_override = plain_material(Color(0.05, 0.05, 0.06), 0.2)
		"candle":
			bm.size = Vector3(0.025, 0.12, 0.025)
			mi.material_override = plain_material(Color(0.95, 0.93, 0.85), 0.5)
		"paper":
			bm.size = Vector3(0.21, 0.28, 0.003)
			mi.material_override = plain_material(Color(0.95, 0.94, 0.88), 0.9)
		"banner":
			bm.size = Vector3(0.9, 0.35, 0.01)
			mi.material_override = plain_material(Color(0.9, 0.85, 0.75), 0.9)
			mi.position = Vector3(0.35, 0.35, 0)
		"stick":
			bm.size = Vector3(0.035, 0.85, 0.035)
			mi.material_override = plain_material(Color(0.45, 0.3, 0.15), 0.8)
			mi.position = Vector3(0, -0.2, 0)
		_:
			bm.size = Vector3(0.08, 0.08, 0.08)
			mi.material_override = plain_material(Color(0.6, 0.6, 0.6), 0.6)
	mi.mesh = bm
	p.add_child(mi)

func set_alpha(a: float) -> void:
	visible = a > 0.02
	for mi in mesh_nodes:
		mi.transparency = 1.0 - a

## Capsule list for the ragdoll: name, joint, parent, radius, length, direction.
func segment_specs() -> Array:
	return [
		{"n": "pelvis", "j": hips, "p": "", "r": 0.14, "l": 0.28, "o": 0.0},
		{"n": "torso", "j": chest, "p": "pelvis", "r": 0.16, "l": 0.5, "o": 1.0},
		{"n": "head", "j": head, "p": "torso", "r": 0.1, "l": 0.26, "o": 1.0},
		{"n": "uarm_l", "j": sh_l, "p": "torso", "r": 0.05, "l": 0.3, "o": -1.0},
		{"n": "uarm_r", "j": sh_r, "p": "torso", "r": 0.05, "l": 0.3, "o": -1.0},
		{"n": "farm_l", "j": el_l, "p": "uarm_l", "r": 0.045, "l": 0.34, "o": -1.0},
		{"n": "farm_r", "j": el_r, "p": "uarm_r", "r": 0.045, "l": 0.34, "o": -1.0},
		{"n": "thigh_l", "j": hip_l, "p": "pelvis", "r": 0.07, "l": 0.44, "o": -1.0},
		{"n": "thigh_r", "j": hip_r, "p": "pelvis", "r": 0.07, "l": 0.44, "o": -1.0},
		{"n": "shin_l", "j": knee_l, "p": "thigh_l", "r": 0.055, "l": 0.46, "o": -1.0},
		{"n": "shin_r", "j": knee_r, "p": "thigh_r", "r": 0.055, "l": 0.46, "o": -1.0},
	]

func ragdoll_groups() -> Dictionary:
	return {
		"pelvis": [hips, skirt], "torso": [spine, chest, neck], "head": [head], "uarm_l": [sh_l], "uarm_r": [sh_r],
		"farm_l": [el_l, hand_l], "farm_r": [el_r, hand_r], "thigh_l": [hip_l], "thigh_r": [hip_r],
		"shin_l": [knee_l, foot_l], "shin_r": [knee_r, foot_r],
	}

# ============================================================================ clips
## Each clip: [time, {joint: euler offset}] keys, eased. Anticipation and overshoot keys give weight.
func _clip_data(nm: String) -> Array:
	match nm:
		"punch_r":
			return [[0.0, {}],
				[0.08, {"sh_r": Vector3(-0.4, 0, 0.3), "el_r": Vector3(2.1, 0, 0), "chest": Vector3(0, 0.35, 0), "spine": Vector3(0, 0.15, 0)}],
				[0.16, {"sh_r": Vector3(1.55, 0, 0.05), "el_r": Vector3(0.1, 0, 0), "chest": Vector3(-0.08, -0.45, 0), "spine": Vector3(-0.05, -0.2, 0), "hip_l": Vector3(0.25, 0, 0)}],
				[0.24, {"sh_r": Vector3(1.45, 0, 0.05), "el_r": Vector3(0.2, 0, 0), "chest": Vector3(-0.06, -0.4, 0)}],
				[0.42, {}]]
		"punch_l":
			return [[0.0, {}],
				[0.08, {"sh_l": Vector3(-0.4, 0, -0.3), "el_l": Vector3(2.1, 0, 0), "chest": Vector3(0, -0.35, 0), "spine": Vector3(0, -0.15, 0)}],
				[0.16, {"sh_l": Vector3(1.55, 0, -0.05), "el_l": Vector3(0.1, 0, 0), "chest": Vector3(-0.08, 0.45, 0), "spine": Vector3(-0.05, 0.2, 0), "hip_r": Vector3(0.25, 0, 0)}],
				[0.24, {"sh_l": Vector3(1.45, 0, -0.05), "el_l": Vector3(0.2, 0, 0), "chest": Vector3(-0.06, 0.4, 0)}],
				[0.42, {}]]
		"hook":
			return [[0.0, {}],
				[0.12, {"sh_r": Vector3(0.2, 0.6, 1.3), "el_r": Vector3(1.6, 0, 0), "chest": Vector3(0, 0.55, 0), "spine": Vector3(0.05, 0.25, 0), "hips": Vector3(0, 0.2, 0)}],
				[0.24, {"sh_r": Vector3(1.4, -0.9, 0.6), "el_r": Vector3(1.4, 0, 0), "chest": Vector3(-0.1, -0.7, 0), "spine": Vector3(-0.1, -0.3, 0), "hips": Vector3(0, -0.25, 0)}],
				[0.34, {"sh_r": Vector3(1.2, -1.0, 0.4), "el_r": Vector3(1.3, 0, 0), "chest": Vector3(-0.08, -0.65, 0)}],
				[0.6, {}]]
		"kick":
			return [[0.0, {}],
				[0.12, {"hip_r": Vector3(1.3, 0, 0), "knee_r": Vector3(-1.9, 0, 0), "spine": Vector3(0.15, 0, 0), "sh_l": Vector3(0.5, 0, -0.4), "sh_r": Vector3(-0.4, 0, 0.4)}],
				[0.22, {"hip_r": Vector3(1.55, 0, 0), "knee_r": Vector3(-0.1, 0, 0), "foot_r": Vector3(0.5, 0, 0), "spine": Vector3(0.3, 0, 0), "sh_l": Vector3(0.6, 0, -0.6), "sh_r": Vector3(-0.6, 0, 0.6)}],
				[0.32, {"hip_r": Vector3(1.4, 0, 0), "knee_r": Vector3(-0.3, 0, 0), "spine": Vector3(0.25, 0, 0)}],
				[0.55, {}]]
		"slam":
			return [[0.0, {}],
				[0.22, {"sh_l": Vector3(2.8, 0, -0.2), "sh_r": Vector3(2.8, 0, 0.2), "el_l": Vector3(0.6, 0, 0), "el_r": Vector3(0.6, 0, 0), "spine": Vector3(0.3, 0, 0), "head": Vector3(0.2, 0, 0)}],
				[0.34, {"sh_l": Vector3(0.9, 0, -0.2), "sh_r": Vector3(0.9, 0, 0.2), "spine": Vector3(-0.45, 0, 0), "chest": Vector3(-0.2, 0, 0), "hip_l": Vector3(0.6, 0, 0), "knee_l": Vector3(-0.9, 0, 0), "hip_r": Vector3(0.6, 0, 0), "knee_r": Vector3(-0.9, 0, 0)}],
				[0.7, {}]]
		"throw":
			return [[0.0, {}],
				[0.22, {"sh_r": Vector3(-2.3, 0, 0.35), "el_r": Vector3(1.6, 0, 0), "chest": Vector3(0.08, 0.55, 0), "spine": Vector3(0.12, 0.2, 0), "hip_l": Vector3(0.35, 0, 0), "head": Vector3(0.1, -0.3, 0)}],
				[0.32, {"sh_r": Vector3(1.4, 0, 0.1), "el_r": Vector3(0.15, 0, 0), "chest": Vector3(-0.2, -0.5, 0), "spine": Vector3(-0.25, -0.2, 0), "hip_r": Vector3(0.25, 0, 0)}],
				[0.44, {"sh_r": Vector3(1.0, 0, 0), "el_r": Vector3(0.4, 0, 0), "chest": Vector3(-0.15, -0.35, 0)}],
				[0.75, {}]]
		"parry":
			return [[0.0, {}],
				[0.07, {"sh_l": Vector3(1.9, 0, -0.5), "el_l": Vector3(1.7, 0, 0), "sh_r": Vector3(0.6, 0, 0.6), "chest": Vector3(-0.1, 0.35, 0)}],
				[0.22, {"sh_l": Vector3(2.0, 0, -0.2), "el_l": Vector3(1.2, 0, 0), "chest": Vector3(-0.05, -0.25, 0)}],
				[0.45, {}]]
		"hit_front":
			return [[0.0, {}],
				[0.07, {"spine": Vector3(0.3, 0, 0.1), "chest": Vector3(0.25, 0, 0), "head": Vector3(0.45, 0.2, 0), "sh_l": Vector3(-0.5, 0, -0.6), "sh_r": Vector3(-0.5, 0, 0.6), "el_l": Vector3(0.8, 0, 0), "el_r": Vector3(0.8, 0, 0)}],
				[0.2, {"spine": Vector3(0.15, 0, 0.05), "head": Vector3(0.2, 0.1, 0)}],
				[0.45, {}]]
		"hit_back":
			return [[0.0, {}],
				[0.07, {"spine": Vector3(-0.35, 0, 0), "chest": Vector3(-0.2, 0, 0), "head": Vector3(-0.3, 0, 0), "sh_l": Vector3(0.6, 0, -0.5), "sh_r": Vector3(0.6, 0, 0.5)}],
				[0.45, {}]]
		"dodge":
			var tuck := {"spine": Vector3(-0.6, 0, 0), "chest": Vector3(-0.4, 0, 0), "head": Vector3(-0.5, 0, 0), "hip_l": Vector3(1.6, 0, 0), "hip_r": Vector3(1.4, 0, 0), "knee_l": Vector3(-2.0, 0, 0), "knee_r": Vector3(-2.0, 0, 0), "sh_l": Vector3(1.2, 0, 0), "sh_r": Vector3(1.2, 0, 0), "el_l": Vector3(1.8, 0, 0), "el_r": Vector3(1.8, 0, 0)}
			return [[0.0, {}], [0.08, tuck], [0.32, tuck], [0.48, {}]]
		"wave":
			return [[0.0, {}],
				[0.25, {"sh_r": Vector3(0.3, 0, 2.6), "el_r": Vector3(0.9, 0, 0)}],
				[0.45, {"sh_r": Vector3(0.3, 0, 2.6), "el_r": Vector3(0.3, 0, 0)}],
				[0.65, {"sh_r": Vector3(0.3, 0, 2.6), "el_r": Vector3(1.0, 0, 0)}],
				[0.85, {"sh_r": Vector3(0.3, 0, 2.6), "el_r": Vector3(0.3, 0, 0)}],
				[1.2, {}]]
		"point":
			return [[0.0, {}], [0.25, {"sh_r": Vector3(1.5, 0, 0.15), "el_r": Vector3(0.05, 0, 0), "chest": Vector3(0, -0.15, 0), "head": Vector3(0.05, 0, 0)}],
				[1.0, {"sh_r": Vector3(1.5, 0, 0.15), "el_r": Vector3(0.05, 0, 0), "chest": Vector3(0, -0.15, 0)}], [1.3, {}]]
		"shrug":
			return [[0.0, {}], [0.2, {"sh_l": Vector3(0.3, 0, -0.5), "sh_r": Vector3(0.3, 0, 0.5), "el_l": Vector3(1.5, 0.6, 0), "el_r": Vector3(1.5, -0.6, 0), "chest": Vector3(0.05, 0, 0), "head": Vector3(0.1, 0, 0.15)}],
				[0.6, {"sh_l": Vector3(0.3, 0, -0.5), "sh_r": Vector3(0.3, 0, 0.5), "el_l": Vector3(1.5, 0.6, 0), "el_r": Vector3(1.5, -0.6, 0)}], [0.85, {}]]
		"facepalm":
			return [[0.0, {}], [0.3, {"sh_r": Vector3(1.4, 0, -0.35), "el_r": Vector3(2.35, 0, 0), "head": Vector3(0.35, 0, 0), "spine": Vector3(0.1, 0, 0)}],
				[1.0, {"sh_r": Vector3(1.4, 0, -0.35), "el_r": Vector3(2.35, 0, 0), "head": Vector3(0.4, 0.1, 0)}], [1.3, {}]]
		"slogan":
			return [[0.0, {}], [0.15, {"sh_r": Vector3(0.4, 0, 2.7), "el_r": Vector3(0.8, 0, 0), "head": Vector3(-0.15, 0, 0)}],
				[0.3, {"sh_r": Vector3(0.3, 0, 2.9), "el_r": Vector3(0.1, 0, 0), "head": Vector3(-0.25, 0, 0), "chest": Vector3(-0.08, 0, 0)}],
				[0.45, {"sh_r": Vector3(0.4, 0, 2.7), "el_r": Vector3(0.9, 0, 0)}],
				[0.6, {"sh_r": Vector3(0.3, 0, 2.9), "el_r": Vector3(0.1, 0, 0), "head": Vector3(-0.25, 0, 0)}], [0.9, {}]]
		"clap":
			var a := {"sh_l": Vector3(1.0, 0.5, -0.1), "sh_r": Vector3(1.0, -0.5, 0.1), "el_l": Vector3(1.2, 0, 0), "el_r": Vector3(1.2, 0, 0)}
			var b := {"sh_l": Vector3(1.0, 0.2, -0.4), "sh_r": Vector3(1.0, -0.2, 0.4), "el_l": Vector3(1.2, 0, 0), "el_r": Vector3(1.2, 0, 0)}
			return [[0.0, {}], [0.12, b], [0.2, a], [0.32, b], [0.4, a], [0.52, b], [0.6, a], [0.85, {}]]
		"taunt":
			return [[0.0, {}], [0.2, {"sh_r": Vector3(1.6, 0, 0.3), "el_r": Vector3(0.9, 0, 0), "head": Vector3(-0.1, 0, 0.15), "chest": Vector3(0.05, -0.2, 0)}],
				[0.35, {"sh_r": Vector3(1.6, 0.25, 0.4), "el_r": Vector3(0.9, 0, 0), "head": Vector3(-0.1, 0, -0.1)}],
				[0.5, {"sh_r": Vector3(1.6, -0.25, 0.2), "el_r": Vector3(0.9, 0, 0), "head": Vector3(-0.1, 0, 0.12)}],
				[0.65, {"sh_r": Vector3(1.6, 0.25, 0.4), "el_r": Vector3(0.9, 0, 0)}], [1.0, {}]]
		"pickup":
			return [[0.0, {}], [0.3, {"spine": Vector3(-0.9, 0, 0), "chest": Vector3(-0.3, 0, 0), "sh_r": Vector3(1.0, 0, 0.1), "hip_l": Vector3(0.6, 0, 0), "hip_r": Vector3(0.6, 0, 0), "knee_l": Vector3(-0.9, 0, 0), "knee_r": Vector3(-0.9, 0, 0)}],
				[0.45, {"spine": Vector3(-0.9, 0, 0), "chest": Vector3(-0.3, 0, 0), "sh_r": Vector3(1.0, 0, 0.1)}], [0.75, {}]]
		"give":
			return [[0.0, {}], [0.3, {"sh_r": Vector3(1.2, 0, 0.1), "el_r": Vector3(0.4, 0, 0), "spine": Vector3(-0.15, 0, 0)}], [0.7, {"sh_r": Vector3(1.2, 0, 0.1), "el_r": Vector3(0.4, 0, 0)}], [1.0, {}]]
		"getup":
			return [[0.0, {"spine": Vector3(-1.0, 0, 0), "hip_l": Vector3(1.6, 0, 0), "hip_r": Vector3(1.2, 0, 0), "knee_l": Vector3(-2.2, 0, 0), "knee_r": Vector3(-1.8, 0, 0), "sh_l": Vector3(1.0, 0, -0.3), "sh_r": Vector3(1.0, 0, 0.3)}],
				[0.4, {"spine": Vector3(-0.6, 0, 0), "hip_l": Vector3(1.2, 0, 0), "knee_l": Vector3(-1.6, 0, 0), "hip_r": Vector3(0.6, 0, 0), "knee_r": Vector3(-1.0, 0, 0)}], [0.8, {}]]
		"cast":
			return [[0.0, {}], [0.25, {"sh_l": Vector3(-0.6, 0, -1.3), "sh_r": Vector3(-0.6, 0, 1.3), "el_l": Vector3(0.6, 0, 0), "el_r": Vector3(0.6, 0, 0), "head": Vector3(-0.3, 0, 0)}],
				[0.45, {"sh_l": Vector3(1.6, 0, -0.2), "sh_r": Vector3(1.6, 0, 0.2), "el_l": Vector3(0.1, 0, 0), "el_r": Vector3(0.1, 0, 0), "spine": Vector3(-0.2, 0, 0)}], [0.8, {}]]
		"victory":
			return [[0.0, {}], [0.35, {"sh_r": Vector3(0.3, 0, 2.8), "el_r": Vector3(0.3, 0, 0), "head": Vector3(-0.2, 0, 0)}],
				[0.7, {"sh_r": Vector3(0.3, 0, 2.85), "el_r": Vector3(0.2, 0, 0), "head": Vector3(-0.25, 0.1, 0)}], [1.2, {}]]
		"g_open":
			return [[0.0, {}], [0.25, {"sh_r": Vector3(0.7, 0, 0.25), "el_r": Vector3(1.2, -0.8, 0), "sh_l": Vector3(0.6, 0, -0.2), "el_l": Vector3(1.1, 0.8, 0)}], [0.7, {"sh_r": Vector3(0.6, 0, 0.3), "el_r": Vector3(1.1, -0.9, 0)}], [1.0, {}]]
		"g_count":
			return [[0.0, {}], [0.2, {"sh_r": Vector3(0.9, 0, 0.1), "el_r": Vector3(1.6, 0, 0), "sh_l": Vector3(0.9, 0, -0.1), "el_l": Vector3(1.6, 0, 0)}],
				[0.4, {"sh_r": Vector3(0.95, 0.1, 0.1), "el_r": Vector3(1.7, 0, 0), "sh_l": Vector3(0.9, -0.1, -0.1), "el_l": Vector3(1.5, 0, 0)}],
				[0.6, {"sh_r": Vector3(0.9, 0, 0.1), "el_r": Vector3(1.6, 0, 0), "sh_l": Vector3(0.9, 0, -0.1), "el_l": Vector3(1.6, 0, 0)}], [0.9, {}]]
		"g_chop":
			return [[0.0, {}], [0.15, {"sh_r": Vector3(1.0, 0, 0.3), "el_r": Vector3(1.2, 0, 0)}], [0.3, {"sh_r": Vector3(0.6, 0, 0.2), "el_r": Vector3(0.8, 0, 0)}],
				[0.45, {"sh_r": Vector3(1.0, 0, 0.3), "el_r": Vector3(1.2, 0, 0)}], [0.6, {"sh_r": Vector3(0.6, 0, 0.2), "el_r": Vector3(0.8, 0, 0)}], [0.85, {}]]
		"die":
			return [[0.0, {}], [0.25, {"spine": Vector3(0.4, 0, 0.2), "head": Vector3(0.5, 0, 0.3), "sh_l": Vector3(-0.3, 0, -0.8), "sh_r": Vector3(-0.3, 0, 0.8), "knee_l": Vector3(-1.0, 0, 0), "knee_r": Vector3(-0.6, 0, 0)}], [0.6, {}]]
	return []

func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)

func _sample_clip() -> Dictionary:
	var out := {}
	if clip == "" or _clip_keys.is_empty():
		return out
	var k0: Array = _clip_keys[0]
	var k1: Array = _clip_keys[_clip_keys.size() - 1]
	for i in _clip_keys.size() - 1:
		var a: Array = _clip_keys[i]
		var b: Array = _clip_keys[i + 1]
		if clip_t >= float(a[0]) and clip_t <= float(b[0]):
			k0 = a
			k1 = b
			break
	var span := maxf(float(k1[0]) - float(k0[0]), 0.0001)
	var u := _ease(clampf((clip_t - float(k0[0])) / span, 0.0, 1.0))
	var p0: Dictionary = k0[1]
	var p1: Dictionary = k1[1]
	var names := {}
	for n in p0.keys():
		names[n] = true
	for n in p1.keys():
		names[n] = true
	for n in names.keys():
		var a0: Vector3 = p0.get(n, Vector3.ZERO)
		var a1: Vector3 = p1.get(n, Vector3.ZERO)
		out[n] = a0.lerp(a1, u)
	return out

# ============================================================================ per-frame animation
const JOINT_ORDER: Array[String] = ["hips", "spine", "chest", "neck", "head", "sh_l", "sh_r", "el_l", "el_r", "hip_l", "hip_r", "knee_l", "knee_r", "foot_l", "foot_r"]

func animate(delta: float, vel: Vector3, grounded: bool = true) -> void:
	if delta <= 0.0:
		return
	t += delta
	for s in SUSTAINS:
		_w[s] = move_toward(float(_w[s]), float(sustain[s]), delta * 4.0)
	var basis_inv := global_transform.basis.orthonormalized().inverse()
	var lv := basis_inv * vel
	var spd := Vector2(lv.x, lv.z).length()
	var old := clampf((age - 0.55) / 0.45, 0.0, 1.0)
	var stride := lerpf(1.3, 1.0, old) * (0.92 if female else 1.0)
	var dir_sign := -1.0 if lv.z > 0.25 else 1.0
	phase += spd * delta * TAU / stride * dir_sign
	var ww := clampf(spd / 1.5, 0.0, 1.0)
	var rw := clampf((spd - 3.2) / 2.3, 0.0, 1.0)
	var air := 0.0 if grounded else 1.0
	var sp := sin(phase)
	var p := {}
	for j in JOINT_ORDER:
		p[j] = Vector3.ZERO
	var hips_y := _rest_hips_y
	# --- locomotion: stance/swing legs, heel strike and toe-off
	var leg_amp := lerpf(0.4, 0.75, rw) * ww * lerpf(1.0, 0.7, old)
	var swing_l := maxf(0.0, -cos(phase - 0.5))
	var swing_r := maxf(0.0, cos(phase - 0.5))
	p["hip_l"].x = sp * leg_amp
	p["hip_r"].x = -sp * leg_amp
	p["knee_l"].x = -(swing_l * (0.9 * ww + 0.75 * rw) + 0.06 + 0.12 * rw)
	p["knee_r"].x = -(swing_r * (0.9 * ww + 0.75 * rw) + 0.06 + 0.12 * rw)
	p["foot_l"].x = -p["hip_l"].x * 0.45 - p["knee_l"].x * 0.35 + swing_l * 0.15 * ww
	p["foot_r"].x = -p["hip_r"].x * 0.45 - p["knee_r"].x * 0.35 + swing_r * 0.15 * ww
	hips_y += ((1.0 - absf(sp)) * 0.035 - 0.02) * ww + (absf(sp) * 0.05 - 0.03) * rw
	p["hips"].y = sp * 0.14 * ww
	p["hips"].z = cos(phase) * 0.045 * ww                    # pelvis drop on the swing side
	p["spine"].y = -sp * 0.09 * ww
	p["chest"].y = -sp * 0.12 * ww                            # shoulders counter-rotate
	p["spine"].x = -(0.04 * ww + 0.22 * rw) - old * 0.28      # run lean, old-age hunch
	p["neck"].x = old * 0.2
	p["head"].y = sp * 0.1 * ww                               # head stays on target
	var arm_amp := (0.42 * ww + 0.55 * rw) * lerpf(1.0, 0.5, old)
	p["sh_l"].x = -sp * arm_amp
	p["sh_r"].x = sp * arm_amp
	p["sh_l"].z = -0.07 - 0.05 * rw
	p["sh_r"].z = 0.07 + 0.05 * rw
	p["el_l"].x = 0.12 + 0.15 * ww + 1.2 * rw + maxf(0.0, -sp) * 0.25 * ww
	p["el_r"].x = 0.12 + 0.15 * ww + 1.2 * rw + maxf(0.0, sp) * 0.25 * ww
	p["head"].x = 0.05 * rw
	# --- airborne
	if air > 0.0:
		p["hip_l"].x = 0.5
		p["knee_l"].x = -0.9
		p["hip_r"].x = -0.1
		p["knee_r"].x = -0.4
		p["sh_l"].z = -0.6
		p["sh_r"].z = 0.6
		p["el_l"].x = 0.6
		p["el_r"].x = 0.6
	# --- idle: breathing, weight shift, fidget
	var idle := 1.0 - ww
	var breath := sin(t * (1.5 + old * 0.4))
	p["chest"].x += breath * 0.02
	p["sh_l"].z -= breath * 0.012
	p["sh_r"].z += breath * 0.012
	var shift := sin(t * 0.41)
	hips_y -= absf(shift) * 0.012 * idle
	p["hips"].z += shift * 0.035 * idle
	p["hip_l"].z = -shift * 0.035 * idle
	p["hip_r"].z = -shift * 0.035 * idle
	p["knee_l"].x -= maxf(0.0, shift) * 0.12 * idle
	p["knee_r"].x -= maxf(0.0, -shift) * 0.12 * idle
	p["head"].y += sin(t * 0.37 + 1.3) * 0.12 * idle
	p["head"].x += sin(t * 0.23) * 0.04 * idle
	# --- acceleration lean and turn banking
	var acc := (lv - (basis_inv * _last_vel)) / delta
	_last_vel = vel
	var target_lean := Vector3(clampf(acc.z * 0.016, -0.22, 0.22), 0, clampf(-acc.x * 0.014, -0.18, 0.18))
	var yaw := global_rotation.y
	_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, 0.15)
	_last_yaw = yaw
	target_lean.z += clampf(_yaw_rate * spd * 0.02, -0.25, 0.25)
	_lean = _lean.lerp(target_lean, 1.0 - exp(-delta * 8.0))
	p["spine"] += _lean
	# --- talking gestures
	if talking and clip == "" and ww < 0.3:
		_gesture_t -= delta
		if _gesture_t <= 0.0:
			_gesture_t = randf_range(1.2, 2.6)
			play(["g_open", "g_count", "g_chop", "shrug", "point"][randi() % 5])
	_apply_sustains(p, delta)
	hips_y = _sustain_height(hips_y)
	# --- action clip overlay
	if clip != "":
		clip_t += delta * _clip_speed
		var c := _sample_clip()
		for n in c.keys():
			if p.has(n):
				p[n] += c[n]
		if clip == "dodge":
			roll_angle = -TAU * _ease(clampf(clip_t / 0.44, 0.0, 1.0))
		if clip_t >= _clip_len:
			var done := _clip_done
			clip = ""
			roll_angle = 0.0
			_clip_done = Callable()
			if done.is_valid():
				done.call()
	# --- look-at: head, neck, a little chest, and the eyes
	var down_w: float = _w["down"]
	if look_target != null and down_w < 0.5:
		var lt: Vector3 = look_target
		var local := chest.global_transform.affine_inverse() * lt
		var yaw_t := clampf(atan2(-local.x, -local.z), -1.25, 1.25)
		var pitch_t := clampf(atan2(local.y - 0.4, Vector2(local.x, local.z).length()), -0.5, 0.5)
		p["head"].y += yaw_t * 0.6
		p["neck"].y += yaw_t * 0.15
		p["head"].x -= pitch_t * 0.7
		p["chest"].y += yaw_t * 0.2
		if not lod_far and eye_l:
			var hl := head.global_transform.affine_inverse() * lt
			var ey := clampf(atan2(-hl.x, -hl.z) * 0.5, -0.4, 0.4)
			var ex := clampf(atan2(hl.y - 0.13, Vector2(hl.x, hl.z).length()) * 0.5, -0.3, 0.3)
			eye_l.rotation = Vector3(ex, ey, 0)
			eye_r.rotation = eye_l.rotation
	# --- hit spring
	var acc_h := -_hit * 120.0 - _hit_v * 14.0
	_hit_v += acc_h * delta
	_hit += _hit_v * delta
	p["spine"] += _hit * 0.6
	p["chest"] += _hit * 0.4
	p["head"] += _hit * 0.8
	# --- apply
	hips.position.y = lerpf(hips.position.y, hips_y, 1.0 - exp(-delta * 16.0))
	var sm := 1.0 - exp(-delta * 20.0)
	for j in JOINT_ORDER:
		_apply(joints[j] as Node3D, p[j] as Vector3, sm)
	var lie := down_w
	rotation.x = lerp_angle(rotation.x, roll_angle - lie * PI * 0.5, 1.0 - exp(-delta * 12.0))
	position.y = lie * 0.14 * h
	if roll_angle != 0.0:
		position.y += sin(-roll_angle * 0.5) * 0.35
	# squash & stretch
	var acc_s := -_squash * 160.0 - _squash_v * 12.0
	_squash_v += acc_s * delta
	_squash += _squash_v * delta
	scale = Vector3(1.0 - _squash * 0.4, 1.0 + _squash, 1.0 - _squash * 0.4) * h
	if not lod_far:
		_face(delta)
	_update_skirt(delta, lv)
	_update_scarf(delta)

func _apply_sustains(p: Dictionary, _delta: float) -> void:
	var w: float = _w["crouch"]
	if w > 0.0:
		p["hip_l"].x += 1.05 * w
		p["hip_r"].x += 1.05 * w
		p["knee_l"].x -= 1.7 * w
		p["knee_r"].x -= 1.7 * w
		p["foot_l"].x += 0.6 * w
		p["foot_r"].x += 0.6 * w
		p["spine"].x -= 0.45 * w
		p["head"].x += 0.35 * w
		p["sh_l"].x += 0.3 * w
		p["sh_r"].x += 0.3 * w
		p["el_l"].x += 0.6 * w
		p["el_r"].x += 0.6 * w
	w = _w["block"]
	if w > 0.0:
		p["sh_l"] = (p["sh_l"] as Vector3).lerp(Vector3(1.35, 0.35, -0.2), w)
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(1.35, -0.35, 0.2), w)
		p["el_l"] = (p["el_l"] as Vector3).lerp(Vector3(1.9, 0, 0), w)
		p["el_r"] = (p["el_r"] as Vector3).lerp(Vector3(1.9, 0, 0), w)
		p["head"].x += 0.15 * w
		p["spine"].x -= 0.1 * w
	var ws: float = minf(1.0, float(_w["sit"]) + float(_w["type"]))
	if ws > 0.0:
		p["hip_l"].x = lerpf(p["hip_l"].x, 1.5, ws)
		p["hip_r"].x = lerpf(p["hip_r"].x, 1.5, ws)
		p["knee_l"].x = lerpf(p["knee_l"].x, -1.5, ws)
		p["knee_r"].x = lerpf(p["knee_r"].x, -1.5, ws)
		p["spine"].x = lerpf(p["spine"].x, -0.08, ws)
	w = _w["type"]
	if w > 0.0:
		p["sh_l"] = (p["sh_l"] as Vector3).lerp(Vector3(0.75, 0.1, -0.15), w)
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(0.75, -0.1, 0.15), w)
		p["el_l"] = (p["el_l"] as Vector3).lerp(Vector3(1.1 + sin(t * 23.0) * 0.06, 0, 0), w)
		p["el_r"] = (p["el_r"] as Vector3).lerp(Vector3(1.1 + sin(t * 19.0 + 1.3) * 0.06, 0, 0), w)
		p["head"].x -= 0.25 * w
	w = _w["phone"]
	if w > 0.0:
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(0.6, 0, 0.25), w)
		p["el_r"] = (p["el_r"] as Vector3).lerp(Vector3(1.9 + sin(t * 17.0) * 0.05, 0, 0), w)
		p["head"].x -= 0.45 * w
	w = _w["read"]
	if w > 0.0:
		p["sh_l"] = (p["sh_l"] as Vector3).lerp(Vector3(0.75, 0.25, -0.1), w)
		p["el_l"] = (p["el_l"] as Vector3).lerp(Vector3(1.5, 0, 0), w)
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(0.75, -0.25, 0.1), w)
		p["el_r"] = (p["el_r"] as Vector3).lerp(Vector3(1.5, 0, 0), w)
		p["head"].x -= 0.4 * w
	w = _w["aim"]
	if w > 0.0:
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(-2.2, 0, 0.4), w)
		p["el_r"] = (p["el_r"] as Vector3).lerp(Vector3(1.5, 0, 0), w)
		p["sh_l"] = (p["sh_l"] as Vector3).lerp(Vector3(1.4, 0, -0.2), w)
		p["chest"].y += 0.45 * w
	w = _w["carry"]
	if w > 0.0:
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(0.5, 0, 0.15), w)
		p["el_r"] = (p["el_r"] as Vector3).lerp(Vector3(1.4, 0, 0), w)
	w = _w["march"]
	if w > 0.0:
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(0.3, 0, 2.6 + sin(t * 4.0) * 0.15), w)
		p["el_r"] = (p["el_r"] as Vector3).lerp(Vector3(0.6 + absf(sin(t * 4.0)) * 0.5, 0, 0), w)
		p["head"].x -= 0.15 * w
	w = _w["hands_up"]
	if w > 0.0:
		p["sh_l"] = (p["sh_l"] as Vector3).lerp(Vector3(0.2, 0, -2.6), w)
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(0.2, 0, 2.6), w)
		p["el_l"] = (p["el_l"] as Vector3).lerp(Vector3(0.5, 0, 0), w)
		p["el_r"] = (p["el_r"] as Vector3).lerp(Vector3(0.5, 0, 0), w)
	w = _w["cower"]
	if w > 0.0:
		p["sh_l"] = (p["sh_l"] as Vector3).lerp(Vector3(2.2, 0, -0.5), w)
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(2.2, 0, 0.5), w)
		p["el_l"] = (p["el_l"] as Vector3).lerp(Vector3(2.3, 0, 0), w)
		p["el_r"] = (p["el_r"] as Vector3).lerp(Vector3(2.3, 0, 0), w)
		p["spine"].x -= 0.5 * w
		p["head"].x += 0.4 * w
		p["hip_l"].x += 0.8 * w
		p["hip_r"].x += 0.8 * w
		p["knee_l"].x -= 1.4 * w
		p["knee_r"].x -= 1.4 * w
	w = _w["kneel"]
	if w > 0.0:
		p["hip_l"].x = lerpf(p["hip_l"].x, 1.5, w)
		p["knee_l"].x = lerpf(p["knee_l"].x, -2.4, w)
		p["hip_r"].x = lerpf(p["hip_r"].x, -0.1, w)
		p["knee_r"].x = lerpf(p["knee_r"].x, -1.5, w)
		p["spine"].x -= 0.2 * w
	w = _w["beg"]
	if w > 0.0:
		p["sh_l"] = (p["sh_l"] as Vector3).lerp(Vector3(1.2, 0.3, -0.1), w)
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(1.2, -0.3, 0.1), w)
		p["el_l"] = (p["el_l"] as Vector3).lerp(Vector3(1.0, 0, 0), w)
		p["el_r"] = (p["el_r"] as Vector3).lerp(Vector3(1.0, 0, 0), w)
		p["head"].x -= 0.3 * w
	w = _w["lean_wall"]
	if w > 0.0:
		p["spine"].x += 0.12 * w
		p["hip_r"].x += 0.2 * w
		p["knee_r"].x -= 0.4 * w
		p["sh_l"] = (p["sh_l"] as Vector3).lerp(Vector3(-0.2, 0, -0.15), w)
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(-0.2, 0, 0.15), w)
	w = _w["float"]
	if w > 0.0:
		p["hip_l"].x = lerpf(p["hip_l"].x, 0.25 + sin(t * 1.3) * 0.15, w)
		p["hip_r"].x = lerpf(p["hip_r"].x, 0.15 + sin(t * 1.3 + 1.0) * 0.15, w)
		p["knee_l"].x = lerpf(p["knee_l"].x, -0.6, w)
		p["knee_r"].x = lerpf(p["knee_r"].x, -0.7, w)
		p["foot_l"].x = lerpf(p["foot_l"].x, 0.6, w)
		p["foot_r"].x = lerpf(p["foot_r"].x, 0.6, w)
		p["sh_l"].z -= 0.45 * w
		p["sh_r"].z += 0.45 * w
		p["sh_l"].x += (0.6 + sin(t * 1.1) * 0.2) * w
		p["sh_r"].x += (0.6 + sin(t * 1.1 + 0.6) * 0.2) * w
		p["head"].z += sin(t * 0.8) * 0.15 * w
		p["head"].x += 0.2 * w
	w = _w["down"]
	if w > 0.0:
		p["sh_l"] = (p["sh_l"] as Vector3).lerp(Vector3(0.3, 0, -1.2), w)
		p["sh_r"] = (p["sh_r"] as Vector3).lerp(Vector3(0.6, 0, 1.0), w)
		p["el_l"] = (p["el_l"] as Vector3).lerp(Vector3(0.4, 0, 0), w)
		p["knee_l"].x = lerpf(p["knee_l"].x, -0.5, w)
		p["hip_l"].x = lerpf(p["hip_l"].x, 0.35, w)
		p["head"].y += sin(t * 0.7) * 0.1 * w
		p["head"].z += 0.3 * w

func _sustain_height(hips_y: float) -> float:
	var y := hips_y
	y -= 0.3 * float(_w["crouch"])
	y -= 0.28 * float(_w["cower"])
	var ws: float = minf(1.0, float(_w["sit"]) + float(_w["type"]))
	y = lerpf(y, 0.5, ws)
	y = lerpf(y, 0.45, float(_w["kneel"]))
	y += (0.28 + sin(t * 1.6) * 0.08) * float(_w["float"])
	return y

func _apply(j: Node3D, e: Vector3, s: float) -> void:
	j.rotation = Vector3(lerp_angle(j.rotation.x, e.x, s), lerp_angle(j.rotation.y, e.y, s), lerp_angle(j.rotation.z, e.z, s))

func _face(delta: float) -> void:
	if lid_l == null:
		return
	_blink_t -= delta
	var target_blink := 0.0
	if _blink_t < 0.0:
		target_blink = 1.0
		if _blink_t < -0.12:
			_blink_t = randf_range(2.0, 5.5)
	_blink = lerpf(_blink, target_blink, 0.7)
	var open := 1.0
	var br := 0.0
	var by := 0.0
	match expression:
		"angry":
			open = 0.65
			br = 0.4
			by = -0.004
		"smug":
			open = 0.7
			br = -0.1
			by = 0.004
		"shock":
			open = 1.35
			br = -0.25
			by = 0.008
		"sad":
			open = 0.8
			br = -0.4
			by = 0.002
		"scared":
			open = 1.25
			br = -0.35
			by = 0.006
		"dead":
			open = 0.0
	var lid_rot := lerpf(-1.2, 0.45 * open, 1.0 - _blink)
	if _w["down"] > 0.5 and expression == "dead":
		lid_rot = -1.2
	lid_l.rotation.x = lerpf(lid_l.rotation.x, lid_rot, 0.6)
	lid_r.rotation.x = lid_l.rotation.x
	brow_l.rotation.z = lerpf(brow_l.rotation.z, 0.08 + br, 0.2)
	brow_r.rotation.z = lerpf(brow_r.rotation.z, -0.08 - br, 0.2)
	if _brow_base < 0.0:
		_brow_base = brow_l.position.y
	brow_l.position.y = lerpf(brow_l.position.y, _brow_base + by, 0.2)
	brow_r.position.y = brow_l.position.y
	var jaw := 0.0
	if talking:
		jaw = absf(sin(t * 15.0) * sin(t * 5.7 + 0.4)) * 0.012
	elif expression == "shock" or expression == "scared":
		jaw = 0.008
	lower_lip.scale.y = lerpf(lower_lip.scale.y, 0.05 + jaw * 55.0, 0.5)

func _update_skirt(delta: float, lv: Vector3) -> void:
	if skirt == null:
		return
	var target := Vector3(clampf(-lv.z * 0.05, -0.3, 0.3), 0, clampf(lv.x * 0.05, -0.3, 0.3))
	target.x += sin(phase * 2.0) * 0.05 * clampf(lv.length() / 3.0, 0.0, 1.0)
	target.x += absf(sin(phase)) * 0.12 * clampf(lv.length() / 2.0, 0.0, 1.0)
	var acc := (target - _skirt_rot) * 90.0 - _skirt_v * 9.0
	_skirt_v += acc * delta
	_skirt_rot += _skirt_v * delta
	skirt.rotation = _skirt_rot

func _update_scarf(delta: float) -> void:
	if _scarf.is_empty() or not is_inside_tree():
		return
	var seg := 0.1 * h
	_scarf_pts[0] = _scarf_anchor()
	var g := Vector3(0, -6.5, 0) * delta * delta
	for i in range(1, _scarf_pts.size()):
		var cur: Vector3 = _scarf_pts[i]
		var prev: Vector3 = _scarf_prev[i]
		_scarf_prev[i] = cur
		_scarf_pts[i] = cur + (cur - prev) * 0.93 + g
	var c := chest.global_position
	for it in 3:
		for i in range(1, _scarf_pts.size()):
			var a: Vector3 = _scarf_pts[i - 1]
			var b: Vector3 = _scarf_pts[i]
			var dv := b - a
			var l := dv.length()
			if l > 0.0001:
				var corr := dv * ((l - seg) / l)
				if i == 1:
					_scarf_pts[i] = b - corr
				else:
					_scarf_pts[i - 1] = a + corr * 0.5
					_scarf_pts[i] = b - corr * 0.5
		for i in range(1, _scarf_pts.size()):
			var q: Vector3 = _scarf_pts[i]
			var off := Vector3(q.x - c.x, 0, q.z - c.z)
			var rr := 0.17 * h
			if off.length() < rr and q.y > c.y - 0.6 * h:
				_scarf_pts[i] = q + off.normalized() * (rr - off.length())
	for i in _scarf.size():
		var a2: Vector3 = _scarf_pts[i]
		var b2: Vector3 = _scarf_pts[i + 1]
		var mi: MeshInstance3D = _scarf[i]
		var fwd := b2 - a2
		if fwd.length() < 0.0001:
			continue
		var right := chest.global_transform.basis.x.normalized()
		var up := fwd.normalized().cross(right).normalized()
		if up.length() < 0.001:
			up = Vector3.UP
		mi.global_transform = Transform3D(Basis(right, up, fwd.normalized()).orthonormalized().scaled(Vector3.ONE * h), (a2 + b2) * 0.5)
		mi.scale = Vector3(1.0 - i * 0.05, 1.0, 1.0) * h
