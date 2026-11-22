class_name DailyChallenge
extends RefCounted

## Deterministic Daily Challenge generator & share-card formatter for Kombo by SOYA GAMES.
## Every player worldwide on the same calendar date (YYYY-MM-DD) receives:
##   1. The exact same pre-seeded starter board layout & initial x2/x3 multiplier tiles.
##   2. The exact same ordered sequence of 3-piece deals (isolated RNG stream so player
##      placement differences NEVER diverge the dealt piece queue!).

const MAX_DAILY_ATTEMPTS: int = 3
const SEED_SALT: String = "KOMBO_SOYA_DAILY_V1:"

const MONTH_ABBR: Array[String] = [
	"JAN", "FEB", "MAR", "APR", "MAY", "JUN",
	"JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
]

## Eight handcrafted symmetrical/architectural 8x8 starter motifs (each 10..12 cells,
## guaranteed ZERO completed rows or columns and rich early combo/clear setups).
const STARTER_MOTIFS: Array = [
	# 0: Center Diamond Ring
	[
		Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(2, 2), Vector2i(5, 2),
		Vector2i(1, 3), Vector2i(6, 3),
		Vector2i(1, 4), Vector2i(6, 4),
		Vector2i(2, 5), Vector2i(5, 5),
		Vector2i(3, 6), Vector2i(4, 6),
	],
	# 1: Four Corner Bastions
	[
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1),
		Vector2i(6, 0), Vector2i(7, 0), Vector2i(7, 1),
		Vector2i(0, 6), Vector2i(0, 7), Vector2i(1, 7),
		Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7),
	],
	# 2: Twin Diagonal Bridges
	[
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2),
		Vector2i(3, 3), Vector2i(4, 3),
		Vector2i(3, 4), Vector2i(4, 4),
		Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6),
	],
	# 3: Broken Crossroad
	[
		Vector2i(3, 0), Vector2i(4, 0),
		Vector2i(3, 2), Vector2i(4, 5),
		Vector2i(0, 3), Vector2i(2, 3),
		Vector2i(5, 4), Vector2i(7, 4),
		Vector2i(3, 7), Vector2i(4, 7),
	],
	# 4: Twin Vertical Pillars (open center lane)
	[
		Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 5), Vector2i(2, 6),
		Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 5), Vector2i(5, 6),
		Vector2i(3, 3), Vector2i(4, 4),
	],
	# 5: Hourglass Pockets
	[
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(5, 1), Vector2i(6, 1),
		Vector2i(3, 2), Vector2i(4, 2),
		Vector2i(3, 5), Vector2i(4, 5),
		Vector2i(1, 6), Vector2i(2, 6), Vector2i(5, 6), Vector2i(6, 6),
	],
	# 6: Pinwheel Clusters
	[
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1),
		Vector2i(5, 1), Vector2i(5, 2), Vector2i(6, 2),
		Vector2i(1, 5), Vector2i(2, 5), Vector2i(2, 6),
		Vector2i(5, 6), Vector2i(5, 5), Vector2i(6, 5),
	],
	# 7: Zigzag Stepping Stones
	[
		Vector2i(0, 2), Vector2i(1, 2),
		Vector2i(2, 4), Vector2i(3, 4),
		Vector2i(4, 3), Vector2i(5, 3),
		Vector2i(6, 5), Vector2i(7, 5),
		Vector2i(3, 1), Vector2i(4, 6),
	],
]

const HEAVY_SHAPE_IDS: Array[String] = [
	"sq3", "h5", "v5", "l3x3_bl", "l3x3_br", "l3x3_tl", "l3x3_tr", "rect_2x3", "rect_3x2",
]


static func get_today_date_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(d.get("year", 2026)), int(d.get("month", 1)), int(d.get("day", 1))]


static func format_display_date(date_key: String, include_year: bool = true) -> String:
	var parts := date_key.split("-")
	if parts.size() != 3:
		return date_key
	var yr := parts[0].to_int()
	var mo := clampi(parts[1].to_int(), 1, 12)
	var dy := clampi(parts[2].to_int(), 1, 31)
	var m_str := MONTH_ABBR[mo - 1]
	if include_year:
		return "%02d %s %04d" % [dy, m_str, yr]
	return "%02d %s" % [dy, m_str]


static func get_previous_date_key(date_key: String) -> String:
	var parts := date_key.split("-")
	if parts.size() != 3:
		return ""
	var y := parts[0].to_int()
	var m := parts[1].to_int()
	var d := parts[2].to_int()
	if y <= 0 or m < 1 or m > 12 or d < 1 or d > 31:
		return ""
	d -= 1
	if d < 1:
		m -= 1
		if m < 1:
			m = 12
			y -= 1
		d = _days_in_month(y, m)
	return "%04d-%02d-%02d" % [y, m, d]


static func _days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			var is_leap := (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)
			return 29 if is_leap else 28
		_:
			return 30


