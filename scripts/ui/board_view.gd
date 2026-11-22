class_name BoardView
extends Control

## Portrait 8x8 puzzle board renderer with deep beveled frame, heat-reactive rim,
## GPU-batched pre-baked jewel blocks, landing spring animations, blazing line-clear
## anticipation glow + floating spark motes, special blast-zone reticles, and
## forgiving one-handed coordinate snapping.

const DEFAULT_RECT: Rect2 = Rect2(32.0, 192.0, 476.0, 476.0)
const GRID_SIZE: int = BoardState.GRID_SIZE
const FRAME_PADDING: float = 8.0
const SNAP_ASSIST_PX: float = 22.0
const LANDING_DURATION: float = 0.18
const LANDING_PEAK_RATIO: float = 0.55

# Frame palette tokens
const COL_SHADOW_DEEP: Color = Color("#080C22")
const COL_SHADOW_MID: Color = Color("#101633")
const COL_BEZEL_BODY: Color = Color("#172044")
const COL_BEZEL_TOP_BEVEL: Color = Color("#283876")
const COL_BEZEL_BOT_BEVEL: Color = Color("#0D132B")
const COL_WELL_BG: Color = Color("#0E142E")

const COL_RIM_CALM: Color = Color("#384C96")
const COL_RIM_COMBO: Color = Color("#24E8FF")
const COL_RIM_FEVER_A: Color = Color("#FF7A1F")
const COL_RIM_FEVER_B: Color = Color("#FFD642")

var board_state: BoardState = null:
	set(value):
		board_state = value
		queue_redraw()

var _time: float = 0.0

# Heat state (smoothly interpolated for silky Combo & FEVER frame transitions)
var _target_combo: int = 0
var _target_fever: bool = false
var _combo_heat: float = 0.0
var _fever_heat: float = 0.0
var _clear_flash: float = 0.0
var _clear_flash_color: Color = Color("#6CEEFF")

# Landing spring animations: Dictionary[Vector2i(col, row), float elapsed_sec]
var _landing_anims: Dictionary = {}

# Active drag preview state
var _preview_active: bool = false
var _preview_piece: PieceCatalog.Piece = null
var _preview_origin: Vector2i = Vector2i(-1, -1)
var _preview_placed_cells: Array[Vector2i] = []
var _preview_cleared_rows: Array[int] = []
var _preview_cleared_cols: Array[int] = []
var _preview_blast_zone: Array[Vector2i] = []
var _preview_hit_multipliers: Array[Dictionary] = []
var _preview_row_set: Dictionary = {}
var _preview_col_set: Dictionary = {}
var _preview_blast_set: Dictionary = {}

# Cached StyleBoxFlat instances (zero per-frame rounded-rect CPU triangulation!)
var _sb_ready: bool = false
var _sb_shadow_deep: StyleBoxFlat = null
var _sb_shadow_mid: StyleBoxFlat = null
var _sb_aura_outer: StyleBoxFlat = null
var _sb_aura_inner: StyleBoxFlat = null
var _sb_bezel: StyleBoxFlat = null
var _sb_bezel_inner: StyleBoxFlat = null
var _sb_well: StyleBoxFlat = null


func _init() -> void:
	position = DEFAULT_RECT.position
	size = DEFAULT_RECT.size
	custom_minimum_size = DEFAULT_RECT.size
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _ready() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		position = DEFAULT_RECT.position
		size = DEFAULT_RECT.size
	clip_contents = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ensure_styleboxes()
	TilePainter.warm_cache()
	queue_redraw()


var _shimmer_accum: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	var dirty: bool = false

	var target_combo_heat: float = 0.0
	if _target_combo >= 2:
		target_combo_heat = clampf(0.55 + float(_target_combo - 2) * 0.15, 0.55, 1.0)
	var target_fever_heat: float = 1.0 if _target_fever else 0.0

	var blend_step: float = 1.0 - exp(-7.5 * delta)
	if absf(_combo_heat - target_combo_heat) > 0.002:
		_combo_heat = lerpf(_combo_heat, target_combo_heat, blend_step)
		dirty = true
	else:
		_combo_heat = target_combo_heat

	if absf(_fever_heat - target_fever_heat) > 0.002:
		_fever_heat = lerpf(_fever_heat, target_fever_heat, blend_step)
		dirty = true
	else:
		_fever_heat = target_fever_heat

	if _clear_flash > 0.0:
		_clear_flash = maxf(0.0, _clear_flash - delta * 4.2)
		dirty = true

	if not _landing_anims.is_empty():
		dirty = true
		var expired: Array[Vector2i] = []
		for cell_key in _landing_anims.keys():
			var cell_pos: Vector2i = cell_key as Vector2i
			var next_t: float = float(_landing_anims[cell_pos]) + delta
			if next_t >= LANDING_DURATION:
				expired.append(cell_pos)
			else:
				_landing_anims[cell_pos] = next_t
		for cell_pos: Vector2i in expired:
			_landing_anims.erase(cell_pos)

	if _preview_active:
		dirty = true

	if dirty:
		queue_redraw()


## Binds the BoardState model and triggers an immediate redraw.
func set_board_state(p_board: BoardState) -> void:
	board_state = p_board
	queue_redraw()


## Forces a visual refresh of the board.
func refresh() -> void:
	queue_redraw()


## Smoothly transitions the board frame rim & aura across Calm, Combo Heat, and FEVER.
func set_heat_level(combo: int, fever: bool) -> void:
	_target_combo = maxi(0, combo)
	_target_fever = fever
	queue_redraw()


## Triggers a snappy 0.18s overshoot scale spring (0.72 -> 1.08 -> 1.0) on newly placed tiles.
func animate_placed_cells(cells: Array[Vector2i]) -> void:
	for cell_pos: Vector2i in cells:
		if cell_pos.x >= 0 and cell_pos.x < GRID_SIZE and cell_pos.y >= 0 and cell_pos.y < GRID_SIZE:
			_landing_anims[cell_pos] = 0.0
	queue_redraw()


