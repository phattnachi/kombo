class_name TrayAndHoldView
extends Control

## One-handed bottom thumb-zone controller for Kombo:
## - Top row: 3 recessed dark-glass piece slots with grounded shadows, pop-in deal springs,
##   dramatic special-award starbursts, and unplayable board-danger dimming.
## - Bottom row: Centered beveled HOLD vault dock with pill tab, swap badge, hover glow,
##   and per-turn lock feedback (still allowing dragging the held piece to the board).
## - Fluid mouse + touch drag controller with -76px thumb lift, full 1.0x board-scale float,
##   grounded shadow, velocity-driven Balatro sway tilt, and programmatic screenshot staging.

signal drag_started(source_type: String, slot_idx: int, piece: PieceCatalog.Piece)
signal drag_moved(global_pos: Vector2, source_type: String, slot_idx: int, piece: PieceCatalog.Piece)
signal drag_dropped_on_board(source_type: String, slot_idx: int, origin_cell: Vector2i)
signal drag_dropped_on_hold(slot_idx: int)
signal drag_cancelled()
signal hold_tapped()
signal skill_pressed(skill_id: String)

const DEFAULT_RECT: Rect2 = Rect2(0.0, 680.0, 540.0, 268.0)
const TRAY_SIZE: int = GameController.TRAY_SIZE

# Layout metrics (relative to TrayAndHoldView top-left at (0, 680))
const SLOT_WIDTH: float = 156.0
const SLOT_HEIGHT: float = 136.0
const SLOT_Y: float = 2.0
const SLOT_LEFT_MARGIN: float = 24.0
const SLOT_GAP: float = 12.0

const HOLD_RECT: Rect2 = Rect2(24.0, 148.0, 140.0, 78.0)
const HOLD_HIT_GROW: float = 14.0

const SKILL_BUTTON_SPECS: Array[Dictionary] = [
	{
		"id": "reroll",
		"label": "REROLL",
		"cost": GameController.SKILL_REROLL_COST,
		"cost_short": "3K",
		"rect": Rect2(174.0, 148.0, 108.0, 78.0),
		"accent": Color("#2EEB98"),
		"bg": Color("#0F3132"),
	},
	{
		"id": "bomb",
		"label": "BOMB",
		"cost": GameController.SKILL_BOMB_COST,
		"cost_short": "6K",
		"rect": Rect2(291.0, 148.0, 108.0, 78.0),
		"accent": Color("#FF8A2B"),
		"bg": Color("#38191D"),
	},
	{
		"id": "lightning",
		"label": "ZAP +",
		"cost": GameController.SKILL_LIGHTNING_COST,
		"cost_short": "12K",
		"rect": Rect2(408.0, 148.0, 108.0, 78.0),
		"accent": Color("#24E8FF"),
		"bg": Color("#122652"),
	},
]

# Drag & feel tuning
const DEFAULT_BOARD_CELL_SIZE: float = 57.5
const LIFT_OFFSET_Y: float = 86.0
const MAX_SWAY_RADIANS: float = 0.14
const SWAY_VEL_FACTOR: float = 0.0012
const TAP_MAX_DIST: float = 12.0
const TAP_MAX_TIME: float = 0.24

# Animation durations
const REFILL_STAGGER: float = 0.06
const REFILL_DURATION: float = 0.24
const SPECIAL_AWARD_DURATION: float = 0.42
const RETURN_ANIM_DURATION: float = 0.13

# Visual palette tokens
const COL_SLOT_FILL: Color = Color(0.078, 0.110, 0.239, 0.55) # #141C3D @ 55%
const COL_SLOT_BORDER: Color = Color(0.255, 0.349, 0.659, 0.46)
const COL_SLOT_TOP_RIM: Color = Color(0.451, 0.580, 0.941, 0.42)
const COL_SLOT_SHADOW: Color = Color(0.031, 0.047, 0.125, 0.52)

const COL_HOLD_OUTER: Color = Color("#121A3B")
const COL_HOLD_WELL: Color = Color("#18224A")
const COL_HOLD_BORDER: Color = Color("#3A4F9C")
const COL_HOLD_CYAN: Color = Color("#24E8FF")
const COL_HOLD_GOLD: Color = Color("#FFD642")
const COL_HOLD_LOCKED: Color = Color("#5A6488")

var board_view: BoardView = null

var _tray_pieces: Array[PieceCatalog.Piece] = [null, null, null]
var _slot_playable: Array[bool] = [true, true, true]
var _hold_piece: PieceCatalog.Piece = null
var _hold_used_this_turn: bool = false
var _hold_playable: bool = true
var _wallet_coins: int = 0
var _skill_flash_timers: Array[float] = [0.0, 0.0, 0.0]
var _input_enabled: bool = true

var _time: float = 0.0
var _heat_combo: float = 0.0
var _heat_fever: float = 0.0
var _target_combo: int = 0
var _target_fever: bool = false

# Slot entrance & special-award animation timers (-1.0 = inactive)
var _refill_timers: Array[float] = [-1.0, -1.0, -1.0]
var _special_award_timers: Array[float] = [-1.0, -1.0, -1.0]

# Hold Dock interactive visual polish
var _hold_hover_blend: float = 0.0
var _hold_tap_pulse: float = 0.0

# Active drag state
var _is_dragging: bool = false
var _programmatic_drag: bool = false
var _active_pointer_id: int = -1 # -1 none, -2 mouse, >= 0 touch finger index
var _drag_source_type: String = "" # "tray" or "hold"
var _drag_slot_idx: int = -1
var _drag_piece: PieceCatalog.Piece = null
var _drag_press_global: Vector2 = Vector2.ZERO
var _drag_press_time: float = 0.0
var _drag_pointer_global: Vector2 = Vector2.ZERO
var _drag_prev_pointer_x: float = 0.0
var _drag_vel_x: float = 0.0
var _drag_tilt: float = 0.0
var _drag_lift_current: float = 0.0
var _drag_scale_current: float = 0.5
var _drag_hovering_hold: bool = false

# Empty-Hold tap tracking
var _pending_empty_hold_tap: bool = false
var _pending_tap_pointer_id: int = -1
var _pending_tap_start_global: Vector2 = Vector2.ZERO
var _pending_tap_start_time: float = 0.0

# Smooth snap-back visual return animation after cancelled drag
var _return_active: bool = false
var _return_piece: PieceCatalog.Piece = null
var _return_source_type: String = ""
var _return_slot_idx: int = -1
var _return_from_global: Vector2 = Vector2.ZERO
var _return_to_global: Vector2 = Vector2.ZERO
var _return_from_scale: float = 1.0
var _return_to_scale: float = 0.55
var _return_from_tilt: float = 0.0
var _return_elapsed: float = 0.0

# High-Z overlay child so floating dragged piece always renders above BoardView
var _drag_overlay: Control = null

# Cached StyleBoxFlat & smooth radial glow resources (60+ FPS zero CPU polygon triangulation)
var _sb_ready: bool = false
var _sb_hold_shadow: StyleBoxFlat = null
var _sb_hold_outer: StyleBoxFlat = null
var _sb_hold_inner: StyleBoxFlat = null
var _sb_hold_glow: StyleBoxFlat = null
var _sb_hold_tag: StyleBoxFlat = null
var _sb_hold_cue: StyleBoxFlat = null
var _radial_glow_tex: GradientTexture2D = null


func _ensure_cached_styles() -> void:
	if _sb_ready:
		return
	_sb_ready = true

	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.48, 0.75, 0.94, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.65),
		Color(1.0, 1.0, 1.0, 0.26),
		Color(1.0, 1.0, 1.0, 0.06),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	_radial_glow_tex = GradientTexture2D.new()
	_radial_glow_tex.width = 96
	_radial_glow_tex.height = 96
	_radial_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_radial_glow_tex.fill_from = Vector2(0.5, 0.5)
	_radial_glow_tex.fill_to = Vector2(1.0, 0.5)
	_radial_glow_tex.gradient = grad

	_sb_hold_shadow = StyleBoxFlat.new()
	_sb_hold_shadow.bg_color = Color(0.015, 0.025, 0.09, 0.52)
	_sb_hold_shadow.set_corner_radius_all(20)
	_sb_hold_shadow.corner_detail = 8

	_sb_hold_outer = StyleBoxFlat.new()
	_sb_hold_outer.bg_color = Color(0.059, 0.086, 0.204, 0.72)
	_sb_hold_outer.set_corner_radius_all(20)
	_sb_hold_outer.corner_detail = 8
	_sb_hold_outer.set_border_width_all(2)
	_sb_hold_outer.border_color = Color(0.36, 0.68, 0.96, 0.52)

	_sb_hold_inner = StyleBoxFlat.new()
	_sb_hold_inner.bg_color = Color(0.075, 0.115, 0.265, 0.58)
	_sb_hold_inner.set_corner_radius_all(16)
	_sb_hold_inner.corner_detail = 8

	_sb_hold_glow = StyleBoxFlat.new()
	_sb_hold_glow.draw_center = false
	_sb_hold_glow.set_corner_radius_all(24)
	_sb_hold_glow.corner_detail = 8
	_sb_hold_glow.set_border_width_all(4)

	_sb_hold_tag = StyleBoxFlat.new()
	_sb_hold_tag.bg_color = Color(0.09, 0.16, 0.36, 0.88)
	_sb_hold_tag.set_corner_radius_all(8)
	_sb_hold_tag.corner_detail = 6
	_sb_hold_tag.set_border_width_all(1)

	_sb_hold_cue = StyleBoxFlat.new()
	_sb_hold_cue.set_corner_radius_all(8)
	_sb_hold_cue.corner_detail = 6
	_sb_hold_cue.set_border_width_all(2)


