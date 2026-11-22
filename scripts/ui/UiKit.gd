class_name UiKit
extends RefCounted
## Turns res://ui/svg/*.svg into a Godot Theme plus ready-made widgets.
## Plain RefCounted with static helpers. It is not an autoload, so the Phase 5 dependency-injection
## container can own it or replace it.
##
##   var theme := UiKit.build_theme()              # assign to a root Control
##   var hp := UiKit.make_bar("health")            # TextureProgressBar, 420x40
##   var ring := UiKit.make_ring()                 # radial countdown / hold-to-interact
##   UiKit.set_option_state(button, "correct")     # exam answer feedback
##   var title := UiKit.make_title("অধ্যায় ১ — পুরান ঢাকা")
##
## SVGs import at scale 1.0, which suits 1080p. For 1440p/4K, raise "svg/scale" in the Import dock
## and multiply the margins below by the same factor (SVG_SCALE).

const DIR := "res://ui/svg/"
const SVG_SCALE := 1.0
const FONT_REGULAR := "res://assets/fonts/FreeSans.ttf"     # swap in Noto Sans Bengali / Hind Siliguri if you add them
const FONT_BOLD := "res://assets/fonts/FreeSansBold.ttf"

const SAFFRON := Color("f2a541")
const SIGNAL_RED := Color("e5484d")
const TEAL := Color("2ec4b6")
const INK := Color("0b0f14")
const PAPER := Color("f4efe4")

static var _cache: Dictionary = {}

static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var t: Texture2D = load(DIR + name + ".svg")
	_cache[name] = t
	return t

## 9-slice StyleBoxTexture. margins/content are (left, top, right, bottom) in SVG pixels.
static func slice(name: String, margins: Vector4, content: Vector4 = Vector4(-1, -1, -1, -1)) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(name)
	var m := margins * SVG_SCALE
	sb.texture_margin_left = m.x
	sb.texture_margin_top = m.y
	sb.texture_margin_right = m.z
	sb.texture_margin_bottom = m.w
	var c := content if content.x >= 0.0 else margins
	sb.content_margin_left = c.x
	sb.content_margin_top = c.y
	sb.content_margin_right = c.z
	sb.content_margin_bottom = c.w
	return sb

static func font(bold: bool = false) -> Font:
	return BnText.font(bold)

static func build_theme() -> Theme:
	var th := Theme.new()
	th.default_font = font(false)
	th.default_font_size = 22
	# panels
	th.set_stylebox("panel", "PanelContainer", slice("panel_glass", Vector4(40, 40, 40, 40), Vector4(28, 24, 28, 24)))
	th.set_stylebox("panel", "Panel", slice("panel_glass", Vector4(40, 40, 40, 40)))
	# buttons use the exam option states
	var opt_m := Vector4(84, 20, 64, 20)
	var opt_c := Vector4(84, 14, 64, 14)
	th.set_stylebox("normal", "Button", slice("exam_option_normal", opt_m, opt_c))
	th.set_stylebox("hover", "Button", slice("exam_option_hover", opt_m, opt_c))
	th.set_stylebox("pressed", "Button", slice("exam_option_hover", opt_m, opt_c))
	th.set_stylebox("focus", "Button", slice("exam_option_hover", opt_m, opt_c))
	th.set_stylebox("disabled", "Button", slice("exam_option_disabled", opt_m, opt_c))
	th.set_color("font_color", "Button", PAPER)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(0.42, 0.4, 0.37))
	th.set_font_size("font_size", "Button", 24)
	# labels
	th.set_color("font_color", "Label", PAPER)
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	th.set_constant("outline_size", "Label", 4)
	# heading variation
	th.add_type("HeaderLabel")
	th.set_type_variation("HeaderLabel", "Label")
	th.set_font("font", "HeaderLabel", font(true))
	th.set_font_size("font_size", "HeaderLabel", 30)
	th.set_color("font_color", "HeaderLabel", Color("ffd27a"))
	# tooltip / toast
	th.set_stylebox("panel", "TooltipPanel", slice("toast_bg", Vector4(24, 16, 16, 16), Vector4(24, 10, 16, 10)))
	return th

## TextureProgressBar for "health", "sanity", "stealth" or "stamina".
static func make_bar(kind: String) -> TextureProgressBar:
	var b := TextureProgressBar.new()
	b.texture_under = tex("bar_under")
	b.texture_progress = tex("bar_fill_" + kind)
	b.texture_over = tex("bar_over")
	b.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT
	b.max_value = 100.0
	b.value = 100.0
	b.custom_minimum_size = Vector2(420, 40) * SVG_SCALE
	return b

## Radial ring for exam countdowns and hold-to-interact prompts.
static func make_ring(size_px: float = 80.0) -> TextureProgressBar:
	var r := TextureProgressBar.new()
	r.texture_under = tex("ring_track")
	r.texture_progress = tex("ring_fill")
	r.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	r.radial_initial_angle = 0.0
	r.max_value = 1.0
	r.step = 0.001
	r.value = 1.0
	r.nine_patch_stretch = false        # radial fill modes don't support nine-patch, so size with scale
	r.scale = Vector2.ONE * (size_px / 140.0)
	return r

## Screen-space marker icon: "objective", "exam", "intel", "danger", "offscreen_arrow".
static func make_marker(kind: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex("marker_" + kind)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.pivot_offset = Vector2(48, 120) if kind == "objective" else t.texture.get_size() * 0.5
	return t

## Swap an answer button's look: "normal", "hover", "correct", "wrong", "disabled".
static func set_option_state(b: Button, state: String) -> void:
	var sb := slice("exam_option_" + state, Vector4(84, 20, 64, 20), Vector4(84, 14, 64, 14))
	for slot in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(slot, sb)

## Ink-brush title card. The label sits so the Bengali matra (headline) rides the saffron rule.
static func make_title(text: String, red: bool = false, font_size: int = 58) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(960, 200)
	var bg := TextureRect.new()
	bg.texture = tex("bn_title_backdrop_red" if red else "bn_title_backdrop")
	root.add_child(bg)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(true))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color("fff4dc"))
	l.position = Vector2(110, 58.0 - font_size * 0.36)
	root.add_child(l)
	return root

## Key prompt: keycap + letter + action text.
static func make_key_prompt(key: String, action: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var cap := TextureRect.new()
	cap.texture = tex("keycap")
	cap.custom_minimum_size = Vector2(52, 52)
	cap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h.add_child(cap)
	var k := Label.new()
	k.text = key
	k.add_theme_font_override("font", font(true))
	k.add_theme_font_size_override("font_size", 24)
	k.add_theme_color_override("font_color", Color(0.13, 0.12, 0.11))
	k.add_theme_constant_override("outline_size", 0)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	k.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	k.offset_bottom = -6
	cap.add_child(k)
	var a := Label.new()
	a.text = action
	a.add_theme_font_size_override("font_size", 22)
	h.add_child(a)
	return h

## Anchors a control with explicit offsets (offsets are relative to the anchor point), so panels
## land in the same place regardless of when their parent gets its size.
static func place(c: Control, preset: Control.LayoutPreset, pos: Vector2, size: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + size.x
	c.offset_bottom = pos.y + size.y
