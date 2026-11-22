class_name GameOverOverlay
extends Control

## Full-screen 540x960 Game Over & New High Score celebration modal for Kombo.
## Hidden by default; springs & fades in cleanly over a dark midnight-indigo backdrop.

signal play_again_pressed()
signal home_pressed()
signal share_pressed()
signal stages_pressed()
signal double_reward_pressed()

const OVERLAY_SIZE := Vector2(540.0, 960.0)
const CARD_SIZE := Vector2(410.0, 520.0)
const REWARD_STRIP_RECT := Rect2(24.0, 338.0, 362.0, 68.0)
const DOUBLE_BTN_RECT := Rect2(236.0, 348.0, 140.0, 48.0)
const HOME_BTN_RECT := Rect2(24.0, 422.0, 68.0, 68.0)
const PLAY_BTN_RECT := Rect2(104.0, 422.0, 282.0, 68.0)
const DAILY_RETRY_BTN_RECT := Rect2(104.0, 422.0, 174.0, 68.0)
const DAILY_SHARE_COMPACT_RECT := Rect2(288.0, 422.0, 98.0, 68.0)
const DAILY_SHARE_WIDE_RECT := Rect2(104.0, 422.0, 282.0, 68.0)

const FONT_EXTRABOLD_PATH := "res://assets/fonts/Kanit-ExtraBold.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/Kanit-Bold.ttf"
const FONT_SEMIBOLD_PATH := "res://assets/fonts/Kanit-SemiBold.ttf"

const SCORE_ROLL_DURATION := 0.65

var _font_extrabold: Font
var _font_bold: Font
var _font_semibold: Font

var _final_score: int = 0
var _high_score: int = 0
var _best_combo: int = 0
var _is_new_best: bool = false
var _is_daily_mode: bool = false
var _daily_date_label: String = ""
var _daily_attempt_num: int = 1
var _daily_attempts_left: int = 0
var _daily_streak: int = 0
var _daily_summary_only: bool = false
var _is_sprint_mode: bool = false
var _sprint_moves_used: int = 0
var _sprint_moves_limit: int = 60
var _sprint_completed: bool = false
var _is_gem_hunt_mode: bool = false
var _gem_stage_reached: int = 1
var _gem_best_stage: int = 1
var _copied_timer: float = 0.0

var _reward_coins_run: int = 0
var _reward_coins_wallet: int = 0
var _reward_can_double: bool = false
var _reward_doubled: bool = false
var _reward_visible: bool = false
var _reward_pop_scale: float = 1.0
var _reward_pop_vel: float = 0.0
var _is_processing_ad: bool = false

var _is_showing: bool = false
var _time_sec: float = 0.0
var _backdrop_alpha: float = 0.0
var _card_alpha: float = 0.0
var _card_scale: float = 0.82
var _card_scale_vel: float = 0.0
var _card_y_offset: float = 28.0

var _score_roll_t: float = 0.0
var _displayed_final_score: float = 0.0
var _score_landed: bool = false
var _score_pop_scale: float = 1.0
var _score_pop_vel: float = 0.0

var _sparkles: Array[Dictionary] = []

var _radial_glow_tex: GradientTexture2D
var _sb_card_shadow: StyleBoxFlat
var _sb_card_lip: StyleBoxFlat
var _sb_card_body: StyleBoxFlat
var _sb_card_inner: StyleBoxFlat
var _sb_card_rim: StyleBoxFlat
var _sb_stat_shadow: StyleBoxFlat
var _sb_stat_body: StyleBoxFlat
var _sb_stat_gloss: StyleBoxFlat

var _card: _GameOverCard
var _home_btn: _HomeModalButton
var _play_btn: _PlayAgainButton
var _share_btn: _ShareResultButton
var _double_btn: _DoubleRewardButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_load_fonts()
	_init_cached_gpu_resources()
	_init_sparkles()
	_build_card()
	_center_card()
	set_process(true)


func _init_cached_gpu_resources() -> void:
	_radial_glow_tex = _create_radial_glow_texture()

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

	_sb_stat_shadow = StyleBoxFlat.new()
	_sb_stat_shadow.bg_color = Color(0.01, 0.02, 0.07, 0.55)
	_sb_stat_shadow.set_corner_radius_all(16)
	_sb_stat_shadow.corner_detail = 8

	_sb_stat_body = StyleBoxFlat.new()
	_sb_stat_body.set_corner_radius_all(16)
	_sb_stat_body.corner_detail = 8
	_sb_stat_body.set_border_width_all(2)

	_sb_stat_gloss = StyleBoxFlat.new()
	_sb_stat_gloss.set_corner_radius_all(6)
	_sb_stat_gloss.corner_detail = 6


