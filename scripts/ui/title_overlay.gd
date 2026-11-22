class_name TitleOverlay
extends Control

## Full-screen 540x960 animated Title Screen for Kombo featuring the official
## K-jewel emblem (Option 3), bold 3D-extruded KOMBO! typography, high-score
## crown pill, and juicy 3D emerald-gold PLAY button over the live swirl BG.

signal play_pressed()
signal daily_pressed()
signal sprint_pressed()
signal gem_hunt_pressed()
signal settings_pressed()
signal how_to_play_pressed()

const LOGICAL_SIZE := Vector2(540.0, 960.0)
const EMBLEM_PATH := "res://assets/logo/kombo_icon_rounded.png"
const STUDIO_MARK_PATH := "res://assets/logo/soya_games_mark_light.png"
const FONT_EXTRABOLD_PATH := "res://assets/fonts/Kanit-ExtraBold.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/Kanit-Bold.ttf"

const EMBLEM_SIZE := 218.0
const PLAY_BTN_SIZE := Vector2(324.0, 66.0)
const MODE_CARD_SIZE := Vector2(102.0, 82.0)
const MODE_CARD_GAP := 9.0

var _font_extrabold: Font
var _font_bold: Font
var _emblem_tex: Texture2D
var _studio_mark_tex: Texture2D
var _radial_glow_tex: GradientTexture2D
var _sb_badge_shadow: StyleBoxFlat
var _sb_badge_body: StyleBoxFlat

var _high_score: int = 0
var _time_sec: float = 0.0
var _is_open: bool = true
var _fade_alpha: float = 1.0
var _dismissing: bool = false
var _sparkles: Array[Dictionary] = []

var _play_btn: _TitlePlayButton
var _daily_btn: _TitleDailyButton
var _sprint_btn: _TitleSprintButton
var _gem_btn: _TitleGemHuntButton
var _help_btn: _TitleTopIconButton
var _settings_btn: _TitleTopIconButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_load_assets()
	_init_cached_styles()
	_init_sparkles()
	_build_play_button()
	_layout_button()
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _play_btn != null:
		_layout_button()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _is_open or _dismissing:
		return
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo and (key_ev.keycode == KEY_ENTER or key_ev.keycode == KEY_KP_ENTER or key_ev.keycode == KEY_SPACE):
			get_viewport().set_input_as_handled()
			_trigger_play()


func _process(delta: float) -> void:
	if not visible:
		return
	var dt := minf(delta, 0.05)
	_time_sec += dt

	if _dismissing:
		_fade_alpha = move_toward(_fade_alpha, 0.0, dt * 5.5)
		modulate = Color(1.0, 1.0, 1.0, _fade_alpha)
		if _fade_alpha <= 0.01:
			visible = false
			_is_open = false
			_dismissing = false
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			return

	var vw := maxf(LOGICAL_SIZE.x, size.x)
	var vh := maxf(LOGICAL_SIZE.y, size.y)
	for mote in _sparkles:
		var pos := mote["pos"] as Vector2
		pos.y -= float(mote["speed"]) * dt
		pos.x += sin(_time_sec * 1.6 + float(mote["phase"])) * float(mote["drift"]) * dt
		if pos.y < -16.0:
			pos.y = vh + 16.0
			pos.x = fposmod(pos.x + 149.0, vw)
		mote["pos"] = pos

	queue_redraw()


func show_title(high_score: int, daily_info: Dictionary = {}, sprint_info: Dictionary = {}, gem_info: Dictionary = {}, classic_info: Dictionary = {}) -> void:
	_high_score = maxi(0, high_score)
	_is_open = true
	_dismissing = false
	_fade_alpha = 1.0
	modulate = Color.WHITE
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _play_btn != null:
		_play_btn.set_classic_info(classic_info)
	if _daily_btn != null:
		_daily_btn.set_daily_info(daily_info)
	if _sprint_btn != null:
		_sprint_btn.set_sprint_info(sprint_info)
	if _gem_btn != null:
		_gem_btn.set_gem_info(gem_info)
	_layout_button()
	queue_redraw()


func hide_immediate() -> void:
	_is_open = false
	_dismissing = false
	_fade_alpha = 0.0
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _trigger_play() -> void:
	if _dismissing:
		return
	_dismissing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_pressed.emit()


func _trigger_daily() -> void:
	if _dismissing:
		return
	daily_pressed.emit()


func _trigger_sprint() -> void:
	if _dismissing:
		return
	_dismissing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprint_pressed.emit()


func _trigger_gem_hunt() -> void:
	if _dismissing:
		return
	gem_hunt_pressed.emit()


func _load_assets() -> void:
	if ResourceLoader.exists(FONT_EXTRABOLD_PATH):
		_font_extrabold = load(FONT_EXTRABOLD_PATH) as Font
	if ResourceLoader.exists(FONT_BOLD_PATH):
		_font_bold = load(FONT_BOLD_PATH) as Font
	if _font_extrabold == null:
		_font_extrabold = ThemeDB.fallback_font
	if _font_bold == null:
		_font_bold = _font_extrabold

	if ResourceLoader.exists(EMBLEM_PATH):
		_emblem_tex = load(EMBLEM_PATH) as Texture2D
	if _emblem_tex == null:
		var abs_path := ProjectSettings.globalize_path(EMBLEM_PATH)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				_emblem_tex = ImageTexture.create_from_image(img)

	if ResourceLoader.exists(STUDIO_MARK_PATH):
		_studio_mark_tex = load(STUDIO_MARK_PATH) as Texture2D
	if _studio_mark_tex == null:
		var studio_abs := ProjectSettings.globalize_path(STUDIO_MARK_PATH)
		if FileAccess.file_exists(studio_abs):
			var s_img := Image.load_from_file(studio_abs)
			if s_img != null and not s_img.is_empty():
				_studio_mark_tex = ImageTexture.create_from_image(s_img)


