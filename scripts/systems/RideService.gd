class_name RideService
extends Node
## Hailable Dhaka rickshaws and CNGs with a real fare exchange (BRTA fare table in
## DhakaDistricts.VEHICLES). Walk up to a waiting vehicle, press E / tap the on-screen
## button, choose a destination and pay. A short ride animation carries Sakib there.

const VModels = preload("res://scripts/systems/VehicleModels.gd")
const DD = preload("res://scripts/world/DhakaDistricts.gd")

var s: Services
var hailable: Array = []
var _t := 0.0
var _riding := false
var _panel: Control
var _ride_vehicle: Node3D
var _ride_kind := "rickshaw"
var _ride_dest := Vector3.ZERO
var _qa_once := false

const DEST_NAMES := {
	"safehouse": "সাকিবের বাড়ি (সেফহাউস)", "tea_stall": "নাসিমা খালার চা-দোকান", "square": "চত্বর",
	"market": "বাজার / সুপারমার্কেট", "bus_stand": "বাস স্ট্যান্ড", "hospital": "হাসপাতাল",
	"printing": "প্রিন্টিং প্রেস", "coaching": "কোচিং সেন্টার", "bank": "ব্যাংক",
	"ghat": "ঘাট / ওয়াটার পাম্প", "den": "সিন্ডিকেট আড্ডা", "alley": "গলি", "roof_extract": "ছাদ",
}

func setup(services: Services) -> void:
	s = services

func _process(delta: float) -> void:
	if _riding or s.player == null or not is_instance_valid(s.player):
		return
	_t -= delta
	if OS.get_environment("DHAKA_RIDE") != "" and not _qa_once:
		_qa_once = true
		var pp0 := (s.player as Node3D).global_position
		_spawn_hailable(pp0)
		if hailable.size() > 0:
			open_destinations(hailable[hailable.size() - 1])
	if _t <= 0.0:
		_t = 1.0
		# keep at most two hailable vehicles near the player
		var pp := (s.player as Node3D).global_position
		hailable = hailable.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and n.global_position.distance_to(pp) < 90.0)
		if hailable.size() < 2 and pp.y < 8.0:
			_spawn_hailable(pp)

func _spawn_hailable(pp: Vector3) -> void:
	var w := s.world as ProceduralDhaka
	if w == null:
		return
	var kind := "rickshaw" if randf() < 0.6 else "cng"
	var model: Node3D = VModels.make(kind)
	if model == null:
		return
	VModels.no_shadows(model)
	var hv := preload("res://scripts/systems/HailableVehicle.gd")
	var v: Node3D = hv.new()
	v.name = "Hail_%s" % kind
	(v as Node).call("setup", self, kind)
	v.add_child(model)
	# park it on a nearby street / footpath, facing the road
	var b := w.block_of(pp)
	var k := Vector2i(b.x + randi_range(-2, 2), b.y + randi_range(-2, 2))
	var f := w.footprint(k.x, k.y)
	var spot := Vector3(lerpf(f.position.x + 2.0, f.end.x - 2.0, randf()), 0.0, f.position.y - 2.6)
	v.set_meta("kind", kind)
	v.set_meta("interact_radius", 3.0)
	v.add_to_group("interactable")
	s.world.add_child(v)
	v.global_position = spot
	v.rotation.y = randf_range(-0.3, 0.3)
	hailable.append(v)

# ---- interactable interface (called by Player._scan_interactables / _interact) ----
func can_interact(_p: Node) -> bool:
	return not _riding

func interact_prompt() -> String:
	return "রিকশা/সিএনজি নিন — গন্তব্য বাছুন"

func interact(_p: Node) -> void:
	# Player calls interact() on the *vehicle*, not on this service; see _vehicle_interact below.
	pass

func open_destinations(v: Node3D) -> void:
	if _riding or v == null:
		return
	_ride_vehicle = v
	_ride_kind = str(v.get_meta("kind"))
	_build_panel()

