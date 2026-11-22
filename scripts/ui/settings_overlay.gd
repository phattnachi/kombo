class_name SettingsOverlay
extends Control

## Sleek Dark-Indigo 3D Settings modal for Kombo by SOYA GAMES.
## Matches GameOverOverlay craftsmanship with animated toggles for Sound (SFX),
## BGM, and Vibration, tactile Replay/Home actions during gameplay, and a
## compact branded KOMBO! v1.0.0 • SOYA GAMES studio footer.

signal sfx_toggled(enabled: bool)
signal bgm_toggled(enabled: bool)
signal vibration_toggled(enabled: bool)
signal how_to_play_pressed()
signal replay_pressed()
signal home_pressed()
signal closed()

const OVERLAY_SIZE := Vector2(540.0, 960.0)
const CARD_WIDTH := 400.0
const CARD_HEIGHT_GAMEPLAY := 536.0
const CARD_HEIGHT_TITLE := 414.0
const HEADER_HEIGHT := 68.0
const ROW_STEP := 61.0

const FONT_EXTRABOLD_PATH := "res://assets/fonts/Kanit-ExtraBold.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/Kanit-Bold.ttf"
const APP_ICON_PATH := "res://assets/logo/kombo_icon_rounded.png"
const STUDIO_MARK_PATH := "res://assets/logo/soya_games_mark_light.png"
const APP_VERSION_TEXT := "v1.0.0"

var _font_extrabold: Font
var _font_bold: Font
var _app_icon_tex: Texture2D
var _studio_mark_tex: Texture2D
var _radial_glow_tex: GradientTexture2D

var _sb_card_shadow: StyleBoxFlat
var _sb_card_lip: StyleBoxFlat
var _sb_card_body: StyleBoxFlat
var _sb_card_inner: StyleBoxFlat
var _sb_card_rim: StyleBoxFlat
var _sb_footer_pill: StyleBoxFlat

var _is_open: bool = false
var _show_gameplay_actions: bool = true
var _sfx_enabled: bool = true
var _bgm_enabled: bool = true
var _vibration_enabled: bool = true

var _time_sec: float = 0.0
var _backdrop_alpha: float = 0.0
var _card_alpha: float = 0.0
var _card_scale: float = 0.84
var _card_scale_vel: float = 0.0
var _card_y_offset: float = 20.0

var _card: _SettingsCard
var _close_btn: _CloseIconButton
var _sfx_toggle: _ToggleSwitch
var _bgm_toggle: _ToggleSwitch
var _vib_toggle: _ToggleSwitch
var _guide_btn: _ActionPillButton
var _replay_btn: _ActionPillButton
var _home_btn: _ActionPillButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_load_assets()
	_init_cached_styles()
	_build_card()
	_layout_card_contents()
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
				close_settings(true)
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
		close_settings()


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

func open_settings(
	sfx_on: bool,
	bgm_on: bool,
	vib_on: bool,
	show_gameplay_actions: bool = true,
	replay_label: String = "Replay",
	replay_enabled: bool = true
) -> void:
	_sfx_enabled = sfx_on
	_bgm_enabled = bgm_on
	_vibration_enabled = vib_on
	_show_gameplay_actions = show_gameplay_actions

	_is_open = true
	_backdrop_alpha = 0.0
	_card_alpha = 0.0
	_card_scale = 0.82
	_card_scale_vel = 4.2
	_card_y_offset = 22.0

	if _sfx_toggle != null:
		_sfx_toggle.set_state(_sfx_enabled, true)
	if _bgm_toggle != null:
		_bgm_toggle.set_state(_bgm_enabled, true)
	if _vib_toggle != null:
		_vib_toggle.set_state(_vibration_enabled, true)
	if _replay_btn != null:
		_replay_btn.label_text = replay_label
		_replay_btn.set_enabled(replay_enabled)

	_layout_card_contents()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


func close_settings(emit_closed: bool = true) -> void:
	if not _is_open and not visible:
		return
	_is_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	if emit_closed:
		closed.emit()


func sync_states(sfx_on: bool, bgm_on: bool, vib_on: bool) -> void:
	_sfx_enabled = sfx_on
	_bgm_enabled = bgm_on
	_vibration_enabled = vib_on
	if _sfx_toggle != null:
		_sfx_toggle.set_state(_sfx_enabled, false)
	if _bgm_toggle != null:
		_bgm_toggle.set_state(_bgm_enabled, false)
	if _vib_toggle != null:
		_vib_toggle.set_state(_vibration_enabled, false)


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

