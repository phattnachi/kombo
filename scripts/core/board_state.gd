class_name BoardState
extends RefCounted

## 8x8 Kombo puzzle board state, collision, line clearing, special blasts, and multiplier tiles.

const GRID_SIZE := 8
const MAX_ACTIVE_MULTIPLIERS := 3

enum TargetType {
	NONE = 0,
	CRYSTAL = 1,
	ICE = 2,
	PADLOCK = 3,
}


class Cell extends RefCounted:
	var occupied: bool = false
	var color_id: int = -1
	var multiplier: int = 1
	var target_type: int = TargetType.NONE
	var target_hp: int = 0

	func reset() -> void:
		occupied = false
		color_id = -1
		multiplier = 1
		target_type = TargetType.NONE
		target_hp = 0


var _cells: Array[Cell] = []


func _init() -> void:
	_cells.resize(GRID_SIZE * GRID_SIZE)
	for i in range(GRID_SIZE * GRID_SIZE):
		_cells[i] = Cell.new()


func clear_board() -> void:
	for cell in _cells:
		cell.reset()


func in_bounds_xy(x: int, y: int) -> bool:
	return x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE


func in_bounds(pos: Vector2i) -> bool:
	return in_bounds_xy(pos.x, pos.y)


func _index(x: int, y: int) -> int:
	return y * GRID_SIZE + x


func get_cell(x: int, y: int) -> Cell:
	assert(in_bounds_xy(x, y), "Board cell out of bounds: (%d, %d)" % [x, y])
	return _cells[_index(x, y)]


func is_occupied(x: int, y: int) -> bool:
	if not in_bounds_xy(x, y):
		return true
	return _cells[_index(x, y)].occupied


func is_occupied_v(pos: Vector2i) -> bool:
	return is_occupied(pos.x, pos.y)


func get_color_id(x: int, y: int) -> int:
	if not in_bounds_xy(x, y):
		return -1
	return _cells[_index(x, y)].color_id


func get_multiplier(x: int, y: int) -> int:
	if not in_bounds_xy(x, y):
		return 1
	return _cells[_index(x, y)].multiplier


func set_cell(x: int, y: int, occupied: bool, color_id: int = 0) -> void:
	assert(in_bounds_xy(x, y), "Board cell out of bounds: (%d, %d)" % [x, y])
	var cell := _cells[_index(x, y)]
	cell.occupied = occupied
	cell.color_id = clampi(color_id, 0, PieceCatalog.COLOR_COUNT - 1) if occupied else -1


func set_multiplier(x: int, y: int, mult: int) -> void:
	assert(in_bounds_xy(x, y), "Board cell out of bounds: (%d, %d)" % [x, y])
	var cell := _cells[_index(x, y)]
	cell.multiplier = maxi(1, mult)


func get_target_type(x: int, y: int) -> int:
	if not in_bounds_xy(x, y):
		return TargetType.NONE
	return _cells[_index(x, y)].target_type


func get_target_hp(x: int, y: int) -> int:
	if not in_bounds_xy(x, y):
		return 0
	return _cells[_index(x, y)].target_hp


func set_target_cell(x: int, y: int, color_id: int, p_target_type: int, p_hp: int = -1) -> void:
	assert(in_bounds_xy(x, y), "Board cell out of bounds: (%d, %d)" % [x, y])
	var cell := _cells[_index(x, y)]
	cell.occupied = true
	cell.color_id = clampi(color_id, 0, PieceCatalog.COLOR_COUNT - 1)
	cell.target_type = p_target_type
	if p_hp > 0:
		cell.target_hp = p_hp
	else:
		cell.target_hp = 2 if p_target_type == TargetType.ICE else (1 if p_target_type != TargetType.NONE else 0)


func count_remaining_targets() -> int:
	var count := 0
	for cell in _cells:
		if cell.occupied and cell.target_type != TargetType.NONE and cell.target_hp > 0:
			count += 1
	return count


func get_cell_snapshot(x: int, y: int) -> Dictionary:
	var cell := get_cell(x, y)
	return {
		"occupied": cell.occupied,
		"color_id": cell.color_id,
		"multiplier": cell.multiplier,
		"target_type": cell.target_type,
		"target_hp": cell.target_hp,
	}


func get_occupied_count() -> int:
	var count := 0
	for cell in _cells:
		if cell.occupied:
			count += 1
	return count


func get_empty_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if not _cells[_index(x, y)].occupied:
				result.append(Vector2i(x, y))
	return result


func get_active_multiplier_cells() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var cell := _cells[_index(x, y)]
			if cell.multiplier > 1:
				result.append({
					"cell": Vector2i(x, y),
					"value": cell.multiplier,
					"occupied": cell.occupied,
				})
	return result


