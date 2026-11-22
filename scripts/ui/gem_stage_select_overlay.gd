class_name GemStageSelectOverlay
extends Control

## Dark-Indigo 3D Stage Select modal for Kombo's Gem Hunt mode.
## Shows all unlocked stages (cleared with golden stars, frontier highlighted,
## locked stages previewed), optional 1-tap RESUME banner for in-progress runs,
## and infinite pagination (12 stages per page) for deep stage climbers.

signal stage_selected(stage: int)
signal resume_pressed()
signal closed()

const OVERLAY_SIZE := Vector2(540.0, 960.0)
const CARD_WIDTH := 436.0
const CARD_HEIGHT_BASE := 574.0
const CARD_HEIGHT_WITH_RESUME := 646.0
const HEADER_HEIGHT := 72.0
const STAGES_PER_PAGE := 12

const FONT_EXTRABOLD_PATH := "res://assets/fonts/Kanit-ExtraBold.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/Kanit-Bold.ttf"

var _font_extrabold: Font
var _font_bold: Font
var _radial_glow_tex: GradientTexture2D

var _sb_card_shadow: StyleBoxFlat
var _sb_card_lip: StyleBoxFlat
var _sb_card_body: StyleBoxFlat
var _sb_card_inner: StyleBoxFlat
var _sb_card_rim: StyleBoxFlat

var _is_open: bool = false
var _best_stage: int = 1
var _best_score: int = 0
var _can_resume: bool = false
var _resume_stage: int = 1
var _resume_targets_left: int = 0
var _resume_score: int = 0
var _page_index: int = 0

var _time_sec: float = 0.0
var _backdrop_alpha: float = 0.0
var _card_alpha: float = 0.0
var _card_scale: float = 0.84
var _card_scale_vel: float = 0.0
var _card_y_offset: float = 20.0

var _card: _StageSelectCard
var _close_btn: _SelectCloseButton
var _resume_btn: _ResumeBannerButton
var _stage_tiles: Array[_StageTileButton] = []
var _prev_page_btn: _PageNavButton
var _next_page_btn: _PageNavButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_load_fonts()
	_init_cached_styles()
	_build_card()
	_layout_contents()
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
			if ke.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				close_selector(true)
			elif ke.keycode == KEY_SPACE or ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
				get_viewport().set_input_as_handled()


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
		close_selector(true)


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

func open_selector(
	best_stage: int,
	best_score: int,
	can_resume: bool = false,
	resume_stage: int = 1,
	resume_targets_left: int = 0,
	resume_score: int = 0
) -> void:
	_best_stage = maxi(1, best_stage)
	_best_score = maxi(0, best_score)
	_can_resume = can_resume
	_resume_stage = maxi(1, resume_stage)
	_resume_targets_left = maxi(0, resume_targets_left)
	_resume_score = maxi(0, resume_score)

	# Open on the page containing the player's current frontier stage!
	_page_index = (_best_stage - 1) / STAGES_PER_PAGE

	_is_open = true
	_backdrop_alpha = 0.0
	_card_alpha = 0.0
	_card_scale = 0.82
	_card_scale_vel = 4.2
	_card_y_offset = 22.0

	_layout_contents()
	_refresh_page_tiles()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


func close_selector(emit_closed: bool = true) -> void:
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
	if _font_extrabold == null:
		_font_extrabold = ThemeDB.fallback_font
	if _font_bold == null:
		_font_bold = _font_extrabold


func _init_cached_styles() -> void:
	_radial_glow_tex = GameOverOverlay._create_radial_glow_texture()

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
	_sb_card_inner.border_color = Color(0.32, 0.72, 0.96, 0.22)

	_sb_card_rim = StyleBoxFlat.new()
	_sb_card_rim.draw_center = false
	_sb_card_rim.set_corner_radius_all(24)
	_sb_card_rim.corner_detail = 10
	_sb_card_rim.set_border_width_all(3)
	_sb_card_rim.border_color = Color("#34D6FF")


