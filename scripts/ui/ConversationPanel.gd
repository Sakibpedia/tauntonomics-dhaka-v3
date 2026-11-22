class_name ConversationPanel
extends Control
## Talking to anyone in the city. Spoken lines (TTS when a Bengali voice exists) and subtitles.
## Choice options and a free-text box ("নিজে কিছু বলুন…"): typed Bengali, Banglish or English is
## classified into an intent and answered in character by the DialogueBrain. The answer depends on
## the person's faction and role, their memory of you (met, beaten, quizzed, relationship), time of
## day, Heat, ghosts and your current objective. Every person can quiz you (universal exam).
## Mission scripts (talk/exam/deliver/advise/buy steps) plug in through the MissionDirector.
## Also hosts the fate choice for downed Syndicate members: arrest, finish (last question), spare.

var s: Services
var ui: UIRoot
var actor: Actor
var player: Node
var box: PanelContainer
var name_l: Label
var line_l: RichTextLabel
var opts: VBoxContainer
var input: LineEdit
var _script: Array = []
var _script_i := 0
var _script_done: Callable
var _open := false
var _fate_mode := false

const COMPASS := ["উত্তর", "উত্তর-পূর্ব", "পূর্ব", "দক্ষিণ-পূর্ব", "দক্ষিণ", "দক্ষিণ-পশ্চিম", "পশ্চিম", "উত্তর-পশ্চিম"]
const INTENTS := {
	"greet": ["সালাম", "আসসালামু", "হ্যালো", "hello", "hi ", "কেমন", "kemon", "নমস্কার", "আদাব", "salam"],
	"news": ["খবর", "khobor", "news", "গুজব", "কী হচ্ছে", "ki hocche", "নতুন কী", "rumou"],
	"quiz": ["প্রশ্ন", "proshno", "question", "পরীক্ষা", "exam", "quiz", "বিসিএস", "bcs", "চ্যালেঞ্জ", "challenge"],
	"directions": ["কোথায়", "কোথা", "kothay", "where", "রাস্তা", "পথ", "যাব", "direction", "দিক"],
	"homeco": ["গার্হস্থ্য", "home eco", "homeco", "নিউট্রিশন", "nutrition", "ডায়েট", "diet", "পুষ্টি", "ক্লিনিক্যাল", "clinical", "পদবি"],
	"syndicate": ["সিন্ডিকেট", "syndicate", "ফাঁস", "leak", "মহাপরীক্ষক", "কোচিং", "coaching"],
	"job": ["চাকরি", "job", "chakri", "বেকার", "unemploy", "ভাইভা", "viva"],
	"insult": ["বোকা", "গাধা", "stupid", "idiot", "fool", "চুপ", "shut up", "ফালতু"],
	"praise": ["ধন্যবাদ", "thanks", "thank", "ভালো মানুষ", "সুন্দর", "nice", "great", "শাবাশ"],
	"threat": ["মারব", "মেরে", "kill", "মারবো", "পিটাব", "পিটিয়ে", "threat", "শেষ করে"],
	"bribe": ["টাকা", "taka", "money", "ঘুষ", "bribe", "পয়সা"],
	"weapon": ["পাথর", "stone", "শস্ত্র", "weapon", "ধারালো", "cutter", "খ separado", "ছোড়া", "fight"],
	"ghost": ["ভূত", "bhut", "ghost", "রাত", "night", "অন্ধকার"],
	"law": ["আইন", "ধারা", "law", "section", "কোর্ট", "court", "মামলা", "উকিল"],
	"joke": ["কৌতুক", "joke", "হাসি", "মজা", "funny"],
	"bye": ["বিদায়", "bye", "আসি", "খোদা হাফেজ", "আল্লাহ হাফেজ", "khoda hafez", "পরে কথা"],
}

