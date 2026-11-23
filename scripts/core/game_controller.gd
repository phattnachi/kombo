class_name GameController
extends RefCounted

## Central state machine and rule orchestrator for Kombo.

signal state_changed()
signal move_resolved(result: Dictionary)
signal tray_refilled(tray: Array)
signal hold_changed(hold_piece: PieceCatalog.Piece)
signal game_over_triggered(final_score: int, high_score: int)

enum GameMode {
	CLASSIC = 0,
	DAILY = 1,
	SPRINT = 2,
	GEM_HUNT = 3,
}

const TRAY_SIZE := 3
const SAVE_MILESTONE_STEP := 2500
const SPRINT_TOTAL_TRAYS := 20
const SPRINT_TOTAL_MOVES := 60

const SKILL_REROLL_COST := 3000
const SKILL_BOMB_COST := 6000
const SKILL_LIGHTNING_COST := 12000

var board: BoardState
var score_engine: ScoreEngine
var save_manager: SaveManager
var rng: RandomNumberGenerator

var game_mode: int = GameMode.CLASSIC
var daily_date_key: String = ""
var daily_attempt_number: int = 0
var _daily_deal_rng: RandomNumberGenerator
var _daily_mult_rng: RandomNumberGenerator

var sprint_moves_limit: int = SPRINT_TOTAL_MOVES
var sprint_moves_left: int = 0
var sprint_completed: bool = false

var gem_hunt_stage: int = 1
var gem_hunt_targets_total: int = 0
var gem_hunt_targets_left: int = 0
var gem_hunt_stages_cleared: int = 0

var tray: Array[PieceCatalog.Piece] = []
var hold_piece: PieceCatalog.Piece = null
var hold_used_this_turn: bool = false
var pending_specials: Array[int] = []
var is_game_over: bool = false
var turn_count: int = 0
var has_used_revive: bool = false
var has_used_double_reward: bool = false
var last_run_base_coins: int = 0
var _coins_credited_this_run: int = 0

var _last_saved_high_score: int = 0
var _sim_board: BoardState = null
var _cached_shape_templates: Dictionary = {}


func _init(p_save_manager: SaveManager = null, seed_value: int = -1) -> void:
	board = BoardState.new()
	score_engine = ScoreEngine.new()
	save_manager = p_save_manager if p_save_manager != null else SaveManager.new()
	rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

	tray.resize(TRAY_SIZE)
	for i in range(TRAY_SIZE):
		tray[i] = null

	_last_saved_high_score = save_manager.high_score
	score_engine.reset(save_manager.high_score, save_manager.best_combo)


func start_new_game(seed_value: int = -1) -> void:
	# Flush any unsaved progress from a prior session before starting fresh.
	flush_save()

	game_mode = GameMode.CLASSIC
	daily_date_key = ""
	daily_attempt_number = 0
	sprint_moves_left = 0
	sprint_completed = false
	if seed_value >= 0:
		rng.seed = seed_value
	board.clear_board()
	board.spawn_initial_multipliers(rng)
	score_engine.reset(save_manager.high_score, save_manager.best_combo)
	_last_saved_high_score = save_manager.high_score

	for i in range(TRAY_SIZE):
		tray[i] = null
	hold_piece = null
	hold_used_this_turn = false
	pending_specials.clear()
	is_game_over = false
	turn_count = 0
	_reset_run_rewards_state()

	_deal_fresh_tray_internal(false)
	hold_changed.emit(hold_piece)
	tray_refilled.emit(get_tray_snapshot())
	state_changed.emit()


func _reset_run_rewards_state() -> void:
	has_used_revive = false
	has_used_double_reward = false
	last_run_base_coins = 0
	_coins_credited_this_run = 0


func start_daily_challenge(date_key: String = "", consume_attempt: bool = true) -> Dictionary:
	flush_save()

	var resolved_date := date_key if not date_key.is_empty() else DailyChallenge.get_today_date_key()
	save_manager.sync_daily_date(resolved_date)
	var attempts_left := save_manager.get_daily_attempts_left(resolved_date)
	if consume_attempt and attempts_left <= 0:
		return {
			"started": false,
			"reason": "no_attempts_left",
			"date_key": resolved_date,
			"attempts_left": 0,
			"daily_best_score": save_manager.daily_best_score,
			"daily_best_combo": save_manager.daily_best_combo,
			"daily_streak": save_manager.daily_streak,
		}

	game_mode = GameMode.DAILY
	daily_date_key = resolved_date
	sprint_moves_left = 0
	sprint_completed = false
	if consume_attempt:
		daily_attempt_number = save_manager.consume_daily_attempt(resolved_date)
	else:
		daily_attempt_number = maxi(1, save_manager.daily_attempts_used)

	_daily_deal_rng = RandomNumberGenerator.new()
	_daily_deal_rng.seed = DailyChallenge.compute_deal_seed(resolved_date)
	_daily_mult_rng = RandomNumberGenerator.new()
	_daily_mult_rng.seed = DailyChallenge.compute_mult_seed(resolved_date)

	DailyChallenge.populate_starter_board(board, resolved_date)
	score_engine.reset(save_manager.daily_best_score, save_manager.daily_best_combo)
	_last_saved_high_score = save_manager.daily_best_score

	for i in range(TRAY_SIZE):
		tray[i] = null
	hold_piece = null
	hold_used_this_turn = false
	pending_specials.clear()
	is_game_over = false
	turn_count = 0
	_reset_run_rewards_state()

	_deal_fresh_tray_internal(false)
	hold_changed.emit(hold_piece)
	tray_refilled.emit(get_tray_snapshot())
	state_changed.emit()

	return {
		"started": true,
		"date_key": resolved_date,
		"attempt_number": daily_attempt_number,
		"attempts_left": save_manager.get_daily_attempts_left(resolved_date),
		"daily_best_score": save_manager.daily_best_score,
		"daily_streak": save_manager.daily_streak,
	}


