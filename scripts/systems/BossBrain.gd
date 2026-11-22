class_name BossBrain
extends Node
## মহাপরীক্ষক, the Grand Examiner. Floats in a cloak of exam papers that makes him nearly invulnerable
## (armour 0.92). Each lectern exam the player passes tears off a third of it. He throws homing
## question papers, summons question-ghosts in daylight on his roof, and lectures. With the armour
## gone he can be beaten down, and then it is the player's choice, as with everyone.

var s: Services
var boss: Actor
var _throw_t := 3.0
var _summon_t := 12.0
var _talk_t := 4.0
var armor_left := 3
var _papers: Array[MeshInstance3D] = []

const LINES := ["প্রশ্ন আমি বানাই, উত্তরও আমি বেচি।", "তুমি তিনবার ভাইভায় বাদ পড়েছিলে। কারণ তোমার জায়গা আমি বিক্রি করেছিলাম।",
	"সিলেবাস পুরোনো রাখি, যাতে কোচিং নতুন থাকে।", "পদবি বেচি, কারণ যোগ্যতা বেচা যায় না।", "এই শহরে প্রতিটি প্রশ্নের নিচে আমার জলছাপ।",
	"তোমার আইনের বই আমার প্রশ্নপত্রের কাছে শুধু কাগজ।"]

func setup(services: Services, b: Actor) -> void:
	s = services
	boss = b
	for k in 14:
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.35, 0.45)
		m.mesh = q
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.94, 0.86)
		mat.emission_enabled = true
		mat.emission = Color(0.9, 0.3, 0.2)
		mat.emission_energy_multiplier = 0.8
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.material_override = mat
		boss.add_child(m)
		_papers.append(m)
	s.ui.call("banner_show", "মহাপরীক্ষক", "লেকটার্নে পরীক্ষা দিয়ে তার কাগজের বর্ম ভাঙুন।", UiKit.SIGNAL_RED, 5.0)

func crack(n: int) -> void:
	armor_left = 3 - n
	boss.health.armor = [0.0, 0.45, 0.7, 0.92][armor_left]
	s.fx.paper(boss.head_pos(), 40)
	s.sfx.play("shatter", 0.0)
	s.fx.shake(0.6)
	var keep := int(_papers.size() * armor_left / 3.0)
	for i in _papers.size():
		_papers[i].visible = i < keep
	boss.say(["আমার বর্ম! কে শিখিয়েছে তোমাকে এসব?", "এ প্রশ্ন তো ফাঁস হয়নি!", "অসম্ভব... কোচিং ছাড়া পাস?"][clampi(n - 1, 0, 2)], 3.5, true)
	if armor_left == 0:
		s.ui.call("banner_show", "বর্ম ভেঙেছে!", "এবার লড়াই। পরাস্ত করে সিদ্ধান্ত নিন।", UiKit.SAFFRON, 4.0)

func _process(delta: float) -> void:
	if boss == null or not is_instance_valid(boss) or boss.health.is_down or boss.dead:
		return
	var t := Time.get_ticks_msec() / 1000.0
	for i in _papers.size():
		var a := t * 1.4 + TAU * i / _papers.size()
		_papers[i].position = Vector3(cos(a) * 0.9, 0.6 + sin(a * 2.0 + i) * 0.6 + float(i % 3) * 0.4, sin(a) * 0.9)
		_papers[i].rotation = Vector3(0.3, -a, 0.2)
	var p := s.player as Node3D
	if p == null:
		return
	_talk_t -= delta
	if _talk_t <= 0.0:
		_talk_t = randf_range(8.0, 12.0)
		boss.say(LINES[randi() % LINES.size()], 4.0, true)
	_throw_t -= delta
	if _throw_t <= 0.0:
		_throw_t = randf_range(2.2, 3.5) if armor_left > 0 else randf_range(3.5, 5.0)
		for k in (2 if armor_left > 1 else 1):
			var pr := Projectile.new()
			boss.get_parent().add_child(pr)
			pr.launch(s, boss.head_pos() + Vector3(randf_range(-0.5, 0.5), 0.3, 0), p.global_position + Vector3(0, 1.3, 0), boss, "paper", 9.0)
		boss.body.play("cast")
	_summon_t -= delta
	if _summon_t <= 0.0 and armor_left > 0:
		_summon_t = 18.0
		if s.ghosts:
			s.ghosts.call("spawn_random_near", boss.global_position, true)
