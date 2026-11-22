class_name GemHunt
extends RefCounted

## Stage-based Clear-the-Board / Gem Hunt Adventure generator for Kombo by SOYA GAMES.
## Populates each 8x8 stage with tactical Crystal Gems, Cursed Padlocks, and 2-HP Frozen
## Ice blocks plus escalating stage base score multipliers (x1.0 -> x1.25 -> x1.5 -> ...).

const STAGE_CLEAR_BONUS_PER_STAGE: int = 3000
const PADLOCK_SHATTER_BONUS: int = 450
const MAX_STAGE_MULT: float = 4.0

## Ten handcrafted architectural target layouts (8..14 cells, zero full rows/cols).
const STAGE_LAYOUTS: Array = [
	# 0: Crystal Diamond (8 targets — snappy Stage 1 intro!)
	[
		Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(1, 3), Vector2i(6, 3),
		Vector2i(1, 4), Vector2i(6, 4),
		Vector2i(3, 6), Vector2i(4, 6),
	],
	# 1: Twin Vaults (10 targets)
	[
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2),
		Vector2i(3, 3), Vector2i(4, 3),
		Vector2i(3, 4), Vector2i(4, 4),
		Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6),
	],
	# 2: Frozen Crown (12 targets)
	[
		Vector2i(1, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(6, 1),
		Vector2i(2, 3), Vector2i(5, 3),
		Vector2i(2, 4), Vector2i(5, 4),
		Vector2i(1, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(6, 6),
	],
	# 3: Four Bastions (12 targets)
	[
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1),
		Vector2i(6, 0), Vector2i(7, 0), Vector2i(7, 1),
		Vector2i(0, 6), Vector2i(0, 7), Vector2i(1, 7),
		Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7),
	],
	# 4: Hourglass Sanctum (12 targets)
	[
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(5, 1), Vector2i(6, 1),
		Vector2i(3, 2), Vector2i(4, 2),
		Vector2i(3, 5), Vector2i(4, 5),
		Vector2i(1, 6), Vector2i(2, 6), Vector2i(5, 6), Vector2i(6, 6),
	],
	# 5: Twin Pillars & Core (12 targets)
	[
		Vector2i(2, 0), Vector2i(2, 2), Vector2i(2, 5), Vector2i(2, 7),
		Vector2i(5, 0), Vector2i(5, 2), Vector2i(5, 5), Vector2i(5, 7),
		Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4),
	],
	# 6: Pinwheel Shrine (12 targets)
	[
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1),
		Vector2i(5, 1), Vector2i(5, 2), Vector2i(6, 2),
		Vector2i(1, 5), Vector2i(2, 5), Vector2i(2, 6),
		Vector2i(5, 6), Vector2i(5, 5), Vector2i(6, 5),
	],
	# 7: Crossroad Sigil (14 targets)
	[
		Vector2i(3, 0), Vector2i(4, 0),
		Vector2i(3, 2), Vector2i(4, 2),
		Vector2i(0, 3), Vector2i(2, 3), Vector2i(5, 3), Vector2i(7, 3),
		Vector2i(0, 4), Vector2i(2, 4), Vector2i(5, 4), Vector2i(7, 4),
		Vector2i(3, 7), Vector2i(4, 7),
	],
	# 8: Diagonal Vault (14 targets)
	[
		Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(3, 2), Vector2i(4, 2),
		Vector2i(2, 3), Vector2i(5, 3),
		Vector2i(2, 4), Vector2i(5, 4),
		Vector2i(3, 5), Vector2i(4, 5),
		Vector2i(6, 6), Vector2i(6, 7), Vector2i(7, 6),
	],
	# 9: Citadel Ring (14 targets)
	[
		Vector2i(1, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(6, 1),
		Vector2i(1, 3), Vector2i(6, 3),
		Vector2i(3, 3), Vector2i(4, 4),
		Vector2i(1, 4), Vector2i(6, 4),
		Vector2i(1, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(6, 6),
	],
]


static func get_stage_base_mult(stage: int) -> float:
	var s := maxi(1, stage)
	return minf(MAX_STAGE_MULT, 1.0 + float(s - 1) * 0.25)


static func get_stage_clear_bonus(stage: int) -> int:
	return maxi(1, stage) * STAGE_CLEAR_BONUS_PER_STAGE


static func populate_stage_board(board: BoardState, stage: int, rng: RandomNumberGenerator = null) -> int:
	board.clear_board()
	var s := maxi(1, stage)
	var use_rng := rng if rng != null else RandomNumberGenerator.new()

	var layout_idx := (s - 1) % STAGE_LAYOUTS.size()
	var raw_pts: Array = STAGE_LAYOUTS[layout_idx]
	var rot_steps := (s - 1) % 4
	var mirror_x := ((s - 1) / STAGE_LAYOUTS.size()) % 2 == 1

	var placed_targets: Array[Vector2i] = []
	for i in range(raw_pts.size()):
		var pt := raw_pts[i] as Vector2i
		var x := pt.x
		var y := pt.y
		if mirror_x:
			x = (BoardState.GRID_SIZE - 1) - x
		for _r in range(rot_steps):
			var nx := (BoardState.GRID_SIZE - 1) - y
			var ny := x
			x = nx
			y = ny

		var t_type := _pick_target_type_for_stage(s, i, raw_pts.size())
		var col_id := _color_for_target(t_type, i, s)
		var hp := 2 if t_type == BoardState.TargetType.ICE else 1
		board.set_target_cell(x, y, col_id, t_type, hp)
		placed_targets.append(Vector2i(x, y))

	# On higher stages (Stage 5+), sprinkle 1..2 extra random open-cell targets (max 16 total)
	# while keeping every row and column strictly below 6 occupied cells.
	var extra_count := clampi((s - 4) / 2, 0, 2)
	if extra_count > 0:
		var empties := board.get_empty_cells()
		for _e in range(extra_count):
			if empties.is_empty():
				break
			var pick_i := use_rng.randi_range(0, empties.size() - 1)
			var cell := empties[pick_i]
			empties.remove_at(pick_i)
			if _row_occupied(board, cell.y) < 5 and _col_occupied(board, cell.x) < 5:
				var extra_type := BoardState.TargetType.ICE if (s >= 6 and _e == 0) else BoardState.TargetType.PADLOCK
				board.set_target_cell(cell.x, cell.y, _color_for_target(extra_type, _e, s), extra_type)
				placed_targets.append(cell)

	# Spawn 3 starter x2/x3 multiplier tiles on open empty cells!
	board.spawn_initial_multipliers(use_rng)
	return board.count_remaining_targets()


static func _pick_target_type_for_stage(stage: int, idx: int, total: int) -> int:
	if stage <= 1:
		# Stage 1: pure gleaming Crystal Gems so the first stage clear is crisp & inviting!
		return BoardState.TargetType.CRYSTAL
	if stage == 2:
		# Stage 2: Crystals + Golden Cursed Padlocks!
		return BoardState.TargetType.PADLOCK if (idx % 3 == 0) else BoardState.TargetType.CRYSTAL
	if stage == 3:
		# Stage 3: Introduce 2-HP Frozen Ice blocks alongside Crystals & Padlocks!
		if idx == 0 or idx == total - 1 or (idx == total / 2):
			return BoardState.TargetType.ICE
		if idx % 3 == 1:
			return BoardState.TargetType.PADLOCK
		return BoardState.TargetType.CRYSTAL

	# Stage 4+: Rich escalating mix of Ice (2-HP), Padlocks, and Crystals!
	var ice_mod := 3 if stage >= 6 else 4
	if idx % ice_mod == 0:
		return BoardState.TargetType.ICE
	if idx % 3 == 1:
		return BoardState.TargetType.PADLOCK
	return BoardState.TargetType.CRYSTAL


static func _color_for_target(t_type: int, idx: int, stage: int) -> int:
	match t_type:
		BoardState.TargetType.CRYSTAL:
			return 5 if ((idx + stage) % 2 == 0) else 6 # Electric Cyan / Amethyst
		BoardState.TargetType.ICE:
			return 4 # Royal Blue beneath frost glaze
		BoardState.TargetType.PADLOCK:
			return 0 # Deep Ruby beneath golden padlock
		_:
			return (idx + stage) % PieceCatalog.COLOR_COUNT


static func _row_occupied(board: BoardState, y: int) -> int:
	var c := 0
	for x in range(BoardState.GRID_SIZE):
		if board.is_occupied(x, y):
			c += 1
	return c


static func _col_occupied(board: BoardState, x: int) -> int:
	var c := 0
	for y in range(BoardState.GRID_SIZE):
		if board.is_occupied(x, y):
			c += 1
	return c
