class_name BgmManager
extends Node

## Seamless looping BGM manager for Kombo.
## Plays res://assets/audio/bgm_mellow_groove.mp3 with smooth state-aware mixing
## (Title, Playing, FEVER energy lift, Game Over ducking) and transient ducking
## so rising-pitch combo chimes and special-block blasts always punch cleanly.

enum Mode {
	TITLE,
	PLAYING,
	FEVER,
	GAME_OVER,
}

const BGM_PATH: String = "res://assets/audio/bgm_mellow_groove.mp3"

# Tuned against the track's -16.5 dB mean RMS / -1.8 dB peak so SFX stay crisp on top.
const VOL_TITLE_DB: float = -14.0
const VOL_PLAYING_DB: float = -11.5
const VOL_FEVER_DB: float = -9.5
const VOL_GAME_OVER_DB: float = -18.5
const FADE_START_DB: float = -42.0

const PITCH_NORMAL: float = 1.0
const PITCH_FEVER: float = 1.035

var _player: AudioStreamPlayer
var _mode: Mode = Mode.TITLE
var _muted: bool = false
var _bgm_enabled: bool = true

var _current_vol_db: float = FADE_START_DB
var _target_vol_db: float = VOL_TITLE_DB
var _current_pitch: float = PITCH_NORMAL
var _target_pitch: float = PITCH_NORMAL

var _duck_db: float = 0.0
var _duck_target_db: float = 0.0
var _duck_hold_left: float = 0.0
var _duck_release_rate: float = 8.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_player()
	set_process(true)


func _exit_tree() -> void:
	if _player != null:
		_player.stop()
		_player.stream = null


func _process(delta: float) -> void:
	var dt: float = minf(delta, 0.05)
	if _player == null:
		return

	# Smoothly approach mode volume & pitch targets.
	var vol_rate: float = 22.0 if _target_vol_db > _current_vol_db else 16.0
	_current_vol_db = move_toward(_current_vol_db, _target_vol_db, vol_rate * dt)

	var pitch_rate: float = 0.09 if _target_pitch > _current_pitch else 0.06
	_current_pitch = move_toward(_current_pitch, _target_pitch, pitch_rate * dt)

	# Smooth transient ducking envelope (fast attack, brief hold, smooth musical release).
	if _duck_hold_left > 0.0:
		_duck_hold_left = maxf(0.0, _duck_hold_left - dt)
		_duck_db = move_toward(_duck_db, _duck_target_db, 38.0 * dt)
	else:
		_duck_target_db = 0.0
		_duck_db = move_toward(_duck_db, 0.0, _duck_release_rate * dt)

	_player.volume_db = _current_vol_db + _duck_db
	_player.pitch_scale = _current_pitch


func set_mode(mode: Mode) -> void:
	_mode = mode
	match _mode:
		Mode.TITLE:
			_target_vol_db = VOL_TITLE_DB
			_target_pitch = PITCH_NORMAL
		Mode.PLAYING:
			_target_vol_db = VOL_PLAYING_DB
			_target_pitch = PITCH_NORMAL
		Mode.FEVER:
			_target_vol_db = VOL_FEVER_DB
			_target_pitch = PITCH_FEVER
		Mode.GAME_OVER:
			_target_vol_db = VOL_GAME_OVER_DB
			_target_pitch = PITCH_NORMAL


func get_mode() -> Mode:
	return _mode


func duck(dip_db: float = 4.0, hold_sec: float = 0.25, release_sec: float = 0.6) -> void:
	var dip: float = -absf(dip_db)
	_duck_target_db = minf(_duck_target_db, dip)
	_duck_hold_left = maxf(_duck_hold_left, maxf(0.02, hold_sec))
	_duck_release_rate = maxf(2.0, absf(_duck_target_db) / maxf(0.15, release_sec))


func set_muted(muted: bool) -> void:
	_muted = muted
	_sync_playback_state()


func is_muted() -> bool:
	return _muted


func set_bgm_enabled(enabled: bool) -> void:
	_bgm_enabled = enabled
	_sync_playback_state()


func is_bgm_enabled() -> bool:
	return _bgm_enabled


func is_playing() -> bool:
	return _player != null and _player.playing and not _player.stream_paused


func get_stream_path() -> String:
	return BGM_PATH


func ensure_started_on_gesture() -> void:
	if _player == null or _player.stream == null:
		return
	if _bgm_enabled and not _muted and _player.is_inside_tree():
		if not _player.playing:
			_current_vol_db = minf(_current_vol_db, -28.0)
			_player.volume_db = _current_vol_db
			_player.stream_paused = false
			_player.play()
		elif _player.stream_paused:
			_player.stream_paused = false


func _setup_player() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "BgmStreamPlayer"
	_player.bus = &"Master"
	_player.volume_db = _current_vol_db
	_player.pitch_scale = _current_pitch
	_player.finished.connect(_on_player_finished)
	add_child(_player)

	if not ResourceLoader.exists(BGM_PATH):
		push_warning("BgmManager: BGM stream not found at %s" % BGM_PATH)
		return

	var stream: AudioStream = load(BGM_PATH) as AudioStream
	if stream == null:
		push_warning("BgmManager: Failed to load BGM stream at %s" % BGM_PATH)
		return

	if stream is AudioStreamMP3:
		var mp3: AudioStreamMP3 = stream as AudioStreamMP3
		mp3.loop = true
		mp3.loop_offset = 0.0

	_player.stream = stream
	_sync_playback_state()


func _sync_playback_state() -> void:
	if _player == null or _player.stream == null:
		return

	var should_play: bool = (not _muted) and _bgm_enabled
	if should_play:
		if not _player.playing:
			_current_vol_db = minf(_current_vol_db, -28.0)
			_player.volume_db = _current_vol_db
			_player.stream_paused = false
			if _player.is_inside_tree():
				_player.play()
		elif _player.stream_paused:
			_current_vol_db = minf(_current_vol_db, -28.0)
			_player.volume_db = _current_vol_db
			_player.stream_paused = false
	else:
		if _player.playing:
			_player.stream_paused = true


func _on_player_finished() -> void:
	if _player == null or _player.stream == null:
		return
	if not _muted and _bgm_enabled and _player.is_inside_tree():
		_player.play()