func start_sprint_game(seed_value: int = -1, moves_limit: int = SPRINT_TOTAL_MOVES) -> void:
	flush_save()

	game_mode = GameMode.SPRINT
	daily_date_key = ""
	daily_attempt_number = 0
	sprint_moves_limit = maxi(1, moves_limit)
	sprint_moves_left = sprint_moves_limit
	sprint_completed = false

	if seed_value >= 0:
		rng.seed = seed_value
	board.clear_board()
	board.spawn_initial_multipliers(rng)
	score_engine.reset(save_manager.sprint_high_score, save_manager.sprint_best_combo)
	_last_saved_high_score = save_manager.sprint_high_score

	for i in range(TRAY_SIZE):
		tray[i] = null
	hold_piece = null
	hold_used_this_turn = false
	pending_specials.clear()
	is_game_over = false
	turn_count = 0
	_reset_run_rewards_state()

	_deal_fresh_tray_internal(false)
	hold_changed.emit(hold_piece)
	tray_refilled.emit(get_tray_snapshot())
	state_changed.emit()


func start_gem_hunt_game(seed_value: int = -1, start_stage: int = 1) -> void:
	flush_save()

	game_mode = GameMode.GEM_HUNT
	daily_date_key = ""
	daily_attempt_number = 0
	sprint_moves_left = 0
	sprint_completed = false
	gem_hunt_stage = maxi(1, start_stage)
	gem_hunt_stages_cleared = 0

	if seed_value >= 0:
		rng.seed = seed_value
	gem_hunt_targets_total = GemHunt.populate_stage_board(board, gem_hunt_stage, rng)
	gem_hunt_targets_left = gem_hunt_targets_total

	score_engine.reset(save_manager.gem_hunt_high_score, save_manager.gem_hunt_best_combo)
	score_engine.stage_mult = GemHunt.get_stage_base_mult(gem_hunt_stage)
	_last_saved_high_score = save_manager.gem_hunt_high_score

	for i in range(TRAY_SIZE):
		tray[i] = null
	hold_piece = null
	hold_used_this_turn = false
	pending_specials.clear()
	is_game_over = false
	turn_count = 0
	_reset_run_rewards_state()

	_deal_fresh_tray_internal(false)
	hold_changed.emit(hold_piece)
	tray_refilled.emit(get_tray_snapshot())
	state_changed.emit()


func is_daily_mode() -> bool:
	return game_mode == GameMode.DAILY


func is_sprint_mode() -> bool:
	return game_mode == GameMode.SPRINT


func is_gem_hunt_mode() -> bool:
	return game_mode == GameMode.GEM_HUNT


func should_persist_run() -> bool:
	if is_game_over:
		return false
	if game_mode == GameMode.DAILY:
		return not daily_date_key.is_empty()
	return turn_count > 0 or hold_piece != null


func export_run_state() -> Dictionary:
	var board_cells: Array = []
	for y in range(BoardState.GRID_SIZE):
		for x in range(BoardState.GRID_SIZE):
			var c := board.get_cell(x, y)
			if c.occupied or c.multiplier > 1 or c.target_type != BoardState.TargetType.NONE:
				board_cells.append([
					x,
					y,
					1 if c.occupied else 0,
					c.color_id,
					c.multiplier,
					c.target_type,
					c.target_hp,
				])

	var tray_data: Array = []
	for i in range(TRAY_SIZE):
		tray_data.append(_serialize_piece(tray[i]))

	var pending_copy: Array = []
	for sp in pending_specials:
		pending_copy.append(int(sp))

	return {
		"game_mode": game_mode,
		"is_game_over": is_game_over,
		"turn_count": turn_count,
		"hold_used_this_turn": hold_used_this_turn,
		"has_used_revive": has_used_revive,
		"coins_credited_this_run": _coins_credited_this_run,
		"board_cells": board_cells,
		"tray": tray_data,
		"hold_piece": _serialize_piece(hold_piece),
		"pending_specials": pending_copy,
		"rng_state": str(rng.state),
		"daily_date_key": daily_date_key,
		"daily_attempt_number": daily_attempt_number,
		"daily_deal_rng_state": str(_daily_deal_rng.state) if _daily_deal_rng != null else "",
		"daily_mult_rng_state": str(_daily_mult_rng.state) if _daily_mult_rng != null else "",
		"sprint_moves_limit": sprint_moves_limit,
		"sprint_moves_left": sprint_moves_left,
		"sprint_completed": sprint_completed,
		"gem_hunt_stage": gem_hunt_stage,
		"gem_hunt_targets_total": gem_hunt_targets_total,
		"gem_hunt_targets_left": gem_hunt_targets_left,
		"gem_hunt_stages_cleared": gem_hunt_stages_cleared,
		"score_state": {
			"score": score_engine.score,
			"high_score": score_engine.high_score,
			"session_starting_high_score": score_engine.session_starting_high_score,
			"has_beaten_session_high": score_engine._has_beaten_session_high,
			"combo_streak": score_engine.combo_streak,
			"combo_grace_left": score_engine.combo_grace_left,
			"best_combo": score_engine.best_combo,
			"fever_charge": score_engine.fever_charge,
			"fever_active": score_engine.fever_active,
			"fever_turns_left": score_engine.fever_turns_left,
			"stage_mult": score_engine.stage_mult,
			"all_clear_count": score_engine.all_clear_count,
		},
	}


