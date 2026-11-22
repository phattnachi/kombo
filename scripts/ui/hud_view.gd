class_name HudView
extends Control

## Top HUD for Kombo (540x190) — Round 2 Overhaul:
## - Block Blast!-inspired Golden Crown High Score + tactile top-right arcade buttons
## - High, clean Hero Total Score (48px Kanit-ExtraBold) completely clear above flames
## - Balatro Chips × Mult equation with oversized bold numerals (NO double-× operator!),
##   low-profile open-top cradle, and seamless pill-melting shader flames (OFF when calm!)
## - Symmetrical unified FEVER / COMBO gauge bar (ZERO asymmetric hanging badges)
## - 60+ FPS native C++ cached StyleBoxFlat + velvety Gaussian GradientTexture2D glows

signal audio_toggled(muted: bool)
signal restart_requested()
signal home_requested()
signal settings_requested()

const HUD_SIZE := Vector2(540.0, 190.0)
const FONT_EXTRABOLD_PATH := "res://assets/fonts/Kanit-ExtraBold.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/Kanit-Bold.ttf"
const FONT_SEMIBOLD_PATH := "res://assets/fonts/Kanit-SemiBold.ttf"
const FLAME_SHADER_PATH := "res://shaders/flame_pill.gdshader"

# Top bar (y = 12..50) & Hero Score (y = 20..70, center y = 45)
const CROWN_RECT := Rect2(22.0, 13.0, 34.0, 27.0)
const HOME_BTN_RECT := Rect2(432.0, 12.0, 38.0, 38.0)
const SETTINGS_BTN_RECT := Rect2(478.0, 12.0, 38.0, 38.0)
const SCORE_CENTER_LOCAL := Vector2(270.0, 46.0)

# Balatro Equation Row (y = 104..152, 100% symmetrical around x = 270)
const BACKING_PLATE_RECT := Rect2(106.0, 126.0, 328.0, 30.0)
const CHIPS_PILL_RECT := Rect2(114.0, 106.0, 130.0, 44.0)
const MULT_PILL_RECT := Rect2(296.0, 106.0, 130.0, 44.0)
const MULT_SIGN_CENTER := Vector2(270.0, 128.0)
const CHIPS_FLAME_RECT := Rect2(106.0, 50.0, 146.0, 70.0)
const MULT_FLAME_RECT := Rect2(288.0, 50.0, 146.0, 70.0)

# Symmetrical Unified FEVER / COMBO Bar (y = 162..184)
const FEVER_BAR_RECT := Rect2(28.0, 166.0, 484.0, 14.0)
const FEVER_POD_LEFT_RECT := Rect2(36.0, 162.0, 228.0, 22.0)
const FEVER_POD_RIGHT_RECT := Rect2(276.0, 162.0, 228.0, 22.0)
const FEVER_MAX_PIPS := 6

var _font_extrabold: Font
var _font_bold: Font
var _font_semibold: Font

# Score & high score rolling state
var _target_score: int = 0
var _displayed_score: float = 0.0
var _target_high_score: int = 0
var _displayed_high_score: float = 0.0
var _is_new_high_score: bool = false

# Equation & Fever state
var _display_chips: int = 0
var _display_mult: float = 1.0
var _combo_streak: int = 0
var _fever_active: bool = false
var _target_fever_charge: float = 0.0
var _displayed_fever_charge: float = 0.0
var _fever_turns_left: int = 0

# Spring & juice animation state
var _time_sec: float = 0.0
var _score_scale: float = 1.0
var _score_scale_vel: float = 0.0
var _score_rot: float = 0.0
var _score_rot_vel: float = 0.0
var _score_flash: float = 0.0
var _score_tilt_dir: float = 1.0

var _crown_scale: float = 1.0
var _crown_scale_vel: float = 0.0
var _crown_glow: float = 0.0

var _chips_scale: float = 1.0
var _chips_scale_vel: float = 0.0
var _chips_rot: float = 0.0
var _chips_rot_vel: float = 0.0
var _chips_flash: float = 0.0

var _mult_scale: float = 1.0
var _mult_scale_vel: float = 0.0
var _mult_rot: float = 0.0
var _mult_rot_vel: float = 0.0
var _mult_flash: float = 0.0

var _x_scale: float = 1.0
var _x_scale_vel: float = 0.0

var _combo_badge_scale: float = 0.0
var _combo_badge_vel: float = 0.0
var _combo_badge_wobble: float = 0.0

var _fever_ignition_flash: float = 0.0
var _orb_halo_pulse: float = 0.0

# Flame shader controls
var _chips_flame_rect: ColorRect
var _mult_flame_rect: ColorRect
var _chips_flame_mat: ShaderMaterial
var _mult_flame_mat: ShaderMaterial
var _chips_flame_intensity: float = 0.0
var _chips_flame_target: float = 0.0
var _mult_flame_intensity: float = 0.0
var _mult_flame_target: float = 0.0

# Cached GPU resources (60+ FPS zero-triangulation rendering)
var _radial_glow_tex: GradientTexture2D
var _charge_grad_tex: GradientTexture2D
var _fever_grad_tex: GradientTexture2D

var _sb_backing_plate: StyleBoxFlat
var _sb_pill_lip: StyleBoxFlat
var _sb_pill_face: StyleBoxFlat
var _sb_pill_upper_gloss: StyleBoxFlat
var _sb_pill_rim: StyleBoxFlat

var _sb_fever_trough: StyleBoxFlat
var _sb_fever_cap_left: StyleBoxFlat
var _sb_fever_cap_right: StyleBoxFlat
var _sb_fever_cap_single: StyleBoxFlat
var _sb_fever_gloss: StyleBoxFlat
var _sb_fever_border: StyleBoxFlat

var _sb_tag_calm: StyleBoxFlat
var _sb_combo_lip: StyleBoxFlat
var _sb_combo_face: StyleBoxFlat
var _sb_combo_gloss: StyleBoxFlat
var _sb_fever_pod_left: StyleBoxFlat
var _sb_fever_pod_left_gloss: StyleBoxFlat
var _sb_fever_pod_right: StyleBoxFlat
var _sb_daily_pill: StyleBoxFlat

# Top-center Mode HUD pill state (Daily Challenge / 20-Turn Sprint / Gem Hunt)
var _mode_badge_kind: int = 0 # 0 = off, 1 = daily, 2 = sprint, 3 = gem_hunt
var _mode_badge_text: String = ""
var _mode_badge_urgent: bool = false

# Child layers & interactive top-right arcade buttons
var _fg_layer: _HudForegroundLayer
var _home_btn: _ArcadeIconButton
var _settings_btn: _ArcadeIconButton
var _audio_btn: _ArcadeIconButton
var _restart_btn: _ArcadeIconButton
var _is_muted: bool = false


func _ready() -> void:
	custom_minimum_size = HUD_SIZE
	if size.x < 10.0 or size.y < 10.0:
		size = HUD_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS

	_load_fonts()
	_init_cached_gpu_resources()
	_build_child_layers()
	_apply_flame_uniforms()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	_time_sec += dt

	# Smooth rolling score count-up with acceleration on big jumps.
	if _displayed_score < float(_target_score):
		var diff := float(_target_score) - _displayed_score
		var min_step := maxf(45.0, diff * 7.5) * dt
		_displayed_score = minf(float(_target_score), _displayed_score + min_step)
	elif _displayed_score > float(_target_score):
		_displayed_score = float(_target_score)

	if _displayed_high_score < float(_target_high_score):
		var hdiff := float(_target_high_score) - _displayed_high_score
		var hstep := maxf(45.0, hdiff * 7.5) * dt
		_displayed_high_score = minf(float(_target_high_score), _displayed_high_score + hstep)
	elif _displayed_high_score > float(_target_high_score):
		_displayed_high_score = float(_target_high_score)

	# Smooth FEVER gauge fill interpolation (stays monotonic with fever_turns_left during active FEVER).
	var fever_target := clampf(_target_fever_charge, 0.0, 1.0)
	var fever_rate := 9.0 if fever_target >= _displayed_fever_charge else 6.0
	_displayed_fever_charge = move_toward(_displayed_fever_charge, fever_target, maxf(0.15, absf(fever_target - _displayed_fever_charge) * fever_rate) * dt)

	# Spring physics updates (Balatro snappy spring-back).
	var s_res := _step_spring(_score_scale, _score_scale_vel, 1.0, 260.0, 18.0, dt)
	_score_scale = s_res.x
	_score_scale_vel = s_res.y

	var sr_res := _step_spring(_score_rot, _score_rot_vel, 0.0, 240.0, 16.0, dt)
	_score_rot = sr_res.x
	_score_rot_vel = sr_res.y

	var cr_res := _step_spring(_crown_scale, _crown_scale_vel, 1.0, 240.0, 16.0, dt)
	_crown_scale = cr_res.x
	_crown_scale_vel = cr_res.y

	var cs_res := _step_spring(_chips_scale, _chips_scale_vel, 1.0, 290.0, 19.0, dt)
	_chips_scale = cs_res.x
	_chips_scale_vel = cs_res.y

	var crot_res := _step_spring(_chips_rot, _chips_rot_vel, 0.0, 250.0, 17.0, dt)
	_chips_rot = crot_res.x
	_chips_rot_vel = crot_res.y

	var ms_res := _step_spring(_mult_scale, _mult_scale_vel, 1.0, 290.0, 19.0, dt)
	_mult_scale = ms_res.x
	_mult_scale_vel = ms_res.y

	var mrot_res := _step_spring(_mult_rot, _mult_rot_vel, 0.0, 250.0, 17.0, dt)
	_mult_rot = mrot_res.x
	_mult_rot_vel = mrot_res.y

	var xs_res := _step_spring(_x_scale, _x_scale_vel, 1.0, 300.0, 18.0, dt)
	_x_scale = xs_res.x
	_x_scale_vel = xs_res.y

	var badge_target := 1.0 if (_combo_streak >= 2 and not _fever_active) else 0.0
	var bs_res := _step_spring(_combo_badge_scale, _combo_badge_vel, badge_target, 320.0, 17.0, dt)
	_combo_badge_scale = maxf(0.0, bs_res.x)
	_combo_badge_vel = bs_res.y
	if badge_target == 0.0 and _combo_badge_scale < 0.02 and absf(_combo_badge_vel) < 0.05:
		_combo_badge_scale = 0.0
		_combo_badge_vel = 0.0

	# Flash & pulse decays.
	_score_flash = maxf(0.0, _score_flash - dt * 2.8)
	_chips_flash = maxf(0.0, _chips_flash - dt * 3.0)
	_mult_flash = maxf(0.0, _mult_flash - dt * 2.6)
	_combo_badge_wobble = maxf(0.0, _combo_badge_wobble - dt * 2.4)
	_fever_ignition_flash = maxf(0.0, _fever_ignition_flash - dt * 1.8)
	_orb_halo_pulse = maxf(0.0, _orb_halo_pulse - dt * 3.4)

	if _is_new_high_score:
		_crown_glow = lerpf(_crown_glow, 0.72, dt * 3.0)
	else:
		_crown_glow = maxf(0.0, _crown_glow - dt * 1.8)

	# Smoothly ramp live Balatro pill flames & lock transforms to bouncing pills.
	var c_rate := 10.5 if _chips_flame_target > _chips_flame_intensity else 5.5
	var m_rate := 10.5 if _mult_flame_target > _mult_flame_intensity else 5.5
	_chips_flame_intensity = lerpf(_chips_flame_intensity, _chips_flame_target, clampf(c_rate * dt, 0.0, 1.0))
	_mult_flame_intensity = lerpf(_mult_flame_intensity, _mult_flame_target, clampf(m_rate * dt, 0.0, 1.0))
	if absf(_chips_flame_intensity - _chips_flame_target) < 0.004:
		_chips_flame_intensity = _chips_flame_target
	if absf(_mult_flame_intensity - _mult_flame_target) < 0.004:
		_mult_flame_intensity = _mult_flame_target
	_apply_flame_uniforms()

	queue_redraw()
	if _fg_layer != null:
		_fg_layer.queue_redraw()