func _load_assets() -> void:
	if ResourceLoader.exists(FONT_EXTRABOLD_PATH):
		_font_extrabold = load(FONT_EXTRABOLD_PATH) as Font
	if ResourceLoader.exists(FONT_BOLD_PATH):
		_font_bold = load(FONT_BOLD_PATH) as Font
	if _font_extrabold == null:
		_font_extrabold = ThemeDB.fallback_font
	if _font_bold == null:
		_font_bold = _font_extrabold

	if ResourceLoader.exists(APP_ICON_PATH):
		_app_icon_tex = load(APP_ICON_PATH) as Texture2D
	if ResourceLoader.exists(STUDIO_MARK_PATH):
		_studio_mark_tex = load(STUDIO_MARK_PATH) as Texture2D


func _init_cached_styles() -> void:
	_radial_glow_tex = GameOverOverlay._create_radial_glow_texture()

	_sb_card_shadow = StyleBoxFlat.new()
	_sb_card_shadow.bg_color = Color(0.01, 0.02, 0.07, 0.68)
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

	_sb_footer_pill = StyleBoxFlat.new()
	_sb_footer_pill.bg_color = Color(0.045, 0.072, 0.185, 0.92)
	_sb_footer_pill.set_corner_radius_all(14)
	_sb_footer_pill.corner_detail = 8
	_sb_footer_pill.set_border_width_all(1)
	_sb_footer_pill.border_color = Color(0.32, 0.48, 0.86, 0.34)


func _build_card() -> void:
	_card = _SettingsCard.new()
	_card.name = "SettingsCard"
	_card.overlay = self
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)

	_close_btn = _CloseIconButton.new()
	_close_btn.name = "CloseButton"
	_close_btn.size = Vector2(36.0, 36.0)
	_close_btn.position = Vector2(CARD_WIDTH - 52.0, 18.0)
	_close_btn.pressed_clean.connect(func() -> void: close_settings(true))
	_card.add_child(_close_btn)

	_sfx_toggle = _ToggleSwitch.new()
	_sfx_toggle.name = "SoundToggle"
	_sfx_toggle.size = Vector2(76.0, 38.0)
	_sfx_toggle.toggled_clean.connect(_on_sfx_switch_changed)
	_card.add_child(_sfx_toggle)

	_bgm_toggle = _ToggleSwitch.new()
	_bgm_toggle.name = "BgmToggle"
	_bgm_toggle.size = Vector2(76.0, 38.0)
	_bgm_toggle.toggled_clean.connect(_on_bgm_switch_changed)
	_card.add_child(_bgm_toggle)

	_vib_toggle = _ToggleSwitch.new()
	_vib_toggle.name = "VibrationToggle"
	_vib_toggle.size = Vector2(76.0, 38.0)
	_vib_toggle.toggled_clean.connect(_on_vib_switch_changed)
	_card.add_child(_vib_toggle)

	_guide_btn = _ActionPillButton.new()
	_guide_btn.name = "GuideActionButton"
	_guide_btn.label_text = "Guide"
	_guide_btn.font_extrabold = _font_extrabold
	_guide_btn.is_primary_green = false
	_guide_btn.size = Vector2(118.0, 42.0)
	_guide_btn.pressed_clean.connect(_on_guide_clicked)
	_card.add_child(_guide_btn)

	_replay_btn = _ActionPillButton.new()
	_replay_btn.name = "ReplayButton"
	_replay_btn.label_text = "Replay"
	_replay_btn.font_extrabold = _font_extrabold
	_replay_btn.is_primary_green = true
	_replay_btn.size = Vector2(118.0, 42.0)
	_replay_btn.pressed_clean.connect(_on_replay_clicked)
	_card.add_child(_replay_btn)

	_home_btn = _ActionPillButton.new()
	_home_btn.name = "HomeActionButton"
	_home_btn.label_text = "Home"
	_home_btn.font_extrabold = _font_extrabold
	_home_btn.is_primary_green = false
	_home_btn.size = Vector2(118.0, 42.0)
	_home_btn.pressed_clean.connect(_on_home_clicked)
	_card.add_child(_home_btn)


func _get_card_size() -> Vector2:
	return Vector2(CARD_WIDTH, CARD_HEIGHT_GAMEPLAY if _show_gameplay_actions else CARD_HEIGHT_TITLE)


