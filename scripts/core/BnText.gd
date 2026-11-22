class_name BnText
extends RefCounted
## Bengali text helpers: digits, money, time, JSON loading, fonts.

const DIGITS: Array[String] = ["০", "১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯"]
const OPTION_LETTERS: Array[String] = ["ক", "খ", "গ", "ঘ"]
const CAT_NAMES := {
	"past": "বিগত বিসিএস", "law": "আইন", "math": "গণিত", "mental": "মানসিক দক্ষতা", "bangla": "বাংলা",
	"english": "ইংরেজি", "gk": "আন্তর্জাতিক", "bd": "বাংলাদেশ", "science": "বিজ্ঞান", "ict": "আইসিটি",
}

static var _font: Font
static var _font_bold: Font

static func num(v: Variant) -> String:
	var s := str(v)
	var out := ""
	for ch in s:
		var code := ch.unicode_at(0)
		if code >= 48 and code <= 57:
			out += DIGITS[code - 48]
		else:
			out += ch
	return out

static func money(v: int) -> String:
	return "৳" + num(v)

static func clock(hour: float) -> String:
	var h := int(floor(hour)) % 24
	var m := int(floor((hour - floor(hour)) * 60.0))
	var part := "রাত"
	if h >= 4 and h < 6:
		part = "ভোর"
	elif h >= 6 and h < 12:
		part = "সকাল"
	elif h >= 12 and h < 15:
		part = "দুপুর"
	elif h >= 15 and h < 18:
		part = "বিকাল"
	elif h >= 18 and h < 19:
		part = "সন্ধ্যা"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%s %s:%s" % [part, num(h12), num("%02d" % m)]

static func cat_name(cat: String) -> String:
	return str(CAT_NAMES.get(cat, cat))

static func load_json(path: String, fallback: Variant = null) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("JSON missing: " + path)
		return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("JSON parse failed: " + path)
		return fallback
	return parsed

## Noto Sans Bengali (proper conjunct shaping through HarfBuzz) with FreeSans as the Latin fallback.
static func font(bold: bool = false) -> Font:
	if _font == null:
		var fb: FontFile = load("res://assets/fonts/FreeSans.ttf")
		var fbb: FontFile = load("res://assets/fonts/FreeSansBold.ttf")
		var r: FontFile = load("res://assets/fonts/NotoSansBengali-Regular.ttf")
		var b: FontFile = load("res://assets/fonts/NotoSansBengali-Bold.ttf")
		r.fallbacks = [fb]
		b.fallbacks = [fbb]
		_font = r
		_font_bold = b
	return _font_bold if bold else _font

## Replaces {key} placeholders.
static func fmt(text: String, vars: Dictionary) -> String:
	var out := text
	for k in vars.keys():
		out = out.replace("{" + str(k) + "}", str(vars[k]))
	return out