func restore_run_state(data: Dictionary) -> bool:
	if data.is_empty() or bool(data.get("is_game_over", false)):
		return false

	var mode := int(data.get("game_mode", GameMode.CLASSIC))
	if mode < GameMode.CLASSIC or mode > GameMode.GEM_HUNT:
		return false

	# Validate tray array before mutating live controller state.
	var raw_tray: Variant = data.get("tray", [])
	if typeof(raw_tray) != TYPE_ARRAY or (raw_tray as Array).size() != TRAY_SIZE:
		return false

	board.clear_board()
	var raw_cells: Variant = data.get("board_cells", [])
	if typeof(raw_cells) == TYPE_ARRAY:
		for item in (raw_cells as Array):
			if typeof(item) == TYPE_ARRAY and (item as Array).size() >= 7:
				var arr: Array = item
				var x := int(arr[0])
				var y := int(arr[1])
				if board.in_bounds_xy(x, y):
					var cell := board.get_cell(x, y)
					cell.occupied = int(arr[2]) != 0
					cell.color_id = int(arr[3]) if cell.occupied else -1
					cell.multiplier = maxi(1, int(arr[4]))
					cell.target_type = int(arr[5])
					cell.target_hp = maxi(0, int(arr[6]))

	var has_any_piece := false
	for i in range(TRAY_SIZE):
		tray[i] = _deserialize_piece((raw_tray as Array)[i])
		if tray[i] != null:
			has_any_piece = true

	hold_piece = _deserialize_piece(data.get("hold_piece", null))
	if hold_piece != null:
		has_any_piece = true
	if not has_any_piece:
		return false

	pending_specials.clear()
	var raw_pending: Variant = data.get("pending_specials", [])
	if typeof(raw_pending) == TYPE_ARRAY:
		for sp in (raw_pending as Array):
			pending_specials.append(int(sp))

	game_mode = mode
	turn_count = maxi(0, int(data.get("turn_count", 0)))
	hold_used_this_turn = bool(data.get("hold_used_this_turn", false))
	has_used_revive = bool(data.get("has_used_revive", false))
	has_used_double_reward = false
	last_run_base_coins = 0
	_coins_credited_this_run = maxi(0, int(data.get("coins_credited_this_run", 0)))
	is_game_over = false

	var rng_s := String(data.get("rng_state", ""))
	if not rng_s.is_empty() and rng_s.is_valid_int():
		rng.state = rng_s.to_int()

	daily_date_key = String(data.get("daily_date_key", ""))
	daily_attempt_number = maxi(0, int(data.get("daily_attempt_number", 0)))
	if game_mode == GameMode.DAILY and not daily_date_key.is_empty():
		_daily_deal_rng = RandomNumberGenerator.new()
		_daily_deal_rng.seed = DailyChallenge.compute_deal_seed(daily_date_key)
		var deal_s := String(data.get("daily_deal_rng_state", ""))
		if not deal_s.is_empty() and deal_s.is_valid_int():
			_daily_deal_rng.state = deal_s.to_int()

		_daily_mult_rng = RandomNumberGenerator.new()
		_daily_mult_rng.seed = DailyChallenge.compute_mult_seed(daily_date_key)
		var mult_s := String(data.get("daily_mult_rng_state", ""))
		if not mult_s.is_empty() and mult_s.is_valid_int():
			_daily_mult_rng.state = mult_s.to_int()
	else:
		_daily_deal_rng = null
		_daily_mult_rng = null

	sprint_moves_limit = maxi(1, int(data.get("sprint_moves_limit", SPRINT_TOTAL_MOVES)))
	sprint_moves_left = clampi(int(data.get("sprint_moves_left", sprint_moves_limit)), 0, sprint_moves_limit)
	sprint_completed = bool(data.get("sprint_completed", false))

	gem_hunt_stage = maxi(1, int(data.get("gem_hunt_stage", 1)))
	gem_hunt_targets_total = maxi(1, int(data.get("gem_hunt_targets_total", board.count_remaining_targets())))
	gem_hunt_targets_left = board.count_remaining_targets() if game_mode == GameMode.GEM_HUNT else 0
	gem_hunt_stages_cleared = maxi(0, int(data.get("gem_hunt_stages_cleared", 0)))

	var sd: Variant = data.get("score_state", {})
	var sdict: Dictionary = sd if typeof(sd) == TYPE_DICTIONARY else {}
	var mode_saved_hi := save_manager.high_score
	if game_mode == GameMode.DAILY:
		mode_saved_hi = save_manager.daily_best_score
	elif game_mode == GameMode.SPRINT:
		mode_saved_hi = save_manager.sprint_high_score
	elif game_mode == GameMode.GEM_HUNT:
		mode_saved_hi = save_manager.gem_hunt_high_score

	score_engine.score = maxi(0, int(sdict.get("score", 0)))
	score_engine.high_score = maxi(mode_saved_hi, maxi(score_engine.score, int(sdict.get("high_score", 0))))
	score_engine.session_starting_high_score = maxi(0, int(sdict.get("session_starting_high_score", mode_saved_hi)))
	score_engine._has_beaten_session_high = bool(sdict.get("has_beaten_session_high", false))
	score_engine.combo_streak = maxi(0, int(sdict.get("combo_streak", 0)))
	score_engine.combo_grace_left = maxi(0, int(sdict.get("combo_grace_left", 0)))
	score_engine.best_combo = maxi(0, int(sdict.get("best_combo", 0)))
	score_engine.fever_charge = clampf(float(sdict.get("fever_charge", 0.0)), 0.0, 1.0)
	score_engine.fever_active = bool(sdict.get("fever_active", false))
	score_engine.fever_turns_left = maxi(0, int(sdict.get("fever_turns_left", 0)))
	score_engine.stage_mult = maxf(1.0, float(sdict.get("stage_mult", 1.0)))
	score_engine.all_clear_count = maxi(0, int(sdict.get("all_clear_count", 0)))
	_last_saved_high_score = score_engine.high_score

	is_game_over = not can_continue()
	if game_mode == GameMode.SPRINT and sprint_moves_left <= 0:
		is_game_over = true
	if is_game_over:
		return false

	hold_changed.emit(hold_piece)
	tray_refilled.emit(get_tray_snapshot())
	state_changed.emit()
	return true


static func _serialize_piece(p: PieceCatalog.Piece) -> Variant:
	if p == null:
		return null
	return {
		"id": p.id,
		"color_id": p.color_id,
		"special_type": p.special_type,
	}


static func _deserialize_piece(raw: Variant) -> PieceCatalog.Piece:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	var sp := int(d.get("special_type", PieceCatalog.SPECIAL_NORMAL))
	if sp != PieceCatalog.SPECIAL_NORMAL:
		return PieceCatalog.create_special_piece(sp)
	var pid := String(d.get("id", ""))
	if pid.is_empty():
		return null
	var col := clampi(int(d.get("color_id", 0)), 0, PieceCatalog.COLOR_COUNT - 1)
	return PieceCatalog.create_piece_by_id(pid, col)


func get_tray_snapshot() -> Array:
	return tray.duplicate()


# ==============================================================================
# DECOUPLED REWARD MECHANICS (REVIVE & DOUBLE END-OF-RUN COINS)
# Pure gameplay mutations — completely independent of any Ad SDK!
# ==============================================================================

func can_revive() -> bool:
	if has_used_revive or not is_game_over:
		return false
	if game_mode == GameMode.SPRINT and sprint_completed:
		return false
	return true


