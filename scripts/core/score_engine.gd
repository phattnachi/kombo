class_name ScoreEngine
extends RefCounted

## Balatro-inspired Kombo scoring engine: base_chips * (combo_mult * tile_mult * fever_mult).

const CHIPS_PER_PLACED_CELL := 5
const CHIPS_PER_LINE := 100
const CHIPS_PER_BLAST_CELL := 15

const MULTI_LINE_BONUS_2 := 50
const MULTI_LINE_BONUS_3 := 150
const MULTI_LINE_BONUS_4_PLUS := 300

const COMBO_MULT_STEP := 0.5
const COMBO_GRACE_MAX := 3

const FEVER_CHARGE_PER_CLEAR := 0.34
const FEVER_EXTRA_LINE_BONUS := 0.15
const FEVER_DECAY_ON_COMBO_BREAK := 0.35
const FEVER_DECAY_IDLE := 0.15
const FEVER_INITIAL_TURNS := 5
const FEVER_MAX_TURNS := 6
const FEVER_MULT := 2.0

var score: int = 0
var high_score: int = 0
var session_starting_high_score: int = 0
var _has_beaten_session_high: bool = false

var combo_streak: int = 0
var combo_grace_left: int = 0
var best_combo: int = 0

var fever_charge: float = 0.0
var fever_active: bool = false
var fever_turns_left: int = 0
var stage_mult: float = 1.0


func reset(p_high_score: int = 0, p_best_combo: int = 0) -> void:
	score = 0
	high_score = maxi(0, p_high_score)
	session_starting_high_score = high_score
	_has_beaten_session_high = false
	combo_streak = 0
	combo_grace_left = 0
	best_combo = maxi(0, p_best_combo)
	fever_charge = 0.0
	fever_active = false
	fever_turns_left = 0
	stage_mult = 1.0


func add_bonus_points(bonus: int) -> Dictionary:
	var pts := maxi(0, bonus)
	score += pts
	if score > high_score:
		high_score = score
	var is_new_high := score > session_starting_high_score
	var just_beat := false
	if session_starting_high_score > 0 and not _has_beaten_session_high and score > session_starting_high_score:
		_has_beaten_session_high = true
		just_beat = true
	return {
		"bonus": pts,
		"new_score": score,
		"high_score": high_score,
		"is_new_high_score": is_new_high,
		"just_beat_high_score": just_beat,
	}


func is_new_personal_best() -> bool:
	return score > session_starting_high_score


func get_current_combo_mult() -> float:
	if combo_streak <= 0:
		return 1.0
	return 1.0 + float(combo_streak - 1) * COMBO_MULT_STEP


func get_current_fever_mult() -> float:
	return FEVER_MULT if fever_active else 1.0


func get_multi_line_bonus(lines_cleared: int) -> int:
	if lines_cleared <= 1:
		return 0
	if lines_cleared == 2:
		return MULTI_LINE_BONUS_2
	if lines_cleared == 3:
		return MULTI_LINE_BONUS_3
	return MULTI_LINE_BONUS_4_PLUS


func evaluate_move(
	placed_cell_count: int,
	lines_cleared: int,
	blast_cell_count: int,
	hit_multipliers: Array[Dictionary],
	_triggered_special: bool = false
) -> Dictionary:
	var placement_chips := placed_cell_count * CHIPS_PER_PLACED_CELL
	var line_chips := 0
	if lines_cleared > 0:
		line_chips = lines_cleared * CHIPS_PER_LINE + get_multi_line_bonus(lines_cleared)
	var blast_chips := blast_cell_count * CHIPS_PER_BLAST_CELL
	var base_chips := placement_chips + line_chips + blast_chips

	# Only treat a move as a clearing action if it cleared a line or destroyed pre-existing blocks
	# via Bomb/Lightning blast (empty-space specials cannot farm combo or FEVER).
	var is_clear_action := lines_cleared > 0 or blast_cell_count > 0
	var fever_just_ignited := false
	var fever_extinguished := false
	var tile_mult := 1.0

	if is_clear_action:
		combo_streak += 1
		combo_grace_left = COMBO_GRACE_MAX
		if combo_streak > best_combo:
			best_combo = combo_streak

		for item in hit_multipliers:
			var mult_val := int(item.get("value", 1))
			if mult_val > 1:
				tile_mult *= float(mult_val)

		if fever_active:
			fever_turns_left = mini(FEVER_MAX_TURNS, fever_turns_left + 1)
			fever_charge = clampf(float(fever_turns_left) / float(FEVER_INITIAL_TURNS), 0.0, 1.0)
		else:
			var extra_lines := maxi(0, lines_cleared - 1)
			var gain := FEVER_CHARGE_PER_CLEAR + float(extra_lines) * FEVER_EXTRA_LINE_BONUS
			fever_charge = minf(1.0, fever_charge + gain)
			if fever_charge >= 1.0:
				fever_active = true
				fever_just_ignited = true
				fever_turns_left = FEVER_INITIAL_TURNS
				fever_charge = 1.0
	else:
		var was_fever_active := fever_active

		# Authentic 3-move combo grace window: 1-2 setup blocks preserve combo, 3rd resets combo.
		if combo_streak > 0:
			combo_grace_left -= 1
			if combo_grace_left <= 0:
				combo_grace_left = 0
				combo_streak = 0
				if not was_fever_active:
					fever_charge = maxf(0.0, fever_charge - FEVER_DECAY_ON_COMBO_BREAK)
		else:
			combo_grace_left = 0
			if not was_fever_active:
				fever_charge = maxf(0.0, fever_charge - FEVER_DECAY_IDLE)

		# FEVER turn countdown: decrement by 1 per non-clearing placement; extinguish only at <= 0.
		if was_fever_active:
			fever_turns_left -= 1
			if fever_turns_left <= 0:
				fever_active = false
				fever_extinguished = true
				fever_turns_left = 0
				fever_charge = 0.0
			else:
				fever_charge = clampf(float(fever_turns_left) / float(FEVER_INITIAL_TURNS), 0.0, 1.0)

	var combo_mult := get_current_combo_mult() if is_clear_action else 1.0
	var fever_mult := get_current_fever_mult() if is_clear_action else 1.0
	var active_stage_mult := maxf(1.0, stage_mult) if is_clear_action else 1.0
	var total_mult := combo_mult * tile_mult * fever_mult * active_stage_mult
	var points_earned := int(round(float(base_chips) * total_mult))

	score += points_earned
	if score > high_score:
		high_score = score

	var is_new_high_score := score > session_starting_high_score
	var just_beat_high_score := false
	if (
		session_starting_high_score > 0
		and not _has_beaten_session_high
		and score > session_starting_high_score
	):
		_has_beaten_session_high = true
		just_beat_high_score = true

	return {
		"placement_chips": placement_chips,
		"line_chips": line_chips,
		"blast_chips": blast_chips,
		"base_chips": base_chips,
		"combo_streak": combo_streak,
		"combo_grace_left": combo_grace_left,
		"combo_mult": combo_mult,
		"tile_mult": tile_mult,
		"fever_active": fever_active,
		"fever_just_ignited": fever_just_ignited,
		"fever_extinguished": fever_extinguished,
		"fever_charge": fever_charge,
		"fever_turns_left": fever_turns_left,
		"fever_mult": fever_mult,
		"total_mult": total_mult,
		"points_earned": points_earned,
		"new_score": score,
		"high_score": high_score,
		"is_new_high_score": is_new_high_score,
		"just_beat_high_score": just_beat_high_score,
	}
