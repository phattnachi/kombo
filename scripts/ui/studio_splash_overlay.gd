class_name StudioSplashOverlay
extends Control

## Animated launch studio splash for SOYA GAMES.
## Matches project.godot boot_splash/bg_color (#0B112C) and boot_splash/image
## (soya_games_boot_splash.png) for a zero-flash transition from OS boot into
## a sleek 2.0s branded intro that cross-fades cleanly into the KOMBO! Title Screen.

signal splash_finished()

const LOGICAL_SIZE := Vector2(540.0, 960.0)
const LOGO_PATH := "res://assets/logo/soya_games_boot_splash.png"
const FONT_BOLD_PATH := "res://assets/fonts/Kanit-Bold.ttf"

const BG_COLOR := Color(0.0431373, 0.0666667, 0.172549, 1.0)
const INTRO_SEC := 0.42
const HOLD_SEC := 1.15
const FADE_OUT_SEC := 0.48
const LOGO_DRAW_SIZE := 272.0

var _logo_tex: Texture2D
var _font_bold: Font
var _radial_glow_tex: GradientTexture2D

var _elapsed: float = 0.0
var _active: bool = false
var _skipping: bool = false
var _skip_alpha: float = 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_assets()
	_init_glow_texture()
	visible = false
	set_process(true)


func _input(event: InputEvent) -> void:
	if not visible or not _active or _skipping:
		return
	var should_skip := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			should_skip = true
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			should_skip = true
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			should_skip = true

	if should_skip:
		get_viewport().set_input_as_handled()
		_skipping = true
		_skip_alpha = modulate.a


func _process(delta: float) -> void:
	if not visible or not _active:
		return
	var dt := minf(delta, 0.05)
	_elapsed += dt

	if _skipping:
		_skip_alpha = move_toward(_skip_alpha, 0.0, dt * 4.5)
		modulate = Color(1.0, 1.0, 1.0, _skip_alpha)
		if _skip_alpha <= 0.01:
			_finish_splash()
			return
		queue_redraw()
		return

	var fade_start := INTRO_SEC + HOLD_SEC
	var total_dur := fade_start + FADE_OUT_SEC
	if _elapsed >= total_dur:
		_finish_splash()
		return

	if _elapsed >= fade_start:
		var ft := clampf((_elapsed - fade_start) / FADE_OUT_SEC, 0.0, 1.0)
		var smooth_ft := ft * ft * (3.0 - 2.0 * ft)
		modulate = Color(1.0, 1.0, 1.0, 1.0 - smooth_ft)
		if ft > 0.25:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		modulate = Color.WHITE

	queue_redraw()


func start_splash() -> void:
	_elapsed = 0.0
	_active = true
	_skipping = false
	_skip_alpha = 1.0
	modulate = Color.WHITE
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func hide_immediate() -> void:
	_active = false
	_skipping = false
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_active() -> bool:
	return _active and visible


func set_preview_time(t_sec: float) -> void:
	_elapsed = maxf(0.0, t_sec)
	_active = true
	_skipping = false
	modulate = Color.WHITE
	visible = true
	queue_redraw()


func _finish_splash() -> void:
	_active = false
	_skipping = false
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash_finished.emit()


func _load_assets() -> void:
	if ResourceLoader.exists(FONT_BOLD_PATH):
		_font_bold = load(FONT_BOLD_PATH) as Font
	if _font_bold == null:
		_font_bold = ThemeDB.fallback_font

	if ResourceLoader.exists(LOGO_PATH):
		_logo_tex = load(LOGO_PATH) as Texture2D
	if _logo_tex == null:
		var abs_path := ProjectSettings.globalize_path(LOGO_PATH)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				_logo_tex = ImageTexture.create_from_image(img)


func _init_glow_texture() -> void:
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.45, 0.70, 0.92, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.62),
		Color(1.0, 1.0, 1.0, 0.28),
		Color(1.0, 1.0, 1.0, 0.08),
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


func _draw() -> void:
	if not visible:
		return
	var view_size := size if (size.x > 10.0 and size.y > 10.0) else LOGICAL_SIZE
	var center := view_size * 0.5

	# Seamless midnight-navy studio backdrop matching OS boot splash.
	draw_rect(Rect2(Vector2.ZERO, view_size), BG_COLOR, true)

	var intro_t := clampf(_elapsed / INTRO_SEC, 0.0, 1.0)
	var ease_out := 1.0 - pow(1.0 - intro_t, 3.0)
	var pulse := 0.5 + 0.5 * sin(_elapsed * 3.4)

	# Velvety cyan-cobalt & subtle warm-gold ambient aura behind the studio emblem.
	if _radial_glow_tex != null:
		var aura_alpha := ease_out * (0.28 + 0.08 * pulse)
		var cyan_half := Vector2(210.0, 210.0) * lerpf(0.82, 1.04, ease_out)
		draw_texture_rect(
			_radial_glow_tex,
			Rect2(center + Vector2(0.0, -24.0) - cyan_half, cyan_half * 2.0),
			false,
			Color(0.16, 0.72, 1.0, aura_alpha)
		)
		var gold_half := Vector2(128.0, 128.0) * lerpf(0.85, 1.02, ease_out)
		draw_texture_rect(
			_radial_glow_tex,
			Rect2(center + Vector2(0.0, -34.0) - gold_half, gold_half * 2.0),
			false,
			Color(1.0, 0.78, 0.28, ease_out * (0.14 + 0.05 * pulse))
		)

	# Crisp SOYA GAMES studio mark + wordmark lockup.
	var logo_scale := lerpf(0.92, 1.0, ease_out)
	var logo_center := center + Vector2(0.0, -22.0)
	if _logo_tex != null:
		var half := Vector2(LOGO_DRAW_SIZE, LOGO_DRAW_SIZE) * 0.5 * logo_scale
		draw_texture_rect(
			_logo_tex,
			Rect2(logo_center - half, half * 2.0),
			false,
			Color(1.0, 1.0, 1.0, lerpf(0.85, 1.0, ease_out))
		)

	# Clean spaced "PRESENTS" studio caption fading up gently below the lockup.
	var cap_t := clampf((_elapsed - 0.14) / 0.34, 0.0, 1.0)
	var cap_ease := 1.0 - pow(1.0 - cap_t, 2.0)
	if cap_ease > 0.01 and _font_bold != null:
		var cap_text := "P  R  E  S  E  N  T  S"
		var cap_size := 13
		var cap_w := _font_bold.get_string_size(cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size).x
		var cap_pos := Vector2(
			center.x - cap_w * 0.5,
			logo_center.y + LOGO_DRAW_SIZE * 0.5 + 34.0 + lerpf(8.0, 0.0, cap_ease)
		)
		draw_string(
			_font_bold,
			cap_pos,
			cap_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			cap_size,
			Color(0.62, 0.84, 1.0, 0.72 * cap_ease)
		)