func _build_card() -> void:
	_card = _StageSelectCard.new()
	_card.name = "StageSelectCard"
	_card.overlay = self
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)

	_close_btn = _SelectCloseButton.new()
	_close_btn.name = "CloseStagesButton"
	_close_btn.size = Vector2(36.0, 36.0)
	_close_btn.position = Vector2(CARD_WIDTH - 52.0, 18.0)
	_close_btn.pressed_clean.connect(func() -> void: close_selector(true))
	_card.add_child(_close_btn)

	_resume_btn = _ResumeBannerButton.new()
	_resume_btn.name = "ResumeGemBanner"
	_resume_btn.font_extrabold = _font_extrabold
	_resume_btn.font_bold = _font_bold
	_resume_btn.size = Vector2(CARD_WIDTH - 40.0, 58.0)
	_resume_btn.pressed_clean.connect(_on_resume_clicked)
	_card.add_child(_resume_btn)

	_stage_tiles.clear()
	for i in range(STAGES_PER_PAGE):
		var tile := _StageTileButton.new()
		tile.name = "StageTile_%02d" % i
		tile.font_extrabold = _font_extrabold
		tile.font_bold = _font_bold
		tile.size = Vector2(124.0, 96.0)
		tile.stage_clicked.connect(_on_stage_tile_clicked)
		_card.add_child(tile)
		_stage_tiles.append(tile)

	_prev_page_btn = _PageNavButton.new()
	_prev_page_btn.name = "PrevPageBtn"
	_prev_page_btn.is_next = false
	_prev_page_btn.font_extrabold = _font_extrabold
	_prev_page_btn.size = Vector2(44.0, 36.0)
	_prev_page_btn.pressed_clean.connect(_on_prev_page)
	_card.add_child(_prev_page_btn)

	_next_page_btn = _PageNavButton.new()
	_next_page_btn.name = "NextPageBtn"
	_next_page_btn.is_next = true
	_next_page_btn.font_extrabold = _font_extrabold
	_next_page_btn.size = Vector2(44.0, 36.0)
	_next_page_btn.pressed_clean.connect(_on_next_page)
	_card.add_child(_next_page_btn)


func _get_card_size() -> Vector2:
	return Vector2(CARD_WIDTH, CARD_HEIGHT_WITH_RESUME if _can_resume else CARD_HEIGHT_BASE)


func _layout_contents() -> void:
	if _card == null:
		return
	var cs := _get_card_size()
	_card.size = cs
	_card.pivot_offset = cs * 0.5

	_resume_btn.visible = _can_resume
	if _can_resume:
		_resume_btn.position = Vector2(20.0, HEADER_HEIGHT + 16.0)
		_resume_btn.set_info(_resume_stage, _resume_targets_left, _resume_score)

	var grid_top := HEADER_HEIGHT + (88.0 if _can_resume else 20.0)
	var col_w := 124.0
	var row_h := 96.0
	var gap_x := 12.0
	var gap_y := 12.0
	var grid_w := col_w * 3.0 + gap_x * 2.0
	var start_x := (CARD_WIDTH - grid_w) * 0.5

	for idx in range(_stage_tiles.size()):
		var col := idx % 3
		var row := idx / 3
		_stage_tiles[idx].position = Vector2(
			start_x + float(col) * (col_w + gap_x),
			grid_top + float(row) * (row_h + gap_y)
		)

	var nav_y := cs.y - 52.0
	_prev_page_btn.position = Vector2(22.0, nav_y)
	_next_page_btn.position = Vector2(CARD_WIDTH - 22.0 - 44.0, nav_y)


func _refresh_page_tiles() -> void:
	var base_stage := _page_index * STAGES_PER_PAGE + 1
	for i in range(_stage_tiles.size()):
		var stg := base_stage + i
		var state_kind := 0 # 0 = locked, 1 = current unlocked, 2 = cleared
		if stg < _best_stage:
			state_kind = 2
		elif stg == _best_stage:
			state_kind = 1
		else:
			state_kind = 0
		_stage_tiles[i].configure(stg, state_kind)

	var max_page := maxi(0, (_best_stage) / STAGES_PER_PAGE)
	_prev_page_btn.set_enabled(_page_index > 0)
	_next_page_btn.set_enabled(_page_index < max_page)
	if _card != null:
		_card.queue_redraw()


