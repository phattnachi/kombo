class_name PieceCatalog
extends RefCounted

## Catalog of polyomino shapes, jewel color definitions, and special blocks for Kombo.

enum SpecialType {
	NORMAL = 0,
	BOMB = 1,
	LIGHTNING = 2,
}

const SPECIAL_NORMAL := SpecialType.NORMAL
const SPECIAL_BOMB := SpecialType.BOMB
const SPECIAL_LIGHTNING := SpecialType.LIGHTNING

const COLOR_COUNT := 7

const COLOR_NAMES: Array[String] = [
	"Ruby Red",
	"Solar Gold",
	"Tangerine",
	"Emerald",
	"Royal Blue",
	"Electric Cyan",
	"Amethyst",
]

const COLOR_PALETTE: Array[Color] = [
	Color(0.95, 0.20, 0.30), # 0: Ruby Red
	Color(0.98, 0.78, 0.14), # 1: Solar Gold
	Color(0.98, 0.47, 0.14), # 2: Tangerine
	Color(0.14, 0.80, 0.46), # 3: Emerald
	Color(0.20, 0.46, 0.96), # 4: Royal Blue
	Color(0.10, 0.84, 0.94), # 5: Electric Cyan
	Color(0.68, 0.28, 0.95), # 6: Amethyst
]


class Piece extends RefCounted:
	var id: String = ""
	var cells: Array[Vector2i] = []
	var color_id: int = 0
	var special_type: int = SpecialType.NORMAL
	var width: int = 1
	var height: int = 1

	func _init(
		p_id: String,
		p_cells: Array[Vector2i],
		p_color_id: int,
		p_special_type: int = SpecialType.NORMAL
	) -> void:
		id = p_id
		color_id = clampi(p_color_id, 0, COLOR_COUNT - 1)
		special_type = p_special_type
		cells = _normalize_cells(p_cells)
		_compute_bounds()

	func _normalize_cells(raw_cells: Array[Vector2i]) -> Array[Vector2i]:
		if raw_cells.is_empty():
			return [Vector2i.ZERO]
		var min_x := raw_cells[0].x
		var min_y := raw_cells[0].y
		for c in raw_cells:
			min_x = mini(min_x, c.x)
			min_y = mini(min_y, c.y)
		var out: Array[Vector2i] = []
		for c in raw_cells:
			out.append(Vector2i(c.x - min_x, c.y - min_y))
		return out

	func _compute_bounds() -> void:
		var max_x := 0
		var max_y := 0
		for c in cells:
			max_x = maxi(max_x, c.x)
			max_y = maxi(max_y, c.y)
		width = max_x + 1
		height = max_y + 1

	func cell_count() -> int:
		return cells.size()

	func is_special() -> bool:
		return special_type != SpecialType.NORMAL

	func duplicate_piece() -> Piece:
		var copied_cells: Array[Vector2i] = []
		for c in cells:
			copied_cells.append(c)
		return Piece.new(id, copied_cells, color_id, special_type)

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"cells": cells.duplicate(),
			"color_id": color_id,
			"special_type": special_type,
			"width": width,
			"height": height,
		}


class ShapeDef extends RefCounted:
	var id: String
	var cells: Array[Vector2i]
	var weight: float

	func _init(p_id: String, p_cells: Array[Vector2i], p_weight: float) -> void:
		id = p_id
		cells = p_cells
		weight = p_weight


static var _shapes: Array[ShapeDef] = []
static var _shape_by_id: Dictionary = {}
static var _total_weight: float = 0.0
static var _initialized: bool = false


static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_shapes.clear()
	_shape_by_id.clear()
	_total_weight = 0.0

	# Single cell (1x1)
	_register("dot_1x1", [Vector2i(0, 0)], 0.65)

	# Dominoes (1x2, 2x1)
	_register("h2", [Vector2i(0, 0), Vector2i(1, 0)], 1.4)
	_register("v2", [Vector2i(0, 0), Vector2i(0, 1)], 1.4)

	# Lines of 3 (1x3, 3x1)
	_register("h3", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], 1.5)
	_register("v3", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)], 1.5)

	# Lines of 4 (1x4, 4x1)
	_register("h4", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], 1.1)
	_register("v4", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)], 1.1)

	# Lines of 5 (1x5, 5x1)
	_register("h5", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)], 0.7)
	_register("v5", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4)], 0.7)

	# Squares (2x2, 3x3)
	_register("sq2", [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	], 1.8)
	_register("sq3", [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
	], 0.75)

	# L3 corner variants (all 4 rotations)
	_register("l3_br", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)], 0.75)
	_register("l3_bl", [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], 0.75)
	_register("l3_tr", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], 0.75)
	_register("l3_tl", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)], 0.75)

	# L4 / J4 variants (all 8 orientations)
	_register("l4_tall_r", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)], 0.45)
	_register("l4_tall_l", [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(0, 2)], 0.45)
	_register("l4_inv_r", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2)], 0.45)
	_register("l4_inv_l", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)], 0.45)
	_register("l4_wide_r", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)], 0.45)
	_register("l4_wide_l", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)], 0.45)
	_register("l4_bot_r", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], 0.45)
	_register("l4_bot_l", [Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], 0.45)

	# Big 3x3 L5 corner variants (classic Block Blast staple)
	_register("l5_br", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)], 0.35)
	_register("l5_bl", [Vector2i(2, 0), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)], 0.35)
	_register("l5_tr", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(0, 2)], 0.35)
	_register("l5_tl", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)], 0.35)

	# T4 variants (all 4 rotations)
	_register("t4_down", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)], 0.55)
	_register("t4_up", [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)], 0.55)
	_register("t4_right", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)], 0.55)
	_register("t4_left", [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)], 0.55)

	# Z4 / S4 variants (all 4 orientations)
	_register("z4_h", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)], 0.45)
	_register("s4_h", [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)], 0.45)
	_register("z4_v", [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)], 0.45)
	_register("s4_v", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)], 0.45)

	# Rectangles (2x3, 3x2)
	_register("rect_2x3", [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
		Vector2i(0, 2), Vector2i(1, 2),
	], 0.7)
	_register("rect_3x2", [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
	], 0.7)


