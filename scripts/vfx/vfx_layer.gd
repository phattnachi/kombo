class_name VfxLayer
extends Control

## High-impact 60+ FPS single-pass CanvasItem VFX layer for Kombo.
## Renders smooth GPU-quad radial blooms, thick feathered plasma shockwaves,
## blazing line-clear energy corridors, 3D-shaded tumbling beveled jewel cubes
## with directional motion streaks, incandescent 3x3 bomb detonations, high-voltage
## lightning cross surges, smart non-overlapping Balatro pop badges, curved
## flying score orbs, FEVER molten edge aura, and trauma-driven screen shake
## with zero per-particle Node instantiation.

signal score_orb_arrived(points_chunk: int)

const MAX_SHAKE_PX: float = 14.0
const TRAUMA_DECAY: float = 2.15
const LIGHTNING_JITTER_INTERVAL: float = 0.04
const MAX_SHARDS: int = 280
const MAX_SPARKS: int = 340
const MAX_FIRE_PLUMES: int = 80
const MAX_FEVER_EMBERS: int = 36

const POPUP_SAFE_X_MIN: float = 70.0
const POPUP_SAFE_X_MAX: float = 470.0
const POPUP_SAFE_Y_MIN: float = 210.0
const POPUP_SAFE_Y_MAX: float = 630.0
const POPUP_COLLISION_PAD: float = 10.0

const SCORE_GOLD_COLOR: Color = Color("#FFE055")
const SCORE_CYAN_COLOR: Color = Color("#38F0FF")
const LIGHTNING_CYAN: Color = Color("#18D5FF")
const LIGHTNING_GOLD: Color = Color("#FFE46B")

var _font: Font = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Cached procedural GPU textures (built once in _ready for 60+ FPS quad blooms).
var _radial_glow_tex: GradientTexture2D = null
var _radial_ring_wide_tex: GradientTexture2D = null
var _radial_ring_core_tex: GradientTexture2D = null
var _beam_band_v_tex: GradientTexture2D = null
var _beam_band_h_tex: GradientTexture2D = null

var _time: float = 0.0
var _shake_phase: float = 0.0
var _trauma: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO

var _fever_target: float = 0.0
var _fever_intensity: float = 0.0
var _fever_ember_accum: float = 0.0
var _mult_tilt_sign: float = -1.0
var _was_active: bool = false

# Lightweight Dictionary pools (zero per-particle SceneTree nodes).
var _sweeps: Array[Dictionary] = []
var _flashes: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _starbursts: Array[Dictionary] = []
var _lightnings: Array[Dictionary] = []
var _shards: Array[Dictionary] = []
var _fire_plumes: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _score_orbs: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _fever_embers: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = TilePainter.get_badge_font()
	_ensure_textures()
	set_process(true)


func _process(delta: float) -> void:
	var dt: float = clampf(delta, 0.0, 0.05)
	_time += dt

	# Smoothly track FEVER edge aura intensity.
	if absf(_fever_target - _fever_intensity) > 0.0005:
		var rate: float = 8.0 if _fever_target > _fever_intensity else 3.2
		_fever_intensity = lerpf(_fever_intensity, _fever_target, clampf(dt * rate, 0.0, 1.0))
		if _fever_target <= 0.001 and _fever_intensity < 0.004:
			_fever_intensity = 0.0
	else:
		_fever_intensity = _fever_target

	# Decay screen-shake trauma with zero persistent drift.
	if _trauma > 0.0:
		_shake_phase += dt
		_trauma = maxf(0.0, _trauma - dt * TRAUMA_DECAY)
		_recompute_shake_offset()
	elif _shake_offset != Vector2.ZERO:
		_shake_offset = Vector2.ZERO

	_update_fever_embers(dt)
	_update_sweeps(dt)
	_update_flashes(dt)
	_update_rings(dt)
	_update_starbursts(dt)
	_update_lightnings(dt)
	_update_shards(dt)
	_update_fire_plumes(dt)
	_update_sparks(dt)
	_update_score_orbs(dt)
	_update_popups(dt)

	var active_now: bool = _has_visual_activity()
	if active_now or _was_active:
		queue_redraw()
	_was_active = active_now


# ==============================================================================
# PUBLIC API
# ==============================================================================

## Launches blazing white-core + jewel-tinted energy sweeps across every cleared
## row and column with soft feathered corridor glows, sinuous ribbons, and motes.
func spawn_line_clear(
	board_rect: Rect2,
	rows: Array,
	cols: Array,
	cell_size: float,
	accent_color: Color
) -> void:
	if cell_size <= 1.0 or (rows.is_empty() and cols.is_empty()):
		return

	var line_idx: int = 0
	for row_val: Variant in rows:
		var r_idx: int = int(row_val)
		var y_center: float = board_rect.position.y + (float(r_idx) + 0.5) * cell_size
		var dir: float = 1.0 if (line_idx & 1) == 0 else -1.0
		_add_sweep(
			true,
			board_rect.position.x,
			board_rect.end.x,
			y_center,
			cell_size,
			accent_color,
			dir,
			float(line_idx) * 0.018
		)
		_spawn_sweep_motes(
			Vector2(board_rect.position.x, y_center),
			Vector2(board_rect.end.x, y_center),
			cell_size,
			accent_color,
			dir,
			11
		)
		line_idx += 1

	for col_val: Variant in cols:
		var c_idx: int = int(col_val)
		var x_center: float = board_rect.position.x + (float(c_idx) + 0.5) * cell_size
		var dir: float = 1.0 if (line_idx & 1) == 0 else -1.0
		_add_sweep(
			false,
			board_rect.position.y,
			board_rect.end.y,
			x_center,
			cell_size,
			accent_color,
			dir,
			float(line_idx) * 0.018
		)
		_spawn_sweep_motes(
			Vector2(x_center, board_rect.position.y),
			Vector2(x_center, board_rect.end.y),
			cell_size,
			accent_color,
			dir,
			11
		)
		line_idx += 1

	var total_lines: int = rows.size() + cols.size()
	add_trauma(minf(0.42, 0.14 + float(total_lines) * 0.065))


## Bursts scale-varied 3D-shaded tumbling beveled jewel cubes and micro-glints
## (0.11x..0.30x cell_size) in the tile's exact TilePainter palette with
## directional velocity streaks and a blazing white cell pop-flash.
func spawn_cell_shatter(
	cell_center: Vector2,
	color_id: int,
	cell_size: float,
	count: int = 5
) -> void:
	if cell_size <= 1.0:
		return

	var pal: Dictionary = TilePainter.get_palette(color_id)
	var c_top: Color = pal["top"] as Color
	var c_left: Color = pal["left"] as Color
	var c_face: Color = pal["face_top"] as Color
	var c_deep: Color = pal["face_bot"] as Color
	var c_right: Color = pal["right"] as Color
	var c_bottom: Color = pal["bottom"] as Color
	var c_glow: Color = pal["glow"] as Color
	var c_rim: Color = pal["rim"] as Color

	# Initial blazing white cell pop-flash with soft radial bloom.
	_flashes.append({
		"kind": 0, # cell square flash
		"pos": cell_center,
		"size": cell_size,
		"glow": c_glow,
		"core": Color.WHITE,
		"age": 0.0,
		"dur": 0.17,
	})

	var shard_count: int = maxi(1, count)
	var angle_step: float = TAU / float(shard_count)
	var base_angle: float = _rng.randf_range(0.0, TAU)

	for i: int in range(shard_count):
		# Curated size hierarchy: chunky 3D cubes (tier 2), medium cubes (tier 1), micro glints (tier 0).
		var tier: int = 2 if (i % 3 == 0) else (1 if (i % 3 == 1) else 0)
		var rad_ratio: float
		var radial_spd: float
		var lift_spd: float
		if tier == 2:
			rad_ratio = _rng.randf_range(0.24, 0.30)
			radial_spd = _rng.randf_range(105.0, 210.0)
			lift_spd = _rng.randf_range(175.0, 295.0)
		elif tier == 1:
			rad_ratio = _rng.randf_range(0.165, 0.225)
			radial_spd = _rng.randf_range(140.0, 265.0)
			lift_spd = _rng.randf_range(195.0, 330.0)
		else:
			rad_ratio = _rng.randf_range(0.11, 0.145)
			radial_spd = _rng.randf_range(195.0, 360.0)
			lift_spd = _rng.randf_range(210.0, 365.0)

		var ang: float = base_angle + float(i) * angle_step + _rng.randf_range(-0.34, 0.34)
		var vx: float = cos(ang) * radial_spd
		var vy: float = sin(ang) * radial_spd * 0.68 - lift_spd
		var offset: Vector2 = Vector2(
			_rng.randf_range(-0.24, 0.24),
			_rng.randf_range(-0.24, 0.24)
		) * cell_size

		_push_shard({
			"pos": cell_center + offset,
			"vel": Vector2(vx, vy),
			"rot": _rng.randf_range(0.0, TAU),
			"rot_spd": _rng.randf_range(-11.5, 11.5) * (0.85 if tier == 2 else 1.15),
			"tumble": _rng.randf_range(0.0, TAU),
			"tumble_spd": _rng.randf_range(-9.0, 9.0),
			"rad": cell_size * rad_ratio,
			"aspect": _rng.randf_range(0.86, 1.14) if tier >= 1 else _rng.randf_range(0.68, 1.32),
			"tier": tier,
			"top": c_top,
			"left": c_left,
			"face": c_face,
			"deep": c_deep,
			"right": c_right,
			"bottom": c_bottom,
			"glow": c_glow,
			"rim": c_rim,
			"age": 0.0,
			"dur": _rng.randf_range(0.46, 0.56) if tier >= 1 else _rng.randf_range(0.36, 0.46),
		})


## Triggers an incandescent 3x3 bomb blast: layered white-hot solar-gold radial
## bloom spilling 2.4x+ cell radius across neighboring blocks, thick blazing
## plasma shockwave rings, luminous molten fire plumes (zero muddy smoke),
## directional golden energy streaks, scale-varied 3D tumbling debris cubes,
## and heavy camera shake trauma.
func spawn_bomb_explosion(origin_center: Vector2, cell_size: float) -> void:
	if cell_size <= 1.0:
		return

	# 1. Incandescent white-hot -> solar gold -> fiery orange radial core flash & light spill.
	_flashes.append({
		"kind": 1, # bomb 3x3 blast fireball
		"pos": origin_center,
		"size": cell_size * 2.55, # light spill radius reaches ~2.4x-3.1x cell_size
		"glow": Color("#FF6A14"),
		"core": Color("#FFFDF0"),
		"age": 0.0,
		"dur": 0.44,
	})

	# 2. Radiant golden starburst flare at detonation center.
	_starbursts.append({
		"pos": origin_center,
		"r0": cell_size * 0.55,
		"r1": cell_size * 2.10,
		"points": 8,
		"rot": _rng.randf_range(0.0, PI * 0.25),
		"rot_spd": 1.8,
		"outer_col": Color("#FF7E1A"),
		"mid_col": Color("#FFE055"),
		"core_col": Color("#FFFDF2"),
		"age": 0.0,
		"dur": 0.34,
	})

	# 3. Thick blazing multi-layered plasma shockwave rings (GPU feathered annular quads).
	# Primary blazing golden-orange plasma wave.
	_rings.append({
		"pos": origin_center,
		"r0": cell_size * 0.42,
		"r1": cell_size * 2.72,
		"col_a": Color("#FFF7C2"),
		"col_b": Color("#FFAA24"),
		"halo": Color("#FF5E14"),
		"halo_b": Color("#FF3B1A"),
		"intensity": 1.15,
		"delay": 0.0,
		"age": 0.0,
		"dur": 0.44,
	})
	# Secondary rapid incandescent inner plasma ripple.
	_rings.append({
		"pos": origin_center,
		"r0": cell_size * 0.24,
		"r1": cell_size * 1.92,
		"col_a": Color("#FFFFFF"),
		"col_b": Color("#FFCE3A"),
		"halo": Color("#FF941C"),
		"halo_b": Color("#FF5818"),
		"intensity": 0.95,
		"delay": 0.042,
		"age": 0.0,
		"dur": 0.34,
	})

	# 4. Directional fiery golden energy streaks & radiant spark streamers (24).
	var streak_count: int = 18
	for i: int in range(streak_count):
		var ang: float = (TAU * float(i) / float(streak_count)) + _rng.randf_range(-0.14, 0.14)
		var is_long: bool = (i & 1) == 0
		var spd: float = _rng.randf_range(410.0, 740.0) if is_long else _rng.randf_range(240.0, 440.0)
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		var hot_col: Color = Color("#FFF49C").lerp(Color("#FF921F"), _rng.randf_range(0.0, 0.55))
		_push_spark({
			"kind": 1, # fiery golden energy streak
			"pos": origin_center + dir * _rng.randf_range(6.0, cell_size * 0.42),
			"vel": dir * spd,
			"drag": _rng.randf_range(3.6, 5.0),
			"gravity": 120.0,
			"size": _rng.randf_range(3.8, 6.2) if is_long else _rng.randf_range(2.8, 4.4),
			"tail_scale": _rng.randf_range(0.052, 0.082),
			"col": hot_col,
			"tail_col": Color("#FF5414"),
			"delay": 0.0,
			"age": 0.0,
			"dur": _rng.randf_range(0.38, 0.56),
		})

	for g: int in range(8):
		var ang_g: float = (TAU * float(g) / 8.0) + _rng.randf_range(-0.24, 0.24)
		var spd_g: float = _rng.randf_range(160.0, 360.0)
		var dir_g: Vector2 = Vector2(cos(ang_g), sin(ang_g))
		_push_spark({
			"kind": 0, # radiant solar star-mote
			"pos": origin_center + dir_g * _rng.randf_range(8.0, cell_size * 0.55),
			"vel": dir_g * spd_g,
			"drag": 3.2,
			"gravity": -40.0,
			"size": _rng.randf_range(4.0, 6.6),
			"tail_scale": 0.0,
			"col": Color("#FFF28A") if (g & 1) == 0 else Color("#FFA62B"),
			"tail_col": Color.WHITE,
			"delay": _rng.randf_range(0.0, 0.05),
			"age": 0.0,
			"dur": _rng.randf_range(0.36, 0.54),
		})

	# 5. Luminous golden-amber plasma fire plumes (ZERO muddy dark brown smoke!).
	var plume_count: int = 10
	for j: int in range(plume_count):
		if _fire_plumes.size() >= MAX_FIRE_PLUMES:
			_fire_plumes.remove_at(0)
		var ang_p: float = (TAU * float(j) / float(plume_count)) + _rng.randf_range(-0.26, 0.26)
		var spd_p: float = _rng.randf_range(120.0, 290.0)
		var dir_p: Vector2 = Vector2(cos(ang_p), sin(ang_p))
		_fire_plumes.append({
			"pos": origin_center + dir_p * _rng.randf_range(4.0, cell_size * 0.45),
			"vel": dir_p * spd_p + Vector2(0.0, -32.0),
			"drag": _rng.randf_range(4.4, 5.8),
			"r0": cell_size * _rng.randf_range(0.30, 0.46),
			"r1": cell_size * _rng.randf_range(0.66, 0.96),
			"hot": Color("#FFF39E").lerp(Color("#FFBF2E"), _rng.randf_range(0.0, 0.5)),
			"outer": Color("#FF7D1A").lerp(Color("#FF4814"), _rng.randf_range(0.0, 0.65)),
			"age": 0.0,
			"dur": _rng.randf_range(0.38, 0.54),
		})

	# 6. Scale-varied 3D tumbling incandescent debris cubes (bold fiery chunks + sparks).
	var debris_colors: Array[int] = [1, 2, 0] # Solar Gold, Tangerine, Ruby
	var debris_count: int = 12
	for d: int in range(debris_count):
		var pal_id: int = debris_colors[d % debris_colors.size()]
		var pal: Dictionary = TilePainter.get_palette(pal_id)
		var tier: int = 2 if (d % 3 == 0) else (1 if (d % 3 == 1) else 0)
		var rad_ratio: float = (
			_rng.randf_range(0.24, 0.30) if tier == 2
			else (_rng.randf_range(0.16, 0.22) if tier == 1 else _rng.randf_range(0.11, 0.145))
		)
		var ang_d: float = (TAU * float(d) / float(debris_count)) + _rng.randf_range(-0.22, 0.22)
		var spd_d: float = _rng.randf_range(210.0, 440.0) if tier >= 1 else _rng.randf_range(300.0, 540.0)
		var dir_d: Vector2 = Vector2(cos(ang_d), sin(ang_d))
		_push_shard({
			"pos": origin_center + dir_d * _rng.randf_range(4.0, cell_size * 0.42),
			"vel": dir_d * spd_d + Vector2(0.0, -_rng.randf_range(75.0, 180.0)),
			"rot": _rng.randf_range(0.0, TAU),
			"rot_spd": _rng.randf_range(-13.0, 13.0),
			"tumble": _rng.randf_range(0.0, TAU),
			"tumble_spd": _rng.randf_range(-10.0, 10.0),
			"rad": cell_size * rad_ratio,
			"aspect": _rng.randf_range(0.86, 1.14) if tier >= 1 else _rng.randf_range(0.70, 1.30),
			"tier": tier,
			"top": pal["top"] as Color,
			"left": pal["left"] as Color,
			"face": pal["face_top"] as Color,
			"deep": pal["face_bot"] as Color,
			"right": pal["right"] as Color,
			"bottom": pal["bottom"] as Color,
			"glow": pal["glow"] as Color,
			"rim": pal["rim"] as Color,
			"age": 0.0,
			"dur": _rng.randf_range(0.46, 0.60),
		})

	# 7. Heavy detonation camera trauma.
	add_trauma(0.72)


