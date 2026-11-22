class_name ReviveOverlay
extends Control

## One-handed portrait "SECOND CHANCE?" Revive modal for Kombo by SOYA GAMES.
## Shown when the 8x8 board runs out of legal placements while has_used_revive == false.
## Features anti-spam button lock (set_processing_ad) for seamless future Ad SDK integration.

signal revive_pressed()
signal decline_pressed()

const OVERLAY_SIZE := Vector2(540.0, 960.0)
const CARD_SIZE := Vector2(406.0, 456.0)
const REVIVE_BTN_RECT := Rect2(24.0, 276.0, 358.0, 76.0)
const DECLINE_BTN_RECT := Rect2(108.0, 370.0, 190.0, 52.0)

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
var _sb_info_box: StyleBoxFlat

var _is_open: bool = false
var _is_processing_ad: bool = false
var _current_score: int = 0
var _combo_streak: int = 0
var _fever_active: bool = false
var _has_hold_piece: bool = false
var _mode_badge: String = "CLASSIC"

var _time_sec: float = 0.0
var _backdrop_alpha: float = 0.0
var _card_alpha: float = 0.0
var _card_scale: float = 0.80
var _card_scale_vel: float = 0.0
var _card_y_offset: float = 24.0

var _card: _ReviveCard
var _revive_btn: _ReviveCtaButton
var _decline_btn: _DeclineButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_load_fonts()
	_init_styles()
	_build_card()
	_apply_card_transform()
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _card != null:
		_apply_card_transform()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _is_open:
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if _is_processing_ad:
				get_viewport().set_input_as_handled()
				return
			if ke.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_on_decline_clicked()
			elif ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER or ke.keycode == KEY_SPACE:
				get_viewport().set_input_as_handled()
				_on_revive_clicked()


func _process(delta: float) -> void:
	if not visible:
		return
	var dt := minf(delta, 0.05)
	_time_sec += dt

	_backdrop_alpha = move_toward(_backdrop_alpha, 1.0, dt * 4.8)
	_card_alpha = move_toward(_card_alpha, 1.0, dt * 5.2)
	_card_y_offset = lerpf(_card_y_offset, 0.0, clampf(15.0 * dt, 0.0, 1.0))

	var cs := GameOverOverlay._step_spring(_card_scale, _card_scale_vel, 1.0, 275.0, 17.0, dt)
	_card_scale = cs.x
	_card_scale_vel = cs.y

	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


# ==============================================================================
# PUBLIC API
# ==============================================================================

func show_revive_offer(
	current_score: int,
	combo_streak: int,
	fever_active: bool,
	has_hold_piece: bool,
	mode_label: String = "CLASSIC"
) -> void:
	_current_score = maxi(0, current_score)
	_combo_streak = maxi(0, combo_streak)
	_fever_active = fever_active
	_has_hold_piece = has_hold_piece
	_mode_badge = mode_label
	_is_processing_ad = false

	_is_open = true
	_backdrop_alpha = 0.0
	_card_alpha = 0.0
	_card_scale = 0.80
	_card_scale_vel = 4.4
	_card_y_offset = 24.0

	if _revive_btn != null:
		_revive_btn.set_locked(false)
	if _decline_btn != null:
		_decline_btn.set_locked(false)

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


func hide_overlay() -> void:
	_is_open = false
	_is_processing_ad = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _revive_btn != null:
		_revive_btn.set_locked(false)
	if _decline_btn != null:
		_decline_btn.set_locked(false)
	queue_redraw()


func is_open() -> bool:
	return _is_open and visible


func set_processing_ad(locked: bool) -> void:
	_is_processing_ad = locked
	if _revive_btn != null:
		_revive_btn.set_locked(locked)
	if _decline_btn != null:
		_decline_btn.set_locked(locked)
	if _card != null:
		_card.queue_redraw()


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
# SETUP
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