## Optional luminous rim flash when lines clear or a special block detonates.
func trigger_clear_flash(intensity: float = 0.85, tint: Color = Color("#6CEEFF")) -> void:
	_clear_flash = clampf(maxf(_clear_flash, intensity), 0.0, 1.0)
	_clear_flash_color = tint
	queue_redraw()


## Updates the live drag ghost, line-clear anticipation glow, and special blast reticle.
## (Named set_placement_preview / update_drag_preview because Control already owns native set_drag_preview(Control).)
func set_placement_preview(piece: PieceCatalog.Piece, origin_cell: Vector2i, preview: Dictionary) -> void:
	if piece == null or preview.is_empty() or not bool(preview.get("valid", false)):
		clear_placement_preview()
		return

	_preview_active = true
	_preview_piece = piece
	_preview_origin = origin_cell

	_preview_placed_cells.clear()
	var raw_placed: Array = preview.get("placed_cells", []) as Array
	for item in raw_placed:
		if item is Vector2i:
			_preview_placed_cells.append(item as Vector2i)

	_preview_cleared_rows.clear()
	_preview_row_set.clear()
	var raw_rows: Array = preview.get("cleared_rows", []) as Array
	for r_val in raw_rows:
		var r_idx: int = int(r_val)
		_preview_cleared_rows.append(r_idx)
		_preview_row_set[r_idx] = true

	_preview_cleared_cols.clear()
	_preview_col_set.clear()
	var raw_cols: Array = preview.get("cleared_cols", []) as Array
	for c_val in raw_cols:
		var c_idx: int = int(c_val)
		_preview_cleared_cols.append(c_idx)
		_preview_col_set[c_idx] = true

	_preview_blast_zone.clear()
	_preview_blast_set.clear()
	var raw_blast: Array = preview.get("blast_zone_cells", []) as Array
	for b_item in raw_blast:
		if b_item is Vector2i:
			var b_pos: Vector2i = b_item as Vector2i
			_preview_blast_zone.append(b_pos)
			_preview_blast_set[b_pos] = true

	_preview_hit_multipliers.clear()
	var raw_mults: Array = preview.get("hit_multipliers", []) as Array
	for m_item in raw_mults:
		if m_item is Dictionary:
			_preview_hit_multipliers.append(m_item as Dictionary)

	queue_redraw()


## Alias for set_placement_preview.
func update_drag_preview(piece: PieceCatalog.Piece, origin_cell: Vector2i, preview: Dictionary) -> void:
	set_placement_preview(piece, origin_cell, preview)


## Clears any active ghost or anticipation preview.
func clear_placement_preview() -> void:
	if not _preview_active:
		return
	_preview_active = false
	_preview_piece = null
	_preview_origin = Vector2i(-1, -1)
	_preview_placed_cells.clear()
	_preview_cleared_rows.clear()
	_preview_cleared_cols.clear()
	_preview_blast_zone.clear()
	_preview_hit_multipliers.clear()
	_preview_row_set.clear()
	_preview_col_set.clear()
	_preview_blast_set.clear()
	queue_redraw()


## Alias for clear_placement_preview.
func clear_drag_preview() -> void:
	clear_placement_preview()


## Returns the 8x8 inner grid rectangle in local BoardView coordinates (Rect2(8, 8, 460, 460) at 476x476).
func get_board_inner_rect() -> Rect2:
	var inner_w: float = maxf(8.0, size.x - FRAME_PADDING * 2.0)
	var inner_h: float = maxf(8.0, size.y - FRAME_PADDING * 2.0)
	var side: float = minf(inner_w, inner_h)
	var offset_x: float = (size.x - side) * 0.5
	var offset_y: float = (size.y - side) * 0.5
	return Rect2(offset_x, offset_y, side, side)


## Returns the pixel size of a single grid cell (57.5px at 476x476).
func get_cell_size() -> float:
	return get_board_inner_rect().size.x / float(GRID_SIZE)


## Returns the local Rect2 of cell (row, col).
func get_cell_rect(row: int, col: int) -> Rect2:
	var inner: Rect2 = get_board_inner_rect()
	var cell_size: float = inner.size.x / float(GRID_SIZE)
	return Rect2(
		inner.position.x + float(col) * cell_size,
		inner.position.y + float(row) * cell_size,
		cell_size,
		cell_size
	)


## Returns the canvas/global center position of cell (row, col).
func get_cell_center_global(row: int, col: int) -> Vector2:
	var local_center: Vector2 = get_cell_rect(row, col).get_center()
	return get_global_transform() * local_center


## Maps a floating piece's global bounding center to the best BoardState origin cell Vector2i(col, row),
## with a forgiving 1-cell nearest-valid-snap assist within 22px so fingers never miss by a few pixels.
## Returns Vector2i(-1, -1) if no valid snap target is within range.
func global_pos_to_origin_cell(piece_center_global: Vector2, piece: PieceCatalog.Piece) -> Vector2i:
	if piece == null or piece.cells.is_empty():
		return Vector2i(-1, -1)

	var inner: Rect2 = get_board_inner_rect()
	var cell_size: float = inner.size.x / float(GRID_SIZE)
	if cell_size <= 1.0:
		return Vector2i(-1, -1)

	var local_center: Vector2 = get_global_transform().affine_inverse() * piece_center_global
	var half_w_cells: float = float(piece.width) * 0.5
	var half_h_cells: float = float(piece.height) * 0.5

	var col_f: float = (local_center.x - inner.position.x) / cell_size - half_w_cells
	var row_f: float = (local_center.y - inner.position.y) / cell_size - half_h_cells

	var base_col: int = int(round(col_f))
	var base_row: int = int(round(row_f))
	var raw_origin: Vector2i = Vector2i(base_col, base_row)

	# Direct hit on the nearest grid cell.
	if _is_origin_valid(piece, raw_origin):
		return raw_origin

	# Forgiving 1-cell nearest-valid-snap assist within SNAP_ASSIST_PX (22px) of candidate cell boundary.
	var half_cell: float = cell_size * 0.5
	var best_origin: Vector2i = Vector2i(-1, -1)
	var best_dist_sq: float = INF

	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var cand: Vector2i = Vector2i(base_col + dx, base_row + dy)
			if not _is_origin_valid(piece, cand):
				continue

			var cand_center: Vector2 = Vector2(
				inner.position.x + (float(cand.x) + half_w_cells) * cell_size,
				inner.position.y + (float(cand.y) + half_h_cells) * cell_size
			)
			var delta: Vector2 = local_center - cand_center
			var margin_x: float = maxf(0.0, absf(delta.x) - half_cell)
			var margin_y: float = maxf(0.0, absf(delta.y) - half_cell)
			var margin_dist: float = Vector2(margin_x, margin_y).length()

			if margin_dist <= SNAP_ASSIST_PX:
				var dist_sq: float = delta.length_squared()
				if dist_sq < best_dist_sq:
					best_dist_sq = dist_sq
					best_origin = cand

	return best_origin