## Triggers a massive commercial-grade electric plasma cross surge: wide feathered
## electric-cyan corridor light spills along row & column, sinuous twin golden-cyan
## wavy energy ribbons, blazing thick white-hot core beams, dual re-jittering
## branching electric lightning arcs, multi-layered radial starburst bloom,
## thick cyan plasma shockwave ring, and streaming golden-cyan spark motes.
func spawn_lightning_cross(
	origin_center: Vector2,
	board_rect: Rect2,
	cell_size: float
) -> void:
	if cell_size <= 1.0:
		return

	var bolt_entry: Dictionary = {
		"origin": origin_center,
		"board_rect": board_rect,
		"cell_size": cell_size,
		"phase": _rng.randf_range(0.0, TAU),
		"age": 0.0,
		"dur": 0.44,
		"jitter_timer": 0.0,
		"polylines": [] as Array,
		"secondary_polylines": [] as Array,
		"branches": [] as Array,
	}
	_rebuild_lightning_geometry(bolt_entry)
	_lightnings.append(bolt_entry)

	# 1. Blazing radial cyan-gold intersection core flash.
	_flashes.append({
		"kind": 2, # lightning core radial surge
		"pos": origin_center,
		"size": cell_size * 2.35,
		"glow": LIGHTNING_CYAN,
		"core": Color("#F5FFFF"),
		"age": 0.0,
		"dur": 0.36,
	})

	# 2. Luminous multi-layered 8-point electric starburst + thick plasma voltage ring.
	_starbursts.append({
		"pos": origin_center,
		"r0": cell_size * 0.56,
		"r1": cell_size * 1.95,
		"points": 8,
		"rot": 0.0,
		"rot_spd": 2.2,
		"outer_col": LIGHTNING_CYAN,
		"mid_col": LIGHTNING_GOLD,
		"core_col": Color.WHITE,
		"age": 0.0,
		"dur": 0.40,
	})
	_rings.append({
		"pos": origin_center,
		"r0": cell_size * 0.32,
		"r1": cell_size * 2.28,
		"col_a": Color("#F2FFFF"),
		"col_b": LIGHTNING_CYAN,
		"halo": Color("#1E96FF"),
		"halo_b": Color("#0B5CFF"),
		"intensity": 1.08,
		"delay": 0.0,
		"age": 0.0,
		"dur": 0.36,
	})

	# 3. 28 bright golden-cyan spark motes & streamers blasting outward along both axes.
	for i: int in range(14):
		var use_gold: bool = (i % 3) == 0
		var ang: float = (TAU * float(i) / 14.0) + _rng.randf_range(-0.18, 0.18)
		var spd: float = _rng.randf_range(320.0, 660.0)
		var dir: Vector2 = Vector2(cos(ang), sin(ang))
		_push_spark({
			"kind": 2, # electric plasma streamer
			"pos": origin_center + dir * _rng.randf_range(4.0, cell_size * 0.32),
			"vel": dir * spd,
			"drag": _rng.randf_range(4.0, 5.8),
			"gravity": 28.0,
			"size": _rng.randf_range(3.0, 5.0),
			"tail_scale": _rng.randf_range(0.050, 0.080),
			"col": LIGHTNING_GOLD if use_gold else Color("#8CF6FF"),
			"tail_col": Color("#FF9E1F") if use_gold else Color("#189CFF"),
			"delay": 0.0,
			"age": 0.0,
			"dur": _rng.randf_range(0.32, 0.48),
		})

	for j: int in range(14):
		var on_horiz: bool = (j & 1) == 0
		var use_gold: bool = (j % 3) == 0
		var spawn_pos: Vector2
		var vel: Vector2
		if on_horiz:
			var px: float = _rng.randf_range(board_rect.position.x + 12.0, board_rect.end.x - 12.0)
			spawn_pos = Vector2(px, origin_center.y + _rng.randf_range(-cell_size * 0.34, cell_size * 0.34))
			var out_x: float = 1.0 if px >= origin_center.x else -1.0
			vel = Vector2(out_x * _rng.randf_range(190.0, 420.0), _rng.randf_range(-130.0, 130.0))
		else:
			var py: float = _rng.randf_range(board_rect.position.y + 12.0, board_rect.end.y - 12.0)
			spawn_pos = Vector2(origin_center.x + _rng.randf_range(-cell_size * 0.34, cell_size * 0.34), py)
			var out_y: float = 1.0 if py >= origin_center.y else -1.0
			vel = Vector2(_rng.randf_range(-130.0, 130.0), out_y * _rng.randf_range(190.0, 420.0))

		var is_mote: bool = (j % 2 == 0)
		_push_spark({
			"kind": 0 if is_mote else 2,
			"pos": spawn_pos,
			"vel": vel,
			"drag": _rng.randf_range(4.2, 6.0),
			"gravity": 16.0,
			"size": _rng.randf_range(3.4, 5.6) if is_mote else _rng.randf_range(2.6, 4.2),
			"tail_scale": 0.0 if is_mote else _rng.randf_range(0.044, 0.066),
			"col": LIGHTNING_GOLD if use_gold else Color("#78F4FF"),
			"tail_col": Color("#FFAA22") if use_gold else Color("#1D8BFF"),
			"delay": _rng.randf_range(0.0, 0.055),
			"age": 0.0,
			"dur": _rng.randf_range(0.30, 0.46),
		})

	# 4. Crisp high-voltage camera trauma.
	add_trauma(0.85)


## Spawns a punchy Balatro-style floating text popup with thick crisp dark
## stroke, drop shadow, optional tilted colored pill badge, automatic 2D
## collision de-overlapping, overshoot scale-in (0.3 -> 1.25 -> 1.0), smooth
## drift, and clean fade (0.85s).
func spawn_floating_text(
	pos: Vector2,
	text: String,
	fill_color: Color,
	font_size: int = 30,
	tilt_deg: float = 0.0,
	badge_bg: Color = Color(0.0, 0.0, 0.0, 0.0)
) -> void:
	if text.is_empty():
		return
	var rim_col: Color = Color("#FFE055") if badge_bg.a > 0.01 else Color.TRANSPARENT
	_spawn_popup_internal(pos, text, fill_color, font_size, tilt_deg, badge_bg, rim_col, 0.0, 0.85, 58.0)


## Spawns a vibrant tilted x2 (cyan-gold) or x3 (magenta-gold) multiplier badge
## automatically de-overlapped against active popups, backed by a thick plasma
## starburst ring and diamond sparkles.
func spawn_multiplier_pop(pos: Vector2, mult_value: int) -> void:
	var clamped_mult: int = maxi(2, mult_value)
	var is_x3: bool = clamped_mult >= 3
	var tilt: float = _mult_tilt_sign * (8.5 if is_x3 else 7.2)
	_mult_tilt_sign *= -1.0

	var bg: Color = Color("#9B147C", 0.96) if is_x3 else Color("#0C6A9A", 0.96)
	var rim: Color = Color("#FFD84D") if is_x3 else Color("#5CEEFF")
	var fill: Color = Color("#FFF4A8") if is_x3 else Color("#EAFCFF")
	var fsize: int = 38 if is_x3 else 34

	var resolved_pos: Vector2 = _spawn_popup_internal(
		pos, "×%d" % clamped_mult, fill, fsize, tilt, bg, rim, 0.0, 0.88, 64.0
	)

	# Radiant plasma starburst ring + 8-point flash locked cleanly behind the badge.
	_rings.append({
		"pos": resolved_pos,
		"r0": 14.0,
		"r1": 66.0 if is_x3 else 54.0,
		"col_a": Color("#FFF3A6") if is_x3 else Color("#D8FCFF"),
		"col_b": Color("#FF44D6") if is_x3 else Color("#1CE2FF"),
		"halo": Color("#D926B8") if is_x3 else Color("#0EA5E9"),
		"halo_b": Color("#8A1696") if is_x3 else Color("#0866B8"),
		"intensity": 0.90,
		"delay": 0.0,
		"age": 0.0,
		"dur": 0.34,
	})
	_starbursts.append({
		"pos": resolved_pos,
		"r0": 16.0,
		"r1": 52.0 if is_x3 else 42.0,
		"points": 8,
		"rot": _rng.randf_range(0.0, PI * 0.25),
		"rot_spd": 3.2 if is_x3 else -2.8,
		"outer_col": Color("#FF46D6") if is_x3 else Color("#24E8FF"),
		"mid_col": Color("#FFE055"),
		"core_col": Color.WHITE,
		"age": 0.0,
		"dur": 0.30,
	})

	var mote_count: int = 8 if is_x3 else 6
	for i: int in range(mote_count):
		var ang: float = (TAU * float(i) / float(mote_count)) + _rng.randf_range(-0.22, 0.22)
		var spd: float = _rng.randf_range(95.0, 190.0)
		_push_spark({
			"kind": 0, # diamond sparkle mote
			"pos": resolved_pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"drag": 4.2,
			"gravity": -18.0,
			"size": _rng.randf_range(3.6, 5.8),
			"tail_scale": 0.0,
			"col": Color("#FFE46B") if (i & 1) == 0 else (Color("#FF6AE5") if is_x3 else Color("#5CEEFF")),
			"tail_col": Color.WHITE,
			"delay": 0.0,
			"age": 0.0,
			"dur": _rng.randf_range(0.32, 0.48),
		})