static func _create_radial_glow_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	grad.offsets = PackedFloat32Array([0.0, 0.16, 0.34, 0.52, 0.70, 0.84, 0.94, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.74),
		Color(1.0, 1.0, 1.0, 0.42),
		Color(1.0, 1.0, 1.0, 0.20),
		Color(1.0, 1.0, 1.0, 0.08),
		Color(1.0, 1.0, 1.0, 0.02),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.gradient = grad
	return tex


func _draw_soft_glow(ci: CanvasItem, center: Vector2, half_size: Vector2, tint: Color) -> void:
	if _radial_glow_tex == null or tint.a <= 0.002:
		return
	ci.draw_texture_rect(_radial_glow_tex, Rect2(center - half_size, half_size * 2.0), false, tint)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _card != null:
		_center_card()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _is_showing:
		return
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			if _is_processing_ad:
				get_viewport().set_input_as_handled()
				return
			if key_ev.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_on_home_clicked()
			elif key_ev.keycode == KEY_ENTER or key_ev.keycode == KEY_KP_ENTER or key_ev.keycode == KEY_SPACE:
				get_viewport().set_input_as_handled()
				if _is_daily_mode and _daily_attempts_left <= 0:
					_on_share_clicked()
				else:
					_on_play_again_clicked()


func _process(delta: float) -> void:
	if not visible:
		return
	var dt := minf(delta, 0.05)
	_time_sec += dt
	if _copied_timer > 0.0:
		_copied_timer = maxf(0.0, _copied_timer - dt)
		if _share_btn != null:
			_share_btn.set_copied(_copied_timer > 0.0)

	# Backdrop & card fade + elastic spring entrance.
	_backdrop_alpha = move_toward(_backdrop_alpha, 1.0, dt * 4.2)
	_card_alpha = move_toward(_card_alpha, 1.0, dt * 4.8)
	_card_y_offset = lerpf(_card_y_offset, 0.0, clampf(14.0 * dt, 0.0, 1.0))

	var cs := _step_spring(_card_scale, _card_scale_vel, 1.0, 260.0, 16.5, dt)
	_card_scale = cs.x
	_card_scale_vel = cs.y

	# Final score animated roll-up with ease-out curve & landing bounce.
	if _final_score <= 0:
		_displayed_final_score = 0.0
		_score_landed = true
	elif not _score_landed:
		_score_roll_t = minf(1.0, _score_roll_t + dt / SCORE_ROLL_DURATION)
		var eased := 1.0 - pow(1.0 - _score_roll_t, 3.0)
		_displayed_final_score = float(_final_score) * eased
		if _score_roll_t >= 1.0:
			_displayed_final_score = float(_final_score)
			_score_landed = true
			_score_pop_scale = 1.24 if _is_new_best else 1.16
			_score_pop_vel = 2.2

	var sp := _step_spring(_score_pop_scale, _score_pop_vel, 1.0, 280.0, 17.0, dt)
	_score_pop_scale = sp.x
	_score_pop_vel = sp.y

	var rp := _step_spring(_reward_pop_scale, _reward_pop_vel, 1.0, 290.0, 16.0, dt)
	_reward_pop_scale = rp.x
	_reward_pop_vel = rp.y

	# Gently drift ambient celebration motes.
	var view_w := maxf(OVERLAY_SIZE.x, size.x)
	var view_h := maxf(OVERLAY_SIZE.y, size.y)
	for mote in _sparkles:
		var pos := mote["pos"] as Vector2
		var speed := float(mote["speed"])
		var drift := float(mote["drift"])
		pos.y -= speed * dt
		pos.x += sin(_time_sec * 1.8 + float(mote["phase"])) * drift * dt
		if pos.y < -16.0:
			pos.y = view_h + 16.0
			pos.x = fposmod(pos.x + 137.0, view_w)
		mote["pos"] = pos

	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


# ==============================================================================
# PUBLIC API
# ==============================================================================

func show_game_over(final_score: int, high_score: int, best_combo: int, is_new_best: bool) -> void:
	_is_daily_mode = false
	_is_sprint_mode = false
	_is_gem_hunt_mode = false
	_daily_date_label = ""
	_daily_attempt_num = 1
	_daily_attempts_left = 0
	_daily_streak = 0
	_daily_summary_only = false
	_copied_timer = 0.0
	_configure_action_buttons()
	_open_modal_common(final_score, high_score, best_combo, is_new_best)


func show_daily_over(
	final_score: int,
	daily_best: int,
	best_combo: int,
	is_new_best: bool,
	date_key: String,
	attempt_num: int,
	attempts_left: int,
	streak: int,
	is_summary_only: bool = false
) -> void:
	_is_daily_mode = true
	_is_sprint_mode = false
	_is_gem_hunt_mode = false
	_daily_date_label = DailyChallenge.format_display_date(date_key, true)
	_daily_attempt_num = clampi(attempt_num, 1, DailyChallenge.MAX_DAILY_ATTEMPTS)
	_daily_attempts_left = maxi(0, attempts_left)
	_daily_streak = maxi(0, streak)
	_daily_summary_only = is_summary_only
	_copied_timer = 0.0
	_configure_action_buttons()
	_open_modal_common(final_score, daily_best, best_combo, is_new_best)


func show_sprint_over(
	final_score: int,
	sprint_best: int,
	best_combo: int,
	is_new_best: bool,
	moves_used: int,
	moves_limit: int,
	completed: bool
) -> void:
	_is_daily_mode = false
	_is_sprint_mode = true
	_is_gem_hunt_mode = false
	_sprint_moves_used = clampi(moves_used, 0, maxi(1, moves_limit))
	_sprint_moves_limit = maxi(1, moves_limit)
	_sprint_completed = completed
	_copied_timer = 0.0
	_configure_action_buttons()
	_open_modal_common(final_score, sprint_best, best_combo, is_new_best)


func show_gem_hunt_over(
	final_score: int,
	gem_best: int,
	best_combo: int,
	is_new_best: bool,
	stage_reached: int,
	best_stage: int
) -> void:
	_is_daily_mode = false
	_is_sprint_mode = false
	_is_gem_hunt_mode = true
	_gem_stage_reached = maxi(1, stage_reached)
	_gem_best_stage = maxi(_gem_stage_reached, best_stage)
	_copied_timer = 0.0
	_configure_action_buttons()
	_open_modal_common(final_score, gem_best, best_combo, is_new_best)


func _open_modal_common(final_score: int, high_score: int, best_combo: int, is_new_best: bool) -> void:
	_final_score = maxi(0, final_score)
	_high_score = maxi(_final_score, maxi(0, high_score))
	_best_combo = maxi(0, best_combo)
	_is_new_best = is_new_best

	_is_showing = true
	_backdrop_alpha = 0.0
	_card_alpha = 0.0
	_card_scale = 0.78
	_card_scale_vel = 4.6
	_card_y_offset = 28.0
	_score_roll_t = 0.0
	_displayed_final_score = 0.0
	_score_landed = false
	_score_pop_scale = 1.0
	_score_pop_vel = 0.0
	_reward_visible = false
	_reward_can_double = false
	_reward_doubled = false
	_is_processing_ad = false
	if _double_btn != null:
		_double_btn.visible = false

	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_center_card()
	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


func _configure_action_buttons() -> void:
	if _play_btn == null or _share_btn == null:
		return
	_share_btn.set_copied(false)
	if not _is_daily_mode and not _is_gem_hunt_mode:
		_play_btn.visible = true
		_play_btn.position = PLAY_BTN_RECT.position
		_play_btn.size = PLAY_BTN_RECT.size
		_play_btn.button_label = "SPRINT AGAIN" if _is_sprint_mode else "PLAY AGAIN"
		_play_btn.queue_redraw()
		_share_btn.visible = false
	elif _is_gem_hunt_mode:
		_play_btn.visible = true
		_play_btn.position = DAILY_RETRY_BTN_RECT.position
		_play_btn.size = DAILY_RETRY_BTN_RECT.size
		_play_btn.button_label = "RETRY STG %d" % _gem_stage_reached
		_play_btn.queue_redraw()
		_share_btn.visible = true
		_share_btn.position = DAILY_SHARE_COMPACT_RECT.position
		_share_btn.size = DAILY_SHARE_COMPACT_RECT.size
		_share_btn.is_wide = false
		_share_btn.custom_label = "STAGES"
		_share_btn.queue_redraw()
	elif _daily_attempts_left > 0:
		_play_btn.visible = true
		_play_btn.position = DAILY_RETRY_BTN_RECT.position
		_play_btn.size = DAILY_RETRY_BTN_RECT.size
		_play_btn.button_label = "RETRY (%d)" % _daily_attempts_left
		_play_btn.queue_redraw()
		_share_btn.visible = true
		_share_btn.position = DAILY_SHARE_COMPACT_RECT.position
		_share_btn.size = DAILY_SHARE_COMPACT_RECT.size
		_share_btn.is_wide = false
		_share_btn.custom_label = ""
		_share_btn.queue_redraw()
	else:
		_play_btn.visible = false
		_share_btn.visible = true
		_share_btn.position = DAILY_SHARE_WIDE_RECT.position
		_share_btn.size = DAILY_SHARE_WIDE_RECT.size
		_share_btn.is_wide = true
		_share_btn.custom_label = ""
		_share_btn.queue_redraw()


func trigger_copied_feedback() -> void:
	_copied_timer = 2.0
	if _share_btn != null:
		_share_btn.set_copied(true)


func set_reward_info(base_coins: int, wallet_coins: int, can_double: bool, already_doubled: bool = false) -> void:
	_reward_coins_run = maxi(0, base_coins * (2 if already_doubled else 1))
	_reward_coins_wallet = maxi(0, wallet_coins)
	_reward_can_double = can_double and not already_doubled
	_reward_doubled = already_doubled
	_reward_visible = (not _daily_summary_only) and _reward_coins_run > 0
	_reward_pop_scale = 1.0
	_reward_pop_vel = 0.0
	if _double_btn != null:
		_double_btn.visible = _reward_visible
		_double_btn.set_state(_reward_can_double, _reward_doubled, _is_processing_ad)
	if _card != null:
		_card.queue_redraw()


func apply_double_reward_visual(total_run_coins: int, new_wallet: int) -> void:
	_reward_coins_run = maxi(0, total_run_coins)
	_reward_coins_wallet = maxi(0, new_wallet)
	_reward_can_double = false
	_reward_doubled = true
	_reward_visible = true
	_reward_pop_scale = 1.24
	_reward_pop_vel = 2.6
	if _double_btn != null:
		_double_btn.visible = true
		_double_btn.set_state(false, true, _is_processing_ad)
	if _card != null:
		_card.queue_redraw()


func set_processing_ad(locked: bool) -> void:
	_is_processing_ad = locked
	if _double_btn != null:
		_double_btn.set_state(_reward_can_double, _reward_doubled, _is_processing_ad)
	if _card != null:
		_card.queue_redraw()


func hide_overlay() -> void:
	_is_showing = false
	_is_processing_ad = false
	_backdrop_alpha = 0.0
	_card_alpha = 0.0
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


# ==============================================================================
# INTERNAL SETUP & LAYOUT
# ==============================================================================

func _load_fonts() -> void:
	if ResourceLoader.exists(FONT_EXTRABOLD_PATH):
		_font_extrabold = load(FONT_EXTRABOLD_PATH) as Font
	if ResourceLoader.exists(FONT_BOLD_PATH):
		_font_bold = load(FONT_BOLD_PATH) as Font
	if ResourceLoader.exists(FONT_SEMIBOLD_PATH):
		_font_semibold = load(FONT_SEMIBOLD_PATH) as Font

	if _font_extrabold == null:
		_font_extrabold = _font_bold if _font_bold != null else ThemeDB.fallback_font
	if _font_bold == null:
		_font_bold = _font_extrabold
	if _font_semibold == null:
		_font_semibold = _font_bold


func _init_sparkles() -> void:
	_sparkles.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42077
	for i in range(22):
		_sparkles.append({
			"pos": Vector2(rng.randf_range(20.0, OVERLAY_SIZE.x - 20.0), rng.randf_range(20.0, OVERLAY_SIZE.y - 20.0)),
			"radius": rng.randf_range(2.2, 5.4),
			"speed": rng.randf_range(16.0, 44.0),
			"drift": rng.randf_range(8.0, 22.0),
			"phase": rng.randf_range(0.0, TAU),
			"is_gold": (i % 2) == 0,
		})


func _build_card() -> void:
	_card = _GameOverCard.new()
	_card.name = "GameOverCard"
	_card.overlay = self
	_card.size = CARD_SIZE
	_card.pivot_offset = CARD_SIZE * 0.5
	_card.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_card)

	_home_btn = _HomeModalButton.new()
	_home_btn.name = "HomeModalButton"
	_home_btn.position = HOME_BTN_RECT.position
	_home_btn.size = HOME_BTN_RECT.size
	_home_btn.tooltip_text = "Home"
	_home_btn.pressed_clean.connect(_on_home_clicked)
	_card.add_child(_home_btn)

	_play_btn = _PlayAgainButton.new()
	_play_btn.name = "PlayAgainButton"
	_play_btn.font_extrabold = _font_extrabold
	_play_btn.position = PLAY_BTN_RECT.position
	_play_btn.size = PLAY_BTN_RECT.size
	_play_btn.pressed_clean.connect(_on_play_again_clicked)
	_card.add_child(_play_btn)

	_share_btn = _ShareResultButton.new()
	_share_btn.name = "ShareResultButton"
	_share_btn.font_extrabold = _font_extrabold
	_share_btn.position = DAILY_SHARE_WIDE_RECT.position
	_share_btn.size = DAILY_SHARE_WIDE_RECT.size
	_share_btn.visible = false
	_share_btn.pressed_clean.connect(_on_share_clicked)
	_card.add_child(_share_btn)

	_double_btn = _DoubleRewardButton.new()
	_double_btn.name = "DoubleRewardButton"
	_double_btn.font_extrabold = _font_extrabold
	_double_btn.position = DOUBLE_BTN_RECT.position
	_double_btn.size = DOUBLE_BTN_RECT.size
	_double_btn.visible = false
	_double_btn.pressed_clean.connect(_on_double_reward_clicked)
	_card.add_child(_double_btn)