# ==============================================================================
# CACHED STYLEBOXES
# ==============================================================================

func _ensure_styleboxes() -> void:
	if _sb_ready:
		return
	_sb_ready = true

	_sb_shadow_deep = _make_stylebox(Color(COL_SHADOW_DEEP.r, COL_SHADOW_DEEP.g, COL_SHADOW_DEEP.b, 0.44), 17, 0, Color.TRANSPARENT, true)
	_sb_shadow_mid = _make_stylebox(Color(COL_SHADOW_MID.r, COL_SHADOW_MID.g, COL_SHADOW_MID.b, 0.72), 14, 0, Color.TRANSPARENT, true)
	_sb_aura_outer = _make_stylebox(Color.TRANSPARENT, 18, 9, Color.TRANSPARENT, false)
	_sb_aura_inner = _make_stylebox(Color.TRANSPARENT, 15, 4, Color.TRANSPARENT, false)
	_sb_bezel = _make_stylebox(COL_BEZEL_BODY, 13, 2, COL_BEZEL_BOT_BEVEL, true)
	_sb_bezel_inner = _make_stylebox(Color.TRANSPARENT, 10, 2, COL_BEZEL_TOP_BEVEL, false)
	_sb_well = _make_stylebox(COL_WELL_BG, 5, 0, Color.TRANSPARENT, true)


