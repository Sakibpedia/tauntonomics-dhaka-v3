class_name Sfx
extends Node
## Every sound in the game is synthesised at runtime (no audio files): stings, punches, ghost drones,
## the street bed with rickshaw bells and bus horns, a CNG engine loop and a police siren.

const SR := 22050
var _cache: Dictionary = {}
var _pool: Array = []
var _loops: Dictionary = {}
var _b := PackedFloat32Array()
# Sounds are synthesised in GDScript and cost 10-800 ms each. A worker thread pre-generates the
# whole bank while the player is still in the menu, so no first-use hitch ever reaches gameplay.
var _warm_thread: Thread
var _warm_gen: Sfx          # separate synth instance: its own scratch buffer and cache
var _warm_cache: Dictionary = {}
var _warm_done := false
var _warm_cancel := false
var _warm_mutex := Mutex.new()
const LOOPED := ["crowd", "street", "ghost", "sizzle", "fluoro", "engine", "siren", "night"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)
	if not OS.has_feature("web"):
		_start_warm_thread()

func _start_warm_thread() -> void:
	var names: Array[String] = []
	for m in get_method_list():
		var nm := str(m["name"])
		if nm.begins_with("_gen_"):
			names.append(nm.substr(5))
	if names.is_empty():
		return
	_warm_gen = Sfx.new()
	_warm_gen.name = "SfxWarm"
	_warm_thread = Thread.new()
	_warm_thread.start(_warm_worker.bind(names, _warm_gen))

func _warm_worker(names: Array[String], gen: Sfx) -> void:
	var local := {}
	for n in names:
		if _warm_cancel:
			break
		var st := gen._get_stream(n)
		if st != null:
			local[n] = st
	_warm_mutex.lock()
	_warm_cache = local
	_warm_done = true
	_warm_mutex.unlock()

func _exit_tree() -> void:
	_warm_cancel = true
	if _warm_thread and _warm_thread.is_started():
		_warm_thread.wait_to_finish()
	if _warm_gen:
		_warm_gen.free()
		_warm_gen = null

func _process(_delta: float) -> void:
	_warm_mutex.lock()
	if not _warm_done:
		_warm_mutex.unlock()
		return
	var done := _warm_cache
	_warm_cache = {}
	_warm_done = false
	_warm_mutex.unlock()
	for k in done:
		if not _cache.has(k):
			_cache[k] = done[k]
	if _warm_thread:
		_warm_thread.wait_to_finish()
		_warm_thread = null
	if _warm_gen:
		_warm_gen.free()
		_warm_gen = null
	if OS.get_environment("DHAKA_LOG_SLOW") != "":
		print("WARM audio ready: %d sounds" % _cache.size())

func set_master(linear: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(linear, 0.001, 1.0)))

func warm(names: Array) -> void:
	for n in names:
		_get_stream(str(n))