## Spawns dramatic center-board callout banners (DOUBLE!, TRIPLE!, MEGA CLEAR!,
## COMBO xN!, FEVER MODE!) stacked cleanly with automatic collision resolution
## and staggered punchy cadence.
func spawn_combo_banner(
	board_center: Vector2,
	combo_streak: int,
	lines_cleared: int,
	fever_ignited: bool
) -> void:
	var entries: Array[Dictionary] = []

	if fever_ignited:
		entries.append({
			"text": "FEVER MODE!",
			"fill": Color("#FFFBE0"),
			"bg": Color("#D41E2E", 0.96),
			"rim": Color("#FFE44D"),
			"size": 42,
			"tilt": -2.4,
			"dur": 1.02,
		})

	if lines_cleared >= 4:
		entries.append({
			"text": "MEGA CLEAR!",
			"fill": Color("#FFFBE0"),
			"bg": Color("#B81466", 0.96),
			"rim": Color("#FFE14D"),
			"size": 40,
			"tilt": 3.2,
			"dur": 0.96,
		})
	elif lines_cleared == 3:
		entries.append({
			"text": "TRIPLE!",
			"fill": Color("#FFF9CC"),
			"bg": Color("#DB5414", 0.96),
			"rim": Color("#FFDE4A"),
			"size": 38,
			"tilt": -3.6,
			"dur": 0.92,
		})
	elif lines_cleared == 2:
		entries.append({
			"text": "DOUBLE!",
			"fill": Color("#EAFCFF"),
			"bg": Color("#1372BA", 0.96),
			"rim": Color("#4CF2FF"),
			"size": 34,
			"tilt": -3.2,
			"dur": 0.88,
		})

	if combo_streak >= 2:
		var combo_tilt: float = 4.2 if (entries.is_empty() or (entries[entries.size() - 1]["tilt"] as float) < 0.0) else -4.2
		var combo_fsize: int = clampi(28 + combo_streak * 2, 30, 40)
		entries.append({
			"text": "COMBO ×%d!" % combo_streak,
			"fill": Color("#FFE875") if combo_streak < 5 else Color("#FFFFFF"),
			"bg": Color("#C91C3A", 0.96),
			"rim": Color("#FFD447"),
			"size": combo_fsize,
			"tilt": combo_tilt,
			"dur": 0.92,
		})

	if entries.is_empty():
		return

	var total_h: float = 0.0
	var heights: Array[float] = []
	for item_h: Dictionary in entries:
		var fs: int = item_h["size"] as int
		var pill_h: float = float(fs) * 0.96 + clampf(float(fs) * 0.17, 5.0, 9.0) * 2.0
		heights.append(pill_h)
		total_h += pill_h
	var gap: float = 20.0
	total_h += float(maxi(0, entries.size() - 1)) * gap

	var cur_y: float = board_center.y - total_h * 0.5
	for idx: int in range(entries.size()):
		var item: Dictionary = entries[idx]
		var ph: float = heights[idx]
		var spawn_pos: Vector2 = Vector2(board_center.x, cur_y + ph * 0.5)
		cur_y += ph + gap
		_spawn_popup_internal(
			spawn_pos,
			item["text"] as String,
			item["fill"] as Color,
			item["size"] as int,
			item["tilt"] as float,
			item["bg"] as Color,
			item["rim"] as Color,
			float(idx) * 0.065,
			item["dur"] as float,
			54.0
		)

	if fever_ignited:
		_rings.append({
			"pos": board_center,
			"r0": 30.0,
			"r1": 225.0,
			"col_a": Color("#FFF4B8"),
			"col_b": Color("#FF8E1C"),
			"halo": Color("#FF5618"),
			"halo_b": Color("#E0201C"),
			"intensity": 1.10,
			"delay": 0.0,
			"age": 0.0,
			"dur": 0.48,
		})
		_starbursts.append({
			"pos": board_center,
			"r0": 28.0,
			"r1": 120.0,
			"points": 8,
			"rot": 0.0,
			"rot_spd": 2.1,
			"outer_col": Color("#FF5A1C"),
			"mid_col": Color("#FFE14D"),
			"core_col": Color.WHITE,
			"age": 0.0,
			"dur": 0.42,
		})
		for s: int in range(14):
			var ang: float = (TAU * float(s) / 14.0) + _rng.randf_range(-0.18, 0.18)
			var spd: float = _rng.randf_range(160.0, 340.0)
			_push_spark({
				"kind": 0,
				"pos": board_center,
				"vel": Vector2(cos(ang), sin(ang)) * spd,
				"drag": 3.4,
				"gravity": -60.0,
				"size": _rng.randf_range(4.2, 6.8),
				"tail_scale": 0.0,
				"col": Color("#FFE659") if (s & 1) == 0 else Color("#FF6A2B"),
				"tail_col": Color.WHITE,
				"delay": 0.0,
				"age": 0.0,
				"dur": _rng.randf_range(0.45, 0.68),
			})
		add_trauma(0.50)


## Launches 5-12 luminous golden-cyan score orbs along staggered curved
## quadratic Bezier arcs directly into target_pos, emitting score_orb_arrived
## as each orb lands so the HUD score counter punches in sync.
func spawn_score_orbs(
	from_positions: Array[Vector2],
	target_pos: Vector2,
	total_points: int,
	color: Color
) -> void:
	if from_positions.is_empty():
		if total_points > 0:
			score_orb_arrived.emit(total_points)
		return

	var orb_count: int = clampi(from_positions.size(), 5, 12)
	var safe_points: int = maxi(0, total_points)
	var base_chunk: int = safe_points / orb_count
	var remainder: int = safe_points % orb_count

	for i: int in range(orb_count):
		var src_idx: int = int(floor(float(i) * float(from_positions.size()) / float(orb_count)))
		var p0: Vector2 = from_positions[clampi(src_idx, 0, from_positions.size() - 1)]
		p0 += Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-10.0, 10.0))

		var to_target: Vector2 = target_pos - p0
		var dist: float = maxf(40.0, to_target.length())
		var dir_norm: Vector2 = to_target / dist
		var perp: Vector2 = Vector2(-dir_norm.y, dir_norm.x)
		var fan_side: float = -1.0 if (i & 1) == 0 else 1.0
		var arc_bow: float = clampf(dist * _rng.randf_range(0.24, 0.44), 56.0, 155.0) * fan_side
		var p1: Vector2 = p0.lerp(target_pos, _rng.randf_range(0.36, 0.56)) + perp * arc_bow + Vector2(0.0, -28.0)

		var blend_target: Color = SCORE_GOLD_COLOR if (i & 1) == 0 else SCORE_CYAN_COLOR
		var orb_col: Color = color.lerp(blend_target, 0.72)
		orb_col.a = 1.0

		var pts_chunk: int = base_chunk + (1 if i < remainder else 0)
		_score_orbs.append({
			"p0": p0,
			"p1": p1,
			"p2": target_pos,
			"pos": p0,
			"col": orb_col,
			"points": pts_chunk,
			"delay": float(i) * 0.030,
			"age": 0.0,
			"dur": _rng.randf_range(0.45, 0.56),
			"trail": PackedVector2Array([p0]),
		})


## Controls the pulsing molten gold-crimson FEVER edge aura & rising edge embers
## (0.0 = off, 1.0 = full blaze). Never obscures the central 8x8 board.
func set_fever_intensity(intensity: float) -> void:
	_fever_target = clampf(intensity, 0.0, 1.0)
	if _fever_target > _fever_intensity and _fever_intensity < 0.01:
		_fever_intensity = _fever_target * 0.35
	queue_redraw()


## Adds camera shake trauma (clamped to [0.0, 1.0]).
func add_trauma(amount: float) -> void:
	if amount <= 0.0:
		return
	var was_zero: bool = _trauma <= 0.0001
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	if was_zero:
		_shake_phase += 0.17
	_recompute_shake_offset()


## Returns the current trauma-driven screen shake offset (Vector2.ZERO at rest).
func get_shake_offset() -> Vector2:
	return _shake_offset


## Returns total number of live visual elements across all pools (for FPS stress tests).
func get_active_particle_count() -> int:
	return (
		_sweeps.size()
		+ _flashes.size()
		+ _rings.size()
		+ _starbursts.size()
		+ _lightnings.size()
		+ _shards.size()
		+ _fire_plumes.size()
		+ _sparks.size()
		+ _score_orbs.size()
		+ _popups.size()
		+ _fever_embers.size()
	)


## Cleanly resets all active particles, trauma, and FEVER state.
func clear_all() -> void:
	_sweeps.clear()
	_flashes.clear()
	_rings.clear()
	_starbursts.clear()
	_lightnings.clear()
	_shards.clear()
	_fire_plumes.clear()
	_sparks.clear()
	_score_orbs.clear()
	_popups.clear()
	_fever_embers.clear()
	_trauma = 0.0
	_shake_offset = Vector2.ZERO
	_fever_target = 0.0
	_fever_intensity = 0.0
	_fever_ember_accum = 0.0
	queue_redraw()


# ==============================================================================
# UPDATE LOOPS
# ==============================================================================

func _has_visual_activity() -> bool:
	return _fever_intensity > 0.004 or get_active_particle_count() > 0


func _recompute_shake_offset() -> void:
	if _trauma <= 0.0001:
		_shake_offset = Vector2.ZERO
		return
	var power: float = _trauma * _trauma
	var sx: float = sin(_shake_phase * 47.0 + 1.1) * 0.62 + sin(_shake_phase * 89.0 + 3.7) * 0.38
	var sy: float = cos(_shake_phase * 53.0 + 2.3) * 0.62 + sin(_shake_phase * 97.0 + 0.5) * 0.38
	_shake_offset = Vector2(sx, sy) * (MAX_SHAKE_PX * power)


func _update_fever_embers(dt: float) -> void:
	if _fever_intensity > 0.05:
		var vp: Vector2 = _get_canvas_size()
		var spawn_rate: float = 22.0 * _fever_intensity
		_fever_ember_accum += dt * spawn_rate
		while _fever_ember_accum >= 1.0:
			_fever_ember_accum -= 1.0
			if _fever_embers.size() >= MAX_FEVER_EMBERS:
				break
			var on_left: bool = _rng.randf() < 0.5
			var edge_x: float = _rng.randf_range(4.0, 28.0) if on_left else _rng.randf_range(vp.x - 28.0, vp.x - 4.0)
			var start_y: float = _rng.randf_range(vp.y * 0.25, vp.y + 10.0)
			_fever_embers.append({
				"x_base": edge_x,
				"x": edge_x,
				"y": start_y,
				"vy": -_rng.randf_range(75.0, 175.0),
				"sway_amp": _rng.randf_range(3.5, 9.5),
				"sway_freq": _rng.randf_range(3.2, 6.2),
				"phase": _rng.randf_range(0.0, TAU),
				"rad": _rng.randf_range(2.2, 4.6),
				"col": Color("#FFE659").lerp(Color("#FF5822"), _rng.randf_range(0.0, 0.55)),
				"age": 0.0,
				"dur": _rng.randf_range(1.1, 1.9),
			})
	else:
		_fever_ember_accum = 0.0

	var i: int = _fever_embers.size() - 1
	while i >= 0:
		var e: Dictionary = _fever_embers[i]
		var age: float = (e["age"] as float) + dt
		var dur: float = e["dur"] as float
		if age >= dur:
			_swap_pop(_fever_embers, i)
		else:
			e["age"] = age
			e["y"] = (e["y"] as float) + (e["vy"] as float) * dt
			var sway: float = sin(age * (e["sway_freq"] as float) + (e["phase"] as float)) * (e["sway_amp"] as float)
			e["x"] = (e["x_base"] as float) + sway
		i -= 1


func _update_sweeps(dt: float) -> void:
	var i: int = _sweeps.size() - 1
	while i >= 0:
		var s: Dictionary = _sweeps[i]
		var delay: float = s["delay"] as float
		if delay > 0.0:
			s["delay"] = delay - dt
			i -= 1
			continue
		var age: float = (s["age"] as float) + dt
		if age >= (s["dur"] as float):
			_sweeps.remove_at(i)
		else:
			s["age"] = age
		i -= 1


func _update_flashes(dt: float) -> void:
	var i: int = _flashes.size() - 1
	while i >= 0:
		var f: Dictionary = _flashes[i]
		var age: float = (f["age"] as float) + dt
		if age >= (f["dur"] as float):
			_swap_pop(_flashes, i)
		else:
			f["age"] = age
		i -= 1


func _update_rings(dt: float) -> void:
	var i: int = _rings.size() - 1
	while i >= 0:
		var ring: Dictionary = _rings[i]
		var delay: float = ring["delay"] as float
		if delay > 0.0:
			ring["delay"] = delay - dt
			i -= 1
			continue
		var age: float = (ring["age"] as float) + dt
		if age >= (ring["dur"] as float):
			_swap_pop(_rings, i)
		else:
			ring["age"] = age
		i -= 1


func _update_starbursts(dt: float) -> void:
	var i: int = _starbursts.size() - 1
	while i >= 0:
		var sb: Dictionary = _starbursts[i]
		var age: float = (sb["age"] as float) + dt
		if age >= (sb["dur"] as float):
			_swap_pop(_starbursts, i)
		else:
			sb["age"] = age
			sb["rot"] = (sb["rot"] as float) + (sb["rot_spd"] as float) * dt
		i -= 1


func _update_lightnings(dt: float) -> void:
	var i: int = _lightnings.size() - 1
	while i >= 0:
		var bolt: Dictionary = _lightnings[i]
		var age: float = (bolt["age"] as float) + dt
		if age >= (bolt["dur"] as float):
			_lightnings.remove_at(i)
		else:
			bolt["age"] = age
			var j_timer: float = (bolt["jitter_timer"] as float) + dt
			if j_timer >= LIGHTNING_JITTER_INTERVAL:
				j_timer -= LIGHTNING_JITTER_INTERVAL
				_rebuild_lightning_geometry(bolt)
			bolt["jitter_timer"] = j_timer
		i -= 1


func _update_shards(dt: float) -> void:
	var drag_factor: float = exp(-1.28 * dt)
	var i: int = _shards.size() - 1
	while i >= 0:
		var sh: Dictionary = _shards[i]
		var age: float = (sh["age"] as float) + dt
		if age >= (sh["dur"] as float):
			_swap_pop(_shards, i)
		else:
			sh["age"] = age
			var vel: Vector2 = (sh["vel"] as Vector2) * drag_factor
			vel.y += 820.0 * dt
			sh["vel"] = vel
			sh["pos"] = (sh["pos"] as Vector2) + vel * dt
			sh["rot"] = (sh["rot"] as float) + (sh["rot_spd"] as float) * dt
			sh["tumble"] = (sh["tumble"] as float) + (sh["tumble_spd"] as float) * dt
		i -= 1


func _update_fire_plumes(dt: float) -> void:
	var i: int = _fire_plumes.size() - 1
	while i >= 0:
		var orb: Dictionary = _fire_plumes[i]
		var age: float = (orb["age"] as float) + dt
		if age >= (orb["dur"] as float):
			_swap_pop(_fire_plumes, i)
		else:
			orb["age"] = age
			var drag: float = exp(-(orb["drag"] as float) * dt)
			var vel: Vector2 = (orb["vel"] as Vector2) * drag
			vel.y -= 34.0 * dt
			orb["vel"] = vel
			orb["pos"] = (orb["pos"] as Vector2) + vel * dt
		i -= 1


