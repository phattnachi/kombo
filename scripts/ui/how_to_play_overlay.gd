class_name HowToPlayOverlay
extends Control

## Visual, scannable Dark-Indigo 3D How to Play guide for Kombo by SOYA GAMES.
## Uses live TilePainter jewel blocks, glowing x2/x3 multiplier tiles, and animated
## Bomb & Lightning special tiles so new players grasp every mechanic in 5 seconds.

signal closed()

const OVERLAY_SIZE := Vector2(540.0, 960.0)
const CARD_SIZE := Vector2(436.0, 672.0)
const HEADER_HEIGHT := 68.0
const GOT_IT_BTN_RECT := Rect2(98.0, 598.0, 240.0, 52.0)

const FONT_EXTRABOLD_PATH := "res://assets/fonts/Kanit-ExtraBold.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/Kanit-Bold.ttf"
const FONT_SEMIBOLD_PATH := "res://assets/fonts/Kanit-SemiBold.ttf"

var _font_extrabold: Font
var _font_bold: Font
var _font_semibold: Font
var _radial_glow_tex: GradientTexture2D

var _sb_card_shadow: StyleBoxFlat
var _sb_card_lip: StyleBoxFlat
var _sb_card_body: StyleBoxFlat
var _sb_card_inner: StyleBoxFlat
var _sb_card_rim: StyleBoxFlat
var _sb_rule_box: StyleBoxFlat
var _sb_icon_stage: StyleBoxFlat

var _is_open: bool = false
var _time_sec: float = 0.0
var _backdrop_alpha: float = 0.0
var _card_alpha: float = 0.0
var _card_scale: float = 0.84
var _card_scale_vel: float = 0.0
var _card_y_offset: float = 20.0

var _card: _GuideCard
var _close_btn: _GuideCloseButton
var _got_it_btn: _GotItButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_load_fonts()
	_init_cached_styles()
	_build_card()
	_apply_card_transform()
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _card != null:
		_apply_card_transform()


func _input(event: InputEvent) -> void:
	if not visible or not _is_open:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_ESCAPE or ke.keycode == KEY_SPACE or ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
				get_viewport().set_input_as_handled()
				close_guide(true)


func _gui_input(event: InputEvent) -> void:
	if not visible or not _is_open:
		return
	var clicked_outside := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _card != null and not _card.get_rect().has_point(mb.position):
				clicked_outside = true
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _card != null and not _card.get_rect().has_point(st.position):
				clicked_outside = true
	if clicked_outside:
		accept_event()
		close_guide(true)


func _process(delta: float) -> void:
	if not visible:
		return
	var dt := minf(delta, 0.05)
	_time_sec += dt

	_backdrop_alpha = move_toward(_backdrop_alpha, 1.0, dt * 5.2)
	_card_alpha = move_toward(_card_alpha, 1.0, dt * 5.8)
	_card_y_offset = lerpf(_card_y_offset, 0.0, clampf(16.0 * dt, 0.0, 1.0))

	var cs := GameOverOverlay._step_spring(_card_scale, _card_scale_vel, 1.0, 290.0, 18.0, dt)
	_card_scale = cs.x
	_card_scale_vel = cs.y

	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


# ==============================================================================
# PUBLIC API
# ==============================================================================

func open_guide() -> void:
	_is_open = true
	_backdrop_alpha = 0.0
	_card_alpha = 0.0
	_card_scale = 0.82
	_card_scale_vel = 4.2
	_card_y_offset = 22.0
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


func close_guide(emit_closed: bool = true) -> void:
	if not _is_open and not visible:
		return
	_is_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	if emit_closed:
		closed.emit()


func is_open() -> bool:
	return _is_open and visible


func snap_entrance_for_preview() -> void:
	_backdrop_alpha = 1.0
	_card_alpha = 1.0
	_card_scale = 1.0
	_card_scale_vel = 0.0
	_card_y_offset = 0.0
	_time_sec = 0.65
	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


# ==============================================================================
# SETUP & LAYOUT
# ==============================================================================

func _load_fonts() -> void:
	if ResourceLoader.exists(FONT_EXTRABOLD_PATH):
		_font_extrabold = load(FONT_EXTRABOLD_PATH) as Font
	if ResourceLoader.exists(FONT_BOLD_PATH):
		_font_bold = load(FONT_BOLD_PATH) as Font
	if ResourceLoader.exists(FONT_SEMIBOLD_PATH):
		_font_semibold = load(FONT_SEMIBOLD_PATH) as Font
	if _font_extrabold == null:
		_font_extrabold = ThemeDB.fallback_font
	if _font_bold == null:
		_font_bold = _font_extrabold
	if _font_semibold == null:
		_font_semibold = _font_bold