# ==============================================================================
# PUBLIC API
# ==============================================================================

func set_initial_state(score: int, high_score: int) -> void:
	_target_score = maxi(0, score)
	_displayed_score = float(_target_score)
	_target_high_score = maxi(0, high_score)
	_displayed_high_score = float(_target_high_score)
	_is_new_high_score = false

	_display_chips = 0
	_display_mult = 1.0
	_combo_streak = 0
	_fever_active = false
	_target_fever_charge = 0.0
	_displayed_fever_charge = 0.0
	_fever_turns_left = 0

	_score_scale = 1.0
	_score_scale_vel = 0.0
	_score_rot = 0.0
	_score_rot_vel = 0.0
	_score_flash = 0.0
	_crown_scale = 1.0
	_crown_scale_vel = 0.0
	_crown_glow = 0.0
	_chips_scale = 1.0
	_chips_scale_vel = 0.0
	_chips_rot = 0.0
	_chips_rot_vel = 0.0
	_chips_flash = 0.0
	_mult_scale = 1.0
	_mult_scale_vel = 0.0
	_mult_rot = 0.0
	_mult_rot_vel = 0.0
	_mult_flash = 0.0
	_x_scale = 1.0
	_x_scale_vel = 0.0
	_combo_badge_scale = 0.0
	_combo_badge_vel = 0.0
	_combo_badge_wobble = 0.0
	_fever_ignition_flash = 0.0
	_orb_halo_pulse = 0.0

	_chips_flame_target = 0.0
	_chips_flame_intensity = 0.0
	_mult_flame_target = 0.0
	_mult_flame_intensity = 0.0
	_apply_flame_uniforms()

	queue_redraw()
	if _fg_layer != null:
		_fg_layer.queue_redraw()


func apply_move_result(result: Dictionary) -> void:
	var points_earned := int(result.get("points_earned", 0))
	var base_chips := int(result.get("base_chips", 0))
	var total_mult := float(result.get("total_mult", 1.0))
	var new_score := int(result.get("new_score", _target_score + points_earned))
	var high_score := int(result.get("high_score", maxi(_target_high_score, new_score)))
	var new_high := bool(result.get("is_new_high_score", false))
	var prev_combo := _combo_streak

	_target_score = maxi(0, new_score)
	_target_high_score = maxi(_target_high_score, high_score)
	_display_chips = maxi(0, base_chips)
	_display_mult = maxf(1.0, total_mult)
	_combo_streak = maxi(0, int(result.get("combo_streak", 0)))
	_fever_active = bool(result.get("fever_active", false))
	_target_fever_charge = clampf(float(result.get("fever_charge", 0.0)), 0.0, 1.0)
	_fever_turns_left = maxi(0, int(result.get("fever_turns_left", 0)))

	var fever_ignited := bool(result.get("fever_just_ignited", false))
	if fever_ignited:
		_fever_ignition_flash = 1.0

	if new_high:
		_is_new_high_score = true
		_crown_glow = 1.25
		_crown_scale = maxf(_crown_scale, 1.24)
		_crown_scale_vel = 2.4

	# Update Balatro flame targets strictly: OFF when calm, dynamic roar at combo >= 2, wild inferno in FEVER.
	_update_flame_targets(_combo_streak, _fever_active, _display_mult, false)

	# Balatro Scale-Punch on Hero Score (1.12x .. 1.32x proportional to points_earned).
	if points_earned > 0:
		var t_mag := clampf((float(points_earned) - 15.0) / 1400.0, 0.0, 1.0)
		var punch := lerpf(1.12, 1.32, pow(t_mag, 0.65))
		_score_scale = maxf(_score_scale, punch)
		_score_scale_vel = maxf(_score_scale_vel, 1.2 + t_mag * 2.4)
		_score_flash = clampf(0.45 + t_mag * 0.55, 0.45, 1.0)
		if points_earned >= 120:
			_score_tilt_dir = -_score_tilt_dir
			var tilt_deg := lerpf(1.0, 2.6, t_mag)
			_score_rot = deg_to_rad(tilt_deg) * _score_tilt_dir

	# Tactile equation pill punches.
	if base_chips > 0:
		var chip_boost := clampf(float(base_chips) / 400.0, 0.0, 1.0)
		_chips_scale = maxf(_chips_scale, lerpf(1.08, 1.22, chip_boost))
		_chips_rot = deg_to_rad(-2.0 - chip_boost * 1.8)
		_chips_flash = clampf(0.45 + chip_boost * 0.55, 0.45, 1.0)

	if total_mult > 1.01 or _fever_active:
		var mult_boost := clampf((total_mult - 1.0) / 9.0, 0.0, 1.0)
		_mult_scale = maxf(_mult_scale, lerpf(1.14, 1.30, mult_boost))
		_mult_rot = deg_to_rad(2.2 + mult_boost * 2.6)
		_mult_flash = clampf(0.55 + mult_boost * 0.45, 0.55, 1.0)
		_x_scale = maxf(_x_scale, lerpf(1.16, 1.34, mult_boost))
	else:
		_x_scale = maxf(_x_scale, 1.06)

	# Elastic spring pop for centered Combo pill on FEVER bar.
	if _combo_streak >= 2 and not _fever_active:
		if prev_combo < 2:
			_combo_badge_scale = 0.35
			_combo_badge_vel = 9.0
		else:
			_combo_badge_scale = 1.22
			_combo_badge_vel = 3.0
		_combo_badge_wobble = 1.0

	queue_redraw()
	if _fg_layer != null:
		_fg_layer.queue_redraw()


func trigger_score_orb_impact(points_chunk: int) -> void:
	var chunk := maxi(0, points_chunk)
	if chunk > 0 and _displayed_score < float(_target_score):
		_displayed_score = minf(float(_target_score), _displayed_score + float(chunk))
		if _is_new_high_score and _displayed_high_score < _displayed_score:
			_displayed_high_score = minf(float(_target_high_score), _displayed_score)

	var chunk_mag := clampf(float(chunk) / 250.0, 0.0, 1.0)
	_score_scale = maxf(_score_scale, lerpf(1.09, 1.22, chunk_mag))
	_score_scale_vel = maxf(_score_scale_vel, 1.1 + chunk_mag * 1.6)
	_score_flash = maxf(_score_flash, 0.65 + chunk_mag * 0.35)
	_orb_halo_pulse = 1.0
	_score_tilt_dir = -_score_tilt_dir
	_score_rot = deg_to_rad(lerpf(0.7, 2.0, chunk_mag)) * _score_tilt_dir

	queue_redraw()
	if _fg_layer != null:
		_fg_layer.queue_redraw()


func set_preview_mult(
	combo_streak: int,
	fever_active: bool,
	fever_charge: float,
	fever_turns_left: int,
	preview_chips: int,
	preview_mult: float
) -> void:
	_combo_streak = maxi(0, combo_streak)
	_fever_active = fever_active
	_target_fever_charge = clampf(fever_charge, 0.0, 1.0)
	_displayed_fever_charge = _target_fever_charge
	_fever_turns_left = maxi(0, fever_turns_left)
	_display_chips = maxi(0, preview_chips)
	_display_mult = maxf(1.0, preview_mult)

	if _combo_streak >= 2 and not _fever_active:
		_combo_badge_scale = 1.0
		_combo_badge_vel = 0.0
	else:
		_combo_badge_scale = 0.0
		_combo_badge_vel = 0.0

	if _display_chips > 0:
		_chips_flash = maxf(_chips_flash, 0.24)
	if _display_mult > 1.01 or _fever_active:
		_mult_flash = maxf(_mult_flash, 0.28)

	# Snap flames immediately so live preview & staged renders show exact flame intensity right away.
	_update_flame_targets(_combo_streak, _fever_active, _display_mult, true)
	_apply_flame_uniforms()

	queue_redraw()
	if _fg_layer != null:
		_fg_layer.queue_redraw()


func get_score_center_global() -> Vector2:
	return get_global_transform() * Vector2(size.x * 0.5, SCORE_CENTER_LOCAL.y)


func set_muted(muted: bool) -> void:
	_is_muted = muted
	if _audio_btn != null:
		_audio_btn.set_muted_state(_is_muted)


func is_muted() -> bool:
	return _is_muted


func set_daily_badge(active: bool, date_label: String = "", attempt_num: int = 1, max_attempts: int = 3) -> void:
	if active:
		_mode_badge_kind = 1
		_mode_badge_text = "DAILY  •  %s  •  TRY %d/%d" % [date_label, attempt_num, max_attempts]
		_mode_badge_urgent = false
	elif _mode_badge_kind == 1:
		_mode_badge_kind = 0
		_mode_badge_text = ""
		_mode_badge_urgent = false
	queue_redraw()
	if _fg_layer != null:
		_fg_layer.queue_redraw()