## Grants a 1-time-per-run Second Chance rescue:
## - Clears non-target blocks in the center 4x4 rescue zone (expanding to 6x6 / full
##   only if needed so >=10 cells are guaranteed open without destroying Gem targets).
## - Preserves x2/x3 multiplier tiles, HOLD piece, Score, Combo Streak, and FEVER gauge!
## - Deals a fresh smart-guaranteed 3-piece tray so Game Over cannot loop immediately.
func apply_revive() -> Dictionary:
	if not can_revive():
		return {"revived": false}

	var cleared_cells: Array[Vector2i] = []
	var cleared_colors: Dictionary = {}

	# Pass 1: Clear non-target blocks in center 4x4 (2..5, 2..5).
	_revive_clear_zone(2, 5, cleared_cells, cleared_colors)
	# Pass 2 (safety): If center was mostly empty or Gem targets, expand to center 6x6.
	if board.get_empty_cells().size() < 10:
		_revive_clear_zone(1, 6, cleared_cells, cleared_colors)
	# Pass 3 (extreme fallback): Clear remaining non-target blocks anywhere on 8x8.
	if board.get_empty_cells().size() < 6:
		_revive_clear_zone(0, BoardState.GRID_SIZE - 1, cleared_cells, cleared_colors)

	has_used_revive = true
	is_game_over = false
	hold_used_this_turn = false

	# Clear old stuck tray and deal a fresh guaranteed-playable 3-piece set.
	for i in range(TRAY_SIZE):
		tray[i] = null
	_deal_fresh_tray_internal(false)

	# Hard anti-loop guard: guarantee at least one legal placement exists.
	if not can_continue() and not board.get_empty_cells().is_empty():
		tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", rng.randi_range(0, PieceCatalog.COLOR_COUNT - 1))

	tray_refilled.emit(get_tray_snapshot())
	state_changed.emit()

	return {
		"revived": true,
		"cleared_cells": cleared_cells,
		"cleared_cell_colors": cleared_colors,
		"tray": get_tray_snapshot(),
		"can_continue": can_continue(),
	}


func _revive_clear_zone(
	min_xy: int,
	max_xy: int,
	cleared_cells: Array[Vector2i],
	cleared_colors: Dictionary
) -> void:
	for y in range(min_xy, max_xy + 1):
		for x in range(min_xy, max_xy + 1):
			var cell := board.get_cell(x, y)
			if cell.occupied and cell.target_type == BoardState.TargetType.NONE:
				var pos := Vector2i(x, y)
				cleared_cells.append(pos)
				cleared_colors[pos] = cell.color_id
				# Preserve cell.multiplier (x2/x3 tiles stay alive on the board!).
				cell.occupied = false
				cell.color_id = -1


static func compute_run_coins(final_score: int, best_combo: int) -> int:
	return maxi(10, int(maxi(0, final_score) / 150) + maxi(0, best_combo) * 5)


## Credits earned run coins safely (only uncredited delta, preventing duplicate credit across Revive).
func credit_end_of_run_coins() -> Dictionary:
	var earned := compute_run_coins(score_engine.score, score_engine.best_combo)
	last_run_base_coins = earned
	var delta := maxi(0, earned - _coins_credited_this_run)
	if delta > 0 and save_manager != null:
		save_manager.add_coins(delta)
		_coins_credited_this_run += delta
	var wallet := save_manager.coins if save_manager != null else _coins_credited_this_run
	return {
		"base_coins": last_run_base_coins,
		"delta_credited": delta,
		"wallet_coins": wallet,
		"already_doubled": has_used_double_reward,
	}


func can_double_reward() -> bool:
	return is_game_over and not has_used_double_reward and last_run_base_coins > 0


## Grants the 2x end-of-run coin bonus once per finished run.
func apply_double_reward() -> Dictionary:
	if not can_double_reward():
		return {"granted": false}
	has_used_double_reward = true
	var bonus := last_run_base_coins
	if save_manager != null:
		save_manager.add_coins(bonus)
	_coins_credited_this_run += bonus
	var wallet := save_manager.coins if save_manager != null else _coins_credited_this_run
	return {
		"granted": true,
		"bonus_coins": bonus,
		"total_run_coins": last_run_base_coins * 2,
		"wallet_coins": wallet,
	}


func flush_save() -> bool:
	if game_mode == GameMode.DAILY and not daily_date_key.is_empty():
		var saved_daily := save_manager.record_daily_score(
			daily_date_key,
			score_engine.score,
			score_engine.best_combo,
			is_game_over
		)
		_last_saved_high_score = save_manager.daily_best_score
		return saved_daily
	if game_mode == GameMode.SPRINT:
		var saved_sprint := save_manager.update_sprint_records(
			score_engine.score,
			score_engine.best_combo
		)
		_last_saved_high_score = save_manager.sprint_high_score
		return saved_sprint
	if game_mode == GameMode.GEM_HUNT:
		var saved_gem := save_manager.update_gem_hunt_records(
			score_engine.score,
			gem_hunt_stage,
			score_engine.best_combo
		)
		_last_saved_high_score = save_manager.gem_hunt_high_score
		return saved_gem
	var saved := save_manager.update_records(score_engine.score, score_engine.best_combo)
	_last_saved_high_score = save_manager.high_score
	return saved


func get_tray_piece(slot_idx: int) -> PieceCatalog.Piece:
	if slot_idx < 0 or slot_idx >= TRAY_SIZE:
		return null
	return tray[slot_idx]


func is_tray_piece_playable(slot_idx: int) -> bool:
	var piece := get_tray_piece(slot_idx)
	if piece == null:
		return false
	return board.can_piece_fit_anywhere(piece)


func is_hold_piece_playable() -> bool:
	if hold_piece == null:
		return false
	return board.can_piece_fit_anywhere(hold_piece)


func can_place_from_tray(slot_idx: int, origin: Vector2i) -> bool:
	if is_game_over:
		return false
	var piece := get_tray_piece(slot_idx)
	if piece == null:
		return false
	return board.can_place_piece(piece, origin)


func can_place_from_hold(origin: Vector2i) -> bool:
	if is_game_over or hold_piece == null:
		return false
	return board.can_place_piece(hold_piece, origin)