func _apply_card_transform() -> void:
	if _card == null:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	var cs := _get_card_size()
	var base_pos := (view_size - cs) * 0.5
	_card.position = base_pos + Vector2(0.0, _card_y_offset)
	_card.pivot_offset = cs * 0.5
	_card.scale = Vector2(_card_scale, _card_scale)
	_card.modulate = Color(1.0, 1.0, 1.0, _card_alpha)


func _on_stage_tile_clicked(stage_num: int) -> void:
	close_selector(false)
	stage_selected.emit(stage_num)


func _on_resume_clicked() -> void:
	close_selector(false)
	resume_pressed.emit()


func _on_prev_page() -> void:
	if _page_index > 0:
		_page_index -= 1
		_refresh_page_tiles()


func _on_next_page() -> void:
	var max_page := maxi(0, (_best_stage) / STAGES_PER_PAGE)
	if _page_index < max_page:
		_page_index += 1
		_refresh_page_tiles()


# ==============================================================================
# RENDERING
# ==============================================================================

func _draw() -> void:
	if not visible:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.025, 0.042, 0.115, 0.82 * _backdrop_alpha), true)

	if _radial_glow_tex != null:
		var center := view_size * 0.5
		var pulse := 0.5 + 0.5 * sin(_time_sec * 3.0)
		var half := Vector2(330.0, 390.0)
		draw_texture_rect(
			_radial_glow_tex,
			Rect2(center - half, half * 2.0),
			false,
			Color(0.10, 0.72, 1.0, (0.26 + 0.07 * pulse) * _backdrop_alpha)
		)


func _draw_card(ci: CanvasItem) -> void:
	var cs := _get_card_size()
	var card_rect := Rect2(Vector2.ZERO, cs)
	var cid := ci.get_canvas_item()

	_sb_card_shadow.draw(cid, Rect2(Vector2(0.0, 12.0), cs))
	_sb_card_lip.draw(cid, Rect2(Vector2(0.0, 6.0), cs))
	_sb_card_body.draw(cid, card_rect)
	_sb_card_inner.draw(cid, card_rect.grow(-4.0))

	var header_rect := Rect2(Vector2.ZERO, Vector2(cs.x, HEADER_HEIGHT))
	SettingsOverlay._draw_top_rounded_header(ci, header_rect, Color("#12487A"), Color("#0F2458"), 24.0)
	ci.draw_polygon(
		PackedVector2Array([
			Vector2(2.0, HEADER_HEIGHT - 3.0),
			Vector2(cs.x * 0.5, HEADER_HEIGHT - 3.0),
			Vector2(cs.x * 0.5, HEADER_HEIGHT + 0.5),
			Vector2(2.0, HEADER_HEIGHT + 0.5),
		]),
		PackedColorArray([Color("#2CEEFF"), Color("#FFE066"), Color("#FFE066"), Color("#2CEEFF")])
	)
	ci.draw_polygon(
		PackedVector2Array([
			Vector2(cs.x * 0.5, HEADER_HEIGHT - 3.0),
			Vector2(cs.x - 2.0, HEADER_HEIGHT - 3.0),
			Vector2(cs.x - 2.0, HEADER_HEIGHT + 0.5),
			Vector2(cs.x * 0.5, HEADER_HEIGHT + 0.5),
		]),
		PackedColorArray([Color("#FFE066"), Color("#2CEEFF"), Color("#2CEEFF"), Color("#FFE066")])
	)
	_sb_card_rim.draw(cid, card_rect)

	GameOverOverlay._draw_centered_outlined_text(
		ci,
		_font_extrabold,
		Vector2(cs.x * 0.5, 29.0),
		"GEM HUNT STAGES",
		24,
		Color("#FFFFFF"),
		Color("#061C38"),
		5,
		2.0
	)
	var sub_txt := "UNLOCKED: STAGE %d   •   BEST SCORE: %s" % [_best_stage, HudView.format_comma_int(_best_score)]
	GameOverOverlay._draw_centered_outlined_text(
		ci,
		_font_bold,
		Vector2(cs.x * 0.5, 54.0),
		sub_txt,
		11,
		Color("#9AF6FF"),
		Color("#06162E"),
		3,
		1.0
	)

	# Bottom pagination indicator ("STAGES 1 – 12").
	var first_stg := _page_index * STAGES_PER_PAGE + 1
	var last_stg := first_stg + STAGES_PER_PAGE - 1
	var page_txt := "STAGES  %d – %d" % [first_stg, last_stg]
	GameOverOverlay._draw_centered_outlined_text(
		ci,
		_font_bold,
		Vector2(cs.x * 0.5, cs.y - 34.0),
		page_txt,
		13,
		Color("#A6CCF7"),
		Color("#070D24"),
		3,
		1.0
	)


