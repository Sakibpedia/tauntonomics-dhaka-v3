class_name ExamPanel
extends Control
## The universal exam: every gatekeeper, poster, ghost, dying goon and boss lectern uses it.
## Four options (keys 1–4 or click), a countdown ring by difficulty, one ৫০:৫০ lifeline per exam
## (a phone call to Hakim sir, ৳১৫০), then the verdict with an explanation, its source (past paper,
## statute section, computed) and a taunt from the examiner or Sakib's comeback.

var s: Services
var ui: UIRoot
var questions: Array = []
var idx := 0
var correct := 0
var need := 1
var cb: Callable
var context := ""
var examiner := ""
var _answered := false
var _time := 0.0
var _limit := 20.0
var _lifeline_used := false
var _done := false
var title_l: Label
var count_l: Label
var q_l: Label
var opts: Array[Button] = []
var ring: TextureProgressBar
var ring_l: Label
var info: RichTextLabel
var next_b: Button
var life_b: Button
var end_b: Button
var panel: Panel

func setup(services: Services, root: UIRoot) -> void:
	s = services
	ui = root
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = Panel.new()
	UiKit.place(panel, Control.PRESET_CENTER, Vector2(-640, -380), Vector2(1280, 760))
	var sb := StyleBoxTexture.new()
	sb.texture = UiKit.tex("exam_panel_bg")
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	title_l = ui._lbl("", 30, Color("ffd27a"), true)
	title_l.position = Vector2(60, 34)
	panel.add_child(title_l)
	count_l = ui._lbl("", 22, UiKit.PAPER)
	count_l.position = Vector2(60, 80)
	panel.add_child(count_l)
	ring = UiKit.make_ring(90)
	ring.position = Vector2(1140, 30)
	panel.add_child(ring)
	ring_l = ui._lbl("", 26, UiKit.PAPER, true)
	ring_l.position = Vector2(1168, 56)
	panel.add_child(ring_l)
	q_l = ui._lbl("", 32, Color.WHITE, true)
	q_l.position = Vector2(60, 130)
	q_l.size = Vector2(1160, 120)
	q_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(q_l)
	for i in 4:
		var b := Button.new()
		b.position = Vector2(60 + (i % 2) * 590, 270 + (i / 2) * 96)
		b.size = Vector2(570, 80)
		b.add_theme_font_override("font", BnText.font(true))
		b.add_theme_font_size_override("font_size", 25)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.pressed.connect(_answer.bind(i))
		panel.add_child(b)
		opts.append(b)
	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.position = Vector2(60, 470)
	info.size = Vector2(1160, 190)
	info.add_theme_font_override("normal_font", BnText.font(false))
	info.add_theme_font_override("bold_font", BnText.font(true))
	info.add_theme_font_size_override("normal_font_size", 22)
	info.add_theme_font_size_override("bold_font_size", 24)
	panel.add_child(info)
	next_b = Button.new()
	next_b.text = "পরবর্তী ➜"
	next_b.position = Vector2(930, 670)
	next_b.size = Vector2(290, 66)
	next_b.pressed.connect(_next)
	panel.add_child(next_b)
	life_b = Button.new()
	life_b.text = "৫০:৫০ — হাকিম স্যারকে ফোন (৳১৫০)"
	life_b.position = Vector2(60, 670)
	life_b.size = Vector2(520, 66)
	life_b.add_theme_font_size_override("font_size", 20)
	life_b.pressed.connect(_lifeline)
	panel.add_child(life_b)
	end_b = Button.new()
	end_b.text = "⏹ শেষ করুন"
	end_b.position = Vector2(600, 670)
	end_b.size = Vector2(310, 66)
	end_b.add_theme_font_size_override("font_size", 20)
	end_b.pressed.connect(_end_quiz)
	panel.add_child(end_b)

func open(qs: Array, title: String, exam_by: String, need_correct: int, done: Callable, ctx: String = "") -> void:
	questions = []
	for q in qs:
		if typeof(q) == TYPE_DICTIONARY and not (q as Dictionary).is_empty():
			questions.append(q)
	if questions.is_empty():
		questions = s.qdb.draw_many(["bcs"], maxi(1, qs.size()))
	idx = 0
	correct = 0
	need = mini(need_correct, questions.size())
	cb = done
	context = ctx
	examiner = exam_by
	_lifeline_used = false
	_done = false
	title_l.text = title + ("  •  পরীক্ষক: " + exam_by if exam_by != "" else "")
	visible = true
	move_to_front()           # exam sits on top of any other modal
	ui.push_modal()
	s.sfx.play("tension", -8.0)
	_show()

func _show() -> void:
	_answered = false
	var q: Dictionary = questions[idx]
	count_l.text = "প্রশ্ন %s / %s   •   %s   •   পাস করতে %sটি সঠিক" % [BnText.num(idx + 1), BnText.num(questions.size()), BnText.cat_name(str(q.get("cat", ""))), BnText.num(need)]
	q_l.text = str(q.get("q", ""))
	var o: Array = q.get("o", [])
	for i in 4:
		var b := opts[i]
		b.visible = i < o.size()
		if i < o.size():
			b.text = "   %s) %s" % [BnText.OPTION_LETTERS[i], str(o[i])]
			b.disabled = false
			UiKit.set_option_state(b, "normal")
	info.text = "[color=#a09a8a]কীবোর্ডে ১–৪ চাপুন বা ক্লিক করুন।[/color]"
	next_b.visible = false
	end_b.visible = true
	life_b.visible = not _lifeline_used and context != "dying"
	_limit = [25.0, 22.0, 18.0, 15.0][clampi(int(q.get("d", 2)), 0, 3)]
	_time = _limit
	ring.max_value = _limit
	if bool(s.save.setting("tts", true)):
		Speech.speak(q_l.text)