func _init_styles() -> void:
	_radial_glow_tex = GameOverOverlay._create_radial_glow_texture()

	_sb_card_shadow = StyleBoxFlat.new()
	_sb_card_shadow.bg_color = Color(0.01, 0.02, 0.07, 0.72)
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
	_sb_card_inner.border_color = Color(0.32, 0.88, 0.64, 0.22)

	_sb_card_rim = StyleBoxFlat.new()
	_sb_card_rim.draw_center = false
	_sb_card_rim.set_corner_radius_all(24)
	_sb_card_rim.corner_detail = 10
	_sb_card_rim.set_border_width_all(3)
	_sb_card_rim.border_color = Color("#3CF27E")

	_sb_info_box = StyleBoxFlat.new()
	_sb_info_box.bg_color = Color("#0B1330")
	_sb_info_box.set_corner_radius_all(16)
	_sb_info_box.corner_detail = 8
	_sb_info_box.set_border_width_all(2)
	_sb_info_box.border_color = Color(0.24, 0.54, 0.92, 0.45)


func _build_card() -> void:
	_card = _ReviveCard.new()
	_card.name = "ReviveCard"
	_card.overlay = self
	_card.size = CARD_SIZE
	_card.pivot_offset = CARD_SIZE * 0.5
	_card.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_card)

	_revive_btn = _ReviveCtaButton.new()
	_revive_btn.name = "ReviveCtaButton"
	_revive_btn.font_extrabold = _font_extrabold
	_revive_btn.font_bold = _font_bold
	_revive_btn.position = REVIVE_BTN_RECT.position
	_revive_btn.size = REVIVE_BTN_RECT.size
	_revive_btn.pressed_clean.connect(_on_revive_clicked)
	_card.add_child(_revive_btn)

	_decline_btn = _DeclineButton.new()
	_decline_btn.name = "DeclineReviveButton"
	_decline_btn.font_bold = _font_bold
	_decline_btn.position = DECLINE_BTN_RECT.position
	_decline_btn.size = DECLINE_BTN_RECT.size
	_decline_btn.pressed_clean.connect(_on_decline_clicked)
	_card.add_child(_decline_btn)


func _apply_card_transform() -> void:
	if _card == null:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	var base_pos := (view_size - CARD_SIZE) * 0.5
	_card.position = base_pos + Vector2(0.0, _card_y_offset)
	_card.pivot_offset = CARD_SIZE * 0.5
	_card.scale = Vector2(_card_scale, _card_scale)
	_card.modulate = Color(1.0, 1.0, 1.0, _card_alpha)


func _on_revive_clicked() -> void:
	if _is_processing_ad:
		return
	revive_pressed.emit()


func _on_decline_clicked() -> void:
	if _is_processing_ad:
		return
	decline_pressed.emit()


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
		var pulse := 0.5 + 0.5 * sin(_time_sec * 3.6)
		var half := Vector2(330.0, 350.0)
		draw_texture_rect(
			_radial_glow_tex,
			Rect2(center - half, half * 2.0),
			false,
			Color(0.14, 0.90, 0.52, (0.28 + 0.08 * pulse) * _backdrop_alpha)
		)


