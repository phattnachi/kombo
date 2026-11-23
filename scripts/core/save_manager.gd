class_name SaveManager
extends RefCounted

## Persistent storage for Kombo high score and best combo records.

const DEFAULT_SAVE_PATH := "user://kombo_save.json"

var save_path: String = DEFAULT_SAVE_PATH
var high_score: int = 0
var best_combo: int = 0
var sfx_enabled: bool = true
var bgm_enabled: bool = true
var vibration_enabled: bool = true
var notifications_enabled: bool = true
var daily_date: String = ""
var daily_attempts_used: int = 0
var daily_best_score: int = 0
var daily_best_combo: int = 0
var daily_streak: int = 0
var daily_last_completed_date: String = ""
var sprint_high_score: int = 0
var sprint_best_combo: int = 0
var gem_hunt_high_score: int = 0
var gem_hunt_best_stage: int = 1
var gem_hunt_best_combo: int = 0
var coins: int = 0
var unlocked_skins: Array[String] = ["jewel"]
var equipped_skin: String = "jewel"
var unlocked_backgrounds: Array[String] = ["swirl"]
var equipped_background: String = "swirl"
var skill_reroll_stock: int = 0
var skill_bomb_stock: int = 0
var skill_lightning_stock: int = 0
var gem_hunt_cleared_stages: Array[int] = []
var daily_reward_claimed_date: String = ""
var save_count: int = 0


func _init(p_save_path: String = DEFAULT_SAVE_PATH) -> void:
	save_path = p_save_path
	load_data()


func load_data() -> Dictionary:
	high_score = 0
	best_combo = 0
	sfx_enabled = true
	bgm_enabled = true
	vibration_enabled = true
	notifications_enabled = true
	daily_date = ""
	daily_attempts_used = 0
	daily_best_score = 0
	daily_best_combo = 0
	daily_streak = 0
	daily_last_completed_date = ""
	sprint_high_score = 0
	sprint_best_combo = 0
	gem_hunt_high_score = 0
	gem_hunt_best_stage = 1
	gem_hunt_best_combo = 0
	coins = 0
	unlocked_skins = ["jewel"]
	equipped_skin = "jewel"
	unlocked_backgrounds = ["swirl"]
	equipped_background = "swirl"
	skill_reroll_stock = 0
	skill_bomb_stock = 0
	skill_lightning_stock = 0
	gem_hunt_cleared_stages = []
	daily_reward_claimed_date = ""

	if not FileAccess.file_exists(save_path):
		return _to_dict()

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return _to_dict()

	var raw_text := file.get_as_text()
	file.close()
	if raw_text.strip_edges().is_empty():
		return _to_dict()

	var json := JSON.new()
	if json.parse(raw_text) != OK:
		return _to_dict()
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return _to_dict()

	var data: Dictionary = parsed
	high_score = _parse_non_negative_int(data.get("high_score", 0))
	best_combo = _parse_non_negative_int(data.get("best_combo", 0))
	sfx_enabled = _parse_bool(data.get("sfx_enabled", true), true)
	bgm_enabled = _parse_bool(data.get("bgm_enabled", true), true)
	vibration_enabled = _parse_bool(data.get("vibration_enabled", true), true)
	notifications_enabled = _parse_bool(data.get("notifications_enabled", true), true)
	daily_date = _parse_string(data.get("daily_date", ""))
	daily_attempts_used = clampi(_parse_non_negative_int(data.get("daily_attempts_used", 0)), 0, DailyChallenge.MAX_DAILY_ATTEMPTS)
	daily_best_score = _parse_non_negative_int(data.get("daily_best_score", 0))
	daily_best_combo = _parse_non_negative_int(data.get("daily_best_combo", 0))
	daily_streak = _parse_non_negative_int(data.get("daily_streak", 0))
	daily_last_completed_date = _parse_string(data.get("daily_last_completed_date", ""))
	sprint_high_score = _parse_non_negative_int(data.get("sprint_high_score", 0))
	sprint_best_combo = _parse_non_negative_int(data.get("sprint_best_combo", 0))
	gem_hunt_high_score = _parse_non_negative_int(data.get("gem_hunt_high_score", 0))
	gem_hunt_best_stage = maxi(1, _parse_non_negative_int(data.get("gem_hunt_best_stage", 1)))
	gem_hunt_best_combo = _parse_non_negative_int(data.get("gem_hunt_best_combo", 0))
	coins = _parse_non_negative_int(data.get("coins", 0))
	unlocked_skins = ["jewel"]
	var raw_skins: Variant = data.get("unlocked_skins", ["jewel"])
	if typeof(raw_skins) == TYPE_ARRAY:
		for item in (raw_skins as Array):
			var sid := _parse_string(item)
			if not sid.is_empty() and not unlocked_skins.has(sid):
				unlocked_skins.append(sid)
	var eq := _parse_string(data.get("equipped_skin", "jewel"))
	equipped_skin = eq if unlocked_skins.has(eq) else "jewel"
	unlocked_backgrounds = ["swirl"]
	var raw_bgs: Variant = data.get("unlocked_backgrounds", ["swirl"])
	if typeof(raw_bgs) == TYPE_ARRAY:
		for item in (raw_bgs as Array):
			var bid := _parse_string(item)
			if not bid.is_empty() and not unlocked_backgrounds.has(bid):
				unlocked_backgrounds.append(bid)
	var eq_bg := _parse_string(data.get("equipped_background", "swirl"))
	equipped_background = eq_bg if unlocked_backgrounds.has(eq_bg) else "swirl"
	skill_reroll_stock = _parse_non_negative_int(data.get("skill_reroll_stock", 0))
	skill_bomb_stock = _parse_non_negative_int(data.get("skill_bomb_stock", 0))
	skill_lightning_stock = _parse_non_negative_int(data.get("skill_lightning_stock", 0))
	gem_hunt_cleared_stages = []
	var raw_stages: Variant = data.get("gem_hunt_cleared_stages", [])
	if typeof(raw_stages) == TYPE_ARRAY:
		for st_item in (raw_stages as Array):
			var st_num := _parse_non_negative_int(st_item)
			if st_num >= 1 and not gem_hunt_cleared_stages.has(st_num):
				gem_hunt_cleared_stages.append(st_num)
	daily_reward_claimed_date = _parse_string(data.get("daily_reward_claimed_date", ""))
	return _to_dict()