func setup(services: Services, root: UIRoot) -> void:
	s = services
	ui = root
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	box = PanelContainer.new()
	UiKit.place(box, Control.PRESET_CENTER_BOTTOM, Vector2(-700, -660), Vector2(1400, 630))
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)
	# Header with name and an always-visible "stop talking" button (mouse/touch friendly).
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	v.add_child(header)
	name_l = ui._lbl("", 28, Color("ffd27a"), true)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_l)
	var close_b := Button.new()
	close_b.text = "✕ বিদায় (বন্ধ করুন)"
	close_b.custom_minimum_size = Vector2(260, 48)
	close_b.add_theme_font_size_override("font_size", 22)
	close_b.pressed.connect(close)
	header.add_child(close_b)
	line_l = RichTextLabel.new()
	line_l.bbcode_enabled = true
	line_l.fit_content = false
	line_l.scroll_active = true
	line_l.custom_minimum_size = Vector2(1340, 96)
	line_l.add_theme_font_override("normal_font", BnText.font(false))
	line_l.add_theme_font_override("bold_font", BnText.font(true))
	line_l.add_theme_font_size_override("normal_font_size", 26)
	line_l.add_theme_font_size_override("bold_font_size", 26)
	v.add_child(line_l)
	# Scrollable options so a long question bank never overlaps the input row.
	var opt_scroll := ScrollContainer.new()
	opt_scroll.custom_minimum_size = Vector2(1340, 300)
	opt_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(opt_scroll)
	opts = VBoxContainer.new()
	opts.add_theme_constant_override("separation", 4)
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt_scroll.add_child(opts)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(1340, 56)
	v.add_child(row)
	input = LineEdit.new()
	input.placeholder_text = "নিজে কিছু বলুন… (বাংলা, Banglish বা English)"
	input.custom_minimum_size = Vector2(1120, 52)
	input.add_theme_font_override("font", BnText.font(false))
	input.add_theme_font_size_override("font_size", 22)
	input.text_submitted.connect(func(t: String) -> void: _free_text(t))
	row.add_child(input)
	var say_b := Button.new()
	say_b.text = "বলুন"
	say_b.custom_minimum_size = Vector2(200, 52)
	say_b.pressed.connect(func() -> void: _free_text(input.text))
	row.add_child(say_b)

# ---------------------------------------------------------------- open / close
func open(a: Actor, p: Node) -> void:
	if _open:
		return
	actor = a
	player = p
	_open = true
	visible = true
	move_to_front()           # conversation sits on top of any other modal
	ui.push_modal(false)
	a.ai.set_state(ActorAI.State.TALK)
	a.visuals.show_tag(true)
	var m := s.save.mem(a.id)
	m["met"] = int(m.get("met", 0)) + 1
	name_l.text = "%s  •  %s%s" % [a.display_name, a.role, _rel_tag(m)]
	# mission script first
	var script: Array = []
	if s.missions:
		script = s.missions.call("talk_script", a)
	if not script.is_empty():
		_play_script(script, _after_script.bind(a))
		return
	_say(a, _greeting(a, m))
	_menu()

func _after_script(a: Actor) -> void:
	if s.missions:
		s.missions.call("on_talk_done", a)
	_menu()

func close() -> void:
	if _fate_mode:
		_close_fate()
		return
	if not _open:
		return
	_open = false
	visible = false
	input.text = ""
	Speech.stop()
	if is_instance_valid(actor):
		actor.visuals.show_tag(false)
		if actor.ai.state == ActorAI.State.TALK:
			actor.ai.set_state(ActorAI.State.WANDER if not actor.story_char else ActorAI.State.STAND)
		actor.body.look_target = null
	ui.pop_modal(false)

func _rel_tag(m: Dictionary) -> String:
	var r := int(m.get("rel", 0))
	if r >= 3:
		return "  •  সম্পর্ক: ঘনিষ্ঠ"
	if r <= -2:
		return "  •  সম্পর্ক: বিরক্ত"
	return ""

func _say(a: Actor, text: String) -> void:
	line_l.text = "[b][color=#ffd27a]%s:[/color][/b] %s" % [a.display_name, text]
	a.say(text, 4.0)
	a.body.talking = true
	if bool(s.save.setting("tts", true)):
		Speech.speak(text, 0.9 if a.body.female else 0.75)

func _sakib(text: String) -> void:
	line_l.text = "[b][color=#9fe8ff]সাকিব:[/color][/b] %s" % text
	if bool(s.save.setting("tts", true)):
		Speech.speak(text)

func _clear_opts() -> void:
	for c in opts.get_children():
		opts.remove_child(c)
		c.queue_free()

