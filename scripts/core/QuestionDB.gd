class_name QuestionDB
extends Node
## The 3,000+ question bank (data/questions/questions.json, built by tools/generate_questions.py).
## Draws without repetition: each category keeps a shuffled deck, and ids already seen are stored in
## the save file. Only when a whole category is used up is it reshuffled.

const PATH := "res://data/questions/questions.json"
const EXAM_PROFILES := {
	"bcs": ["past", "bangla", "english", "math", "mental", "gk", "bd", "science", "ict"],
	"bar": ["law", "law", "law", "past"],
	"job": ["bangla", "english", "math", "mental", "gk", "bd", "ict"],
	"judiciary": ["law", "law", "bangla", "english"],
}

var items: Array = []
var by_id: Dictionary = {}
var by_cat: Dictionary = {}       # cat -> Array[int] indices
var decks: Dictionary = {}        # cat -> Array[int] remaining
var used: Dictionary = {}         # id -> true
var save: SaveData
var bus: EventBus

func _ready() -> void:
	var d: Variant = BnText.load_json(PATH, {})
	if typeof(d) == TYPE_DICTIONARY:
		var dd: Dictionary = d
		items = dd.get("items", [])
	for i in items.size():
		var it: Dictionary = items[i]
		by_id[str(it["id"])] = i
		var cat := str(it["cat"])
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(i)

func count() -> int:
	return items.size()

func categories() -> Array:
	return by_cat.keys()

func sync_from_save() -> void:
	used.clear()
	if save:
		for id in save.g("used_q", []):
			used[str(id)] = true
	decks.clear()

func _deck(cat: String) -> Array:
	if decks.has(cat) and not (decks[cat] as Array).is_empty():
		return decks[cat]
	var src: Array = by_cat.get(cat, [])
	var fresh: Array = []
	for i in src:
		var it: Dictionary = items[int(i)]
		if not used.has(str(it["id"])):
			fresh.append(i)
	if fresh.is_empty() and not src.is_empty():
		# whole category used: forget it and start a new cycle
		for i in src:
			var it2: Dictionary = items[int(i)]
			used.erase(str(it2["id"]))
		fresh = src.duplicate()
		if bus:
			bus.toast.emit("%s: সব প্রশ্ন শেষ, নতুন চক্র শুরু" % BnText.cat_name(cat), "info")
		_write_used()
	fresh.shuffle()
	decks[cat] = fresh
	return fresh

## Draw one question from any of `cats` (weighted by deck size), optionally biased to a difficulty.
func draw(cats: Array, max_difficulty: int = 3) -> Dictionary:
	var pool: Array = []
	for c in cats:
		var cs := str(c)
		if cs in ["bcs", "bar", "job", "judiciary"]:
			pool.append_array(EXAM_PROFILES[cs])
		elif by_cat.has(cs):
			pool.append(cs)
	if pool.is_empty():
		pool = by_cat.keys()
	if pool.is_empty():
		return {}
	var cat := str(pool[randi() % pool.size()])
	var deck := _deck(cat)
	if deck.is_empty():
		return {}
	var pick := -1
	for k in range(deck.size() - 1, maxi(-1, deck.size() - 12), -1):
		var it: Dictionary = items[int(deck[k])]
		if int(it.get("d", 2)) <= max_difficulty:
			pick = k
			break
	if pick == -1:
		pick = deck.size() - 1
	var idx := int(deck[pick])
	deck.remove_at(pick)
	var q: Dictionary = (items[idx] as Dictionary).duplicate(true)
	mark_used(str(q["id"]))
	return q

func draw_many(cats: Array, n: int, max_difficulty: int = 3) -> Array:
	var out: Array = []
	for i in n:
		var q := draw(cats, max_difficulty)
		if not q.is_empty():
			out.append(q)
	return out

func get_by_id(id: String) -> Dictionary:
	if by_id.has(id):
		return (items[int(by_id[id])] as Dictionary).duplicate(true)
	return {}

func mark_used(id: String) -> void:
	if used.has(id):
		return
	used[id] = true
	_write_used()

func _write_used() -> void:
	if save:
		save.s("used_q", used.keys())

func remaining(cat: String) -> int:
	var n := 0
	for i in by_cat.get(cat, []):
		var it: Dictionary = items[int(i)]
		if not used.has(str(it["id"])):
			n += 1
	return n

func total(cat: String) -> int:
	return (by_cat.get(cat, []) as Array).size()

## Human-readable provenance shown after every answer, so players can check the source.
static func source_label(q: Dictionary) -> String:
	var s: Dictionary = q.get("s", {})
	match str(s.get("t", "")):
		"past_paper":
			var t := "উৎস: %s" % str(s.get("exam", "বিগত প্রশ্ন"))
			if s.get("qno") != null:
				t += ", প্রশ্ন %s" % BnText.num(s.get("qno"))
			return t
		"statute":
			return "উৎস: %s, ধারা %s (bdlaws.minlaw.gov.bd)" % [str(s.get("statute", "")), BnText.num(s.get("section", ""))]
		"computed":
			return "উৎস: গণনা করে যাচাইকৃত"
		"derived":
			return "উৎস: " + str(s.get("note", "প্রমিত তালিকা"))
		_:
			return "উৎস: পাঠ্যবই ও সাধারণ তথ্যসূত্র"
