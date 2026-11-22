class_name PhonePanel
extends Control
## Sakib's phone (Tab / M / Esc): missions, a full map, career stats (accuracy per category,
## arrests vs. executions, ghosts), question-bank progress (no repeats until a pool is used up),
## settings (volume, mouse sensitivity, voice, graphics quality), save, and quit to menu.

var s: Services
var ui: UIRoot
var tabs: TabContainer
var map: Minimap
var stats_l: RichTextLabel
var bank_l: RichTextLabel
var missions_l: RichTextLabel

func setup(services: Services, root: UIRoot) -> void:
	s = services
	ui = root
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var pc := PanelContainer.new()
	UiKit.place(pc, Control.PRESET_CENTER, Vector2(-700, -460), Vector2(1400, 920))
	add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(ui._lbl("সাকিবের ফোন", 30, Color("ffd27a"), true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close_b := Button.new()
	close_b.text = "বন্ধ করুন ✕"
	close_b.custom_minimum_size = Vector2(220, 56)
	close_b.pressed.connect(close)
	head.add_child(close_b)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(1360, 820)
	tabs.add_theme_font_override("font", BnText.font(true))
	tabs.add_theme_font_size_override("font_size", 22)
	v.add_child(tabs)
	missions_l = _page("মিশন")
	var map_page := Control.new()
	map_page.name = "মানচিত্র"
	tabs.add_child(map_page)
	map = Minimap.new()
	map.setup(s, true)
	map.position = Vector2(20, 10)
	map.size = Vector2(1300, 760)
	map_page.add_child(map)
	stats_l = _page("পরিসংখ্যান")
	bank_l = _page("প্রশ্নব্যাংক")
	_settings_page()
	_system_page()

func _page(title: String) -> RichTextLabel:
	var sc := ScrollContainer.new()
	sc.name = title
	tabs.add_child(sc)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.custom_minimum_size = Vector2(1320, 760)
	r.add_theme_font_override("normal_font", BnText.font(false))
	r.add_theme_font_override("bold_font", BnText.font(true))
	r.add_theme_font_size_override("normal_font_size", 22)
	r.add_theme_font_size_override("bold_font_size", 24)
	sc.add_child(r)
	return r

func _settings_page() -> void:
	var v := VBoxContainer.new()
	v.name = "সেটিংস"
	v.add_theme_constant_override("separation", 16)
	tabs.add_child(v)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = float(s.save.setting("volume", 0.8))
	vol.custom_minimum_size = Vector2(600, 40)
	vol.value_changed.connect(func(x: float) -> void:
		s.save.set_setting("volume", x)
		s.sfx.set_master(x))
	v.add_child(ui._lbl("শব্দ", 22))
	v.add_child(vol)
	var sens := HSlider.new()
	sens.min_value = 0.05
	sens.max_value = 0.6
	sens.step = 0.01
	sens.value = float(s.save.setting("sens", 0.18))
	sens.custom_minimum_size = Vector2(600, 40)
	sens.value_changed.connect(func(x: float) -> void:
		s.save.set_setting("sens", x)
		if s.camera:
			(s.camera as PlayerCamera).sens = x * 0.014)
	v.add_child(ui._lbl("মাউস সংবেদনশীলতা", 22))
	v.add_child(sens)
	var tts := CheckButton.new()
	tts.text = "বাংলা কথা বলা (রেকর্ড করা কণ্ঠ + OS ভয়েস)"
	tts.button_pressed = bool(s.save.setting("tts", true))
	tts.toggled.connect(func(on: bool) -> void: s.save.set_setting("tts", on))
	v.add_child(tts)
	var test_v := Button.new()
	test_v.text = "▶ কণ্ঠ পরীক্ষা করুন (spoken voice test)"
	test_v.custom_minimum_size = Vector2(560, 56)
	test_v.add_theme_font_override("font", BnText.font(true))
	test_v.pressed.connect(func() -> void:
		Speech.speak("আমি সাকিব। কেমন আছেন? শহরের খবর কী?", 1.0, 1.0)
		ui.toast("বাংলা কণ্ঠ চালু করা হয়েছে", "info"))
	v.add_child(test_v)
	var q := OptionButton.new()
	for name in ["নিম্ন", "মাঝারি", "উচ্চ", "আল্ট্রা"]:
		q.add_item(name)
	q.selected = int(s.save.setting("quality", 2))
	q.item_selected.connect(func(i: int) -> void:
		s.save.set_setting("quality", i)
		if s.atmo:
			s.atmo.quality = i as DhakaAtmosphere.Quality)
	v.add_child(ui._lbl("গ্রাফিক্স মান", 22))
	v.add_child(q)

func _system_page() -> void:
	var v := VBoxContainer.new()
	v.name = "সংরক্ষণ"
	v.add_theme_constant_override("separation", 14)
	tabs.add_child(v)
	var sv := Button.new()
	sv.text = "খেলা সংরক্ষণ করুন"
	sv.custom_minimum_size = Vector2(520, 64)
	sv.pressed.connect(func() -> void:
		if s.main:
			s.main.call("save_now")
		s.toast("সংরক্ষিত হয়েছে", "good"))
	v.add_child(sv)
	var mm := Button.new()
	mm.text = "প্রধান মেনুতে ফিরুন"
	mm.custom_minimum_size = Vector2(520, 64)
	mm.pressed.connect(func() -> void:
		close()
		if s.main:
			s.main.call("to_menu"))
	v.add_child(mm)
	var qb := Button.new()
	qb.text = "খেলা বন্ধ করুন"
	qb.custom_minimum_size = Vector2(520, 64)
	qb.pressed.connect(func() -> void:
		if s.main:
			s.main.call("save_now")
		get_tree().quit())
	v.add_child(qb)
	v.add_child(ui._lbl("নিয়ন্ত্রণ: WASD চলা • Shift দৌড় • Space লাফ • C নিচু হওয়া • E কথা/ব্যবহার • বাম-ক্লিক ঘুষি • মাঝের বোতাম/X লাথি\nF ব্লক/প্যারি • V ডজ • Q আইনের বই-ঢাল • G ইট তোলা • ডান-ক্লিক তাক • T খোঁচা • B মোমবাতি • R লক-অন • Tab/M ফোন", 20, Color(0.85, 0.82, 0.75)))

func open() -> void:
	_refresh()
	visible = true
	ui.push_modal(true)

func close() -> void:
	if not visible:
		return
	visible = false
	ui.pop_modal(true)

func _refresh() -> void:
	if s.missions:
		missions_l.text = str(s.missions.call("status_bbcode"))
	var d: Dictionary = s.save.data
	var acc := int(round(s.save.accuracy() * 100.0))
	var t := "[b]ক্যারিয়ার[/b]\nউত্তর দেওয়া প্রশ্ন: %s   সঠিক: %s   নির্ভুলতা: %s%%\n" % [BnText.num(int(d.get("answered", 0))), BnText.num(int(d.get("correct", 0))), BnText.num(acc)]
	t += "গ্রেপ্তার: %s   শেষ করা: %s   ছেড়ে দেওয়া/অজ্ঞান: %s\n" % [BnText.num(int(d.get("arrests", 0))), BnText.num(int(d.get("kills", 0))), BnText.num(int(d.get("kos", 0)))]
	t += "মুক্ত করা প্রশ্নভূত: %s   এখনো ঘুরছে: %s   সহমর্মিতা: %s   পোস্টার: %s\n\n" % [BnText.num(int(d.get("ghosts_banished", 0))), BnText.num(s.save.ghosts().size()), BnText.num(int(d.get("empathy", 0))), BnText.num(int(d.get("posters", 0)))]
	t += "[b]বিষয়ভিত্তিক ফলাফল[/b]\n"
	var bc: Dictionary = d.get("by_cat", {})
	for cat in bc.keys():
		var row: Array = bc[cat]
		t += "%s: %s / %s\n" % [BnText.cat_name(str(cat)), BnText.num(int(row[1])), BnText.num(int(row[0]))]
	var ending := s.save.ending()
	t += "\n[b]এই মুহূর্তে আপনার পথ:[/b] %s" % {"justice": "ন্যায়ের ভাইভা", "vengeance": "প্রতিশোধের রায়", "haunted": "প্রশ্নভূতের শহর"}[ending]
	stats_l.text = t
	var b := "[b]প্রশ্নব্যাংক: মোট %s টি প্রশ্ন[/b] (একবার আসা প্রশ্ন আর আসবে না, পুরো বিভাগ শেষ হলে নতুন চক্র)\n\n" % BnText.num(s.qdb.count())
	for cat in s.qdb.categories():
		b += "%s: বাকি %s / %s\n" % [BnText.cat_name(str(cat)), BnText.num(s.qdb.remaining(str(cat))), BnText.num(s.qdb.total(str(cat)))]
	b += "\nউৎস: বিগত বিসিএস প্রশ্ন (পরীক্ষা ও প্রশ্ন নম্বরসহ), bdlaws.minlaw.gov.bd-এর আইনের ধারা-শিরোনাম, গণনা করে যাচাইকৃত গণিত, প্রমিত বানান তালিকা এবং পাঠ্যবই-ভিত্তিক তথ্য।"
	bank_l.text = b