func _draw_card(ci: CanvasItem) -> void:
	var card_rect := Rect2(Vector2.ZERO, CARD_SIZE)
	var cid := ci.get_canvas_item()
	var pulse := 0.5 + 0.5 * sin(_time_sec * 4.4)

	_sb_card_shadow.draw(cid, Rect2(Vector2(0.0, 12.0), CARD_SIZE))
	_sb_card_lip.draw(cid, Rect2(Vector2(0.0, 6.0), CARD_SIZE))
	_sb_card_body.draw(cid, card_rect)
	_sb_card_inner.draw(cid, card_rect.grow(-4.0))

	# Emerald-to-teal glowing second-chance header.
	var header_h := 80.0
	var header_rect := Rect2(Vector2.ZERO, Vector2(CARD_SIZE.x, header_h))
	SettingsOverlay._draw_top_rounded_header(ci, header_rect, Color("#15855A"), Color("#0D3D59"), 24.0)
	ci.draw_polygon(
		PackedVector2Array([
			Vector2(2.0, header_h - 3.0),
			Vector2(CARD_SIZE.x * 0.5, header_h - 3.0),
			Vector2(CARD_SIZE.x * 0.5, header_h + 0.5),
			Vector2(2.0, header_h + 0.5),
		]),
		PackedColorArray([Color("#2CEEFF"), Color("#7CFF6B"), Color("#7CFF6B"), Color("#2CEEFF")])
	)
	ci.draw_polygon(
		PackedVector2Array([
			Vector2(CARD_SIZE.x * 0.5, header_h - 3.0),
			Vector2(CARD_SIZE.x - 2.0, header_h - 3.0),
			Vector2(CARD_SIZE.x - 2.0, header_h + 0.5),
			Vector2(CARD_SIZE.x * 0.5, header_h + 0.5),
		]),
		PackedColorArray([Color("#7CFF6B"), Color("#2CEEFF"), Color("#2CEEFF"), Color("#7CFF6B")])
	)
	_sb_card_rim.draw(cid, card_rect)

	# Glowing floating Heart / Life Shield crest perched at top center.
	var crest_c := Vector2(CARD_SIZE.x * 0.5, -4.0)
	if _radial_glow_tex != null:
		var g_r := 44.0 + pulse * 7.0
		ci.draw_texture_rect(_radial_glow_tex, Rect2(crest_c - Vector2(g_r, g_r), Vector2(g_r * 2.0, g_r * 2.0)), false, Color(0.24, 1.0, 0.58, 0.52 + pulse * 0.16))
	var h_scale := 1.0 + 0.06 * pulse
	ci.draw_set_transform(crest_c, 0.0, Vector2(h_scale, h_scale))
	_draw_heart_emblem(ci, 18.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	GameOverOverlay._draw_centered_outlined_text(
		ci, _font_extrabold, Vector2(CARD_SIZE.x * 0.5, 48.0), "SECOND CHANCE?", 29, Color("#FFFFFF"), Color("#062624"), 6, 2.4
	)

	GameOverOverlay._draw_centered_outlined_text(
		ci, _font_bold, Vector2(CARD_SIZE.x * 0.5, 104.0), "NO MOVES LEFT  •  %s" % _mode_badge, 12, Color("#9AF6FF"), Color("#070D24"), 3, 1.0
	)

	# Run Preservation Info Box.
	var box := Rect2(24.0, 124.0, CARD_SIZE.x - 48.0, 134.0)
	_sb_info_box.draw(cid, box)

	var score_txt := HudView.format_comma_int(_current_score)
	GameOverOverlay._draw_centered_outlined_text(ci, _font_bold, Vector2(box.get_center().x, box.position.y + 20.0), "CURRENT SCORE", 11, Color("#8DB4F5"), Color("#060B1E"), 2, 0.8)
	GameOverOverlay._draw_centered_outlined_text(ci, _font_extrabold, Vector2(box.get_center().x, box.position.y + 49.0), score_txt, 32, Color("#FFE875"), Color("#2E1800"), 6, 2.0)

	# Divider inside info box.
	ci.draw_line(Vector2(box.position.x + 18.0, box.position.y + 76.0), Vector2(box.end.x - 18.0, box.position.y + 76.0), Color(0.32, 0.56, 0.92, 0.30), 1.2, true)

	# Clear explanation of what Revive restores & preserves!
	GameOverOverlay._draw_centered_outlined_text(
		ci, _font_extrabold, Vector2(box.get_center().x, box.position.y + 96.0), "✦ CLEAR CENTER 4×4  +  3 NEW BLOCKS", 12, Color("#78FFAB"), Color("#052B17"), 3, 1.0
	)
	var keep_parts: Array[String] = ["KEEP SCORE", "×2/×3"]
	if _has_hold_piece:
		keep_parts.append("HOLD")
	if _fever_active:
		keep_parts.append("FEVER!")
	elif _combo_streak >= 2:
		keep_parts.append("COMBO ×%d" % _combo_streak)
	else:
		keep_parts.append("FEVER GAUGE")
	var keep_line := "  •  ".join(keep_parts)
	GameOverOverlay._draw_centered_outlined_text(
		ci, _font_bold, Vector2(box.get_center().x, box.position.y + 117.0), keep_line, 10, Color("#B4DCFF"), Color("#060B1E"), 2, 0.8
	)


static func _draw_heart_emblem(ci: CanvasItem, r: float) -> void:
	# Crisp dark-stroked emerald-gold heart shield.
	var pts := PackedVector2Array([
		Vector2(0.0, r * 0.95),
		Vector2(-r * 0.96, -r * 0.02),
		Vector2(-r * 0.92, -r * 0.58),
		Vector2(-r * 0.48, -r * 0.88),
		Vector2(0.0, -r * 0.44),
		Vector2(r * 0.48, -r * 0.88),
		Vector2(r * 0.92, -r * 0.58),
		Vector2(r * 0.96, -r * 0.02),
	])
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, Color("#043018"), 5.2, true)
	ci.draw_colored_polygon(pts, Color("#24E878"))
	# Inner glossy highlight + crisp white '+' rescue cross.
	ci.draw_rect(Rect2(-r * 0.16, -r * 0.30, r * 0.32, r * 0.72), Color("#FFFFFF"), true)
	ci.draw_rect(Rect2(-r * 0.38, -r * 0.08, r * 0.76, r * 0.28), Color("#FFFFFF"), true)