func preview_from_tray(slot_idx: int, origin: Vector2i) -> Dictionary:
	var piece := get_tray_piece(slot_idx)
	if piece == null or is_game_over:
		return BoardState.empty_preview()
	return board.preview_placement(piece, origin)


func preview_from_hold(origin: Vector2i) -> Dictionary:
	if hold_piece == null or is_game_over:
		return BoardState.empty_preview()
	return board.preview_placement(hold_piece, origin)


func place_from_tray(slot_idx: int, origin: Vector2i) -> Dictionary:
	if not can_place_from_tray(slot_idx, origin):
		return {"valid": false}
	var piece := tray[slot_idx]
	return _resolve_placement(piece, origin, slot_idx)


func place_from_hold(origin: Vector2i) -> Dictionary:
	if not can_place_from_hold(origin):
		return {"valid": false}
	var piece := hold_piece
	return _resolve_placement(piece, origin, -1)


func can_hold_from_tray(slot_idx: int) -> bool:
	if is_game_over:
		return false
	if hold_used_this_turn:
		return false
	if slot_idx < 0 or slot_idx >= TRAY_SIZE:
		return false
	return tray[slot_idx] != null


func hold_from_tray(slot_idx: int) -> Dictionary:
	if is_game_over:
		return {"success": false, "reason": "game_over"}
	if slot_idx < 0 or slot_idx >= TRAY_SIZE:
		return {"success": false, "reason": "invalid_slot"}
	if tray[slot_idx] == null:
		return {"success": false, "reason": "empty_slot"}
	if hold_used_this_turn:
		return {"success": false, "reason": "already_used_this_turn"}

	var was_swap := hold_piece != null
	var refilled := false

	if not was_swap:
		hold_piece = tray[slot_idx]
		tray[slot_idx] = null
		hold_used_this_turn = true
		if _is_tray_empty():
			_deal_fresh_tray_internal(false)
			refilled = true
	else:
		var prev_hold := hold_piece
		hold_piece = tray[slot_idx]
		tray[slot_idx] = prev_hold
		hold_used_this_turn = true

	is_game_over = not can_continue()
	if is_game_over:
		flush_save()

	hold_changed.emit(hold_piece)
	if refilled:
		tray_refilled.emit(tray.duplicate())
	if is_game_over:
		game_over_triggered.emit(score_engine.score, score_engine.high_score)
	state_changed.emit()

	return {
		"success": true,
		"swapped": was_swap,
		"tray_refilled": refilled,
		"game_over": is_game_over,
	}


func can_continue() -> bool:
	for piece in tray:
		if piece != null and board.can_piece_fit_anywhere(piece):
			return true

	if hold_piece != null and board.can_piece_fit_anywhere(hold_piece):
		return true

	# Hold Rescue: if Hold is empty, not yet used this turn, and only 1 tray piece remains,
	# holding that final tray piece will trigger a fresh smart-dealt tray of 3 pieces.
	if (
		hold_piece == null
		and not hold_used_this_turn
		and _remaining_tray_count() == 1
		and not board.get_empty_cells().is_empty()
	):
		return true

	return false


func recheck_game_over() -> bool:
	is_game_over = not can_continue()
	return is_game_over


func deal_fresh_tray() -> Array[PieceCatalog.Piece]:
	return _deal_fresh_tray_internal(true)


func buy_skill(skill_id: String) -> Dictionary:
	if is_game_over:
		return {"success": false, "reason": "game_over"}
	if save_manager == null:
		return {"success": false, "reason": "no_wallet"}

	if skill_id == "reroll":
		if save_manager.coins < SKILL_REROLL_COST:
			return {"success": false, "reason": "insufficient_coins", "cost": SKILL_REROLL_COST}
		var replaceable_slots: Array[int] = []
		for i in range(TRAY_SIZE):
			if tray[i] == null or not tray[i].is_special():
				replaceable_slots.append(i)
		if replaceable_slots.is_empty():
			return {"success": false, "reason": "no_slot"}
		if not save_manager.spend_coins(SKILL_REROLL_COST):
			return {"success": false, "reason": "insufficient_coins", "cost": SKILL_REROLL_COST}
		var used_ids: Array[String] = []
		for idx in replaceable_slots:
			var np := PieceCatalog.create_random_piece(rng, used_ids)
			tray[idx] = np
			used_ids.append(np.id)
		_apply_smart_deal_guarantee()
		tray_refilled.emit(get_tray_snapshot())
		state_changed.emit()
		return {
			"success": true,
			"skill_id": "reroll",
			"cost": SKILL_REROLL_COST,
			"slot": -2,
			"remaining_coins": save_manager.coins,
		}

	if skill_id == "bomb" or skill_id == "lightning":
		var sp_type := PieceCatalog.SPECIAL_BOMB if skill_id == "bomb" else PieceCatalog.SPECIAL_LIGHTNING
		var cost := SKILL_BOMB_COST if skill_id == "bomb" else SKILL_LIGHTNING_COST
		if save_manager.coins < cost:
			return {"success": false, "reason": "insufficient_coins", "cost": cost}

		# Smart placement priority: 1) empty tray slot, 2) empty Hold, 3) largest non-special tray slot, 4) upgrade Bomb->Lightning.
		var target_slot := -2 # -2 = none, -1 = hold, 0..2 = tray
		for i in range(TRAY_SIZE):
			if tray[i] == null:
				target_slot = i
				break
		if target_slot == -2 and hold_piece == null:
			target_slot = -1
		if target_slot == -2:
			var best_cells := -1
			for i in range(TRAY_SIZE):
				if tray[i] != null and not tray[i].is_special() and tray[i].cells.size() > best_cells:
					best_cells = tray[i].cells.size()
					target_slot = i
		if target_slot == -2 and sp_type == PieceCatalog.SPECIAL_LIGHTNING:
			for i in range(TRAY_SIZE):
				if tray[i] != null and tray[i].special_type == PieceCatalog.SPECIAL_BOMB:
					target_slot = i
					break
		if target_slot == -2:
			return {"success": false, "reason": "no_slot"}

		if not save_manager.spend_coins(cost):
			return {"success": false, "reason": "insufficient_coins", "cost": cost}

		var sp_piece := PieceCatalog.create_special_piece(sp_type)
		if target_slot == -1:
			hold_piece = sp_piece
			hold_changed.emit(hold_piece)
		else:
			tray[target_slot] = sp_piece
		state_changed.emit()
		return {
			"success": true,
			"skill_id": skill_id,
			"cost": cost,
			"slot": target_slot,
			"remaining_coins": save_manager.coins,
		}

	return {"success": false, "reason": "unknown_skill"}


