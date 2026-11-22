class_name Speech
extends RefCounted
## Bengali spoken dialogue. Every authored line is pre-generated as a real Bengali voice clip
## (assets/voice/<md5>.mp3, generated with gTTS from the game's own strings). If a clip exists it
## is played; otherwise we fall back to the OS text-to-speech when a Bengali voice is installed.
## This means the game actually speaks Bengali on Windows too, where no Bengali SAPI voice exists.

const VOICE_DIR := "res://assets/voice/"
static var _player: AudioStreamPlayer
static var _clips: Dictionary = {}
static var _voice := ""
static var _checked := false
static var enabled := true

## Services creates one player and hands it to us (RefCounted cannot own a node).
static func bind(player: AudioStreamPlayer) -> void:
	_player = player

static func available() -> bool:
	if not _checked:
		_checked = true
		if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
			return false
		for lang in ["bn", "bn_BD", "bn-IN", "bn_BD.UTF-8"]:
			var voices := DisplayServer.tts_get_voices_for_language(lang)
			if voices.size() > 0:
				_voice = voices[0]
				return true
	return _voice != ""

static func _key(text: String) -> String:
	return text.md5_text().substr(0, 16)

static func speak(text: String, pitch: float = 1.0, rate: float = 1.0) -> void:
	if not enabled or text.strip_edges() == "":
		return
	var h := _key(text)
	# 1) pre-generated Bengali clip — real voice on every platform. Loaded as raw bytes so the
	#    MP3s need no Godot import step and work identically in source and exported builds.
	if not _clips.has(h):
		var path := VOICE_DIR + h + ".mp3"
		if FileAccess.file_exists(path):
			var bytes := FileAccess.get_file_as_bytes(path)
			# Skip empty / partially written files (the voice bank is generated offline).
			if bytes.size() > 256:
				var stream := AudioStreamMP3.new()
				stream.data = bytes
				_clips[h] = stream
	if _clips.has(h) and _player and is_instance_valid(_player):
		_player.stream = _clips[h]
		_player.pitch_scale = pitch * clampf(rate, 0.6, 1.8)
		_player.play()
		return
	# 2) OS Bengali voice fallback
	if available():
		var clean := text.replace("'", "").replace("\"", "")
		DisplayServer.tts_speak(clean, _voice, 70, pitch, rate, 0, true)

static func stop() -> void:
	if _player and is_instance_valid(_player):
		_player.stop()
	if _voice != "":
		DisplayServer.tts_stop()

## How many authored lines have a recorded voice clip (for diagnostics).
static func clip_count() -> int:
	return _clips.size()