func _update_sparks(dt: float) -> void:
	var i: int = _sparks.size() - 1
	while i >= 0:
		var sp: Dictionary = _sparks[i]
		var delay: float = sp["delay"] as float
		if delay > 0.0:
			sp["delay"] = delay - dt
			i -= 1
			continue
		var age: float = (sp["age"] as float) + dt
		if age >= (sp["dur"] as float):
			_swap_pop(_sparks, i)
		else:
			sp["age"] = age
			var drag: float = exp(-(sp["drag"] as float) * dt)
			var vel: Vector2 = (sp["vel"] as Vector2) * drag
			vel.y += (sp["gravity"] as float) * dt
			sp["vel"] = vel
			sp["pos"] = (sp["pos"] as Vector2) + vel * dt
		i -= 1


func _update_score_orbs(dt: float) -> void:
	var i: int = _score_orbs.size() - 1
	while i >= 0:
		var orb: Dictionary = _score_orbs[i]
		var delay: float = orb["delay"] as float
		if delay > 0.0:
			orb["delay"] = delay - dt
			i -= 1
			continue

		var age: float = (orb["age"] as float) + dt
		var dur: float = orb["dur"] as float
		if age >= dur:
			var target: Vector2 = orb["p2"] as Vector2
			var pts: int = orb["points"] as int
			var col: Color = orb["col"] as Color
			_score_orbs.remove_at(i)
			_spawn_orb_arrival_burst(target, col)
			score_orb_arrived.emit(pts)
		else:
			orb["age"] = age
			var t_raw: float = clampf(age / dur, 0.0, 1.0)
			var t_eased: float = t_raw * t_raw * (2.4 - 1.4 * t_raw)
			var p0: Vector2 = orb["p0"] as Vector2
			var p1: Vector2 = orb["p1"] as Vector2
			var p2: Vector2 = orb["p2"] as Vector2
			var inv: float = 1.0 - t_eased
			var cur_pos: Vector2 = (inv * inv) * p0 + (2.0 * inv * t_eased) * p1 + (t_eased * t_eased) * p2
			orb["pos"] = cur_pos

			var trail: PackedVector2Array = orb["trail"] as PackedVector2Array
			trail.append(cur_pos)
			if trail.size() > 10:
				trail.remove_at(0)
			orb["trail"] = trail
		i -= 1


func _update_popups(dt: float) -> void:
	var i: int = _popups.size() - 1
	while i >= 0:
		var pop: Dictionary = _popups[i]
		var delay: float = pop["delay"] as float
		if delay > 0.0:
			pop["delay"] = delay - dt
			i -= 1
			continue
		var age: float = (pop["age"] as float) + dt
		if age >= (pop["dur"] as float):
			_popups.remove_at(i)
		else:
			pop["age"] = age
		i -= 1


# ==============================================================================
# SINGLE-PASS RENDER LOOP
# ==============================================================================

func _draw() -> void:
	_ensure_textures()

	if _fever_intensity > 0.004 or not _fever_embers.is_empty():
		_draw_fever_aura()

	if not _flashes.is_empty():
		_draw_flashes()

	if not _sweeps.is_empty():
		_draw_sweeps()

	if not _fire_plumes.is_empty():
		_draw_fire_plumes()

	if not _rings.is_empty():
		_draw_rings()

	if not _lightnings.is_empty():
		_draw_lightnings()

	if not _starbursts.is_empty():
		_draw_starbursts()

	if not _shards.is_empty():
		_draw_shards()

	if not _sparks.is_empty():
		_draw_sparks()

	if not _score_orbs.is_empty():
		_draw_score_orbs()

	if not _popups.is_empty():
		_draw_popups()


# ==============================================================================
# DRAW SUB-PASSES
# ==============================================================================

func _draw_fever_aura() -> void:
	var vp: Vector2 = _get_canvas_size()
	var w: float = vp.x
	var h: float = vp.y
	if w <= 8.0 or h <= 8.0:
		return

	if _fever_intensity > 0.004:
		var pulse: float = 0.78 + 0.22 * sin(_time * 5.2) + 0.08 * sin(_time * 10.7)
		var strength: float = clampf(_fever_intensity * pulse, 0.0, 1.0)
		var side_band: float = clampf(w * 0.062, 22.0, 34.0)
		var vert_band: float = clampf(h * 0.052, 32.0, 50.0)

		var outer_crimson: Color = Color(1.0, 0.24, 0.10, 0.30 * strength)
		var outer_gold: Color = Color(1.0, 0.66, 0.14, 0.28 * strength)
		var clear_col: Color = Color(1.0, 0.42, 0.12, 0.0)

		draw_polygon(
			PackedVector2Array([Vector2(0.0, 0.0), Vector2(side_band, 0.0), Vector2(side_band, h), Vector2(0.0, h)]),
			PackedColorArray([outer_crimson, clear_col, clear_col, outer_gold])
		)
		draw_polygon(
			PackedVector2Array([Vector2(w - side_band, 0.0), Vector2(w, 0.0), Vector2(w, h), Vector2(w - side_band, h)]),
			PackedColorArray([clear_col, outer_gold, outer_crimson, clear_col])
		)
		draw_polygon(
			PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w, vert_band), Vector2(0.0, vert_band)]),
			PackedColorArray([outer_crimson, outer_gold, clear_col, clear_col])
		)
		draw_polygon(
			PackedVector2Array([Vector2(0.0, h - vert_band), Vector2(w, h - vert_band), Vector2(w, h), Vector2(0.0, h)]),
			PackedColorArray([clear_col, clear_col, outer_crimson, outer_gold])
		)

		var rim_col: Color = Color("#FFCA3A").lerp(Color("#FF4D1F"), 0.5 + 0.5 * sin(_time * 6.4))
		rim_col.a = 0.55 * strength
		draw_rect(Rect2(Vector2(1.5, 1.5), vp - Vector2(3.0, 3.0)), rim_col, false, 3.0, true)

	for e: Dictionary in _fever_embers:
		var t: float = clampf((e["age"] as float) / (e["dur"] as float), 0.0, 1.0)
		var env: float = sin(t * PI)
		var flicker: float = 0.72 + 0.28 * sin(_time * 18.0 + (e["phase"] as float))
		var a: float = env * flicker * maxf(_fever_intensity, 0.35)
		if a <= 0.01:
			continue
		var pt: Vector2 = Vector2(e["x"] as float, e["y"] as float)
		var rad: float = (e["rad"] as float) * (0.75 + 0.35 * env)
		var c: Color = e["col"] as Color
		_draw_radial_glow(pt, rad * 3.8, Color(c.r, c.g, c.b, 0.42 * a))
		_draw_radial_glow(pt, rad * 1.6, Color(1.0, 0.96, 0.76, 0.96 * a))


func _draw_flashes() -> void:
	for f: Dictionary in _flashes:
		var t: float = clampf((f["age"] as float) / (f["dur"] as float), 0.0, 1.0)
		var pos: Vector2 = f["pos"] as Vector2
		var sz: float = f["size"] as float
		var glow_col: Color = f["glow"] as Color
		var core_col: Color = f["core"] as Color
		var kind: int = f["kind"] as int

		if kind == 0:
			# Crisp cell pop-flash with soft radial halo before 3D jewel cubes scatter.
			var alpha: float = (1.0 - t) * (1.0 - t)
			var sc: float = lerpf(0.88, 1.24, _ease_out_cubic(t))
			var cur_sz: float = sz * sc
			_draw_radial_glow(pos, cur_sz * 1.15, Color(glow_col.r, glow_col.g, glow_col.b, 0.56 * alpha))
			var r: Rect2 = Rect2(pos - Vector2(cur_sz, cur_sz) * 0.48, Vector2(cur_sz, cur_sz) * 0.96)
			draw_rect(r, Color(core_col.r, core_col.g, core_col.b, 0.84 * alpha), true)
		elif kind == 1:
			# Incandescent 3x3 bomb fireball: layered smooth radial blooms extending 2.4x+ cell_size
			# to illuminate neighboring intact blocks — zero hard circle discs!
			var ease_t: float = _ease_out_cubic(t)
			var spill_alpha: float = pow(1.0 - t, 1.35)
			var gold_alpha: float = pow(1.0 - t, 1.55)
			var core_alpha: float = pow(1.0 - t, 1.85)
			var spill_r: float = sz * lerpf(0.82, 1.36, ease_t)

			# Wide fiery orange ambient light spill over surrounding intact blocks.
			_draw_radial_glow(pos, spill_r * 1.18, Color(1.0, 0.38, 0.08, 0.56 * spill_alpha))
			# Radiant molten amber-orange outer fireball.
			_draw_radial_glow(pos, spill_r * 0.88, Color(1.0, 0.62, 0.12, 0.78 * gold_alpha))
			# Blazing solar-gold inner plasma core.
			_draw_radial_glow(pos, spill_r * 0.58, Color(1.0, 0.88, 0.34, 0.94 * gold_alpha))
			# Incandescent white-hot center flash.
			var hot_r: float = spill_r * lerpf(0.46, 0.16, t)
			_draw_radial_glow(pos, hot_r, Color(core_col.r, core_col.g, core_col.b, 1.0 * core_alpha))
		else:
			# High-voltage lightning intersection radial bloom.
			var ease_t: float = _ease_out_cubic(t)
			var outer_a: float = pow(1.0 - t, 1.35)
			var core_a: float = pow(1.0 - t, 1.70)
			var bloom_r: float = sz * lerpf(0.75, 1.24, ease_t)

			_draw_radial_glow(pos, bloom_r * 1.15, Color(0.10, 0.62, 1.0, 0.54 * outer_a))
			_draw_radial_glow(pos, bloom_r * 0.78, Color(0.24, 0.95, 1.0, 0.78 * outer_a))
			_draw_radial_glow(pos, bloom_r * 0.48, Color(1.0, 0.92, 0.52, 0.74 * core_a))
			_draw_radial_glow(pos, bloom_r * 0.32, Color(core_col.r, core_col.g, core_col.b, 1.0 * core_a))


func _draw_sweeps() -> void:
	for s: Dictionary in _sweeps:
		if (s["delay"] as float) > 0.0:
			continue
		var t: float = clampf((s["age"] as float) / (s["dur"] as float), 0.0, 1.0)
		var is_horiz: bool = s["horiz"] as bool
		var span_a: float = s["a"] as float
		var span_b: float = s["b"] as float
		var axis_pos: float = s["axis"] as float
		var cell_sz: float = s["cell_size"] as float
		var accent: Color = s["col"] as Color
		var dir: float = s["dir"] as float

		var head_t: float = _ease_out_cubic(clampf(t / 0.46, 0.0, 1.0))
		var tail_t: float = _ease_in_quad(clampf((t - 0.36) / 0.64, 0.0, 1.0))
		var start_p: float = lerpf(span_a, span_b, tail_t) if dir > 0.0 else lerpf(span_b, span_a, tail_t)
		var end_p: float = lerpf(span_a, span_b, head_t) if dir > 0.0 else lerpf(span_b, span_a, head_t)
		var lo: float = minf(start_p, end_p)
		var hi: float = maxf(start_p, end_p)
		if hi - lo <= 2.0:
			continue

		var fade: float = 1.0 - _ease_in_quad(clampf((t - 0.26) / 0.74, 0.0, 1.0))
		var width_env: float = lerpf(1.05, 0.22, _ease_in_quad(t)) * (0.76 + 0.24 * sin(minf(t * 2.4, 1.0) * PI * 0.5))

		# Smooth GPU feathered corridor light spill.
		_draw_feathered_corridor_band(
			is_horiz, lo, hi, axis_pos, cell_sz * 1.65 * width_env,
			Color(accent.r, accent.g, accent.b, 0.48 * fade)
		)
		var mid_base: Color = accent.lerp(Color.WHITE, 0.32)
		_draw_feathered_corridor_band(
			is_horiz, lo, hi, axis_pos, cell_sz * 0.82 * width_env,
			Color(mid_base.r, mid_base.g, mid_base.b, 0.78 * fade)
		)

		_draw_sweep_ribbons(is_horiz, lo, hi, axis_pos, cell_sz * 0.34 * width_env, accent, fade, s["phase"] as float)
		_draw_tapered_beam_band(is_horiz, lo, hi, axis_pos, cell_sz * 0.24 * width_env, Color(1.0, 1.0, 1.0, 0.94 * fade))

		if t < 0.62:
			var flare_alpha: float = 1.0 - t / 0.62
			var head_pt: Vector2 = Vector2(end_p, axis_pos) if is_horiz else Vector2(axis_pos, end_p)
			_draw_radial_glow(head_pt, cell_sz * 0.95 * flare_alpha, Color(accent.r, accent.g, accent.b, 0.62 * flare_alpha))
			_draw_radial_glow(head_pt, cell_sz * 0.42 * flare_alpha, Color(1.0, 1.0, 0.95, 0.96 * flare_alpha))
			_draw_four_point_star(
				head_pt,
				cell_sz * 0.54 * flare_alpha,
				cell_sz * 0.11 * flare_alpha,
				Color(1.0, 1.0, 0.92, 0.92 * flare_alpha)
			)


func _draw_feathered_corridor_band(
	is_horiz: bool,
	lo: float,
	hi: float,
	axis_pos: float,
	thickness: float,
	col: Color
) -> void:
	var span: float = hi - lo
	if span <= 2.0 or thickness <= 1.0 or col.a <= 0.005:
		return
	var half_t: float = thickness * 0.5
	if is_horiz:
		draw_texture_rect(
			_beam_band_v_tex,
			Rect2(lo, axis_pos - half_t, span, thickness),
			false,
			col
		)
	else:
		draw_texture_rect(
			_beam_band_h_tex,
			Rect2(axis_pos - half_t, lo, thickness, span),
			false,
			col
		)


