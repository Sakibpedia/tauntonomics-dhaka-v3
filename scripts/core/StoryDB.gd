class_name StoryDB
extends Node
## Read-only access to data/story/*.json (written by tools/make_story.py).

var characters: Dictionary = {}
var levels: Array = []
var cards: Dictionary = {}
var debates: Dictionary = {}
var posters: Dictionary = {}
var patients: Dictionary = {}
var story: Dictionary = {}

func _ready() -> void:
	characters = BnText.load_json("res://data/story/characters.json", {})
	var lv: Dictionary = BnText.load_json("res://data/story/levels.json", {"levels": []})
	levels = lv.get("levels", [])
	var db: Dictionary = BnText.load_json("res://data/story/debates.json", {})
	cards = db.get("cards", {})
	debates = db.get("debates", {})
	posters = BnText.load_json("res://data/story/posters.json", {})
	patients = BnText.load_json("res://data/story/patients.json", {})
	story = BnText.load_json("res://data/story/story.json", {})

func level(n: int) -> Dictionary:
	for l in levels:
		var d: Dictionary = l
		if int(d["id"]) == n:
			return d
	return {}

func level_count() -> int:
	return levels.size()

func character(id: String) -> Dictionary:
	return characters.get(id, {})

func char_name(id: String) -> String:
	var c := character(id)
	return str(c.get("name", id))

func debate(id: String) -> Dictionary:
	return debates.get(id, {})

func poster_texts(kind: String) -> Array:
	return posters.get(kind, [])

func act_of(level_n: int) -> Dictionary:
	for a in story.get("acts", []):
		var ad: Dictionary = a
		var r: Array = ad["levels"]
		if level_n >= int(r[0]) and level_n <= int(r[1]):
			return ad
	return {}