func _draw_soft_glow(ci: CanvasItem, center: Vector2, half_size: Vector2, tint: Color) -> void:
	if _radial_glow_tex == null or tint.a <= 0.002:
		return
	ci.draw_texture_rect(_radial_glow_tex, Rect2(center - half_size, half_size * 2.0), false, tint)


func _init() -> void:
	position = DEFAULT_RECT.position
	size = DEFAULT_RECT.size
	custom_minimum_size = DEFAULT_RECT.size
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		position = DEFAULT_RECT.position
		size = DEFAULT_RECT.size
	clip_contents = false
	mouse_filter = Control.MOUSE_FILTER_PASS

	_drag_overlay = Control.new()
	_drag_overlay.name = "DragOverlay"
	_drag_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_overlay.clip_contents = false
	_drag_overlay.z_index = 50
	_drag_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_drag_overlay.position = Vector2.ZERO
	_drag_overlay.size = size
	_drag_overlay.draw.connect(_on_drag_overlay_draw)
	add_child(_drag_overlay)

	queue_redraw()


var _idle_shimmer_accum: float = 0.0


func _has_special_piece_in_tray_or_hold() -> bool:
	if _hold_piece != null and _hold_piece.is_special():
		return true
	for i: int in range(TRAY_SIZE):
		if _tray_pieces[i] != null and _tray_pieces[i].is_special():
			return true
	return false


func _process(delta: float) -> void:
	_time += delta
	var dirty: bool = false
	var overlay_dirty: bool = false

	# Smooth heat tint blending
	var target_combo_heat: float = clampf(0.5 + float(_target_combo - 2) * 0.2, 0.0, 1.0) if _target_combo >= 2 else 0.0
	var target_fever_heat: float = 1.0 if _target_fever else 0.0
	var heat_step: float = 1.0 - exp(-7.0 * delta)
	if absf(_heat_combo - target_combo_heat) > 0.002:
		_heat_combo = lerpf(_heat_combo, target_combo_heat, heat_step)
		dirty = true
	else:
		_heat_combo = target_combo_heat
	if absf(_heat_fever - target_fever_heat) > 0.002:
		_heat_fever = lerpf(_heat_fever, target_fever_heat, heat_step)
		dirty = true
	else:
		_heat_fever = target_fever_heat

	# Advance staggered tray refill pop-in springs
	for i: int in range(TRAY_SIZE):
		if _refill_timers[i] >= 0.0:
			dirty = true
			_refill_timers[i] += delta
			var finish_time: float = float(i) * REFILL_STAGGER + REFILL_DURATION
			if _refill_timers[i] >= finish_time:
				_refill_timers[i] = -1.0

		if _special_award_timers[i] >= 0.0:
			dirty = true
			_special_award_timers[i] += delta
			if _special_award_timers[i] >= SPECIAL_AWARD_DURATION:
				_special_award_timers[i] = -1.0

	# Hold Dock hover glow & scale interpolation
	var hover_target: float = 1.0 if (_is_dragging and _drag_hovering_hold and _drag_source_type == "tray" and not _hold_used_this_turn) else 0.0
	if absf(_hold_hover_blend - hover_target) > 0.002:
		_hold_hover_blend = lerpf(_hold_hover_blend, hover_target, 1.0 - exp(-18.0 * delta))
		dirty = true
	else:
		_hold_hover_blend = hover_target

	if _hold_tap_pulse > 0.0:
		_hold_tap_pulse = maxf(0.0, _hold_tap_pulse - delta * 4.5)
		dirty = true

	# Active drag smoothing (lift, full-size scale-up, velocity sway tilt)
	if _is_dragging:
		dirty = true
		overlay_dirty = true
		if not _programmatic_drag:
			var safe_dt: float = maxf(delta, 0.001)
			var inst_vel_x: float = (_drag_pointer_global.x - _drag_prev_pointer_x) / safe_dt
			_drag_prev_pointer_x = _drag_pointer_global.x
			_drag_vel_x = lerpf(_drag_vel_x, inst_vel_x, 1.0 - exp(-18.0 * delta))

			var target_tilt: float = clampf(_drag_vel_x * SWAY_VEL_FACTOR, -MAX_SWAY_RADIANS, MAX_SWAY_RADIANS)
			_drag_tilt = lerpf(_drag_tilt, target_tilt, 1.0 - exp(-16.0 * delta))

			var hovering_valid_hold: bool = _drag_hovering_hold and _drag_source_type == "tray" and not _hold_used_this_turn
			var target_lift: float = 6.0 if hovering_valid_hold else LIFT_OFFSET_Y
			var target_scale: float = 0.56 if hovering_valid_hold else 1.0

			var lift_before: float = _drag_lift_current
			_drag_lift_current = lerpf(_drag_lift_current, target_lift, 1.0 - exp(-22.0 * delta))
			_drag_scale_current = lerpf(_drag_scale_current, target_scale, 1.0 - exp(-24.0 * delta))

			# Keep board preview smoothly synced while the lift eases upward right after pickup
			if absf(_drag_lift_current - lift_before) > 0.35 and _drag_piece != null:
				drag_moved.emit(_get_floating_piece_center_global(), _drag_source_type, _drag_slot_idx, _drag_piece)

	# Return spring animation after cancelled drag
	if _return_active:
		dirty = true
		overlay_dirty = true
		_return_elapsed += delta
		if _return_elapsed >= RETURN_ANIM_DURATION:
			_return_active = false
			_return_piece = null

	for si: int in range(_skill_flash_timers.size()):
		if _skill_flash_timers[si] > 0.0:
			_skill_flash_timers[si] = maxf(0.0, _skill_flash_timers[si] - delta * 3.8)
			dirty = true

	if dirty:
		queue_redraw()
	if overlay_dirty and _drag_overlay != null:
		_drag_overlay.queue_redraw()


# ==============================================================================
# PUBLIC API
# ==============================================================================

## Links the BoardView for 1:1 cell sizing and snapping on drop.
func set_board_view(p_board_view: BoardView) -> void:
	board_view = p_board_view
	queue_redraw()


## Synchronizes tray pieces, playability dimming, and Hold Dock state from GameController.
func sync_from_controller(controller: GameController) -> void:
	if controller == null:
		return

	for i: int in range(TRAY_SIZE):
		_tray_pieces[i] = controller.get_tray_piece(i)
		_slot_playable[i] = controller.is_tray_piece_playable(i)

	_hold_piece = controller.hold_piece
	_hold_used_this_turn = controller.hold_used_this_turn
	_hold_playable = controller.is_hold_piece_playable()
	if controller.save_manager != null:
		_wallet_coins = controller.save_manager.coins

	# Cancel active user drag cleanly if the underlying source piece vanished externally.
	if _is_dragging and not _programmatic_drag:
		var source_piece: PieceCatalog.Piece = _get_source_piece(_drag_source_type, _drag_slot_idx)
		if source_piece == null:
			_cancel_active_drag(false)

	queue_redraw()
	if _drag_overlay != null:
		_drag_overlay.queue_redraw()


## Directly sets the 3 tray pieces and optional per-slot playability booleans.
func set_tray_pieces(pieces: Array, playable_flags: Array = []) -> void:
	for i: int in range(TRAY_SIZE):
		var piece: PieceCatalog.Piece = null
		if i < pieces.size() and pieces[i] is PieceCatalog.Piece:
			piece = pieces[i] as PieceCatalog.Piece
		_tray_pieces[i] = piece

		if i < playable_flags.size():
			_slot_playable[i] = bool(playable_flags[i])
		elif piece != null and board_view != null and board_view.board_state != null:
			_slot_playable[i] = board_view.board_state.can_piece_fit_anywhere(piece)
		else:
			_slot_playable[i] = true

	queue_redraw()


## Directly sets the Hold Dock piece, per-turn lock state, and board playability flag.
func set_hold_state(piece: PieceCatalog.Piece, used_this_turn: bool, playable: bool = true) -> void:
	_hold_piece = piece
	_hold_used_this_turn = used_this_turn
	_hold_playable = playable
	queue_redraw()


## Updates subtle accent heat tinting during Combo >= 2 and FEVER.
func set_heat_level(combo: int, fever: bool) -> void:
	_target_combo = maxi(0, combo)
	_target_fever = fever
	queue_redraw()