func save_data() -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	var payload := JSON.stringify(_to_dict(), "\t")
	file.store_string(payload)
	file.close()
	save_count += 1
	return true


func update_records(candidate_score: int, candidate_combo: int) -> bool:
	var changed := false
	if candidate_score > high_score:
		high_score = candidate_score
		changed = true
	if candidate_combo > best_combo:
		best_combo = candidate_combo
		changed = true
	if changed:
		save_data()
	return changed


func update_settings(p_sfx: bool, p_bgm: bool, p_vibration: bool, p_notifications: Variant = null) -> bool:
	var next_notif := notifications_enabled if p_notifications == null else bool(p_notifications)
	var changed := (
		(sfx_enabled != p_sfx)
		or (bgm_enabled != p_bgm)
		or (vibration_enabled != p_vibration)
		or (notifications_enabled != next_notif)
	)
	sfx_enabled = p_sfx
	bgm_enabled = p_bgm
	vibration_enabled = p_vibration
	notifications_enabled = next_notif
	if changed:
		save_data()
	return changed


func sync_daily_date(today_key: String) -> void:
	if today_key.is_empty():
		return
	var changed := false
	if daily_date != today_key:
		daily_date = today_key
		daily_attempts_used = 0
		daily_best_score = 0
		daily_best_combo = 0
		changed = true

	# Expire streak only if last completed date is older than yesterday.
	if not daily_last_completed_date.is_empty() and daily_last_completed_date != today_key:
		var yesterday := DailyChallenge.get_previous_date_key(today_key)
		if daily_last_completed_date != yesterday and daily_streak > 0:
			daily_streak = 0
			changed = true

	if changed:
		save_data()


func get_daily_attempts_left(today_key: String) -> int:
	if daily_date != today_key:
		return DailyChallenge.MAX_DAILY_ATTEMPTS
	return maxi(0, DailyChallenge.MAX_DAILY_ATTEMPTS - daily_attempts_used)