func _layout_card_contents() -> void:
	if _card == null:
		return
	var cs := _get_card_size()
	_card.size = cs
	_card.pivot_offset = cs * 0.5

	var switch_x := CARD_WIDTH - 28.0 - 76.0
	_sfx_toggle.position = Vector2(switch_x, _row_center_y(0) - 19.0)
	_bgm_toggle.position = Vector2(switch_x, _row_center_y(1) - 19.0)
	_vib_toggle.position = Vector2(switch_x, _row_center_y(2) - 19.0)

	var btn_x := CARD_WIDTH - 28.0 - 118.0
	_guide_btn.position = Vector2(btn_x, _row_center_y(3) - 21.0)
	_replay_btn.visible = _show_gameplay_actions
	_home_btn.visible = _show_gameplay_actions
	_replay_btn.position = Vector2(btn_x, _row_center_y(4) - 21.0)
	_home_btn.position = Vector2(btn_x, _row_center_y(5) - 21.0)


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


func _row_center_y(row_idx: int) -> float:
	return HEADER_HEIGHT + 40.0 + float(row_idx) * ROW_STEP


func _on_sfx_switch_changed(enabled: bool) -> void:
	_sfx_enabled = enabled
	sfx_toggled.emit(enabled)


func _on_bgm_switch_changed(enabled: bool) -> void:
	_bgm_enabled = enabled
	bgm_toggled.emit(enabled)


func _on_vib_switch_changed(enabled: bool) -> void:
	_vibration_enabled = enabled
	vibration_toggled.emit(enabled)


func _on_guide_clicked() -> void:
	close_settings(false)
	how_to_play_pressed.emit()


func _on_replay_clicked() -> void:
	close_settings(false)
	replay_pressed.emit()


func _on_home_clicked() -> void:
	close_settings(false)
	home_pressed.emit()


# ==============================================================================
# BACKDROP & CARD RENDERING
# ==============================================================================

func _draw() -> void:
	if not visible:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.027, 0.043, 0.118, 0.78 * _backdrop_alpha), true)

	if _radial_glow_tex != null:
		var center := view_size * 0.5
		var pulse := 0.5 + 0.5 * sin(_time_sec * 2.8)
		var half := Vector2(310.0, 340.0)
		draw_texture_rect(
			_radial_glow_tex,
			Rect2(center - half, half * 2.0),
			false,
			Color(0.18, 0.56, 1.0, (0.24 + 0.06 * pulse) * _backdrop_alpha)
		)