func _init_cached_styles() -> void:
	_radial_glow_tex = GameOverOverlay._create_radial_glow_texture()
	TilePainter.warm_cache()

	_sb_card_shadow = StyleBoxFlat.new()
	_sb_card_shadow.bg_color = Color(0.01, 0.02, 0.07, 0.70)
	_sb_card_shadow.set_corner_radius_all(24)
	_sb_card_shadow.corner_detail = 10

	_sb_card_lip = StyleBoxFlat.new()
	_sb_card_lip.bg_color = Color("#070C22")
	_sb_card_lip.set_corner_radius_all(24)
	_sb_card_lip.corner_detail = 10

	_sb_card_body = StyleBoxFlat.new()
	_sb_card_body.bg_color = Color("#111A3E")
	_sb_card_body.set_corner_radius_all(24)
	_sb_card_body.corner_detail = 10

	_sb_card_inner = StyleBoxFlat.new()
	_sb_card_inner.draw_center = false
	_sb_card_inner.set_corner_radius_all(20)
	_sb_card_inner.corner_detail = 8
	_sb_card_inner.set_border_width_all(1)
	_sb_card_inner.border_color = Color(0.42, 0.58, 0.96, 0.18)

	_sb_card_rim = StyleBoxFlat.new()
	_sb_card_rim.draw_center = false
	_sb_card_rim.set_corner_radius_all(24)
	_sb_card_rim.corner_detail = 10
	_sb_card_rim.set_border_width_all(3)
	_sb_card_rim.border_color = Color("#4C7CFF")

	_sb_rule_box = StyleBoxFlat.new()
	_sb_rule_box.bg_color = Color(0.052, 0.082, 0.210, 0.92)
	_sb_rule_box.set_corner_radius_all(15)
	_sb_rule_box.corner_detail = 8
	_sb_rule_box.set_border_width_all(1)
	_sb_rule_box.border_color = Color(0.32, 0.48, 0.88, 0.34)

	_sb_icon_stage = StyleBoxFlat.new()
	_sb_icon_stage.bg_color = Color(0.032, 0.052, 0.140, 0.95)
	_sb_icon_stage.set_corner_radius_all(11)
	_sb_icon_stage.corner_detail = 6
	_sb_icon_stage.set_border_width_all(1)
	_sb_icon_stage.border_color = Color(0.26, 0.40, 0.78, 0.32)


func _build_card() -> void:
	_card = _GuideCard.new()
	_card.name = "GuideCard"
	_card.overlay = self
	_card.size = CARD_SIZE
	_card.pivot_offset = CARD_SIZE * 0.5
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)

	_close_btn = _GuideCloseButton.new()
	_close_btn.name = "CloseGuideButton"
	_close_btn.size = Vector2(36.0, 36.0)
	_close_btn.position = Vector2(CARD_SIZE.x - 52.0, 16.0)
	_close_btn.pressed_clean.connect(func() -> void: close_guide(true))
	_card.add_child(_close_btn)

	_got_it_btn = _GotItButton.new()
	_got_it_btn.name = "GotItButton"
	_got_it_btn.font_extrabold = _font_extrabold
	_got_it_btn.position = GOT_IT_BTN_RECT.position
	_got_it_btn.size = GOT_IT_BTN_RECT.size
	_got_it_btn.pressed_clean.connect(func() -> void: close_guide(true))
	_card.add_child(_got_it_btn)


func _apply_card_transform() -> void:
	if _card == null:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	var base_pos := (view_size - CARD_SIZE) * 0.5
	_card.position = base_pos + Vector2(0.0, _card_y_offset)
	_card.pivot_offset = CARD_SIZE * 0.5
	_card.scale = Vector2(_card_scale, _card_scale)
	_card.modulate = Color(1.0, 1.0, 1.0, _card_alpha)


# ==============================================================================
# BACKDROP & ILLUSTRATED GUIDE RENDERING
# ==============================================================================

func _draw() -> void:
	if not visible:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.025, 0.040, 0.115, 0.82 * _backdrop_alpha), true)

	if _radial_glow_tex != null:
		var center := view_size * 0.5
		var pulse := 0.5 + 0.5 * sin(_time_sec * 2.8)
		var half := Vector2(330.0, 390.0)
		draw_texture_rect(
			_radial_glow_tex,
			Rect2(center - half, half * 2.0),
			false,
			Color(0.16, 0.62, 1.0, (0.24 + 0.06 * pulse) * _backdrop_alpha)
		)


