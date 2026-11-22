extends Node3D
## Test bench: a line-up of procedural citizens in every outfit, walking, talking and posing.

var rigs: Array[Humanoid] = []
var cam: Camera3D

func _ready() -> void:
	var atmo := DhakaAtmosphere.new()
	atmo.preset = DhakaAtmosphere.Preset.HAZE_NOON
	add_child(atmo)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	ground.material_override = load("res://assets/textures/pavers_checker/pavers_checker.tres")
	add_child(ground)
	var looks := [
		{"sex": "m", "outfit": "coat", "hair": "short", "beard": "full", "age": 0.2, "colors": ["#16171b", "#f2f2f2"]},
		{"sex": "m", "outfit": "lungi_vest", "hair": "short", "beard": "stubble", "gamchha": true, "age": 0.35, "colors": ["#2a4f7a", "#c63b3b"]},
		{"sex": "f", "outfit": "saree", "hair": "bun", "age": 0.6, "colors": ["#2f6b4f", "#e7c35a"]},
		{"sex": "m", "outfit": "panjabi", "hair": "cap_white", "beard": "full", "glasses": true, "age": 0.95, "colors": ["#efe9dc", "#8a6d3b"]},
		{"sex": "f", "outfit": "salwar", "hair": "hijab", "age": 0.2, "colors": ["#6b3f7a", "#e6dcc6"]},
		{"sex": "f", "outfit": "tshirt_jeans", "hair": "long", "glasses": true, "age": 0.15, "colors": ["#3a3a3a", "#7a2fd6"]},
		{"sex": "m", "outfit": "goon", "hair": "short", "beard": "stubble", "age": 0.35, "colors": ["#101010", "#a61b1b"]},
		{"sex": "m", "outfit": "uniform_police", "hair": "short", "beard": "moustache", "age": 0.45, "colors": ["#5b5a3c", "#2c2c2c"]},
		{"sex": "f", "outfit": "labcoat", "hair": "bun", "glasses": true, "age": 0.4, "colors": ["#f4f4f4", "#2b6cb0"]},
		{"sex": "m", "outfit": "suit", "hair": "bald", "beard": "full", "glasses": true, "age": 1.0, "colors": ["#2a2018", "#c9a227"]},
	]
	for i in looks.size():
		var hmn := Humanoid.new()
		add_child(hmn)
		hmn.setup(looks[i])
		hmn.position = Vector3((i - looks.size() / 2.0 + 0.5) * 0.9, 0, 0)
		hmn.rotation.y = PI
		rigs.append(hmn)
	cam = Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.45, 3.4)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.fov = 50
	var close := OS.get_environment("LINEUP_CLOSE")
	if close != "":
		var i := int(close)
		var x := (i - looks.size() / 2.0 + 0.5) * 0.9
		cam.position = Vector3(x + 0.45, 1.6, 1.25)
		cam.look_at(Vector3(x + 0.45, 1.55, 0))
		cam.fov = 32

func _process(delta: float) -> void:
	for i in rigs.size():
		var r := rigs[i]
		r.look_target = cam.global_position
		r.talking = false
		r.animate(delta, Vector3.ZERO, true)
