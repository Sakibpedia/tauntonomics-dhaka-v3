class_name BuildingPart
extends Node3D
## A hinged door or window of a WalkableBuilding. Exposes the Player interact interface so
## E / tap animates it open and closed.

var building: WalkableBuilding
var is_door := true
var interact_radius := 2.2

func setup(b: WalkableBuilding, door: bool) -> void:
	building = b
	is_door = door
	add_to_group("interactable")

func can_interact(_p: Node) -> bool:
	return building != null and is_instance_valid(building)

func interact_prompt() -> String:
	var open := bool(get_meta("open"))
	if is_door:
		return ("দরজা বন্ধ করুন" if open else "দরজা খুলুন") + " — " + str(get_meta("label", ""))
	return "জানালা " + ("বন্ধ করুন" if open else "খুলুন")

func interact(_p: Node) -> void:
	if building == null:
		return
	if is_door:
		building.toggle_door(self)
	else:
		building.toggle_window(self)