func _draw_tapered_beam_band(
	is_horiz: bool,
	lo: float,
	hi: float,
	axis_pos: float,
	thickness: float,
	col: Color
) -> void:
	var span: float = hi - lo
	if span <= 2.0 or thickness <= 0.5:
		return
	var half_t: float = thickness * 0.5
	var cap: float = minf(span * 0.26, 32.0)
	var c_clear: Color = Color(col.r, col.g, col.b, 0.0)
	var m_lo: float = lo + cap
	var m_hi: float = hi - cap

	if is_horiz:
		draw_polygon(
			PackedVector2Array([
				Vector2(lo, axis_pos - half_t * 0.35),
				Vector2(m_lo, axis_pos - half_t),
				Vector2(m_lo, axis_pos + half_t),
				Vector2(lo, axis_pos + half_t * 0.35),
			]),
			PackedColorArray([c_clear, col, col, c_clear])
		)
		if m_hi > m_lo:
			draw_rect(Rect2(m_lo, axis_pos - half_t, m_hi - m_lo, thickness), col, true)
		draw_polygon(
			PackedVector2Array([
				Vector2(m_hi, axis_pos - half_t),
				Vector2(hi, axis_pos - half_t * 0.35),
				Vector2(hi, axis_pos + half_t * 0.35),
				Vector2(m_hi, axis_pos + half_t),
			]),
			PackedColorArray([col, c_clear, c_clear, col])
		)
	else:
		draw_polygon(
			PackedVector2Array([
				Vector2(axis_pos - half_t * 0.35, lo),
				Vector2(axis_pos + half_t * 0.35, lo),
				Vector2(axis_pos + half_t, m_lo),
				Vector2(axis_pos - half_t, m_lo),
			]),
			PackedColorArray([c_clear, c_clear, col, col])
		)
		if m_hi > m_lo:
			draw_rect(Rect2(axis_pos - half_t, m_lo, thickness, m_hi - m_lo), col, true)
		draw_polygon(
			PackedVector2Array([
				Vector2(axis_pos - half_t, m_hi),
				Vector2(axis_pos + half_t, m_hi),
				Vector2(axis_pos + half_t * 0.35, hi),
				Vector2(axis_pos - half_t * 0.35, hi),
			]),
			PackedColorArray([col, col, c_clear, c_clear])
		)


func _draw_sweep_ribbons(
	is_horiz: bool,
	lo: float,
	hi: float,
	axis_pos: float,
	amp: float,
	accent: Color,
	fade: float,
	phase: float
) -> void:
	if hi - lo < 16.0 or amp < 1.2:
		return
	var steps: int = 12
	var ribbon_a: PackedVector2Array = PackedVector2Array()
	var ribbon_b: PackedVector2Array = PackedVector2Array()
	var wave_t: float = _time * 24.0 + phase
	for i: int in range(steps + 1):
		var u: float = float(i) / float(steps)
		var along: float = lerpf(lo, hi, u)
		var taper: float = sin(u * PI)
		var off_a: float = sin(u * 10.5 - wave_t) * amp * taper
		var off_b: float = sin(u * 10.5 - wave_t + PI) * amp * 0.85 * taper
		if is_horiz:
			ribbon_a.append(Vector2(along, axis_pos + off_a))
			ribbon_b.append(Vector2(along, axis_pos + off_b))
		else:
			ribbon_a.append(Vector2(axis_pos + off_a, along))
			ribbon_b.append(Vector2(axis_pos + off_b, along))

	var tint_a: Color = accent.lerp(Color("#FFF5B0"), 0.58)
	var glow_a: Color = Color(tint_a.r, tint_a.g, tint_a.b, 0.34 * fade)
	tint_a.a = 0.82 * fade
	var tint_b: Color = Color(1.0, 1.0, 1.0, 0.72 * fade)
	draw_polyline(ribbon_a, glow_a, 6.4, true)
	draw_polyline(ribbon_a, tint_a, 2.8, true)
	draw_polyline(ribbon_b, tint_b, 2.0, true)


func _draw_rings() -> void:
	# Multi-layered blazing plasma shockwave rings rendered via GPU annular textures
	# (thick luminous outer halo + incandescent core ridge — NEVER skinny wireframe circles!).
	for ring: Dictionary in _rings:
		if (ring["delay"] as float) > 0.0:
			continue
		var t: float = clampf((ring["age"] as float) / (ring["dur"] as float), 0.0, 1.0)
		var eased: float = _ease_out_cubic(t)
		var alpha: float = pow(1.0 - t, 1.25)
		if alpha <= 0.01:
			continue

		var pos: Vector2 = ring["pos"] as Vector2
		var rad: float = lerpf(ring["r0"] as float, ring["r1"] as float, eased)
		var col_core: Color = (ring["col_a"] as Color).lerp(ring["col_b"] as Color, t)
		var col_halo: Color = (ring["halo"] as Color).lerp(ring["halo_b"] as Color, t)
		var intensity: float = ring["intensity"] as float

		# 1. Wide luminous plasma outer halo wave.
		_draw_radial_ring(
			pos,
			rad * 1.03,
			_radial_ring_wide_tex,
			Color(col_halo.r, col_halo.g, col_halo.b, clampf(0.84 * intensity * alpha, 0.0, 1.0))
		)
		# 2. Intense blazing plasma core ridge (thickest early, tapers smoothly as it expands).
		_draw_radial_ring(
			pos,
			rad,
			_radial_ring_core_tex,
			Color(col_core.r, col_core.g, col_core.b, clampf(0.96 * intensity * alpha, 0.0, 1.0))
		)
		# 3. White-hot leading plasma crest during peak expansion.
		if t < 0.76:
			var crest_a: float = (1.0 - t / 0.76) * alpha * 0.78 * intensity
			_draw_radial_ring(
				pos,
				rad * 0.975,
				_radial_ring_core_tex,
				Color(1.0, 0.99, 0.92, clampf(crest_a, 0.0, 1.0))
			)


func _draw_lightnings() -> void:
	for bolt: Dictionary in _lightnings:
		var t: float = clampf((bolt["age"] as float) / (bolt["dur"] as float), 0.0, 1.0)
		var fade: float = 1.0 - _ease_in_quad(clampf((t - 0.24) / 0.76, 0.0, 1.0))
		var flicker: float = 0.88 + 0.12 * sin(_time * 88.0)
		var alpha: float = fade * flicker
		var env: float = lerpf(1.16, 0.30, _ease_in_quad(t))

		var origin: Vector2 = bolt["origin"] as Vector2
		var b_rect: Rect2 = bolt["board_rect"] as Rect2
		var cell_sz: float = bolt["cell_size"] as float
		var phase: float = bolt["phase"] as float

		# 1. Wide soft electric-cyan corridor light spill across full row & full column.
		var spill_w: float = cell_sz * 2.15 * env
		var plasma_w: float = cell_sz * 1.12 * env
		var core_w: float = cell_sz * 0.42 * env
		var hot_w: float = cell_sz * 0.17 * env

		_draw_feathered_corridor_band(
			true, b_rect.position.x, b_rect.end.x, origin.y, spill_w,
			Color(0.08, 0.56, 1.0, 0.46 * alpha)
		)
		_draw_feathered_corridor_band(
			false, b_rect.position.y, b_rect.end.y, origin.x, spill_w,
			Color(0.08, 0.56, 1.0, 0.46 * alpha)
		)
		_draw_feathered_corridor_band(
			true, b_rect.position.x, b_rect.end.x, origin.y, plasma_w,
			Color(0.18, 0.92, 1.0, 0.80 * alpha)
		)
		_draw_feathered_corridor_band(
			false, b_rect.position.y, b_rect.end.y, origin.x, plasma_w,
			Color(0.18, 0.92, 1.0, 0.80 * alpha)
		)

		# 2. Sinuous twin golden-cyan wavy plasma energy ribbons along BOTH axes.
		_draw_lightning_ribbons(true, b_rect.position.x, b_rect.end.x, origin.y, cell_sz * 0.44 * env, alpha, phase)
		_draw_lightning_ribbons(false, b_rect.position.y, b_rect.end.y, origin.x, cell_sz * 0.44 * env, alpha, phase + 1.7)

		# 3. Blazing thick white-hot core energy beam.
		_draw_feathered_corridor_band(
			true, b_rect.position.x, b_rect.end.x, origin.y, core_w,
			Color(0.92, 1.0, 1.0, 0.96 * alpha)
		)
		_draw_feathered_corridor_band(
			false, b_rect.position.y, b_rect.end.y, origin.x, core_w,
			Color(0.92, 1.0, 1.0, 0.96 * alpha)
		)
		var h_a: Vector2 = Vector2(b_rect.position.x, origin.y)
		var h_b: Vector2 = Vector2(b_rect.end.x, origin.y)
		var v_a: Vector2 = Vector2(origin.x, b_rect.position.y)
		var v_b: Vector2 = Vector2(origin.x, b_rect.end.y)
		draw_line(h_a, h_b, Color(1.0, 1.0, 1.0, 0.98 * alpha), hot_w, true)
		draw_line(v_a, v_b, Color(1.0, 1.0, 1.0, 0.98 * alpha), hot_w, true)

		# 4. Primary + secondary re-jittering jagged electric lightning arcs.
		var outer_arc_col: Color = Color(0.14, 0.82, 1.0, 0.56 * alpha)
		var mid_arc_col: Color = Color(0.56, 0.97, 1.0, 0.92 * alpha)
		var hot_arc_col: Color = Color(1.0, 1.0, 1.0, 0.98 * alpha)
		var polylines: Array = bolt["polylines"] as Array
		for pl_var: Variant in polylines:
			var pts: PackedVector2Array = pl_var as PackedVector2Array
			if pts.size() >= 2:
				draw_polyline(pts, outer_arc_col, 9.2 * env, true)
				draw_polyline(pts, mid_arc_col, 4.4 * env, true)
				draw_polyline(pts, hot_arc_col, 2.0 * env, true)

		var sec_glow_col: Color = Color(LIGHTNING_GOLD.r, LIGHTNING_GOLD.g, LIGHTNING_GOLD.b, 0.50 * alpha)
		var sec_core_col: Color = Color(1.0, 0.98, 0.82, 0.88 * alpha)
		var sec_polylines: Array = bolt["secondary_polylines"] as Array
		for spl_var: Variant in sec_polylines:
			var s_pts: PackedVector2Array = spl_var as PackedVector2Array
			if s_pts.size() >= 2:
				draw_polyline(s_pts, sec_glow_col, 5.4 * env, true)
				draw_polyline(s_pts, sec_core_col, 2.0 * env, true)

		# 5. Crackling golden-cyan fork branches.
		var branch_outer: Color = Color(LIGHTNING_GOLD.r, LIGHTNING_GOLD.g, LIGHTNING_GOLD.b, 0.45 * alpha)
		var branch_mid: Color = Color(LIGHTNING_GOLD.r, LIGHTNING_GOLD.g, LIGHTNING_GOLD.b, 0.86 * alpha)
		var branch_core: Color = Color(1.0, 1.0, 1.0, 0.94 * alpha)
		var branches: Array = bolt["branches"] as Array
		for br_var: Variant in branches:
			var b_pts: PackedVector2Array = br_var as PackedVector2Array
			if b_pts.size() >= 2:
				draw_polyline(b_pts, branch_outer, 6.2 * env, true)
				draw_polyline(b_pts, branch_mid, 3.0 * env, true)
				draw_polyline(b_pts, branch_core, 1.35 * env, true)

		# 6. Luminous intersection flare & axis cross gleam.
		_draw_radial_glow(origin, cell_sz * 1.95 * env, Color(0.22, 0.90, 1.0, 0.56 * alpha))
		_draw_radial_glow(origin, cell_sz * 1.05 * env, Color(1.0, 0.93, 0.55, 0.65 * alpha))
		_draw_radial_glow(origin, cell_sz * 0.62 * env, Color(1.0, 1.0, 1.0, 0.98 * alpha))
		_draw_four_point_star(
			origin,
			cell_sz * 1.48 * env,
			cell_sz * 0.22 * env,
			Color(1.0, 1.0, 0.94, 0.92 * alpha)
		)


func _draw_lightning_ribbons(
	is_horiz: bool,
	lo: float,
	hi: float,
	axis_pos: float,
	amp: float,
	alpha: float,
	phase: float
) -> void:
	if hi - lo < 20.0 or amp < 1.5:
		return
	var steps: int = 16
	var rib_gold: PackedVector2Array = PackedVector2Array()
	var rib_cyan: PackedVector2Array = PackedVector2Array()
	var wave_t: float = _time * 32.0 + phase
	for i: int in range(steps + 1):
		var u: float = float(i) / float(steps)
		var along: float = lerpf(lo, hi, u)
		var taper: float = 0.28 + 0.72 * sin(u * PI)
		var off_g: float = sin(u * 13.5 - wave_t) * amp * taper
		var off_c: float = sin(u * 11.5 + wave_t * 1.15 + PI * 0.65) * amp * 0.90 * taper
		if is_horiz:
			rib_gold.append(Vector2(along, axis_pos + off_g))
			rib_cyan.append(Vector2(along, axis_pos + off_c))
		else:
			rib_gold.append(Vector2(axis_pos + off_g, along))
			rib_cyan.append(Vector2(axis_pos + off_c, along))

	draw_polyline(rib_gold, Color(1.0, 0.78, 0.16, 0.42 * alpha), 8.2, true)
	draw_polyline(rib_gold, Color(1.0, 0.93, 0.50, 0.88 * alpha), 3.2, true)
	draw_polyline(rib_cyan, Color(0.16, 0.88, 1.0, 0.46 * alpha), 7.6, true)
	draw_polyline(rib_cyan, Color(0.84, 0.99, 1.0, 0.86 * alpha), 2.6, true)