func set_sprint_badge(active: bool, moves_left: int = 60, moves_limit: int = 60) -> void:
	if active:
		_mode_badge_kind = 2
		_mode_badge_urgent = moves_left <= 10
		if moves_left <= 0:
			_mode_badge_text = "SPRINT  •  DONE!"
		elif moves_left == 1:
			_mode_badge_text = "SPRINT  •  LAST MOVE!"
		elif moves_left <= 10:
			_mode_badge_text = "SPRINT  •  FINAL %d MOVES!" % moves_left
		else:
			_mode_badge_text = "20-TURN SPRINT  •  %d/%d MOVES" % [moves_left, moves_limit]
	elif _mode_badge_kind == 2:
		_mode_badge_kind = 0
		_mode_badge_text = ""
		_mode_badge_urgent = false
	queue_redraw()
	if _fg_layer != null:
		_fg_layer.queue_redraw()


func set_gem_hunt_badge(active: bool, stage: int = 1, targets_left: int = 8, targets_total: int = 8, stage_mult: float = 1.0) -> void:
	if active:
		_mode_badge_kind = 3
		_mode_badge_urgent = targets_left <= 2
		var m_clean := ("%.2f" % stage_mult).rstrip("0").rstrip(".")
		var mult_str := (" (×%s)" % m_clean) if stage_mult > 1.01 else ""
		if targets_left <= 2:
			_mode_badge_text = "STAGE %d%s  •  ◆ %d LEFT!" % [stage, mult_str, maxi(0, targets_left)]
		else:
			_mode_badge_text = "STAGE %d%s  •  ◆ %d/%d GEMS" % [stage, mult_str, maxi(0, targets_left), maxi(1, targets_total)]
	elif _mode_badge_kind == 3:
		_mode_badge_kind = 0
		_mode_badge_text = ""
		_mode_badge_urgent = false
	queue_redraw()
	if _fg_layer != null:
		_fg_layer.queue_redraw()


func clear_mode_badge() -> void:
	_mode_badge_kind = 0
	_mode_badge_text = ""
	_mode_badge_urgent = false
	queue_redraw()
	if _fg_layer != null:
		_fg_layer.queue_redraw()


# ==============================================================================
# INTERNAL SETUP & CACHED GPU RESOURCES (60+ FPS)
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


func _init_cached_gpu_resources() -> void:
	_radial_glow_tex = _create_radial_glow_texture()
	_charge_grad_tex = _create_horizontal_gradient_texture(
		PackedFloat32Array([0.0, 0.52, 1.0]),
		PackedColorArray([Color("#16E0FF"), Color("#DF42FF"), Color("#FFD43B")])
	)
	_fever_grad_tex = _create_horizontal_gradient_texture(
		PackedFloat32Array([0.0, 0.45, 0.80, 1.0]),
		PackedColorArray([Color("#FF3814"), Color("#FF8C14"), Color("#FFE048"), Color("#FF5A14")])
	)

	# Sleek low-profile dark backing plate behind ONLY the lower half of the pills (ZERO top border!).
	_sb_backing_plate = StyleBoxFlat.new()
	_sb_backing_plate.bg_color = Color(0.043, 0.067, 0.165, 0.80)
	_sb_backing_plate.corner_radius_top_left = 10
	_sb_backing_plate.corner_radius_top_right = 10
	_sb_backing_plate.corner_radius_bottom_left = 14
	_sb_backing_plate.corner_radius_bottom_right = 14
	_sb_backing_plate.corner_detail = 8
	_sb_backing_plate.border_width_top = 0
	_sb_backing_plate.border_width_left = 1
	_sb_backing_plate.border_width_right = 1
	_sb_backing_plate.border_width_bottom = 2
	_sb_backing_plate.border_color = Color(0.26, 0.40, 0.72, 0.46)
	_sb_backing_plate.shadow_color = Color(0.015, 0.025, 0.085, 0.52)
	_sb_backing_plate.shadow_size = 5
	_sb_backing_plate.shadow_offset = Vector2(0.0, 3.0)

	# Shared pill StyleBoxes (tinted dynamically in C++ with zero allocation).
	_sb_pill_lip = StyleBoxFlat.new()
	_sb_pill_lip.set_corner_radius_all(11)
	_sb_pill_lip.corner_detail = 8
	_sb_pill_lip.shadow_color = Color(0.01, 0.02, 0.08, 0.56)
	_sb_pill_lip.shadow_size = 4
	_sb_pill_lip.shadow_offset = Vector2(0.0, 3.0)

	_sb_pill_face = StyleBoxFlat.new()
	_sb_pill_face.set_corner_radius_all(10)
	_sb_pill_face.corner_detail = 8

	_sb_pill_upper_gloss = StyleBoxFlat.new()
	_sb_pill_upper_gloss.corner_radius_top_left = 9
	_sb_pill_upper_gloss.corner_radius_top_right = 9
	_sb_pill_upper_gloss.corner_radius_bottom_left = 4
	_sb_pill_upper_gloss.corner_radius_bottom_right = 4
	_sb_pill_upper_gloss.corner_detail = 6

	_sb_pill_rim = StyleBoxFlat.new()
	_sb_pill_rim.draw_center = false
	_sb_pill_rim.set_corner_radius_all(10)
	_sb_pill_rim.corner_detail = 8
	_sb_pill_rim.set_border_width_all(1)

	# FEVER gauge StyleBoxes.
	_sb_fever_trough = StyleBoxFlat.new()
	_sb_fever_trough.bg_color = Color(0.043, 0.068, 0.175, 0.94)
	_sb_fever_trough.set_corner_radius_all(7)
	_sb_fever_trough.corner_detail = 6
	_sb_fever_trough.shadow_color = Color(0.015, 0.025, 0.09, 0.52)
	_sb_fever_trough.shadow_size = 3
	_sb_fever_trough.shadow_offset = Vector2(0.0, 2.0)

	_sb_fever_cap_left = StyleBoxFlat.new()
	_sb_fever_cap_left.corner_radius_top_left = 5
	_sb_fever_cap_left.corner_radius_bottom_left = 5
	_sb_fever_cap_left.corner_radius_top_right = 0
	_sb_fever_cap_left.corner_radius_bottom_right = 0
	_sb_fever_cap_left.corner_detail = 6

	_sb_fever_cap_right = StyleBoxFlat.new()
	_sb_fever_cap_right.corner_radius_top_left = 0
	_sb_fever_cap_right.corner_radius_bottom_left = 0
	_sb_fever_cap_right.corner_radius_top_right = 5
	_sb_fever_cap_right.corner_radius_bottom_right = 5
	_sb_fever_cap_right.corner_detail = 6

	_sb_fever_cap_single = StyleBoxFlat.new()
	_sb_fever_cap_single.set_corner_radius_all(5)
	_sb_fever_cap_single.corner_detail = 6

	_sb_fever_gloss = StyleBoxFlat.new()
	_sb_fever_gloss.bg_color = Color(1.0, 1.0, 1.0, 0.28)
	_sb_fever_gloss.set_corner_radius_all(2)
	_sb_fever_gloss.corner_detail = 4

	_sb_fever_border = StyleBoxFlat.new()
	_sb_fever_border.draw_center = false
	_sb_fever_border.set_corner_radius_all(7)
	_sb_fever_border.corner_detail = 6
	_sb_fever_border.set_border_width_all(2)

	# Calm centered FEVER tag.
	_sb_tag_calm = StyleBoxFlat.new()
	_sb_tag_calm.bg_color = Color(0.065, 0.10, 0.24, 0.96)
	_sb_tag_calm.set_corner_radius_all(9)
	_sb_tag_calm.corner_detail = 6
	_sb_tag_calm.set_border_width_all(1)
	_sb_tag_calm.shadow_color = Color(0.01, 0.02, 0.08, 0.55)
	_sb_tag_calm.shadow_size = 3
	_sb_tag_calm.shadow_offset = Vector2(0.0, 1.5)

	# Centered Combo badge pill (on FEVER bar when combo_streak >= 2 and not FEVER).
	_sb_combo_lip = StyleBoxFlat.new()
	_sb_combo_lip.set_corner_radius_all(11)
	_sb_combo_lip.corner_detail = 6
	_sb_combo_lip.shadow_color = Color(0.02, 0.02, 0.08, 0.62)
	_sb_combo_lip.shadow_size = 4
	_sb_combo_lip.shadow_offset = Vector2(0.0, 2.0)

	_sb_combo_face = StyleBoxFlat.new()
	_sb_combo_face.set_corner_radius_all(11)
	_sb_combo_face.corner_detail = 6
	_sb_combo_face.set_border_width_all(2)

	_sb_combo_gloss = StyleBoxFlat.new()
	_sb_combo_gloss.bg_color = Color(1.0, 1.0, 1.0, 0.26)
	_sb_combo_gloss.set_corner_radius_all(5)
	_sb_combo_gloss.corner_detail = 4

	# Symmetrical FEVER twin pods: Left blazing medallion & Right burning ember-pip pod.
	_sb_fever_pod_left = StyleBoxFlat.new()
	_sb_fever_pod_left.bg_color = Color("#D92A14")
	_sb_fever_pod_left.set_corner_radius_all(11)
	_sb_fever_pod_left.corner_detail = 6
	_sb_fever_pod_left.set_border_width_all(2)
	_sb_fever_pod_left.border_color = Color("#FFF08A")
	_sb_fever_pod_left.shadow_color = Color(0.35, 0.05, 0.0, 0.55)
	_sb_fever_pod_left.shadow_size = 4
	_sb_fever_pod_left.shadow_offset = Vector2(0.0, 2.0)

	_sb_fever_pod_left_gloss = StyleBoxFlat.new()
	_sb_fever_pod_left_gloss.bg_color = Color("#FF8F33", 0.55)
	_sb_fever_pod_left_gloss.corner_radius_top_left = 9
	_sb_fever_pod_left_gloss.corner_radius_top_right = 9
	_sb_fever_pod_left_gloss.corner_radius_bottom_left = 4
	_sb_fever_pod_left_gloss.corner_radius_bottom_right = 4
	_sb_fever_pod_left_gloss.corner_detail = 5

	_sb_fever_pod_right = StyleBoxFlat.new()
	_sb_fever_pod_right.bg_color = Color(0.16, 0.04, 0.05, 0.94)
	_sb_fever_pod_right.set_corner_radius_all(11)
	_sb_fever_pod_right.corner_detail = 6
	_sb_fever_pod_right.set_border_width_all(2)
	_sb_fever_pod_right.border_color = Color("#FFB833", 0.92)
	_sb_fever_pod_right.shadow_color = Color(0.28, 0.04, 0.0, 0.50)
	_sb_fever_pod_right.shadow_size = 4
	_sb_fever_pod_right.shadow_offset = Vector2(0.0, 2.0)

	_sb_daily_pill = StyleBoxFlat.new()
	_sb_daily_pill.bg_color = Color(0.06, 0.09, 0.24, 0.92)
	_sb_daily_pill.set_corner_radius_all(10)
	_sb_daily_pill.corner_detail = 6
	_sb_daily_pill.set_border_width_all(1)
	_sb_daily_pill.border_color = Color("#FFD43B", 0.78)