func _draw_card(ci: CanvasItem) -> void:
	var cs := _get_card_size()
	var card_rect := Rect2(Vector2.ZERO, cs)
	var cid := ci.get_canvas_item()

	# 1. Outer drop shadow + 3D navy lip + body + inner bevel frame.
	_sb_card_shadow.draw(cid, Rect2(Vector2(0.0, 12.0), cs))
	_sb_card_lip.draw(cid, Rect2(Vector2(0.0, 6.0), cs))
	_sb_card_body.draw(cid, card_rect)
	_sb_card_inner.draw(cid, card_rect.grow(-4.0))

	# 2. Gradient royal-cobalt header with electric cyan-gold accent seam.
	var header_rect := Rect2(Vector2.ZERO, Vector2(cs.x, HEADER_HEIGHT))
	_draw_top_rounded_header(ci, header_rect, Color("#24367A"), Color("#141F4F"), 24.0)
	ci.draw_polygon(
		PackedVector2Array([
			Vector2(2.0, HEADER_HEIGHT - 3.0),
			Vector2(cs.x * 0.5, HEADER_HEIGHT - 3.0),
			Vector2(cs.x * 0.5, HEADER_HEIGHT + 0.5),
			Vector2(2.0, HEADER_HEIGHT + 0.5),
		]),
		PackedColorArray([Color("#18D5FF"), Color("#FFD43B"), Color("#FFD43B"), Color("#18D5FF")])
	)
	ci.draw_polygon(
		PackedVector2Array([
			Vector2(cs.x * 0.5, HEADER_HEIGHT - 3.0),
			Vector2(cs.x - 2.0, HEADER_HEIGHT - 3.0),
			Vector2(cs.x - 2.0, HEADER_HEIGHT + 0.5),
			Vector2(cs.x * 0.5, HEADER_HEIGHT + 0.5),
		]),
		PackedColorArray([Color("#FFD43B"), Color("#18D5FF"), Color("#18D5FF"), Color("#FFD43B")])
	)

	# 3. Crisp outer card border rim.
	_sb_card_rim.draw(cid, card_rect)

	# 4. Centered SETTINGS title.
	GameOverOverlay._draw_centered_outlined_text(
		ci,
		_font_extrabold,
		Vector2(cs.x * 0.5, HEADER_HEIGHT * 0.5),
		"SETTINGS",
		30,
		Color("#FFFFFF"),
		Color("#090F2B"),
		6,
		2.2
	)

	# 5. Settings Rows (icons, labels, subtle divider hairlines).
	var row_specs: Array[Array] = [
		[0, "Sound"],
		[1, "BGM"],
		[2, "Vibration"],
		[5, "How to Play"],
	]
	if _show_gameplay_actions:
		row_specs.append([3, "Replay"])
		row_specs.append([4, "Home"])

	for idx in range(row_specs.size()):
		var kind := int(row_specs[idx][0])
		var label := String(row_specs[idx][1])
		var ry := _row_center_y(idx)

		_draw_row_icon(ci, kind, Vector2(48.0, ry))
		GameOverOverlay._draw_left_outlined_text(
			ci,
			_font_bold,
			Vector2(82.0, ry),
			label,
			20,
			Color("#EEF5FF"),
			Color("#080D24"),
			4,
			1.5
		)

		if idx < row_specs.size() - 1:
			var div_y := ry + ROW_STEP * 0.5
			ci.draw_line(Vector2(26.0, div_y), Vector2(cs.x - 26.0, div_y), Color(0.36, 0.52, 0.92, 0.22), 1.3, true)

	# 6. Compact Branded Studio Footer Pill (KOMBO! v1.0.0  •  SOYA GAMES).
	var footer_rect := Rect2(22.0, cs.y - 74.0, cs.x - 44.0, 56.0)
	_sb_footer_pill.draw(cid, footer_rect)
	var fy := footer_rect.get_center().y

	if _app_icon_tex != null:
		ci.draw_texture_rect(_app_icon_tex, Rect2(footer_rect.position.x + 11.0, fy - 19.0, 38.0, 38.0), false, Color.WHITE)

	GameOverOverlay._draw_left_outlined_text(
		ci,
		_font_extrabold,
		Vector2(footer_rect.position.x + 58.0, fy - 7.0),
		"KOMBO!",
		16,
		Color("#FFE36E"),
		Color("#10173B"),
		4,
		1.0
	)
	GameOverOverlay._draw_left_outlined_text(
		ci,
		_font_bold,
		Vector2(footer_rect.position.x + 58.0, fy + 11.0),
		APP_VERSION_TEXT,
		11,
		Color("#86C8FF"),
		Color("#060B1E"),
		2,
		0.8
	)

	# Right side of footer: SOYA GAMES studio mark + name.
	var studio_txt := "SOYA GAMES"
	var s_w := _font_extrabold.get_string_size(studio_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var right_end := footer_rect.end.x - 14.0
	var s_txt_x := right_end - s_w
	GameOverOverlay._draw_left_outlined_text(
		ci,
		_font_extrabold,
		Vector2(s_txt_x, fy),
		studio_txt,
		13,
		Color(0.90, 0.95, 1.0, 0.88),
		Color("#070C22"),
		3,
		1.0
	)
	if _studio_mark_tex != null and _studio_mark_tex.get_height() > 0:
		var mh := 22.0
		var mw := mh * (float(_studio_mark_tex.get_width()) / float(_studio_mark_tex.get_height()))
		ci.draw_texture_rect(_studio_mark_tex, Rect2(s_txt_x - mw - 7.0, fy - mh * 0.5 - 0.5, mw, mh), false, Color(0.92, 0.96, 1.0, 0.88))


func _draw_row_icon(ci: CanvasItem, kind: int, c: Vector2) -> void:
	match kind:
		0: # Sound (Speaker + waves)
			var col := Color("#EDF6FF") if _sfx_enabled else Color("#6C7FA8")
			var spk := PackedVector2Array([
				c + Vector2(-11.0, -4.2),
				c + Vector2(-5.8, -4.2),
				c + Vector2(1.0, -9.5),
				c + Vector2(1.0, 9.5),
				c + Vector2(-5.8, 4.2),
				c + Vector2(-11.0, 4.2),
			])
			ci.draw_colored_polygon(spk, col)
			if _sfx_enabled:
				ci.draw_arc(c + Vector2(0.8, 0.0), 6.2, -0.78, 0.78, 12, Color("#6BE4FF"), 2.2, true)
				ci.draw_arc(c + Vector2(0.8, 0.0), 10.4, -0.84, 0.84, 14, Color("#6BE4FF", 0.78), 2.2, true)
			else:
				var xc := c + Vector2(7.2, 0.0)
				ci.draw_line(xc + Vector2(-4.0, -4.0), xc + Vector2(4.0, 4.0), Color("#FF5A6E"), 2.4, true)
				ci.draw_line(xc + Vector2(-4.0, 4.0), xc + Vector2(4.0, -4.0), Color("#FF5A6E"), 2.4, true)
		1: # BGM (Beamed eighth notes)
			var col := Color("#EDF6FF") if _bgm_enabled else Color("#6C7FA8")
			var accent := Color("#74E8FF") if _bgm_enabled else Color("#6C7FA8")
			ci.draw_circle(c + Vector2(-6.5, 6.2), 4.0, col)
			ci.draw_circle(c + Vector2(6.5, 4.2), 4.0, col)
			ci.draw_line(c + Vector2(-3.2, 5.8), c + Vector2(-3.2, -8.0), col, 2.6, true)
			ci.draw_line(c + Vector2(9.8, 3.8), c + Vector2(9.8, -10.0), col, 2.6, true)
			ci.draw_colored_polygon(
				PackedVector2Array([
					c + Vector2(-4.4, -9.2),
					c + Vector2(11.0, -11.4),
					c + Vector2(11.0, -7.2),
					c + Vector2(-4.4, -5.0),
				]),
				accent
			)
		2: # Vibration (Phone + side wave bars)
			var col := Color("#EDF6FF") if _vibration_enabled else Color("#6C7FA8")
			var wave_col := Color("#5CE89A") if _vibration_enabled else Color("#6C7FA8")
			var phone := Rect2(c.x - 6.0, c.y - 10.5, 12.0, 21.0)
			GameOverOverlay._draw_rounded_rect_static(ci, phone, col, 3.0)
			GameOverOverlay._draw_rounded_rect_static(ci, phone.grow(-2.2), Color("#111A3E"), 1.6)
			ci.draw_circle(c + Vector2(0.0, 7.6), 1.2, col)
			# Left & right vibration zig-waves
			ci.draw_polyline(PackedVector2Array([c + Vector2(-9.5, -5.5), c + Vector2(-11.8, -2.0), c + Vector2(-9.5, 1.5), c + Vector2(-11.8, 5.0)]), wave_col, 2.0, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(9.5, -5.5), c + Vector2(11.8, -2.0), c + Vector2(9.5, 1.5), c + Vector2(11.8, 5.0)]), wave_col, 2.0, true)
		3: # Replay (Circular arrow)
			var col := Color("#5DF58A")
			var r := 9.2
			var start_a := -PI * 0.25
			var end_a := PI * 1.32
			ci.draw_arc(c, r, start_a, end_a, 20, col, 2.8, true)
			var tip := c + Vector2(cos(start_a), sin(start_a)) * r
			var tangent := Vector2(-sin(start_a), cos(start_a))
			var outward := Vector2(cos(start_a), sin(start_a))
			ci.draw_colored_polygon(
				PackedVector2Array([
					tip + tangent * 2.8 - outward * 0.6,
					tip - tangent * 4.4 + outward * 4.2,
					tip - tangent * 4.4 - outward * 4.2,
				]),
				col
			)
		4: # Home (House silhouette)
			var col := Color("#7CC4FF")
			var house := PackedVector2Array([
				c + Vector2(-7.8, -0.5),
				c + Vector2(0.0, -8.2),
				c + Vector2(7.8, -0.5),
				c + Vector2(7.8, 9.4),
				c + Vector2(-7.8, 9.4),
			])
			ci.draw_colored_polygon(house, col)
			ci.draw_polyline(
				PackedVector2Array([
					c + Vector2(-11.2, 0.3),
					c + Vector2(0.0, -10.2),
					c + Vector2(11.2, 0.3),
				]),
				col,
				3.0,
				true
			)
			ci.draw_rect(Rect2(c.x - 2.6, c.y + 2.4, 5.2, 7.2), Color("#111A3E"), true)
		5: # How to Play (Glowing cyan "?" badge)
			ci.draw_circle(c, 11.5, Color("#18367A"))
			ci.draw_arc(c, 11.5, 0.0, TAU, 24, Color("#56E6FF"), 2.2, true)
			GameOverOverlay._draw_centered_outlined_text(ci, _font_extrabold, c + Vector2(0.0, 0.5), "?", 17, Color("#FFF4B8"), Color("#07122E"), 3, 0.8)