func _draw_starbursts() -> void:
	for sb: Dictionary in _starbursts:
		var t: float = clampf((sb["age"] as float) / (sb["dur"] as float), 0.0, 1.0)
		var alpha: float = (1.0 - t) * (1.0 - t * 0.45)
		if alpha <= 0.01:
			continue
		var pos: Vector2 = sb["pos"] as Vector2
		var rad: float = lerpf(sb["r0"] as float, sb["r1"] as float, _ease_out_cubic(t))
		var pts_count: int = sb["points"] as int
		var rot: float = sb["rot"] as float
		var outer_col: Color = sb["outer_col"] as Color
		var mid_col: Color = sb["mid_col"] as Color
		var core_col: Color = sb["core_col"] as Color

		# Smooth radial outer bloom + crisp convex diamond starburst rays.
		_draw_radial_glow(pos, rad * 1.35, Color(outer_col.r, outer_col.g, outer_col.b, 0.52 * alpha))
		_draw_n_point_star(pos, rad, rad * 0.18, pts_count, rot, Color(outer_col.r, outer_col.g, outer_col.b, 0.82 * alpha))
		_draw_n_point_star(pos, rad * 0.76, rad * 0.15, pts_count, rot + PI / float(maxi(2, pts_count)), Color(mid_col.r, mid_col.g, mid_col.b, 0.92 * alpha))
		_draw_four_point_star(pos, rad * 0.62, rad * 0.13, Color(core_col.r, core_col.g, core_col.b, alpha))
		_draw_radial_glow(pos, rad * 0.44, Color(core_col.r, core_col.g, core_col.b, 0.98 * alpha))


func _draw_fire_plumes() -> void:
	# Luminous molten gold -> fiery tangerine radial fire plumes (zero dark brown smudges!).
	for orb: Dictionary in _fire_plumes:
		var t: float = clampf((orb["age"] as float) / (orb["dur"] as float), 0.0, 1.0)
		var eased: float = _ease_out_cubic(t)
		var pos: Vector2 = orb["pos"] as Vector2
		var rad: float = lerpf(orb["r0"] as float, orb["r1"] as float, eased)
		var alpha: float = (1.0 - t) * (1.0 - t * 0.65)
		if alpha <= 0.01:
			continue

		var outer_col: Color = orb["outer"] as Color
		var hot_col: Color = orb["hot"] as Color
		_draw_radial_glow(pos, rad * 1.55, Color(outer_col.r, outer_col.g, outer_col.b, 0.44 * alpha))
		if t < 0.85:
			var core_fade: float = (1.0 - t / 0.85) * alpha
			_draw_radial_glow(pos, rad * 0.90, Color(hot_col.r, hot_col.g, hot_col.b, 0.72 * core_fade))
			_draw_radial_glow(pos, rad * 0.42, Color(1.0, 0.99, 0.84, 0.82 * core_fade))


func _draw_shards() -> void:
	for sh: Dictionary in _shards:
		var t: float = clampf((sh["age"] as float) / (sh["dur"] as float), 0.0, 1.0)
		var alpha: float = 1.0 - _ease_in_quad(clampf((t - 0.42) / 0.58, 0.0, 1.0))
		if alpha <= 0.01:
			continue

		var pos: Vector2 = sh["pos"] as Vector2
		var vel: Vector2 = sh["vel"] as Vector2
		var rot: float = sh["rot"] as float
		var tumble: float = sh["tumble"] as float
		var tier: int = sh["tier"] as int
		var sc: float = lerpf(1.08, 0.62, t * t)
		var rx: float = (sh["rad"] as float) * sc
		var ry: float = rx * (sh["aspect"] as float)
		if rx < 1.2 or ry < 1.2:
			continue

		var c_top: Color = sh["top"] as Color
		var c_left: Color = sh["left"] as Color
		var c_face: Color = sh["face"] as Color
		var c_deep: Color = sh["deep"] as Color
		var c_right: Color = sh["right"] as Color
		var c_bottom: Color = sh["bottom"] as Color
		var c_glow: Color = sh["glow"] as Color
		var c_rim: Color = sh["rim"] as Color

		# 1. Directional velocity motion-blur tail streak behind fast shards.
		var speed: float = vel.length()
		if speed > 125.0:
			var fwd: Vector2 = vel / speed
			var perp: Vector2 = Vector2(-fwd.y, fwd.x)
			var tail_len: float = clampf(speed * 0.044, rx * 1.45, 34.0)
			var hw: float = maxf(1.5, rx * (0.64 if tier >= 1 else 0.48))
			var tail_tip: Vector2 = pos - fwd * tail_len
			draw_colored_polygon(
				PackedVector2Array([
					pos + perp * hw,
					pos + fwd * (rx * 0.35),
					pos - perp * hw,
					tail_tip,
				]),
				Color(c_glow.r, c_glow.g, c_glow.b, 0.34 * alpha)
			)
			var hw_in: float = hw * 0.46
			draw_colored_polygon(
				PackedVector2Array([
					pos + perp * hw_in,
					pos + fwd * (rx * 0.20),
					pos - perp * hw_in,
					pos - fwd * (tail_len * 0.68),
				]),
				Color(c_top.r, c_top.g, c_top.b, 0.48 * alpha)
			)

		# 2. Soft GPU radial glow aura (zero hard circular bubble edges!).
		_draw_radial_glow(
			pos,
			maxf(rx, ry) * (1.85 if tier == 2 else 1.55),
			Color(c_glow.r, c_glow.g, c_glow.b, (0.30 if tier == 2 else 0.24) * alpha)
		)

		var cos_r: float = cos(rot)
		var sin_r: float = sin(rot)

		if tier >= 1:
			# 3D-shaded tumbling beveled jewel cube (medium & chunky tiers).
			var foreshorten: float = 0.76 + 0.24 * absf(cos(tumble))
			var ux: Vector2 = Vector2(cos_r, sin_r) * (rx * 0.92)
			var uy: Vector2 = Vector2(-sin_r, cos_r) * (ry * 0.92 * foreshorten)

			var c0: Vector2 = pos - ux - uy # top-left
			var c1: Vector2 = pos + ux - uy # top-right
			var c2: Vector2 = pos + ux + uy # bottom-right
			var c3: Vector2 = pos - ux + uy # bottom-left

			# 3D cube thickness extrusion along consistent bottom-right shadow vector.
			var ext_scale: float = maxf(rx, ry) * (0.58 if tier == 2 else 0.46)
			var ext: Vector2 = Vector2(0.56, 0.78) * ext_scale
			var corners: Array[Vector2] = [c0, c1, c2, c3]
			for edge_idx: int in range(4):
				var p_a: Vector2 = corners[edge_idx]
				var p_b: Vector2 = corners[(edge_idx + 1) & 3]
				var edge_d: Vector2 = p_b - p_a
				var out_n: Vector2 = Vector2(edge_d.y, -edge_d.x)
				if out_n.dot(ext) > 0.0:
					var n_norm: Vector2 = out_n.normalized()
					var side_col: Color = c_bottom if n_norm.y > 0.35 else (c_right if n_norm.x > 0.0 else c_deep)
					draw_colored_polygon(
						PackedVector2Array([p_a, p_b, p_b + ext, p_a + ext]),
						Color(side_col.r, side_col.g, side_col.b, alpha)
					)

			# Front beveled jewel face (4 outer bevels + luminous inner face).
			var inner_k: float = 0.56
			var i0: Vector2 = pos + (c0 - pos) * inner_k
			var i1: Vector2 = pos + (c1 - pos) * inner_k
			var i2: Vector2 = pos + (c2 - pos) * inner_k
			var i3: Vector2 = pos + (c3 - pos) * inner_k

			draw_colored_polygon(PackedVector2Array([c0, c1, i1, i0]), Color(c_top.r, c_top.g, c_top.b, alpha))
			draw_colored_polygon(PackedVector2Array([c0, i0, i3, c3]), Color(c_left.r, c_left.g, c_left.b, alpha))
			draw_colored_polygon(PackedVector2Array([c1, c2, i2, i1]), Color(c_right.r, c_right.g, c_right.b, alpha))
			draw_colored_polygon(PackedVector2Array([c3, i3, i2, c2]), Color(c_bottom.r, c_bottom.g, c_bottom.b, alpha))

			var face_col: Color = c_face.lerp(c_top, 0.14)
			draw_colored_polygon(PackedVector2Array([i0, i1, i2, i3]), Color(face_col.r, face_col.g, face_col.b, alpha))

			# Crisp specular top highlight rim & inner glint corner.
			draw_line(c3, c0, Color(c_rim.r, c_rim.g, c_rim.b, 0.85 * alpha), 1.3, true)
			draw_line(c0, c1, Color(1.0, 1.0, 1.0, 0.88 * alpha), 1.45, true)
			draw_line(i0, i1, Color(1.0, 1.0, 1.0, 0.55 * alpha), 1.1, true)
		else:
			# Crisp micro-glint crystal chip (0.11x..0.145x) for bright scale contrast.
			var ux_s: Vector2 = Vector2(cos_r, sin_r) * rx
			var uy_s: Vector2 = Vector2(-sin_r, cos_r) * ry
			var p_top: Vector2 = pos - uy_s
			var p_right: Vector2 = pos + ux_s
			var p_bot: Vector2 = pos + uy_s
			var p_left: Vector2 = pos - ux_s
			draw_colored_polygon(PackedVector2Array([p_top, p_right, p_left]), Color(c_top.r, c_top.g, c_top.b, alpha))
			draw_colored_polygon(PackedVector2Array([p_left, p_right, p_bot]), Color(c_face.r, c_face.g, c_face.b, alpha))
			draw_line(p_left, p_top, Color(1.0, 1.0, 1.0, 0.92 * alpha), 1.2, true)
			if t < 0.55:
				_draw_four_point_star(pos, rx * 1.15, rx * 0.24, Color(1.0, 1.0, 0.96, 0.78 * alpha))


func _draw_sparks() -> void:
	for sp: Dictionary in _sparks:
		if (sp["delay"] as float) > 0.0:
			continue
		var t: float = clampf((sp["age"] as float) / (sp["dur"] as float), 0.0, 1.0)
		var alpha: float = 1.0 - _ease_in_quad(t)
		if alpha <= 0.01:
			continue

		var pos: Vector2 = sp["pos"] as Vector2
		var vel: Vector2 = sp["vel"] as Vector2
		var sz: float = (sp["size"] as float) * lerpf(1.0, 0.36, t)
		if sz < 0.8:
			continue
		var col: Color = sp["col"] as Color
		var kind: int = sp["kind"] as int

		if kind == 0:
			# Twinkling 4-point convex diamond sparkle mote with smooth radial glow.
			var twinkle: float = 0.74 + 0.26 * sin(_time * 26.0 + pos.x * 0.1)
			var r_star: float = sz * 1.60 * twinkle
			_draw_radial_glow(pos, r_star * 1.45, Color(col.r, col.g, col.b, 0.44 * alpha))
			_draw_four_point_star(pos, r_star, r_star * 0.26, Color(col.r, col.g, col.b, 0.94 * alpha))
			_draw_radial_glow(pos, maxf(1.8, sz * 0.72), Color(1.0, 1.0, 0.95, alpha))
		else:
			# Velocity-stretched razor-tapered fiery golden or electric plasma streamer.
			var tail_scale: float = sp["tail_scale"] as float
			var speed: float = vel.length()
			var fwd: Vector2 = (vel / speed) if speed > 0.5 else Vector2.UP
			var perp: Vector2 = Vector2(-fwd.y, fwd.x)
			var tail_len: float = clampf(speed * tail_scale * 1.55, sz * 2.4, 58.0)
			var head_tip: Vector2 = pos + fwd * (sz * 1.45)
			var tail_tip: Vector2 = pos - fwd * tail_len
			var tail_col: Color = sp["tail_col"] as Color

			# Soft glowing energy bloom at streamer head.
			_draw_radial_glow(pos, sz * 3.1, Color(col.r, col.g, col.b, 0.42 * alpha))

			var hw_outer: float = sz * 1.05
			draw_colored_polygon(
				PackedVector2Array([
					head_tip + fwd * (sz * 0.45),
					pos + perp * hw_outer,
					tail_tip,
					pos - perp * hw_outer,
				]),
				Color(tail_col.r, tail_col.g, tail_col.b, 0.54 * alpha)
			)
			var hw_inner: float = sz * 0.58
			draw_colored_polygon(
				PackedVector2Array([
					head_tip,
					pos + perp * hw_inner,
					pos - fwd * (tail_len * 0.78),
					pos - perp * hw_inner,
				]),
				Color(col.r, col.g, col.b, 0.96 * alpha)
			)
			_draw_radial_glow(pos, maxf(2.0, sz * 1.18), Color(1.0, 0.99, 0.92, alpha))


func _draw_score_orbs() -> void:
	for orb: Dictionary in _score_orbs:
		if (orb["delay"] as float) > 0.0:
			continue
		var pos: Vector2 = orb["pos"] as Vector2
		var col: Color = orb["col"] as Color
		var trail: PackedVector2Array = orb["trail"] as PackedVector2Array

		var trail_len: int = trail.size()
		if trail_len >= 2:
			for k: int in range(1, trail_len):
				var frac: float = float(k) / float(trail_len - 1)
				var w_halo: float = lerpf(2.0, 13.0, frac)
				var w_core: float = lerpf(0.9, 5.6, frac)
				draw_line(trail[k - 1], trail[k], Color(col.r, col.g, col.b, 0.38 * frac), w_halo, true)
				draw_line(trail[k - 1], trail[k], Color(1.0, 0.98, 0.86, 0.80 * frac), w_core, true)

		_draw_radial_glow(pos, 22.0, Color(col.r, col.g, col.b, 0.58))
		_draw_radial_glow(pos, 11.0, Color(1.0, 0.98, 0.84, 0.96))
		_draw_four_point_star(pos, 12.0, 2.6, Color(1.0, 0.99, 0.88, 0.92))