func _build_child_layers() -> void:
	# Layer 2: Seamless melted Balatro pill flame shaders sitting OVER the pill's top lip
	# (erasing the top seam into wild fire!) and directly BEHIND the Layer 3 numerals & Hero Score.
	var flame_shader: Shader = null
	if ResourceLoader.exists(FLAME_SHADER_PATH):
		flame_shader = load(FLAME_SHADER_PATH) as Shader

	_chips_flame_rect = ColorRect.new()
	_chips_flame_rect.name = "ChipsFlame"
	_chips_flame_rect.position = CHIPS_FLAME_RECT.position
	_chips_flame_rect.size = CHIPS_FLAME_RECT.size
	_chips_flame_rect.pivot_offset = CHIPS_PILL_RECT.get_center() - CHIPS_FLAME_RECT.position
	_chips_flame_rect.color = Color.WHITE
	_chips_flame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips_flame_rect.visible = false
	if flame_shader != null:
		_chips_flame_mat = ShaderMaterial.new()
		_chips_flame_mat.shader = flame_shader
		_chips_flame_mat.set_shader_parameter("base_color", Color("#198EFF"))
		_chips_flame_mat.set_shader_parameter("outer_color", Color("#0094FF"))
		_chips_flame_mat.set_shader_parameter("core_color", Color("#9CF9FF"))
		_chips_flame_mat.set_shader_parameter("intensity", 0.0)
		_chips_flame_mat.set_shader_parameter("flame_speed", 3.4)
		_chips_flame_mat.set_shader_parameter("seed_offset", 1.7)
		_chips_flame_rect.material = _chips_flame_mat
	add_child(_chips_flame_rect)

	_mult_flame_rect = ColorRect.new()
	_mult_flame_rect.name = "MultFlame"
	_mult_flame_rect.position = MULT_FLAME_RECT.position
	_mult_flame_rect.size = MULT_FLAME_RECT.size
	_mult_flame_rect.pivot_offset = MULT_PILL_RECT.get_center() - MULT_FLAME_RECT.position
	_mult_flame_rect.color = Color.WHITE
	_mult_flame_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mult_flame_rect.visible = false
	if flame_shader != null:
		_mult_flame_mat = ShaderMaterial.new()
		_mult_flame_mat.shader = flame_shader
		_mult_flame_mat.set_shader_parameter("base_color", Color("#F02A24"))
		_mult_flame_mat.set_shader_parameter("outer_color", Color("#FF3B12"))
		_mult_flame_mat.set_shader_parameter("core_color", Color("#FFF066"))
		_mult_flame_mat.set_shader_parameter("intensity", 0.0)
		_mult_flame_mat.set_shader_parameter("flame_speed", 3.7)
		_mult_flame_mat.set_shader_parameter("seed_offset", 5.9)
		_mult_flame_rect.material = _mult_flame_mat
	add_child(_mult_flame_rect)

	# Layer 3: Foreground canvas for Hero Score, bold oversized Pill Numerals, and molten × sign
	# so typography ALWAYS stays razor-crisp in front of roaring flames!
	_fg_layer = _HudForegroundLayer.new()
	_fg_layer.name = "HudForegroundLayer"
	_fg_layer.hud = self
	_fg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fg_layer)

	# Layer 4: Clean 2-button top-right dark-glass arcade cluster (Home & Settings).
	_home_btn = _ArcadeIconButton.new()
	_home_btn.name = "HomeButton"
	_home_btn.icon_kind = _ArcadeIconButton.ICON_HOME
	_home_btn.position = HOME_BTN_RECT.position
	_home_btn.size = HOME_BTN_RECT.size
	_home_btn.tooltip_text = "Home"
	_home_btn.activated.connect(_on_home_button_activated)
	add_child(_home_btn)

	_settings_btn = _ArcadeIconButton.new()
	_settings_btn.name = "SettingsButton"
	_settings_btn.icon_kind = _ArcadeIconButton.ICON_SETTINGS
	_settings_btn.position = SETTINGS_BTN_RECT.position
	_settings_btn.size = SETTINGS_BTN_RECT.size
	_settings_btn.tooltip_text = "Settings"
	_settings_btn.activated.connect(_on_settings_button_activated)
	add_child(_settings_btn)


func _on_home_button_activated() -> void:
	home_requested.emit()


func _on_settings_button_activated() -> void:
	settings_requested.emit()


func _on_audio_button_activated() -> void:
	_is_muted = not _is_muted
	if _audio_btn != null:
		_audio_btn.set_muted_state(_is_muted)
	audio_toggled.emit(_is_muted)


func _on_restart_button_activated() -> void:
	restart_requested.emit()


func _update_flame_targets(combo_streak: int, fever_active: bool, total_mult: float, immediate: bool) -> void:
	var c_target := 0.0
	var m_target := 0.0

	if fever_active:
		# Wild roaring FEVER inferno!
		c_target = 1.38
		m_target = 1.45
	elif combo_streak >= 2:
		# Dynamic roaring flames starting cleanly at combo >= 2.
		var heat := clampf(float(combo_streak - 2) / 4.0, 0.0, 1.0)
		var mult_bonus := clampf((total_mult - 2.0) * 0.025, 0.0, 0.16)
		c_target = clampf(0.58 + heat * 0.46 + mult_bonus * 0.6, 0.58, 1.12)
		m_target = clampf(0.66 + heat * 0.50 + mult_bonus, 0.66, 1.20)
	else:
		# Strictly OFF when calm (combo_streak < 2 and not fever_active).
		c_target = 0.0
		m_target = 0.0

	_chips_flame_target = c_target
	_mult_flame_target = m_target

	if immediate:
		_chips_flame_intensity = _chips_flame_target
		_mult_flame_intensity = _mult_flame_target


func _apply_flame_uniforms() -> void:
	if _chips_flame_rect != null:
		var c_active := _chips_flame_intensity > 0.002
		_chips_flame_rect.visible = c_active
		if c_active:
			_chips_flame_rect.scale = Vector2(_chips_scale, _chips_scale)
			_chips_flame_rect.rotation = _chips_rot
	if _mult_flame_rect != null:
		var m_active := _mult_flame_intensity > 0.002
		_mult_flame_rect.visible = m_active
		if m_active:
			_mult_flame_rect.scale = Vector2(_mult_scale, _mult_scale)
			_mult_flame_rect.rotation = _mult_rot

	if _chips_flame_mat != null:
		_chips_flame_mat.set_shader_parameter("intensity", _chips_flame_intensity)
		_chips_flame_mat.set_shader_parameter("flame_speed", 4.5 if _fever_active else 3.4)
	if _mult_flame_mat != null:
		_mult_flame_mat.set_shader_parameter("intensity", _mult_flame_intensity)
		_mult_flame_mat.set_shader_parameter("flame_speed", 4.9 if _fever_active else 3.7)
		_mult_flame_mat.set_shader_parameter("base_color", Color("#FF461F") if _fever_active else Color("#F02A24"))


# ==============================================================================
# LAYER 1 DRAW: TOP BAR CROWN, OPEN-TOP CRADLE, 3D PILL BODIES, FEVER/COMBO BAR
# ==============================================================================

func _draw() -> void:
	_draw_top_bar_high_score(self)
	_draw_low_backing_plate(self)
	_draw_chips_pill_body(self)
	_draw_mult_pill_body(self)
	_draw_fever_gauge(self)


func _draw_top_bar_high_score(ci: CanvasItem) -> void:
	var crown_center := CROWN_RECT.get_center()
	var pulse := 0.5 + 0.5 * sin(_time_sec * 5.2)

	# Velvety Gaussian golden aura when beating high score (ZERO hard circular halo!).
	if _crown_glow > 0.02:
		var glow_r := 28.0 + pulse * 6.0
		_draw_soft_glow(ci, crown_center, Vector2(glow_r, glow_r), Color(1.0, 0.84, 0.22, 0.42 * _crown_glow))

	# Custom-drawn Block Blast!-inspired gleaming Golden Crown.
	var c_scale := _crown_scale + (pulse * 0.05 if _is_new_high_score else 0.0)
	ci.draw_set_transform(crown_center, 0.0, Vector2(c_scale, c_scale))
	_draw_golden_crown(ci, Rect2(-CROWN_RECT.size * 0.5, CROWN_RECT.size), _crown_glow, _time_sec)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Bold golden High Score numeral immediately right of crown.
	var hs_text := format_comma_int(int(round(_displayed_high_score)))
	var hs_font_size := 25
	var hs_pos := Vector2(CROWN_RECT.end.x + 8.0, crown_center.y + 1.0)
	var hs_color := Color("#FFD43B").lerp(Color("#FFF6B3"), clampf(_crown_glow * 0.45 * (0.65 + 0.35 * pulse), 0.0, 0.65))
	_draw_left_outlined_text(ci, _font_extrabold, hs_pos, hs_text, hs_font_size, hs_color, Color("#2A1A00"), 5, 2.0)


func _is_equation_calm() -> bool:
	return _combo_streak < 2 and not _fever_active and _display_mult <= 1.05