# ==============================================================================
# INNER CLASSES
# ==============================================================================

class _ReviveCard extends Control:
	var overlay: ReviveOverlay

	func _draw() -> void:
		if overlay != null:
			overlay._draw_card(self)


class _ReviveCtaButton extends Control:
	signal pressed_clean()

	var font_extrabold: Font
	var font_bold: Font
	var _locked: bool = false
	var _hovered: bool = false
	var _pressed: bool = false
	var _scale_v: float = 1.0
	var _time: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			if not _locked:
				_hovered = true
				queue_redraw()
		)
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())
		set_process(true)

	func set_locked(val: bool) -> void:
		_locked = val
		mouse_default_cursor_shape = Control.CURSOR_ARROW if _locked else Control.CURSOR_POINTING_HAND
		if _locked:
			_hovered = false
			_pressed = false
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		_time += dt
		var target := 0.95 if _pressed else (1.035 if _hovered else 1.0)
		_scale_v = lerpf(_scale_v, target, clampf(18.0 * dt, 0.0, 1.0))
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if _locked:
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
		var c := size * 0.5
		var local_rect := Rect2(-c, size)
		var r := 18.0
		var press_y := 4.0 if _pressed else 0.0
		var lip_h := 2.5 if _pressed else 7.0
		var pulse := 0.5 + 0.5 * sin(_time * 4.5)

		draw_set_transform(c, 0.0, Vector2(_scale_v, _scale_v))
		if not _locked:
			GameOverOverlay._draw_rounded_rect_static(self, local_rect.grow(4.0), Color(0.22, 0.96, 0.46, 0.22 + pulse * 0.12), r + 4.0)
		GameOverOverlay._draw_rounded_rect_static(self, Rect2(local_rect.position + Vector2(0.0, 5.0), local_rect.size), Color(0.01, 0.05, 0.03, 0.62), r)

		var outer := Rect2(local_rect.position + Vector2(0.0, press_y), Vector2(local_rect.size.x, local_rect.size.y - press_y))
		GameOverOverlay._draw_rounded_rect_static(self, outer, Color("#1D2847") if _locked else Color("#086B2B"), r)

		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		var top_col := Color("#3E4E75") if _locked else (Color("#46F770").lerp(Color("#D8FF6B"), 0.20 + (0.14 if _hovered else 0.0)))
		var bot_col := Color("#2B385C") if _locked else (Color("#12B842").lerp(Color("#2CE058"), 0.12 if _hovered else 0.0))
		var face_pts := GameOverOverlay._build_rounded_rect_points(face, r - 1.0)
		var face_cols := PackedColorArray()
		var fh := maxf(1.0, face.size.y)
		for pt in face_pts:
			face_cols.append(top_col.lerp(bot_col, clampf((pt.y - face.position.y) / fh, 0.0, 1.0)))
		draw_polygon(face_pts, face_cols)

		GameOverOverlay._draw_rounded_rect_static(self, Rect2(face.position + Vector2(12.0, 4.0), Vector2(face.size.x - 24.0, face.size.y * 0.34)), Color(1.0, 1.0, 0.90, 0.14 if _locked else 0.28), 10.0)
		var rim_loop := face_pts.duplicate()
		rim_loop.append(face_pts[0])
		draw_polyline(rim_loop, Color("#7A8CB8") if _locked else Color("#D2FF85"), 2.3, true)

		var eb := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var b := font_bold if font_bold != null else eb
		var fc := face.get_center()
		var out_c := Color("#161D36") if _locked else Color("#053D16")

		if _locked:
			GameOverOverlay._draw_centered_outlined_text(self, eb, fc + Vector2(0.0, -1.0), "PROCESSING...", 22, Color("#D8E2FF"), out_c, 5, 1.8)
		else:
			# Crisp Video-Ad Play Badge icon on left (SDK-ready visual cue!).
			var badge := Rect2(face.position.x + 22.0, fc.y - 14.0, 34.0, 28.0)
			GameOverOverlay._draw_rounded_rect_static(self, badge, Color(0.03, 0.24, 0.10, 0.62), 8.0)
			var bc := badge.get_center()
			draw_colored_polygon(PackedVector2Array([bc + Vector2(-4.5, -6.5), bc + Vector2(7.0, 0.0), bc + Vector2(-4.5, 6.5)]), Color("#FFE875"))

			GameOverOverlay._draw_centered_outlined_text(self, eb, fc + Vector2(16.0, -8.5), "REVIVE & PLAY", 23, Color("#FFFFFF"), out_c, 6, 2.0)
			GameOverOverlay._draw_centered_outlined_text(self, b, fc + Vector2(16.0, 14.0), "1× PER RUN  •  INSTANT RESCUE", 11, Color("#E6FFBA"), out_c, 3, 0.9)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _DeclineButton extends Control:
	signal pressed_clean()

	var font_bold: Font
	var _locked: bool = false
	var _hovered: bool = false
	var _pressed: bool = false
	var _scale_v: float = 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			if not _locked:
				_hovered = true
				queue_redraw()
		)
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())
		set_process(true)

	func set_locked(val: bool) -> void:
		_locked = val
		mouse_default_cursor_shape = Control.CURSOR_ARROW if _locked else Control.CURSOR_POINTING_HAND
		if _locked:
			_hovered = false
			_pressed = false
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var target := 0.95 if _pressed else (1.03 if _hovered else 1.0)
		if absf(_scale_v - target) > 0.002:
			_scale_v = lerpf(_scale_v, target, clampf(18.0 * minf(delta, 0.05), 0.0, 1.0))
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if _locked:
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
		var c := size * 0.5
		var local_rect := Rect2(-c, size)
		draw_set_transform(c, 0.0, Vector2(_scale_v, _scale_v))
		var bg := Color(0.10, 0.15, 0.34, 0.55) if _locked else (Color(0.18, 0.27, 0.56, 0.92) if _hovered else Color(0.11, 0.17, 0.38, 0.88))
		var rim := Color(0.30, 0.38, 0.62, 0.35) if _locked else (Color("#82B2FF") if _hovered else Color(0.38, 0.54, 0.88, 0.55))
		GameOverOverlay._draw_rounded_rect_static(self, local_rect, bg, 14.0)
		var pts := GameOverOverlay._build_rounded_rect_points(local_rect, 14.0)
		pts.append(pts[0])
		draw_polyline(pts, rim, 1.8, true)

		var b := font_bold if font_bold != null else ThemeDB.fallback_font
		var txt_col := Color(0.55, 0.62, 0.80, 0.55) if _locked else (Color("#FFFFFF") if _hovered else Color("#BDD4FA"))
		GameOverOverlay._draw_centered_outlined_text(self, b, Vector2.ZERO, "NO THANKS", 15, txt_col, Color("#060B1E"), 3, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