func _init_cached_styles() -> void:
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.38, 0.58, 0.78, 0.94, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.72),
		Color(1.0, 1.0, 1.0, 0.36),
		Color(1.0, 1.0, 1.0, 0.14),
		Color(1.0, 1.0, 1.0, 0.03),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	_radial_glow_tex = GradientTexture2D.new()
	_radial_glow_tex.width = 128
	_radial_glow_tex.height = 128
	_radial_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_radial_glow_tex.fill_from = Vector2(0.5, 0.5)
	_radial_glow_tex.fill_to = Vector2(1.0, 0.5)
	_radial_glow_tex.gradient = grad

	_sb_badge_shadow = StyleBoxFlat.new()
	_sb_badge_shadow.bg_color = Color(0.015, 0.025, 0.09, 0.58)
	_sb_badge_shadow.set_corner_radius_all(18)
	_sb_badge_shadow.corner_detail = 8

	_sb_badge_body = StyleBoxFlat.new()
	_sb_badge_body.bg_color = Color(0.055, 0.088, 0.225, 0.86)
	_sb_badge_body.set_corner_radius_all(18)
	_sb_badge_body.corner_detail = 8
	_sb_badge_body.set_border_width_all(2)
	_sb_badge_body.border_color = Color("#FFD43B", 0.76)


func _init_sparkles() -> void:
	_sparkles.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90911
	for i in range(24):
		_sparkles.append({
			"pos": Vector2(rng.randf_range(20.0, LOGICAL_SIZE.x - 20.0), rng.randf_range(20.0, LOGICAL_SIZE.y - 20.0)),
			"radius": rng.randf_range(2.0, 4.8),
			"speed": rng.randf_range(14.0, 38.0),
			"drift": rng.randf_range(8.0, 20.0),
			"phase": rng.randf_range(0.0, TAU),
			"is_gold": (i % 2) == 0,
		})


func _build_play_button() -> void:
	_play_btn = _TitlePlayButton.new()
	_play_btn.name = "TitlePlayButton"
	_play_btn.font_extrabold = _font_extrabold
	_play_btn.font_bold = _font_bold
	_play_btn.size = PLAY_BTN_SIZE
	_play_btn.pressed_clean.connect(_trigger_play)
	add_child(_play_btn)

	_daily_btn = _TitleDailyButton.new()
	_daily_btn.name = "TitleDailyButton"
	_daily_btn.font_extrabold = _font_extrabold
	_daily_btn.font_bold = _font_bold
	_daily_btn.size = MODE_CARD_SIZE
	_daily_btn.pressed_clean.connect(_trigger_daily)
	add_child(_daily_btn)

	_sprint_btn = _TitleSprintButton.new()
	_sprint_btn.name = "TitleSprintButton"
	_sprint_btn.font_extrabold = _font_extrabold
	_sprint_btn.font_bold = _font_bold
	_sprint_btn.size = MODE_CARD_SIZE
	_sprint_btn.pressed_clean.connect(_trigger_sprint)
	add_child(_sprint_btn)

	_gem_btn = _TitleGemHuntButton.new()
	_gem_btn.name = "TitleGemHuntButton"
	_gem_btn.font_extrabold = _font_extrabold
	_gem_btn.font_bold = _font_bold
	_gem_btn.size = MODE_CARD_SIZE
	_gem_btn.pressed_clean.connect(_trigger_gem_hunt)
	add_child(_gem_btn)

	_help_btn = _TitleTopIconButton.new()
	_help_btn.name = "TitleHelpButton"
	_help_btn.is_help_icon = true
	_help_btn.font_extrabold = _font_extrabold
	_help_btn.size = Vector2(40.0, 40.0)
	_help_btn.tooltip_text = "How to Play"
	_help_btn.pressed_clean.connect(func() -> void: how_to_play_pressed.emit())
	add_child(_help_btn)

	_settings_btn = _TitleTopIconButton.new()
	_settings_btn.name = "TitleSettingsButton"
	_settings_btn.is_help_icon = false
	_settings_btn.size = Vector2(40.0, 40.0)
	_settings_btn.tooltip_text = "Settings"
	_settings_btn.pressed_clean.connect(func() -> void: settings_pressed.emit())
	add_child(_settings_btn)


func _layout_button() -> void:
	if _play_btn == null:
		return
	var vw := size.x if size.x > 10.0 else LOGICAL_SIZE.x
	var vh := size.y if size.y > 10.0 else LOGICAL_SIZE.y
	var cx := vw * 0.5
	var cy := vh * 0.5
	_play_btn.position = Vector2(cx - PLAY_BTN_SIZE.x * 0.5, cy + 114.0)
	var row2_w := MODE_CARD_SIZE.x * 3.0 + MODE_CARD_GAP * 2.0
	var row2_x := cx - row2_w * 0.5
	if _daily_btn != null:
		_daily_btn.position = Vector2(row2_x, cy + 194.0)
	if _sprint_btn != null:
		_sprint_btn.position = Vector2(row2_x + MODE_CARD_SIZE.x + MODE_CARD_GAP, cy + 194.0)
	if _gem_btn != null:
		_gem_btn.position = Vector2(row2_x + (MODE_CARD_SIZE.x + MODE_CARD_GAP) * 2.0, cy + 194.0)
	if _help_btn != null:
		_help_btn.position = Vector2(vw - 106.0, 16.0)
	if _settings_btn != null:
		_settings_btn.position = Vector2(vw - 58.0, 16.0)