func _make_stylebox(bg: Color, radius: int, border_w: int, border_col: Color, draw_center_flag: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.draw_center = draw_center_flag
	sb.corner_detail = 8
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 1.0
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_col
	return sb


# ==============================================================================
# RENDERING
# ==============================================================================

func _draw() -> void:
	_ensure_styleboxes()
	var outer_rect: Rect2 = Rect2(Vector2.ZERO, size)
	var inner_rect: Rect2 = get_board_inner_rect()
	var cell_size: float = inner_rect.size.x / float(GRID_SIZE)
	var pulse: float = 0.5 + 0.5 * sin(_time * 8.5)

	_draw_board_frame(outer_rect, inner_rect)
	_draw_grid_cells(inner_rect, cell_size, pulse)

	if _preview_active and _preview_piece != null:
		_draw_drag_preview(inner_rect, cell_size, pulse)

	if _clear_flash > 0.005:
		_draw_clear_flash_overlay(inner_rect)


func _draw_board_frame(outer_rect: Rect2, inner_rect: Rect2) -> void:
	var ci: RID = get_canvas_item()
	var outer_radius: float = 13.0
	var inner_radius: float = 5.0

	var fever_pulse: float = 0.5 + 0.5 * sin(_time * 6.5)
	var combo_pulse: float = 0.5 + 0.5 * sin(_time * 4.2)

	var fever_rim: Color = COL_RIM_FEVER_A.lerp(COL_RIM_FEVER_B, 0.35 + 0.45 * fever_pulse)
	var active_rim: Color = COL_RIM_CALM.lerp(COL_RIM_COMBO, _combo_heat * (0.85 + 0.15 * combo_pulse))
	active_rim = active_rim.lerp(fever_rim, _fever_heat)

	# 1. Layered deep midnight drop shadow anchoring the board above the swirling background.
	_sb_shadow_deep.draw(ci, Rect2(outer_rect.position + Vector2(0.0, 10.0), outer_rect.size).grow(4.0))
	_sb_shadow_mid.draw(ci, Rect2(outer_rect.position + Vector2(0.0, 5.0), outer_rect.size).grow(1.5))

	# 2. Heat-reactive outer aura bloom during Combo >= 2 or FEVER.
	var heat_power: float = maxf(_combo_heat * 0.75, _fever_heat)
	if heat_power > 0.02:
		var aura_col: Color = COL_RIM_COMBO.lerp(fever_rim, _fever_heat)
		var aura_pulse: float = 0.80 + 0.20 * (fever_pulse if _fever_heat > 0.3 else combo_pulse)
		_sb_aura_outer.border_color = Color(aura_col.r, aura_col.g, aura_col.b, 0.16 * heat_power * aura_pulse)
		_sb_aura_outer.draw(ci, outer_rect.grow(5.5))
		_sb_aura_inner.border_color = Color(aura_col.r, aura_col.g, aura_col.b, 0.34 * heat_power * aura_pulse)
		_sb_aura_inner.draw(ci, outer_rect.grow(2.2))

	# 3. Outer midnight beveled bezel body + outer rim.
	var bezel_body: Color = COL_BEZEL_BODY.lerp(Color("#1A2352"), _combo_heat * 0.35)
	bezel_body = bezel_body.lerp(Color("#2D1224"), _fever_heat * 0.65)
	var outer_edge: Color = COL_BEZEL_BOT_BEVEL.lerp(active_rim, 0.24 + 0.38 * heat_power)
	_sb_bezel.bg_color = bezel_body
	_sb_bezel.border_color = outer_edge
	_sb_bezel.draw(ci, outer_rect)

	# Crisp top-edge specular lip highlight across the upper bezel rim.
	var top_lip_col: Color = active_rim.lerp(Color.WHITE, 0.25 + 0.20 * heat_power)
	top_lip_col.a = 0.82 + 0.16 * heat_power
	draw_line(
		Vector2(outer_rect.position.x + outer_radius, outer_rect.position.y + 1.4),
		Vector2(outer_rect.end.x - outer_radius, outer_rect.position.y + 1.4),
		top_lip_col,
		2.0,
		true
	)

	# Subtle inner bezel bevel sheen.
	var top_bevel_tint: Color = COL_BEZEL_TOP_BEVEL.lerp(active_rim, 0.30 + 0.35 * heat_power)
	top_bevel_tint.a = 0.38
	_sb_bezel_inner.border_color = top_bevel_tint
	_sb_bezel_inner.draw(ci, outer_rect.grow(-2.6))

	# 4. Recessed dark cavity well framing the 8x8 grid.
	var well_outer: Rect2 = inner_rect.grow(2.2)
	_sb_well.draw(ci, well_outer)
	draw_rect(inner_rect, COL_WELL_BG, true)

	# Crisp inner top-edge rim catching overhead light (shifts calmly -> cyan -> molten orange-gold!).
	var rim_glow_alpha: float = 0.72 + 0.24 * heat_power
	var rim_top: Color = Color(active_rim.r, active_rim.g, active_rim.b, rim_glow_alpha)
	var rim_side: Color = Color(active_rim.r, active_rim.g, active_rim.b, 0.36 + 0.34 * heat_power)
	var rim_bot: Color = Color(active_rim.r, active_rim.g, active_rim.b, 0.22 + 0.28 * heat_power)

	draw_line(
		Vector2(well_outer.position.x + inner_radius, well_outer.position.y + 0.6),
		Vector2(well_outer.end.x - inner_radius, well_outer.position.y + 0.6),
		rim_top,
		2.0,
		true
	)
	draw_line(
		Vector2(well_outer.position.x + 0.6, well_outer.position.y + inner_radius),
		Vector2(well_outer.position.x + 0.6, well_outer.end.y - inner_radius),
		rim_side,
		1.4,
		true
	)
	draw_line(
		Vector2(well_outer.end.x - 0.6, well_outer.position.y + inner_radius),
		Vector2(well_outer.end.x - 0.6, well_outer.end.y - inner_radius),
		rim_side,
		1.4,
		true
	)
	draw_line(
		Vector2(well_outer.position.x + inner_radius, well_outer.end.y - 0.6),
		Vector2(well_outer.end.x - inner_radius, well_outer.end.y - 0.6),
		rim_bot,
		1.4,
		true
	)


func _draw_grid_cells(inner_rect: Rect2, cell_size: float, pulse: float) -> void:
	var has_board: bool = board_state != null
	var animating_cells: Array[Vector2i] = []

	# Pass 1: Draw recessed empty cells (skipping static opaque occupied cells to halve overdraw!).
	for row: int in range(GRID_SIZE):
		var y_pos: float = inner_rect.position.y + float(row) * cell_size
		for col: int in range(GRID_SIZE):
			var occupied: bool = has_board and board_state.is_occupied(col, row)
			var pos: Vector2i = Vector2i(col, row)
			var is_anim: bool = occupied and _landing_anims.has(pos)
			if occupied and not is_anim:
				continue
			var rect: Rect2 = Rect2(
				inner_rect.position.x + float(col) * cell_size,
				y_pos,
				cell_size,
				cell_size
			)
			var mult_value: int = 1
			if has_board and not occupied:
				mult_value = board_state.get_multiplier(col, row)
			TilePainter.draw_empty_cell(self, rect, row, col, mult_value, _time)

	if not has_board:
		return

	# Pass 2: Draw static occupied jewel blocks (ONE GPU quad each!) + occupied multiplier badges.
	for row: int in range(GRID_SIZE):
		var y_pos: float = inner_rect.position.y + float(row) * cell_size
		for col: int in range(GRID_SIZE):
			if not board_state.is_occupied(col, row):
				continue
			var pos: Vector2i = Vector2i(col, row)
			if _landing_anims.has(pos):
				animating_cells.append(pos)
				continue

			var rect: Rect2 = Rect2(
				inner_rect.position.x + float(col) * cell_size,
				y_pos,
				cell_size,
				cell_size
			)
			var color_id: int = board_state.get_color_id(col, row)
			var mult_value: int = board_state.get_multiplier(col, row)
			var target_type: int = board_state.get_target_type(col, row)
			var target_hp: int = board_state.get_target_hp(col, row)
			var boost: float = _compute_preview_block_boost(pos, pulse)

			TilePainter.draw_jewel_tile(self, rect, color_id, 1.0, 1.0, boost)
			if target_type != BoardState.TargetType.NONE:
				TilePainter.draw_target_overlay(self, rect, target_type, target_hp, _time)
			if mult_value >= 2:
				TilePainter.draw_occupied_mult_badge(self, rect, mult_value, _time)

	# Pass 3: Draw landing-spring animated blocks on top so 1.08x overshoot pops crisply!
	for pos: Vector2i in animating_cells:
		var elapsed: float = float(_landing_anims.get(pos, LANDING_DURATION))
		var spring_scale: float = _eval_landing_scale(elapsed)
		var u: float = clampf(elapsed / LANDING_DURATION, 0.0, 1.0)
		var land_flash: float = (1.0 - u) * 0.32

		var rect: Rect2 = Rect2(
			inner_rect.position.x + float(pos.x) * cell_size,
			inner_rect.position.y + float(pos.y) * cell_size,
			cell_size,
			cell_size
		)
		var color_id: int = board_state.get_color_id(pos.x, pos.y)
		var mult_value: int = board_state.get_multiplier(pos.x, pos.y)
		var target_type: int = board_state.get_target_type(pos.x, pos.y)
		var target_hp: int = board_state.get_target_hp(pos.x, pos.y)
		var boost: float = maxf(land_flash, _compute_preview_block_boost(pos, pulse))

		TilePainter.draw_jewel_tile(self, rect, color_id, 1.0, spring_scale, boost)
		if target_type != BoardState.TargetType.NONE:
			var t_scaled_size: Vector2 = rect.size * spring_scale
			var t_scaled_rect: Rect2 = Rect2(rect.get_center() - t_scaled_size * 0.5, t_scaled_size)
			TilePainter.draw_target_overlay(self, t_scaled_rect, target_type, target_hp, _time)
		if mult_value >= 2:
			var scaled_size: Vector2 = rect.size * spring_scale
			var scaled_rect: Rect2 = Rect2(rect.get_center() - scaled_size * 0.5, scaled_size)
			TilePainter.draw_occupied_mult_badge(self, scaled_rect, mult_value, _time)


func _draw_drag_preview(inner_rect: Rect2, cell_size: float, pulse: float) -> void:
	var piece_pal: Dictionary = TilePainter.get_palette(_preview_piece.color_id)
	var line_glow: Color = (piece_pal["glow"] as Color).lerp(Color("#FFD94A"), 0.45)
	var line_rim: Color = Color("#FFF7CC")

	if _preview_piece.special_type == PieceCatalog.SPECIAL_BOMB:
		line_glow = Color("#FF6A2E")
		line_rim = Color("#FFE2B0")
	elif _preview_piece.special_type == PieceCatalog.SPECIAL_LIGHTNING:
		line_glow = Color("#24ECFF")
		line_rim = Color("#EBFEFF")
	elif (_preview_cleared_rows.size() + _preview_cleared_cols.size()) >= 2:
		# Multi-line clear preview elevates with radiant golden-white brilliance!
		line_glow = line_glow.lerp(Color("#FFE259"), 0.55)
		line_rim = Color("#FFFCE0")

	# 1. Special blast zone reticle underneath ghost so Bomb / Lightning icon stays crystal-clear.
	if _preview_piece.special_type == PieceCatalog.SPECIAL_BOMB and not _preview_blast_zone.is_empty():
		_draw_bomb_blast_reticle(inner_rect, cell_size, pulse)
	elif _preview_piece.special_type == PieceCatalog.SPECIAL_LIGHTNING and not _preview_blast_zone.is_empty():
		_draw_lightning_blast_beams(inner_rect, cell_size, pulse)

	# 2. Crisp frosted-white translucent ghost cells (radiant gold when clearing!).
	var any_line_clear: bool = (not _preview_cleared_rows.is_empty()) or (not _preview_cleared_cols.is_empty())
	for pos: Vector2i in _preview_placed_cells:
		var cell_rect: Rect2 = Rect2(
			inner_rect.position.x + float(pos.x) * cell_size,
			inner_rect.position.y + float(pos.y) * cell_size,
			cell_size,
			cell_size
		)
		var will_clear: bool = (
			_preview_row_set.has(pos.y)
			or _preview_col_set.has(pos.x)
			or _preview_piece.is_special()
		)
		TilePainter.draw_ghost_cell(
			self,
			cell_rect,
			_preview_piece.color_id,
			will_clear,
			_preview_piece.special_type,
			_time
		)

		# Keep underlying x2/x3 multiplier tiles brightly illuminated & readable RIGHT THROUGH the ghost!
		if board_state != null:
			var under_mult: int = board_state.get_multiplier(pos.x, pos.y)
			if under_mult >= 2:
				TilePainter.draw_ghost_mult_passthrough(self, cell_rect, under_mult, _time)

	# 3. Blazing full-row / full-column anticipation glow + pulsing outer frame + drifting gold sparks!
	if any_line_clear:
		for r: int in _preview_cleared_rows:
			var row_rect: Rect2 = Rect2(
				inner_rect.position.x,
				inner_rect.position.y + float(r) * cell_size,
				inner_rect.size.x,
				cell_size
			)
			_draw_line_clear_strip(row_rect, true, line_glow, line_rim, pulse, r)

		for c: int in _preview_cleared_cols:
			var col_rect: Rect2 = Rect2(
				inner_rect.position.x + float(c) * cell_size,
				inner_rect.position.y,
				cell_size,
				inner_rect.size.y
			)
			_draw_line_clear_strip(col_rect, false, line_glow, line_rim, pulse, c + 16)

		# Incandescent starburst diamond glint at row x col clear intersections!
		var glow_tex: ImageTexture = TilePainter.get_soft_glow_texture()
		for r: int in _preview_cleared_rows:
			for c: int in _preview_cleared_cols:
				var center: Vector2 = get_cell_rect(r, c).get_center()
				var star_r: float = cell_size * (0.30 + 0.08 * pulse)
				var bloom_s: float = cell_size * 1.45
				draw_texture_rect(
					glow_tex,
					Rect2(center - Vector2(bloom_s, bloom_s) * 0.5, Vector2(bloom_s, bloom_s)),
					false,
					Color(line_glow.r, line_glow.g, line_glow.b, 0.55 + 0.24 * pulse)
				)
				_draw_four_point_star(center, star_r, star_r * 0.28, Color(1.0, 1.0, 0.96, 0.95))

	# 4. Highlight any x2/x3 multiplier tiles about to be triggered (soft frameless glow)!
	var mult_glow_tex: ImageTexture = TilePainter.get_soft_glow_texture()
	for m_entry: Dictionary in _preview_hit_multipliers:
		var m_pos: Vector2i = m_entry.get("cell", Vector2i(-1, -1)) as Vector2i
		if m_pos.x < 0 or m_pos.y < 0:
			continue
		var m_val: int = int(m_entry.get("value", 2))
		var m_center: Vector2 = get_cell_rect(m_pos.y, m_pos.x).get_center()
		var ring_col: Color = Color("#FF6BE8") if m_val >= 3 else Color("#40F0FF")
		var bloom_sz: float = cell_size * (1.15 + 0.15 * pulse)
		draw_texture_rect(
			mult_glow_tex,
			Rect2(m_center - Vector2(bloom_sz, bloom_sz) * 0.5, Vector2(bloom_sz, bloom_sz)),
			false,
			Color(ring_col.r, ring_col.g, ring_col.b, 0.38 + 0.22 * pulse)
		)


func _draw_line_clear_strip(
	strip_rect: Rect2,
	is_horizontal: bool,
	glow_col: Color,
	rim_col: Color,
	pulse: float,
	line_seed: int
) -> void:
	var glow_tex: ImageTexture = TilePainter.get_soft_glow_texture()

	# 1. Soft GPU radial golden aura blooms spilling gently off the clearing line.
	var span_steps: int = 4
	for k: int in range(span_steps):
		var frac: float = (float(k) + 0.5) / float(span_steps)
		var pt: Vector2 = Vector2(
			lerpf(strip_rect.position.x, strip_rect.end.x, frac) if is_horizontal else strip_rect.get_center().x,
			strip_rect.get_center().y if is_horizontal else lerpf(strip_rect.position.y, strip_rect.end.y, frac)
		)
		var bloom_w: float = strip_rect.size.x * 0.42 if is_horizontal else strip_rect.size.x * 2.1
		var bloom_h: float = strip_rect.size.y * 2.1 if is_horizontal else strip_rect.size.y * 0.42
		draw_texture_rect(
			glow_tex,
			Rect2(pt - Vector2(bloom_w, bloom_h) * 0.5, Vector2(bloom_w, bloom_h)),
			false,
			Color(glow_col.r, glow_col.g, glow_col.b, 0.24 + 0.14 * pulse)
		)

	# 2. Radiant luminous golden/piece-color glow wash over every cell in the line.
	var wash_col: Color = Color(glow_col.r, glow_col.g, glow_col.b, 0.24 + 0.14 * pulse)
	draw_rect(strip_rect, wash_col, true)

	# 3. Travelling high-energy white-gold specular sweep along the imminent clear strip.
	var sweep_t: float = fmod(_time * 1.65 + float(line_seed) * 0.17, 1.0)
	var band_col_mid: Color = Color(rim_col.r, rim_col.g, rim_col.b, 0.40 + 0.18 * pulse)
	var band_col_edge: Color = Color(rim_col.r, rim_col.g, rim_col.b, 0.0)
	if is_horizontal:
		var bw: float = strip_rect.size.x * 0.30
		var cx: float = lerpf(strip_rect.position.x - bw, strip_rect.end.x + bw, sweep_t)
		var x0: float = clampf(cx - bw * 0.5, strip_rect.position.x, strip_rect.end.x)
		var xm: float = clampf(cx, strip_rect.position.x, strip_rect.end.x)
		var x1: float = clampf(cx + bw * 0.5, strip_rect.position.x, strip_rect.end.x)
		if xm > x0 + 0.5:
			draw_polygon(
				PackedVector2Array([
					Vector2(x0, strip_rect.position.y),
					Vector2(xm, strip_rect.position.y),
					Vector2(xm, strip_rect.end.y),
					Vector2(x0, strip_rect.end.y),
				]),
				PackedColorArray([band_col_edge, band_col_mid, band_col_mid, band_col_edge])
			)
		if x1 > xm + 0.5:
			draw_polygon(
				PackedVector2Array([
					Vector2(xm, strip_rect.position.y),
					Vector2(x1, strip_rect.position.y),
					Vector2(x1, strip_rect.end.y),
					Vector2(xm, strip_rect.end.y),
				]),
				PackedColorArray([band_col_mid, band_col_edge, band_col_edge, band_col_mid])
			)
	else:
		var bh: float = strip_rect.size.y * 0.30
		var cy: float = lerpf(strip_rect.position.y - bh, strip_rect.end.y + bh, sweep_t)
		var y0: float = clampf(cy - bh * 0.5, strip_rect.position.y, strip_rect.end.y)
		var ym: float = clampf(cy, strip_rect.position.y, strip_rect.end.y)
		var y1: float = clampf(cy + bh * 0.5, strip_rect.position.y, strip_rect.end.y)
		if ym > y0 + 0.5:
			draw_polygon(
				PackedVector2Array([
					Vector2(strip_rect.position.x, y0),
					Vector2(strip_rect.end.x, y0),
					Vector2(strip_rect.end.x, ym),
					Vector2(strip_rect.position.x, ym),
				]),
				PackedColorArray([band_col_edge, band_col_edge, band_col_mid, band_col_mid])
			)
		if y1 > ym + 0.5:
			draw_polygon(
				PackedVector2Array([
					Vector2(strip_rect.position.x, ym),
					Vector2(strip_rect.end.x, ym),
					Vector2(strip_rect.end.x, y1),
					Vector2(strip_rect.position.x, y1),
				]),
				PackedColorArray([band_col_mid, band_col_mid, band_col_edge, band_col_edge])
			)

	# 4. Pulsing blazing triple-layered luminous outer frame wrapping the entire row/col.
	var outer_bloom: Color = Color(glow_col.r, glow_col.g, glow_col.b, 0.50 + 0.32 * pulse)
	var mid_stroke: Color = Color(glow_col.r, glow_col.g, glow_col.b, 0.90 + 0.10 * pulse)
	var hot_inner: Color = rim_col.lerp(Color.WHITE, 0.58 + 0.34 * pulse)
	hot_inner.a = 0.98

	draw_rect(strip_rect.grow(1.6), outer_bloom, false, 6.2, true)
	draw_rect(strip_rect.grow(-0.4), mid_stroke, false, 3.0, true)
	draw_rect(strip_rect.grow(-1.6), hot_inner, false, 1.7, true)

	# 5. Floating anticipation golden spark motes drifting off the clearing row/column!
	_draw_line_clear_sparks(strip_rect, is_horizontal, glow_col, line_seed)


func _draw_line_clear_sparks(
	strip_rect: Rect2,
	is_horizontal: bool,
	glow_col: Color,
	line_seed: int
) -> void:
	var glow_tex: ImageTexture = TilePainter.get_soft_glow_texture()
	const SPARK_COUNT: int = 9
	for i: int in range(SPARK_COUNT):
		var seed_f: float = float(line_seed * 19 + i * 31)
		var life: float = fmod(_time * (0.72 + 0.18 * fmod(seed_f * 0.37, 1.0)) + float(i) / float(SPARK_COUNT), 1.0)
		var env: float = sin(life * PI)
		if env <= 0.04:
			continue

		var along: float = fmod(0.06 + float(i) * 0.113 + sin(seed_f) * 0.04, 0.92) + 0.04
		var side_sign: float = -1.0 if ((i + line_seed) & 1) == 0 else 1.0
		var drift_dist: float = lerpf(4.0, 26.0, life)
		var sway: float = sin(_time * 4.2 + seed_f) * 4.5

		var pos: Vector2
		if is_horizontal:
			var edge_y: float = strip_rect.position.y if side_sign < 0.0 else strip_rect.end.y
			pos = Vector2(
				lerpf(strip_rect.position.x, strip_rect.end.x, along) + sway,
				edge_y + side_sign * drift_dist
			)
		else:
			var edge_x: float = strip_rect.position.x if side_sign < 0.0 else strip_rect.end.x
			pos = Vector2(
				edge_x + side_sign * drift_dist,
				lerpf(strip_rect.position.y, strip_rect.end.y, along) + sway
			)

		var rad: float = lerpf(2.2, 4.2, env) * (0.82 if (i & 1) == 0 else 1.12)
		var halo_s: float = rad * 4.4
		draw_texture_rect(
			glow_tex,
			Rect2(pos - Vector2(halo_s, halo_s) * 0.5, Vector2(halo_s, halo_s)),
			false,
			Color(glow_col.r, glow_col.g, glow_col.b, 0.52 * env)
		)

		var core_col: Color = Color(1.0, 0.96, 0.72, 0.94 * env) if (i % 3 != 0) else Color(1.0, 1.0, 1.0, 0.98 * env)
		if (i % 3) == 0:
			_draw_four_point_star(pos, rad * 1.35, rad * 0.36, core_col)
		else:
			draw_colored_polygon(
				PackedVector2Array([
					pos + Vector2(0.0, -rad),
					pos + Vector2(rad, 0.0),
					pos + Vector2(0.0, rad),
					pos + Vector2(-rad, 0.0),
				]),
				core_col
			)


func _draw_bomb_blast_reticle(inner_rect: Rect2, cell_size: float, pulse: float) -> void:
	var min_x: int = GRID_SIZE
	var min_y: int = GRID_SIZE
	var max_x: int = -1
	var max_y: int = -1

	for pos: Vector2i in _preview_blast_zone:
		min_x = mini(min_x, pos.x)
		min_y = mini(min_y, pos.y)
		max_x = maxi(max_x, pos.x)
		max_y = maxi(max_y, pos.y)

		var c_rect: Rect2 = Rect2(
			inner_rect.position.x + float(pos.x) * cell_size,
			inner_rect.position.y + float(pos.y) * cell_size,
			cell_size,
			cell_size
		)
		var is_target_block: bool = board_state != null and board_state.is_occupied(pos.x, pos.y)
		var fill_alpha: float = (0.30 + 0.14 * pulse) if is_target_block else (0.16 + 0.08 * pulse)
		draw_rect(c_rect.grow(-1.5), Color(1.0, 0.30, 0.14, fill_alpha), true)
		draw_rect(c_rect.grow(-2.2), Color(1.0, 0.62, 0.22, 0.35 + 0.22 * pulse), false, 1.3, true)

	if max_x < min_x or max_y < min_y:
		return

	var zone_rect: Rect2 = Rect2(
		inner_rect.position.x + float(min_x) * cell_size,
		inner_rect.position.y + float(min_y) * cell_size,
		float(max_x - min_x + 1) * cell_size,
		float(max_y - min_y + 1) * cell_size
	)

	var outer_glow: Color = Color(1.0, 0.32, 0.14, 0.45 + 0.30 * pulse)
	var hot_amber: Color = Color(1.0, 0.78, 0.30, 0.88 + 0.12 * pulse)
	draw_rect(zone_rect.grow(1.0), outer_glow, false, 4.4, true)
	draw_rect(zone_rect.grow(-0.8), Color(1.0, 0.46, 0.18, 0.85), false, 2.0, true)

	var brk: float = minf(16.0, cell_size * 0.30)
	var zr: Rect2 = zone_rect.grow(1.5)
	_draw_corner_brackets(zr, brk, hot_amber, 2.8)

	var origin_center: Vector2 = get_cell_rect(_preview_origin.y, _preview_origin.x).get_center()
	draw_circle(
		origin_center,
		cell_size * (0.44 + 0.05 * pulse),
		Color(1.0, 0.68, 0.22, 0.65 + 0.25 * pulse),
		false,
		2.0,
		true
	)


func _draw_lightning_blast_beams(inner_rect: Rect2, cell_size: float, pulse: float) -> void:
	var row_rect: Rect2 = Rect2(
		inner_rect.position.x,
		inner_rect.position.y + float(_preview_origin.y) * cell_size,
		inner_rect.size.x,
		cell_size
	)
	var col_rect: Rect2 = Rect2(
		inner_rect.position.x + float(_preview_origin.x) * cell_size,
		inner_rect.position.y,
		cell_size,
		inner_rect.size.y
	)

	var beam_fill: Color = Color(0.10, 0.84, 1.0, 0.18 + 0.11 * pulse)
	var rail_glow: Color = Color(0.14, 0.90, 1.0, 0.48 + 0.28 * pulse)
	var rail_hot: Color = Color(0.86, 0.99, 1.0, 0.90)

	draw_rect(row_rect, beam_fill, true)
	draw_rect(col_rect, beam_fill, true)

	draw_rect(row_rect.grow(0.8), rail_glow, false, 4.0, true)
	draw_rect(col_rect.grow(0.8), rail_glow, false, 4.0, true)
	draw_rect(row_rect.grow(-1.0), rail_hot, false, 1.5, true)
	draw_rect(col_rect.grow(-1.0), rail_hot, false, 1.5, true)

	var step_seed: int = int(floor(_time * 16.0))
	var row_y: float = row_rect.get_center().y
	var col_x: float = col_rect.get_center().x

	_draw_jagged_beam(
		Vector2(row_rect.position.x + 4.0, row_y),
		Vector2(row_rect.end.x - 4.0, row_y),
		step_seed + 13,
		cell_size * 0.14,
		Color(0.20, 0.92, 1.0, 0.65),
		3.8
	)
	_draw_jagged_beam(
		Vector2(row_rect.position.x + 4.0, row_y),
		Vector2(row_rect.end.x - 4.0, row_y),
		step_seed + 13,
		cell_size * 0.14,
		Color(0.95, 1.0, 1.0, 0.92),
		1.6
	)

	_draw_jagged_beam(
		Vector2(col_x, col_rect.position.y + 4.0),
		Vector2(col_x, col_rect.end.y - 4.0),
		step_seed + 37,
		cell_size * 0.14,
		Color(0.20, 0.92, 1.0, 0.65),
		3.8
	)
	_draw_jagged_beam(
		Vector2(col_x, col_rect.position.y + 4.0),
		Vector2(col_x, col_rect.end.y - 4.0),
		step_seed + 37,
		cell_size * 0.14,
		Color(0.95, 1.0, 1.0, 0.92),
		1.6
	)

	var core: Vector2 = Vector2(col_x, row_y)
	var glow_tex: ImageTexture = TilePainter.get_soft_glow_texture()
	var halo_s: float = cell_size * 1.4
	draw_texture_rect(
		glow_tex,
		Rect2(core - Vector2(halo_s, halo_s) * 0.5, Vector2(halo_s, halo_s)),
		false,
		Color(0.24, 0.95, 1.0, 0.42 + 0.22 * pulse)
	)
	draw_circle(core, cell_size * 0.44, Color(0.92, 1.0, 1.0, 0.85), false, 2.0, true)


func _draw_clear_flash_overlay(inner_rect: Rect2) -> void:
	var alpha: float = _clear_flash * 0.42
	draw_rect(
		inner_rect.grow(1.5),
		Color(_clear_flash_color.r, _clear_flash_color.g, _clear_flash_color.b, alpha),
		false,
		4.5,
		true
	)


# ==============================================================================
# INTERNAL HELPERS
# ==============================================================================

func _is_origin_valid(piece: PieceCatalog.Piece, origin: Vector2i) -> bool:
	if origin.x < 0 or origin.y < 0:
		return false
	if origin.x + piece.width > GRID_SIZE or origin.y + piece.height > GRID_SIZE:
		return false
	if board_state != null:
		return board_state.can_place_piece(piece, origin)
	return true


func _compute_preview_block_boost(pos: Vector2i, pulse: float) -> float:
	if not _preview_active:
		return 0.0
	if _preview_row_set.has(pos.y) or _preview_col_set.has(pos.x):
		return 0.46 + 0.16 * pulse
	if _preview_blast_set.has(pos):
		return 0.30 + 0.10 * pulse
	return 0.0


func _eval_landing_scale(elapsed: float) -> float:
	var u: float = clampf(elapsed / LANDING_DURATION, 0.0, 1.0)
	if u <= LANDING_PEAK_RATIO:
		var t1: float = u / LANDING_PEAK_RATIO
		var eased: float = 1.0 - pow(1.0 - t1, 3.0)
		return lerpf(0.72, 1.08, eased)
	var t2: float = (u - LANDING_PEAK_RATIO) / (1.0 - LANDING_PEAK_RATIO)
	var settle: float = 0.5 - 0.5 * cos(t2 * PI)
	return lerpf(1.08, 1.0, settle)


func _draw_corner_brackets(r: Rect2, arm: float, col: Color, width: float) -> void:
	var x0: float = r.position.x
	var y0: float = r.position.y
	var x1: float = r.end.x
	var y1: float = r.end.y
	draw_line(Vector2(x0, y0 + arm), Vector2(x0, y0), col, width, true)
	draw_line(Vector2(x0, y0), Vector2(x0 + arm, y0), col, width, true)
	draw_line(Vector2(x1 - arm, y0), Vector2(x1, y0), col, width, true)
	draw_line(Vector2(x1, y0), Vector2(x1, y0 + arm), col, width, true)
	draw_line(Vector2(x1, y1 - arm), Vector2(x1, y1), col, width, true)
	draw_line(Vector2(x1, y1), Vector2(x1 - arm, y1), col, width, true)
	draw_line(Vector2(x0 + arm, y1), Vector2(x0, y1), col, width, true)
	draw_line(Vector2(x0, y1), Vector2(x0, y1 - arm), col, width, true)


func _draw_jagged_beam(
	a: Vector2,
	b: Vector2,
	seed_val: int,
	amp: float,
	col: Color,
	width: float
) -> void:
	var dir: Vector2 = b - a
	var seg_len: float = dir.length()
	if seg_len <= 2.0:
		return
	var normal: Vector2 = Vector2(-dir.y, dir.x) / seg_len
	var segments: int = 12
	var pts: PackedVector2Array = PackedVector2Array([a])
	for i: int in range(1, segments):
		var t: float = float(i) / float(segments)
		var jitter: float = sin(float(seed_val * 53 + i * 97) * 1.6180339)
		var envelope: float = sin(t * PI)
		pts.append(a.lerp(b, t) + normal * (jitter * amp * (0.35 + 0.65 * envelope)))
	pts.append(b)
	draw_polyline(pts, col, width, true)


func _draw_four_point_star(center: Vector2, outer_r: float, inner_r: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(8):
		var angle: float = float(i) * (PI * 0.25)
		var rad: float = outer_r if (i & 1) == 0 else inner_r
		pts.append(center + Vector2(cos(angle), sin(angle)) * rad)
	draw_colored_polygon(pts, col)
