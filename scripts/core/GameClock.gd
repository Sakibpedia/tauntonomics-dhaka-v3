class_name GameClock
extends Node
## Day/night cycle. One real second = `minutes_per_second` game minutes (default 1, so a full
## day takes 24 real minutes, as in GTA). Drives DhakaAtmosphere by blending its presets and
## swinging the sun across the sky. Night (19:00–05:30) is when the question-ghosts walk.

const DAWN := 5.5
const DUSK := 19.0

var hour := 8.5
var day := 1
var minutes_per_second := 1.0
var frozen := false
var atmo: DhakaAtmosphere
var bus: EventBus
var _last_hour := -1
var _was_night := false
var _apply_t := 0.0

## [hour, preset] keys; the sun direction is computed separately from the hour.
var _keys: Array = []

func _ready() -> void:
	_keys = [
		[0.0, DhakaAtmosphere.Preset.NIGHT_SODIUM], [4.8, DhakaAtmosphere.Preset.NIGHT_SODIUM],
		[6.0, DhakaAtmosphere.Preset.GOLDEN_SMOG], [8.0, DhakaAtmosphere.Preset.HAZE_NOON],
		[16.2, DhakaAtmosphere.Preset.HAZE_NOON], [17.7, DhakaAtmosphere.Preset.GOLDEN_SMOG],
		[19.3, DhakaAtmosphere.Preset.NIGHT_SODIUM], [24.0, DhakaAtmosphere.Preset.NIGHT_SODIUM],
	]

func set_hour(h: float) -> void:
	hour = fposmod(h, 24.0)
	_apply_t = 0.0
	apply_now()

func is_night() -> bool:
	return hour >= DUSK or hour < DAWN

## 0 at night, 1 in full day, smooth at dawn/dusk.
func daylight() -> float:
	if hour >= DAWN and hour < DAWN + 1.0:
		return hour - DAWN
	if hour >= DUSK - 1.0 and hour < DUSK:
		return DUSK - hour
	return 0.0 if is_night() else 1.0

func hours_to_dawn() -> float:
	return fposmod(DAWN - hour, 24.0)

func skip_to(target_hour: float) -> void:
	if target_hour < hour:
		day += 1
	set_hour(target_hour)

func _process(delta: float) -> void:
	if not frozen:
		hour += delta * minutes_per_second / 60.0
		if hour >= 24.0:
			hour -= 24.0
			day += 1
	var hi := int(floor(hour))
	if hi != _last_hour:
		_last_hour = hi
		if bus:
			bus.hour_changed.emit(hi)
	var night := is_night()
	if night != _was_night:
		_was_night = night
		if bus:
			bus.night_changed.emit(night)
	_apply_t -= delta
	if _apply_t <= 0.0:
		_apply_t = 0.2
		apply_now()

func apply_now() -> void:
	if atmo == null or not is_instance_valid(atmo) or atmo.sky_mat == null:
		return
	var a: Array = _keys[0]
	var b: Array = _keys[_keys.size() - 1]
	for i in _keys.size() - 1:
		var k0: Array = _keys[i]
		var k1: Array = _keys[i + 1]
		if hour >= float(k0[0]) and hour <= float(k1[0]):
			a = k0
			b = k1
			break
	var span := maxf(float(b[0]) - float(a[0]), 0.001)
	var t := clampf((hour - float(a[0])) / span, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var pa: Dictionary = DhakaAtmosphere.PRESETS[a[1]]
	var pb: Dictionary = DhakaAtmosphere.PRESETS[b[1]]
	var p: Dictionary = atmo._mix(pa, pb, t)
	# Sun path: rises in the east (+X) at 06:00, highest at 12:00, sets west at 18:00.
	# At night the same light is a weak bluish moon on the opposite arc.
	var day_frac := (hour - 6.0) / 12.0
	var elev: float
	var azim: float
	if hour >= 6.0 and hour <= 18.0:
		elev = -lerpf(4.0, 64.0, sin(day_frac * PI))
		azim = lerpf(-95.0, -265.0, day_frac)
	else:
		var nf := fposmod(hour - 18.0, 24.0) / 12.0
		elev = -lerpf(10.0, 55.0, sin(nf * PI))
		azim = lerpf(-95.0, -265.0, nf)
	p["sun_rot"] = Vector3(elev, azim, 0.0)
	atmo.apply_preset(p)
	atmo.sun.shadow_enabled = daylight() > 0.05 or atmo.quality >= DhakaAtmosphere.Quality.HIGH
