class_name Services
extends Node
## Dependency-injection container. Main creates exactly one Services node and hands it to every
## system, actor and UI panel through `setup(s)` / `inject(s)`; nothing uses autoload singletons.
## Long-lived services are children of this node; per-level objects (world, player, directors)
## are assigned by Main when a level loads.

var bus: EventBus
var save: SaveData
var clock: GameClock
var heat: Heat
var qdb: QuestionDB
var taunts: TauntBank
var story: StoryDB
var sfx: Sfx
var fx: Fx
## Resolved graphics quality (0 low .. 3 ultra), set by Main before the world is built.
var quality := 1

# per-level
var world: Node3D          # ProceduralDhaka
var atmo: DhakaAtmosphere
var player: Node           # Player
var camera: Node           # PlayerCamera
var missions: Node         # MissionDirector
var ghosts: Node           # GhostDirector
var crowd: Node            # PedestrianSpawner
var traffic: Node          # Traffic
var ride: Node             # RideService (hailable rickshaws/CNGs with fares)
var ui: Node               # UIRoot
var main: Node             # Main

func build() -> void:
	bus = EventBus.new()
	bus.name = "EventBus"
	add_child(bus)
	save = SaveData.new()
	save.name = "SaveData"
	save.bus = bus
	add_child(save)
	clock = GameClock.new()
	clock.name = "GameClock"
	clock.bus = bus
	add_child(clock)
	heat = Heat.new()
	heat.name = "Heat"
	heat.bus = bus
	add_child(heat)
	qdb = QuestionDB.new()
	qdb.name = "QuestionDB"
	qdb.save = save
	qdb.bus = bus
	add_child(qdb)
	taunts = TauntBank.new()
	taunts.name = "TauntBank"
	add_child(taunts)
	story = StoryDB.new()
	story.name = "StoryDB"
	add_child(story)
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	# One shared player for pre-generated Bengali voice clips (Speech is RefCounted).
	var voice := AudioStreamPlayer.new()
	voice.name = "BengaliVoice"
	voice.bus = "Master"
	add_child(voice)
	Speech.bind(voice)

## Convenience: say a line as a subtitle, and through text-to-speech when a Bengali voice exists.
func say(speaker: String, text: String, seconds: float = 3.5) -> void:
	bus.subtitle.emit(speaker, text, seconds)
	if bool(save.setting("tts", true)):
		Speech.speak(text)

func toast(text: String, kind: String = "info") -> void:
	bus.toast.emit(text, kind)
