class_name Usable
extends Node3D
## Generic interactable (doors, roof stairs, beds, lecterns, hospital trays, shop counters, ladders).
## Press E to fire `on_use`; with hold_time > 0 the player must keep holding E nearby.

signal used(by: Node)

var prompt := "ব্যবহার করুন"
var interact_radius := 2.2
var enabled := true
var on_use: Callable
var hold_time := 0.0
var once := false
var _holding := false
var _progress := 0.0
var _bar: Label3D
var _by: Node

func _ready() -> void:
	add_to_group("interactable")

func can_interact(_p: Node) -> bool:
	return enabled

func interact_prompt() -> String:
	return prompt

func interact(p: Node) -> void:
	if not enabled:
		return
	if hold_time <= 0.0:
		_fire(p)
		return
	_holding = true
	_by = p
	if _bar == null:
		_bar = Label3D.new()
		_bar.font = BnText.font(true)
		_bar.font_size = 48
		_bar.pixel_size = 0.004
		_bar.outline_size = 10
		_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bar.no_depth_test = true
		_bar.position = Vector3(0, 1.4, 0)
		add_child(_bar)

func _process(delta: float) -> void:
	if not _holding:
		return
	var p3 := _by as Node3D
	if p3 == null or p3.global_position.distance_to(global_position) > interact_radius + 0.6 or not Input.is_action_pressed("interact"):
		_holding = false
		_progress = 0.0
		if _bar:
			_bar.text = ""
		return
	_progress += delta
	var n := int(clampf(_progress / hold_time, 0.0, 1.0) * 10.0)
	_bar.text = "■".repeat(n) + "□".repeat(10 - n)
	if _progress >= hold_time:
		_holding = false
		_progress = 0.0
		_bar.text = ""
		_fire(_by)

func _fire(p: Node) -> void:
	if once:
		enabled = false
	used.emit(p)
	if on_use.is_valid():
		on_use.call(p)
