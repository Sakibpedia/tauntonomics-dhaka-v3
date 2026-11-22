class_name VehicleModels
extends RefCounted
## Authentic Dhaka vehicle GLB models (generated from researched designs — see DhakaDistricts.gd).
## Each model is a single vertex-coloured mesh = one draw call, so even LOW quality can use them.

const MODELS := {
	"rickshaw": "res://assets/models/rickshaw.glb",
	"cng": "res://assets/models/cng.glb",
	"bus": "res://assets/models/bus.glb",
}

static var _cache: Dictionary = {}

static func make(kind: String) -> Node3D:
	if not MODELS.has(kind):
		return null
	if not _cache.has(kind):
		_cache[kind] = load(MODELS[kind] as String)
	var packed: PackedScene = _cache[kind]
	if packed == null:
		return null
	var inst := packed.instantiate()
	if inst is Node3D:
		return inst as Node3D
	return null

## Shadows on every traffic vehicle are off (weak GPU + they look better flat in daylight).
static func no_shadows(node: Node) -> void:
	for c in node.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