func _draw_card(ci: CanvasItem) -> void:
	var card_rect := Rect2(Vector2.ZERO, CARD_SIZE)
	var cid := ci.get_canvas_item()

	# 1. Card shadow, 3D navy lip, body & inner frame.
	_sb_card_shadow.draw(cid, Rect2(Vector2(0.0, 12.0), CARD_SIZE))
	_sb_card_lip.draw(cid, Rect2(Vector2(0.0, 6.0), CARD_SIZE))
	_sb_card_body.draw(cid, card_rect)
	_sb_card_inner.draw(cid, card_rect.grow(-4.0))

	# 2. Gradient header with cyan-gold energy seam.
	var header_rect := Rect2(Vector2.ZERO, Vector2(CARD_SIZE.x, HEADER_HEIGHT))
	SettingsOverlay._draw_top_rounded_header(ci, header_rect, Color("#24367A"), Color("#141F4F"), 24.0)
	ci.draw_polygon(
		PackedVector2Array([
			Vector2(2.0, HEADER_HEIGHT - 3.0),
			Vector2(CARD_SIZE.x * 0.5, HEADER_HEIGHT - 3.0),
			Vector2(CARD_SIZE.x * 0.5, HEADER_HEIGHT + 0.5),
			Vector2(2.0, HEADER_HEIGHT + 0.5),
		]),
		PackedColorArray([Color("#18D5FF"), Color("#FFD43B"), Color("#FFD43B"), Color("#18D5FF")])
	)
	ci.draw_polygon(
		PackedVector2Array([
			Vector2(CARD_SIZE.x * 0.5, HEADER_HEIGHT - 3.0),
			Vector2(CARD_SIZE.x - 2.0, HEADER_HEIGHT - 3.0),
			Vector2(CARD_SIZE.x - 2.0, HEADER_HEIGHT + 0.5),
			Vector2(CARD_SIZE.x * 0.5, HEADER_HEIGHT + 0.5),
		]),
		PackedColorArray([Color("#FFD43B"), Color("#18D5FF"), Color("#18D5FF"), Color("#FFD43B")])
	)
	_sb_card_rim.draw(cid, card_rect)

	GameOverOverlay._draw_centered_outlined_text(
		ci,
		_font_extrabold,
		Vector2(CARD_SIZE.x * 0.5, HEADER_HEIGHT * 0.5),
		"HOW TO PLAY",
		28,
		Color("#FFFFFF"),
		Color("#090F2B"),
		6,
		2.2
	)

	# 3. Five Illustrated Scannable Rule Cards.
	var rules: Array[Dictionary] = [
		{
			"title": "DRAG & CLEAR",
			"accent": Color("#56E6FF"),
			"line1": "Drag pieces onto the 8×8 board.",
			"line2": "Fill any full row or column to clear!",
		},
		{
			"title": "HOLD SLOT",
			"accent": Color("#FFD94D"),
			"line1": "Stash 1 tricky block inside HOLD",
			"line2": "and swap it back whenever it fits.",
		},
		{
			"title": "COMBO & ×2 / ×3 TILES",
			"accent": Color("#FF7AD9"),
			"line1": "Clear on back-to-back turns for Combos.",
			"line2": "Clear over ×2 or ×3 tiles to multiply!",
		},
		{
			"title": "BOMB & LIGHTNING",
			"accent": Color("#FF9442"),
			"line1": "2 lines at once → Bomb (3×3 blast).",
			"line2": "3+ lines at once → Lightning (cross)!",
		},
		{
			"title": "FEVER MODE",
			"accent": Color("#FFE65C"),
			"line1": "Chain clears to charge the FEVER bar.",
			"line2": "Ignite FEVER for blazing score boosts!",
		},
	]

	for i in range(rules.size()):
		var r := rules[i]
		var box_rect := Rect2(18.0, 82.0 + float(i) * 100.0, CARD_SIZE.x - 36.0, 90.0)
		_sb_rule_box.draw(cid, box_rect)

		# Left mini-illustration stage.
		var stage_rect := Rect2(box_rect.position.x + 9.0, box_rect.position.y + 9.0, 82.0, 72.0)
		_sb_icon_stage.draw(cid, stage_rect)
		_draw_rule_illustration(ci, i, stage_rect)

		# Right headline + crisp 2-line caption.
		var text_x := stage_rect.end.x + 12.0
		GameOverOverlay._draw_left_outlined_text(
			ci,
			_font_extrabold,
			Vector2(text_x, box_rect.position.y + 23.0),
			String(r["title"]),
			15,
			r["accent"] as Color,
			Color("#070B1E"),
			4,
			1.2
		)
		ci.draw_string(
			_font_semibold,
			Vector2(text_x, box_rect.position.y + 52.0),
			String(r["line1"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color("#E8F2FF")
		)
		ci.draw_string(
			_font_semibold,
			Vector2(text_x, box_rect.position.y + 72.0),
			String(r["line2"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color("#B4CBF5")
		)


func _draw_rule_illustration(ci: CanvasItem, kind: int, stage: Rect2) -> void:
	var c := stage.get_center()
	var pulse := 0.5 + 0.5 * sin(_time_sec * 4.5)

	match kind:
		0: # Mini 4x3 grid with glowing full-row clear!
			var cell := 16.0
			var gx := c.x - cell * 2.0
			var gy := c.y - cell * 1.5
			var row_colors: Array[int] = [0, 1, 3, 5]
			for r in range(3):
				for col in range(4):
					var cell_rect := Rect2(gx + float(col) * cell, gy + float(r) * cell, cell, cell)
					if r == 1:
						TilePainter.draw_jewel_tile(ci, cell_rect.grow(-0.5), row_colors[col], 1.0, 1.0, 0.35 + 0.25 * pulse)
					elif (r == 0 and col == 1) or (r == 2 and col == 2):
						TilePainter.draw_jewel_tile(ci, cell_rect.grow(-0.5), 4 if r == 0 else 6, 0.92, 1.0, 0.0)
					else:
						TilePainter.draw_empty_cell(ci, cell_rect, r, col, 1, _time_sec)
			# Luminous golden sweep highlight across the completed row!
			var beam := Rect2(gx - 2.0, gy + cell + 1.0, cell * 4.0 + 4.0, cell - 2.0)
			ci.draw_rect(beam, Color(1.0, 0.92, 0.45, 0.22 + 0.16 * pulse), true)
			ci.draw_rect(beam, Color("#FFE45C", 0.85), false, 1.6, true)

		1: # Mini HOLD dock with a jewel L-block & cyan swap badge!
			var dock := Rect2(stage.position.x + 6.0, c.y - 22.0, stage.size.x - 12.0, 44.0)
			GameOverOverlay._draw_rounded_rect_static(ci, dock, Color("#152048"), 10.0)
			var dock_pts := GameOverOverlay._build_rounded_rect_points(dock, 10.0)
			if not dock_pts.is_empty():
				dock_pts.append(dock_pts[0])
				ci.draw_polyline(dock_pts, Color("#28E8FF", 0.72 + 0.22 * pulse), 1.8, true)
			# Mini jewel L-piece inside dock.
			var sz := 13.0
			var bx := dock.position.x + 11.0
			var by := dock.position.y + 9.0
			TilePainter.draw_jewel_tile(ci, Rect2(bx, by, sz, sz), 5, 1.0, 1.0, 0.12)
			TilePainter.draw_jewel_tile(ci, Rect2(bx, by + sz, sz, sz), 5, 1.0, 1.0, 0.12)
			TilePainter.draw_jewel_tile(ci, Rect2(bx + sz, by + sz, sz, sz), 5, 1.0, 1.0, 0.12)
			# Crisp swap arrows on right side of mini dock.
			var ax := dock.end.x - 17.0
			var ay := dock.get_center().y
			var acol := Color("#3AE8FF")
			ci.draw_line(Vector2(ax - 7.0, ay - 4.0), Vector2(ax + 6.0, ay - 4.0), acol, 2.0, true)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(ax + 8.0, ay - 4.0), Vector2(ax + 3.0, ay - 7.5), Vector2(ax + 3.0, ay - 0.5)]), acol)
			ci.draw_line(Vector2(ax + 7.0, ay + 4.0), Vector2(ax - 6.0, ay + 4.0), Color("#FFD94D"), 2.0, true)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(ax - 8.0, ay + 4.0), Vector2(ax - 3.0, ay + 0.5), Vector2(ax - 3.0, ay + 7.5)]), Color("#FFD94D"))

		2: # Real live x2 and x3 multiplier tiles!
			var tile_sz := 32.0
			var r_x2 := Rect2(c.x - tile_sz - 2.0, c.y - tile_sz * 0.5 - 5.0, tile_sz, tile_sz)
			var r_x3 := Rect2(c.x + 2.0, c.y - tile_sz * 0.5 + 5.0, tile_sz, tile_sz)
			TilePainter.draw_empty_cell(ci, r_x2, 0, 0, 2, _time_sec)
			TilePainter.draw_empty_cell(ci, r_x3, 1, 1, 3, _time_sec)

		3: # Real live animated Bomb & Lightning special blocks!
			var sz := 33.0
			var b_rect := Rect2(c.x - sz - 3.0, c.y - sz * 0.5, sz, sz)
			var l_rect := Rect2(c.x + 3.0, c.y - sz * 0.5, sz, sz)
			if _radial_glow_tex != null:
				ci.draw_texture_rect(_radial_glow_tex, b_rect.grow(10.0), false, Color(1.0, 0.36, 0.14, 0.34 + 0.12 * pulse))
				ci.draw_texture_rect(_radial_glow_tex, l_rect.grow(10.0), false, Color(0.14, 0.86, 1.0, 0.34 + 0.12 * pulse))
			TilePainter.draw_special_tile(ci, b_rect, TilePainter.SPECIAL_BOMB, _time_sec, 1.0)
			TilePainter.draw_special_tile(ci, l_rect, TilePainter.SPECIAL_LIGHTNING, _time_sec, 1.0)

		4: # Blazing FEVER gauge + glowing flame emblem!
			if _radial_glow_tex != null:
				ci.draw_texture_rect(_radial_glow_tex, Rect2(c - Vector2(36.0, 30.0), Vector2(72.0, 60.0)), false, Color(1.0, 0.48, 0.12, 0.36 + 0.14 * pulse))
			GameOverOverlay._draw_flame_icon(ci, c + Vector2(0.0, -10.0), 14.5, _time_sec)
			var bar := Rect2(stage.position.x + 9.0, stage.end.y - 20.0, stage.size.x - 18.0, 11.0)
			GameOverOverlay._draw_rounded_rect_static(ci, bar, Color("#1D0B12"), 5.0)
			var fill := Rect2(bar.position + Vector2(1.5, 1.5), Vector2(bar.size.x - 3.0, bar.size.y - 3.0))
			GameOverOverlay._draw_rounded_rect_static(ci, fill, Color("#FF7818").lerp(Color("#FFE048"), 0.35 + 0.25 * pulse), 4.0)
			var bar_pts := GameOverOverlay._build_rounded_rect_points(bar, 5.0)
			if not bar_pts.is_empty():
				bar_pts.append(bar_pts[0])
				ci.draw_polyline(bar_pts, Color("#FFE46B", 0.90), 1.4, true)


