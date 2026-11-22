class_name ActorVisuals
extends Node3D
## Everything you see of an actor apart from the body motion itself: the Humanoid rig, a floating
## name and role tag, a speech bubble for barks, and a marker icon (exam giver, objective, alert,
## question mark when suspicious). Faces/eyes switch off with distance (LOD).

const ICONS := {
	"exam": "res://ui/svg/marker_exam.svg", "objective": "res://ui/svg/marker_objective.svg",
	"danger": "res://ui/svg/marker_danger.svg", "intel": "res://ui/svg/marker_intel.svg",
}

var body: Humanoid
var tag: Label3D
var bubble: Label3D
var icon: Sprite3D
var _bubble_t := 0.0
var _icon_kind := ""
var alert_level := 0.0      # 0..1 detection meter shown as a growing "!"
var alert_label: Label3D

func build(look: Dictionary, display_name: String, role: String) -> void:
	body = Humanoid.new()
	body.name = "Body"
	add_child(body)
	body.setup(look)
	var top := 1.95 * body.h
	tag = Label3D.new()
	tag.text = display_name + ("\n" + role if role != "" else "")
	tag.font = BnText.font(true)
	tag.font_size = 40
	tag.pixel_size = 0.0022
	tag.visibility_range_begin = 1.5
	tag.outline_size = 10
	tag.outline_modulate = Color(0, 0, 0, 0.85)
	tag.modulate = Color(1, 0.95, 0.85)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, top, 0)
	tag.visible = false
	tag.fixed_size = false
	add_child(tag)
	bubble = Label3D.new()
	bubble.font = BnText.font(false)
	bubble.font_size = 40
	bubble.pixel_size = 0.0019
	bubble.visibility_range_begin = 2.6
	bubble.visibility_range_end = 26.0
	bubble.outline_size = 12
	bubble.outline_modulate = Color(0.05, 0.05, 0.05, 0.9)
	bubble.modulate = Color(1, 1, 1)
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.width = 800
	bubble.position = Vector3(0, top + 0.35, 0)
	bubble.visible = false
	bubble.no_depth_test = true
	add_child(bubble)
	icon = Sprite3D.new()
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.pixel_size = 0.006
	icon.position = Vector3(0, top + 0.25, 0)
	icon.no_depth_test = true
	icon.visible = false
	add_child(icon)
	alert_label = Label3D.new()
	alert_label.text = "!"
	alert_label.font = BnText.font(true)
	alert_label.font_size = 96
	alert_label.pixel_size = 0.004
	alert_label.outline_size = 16
	alert_label.modulate = Color(1, 0.85, 0.2)
	alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert_label.position = Vector3(0, top + 0.2, 0)
	alert_label.no_depth_test = true
	alert_label.visible = false
	add_child(alert_label)

func say(text: String, seconds: float = 3.0) -> void:
	if bubble == null:
		return
	bubble.text = text
	bubble.visible = true
	_bubble_t = seconds
	body.talking = true

func set_icon(kind: String) -> void:
	if kind == _icon_kind:
		return
	_icon_kind = kind
	if kind == "" or not ICONS.has(kind):
		icon.visible = false
		return
	icon.texture = load(str(ICONS[kind]))
	icon.visible = true

func show_tag(on: bool) -> void:
	if tag:
		tag.visible = on

func set_lod(far: bool) -> void:
	if body:
		body.lod_far = far

func _process(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			bubble.visible = false
			body.talking = false
	if icon and icon.visible:
		icon.position.y = 1.95 * body.h + 0.25 + sin(Time.get_ticks_msec() * 0.004) * 0.05
	if alert_label:
		alert_label.visible = alert_level > 0.05
		if alert_label.visible:
			alert_label.modulate = Color(1, 0.85, 0.2).lerp(Color(1, 0.15, 0.1), alert_level)
			alert_label.scale = Vector3.ONE * lerpf(0.4, 1.2, alert_level)