func _draw() -> void:
	if not visible:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else LOGICAL_SIZE
	var cx := view_size.x * 0.5
	var cy := view_size.y * 0.5
	var pulse := 0.5 + 0.5 * sin(_time_sec * 3.2)

	# 1. Subtle velvety radial atmosphere over the live swirling royal-cobalt shader BG.
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.032, 0.052, 0.145, 0.24), true)

	# 2. Floating golden & cyan sparkle motes.
	for mote in _sparkles:
		var pos := mote["pos"] as Vector2
		var rad := float(mote["radius"])
		var twinkle := 0.35 + 0.65 * (0.5 + 0.5 * sin(_time_sec * 4.0 + float(mote["phase"])))
		var m_col := Color("#FFE066", 0.52 * twinkle) if bool(mote["is_gold"]) else Color("#3AE8FF", 0.44 * twinkle)
		draw_colored_polygon(
			PackedVector2Array([
				pos + Vector2(0.0, -rad),
				pos + Vector2(rad, 0.0),
				pos + Vector2(0.0, rad),
				pos + Vector2(-rad, 0.0),
			]),
			m_col
		)

	# 3. Hero Official K-Jewel Emblem (Option 3) gently floating with smooth Gaussian aura!
	var bob_y := sin(_time_sec * 2.4) * 5.5
	var emblem_center := Vector2(cx, cy - 196.0 + bob_y)
	var emblem_scale := 1.0 + 0.018 * sin(_time_sec * 2.4 + 0.5)

	# Dual velvety cyan + solar-gold Gaussian halos (ZERO hard circle boundaries!).
	_draw_soft_glow(emblem_center, Vector2(200.0, 200.0), Color(0.14, 0.72, 1.0, 0.34 + 0.10 * pulse))
	_draw_soft_glow(emblem_center + Vector2(0.0, -10.0), Vector2(140.0, 140.0), Color(1.0, 0.72, 0.16, 0.30 + 0.12 * pulse))

	# Soft grounded emblem shadow.
	_draw_soft_glow(emblem_center + Vector2(0.0, EMBLEM_SIZE * 0.52), Vector2(118.0, 24.0), Color(0.01, 0.02, 0.08, 0.58))

	if _emblem_tex != null:
		var half := Vector2(EMBLEM_SIZE, EMBLEM_SIZE) * 0.5 * emblem_scale
		draw_texture_rect(_emblem_tex, Rect2(emblem_center - half, half * 2.0), false, Color.WHITE)

	# 4. Bold 3D-stroked KOMBO! Arcade Title Wordmark + Crisp Tagline.
	var title_center := Vector2(cx, cy - 26.0)
	_draw_soft_glow(title_center, Vector2(205.0, 52.0), Color(1.0, 0.68, 0.16, 0.24 + 0.08 * pulse))

	# Thick 3D deep midnight extrusion underneath.
	_draw_centered_outlined_text(self, _font_extrabold, title_center + Vector2(0.0, 6.0), "KOMBO!", 70, Color("#0A1130"), Color("#070B20"), 14)
	_draw_centered_outlined_text(self, _font_extrabold, title_center, "KOMBO!", 70, Color("#FFE266"), Color("#121A42"), 12)
	# Crisp subtle upper-highlight tint overlay for arcade gloss.
	_draw_centered_outlined_text(self, _font_extrabold, title_center + Vector2(0.0, -2.0), "KOMBO!", 70, Color(1.0, 0.98, 0.84, 0.45), Color(0, 0, 0, 0), 0)

	# Sleek cyan-silver subtitle pill text.
	_draw_centered_outlined_text(self, _font_bold, Vector2(cx, cy + 22.0), "8×8 COMBO & FEVER PUZZLE", 14, Color("#8CE6FF"), Color("#08102E"), 4)

	# 5. Best Score Golden Crown Badge (cleanly centered above PLAY button).
	var badge_rect := Rect2(cx - 112.0, cy + 48.0, 224.0, 44.0)
	var cid := get_canvas_item()
	_sb_badge_shadow.draw(cid, Rect2(badge_rect.position + Vector2(0.0, 4.0), badge_rect.size))
	_sb_badge_body.draw(cid, badge_rect)

	var best_txt := "BEST  %s" % HudView.format_comma_int(_high_score)
	var crown_w := 24.0
	var gap := 8.0
	var txt_w := _font_extrabold.get_string_size(best_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var start_x := badge_rect.get_center().x - (crown_w + gap + txt_w) * 0.5
	var crown_rect := Rect2(start_x, badge_rect.get_center().y - 10.0, crown_w, 19.0)
	GameOverOverlay._draw_golden_crown(self, crown_rect, 0.5, _time_sec)
	GameOverOverlay._draw_left_outlined_text(
		self,
		_font_extrabold,
		Vector2(crown_rect.end.x + gap, badge_rect.get_center().y),
		best_txt,
		20,
		Color("#FFE46B"),
		Color("#2A1600"),
		5,
		1.6
	)

	# 6. Subtle bottom control cue.
	_draw_centered_outlined_text(
		self,
		_font_bold,
		Vector2(cx, cy + 312.0),
		"DRAG BLOCKS  •  STASH IN HOLD  •  IGNITE FEVER",
		12,
		Color(0.72, 0.84, 1.0, 0.68),
		Color(0.03, 0.05, 0.14, 0.65),
		3
	)

	# 7. Clean bottom studio signature lockup (SOYA GAMES).
	var studio_y := view_size.y - 44.0
	var studio_label := "SOYA GAMES"
	var studio_font_size := 15
	var s_txt_w := _font_extrabold.get_string_size(studio_label, HORIZONTAL_ALIGNMENT_LEFT, -1, studio_font_size).x
	var mark_h := 26.0
	var mark_w := 24.0
	if _studio_mark_tex != null and _studio_mark_tex.get_height() > 0:
		mark_w = mark_h * (float(_studio_mark_tex.get_width()) / float(_studio_mark_tex.get_height()))
	var s_gap := 8.0
	var total_w := (mark_w + s_gap + s_txt_w) if _studio_mark_tex != null else s_txt_w
	var left_x := cx - total_w * 0.5
	if _studio_mark_tex != null:
		draw_texture_rect(
			_studio_mark_tex,
			Rect2(left_x, studio_y - mark_h * 0.5 - 1.0, mark_w, mark_h),
			false,
			Color(0.92, 0.96, 1.0, 0.82)
		)
	var text_x := (left_x + mark_w + s_gap) if _studio_mark_tex != null else left_x
	var ascent := _font_extrabold.get_ascent(studio_font_size)
	var descent := _font_extrabold.get_descent(studio_font_size)
	var s_baseline := Vector2(text_x, studio_y + (ascent - descent) * 0.44)
	draw_string_outline(_font_extrabold, s_baseline, studio_label, HORIZONTAL_ALIGNMENT_LEFT, -1, studio_font_size, 4, Color(0.03, 0.05, 0.14, 0.72))
	draw_string(_font_extrabold, s_baseline, studio_label, HORIZONTAL_ALIGNMENT_LEFT, -1, studio_font_size, Color(0.88, 0.94, 1.0, 0.82))


func _draw_soft_glow(center: Vector2, half_size: Vector2, tint: Color) -> void:
	if _radial_glow_tex == null or tint.a <= 0.002:
		return
	draw_texture_rect(_radial_glow_tex, Rect2(center - half_size, half_size * 2.0), false, tint)


static func _draw_centered_outlined_text(
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
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline := Vector2(center.x - text_size.x * 0.5, center.y + (ascent - descent) * 0.45)
	if outline_size > 0:
		ci.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, outline_color)
	ci.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill_color)