func _center_card() -> void:
	if _card == null:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	var base_pos := (view_size - CARD_SIZE) * 0.5
	_card.position = base_pos + Vector2(0.0, _card_y_offset)
	_card.pivot_offset = CARD_SIZE * 0.5


func _apply_card_transform() -> void:
	if _card == null:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	var base_pos := (view_size - CARD_SIZE) * 0.5
	_card.position = base_pos + Vector2(0.0, _card_y_offset)
	_card.scale = Vector2(_card_scale, _card_scale)
	_card.modulate = Color(1.0, 1.0, 1.0, _card_alpha)


func _on_play_again_clicked() -> void:
	if _is_processing_ad:
		return
	play_again_pressed.emit()


func _on_home_clicked() -> void:
	if _is_processing_ad:
		return
	home_pressed.emit()


func _on_share_clicked() -> void:
	if _is_processing_ad:
		return
	if _is_gem_hunt_mode:
		stages_pressed.emit()
		return
	trigger_copied_feedback()
	share_pressed.emit()


func _on_double_reward_clicked() -> void:
	if _is_processing_ad or not _reward_can_double or _reward_doubled:
		return
	double_reward_pressed.emit()


# ==============================================================================
# BACKDROP DRAW (FULL SCREEN)
# ==============================================================================

func _draw() -> void:
	if not visible:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	var bg_alpha := 0.82 * _backdrop_alpha

	# Semi-transparent dark blurred-feel midnight-indigo backdrop (#070B1E at 82% alpha).
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.027, 0.043, 0.118, bg_alpha), true)

	# Velvety smooth radial spotlight behind the modal card (ZERO hard circular disc edges!).
	var center := view_size * 0.5
	var pulse := 0.5 + 0.5 * sin(_time_sec * 3.0)
	var spot_col := Color(1.0, 0.72, 0.18, (0.34 + pulse * 0.10) * _backdrop_alpha) if _is_new_best else Color(0.20, 0.54, 1.0, (0.28 + pulse * 0.08) * _backdrop_alpha)
	_draw_soft_glow(self, center, Vector2(360.0, 390.0), spot_col)
	_draw_soft_glow(self, center + Vector2(0.0, -40.0), Vector2(210.0, 210.0), Color(spot_col.r, spot_col.g, spot_col.b, spot_col.a * 0.55))

	# Subtle floating celebration diamond sparkles (gold & warm amber on new best, soft cyan otherwise).
	for mote in _sparkles:
		var pos := mote["pos"] as Vector2
		var rad := float(mote["radius"])
		var phase := float(mote["phase"])
		var twinkle := 0.35 + 0.65 * (0.5 + 0.5 * sin(_time_sec * 4.2 + phase))
		var m_col: Color
		if _is_new_best:
			m_col = Color("#FFE366") if bool(mote["is_gold"]) else Color("#FF8A2B")
			m_col.a = 0.52 * twinkle * _backdrop_alpha
		else:
			m_col = Color("#5CD6FF") if bool(mote["is_gold"]) else Color("#8A7BFF")
			m_col.a = 0.24 * twinkle * _backdrop_alpha
		_draw_diamond(self, pos, rad, m_col)


# ==============================================================================
# CARD DRAW (410x460 CENTERED BEVELED ARCADE PANEL)
# ==============================================================================