func _deal_fresh_tray_internal(emit_signal: bool) -> Array[PieceCatalog.Piece]:
	if game_mode == GameMode.DAILY and _daily_deal_rng != null:
		var dealt := DailyChallenge.deal_deterministic_tray(_daily_deal_rng, pending_specials)
		for i in range(TRAY_SIZE):
			tray[i] = dealt[i]
		if emit_signal:
			tray_refilled.emit(tray.duplicate())
		return tray

	var used_ids: Array[String] = []
	for i in range(TRAY_SIZE):
		if not pending_specials.is_empty():
			var sp_type: int = pending_specials.pop_front()
			tray[i] = PieceCatalog.create_special_piece(sp_type)
		else:
			var piece := PieceCatalog.create_random_piece(rng, used_ids)
			tray[i] = piece
			used_ids.append(piece.id)

	_apply_smart_deal_guarantee()
	if emit_signal:
		tray_refilled.emit(tray.duplicate())
	return tray


func _resolve_placement(
	piece: PieceCatalog.Piece,
	origin: Vector2i,
	source_slot: int
) -> Dictionary:
	# Validate & resolve board placement FIRST before mutating controller state.
	var board_res := board.place_and_resolve(piece, origin)
	if not bool(board_res.get("valid", false)):
		return {"valid": false}

	var placed_from_hold := (source_slot == -1)
	if placed_from_hold:
		hold_piece = null
	elif source_slot >= 0 and source_slot < TRAY_SIZE:
		tray[source_slot] = null

	hold_used_this_turn = false
	turn_count += 1

	var placed_cells: Array[Vector2i] = board_res["placed_cells"]
	var cleared_rows: Array[int] = board_res["cleared_rows"]
	var cleared_cols: Array[int] = board_res["cleared_cols"]
	var blast_cells: Array[Vector2i] = board_res["blast_cells"]
	var blast_zone_cells: Array[Vector2i] = board_res["blast_zone_cells"]
	var cleared_cells: Array[Vector2i] = board_res["cleared_cells"]
	var cleared_cell_colors: Dictionary = board_res["cleared_cell_colors"]
	var hit_multipliers: Array[Dictionary] = board_res["hit_multipliers"]
	var destroyed_targets: Array[Dictionary] = board_res.get("destroyed_targets", []) as Array[Dictionary]
	var cracked_targets: Array[Vector2i] = board_res.get("cracked_targets", []) as Array[Vector2i]
	var lines_cleared: int = int(board_res["lines_cleared"])
	var special_triggered: int = int(board_res["special_triggered"])

	var score_res := score_engine.evaluate_move(
		placed_cells.size(),
		lines_cleared,
		blast_cells.size(),
		hit_multipliers,
		special_triggered != PieceCatalog.SPECIAL_NORMAL
	)

	# Bonus points for shattering Cursed Padlock targets in Gem Hunt.
	var padlock_bonus := 0
	for dt in destroyed_targets:
		if int(dt.get("type", 0)) == BoardState.TargetType.PADLOCK:
			padlock_bonus += GemHunt.PADLOCK_SHATTER_BONUS
	if padlock_bonus > 0:
		var p_add := score_engine.add_bonus_points(padlock_bonus)
		score_res["points_earned"] = int(score_res["points_earned"]) + padlock_bonus
		score_res["new_score"] = int(p_add["new_score"])
		score_res["high_score"] = int(p_add["high_score"])
		score_res["is_new_high_score"] = bool(p_add["is_new_high_score"])
		if bool(p_add["just_beat_high_score"]):
			score_res["just_beat_high_score"] = true

	# Replenish board multiplier tiles up to MAX_ACTIVE_MULTIPLIERS after real clears.
	var avoid_mult_cells: Array[Vector2i] = []
	for m in hit_multipliers:
		avoid_mult_cells.append(m["cell"] as Vector2i)
	var spawned_multipliers: Array[Dictionary] = []
	var did_real_clear := lines_cleared > 0 or not blast_cells.is_empty()

	# PERFECT CLEAR (ALL CLEAR): clearing every remaining block off the 8x8 board!
	# Each subsequent ALL CLEAR in the same run multiplies both the score & coin jackpot (x1, x2, x3, x4...)!
	var all_clear := did_real_clear and board.get_occupied_count() == 0
	var all_clear_count := score_engine.all_clear_count
	var all_clear_bonus := 0
	var all_clear_coins := 0
	if all_clear:
		score_engine.all_clear_count += 1
		all_clear_count = score_engine.all_clear_count
		var ac_mult := maxf(1.0, float(score_res["total_mult"])) * float(all_clear_count)
		all_clear_bonus = int(round(float(ScoreEngine.ALL_CLEAR_BONUS_BASE) * ac_mult))
		var ac_add := score_engine.add_bonus_points(all_clear_bonus)
		score_res["points_earned"] = int(score_res["points_earned"]) + all_clear_bonus
		score_res["new_score"] = int(ac_add["new_score"])
		score_res["high_score"] = int(ac_add["high_score"])
		score_res["is_new_high_score"] = bool(ac_add["is_new_high_score"])
		if bool(ac_add["just_beat_high_score"]):
			score_res["just_beat_high_score"] = true
		all_clear_coins = ScoreEngine.ALL_CLEAR_BONUS_COINS * all_clear_count
		if save_manager != null:
			save_manager.add_coins(all_clear_coins)

	var active_mult_rng := _daily_mult_rng if (game_mode == GameMode.DAILY and _daily_mult_rng != null) else rng
	if did_real_clear:
		spawned_multipliers = board.replenish_multipliers(active_mult_rng, 2, avoid_mult_cells)
	elif turn_count % 4 == 0 and board.get_active_multiplier_cells().size() < BoardState.MAX_ACTIVE_MULTIPLIERS:
		spawned_multipliers = board.replenish_multipliers(active_mult_rng, 1, avoid_mult_cells)

	# Award Bomb (2 lines or 1st All Clear) or Lightning (3+ lines or 2nd+ All Clear chain)!
	var awarded_special := PieceCatalog.SPECIAL_NORMAL
	var awarded_slot := -1
	if lines_cleared >= 3 or (all_clear and all_clear_count >= 2):
		awarded_special = PieceCatalog.SPECIAL_LIGHTNING
	elif lines_cleared == 2 or all_clear:
		awarded_special = PieceCatalog.SPECIAL_BOMB

	if awarded_special != PieceCatalog.SPECIAL_NORMAL:
		var special_piece := PieceCatalog.create_special_piece(awarded_special)
		if source_slot >= 0 and source_slot < TRAY_SIZE and tray[source_slot] == null:
			tray[source_slot] = special_piece
			awarded_slot = source_slot
		else:
			var empty_slot := _find_first_empty_tray_slot()
			if empty_slot >= 0:
				tray[empty_slot] = special_piece
				awarded_slot = empty_slot
			else:
				pending_specials.append(awarded_special)
				awarded_slot = -1

	# Sprint move quota countdown (60 placements = 20 sets of 3 blocks).
	if game_mode == GameMode.SPRINT:
		sprint_moves_left = maxi(0, sprint_moves_left - 1)

	# Gem Hunt stage progression: when all targets on the board are cleared, celebrate & advance stage!
	var stage_cleared := false
	var cleared_stage_num := 0
	var stage_bonus := 0
	if game_mode == GameMode.GEM_HUNT:
		gem_hunt_targets_left = board.count_remaining_targets()
		if gem_hunt_targets_left <= 0:
			stage_cleared = true
			cleared_stage_num = gem_hunt_stage
			stage_bonus = GemHunt.get_stage_clear_bonus(cleared_stage_num)
			var s_add := score_engine.add_bonus_points(stage_bonus)
			score_res["points_earned"] = int(score_res["points_earned"]) + stage_bonus
			score_res["new_score"] = int(s_add["new_score"])
			score_res["high_score"] = int(s_add["high_score"])
			score_res["is_new_high_score"] = bool(s_add["is_new_high_score"])
			if bool(s_add["just_beat_high_score"]):
				score_res["just_beat_high_score"] = true

			gem_hunt_stages_cleared += 1
			gem_hunt_stage += 1
			gem_hunt_targets_total = GemHunt.populate_stage_board(board, gem_hunt_stage, rng)
			gem_hunt_targets_left = gem_hunt_targets_total
			score_engine.stage_mult = GemHunt.get_stage_base_mult(gem_hunt_stage)

	# Refill tray only when all 3 slots are empty (skip refill if Sprint quota hit 0).
	var did_refill := false
	if _is_tray_empty() and not (game_mode == GameMode.SPRINT and sprint_moves_left <= 0):
		_deal_fresh_tray_internal(false)
		did_refill = true
	elif stage_cleared:
		# Ensure remaining tray pieces can fit on the freshly populated next-stage board!
		_apply_smart_deal_guarantee()

	if game_mode == GameMode.SPRINT and sprint_moves_left <= 0:
		sprint_completed = true
		is_game_over = true
	else:
		is_game_over = not can_continue()

	# Throttled persistence: save on first PB beat, Stage Clear, All Clear, Game Over, or >=500-point milestones.
	var just_beat_high := bool(score_res["just_beat_high_score"])
	var reached_milestone := (score_engine.score - _last_saved_high_score) >= SAVE_MILESTONE_STEP
	if just_beat_high or stage_cleared or all_clear or is_game_over or reached_milestone:
		flush_save()

	var result := {
		"valid": true,
		"placed_cells": placed_cells,
		"cleared_rows": cleared_rows,
		"cleared_cols": cleared_cols,
		"blast_cells": blast_cells,
		"blast_zone_cells": blast_zone_cells,
		"cleared_cells": cleared_cells,
		"cleared_cell_colors": cleared_cell_colors,
		"special_triggered": special_triggered,
		"blast_origin": origin,
		"lines_cleared": lines_cleared,
		"all_clear": all_clear,
		"all_clear_count": all_clear_count,
		"all_clear_bonus": all_clear_bonus,
		"all_clear_coins": all_clear_coins,
		"base_chips": int(score_res["base_chips"]),
		"placement_chips": int(score_res["placement_chips"]),
		"line_chips": int(score_res["line_chips"]),
		"blast_chips": int(score_res["blast_chips"]),
		"combo_streak": int(score_res["combo_streak"]),
		"combo_grace_left": int(score_res["combo_grace_left"]),
		"combo_mult": float(score_res["combo_mult"]),
		"tile_mult": float(score_res["tile_mult"]),
		"hit_multipliers": hit_multipliers,
		"spawned_multipliers": spawned_multipliers,
		"fever_active": bool(score_res["fever_active"]),
		"fever_just_ignited": bool(score_res["fever_just_ignited"]),
		"fever_extinguished": bool(score_res["fever_extinguished"]),
		"fever_charge": float(score_res["fever_charge"]),
		"fever_turns_left": int(score_res["fever_turns_left"]),
		"fever_mult": float(score_res["fever_mult"]),
		"total_mult": float(score_res["total_mult"]),
		"points_earned": int(score_res["points_earned"]),
		"new_score": int(score_res["new_score"]),
		"high_score": int(score_res["high_score"]),
		"is_new_high_score": bool(score_res["is_new_high_score"]),
		"just_beat_high_score": just_beat_high,
		"awarded_special": awarded_special,
		"awarded_slot": awarded_slot,
		"tray_refilled": did_refill,
		"game_over": is_game_over,
		"sprint_moves_left": sprint_moves_left,
		"sprint_moves_limit": sprint_moves_limit,
		"sprint_completed": sprint_completed,
		"destroyed_targets": destroyed_targets,
		"cracked_targets": cracked_targets,
		"stage_cleared": stage_cleared,
		"cleared_stage": cleared_stage_num,
		"next_stage": gem_hunt_stage,
		"stage_bonus": stage_bonus,
		"stage_mult": score_engine.stage_mult,
		"gem_targets_left": gem_hunt_targets_left,
		"gem_targets_total": gem_hunt_targets_total,
	}

	# Deterministic signal ordering: hold_changed -> tray_refilled -> move_resolved -> game_over -> state_changed.
	if placed_from_hold:
		hold_changed.emit(hold_piece)
	if did_refill:
		tray_refilled.emit(tray.duplicate())
	move_resolved.emit(result)
	if is_game_over:
		game_over_triggered.emit(score_engine.score, score_engine.high_score)
	state_changed.emit()
	return result


