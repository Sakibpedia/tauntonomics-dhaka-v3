class_name DebatePanel
extends Control
## Protest encounters are won with arguments, not fists. The leader makes claims; you answer each
## with a tactic card: সনদ যাচাই (magnifier on the certificate), আইনের ধারা, পাঠ্যসূচি তুলনা,
## রোগীর সাক্ষ্য (strong only if you gave patients good advice in the hospital), পাল্টা প্রশ্ন (answer a
## BCS question live), সহমর্মিতা, টাকার উৎস (needs intel), নীরবতা. The best card lowers the crowd's
## conviction and protesters peel off and join you. A wrong card raises their anger, and slippers fly.

var s: Services
var ui: UIRoot
var data: Dictionary = {}
var claims: Array = []
var ci := 0
var conviction := 100.0
var anger := 0.0
var crowd: Array = []
var cb: Callable
var used: Dictionary = {}
var title_l: Label
var claim_l: RichTextLabel
var reply_l: RichTextLabel
var conv_bar: TextureProgressBar
var anger_bar: TextureProgressBar
var grid: GridContainer
var _wait := false

func setup(services: Services, root: UIRoot) -> void:
	s = services
	ui = root
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pc := PanelContainer.new()
	UiKit.place(pc, Control.PRESET_CENTER, Vector2(-760, -440), Vector2(1520, 880))
	add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	title_l = ui._lbl("", 32, Color("ffd27a"), true)
	v.add_child(title_l)
	var meters := HBoxContainer.new()
	v.add_child(meters)
	meters.add_child(ui._lbl("জনতার বিশ্বাস", 20))
	conv_bar = UiKit.make_bar("stealth")
	conv_bar.custom_minimum_size = Vector2(420, 28)
	conv_bar.nine_patch_stretch = true
	meters.add_child(conv_bar)
	meters.add_child(ui._lbl("   ক্ষোভ", 20))
	anger_bar = UiKit.make_bar("health")
	anger_bar.custom_minimum_size = Vector2(420, 28)
	anger_bar.nine_patch_stretch = true
	meters.add_child(anger_bar)
	claim_l = _rich(30)
	claim_l.custom_minimum_size = Vector2(1460, 110)
	v.add_child(claim_l)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	reply_l = _rich(24)
	reply_l.custom_minimum_size = Vector2(1460, 200)
	v.add_child(reply_l)

func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.add_theme_font_override("normal_font", BnText.font(false))
	r.add_theme_font_override("bold_font", BnText.font(true))
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	return r

func open(id: String, crowd_actors: Array, done: Callable) -> void:
	data = s.story.debate(id)
	claims = data.get("claims", [])
	ci = 0
	conviction = 100.0
	anger = 0.0
	used = {}
	crowd = crowd_actors
	cb = done
	title_l.text = str(data.get("title", "বিতর্ক"))
	visible = true
	ui.push_modal(true)
	_show_claim()

func _leader() -> String:
	return s.story.char_name(str(data.get("leader", "")))

func _show_claim() -> void:
	_wait = false
	conv_bar.value = conviction
	anger_bar.value = anger
	if ci >= claims.size() or anger >= 100.0:
		_finish()
		return
	var c: Dictionary = claims[ci]
	claim_l.text = "[b][color=#ff9d7a]%s:[/color][/b] “%s”" % [_leader(), str(c.get("text", ""))]
	if bool(s.save.setting("tts", true)):
		Speech.speak(str(c.get("text", "")))
	for ch in grid.get_children():
		grid.remove_child(ch)
		ch.queue_free()
	var good_patients := 0
	for v in (s.save.g("patients", {}) as Dictionary).values():
		if str(v) == "good":
			good_patients += 1
	for key in s.story.cards.keys():
		var card: Dictionary = s.story.cards[key]
		var b := Button.new()
		b.text = "%s\n%s" % [str(card["name"]), str(card["desc"])]
		b.custom_minimum_size = Vector2(360, 92)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 17)
		if str(key) == "leak" and int(s.save.g("intel", 0)) <= 0:
			b.disabled = true
			b.text += "\n(ইন্টেল লাগবে)"
		if str(key) == "testimony" and good_patients == 0:
			b.text += "\n(সাক্ষী দুর্বল)"
		b.pressed.connect(_play.bind(str(key)))
		grid.add_child(b)
	reply_l.text = "[color=#a09a8a]একটি কৌশল বেছে নিন।[/color]"

