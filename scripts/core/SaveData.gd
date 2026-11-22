class_name SaveData
extends Node
## Persistent career state in user://dhaka_save.json.
## Holds progress, money, the question-bank deck, unbanished ghosts, NPC memories and the
## choices that decide the ending (arrests vs. executions, patients helped, protests won).

const PATH := "user://dhaka_save.json"
const VERSION := 3

var data: Dictionary = {}
var bus: EventBus

func _ready() -> void:
	reset_defaults()

func reset_defaults() -> void:
	data = {
		"version": VERSION,
		"level": 1, "mission": 0, "unlocked": 1,
		"money": 500, "candles": 1, "intel": 0, "empathy": 0,
		"hp": 100.0, "sanity": 100.0,
		"hour": 8.5, "day": 1,
		"arrests": 0, "kills": 0, "kos": 0, "ghosts_banished": 0,
		"answered": 0, "correct": 0, "by_cat": {},
		"used_q": [],
		"ghosts": [],
		"patients": {},
		"debates": {},
		"npc_mem": {},
		"posters": 0,
		"settings": {"volume": 0.8, "sens": 0.18, "tts": true, "quality": 1, "quality_auto": true, "subtitles": true},
	}

func has_save() -> bool:
	return FileAccess.file_exists(PATH)

func load_game() -> bool:
	if not has_save():
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	reset_defaults()
	var d: Dictionary = parsed
	for k in d.keys():
		data[k] = d[k]
	return true

func save_game() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()

func new_game() -> void:
	var settings: Dictionary = data.get("settings", {})
	reset_defaults()
	data["settings"] = settings

func g(key: String, fallback: Variant = null) -> Variant:
	return data.get(key, fallback)

func s(key: String, value: Variant) -> void:
	data[key] = value

func add(key: String, amount: float) -> float:
	var v := float(data.get(key, 0)) + amount
	if typeof(data.get(key, 0)) == TYPE_INT or key in ["money", "candles", "intel", "empathy", "arrests", "kills", "kos", "ghosts_banished", "answered", "correct", "posters"]:
		data[key] = int(round(v))
	else:
		data[key] = v
	if key == "money" and bus:
		bus.money_changed.emit(int(data["money"]))
	return v

func money() -> int:
	return int(data.get("money", 0))

func spend(amount: int) -> bool:
	if money() < amount:
		return false
	add("money", -amount)
	return true

func setting(key: String, fallback: Variant = null) -> Variant:
	var st: Dictionary = data.get("settings", {})
	return st.get(key, fallback)

func set_setting(key: String, value: Variant) -> void:
	var st: Dictionary = data.get("settings", {})
	st[key] = value
	data["settings"] = st

func record_answer(cat: String, correct: bool) -> void:
	add("answered", 1)
	if correct:
		add("correct", 1)
	var bc: Dictionary = data.get("by_cat", {})
	var row: Array = bc.get(cat, [0, 0])
	row[0] = int(row[0]) + 1
	if correct:
		row[1] = int(row[1]) + 1
	bc[cat] = row
	data["by_cat"] = bc

## NPC memory: relationship and what the player has done with this person.
func mem(npc_id: String) -> Dictionary:
	var m: Dictionary = data.get("npc_mem", {})
	if not m.has(npc_id):
		m[npc_id] = {"met": 0, "rel": 0, "beaten": 0, "answered": 0, "failed": 0, "last": ""}
		data["npc_mem"] = m
	return m[npc_id]

func add_ghost(record: Dictionary) -> void:
	var gs: Array = data.get("ghosts", [])
	gs.append(record)
	data["ghosts"] = gs

func remove_ghost(gid: String) -> void:
	var gs: Array = data.get("ghosts", [])
	var keep: Array = []
	for r in gs:
		var rec: Dictionary = r
		if str(rec.get("id", "")) != gid:
			keep.append(rec)
	data["ghosts"] = keep

func ghosts() -> Array:
	return data.get("ghosts", [])

func accuracy() -> float:
	var a := int(data.get("answered", 0))
	return 0.0 if a == 0 else float(data.get("correct", 0)) / float(a)

## Which ending the choices add up to.
func ending() -> String:
	var arrests := int(data.get("arrests", 0))
	var kills := int(data.get("kills", 0))
	var unbanished := ghosts().size()
	if unbanished >= 4:
		return "haunted"
	if kills > arrests:
		return "vengeance"
	return "justice"
