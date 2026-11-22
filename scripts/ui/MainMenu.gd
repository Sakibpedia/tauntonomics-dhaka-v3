class_name MainMenu
extends Control
## Title screen over a live, slowly orbiting Dhaka at dusk. Logo: the creator's photo.
## নতুন খেলা • চালিয়ে যান • লেভেল বাছাই • সেটিংস • কৃতজ্ঞতা • প্রস্থান

var s: Services
var main: Node
var levels_box: GridContainer
var credits: RichTextLabel
var right: VBoxContainer

func setup(services: Services, main_node: Node) -> void:
	s = services
	main = main_node
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.build_theme()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ float g = smoothstep(0.0, 0.7, UV.x); COLOR = vec4(0.02, 0.02, 0.03, mix(0.86, 0.15, g)); }"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	shade.material = sm
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var left := VBoxContainer.new()
	left.position = Vector2(80, 60)
	left.custom_minimum_size = Vector2(640, 0)
	left.add_theme_constant_override("separation", 12)
	add_child(left)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/logo/sakib_logo.png")
	logo.custom_minimum_size = Vector2(220, 268)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	left.add_child(logo)
	var t := Label.new()
	t.text = "ট্যান্ট-ও-নমিক্স: ঢাকা"
	t.add_theme_font_override("font", BnText.font(true))
	t.add_theme_font_size_override("font_size", 64)
	t.add_theme_color_override("font_color", UiKit.SAFFRON)
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	left.add_child(t)
	var tag := Label.new()
	tag.text = "প্রশ্নই অস্ত্র। উত্তরই মুক্তি।\nনির্মাতা ও স্বত্বাধিকারী: এস এম নাজমুয সাকিব"
	tag.add_theme_font_override("font", BnText.font(false))
	tag.add_theme_font_size_override("font_size", 26)
	left.add_child(tag)
	var buttons := [["নতুন খেলা", "_new"], ["চালিয়ে যান", "_continue"], ["লেভেল বাছাই", "_levels"], ["কৃতজ্ঞতা ও তথ্যসূত্র", "_credits"], ["প্রস্থান", "_quit"]]
	for bd in buttons:
		var b := Button.new()
		b.text = "   " + str(bd[0])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(560, 70)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(Callable(self, str(bd[1])))
		if str(bd[1]) == "_continue":
			b.disabled = not s.save.has_save()
		left.add_child(b)
	right = VBoxContainer.new()
	UiKit.place(right, Control.PRESET_TOP_RIGHT, Vector2(-900, 80), Vector2(840, 900))
	right.visible = false
	add_child(right)
	levels_box = GridContainer.new()
	levels_box.columns = 2
	right.add_child(levels_box)
	credits = RichTextLabel.new()
	credits.bbcode_enabled = true
	credits.fit_content = true
	credits.custom_minimum_size = Vector2(820, 600)
	credits.add_theme_font_override("normal_font", BnText.font(false))
	credits.add_theme_font_override("bold_font", BnText.font(true))
	credits.add_theme_font_size_override("normal_font_size", 22)
	credits.add_theme_font_size_override("bold_font_size", 24)
	right.add_child(credits)

func _new() -> void:
	main.call("new_game")

func _continue() -> void:
	main.call("continue_game")

func _quit() -> void:
	get_tree().quit()

func _levels() -> void:
	right.visible = true
	credits.visible = false
	levels_box.visible = true
	for c in levels_box.get_children():
		c.queue_free()
	var unlocked := 1
	if s.save.has_save():
		var tmp := SaveData.new()
		tmp.reset_defaults()
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveData.PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			unlocked = int((parsed as Dictionary).get("unlocked", 1))
		tmp.free()
	for l in s.story.levels:
		var ld: Dictionary = l
		var n := int(ld["id"])
		var b := Button.new()
		b.text = "%s. %s" % [BnText.num(n), str(ld["name"])]
		b.custom_minimum_size = Vector2(410, 54)
		b.add_theme_font_size_override("font_size", 20)
		b.disabled = n > unlocked
		b.pressed.connect(func() -> void: main.call("start_level", n))
		levels_box.add_child(b)

func _credits() -> void:
	right.visible = true
	levels_box.visible = false
	credits.visible = true
	var st: Dictionary = s.story.story
	var t := "[b][color=#f2a541]%s[/color][/b]\n%s\n\n" % [str(st.get("title", "")), str(st.get("tagline", ""))]
	for c in st.get("credits", []):
		t += "• %s\n" % str(c)
	t += "\n[b]প্রশ্নব্যাংক[/b]: %s টি প্রশ্ন, একবার আসা প্রশ্ন আর আসে না।\n[b]টাউন্ট-ব্যাংক[/b]: %s টি সংলাপ।\n" % [BnText.num(s.qdb.count()), BnText.num(s.taunts.total())]
	t += "\n[b]প্রযুক্তি[/b]: Godot 4.6 (Forward+), Jolt Physics। সব টেক্সচার Python/Pillow দিয়ে তৈরি, সব শব্দ রানটাইমে সংশ্লেষিত, সব চরিত্র ও শহর প্রসিডিউরাল।\nফন্ট: Noto Sans Bengali (SIL OFL), GNU FreeFont।\n\n[color=#a09a8a]এটি একটি ব্যঙ্গাত্মক কাল্পনিক খেলা। গার্হস্থ্য অর্থনীতি বিষয়টি নয়, বিদ্রুপের লক্ষ্য হলো পদবি-জালিয়াতি, প্রশ্নফাঁস আর কোচিং-সিন্ডিকেট।[/color]"
	credits.text = t