func _play(card: String) -> void:
	if _wait:
		return
	_wait = true
	var c: Dictionary = claims[ci]
	if card == "exam":
		var q := s.qdb.draw(["bcs", "law"], 2)
		var after := func(passed: bool, _c: int, _t: int) -> void:
			_resolve(card if passed else "__bad", c)
		ui.open_exam([q], "পাল্টা প্রশ্ন: জনতার সামনে", _leader(), 1, after, "debate")
		return
	_resolve(card, c)

func _resolve(card: String, c: Dictionary) -> void:
	var best := str(c.get("best", ""))
	var ok: Array = c.get("ok", [])
	var good_patients := 0
	for v in (s.save.g("patients", {}) as Dictionary).values():
		if str(v) == "good":
			good_patients += 1
	var grade := "bad"
	if card == best:
		grade = "best"
	elif ok.has(card):
		grade = "ok"
	if card == "testimony" and grade == "best" and good_patients < 2:
		grade = "ok"
	if card == "leak" and grade != "bad":
		s.save.add("intel", -1)
	var step := 100.0 / maxf(1.0, claims.size())
	match grade:
		"best":
			conviction -= step * 1.15
			reply_l.text = "[b][color=#7dff9a]সাকিব:[/color][/b] %s\n[color=#7dff9a]জনতার একাংশ চুপ হয়ে গেল, কেউ কেউ হাততালি দিল।[/color]" % str(c.get("reply", ""))
			s.sfx.play("sting_win", -6.0)
			_convert(2)
		"ok":
			conviction -= step * 0.55
			reply_l.text = "[b][color=#ffd27a]সাকিব:[/color][/b] %s\n[color=#ffd27a]যুক্তি ঠিক, তবে সবাই মানল না।[/color]" % str(c.get("reply", ""))
			s.sfx.play("ding", -6.0)
			_convert(1)
		_:
			anger += 34.0
			var fail := str(c.get("fail", ""))
			reply_l.text = "[b][color=#ff8a80]ভুল কৌশল![/color][/b] %s\n[color=#ff8a80]জনতা স্যান্ডেল ছুড়ছে! (স্যানিটি কমছে)[/color]" % (fail if fail != "" else s.taunts.pick("protest_chant"))
			s.sfx.play("wrong", -2.0)
			if s.player:
				s.player.call("drain_sanity", 7.0)
			for a in crowd:
				if is_instance_valid(a):
					(a as Actor).body.play("slogan")
	if bool(s.save.setting("tts", true)):
		Speech.speak(str(c.get("reply", "")) if grade != "bad" else "ভুল কৌশল")
	ci += 1
	conv_bar.value = conviction
	anger_bar.value = anger
	var t := get_tree().create_timer(3.2, true, false, true)
	t.timeout.connect(_show_claim)

func _convert(n: int) -> void:
	var k := 0
	for a in crowd:
		if k >= n:
			break
		var ac := a as Actor
		if ac and is_instance_valid(ac) and ac.ai.state == ActorAI.State.PROTEST:
			ac.ai.set_state(ActorAI.State.STAND)
			ac.body.play("clap")
			ac.body.expression = "smug"
			ac.say(["ঠিকই তো বলছে!", "আমরা আসলে প্রতারিত হয়েছি...", "পদবি না, যোগ্যতা চাই।", "কোচিংওয়ালাদের ধরেন!"][randi() % 4], 3.0)
			k += 1

func _finish() -> void:
	var won := conviction <= 50.0 and anger < 100.0
	for ch in grid.get_children():
		grid.remove_child(ch)
		ch.queue_free()
	if won:
		claim_l.text = "[b][color=#7dff9a]বিতর্কে জয়![/color][/b] মিছিল থেমে গেছে। অনেকে বুঝেছে আসল প্রতারক কারা।"
		s.save.add("empathy", 1)
	else:
		claim_l.text = "[b][color=#ff8a80]জনতা আপনাকে মঞ্চ থেকে নামিয়ে দিল।[/color][/b] আবার চেষ্টা করুন: কোন দাবির জন্য কোন যুক্তি, ভেবে দেখুন।"
	var b := Button.new()
	b.text = "চালিয়ে যান"
	b.custom_minimum_size = Vector2(360, 70)
	b.pressed.connect(func() -> void:
		visible = false
		ui.pop_modal(true)
		var f := cb
		cb = Callable()
		s.bus.debate_finished.emit(str(data.get("leader", "")), won)
		if f.is_valid():
			f.call(won))
	grid.add_child(b)