func _draw_card(ci: CanvasItem) -> void:
	var card_rect := Rect2(Vector2.ZERO, CARD_SIZE)
	var radius := 24.0
	var pulse := 0.5 + 0.5 * sin(_time_sec * 4.5)

	var cid := ci.get_canvas_item()

	# 1. Soft Gaussian outer card bloom & deep drop shadow (native StyleBoxFlat).
	var outer_glow := Color("#FFB824", 0.32 + pulse * 0.12) if _is_new_best else Color("#2878FF", 0.26 + pulse * 0.08)
	_draw_soft_glow(ci, card_rect.get_center(), Vector2(CARD_SIZE.x * 0.66, CARD_SIZE.y * 0.64), outer_glow)
	_sb_card_shadow.draw(cid, Rect2(Vector2(0.0, 12.0), CARD_SIZE))

	# 2. Tactile dark-navy 3D card thickness lip.
	_sb_card_lip.draw(cid, Rect2(Vector2(0.0, 6.0), CARD_SIZE))

	# 3. Main dark-indigo beveled card body.
	_sb_card_body.draw(cid, card_rect)

	# Subtle recessed inner bevel frame.
	_sb_card_inner.draw(cid, card_rect.grow(-4.0))

	# 4. Golden / Cyan accent header stripe at the top of the card.
	var header_h := 82.0
	var header_rect := Rect2(Vector2(0.0, 0.0), Vector2(CARD_SIZE.x, header_h))
	if _is_new_best:
		_draw_top_rounded_rect_vgrad(ci, header_rect, Color("#FFBF1A"), Color("#E66300"), radius)
		# Diagonal celebratory gloss stripe on gold banner.
		ci.draw_colored_polygon(
			PackedVector2Array([
				Vector2(48.0, 0.0),
				Vector2(104.0, 0.0),
				Vector2(66.0, header_h),
				Vector2(10.0, header_h),
			]),
			Color(1.0, 0.98, 0.80, 0.20)
		)
		ci.draw_colored_polygon(
			PackedVector2Array([
				Vector2(314.0, 0.0),
				Vector2(350.0, 0.0),
				Vector2(312.0, header_h),
				Vector2(276.0, header_h),
			]),
			Color(1.0, 0.98, 0.80, 0.14)
		)
		# Gleaming golden accent trim line beneath header.
		ci.draw_line(Vector2(2.0, header_h), Vector2(CARD_SIZE.x - 2.0, header_h), Color("#FFF08A"), 2.6, false)
	else:
		_draw_top_rounded_rect_vgrad(ci, header_rect, Color("#24367A"), Color("#141F4F"), radius)
		# Crisp electric cyan-to-gold energy accent stripe along the header bottom seam.
		ci.draw_polygon(
			PackedVector2Array([
				Vector2(2.0, header_h - 3.0),
				Vector2(CARD_SIZE.x * 0.5, header_h - 3.0),
				Vector2(CARD_SIZE.x * 0.5, header_h + 0.5),
				Vector2(2.0, header_h + 0.5),
			]),
			PackedColorArray([Color("#18D5FF"), Color("#FFD43B"), Color("#FFD43B"), Color("#18D5FF")])
		)
		ci.draw_polygon(
			PackedVector2Array([
				Vector2(CARD_SIZE.x * 0.5, header_h - 3.0),
				Vector2(CARD_SIZE.x - 2.0, header_h - 3.0),
				Vector2(CARD_SIZE.x - 2.0, header_h + 0.5),
				Vector2(CARD_SIZE.x * 0.5, header_h + 0.5),
			]),
			PackedColorArray([Color("#FFD43B"), Color("#18D5FF"), Color("#18D5FF"), Color("#FFD43B")])
		)

	# Card outer border rim (gleaming gold if new best, electric cyan-indigo otherwise).
	_sb_card_rim.border_color = Color("#FFE066") if _is_new_best else Color("#4C7CFF")
	_sb_card_rim.draw(cid, card_rect)

	# 5. Header Title (+ big gleaming Golden Crown crest with velvety radial glow when NEW HIGH SCORE!).
	if _is_new_best:
		var crest_center := Vector2(CARD_SIZE.x * 0.5, -6.0)
		var g_r := 54.0 + pulse * 8.0
		_draw_soft_glow(ci, crest_center, Vector2(g_r, g_r), Color(1.0, 0.86, 0.26, 0.58 + pulse * 0.18))
		var c_pulse := 1.0 + 0.05 * pulse
		ci.draw_set_transform(crest_center, 0.0, Vector2(c_pulse, c_pulse))
		_draw_golden_crown(ci, Rect2(-28.0, -22.0, 56.0, 44.0), 1.0, _time_sec)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var best_hdr := "NEW DAILY BEST!" if _is_daily_mode else ("NEW SPRINT BEST!" if _is_sprint_mode else ("NEW GEM BEST!" if _is_gem_hunt_mode else "NEW HIGH SCORE!"))
		_draw_centered_outlined_text(ci, _font_extrabold, Vector2(CARD_SIZE.x * 0.5, 48.0), best_hdr, 29 if _is_sprint_mode else 30, Color("#FFFBE0"), Color("#4A1B00"), 6, 2.5)
	else:
		var std_hdr := "GAME OVER"
		if _is_daily_mode:
			std_hdr = "TODAY'S DAILY" if _daily_summary_only else "DAILY COMPLETE!"
		elif _is_sprint_mode:
			std_hdr = "SPRINT COMPLETE!" if _sprint_completed else "OUT OF SPACE!"
		elif _is_gem_hunt_mode:
			std_hdr = "STAGE %d ENDED" % _gem_stage_reached
		_draw_centered_outlined_text(ci, _font_extrabold, Vector2(CARD_SIZE.x * 0.5, 41.0), std_hdr, 32 if (_is_daily_mode or _is_sprint_mode or _is_gem_hunt_mode) else 36, Color("#FFFFFF"), Color("#090F2B"), 7, 2.8)

	# 6. Hero Animated Final Score Display (+ Mode sub-caption).
	var sub_caption := "FINAL SCORE"
	var sub_color := Color("#99B5F5")
	if _is_daily_mode:
		var streak_part := ("  •  STREAK %dd" % _daily_streak) if _daily_streak > 0 else ""
		sub_caption = "%s  •  TRY %d/%d%s" % [_daily_date_label, _daily_attempt_num, DailyChallenge.MAX_DAILY_ATTEMPTS, streak_part]
		sub_color = Color("#FFE475")
	elif _is_sprint_mode:
		sub_caption = "20-TURN SPRINT  •  %d/%d MOVES" % [_sprint_moves_used, _sprint_moves_limit]
		sub_color = Color("#DDA8FF")
	elif _is_gem_hunt_mode:
		sub_caption = "GEM HUNT  •  STAGE %d  (BEST: STG %d)" % [_gem_stage_reached, _gem_best_stage]
		sub_color = Color("#7CF5FF")
	_draw_centered_outlined_text(
		ci,
		_font_bold,
		Vector2(CARD_SIZE.x * 0.5, 114.0),
		sub_caption,
		13 if (_is_daily_mode or _is_sprint_mode or _is_gem_hunt_mode) else 14,
		sub_color,
		Color("#070B1E"),
		3,
		1.2
	)

	var score_str := _format_comma_int(int(round(_displayed_final_score)))
	var score_font_size := _fit_text_size(_font_extrabold, score_str, 62, 36, CARD_SIZE.x - 44.0)
	var score_center := Vector2(CARD_SIZE.x * 0.5, 168.0)

	# Velvety smooth Gaussian glow behind Final Score (ZERO hard oval disc edge!).
	var score_glow := Color(1.0, 0.84, 0.24, 0.42) if _is_new_best else Color(0.32, 0.68, 1.0, 0.34)
	_draw_soft_glow(ci, score_center, Vector2(150.0, 56.0), score_glow)

	var score_fill := Color("#FFF3A6") if _is_new_best else Color("#FFFFFF")
	var score_outline := Color("#3D1E00") if _is_new_best else Color("#090F29")
	ci.draw_set_transform(score_center, 0.0, Vector2(_score_pop_scale, _score_pop_scale))
	_draw_centered_outlined_text(ci, _font_extrabold, Vector2.ZERO, score_str, score_font_size, score_fill, score_outline, 9, 4.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Crisp luminous divider hairline above stat pills.
	ci.draw_line(Vector2(36.0, 222.0), Vector2(CARD_SIZE.x - 36.0, 222.0), Color(0.38, 0.54, 0.94, 0.28), 1.4, true)

	# 7. Side-by-Side Stat Pills: BEST SCORE (gold crown) & MAX COMBO (flame accent).
	_draw_stat_pill_best(ci, Rect2(24.0, 236.0, 173.0, 88.0))
	_draw_stat_pill_combo(ci, Rect2(213.0, 236.0, 173.0, 88.0))

	# 8. End-of-Run Coin Reward Strip (+ ×2 COINS ad-ready button).
	if _reward_visible:
		_draw_reward_strip(ci, REWARD_STRIP_RECT)


func _draw_reward_strip(ci: CanvasItem, rect: Rect2) -> void:
	var cid := ci.get_canvas_item()
	_sb_stat_shadow.draw(cid, Rect2(rect.position + Vector2(0.0, 3.0), rect.size))
	_sb_stat_body.bg_color = Color("#0D1B38") if _reward_doubled else Color("#151B3E")
	_sb_stat_body.border_color = Color("#44F084", 0.78) if _reward_doubled else Color("#FFD43B", 0.62)
	_sb_stat_body.draw(cid, rect)

	_sb_stat_gloss.bg_color = Color(0.38, 1.0, 0.62, 0.08) if _reward_doubled else Color(1.0, 0.88, 0.42, 0.08)
	_sb_stat_gloss.draw(cid, Rect2(rect.position + Vector2(10.0, 4.0), Vector2(rect.size.x - 20.0, 12.0)))

	# Crisp golden vector coin emblem on the left.
	var coin_c := Vector2(rect.position.x + 30.0, rect.get_center().y)
	ci.draw_circle(coin_c + Vector2(0.0, 2.0), 16.0, Color(0.02, 0.03, 0.08, 0.55))
	ci.draw_circle(coin_c, 16.0, Color("#B86B00"))
	ci.draw_circle(coin_c + Vector2(0.0, -1.0), 14.0, Color("#FFD43B"))
	ci.draw_circle(coin_c + Vector2(0.0, -1.0), 10.5, Color("#F59F00"))
	ci.draw_circle(coin_c + Vector2(-4.0, -5.0), 3.6, Color(1.0, 0.99, 0.84, 0.72))
	_draw_centered_outlined_text(ci, _font_extrabold, coin_c + Vector2(0.0, -1.0), "K", 13, Color("#FFF9CC"), Color("#703A00"), 3, 0.8)

	# Run coin reward + wallet balance.
	var coin_txt := "+%s COINS" % _format_comma_int(_reward_coins_run)
	if _reward_doubled:
		coin_txt = "+%s (×2!)" % _format_comma_int(_reward_coins_run)
	var text_x := rect.position.x + 56.0
	var top_y := rect.position.y + 23.0
	ci.draw_set_transform(Vector2(text_x, top_y), 0.0, Vector2(_reward_pop_scale, _reward_pop_scale))
	_draw_left_outlined_text(
		ci,
		_font_extrabold,
		Vector2.ZERO,
		coin_txt,
		17,
		Color("#86FFAA") if _reward_doubled else Color("#FFE66D"),
		Color("#05381A") if _reward_doubled else Color("#361C00"),
		4,
		1.2
	)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var bank_txt := "BANK: %s" % _format_comma_int(_reward_coins_wallet)
	_draw_left_outlined_text(ci, _font_bold, Vector2(text_x, rect.position.y + 47.0), bank_txt, 11, Color("#A4C6F7"), Color("#060B1E"), 2, 0.8)


func _draw_stat_pill_best(ci: CanvasItem, rect: Rect2) -> void:
	var cid := ci.get_canvas_item()
	_sb_stat_shadow.draw(cid, Rect2(rect.position + Vector2(0.0, 3.0), rect.size))
	_sb_stat_body.bg_color = Color("#0D1536")
	_sb_stat_body.border_color = Color("#FFD43B", 0.68)
	_sb_stat_body.draw(cid, rect)

	# Subtle top golden sheen strip.
	_sb_stat_gloss.bg_color = Color(1.0, 0.88, 0.42, 0.09)
	_sb_stat_gloss.draw(cid, Rect2(rect.position + Vector2(10.0, 4.0), Vector2(rect.size.x - 20.0, 14.0)))

	# Label row: mathematically centered [Golden Crown + BEST SCORE / DAILY BEST] above the centered value!
	var label_y := rect.position.y + 24.0
	var crown_w := 20.0
	var gap := 6.0
	var best_title := "DAILY BEST" if _is_daily_mode else ("SPRINT BEST" if _is_sprint_mode else ("GEM BEST" if _is_gem_hunt_mode else "BEST SCORE"))
	var txt_w := _font_bold.get_string_size(best_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var start_x := rect.get_center().x - (crown_w + gap + txt_w) * 0.5
	var crown_rect := Rect2(start_x, label_y - 9.0, crown_w, 16.0)
	_draw_golden_crown(ci, crown_rect, 0.45, _time_sec)
	_draw_left_outlined_text(ci, _font_bold, Vector2(crown_rect.end.x + gap, label_y), best_title, 13, Color("#FFD94D"), Color("#291600"), 3, 1.0)

	# Value row (synchronized with rolling Final Score on New High Score so Final NEVER reads < Best!).
	var displayed_best := int(round(_displayed_final_score)) if (_is_new_best and _high_score == _final_score) else _high_score
	var best_str := _format_comma_int(displayed_best)
	var val_size := _fit_text_size(_font_extrabold, best_str, 28, 18, rect.size.x - 20.0)
	_draw_centered_outlined_text(ci, _font_extrabold, Vector2(rect.get_center().x, rect.position.y + 62.0), best_str, val_size, Color("#FFE778"), Color("#2E1800"), 5, 2.0)


func _draw_stat_pill_combo(ci: CanvasItem, rect: Rect2) -> void:
	var cid := ci.get_canvas_item()
	_sb_stat_shadow.draw(cid, Rect2(rect.position + Vector2(0.0, 3.0), rect.size))
	_sb_stat_body.bg_color = Color("#111536")
	_sb_stat_body.border_color = Color("#FF6B35", 0.72)
	_sb_stat_body.draw(cid, rect)

	# Subtle top flame sheen strip.
	_sb_stat_gloss.bg_color = Color(1.0, 0.52, 0.24, 0.10)
	_sb_stat_gloss.draw(cid, Rect2(rect.position + Vector2(10.0, 4.0), Vector2(rect.size.x - 20.0, 14.0)))

	# Label row: mathematically centered [Crisp Outlined Flame + MAX COMBO] above the centered value!
	var label_y := rect.position.y + 24.0
	var flame_w := 17.0
	var gap := 6.0
	var txt_w := _font_bold.get_string_size("MAX COMBO", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var start_x := rect.get_center().x - (flame_w + gap + txt_w) * 0.5
	var flame_center := Vector2(start_x + flame_w * 0.5, label_y - 1.0)
	_draw_flame_icon(ci, flame_center, 9.5, _time_sec)
	_draw_left_outlined_text(ci, _font_bold, Vector2(start_x + flame_w + gap, label_y), "MAX COMBO", 13, Color("#FFA46B"), Color("#330D02"), 3, 1.0)

	# Value row.
	var combo_str := "×%d" % _best_combo
	var val_size := _fit_text_size(_font_extrabold, combo_str, 28, 20, rect.size.x - 20.0)
	_draw_centered_outlined_text(ci, _font_extrabold, Vector2(rect.get_center().x, rect.position.y + 62.0), combo_str, val_size, Color("#FFFFFF"), Color("#3B0E04"), 5, 2.0)


# ==============================================================================
# VECTOR ART & TYPOGRAPHY HELPERS
# ==============================================================================

static func _draw_golden_crown(ci: CanvasItem, rect: Rect2, glow: float, time_sec: float) -> void:
	var w := rect.size.x
	var h := rect.size.y
	var x0 := rect.position.x
	var y0 := rect.position.y

	var p := func(nx: float, ny: float) -> Vector2:
		return Vector2(x0 + nx * w, y0 + ny * h)

	var body_pts := PackedVector2Array([
		p.call(0.14, 0.90),
		p.call(0.06, 0.36),
		p.call(0.32, 0.58),
		p.call(0.50, 0.16),
		p.call(0.68, 0.58),
		p.call(0.94, 0.36),
		p.call(0.86, 0.90),
	])

	var shadow_pts := PackedVector2Array()
	for pt in body_pts:
		shadow_pts.append(pt + Vector2(0.0, 2.0))
	ci.draw_colored_polygon(shadow_pts, Color(0.04, 0.02, 0.0, 0.45))

	var loop := body_pts.duplicate()
	loop.append(body_pts[0])
	ci.draw_polyline(loop, Color("#4D2600"), maxf(2.4, w * 0.095), true)

	var top_gold := Color("#FFF078")
	var mid_gold := Color("#FFC414")
	var bot_gold := Color("#E68A00")
	ci.draw_polygon(body_pts, PackedColorArray([bot_gold, top_gold, mid_gold, top_gold, mid_gold, top_gold, bot_gold]))

	# Glossy left highlight facet.
	ci.draw_colored_polygon(
		PackedVector2Array([
			p.call(0.16, 0.80),
			p.call(0.10, 0.40),
			p.call(0.32, 0.60),
			p.call(0.50, 0.22),
			p.call(0.50, 0.80),
		]),
		Color(1.0, 0.98, 0.78, 0.28)
	)

	# Crown base band & jewels.
	var band := Rect2(p.call(0.13, 0.74), Vector2(w * 0.74, h * 0.19))
	_draw_rounded_rect_static(ci, band, Color("#D67600"), maxf(1.5, h * 0.08))
	var gem_r := maxf(1.4, w * 0.062)
	ci.draw_circle(p.call(0.50, 0.835), gem_r, Color("#FF405C"))
	ci.draw_circle(p.call(0.28, 0.835), gem_r * 0.76, Color("#30E8FF"))
	ci.draw_circle(p.call(0.72, 0.835), gem_r * 0.76, Color("#30E8FF"))

	# Tip spheres.
	var tips: Array[Vector2] = [p.call(0.06, 0.34), p.call(0.50, 0.13), p.call(0.94, 0.34)]
	var rads: Array[float] = [w * 0.075, w * 0.092, w * 0.075]
	for i in range(tips.size()):
		var tc := tips[i]
		var tr := maxf(1.6, rads[i])
		ci.draw_circle(tc, tr + 1.0, Color("#4D2600"))
		ci.draw_circle(tc, tr, Color("#FFD942"))
		ci.draw_circle(tc + Vector2(-tr * 0.26, -tr * 0.26), tr * 0.44, Color("#FFFCE3"))

	if glow > 0.5:
		var sp: Vector2 = p.call(0.50, 0.12)
		var glint := 0.75 + 0.25 * sin(time_sec * 10.0)
		var rl := w * 0.15 * glint
		var rs := w * 0.036 * glint
		ci.draw_colored_polygon(
			PackedVector2Array([
				sp + Vector2(0.0, -rl),
				sp + Vector2(rs, -rs),
				sp + Vector2(rl, 0.0),
				sp + Vector2(rs, rs),
				sp + Vector2(0.0, rl),
				sp + Vector2(-rs, rs),
				sp + Vector2(-rl, 0.0),
				sp + Vector2(-rs, -rs),
			]),
			Color(1.0, 1.0, 0.92, 0.92)
		)


static func _draw_flame_icon(ci: CanvasItem, center: Vector2, radius: float, time_sec: float) -> void:
	var sway := sin(time_sec * 7.5) * radius * 0.12
	# Crisp dark-outlined blazing outer orange-red flame tongue (matching the sharp vector crown style!).
	var outer := PackedVector2Array([
		center + Vector2(0.0, radius * 0.95),
		center + Vector2(-radius * 0.74, radius * 0.48),
		center + Vector2(-radius * 0.68, -radius * 0.14),
		center + Vector2(-radius * 0.24, -radius * 0.42),
		center + Vector2(sway, -radius * 1.12),
		center + Vector2(radius * 0.48, -radius * 0.34),
		center + Vector2(radius * 0.76, radius * 0.24),
		center + Vector2(radius * 0.56, radius * 0.74),
	])
	var shadow_loop := PackedVector2Array()
	for pt in outer:
		shadow_loop.append(pt + Vector2(0.0, 1.8))
	ci.draw_colored_polygon(shadow_loop, Color(0.06, 0.01, 0.0, 0.55))
	var outline_loop := outer.duplicate()
	outline_loop.append(outer[0])
	ci.draw_polyline(outline_loop, Color("#3B0A00"), 4.2, true)
	ci.draw_colored_polygon(outer, Color("#FF4619"))

	# Mid fiery gold tongue.
	var mid := PackedVector2Array([
		center + Vector2(0.0, radius * 0.85),
		center + Vector2(-radius * 0.48, radius * 0.42),
		center + Vector2(-radius * 0.36, -radius * 0.12),
		center + Vector2(sway * 0.6, -radius * 0.68),
		center + Vector2(radius * 0.44, -radius * 0.05),
		center + Vector2(radius * 0.46, radius * 0.52),
	])
	ci.draw_colored_polygon(mid, Color("#FFB81C"))

	# Incandescent white-gold heart.
	var core := PackedVector2Array([
		center + Vector2(0.0, radius * 0.72),
		center + Vector2(-radius * 0.26, radius * 0.34),
		center + Vector2(sway * 0.3, -radius * 0.26),
		center + Vector2(radius * 0.26, radius * 0.34),
	])
	ci.draw_colored_polygon(core, Color("#FFF9C4"))


static func _step_spring(pos: float, vel: float, target: float, stiffness: float, damping: float, dt: float) -> Vector2:
	var force := (target - pos) * stiffness - vel * damping
	vel += force * dt
	pos += vel * dt
	return Vector2(pos, vel)


static func _format_comma_int(value: int) -> String:
	var neg := value < 0
	var s := str(absi(value))
	var length := s.length()
	if length <= 3:
		return ("-" + s) if neg else s
	var out := ""
	for i in range(length):
		if i > 0 and (length - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" + out) if neg else out


static func _fit_text_size(font: Font, text: String, max_size: int, min_size: int, max_width: float) -> int:
	if font == null or text.is_empty():
		return max_size
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, max_size).x
	if w <= max_width or w <= 1.0:
		return max_size
	return maxi(min_size, int(floor(float(max_size) * (max_width / w))))


static func _build_rounded_rect_points(rect: Rect2, radius: float, corner_steps: int = 6) -> PackedVector2Array:
	if rect.size.x <= 0.5 or rect.size.y <= 0.5:
		return PackedVector2Array()
	var r := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.49)
	if r <= 0.5:
		return PackedVector2Array([
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		])
	var pts := PackedVector2Array()
	var centers: Array[Vector2] = [
		Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.position.y + r),
	]
	var start_angles: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	for c_idx in range(4):
		var c := centers[c_idx]
		var a0 := start_angles[c_idx]
		for s in range(corner_steps + 1):
			var a := a0 + (PI * 0.5) * (float(s) / float(corner_steps))
			var pt := c + Vector2(cos(a), sin(a)) * r
			if pts.is_empty() or pts[pts.size() - 1].distance_squared_to(pt) > 0.01:
				pts.append(pt)
	if pts.size() >= 2 and pts[0].distance_squared_to(pts[pts.size() - 1]) <= 0.01:
		pts.remove_at(pts.size() - 1)
	return pts


static func _build_top_rounded_rect_points(rect: Rect2, radius: float, corner_steps: int = 6) -> PackedVector2Array:
	if rect.size.x <= 0.5 or rect.size.y <= 0.5:
		return PackedVector2Array()
	var r := clampf(radius, 0.0, minf(rect.size.x * 0.49, rect.size.y * 0.98))
	var pts := PackedVector2Array()
	var c_tr := Vector2(rect.end.x - r, rect.position.y + r)
	for s in range(corner_steps + 1):
		var a := -PI * 0.5 + (PI * 0.5) * (float(s) / float(corner_steps))
		var pt := c_tr + Vector2(cos(a), sin(a)) * r
		if pts.is_empty() or pts[pts.size() - 1].distance_squared_to(pt) > 0.01:
			pts.append(pt)
	for corner_pt: Vector2 in [rect.end, Vector2(rect.position.x, rect.end.y)]:
		if pts.is_empty() or pts[pts.size() - 1].distance_squared_to(corner_pt) > 0.01:
			pts.append(corner_pt)
	var c_tl := Vector2(rect.position.x + r, rect.position.y + r)
	for s in range(corner_steps + 1):
		var a := PI + (PI * 0.5) * (float(s) / float(corner_steps))
		var pt := c_tl + Vector2(cos(a), sin(a)) * r
		if pts.is_empty() or pts[pts.size() - 1].distance_squared_to(pt) > 0.01:
			pts.append(pt)
	if pts.size() >= 2 and pts[0].distance_squared_to(pts[pts.size() - 1]) <= 0.01:
		pts.remove_at(pts.size() - 1)
	return pts


static func _draw_rounded_rect_static(ci: CanvasItem, rect: Rect2, col: Color, radius: float) -> void:
	var pts := _build_rounded_rect_points(rect, radius)
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, col)


