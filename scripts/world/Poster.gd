class_name Poster
extends Node3D
## Wheat-pasted wall poster. Kinds:
##   bcs_quiz       a live BCS/job/bar question (from the bank): answer it for money
##   coaching_ad    "সাত দিনে ক্যাডার": tear it down, Sakib comments
##   home_eco_ad    self-styled "clinical nutritionist" ads: inspect the fine print
##   govt_notice    the law, as printed
##   syndicate_code coded Syndicate messages (mission intel)
##   missing        satirical "missing" notices

var s: Services
var kind := "bcs_quiz"
var text := ""
var question: Dictionary = {}
var done := false
var interact_radius := 2.4
var _label: Label3D
var _head: Label3D
var _stamp: Label3D

const HEADERS := {"bcs_quiz": ["বিসিএস প্রস্তুতি", Color("#1d4f93")], "coaching_ad": ["ভর্তি চলছে!", Color("#c0262d")],
	"home_eco_ad": ["পুষ্টি পরামর্শ", Color("#1f8a4c")], "govt_notice": ["সরকারি বিজ্ঞপ্তি", Color("#2f2f2f")],
	"syndicate_code": ["বিজ্ঞপ্তি", Color("#6b4a2a")], "missing": ["নিখোঁজ", Color("#111111")]}

func setup(services: Services, k: String, body_text: String, q: Dictionary = {}) -> void:
	s = services
	kind = k
	text = body_text
	question = q
	add_to_group("interactable")
	add_to_group("posters")
	var paper := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.9, 1.25)
	paper.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/paper_aged/paper_aged_albedo.png")
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/paper_aged/paper_aged_normal.png")
	m.roughness = 0.9
	paper.material_override = m
	paper.position = Vector3(0, 0, 0.012)
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paper)
	var hd: Array = HEADERS.get(kind, ["", Color.BLACK])
	var band := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(0.86, 0.2)
	band.mesh = bq
	band.material_override = Humanoid.plain_material(hd[1] as Color, 0.8)
	band.position = Vector3(0, 0.5, 0.014)
	add_child(band)
	_head = _lbl(str(hd[0]), 56, Color(1, 0.97, 0.9), Vector3(0, 0.5, 0.017), true)
	var body_txt := text
	if kind == "bcs_quiz" and not question.is_empty():
		body_txt = str(question.get("q", ""))
		var opts: Array = question.get("o", [])
		for i in opts.size():
			body_txt += "\n%s) %s" % [BnText.OPTION_LETTERS[i], str(opts[i])]
	_label = _lbl(body_txt, 30, Color(0.1, 0.08, 0.06), Vector3(0, -0.08, 0.017), false)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = 760
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _lbl(t: String, size: int, c: Color, pos: Vector3, bold: bool) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.font = BnText.font(bold)
	l.font_size = size
	l.pixel_size = 0.001
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	l.double_sided = false
	l.visibility_range_end = 30.0
	add_child(l)
	return l

func can_interact(_p: Node) -> bool:
	return not done or kind == "govt_notice"

func interact_prompt() -> String:
	match kind:
		"bcs_quiz": return "পোস্টারের প্রশ্নের উত্তর দিন"
		"coaching_ad": return "কোচিংয়ের পোস্টার ছিঁড়ে ফেলুন"
		"home_eco_ad": return "ছোট অক্ষরের লেখা পড়ুন (ম্যাগনিফাইং গ্লাস)"
		"syndicate_code": return "সাংকেতিক বিজ্ঞপ্তি পড়ুন"
	return "পড়ুন"

func interact(_p: Node) -> void:
	match kind:
		"bcs_quiz":
			if s.ui:
				s.ui.call("open_poster_exam", self)
		"coaching_ad":
			done = true
			s.sfx.play("page", 0.0)
			s.fx.paper(global_position, 18)
			s.say("সাকিব", s.taunts.pick("homeco") if randf() < 0.4 else "সাত দিনে ক্যাডার হয় না, সাত দিনে শুধু টাকা হাতবদল হয়।", 4.0)
			s.save.add("posters", 1)
			s.bus.poster_answered.emit(kind, true)
			queue_free()
		"home_eco_ad":
			done = true
			s.sfx.play("page", -4.0)
			_label.text += "\n\n* নিবন্ধন নম্বর: নেই\n* 'ক্লিনিক্যাল' শব্দটি সাজসজ্জার জন্য\n* রোগ সারলে কৃতিত্ব আমাদের, না সারলে আপনার"
			s.say("সাকিব", s.taunts.pick("homeco"), 5.0)
			s.save.add("posters", 1)
			s.bus.poster_answered.emit(kind, true)
		"syndicate_code":
			done = true
			s.sfx.play("notify", -4.0)
			s.toast("সাংকেতিক বিজ্ঞপ্তি পড়লেন: '%s'" % text.replace("\n", " "), "intel")
			s.save.add("intel", 1)
			s.bus.poster_answered.emit(kind, true)
			_mark("✓ পড়া হয়েছে")
		_:
			s.toast(text.replace("\n", " "), "info")

func answered(correct: bool) -> void:
	done = true
	s.bus.poster_answered.emit(kind, correct)
	if correct:
		s.save.add("money", 60)
		s.save.add("posters", 1)
		_mark("✓ সঠিক")
	else:
		_mark("✗ ভুল")
		if s.heat and randf() < 0.35:
			s.heat.add(0.6, "পোস্টারে ভুল উত্তর: সিন্ডিকেটের খবরি দেখেছে")

func _mark(t: String) -> void:
	if _stamp == null:
		_stamp = _lbl(t, 90, Color(0.75, 0.1, 0.1), Vector3(0, -0.15, 0.02), true)
		_stamp.rotation.z = 0.35
	else:
		_stamp.text = t