func _opt(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = "   " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(1340, 50)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	opts.add_child(b)

# ---------------------------------------------------------------- scripted lines
func _play_script(lines: Array, done: Callable) -> void:
	_script = lines
	_script_i = -1
	_script_done = done
	_script_next()

func _script_next() -> void:
	_script_i += 1
	_clear_opts()
	if _script_i >= _script.size():
		var d := _script_done
		_script_done = Callable()
		if d.is_valid():
			d.call()
		return
	var ln: Array = _script[_script_i]
	var who := str(ln[0])
	var txt := str(ln[1])
	if who == "sakib":
		_sakib(txt)
	elif is_instance_valid(actor) and who == actor.id:
		_say(actor, txt)
	else:
		line_l.text = "[b][color=#ffd27a]%s:[/color][/b] %s" % [s.story.char_name(who), txt]
		if bool(s.save.setting("tts", true)):
			Speech.speak(txt)
	_opt("চালিয়ে যান ➜", _script_next)

# ---------------------------------------------------------------- menu
func _menu() -> void:
	_clear_opts()
	if not is_instance_valid(actor):
		close()
		return
	var a := actor
	if s.missions:
		var ex: Dictionary = s.missions.call("exam_for", a)
		if not ex.is_empty():
			_opt("► পরীক্ষা দিন: %s" % str(ex.get("text", "")), func() -> void: _mission_exam(ex))
		var adv: Dictionary = s.missions.call("advice_for", a)
		if not adv.is_empty():
			_advice(adv)
			return
	if a.role in ["দোকানদার", "চা-দোকানি"] or a.id == "shopkeeper":
		_opt("► মোমবাতি কিনুন (৳১২০)", func() -> void: _buy_candle(false))
		_opt("► প্রশ্নের উত্তর দিয়ে অর্ধেক দামে মোমবাতি", func() -> void: _buy_candle(true))
	_opt("কেমন আছেন? শহরের খবর কী?", func() -> void: _intent("news"))
	_opt("আমাকে একটা প্রশ্ন করুন (বিসিএস/চাকরি/বার)", func() -> void: _quiz())
	_opt("পরের গন্তব্যের পথ দেখাবেন?", func() -> void: _intent("directions"))
	_opt("গার্হস্থ্য অর্থনীতির 'ক্লিনিক্যাল' পদবি নিয়ে আপনার মত?", func() -> void: _intent("homeco"))
	_opt("সিন্ডিকেট আর প্রশ্নফাঁস সম্পর্কে কিছু জানেন?", func() -> void: _intent("syndicate"))
	_opt("বিদায়", close)

func _free_text(t: String) -> void:
	if t.strip_edges() == "":
		return
	input.text = ""
	_sakib(t)
	var low := t.to_lower() + " "
	var best := "unknown"
	for k in INTENTS.keys():
		for w in INTENTS[k]:
			if low.find(str(w)) != -1:
				best = str(k)
				break
		if best != "unknown":
			break
	get_tree().create_timer(0.6, true, false, true).timeout.connect(func() -> void: _intent(best))

func _intent(intent: String) -> void:
	if not is_instance_valid(actor):
		close()
		return
	var a := actor
	var m := s.save.mem(a.id)
	var reply := DialogueBrain.respond(s, a, intent, m)
	match intent:
		"insult":
			m["rel"] = int(m.get("rel", 0)) - 1
			a.body.expression = "angry"
		"praise":
			m["rel"] = int(m.get("rel", 0)) + 1
			a.body.expression = "smug"
		"threat":
			m["rel"] = int(m.get("rel", 0)) - 2
			_say(a, reply)
			if a.faction == "syndicate":
				a.ai.aggro = true
				a.ai.set_state(ActorAI.State.FIGHT)
			else:
				a.ai.set_state(ActorAI.State.FLEE)
				s.bus.crime.emit(a.global_position, 1)
			close()
			return
		"bribe":
			if s.save.spend(100):
				if int(m.get("rel", 0)) >= 0 and (a.informant or a.story_char or a.faction == "syndicate"):
					s.save.add("intel", 1)
					reply += " (ইন্টেল +১)"
				else:
					m["rel"] = int(m.get("rel", 0)) - 1
			else:
				reply = "টাকাই নেই, আবার ঘুষ দিতে চান? আপনি সত্যিই বেকার।"
		"weapon":
			if s.save.spend(30):
				s.save.set("weapon_unlocked", true)
				var p := player as Player
				if p and is_instance_valid(p):
					p.carried = "stone"
					p.body.hold("stone", true)
				reply = "Weapon unlocked — throw stones at enemies from a distance."
			else:
				reply = "Not enough money — need ৩০ টাকা."

		"quiz":
			_quiz()
			return
		"bye":
			_say(a, reply)
			get_tree().create_timer(1.2, true, false, true).timeout.connect(close)
			return
	_say(a, reply)
	m["last"] = intent
	name_l.text = "%s  •  %s%s" % [a.display_name, a.role, _rel_tag(m)]
	_menu()

func _greeting(a: Actor, m: Dictionary) -> String:
	if int(m.get("beaten", 0)) > 0:
		return ["আবার আপনি? সেদিনের ঘুষির দাগ এখনো আছে।", "দূরে থাকেন, উকিল সাহেব। আপনার হাত বেশি চলে।"][randi() % 2]
	if int(m.get("met", 0)) > 1:
		return ["আবার দেখা! আজ কোন ধারা মুখস্থ করলেন?", "সাকিব ভাই, আবার এসেছেন? চা খাবেন?", "আপনাকে তো চিনি। গতবার প্রশ্নটা ভালোই পেরেছিলেন।"][randi() % 3]
	if not a.greet_lines.is_empty():
		return str(a.greet_lines[randi() % a.greet_lines.size()])
	return DialogueBrain.respond(s, a, "greet", m)

# ---------------------------------------------------------------- exams from conversation
func _quiz() -> void:
	var a := actor
	var m := s.save.mem(a.id)
	var n := 1 if randf() < 0.6 else 2
	var qs := s.qdb.draw_many(a.cats, n, 2 + int(a.examiner > 0.8))
	_say(a, ["ঠিক আছে, শুনুন তাহলে।", "দেখি কত পারেন!", "এটা আমার ভাগ্নের মডেল টেস্ট থেকে।", "পারলে চা আমার পক্ষ থেকে।"][randi() % 4])
	var done := func(passed: bool, c: int, _t: int) -> void:
		m["answered"] = int(m.get("answered", 0)) + c
		if passed:
			m["rel"] = int(m.get("rel", 0)) + 1
			var reward := a.exam_reward if not a.quizzed else 30
			a.quizzed = true
			s.save.add("money", reward)
			_say(a, "শাবাশ! এই নিন %s। আপনার মতো লোক ক্যাডার হয় না কেন, সেটাই প্রশ্ন।" % BnText.money(reward))
			if a.story_char or randf() < 0.3:
				s.save.add("intel", 1)
				s.toast("ইন্টেল +১", "intel")
		else:
			m["failed"] = int(m.get("failed", 0)) + 1
			_say(a, s.taunts.pick("wrong"))
			if a.informant or a.faction == "syndicate":
				s.heat.add(1.0, "%s আপনার ভুল উত্তর সিন্ডিকেটকে জানিয়ে দিয়েছে" % a.display_name)
		_menu()
	ui.open_exam(qs, "%s-এর প্রশ্ন" % a.display_name, a.display_name, n, done, "npc")

func _mission_exam(ex: Dictionary) -> void:
	var a := actor
	var qs := s.qdb.draw_many(ex.get("cats", ["bcs"]), int(ex.get("count", 3)), 3)
	var done := func(passed: bool, c: int, t: int) -> void:
		if s.missions:
			s.missions.call("on_exam_result", a, passed, c, t)
		if passed:
			_say(a, "ঠিক আছে, আপনি পাস। যান।")
		else:
			_say(a, s.taunts.pick("wrong") + " আবার চেষ্টা করুন।")
			if a.faction in ["syndicate", "pseudo"] or bool(ex.get("alerts", false)):
				s.heat.add(1.0, "ভুল উত্তর সিন্ডিকেটের কানে পৌঁছেছে")
		_menu()
	ui.open_exam(qs, str(ex.get("text", "পরীক্ষা")), a.display_name, int(ex.get("pass", 2)), done, "mission")

func _buy_candle(by_answer: bool) -> void:
	var a := actor
	if not by_answer:
		if s.save.spend(120):
			s.save.add("candles", 1)
			_say(a, "এই নিন মোমবাতি। রাতে আলো জ্বেলে রাখবেন, ভূতেরা আলো সহ্য করে না।")
			s.bus.item_collected.emit("candle", int(s.save.g("candles", 0)))
		else:
			_say(a, "টাকা নেই? বাকি নাই ভাই, এটা দোকান, কোচিং না।")
		_menu()
		return
	var done := func(passed: bool, _c: int, _t: int) -> void:
		if passed and s.save.spend(60):
			s.save.add("candles", 1)
			_say(a, "হিসাবে পাকা! অর্ধেক দামে নিন।")
			s.bus.item_collected.emit("candle", int(s.save.g("candles", 0)))
		elif passed:
			_say(a, "উত্তর ঠিক, কিন্তু ৬০ টাকাও তো লাগবে।")
		else:
			_say(a, "হিসাব ভুল। পুরো দাম লাগবে।")
		_menu()
	ui.open_exam(s.qdb.draw_many(["math"], 1, 2), "দোকানির হিসাবের প্রশ্ন", a.display_name, 1, done, "shop")

func _advice(adv: Dictionary) -> void:
	var a := actor
	var pid := str(adv["pid"])
	var pd: Dictionary = s.story.patients.get(pid, {})
	_say(a, "%s। %s" % [str(pd.get("condition", "")), str(pd.get("fake", ""))])
	_clear_opts()
	for ch in pd.get("choices", []):
		var ca: Array = ch
		_opt(str(ca[0]), _choose_advice.bind(a, pid, str(ca[1])))

func _choose_advice(a: Actor, pid: String, verdict: String) -> void:
	var pts: Dictionary = s.save.g("patients", {})
	pts[pid] = verdict
	s.save.s("patients", pts)
	match verdict:
		"good":
			_say(a, "ধন্যবাদ বাবা। ডাক্তার ফারজানার কাছেই যাব।")
			s.save.add("empathy", 1)
		"bad":
			_say(a, "আচ্ছা... তাহলে তা-ই করি।")
		_:
			_say(a, "আইনের ধারা দিয়ে কী করব বাবা, আমি তো অসুস্থ।")
	if s.missions:
		s.missions.call("on_advice", a, pid, verdict)
	_clear_opts()
	_opt("বিদায়", close)

# ---------------------------------------------------------------- fate of a downed Syndicate member
func open_fate(a: Actor) -> void:
	if _fate_mode:
		return
	actor = a
	_open = true
	_fate_mode = true
	visible = true
	ui.push_modal(true)
	a.finish_pending = true
	name_l.text = "%s  •  %s  •  সিদ্ধান্ত আপনার" % [a.display_name, a.role]
	line_l.text = "[b][color=#ffd27a]%s:[/color][/b] %s\n[color=#a09a8a]গ্রেপ্তার করলে সে সাক্ষী হবে। শেষ করলে মৃত্যুর আগে সে একটা প্রশ্ন করবে। উত্তর না পারলে রাতে প্রশ্নভূত হয়ে ফিরবে। ছেড়ে দিলে হয়তো বদলাবে।[/color]" % [a.display_name, s.taunts.pick("dying")]
	_clear_opts()
	var do_arrest := func() -> void:
		_close_fate()
		a.arrest()
		if s.missions:
			s.missions.call("on_target_resolved", a, "arrested")
	var after_q := func(passed: bool, _c: int, _t: int, q: Dictionary) -> void:
		if is_instance_valid(a):
			a.die_after_question(q, passed)
			if s.missions:
				s.missions.call("on_target_resolved", a, "killed")
	var do_finish := func() -> void:
		_close_fate()
		var q := s.qdb.draw(a.cats, 3)
		a.say(s.taunts.pick("dying"), 4.0)
		ui.open_exam([q], "মৃত্যুর আগে শেষ প্রশ্ন", a.display_name, 1, after_q.bind(q), "dying")
	var do_spare := func() -> void:
		_close_fate()
		a.spare()
		if s.missions:
			s.missions.call("on_target_resolved", a, "spared")
	_opt("গ্রেপ্তার করুন (পুলিশের হাতে দিন)", do_arrest)
	_opt("শেষ করুন (মৃত্যুর আগে তার শেষ প্রশ্ন)", do_finish)
	_opt("ছেড়ে দিন", do_spare)

func _close_fate() -> void:
	if not _fate_mode:
		return
	_fate_mode = false
	_open = false
	visible = false
	if is_instance_valid(actor):
		actor.finish_pending = false
	ui.pop_modal(true)
