class_name Projectile
extends Node3D
## Thrown objects: bricks and slippers from goons, books and bricks from the player, glowing
## question-papers from ghosts and the boss. Ballistic arc, swept ray collision, impact effects.

var s: Services
var vel := Vector3.ZERO
var owner_node: Node
var kind := "brick"
var damage := 10.0
var life := 4.0
var gravity := 9.8
var _mesh: MeshInstance3D
var _spin := Vector3.ZERO

func launch(services: Services, from: Vector3, target: Vector3, by: Node, k: String, dmg: float, speed: float = 16.0) -> void:
	s = services
	owner_node = by
	kind = k
	damage = dmg
	global_position = from
	if kind == "paper":
		gravity = 0.0
		speed = 9.0
	var to := target - from
	var flat := Vector3(to.x, 0, to.z)
	var t := maxf(flat.length() / speed, 0.2)
	vel = flat / t
	vel.y = (to.y + 0.5 * gravity * t * t) / t
	_spin = Vector3(randf_range(-12, 12), randf_range(-8, 8), randf_range(-12, 12))
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	match kind:
		"brick":
			bm.size = Vector3(0.1, 0.06, 0.2)
			_mesh.material_override = Humanoid.plain_material(Color(0.55, 0.25, 0.17), 0.95)
		"book":
			bm.size = Vector3(0.15, 0.04, 0.21)
			_mesh.material_override = Humanoid.plain_material(Color(0.42, 0.08, 0.08), 0.6)
		"slipper":
			bm.size = Vector3(0.1, 0.025, 0.26)
			_mesh.material_override = Humanoid.plain_material(Color(0.2, 0.35, 0.7), 0.7)
		"paper":
			bm.size = Vector3(0.3, 0.4, 0.01)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.95, 0.95, 0.85)
			m.emission_enabled = true
			m.emission = Color(0.5, 0.8, 1.0)
			m.emission_energy_multiplier = 2.0
			_mesh.material_override = m
			_spin = Vector3(0, 6, 0)
		_:
			bm.size = Vector3(0.1, 0.1, 0.1)
	_mesh.mesh = bm
	add_child(_mesh)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if kind == "paper" and s and s.player and is_instance_valid(s.player):
		var tgt: Vector3 = (s.player as Node3D).global_position + Vector3(0, 1.3, 0)
		vel = vel.lerp((tgt - global_position).normalized() * 9.0, delta * 1.2)
	vel.y -= gravity * delta
	var from := global_position
	var to := from + vel * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4 | 32)
	var ex: Array[RID] = []
	if owner_node is CollisionObject3D:
		ex.append((owner_node as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		_impact(hit)
		return
	global_position = to
	_mesh.rotation += _spin * delta

func _impact(hit: Dictionary) -> void:
	var col: Object = hit.get("collider")
	var pos: Vector3 = hit.get("position")
	if col != null and col.has_method("receive_hit"):
		col.call("receive_hit", damage, global_position - vel.normalized(), owner_node, "throw")
	if s:
		if kind == "paper":
			s.fx.paper(pos, 12)
			s.sfx.play_at("page", pos, -2.0)
		else:
			s.fx.dust(pos, 8)
			s.sfx.play_at("thwack", pos, -4.0, randf_range(0.9, 1.2))
		s.bus.noise.emit(pos, 10.0, "impact")
	queue_free()