func _draw_popups() -> void:
	var font: Font = _get_font()
	if font == null:
		return

	for pop: Dictionary in _popups:
		if (pop["delay"] as float) > 0.0:
			continue
		var age: float = pop["age"] as float
		var dur: float = pop["dur"] as float
		var t: float = clampf(age / dur, 0.0, 1.0)

		var sc: float = 1.0
		if age < 0.08:
			sc = lerpf(0.30, 1.25, _ease_out_cubic(age / 0.08))
		elif age < 0.14:
			sc = lerpf(1.25, 1.0, _ease_out_quad((age - 0.08) / 0.06))
		elif t > 0.72:
			sc = lerpf(1.0, 1.06, (t - 0.72) / 0.28)

		var alpha: float = 1.0
		if t > 0.72:
			alpha = 1.0 - _ease_in_quad((t - 0.72) / 0.28)
		if alpha <= 0.01:
			continue

		var base_pos: Vector2 = pop["pos"] as Vector2
		var rise_dist: float = pop["rise"] as float
		var draw_pos: Vector2 = base_pos + Vector2(0.0, -rise_dist * _ease_out_quad(t))
		var tilt_rad: float = pop["tilt_rad"] as float
		var txt: String = pop["text"] as String
		var fsize: int = pop["font_size"] as int
		var fill_col: Color = pop["fill"] as Color
		var badge_bg: Color = pop["bg"] as Color
		var rim_col: Color = pop["rim"] as Color
		var txt_sz: Vector2 = pop["text_size"] as Vector2
		var ascent: float = pop["ascent"] as float
		var descent: float = pop["descent"] as float

		draw_set_transform(draw_pos, tilt_rad, Vector2(sc, sc))

		if badge_bg.a > 0.01:
			var pad_x: float = clampf(float(fsize) * 0.50, 14.0, 24.0)
			var pad_y: float = clampf(float(fsize) * 0.17, 5.0, 9.0)
			var pill_w: float = txt_sz.x + pad_x * 2.0
			var pill_h: float = float(fsize) * 0.96 + pad_y * 2.0
			var pill_rect: Rect2 = Rect2(-Vector2(pill_w, pill_h) * 0.5, Vector2(pill_w, pill_h))
			var chamfer: float = clampf(pill_h * 0.28, 6.0, 12.0)

			_draw_chamfered_pill(
				Rect2(pill_rect.position + Vector2(0.0, 4.2), pill_rect.size),
				Color(0.02, 0.03, 0.10, 0.68 * alpha),
				chamfer
			)
			if rim_col.a > 0.01:
				_draw_chamfered_pill_outline(
					pill_rect.grow(1.4),
					Color(rim_col.r, rim_col.g, rim_col.b, 0.42 * alpha),
					chamfer + 1.0,
					4.2
				)
			_draw_chamfered_pill(
				pill_rect,
				Color(badge_bg.r, badge_bg.g, badge_bg.b, badge_bg.a * alpha),
				chamfer
			)
			var sheen_rect: Rect2 = Rect2(
				pill_rect.position + Vector2(chamfer * 0.65, 2.0),
				Vector2(maxf(4.0, pill_rect.size.x - chamfer * 1.3), pill_rect.size.y * 0.36)
			)
			draw_rect(sheen_rect, Color(1.0, 1.0, 1.0, 0.18 * alpha), true)
			if rim_col.a > 0.01:
				_draw_chamfered_pill_outline(
					pill_rect,
					Color(rim_col.r, rim_col.g, rim_col.b, 0.96 * alpha),
					chamfer,
					2.4
				)

		var baseline: Vector2 = Vector2(-txt_sz.x * 0.5, (ascent - descent) * 0.41)
		var outline_px: int = clampi(int(round(float(fsize) * 0.26)), 6, 12)

		draw_string_outline(
			font,
			baseline + Vector2(0.0, 3.2),
			txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fsize,
			outline_px,
			Color(0.02, 0.03, 0.09, 0.72 * alpha)
		)
		draw_string_outline(
			font,
			baseline,
			txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fsize,
			outline_px,
			Color(0.04, 0.05, 0.15, alpha)
		)
		draw_string(
			font,
			baseline,
			txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fsize,
			Color(fill_col.r, fill_col.g, fill_col.b, fill_col.a * alpha)
		)

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ==============================================================================
# PROCEDURAL GPU TEXTURE CACHE & QUAD BLOOM HELPERS
# ==============================================================================

func _ensure_textures() -> void:
	if _radial_glow_tex != null:
		return

	# 1. Smooth 4-stop radial glow bloom (reaches exact 0.0 alpha at 0.96 -> zero edge seams).
	var glow_grad: Gradient = Gradient.new()
	glow_grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	glow_grad.offsets = PackedFloat32Array([0.0, 0.28, 0.62, 0.96])
	glow_grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.65),
		Color(1.0, 1.0, 1.0, 0.20),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	_radial_glow_tex = GradientTexture2D.new()
	_radial_glow_tex.width = 128
	_radial_glow_tex.height = 128
	_radial_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_radial_glow_tex.fill_from = Vector2(0.5, 0.5)
	_radial_glow_tex.fill_to = Vector2(1.0, 0.5)
	_radial_glow_tex.gradient = glow_grad

	# 2. Wide luminous plasma shockwave halo ring.
	var ring_wide_grad: Gradient = Gradient.new()
	ring_wide_grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	ring_wide_grad.offsets = PackedFloat32Array([0.0, 0.44, 0.64, 0.78, 0.90, 0.97])
	ring_wide_grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.52),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.34),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	_radial_ring_wide_tex = GradientTexture2D.new()
	_radial_ring_wide_tex.width = 128
	_radial_ring_wide_tex.height = 128
	_radial_ring_wide_tex.fill = GradientTexture2D.FILL_RADIAL
	_radial_ring_wide_tex.fill_from = Vector2(0.5, 0.5)
	_radial_ring_wide_tex.fill_to = Vector2(1.0, 0.5)
	_radial_ring_wide_tex.gradient = ring_wide_grad

	# 3. Blazing intense inner plasma shockwave core ridge.
	var ring_core_grad: Gradient = Gradient.new()
	ring_core_grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	ring_core_grad.offsets = PackedFloat32Array([0.0, 0.67, 0.76, 0.81, 0.87, 0.95])
	ring_core_grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.76),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.40),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	_radial_ring_core_tex = GradientTexture2D.new()
	_radial_ring_core_tex.width = 128
	_radial_ring_core_tex.height = 128
	_radial_ring_core_tex.fill = GradientTexture2D.FILL_RADIAL
	_radial_ring_core_tex.fill_from = Vector2(0.5, 0.5)
	_radial_ring_core_tex.fill_to = Vector2(1.0, 0.5)
	_radial_ring_core_tex.gradient = ring_core_grad

	# 4. Smooth feathered beam corridor bands (vertical cross-section & horizontal cross-section).
	var band_grad: Gradient = Gradient.new()
	band_grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	band_grad.offsets = PackedFloat32Array([0.02, 0.24, 0.42, 0.50, 0.58, 0.76, 0.98])
	band_grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.36),
		Color(1.0, 1.0, 1.0, 0.88),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.88),
		Color(1.0, 1.0, 1.0, 0.36),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	_beam_band_v_tex = GradientTexture2D.new()
	_beam_band_v_tex.width = 8
	_beam_band_v_tex.height = 64
	_beam_band_v_tex.fill = GradientTexture2D.FILL_LINEAR
	_beam_band_v_tex.fill_from = Vector2(0.5, 0.0)
	_beam_band_v_tex.fill_to = Vector2(0.5, 1.0)
	_beam_band_v_tex.gradient = band_grad

	_beam_band_h_tex = GradientTexture2D.new()
	_beam_band_h_tex.width = 64
	_beam_band_h_tex.height = 8
	_beam_band_h_tex.fill = GradientTexture2D.FILL_LINEAR
	_beam_band_h_tex.fill_from = Vector2(0.0, 0.5)
	_beam_band_h_tex.fill_to = Vector2(1.0, 0.5)
	_beam_band_h_tex.gradient = band_grad


func _draw_radial_glow(center: Vector2, radius: float, col: Color) -> void:
	if radius <= 0.5 or col.a <= 0.005 or _radial_glow_tex == null:
		return
	var d: float = radius * 2.0
	draw_texture_rect(_radial_glow_tex, Rect2(center.x - radius, center.y - radius, d, d), false, col)


func _draw_radial_ring(center: Vector2, radius: float, tex: Texture2D, col: Color) -> void:
	if radius <= 1.0 or col.a <= 0.005 or tex == null:
		return
	# Ring ridge peaks at ~0.80 of texture radius -> scale quad by 1.25 so ridge tracks `radius`.
	var quad_r: float = radius * 1.25
	var d: float = quad_r * 2.0
	draw_texture_rect(tex, Rect2(center.x - quad_r, center.y - quad_r, d, d), false, col)


# ==============================================================================
# INTERNAL BUILDERS, SMART POPUP COLLISION RESOLVER & GEOMETRY HELPERS
# ==============================================================================

func _get_font() -> Font:
	if _font == null:
		_font = TilePainter.get_badge_font()
	return _font


func _get_canvas_size() -> Vector2:
	if size.x > 4.0 and size.y > 4.0:
		return size
	var vp_rect: Rect2 = get_viewport_rect()
	if vp_rect.size.x > 4.0 and vp_rect.size.y > 4.0:
		return vp_rect.size
	return Vector2(540.0, 960.0)


func _add_sweep(
	is_horiz: bool,
	span_a: float,
	span_b: float,
	axis_pos: float,
	cell_size: float,
	accent_color: Color,
	dir: float,
	delay: float
) -> void:
	_sweeps.append({
		"horiz": is_horiz,
		"a": span_a,
		"b": span_b,
		"axis": axis_pos,
		"cell_size": cell_size,
		"col": accent_color,
		"dir": dir,
		"phase": _rng.randf_range(0.0, TAU),
		"delay": delay,
		"age": 0.0,
		"dur": 0.34,
	})


func _spawn_sweep_motes(
	start_pt: Vector2,
	end_pt: Vector2,
	cell_size: float,
	accent_color: Color,
	dir: float,
	count: int
) -> void:
	var a: Vector2 = start_pt if dir > 0.0 else end_pt
	var b: Vector2 = end_pt if dir > 0.0 else start_pt
	var along: Vector2 = (b - a).normalized()
	var perp: Vector2 = Vector2(-along.y, along.x)

	for i: int in range(count):
		var u: float = (float(i) + _rng.randf_range(0.15, 0.85)) / float(count)
		var pt: Vector2 = a.lerp(b, u) + perp * _rng.randf_range(-cell_size * 0.38, cell_size * 0.38)
		var side: float = -1.0 if (i & 1) == 0 else 1.0
		var vel: Vector2 = along * _rng.randf_range(35.0, 110.0) + perp * (side * _rng.randf_range(35.0, 95.0))
		var mote_col: Color = accent_color.lerp(Color("#FFF7C2"), _rng.randf_range(0.35, 0.80))
		_push_spark({
			"kind": 0, # diamond sparkle mote
			"pos": pt,
			"vel": vel,
			"drag": 3.8,
			"gravity": -25.0,
			"size": _rng.randf_range(2.8, 5.0),
			"tail_scale": 0.0,
			"col": mote_col,
			"tail_col": Color.WHITE,
			"delay": u * 0.12,
			"age": 0.0,
			"dur": _rng.randf_range(0.28, 0.44),
		})


func _rebuild_lightning_geometry(bolt: Dictionary) -> void:
	var origin: Vector2 = bolt["origin"] as Vector2
	var b_rect: Rect2 = bolt["board_rect"] as Rect2
	var cell_sz: float = bolt["cell_size"] as float

	var targets: Array[Vector2] = [
		Vector2(b_rect.position.x, origin.y),
		Vector2(b_rect.end.x, origin.y),
		Vector2(origin.x, b_rect.position.y),
		Vector2(origin.x, b_rect.end.y),
	]

	var polylines: Array = []
	var secondary_polylines: Array = []
	var branches: Array = []
	var jitter_amp: float = cell_sz * 0.36
	var sec_jitter_amp: float = cell_sz * 0.44

	for target_pt: Vector2 in targets:
		var delta_vec: Vector2 = target_pt - origin
		var length: float = delta_vec.length()
		if length <= 4.0:
			continue
		var dir: Vector2 = delta_vec / length
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var segs: int = clampi(int(round(length / maxf(24.0, cell_sz * 0.62))), 4, 12)

		var pts: PackedVector2Array = PackedVector2Array()
		var sec_pts: PackedVector2Array = PackedVector2Array()
		pts.append(origin)
		sec_pts.append(origin)

		for s: int in range(1, segs):
			var u: float = float(s) / float(segs)
			var envelope: float = sin(u * PI)
			var offset: float = _rng.randf_range(-1.0, 1.0) * jitter_amp * (0.45 + 0.65 * envelope)
			var vertex: Vector2 = origin.lerp(target_pt, u) + perp * offset
			pts.append(vertex)

			var sec_off: float = _rng.randf_range(-1.0, 1.0) * sec_jitter_amp * (0.35 + 0.75 * envelope)
			sec_pts.append(origin.lerp(target_pt, u) + perp * sec_off)

			# Spawn crackling fork branches off interior vertices.
			if (s == segs / 2 or s == maxi(1, segs - 2) or (segs >= 7 and s == 2)) and _rng.randf() < 0.78:
				var fork_sign: float = -1.0 if _rng.randf() < 0.5 else 1.0
				var fork_dir: Vector2 = (dir * 0.62 + perp * (fork_sign * 0.78)).normalized()
				var fork_len: float = cell_sz * _rng.randf_range(0.60, 1.28)
				var mid_v: Vector2 = vertex + fork_dir * (fork_len * 0.52) + perp * _rng.randf_range(-9.0, 9.0)
				var end_v: Vector2 = vertex + fork_dir * fork_len + perp * _rng.randf_range(-13.0, 13.0)
				branches.append(PackedVector2Array([vertex, mid_v, end_v]))

		pts.append(target_pt)
		sec_pts.append(target_pt)
		polylines.append(pts)
		secondary_polylines.append(sec_pts)

	bolt["polylines"] = polylines
	bolt["secondary_polylines"] = secondary_polylines
	bolt["branches"] = branches