func _draw_low_backing_plate(ci: CanvasItem) -> void:
	if _is_equation_calm():
		return
	var plate := BACKING_PLATE_RECT
	var fever_pulse := 0.5 + 0.5 * sin(_time_sec * 7.0)

	# Velvety ambient glow behind the equation cradle during combo / FEVER.
	if _fever_active:
		_draw_soft_glow(ci, Vector2(270.0, 128.0), Vector2(195.0, 38.0), Color(1.0, 0.44, 0.12, 0.32 + fever_pulse * 0.14))
		_sb_backing_plate.border_color = Color("#FF6A1A").lerp(Color("#FFE066"), 0.42 + fever_pulse * 0.35)
	elif _combo_streak >= 2:
		_draw_soft_glow(ci, Vector2(270.0, 128.0), Vector2(180.0, 32.0), Color(0.24, 0.64, 1.0, 0.22 + 0.08 * sin(_time_sec * 5.0)))
		_sb_backing_plate.border_color = Color("#458CFF").lerp(Color("#FFD43B"), clampf(float(_combo_streak - 1) * 0.18, 0.0, 0.65))
	else:
		_sb_backing_plate.border_color = Color(0.26, 0.40, 0.72, 0.46)

	# Sleek low-profile cradle ONLY behind the lower half of pills (ZERO top border above pills!).
	_sb_backing_plate.draw(ci.get_canvas_item(), plate)


func _draw_chips_pill_body(ci: CanvasItem) -> void:
	var calm := _is_equation_calm()
	var rect := Rect2(142.0, 113.0, 102.0, 34.0) if calm else CHIPS_PILL_RECT
	var center := rect.get_center()
	var local_rect := Rect2(-rect.size * 0.5, rect.size)

	ci.draw_set_transform(center, _chips_rot, Vector2(_chips_scale, _chips_scale))
	if calm:
		_draw_3d_arcade_pill_stylebox(
			ci,
			local_rect,
			Color(0.11, 0.23, 0.55, 0.78),
			Color(0.24, 0.44, 0.84, 0.55),
			Color(0.06, 0.12, 0.32, 0.82),
			Color(0.55, 0.76, 1.0, 0.65),
			_chips_flash,
			0.0
		)
	else:
		_draw_3d_arcade_pill_stylebox(
			ci,
			local_rect,
			Color("#168EFF"),   # rich saturated electric blue face
			Color("#48BEFF"),   # luminous upper candy sheen
			Color("#084EA6"),   # 4px tactile 3D bottom lip
			Color("#8EE0FF"),   # crisp top specular rim (fades seamlessly when flaming!)
			_chips_flash,
			_chips_flame_intensity
		)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_mult_pill_body(ci: CanvasItem) -> void:
	var calm := _is_equation_calm()
	var rect := Rect2(296.0, 113.0, 102.0, 34.0) if calm else MULT_PILL_RECT
	var center := rect.get_center()
	var local_rect := Rect2(-rect.size * 0.5, rect.size)

	ci.draw_set_transform(center, _mult_rot, Vector2(_mult_scale, _mult_scale))
	if calm:
		_draw_3d_arcade_pill_stylebox(
			ci,
			local_rect,
			Color(0.26, 0.18, 0.46, 0.78),
			Color(0.44, 0.30, 0.68, 0.52),
			Color(0.13, 0.08, 0.26, 0.82),
			Color(0.72, 0.62, 0.96, 0.60),
			_mult_flash,
			0.0
		)
	else:
		var face_col := Color("#F02A24").lerp(Color("#FF461F"), 0.40 if _fever_active else 0.0)
		var upper_col := Color("#FF6A4D").lerp(Color("#FF992E"), 0.45 if _fever_active else 0.0)
		var rim_col := Color("#FF9980").lerp(Color("#FFE875"), 0.55 if _fever_active else 0.0)
		_draw_3d_arcade_pill_stylebox(
			ci,
			local_rect,
			face_col,
			upper_col,
			Color("#9E1410"),   # 4px tactile 3D bottom lip
			rim_col,
			_mult_flash,
			_mult_flame_intensity
		)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_3d_arcade_pill_stylebox(
	ci: CanvasItem,
	rect: Rect2,
	face_col: Color,
	upper_col: Color,
	lip_col: Color,
	rim_col: Color,
	flash: float,
	flame_intensity: float
) -> void:
	var lip_h := 4.5
	var face_rect := Rect2(rect.position, Vector2(rect.size.x, rect.size.y - lip_h))
	var boost := clampf(flash, 0.0, 1.0)
	var cid := ci.get_canvas_item()

	# 1. Tactile 3D bottom lip + native GPU drop shadow.
	_sb_pill_lip.bg_color = lip_col
	_sb_pill_lip.draw(cid, rect)

	# 2. Saturated Balatro pill face.
	var lit_face := face_col.lerp(Color.WHITE, boost * 0.36)
	_sb_pill_face.bg_color = lit_face
	_sb_pill_face.draw(cid, face_rect)

	# 3. Lush upper candy-bevel highlight band (softens naturally when melting into flames).
	var calm_mix := 1.0 - clampf(flame_intensity * 2.2, 0.0, 1.0)
	var sheen_rect := Rect2(face_rect.position + Vector2(3.0, 2.0), Vector2(face_rect.size.x - 6.0, face_rect.size.y * 0.44))
	var sheen_col := upper_col.lerp(Color.WHITE, boost * 0.35)
	sheen_col.a = lerpf(0.32, 0.54, calm_mix) + boost * 0.14
	_sb_pill_upper_gloss.bg_color = sheen_col
	_sb_pill_upper_gloss.draw(cid, sheen_rect)

	# 4. Top specular rim (crisp when calm; fades completely away when flames melt the top edge!).
	if calm_mix > 0.02:
		var top_rim := rim_col.lerp(Color.WHITE, boost * 0.45)
		_sb_pill_rim.border_color = Color(top_rim.r, top_rim.g, top_rim.b, 0.58 * calm_mix)
		_sb_pill_rim.draw(cid, face_rect)
		ci.draw_line(
			Vector2(face_rect.position.x + 11.0, face_rect.position.y + 1.2),
			Vector2(face_rect.end.x - 11.0, face_rect.position.y + 1.2),
			Color(top_rim.r, top_rim.g, top_rim.b, 0.82 * calm_mix),
			1.6,
			true
		)


func _draw_fever_gauge(ci: CanvasItem) -> void:
	var bar := FEVER_BAR_RECT
	var bar_center := bar.get_center()
	var pulse := 0.5 + 0.5 * sin(_time_sec * 8.0)
	var cid := ci.get_canvas_item()

	# Velvety Gaussian bloom aura behind the bar when FEVER is active!
	if _fever_active:
		var aura_alpha := 0.30 + pulse * 0.18 + _fever_ignition_flash * 0.25
		_draw_soft_glow(ci, bar_center, Vector2(bar.size.x * 0.56, 26.0), Color(1.0, 0.46, 0.10, aura_alpha))

	# Recessed dark-indigo pill trough.
	_sb_fever_trough.draw(cid, bar)

	var inner := bar.grow(-2.0)

	# Subtle 3-clear milestone ticks inside empty trough when charging.
	if not _fever_active:
		for seg_idx in range(1, 3):
			var tx := inner.position.x + inner.size.x * (float(seg_idx) / 3.0)
			ci.draw_line(
				Vector2(tx, inner.position.y + 1.5),
				Vector2(tx, inner.end.y - 1.5),
				Color(0.36, 0.50, 0.84, 0.36),
				1.2,
				false
			)

	# Zero-triangulation smooth horizontal neon gradient fill!
	var fill_ratio := clampf(_displayed_fever_charge, 0.0, 1.0)
	if _fever_active:
		fill_ratio = maxf(0.12, fill_ratio)
	if fill_ratio > 0.008:
		var fill_w := maxf(inner.size.y, inner.size.x * fill_ratio)
		var fill_rect := Rect2(inner.position, Vector2(fill_w, inner.size.y))
		_draw_fever_gradient_fill_fast(ci, fill_rect, fill_ratio, _fever_active)

		# Velvety Gaussian charge-tip spark orb while charging (ZERO hard circle!).
		if not _fever_active and fill_ratio < 0.995:
			var tip_pos := Vector2(fill_rect.end.x - inner.size.y * 0.45, fill_rect.get_center().y)
			var tip_col := _sample_charge_gradient(fill_ratio)
			_draw_soft_glow(ci, tip_pos, Vector2(14.0, 14.0), Color(tip_col.r, tip_col.g, tip_col.b, 0.65))
			_draw_soft_glow(ci, tip_pos, Vector2(5.5, 5.5), Color(1.0, 1.0, 1.0, 0.95))

	# Crisp outer bevel rim around trough.
	var border_col := Color(0.28, 0.44, 0.80, 0.68)
	if _fever_active:
		border_col = Color("#FF8822").lerp(Color("#FFF08A"), 0.45 + 0.35 * pulse)
	elif _combo_streak >= 2:
		border_col = Color("#9B5CFF").lerp(Color("#FFD43B"), 0.45 + 0.25 * sin(_time_sec * 6.0))
	elif fill_ratio > 0.65:
		border_col = Color("#8D5BFF").lerp(Color("#FFD43B"), (fill_ratio - 0.65) / 0.35)
	_sb_fever_border.border_color = border_col
	_sb_fever_border.draw(cid, bar)

	# Symmetrical unified status badges integrated directly onto the FEVER bar:
	if _fever_active:
		_draw_fever_active_twin_pods(ci, pulse)
	elif _combo_streak >= 2 and _combo_badge_scale > 0.02:
		_draw_centered_combo_pill_on_bar(ci, bar_center)
	else:
		_draw_calm_fever_tag(ci, bar_center, fill_ratio)