func can_place_piece(piece: PieceCatalog.Piece, origin: Vector2i) -> bool:
	if piece == null or piece.cells.is_empty():
		return false
	for offset in piece.cells:
		var pos := origin + offset
		if not in_bounds(pos):
			return false
		if _cells[_index(pos.x, pos.y)].occupied:
			return false
	return true


func can_piece_fit_anywhere(piece: PieceCatalog.Piece) -> bool:
	if piece == null or piece.cells.is_empty():
		return false
	var max_x := GRID_SIZE - piece.width
	var max_y := GRID_SIZE - piece.height
	if max_x < 0 or max_y < 0:
		return false
	for y in range(max_y + 1):
		for x in range(max_x + 1):
			if can_place_piece(piece, Vector2i(x, y)):
				return true
	return false


func get_valid_placements(piece: PieceCatalog.Piece) -> Array[Vector2i]:
	var placements: Array[Vector2i] = []
	if piece == null or piece.cells.is_empty():
		return placements
	var max_x := GRID_SIZE - piece.width
	var max_y := GRID_SIZE - piece.height
	if max_x < 0 or max_y < 0:
		return placements
	for y in range(max_y + 1):
		for x in range(max_x + 1):
			var origin := Vector2i(x, y)
			if can_place_piece(piece, origin):
				placements.append(origin)
	return placements


static func empty_preview() -> Dictionary:
	return {
		"valid": false,
		"placed_cells": [] as Array[Vector2i],
		"cleared_rows": [] as Array[int],
		"cleared_cols": [] as Array[int],
		"blast_zone_cells": [] as Array[Vector2i],
		"hit_multipliers": [] as Array[Dictionary],
	}


func clone() -> BoardState:
	var copy := BoardState.new()
	for i in range(GRID_SIZE * GRID_SIZE):
		var src := _cells[i]
		var dst := copy._cells[i]
		dst.occupied = src.occupied
		dst.color_id = src.color_id
		dst.multiplier = src.multiplier
		dst.target_type = src.target_type
		dst.target_hp = src.target_hp
	return copy


func preview_placement(piece: PieceCatalog.Piece, origin: Vector2i) -> Dictionary:
	if not can_place_piece(piece, origin):
		return empty_preview()

	var placed_cells: Array[Vector2i] = []
	var placed_set: Dictionary = {}
	for offset in piece.cells:
		var pos := origin + offset
		placed_cells.append(pos)
		placed_set[pos] = true

	var cleared_rows: Array[int] = []
	for y in range(GRID_SIZE):
		var full := true
		for x in range(GRID_SIZE):
			var p := Vector2i(x, y)
			if not _cells[_index(x, y)].occupied and not placed_set.has(p):
				full = false
				break
		if full:
			cleared_rows.append(y)

	var cleared_cols: Array[int] = []
	for x in range(GRID_SIZE):
		var full := true
		for y in range(GRID_SIZE):
			var p := Vector2i(x, y)
			if not _cells[_index(x, y)].occupied and not placed_set.has(p):
				full = false
				break
		if full:
			cleared_cols.append(x)

	var blast_zone_cells := _compute_blast_zone(piece.special_type, origin)
	var has_blast_target := false
	for pos in blast_zone_cells:
		if _cells[_index(pos.x, pos.y)].occupied:
			has_blast_target = true
			break
	var empty_special_fizzle := (
		piece.is_special()
		and cleared_rows.is_empty()
		and cleared_cols.is_empty()
		and not has_blast_target
	)

	var cleared_set: Dictionary = {}
	for y in cleared_rows:
		for x in range(GRID_SIZE):
			cleared_set[Vector2i(x, y)] = true
	for x in cleared_cols:
		for y in range(GRID_SIZE):
			cleared_set[Vector2i(x, y)] = true
	for pos in blast_zone_cells:
		if _cells[_index(pos.x, pos.y)].occupied:
			cleared_set[pos] = true
		elif placed_set.has(pos) and not empty_special_fizzle:
			cleared_set[pos] = true

	var hit_multipliers: Array[Dictionary] = []
	for pos_key in cleared_set.keys():
		var pos: Vector2i = pos_key
		var mult := _cells[_index(pos.x, pos.y)].multiplier
		if mult > 1:
			hit_multipliers.append({"cell": pos, "value": mult})

	return {
		"valid": true,
		"placed_cells": placed_cells,
		"cleared_rows": cleared_rows,
		"cleared_cols": cleared_cols,
		"blast_zone_cells": blast_zone_cells,
		"hit_multipliers": hit_multipliers,
	}


