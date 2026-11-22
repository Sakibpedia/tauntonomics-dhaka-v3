class_name Heat
extends Node
## GTA-style wanted level, but the people hunting you are the fictional Syndicate's goons.
## Crimes, wrong answers given to Syndicate informants, and noisy fights raise it. It cools when
## no hunter can see you. Each star spawns more and tougher pursuers.

signal pursue(stars: int)

var stars := 0
var level := 0.0           # 0..5 continuous
var seen_timer := 0.0      # seconds since a hunter last saw the player
var bus: EventBus
var _spawn_t := 0.0
var locked := false        # missions can pin the level (rooftop chase)

func add(amount: float, reason: String = "") -> void:
	var before := stars
	level = clampf(level + amount, 0.0, 5.0)
	seen_timer = 0.0
	stars = int(ceil(level - 0.001))
	if stars != before and bus:
		bus.heat_changed.emit(stars)
		if stars > before and reason != "":
			bus.toast.emit("সিন্ডিকেট সতর্ক: " + reason, "danger")

func set_level(v: int, lock: bool = false) -> void:
	level = float(v)
	stars = v
	locked = lock
	seen_timer = 0.0
	if bus:
		bus.heat_changed.emit(stars)

func clear() -> void:
	locked = false
	set_level(0)

func spotted() -> void:
	seen_timer = 0.0

func _process(delta: float) -> void:
	if stars == 0:
		return
	seen_timer += delta
	if not locked and seen_timer > 12.0:
		var before := stars
		level = maxf(0.0, level - delta * 0.18)
		stars = int(ceil(level - 0.001))
		if stars != before and bus:
			bus.heat_changed.emit(stars)
			if stars == 0:
				bus.toast.emit("সিন্ডিকেট আপনাকে হারিয়ে ফেলেছে", "info")
	_spawn_t -= delta
	if _spawn_t <= 0.0 and stars > 0:
		_spawn_t = maxf(6.0, 22.0 - stars * 3.5)
		pursue.emit(stars)