class _TitlePlayButton extends Control:
	signal pressed_clean()

	var font_extrabold: Font
	var font_bold: Font
	var _can_resume: bool = false
	var _resume_score: int = 0
	var _hovered: bool = false
	var _pressed: bool = false
	var _btn_scale: float = 1.0
	var _sheen_time: float = 0.0
	var _sb_shadow: StyleBoxFlat
	var _sb_lip: StyleBoxFlat
	var _sb_face: StyleBoxFlat
	var _sb_gloss: StyleBoxFlat
	var _sb_rim: StyleBoxFlat

	func set_classic_info(info: Dictionary) -> void:
		if info.is_empty():
			_can_resume = false
			_resume_score = 0
		else:
			_can_resume = bool(info.get("can_resume", false))
			_resume_score = maxi(0, int(info.get("score", 0)))
		queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true)
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false)
		_init_styles()
		set_process(true)

	func _init_styles() -> void:
		_sb_shadow = StyleBoxFlat.new()
		_sb_shadow.bg_color = Color(0.01, 0.05, 0.03, 0.62)
		_sb_shadow.set_corner_radius_all(20)
		_sb_shadow.corner_detail = 8

		_sb_lip = StyleBoxFlat.new()
		_sb_lip.bg_color = Color("#086B2B")
		_sb_lip.set_corner_radius_all(20)
		_sb_lip.corner_detail = 8

		_sb_face = StyleBoxFlat.new()
		_sb_face.bg_color = Color("#1CD653")
		_sb_face.set_corner_radius_all(19)
		_sb_face.corner_detail = 8

		_sb_gloss = StyleBoxFlat.new()
		_sb_gloss.bg_color = Color(1.0, 1.0, 0.88, 0.28)
		_sb_gloss.corner_radius_top_left = 14
		_sb_gloss.corner_radius_top_right = 14
		_sb_gloss.corner_radius_bottom_left = 6
		_sb_gloss.corner_radius_bottom_right = 6
		_sb_gloss.corner_detail = 6

		_sb_rim = StyleBoxFlat.new()
		_sb_rim.draw_center = false
		_sb_rim.set_corner_radius_all(19)
		_sb_rim.corner_detail = 8
		_sb_rim.set_border_width_all(3)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		_sheen_time += dt
		var target := 0.96 if _pressed else (1.035 if _hovered else 1.0 + 0.012 * sin(_sheen_time * 3.8))
		_btn_scale = lerpf(_btn_scale, target, clampf(16.0 * dt, 0.0, 1.0))
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressed = true
					accept_event()
				else:
					var was_pressed := _pressed
					_pressed = false
					if was_pressed and Rect2(Vector2.ZERO, size).has_point(mb.position):
						pressed_clean.emit()
					accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_pressed = true
				accept_event()
			else:
				var was_pressed := _pressed
				_pressed = false
				if was_pressed and Rect2(Vector2.ZERO, size).has_point(st.position):
					pressed_clean.emit()
				accept_event()

	func _draw() -> void:
		var cid := get_canvas_item()
		var center := size * 0.5
		var local_rect := Rect2(-center, size)
		var press_drop := 4.5 if _pressed else 0.0
		var lip_h := 2.5 if _pressed else 7.5
		var hover_boost := 0.12 if _hovered else 0.0
		var pulse := 0.5 + 0.5 * sin(_sheen_time * 4.5)

		draw_set_transform(center, 0.0, Vector2(_btn_scale, _btn_scale))

		_sb_shadow.draw(cid, Rect2(local_rect.position + Vector2(0.0, 6.0), local_rect.size))
		var outer := Rect2(local_rect.position + Vector2(0.0, press_drop), Vector2(local_rect.size.x, local_rect.size.y - press_drop))
		_sb_lip.draw(cid, outer)

		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		_sb_face.bg_color = Color("#1CD653").lerp(Color("#46FA72"), hover_boost + pulse * 0.08)
		_sb_face.draw(cid, face)

		var gloss_rect := Rect2(face.position + Vector2(12.0, 4.0), Vector2(face.size.x - 24.0, face.size.y * 0.38))
		_sb_gloss.draw(cid, gloss_rect)

		_sb_rim.border_color = Color("#C9FF7A").lerp(Color("#FFE46B"), 0.45 + pulse * 0.25)
		_sb_rim.draw(cid, face)

		var fc := face.get_center()
		var used_font := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var used_bold := font_bold if font_bold != null else used_font
		var tri_c := fc + Vector2(-78.0 if _can_resume else -56.0, -0.5)
		var tri := PackedVector2Array([
			tri_c + Vector2(-8.0, -10.5),
			tri_c + Vector2(11.0, 0.0),
			tri_c + Vector2(-8.0, 10.5),
		])
		var tri_shadow := PackedVector2Array([tri[0] + Vector2(0.0, 2.5), tri[1] + Vector2(0.0, 2.5), tri[2] + Vector2(0.0, 2.5)])
		draw_colored_polygon(tri_shadow, Color("#053D16", 0.78))
		var tri_loop := tri.duplicate()
		tri_loop.append(tri[0])
		draw_polyline(tri_loop, Color("#053D16"), 5.2, true)
		draw_colored_polygon(tri, Color("#FFFFFF"))

		if _can_resume:
			GameOverOverlay._draw_centered_outlined_text(self, used_font, fc + Vector2(14.0, -8.5), "RESUME", 24, Color("#FFFFFF"), Color("#053D16"), 6, 2.0)
			GameOverOverlay._draw_centered_outlined_text(self, used_bold, fc + Vector2(14.0, 13.0), "CLASSIC  •  %s PTS" % HudView.format_comma_int(_resume_score), 11, Color("#E6FFBA"), Color("#053D16"), 3, 1.0)
		else:
			GameOverOverlay._draw_centered_outlined_text(self, used_font, fc + Vector2(18.0, -1.0), "PLAY", 32, Color("#FFFFFF"), Color("#053D16"), 7, 2.4)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _TitleTopIconButton extends Control:
	signal pressed_clean()

	var is_help_icon: bool = false
	var font_extrabold: Font
	var _hovered: bool = false
	var _pressed: bool = false
	var _pop_scale: float = 1.0
	var _spin_angle: float = 0.0
	var _sb_lip: StyleBoxFlat
	var _sb_face: StyleBoxFlat
	var _sb_gloss: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())

		_sb_lip = StyleBoxFlat.new()
		_sb_lip.bg_color = Color("#090F29")
		_sb_lip.set_corner_radius_all(11)
		_sb_lip.corner_detail = 6
		_sb_lip.shadow_color = Color(0.02, 0.03, 0.10, 0.55)
		_sb_lip.shadow_size = 3
		_sb_lip.shadow_offset = Vector2(0.0, 2.5)

		_sb_face = StyleBoxFlat.new()
		_sb_face.set_corner_radius_all(10)
		_sb_face.corner_detail = 6
		_sb_face.set_border_width_all(1)

		_sb_gloss = StyleBoxFlat.new()
		_sb_gloss.set_corner_radius_all(4)
		_sb_gloss.corner_detail = 4
		set_process(true)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		var target := 0.92 if _pressed else (1.06 if _hovered else 1.0)
		var dirty := false
		if absf(_pop_scale - target) > 0.002:
			_pop_scale = lerpf(_pop_scale, target, clampf(18.0 * dt, 0.0, 1.0))
			dirty = true
		if _spin_angle > 0.01:
			_spin_angle = maxf(0.0, _spin_angle - dt * 10.0)
			dirty = true
		if dirty:
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
						if not is_help_icon:
							_spin_angle = PI * 0.5
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
					if not is_help_icon:
						_spin_angle = PI * 0.5
					pressed_clean.emit()
				accept_event()

	func _draw() -> void:
		var cid := get_canvas_item()
		var center := size * 0.5
		var local_rect := Rect2(-center, size)
		var press_y := 1.8 if _pressed else 0.0
		var lip_h := 1.4 if _pressed else 3.2

		draw_set_transform(center, 0.0, Vector2(_pop_scale, _pop_scale))
		var btn_rect := Rect2(local_rect.position + Vector2(0.0, press_y), Vector2(local_rect.size.x, local_rect.size.y - press_y))
		_sb_lip.draw(cid, btn_rect)

		var face_rect := Rect2(btn_rect.position, Vector2(btn_rect.size.x, btn_rect.size.y - lip_h))
		_sb_face.bg_color = Color(0.12, 0.19, 0.42, 0.92) if _hovered else Color(0.09, 0.14, 0.33, 0.86)
		_sb_face.border_color = Color(0.54, 0.74, 1.0, 0.74) if _hovered else Color(0.38, 0.54, 0.90, 0.54)
		_sb_face.draw(cid, face_rect)

		var gloss := Rect2(face_rect.position + Vector2(4.0, 2.0), Vector2(face_rect.size.x - 8.0, face_rect.size.y * 0.36))
		_sb_gloss.bg_color = Color(0.75, 0.88, 1.0, 0.16 if _hovered else 0.11)
		_sb_gloss.draw(cid, gloss)

		var c := face_rect.get_center()
		var col := Color("#FFE57A") if _hovered else Color("#EDF6FF")
		if is_help_icon:
			var used_font := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
			GameOverOverlay._draw_centered_outlined_text(self, used_font, c + Vector2(0.0, 0.5), "?", 22, col, Color("#08102A"), 3, 1.0)
		else:
			var hole_col := Color(0.12, 0.19, 0.42, 1.0) if _hovered else Color(0.09, 0.14, 0.33, 1.0)
			for i in range(8):
				var a := _spin_angle + float(i) * (TAU / 8.0)
				var dir := Vector2(cos(a), sin(a))
				var perp := Vector2(-dir.y, dir.x)
				draw_colored_polygon(
					PackedVector2Array([
						c + dir * 5.6 - perp * 2.0,
						c + dir * 9.8 - perp * 1.4,
						c + dir * 9.8 + perp * 1.4,
						c + dir * 5.6 + perp * 2.0,
					]),
					col
				)
			draw_circle(c, 6.8, col)
			draw_circle(c, 3.0, hole_col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _TitleDailyButton extends Control:
	signal pressed_clean()

	var font_extrabold: Font
	var font_bold: Font

	var _date_short: String = ""
	var _attempts_left: int = DailyChallenge.MAX_DAILY_ATTEMPTS
	var _daily_best: int = 0
	var _streak: int = 0
	var _can_resume: bool = false
	var _active_attempt: int = 1

	var _hovered: bool = false
	var _pressed: bool = false
	var _btn_scale: float = 1.0
	var _time: float = 0.0

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
		_date_short = DailyChallenge.format_display_date(DailyChallenge.get_today_date_key(), false)

		_sb_shadow = StyleBoxFlat.new()
		_sb_shadow.bg_color = Color(0.02, 0.02, 0.09, 0.60)
		_sb_shadow.set_corner_radius_all(18)
		_sb_shadow.corner_detail = 8

		_sb_lip = StyleBoxFlat.new()
		_sb_lip.set_corner_radius_all(18)
		_sb_lip.corner_detail = 8

		_sb_face = StyleBoxFlat.new()
		_sb_face.set_corner_radius_all(17)
		_sb_face.corner_detail = 8

		_sb_gloss = StyleBoxFlat.new()
		_sb_gloss.corner_radius_top_left = 13
		_sb_gloss.corner_radius_top_right = 13
		_sb_gloss.corner_radius_bottom_left = 5
		_sb_gloss.corner_radius_bottom_right = 5
		_sb_gloss.corner_detail = 6

		_sb_rim = StyleBoxFlat.new()
		_sb_rim.draw_center = false
		_sb_rim.set_corner_radius_all(17)
		_sb_rim.corner_detail = 8
		_sb_rim.set_border_width_all(2)
		set_process(true)

	func set_daily_info(info: Dictionary) -> void:
		if info.is_empty():
			_date_short = DailyChallenge.format_display_date(DailyChallenge.get_today_date_key(), false)
			_attempts_left = DailyChallenge.MAX_DAILY_ATTEMPTS
			_daily_best = 0
			_streak = 0
			_can_resume = false
			_active_attempt = 1
		else:
			var dkey := String(info.get("date_key", DailyChallenge.get_today_date_key()))
			_date_short = DailyChallenge.format_display_date(dkey, false)
			_attempts_left = int(info.get("attempts_left", DailyChallenge.MAX_DAILY_ATTEMPTS))
			_daily_best = int(info.get("daily_best_score", 0))
			_streak = int(info.get("daily_streak", 0))
			_can_resume = bool(info.get("can_resume", false))
			_active_attempt = int(info.get("active_attempt", 1))
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		_time += dt
		var target := 0.96 if _pressed else (1.03 if _hovered else 1.0)
		_btn_scale = lerpf(_btn_scale, target, clampf(16.0 * dt, 0.0, 1.0))
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
		var center := size * 0.5
		var local_rect := Rect2(-center, size)
		var press_drop := 4.0 if _pressed else 0.0
		var lip_h := 2.0 if _pressed else 6.5
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		var is_done := (not _can_resume) and _attempts_left <= 0

		draw_set_transform(center, 0.0, Vector2(_btn_scale, _btn_scale))
		_sb_shadow.draw(cid, Rect2(local_rect.position + Vector2(0.0, 5.0), local_rect.size))

		var outer := Rect2(local_rect.position + Vector2(0.0, press_drop), Vector2(local_rect.size.x, local_rect.size.y - press_drop))
		_sb_lip.bg_color = Color("#132054") if is_done else Color("#8F4200")
		_sb_lip.draw(cid, outer)

		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		if is_done:
			_sb_face.bg_color = Color("#253A82") if _hovered else Color("#1D2E6B")
			_sb_rim.border_color = Color("#70D8FF").lerp(Color("#FFE26A"), 0.35 + 0.2 * pulse)
			_sb_gloss.bg_color = Color(0.84, 0.94, 1.0, 0.16)
		else:
			var base_gold := Color("#FF9818").lerp(Color("#FFB828"), 0.35 + (0.25 if _hovered else 0.0) + pulse * 0.12)
			_sb_face.bg_color = base_gold
			_sb_rim.border_color = Color("#FFF094")
			_sb_gloss.bg_color = Color(1.0, 0.98, 0.82, 0.28)
		_sb_face.draw(cid, face)
		_sb_gloss.draw(cid, Rect2(face.position + Vector2(10.0, 3.0), Vector2(face.size.x - 20.0, face.size.y * 0.36)))
		_sb_rim.draw(cid, face)

		# Compact 102x82 card layout for 3-mode row!
		var fc := face.get_center()
		var ic := Vector2(face.position.x + 21.0, face.position.y + 21.0)
		var cal := Rect2(ic.x - 9.5, ic.y - 9.0, 19.0, 18.0)
		GameOverOverlay._draw_rounded_rect_static(self, cal, Color("#FFF7DC"), 3.8)
		GameOverOverlay._draw_rounded_rect_static(self, Rect2(cal.position, Vector2(cal.size.x, 5.8)), Color("#E63B2E") if not is_done else Color("#20B8F0"), 3.0)
		draw_rect(Rect2(cal.position.x + 3.5, cal.position.y - 2.2, 2.4, 4.0), Color("#FFFFFF"), true)
		draw_rect(Rect2(cal.end.x - 5.9, cal.position.y - 2.2, 2.4, 4.0), Color("#FFFFFF"), true)
		var sc := Vector2(ic.x, ic.y + 3.0)
		draw_colored_polygon(PackedVector2Array([sc + Vector2(0, -4.0), sc + Vector2(3.8, 0), sc + Vector2(0, 4.0), sc + Vector2(-3.8, 0)]), Color("#E67A00") if not is_done else Color("#1D6CE6"))

		var used_eb := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var used_b := font_bold if font_bold != null else used_eb
		var outline_col := Color("#0B163D") if is_done else Color("#592300")

		if _streak > 0:
			var sp := Rect2(face.end.x - 39.0, face.position.y + 10.0, 32.0, 20.0)
			GameOverOverlay._draw_rounded_rect_static(self, sp, Color(0.08, 0.05, 0.16, 0.72), 8.0)
			GameOverOverlay._draw_flame_icon(self, Vector2(sp.position.x + 9.0, sp.get_center().y), 5.0, _time)
			GameOverOverlay._draw_left_outlined_text(self, used_eb, Vector2(sp.position.x + 16.5, sp.get_center().y), "%d" % _streak, 11, Color("#FFE46B"), Color("#291000"), 2, 0.8)
		else:
			var badge_r := Rect2(face.end.x - 42.0, face.position.y + 10.0, 35.0, 19.0)
			GameOverOverlay._draw_rounded_rect_static(self, badge_r, Color(0.14, 0.06, 0.02, 0.45), 8.0)
			GameOverOverlay._draw_centered_outlined_text(self, used_eb, badge_r.get_center(), "%d/3" % _attempts_left, 10, Color("#FFF4B8"), outline_col, 2, 0.6)

		var main_label := "RESUME" if _can_resume else "DAILY"
		var sub_label := ""
		if _can_resume:
			sub_label = "TRY %d/%d" % [_active_attempt, DailyChallenge.MAX_DAILY_ATTEMPTS]
		elif is_done:
			sub_label = HudView.format_comma_int(_daily_best)
		else:
			sub_label = "%s • %d/3" % [_date_short, _attempts_left]

		GameOverOverlay._draw_centered_outlined_text(self, used_eb, Vector2(fc.x, face.position.y + 44.0), main_label, 16, Color("#FFFFFF"), outline_col, 4, 1.3)
		GameOverOverlay._draw_centered_outlined_text(
			self,
			used_b,
			Vector2(fc.x, face.position.y + 62.0),
			sub_label,
			10,
			Color("#9CE8FF") if is_done else Color("#FFF6C7"),
			outline_col,
			2,
			0.8
		)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _TitleSprintButton extends Control:
	signal pressed_clean()

	var font_extrabold: Font
	var font_bold: Font

	var _sprint_best: int = 0
	var _can_resume: bool = false
	var _moves_left: int = GameController.SPRINT_TOTAL_MOVES

	var _hovered: bool = false
	var _pressed: bool = false
	var _btn_scale: float = 1.0
	var _time: float = 0.0

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
		_sb_shadow.bg_color = Color(0.03, 0.01, 0.10, 0.60)
		_sb_shadow.set_corner_radius_all(18)
		_sb_shadow.corner_detail = 8

		_sb_lip = StyleBoxFlat.new()
		_sb_lip.bg_color = Color("#46127D")
		_sb_lip.set_corner_radius_all(18)
		_sb_lip.corner_detail = 8

		_sb_face = StyleBoxFlat.new()
		_sb_face.set_corner_radius_all(17)
		_sb_face.corner_detail = 8

		_sb_gloss = StyleBoxFlat.new()
		_sb_gloss.bg_color = Color(0.95, 0.84, 1.0, 0.24)
		_sb_gloss.corner_radius_top_left = 13
		_sb_gloss.corner_radius_top_right = 13
		_sb_gloss.corner_radius_bottom_left = 5
		_sb_gloss.corner_radius_bottom_right = 5
		_sb_gloss.corner_detail = 6

		_sb_rim = StyleBoxFlat.new()
		_sb_rim.draw_center = false
		_sb_rim.set_corner_radius_all(17)
		_sb_rim.corner_detail = 8
		_sb_rim.set_border_width_all(2)
		set_process(true)

	func set_sprint_info(info: Dictionary) -> void:
		if info.is_empty():
			_sprint_best = 0
			_can_resume = false
			_moves_left = GameController.SPRINT_TOTAL_MOVES
		else:
			_sprint_best = int(info.get("sprint_high_score", 0))
			_can_resume = bool(info.get("can_resume", false))
			_moves_left = int(info.get("moves_left", GameController.SPRINT_TOTAL_MOVES))
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		_time += dt
		var target := 0.96 if _pressed else (1.03 if _hovered else 1.0)
		_btn_scale = lerpf(_btn_scale, target, clampf(16.0 * dt, 0.0, 1.0))
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
		var center := size * 0.5
		var local_rect := Rect2(-center, size)
		var press_drop := 4.0 if _pressed else 0.0
		var lip_h := 2.0 if _pressed else 6.5
		var pulse := 0.5 + 0.5 * sin(_time * 4.4 + 1.2)

		draw_set_transform(center, 0.0, Vector2(_btn_scale, _btn_scale))
		_sb_shadow.draw(cid, Rect2(local_rect.position + Vector2(0.0, 5.0), local_rect.size))

		var outer := Rect2(local_rect.position + Vector2(0.0, press_drop), Vector2(local_rect.size.x, local_rect.size.y - press_drop))
		_sb_lip.draw(cid, outer)

		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		_sb_face.bg_color = Color("#8D2CE6").lerp(Color("#B648FF"), (0.30 if _hovered else 0.0) + pulse * 0.14)
		_sb_face.draw(cid, face)
		_sb_gloss.draw(cid, Rect2(face.position + Vector2(10.0, 3.0), Vector2(face.size.x - 20.0, face.size.y * 0.36)))
		_sb_rim.border_color = Color("#E8B0FF").lerp(Color("#66F0FF"), 0.25 + pulse * 0.25)
		_sb_rim.draw(cid, face)

		var fc := face.get_center()
		var used_eb := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var used_b := font_bold if font_bold != null else used_eb
		var outline_col := Color("#2B0752")

		# Top-left electric lightning bolt emblem (2 crisp convex triangles!).
		var bc := Vector2(face.position.x + 21.0, face.position.y + 20.0)
		draw_colored_polygon(PackedVector2Array([bc + Vector2(1.8, -9.5), bc + Vector2(-6.2, 0.8), bc + Vector2(0.8, 0.8)]), Color("#FFF48C"))
		draw_colored_polygon(PackedVector2Array([bc + Vector2(-0.8, -0.8), bc + Vector2(6.2, -0.8), bc + Vector2(-1.8, 9.5)]), Color("#FFE048"))

		# Top-right compact "60" moves pill badge.
		var badge := Rect2(face.end.x - 45.0, face.position.y + 10.0, 38.0, 19.0)
		GameOverOverlay._draw_rounded_rect_static(self, badge, Color(0.11, 0.03, 0.24, 0.72), 8.0)
		GameOverOverlay._draw_centered_outlined_text(self, used_eb, badge.get_center(), "20×3", 10, Color("#7EF2FF"), Color("#1C0638"), 2, 0.8)

		var main_label := "RESUME" if _can_resume else "SPRINT"
		var sub_label := ""
		if _can_resume:
			sub_label = "%d LEFT" % _moves_left
		elif _sprint_best > 0:
			sub_label = "BEST %s" % HudView.format_comma_int(_sprint_best)
		else:
			sub_label = "60 MOVES"

		GameOverOverlay._draw_centered_outlined_text(self, used_eb, Vector2(fc.x, face.position.y + 44.0), main_label, 16, Color("#FFFFFF"), outline_col, 4, 1.3)
		GameOverOverlay._draw_centered_outlined_text(self, used_b, Vector2(fc.x, face.position.y + 62.0), sub_label, 10, Color("#E7D6FF"), outline_col, 2, 0.8)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _TitleGemHuntButton extends Control:
	signal pressed_clean()

	var font_extrabold: Font
	var font_bold: Font

	var _best_stage: int = 1
	var _best_score: int = 0
	var _can_resume: bool = false
	var _active_stage: int = 1
	var _targets_left: int = 0

	var _hovered: bool = false
	var _pressed: bool = false
	var _btn_scale: float = 1.0
	var _time: float = 0.0

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
		_sb_shadow.bg_color = Color(0.01, 0.04, 0.10, 0.60)
		_sb_shadow.set_corner_radius_all(18)
		_sb_shadow.corner_detail = 8

		_sb_lip = StyleBoxFlat.new()
		_sb_lip.bg_color = Color("#065470")
		_sb_lip.set_corner_radius_all(18)
		_sb_lip.corner_detail = 8

		_sb_face = StyleBoxFlat.new()
		_sb_face.set_corner_radius_all(17)
		_sb_face.corner_detail = 8

		_sb_gloss = StyleBoxFlat.new()
		_sb_gloss.bg_color = Color(0.84, 0.99, 1.0, 0.28)
		_sb_gloss.corner_radius_top_left = 13
		_sb_gloss.corner_radius_top_right = 13
		_sb_gloss.corner_radius_bottom_left = 5
		_sb_gloss.corner_radius_bottom_right = 5
		_sb_gloss.corner_detail = 6

		_sb_rim = StyleBoxFlat.new()
		_sb_rim.draw_center = false
		_sb_rim.set_corner_radius_all(17)
		_sb_rim.corner_detail = 8
		_sb_rim.set_border_width_all(2)
		set_process(true)

	func set_gem_info(info: Dictionary) -> void:
		if info.is_empty():
			_best_stage = 1
			_best_score = 0
			_can_resume = false
			_active_stage = 1
			_targets_left = 0
		else:
			_best_stage = maxi(1, int(info.get("best_stage", 1)))
			_best_score = int(info.get("best_score", 0))
			_can_resume = bool(info.get("can_resume", false))
			_active_stage = maxi(1, int(info.get("active_stage", 1)))
			_targets_left = maxi(0, int(info.get("targets_left", 0)))
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		_time += dt
		var target := 0.96 if _pressed else (1.03 if _hovered else 1.0)
		_btn_scale = lerpf(_btn_scale, target, clampf(16.0 * dt, 0.0, 1.0))
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
		var center := size * 0.5
		var local_rect := Rect2(-center, size)
		var press_drop := 4.0 if _pressed else 0.0
		var lip_h := 2.0 if _pressed else 6.5
		var pulse := 0.5 + 0.5 * sin(_time * 4.2 + 2.4)

		draw_set_transform(center, 0.0, Vector2(_btn_scale, _btn_scale))
		_sb_shadow.draw(cid, Rect2(local_rect.position + Vector2(0.0, 5.0), local_rect.size))

		var outer := Rect2(local_rect.position + Vector2(0.0, press_drop), Vector2(local_rect.size.x, local_rect.size.y - press_drop))
		_sb_lip.draw(cid, outer)

		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		_sb_face.bg_color = Color("#0DB2D9").lerp(Color("#24D9F7"), (0.30 if _hovered else 0.0) + pulse * 0.14)
		_sb_face.draw(cid, face)
		_sb_gloss.draw(cid, Rect2(face.position + Vector2(10.0, 3.0), Vector2(face.size.x - 20.0, face.size.y * 0.36)))
		_sb_rim.border_color = Color("#A8FCFF").lerp(Color("#FFF08A"), 0.22 + pulse * 0.22)
		_sb_rim.draw(cid, face)

		var fc := face.get_center()
		var used_eb := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var used_b := font_bold if font_bold != null else used_eb
		var outline_col := Color("#043045")

		# Top-left gleaming faceted Crystal Diamond emblem!
		var dc := Vector2(face.position.x + 21.0, face.position.y + 20.0)
		var dia := PackedVector2Array([dc + Vector2(0.0, -9.5), dc + Vector2(7.8, 0.0), dc + Vector2(0.0, 9.5), dc + Vector2(-7.8, 0.0)])
		var dia_loop := dia.duplicate()
		dia_loop.append(dia[0])
		draw_polyline(dia_loop, Color("#043045"), 3.2, true)
		draw_colored_polygon(dia, Color("#E4FFFF"))
		draw_colored_polygon(PackedVector2Array([dc + Vector2(0.0, -4.5), dc + Vector2(3.6, 0.0), dc + Vector2(0.0, 4.5), dc + Vector2(-3.6, 0.0)]), Color("#5CEEFF"))

		# Top-right compact stage badge ("STG X").
		var stg_num := _active_stage if _can_resume else _best_stage
		var badge := Rect2(face.end.x - 47.0, face.position.y + 10.0, 40.0, 19.0)
		GameOverOverlay._draw_rounded_rect_static(self, badge, Color(0.02, 0.14, 0.24, 0.72), 8.0)
		GameOverOverlay._draw_centered_outlined_text(self, used_eb, badge.get_center(), "STG %d" % stg_num, 10, Color("#FFE875"), Color("#032233"), 2, 0.8)

		var main_label := "RESUME" if _can_resume else "GEMS"
		var sub_label := ""
		if _can_resume:
			sub_label = "◆ %d LEFT" % _targets_left
		elif _best_score > 0:
			sub_label = "BEST %s" % HudView.format_comma_int(_best_score)
		else:
			sub_label = "CLEAR STAGES"

		GameOverOverlay._draw_centered_outlined_text(self, used_eb, Vector2(fc.x, face.position.y + 44.0), main_label, 16, Color("#FFFFFF"), outline_col, 4, 1.3)
		GameOverOverlay._draw_centered_outlined_text(self, used_b, Vector2(fc.x, face.position.y + 62.0), sub_label, 10, Color("#DEFFFF"), outline_col, 2, 0.8)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