func _process(delta: float) -> void:
	if not visible or _answered or _done:
		return
	_time -= delta
	ring.value = _time
	ring_l.text = BnText.num(int(ceil(maxf(_time, 0.0))))
	if _time <= 0.0:
		_answer(-1)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed:
		var k := (event as InputEventKey).keycode
		if not _answered and k >= KEY_1 and k <= KEY_4:
			_answer(k - KEY_1)
			get_viewport().set_input_as_handled()
		elif _answered and (k == KEY_SPACE or k == KEY_ENTER or k == KEY_E):
			_next()
			get_viewport().set_input_as_handled()

func _lifeline() -> void:
	if _lifeline_used or _answered:
		return
	if not s.save.spend(150):
		info.text = "[color=#ff8a80]টাকা নেই। হাকিম স্যার বললেন: 'বিনা পয়সায় উত্তর শুধু বই দেয়।'[/color]"
		return
	_lifeline_used = true
	life_b.visible = false
	var q: Dictionary = questions[idx]
	var a := int(q.get("a", 0))
	var wrong: Array[int] = []
	for i in (q.get("o", []) as Array).size():
		if i != a:
			wrong.append(i)
	wrong.shuffle()
	for i in mini(2, wrong.size()):
		opts[wrong[i]].disabled = true
		UiKit.set_option_state(opts[wrong[i]], "disabled")
	info.text = "[color=#9fe8ff]হাকিম স্যার (ফোনে): 'দুটো বাদ দিলাম। বাকিটা নিজের মাথা খাটাও।'[/color]"
	s.sfx.play("notify", -6.0)

func _answer(i: int) -> void:
	if _answered:
		return
	_answered = true
	var q: Dictionary = questions[idx]
	var a := int(q.get("a", 0))
	var ok := i == a
	for k in opts.size():
		opts[k].disabled = true
		if k == a:
			UiKit.set_option_state(opts[k], "correct")
		elif k == i:
			UiKit.set_option_state(opts[k], "wrong")
	if ok:
		correct += 1
	var cat := str(q.get("cat", ""))
	s.save.record_answer(cat, ok)
	s.bus.answer_given.emit(ok, cat, context)
	var line := ""
	if ok:
		s.sfx.play("correct", -2.0)
		line = "[b][color=#7dff9a]সঠিক![/color][/b]  [i]সাকিব: %s[/i]" % s.taunts.pick("sakib_correct")
	else:
		s.sfx.play("wrong", -2.0)
		var o: Array = q.get("o", [])
		var right := str(o[a]) if a < o.size() else ""
		line = "[b][color=#ff8a80]%s[/color][/b]  সঠিক উত্তর: [b]%s[/b]\n[i]%s: %s[/i]" % ["সময় শেষ!" if i < 0 else "ভুল!", right, examiner if examiner != "" else "পরীক্ষক", s.taunts.pick("wrong")]
	var x := str(q.get("x", ""))
	if x != "":
		line += "\n[color=#d8d0c0]ব্যাখ্যা: %s[/color]" % x
	line += "\n[color=#8a8478][font_size=18]%s[/font_size][/color]" % QuestionDB.source_label(q)
	info.text = line
	next_b.visible = true
	next_b.text = "পরবর্তী ➜" if idx + 1 < questions.size() else "ফলাফল ➜"

func _next() -> void:
	if _done:
		_close()
		return
	if not _answered:
		return
	idx += 1
	if idx < questions.size():
		_show()
		return
	_done = true
	var passed := correct >= need
	for b in opts:
		b.visible = false
	life_b.visible = false
	end_b.visible = false
	q_l.text = "ফলাফল: %s / %s  —  %s" % [BnText.num(correct), BnText.num(questions.size()), "উত্তীর্ণ" if passed else "অনুত্তীর্ণ"]
	info.text = ("[color=#7dff9a]%s[/color]" % "পরীক্ষক মাথা নাড়লেন। পথ খোলা।") if passed else ("[color=#ff8a80]%s[/color]" % "আবার চেষ্টা করুন। প্রশ্ন বদলাবে, একই প্রশ্ন আর আসবে না।")
	next_b.text = "চালিয়ে যান"
	s.sfx.play("sting_win" if passed else "sting", -4.0)

## End the quiz early — grade whatever has been answered so far.
func _end_quiz() -> void:
	if _done:
		_close()
		return
	_done = true
	var passed := correct >= need
	for b in opts:
		b.visible = false
	life_b.visible = false
	end_b.visible = false
	q_l.text = "ফলাফল: %s / %s  —  %s" % [BnText.num(correct), BnText.num(questions.size()), "উত্তীর্ণ" if passed else "অনুত্তীর্ণ"]
	info.text = ("[color=#7dff9a]%s[/color]" % "পরীক্ষা শেষ। পথ খোলা।") if passed else ("[color=#ff8a80]%s[/color]" % "পরীক্ষা শেষ। আবার চেষ্টা করুন।")
	next_b.visible = true
	next_b.text = "চালিয়ে যান"
	s.sfx.play("sting_win" if passed else "sting", -4.0)

func _close() -> void:
	visible = false
	Speech.stop()
	ui.pop_modal()
	var passed := correct >= need
	var f := cb
	cb = Callable()
	if f.is_valid():
		f.call(passed, correct, questions.size())