# ==============================================================================
# INNER CLASSES: CARD, CLOSE BUTTON, JUICY GOT IT BUTTON
# ==============================================================================

class _GuideCard extends Control:
	var overlay: HowToPlayOverlay

	func _draw() -> void:
		if overlay != null:
			overlay._draw_card(self)


class _GuideCloseButton extends Control:
	signal pressed_clean()

	var _hovered: bool = false
	var _pressed: bool = false
	var _scale_v: float = 1.0
	var _sb_bg: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())
		_sb_bg = StyleBoxFlat.new()
		_sb_bg.set_corner_radius_all(10)
		_sb_bg.corner_detail = 6
		_sb_bg.set_border_width_all(1)
		set_process(true)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var target := 0.90 if _pressed else (1.08 if _hovered else 1.0)
		if absf(_scale_v - target) > 0.002:
			_scale_v = lerpf(_scale_v, target, clampf(18.0 * minf(delta, 0.05), 0.0, 1.0))
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressed = true
					queue_redraw()
					accept_event()
				else:
					var was := _pressed
					_pressed = false
					queue_redraw()
					if was and Rect2(Vector2.ZERO, size).has_point(mb.position):
						pressed_clean.emit()
					accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_pressed = true
				queue_redraw()
				accept_event()
			else:
				var was := _pressed
				_pressed = false
				queue_redraw()
				if was and Rect2(Vector2.ZERO, size).has_point(st.position):
					pressed_clean.emit()
				accept_event()

	func _draw() -> void:
		var c := size * 0.5
		draw_set_transform(c, 0.0, Vector2(_scale_v, _scale_v))
		_sb_bg.bg_color = Color(0.24, 0.34, 0.72, 0.65) if _hovered else Color(0.08, 0.12, 0.30, 0.58)
		_sb_bg.border_color = Color(0.62, 0.80, 1.0, 0.68) if _hovered else Color(0.42, 0.58, 0.94, 0.38)
		_sb_bg.draw(get_canvas_item(), Rect2(-c, size))
		var col := Color("#FFFFFF") if _hovered else Color("#CFE2FF")
		draw_line(Vector2(-6.5, -6.5), Vector2(6.5, 6.5), col, 2.8, true)
		draw_line(Vector2(-6.5, 6.5), Vector2(6.5, -6.5), col, 2.8, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _GotItButton extends Control:
	signal pressed_clean()

	var font_extrabold: Font
	var _hovered: bool = false
	var _pressed: bool = false
	var _btn_scale: float = 1.0
	var _sb_shadow: StyleBoxFlat
	var _sb_lip: StyleBoxFlat
	var _sb_face: StyleBoxFlat
	var _sb_gloss: StyleBoxFlat
	var _sb_rim: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())

		_sb_shadow = StyleBoxFlat.new()
		_sb_shadow.bg_color = Color(0.01, 0.05, 0.03, 0.60)
		_sb_shadow.set_corner_radius_all(16)
		_sb_shadow.corner_detail = 8

		_sb_lip = StyleBoxFlat.new()
		_sb_lip.bg_color = Color("#086B2B")
		_sb_lip.set_corner_radius_all(16)
		_sb_lip.corner_detail = 8

		_sb_face = StyleBoxFlat.new()
		_sb_face.set_corner_radius_all(15)
		_sb_face.corner_detail = 8

		_sb_gloss = StyleBoxFlat.new()
		_sb_gloss.bg_color = Color(1.0, 1.0, 0.88, 0.26)
		_sb_gloss.corner_radius_top_left = 12
		_sb_gloss.corner_radius_top_right = 12
		_sb_gloss.corner_radius_bottom_left = 5
		_sb_gloss.corner_radius_bottom_right = 5
		_sb_gloss.corner_detail = 6

		_sb_rim = StyleBoxFlat.new()
		_sb_rim.draw_center = false
		_sb_rim.set_corner_radius_all(15)
		_sb_rim.corner_detail = 8
		_sb_rim.set_border_width_all(2)
		_sb_rim.border_color = Color("#C8FF82")
		set_process(true)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var target := 0.95 if _pressed else (1.04 if _hovered else 1.0)
		if absf(_btn_scale - target) > 0.002:
			_btn_scale = lerpf(_btn_scale, target, clampf(18.0 * minf(delta, 0.05), 0.0, 1.0))
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressed = true
					queue_redraw()
					accept_event()
				else:
					var was := _pressed
					_pressed = false
					queue_redraw()
					if was and Rect2(Vector2.ZERO, size).has_point(mb.position):
						pressed_clean.emit()
					accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_pressed = true
				queue_redraw()
				accept_event()
			else:
				var was := _pressed
				_pressed = false
				queue_redraw()
				if was and Rect2(Vector2.ZERO, size).has_point(st.position):
					pressed_clean.emit()
				accept_event()

	func _draw() -> void:
		var cid := get_canvas_item()
		var c := size * 0.5
		var local_rect := Rect2(-c, size)
		var press_drop := 3.5 if _pressed else 0.0
		var lip_h := 2.0 if _pressed else 6.0

		draw_set_transform(c, 0.0, Vector2(_btn_scale, _btn_scale))
		_sb_shadow.draw(cid, Rect2(local_rect.position + Vector2(0.0, 5.0), local_rect.size))

		var outer := Rect2(local_rect.position + Vector2(0.0, press_drop), Vector2(local_rect.size.x, local_rect.size.y - press_drop))
		_sb_lip.draw(cid, outer)

		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		_sb_face.bg_color = Color("#34E867") if _hovered else Color("#1FD152")
		_sb_face.draw(cid, face)
		_sb_gloss.draw(cid, Rect2(face.position + Vector2(10.0, 3.0), Vector2(face.size.x - 20.0, face.size.y * 0.36)))
		_sb_rim.draw(cid, face)

		var used_font := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		GameOverOverlay._draw_centered_outlined_text(self, used_font, face.get_center() + Vector2(0.0, -0.5), "GOT IT!", 23, Color("#FFFFFF"), Color("#053D16"), 5, 1.8)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