func place_and_resolve(piece: PieceCatalog.Piece, origin: Vector2i) -> Dictionary:
	if not can_place_piece(piece, origin):
		return {"valid": false}

	# 1. Place cells onto board while preserving any existing multiplier tiles.
	var placed_cells: Array[Vector2i] = []
	for offset in piece.cells:
		var pos := origin + offset
		var cell := _cells[_index(pos.x, pos.y)]
		cell.occupied = true
		cell.color_id = piece.color_id
		placed_cells.append(pos)

	# 2. Detect naturally completed rows and columns.
	var cleared_rows: Array[int] = []
	for y in range(GRID_SIZE):
		var row_full := true
		for x in range(GRID_SIZE):
			if not _cells[_index(x, y)].occupied:
				row_full = false
				break
		if row_full:
			cleared_rows.append(y)

	var cleared_cols: Array[int] = []
	for x in range(GRID_SIZE):
		var col_full := true
		for y in range(GRID_SIZE):
			if not _cells[_index(x, y)].occupied:
				col_full = false
				break
		if col_full:
			cleared_cols.append(x)

	var line_cell_set: Dictionary = {}
	for y in cleared_rows:
		for x in range(GRID_SIZE):
			line_cell_set[Vector2i(x, y)] = true
	for x in cleared_cols:
		for y in range(GRID_SIZE):
			line_cell_set[Vector2i(x, y)] = true

	# 3. Compute special blast zone and destroyed pre-existing blast cells
	# (excluding cells already in completed lines and excluding the Bomb/Lightning origin cell itself;
	# origin is still added to all_cleared_set so the special piece consumes itself off the board,
	# while preserving any uncovered multiplier under origin if the special hit nothing).
	var blast_zone_cells := _compute_blast_zone(piece.special_type, origin)
	var blast_cells: Array[Vector2i] = []
	var all_cleared_set: Dictionary = line_cell_set.duplicate()

	for pos in blast_zone_cells:
		var cell := _cells[_index(pos.x, pos.y)]
		if cell.occupied:
			all_cleared_set[pos] = true
			if not line_cell_set.has(pos) and pos != origin:
				blast_cells.append(pos)

	var empty_special_fizzle := (
		piece.is_special()
		and cleared_rows.is_empty()
		and cleared_cols.is_empty()
		and blast_cells.is_empty()
	)

	# 4. Collect cleared cells, pre-clear colors, target hits/cracks, and triggered multipliers.
	var cleared_cells: Array[Vector2i] = []
	var cleared_cell_colors: Dictionary = {}
	var hit_multipliers: Array[Dictionary] = []
	var destroyed_targets: Array[Dictionary] = []
	var cracked_targets: Array[Vector2i] = []

	var row_set: Dictionary = {}
	for y in cleared_rows:
		row_set[y] = true
	var col_set: Dictionary = {}
	for x in cleared_cols:
		col_set[x] = true

	for pos_key in all_cleared_set.keys():
		var pos: Vector2i = pos_key
		var cell := _cells[_index(pos.x, pos.y)]
		cleared_cell_colors[pos] = cell.color_id
		if empty_special_fizzle and pos == origin:
			# Preserve uncovered multiplier on empty-space special fizzle; only consume the special block itself.
			cleared_cells.append(pos)
			cell.occupied = false
			cell.color_id = -1
		else:
			var dmg := 1
			if piece.is_special() and blast_zone_cells.has(pos):
				dmg = 2
			elif row_set.has(pos.y) and col_set.has(pos.x):
				dmg = 2

			if cell.target_type != TargetType.NONE and cell.target_hp > dmg:
				# Multi-HP target (e.g. Frozen Ice) cracks and remains on board until next hit!
				cell.target_hp -= dmg
				cracked_targets.append(pos)
			else:
				cleared_cells.append(pos)
				if cell.target_type != TargetType.NONE:
					destroyed_targets.append({
						"cell": pos,
						"type": cell.target_type,
					})
				if cell.multiplier > 1:
					hit_multipliers.append({
						"cell": pos,
						"value": cell.multiplier,
					})
				cell.reset()

	return {
		"valid": true,
		"placed_cells": placed_cells,
		"cleared_rows": cleared_rows,
		"cleared_cols": cleared_cols,
		"lines_cleared": cleared_rows.size() + cleared_cols.size(),
		"blast_cells": blast_cells,
		"blast_zone_cells": blast_zone_cells,
		"cleared_cells": cleared_cells,
		"cleared_cell_colors": cleared_cell_colors,
		"hit_multipliers": hit_multipliers,
		"destroyed_targets": destroyed_targets,
		"cracked_targets": cracked_targets,
		"special_triggered": piece.special_type,
		"blast_origin": origin,
	}