static func _draw_top_rounded_header(ci: CanvasItem, rect: Rect2, col_top: Color, col_bot: Color, radius: float) -> void:
	var pts := GameOverOverlay._build_top_rounded_rect_points(rect, radius)
	if pts.size() < 3:
		return
	var cols := PackedColorArray()
	var h := maxf(1.0, rect.size.y)
	for pt in pts:
		cols.append(col_top.lerp(col_bot, clampf((pt.y - rect.position.y) / h, 0.0, 1.0)))
	ci.draw_polygon(pts, cols)


# ==============================================================================
# INNER CLASSES: CARD, CLOSE BUTTON, ANIMATED TOGGLE SWITCH, ACTION PILL BUTTON
# ==============================================================================

class _SettingsCard extends Control:
	var overlay: SettingsOverlay

	func _draw() -> void:
		if overlay != null:
			overlay._draw_card(self)


class _CloseIconButton extends Control:
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


class _ToggleSwitch extends Control:
	signal toggled_clean(enabled: bool)

	var _enabled: bool = true
	var _knob_t: float = 1.0
	var _hovered: bool = false
	var _pressed: bool = false
	var _sb_track: StyleBoxFlat
	var _sb_gloss: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())

		_sb_track = StyleBoxFlat.new()
		_sb_track.set_corner_radius_all(19)
		_sb_track.corner_detail = 10
		_sb_track.set_border_width_all(2)
		_sb_track.shadow_color = Color(0.01, 0.02, 0.08, 0.45)
		_sb_track.shadow_size = 3
		_sb_track.shadow_offset = Vector2(0.0, 2.0)

		_sb_gloss = StyleBoxFlat.new()
		_sb_gloss.set_corner_radius_all(8)
		_sb_gloss.corner_detail = 6
		set_process(true)

	func set_state(enabled: bool, immediate: bool = false) -> void:
		_enabled = enabled
		if immediate:
			_knob_t = 1.0 if enabled else 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var target := 1.0 if _enabled else 0.0
		if absf(_knob_t - target) > 0.002:
			_knob_t = lerpf(_knob_t, target, clampf(18.0 * minf(delta, 0.05), 0.0, 1.0))
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
					if was and Rect2(Vector2.ZERO, size).has_point(mb.position):
						_enabled = not _enabled
						toggled_clean.emit(_enabled)
					queue_redraw()
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
				if was and Rect2(Vector2.ZERO, size).has_point(st.position):
					_enabled = not _enabled
					toggled_clean.emit(_enabled)
				queue_redraw()
				accept_event()

	func _draw() -> void:
		var cid := get_canvas_item()
		var track_rect := Rect2(Vector2.ZERO, size)
		var off_col := Color("#19234B")
		var on_col := Color("#1FD655")
		_sb_track.bg_color = off_col.lerp(on_col, _knob_t)
		var off_rim := Color(0.32, 0.44, 0.78, 0.55)
		var on_rim := Color("#8CFF9C")
		_sb_track.border_color = off_rim.lerp(on_rim, _knob_t)
		_sb_track.draw(cid, track_rect)

		_sb_gloss.bg_color = Color(1.0, 1.0, 1.0, lerpf(0.06, 0.22, _knob_t))
		_sb_gloss.draw(cid, Rect2(8.0, 4.0, size.x - 16.0, size.y * 0.32))

		var knob_r := (size.y * 0.5) - 4.0
		var x_min := knob_r + 4.0
		var x_max := size.x - knob_r - 4.0
		var kx := lerpf(x_min, x_max, _knob_t)
		var ky := size.y * 0.5
		var k_scale := 0.93 if _pressed else (1.04 if _hovered else 1.0)
		var r_draw := knob_r * k_scale

		draw_circle(Vector2(kx, ky + 2.0), r_draw, Color(0.01, 0.04, 0.12, 0.36))
		draw_circle(Vector2(kx, ky), r_draw, Color("#FFFFFF"))
		draw_circle(Vector2(kx - r_draw * 0.24, ky - r_draw * 0.24), r_draw * 0.36, Color(1.0, 1.0, 1.0, 0.65))