## Enables or disables drag interaction (cancels active drag cleanly when disabled).
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled and _is_dragging and not _programmatic_drag:
		_cancel_active_drag(true)


## Triggers staggered 0.06s pop-in spring animations (0 -> 1.06 -> 1.0) on newly dealt tray pieces.
func animate_tray_refill() -> void:
	for i: int in range(TRAY_SIZE):
		_refill_timers[i] = 0.0
	queue_redraw()


## Triggers a dramatic golden pop burst + starburst shockwave when a Bomb or Lightning spawns in slot_idx.
func animate_special_award(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= TRAY_SIZE:
		return
	_special_award_timers[slot_idx] = 0.0
	queue_redraw()


## Stages a crisp programmatic mid-drag state (with ghost snap + line-clear anticipation glow)
## for automated screenshot capture and visual verification.
## Pass slot_idx in 0..2 for a tray piece, or -1 for the held piece.
func set_programmatic_drag_preview(
	slot_idx: int,
	target_global_pos: Vector2,
	tilt_radians: float = 0.055,
	snap_origin_override: Vector2i = Vector2i(-1, -1)
) -> void:
	var source_type: String = "hold" if slot_idx < 0 else "tray"
	var piece: PieceCatalog.Piece = _get_source_piece(source_type, slot_idx)
	if piece == null:
		clear_programmatic_drag_preview()
		return

	_return_active = false
	_is_dragging = true
	_programmatic_drag = true
	_active_pointer_id = -1
	_drag_source_type = source_type
	_drag_slot_idx = slot_idx
	_drag_piece = piece
	_drag_lift_current = LIFT_OFFSET_Y
	_drag_scale_current = 1.0
	_drag_tilt = clampf(tilt_radians, -MAX_SWAY_RADIANS, MAX_SWAY_RADIANS)
	_drag_vel_x = 0.0
	_drag_hovering_hold = false
	_drag_pointer_global = target_global_pos + Vector2(0.0, LIFT_OFFSET_Y)
	_drag_prev_pointer_x = _drag_pointer_global.x

	drag_started.emit(_drag_source_type, _drag_slot_idx, _drag_piece)
	if snap_origin_override.x < 0:
		drag_moved.emit(target_global_pos, _drag_source_type, _drag_slot_idx, _drag_piece)

	# Drive BoardView preview (respecting explicit snap_origin_override so lifted piece & ghost stay cleanly separated!).
	if board_view != null and board_view.board_state != null:
		var origin: Vector2i = snap_origin_override if snap_origin_override.x >= 0 else board_view.global_pos_to_origin_cell(target_global_pos, _drag_piece)
		if origin.x >= 0 and origin.y >= 0:
			var preview: Dictionary = board_view.board_state.preview_placement(_drag_piece, origin)
			board_view.set_placement_preview(_drag_piece, origin, preview)
		else:
			board_view.clear_placement_preview()

	queue_redraw()
	if _drag_overlay != null:
		_drag_overlay.queue_redraw()


## Clears any staged programmatic drag preview cleanly.
func clear_programmatic_drag_preview() -> void:
	if not _programmatic_drag and not _is_dragging:
		return
	_is_dragging = false
	_programmatic_drag = false
	_drag_piece = null
	_drag_source_type = ""
	_drag_slot_idx = -1
	_drag_tilt = 0.0
	_drag_vel_x = 0.0
	_drag_hovering_hold = false
	if board_view != null:
		board_view.clear_placement_preview()
	drag_cancelled.emit()
	queue_redraw()
	if _drag_overlay != null:
		_drag_overlay.queue_redraw()


func is_dragging() -> bool:
	return _is_dragging


func get_slot_rect(slot_idx: int) -> Rect2:
	var idx: int = clampi(slot_idx, 0, TRAY_SIZE - 1)
	var x_pos: float = SLOT_LEFT_MARGIN + float(idx) * (SLOT_WIDTH + SLOT_GAP)
	return Rect2(x_pos, SLOT_Y, SLOT_WIDTH, SLOT_HEIGHT)


func get_slot_center_global(slot_idx: int) -> Vector2:
	return get_global_transform() * get_slot_rect(slot_idx).get_center()


func get_hold_rect() -> Rect2:
	return HOLD_RECT


func get_hold_center_global() -> Vector2:
	return get_global_transform() * HOLD_RECT.get_center()


# ==============================================================================
# INPUT HANDLING (ONE-HANDED MOUSE + TOUCH DRAG)
# ==============================================================================

func _gui_input(event: InputEvent) -> void:
	if not _input_enabled:
		return

	if event is InputEventScreenTouch:
		var touch_ev: InputEventScreenTouch = event as InputEventScreenTouch
		if touch_ev.pressed and _active_pointer_id == -1 and _pending_tap_pointer_id == -1:
			if _try_begin_press(touch_ev.position, touch_ev.index):
				accept_event()
	elif event is InputEventMouseButton:
		var mb_ev: InputEventMouseButton = event as InputEventMouseButton
		if mb_ev.button_index == MOUSE_BUTTON_LEFT and mb_ev.pressed and _active_pointer_id == -1 and _pending_tap_pointer_id == -1:
			if _try_begin_press(mb_ev.position, -2):
				accept_event()


func _input(event: InputEvent) -> void:
	if _programmatic_drag:
		return

	# Handle pending tap on an empty HOLD Dock
	if _pending_empty_hold_tap:
		if event is InputEventScreenTouch:
			var t_ev: InputEventScreenTouch = event as InputEventScreenTouch
			if not t_ev.pressed and t_ev.index == _pending_tap_pointer_id:
				_finish_empty_hold_tap(_event_to_global_pos(event, t_ev.position))
		elif event is InputEventMouseButton:
			var m_ev: InputEventMouseButton = event as InputEventMouseButton
			if m_ev.button_index == MOUSE_BUTTON_LEFT and not m_ev.pressed and _pending_tap_pointer_id == -2:
				_finish_empty_hold_tap(_event_to_global_pos(event, m_ev.position))
		return

	if not _is_dragging:
		return

	if event is InputEventScreenDrag:
		var drag_ev: InputEventScreenDrag = event as InputEventScreenDrag
		if drag_ev.index == _active_pointer_id:
			_update_active_drag(_event_to_global_pos(event, drag_ev.position))
	elif event is InputEventScreenTouch:
		var touch_ev: InputEventScreenTouch = event as InputEventScreenTouch
		if not touch_ev.pressed and touch_ev.index == _active_pointer_id:
			_finish_active_drag(_event_to_global_pos(event, touch_ev.position))
	elif event is InputEventMouseMotion:
		if _active_pointer_id == -2:
			var mm_ev: InputEventMouseMotion = event as InputEventMouseMotion
			_update_active_drag(_event_to_global_pos(event, mm_ev.position))
	elif event is InputEventMouseButton:
		var mb_ev: InputEventMouseButton = event as InputEventMouseButton
		if mb_ev.button_index == MOUSE_BUTTON_LEFT and not mb_ev.pressed and _active_pointer_id == -2:
			_finish_active_drag(_event_to_global_pos(event, mb_ev.position))


func _event_to_global_pos(event: InputEvent, raw_pos: Vector2) -> Vector2:
	if not is_inside_tree():
		return raw_pos
	var local_ev: InputEvent = make_input_local(event)
	var local_pos: Vector2 = raw_pos
	if local_ev is InputEventMouse:
		local_pos = (local_ev as InputEventMouse).position
	elif local_ev is InputEventScreenTouch:
		local_pos = (local_ev as InputEventScreenTouch).position
	elif local_ev is InputEventScreenDrag:
		local_pos = (local_ev as InputEventScreenDrag).position
	return get_global_transform() * local_pos


func _try_begin_press(local_pos: Vector2, pointer_id: int) -> bool:
	var global_pos: Vector2 = get_global_transform() * local_pos

	# 1. Check the 3 Tray Slots (generous 6px forgiving hit padding).
	for i: int in range(TRAY_SIZE):
		var slot_rect: Rect2 = get_slot_rect(i).grow(6.0)
		if slot_rect.has_point(local_pos) and _tray_pieces[i] != null:
			_begin_drag("tray", i, _tray_pieces[i], global_pos, pointer_id)
			return true

	# 2. Check the HOLD Dock.
	var hold_hit: Rect2 = HOLD_RECT.grow(6.0)
	if hold_hit.has_point(local_pos):
		if _hold_piece != null:
			_begin_drag("hold", -1, _hold_piece, global_pos, pointer_id)
			return true
		else:
			_pending_empty_hold_tap = true
			_pending_tap_pointer_id = pointer_id
			_pending_tap_start_global = global_pos
			_pending_tap_start_time = _time
			_hold_tap_pulse = 1.0
			queue_redraw()
			return true

	# 3. Check the 3 Coin Power-Up Skill Buttons.
	for i: int in range(SKILL_BUTTON_SPECS.size()):
		var spec: Dictionary = SKILL_BUTTON_SPECS[i]
		var srect: Rect2 = (spec["rect"] as Rect2).grow(3.0)
		if srect.has_point(local_pos):
			_skill_flash_timers[i] = 1.0
			queue_redraw()
			skill_pressed.emit(String(spec["id"]))
			return true

	return false


func _begin_drag(
	source_type: String,
	slot_idx: int,
	piece: PieceCatalog.Piece,
	pointer_global: Vector2,
	pointer_id: int
) -> void:
	_return_active = false
	_return_piece = null
	_programmatic_drag = false
	_is_dragging = true
	_active_pointer_id = pointer_id
	_drag_source_type = source_type
	_drag_slot_idx = slot_idx
	_drag_piece = piece
	_drag_press_global = pointer_global
	_drag_press_time = _time
	_drag_pointer_global = pointer_global
	_drag_prev_pointer_x = pointer_global.x
	_drag_vel_x = 0.0
	_drag_tilt = 0.0
	_drag_lift_current = 0.0

	var start_cell: float = _get_hold_cell_size(piece) if source_type == "hold" else _get_tray_cell_size(piece)
	_drag_scale_current = clampf(start_cell / _get_board_cell_size(), 0.30, 0.90)
	_drag_hovering_hold = false

	drag_started.emit(_drag_source_type, _drag_slot_idx, _drag_piece)
	drag_moved.emit(_get_floating_piece_center_global(), _drag_source_type, _drag_slot_idx, _drag_piece)
	queue_redraw()
	if _drag_overlay != null:
		_drag_overlay.queue_redraw()


func _update_active_drag(pointer_global: Vector2) -> void:
	_drag_pointer_global = pointer_global
	var pointer_local: Vector2 = get_global_transform().affine_inverse() * pointer_global
	_drag_hovering_hold = HOLD_RECT.grow(HOLD_HIT_GROW).has_point(pointer_local)

	if _drag_hovering_hold and _drag_source_type == "tray" and not _hold_used_this_turn:
		# Clear any active board preview while aiming to drop into Hold.
		if board_view != null:
			board_view.clear_drag_preview()
	else:
		drag_moved.emit(_get_floating_piece_center_global(), _drag_source_type, _drag_slot_idx, _drag_piece)

	queue_redraw()
	if _drag_overlay != null:
		_drag_overlay.queue_redraw()


func _finish_active_drag(pointer_global: Vector2) -> void:
	_drag_pointer_global = pointer_global
	var pointer_local: Vector2 = get_global_transform().affine_inverse() * pointer_global
	var over_hold: bool = HOLD_RECT.grow(HOLD_HIT_GROW).has_point(pointer_local)

	var drag_dist: float = pointer_global.distance_to(_drag_press_global)
	var drag_elapsed: float = _time - _drag_press_time
	var src_type: String = _drag_source_type
	var src_slot: int = _drag_slot_idx
	var piece: PieceCatalog.Piece = _drag_piece
	var floating_center: Vector2 = _get_floating_piece_center_global()

	# Quick tap directly on an occupied Hold Dock -> cancel drag & emit hold_tapped.
	if src_type == "hold" and over_hold and drag_dist <= TAP_MAX_DIST and drag_elapsed <= TAP_MAX_TIME:
		_hold_tap_pulse = 1.0
		_clear_drag_flags()
		drag_cancelled.emit()
		hold_tapped.emit()
		return

	# 1. Drop onto HOLD Dock (when dragging from tray and hold not yet used this turn).
	if src_type == "tray" and over_hold and not _hold_used_this_turn:
		_hold_tap_pulse = 1.0
		_clear_drag_flags()
		drag_dropped_on_hold.emit(src_slot)
		return

	# 2. Drop onto 8x8 Board.
	var origin_cell: Vector2i = _resolve_board_origin(floating_center, piece)
	if origin_cell.x >= 0 and origin_cell.y >= 0:
		_clear_drag_flags()
		drag_dropped_on_board.emit(src_type, src_slot, origin_cell)
		return

	# 3. Invalid drop -> snappy spring return back to original tray/hold slot.
	_cancel_active_drag(true)


func _finish_empty_hold_tap(pointer_global: Vector2) -> void:
	var dist: float = pointer_global.distance_to(_pending_tap_start_global)
	var elapsed: float = _time - _pending_tap_start_time
	var local_pos: Vector2 = get_global_transform().affine_inverse() * pointer_global
	_pending_empty_hold_tap = false
	_pending_tap_pointer_id = -1

	if dist <= TAP_MAX_DIST + 4.0 and elapsed <= TAP_MAX_TIME + 0.12 and HOLD_RECT.grow(HOLD_HIT_GROW).has_point(local_pos):
		_hold_tap_pulse = 1.0
		hold_tapped.emit()
	queue_redraw()


func _cancel_active_drag(play_return_anim: bool) -> void:
	if play_return_anim and _drag_piece != null:
		_return_active = true
		_return_piece = _drag_piece
		_return_source_type = _drag_source_type
		_return_slot_idx = _drag_slot_idx
		_return_from_global = _get_floating_piece_center_global()
		_return_to_global = get_hold_center_global() if _drag_source_type == "hold" else get_slot_center_global(_drag_slot_idx)
		_return_from_scale = _drag_scale_current
		var dest_cell: float = _get_hold_cell_size(_drag_piece) if _drag_source_type == "hold" else _get_tray_cell_size(_drag_piece)
		_return_to_scale = clampf(dest_cell / _get_board_cell_size(), 0.30, 0.90)
		_return_from_tilt = _drag_tilt
		_return_elapsed = 0.0

	_clear_drag_flags()
	drag_cancelled.emit()


func _clear_drag_flags() -> void:
	_is_dragging = false
	_programmatic_drag = false
	_active_pointer_id = -1
	_drag_source_type = ""
	_drag_slot_idx = -1
	_drag_piece = null
	_drag_vel_x = 0.0
	_drag_tilt = 0.0
	_drag_hovering_hold = false
	queue_redraw()
	if _drag_overlay != null:
		_drag_overlay.queue_redraw()


func _resolve_board_origin(piece_center_global: Vector2, piece: PieceCatalog.Piece) -> Vector2i:
	if piece == null:
		return Vector2i(-1, -1)
	if board_view != null:
		return board_view.global_pos_to_origin_cell(piece_center_global, piece)

	# Standalone fallback matching default BoardView Rect2(32, 192, 476, 476) inset 8px
	var inner: Rect2 = Rect2(40.0, 200.0, 460.0, 460.0)
	var cell_size: float = DEFAULT_BOARD_CELL_SIZE
	var col_f: float = (piece_center_global.x - inner.position.x) / cell_size - float(piece.width) * 0.5
	var row_f: float = (piece_center_global.y - inner.position.y) / cell_size - float(piece.height) * 0.5
	var col: int = int(round(col_f))
	var row: int = int(round(row_f))
	if col >= 0 and row >= 0 and col + piece.width <= BoardState.GRID_SIZE and row + piece.height <= BoardState.GRID_SIZE:
		return Vector2i(col, row)
	return Vector2i(-1, -1)


func _get_floating_piece_center_global() -> Vector2:
	return _drag_pointer_global - Vector2(0.0, _drag_lift_current)


func _get_board_cell_size() -> float:
	if board_view != null:
		var s: float = board_view.get_cell_size()
		if s > 4.0:
			return s
	return DEFAULT_BOARD_CELL_SIZE


func _get_source_piece(source_type: String, slot_idx: int) -> PieceCatalog.Piece:
	if source_type == "hold":
		return _hold_piece
	if source_type == "tray" and slot_idx >= 0 and slot_idx < TRAY_SIZE:
		return _tray_pieces[slot_idx]
	return null


# ==============================================================================
# RENDERING: TRAY SLOTS & HOLD DOCK
# ==============================================================================

func _draw() -> void:
	_ensure_cached_styles()
	for i: int in range(TRAY_SIZE):
		_draw_tray_slot(i)
	_draw_hold_dock()
	_draw_skill_buttons()
	_draw_coin_wallet_pill()


func _draw_tray_slot(slot_idx: int) -> void:
	var slot_rect: Rect2 = get_slot_rect(slot_idx)
	var piece: PieceCatalog.Piece = _tray_pieces[slot_idx]
	var is_being_dragged: bool = _is_dragging and _drag_source_type == "tray" and _drag_slot_idx == slot_idx
	var is_returning: bool = _return_active and _return_source_type == "tray" and _return_slot_idx == slot_idx
	var is_special: bool = piece != null and piece.is_special()
	var playable: bool = _slot_playable[slot_idx]

	# Clean, open, borderless Block Blast! thumb zone (NO heavy dark rectangular tray boxes!).
	# Special blocks (Bomb / Lightning) earn a velvety Gaussian ambient aura behind them so they shine!
	if is_special and not is_being_dragged and not is_returning:
		var sp_pulse: float = 0.5 + 0.5 * sin(_time * 4.8 + float(slot_idx))
		var glow_col: Color = Color(1.0, 0.42, 0.16, 0.48 + 0.16 * sp_pulse) if piece.special_type == PieceCatalog.SPECIAL_BOMB else Color(0.16, 0.88, 1.0, 0.50 + 0.18 * sp_pulse)
		_draw_soft_glow(self, slot_rect.get_center(), Vector2(58.0 + 6.0 * sp_pulse, 58.0 + 6.0 * sp_pulse), glow_col)

	if piece == null:
		return

	# Subtle borderless translucent silhouette while dragging (cleaner than Block Blast!'s clunky box!).
	if is_being_dragged:
		var cell_s: float = _get_tray_cell_size(piece)
		_draw_piece_silhouette(self, piece, slot_rect.get_center(), cell_s, Color(1.0, 1.0, 1.0, 0.13))
		return

	if is_returning:
		return

	# Compute entrance & special-award spring scale + special hover breathe!
	var anim_scale: float = 1.0
	var y_bob: float = 0.0

	if _refill_timers[slot_idx] >= 0.0:
		anim_scale *= _eval_refill_scale(_refill_timers[slot_idx], float(slot_idx) * REFILL_STAGGER)

	if _special_award_timers[slot_idx] >= 0.0:
		anim_scale *= _eval_special_award_scale(_special_award_timers[slot_idx])

	if is_special:
		anim_scale *= (1.0 + 0.05 * sin(_time * 4.5 + float(slot_idx)))
		y_bob = -3.0 * sin(_time * 3.1 + float(slot_idx))

	if anim_scale <= 0.02:
		return

	var base_cell: float = _get_tray_cell_size(piece)
	var draw_cell: float = base_cell * anim_scale
	var center: Vector2 = slot_rect.get_center() + Vector2(0.0, y_bob)
	var piece_alpha: float = 1.0 if playable else 0.42

	_draw_piece_grounded_shadow(self, piece, center, draw_cell, Vector2(0.0, 6.5), 0.50 * piece_alpha)
	_draw_piece_cells(self, piece, center, draw_cell, piece_alpha, 0.0)

	# Faint muted cool danger veil on unplayable pieces so board danger reads immediately.
	if not playable:
		_draw_piece_silhouette(self, piece, center, draw_cell, Color(0.11, 0.15, 0.29, 0.30))

	# Dramatic golden starburst shockwave when a Bomb or Lightning just spawned here!
	if _special_award_timers[slot_idx] >= 0.0:
		_draw_special_award_burst(slot_rect.get_center(), _special_award_timers[slot_idx])


func _draw_hold_dock() -> void:
	var cid: RID = get_canvas_item()
	var scale_factor: float = lerpf(1.0, 1.05, _hold_hover_blend) + _hold_tap_pulse * 0.025
	var center: Vector2 = HOLD_RECT.get_center()
	var scaled_size: Vector2 = HOLD_RECT.size * scale_factor
	var dock_rect: Rect2 = Rect2(center - scaled_size * 0.5, scaled_size)

	var hovering_locked: bool = _is_dragging and _drag_hovering_hold and _drag_source_type == "tray" and _hold_used_this_turn
	var is_dragging_hold: bool = _is_dragging and _drag_source_type == "hold"
	var is_returning_hold: bool = _return_active and _return_source_type == "hold"
	var pulse: float = 0.5 + 0.5 * sin(_time * 6.0)

	# 1. Grounded pill shadow (native StyleBoxFlat).
	_sb_hold_shadow.draw(cid, Rect2(dock_rect.position + Vector2(0.0, 5.0), dock_rect.size))

	# 2. Bright velvety cyan-gold bloom when dragging a tray piece over HOLD!
	if _hold_hover_blend > 0.02:
		var glow_col: Color = COL_HOLD_CYAN.lerp(COL_HOLD_GOLD, 0.35 + 0.25 * pulse)
		_draw_soft_glow(self, center, Vector2(dock_rect.size.x * 0.72, dock_rect.size.y * 0.92), Color(glow_col.r, glow_col.g, glow_col.b, 0.42 * _hold_hover_blend))
		_sb_hold_glow.border_color = Color(glow_col.r, glow_col.g, glow_col.b, 0.65 * _hold_hover_blend)
		_sb_hold_glow.draw(cid, dock_rect.grow(3.0))

	# 3. Sleek translucent midnight glass pill vault (native StyleBoxFlat).
	var outer_bg: Color = Color(0.059, 0.086, 0.204, 0.70)
	var border_col: Color = Color(0.36, 0.62, 0.96, 0.56).lerp(Color("#FF9233"), _heat_fever * 0.32)
	if _hold_used_this_turn:
		outer_bg = Color(0.065, 0.080, 0.165, 0.58)
		border_col = Color(0.36, 0.41, 0.56, 0.45)
	if hovering_locked:
		border_col = Color("#E88E3A", 0.90)
	if _hold_hover_blend > 0.02:
		border_col = border_col.lerp(COL_HOLD_CYAN.lerp(COL_HOLD_GOLD, 0.45), _hold_hover_blend)
		outer_bg = outer_bg.lerp(Color(0.09, 0.20, 0.38, 0.84), _hold_hover_blend)

	_sb_hold_outer.bg_color = outer_bg
	_sb_hold_outer.border_color = border_col
	_sb_hold_outer.draw(cid, dock_rect)

	var inner_rect: Rect2 = dock_rect.grow(-4.0)
	_sb_hold_inner.bg_color = Color(0.075, 0.115, 0.265, 0.50).lerp(Color(0.11, 0.23, 0.42, 0.66), _hold_hover_blend)
	_sb_hold_inner.draw(cid, inner_rect)

	# 4. Crisp integrated inline "HOLD" micro-pill anchored neatly at top-left inside compact dock.
	var tag_rect: Rect2 = Rect2(dock_rect.position.x + 8.0, dock_rect.position.y + 6.0, 48.0, 19.0)
	_sb_hold_tag.bg_color = Color(0.09, 0.16, 0.36, 0.85) if not _hold_used_this_turn else Color(0.11, 0.13, 0.24, 0.75)
	_sb_hold_tag.border_color = border_col
	_sb_hold_tag.draw(cid, tag_rect)
	_draw_centered_text(
		self,
		TilePainter.get_badge_font(),
		tag_rect.get_center() + Vector2(0.0, 0.5),
		"HOLD",
		10,
		Color("#8D97BA") if _hold_used_this_turn else Color("#E2F8FF").lerp(Color("#FFF7B2"), _hold_hover_blend),
		Color("#070C20"),
		3
	)

	# 5. Vault interior content centered cleanly in the lower center of HOLD dock.
	var content_center: Vector2 = Vector2(center.x, center.y + 9.0)
	if _hold_piece != null:
		var hold_cell: float = minf(16.0, _get_hold_cell_size(_hold_piece))
		if is_dragging_hold:
			_draw_piece_silhouette(self, _hold_piece, content_center, hold_cell, Color(1.0, 1.0, 1.0, 0.15))
		elif not is_returning_hold:
			var piece_alpha: float = 1.0 if _hold_playable else 0.42
			var sp_bob: float = -1.4 * sin(_time * 3.4) if _hold_piece.is_special() else 0.0
			var sp_scale: float = (1.0 + 0.04 * sin(_time * 4.8)) if _hold_piece.is_special() else 1.0
			var draw_pos: Vector2 = content_center + Vector2(0.0, sp_bob)
			var draw_cell: float = hold_cell * sp_scale
			if _hold_piece.is_special():
				var sp_glow: Color = Color(1.0, 0.42, 0.16, 0.40) if _hold_piece.special_type == PieceCatalog.SPECIAL_BOMB else Color(0.18, 0.90, 1.0, 0.42)
				_draw_soft_glow(self, draw_pos, Vector2(30.0, 30.0), sp_glow)
			_draw_piece_grounded_shadow(self, _hold_piece, draw_pos, draw_cell, Vector2(0.0, 3.0), 0.46 * piece_alpha)
			_draw_piece_cells(self, _hold_piece, draw_pos, draw_cell, piece_alpha, 0.0)
			if not _hold_playable:
				_draw_piece_silhouette(self, _hold_piece, draw_pos, draw_cell, Color(0.11, 0.15, 0.29, 0.30))
	else:
		var prompt_col: Color = Color(0.54, 0.72, 0.98, 0.56) if not _hold_used_this_turn else Color(0.45, 0.50, 0.64, 0.38)
		_draw_centered_text(
			self,
			TilePainter.get_bold_font(),
			content_center,
			"DROP PIECE",
			11,
			prompt_col,
			Color(0.03, 0.05, 0.14, 0.55),
			2
		)

	# 6. Sleek swap/lock status icon anchored neatly at top-right inside the glass pill.
	var icon_center: Vector2 = Vector2(dock_rect.end.x - 16.0, dock_rect.position.y + 15.5)
	var icon_rim: Color = COL_HOLD_LOCKED if _hold_used_this_turn else COL_HOLD_CYAN.lerp(COL_HOLD_GOLD, _hold_hover_blend * 0.6)
	icon_rim.a = 0.55 if _hold_used_this_turn else 0.82
	if _hold_used_this_turn:
		_draw_mini_lock_icon(icon_center, Color(0.62, 0.68, 0.84, 0.78))
	else:
		_draw_swap_arrows_icon(icon_center, 7.2, icon_rim, 1.8)

	# 7. Crisp action cue pill overlay when dragging a tray piece over HOLD.
	if _hold_hover_blend > 0.12:
		var cue_text: String = "SWAP" if _hold_piece != null else "DROP TO HOLD"
		var cue_w: float = 82.0 if _hold_piece != null else 128.0
		var cue_rect: Rect2 = Rect2(center.x - cue_w * 0.5, dock_rect.position.y - 14.0, cue_w, 22.0)
		var pill_alpha: float = clampf(_hold_hover_blend * 1.15, 0.0, 1.0)
		_sb_hold_cue.bg_color = Color(0.05, 0.14, 0.30, 0.94 * pill_alpha)
		_sb_hold_cue.border_color = Color(COL_HOLD_GOLD.r, COL_HOLD_GOLD.g, COL_HOLD_GOLD.b, pill_alpha)
		_sb_hold_cue.draw(cid, cue_rect)
		_draw_centered_text(
			self,
			TilePainter.get_badge_font(),
			cue_rect.get_center() + Vector2(0.0, 0.5),
			cue_text,
			11,
			Color(1.0, 0.96, 0.72, pill_alpha),
			Color(0.04, 0.09, 0.22, pill_alpha),
			3
		)
	elif hovering_locked:
		var lock_rect: Rect2 = Rect2(center.x - 52.0, dock_rect.position.y - 14.0, 104.0, 22.0)
		_sb_hold_cue.bg_color = Color(0.18, 0.09, 0.12, 0.94)
		_sb_hold_cue.border_color = Color("#E89243")
		_sb_hold_cue.draw(cid, lock_rect)
		_draw_centered_text(
			self,
			TilePainter.get_badge_font(),
			lock_rect.get_center() + Vector2(0.0, 0.5),
			"1× PER TURN",
			11,
			Color("#FFD7A6"),
			Color("#220A0E"),
			3
		)


func _draw_skill_buttons() -> void:
	var cid: RID = get_canvas_item()
	var font_eb := TilePainter.get_badge_font()
	for i: int in range(SKILL_BUTTON_SPECS.size()):
		var spec: Dictionary = SKILL_BUTTON_SPECS[i]
		var sid: String = String(spec["id"])
		var label: String = String(spec["label"])
		var cost: int = int(spec["cost"])
		var cost_short: String = String(spec["cost_short"])
		var base_rect: Rect2 = spec["rect"] as Rect2
		var accent: Color = spec["accent"] as Color
		var base_bg: Color = spec["bg"] as Color
		var can_afford: bool = _wallet_coins >= cost
		var flash: float = _skill_flash_timers[i]

		var scale_s: float = 1.0 - flash * 0.06
		var c: Vector2 = base_rect.get_center()
		var rect: Rect2 = Rect2(c - base_rect.size * scale_s * 0.5, base_rect.size * scale_s)

		# Shadow + 3D glass skill pill
		_sb_hold_shadow.draw(cid, Rect2(rect.position + Vector2(0.0, 4.5), rect.size))
		_sb_hold_outer.bg_color = (base_bg.lightened(flash * 0.28) if can_afford else Color(0.06, 0.08, 0.16, 0.62))
		_sb_hold_outer.border_color = (accent.lerp(Color.WHITE, flash * 0.65) if can_afford else Color(0.28, 0.34, 0.52, 0.45))
		_sb_hold_outer.draw(cid, rect)

		# Icon in upper half
		var ic := Vector2(rect.get_center().x, rect.position.y + 23.0)
		var icon_alpha := 1.0 if can_afford else 0.45
		if sid == "reroll":
			var r_col := Color(accent.r, accent.g, accent.b, icon_alpha)
			draw_arc(ic, 11.0, -PI * 0.85, PI * 0.55, 16, r_col, 2.8, true)
			var tip_a := ic + Vector2(cos(PI * 0.55), sin(PI * 0.55)) * 11.0
			draw_colored_polygon(PackedVector2Array([tip_a + Vector2(4.5, -1.0), tip_a + Vector2(-4.0, -4.5), tip_a + Vector2(-2.0, 4.5)]), r_col)
			draw_arc(ic, 11.0, PI * 0.15, PI * 1.55, 16, Color(0.75, 1.0, 0.92, icon_alpha * 0.85), 2.2, true)
		elif sid == "bomb":
			var br := Rect2(ic - Vector2(13.0, 13.0), Vector2(26.0, 26.0))
			TilePainter.draw_special_tile(self, br, TilePainter.SPECIAL_BOMB, _time, icon_alpha)
		else:
			var lr := Rect2(ic - Vector2(13.0, 13.0), Vector2(26.0, 26.0))
			TilePainter.draw_special_tile(self, lr, TilePainter.SPECIAL_LIGHTNING, _time, icon_alpha)

		# Skill name
		_draw_centered_text(
			self,
			font_eb,
			Vector2(rect.get_center().x, rect.position.y + 46.5),
			label,
			11,
			Color("#FFFFFF") if can_afford else Color("#7B88AD"),
			Color("#070C20"),
			3
		)

		# Gold Coin Cost pill along bottom
		var cost_y := rect.end.y - 12.5
		var cc := Vector2(rect.get_center().x - 16.0, cost_y)
		draw_circle(cc, 5.2, Color("#8C4400") if can_afford else Color("#303A58"))
		draw_circle(cc, 4.1, Color("#FFD43B") if can_afford else Color("#627094"))
		_draw_centered_text(
			self,
			font_eb,
			Vector2(rect.get_center().x + 6.0, cost_y + 0.5),
			cost_short,
			11,
			Color("#FFE866") if can_afford else Color("#7987AC"),
			Color("#1A0D00"),
			3
		)


func _draw_coin_wallet_pill() -> void:
	var cid: RID = get_canvas_item()
	var coin_txt: String = HudView.format_comma_int(_wallet_coins)
	var pill_w: float = clampf(44.0 + float(coin_txt.length()) * 9.0, 88.0, 156.0)
	var pill_r := Rect2((size.x - pill_w) * 0.5, 234.0, pill_w, 25.0)
	_sb_hold_tag.bg_color = Color(0.04, 0.07, 0.18, 0.86)
	_sb_hold_tag.border_color = Color("#FFD43B", 0.72)
	_sb_hold_tag.draw(cid, pill_r)

	var cc := Vector2(pill_r.position.x + 14.0, pill_r.get_center().y)
	draw_circle(cc, 6.2, Color("#A85200"))
	draw_circle(cc, 4.8, Color("#FFD43B"))
	draw_circle(cc + Vector2(-1.2, -1.2), 1.7, Color("#FFF7BD"))
	_draw_centered_text(
		self,
		TilePainter.get_badge_font(),
		Vector2(pill_r.get_center().x + 8.0, pill_r.get_center().y + 0.5),
		coin_txt,
		12,
		Color("#FFE866"),
		Color("#241000"),
		3
	)


# ==============================================================================
# RENDERING: HIGH-Z FLOATING DRAGGED PIECE, SILK LIGHT TRAIL & SNAP-BACK OVERLAY
# ==============================================================================

func _on_drag_overlay_draw() -> void:
	if _drag_overlay == null:
		return
	_ensure_cached_styles()

	var inv_xform: Transform2D = get_global_transform().affine_inverse()

	# 1. Cancelled snap-back animation (piece glides cleanly home).
	if _return_active and _return_piece != null:
		var u: float = clampf(_return_elapsed / RETURN_ANIM_DURATION, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - u, 3.0)
		var pos_global: Vector2 = _return_from_global.lerp(_return_to_global, eased)
		var cur_scale: float = lerpf(_return_from_scale, _return_to_scale, eased)
		var cur_tilt: float = lerpf(_return_from_tilt, 0.0, eased)
		var local_center: Vector2 = inv_xform * pos_global
		var cell_s: float = _get_board_cell_size() * cur_scale
		_draw_floating_piece(_drag_overlay, _return_piece, local_center, cell_s, cur_tilt, 1.0 - eased)
		return

	# 2. Active lifted dragged piece (clean direct drag without tether line).
	if _is_dragging and _drag_piece != null:
		var float_global: Vector2 = _get_floating_piece_center_global()
		var local_center: Vector2 = inv_xform * float_global
		var cell_s: float = _get_board_cell_size() * _drag_scale_current
		var lift_ratio: float = clampf(_drag_lift_current / LIFT_OFFSET_Y, 0.15, 1.0)

		_draw_floating_piece(_drag_overlay, _drag_piece, local_center, cell_s, _drag_tilt, lift_ratio)


func _draw_drag_silk_ribbon(
	ci: CanvasItem,
	origin_local: Vector2,
	piece_center: Vector2,
	piece: PieceCatalog.Piece,
	cell_size: float
) -> void:
	var glow_col: Color = (TilePainter.get_palette(piece.color_id)["glow"] as Color)
	if piece.special_type == PieceCatalog.SPECIAL_BOMB:
		glow_col = Color("#FF7A28")
	elif piece.special_type == PieceCatalog.SPECIAL_LIGHTNING:
		glow_col = Color("#24ECFF")

	var span: Vector2 = piece_center - origin_local
	var dist: float = span.length()
	if dist < 24.0:
		return
	var dir: Vector2 = span / dist
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var half_w_top: float = clampf(float(piece.width) * cell_size * 0.42, 34.0, 88.0)
	var half_w_bot: float = half_w_top * 0.34
	# Sweeping organic curved twin-filament silk ribbon bowing gracefully along the hand-drag gesture!
	var arc_sign: float = -1.0 if span.x <= 0.0 else 1.0
	var arc_bow: float = clampf(dist * 0.24, 48.0, 88.0) * arc_sign
	var ctrl_pt: Vector2 = origin_local.lerp(piece_center, 0.52) + perp * arc_bow

	var steps: int = 16
	var left_pts := PackedVector2Array()
	var right_pts := PackedVector2Array()
	for s in range(steps + 1):
		var t: float = float(s) / float(steps)
		var omt: float = 1.0 - t
		var p: Vector2 = omt * omt * origin_local + 2.0 * omt * t * ctrl_pt + t * t * piece_center
		var tang: Vector2 = (2.0 * omt * (ctrl_pt - origin_local) + 2.0 * t * (piece_center - ctrl_pt)).normalized()
		var nrm: Vector2 = Vector2(-tang.y, tang.x)
		var w: float = lerpf(half_w_bot, half_w_top, pow(t, 0.78))
		left_pts.append(p - nrm * w)
		right_pts.append(p + nrm * w)

	# Layered translucent golden-white silk ribbon segments fading smoothly toward origin slot!
	for s in range(steps):
		var t0: float = float(s) / float(steps)
		var t1: float = float(s + 1) / float(steps)
		var a0: float = pow(t0, 1.40) * 0.34
		var a1: float = pow(t1, 1.40) * 0.34
		var col0 := Color(glow_col.r, glow_col.g, glow_col.b, a0).lerp(Color(1.0, 0.98, 0.86, a0), 0.38)
		var col1 := Color(glow_col.r, glow_col.g, glow_col.b, a1).lerp(Color(1.0, 0.98, 0.86, a1), 0.38)
		ci.draw_polygon(
			PackedVector2Array([left_pts[s], right_pts[s], right_pts[s + 1], left_pts[s + 1]]),
			PackedColorArray([col0, col0, col1, col1])
		)

	# Crisp luminous white-gold silk edge filaments along both curved sides of the drag trail!
	for s in range(steps):
		var t1: float = float(s + 1) / float(steps)
		var line_a: float = pow(t1, 1.25) * 0.86
		var fil_col := Color(1.0, 0.99, 0.90, line_a)
		ci.draw_line(left_pts[s], left_pts[s + 1], fil_col, lerpf(1.2, 2.8, t1), true)
		ci.draw_line(right_pts[s], right_pts[s + 1], fil_col, lerpf(1.2, 2.8, t1), true)

	# 8 floating golden spark motes drifting gracefully around the lifted drag wake!
	for k in range(8):
		var phase: float = fposmod(_time * 0.9 + float(k) * 0.137, 1.0)
		var omt: float = 1.0 - phase
		var base_p: Vector2 = omt * omt * origin_local + 2.0 * omt * phase * ctrl_pt + phase * phase * piece_center
		var side: float = sin(float(k) * 2.7 + _time * 2.5) * lerpf(half_w_bot, half_w_top * 1.25, phase)
		var pt: Vector2 = base_p + perp * side
		var sa: float = sin(phase * PI) * 0.85
		var sz: float = lerpf(2.2, 4.4, sin(phase * PI))
		_draw_soft_glow(ci, pt, Vector2(sz * 2.6, sz * 2.6), Color(glow_col.r, glow_col.g, glow_col.b, 0.42 * sa))
		ci.draw_rect(Rect2(pt - Vector2(sz * 0.5, sz * 0.5), Vector2(sz, sz)), Color(1.0, 0.98, 0.82, sa), true)


func _draw_floating_piece(
	ci: CanvasItem,
	piece: PieceCatalog.Piece,
	local_center: Vector2,
	cell_size: float,
	tilt_rad: float,
	lift_ratio: float
) -> void:
	var shadow_drop: float = lerpf(10.0, 26.0, lift_ratio)
	var shadow_center: Vector2 = local_center + Vector2(0.0, shadow_drop)

	# Grounded drop shadow floating beneath the lifted piece.
	ci.draw_set_transform(shadow_center, tilt_rad, Vector2.ONE)
	_draw_piece_shadow_at_origin(ci, piece, cell_size, 0.34 * lift_ratio, 4.0)
	_draw_piece_shadow_at_origin(ci, piece, cell_size, 0.26 * lift_ratio, 0.5)

	# Luminous outer glow aura + crisp full-size jewel/special blocks!
	ci.draw_set_transform(local_center, tilt_rad, Vector2.ONE)
	var glow_col: Color = (TilePainter.get_palette(piece.color_id)["glow"] as Color)
	if piece.special_type == PieceCatalog.SPECIAL_BOMB:
		glow_col = Color("#FF6A2E")
	elif piece.special_type == PieceCatalog.SPECIAL_LIGHTNING:
		glow_col = Color("#24ECFF")

	var total_w: float = float(piece.width) * cell_size
	var total_h: float = float(piece.height) * cell_size
	var origin_offset: Vector2 = Vector2(-total_w * 0.5, -total_h * 0.5)

	# Velvety radiant Gaussian halo bloom behind every lifted cell (crisp 3D lift separation!).
	for c: Vector2i in piece.cells:
		var cell_c: Vector2 = Vector2(
			origin_offset.x + (float(c.x) + 0.5) * cell_size,
			origin_offset.y + (float(c.y) + 0.5) * cell_size
		)
		_draw_soft_glow(ci, cell_c, Vector2(cell_size * 0.96, cell_size * 0.96), Color(glow_col.r, glow_col.g, glow_col.b, 0.44))

	# Draw full-size jewel or special tiles with bright highlight lift!
	_draw_piece_cells(ci, piece, Vector2.ZERO, cell_size, 1.0, 0.18)

	# Crisp luminous white outer silhouette outline along lifted cells!
	for c: Vector2i in piece.cells:
		var r: Rect2 = Rect2(
			origin_offset.x + float(c.x) * cell_size,
			origin_offset.y + float(c.y) * cell_size,
			cell_size,
			cell_size
		)
		ci.draw_rect(r.grow(0.4), Color(1.0, 0.99, 0.92, 0.72), false, 2.2, true)

	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ==============================================================================
# PIECE DRAWING & GEOMETRY HELPERS
# ==============================================================================

func _get_tray_cell_size(piece: PieceCatalog.Piece) -> float:
	if piece == null:
		return 30.0
	if piece.is_special():
		return 44.0
	if piece.width == 1 and piece.height == 1:
		return 36.0
	var max_w: float = 124.0 / float(maxi(1, piece.width))
	var max_h: float = 104.0 / float(maxi(1, piece.height))
	return clampf(minf(max_w, max_h), 18.0, 32.0)


func _get_hold_cell_size(piece: PieceCatalog.Piece) -> float:
	if piece == null:
		return 24.0
	if piece.is_special():
		return 38.0
	if piece.width == 1 and piece.height == 1:
		return 30.0
	var max_w: float = 138.0 / float(maxi(1, piece.width))
	var max_h: float = 62.0 / float(maxi(1, piece.height))
	return clampf(minf(max_w, max_h), 11.5, 25.0)


func _draw_piece_cells(
	ci: CanvasItem,
	piece: PieceCatalog.Piece,
	center: Vector2,
	cell_size: float,
	alpha: float,
	highlight_boost: float
) -> void:
	var total_w: float = float(piece.width) * cell_size
	var total_h: float = float(piece.height) * cell_size
	var top_left: Vector2 = center - Vector2(total_w * 0.5, total_h * 0.5)

	for c: Vector2i in piece.cells:
		var r: Rect2 = Rect2(
			top_left.x + float(c.x) * cell_size,
			top_left.y + float(c.y) * cell_size,
			cell_size,
			cell_size
		)
		if piece.is_special():
			TilePainter.draw_special_tile(ci, r, piece.special_type, _time, alpha)
		else:
			TilePainter.draw_jewel_tile(ci, r, piece.color_id, alpha, 1.0, highlight_boost)


func _draw_piece_grounded_shadow(
	ci: CanvasItem,
	piece: PieceCatalog.Piece,
	center: Vector2,
	cell_size: float,
	offset: Vector2,
	alpha: float
) -> void:
	var total_w: float = float(piece.width) * cell_size
	var total_h: float = float(piece.height) * cell_size
	var top_left: Vector2 = center - Vector2(total_w * 0.5, total_h * 0.5) + offset

	var soft_col: Color = Color(0.02, 0.03, 0.10, alpha * 0.45)
	var core_col: Color = Color(0.02, 0.03, 0.10, alpha * 0.85)
	for c: Vector2i in piece.cells:
		var r: Rect2 = Rect2(
			top_left.x + float(c.x) * cell_size,
			top_left.y + float(c.y) * cell_size,
			cell_size,
			cell_size
		)
		ci.draw_rect(r.grow(1.8), soft_col, true)
		ci.draw_rect(r.grow(-0.5), core_col, true)


func _draw_piece_shadow_at_origin(
	ci: CanvasItem,
	piece: PieceCatalog.Piece,
	cell_size: float,
	alpha: float,
	expand_px: float
) -> void:
	var total_w: float = float(piece.width) * cell_size
	var total_h: float = float(piece.height) * cell_size
	var top_left: Vector2 = Vector2(-total_w * 0.5, -total_h * 0.5)
	var col: Color = Color(0.02, 0.03, 0.11, alpha)
	for c: Vector2i in piece.cells:
		var r: Rect2 = Rect2(
			top_left.x + float(c.x) * cell_size,
			top_left.y + float(c.y) * cell_size,
			cell_size,
			cell_size
		)
		ci.draw_rect(r.grow(expand_px), col, true)


func _draw_piece_silhouette(
	ci: CanvasItem,
	piece: PieceCatalog.Piece,
	center: Vector2,
	cell_size: float,
	col: Color
) -> void:
	var total_w: float = float(piece.width) * cell_size
	var total_h: float = float(piece.height) * cell_size
	var top_left: Vector2 = center - Vector2(total_w * 0.5, total_h * 0.5)
	for c: Vector2i in piece.cells:
		var r: Rect2 = Rect2(
			top_left.x + float(c.x) * cell_size,
			top_left.y + float(c.y) * cell_size,
			cell_size,
			cell_size
		)
		ci.draw_rect(r.grow(-1.0), col, true)


func _draw_special_award_burst(center: Vector2, elapsed: float) -> void:
	var u: float = clampf(elapsed / SPECIAL_AWARD_DURATION, 0.0, 1.0)
	var fade: float = 1.0 - pow(u, 1.6)
	var ring_r: float = lerpf(16.0, 68.0, 1.0 - pow(1.0 - u, 2.5))

	# Expanding golden shockwave ring + warm inner flash.
	draw_circle(center, ring_r * 0.72, Color(1.0, 0.84, 0.24, 0.24 * fade))
	draw_circle(center, ring_r, Color(1.0, 0.86, 0.30, 0.85 * fade), false, lerpf(4.5, 1.2, u), true)

	# 8 outward golden sparkle diamonds.
	for k: int in range(8):
		var angle: float = float(k) * (PI * 0.25) + 0.35 * u
		var dist: float = lerpf(18.0, 60.0, 1.0 - pow(1.0 - u, 2.2))
		var pt: Vector2 = center + Vector2(cos(angle), sin(angle)) * dist
		var spark_r: float = lerpf(5.8, 1.5, u)
		var spark_col: Color = Color(1.0, 0.95, 0.65, fade) if (k & 1) == 0 else Color(1.0, 0.75, 0.18, fade)
		draw_colored_polygon(
			PackedVector2Array([
				pt + Vector2(0.0, -spark_r),
				pt + Vector2(spark_r, 0.0),
				pt + Vector2(0.0, spark_r),
				pt + Vector2(-spark_r, 0.0),
			]),
			spark_col
		)


func _eval_refill_scale(elapsed: float, delay: float) -> float:
	if elapsed < delay:
		return 0.0
	var u: float = clampf((elapsed - delay) / REFILL_DURATION, 0.0, 1.0)
	if u <= 0.65:
		var t1: float = u / 0.65
		var eased: float = 1.0 - pow(1.0 - t1, 3.0)
		return lerpf(0.0, 1.06, eased)
	var t2: float = (u - 0.65) / 0.35
	var settle: float = 0.5 - 0.5 * cos(t2 * PI)
	return lerpf(1.06, 1.0, settle)


func _eval_special_award_scale(elapsed: float) -> float:
	var u: float = clampf(elapsed / SPECIAL_AWARD_DURATION, 0.0, 1.0)
	if u <= 0.42:
		var t1: float = u / 0.42
		return lerpf(0.20, 1.24, 1.0 - pow(1.0 - t1, 3.0))
	if u <= 0.74:
		var t2: float = (u - 0.42) / 0.32
		return lerpf(1.24, 0.96, 0.5 - 0.5 * cos(t2 * PI))
	var t3: float = (u - 0.74) / 0.26
	return lerpf(0.96, 1.0, 0.5 - 0.5 * cos(t3 * PI))


# ==============================================================================
# VECTOR UI PRIMITIVES
# ==============================================================================

func _draw_swap_arrows_icon(center: Vector2, radius: float, col: Color, width: float) -> void:
	# Upper right-pointing arrow
	var y_top: float = center.y - radius * 0.42
	var x_l: float = center.x - radius * 0.75
	var x_r: float = center.x + radius * 0.75
	var head: float = radius * 0.42
	draw_line(Vector2(x_l, y_top), Vector2(x_r, y_top), col, width, true)
	draw_line(Vector2(x_r - head, y_top - head * 0.75), Vector2(x_r, y_top), col, width, true)
	draw_line(Vector2(x_r - head, y_top + head * 0.75), Vector2(x_r, y_top), col, width, true)

	# Lower left-pointing arrow
	var y_bot: float = center.y + radius * 0.42
	draw_line(Vector2(x_r, y_bot), Vector2(x_l, y_bot), col, width, true)
	draw_line(Vector2(x_l + head, y_bot - head * 0.75), Vector2(x_l, y_bot), col, width, true)
	draw_line(Vector2(x_l + head, y_bot + head * 0.75), Vector2(x_l, y_bot), col, width, true)


func _draw_mini_lock_icon(center: Vector2, col: Color) -> void:
	# Lock body
	var body: Rect2 = Rect2(center.x - 4.5, center.y - 0.5, 9.0, 6.5)
	draw_rect(body, col, true)
	# Lock shackle arch
	var arch_pts: PackedVector2Array = PackedVector2Array()
	var arch_center: Vector2 = Vector2(center.x, center.y - 1.0)
	for i: int in range(7):
		var a: float = PI + (float(i) / 6.0) * PI
		arch_pts.append(arch_center + Vector2(cos(a) * 3.0, sin(a) * 3.8))
	draw_polyline(arch_pts, col, 1.5, true)


func _draw_dashed_rect(r: Rect2, col: Color, dash_len: float, gap_len: float, width: float) -> void:
	var edges: Array[Array] = [
		[r.position, Vector2(r.end.x, r.position.y)],
		[Vector2(r.end.x, r.position.y), r.end],
		[r.end, Vector2(r.position.x, r.end.y)],
		[Vector2(r.position.x, r.end.y), r.position],
	]
	for edge: Array in edges:
		var a: Vector2 = edge[0] as Vector2
		var b: Vector2 = edge[1] as Vector2
		var vec: Vector2 = b - a
		var total: float = vec.length()
		if total <= 0.1:
			continue
		var dir: Vector2 = vec / total
		var d: float = 0.0
		while d < total:
			var seg_end: float = minf(d + dash_len, total)
			draw_line(a + dir * d, a + dir * seg_end, col, width, true)
			d += dash_len + gap_len


func _build_rounded_rect_points(r: Rect2, radius: float) -> PackedVector2Array:
	var rad: float = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var pts: PackedVector2Array = PackedVector2Array()
	var segs: int = 5
	var centers: Array[Vector2] = [
		Vector2(r.end.x - rad, r.position.y + rad),
		Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.position.y + rad),
	]
	var start_angles: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	for corner_idx: int in range(4):
		var c: Vector2 = centers[corner_idx]
		var a0: float = start_angles[corner_idx]
		for s: int in range(segs + 1):
			var a: float = a0 + (float(s) / float(segs)) * (PI * 0.5)
			pts.append(c + Vector2(cos(a), sin(a)) * rad)
	return pts


func _draw_rounded_rect_fill(ci: CanvasItem, r: Rect2, radius: float, col: Color) -> void:
	ci.draw_colored_polygon(_build_rounded_rect_points(r, radius), col)


func _draw_rounded_rect_stroke(ci: CanvasItem, r: Rect2, radius: float, col: Color, width: float) -> void:
	var pts: PackedVector2Array = _build_rounded_rect_points(r, radius)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width, true)


func _draw_centered_text(
	ci: CanvasItem,
	font: Font,
	center: Vector2,
	text: String,
	font_size: int,
	fill_color: Color,
	outline_color: Color,
	outline_size: int
) -> void:
	if font == null or text.is_empty():
		return
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	var baseline: Vector2 = Vector2(
		center.x - text_size.x * 0.5,
		center.y + (ascent - descent) * 0.45
	)
	if outline_size > 0:
		ci.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, outline_color)
	ci.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill_color)