func _draw_fever_gradient_fill_fast(ci: CanvasItem, fill_rect: Rect2, fill_ratio: float, is_fever: bool) -> void:
	var cid := ci.get_canvas_item()
	var cap_w := minf(6.0, fill_rect.size.x * 0.5)
	var start_col := Color("#FF3814") if is_fever else Color("#16E0FF")
	var end_col := Color("#FFE048") if is_fever else _sample_charge_gradient(fill_ratio)

	if fill_rect.size.x <= 14.0:
		_sb_fever_cap_single.bg_color = start_col
		_sb_fever_cap_single.draw(cid, fill_rect)
	else:
		# Left anti-aliased rounded cap + center smooth GradientTexture2D strip + right rounded cap.
		_sb_fever_cap_left.bg_color = start_col
		_sb_fever_cap_left.draw(cid, Rect2(fill_rect.position, Vector2(cap_w, fill_rect.size.y)))

		var mid_rect := Rect2(
			Vector2(fill_rect.position.x + cap_w - 1.0, fill_rect.position.y),
			Vector2(fill_rect.size.x - cap_w * 2.0 + 2.0, fill_rect.size.y)
		)
		var grad_tex := _fever_grad_tex if is_fever else _charge_grad_tex
		if grad_tex != null and mid_rect.size.x > 0.5:
			var src_w := maxf(2.0, float(grad_tex.width) * clampf(fill_ratio, 0.05, 1.0))
			ci.draw_texture_rect_region(grad_tex, mid_rect, Rect2(0.0, 0.0, src_w, float(grad_tex.height)))

		_sb_fever_cap_right.bg_color = end_col
		_sb_fever_cap_right.draw(cid, Rect2(Vector2(fill_rect.end.x - cap_w, fill_rect.position.y), Vector2(cap_w, fill_rect.size.y)))

	# Glossy top highlight ribbon.
	if fill_rect.size.x > 16.0:
		var gloss_rect := Rect2(
			Vector2(fill_rect.position.x + 5.0, fill_rect.position.y + 1.2),
			Vector2(fill_rect.size.x - 10.0, fill_rect.size.y * 0.34)
		)
		_sb_fever_gloss.bg_color = Color(1.0, 1.0, 1.0, 0.34 if is_fever else 0.28)
		_sb_fever_gloss.draw(cid, gloss_rect)


func _draw_calm_fever_tag(ci: CanvasItem, center: Vector2, fill_ratio: float) -> void:
	var cid := ci.get_canvas_item()
	var tag_rect := Rect2(center - Vector2(31.0, 9.0), Vector2(62.0, 18.0))
	_sb_tag_calm.border_color = Color(0.36, 0.54, 0.90, 0.78).lerp(Color("#FFD43B"), clampf(fill_ratio, 0.0, 1.0) * 0.75)
	_sb_tag_calm.draw(cid, tag_rect)
	var label_col := Color("#A5C2FF").lerp(Color("#FFF2A8"), clampf(fill_ratio, 0.0, 1.0))
	_draw_centered_outlined_text(ci, _font_extrabold, center + Vector2(0.0, -0.3), "FEVER", 11, label_col, Color("#060A1A"), 3, 0.8)