static func _register(shape_id: String, shape_cells: Array[Vector2i], shape_weight: float) -> void:
	var def := ShapeDef.new(shape_id, shape_cells, shape_weight)
	_shapes.append(def)
	_shape_by_id[shape_id] = def
	_total_weight += shape_weight


static func get_shape_count() -> int:
	_ensure_initialized()
	return _shapes.size()


static func get_all_shape_ids() -> Array[String]:
	_ensure_initialized()
	var ids: Array[String] = []
	for def in _shapes:
		ids.append(def.id)
	return ids


static func get_shape_weight(shape_id: String) -> float:
	_ensure_initialized()
	if not _shape_by_id.has(shape_id):
		return 0.0
	var def: ShapeDef = _shape_by_id[shape_id]
	return def.weight


static func create_weighted_piece_from_ids(
	candidate_ids: Array[String],
	rng: RandomNumberGenerator = null
) -> Piece:
	_ensure_initialized()
	var eligible: Array[ShapeDef] = []
	var weight_sum := 0.0
	for shape_id in candidate_ids:
		if _shape_by_id.has(shape_id):
			var def: ShapeDef = _shape_by_id[shape_id]
			eligible.append(def)
			weight_sum += def.weight
	if eligible.is_empty():
		return create_random_piece(rng)

	var roll := (rng.randf() if rng != null else randf()) * weight_sum
	var accum := 0.0
	var picked: ShapeDef = eligible[eligible.size() - 1]
	for def in eligible:
		accum += def.weight
		if roll <= accum:
			picked = def
			break
	return Piece.new(picked.id, picked.cells, _pick_random_color(rng), SpecialType.NORMAL)


static func get_color(color_id: int) -> Color:
	return COLOR_PALETTE[clampi(color_id, 0, COLOR_COUNT - 1)]


static func get_color_name(color_id: int) -> String:
	return COLOR_NAMES[clampi(color_id, 0, COLOR_COUNT - 1)]


static func create_piece_by_id(
	shape_id: String,
	color_id: int = -1,
	rng: RandomNumberGenerator = null
) -> Piece:
	_ensure_initialized()
	assert(_shape_by_id.has(shape_id), "Unknown shape_id: " + shape_id)
	var def: ShapeDef = _shape_by_id[shape_id]
	var chosen_color := color_id
	if chosen_color < 0:
		chosen_color = _pick_random_color(rng)
	return Piece.new(def.id, def.cells, chosen_color, SpecialType.NORMAL)


static func create_random_piece(rng: RandomNumberGenerator = null, excluded_ids: Array[String] = []) -> Piece:
	_ensure_initialized()
	var eligible: Array[ShapeDef] = []
	var weight_sum := 0.0
	for def in _shapes:
		if not excluded_ids.has(def.id):
			eligible.append(def)
			weight_sum += def.weight
	if eligible.is_empty():
		eligible = _shapes
		weight_sum = _total_weight

	var roll := (rng.randf() if rng != null else randf()) * weight_sum
	var accum := 0.0
	var picked: ShapeDef = eligible[eligible.size() - 1]
	for def in eligible:
		accum += def.weight
		if roll <= accum:
			picked = def
			break
	return Piece.new(picked.id, picked.cells, _pick_random_color(rng), SpecialType.NORMAL)


static func create_custom_piece(
	shape_id: String,
	shape_cells: Array[Vector2i],
	color_id: int,
	special_type: int = SpecialType.NORMAL
) -> Piece:
	return Piece.new(shape_id, shape_cells, color_id, special_type)


static func create_bomb_piece() -> Piece:
	return Piece.new("special_bomb", [Vector2i.ZERO], 0, SpecialType.BOMB)


static func create_lightning_piece() -> Piece:
	return Piece.new("special_lightning", [Vector2i.ZERO], 5, SpecialType.LIGHTNING)


static func create_special_piece(special_type: int) -> Piece:
	if special_type == SpecialType.BOMB:
		return create_bomb_piece()
	if special_type == SpecialType.LIGHTNING:
		return create_lightning_piece()
	return create_piece_by_id("dot_1x1", 0)


static func _pick_random_color(rng: RandomNumberGenerator) -> int:
	if rng != null:
		return rng.randi_range(0, COLOR_COUNT - 1)
	return randi_range(0, COLOR_COUNT - 1)