func _build_panel() -> void:
	_close_panel()
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)
	var pc := PanelContainer.new()
	UiKit.place(pc, Control.PRESET_CENTER, Vector2(-420, -420), Vector2(840, 840))
	_panel.add_child(pc)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	pc.add_child(vbox)
	var head := Label.new()
	head.text = "%s — গন্তব্য বাছুন" % ("রিকশা" if _ride_kind == "rickshaw" else "সিএনজি")
	head.add_theme_font_override("font", BnText.font(true))
	head.add_theme_font_size_override("font_size", 32)
	vbox.add_child(head)
	var info := Label.new()
	info.text = "ভাড়া: %s" % ("আলোচনীয়, সস্তা" if _ride_kind == "rickshaw" else "৳৪০ প্রথম ২ কিমি, পরে ৳১২/কিমি")
	info.add_theme_font_override("font", BnText.font(false))
	info.add_theme_font_size_override("font_size", 20)
	vbox.add_child(info)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 640)
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var w := s.world as ProceduralDhaka
	var pp := (s.player as Node3D).global_position
	var names: Dictionary = DEST_NAMES.duplicate()
	for key in w.pois.keys():
		var dest: Vector3 = w.pois[key]
		var km := pp.distance_to(dest) / 1000.0
		var fare := DD.vehicle_fare(_ride_kind, maxf(km, 0.6))
		var btn := Button.new()
		btn.text = "%s   —   ৳%s" % [str(names.get(str(key), str(key))), BnText.num(fare)]
		btn.add_theme_font_override("font", BnText.font(false))
		btn.add_theme_font_size_override("font_size", 24)
		btn.pressed.connect(_pay_and_ride.bind(dest, fare))
		list.add_child(btn)
	var cancel := Button.new()
	cancel.text = "বাতিল"
	cancel.custom_minimum_size = Vector2(780, 60)
	cancel.add_theme_font_override("font", BnText.font(true))
	cancel.add_theme_font_size_override("font_size", 24)
	cancel.pressed.connect(_close_panel)
	vbox.add_child(cancel)
	s.ui.get_child(0).add_child(_panel)
	s.ui.push_modal(true)

func _close_panel() -> void:
	if _panel and is_instance_valid(_panel):
		s.ui.pop_modal(true)
		_panel.queue_free()
	_panel = null

func _pay_and_ride(dest: Vector3, fare: int) -> void:
	if s.save.money() < fare:
		s.toast("টাকা নেই! ভাড়া ৳%s" % BnText.num(fare), "bad")
		return
	s.save.spend(fare)
	_close_panel()
	_riding = true
	_ride_dest = dest
	var p := s.player as Player
	p.controls_enabled = false
	p.visible = false
	p.collision_layer = 0
	p.collision_mask = 0
	var cam := s.camera as PlayerCamera
	cam.target = _ride_vehicle
	cam.in_vehicle = true
	s.toast("৳%s ভাড়া দেওয়া হয়েছে — যাত্রা শুরু" % BnText.num(fare), "money")
	# Drive along the block grid in two axis-aligned legs (roads), then dismount.
	var start: Vector3 = _ride_vehicle.global_position
	var mid := Vector3(start.x, 0.0, dest.z)
	var speed := 16.0 if _ride_kind == "cng" else 7.0
	var leg1 := maxf(0.4, start.distance_to(mid) / speed)
	var leg2 := maxf(0.4, mid.distance_to(dest) / speed)
	var tw := create_tween()
	tw.tween_method(_move_vehicle.bind(start, mid), 0.0, 1.0, leg1)
	tw.tween_method(_move_vehicle.bind(mid, dest), 0.0, 1.0, leg2)
	tw.tween_callback(_finish_ride)

func _move_vehicle(t: float, a: Vector3, b: Vector3) -> void:
	if _ride_vehicle and is_instance_valid(_ride_vehicle):
		var pos := a.lerp(b, t)
		_ride_vehicle.global_position = pos
		var d := b - a
		if d.length() > 0.1 and _ride_vehicle.get_child(0) is Node3D:
			(_ride_vehicle.get_child(0) as Node3D).rotation.y = atan2(-d.x, -d.z)

func _finish_ride() -> void:
	var p := s.player as Player
	if p and is_instance_valid(p):
		p.global_position = _ride_dest + Vector3(0, 0.3, 1.2)
		p.visible = true
		p.collision_layer = Actor.LAYER_PLAYER
		p.collision_mask = Actor.LAYER_WORLD | Actor.LAYER_ACTOR | Actor.LAYER_VEHICLE
		p.controls_enabled = true
	var cam := s.camera as PlayerCamera
	cam.target = p
	cam.in_vehicle = false
	if _ride_vehicle and is_instance_valid(_ride_vehicle):
		# the driver waits here for the next fare
		_ride_vehicle.set_meta("parked", true)
	_riding = false
	_ride_vehicle = null