func _apply_smart_deal_guarantee() -> void:
	if board.get_empty_cells().is_empty():
		return

	# Step 1: Ensure at least 1 dealt piece fits on the current board right now.
	var fitting_slots := _get_fitting_tray_slots(board)
	if fitting_slots.is_empty():
		var replaceable := _get_non_special_slots(-1)
		if replaceable.is_empty():
			replaceable = [0, 1, 2]
		var slot_a := replaceable[rng.randi_range(0, replaceable.size() - 1)]
		var piece_a := _pick_weighted_fitting_piece(board, _get_tray_shape_ids())
		if piece_a != null:
			tray[slot_a] = piece_a
		fitting_slots = _get_fitting_tray_slots(board)
		if fitting_slots.is_empty():
			return

	# Step 2: Solvency upgrade — verify at least 2 of the 3 pieces can be played sequentially
	# (or placing 1 fitting piece clears a line / blasts blocks to open fresh room).
	if _has_two_piece_solvency():
		return

	# Pick a fitting anchor piece, simulate its best placement, and replace a random other
	# non-special slot with a weighted shape that fits the post-placement board.
	var anchor_slot := fitting_slots[rng.randi_range(0, fitting_slots.size() - 1)]
	var anchor_piece := tray[anchor_slot]
	var anchor_placements := board.get_valid_placements(anchor_piece)
	if anchor_placements.is_empty():
		return

	if _sim_board == null:
		_sim_board = BoardState.new()
	_sim_board.copy_from(board)
	var chosen_origin := anchor_placements[rng.randi_range(0, anchor_placements.size() - 1)]
	# Prefer a line-clearing placement if one exists so post-placement board has maximum room.
	for orig in anchor_placements:
		var prev := board.preview_placement(anchor_piece, orig)
		if not (prev["cleared_rows"] as Array).is_empty() or not (prev["cleared_cols"] as Array).is_empty():
			chosen_origin = orig
			break
	_sim_board.place_and_resolve(anchor_piece, chosen_origin)
	if _sim_board.get_empty_cells().is_empty():
		return

	var other_slots := _get_non_special_slots(anchor_slot)
	if other_slots.is_empty():
		return

	var slot_b := other_slots[rng.randi_range(0, other_slots.size() - 1)]
	var piece_b := _pick_weighted_fitting_piece(_sim_board, _get_tray_shape_ids())
	if piece_b != null:
		tray[slot_b] = piece_b