func play(sname: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := _get_stream(sname)
	if s == null:
		return
	for p in _pool:
		var ap: AudioStreamPlayer = p
		if not ap.playing:
			ap.stream = s
			ap.volume_db = vol_db
			ap.pitch_scale = pitch
			ap.play()
			return
	var ap0: AudioStreamPlayer = _pool[0]
	ap0.stream = s
	ap0.volume_db = vol_db
	ap0.pitch_scale = pitch
	ap0.play()

var world_root: Node3D

func play_at(sname: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var root: Node = world_root if world_root != null and is_instance_valid(world_root) else get_tree().current_scene
	var s := _get_stream(sname)
	if root == null or s == null or not (root is Node3D):
		play(sname, vol_db, pitch)
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = 60.0
	root.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

func play_loop(sname: String, vol_db: float = -10.0) -> void:
	if _loops.has(sname):
		var existing: AudioStreamPlayer = _loops[sname]
		existing.volume_db = vol_db
		return
	var s := _get_stream(sname)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = vol_db
	add_child(p)
	p.play()
	_loops[sname] = p

func set_loop_volume(sname: String, vol_db: float) -> void:
	if _loops.has(sname):
		var p: AudioStreamPlayer = _loops[sname]
		p.volume_db = vol_db

func stop_loop(sname: String) -> void:
	if _loops.has(sname):
		var p: AudioStreamPlayer = _loops[sname]
		p.stop()
		p.queue_free()
		_loops.erase(sname)

func stop_all_loops() -> void:
	for k in _loops.keys():
		stop_loop(str(k))

func _get_stream(sname: String) -> AudioStreamWAV:
	if _cache.has(sname):
		return _cache[sname]
	var m := "_gen_" + sname
	if not has_method(m):
		push_warning("No synth for sound: " + sname)
		return null
	var t0 := Time.get_ticks_usec()
	var data: PackedFloat32Array = call(m)
	var looped := sname in LOOPED
	var st := _mk(data, looped)
	_cache[sname] = st
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if ms > 8.0 and OS.get_environment("DHAKA_LOG_SLOW") != "":
		print("SLOW sfx_synth %s %.1f ms" % [sname, ms])
	return st

## Dev helper: synthesise every sound once and report the cost (DHAKA_WARM_AUDIO=1).
func warm_all() -> void:
	var names: Array[String] = []
	for m in get_method_list():
		var nm := str(m["name"])
		if nm.begins_with("_gen_"):
			names.append(nm.substr(5))
	var t0 := Time.get_ticks_usec()
	for n in names:
		_get_stream(n)
	print("WARM audio %d sounds in %.1f ms" % [names.size(), (Time.get_ticks_usec() - t0) / 1000.0])

func _mk(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w

func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * SR))
	return b

func _n() -> float:
	return randf() * 2.0 - 1.0

func _tone(start: float, dur: float, f0: float, f1: float, amp: float, decay: float, wave: String = "sin", vib: float = 0.0) -> void:
	var i0 := int(start * SR)
	var n := int(dur * SR)
	var ph := 0.0
	for i in n:
		var idx := i0 + i
		if idx >= _b.size():
			break
		var t := float(i) / SR
		var f := lerpf(f0, f1, t / dur) * (1.0 + vib * sin(TAU * 5.5 * t))
		ph += TAU * f / SR
		var v := 0.0
		match wave:
			"sq":
				v = 1.0 if sin(ph) >= 0.0 else -1.0
				v *= 0.55
			"saw":
				v = fposmod(ph / TAU, 1.0) * 2.0 - 1.0
				v *= 0.6
			"brass":
				v = sin(ph) * 0.6 + sin(ph * 2.0) * 0.3 + sin(ph * 3.0) * 0.18 + sin(ph * 4.0) * 0.08
			_:
				v = sin(ph)
		var env := minf(t / 0.008, 1.0) * exp(-t * decay)
		_b[idx] += v * amp * env

func _noise(start: float, dur: float, amp: float, decay: float, lp: float = 0.5) -> void:
	var i0 := int(start * SR)
	var y := 0.0
	for i in int(dur * SR):
		var idx := i0 + i
		if idx >= _b.size():
			break
		var t := float(i) / SR
		y += lp * (_n() - y)
		_b[idx] += y * amp * exp(-t * decay) * minf(t / 0.004, 1.0)

# ---------------- sound recipes ----------------
func _gen_tick() -> PackedFloat32Array:
	_b = _buf(0.04); _tone(0, 0.04, 3200, 2600, 0.25, 90); return _b
func _gen_click() -> PackedFloat32Array:
	_b = _buf(0.08); _noise(0, 0.03, 0.4, 120, 0.9); _tone(0, 0.08, 1400, 900, 0.3, 50); return _b
func _gen_type() -> PackedFloat32Array:
	_b = _buf(0.05); _noise(0, 0.05, 0.6, 160, 0.95); _tone(0, 0.03, 2100, 1800, 0.15, 120); return _b
func _gen_bell() -> PackedFloat32Array:
	_b = _buf(1.1)
	for s in [0.0, 0.2]:
		_tone(s, 0.9, 2350, 2350, 0.35, 5, "sin", 0.006)
		_tone(s, 0.9, 3520, 3520, 0.2, 7)
		_tone(s, 0.6, 5200, 5200, 0.1, 11)
	return _b
func _gen_gate() -> PackedFloat32Array:
	_b = _buf(1.3)
	_tone(0, 1.25, 520, 1250, 0.35, 0.6, "saw", 0.03)
	_tone(0.05, 1.2, 780, 1600, 0.18, 0.9, "sin", 0.05)
	_noise(0, 1.3, 0.12, 0.8, 0.3)
	_noise(1.12, 0.15, 0.6, 30, 0.6)
	return _b
func _gen_cooker() -> PackedFloat32Array:
	_b = _buf(1.8)
	for i in _b.size():
		var t := float(i) / SR
		_b[i] += _n() * 0.22 * minf(t * 1.5, 1.0) * (1.0 if t < 1.6 else (1.8 - t) * 5.0)
	_tone(0.45, 1.3, 1700, 2150, 0.32, 0.4, "sin", 0.02)
	return _b
func _gen_sizzle() -> PackedFloat32Array:
	_b = _buf(2.0)
	for i in _b.size():
		_b[i] = _n() * 0.12 * (0.6 + 0.4 * sin(float(i) * 0.013)) * (1.0 if randf() > 0.002 else 3.0)
	return _b
func _gen_thwack() -> PackedFloat32Array:
	_b = _buf(0.3); _tone(0, 0.3, 170, 55, 0.8, 16); _noise(0, 0.05, 0.5, 60, 0.7); return _b
func _gen_hit() -> PackedFloat32Array:
	_b = _buf(0.25); _tone(0, 0.25, 120, 70, 0.75, 18); _noise(0, 0.08, 0.35, 40, 0.4); return _b
func _gen_boom() -> PackedFloat32Array:
	_b = _buf(0.9); _tone(0, 0.9, 70, 38, 0.95, 5); _noise(0, 0.5, 0.45, 7, 0.2); return _b
func _gen_splash() -> PackedFloat32Array:
	_b = _buf(0.7)
	_noise(0, 0.7, 0.55, 6, 0.35)
	for k in 6:
		_tone(randf() * 0.35, 0.12, randf_range(600, 1200), randf_range(1300, 2000), 0.12, 25)
	return _b
func _gen_shatter() -> PackedFloat32Array:
	_b = _buf(0.9)
	var prev := 0.0
	for i in _b.size():
		var t := float(i) / SR
		var x := _n()
		_b[i] += (x - prev) * 0.5 * exp(-t * 7.0)
		prev = x
	for f in [3150, 4720, 6080, 7400]:
		_tone(0, 0.8, f, f * 0.995, 0.12, randf_range(6, 10))
	for k in 7:
		_tone(randf_range(0.05, 0.6), 0.1, randf_range(3500, 6500), randf_range(3000, 6000), 0.1, 40)
	return _b
func _gen_sting() -> PackedFloat32Array:
	# sad trombone, the internationally recognised sound of a logic break
	_b = _buf(2.0)
	var notes := [233.08, 220.0, 207.65, 196.0]
	for k in 4:
		var d := 0.32 if k < 3 else 0.95
		_tone(k * 0.34, d, notes[k], notes[k] * (0.985 if k == 3 else 1.0), 0.45, 2.2 if k < 3 else 1.4, "brass", 0.0 if k < 3 else 0.035)
	return _b
func _gen_tension() -> PackedFloat32Array:
	_b = _buf(1.4)
	_tone(0, 1.4, 110, 110, 0.4, 1.5, "saw")
	_tone(0, 1.4, 155.6, 155.6, 0.3, 1.5, "saw")
	_tone(0.0, 0.4, 880, 830, 0.12, 4)
	return _b
func _gen_sting_win() -> PackedFloat32Array:
	_b = _buf(1.3)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for k in 4:
		_tone(k * 0.09, 0.9 - k * 0.1, notes[k], notes[k], 0.3, 3.0, "brass")
	return _b
func _gen_ding() -> PackedFloat32Array:
	_b = _buf(0.6); _tone(0, 0.6, 1046.5, 1046.5, 0.35, 5); _tone(0.07, 0.5, 1568, 1568, 0.25, 6); return _b
func _gen_buzz() -> PackedFloat32Array:
	_b = _buf(0.5); _tone(0, 0.5, 140, 120, 0.4, 3, "sq"); return _b
func _gen_stamp() -> PackedFloat32Array:
	_b = _buf(0.8); _tone(0, 0.6, 90, 45, 0.95, 9); _noise(0, 0.06, 0.8, 50, 0.8); _noise(0.02, 0.7, 0.12, 5, 0.15); return _b
func _gen_news() -> PackedFloat32Array:
	_b = _buf(2.6)
	var mel := [[0.0, 392.0], [0.18, 523.25], [0.36, 659.25], [0.54, 783.99], [0.9, 659.25], [1.08, 783.99], [1.26, 1046.5]]
	for m in mel:
		_tone(m[0], 0.5 if m[0] < 1.2 else 1.2, m[1], m[1], 0.28, 2.5 if m[0] < 1.2 else 1.2, "brass")
	for s in [0.0, 0.54, 1.26]:
		_tone(s, 0.5, 98, 98, 0.4, 5, "saw")
	_noise(1.26, 0.4, 0.25, 9, 0.9)
	return _b
func _gen_whoosh() -> PackedFloat32Array:
	_b = _buf(0.4)
	var y := 0.0
	for i in _b.size():
		var t := float(i) / _b.size()
		var a := lerpf(0.05, 0.6, sin(t * PI))
		y += a * (_n() - y)
		_b[i] = y * 0.6 * sin(t * PI)
	return _b
func _gen_parry() -> PackedFloat32Array:
	_b = _buf(0.6); _tone(0, 0.6, 1650, 1650, 0.4, 6); _tone(0, 0.5, 2470, 2470, 0.25, 8); _noise(0, 0.02, 0.5, 200, 0.9); return _b
func _gen_alarm() -> PackedFloat32Array:
	_b = _buf(1.2)
	for k in 8:
		_tone(k * 0.15, 0.15, 880.0 if k % 2 == 0 else 660.0, 880.0 if k % 2 == 0 else 660.0, 0.3, 1, "sq")
	return _b
func _gen_heartbeat() -> PackedFloat32Array:
	_b = _buf(0.9); _tone(0, 0.18, 60, 45, 0.9, 20); _tone(0.22, 0.18, 55, 42, 0.7, 20); return _b
func _gen_ghost() -> PackedFloat32Array:
	_b = _buf(4.0)
	_tone(0, 4.0, 110, 108, 0.18, 0.0, "sin", 0.02)
	_tone(0, 4.0, 164.8, 166, 0.12, 0.0, "sin", 0.03)
	_noise(0, 4.0, 0.05, 0.0, 0.08)
	return _b
func _gen_notify() -> PackedFloat32Array:
	_b = _buf(0.4); _tone(0, 0.18, 1320, 1320, 0.3, 10); _tone(0.1, 0.3, 1760, 1760, 0.3, 9); return _b
func _gen_page() -> PackedFloat32Array:
	_b = _buf(0.35)
	for k in 5:
		_noise(randf() * 0.25, 0.07, 0.35, 35, 0.6)
	return _b
func _gen_step() -> PackedFloat32Array:
	_b = _buf(0.09); _tone(0, 0.09, 95, 70, 0.35, 40); _noise(0, 0.03, 0.15, 90, 0.3); return _b
func _gen_door() -> PackedFloat32Array:
	_b = _buf(0.9); _tone(0, 0.75, 210, 140, 0.25, 2, "saw", 0.08); _noise(0.78, 0.1, 0.6, 50, 0.7); return _b
func _gen_roar() -> PackedFloat32Array:
	_b = _buf(1.8)
	_tone(0, 1.8, 82, 64, 0.6, 1.0, "saw", 0.06)
	_tone(0, 1.8, 123, 96, 0.35, 1.2, "saw", 0.08)
	_noise(0, 1.8, 0.3, 1.2, 0.25)
	for i in _b.size():
		_b[i] = clampf(_b[i] * 1.6, -0.9, 0.9)
	return _b
func _gen_chime() -> PackedFloat32Array:
	_b = _buf(1.6)
	var notes := [784.0, 987.77, 1174.66, 1567.98]
	for k in 4:
		_tone(k * 0.12, 1.2, notes[k], notes[k], 0.22, 3.0)
	return _b
func _gen_horn() -> PackedFloat32Array:
	_b = _buf(0.55); _tone(0, 0.5, 420, 420, 0.25, 1, "sq"); _tone(0, 0.5, 528, 528, 0.2, 1, "sq"); return _b
func _gen_crowd() -> PackedFloat32Array:
	_b = _buf(4.0)
	var voices := 7
	var ys := []
	var phs := []
	for v in voices:
		ys.append(0.0)
		phs.append(randf() * TAU)
	for i in _b.size():
		var t := float(i) / SR
		var s := 0.0
		for v in voices:
			var y: float = ys[v]
			y += 0.09 * (_n() - y)
			ys[v] = y
			var am := 0.5 + 0.5 * sin(TAU * (2.0 + v * 0.7) * t + phs[v])
			s += y * am
		_b[i] = s * 0.35
	return _b
func _gen_street() -> PackedFloat32Array:
	_b = _buf(6.0)
	var y := 0.0
	for i in _b.size():
		y += 0.02 * (_n() - y)
		_b[i] = y * 0.9
	_tone(1.3, 0.4, 420, 420, 0.06, 1, "sq")
	_tone(1.3, 0.4, 528, 528, 0.05, 1, "sq")
	_tone(3.9, 0.7, 2350, 2350, 0.05, 5)
	_tone(4.1, 0.6, 2350, 2350, 0.05, 5)
	return _b
func _gen_fluoro() -> PackedFloat32Array:
	_b = _buf(2.0); _tone(0, 2.0, 120, 120, 0.05, 0); _tone(0, 2.0, 240, 240, 0.03, 0); return _b
func _gen_punch() -> PackedFloat32Array:
	_b = _buf(0.22); _tone(0, 0.2, 140, 60, 0.9, 22); _noise(0, 0.04, 0.7, 90, 0.8); return _b
func _gen_swing() -> PackedFloat32Array:
	_b = _buf(0.25)
	var y := 0.0
	for i in _b.size():
		var t := float(i) / _b.size()
		y += lerpf(0.1, 0.5, t) * (_n() - y)
		_b[i] = y * 0.35 * sin(t * PI)
	return _b
func _gen_correct() -> PackedFloat32Array:
	_b = _buf(0.7); _tone(0, 0.5, 880, 880, 0.3, 6); _tone(0.09, 0.55, 1318.5, 1318.5, 0.28, 5); return _b
func _gen_wrong() -> PackedFloat32Array:
	_b = _buf(0.6); _tone(0, 0.25, 196, 190, 0.35, 4, "sq"); _tone(0.24, 0.35, 147, 140, 0.35, 4, "sq"); return _b
func _gen_coin() -> PackedFloat32Array:
	_b = _buf(0.45); _tone(0, 0.1, 1975, 1975, 0.3, 12); _tone(0.08, 0.35, 2637, 2637, 0.3, 7); return _b
func _gen_burn() -> PackedFloat32Array:
	_b = _buf(1.2)
	for i in _b.size():
		var t := float(i) / SR
		_b[i] = _n() * 0.4 * exp(-t * 2.0) * (1.0 if randf() > 0.004 else 3.0)
	_tone(0, 1.2, 320, 90, 0.25, 2.0, "saw", 0.05)
	return _b
func _gen_engine() -> PackedFloat32Array:
	_b = _buf(1.0)
	var ph := 0.0
	for i in _b.size():
		ph += TAU * 34.0 / SR
		var v := (fposmod(ph / TAU, 1.0) * 2.0 - 1.0) * 0.35 + sin(ph * 2.0) * 0.15
		_b[i] = v * (0.8 + 0.2 * sin(ph * 0.25))
	_noise(0, 1.0, 0.08, 0.0, 0.3)
	return _b
func _gen_siren() -> PackedFloat32Array:
	_b = _buf(2.0)
	var ph := 0.0
	for i in _b.size():
		var t := float(i) / SR
		var f := 700.0 + 350.0 * sin(TAU * 0.5 * t)
		ph += TAU * f / SR
		_b[i] = sin(ph) * 0.18
	return _b
func _gen_night() -> PackedFloat32Array:
	# crickets, a far dog, a generator hum
	_b = _buf(6.0)
	for k in 40:
		var st := randf() * 5.8
		_tone(st, 0.06, 4300, 4250, 0.04, 30)
	_tone(0, 6.0, 100, 100, 0.03, 0)
	_tone(2.2, 0.35, 520, 380, 0.05, 6, "saw")
	_tone(2.7, 0.3, 520, 380, 0.04, 6, "saw")
	_noise(0, 6.0, 0.03, 0.0, 0.05)
	return _b
func _gen_candle() -> PackedFloat32Array:
	_b = _buf(0.5); _noise(0, 0.12, 0.5, 30, 0.7); _noise(0.1, 0.4, 0.15, 6, 0.2); return _b
func _gen_scream() -> PackedFloat32Array:
	_b = _buf(1.2); _tone(0, 1.2, 600, 900, 0.25, 1.5, "saw", 0.08); _tone(0, 1.2, 1200, 1500, 0.1, 2.0, "sin", 0.1); return _b