## Pure cross-platform deterministic positive 62-bit seed from date string.
static func compute_seed_for_date(date_key: String, stream_tag: String = "MAIN") -> int:
	var text := SEED_SALT + date_key + ":" + stream_tag
	var bytes := text.to_utf8_buffer()
	var h: int = 1469598103934665603
	for b in bytes:
		h = (h ^ int(b)) & 0x7FFFFFFFFFFFFFFF
		h = (h * 1099511628211) & 0x7FFFFFFFFFFFFFFF
	# Extra avalanche mixing (signed 64-bit safe xorshift64* prime)
	h = (h ^ (h >> 30)) & 0x7FFFFFFFFFFFFFFF
	h = (h * 0x2545F4914F6CDD1D) & 0x7FFFFFFFFFFFFFFF
	h = (h ^ (h >> 27)) & 0x7FFFFFFFFFFFFFFF
	return maxi(1, h & 0x3FFFFFFFFFFFFFFF)


static func compute_board_seed(date_key: String) -> int:
	return compute_seed_for_date(date_key, "BOARD")


static func compute_deal_seed(date_key: String) -> int:
	return compute_seed_for_date(date_key, "DEAL")


static func compute_mult_seed(date_key: String) -> int:
	return compute_seed_for_date(date_key, "MULT")


## Populates an 8x8 BoardState with today's deterministic symmetrical starter blocks
## and 3 deterministic multiplier tiles (two x2, one x3) on open cells.
static func populate_starter_board(board: BoardState, date_key: String) -> void:
	board.clear_board()
	var brng := RandomNumberGenerator.new()
	brng.seed = compute_board_seed(date_key)

	var motif_idx := brng.randi_range(0, STARTER_MOTIFS.size() - 1)
	var motif: Array = STARTER_MOTIFS[motif_idx]
	var rot_steps := brng.randi_range(0, 3)
	var mirror_x := brng.randi_range(0, 1) == 1

	# Pick a harmonious 2-to-3 jewel color theme for today's starter blocks.
	var primary_col := brng.randi_range(0, PieceCatalog.COLOR_COUNT - 1)
	var secondary_col := (primary_col + brng.randi_range(2, 4)) % PieceCatalog.COLOR_COUNT
	var accent_col := (secondary_col + brng.randi_range(1, 3)) % PieceCatalog.COLOR_COUNT

	for idx in range(motif.size()):
		var pt := motif[idx] as Vector2i
		var x := pt.x
		var y := pt.y
		if mirror_x:
			x = (BoardState.GRID_SIZE - 1) - x
		for _r in range(rot_steps):
			var nx := (BoardState.GRID_SIZE - 1) - y
			var ny := x
			x = nx
			y = ny
		var color_id := primary_col if (idx % 3 == 0) else (secondary_col if (idx % 3 == 1) else accent_col)
		board.set_cell(x, y, true, color_id)

	# Spawn 3 deterministic starter multiplier tiles (2x, 2x, 3x) strictly on empty cells.
	var empties := board.get_empty_cells()
	var targets: Array[int] = [2, 2, 3]
	for mult_val in targets:
		if empties.is_empty():
			break
		var pick_idx := brng.randi_range(0, empties.size() - 1)
		var cell := empties[pick_idx]
		empties.remove_at(pick_idx)
		board.set_multiplier(cell.x, cell.y, mult_val)


## Deals an ordered 3-piece tray using ONLY deal_rng (100% independent of board state!)
## so every player worldwide gets the exact same sequence of trays on the same date.
## Enforces at most 1 heavy piece per tray deterministically to keep daily skill fair.
static func deal_deterministic_tray(
	deal_rng: RandomNumberGenerator,
	pending_specials: Array[int]
) -> Array[PieceCatalog.Piece]:
	var out: Array[PieceCatalog.Piece] = [null, null, null]
	var used_ids: Array[String] = []
	var heavy_count: int = 0

	for i in range(3):
		if not pending_specials.is_empty():
			var sp_type: int = pending_specials.pop_front()
			out[i] = PieceCatalog.create_special_piece(sp_type)
		else:
			var exclude := used_ids.duplicate()
			if heavy_count >= 1:
				for hid in HEAVY_SHAPE_IDS:
					if not exclude.has(hid):
						exclude.append(hid)
			var piece := PieceCatalog.create_random_piece(deal_rng, exclude)
			out[i] = piece
			used_ids.append(piece.id)
			if HEAVY_SHAPE_IDS.has(piece.id):
				heavy_count += 1

	return out


## Builds a crisp, chat-ready result summary card to copy & compare scores with friends.
static func build_share_text(
	date_key: String,
	run_score: int,
	daily_best: int,
	best_combo: int,
	attempt_num: int,
	streak: int
) -> String:
	var date_str := format_display_date(date_key, true)
	var s_run := HudView.format_comma_int(maxi(0, run_score))
	var s_best := HudView.format_comma_int(maxi(run_score, daily_best))
	var tries_str := "%d/%d" % [clampi(attempt_num, 1, MAX_DAILY_ATTEMPTS), MAX_DAILY_ATTEMPTS]
	var lines: Array[String] = [
		"KOMBO! Daily Challenge • %s" % date_str,
		"Score: %s  (Daily Best: %s)" % [s_run, s_best],
		"Max Combo: ×%d  |  Try: %s  |  Streak: %dd" % [maxi(0, best_combo), tries_str, maxi(0, streak)],
		"SOYA GAMES",
	]
	return "\n".join(lines)
