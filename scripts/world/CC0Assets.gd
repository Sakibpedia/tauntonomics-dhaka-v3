class_name CC0Assets
extends RefCounted
## Open (CC0-1.0) 3D models.
const MERGED_DIR := "res://assets/models/cc0_merged/"
const CHAR_DIR := "res://assets/models/cc0_characters/"
static var _cache: Dictionary = {}

static func buildings() -> Array[String]:
	return [
		"residencial__casa_simples", "comercial__mercado",
	]

static func characters() -> Array[String]:
	return ["char__pessoa__fiona", "char__pessoa__lu"]

static func props() -> Array[String]:
	return ["mobiliario__banco_praca"]

static func _cached(name: String, dir: String):
	var path: String = dir + name + ".glb"
	if not FileAccess.file_exists(path):
		return null
	_cache[name] = load(path)
	return _cache[name]

static func make(name: String) -> Node3D:
	var packed: PackedScene = _cached(name, MERGED_DIR)
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	if inst is Node3D:
		return inst as Node3D
	return null

static func make_character(name: String) -> Node3D:
	var file_name: String = name
	if file_name.begins_with("char__"):
		file_name = file_name.substr(6)
	var packed: PackedScene = _cached(file_name, CHAR_DIR)
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	if inst is Node3D:
		var n: Node3D = inst as Node3D
		var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, true)
		if ap != null:
			ap.play("parado")
		return n
	return null

static func scale_for(name: String) -> float:
	if name.begins_with("char__"):
		return 1.0
	var p: Array = name.split("__")
	if p.is_empty():
		return 1.0
	if p[0] in ["residencial", "comercial"]:
		return 8.0
	return 6.0

static func no_shadows(node: Node) -> void:
	for c in node.find_children("*", "GeometryInstance3D", true, false):
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func place_building(model: Node3D, ground_pos: Vector3, lot_w: float, lot_d: float) -> void:
	var fit: float = minf(lot_w, lot_d) * 0.47
	model.scale = Vector3.ONE * fit
	model.position = Vector3(ground_pos.x, 0.0, ground_pos.z)