func _has_two_piece_solvency() -> bool:
	if _sim_board == null:
		_sim_board = BoardState.new()
	for i in range(TRAY_SIZE):
		var pi := tray[i]
		if pi == null:
			continue
		var placements := board.get_valid_placements(pi)
		if placements.is_empty():
			continue

		# Sample up to 8 evenly spaced placements on a zero-allocation reusable _sim_board.
		var max_checks := mini(placements.size(), 8)
		for idx in range(max_checks):
			var sample_idx := idx if placements.size() <= 8 else mini(placements.size() - 1, int(float(idx * placements.size()) / float(max_checks)))
			var orig := placements[sample_idx]
			_sim_board.copy_from(board)
			_sim_board.place_and_resolve(pi, orig)
			for j in range(TRAY_SIZE):
				if j == i or tray[j] == null:
					continue
				if _sim_board.can_piece_fit_anywhere(tray[j]):
					return true
	return false


func _pick_weighted_fitting_piece(
	target_board: BoardState,
	excluded_ids: Array[String]
) -> PieceCatalog.Piece:
	var fitting_all: Array[String] = []
	var fitting_non_dot: Array[String] = []
	var fitting_unique: Array[String] = []
	var fitting_unique_non_dot: Array[String] = []

	for shape_id in PieceCatalog.get_all_shape_ids():
		var candidate: PieceCatalog.Piece = _cached_shape_templates.get(shape_id, null) as PieceCatalog.Piece
		if candidate == null:
			candidate = PieceCatalog.create_piece_by_id(shape_id, 0)
			_cached_shape_templates[shape_id] = candidate
		if target_board.can_piece_fit_anywhere(candidate):
			fitting_all.append(shape_id)
			var is_unique := not excluded_ids.has(shape_id)
			if is_unique:
				fitting_unique.append(shape_id)
			if shape_id != "dot_1x1":
				fitting_non_dot.append(shape_id)
				if is_unique:
					fitting_unique_non_dot.append(shape_id)

	if fitting_all.is_empty():
		return null

	var pool := fitting_all
	var prefer_non_dot := rng.randf() < 0.85
	if prefer_non_dot and not fitting_unique_non_dot.is_empty():
		pool = fitting_unique_non_dot
	elif prefer_non_dot and not fitting_non_dot.is_empty():
		pool = fitting_non_dot
	elif not fitting_unique.is_empty():
		pool = fitting_unique

	return PieceCatalog.create_weighted_piece_from_ids(pool, rng)


func _get_fitting_tray_slots(target_board: BoardState) -> Array[int]:
	var slots: Array[int] = []
	for i in range(TRAY_SIZE):
		if tray[i] != null and target_board.can_piece_fit_anywhere(tray[i]):
			slots.append(i)
	return slots


func _get_non_special_slots(exclude_slot: int) -> Array[int]:
	var slots: Array[int] = []
	for i in range(TRAY_SIZE):
		if i == exclude_slot:
			continue
		if tray[i] == null or not tray[i].is_special():
			slots.append(i)
	return slots


func _get_tray_shape_ids() -> Array[String]:
	var ids: Array[String] = []
	for piece in tray:
		if piece != null:
			ids.append(piece.id)
	return ids


func _is_tray_empty() -> bool:
	for piece in tray:
		if piece != null:
			return false
	return true


func _remaining_tray_count() -> int:
	var count := 0
	for piece in tray:
		if piece != null:
			count += 1
	return count


func _find_first_empty_tray_slot() -> int:
	for i in range(TRAY_SIZE):
		if tray[i] == null:
			return i
	return -1