func consume_daily_attempt(today_key: String) -> int:
	sync_daily_date(today_key)
	daily_attempts_used = mini(DailyChallenge.MAX_DAILY_ATTEMPTS, daily_attempts_used + 1)
	save_data()
	return daily_attempts_used


func record_daily_score(today_key: String, candidate_score: int, candidate_combo: int, is_run_finished: bool) -> bool:
	sync_daily_date(today_key)
	var changed := false
	if candidate_score > daily_best_score:
		daily_best_score = candidate_score
		changed = true
	if candidate_combo > daily_best_combo:
		daily_best_combo = candidate_combo
		changed = true

	if is_run_finished and daily_last_completed_date != today_key:
		var yesterday := DailyChallenge.get_previous_date_key(today_key)
		if daily_last_completed_date == yesterday:
			daily_streak += 1
		else:
			daily_streak = 1
		daily_last_completed_date = today_key
		changed = true

	if changed:
		save_data()
	return changed


func update_sprint_records(candidate_score: int, candidate_combo: int) -> bool:
	var changed := false
	if candidate_score > sprint_high_score:
		sprint_high_score = candidate_score
		changed = true
	if candidate_combo > sprint_best_combo:
		sprint_best_combo = candidate_combo
		changed = true
	if changed:
		save_data()
	return changed


func update_gem_hunt_records(candidate_score: int, candidate_stage: int, candidate_combo: int) -> bool:
	var changed := false
	if candidate_score > gem_hunt_high_score:
		gem_hunt_high_score = candidate_score
		changed = true
	if candidate_stage > gem_hunt_best_stage:
		gem_hunt_best_stage = candidate_stage
		changed = true
	if candidate_combo > gem_hunt_best_combo:
		gem_hunt_best_combo = candidate_combo
		changed = true
	if changed:
		save_data()
	return changed


func add_coins(amount: int) -> int:
	var delta := maxi(0, amount)
	if delta > 0:
		coins += delta
		save_data()
	return coins


func spend_coins(amount: int) -> bool:
	var cost := maxi(0, amount)
	if cost == 0:
		return true
	if coins < cost:
		return false
	coins -= cost
	save_data()
	return true


func is_skin_unlocked(skin_id: String) -> bool:
	return skin_id == "jewel" or unlocked_skins.has(skin_id)


func unlock_skin(skin_id: String, cost: int) -> bool:
	if skin_id.is_empty():
		return false
	if is_skin_unlocked(skin_id):
		return true
	var price := maxi(0, cost)
	if coins < price:
		return false
	coins -= price
	unlocked_skins.append(skin_id)
	equipped_skin = skin_id
	save_data()
	return true


func equip_skin(skin_id: String) -> bool:
	if not is_skin_unlocked(skin_id):
		return false
	if equipped_skin != skin_id:
		equipped_skin = skin_id
		save_data()
	return true


func is_background_unlocked(bg_id: String) -> bool:
	return bg_id == "swirl" or unlocked_backgrounds.has(bg_id)


func unlock_background(bg_id: String, cost: int) -> bool:
	if bg_id.is_empty():
		return false
	if is_background_unlocked(bg_id):
		return true
	var price := maxi(0, cost)
	if coins < price:
		return false
	coins -= price
	unlocked_backgrounds.append(bg_id)
	equipped_background = bg_id
	save_data()
	return true


func equip_background(bg_id: String) -> bool:
	if not is_background_unlocked(bg_id):
		return false
	if equipped_background != bg_id:
		equipped_background = bg_id
		save_data()
	return true


func get_skill_stock(skill_id: String) -> int:
	if skill_id == "reroll":
		return skill_reroll_stock
	if skill_id == "bomb":
		return skill_bomb_stock
	if skill_id == "lightning":
		return skill_lightning_stock
	return 0


func add_skill_stock(skill_id: String, amount: int = 1) -> int:
	var delta := maxi(0, amount)
	if delta <= 0:
		return get_skill_stock(skill_id)
	if skill_id == "reroll":
		skill_reroll_stock += delta
	elif skill_id == "bomb":
		skill_bomb_stock += delta
	elif skill_id == "lightning":
		skill_lightning_stock += delta
	else:
		return 0
	save_data()
	return get_skill_stock(skill_id)


