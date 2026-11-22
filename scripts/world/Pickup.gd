class_name Pickup
extends Area3D
## Collectible mission items (প্রশ্নের বান্ডিল, ভুয়া সনদ, গাইড বই, খাতা, ফাইল, উত্তরপত্র) and money.
## Bobs and spins, glows, and is collected by walking into it. Bricks are "throwable" props instead.

signal collected(item: String)

const NAMES := {"bundle": "প্রশ্নের বান্ডিল", "certificate": "ভুয়া সনদ", "guide": "ফাঁস হওয়া গাইড", "ledger": "হিসাবের খাতা",
	"file": "অ্যাক্রেডিটেশন ফাইল", "answer_sheet": "পুরোনো উত্তরপত্র", "list": "ডিকোড করা তালিকা", "money": "টাকা", "candle": "মোমবাতি"}

var s: Services
var item := "bundle"
var kind := ""          # for throwables: "brick"
var _mesh: MeshInstance3D
var _t := 0.0
var _base_y := 0.0

func setup(services: Services, it: String, throwable: bool = false) -> void:
	s = services
	item = it
	collision_layer = 0
	collision_mask = Actor.LAYER_PLAYER
	monitoring = not throwable
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.9
	cs.shape = sp
	cs.position.y = 0.6
	add_child(cs)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	var col := Color(0.95, 0.92, 0.8)
	match it:
		"bundle":
			bm.size = Vector3(0.35, 0.18, 0.25)
			col = Color(0.8, 0.72, 0.55)
		"certificate", "file", "answer_sheet", "list":
			bm.size = Vector3(0.3, 0.02, 0.4)
		"guide", "ledger":
			bm.size = Vector3(0.22, 0.05, 0.3)
			col = Color(0.15, 0.3, 0.55) if it == "guide" else Color(0.45, 0.12, 0.1)
		"money":
			bm.size = Vector3(0.16, 0.04, 0.08)
			col = Color(0.35, 0.6, 0.35)
		"brick":
			bm.size = Vector3(0.1, 0.06, 0.2)
			col = Color(0.55, 0.25, 0.17)
		_:
			bm.size = Vector3(0.2, 0.2, 0.2)
	_mesh.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if not throwable:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.8, 0.3)
		m.emission_energy_multiplier = 0.6
	_mesh.material_override = m
	_mesh.position.y = 0.6 if not throwable else 0.05
	add_child(_mesh)
	if throwable:
		kind = it
		add_to_group("throwable")
	else:
		body_entered.connect(_on_body)
		add_to_group("pickups")

func _process(delta: float) -> void:
	if monitoring:
		_t += delta
		_mesh.rotation.y += delta * 1.5
		_mesh.position.y = 0.6 + sin(_t * 2.5) * 0.08

func _on_body(b: Node) -> void:
	if b.is_in_group("player"):
		s.sfx.play("coin" if item == "money" else "page", -4.0)
		s.fx.sparkle(global_position + Vector3(0, 0.6, 0))
		collected.emit(item)
		if item == "money":
			s.save.add("money", 100)
		queue_free()
