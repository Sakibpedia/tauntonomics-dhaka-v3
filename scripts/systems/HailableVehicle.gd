class_name HailableVehicle
extends Node3D
## A rickshaw or CNG waiting for a fare. Placed by RideService; the Player's E / tap interaction
## opens the destination-and-payment panel.

var service: RideService
var kind := "rickshaw"
var interact_radius := 3.0

func setup(svc: RideService, k: String) -> void:
	service = svc
	kind = k

func can_interact(_p: Node) -> bool:
	return service != null and not service._riding

func interact_prompt() -> String:
	return ("রিকশা নিন" if kind == "rickshaw" else "সিএনজি নিন") + " — গন্তব্য বাছুন"

func interact(_p: Node) -> void:
	if service:
		service.open_destinations(self)