class _ActionPillButton extends Control:
	signal pressed_clean()

	var label_text: String = "Replay"
	var font_extrabold: Font
	var is_primary_green: bool = true
	var _is_enabled: bool = true

	var _hovered: bool = false
	var _pressed: bool = false
	var _btn_scale: float = 1.0
	var _sb_shadow: StyleBoxFlat
	var _sb_lip: StyleBoxFlat
	var _sb_face: StyleBoxFlat
	var _sb_gloss: StyleBoxFlat
	var _sb_rim: StyleBoxFlat

	func set_enabled(val: bool) -> void:
		_is_enabled = val
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _is_enabled else Control.CURSOR_ARROW
		if not _is_enabled:
			_hovered = false
			_pressed = false
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())

		_sb_shadow = StyleBoxFlat.new()
		_sb_shadow.bg_color = Color(0.01, 0.02, 0.08, 0.55)
		_sb_shadow.set_corner_radius_all(13)
		_sb_shadow.corner_detail = 8

		_sb_lip = StyleBoxFlat.new()
		_sb_lip.set_corner_radius_all(13)
		_sb_lip.corner_detail = 8

		_sb_face = StyleBoxFlat.new()
		_sb_face.set_corner_radius_all(12)
		_sb_face.corner_detail = 8

		_sb_gloss = StyleBoxFlat.new()
		_sb_gloss.corner_radius_top_left = 10
		_sb_gloss.corner_radius_top_right = 10
		_sb_gloss.corner_radius_bottom_left = 4
		_sb_gloss.corner_radius_bottom_right = 4
		_sb_gloss.corner_detail = 6

		_sb_rim = StyleBoxFlat.new()
		_sb_rim.draw_center = false
		_sb_rim.set_corner_radius_all(12)
		_sb_rim.corner_detail = 8
		_sb_rim.set_border_width_all(2)
		set_process(true)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var target := 0.94 if _pressed else (1.04 if _hovered else 1.0)
		if absf(_btn_scale - target) > 0.002:
			_btn_scale = lerpf(_btn_scale, target, clampf(18.0 * minf(delta, 0.05), 0.0, 1.0))
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if not _is_enabled:
			return
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
		var press_drop := 3.0 if _pressed else 0.0
		var lip_h := 2.0 if _pressed else 5.0

		draw_set_transform(c, 0.0, Vector2(_btn_scale, _btn_scale))
		_sb_shadow.draw(cid, Rect2(local_rect.position + Vector2(0.0, 4.0), local_rect.size))

		var outer := Rect2(local_rect.position + Vector2(0.0, press_drop), Vector2(local_rect.size.x, local_rect.size.y - press_drop))
		if not _is_enabled:
			_sb_lip.bg_color = Color("#12172E")
			_sb_face.bg_color = Color("#242D52")
			_sb_rim.border_color = Color("#4B598A")
			_sb_gloss.bg_color = Color(1.0, 1.0, 1.0, 0.06)
		elif is_primary_green:
			_sb_lip.bg_color = Color("#086B2B")
			_sb_face.bg_color = Color("#34E867") if _hovered else Color("#1FD152")
			_sb_rim.border_color = Color("#C8FF82")
			_sb_gloss.bg_color = Color(1.0, 1.0, 0.88, 0.26)
		else:
			_sb_lip.bg_color = Color("#0D1C52")
			_sb_face.bg_color = Color("#3558BF") if _hovered else Color("#254196")
			_sb_rim.border_color = Color("#7FAEFF")
			_sb_gloss.bg_color = Color(0.84, 0.94, 1.0, 0.20)
		_sb_lip.draw(cid, outer)

		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		_sb_face.draw(cid, face)
		_sb_gloss.draw(cid, Rect2(face.position + Vector2(8.0, 3.0), Vector2(face.size.x - 16.0, face.size.y * 0.36)))
		_sb_rim.draw(cid, face)

		var used_font := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var outline_col := Color("#0B0E1E") if not _is_enabled else (Color("#053D16") if is_primary_green else Color("#0A153D"))
		var text_col := Color("#8B98C4") if not _is_enabled else Color("#FFFFFF")
		GameOverOverlay._draw_centered_outlined_text(self, used_font, face.get_center() + Vector2(0.0, -0.5), label_text, 18, text_col, outline_col, 4, 1.6)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