func _spawn_orb_arrival_burst(pos: Vector2, col: Color) -> void:
	_rings.append({
		"pos": pos,
		"r0": 6.0,
		"r1": 28.0,
		"col_a": Color.WHITE,
		"col_b": col,
		"halo": col,
		"halo_b": col,
		"intensity": 0.82,
		"delay": 0.0,
		"age": 0.0,
		"dur": 0.20,
	})
	for k: int in range(3):
		var ang: float = _rng.randf_range(0.0, TAU)
		var spd: float = _rng.randf_range(55.0, 130.0)
		_push_spark({
			"kind": 0,
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"drag": 5.2,
			"gravity": 30.0,
			"size": _rng.randf_range(2.4, 4.0),
			"tail_scale": 0.0,
			"col": col.lerp(Color.WHITE, 0.45),
			"tail_col": Color.WHITE,
			"delay": 0.0,
			"age": 0.0,
			"dur": _rng.randf_range(0.18, 0.28),
		})


func _spawn_popup_internal(
	pos: Vector2,
	text: String,
	fill_color: Color,
	font_size: int,
	tilt_deg: float,
	badge_bg: Color,
	rim_color: Color,
	delay: float,
	duration: float,
	rise_dist: float
) -> Vector2:
	var font: Font = _get_font()
	var txt_sz: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) if font != null else Vector2(float(text.length() * font_size) * 0.6, float(font_size))
	var ascent: float = font.get_ascent(font_size) if font != null else float(font_size) * 0.8
	var descent: float = font.get_descent(font_size) if font != null else float(font_size) * 0.2

	var box_size: Vector2 = _compute_popup_box_size(txt_sz, font_size, tilt_deg, badge_bg.a > 0.01)
	var resolved_pos: Vector2 = _resolve_popup_overlap(pos, box_size)

	_popups.append({
		"pos": resolved_pos,
		"box_size": box_size,
		"text": text,
		"fill": fill_color,
		"font_size": font_size,
		"tilt_rad": deg_to_rad(tilt_deg),
		"bg": badge_bg,
		"rim": rim_color,
		"text_size": txt_sz,
		"ascent": ascent,
		"descent": descent,
		"rise": rise_dist,
		"delay": delay,
		"age": 0.0,
		"dur": duration,
	})
	return resolved_pos


func _compute_popup_box_size(txt_sz: Vector2, font_size: int, tilt_deg: float, has_badge: bool) -> Vector2:
	var base_w: float
	var base_h: float
	if has_badge:
		var pad_x: float = clampf(float(font_size) * 0.50, 14.0, 24.0)
		var pad_y: float = clampf(float(font_size) * 0.17, 5.0, 9.0)
		base_w = txt_sz.x + pad_x * 2.0
		base_h = float(font_size) * 0.96 + pad_y * 2.0
	else:
		base_w = txt_sz.x + 16.0
		base_h = float(font_size) * 1.15

	var rad: float = absf(deg_to_rad(tilt_deg))
	var cos_a: float = cos(rad)
	var sin_a: float = sin(rad)
	var rot_w: float = base_w * cos_a + base_h * sin_a
	var rot_h: float = base_w * sin_a + base_h * cos_a
	return Vector2(rot_w * 1.04, rot_h * 1.04)


func _clamp_popup_pos(pos: Vector2, box_size: Vector2) -> Vector2:
	var vp: Vector2 = _get_canvas_size()
	var half_w: float = box_size.x * 0.5
	var half_h: float = box_size.y * 0.5
	var min_x: float = maxf(POPUP_SAFE_X_MIN, half_w + 16.0)
	var max_x: float = minf(POPUP_SAFE_X_MAX, vp.x - half_w - 16.0)
	var clamped_x: float = vp.x * 0.5 if min_x >= max_x else clampf(pos.x, min_x, max_x)

	var min_y: float = maxf(POPUP_SAFE_Y_MIN, half_h + 196.0)
	var max_y: float = minf(POPUP_SAFE_Y_MAX, 656.0 - half_h)
	var clamped_y: float = 420.0 if min_y >= max_y else clampf(pos.y, min_y, max_y)
	return Vector2(clamped_x, clamped_y)


## 2D bounding-box collision resolver ensuring floating score pops, multiplier
## badges (x2 / x3), and combo banners NEVER intersect or slice each other off.
func _resolve_popup_overlap(desired_pos: Vector2, box_size: Vector2) -> Vector2:
	var origin: Vector2 = _clamp_popup_pos(desired_pos, box_size)
	if _popups.is_empty():
		return origin

	var occupied: Array[Rect2] = []
	for pop: Dictionary in _popups:
		var age: float = pop["age"] as float
		var dur: float = pop["dur"] as float
		var t: float = clampf(age / maxf(0.01, dur), 0.0, 1.0)
		if t >= 0.88:
			continue
		var occ_sz: Vector2 = pop["box_size"] as Vector2
		var base_p: Vector2 = pop["pos"] as Vector2
		var rise_d: float = pop["rise"] as float
		var cur_p: Vector2 = base_p + Vector2(0.0, -rise_d * _ease_out_quad(t))
		occupied.append(Rect2(cur_p - occ_sz * 0.5, occ_sz).grow(POPUP_COLLISION_PAD))

	if occupied.is_empty():
		return origin

	var half_sz: Vector2 = box_size * 0.5
	var origin_rect: Rect2 = Rect2(origin - half_sz, box_size)
	if not _rect_intersects_any(origin_rect, occupied):
		return origin

	# Assemble prioritized candidate slots: direct edge-snaps around colliding popups,
	# concentric radial offsets, and safe-zone grid fallbacks.
	var candidates: Array[Vector2] = []
	for occ: Rect2 in occupied:
		if origin_rect.intersects(occ):
			var y_above: float = occ.position.y - half_sz.y - 2.0
			var y_below: float = occ.end.y + half_sz.y + 2.0
			var x_left: float = occ.position.x - half_sz.x - 2.0
			var x_right: float = occ.end.x + half_sz.x + 2.0
			candidates.append(Vector2(origin.x, y_above))
			candidates.append(Vector2(origin.x, y_below))
			candidates.append(Vector2(x_right, origin.y))
			candidates.append(Vector2(x_left, origin.y))
			candidates.append(Vector2(x_right, y_above))
			candidates.append(Vector2(x_left, y_above))
			candidates.append(Vector2(x_right, y_below))
			candidates.append(Vector2(x_left, y_below))

	for ring_idx: int in range(1, 7):
		var sy: float = (box_size.y * 0.55 + 18.0) * float(ring_idx)
		var sx: float = (box_size.x * 0.42 + 24.0) * float(ring_idx)
		candidates.append(origin + Vector2(0.0, -sy))
		candidates.append(origin + Vector2(0.0, sy))
		candidates.append(origin + Vector2(sx, 0.0))
		candidates.append(origin + Vector2(-sx, 0.0))
		candidates.append(origin + Vector2(sx * 0.72, -sy * 0.82))
		candidates.append(origin + Vector2(-sx * 0.72, -sy * 0.82))
		candidates.append(origin + Vector2(sx * 0.72, sy * 0.82))
		candidates.append(origin + Vector2(-sx * 0.72, sy * 0.82))

	var best_clear_pos: Vector2 = origin
	var best_clear_cost: float = INF
	var found_clear: bool = false

	var best_fallback_pos: Vector2 = origin
	var best_fallback_area: float = INF
	var best_fallback_cost: float = INF

	for raw_cand: Vector2 in candidates:
		var cand: Vector2 = _clamp_popup_pos(raw_cand, box_size)
		var cand_rect: Rect2 = Rect2(cand - half_sz, box_size)
		var overlap_area: float = _total_overlap_area(cand_rect, occupied)
		var dx: float = cand.x - origin.x
		var dy: float = cand.y - origin.y
		var cost: float = dx * dx * 1.15 + dy * dy + (16.0 if dy > 0.0 else 0.0)

		if overlap_area <= 0.01:
			if cost < best_clear_cost:
				best_clear_cost = cost
				best_clear_pos = cand
				found_clear = true
		elif overlap_area < best_fallback_area - 0.5 or (absf(overlap_area - best_fallback_area) <= 0.5 and cost < best_fallback_cost):
			best_fallback_area = overlap_area
			best_fallback_cost = cost
			best_fallback_pos = cand

	if found_clear:
		return best_clear_pos

	# Final deterministic sweep across safe playfield grid if rings were crowded.
	for gy: int in range(7):
		var py: float = lerpf(POPUP_SAFE_Y_MIN + 20.0, POPUP_SAFE_Y_MAX - 20.0, float(gy) / 6.0)
		for gx: int in range(5):
			var px: float = lerpf(POPUP_SAFE_X_MIN + 20.0, POPUP_SAFE_X_MAX - 20.0, float(gx) / 4.0)
			var g_cand: Vector2 = _clamp_popup_pos(Vector2(px, py), box_size)
			var g_rect: Rect2 = Rect2(g_cand - half_sz, box_size)
			var g_area: float = _total_overlap_area(g_rect, occupied)
			var g_dx: float = g_cand.x - origin.x
			var g_dy: float = g_cand.y - origin.y
			var g_cost: float = g_dx * g_dx * 1.15 + g_dy * g_dy
			if g_area <= 0.01:
				if g_cost < best_clear_cost:
					best_clear_cost = g_cost
					best_clear_pos = g_cand
					found_clear = true
			elif g_area < best_fallback_area - 0.5 or (absf(g_area - best_fallback_area) <= 0.5 and g_cost < best_fallback_cost):
				best_fallback_area = g_area
				best_fallback_cost = g_cost
				best_fallback_pos = g_cand

	return best_clear_pos if found_clear else best_fallback_pos


static func _rect_intersects_any(rect: Rect2, rects: Array[Rect2]) -> bool:
	for r: Rect2 in rects:
		if rect.intersects(r):
			return true
	return false


static func _total_overlap_area(rect: Rect2, rects: Array[Rect2]) -> float:
	var total: float = 0.0
	for r: Rect2 in rects:
		if rect.intersects(r):
			total += rect.intersection(r).get_area()
	return total


func _push_shard(shard: Dictionary) -> void:
	if _shards.size() >= MAX_SHARDS:
		_shards.remove_at(0)
	_shards.append(shard)


func _push_spark(spark: Dictionary) -> void:
	if _sparks.size() >= MAX_SPARKS:
		_sparks.remove_at(0)
	_sparks.append(spark)


## Triangulation-proof 4-point star built from two strictly convex 4-vertex
## diamonds (horizontal + vertical). Zero concave triangulation errors, 3x faster.
func _draw_four_point_star(center: Vector2, outer_r: float, inner_r: float, col: Color) -> void:
	if outer_r < 1.5 or col.a <= 0.005:
		return
	var r_in: float = clampf(inner_r, 0.6, outer_r * 0.48)
	# Horizontal convex diamond.
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(-outer_r, 0.0),
			center + Vector2(0.0, -r_in),
			center + Vector2(outer_r, 0.0),
			center + Vector2(0.0, r_in),
		]),
		col
	)
	# Vertical convex diamond.
	draw_colored_polygon(
		PackedVector2Array([
			center + Vector2(0.0, -outer_r),
			center + Vector2(r_in, 0.0),
			center + Vector2(0.0, outer_r),
			center + Vector2(-r_in, 0.0),
		]),
		col
	)


## Triangulation-proof N-point starburst built from strictly convex 4-vertex
## rotated diamonds (never passes concave star polygons to draw_colored_polygon).
func _draw_n_point_star(
	center: Vector2,
	outer_r: float,
	inner_r: float,
	points: int,
	rot: float,
	col: Color
) -> void:
	if outer_r < 1.5 or points < 2 or col.a <= 0.005:
		return
	var r_in: float = clampf(inner_r, 0.6, outer_r * 0.45)
	if (points & 1) == 0:
		var half_pts: int = points / 2
		var step: float = PI / float(half_pts)
		for i: int in range(half_pts):
			var ang: float = rot + float(i) * step
			var dir: Vector2 = Vector2(cos(ang), sin(ang))
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			draw_colored_polygon(
				PackedVector2Array([
					center + dir * outer_r,
					center + perp * r_in,
					center - dir * outer_r,
					center - perp * r_in,
				]),
				col
			)
	else:
		var step_odd: float = TAU / float(points)
		for i: int in range(points):
			var ang: float = rot + float(i) * step_odd
			var dir: Vector2 = Vector2(cos(ang), sin(ang))
			var perp: Vector2 = Vector2(-dir.y, dir.x)
			draw_colored_polygon(
				PackedVector2Array([
					center,
					center + perp * r_in,
					center + dir * outer_r,
					center - perp * r_in,
				]),
				col
			)


func _build_chamfered_pill_points(r: Rect2, chamfer: float) -> PackedVector2Array:
	var ch: float = clampf(chamfer, 0.5, minf(r.size.x, r.size.y) * 0.44)
	var x0: float = r.position.x
	var y0: float = r.position.y
	var x1: float = r.end.x
	var y1: float = r.end.y
	return PackedVector2Array([
		Vector2(x0 + ch, y0),
		Vector2(x1 - ch, y0),
		Vector2(x1, y0 + ch),
		Vector2(x1, y1 - ch),
		Vector2(x1 - ch, y1),
		Vector2(x0 + ch, y1),
		Vector2(x0, y1 - ch),
		Vector2(x0, y0 + ch),
	])


func _draw_chamfered_pill(r: Rect2, col: Color, chamfer: float) -> void:
	if r.size.x < 4.0 or r.size.y < 4.0:
		return
	draw_colored_polygon(_build_chamfered_pill_points(r, chamfer), col)


func _draw_chamfered_pill_outline(r: Rect2, col: Color, chamfer: float, width: float) -> void:
	if r.size.x < 4.0 or r.size.y < 4.0:
		return
	var pts: PackedVector2Array = _build_chamfered_pill_points(r, chamfer)
	pts.append(pts[0])
	draw_polyline(pts, col, width, true)


static func _swap_pop(arr: Array[Dictionary], idx: int) -> void:
	var last: int = arr.size() - 1
	if idx != last:
		arr[idx] = arr[last]
	arr.pop_back()


static func _ease_out_quad(t: float) -> float:
	var inv: float = 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - inv * inv


static func _ease_in_quad(t: float) -> float:
	var c: float = clampf(t, 0.0, 1.0)
	return c * c


static func _ease_out_cubic(t: float) -> float:
	var inv: float = 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - inv * inv * inv