func _draw_rounded_rect(ci: CanvasItem, rect: Rect2, col: Color, radius: float) -> void:
	var pts := _build_rounded_rect_points(rect, radius)
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, col)


func _draw_rounded_rect_vgrad(ci: CanvasItem, rect: Rect2, col_top: Color, col_bot: Color, radius: float) -> void:
	var pts := _build_rounded_rect_points(rect, radius)
	if pts.size() < 3:
		return
	var cols := PackedColorArray()
	var h := maxf(1.0, rect.size.y)
	for pt in pts:
		cols.append(col_top.lerp(col_bot, clampf((pt.y - rect.position.y) / h, 0.0, 1.0)))
	ci.draw_polygon(pts, cols)


func _draw_top_rounded_rect_vgrad(ci: CanvasItem, rect: Rect2, col_top: Color, col_bot: Color, radius: float) -> void:
	var pts := _build_top_rounded_rect_points(rect, radius)
	if pts.size() < 3:
		return
	var cols := PackedColorArray()
	var h := maxf(1.0, rect.size.y)
	for pt in pts:
		cols.append(col_top.lerp(col_bot, clampf((pt.y - rect.position.y) / h, 0.0, 1.0)))
	ci.draw_polygon(pts, cols)


func _draw_rounded_rect_outline(ci: CanvasItem, rect: Rect2, col: Color, radius: float, width: float) -> void:
	var pts := _build_rounded_rect_points(rect, radius)
	if pts.is_empty():
		return
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width, true)


