class_name Ragdoll
extends Node3D
## Jolt ragdoll built from the live Humanoid pose, so the hand-off from animation is seamless.
## Capsule bodies per segment with cone-twist joints, the rig's merged meshes re-parented onto them,
## then a fade-out.

var bodies: Dictionary = {}
var life := 6.0
var _t := 0.0
var _meshes: Array[MeshInstance3D] = []

func build(rig: Humanoid, impulse: Vector3, inherit_vel: Vector3, life_time: float = 6.0) -> void:
	life = life_time
	var specs: Array = rig.segment_specs()
	var groups: Dictionary = rig.ragdoll_groups()
	var hs := rig.h
	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	pm.bounce = 0.08
	for sp in specs:
		var sd: Dictionary = sp
		var nm := str(sd["n"])
		var j: Node3D = sd["j"]
		var body := RigidBody3D.new()
		body.collision_layer = 1 << 4
		body.collision_mask = 1
		body.mass = maxf(float(sd["r"]) * float(sd["l"]) * 70.0, 0.4)
		body.linear_damp = 0.3
		body.angular_damp = 1.5
		body.physics_material_override = pm
		add_child(body)
		var gt := j.global_transform
		body.global_transform = Transform3D(gt.basis.orthonormalized(), gt.origin)
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = float(sd["r"]) * hs
		cap.height = maxf(float(sd["l"]) * hs, cap.radius * 2.0 + 0.01)
		shape.shape = cap
		shape.position = Vector3(0, float(sd["o"]) * float(sd["l"]) * hs * 0.5, 0)
		body.add_child(shape)
		for src in groups.get(nm, [j]):
			var srcn: Node3D = src
			for c in srcn.get_children():
				if c is MeshInstance3D:
					var mi := c as MeshInstance3D
					var copy := MeshInstance3D.new()
					copy.mesh = mi.mesh
					copy.material_override = mi.material_override
					for i in mi.get_surface_override_material_count():
						copy.set_surface_override_material(i, mi.get_surface_override_material(i))
					body.add_child(copy)
					copy.global_transform = mi.global_transform
					_meshes.append(copy)
				elif c is Node3D and not rig.joints.values().has(c):
					# face details live on helper nodes (eyes)
					for cc in (c as Node3D).get_children():
						if cc is MeshInstance3D:
							var mi2 := cc as MeshInstance3D
							var copy2 := MeshInstance3D.new()
							copy2.mesh = mi2.mesh
							copy2.material_override = mi2.material_override
							body.add_child(copy2)
							copy2.global_transform = mi2.global_transform
		bodies[nm] = body
	for sp in specs:
		var sd2: Dictionary = sp
		var parent := str(sd2["p"])
		if parent == "" or not bodies.has(parent):
			continue
		var cj := ConeTwistJoint3D.new()
		add_child(cj)
		var jn: Node3D = sd2["j"]
		cj.global_transform = Transform3D(Basis(), jn.global_position)
		var is_head := str(sd2["n"]) == "head"
		cj.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, 0.5 if is_head else 1.0)
		cj.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, 0.3 if is_head else 0.5)
		cj.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.9)
		cj.node_a = cj.get_path_to(bodies[parent])
		cj.node_b = cj.get_path_to(bodies[str(sd2["n"])])
	for k in bodies.keys():
		var b: RigidBody3D = bodies[k]
		b.linear_velocity = inherit_vel + Vector3(randf_range(-0.4, 0.4), randf_range(0.2, 1.0), randf_range(-0.4, 0.4))
		b.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
	if bodies.has("torso"):
		(bodies["torso"] as RigidBody3D).apply_central_impulse(impulse)

func center() -> Vector3:
	if bodies.has("torso") and is_instance_valid(bodies["torso"]):
		return (bodies["torso"] as RigidBody3D).global_position
	return global_position

func _physics_process(delta: float) -> void:
	_t += delta
	if _t > life:
		var a := clampf(1.0 - (_t - life) / 1.0, 0.0, 1.0)
		for m in _meshes:
			if is_instance_valid(m):
				m.transparency = 1.0 - a
		if a <= 0.0:
			queue_free()
