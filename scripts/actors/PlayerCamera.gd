class_name PlayerCamera
extends Node3D
## Third-person camera: over-the-shoulder spring arm with collision, mouse/stick/touch look,
## aim zoom, sprint FOV kick, lock-on framing, trauma-based shake, and a longer arm in vehicles.

var s: Services
var target: Node3D
var arm: SpringArm3D
var cam: Camera3D
var yaw := 0.0
var pitch := -0.18
var sens := 0.0025
var aiming := false
var in_vehicle := false
var lock_target: Node3D
var _trauma := 0.0
var _noise_t := 0.0
var touch_look := Vector2.ZERO

func setup(services: Services, follow: Node3D) -> void:
	s = services
	target = follow
	arm = SpringArm3D.new()
	arm.spring_length = 3.6
	arm.collision_mask = 1
	arm.margin = 0.15
	var sph := SphereShape3D.new()
	sph.radius = 0.2
	arm.shape = sph
	add_child(arm)
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.08
	cam.far = 900.0
	arm.add_child(cam)
	cam.current = true
	s.fx.camera_shake = shake
	sens = float(s.save.setting("sens", 0.18)) * 0.014

func shake(strength: float) -> void:
	_trauma = minf(1.0, _trauma + strength)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * sens
		pitch = clampf(pitch - mm.relative.y * sens, -1.2, 0.75)

func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))

func right_flat() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var stick := Vector2(Input.get_axis("look_left", "look_right"), Input.get_axis("look_up", "look_down"))
	stick += touch_look
	touch_look = Vector2.ZERO
	yaw -= stick.x * delta * 2.6
	pitch = clampf(pitch - stick.y * delta * 1.8, -1.2, 0.75)
	if lock_target != null and is_instance_valid(lock_target):
		var to := lock_target.global_position - target.global_position
		var want := atan2(-to.x, -to.z)
		yaw = lerp_angle(yaw, want, 1.0 - exp(-delta * 6.0))
	var anchor := target.global_position + Vector3(0, 1.55, 0)
	global_position = global_position.lerp(anchor, 1.0 - exp(-delta * 14.0))
	rotation = Vector3(pitch, yaw, 0)
	var length := 6.5 if in_vehicle else (1.7 if aiming else 3.4)
	arm.spring_length = lerpf(arm.spring_length, length, 1.0 - exp(-delta * 8.0))
	var shoulder := 0.0 if in_vehicle else (0.55 if aiming else 0.42)
	arm.position = arm.position.lerp(Vector3(shoulder, 0.1, 0), 1.0 - exp(-delta * 8.0))
	var sprinting := target.has_method("is_sprinting") and bool(target.call("is_sprinting"))
	cam.fov = lerpf(cam.fov, 55.0 if aiming else (76.0 if sprinting else 68.0), 1.0 - exp(-delta * 5.0))
	# trauma shake
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	_noise_t += delta * 30.0
	var sh := _trauma * _trauma
	cam.position = Vector3(sin(_noise_t * 1.3) * 0.08 * sh, sin(_noise_t * 1.7 + 1.0) * 0.06 * sh, 0)
	cam.rotation = Vector3(sin(_noise_t * 1.1 + 2.0) * 0.03 * sh, 0, sin(_noise_t * 0.9) * 0.05 * sh)