func _draw_centered_combo_pill_on_bar(ci: CanvasItem, center: Vector2) -> void:
	var cid := ci.get_canvas_item()
	var text := "COMBO ×%d" % _combo_streak
	var font_size := 13
	var text_w := _font_extrabold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var badge_w := clampf(text_w + 26.0, 108.0, 144.0)
	var badge_h := 22.0
	var local_rect := Rect2(-badge_w * 0.5, -badge_h * 0.5, badge_w, badge_h)

	var is_hot := _combo_streak >= 4
	var body_col := Color("#E61E88") if is_hot else Color("#F58800")
	var lip_col := Color("#780744") if is_hot else Color("#8F4200")
	var rim_col := Color("#FFF08A") if is_hot else Color("#FFF8C4")
	var outline_col := Color("#3D0325") if is_hot else Color("#471C00")
	var glow_col := Color("#FF3EB5", 0.45) if is_hot else Color("#FFB824", 0.42)

	var wobble_rot := sin(_time_sec * 16.0) * deg_to_rad(2.5) * _combo_badge_wobble
	ci.draw_set_transform(center, wobble_rot, Vector2(_combo_badge_scale, _combo_badge_scale))

	# Velvety soft radial glow behind the centered COMBO badge.
	_draw_soft_glow(ci, Vector2.ZERO, Vector2(badge_w * 0.68, badge_h * 1.05), glow_col)

	_sb_combo_lip.bg_color = lip_col
	_sb_combo_lip.draw(cid, Rect2(local_rect.position + Vector2(0.0, 2.0), local_rect.size))

	_sb_combo_face.bg_color = body_col
	_sb_combo_face.border_color = rim_col
	_sb_combo_face.draw(cid, local_rect)

	var gloss := Rect2(local_rect.position + Vector2(6.0, 2.5), Vector2(local_rect.size.x - 12.0, local_rect.size.y * 0.34))
	_sb_combo_gloss.draw(cid, gloss)

	var fitted_size := _fit_pill_font_size(text, font_size, 10, badge_w - 14.0)
	_draw_centered_outlined_text(ci, _font_extrabold, Vector2(0.0, -0.4), text, fitted_size, Color("#FFFFFF"), outline_col, 3, 1.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_fever_active_twin_pods(ci: CanvasItem, pulse: float) -> void:
	var cid := ci.get_canvas_item()

	# Left Pod: Unified blazing "FEVER ×2  •  COMBO ×N" medallion (x = 36..264, mirrored cleanly!).
	var left_r := FEVER_POD_LEFT_RECT
	_draw_soft_glow(ci, left_r.get_center(), Vector2(left_r.size.x * 0.62, 24.0), Color(1.0, 0.48, 0.10, 0.36 + pulse * 0.16))
	_sb_fever_pod_left.border_color = Color("#FFE066").lerp(Color("#FFFBE0"), 0.35 + pulse * 0.45)
	_sb_fever_pod_left.draw(cid, left_r)
	_sb_fever_pod_left_gloss.draw(cid, Rect2(left_r.position + Vector2(4.0, 2.0), Vector2(left_r.size.x - 8.0, left_r.size.y * 0.42)))

	var fever_label := "FEVER ×2  •  COMBO ×%d" % _combo_streak if _combo_streak >= 2 else "FEVER ×2  INFERNO"
	var fever_font_size := _fit_pill_font_size(fever_label, 13, 10, left_r.size.x - 16.0)
	_draw_centered_outlined_text(ci, _font_extrabold, left_r.get_center() + Vector2(0.0, -0.4), fever_label, fever_font_size, Color("#FFFCE6"), Color("#4D0A00"), 3, 1.0)

	# Right Pod: Perfectly mirrored ember-pip rail holding burning turn pips (x = 276..504)!
	var right_r := FEVER_POD_RIGHT_RECT
	_sb_fever_pod_right.border_color = Color("#FF9922").lerp(Color("#FFF08A"), 0.35 + pulse * 0.35)
	_sb_fever_pod_right.draw(cid, right_r)

	var pip_count := maxi(FEVER_MAX_PIPS, _fever_turns_left)
	var pip_left := right_r.position.x + 22.0
	var pip_right := right_r.end.x - 22.0
	var pip_step := (pip_right - pip_left) / float(maxi(1, pip_count - 1)) if pip_count > 1 else 0.0
	var py := right_r.get_center().y
	for i in range(pip_count):
		var px := pip_left + float(i) * pip_step
		var pip_center := Vector2(px, py)
		var is_lit := i < _fever_turns_left
		if is_lit:
			var ember_p := 0.5 + 0.5 * sin(_time_sec * 10.0 + float(i) * 0.9)
			_draw_soft_glow(ci, pip_center, Vector2(11.0 + ember_p * 2.5, 11.0 + ember_p * 2.5), Color(1.0, 0.56, 0.12, 0.58 + ember_p * 0.24))
			_draw_diamond(ci, pip_center, 5.4, Color("#FF4A14"))
			_draw_diamond(ci, pip_center, 3.8, Color("#FFD942"))
			_draw_diamond(ci, pip_center + Vector2(-0.4, -0.4), 2.0, Color("#FFFFF2"))
		else:
			_draw_diamond(ci, pip_center, 3.9, Color(0.24, 0.07, 0.07, 0.90))
			_draw_diamond_outline(ci, pip_center, 3.9, Color(0.62, 0.28, 0.16, 0.55), 1.0)


# ==============================================================================
# LAYER 3 DRAW (FOREGROUND): HERO SCORE, OVERSIZED PILL NUMERALS, MOLTEN ×
# ==============================================================================

func _draw_foreground(ci: CanvasItem) -> void:
	_draw_hero_total_score(ci)
	if _mode_badge_kind != 0 and not _mode_badge_text.is_empty():
		var pulse := 0.5 + 0.5 * sin(_time_sec * 8.5)
		var pill_w := maxf(188.0, _font_bold.get_string_size(_mode_badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 28.0)
		var pill_rect := Rect2((size.x - pill_w) * 0.5, 76.0, pill_w, 21.0)
		if _mode_badge_kind == 1:
			_sb_daily_pill.bg_color = Color(0.06, 0.09, 0.24, 0.92)
			_sb_daily_pill.border_color = Color("#FFD43B", 0.80)
			_sb_daily_pill.draw(ci.get_canvas_item(), pill_rect)
			_draw_centered_outlined_text(ci, _font_bold, pill_rect.get_center(), _mode_badge_text, 11, Color("#FFE475"), Color("#12193B"), 3, 0.8)
		elif _mode_badge_kind == 3:
			if _mode_badge_urgent:
				_sb_daily_pill.bg_color = Color(0.05, 0.24, 0.34, 0.95).lerp(Color(0.18, 0.36, 0.22, 0.96), pulse * 0.4)
				_sb_daily_pill.border_color = Color("#48F0FF").lerp(Color("#FFE46B"), 0.45 + pulse * 0.40)
				var g_scale := 1.0 + 0.03 * pulse
				ci.draw_set_transform(pill_rect.get_center(), 0.0, Vector2(g_scale, g_scale))
				_sb_daily_pill.draw(ci.get_canvas_item(), Rect2(-pill_rect.size * 0.5, pill_rect.size))
				_draw_centered_outlined_text(ci, _font_extrabold, Vector2.ZERO, _mode_badge_text, 11, Color("#FFF7A8"), Color("#06263A"), 3, 0.8)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				_sb_daily_pill.bg_color = Color(0.04, 0.16, 0.28, 0.93)
				_sb_daily_pill.border_color = Color("#3CE8FF", 0.84)
				_sb_daily_pill.draw(ci.get_canvas_item(), pill_rect)
				_draw_centered_outlined_text(ci, _font_bold, pill_rect.get_center(), _mode_badge_text, 11, Color("#9AF6FF"), Color("#061E33"), 3, 0.8)
		elif _mode_badge_urgent:
			_sb_daily_pill.bg_color = Color(0.28, 0.05, 0.10, 0.95).lerp(Color(0.45, 0.10, 0.08, 0.96), pulse * 0.5)
			_sb_daily_pill.border_color = Color("#FF4D3D").lerp(Color("#FFE46B"), 0.35 + pulse * 0.45)
			var p_scale := 1.0 + 0.035 * pulse
			ci.draw_set_transform(pill_rect.get_center(), 0.0, Vector2(p_scale, p_scale))
			_sb_daily_pill.draw(ci.get_canvas_item(), Rect2(-pill_rect.size * 0.5, pill_rect.size))
			_draw_centered_outlined_text(ci, _font_extrabold, Vector2.ZERO, _mode_badge_text, 11, Color("#FFF394"), Color("#3B0804"), 3, 0.8)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			_sb_daily_pill.bg_color = Color(0.11, 0.06, 0.28, 0.92)
			_sb_daily_pill.border_color = Color("#C266FF", 0.85)
			_sb_daily_pill.draw(ci.get_canvas_item(), pill_rect)
			_draw_centered_outlined_text(ci, _font_bold, pill_rect.get_center(), _mode_badge_text, 11, Color("#E7C6FF"), Color("#19093B"), 3, 0.8)
	_draw_chips_pill_text(ci)
	_draw_mult_sign(ci)
	_draw_mult_pill_text(ci)


func _draw_hero_total_score(ci: CanvasItem) -> void:
	var score_val := int(round(_displayed_score))
	var score_text := format_comma_int(score_val)
	var center := Vector2(size.x * 0.5, SCORE_CENTER_LOCAL.y)

	# Velvety Gaussian glow aura behind score (ZERO hard elliptical circle!).
	var base_glow_alpha := 0.18 + _score_flash * 0.30 + _orb_halo_pulse * 0.24
	var glow_col := Color(0.45, 0.72, 1.0, base_glow_alpha).lerp(
		Color(1.0, 0.82, 0.26, base_glow_alpha * 1.25),
		clampf(_score_flash + _orb_halo_pulse * 0.8 + (0.45 if _fever_active else 0.0), 0.0, 1.0)
	)
	_draw_soft_glow(ci, center, Vector2(118.0 + _orb_halo_pulse * 22.0, 34.0 + _orb_halo_pulse * 8.0), glow_col)

	# 54px Kanit-ExtraBold hero score when calm (effortless hierarchy!), 48px during roaring active combos.
	var font_size := 54 if _is_equation_calm() else 48
	var max_w := 268.0
	var measured_w := _font_extrabold.get_string_size(score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if measured_w > max_w and measured_w > 1.0:
		font_size = maxi(30, int(floor(float(font_size) * (max_w / measured_w))))

	var text_col := Color("#FFFFFF").lerp(Color("#FFE875"), clampf(_score_flash * 0.85, 0.0, 0.85))
	ci.draw_set_transform(center, _score_rot, Vector2(_score_scale, _score_scale))
	_draw_centered_outlined_text(ci, _font_extrabold, Vector2.ZERO, score_text, font_size, text_col, Color("#0A102B"), 8, 3.5)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_chips_pill_text(ci: CanvasItem) -> void:
	var calm := _is_equation_calm()
	var rect := Rect2(142.0, 113.0, 102.0, 34.0) if calm else CHIPS_PILL_RECT
	var center := rect.get_center()
	var chips_text := format_comma_int(_display_chips)
	var font_size := _fit_pill_font_size(chips_text, 22 if calm else 34, 16, rect.size.x - 14.0)
	var fill_col := Color(0.86, 0.94, 1.0, 0.88) if calm else Color("#FFFFFF")

	ci.draw_set_transform(center, _chips_rot, Vector2(_chips_scale, _chips_scale))
	_draw_centered_outlined_text(ci, _font_extrabold, Vector2(0.0, -1.5), chips_text, font_size, fill_col, Color("#052459"), 4 if calm else 5, 1.5 if calm else 1.8)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_mult_sign(ci: CanvasItem) -> void:
	var calm := _is_equation_calm()
	var pulse := 0.5 + 0.5 * sin(_time_sec * 6.5)
	var fever_mix := 1.0 if _fever_active else clampf((_display_mult - 1.0) / 5.0, 0.0, 0.85)
	var sign_col := Color(0.74, 0.82, 0.98, 0.72) if calm else Color("#FF4622").lerp(Color("#FFD84D"), 0.28 + fever_mix * 0.55 + pulse * 0.14)
	var sign_center := Vector2(270.0, 130.0) if calm else MULT_SIGN_CENTER

	if not calm:
		var glow_r := 24.0 + fever_mix * 8.0
		_draw_soft_glow(ci, sign_center, Vector2(glow_r, glow_r), Color(sign_col.r, sign_col.g, sign_col.b, 0.40 + fever_mix * 0.24))

	ci.draw_set_transform(sign_center, 0.0, Vector2(_x_scale, _x_scale))
	_draw_centered_outlined_text(ci, _font_extrabold, Vector2(0.0, -1.5), "×", 24 if calm else 38, sign_col, Color("#121B42") if calm else Color("#2E0804"), 4 if calm else 6, 1.5 if calm else 2.2)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_mult_pill_text(ci: CanvasItem) -> void:
	var calm := _is_equation_calm()
	var rect := Rect2(296.0, 113.0, 102.0, 34.0) if calm else MULT_PILL_RECT
	var center := rect.get_center()
	var mult_text := format_mult(_display_mult)
	var font_size := _fit_pill_font_size(mult_text, 22 if calm else 34, 16, rect.size.x - 14.0)
	var text_col := Color(0.90, 0.86, 1.0, 0.88) if calm else (Color("#FFFCE0") if _fever_active else Color("#FFFFFF"))

	ci.draw_set_transform(center, _mult_rot, Vector2(_mult_scale, _mult_scale))
	_draw_centered_outlined_text(ci, _font_extrabold, Vector2(0.0, -1.5), mult_text, font_size, text_col, Color("#24123D") if calm else Color("#4D0804"), 4 if calm else 5, 1.5 if calm else 1.8)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ==============================================================================
# HELPERS: VELVETY GLOWS, CROWN ART, FORMATTING, TYPOGRAPHY
# ==============================================================================

func _draw_soft_glow(ci: CanvasItem, center: Vector2, half_size: Vector2, tint: Color) -> void:
	if _radial_glow_tex == null or tint.a <= 0.002:
		return
	ci.draw_texture_rect(_radial_glow_tex, Rect2(center - half_size, half_size * 2.0), false, tint)


static func _create_radial_glow_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	grad.offsets = PackedFloat32Array([0.0, 0.18, 0.35, 0.52, 0.68, 0.83, 0.95, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.76),
		Color(1.0, 1.0, 1.0, 0.45),
		Color(1.0, 1.0, 1.0, 0.24),
		Color(1.0, 1.0, 1.0, 0.12),
		Color(1.0, 1.0, 1.0, 0.035),
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


static func _create_horizontal_gradient_texture(offsets: PackedFloat32Array, colors: PackedColorArray) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	grad.offsets = offsets
	grad.colors = colors
	var tex := GradientTexture2D.new()
	tex.width = 256
	tex.height = 8
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.gradient = grad
	return tex


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
	ci.draw_colored_polygon(shadow_pts, Color(0.04, 0.02, 0.0, 0.52))

	var outline_loop := body_pts.duplicate()
	outline_loop.append(body_pts[0])
	ci.draw_polyline(outline_loop, Color("#4D2600"), 3.4, true)

	var top_gold := Color("#FFE866").lerp(Color("#FFF9C4"), clampf(glow * 0.35, 0.0, 0.45))
	var mid_gold := Color("#FFC414")
	var bot_gold := Color("#E68A00")
	ci.draw_polygon(body_pts, PackedColorArray([bot_gold, top_gold, mid_gold, top_gold, mid_gold, top_gold, bot_gold]))

	# Glossy left specular facet.
	ci.draw_colored_polygon(
		PackedVector2Array([
			p.call(0.16, 0.80),
			p.call(0.10, 0.40),
			p.call(0.32, 0.60),
			p.call(0.50, 0.22),
			p.call(0.50, 0.80),
		]),
		Color(1.0, 0.97, 0.72, 0.28)
	)

	# Crown base band & tiny opaque jewel dots.
	var band_rect := Rect2(p.call(0.13, 0.74), Vector2(w * 0.74, h * 0.19))
	ci.draw_rect(band_rect, Color("#D67600"), true)
	ci.draw_rect(Rect2(band_rect.position + Vector2(1.0, 0.8), Vector2(band_rect.size.x - 2.0, band_rect.size.y * 0.42)), Color("#FFE87A", 0.55), true)

	ci.draw_circle(p.call(0.50, 0.835), 2.0, Color("#FF405C"))
	ci.draw_circle(p.call(0.49, 0.825), 0.85, Color("#FFD6DE"))
	ci.draw_circle(p.call(0.28, 0.835), 1.5, Color("#30E8FF"))
	ci.draw_circle(p.call(0.72, 0.835), 1.5, Color("#30E8FF"))

	# Gleaming opaque crown-tip spheres.
	var tips: Array[Vector2] = [p.call(0.06, 0.34), p.call(0.50, 0.13), p.call(0.94, 0.34)]
	var tip_rads: Array[float] = [2.4, 2.9, 2.4]
	for i in range(tips.size()):
		var tc := tips[i]
		var tr := tip_rads[i]
		ci.draw_circle(tc, tr + 1.0, Color("#4D2600"))
		ci.draw_circle(tc, tr, Color("#FFD942"))
		ci.draw_circle(tc + Vector2(-tr * 0.28, -tr * 0.28), tr * 0.44, Color("#FFFCE3"))

	if glow > 0.12:
		var sp: Vector2 = p.call(0.50, 0.12)
		var glint := 0.7 + 0.3 * sin(time_sec * 11.0)
		var r_long := (4.8 + glow * 2.2) * glint
		var r_short := 1.3 * glint
		ci.draw_colored_polygon(
			PackedVector2Array([
				sp + Vector2(0.0, -r_long),
				sp + Vector2(r_short, -r_short),
				sp + Vector2(r_long, 0.0),
				sp + Vector2(r_short, r_short),
				sp + Vector2(0.0, r_long),
				sp + Vector2(-r_short, r_short),
				sp + Vector2(-r_long, 0.0),
				sp + Vector2(-r_short, -r_short),
			]),
			Color(1.0, 1.0, 0.90, clampf(glow, 0.0, 1.0))
		)


static func _sample_charge_gradient(t: float) -> Color:
	var c_cyan := Color("#16E0FF")
	var c_magenta := Color("#DF42FF")
	var c_gold := Color("#FFD43B")
	if t < 0.52:
		return c_cyan.lerp(c_magenta, t / 0.52)
	return c_magenta.lerp(c_gold, (t - 0.52) / 0.48)


func _fit_pill_font_size(text: String, max_size: int, min_size: int, max_width: float) -> int:
	if _font_extrabold == null or text.is_empty():
		return max_size
	var w := _font_extrabold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, max_size).x
	if w <= max_width or w <= 1.0:
		return max_size
	return maxi(min_size, int(floor(float(max_size) * (max_width / w))))


static func _step_spring(pos: float, vel: float, target: float, stiffness: float, damping: float, dt: float) -> Vector2:
	var force := (target - pos) * stiffness - vel * damping
	vel += force * dt
	pos += vel * dt
	return Vector2(pos, vel)


static func format_comma_int(value: int) -> String:
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


static func format_mult(mult_val: float) -> String:
	var rounded_int: float = roundf(mult_val)
	if absf(mult_val - rounded_int) < 0.04:
		return format_comma_int(int(rounded_int))
	return "%.1f" % mult_val


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


static func _draw_diamond_outline(ci: CanvasItem, center: Vector2, radius: float, col: Color, width: float) -> void:
	ci.draw_polyline(
		PackedVector2Array([
			center + Vector2(0.0, -radius),
			center + Vector2(radius, 0.0),
			center + Vector2(0.0, radius),
			center + Vector2(-radius, 0.0),
			center + Vector2(0.0, -radius),
		]),
		col,
		width,
		true
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
	shadow_offset_y: float = 2.0
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
		Color(0.02, 0.01, 0.0, 0.58)
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
# INNER CLASSES: FOREGROUND LAYER & CACHED-STYLEBOX TACTILE ARCADE BUTTONS
# ==============================================================================

class _HudForegroundLayer extends Control:
	var hud: HudView

	func _draw() -> void:
		if hud != null:
			hud._draw_foreground(self)


class _ArcadeIconButton extends Control:
	signal activated()

	const ICON_AUDIO := 0
	const ICON_RESTART := 1
	const ICON_HOME := 2
	const ICON_SETTINGS := 3

	var icon_kind: int = ICON_AUDIO
	var _hovered: bool = false
	var _pressed: bool = false
	var _muted: bool = false
	var _spin_angle: float = 0.0
	var _pop_scale: float = 1.0

	var _sb_lip: StyleBoxFlat
	var _sb_face: StyleBoxFlat
	var _sb_gloss: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)

		_sb_lip = StyleBoxFlat.new()
		_sb_lip.bg_color = Color("#090F29")
		_sb_lip.set_corner_radius_all(10)
		_sb_lip.corner_detail = 6
		_sb_lip.shadow_color = Color(0.02, 0.03, 0.10, 0.55)
		_sb_lip.shadow_size = 3
		_sb_lip.shadow_offset = Vector2(0.0, 2.5)

		_sb_face = StyleBoxFlat.new()
		_sb_face.set_corner_radius_all(9)
		_sb_face.corner_detail = 6
		_sb_face.set_border_width_all(1)

		_sb_gloss = StyleBoxFlat.new()
		_sb_gloss.set_corner_radius_all(4)
		_sb_gloss.corner_detail = 4

		set_process(true)

	func _process(delta: float) -> void:
		var dt := minf(delta, 0.05)
		var target_s := 0.92 if _pressed else (1.05 if _hovered else 1.0)
		var dirty := false
		if absf(_pop_scale - target_s) > 0.002:
			_pop_scale = lerpf(_pop_scale, target_s, clampf(18.0 * dt, 0.0, 1.0))
			dirty = true
		if _spin_angle > 0.01:
			_spin_angle = maxf(0.0, _spin_angle - dt * 11.0)
			dirty = true
		if dirty:
			queue_redraw()

	func set_muted_state(muted: bool) -> void:
		_muted = muted
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
						_trigger_activate()
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
					_trigger_activate()
				accept_event()

	func _trigger_activate() -> void:
		_pop_scale = 1.14
		if icon_kind == ICON_RESTART:
			_spin_angle = TAU
		elif icon_kind == ICON_SETTINGS:
			_spin_angle = PI * 0.5
		queue_redraw()
		activated.emit()

	func _draw() -> void:
		var center := size * 0.5
		var local_rect := Rect2(-center, size)
		var press_y := 1.8 if _pressed else 0.0
		var lip_h := 1.4 if _pressed else 3.2
		var cid := get_canvas_item()

		draw_set_transform(center, 0.0, Vector2(_pop_scale, _pop_scale))

		var btn_rect := Rect2(local_rect.position + Vector2(0.0, press_y), Vector2(local_rect.size.x, local_rect.size.y - press_y))
		_sb_lip.draw(cid, btn_rect)

		var face_rect := Rect2(btn_rect.position, Vector2(btn_rect.size.x, btn_rect.size.y - lip_h))
		_sb_face.bg_color = Color(0.12, 0.19, 0.42, 0.92) if _hovered else Color(0.09, 0.14, 0.33, 0.88)
		var rim_col := Color(0.54, 0.74, 1.0, 0.74) if _hovered else Color(0.38, 0.54, 0.90, 0.54)
		if icon_kind == ICON_AUDIO and _muted:
			rim_col = Color("#FF5C6C", 0.78)
		_sb_face.border_color = rim_col
		_sb_face.draw(cid, face_rect)

		var gloss := Rect2(face_rect.position + Vector2(4.0, 2.0), Vector2(face_rect.size.x - 8.0, face_rect.size.y * 0.36))
		_sb_gloss.bg_color = Color(0.75, 0.88, 1.0, 0.16 if _hovered else 0.11)
		_sb_gloss.draw(cid, gloss)

		var icon_center := face_rect.get_center()
		if icon_kind == ICON_AUDIO:
			_draw_audio_icon(icon_center)
		elif icon_kind == ICON_HOME:
			_draw_home_icon(icon_center)
		elif icon_kind == ICON_SETTINGS:
			_draw_settings_icon(icon_center)
		else:
			_draw_restart_icon(icon_center)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_settings_icon(c: Vector2) -> void:
		var col := Color("#FFE57A") if _hovered else Color("#EDF6FF")
		var hole_col := Color(0.12, 0.19, 0.42, 1.0) if _hovered else Color(0.09, 0.14, 0.33, 1.0)
		var rot := _spin_angle
		for i in range(8):
			var a := rot + float(i) * (TAU / 8.0)
			var dir := Vector2(cos(a), sin(a))
			var perp := Vector2(-dir.y, dir.x)
			var p0 := c + dir * 5.4 - perp * 1.9
			var p1 := c + dir * 9.2 - perp * 1.35
			var p2 := c + dir * 9.2 + perp * 1.35
			var p3 := c + dir * 5.4 + perp * 1.9
			draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), col)
		draw_circle(c, 6.4, col)
		draw_circle(c, 2.8, hole_col)

	func _draw_home_icon(c: Vector2) -> void:
		var col := Color("#FFE57A") if _hovered else Color("#EDF6FF")
		var door_col := Color("#121D45")
		# Clean convex pentagon house body + crisp pitched roof chevron + doorway cutout.
		var house := PackedVector2Array([
			c + Vector2(-6.0, -0.4),
			c + Vector2(0.0, -6.2),
			c + Vector2(6.0, -0.4),
			c + Vector2(6.0, 7.2),
			c + Vector2(-6.0, 7.2),
		])
		draw_colored_polygon(house, col)
		var roof := PackedVector2Array([
			c + Vector2(-8.6, 0.2),
			c + Vector2(0.0, -7.8),
			c + Vector2(8.6, 0.2),
		])
		draw_polyline(roof, col, 2.4, true)
		draw_rect(Rect2(c.x - 2.1, c.y + 1.8, 4.2, 5.5), door_col, true)

	func _draw_audio_icon(c: Vector2) -> void:
		var speaker_col := Color("#9FB2D9") if _muted else Color("#EDF6FF")
		var spk := PackedVector2Array([
			c + Vector2(-8.5, -3.2),
			c + Vector2(-4.6, -3.2),
			c + Vector2(0.4, -7.2),
			c + Vector2(0.4, 7.2),
			c + Vector2(-4.6, 3.2),
			c + Vector2(-8.5, 3.2),
		])
		draw_colored_polygon(spk, speaker_col)

		if _muted:
			var x_col := Color("#FF5A6E")
			var xc := c + Vector2(5.6, 0.0)
			draw_line(xc + Vector2(-3.4, -3.4), xc + Vector2(3.4, 3.4), x_col, 2.3, true)
			draw_line(xc + Vector2(-3.4, 3.4), xc + Vector2(3.4, -3.4), x_col, 2.3, true)
		else:
			draw_arc(c + Vector2(0.2, 0.0), 4.8, -0.78, 0.78, 12, Color("#6BE4FF"), 1.9, true)
			draw_arc(c + Vector2(0.2, 0.0), 8.2, -0.84, 0.84, 14, Color("#6BE4FF", 0.78), 1.9, true)

	func _draw_restart_icon(c: Vector2) -> void:
		var col := Color("#FFE57A") if _hovered else Color("#EDF6FF")
		var r := 7.2
		var rot := -_spin_angle
		var start_a := -PI * 0.28 + rot
		var end_a := PI * 1.28 + rot
		draw_arc(c, r, start_a, end_a, 18, col, 2.3, true)

		var tip := c + Vector2(cos(start_a), sin(start_a)) * r
		var tangent := Vector2(-sin(start_a), cos(start_a))
		var outward := Vector2(cos(start_a), sin(start_a))
		var arrow_pts := PackedVector2Array([
			tip + tangent * 2.2 - outward * 0.5,
			tip - tangent * 3.6 + outward * 3.4,
			tip - tangent * 3.6 - outward * 3.4,
		])
		draw_colored_polygon(arrow_pts, col)