static func _draw_diamond(ci: CanvasItem, center: Vector2, radius: float, col: Color) -> void:
	ci.draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0.0, -radius),
			center + Vector2(radius, 0.0),
			center + Vector2(0.0, radius),
			center + Vector2(-radius, 0.0),
		]),
		col
	)


static func _draw_centered_outlined_text(
	ci: CanvasItem,
	font: Font,
	center: Vector2,
	text: String,
	font_size: int,
	fill_color: Color,
	outline_color: Color,
	outline_size: int,
	shadow_offset_y: float = 2.0
) -> void:
	if font == null or text.is_empty():
		return
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline := Vector2(center.x - text_size.x * 0.5, center.y + (ascent - descent) * 0.45)

	ci.draw_string_outline(
		font,
		baseline + Vector2(0.0, shadow_offset_y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		outline_size + 1,
		Color(0.01, 0.02, 0.08, 0.58)
	)
	ci.draw_string_outline(
		font,
		baseline,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		outline_size,
		outline_color
	)
	ci.draw_string(
		font,
		baseline,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		fill_color
	)


static func _draw_left_outlined_text(
	ci: CanvasItem,
	font: Font,
	left_center: Vector2,
	text: String,
	font_size: int,
	fill_color: Color,
	outline_color: Color,
	outline_size: int,
	shadow_offset_y: float = 1.5
) -> void:
	if font == null or text.is_empty():
		return
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline := Vector2(left_center.x, left_center.y + (ascent - descent) * 0.45)

	ci.draw_string_outline(
		font,
		baseline + Vector2(0.0, shadow_offset_y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		outline_size + 1,
		Color(0.01, 0.02, 0.08, 0.56)
	)
	ci.draw_string_outline(
		font,
		baseline,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		outline_size,
		outline_color
	)
	ci.draw_string(
		font,
		baseline,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		fill_color
	)


# ==============================================================================
# INNER CLASSES: CARD CONTAINER & JUICY 3D EMERALD-GOLD PLAY AGAIN BUTTON
# ==============================================================================

class _GameOverCard extends Control:
	var overlay: GameOverOverlay

	func _draw() -> void:
		if overlay != null:
			overlay._draw_card(self)


class _PlayAgainButton extends Control:
	signal pressed_clean()

	var font_extrabold: Font
	var button_label: String = "PLAY AGAIN"
	var _hovered: bool = false
	var _pressed: bool = false
	var _btn_scale: float = 1.0
	var _sheen_time: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		set_process(true)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		_sheen_time += dt
		var target := 0.96 if _pressed else (1.03 if _hovered else 1.0)
		_btn_scale = lerpf(_btn_scale, target, clampf(18.0 * dt, 0.0, 1.0))
		queue_redraw()

	func _on_mouse_entered() -> void:
		_hovered = true
		queue_redraw()

	func _on_mouse_exited() -> void:
		_hovered = false
		_pressed = false
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
					var was_pressed := _pressed
					_pressed = false
					queue_redraw()
					if was_pressed and Rect2(Vector2.ZERO, size).has_point(mb.position):
						pressed_clean.emit()
					accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_pressed = true
				queue_redraw()
				accept_event()
			else:
				var was_pressed := _pressed
				_pressed = false
				queue_redraw()
				if was_pressed and Rect2(Vector2.ZERO, size).has_point(st.position):
					pressed_clean.emit()
				accept_event()

	func _draw() -> void:
		var center := size * 0.5
		var local_rect := Rect2(-center, size)
		var radius := 18.0
		var press_drop := 4.5 if _pressed else 0.0
		var lip_h := 2.5 if _pressed else 7.0
		var hover_boost := 0.12 if _hovered else 0.0

		draw_set_transform(center, 0.0, Vector2(_btn_scale, _btn_scale))

		# Warm emerald-gold ambient aura under button.
		var pulse := 0.5 + 0.5 * sin(_sheen_time * 4.5)
		GameOverOverlay._draw_rounded_rect_static(
			self,
			local_rect.grow(4.5),
			Color(0.22, 0.92, 0.42, 0.20 + pulse * 0.10 + hover_boost),
			radius + 4.5
		)

		# Deep shadow underneath.
		GameOverOverlay._draw_rounded_rect_static(
			self,
			Rect2(local_rect.position + Vector2(0.0, 5.0), local_rect.size),
			Color(0.01, 0.05, 0.03, 0.62),
			radius
		)

		# 3D tactile emerald-forest bottom lip.
		var outer := Rect2(local_rect.position + Vector2(0.0, press_drop), Vector2(local_rect.size.x, local_rect.size.y - press_drop))
		GameOverOverlay._draw_rounded_rect_static(self, outer, Color("#086B2B"), radius)

		# Lush emerald-to-gold illuminated top face.
		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		var top_col := Color("#42F56C").lerp(Color("#D4FF66"), 0.20 + hover_boost)
		var bot_col := Color("#12B842").lerp(Color("#2CE058"), hover_boost)
		var face_pts := GameOverOverlay._build_rounded_rect_points(face, radius - 1.0)
		var face_cols := PackedColorArray()
		var fh := maxf(1.0, face.size.y)
		for pt in face_pts:
			face_cols.append(top_col.lerp(bot_col, clampf((pt.y - face.position.y) / fh, 0.0, 1.0)))
		draw_polygon(face_pts, face_cols)

		# Glossy upper highlight band.
		var sheen_bar := Rect2(face.position + Vector2(12.0, 4.0), Vector2(face.size.x - 24.0, face.size.y * 0.36))
		GameOverOverlay._draw_rounded_rect_static(self, sheen_bar, Color(1.0, 1.0, 0.88, 0.28 + hover_boost * 0.4), 10.0)

		# Animated subtle diagonal crystal sheen sweep across button face!
		var sweep_phase := fposmod(_sheen_time * 0.42, 1.0)
		if sweep_phase < 0.48:
			var t := sweep_phase / 0.48
			var sx := lerpf(face.position.x - 36.0, face.end.x + 36.0, t)
			var bx0 := clampf(sx - 18.0, face.position.x + 8.0, face.end.x - 8.0)
			var bx1 := clampf(sx + 18.0, face.position.x + 8.0, face.end.x - 8.0)
			var tx0 := clampf(sx - 2.0, face.position.x + 8.0, face.end.x - 8.0)
			var tx1 := clampf(sx + 34.0, face.position.x + 8.0, face.end.x - 8.0)
			if bx1 > bx0 + 1.0 and tx1 > tx0 + 1.0:
				draw_colored_polygon(
					PackedVector2Array([
						Vector2(tx0, face.position.y + 2.0),
						Vector2(tx1, face.position.y + 2.0),
						Vector2(bx1, face.end.y - 2.0),
						Vector2(bx0, face.end.y - 2.0),
					]),
					Color(1.0, 1.0, 0.88, 0.24)
				)

		# Golden-emerald radiant rim outline.
		var rim_col := Color("#C9FF7A").lerp(Color("#FFE46B"), 0.45 + pulse * 0.25)
		var rim_loop := face_pts.duplicate()
		rim_loop.append(face_pts[0])
		draw_polyline(rim_loop, rim_col, 2.3, true)

		# Crisp dark-stroked replay/play icon + bold dynamic CTA text!
		var fc := face.get_center()
		var used_font := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var is_compact := size.x < 220.0
		var lbl_size := 20 if is_compact else 25
		if not is_compact:
			var is_long := button_label.length() > 10
			var tri_c := fc + Vector2(-94.0 if is_long else -84.0, -0.5)
			var tri := PackedVector2Array([
				tri_c + Vector2(-6.5, -8.5),
				tri_c + Vector2(9.0, 0.0),
				tri_c + Vector2(-6.5, 8.5),
			])
			var tri_shadow := PackedVector2Array([
				tri[0] + Vector2(0.0, 2.2),
				tri[1] + Vector2(0.0, 2.2),
				tri[2] + Vector2(0.0, 2.2),
			])
			draw_colored_polygon(tri_shadow, Color("#053D16", 0.78))
			var tri_loop := tri.duplicate()
			tri_loop.append(tri[0])
			draw_polyline(tri_loop, Color("#053D16"), 4.6, true)
			draw_colored_polygon(tri, Color("#FFFFFF"))
			GameOverOverlay._draw_centered_outlined_text(self, used_font, fc + Vector2(14.0, -1.0), button_label, 23 if is_long else lbl_size, Color("#FFFFFF"), Color("#053D16"), 6, 2.2)
		else:
			GameOverOverlay._draw_centered_outlined_text(self, used_font, fc + Vector2(0.0, -1.0), button_label, lbl_size, Color("#FFFFFF"), Color("#053D16"), 5, 2.0)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _ShareResultButton extends Control:
	signal pressed_clean()

	var font_extrabold: Font
	var is_wide: bool = false
	var custom_label: String = ""
	var _copied: bool = false
	var _hovered: bool = false
	var _pressed: bool = false
	var _btn_scale: float = 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())
		set_process(true)

	func set_copied(val: bool) -> void:
		if _copied != val:
			_copied = val
			queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		var target := 0.94 if _pressed else (1.04 if _hovered else 1.0)
		if absf(_btn_scale - target) > 0.002:
			_btn_scale = lerpf(_btn_scale, target, clampf(18.0 * dt, 0.0, 1.0))
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
		var center := size * 0.5
		var local_rect := Rect2(-center, size)
		var radius := 18.0
		var press_drop := 4.5 if _pressed else 0.0
		var lip_h := 2.5 if _pressed else 7.0

		draw_set_transform(center, 0.0, Vector2(_btn_scale, _btn_scale))
		GameOverOverlay._draw_rounded_rect_static(self, Rect2(local_rect.position + Vector2(0.0, 5.0), local_rect.size), Color(0.01, 0.03, 0.09, 0.62), radius)
		var outer := Rect2(local_rect.position + Vector2(0.0, press_drop), Vector2(local_rect.size.x, local_rect.size.y - press_drop))
		GameOverOverlay._draw_rounded_rect_static(self, outer, Color("#0A5B7A") if not _copied else Color("#086B2B"), radius)

		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		var top_col := Color("#3AF576") if _copied else (Color("#48E5FF") if _hovered else Color("#22CEFF"))
		var bot_col := Color("#16B848") if _copied else (Color("#1B8DF2") if _hovered else Color("#1275DB"))
		var face_pts := GameOverOverlay._build_rounded_rect_points(face, radius - 1.0)
		var face_cols := PackedColorArray()
		var fh := maxf(1.0, face.size.y)
		for pt in face_pts:
			face_cols.append(top_col.lerp(bot_col, clampf((pt.y - face.position.y) / fh, 0.0, 1.0)))
		draw_polygon(face_pts, face_cols)

		var sheen_bar := Rect2(face.position + Vector2(10.0, 4.0), Vector2(face.size.x - 20.0, face.size.y * 0.34))
		GameOverOverlay._draw_rounded_rect_static(self, sheen_bar, Color(1.0, 1.0, 1.0, 0.28), 9.0)
		var rim_loop := face_pts.duplicate()
		rim_loop.append(face_pts[0])
		draw_polyline(rim_loop, Color("#D6FF9C") if _copied else Color("#B8F7FF"), 2.2, true)

		var used_font := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var txt := custom_label if not custom_label.is_empty() else ("COPIED!" if _copied else ("COPY RESULT" if is_wide else "SHARE"))
		var fsize := 22 if is_wide else (15 if txt.length() > 5 else 17)
		GameOverOverlay._draw_centered_outlined_text(self, used_font, face.get_center() + Vector2(0.0, -1.0), txt, fsize, Color("#FFFFFF"), Color("#06264F"), 5, 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _HomeModalButton extends Control:
	signal pressed_clean()

	var _hovered: bool = false
	var _pressed: bool = false
	var _btn_scale: float = 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())
		set_process(true)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		var target := 0.94 if _pressed else (1.05 if _hovered else 1.0)
		if absf(_btn_scale - target) > 0.002:
			_btn_scale = lerpf(_btn_scale, target, clampf(18.0 * dt, 0.0, 1.0))
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
					var was_pressed := _pressed
					_pressed = false
					queue_redraw()
					if was_pressed and Rect2(Vector2.ZERO, size).has_point(mb.position):
						pressed_clean.emit()
					accept_event()
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_pressed = true
				queue_redraw()
				accept_event()
			else:
				var was_pressed := _pressed
				_pressed = false
				queue_redraw()
				if was_pressed and Rect2(Vector2.ZERO, size).has_point(st.position):
					pressed_clean.emit()
				accept_event()

	func _draw() -> void:
		var center := size * 0.5
		var local_rect := Rect2(-center, size)
		var radius := 18.0
		var press_drop := 4.5 if _pressed else 0.0
		var lip_h := 2.5 if _pressed else 7.0

		draw_set_transform(center, 0.0, Vector2(_btn_scale, _btn_scale))

		GameOverOverlay._draw_rounded_rect_static(
			self,
			Rect2(local_rect.position + Vector2(0.0, 5.0), local_rect.size),
			Color(0.01, 0.02, 0.08, 0.62),
			radius
		)
		var outer := Rect2(local_rect.position + Vector2(0.0, press_drop), Vector2(local_rect.size.x, local_rect.size.y - press_drop))
		GameOverOverlay._draw_rounded_rect_static(self, outer, Color("#0A1338"), radius)

		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))
		var top_col := Color("#304CA6") if _hovered else Color("#243B86")
		var bot_col := Color("#192B6B") if _hovered else Color("#142154")
		var face_pts := GameOverOverlay._build_rounded_rect_points(face, radius - 1.0)
		var face_cols := PackedColorArray()
		var fh := maxf(1.0, face.size.y)
		for pt in face_pts:
			face_cols.append(top_col.lerp(bot_col, clampf((pt.y - face.position.y) / fh, 0.0, 1.0)))
		draw_polygon(face_pts, face_cols)

		var sheen_bar := Rect2(face.position + Vector2(8.0, 4.0), Vector2(face.size.x - 16.0, face.size.y * 0.34))
		GameOverOverlay._draw_rounded_rect_static(self, sheen_bar, Color(0.82, 0.92, 1.0, 0.22 if _hovered else 0.14), 9.0)

		var rim_col := Color("#8AB8FF") if _hovered else Color("#4C7CFF")
		var rim_loop := face_pts.duplicate()
		rim_loop.append(face_pts[0])
		draw_polyline(rim_loop, rim_col, 2.2, true)

		# Crisp centered House icon (convex pentagon + roof chevron + recessed door).
		var fc := face.get_center()
		var icon_col := Color("#FFE57A") if _hovered else Color("#FFFFFF")
		var house := PackedVector2Array([
			fc + Vector2(-9.2, -0.6),
			fc + Vector2(0.0, -9.5),
			fc + Vector2(9.2, -0.6),
			fc + Vector2(9.2, 11.2),
			fc + Vector2(-9.2, 11.2),
		])
		draw_colored_polygon(house, icon_col)
		var roof := PackedVector2Array([
			fc + Vector2(-13.2, 0.4),
			fc + Vector2(0.0, -11.8),
			fc + Vector2(13.2, 0.4),
		])
		draw_polyline(roof, icon_col, 3.6, true)
		draw_rect(Rect2(fc.x - 3.2, fc.y + 2.8, 6.4, 8.6), Color("#152459"), true)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class _DoubleRewardButton extends Control:
	signal pressed_clean()

	var font_extrabold: Font
	var _can_claim: bool = true
	var _claimed: bool = false
	var _locked: bool = false
	var _hovered: bool = false
	var _pressed: bool = false
	var _scale_v: float = 1.0
	var _time: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			if _is_interactive():
				_hovered = true
				queue_redraw()
		)
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())
		set_process(true)

	func _is_interactive() -> bool:
		return _can_claim and not _claimed and not _locked

	func set_state(can_claim: bool, claimed: bool, locked: bool) -> void:
		_can_claim = can_claim
		_claimed = claimed
		_locked = locked
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _is_interactive() else Control.CURSOR_ARROW
		if not _is_interactive():
			_hovered = false
			_pressed = false
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var dt := minf(delta, 0.05)
		_time += dt
		var target := 0.94 if _pressed else (1.045 if _hovered else 1.0)
		var dirty := _is_interactive()
		if absf(_scale_v - target) > 0.002:
			_scale_v = lerpf(_scale_v, target, clampf(18.0 * dt, 0.0, 1.0))
			dirty = true
		if dirty:
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if not _is_interactive():
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
		var r := 13.0
		var press_y := 3.0 if _pressed else 0.0
		var lip_h := 2.0 if _pressed else 5.0
		var pulse := 0.5 + 0.5 * sin(_time * 4.8)

		draw_set_transform(c, 0.0, Vector2(_scale_v, _scale_v))
		var outer := Rect2(local_rect.position + Vector2(0.0, press_y), Vector2(local_rect.size.x, local_rect.size.y - press_y))
		var face := Rect2(outer.position, Vector2(outer.size.x, outer.size.y - lip_h))

		var lip_c: Color
		var top_c: Color
		var bot_c: Color
		var rim_c: Color
		var out_c: Color
		if _claimed:
			lip_c = Color("#085C27")
			top_c = Color("#2BD96B")
			bot_c = Color("#149E46")
			rim_c = Color("#A8FFBC")
			out_c = Color("#053817")
		elif _locked or not _can_claim:
			lip_c = Color("#161E3A")
			top_c = Color("#344369")
			bot_c = Color("#24304F")
			rim_c = Color("#6D7FA8")
			out_c = Color("#11172B")
		else:
			lip_c = Color("#8C4000")
			top_c = Color("#FFD43B").lerp(Color("#FFF085"), (0.22 if _hovered else 0.0) + pulse * 0.14)
			bot_c = Color("#F08300").lerp(Color("#FFA51A"), 0.14 if _hovered else 0.0)
			rim_c = Color("#FFF4A3")
			out_c = Color("#4D2000")

		GameOverOverlay._draw_rounded_rect_static(self, outer, lip_c, r)
		var pts := GameOverOverlay._build_rounded_rect_points(face, r - 1.0)
		var cols := PackedColorArray()
		var fh := maxf(1.0, face.size.y)
		for pt in pts:
			cols.append(top_c.lerp(bot_c, clampf((pt.y - face.position.y) / fh, 0.0, 1.0)))
		draw_polygon(pts, cols)
		GameOverOverlay._draw_rounded_rect_static(self, Rect2(face.position + Vector2(8.0, 3.0), Vector2(face.size.x - 16.0, face.size.y * 0.34)), Color(1.0, 1.0, 0.90, 0.28), 7.0)
		var rim := pts.duplicate()
		rim.append(pts[0])
		draw_polyline(rim, rim_c, 2.0, true)

		var eb := font_extrabold if font_extrabold != null else ThemeDB.fallback_font
		var fc := face.get_center()
		if _claimed:
			GameOverOverlay._draw_centered_outlined_text(self, eb, fc + Vector2(0.0, -0.5), "✓ DOUBLED!", 14, Color("#FFFFFF"), out_c, 4, 1.2)
		elif _locked:
			GameOverOverlay._draw_centered_outlined_text(self, eb, fc + Vector2(0.0, -0.5), "WAIT...", 14, Color("#D6E0FA"), out_c, 4, 1.2)
		else:
			# Crisp mini video-play triangle badge on left + "×2 COINS" text.
			var badge := Rect2(face.position.x + 10.0, fc.y - 10.0, 22.0, 20.0)
			GameOverOverlay._draw_rounded_rect_static(self, badge, Color(0.28, 0.10, 0.0, 0.52), 6.0)
			var bc := badge.get_center()
			draw_colored_polygon(PackedVector2Array([bc + Vector2(-3.2, -4.8), bc + Vector2(5.2, 0.0), bc + Vector2(-3.2, 4.8)]), Color("#FFFFFF"))
			GameOverOverlay._draw_centered_outlined_text(self, eb, fc + Vector2(12.0, -0.5), "×2 COINS", 15, Color("#FFFFFF"), out_c, 4, 1.4)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