func consume_skill_stock(skill_id: String) -> bool:
	if skill_id == "reroll" and skill_reroll_stock > 0:
		skill_reroll_stock -= 1
		save_data()
		return true
	if skill_id == "bomb" and skill_bomb_stock > 0:
		skill_bomb_stock -= 1
		save_data()
		return true
	if skill_id == "lightning" and skill_lightning_stock > 0:
		skill_lightning_stock -= 1
		save_data()
		return true
	return false


func has_cleared_gem_stage_before(stage_num: int) -> bool:
	return gem_hunt_cleared_stages.has(stage_num)


func mark_gem_stage_cleared(stage_num: int) -> bool:
	if stage_num < 1:
		return false
	if gem_hunt_cleared_stages.has(stage_num):
		return false
	gem_hunt_cleared_stages.append(stage_num)
	save_data()
	return true


func can_claim_daily_skill_reward(date_key: String) -> bool:
	return (not date_key.is_empty()) and (daily_reward_claimed_date != date_key)


func mark_daily_skill_reward_claimed(date_key: String) -> void:
	if date_key.is_empty():
		return
	daily_reward_claimed_date = date_key
	save_data()


func reset_save() -> void:
	high_score = 0
	best_combo = 0
	save_data()


func delete_save_file() -> void:
	high_score = 0
	best_combo = 0
	sfx_enabled = true
	bgm_enabled = true
	vibration_enabled = true
	notifications_enabled = true
	daily_date = ""
	daily_attempts_used = 0
	daily_best_score = 0
	daily_best_combo = 0
	daily_streak = 0
	daily_last_completed_date = ""
	sprint_high_score = 0
	sprint_best_combo = 0
	gem_hunt_high_score = 0
	gem_hunt_best_stage = 1
	gem_hunt_best_combo = 0
	coins = 0
	unlocked_skins = ["jewel"]
	equipped_skin = "jewel"
	unlocked_backgrounds = ["swirl"]
	equipped_background = "swirl"
	skill_reroll_stock = 0
	skill_bomb_stock = 0
	skill_lightning_stock = 0
	gem_hunt_cleared_stages = []
	daily_reward_claimed_date = ""
	save_count = 0
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


static func _parse_non_negative_int(val: Variant) -> int:
	if val is int:
		return maxi(0, int(val))
	if val is float and is_finite(float(val)):
		return int(clampf(float(val), 0.0, 9e15))
	return 0


static func _parse_bool(val: Variant, fallback: bool) -> bool:
	if val is bool:
		return bool(val)
	return fallback


static func _parse_string(val: Variant) -> String:
	if val is String:
		return String(val)
	return ""


func _to_dict() -> Dictionary:
	return {
		"high_score": high_score,
		"best_combo": best_combo,
		"sfx_enabled": sfx_enabled,
		"bgm_enabled": bgm_enabled,
		"vibration_enabled": vibration_enabled,
		"notifications_enabled": notifications_enabled,
		"daily_date": daily_date,
		"daily_attempts_used": daily_attempts_used,
		"daily_best_score": daily_best_score,
		"daily_best_combo": daily_best_combo,
		"daily_streak": daily_streak,
		"daily_last_completed_date": daily_last_completed_date,
		"sprint_high_score": sprint_high_score,
		"sprint_best_combo": sprint_best_combo,
		"gem_hunt_high_score": gem_hunt_high_score,
		"gem_hunt_best_stage": gem_hunt_best_stage,
		"gem_hunt_best_combo": gem_hunt_best_combo,
		"coins": coins,
		"unlocked_skins": unlocked_skins,
		"equipped_skin": equipped_skin,
		"unlocked_backgrounds": unlocked_backgrounds,
		"equipped_background": equipped_background,
		"skill_reroll_stock": skill_reroll_stock,
		"skill_bomb_stock": skill_bomb_stock,
		"skill_lightning_stock": skill_lightning_stock,
		"gem_hunt_cleared_stages": gem_hunt_cleared_stages,
		"daily_reward_claimed_date": daily_reward_claimed_date,
	}