func spawn_initial_multipliers(rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	# Start every game with two x2 tiles and one x3 tile nicely spaced on the board.
	var spawned: Array[Dictionary] = []
	var existing: Array[Vector2i] = []
	for item in get_active_multiplier_cells():
		existing.append(item["cell"] as Vector2i)

	var desired_values: Array[int] = [3, 2, 2]
	for mult_value in desired_values:
		var prefer_inner := (mult_value == 3)
		var pos := _pick_spaced_empty_cell(existing, rng, prefer_inner)
		if pos.x >= 0:
			set_multiplier(pos.x, pos.y, mult_value)
			existing.append(pos)
			spawned.append({"cell": pos, "value": mult_value})
	return spawned


func replenish_multipliers(
	rng: RandomNumberGenerator = null,
	max_to_spawn: int = 2,
	avoid_cells: Array[Vector2i] = []
) -> Array[Dictionary]:
	var active := get_active_multiplier_cells()
	var needed := mini(MAX_ACTIVE_MULTIPLIERS - active.size(), max_to_spawn)
	if needed <= 0:
		return []

	var existing: Array[Vector2i] = []
	var x3_count := 0
	for item in active:
		existing.append(item["cell"] as Vector2i)
		if int(item["value"]) >= 3:
			x3_count += 1

	var spawned: Array[Dictionary] = []
	for _i in range(needed):
		var roll := rng.randf() if rng != null else randf()
		var x3_chance := 0.30 if x3_count == 0 else 0.12
		var mult_value := 3 if roll < x3_chance else 2
		var pos := _pick_spaced_empty_cell(existing, rng, mult_value == 3, avoid_cells)
		if pos.x < 0:
			break
		set_multiplier(pos.x, pos.y, mult_value)
		existing.append(pos)
		if mult_value >= 3:
			x3_count += 1
		spawned.append({"cell": pos, "value": mult_value})
	return spawned


func _compute_blast_zone(special_type: int, origin: Vector2i) -> Array[Vector2i]:
	var zone: Array[Vector2i] = []
	if special_type == PieceCatalog.SPECIAL_BOMB:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var pos := Vector2i(origin.x + dx, origin.y + dy)
				if in_bounds(pos):
					zone.append(pos)
	elif special_type == PieceCatalog.SPECIAL_LIGHTNING:
		var seen: Dictionary = {}
		for x in range(GRID_SIZE):
			var row_pos := Vector2i(x, origin.y)
			if not seen.has(row_pos):
				seen[row_pos] = true
				zone.append(row_pos)
		for y in range(GRID_SIZE):
			var col_pos := Vector2i(origin.x, y)
			if not seen.has(col_pos):
				seen[col_pos] = true
				zone.append(col_pos)
	return zone


func _pick_spaced_empty_cell(
	existing: Array[Vector2i],
	rng: RandomNumberGenerator,
	prefer_inner: bool,
	avoid_cells: Array[Vector2i] = []
) -> Vector2i:
	var all_empty: Array[Vector2i] = []
	var preferred_empty: Array[Vector2i] = []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var cell := _cells[_index(x, y)]
			if not cell.occupied and cell.multiplier == 1:
				var p := Vector2i(x, y)
				all_empty.append(p)
				if not avoid_cells.has(p):
					preferred_empty.append(p)

	var candidates := preferred_empty if not preferred_empty.is_empty() else all_empty
	if candidates.is_empty():
		return Vector2i(-1, -1)

	# Tier 1: Well-spaced (Manhattan >= 3, different row/col from existing), optionally inner 6x6.
	var tier1: Array[Vector2i] = []
	# Tier 2: Manhattan >= 3 from all existing.
	var tier2: Array[Vector2i] = []
	# Tier 3: Manhattan >= 2 from all existing.
	var tier3: Array[Vector2i] = []

	for pos in candidates:
		var min_dist := 999
		var shares_axis := false
		for ex in existing:
			var dist := absi(pos.x - ex.x) + absi(pos.y - ex.y)
			min_dist = mini(min_dist, dist)
			if pos.x == ex.x or pos.y == ex.y:
				shares_axis = true
		var is_inner := pos.x >= 1 and pos.x <= GRID_SIZE - 2 and pos.y >= 1 and pos.y <= GRID_SIZE - 2
		if min_dist >= 3 and not shares_axis and (not prefer_inner or is_inner):
			tier1.append(pos)
		if min_dist >= 3:
			tier2.append(pos)
		if min_dist >= 2:
			tier3.append(pos)

	var pool := candidates
	if not tier1.is_empty():
		pool = tier1
	elif not tier2.is_empty():
		pool = tier2
	elif not tier3.is_empty():
		pool = tier3

	var idx := rng.randi_range(0, pool.size() - 1) if rng != null else randi_range(0, pool.size() - 1)
	return pool[idx]