# ==============================================================================
# INNER CLASSES
# ==============================================================================

class _StageSelectCard extends Control:
	var overlay: GemStageSelectOverlay

	func _draw() -> void:
		if overlay != null:
			overlay._draw_card(self)


class _SelectCloseButton extends Control:
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
		_sb_bg.bg_color = Color(0.18, 0.42, 0.72, 0.70) if _hovered else Color(0.06, 0.14, 0.34, 0.62)
		_sb_bg.border_color = Color(0.56, 0.88, 1.0, 0.72) if _hovered else Color(0.36, 0.64, 0.94, 0.40)
		_sb_bg.draw(get_canvas_item(), Rect2(-c, size))
		var col := Color("#FFFFFF") if _hovered else Color("#D4EEFF")
		draw_line(Vector2(-6.5, -6.5), Vector2(6.5, 6.5), col, 2.8, true)
		draw_line(Vector2(-6.5, 6.5), Vector2(6.5, -6.5), col, 2.8, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _ResumeBannerButton extends Control:
	signal pressed_clean()

	var font_extrabold: Font
	var font_bold: Font
	var _stage: int = 1
	var _targets_left: int = 0
	var _score: int = 0

	var _hovered: bool = false
	var _pressed: bool = false
	var _scale_v: float = 1.0
	var _sb_lip: StyleBoxFlat
	var _sb_face: StyleBoxFlat
	var _sb_gloss: StyleBoxFlat
	var _sb_rim: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())
		_sb_lip = StyleBoxFlat.new(); _sb_lip.bg_color = Color("#086B2B"); _sb_lip.set_corner_radius_all(15); _sb_lip.corner_detail = 8
		_sb_face = StyleBoxFlat.new(); _sb_face.set_corner_radius_all(14); _sb_face.corner_detail = 8
		_sb_gloss = StyleBoxFlat.new(); _sb_gloss.bg_color = Color(1.0, 1.0, 0.88, 0.25); _sb_gloss.set_corner_radius_all(8); _sb_gloss.corner_detail = 6
		_sb_rim = StyleBoxFlat.new(); _sb_rim.draw_center = false; _sb_rim.set_corner_radius_all(14); _sb_rim.corner_detail = 8; _sb_rim.set_border_width_all(2); _sb_rim.border_color = Color("#C8FF82")
		set_process(true)

	func set_info(stg: int, left: int, sc: int) -> void:
		_stage = stg
		_targets_left = left
		_score = sc
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var target := 0.96 if _pressed else (1.025 if _hovered else 1.0)
		if absf(_scale_v - target) > 0.002:
			_scale_v = lerpf(_scale_v, target, clampf(18.0 * minf(delta, 0.05), 0.0, 1.0))
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressed = true; queue_redraw(); accept_event()
				else:
					var was := _pressed; _pressed = false; queue_redraw()
					if was and Rect2(Vector2.ZERO, size).has_point(mb.position):
						pressed_clean.emit()
					accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_pressed = true; queue_redraw(); accept_event()
			else:
				var was := _pressed; _pressed = false; queue_redraw()
				if was and Rect2(Vector2.ZERO, size).has_point(st.position):
					pressed_clean.emit()
				accept_event()

	func _draw() -> void:
		var cid := get_canvas_item()
		var c := size * 0.5
		var local_rect := Rect2(-c, size)
		var press_y := 3.0 if _pressed else 0.0
		var lip_h := 2.0 if _pressed else 5.0

		draw_set_transform(c, 0.0, Vector2(_scale_v, _scale_v))
		var outer := Rect2(local_rect.position + Vector2(0.0, press_y), Vector2(local_rect.size.x, local_rect.size.y - press_y))
		_sb_lip.draw(cid, outer)
		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		_sb_face.bg_color = Color("#34E867") if _hovered else Color("#1FD152")
		_sb_face.draw(cid, face)
		_sb_gloss.draw(cid, Rect2(face.position + Vector2(10.0, 3.0), Vector2(face.size.x - 20.0, face.size.y * 0.34)))
		_sb_rim.draw(cid, face)

		var fc := face.get_center()
		var tri_c := Vector2(face.position.x + 28.0, fc.y)
		draw_colored_polygon(PackedVector2Array([tri_c + Vector2(-6.0, -8.0), tri_c + Vector2(9.0, 0.0), tri_c + Vector2(-6.0, 8.0)]), Color("#FFFFFF"))

		var eb := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var b := font_bold if font_bold != null else eb
		GameOverOverlay._draw_left_outlined_text(self, eb, Vector2(face.position.x + 48.0, fc.y - 7.5), "RESUME STAGE %d" % _stage, 18, Color("#FFFFFF"), Color("#053D16"), 4, 1.4)
		var sub := "◆ %d GEMS LEFT   •   %s PTS" % [_targets_left, HudView.format_comma_int(_score)]
		GameOverOverlay._draw_left_outlined_text(self, b, Vector2(face.position.x + 48.0, fc.y + 11.5), sub, 11, Color("#E6FFBA"), Color("#053D16"), 3, 0.9)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _StageTileButton extends Control:
	signal stage_clicked(stage_num: int)

	var font_extrabold: Font
	var font_bold: Font

	var _stage_num: int = 1
	var _state_kind: int = 0 # 0 = locked, 1 = current unlocked frontier, 2 = cleared
	var _hovered: bool = false
	var _pressed: bool = false
	var _scale_v: float = 1.0
	var _time: float = 0.0

	var _sb_lip: StyleBoxFlat
	var _sb_face: StyleBoxFlat
	var _sb_gloss: StyleBoxFlat
	var _sb_rim: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			if _state_kind > 0:
				_hovered = true
				queue_redraw()
		)
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())

		_sb_lip = StyleBoxFlat.new(); _sb_lip.set_corner_radius_all(15); _sb_lip.corner_detail = 8
		_sb_face = StyleBoxFlat.new(); _sb_face.set_corner_radius_all(14); _sb_face.corner_detail = 8
		_sb_gloss = StyleBoxFlat.new(); _sb_gloss.corner_radius_top_left = 10; _sb_gloss.corner_radius_top_right = 10; _sb_gloss.corner_radius_bottom_left = 4; _sb_gloss.corner_radius_bottom_right = 4; _sb_gloss.corner_detail = 6
		_sb_rim = StyleBoxFlat.new(); _sb_rim.draw_center = false; _sb_rim.set_corner_radius_all(14); _sb_rim.corner_detail = 8; _sb_rim.set_border_width_all(2)
		set_process(true)

	func configure(stage_num: int, state_kind: int) -> void:
		_stage_num = stage_num
		_state_kind = state_kind
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _state_kind > 0 else Control.CURSOR_ARROW
		if _state_kind == 0:
			_hovered = false
			_pressed = false
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		_time += dt
		var target := 0.94 if _pressed else (1.045 if _hovered else 1.0)
		var dirty := _state_kind == 1
		if absf(_scale_v - target) > 0.002:
			_scale_v = lerpf(_scale_v, target, clampf(18.0 * dt, 0.0, 1.0))
			dirty = true
		if dirty:
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if _state_kind <= 0:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressed = true; queue_redraw(); accept_event()
				else:
					var was := _pressed; _pressed = false; queue_redraw()
					if was and Rect2(Vector2.ZERO, size).has_point(mb.position):
						stage_clicked.emit(_stage_num)
					accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_pressed = true; queue_redraw(); accept_event()
			else:
				var was := _pressed; _pressed = false; queue_redraw()
				if was and Rect2(Vector2.ZERO, size).has_point(st.position):
					stage_clicked.emit(_stage_num)
				accept_event()

	func _draw() -> void:
		var cid := get_canvas_item()
		var c := size * 0.5
		var local_rect := Rect2(-c, size)
		var press_y := 3.0 if _pressed else 0.0
		var lip_h := 2.0 if _pressed else 5.0
		var pulse := 0.5 + 0.5 * sin(_time * 4.2)

		draw_set_transform(c, 0.0, Vector2(_scale_v, _scale_v))
		var outer := Rect2(local_rect.position + Vector2(0.0, press_y), Vector2(local_rect.size.x, local_rect.size.y - press_y))

		if _state_kind == 2: # Cleared stage (gleaming cyan-teal)
			_sb_lip.bg_color = Color("#084A69")
			_sb_face.bg_color = Color("#189CC4") if _hovered else Color("#127FA6")
			_sb_rim.border_color = Color("#8AF6FF")
			_sb_gloss.bg_color = Color(0.84, 0.99, 1.0, 0.22)
		elif _state_kind == 1: # Current frontier stage (radiant gold-amber)
			_sb_lip.bg_color = Color("#873C00")
			_sb_face.bg_color = Color("#F59516").lerp(Color("#FFB62B"), (0.28 if _hovered else 0.0) + pulse * 0.14)
			_sb_rim.border_color = Color("#FFF08A")
			_sb_gloss.bg_color = Color(1.0, 0.98, 0.80, 0.28)
		else: # Locked stage (recessed slate-indigo)
			_sb_lip.bg_color = Color("#080D22")
			_sb_face.bg_color = Color("#141C3D")
			_sb_rim.border_color = Color(0.28, 0.38, 0.68, 0.40)
			_sb_gloss.bg_color = Color(1.0, 1.0, 1.0, 0.05)

		_sb_lip.draw(cid, outer)
		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		_sb_face.draw(cid, face)
		_sb_gloss.draw(cid, Rect2(face.position + Vector2(6.0, 3.0), Vector2(face.size.x - 12.0, face.size.y * 0.34)))
		_sb_rim.draw(cid, face)

		var eb := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var b := font_bold if font_bold != null else eb
		var fc := face.get_center()
		var mult := GemHunt.get_stage_base_mult(_stage_num)
		var m_str := "×%s" % ("%.2f" % mult).rstrip("0").rstrip(".")

		if _state_kind == 0:
			# Crisp Lock icon + dimmed Stage number + multiplier preview.
			var lc := Vector2(fc.x, face.position.y + 26.0)
			draw_arc(lc + Vector2(0.0, -4.0), 6.2, PI, TAU, 14, Color("#6C7FA8"), 2.4, true)
			draw_rect(Rect2(lc.x - 9.0, lc.y - 3.5, 18.0, 14.0), Color("#6C7FA8"), true)
			draw_circle(lc + Vector2(0.0, 3.0), 2.2, Color("#141C3D"))
			GameOverOverlay._draw_centered_outlined_text(self, eb, Vector2(fc.x, face.position.y + 54.0), "STAGE %d" % _stage_num, 14, Color("#6C7FA8"), Color("#070B1A"), 3, 0.8)
			GameOverOverlay._draw_centered_outlined_text(self, b, Vector2(fc.x, face.position.y + 73.0), m_str, 11, Color("#51628A"), Color("#070B1A"), 2, 0.6)
		else:
			var outline_c := Color("#042E42") if _state_kind == 2 else Color("#522000")
			# Top-left status badge (golden diamond star for Cleared, or "NEXT" tag for Frontier).
			if _state_kind == 2:
				var sc := Vector2(face.position.x + 17.0, face.position.y + 16.0)
				draw_colored_polygon(PackedVector2Array([sc + Vector2(0, -7.0), sc + Vector2(6.5, 0), sc + Vector2(0, 7.0), sc + Vector2(-6.5, 0)]), Color("#FFE266"))
				draw_colored_polygon(PackedVector2Array([sc + Vector2(0, -3.5), sc + Vector2(3.2, 0), sc + Vector2(0, 3.5), sc + Vector2(-3.2, 0)]), Color("#FFFFFF"))
			else:
				var tag := Rect2(face.position.x + 8.0, face.position.y + 8.0, 42.0, 17.0)
				GameOverOverlay._draw_rounded_rect_static(self, tag, Color(0.18, 0.06, 0.0, 0.55), 7.0)
				GameOverOverlay._draw_centered_outlined_text(self, eb, tag.get_center(), "PLAY", 9, Color("#FFF4B8"), Color("#3B1600"), 2, 0.6)

			# Top-right stage multiplier badge ("×1.5").
			var m_pill := Rect2(face.end.x - 46.0, face.position.y + 8.0, 38.0, 17.0)
			GameOverOverlay._draw_rounded_rect_static(self, m_pill, Color(0.03, 0.08, 0.22, 0.60), 7.0)
			GameOverOverlay._draw_centered_outlined_text(self, eb, m_pill.get_center(), m_str, 10, Color("#FFE875"), Color("#051026"), 2, 0.6)

			# Big bold Stage numeral in center.
			GameOverOverlay._draw_centered_outlined_text(self, eb, Vector2(fc.x, face.position.y + 46.0), "STAGE %d" % _stage_num, 17, Color("#FFFFFF"), outline_c, 4, 1.4)

			# Bottom target type indicator pills (Crystal / Padlock / Ice preview!).
			var feat_txt := "◆ CRYSTAL"
			if _stage_num == 2:
				feat_txt = "◆ + LOCK"
			elif _stage_num >= 3:
				feat_txt = "◆ LOCK ICE"
			GameOverOverlay._draw_centered_outlined_text(
				self,
				b,
				Vector2(fc.x, face.position.y + 72.0),
				feat_txt,
				10,
				Color("#D6FFFF") if _state_kind == 2 else Color("#FFF4C2"),
				outline_c,
				2,
				0.8
			)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _PageNavButton extends Control:
	signal pressed_clean()

	var is_next: bool = true
	var font_extrabold: Font
	var _enabled: bool = true
	var _hovered: bool = false
	var _pressed: bool = false
	var _sb_bg: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			if _enabled:
				_hovered = true
				queue_redraw()
		)
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())
		_sb_bg = StyleBoxFlat.new()
		_sb_bg.set_corner_radius_all(10)
		_sb_bg.corner_detail = 6
		_sb_bg.set_border_width_all(1)

	func set_enabled(val: bool) -> void:
		_enabled = val
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _enabled else Control.CURSOR_ARROW
		if not _enabled:
			_hovered = false
			_pressed = false
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if not _enabled:
			return
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressed = true; queue_redraw(); accept_event()
				else:
					var was := _pressed; _pressed = false; queue_redraw()
					if was and Rect2(Vector2.ZERO, size).has_point(mb.position):
						pressed_clean.emit()
					accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_pressed = true; queue_redraw(); accept_event()
			else:
				var was := _pressed; _pressed = false; queue_redraw()
				if was and Rect2(Vector2.ZERO, size).has_point(st.position):
					pressed_clean.emit()
				accept_event()

	func _draw() -> void:
		_sb_bg.bg_color = Color(0.18, 0.34, 0.72, 0.90) if (_enabled and _hovered) else (Color(0.10, 0.19, 0.46, 0.85) if _enabled else Color(0.08, 0.11, 0.24, 0.50))
		_sb_bg.border_color = Color("#70D8FF") if (_enabled and _hovered) else (Color(0.42, 0.64, 0.96, 0.60) if _enabled else Color(0.25, 0.32, 0.55, 0.30))
		_sb_bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		var col := Color("#FFFFFF") if _enabled else Color("#4C5A82")
		var eb := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		GameOverOverlay._draw_centered_outlined_text(self, eb, size * 0.5, "›" if is_next else "‹", 24, col, Color("#070E26"), 3, 0.8)
