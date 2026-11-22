class_name RunPersistence
extends RefCounted

## Crash-proof per-mode active run persistence for Kombo by SOYA GAMES.
## Stores separate in-progress snapshots for Classic, Daily, Sprint, and Gem Hunt
## in user://kombo_runs.json so closing or backgrounding the app never loses a run.

const DEFAULT_RUNS_PATH := "user://kombo_runs.json"
const SCHEMA_VERSION := 1

var runs_path: String = DEFAULT_RUNS_PATH
var _runs: Dictionary = {}


func _init(p_runs_path: String = DEFAULT_RUNS_PATH) -> void:
	runs_path = p_runs_path
	load_all()


static func mode_key(mode: int) -> String:
	match mode:
		GameController.GameMode.CLASSIC:
			return "classic"
		GameController.GameMode.DAILY:
			return "daily"
		GameController.GameMode.SPRINT:
			return "sprint"
		GameController.GameMode.GEM_HUNT:
			return "gem_hunt"
		_:
			return "classic"


func load_all() -> void:
	_runs.clear()
	if not FileAccess.file_exists(runs_path):
		return
	var f := FileAccess.open(runs_path, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_as_text()
	f.close()
	if raw.strip_edges().is_empty():
		return
	var json := JSON.new()
	if json.parse(raw) != OK:
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		return
	var root_dict: Dictionary = json.data
	if int(root_dict.get("version", 0)) != SCHEMA_VERSION:
		return
	var stored: Variant = root_dict.get("runs", {})
	if typeof(stored) == TYPE_DICTIONARY:
		for k in (stored as Dictionary).keys():
			var entry: Variant = (stored as Dictionary)[k]
			if typeof(entry) == TYPE_DICTIONARY:
				_runs[String(k)] = entry


func _write_disk() -> bool:
	var f := FileAccess.open(runs_path, FileAccess.WRITE)
	if f == null:
		return false
	var payload := {
		"version": SCHEMA_VERSION,
		"runs": _runs,
	}
	f.store_string(JSON.stringify(payload))
	f.close()
	return true


func save_run(mode: int, state: Dictionary) -> bool:
	if state.is_empty():
		return false
	_runs[mode_key(mode)] = state
	return _write_disk()


func clear_run(mode: int) -> bool:
	var k := mode_key(mode)
	if not _runs.has(k):
		return false
	_runs.erase(k)
	return _write_disk()


func clear_all() -> void:
	_runs.clear()
	if FileAccess.file_exists(runs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(runs_path))


func has_saved_run(mode: int, today_date_key: String = "") -> bool:
	return not get_saved_run(mode, today_date_key).is_empty()


func get_saved_run(mode: int, today_date_key: String = "") -> Dictionary:
	var k := mode_key(mode)
	if not _runs.has(k):
		return {}
	var entry: Variant = _runs[k]
	if typeof(entry) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = entry
	if bool(d.get("is_game_over", false)):
		return {}
	# Daily snapshots automatically expire after midnight rollover!
	if mode == GameController.GameMode.DAILY and not today_date_key.is_empty():
		if String(d.get("daily_date_key", "")) != today_date_key:
			_runs.erase(k)
			_write_disk()
			return {}
	return d


func get_run_summary(mode: int, today_date_key: String = "") -> Dictionary:
	var d := get_saved_run(mode, today_date_key)
	if d.is_empty():
		return {"has_run": false}
	var score_d: Dictionary = d.get("score_state", {}) as Dictionary
	return {
		"has_run": true,
		"score": int(score_d.get("score", 0)),
		"turn_count": int(d.get("turn_count", 0)),
		"daily_attempt_number": int(d.get("daily_attempt_number", 1)),
		"daily_date_key": String(d.get("daily_date_key", "")),
		"sprint_moves_left": int(d.get("sprint_moves_left", GameController.SPRINT_TOTAL_MOVES)),
		"gem_hunt_stage": int(d.get("gem_hunt_stage", 1)),
		"gem_hunt_targets_left": int(d.get("gem_hunt_targets_left", 0)),
	}
