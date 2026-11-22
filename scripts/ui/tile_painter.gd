class_name TilePainter
extends RefCounted

## Static 2D visual primitive library for Kombo's jewel-faceted blocks,
## recessed 8x8 grid cells, multiplier tiles, special blocks (Bomb / Lightning),
## and crisp frosted snapping ghost previews.
##
## Round 2 Performance Architecture:
## - Pre-bakes all 7 jewel tile colors, 2 alternating recessed empty grid cells,
##   Bomb & Lightning beveled bases, and a smooth Gaussian radial glow sprite ONCE
##   on first use into mipmapped 128x128 / 64x64 ImageTextures.
## - Reduces normal board tile rendering from ~12 CPU-triangulated polygons/tile
##   down to ONE GPU-batched draw_texture_rect quad per cell for effortless 60+ FPS.

const SPECIAL_NONE: int = 0
const SPECIAL_BOMB: int = 1
const SPECIAL_LIGHTNING: int = 2

const FONT_EXTRABOLD_PATH: String = "res://assets/fonts/Kanit-ExtraBold.ttf"
const FONT_BOLD_PATH: String = "res://assets/fonts/Kanit-Bold.ttf"

const TILE_TEX_SIZE: int = 128
const GLOW_TEX_SIZE: int = 64

## Rich 7-color saturated jewel palette (color_id 0..6) with hand-tuned hue-shifted
## specular top facets, luminous inner face gradients, and deep saturated shadow bevels.
const PALETTE: Array = [
	# 0: Ruby Red (#F03A47)
	{
		"name": "Ruby",
		"base": Color("#F03A47"),
		"top": Color("#FF94A4"),
		"left": Color("#F95D6B"),
		"face_top": Color("#F44452"),
		"face_bot": Color("#D92336"),
		"right": Color("#B0162A"),
		"bottom": Color("#7B0C1D"),
		"rim": Color("#FFD6DD"),
		"glow": Color("#FF4D63"),
	},
	# 1: Solar Gold (#FFC928)
	{
		"name": "SolarGold",
		"base": Color("#FFC928"),
		"top": Color("#FFF5A3"),
		"left": Color("#FFDD57"),
		"face_top": Color("#FFD036"),
		"face_bot": Color("#F0AB0E"),
		"right": Color("#D17F05"),
		"bottom": Color("#995202"),
		"rim": Color("#FFFDE3"),
		"glow": Color("#FFDA4A"),
	},
	# 2: Tangerine (#FF7A1F)
	{
		"name": "Tangerine",
		"base": Color("#FF7A1F"),
		"top": Color("#FFC48A"),
		"left": Color("#FF9745"),
		"face_top": Color("#FF8026"),
		"face_bot": Color("#E8590C"),
		"right": Color("#BF3D07"),
		"bottom": Color("#872404"),
		"rim": Color("#FFE5C7"),
		"glow": Color("#FF9140"),
	},
	# 3: Emerald (#22D14C)
	{
		"name": "Emerald",
		"base": Color("#22D14C"),
		"top": Color("#9BFFAD"),
		"left": Color("#4EEB72"),
		"face_top": Color("#28DB53"),
		"face_bot": Color("#13B03A"),
		"right": Color("#0B8A2D"),
		"bottom": Color("#065B1D"),
		"rim": Color("#DBFFE3"),
		"glow": Color("#3AF56A"),
	},
	# 4: Royal Blue (#2979FF)
	{
		"name": "RoyalBlue",
		"base": Color("#2979FF"),
		"top": Color("#9ECEFF"),
		"left": Color("#549DFF"),
		"face_top": Color("#3080FF"),
		"face_bot": Color("#1B5CE6"),
		"right": Color("#1141B8"),
		"bottom": Color("#0A2982"),
		"rim": Color("#DCF0FF"),
		"glow": Color("#4F9CFF"),
	},
	# 5: Electric Cyan (#18D5FF)
	{
		"name": "ElectricCyan",
		"base": Color("#18D5FF"),
		"top": Color("#B8F7FF"),
		"left": Color("#5CE6FF"),
		"face_top": Color("#24DAFF"),
		"face_bot": Color("#0AB4E6"),
		"right": Color("#0688B5"),
		"bottom": Color("#045B82"),
		"rim": Color("#E8FDFF"),
		"glow": Color("#4EEAFF"),
	},
	# 6: Amethyst (#A94EFF)
	{
		"name": "Amethyst",
		"base": Color("#A94EFF"),
		"top": Color("#E2B8FF"),
		"left": Color("#C278FF"),
		"face_top": Color("#AE57FF"),
		"face_bot": Color("#8B2EEB"),
		"right": Color("#691BC0"),
		"bottom": Color("#440D87"),
		"rim": Color("#F4DEFF"),
		"glow": Color("#C47AFF"),
	},
]

const BOMB_PALETTE: Dictionary = {
	"top": Color("#994B5C"),
	"left": Color("#6B2D40"),
	"face_top": Color("#301426"),
	"face_bot": Color("#170813"),
	"right": Color("#3A1526"),
	"bottom": Color("#180610"),
	"rim": Color("#FFB094"),
	"glow": Color("#FF4D2E"),
}

const LIGHTNING_PALETTE: Dictionary = {
	"top": Color("#9CF4FF"),
	"left": Color("#5C6EFF"),
	"face_top": Color("#2E1D87"),
	"face_bot": Color("#171054"),
	"right": Color("#1B196E"),
	"bottom": Color("#0E0B42"),
	"rim": Color("#DCF9FF"),
	"glow": Color("#22E8FF"),
}

static var _cached_extrabold: Font = null
static var _cached_bold: Font = null

static var _textures_baked: bool = false
static var _jewel_textures: Array[ImageTexture] = []
static var _empty_cell_textures: Array[ImageTexture] = []
static var _bomb_base_texture: ImageTexture = null
static var _lightning_base_texture: ImageTexture = null
static var _soft_glow_texture: ImageTexture = null


## Safely fetches a jewel palette entry by color_id (wraps cleanly via posmod).
static func get_palette(color_id: int) -> Dictionary:
	return PALETTE[posmod(color_id, PALETTE.size())]


## Safely returns the cached Kanit-ExtraBold font for crisp badges and overlays.
static func get_badge_font() -> Font:
	if _cached_extrabold == null:
		if ResourceLoader.exists(FONT_EXTRABOLD_PATH):
			_cached_extrabold = load(FONT_EXTRABOLD_PATH) as Font
		if _cached_extrabold == null and ResourceLoader.exists(FONT_BOLD_PATH):
			_cached_extrabold = load(FONT_BOLD_PATH) as Font
		if _cached_extrabold == null:
			_cached_extrabold = ThemeDB.fallback_font
	return _cached_extrabold


## Safely returns cached Kanit-Bold font.
static func get_bold_font() -> Font:
	if _cached_bold == null:
		if ResourceLoader.exists(FONT_BOLD_PATH):
			_cached_bold = load(FONT_BOLD_PATH) as Font
		if _cached_bold == null:
			_cached_bold = get_badge_font()
	return _cached_bold


## Returns the pre-baked smooth 64x64 Gaussian radial glow sprite (GPU-batched blooms).
static func get_soft_glow_texture() -> ImageTexture:
	_ensure_textures()
	return _soft_glow_texture


## Returns a pre-baked 128x128 mipmapped beveled jewel ImageTexture for color_id 0..6.
static func get_jewel_texture(color_id: int) -> ImageTexture:
	_ensure_textures()
	return _jewel_textures[posmod(color_id, PALETTE.size())]


## Pre-warms all baked tile & glow textures explicitly (safe to call multiple times).
static func warm_cache() -> void:
	_ensure_textures()


## Draws a GPU-batched pre-baked 4-sided chamfered beveled jewel block in ONE draw call
## (+ optional radiant highlight wash when highlight_boost > 0.01).
static func draw_jewel_tile(
	ci: CanvasItem,
	rect: Rect2,
	color_id: int,
	alpha: float = 1.0,
	scale_inset: float = 1.0,
	highlight_boost: float = 0.0
) -> void:
	if ci == null or alpha <= 0.005 or scale_inset <= 0.01:
		return
	_ensure_textures()

	var draw_rect: Rect2 = rect
	if absf(scale_inset - 1.0) > 0.001:
		var scaled_size: Vector2 = rect.size * scale_inset
		draw_rect = Rect2(rect.get_center() - scaled_size * 0.5, scaled_size)
	if draw_rect.size.x <= 2.0 or draw_rect.size.y <= 2.0:
		return

	var tex: ImageTexture = _jewel_textures[posmod(color_id, PALETTE.size())]
	var boost: float = clampf(highlight_boost, 0.0, 1.0)
	var mod: Color = Color(
		1.0 + boost * 0.28,
		1.0 + boost * 0.28,
		1.0 + boost * 0.28,
		alpha
	)
	ci.draw_texture_rect(tex, draw_rect, false, mod)

	if boost > 0.01:
		var pal: Dictionary = get_palette(color_id)
		var c_glow: Color = pal["glow"] as Color
		var min_dim: float = minf(draw_rect.size.x, draw_rect.size.y)
		var inset_px: float = clampf(min_dim * 0.032, 1.0, 2.0)
		var inner_rect: Rect2 = draw_rect.grow(-inset_px)
		ci.draw_rect(inner_rect, Color(1.0, 0.99, 0.90, boost * 0.28 * alpha), true)
		ci.draw_rect(inner_rect, Color(c_glow.r, c_glow.g, c_glow.b, boost * 0.60 * alpha), false, 2.0, true)


## Draws a GPU-batched pre-baked empty recessed navy 8x8 grid slot; renders a glowing
## high-contrast x2 or x3 Multiplier Tile when mult_value >= 2.
static func draw_empty_cell(
	ci: CanvasItem,
	rect: Rect2,
	row: int,
	col: int,
	mult_value: int,
	time_sec: float
) -> void:
	if ci == null or rect.size.x <= 2.0 or rect.size.y <= 2.0:
		return
	_ensure_textures()

	var alt_idx: int = (row + col) & 1
	ci.draw_texture_rect(_empty_cell_textures[alt_idx], rect, false)

	if mult_value < 2:
		return

	var pulse: float = 0.5 + 0.5 * sin(time_sec * 3.4 + float(row * 3 + col * 5) * 0.45)
	var is_x3: bool = mult_value >= 3

	# Centered high-contrast frameless multiplier text ("×2" / "×3") with soft ambient glow.
	var badge_text: String = "×%d" % mult_value
	var min_dim: float = minf(rect.size.x, rect.size.y)
	var font_size: int = maxi(14, int(round(min_dim * 0.38)))
	var center: Vector2 = rect.get_center()

	var halo_col: Color = Color(1.0, 0.28, 0.85, 0.28 + pulse * 0.14) if is_x3 else Color(0.14, 0.88, 1.0, 0.26 + pulse * 0.12)
	var halo_size: float = min_dim * 0.78
	ci.draw_texture_rect(
		_soft_glow_texture,
		Rect2(center - Vector2(halo_size, halo_size) * 0.5, Vector2(halo_size, halo_size)),
		false,
		halo_col
	)

	var text_fill: Color = Color("#FFF3A8") if is_x3 else Color("#E6FCFF")
	var text_outline: Color = Color("#3D0630") if is_x3 else Color("#06233B")
	_draw_centered_outlined_text(ci, get_badge_font(), center, badge_text, font_size, text_fill, text_outline, 4)


## Re-illuminates an underlying x2/x3 multiplier tile RIGHT THROUGH a hovering frosted ghost
## so the player always reads bonus multipliers with 100% clarity while dragging.
static func draw_ghost_mult_passthrough(
	ci: CanvasItem,
	rect: Rect2,
	mult_value: int,
	time_sec: float
) -> void:
	if ci == null or mult_value < 2 or rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return
	_ensure_textures()

	var is_x3: bool = mult_value >= 3
	var pulse: float = 0.5 + 0.5 * sin(time_sec * 6.5)
	var min_dim: float = minf(rect.size.x, rect.size.y)
	var center: Vector2 = rect.get_center()

	# Soft radiant halo behind the frameless numeral so it shines crisply through frosted ghost glass.
	var halo_col: Color = Color(1.0, 0.34, 0.88, 0.36 + pulse * 0.18) if is_x3 else Color(0.16, 0.92, 1.0, 0.34 + pulse * 0.16)
	var halo_size: float = min_dim * 0.82
	ci.draw_texture_rect(
		_soft_glow_texture,
		Rect2(center - Vector2(halo_size, halo_size) * 0.5, Vector2(halo_size, halo_size)),
		false,
		halo_col
	)

	var font_size: int = maxi(15, int(round(min_dim * 0.39)))
	var text_fill: Color = Color("#FFF7BD") if is_x3 else Color("#F0FEFF")
	var text_outline: Color = Color("#3A052E") if is_x3 else Color("#04223B")
	_draw_centered_outlined_text(ci, get_badge_font(), center, "×%d" % mult_value, font_size, text_fill, text_outline, 4)


## Draws crisp Gem Hunt target overlays (Crystal Gem, Frozen Ice 2-HP / Cracked 1-HP, or Cursed Padlock)
## directly on top of an occupied jewel tile at 60+ FPS with zero concave triangulation.
static func draw_target_overlay(
	ci: CanvasItem,
	rect: Rect2,
	target_type: int,
	target_hp: int,
	time_sec: float
) -> void:
	if ci == null or target_type == BoardState.TargetType.NONE or rect.size.x <= 4.0:
		return
	_ensure_textures()

	var center: Vector2 = rect.get_center()
	var s: float = minf(rect.size.x, rect.size.y)
	var pulse: float = 0.5 + 0.5 * sin(time_sec * 4.4 + (rect.position.x + rect.position.y) * 0.04)

	match target_type:
		BoardState.TargetType.CRYSTAL:
			# Soft radiant cyan-gold crystal aura + gleaming corner target brackets.
			var glow_sz: float = s * 1.10
			ci.draw_texture_rect(
				_soft_glow_texture,
				Rect2(center - Vector2(glow_sz, glow_sz) * 0.5, Vector2(glow_sz, glow_sz)),
				false,
				Color(0.28, 0.94, 1.0, 0.30 + 0.14 * pulse)
			)
			var inner: Rect2 = rect.grow(-s * 0.06)
			ci.draw_rect(inner, Color("#8CF9FF", 0.72 + 0.24 * pulse), false, 2.0, true)

			# Multi-faceted prism diamond crystal centerpiece (pure convex polygons!).
			var rx: float = s * 0.27
			var ry: float = s * 0.33
			var outer_pts := PackedVector2Array([
				center + Vector2(0.0, -ry),
				center + Vector2(rx, 0.0),
				center + Vector2(0.0, ry),
				center + Vector2(-rx, 0.0),
			])
			var shadow_pts := PackedVector2Array()
			for pt in outer_pts:
				shadow_pts.append(pt + Vector2(0.0, 2.0))
			ci.draw_colored_polygon(shadow_pts, Color(0.03, 0.06, 0.18, 0.62))
			var outline := outer_pts.duplicate()
			outline.append(outer_pts[0])
			ci.draw_polyline(outline, Color("#0A244D"), 3.6, true)
			ci.draw_colored_polygon(outer_pts, Color("#40EFFF"))

			# Upper-left bright crystal bevel facet + incandescent white core.
			ci.draw_colored_polygon(
				PackedVector2Array([
					center + Vector2(0.0, -ry * 0.92),
					center + Vector2(rx * 0.45, -ry * 0.12),
					center + Vector2(-rx * 0.10, ry * 0.12),
					center + Vector2(-rx * 0.92, 0.0),
				]),
				Color("#D6FEFF", 0.85)
			)
			ci.draw_colored_polygon(
				PackedVector2Array([
					center + Vector2(0.0, -ry * 0.42),
					center + Vector2(rx * 0.36, 0.0),
					center + Vector2(0.0, ry * 0.42),
					center + Vector2(-rx * 0.36, 0.0),
				]),
				Color("#FFFFFF", 0.94)
			)
			# Crisp glint dot on upper tip.
			ci.draw_circle(center + Vector2(-rx * 0.12, -ry * 0.52), maxf(1.6, s * 0.042), Color("#FFFDE0"))

		BoardState.TargetType.ICE:
			# Glacial translucent ice glaze + frosted border.
			var solid: bool = target_hp >= 2
			var inner: Rect2 = rect.grow(-s * 0.04)
			var ice_fill := Color(0.72, 0.96, 1.0, 0.46 if solid else 0.24)
			ci.draw_rect(inner, ice_fill, true)

			# Diagonal glacial sheen stripe.
			ci.draw_colored_polygon(
				PackedVector2Array([
					Vector2(inner.position.x + s * 0.08, inner.position.y),
					Vector2(inner.position.x + s * 0.44, inner.position.y),
					Vector2(inner.position.x + s * 0.16, inner.end.y),
					Vector2(inner.position.x, inner.end.y),
				]),
				Color(1.0, 1.0, 1.0, 0.34 if solid else 0.16)
			)
			ci.draw_rect(inner, Color("#E6FDFF", 0.92 if solid else 0.65), false, 2.6 if solid else 1.8, true)

			if solid:
				# Crisp 6-ray winter snow crystal signifying sturdy 2-hit Frozen Ice!
				var r: float = s * 0.24
				for k in range(3):
					var a := float(k) * (PI / 3.0) + PI * 0.167
					var d := Vector2(cos(a), sin(a)) * r
					ci.draw_line(center - d, center + d, Color("#0C3B66", 0.72), 3.6, true)
					ci.draw_line(center - d, center + d, Color("#FFFFFF", 0.95), 2.0, true)
				ci.draw_circle(center, s * 0.075, Color("#D8FCFF"))
			else:
				# Sharp radiating frost cracks clearly showing 1-hit cracked ice!
				var cracks: Array = [
					[center + Vector2(-s * 0.32, -s * 0.26), center + Vector2(-s * 0.06, -s * 0.04), center + Vector2(s * 0.10, s * 0.08), center + Vector2(s * 0.34, s * 0.24)],
					[center + Vector2(s * 0.28, -s * 0.30), center + Vector2(s * 0.04, -s * 0.02), center + Vector2(-s * 0.24, s * 0.28)],
					[center + Vector2(-s * 0.06, -s * 0.04), center + Vector2(-s * 0.34, s * 0.06)],
				]
				for seg in cracks:
					var pts := PackedVector2Array(seg)
					ci.draw_polyline(pts, Color("#0A2A52", 0.88), 3.0, true)
					ci.draw_polyline(pts, Color("#E6FEFF", 0.92), 1.3, true)

		BoardState.TargetType.PADLOCK:
			# Subtle cursed obsidian-gold vignette + pulsing gold frame.
			var inner: Rect2 = rect.grow(-s * 0.05)
			ci.draw_rect(inner, Color(0.14, 0.03, 0.12, 0.34), true)
			ci.draw_rect(inner, Color("#FFD43B", 0.72 + 0.24 * pulse), false, 2.0, true)

			# Gleaming Golden Padlock shackle arc + solid beveled lock body + keyhole.
			var shackle_c := center + Vector2(0.0, -s * 0.10)
			var shackle_r := s * 0.14
			ci.draw_arc(shackle_c, shackle_r, PI, TAU, 16, Color("#3B1B00"), 5.2, true)
			ci.draw_arc(shackle_c, shackle_r, PI, TAU, 16, Color("#FFE26A"), 2.8, true)

			var body_w := s * 0.42
			var body_h := s * 0.33
			var body := Rect2(center.x - body_w * 0.5, center.y - s * 0.08, body_w, body_h)
			ci.draw_rect(body.grow(1.4), Color("#3B1B00"), true)
			ci.draw_rect(body, Color("#FFB81C"), true)
			ci.draw_rect(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.38)), Color("#FFF3A6", 0.55), true)

			# Crisp dark keyhole silhouette.
			var kh := body.get_center() + Vector2(0.0, -s * 0.02)
			ci.draw_circle(kh, maxf(2.2, s * 0.058), Color("#2B1100"))
			ci.draw_colored_polygon(
				PackedVector2Array([
					kh + Vector2(-s * 0.032, s * 0.02),
					kh + Vector2(s * 0.032, s * 0.02),
					kh + Vector2(s * 0.044, s * 0.12),
					kh + Vector2(-s * 0.044, s * 0.12),
				]),
				Color("#2B1100")
			)


## Draws a crisp frameless multiplier numeral on top of an occupied jewel block
## sitting on an x2/x3 board cell so active multipliers are NEVER obscured.
static func draw_occupied_mult_badge(
	ci: CanvasItem,
	rect: Rect2,
	mult_value: int,
	time_sec: float
) -> void:
	if ci == null or mult_value < 2 or rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return
	_ensure_textures()

	var is_x3: bool = mult_value >= 3
	var pulse: float = 0.5 + 0.5 * sin(time_sec * 4.4)
	var min_dim: float = minf(rect.size.x, rect.size.y)
	var center: Vector2 = rect.get_center()

	var halo_col: Color = Color(1.0, 0.28, 0.88, 0.34 + pulse * 0.16) if is_x3 else Color(0.15, 0.91, 1.0, 0.32 + pulse * 0.14)
	var halo_size: float = min_dim * 0.76
	ci.draw_texture_rect(
		_soft_glow_texture,
		Rect2(center - Vector2(halo_size, halo_size) * 0.5, Vector2(halo_size, halo_size)),
		false,
		halo_col
	)

	var font_size: int = maxi(14, int(round(min_dim * 0.36)))
	var text_col: Color = Color("#FFF4A3") if is_x3 else Color("#E8FDFF")
	var outline_col: Color = Color("#2C0422") if is_x3 else Color("#04192E")
	_draw_centered_outlined_text(ci, get_badge_font(), center, "×%d" % mult_value, font_size, text_col, outline_col, 4)


## Draws unmistakable premium special power-up tiles (pre-baked beveled base + crisp live FX):
## special_type == 1 (BOMB): Obsidian-crimson beveled metallic block + sparkling fuse bomb.
## special_type == 2 (LIGHTNING): Electric royal-violet/cyan beveled crystal + crackling bolt.
static func draw_special_tile(
	ci: CanvasItem,
	rect: Rect2,
	special_type: int,
	time_sec: float,
	alpha: float = 1.0
) -> void:
	if ci == null or alpha <= 0.005 or rect.size.x <= 4.0 or rect.size.y <= 4.0:
		return
	_ensure_textures()

	if special_type == SPECIAL_BOMB:
		_draw_bomb_tile(ci, rect, time_sec, alpha)
	elif special_type == SPECIAL_LIGHTNING:
		_draw_lightning_tile(ci, rect, time_sec, alpha)


## Draws the crisp frosted-white luminous drag snap ghost preview (ZERO murky olive!),
## or floods with radiant gold/piece-color clear anticipation energy when will_clear == true.
static func draw_ghost_cell(
	ci: CanvasItem,
	rect: Rect2,
	color_id: int,
	will_clear: bool,
	special_type: int,
	time_sec: float
) -> void:
	if ci == null or rect.size.x <= 2.0 or rect.size.y <= 2.0:
		return
	_ensure_textures()

	var pal: Dictionary = get_palette(color_id)
	var pulse: float = 0.5 + 0.5 * sin(time_sec * 9.5)
	var glow_base: Color = pal["glow"] as Color

	if special_type == SPECIAL_BOMB:
		glow_base = Color("#FF6A2E")
	elif special_type == SPECIAL_LIGHTNING:
		glow_base = Color("#28E8FF")

	var inset_rect: Rect2 = rect.grow(-1.1)
	var center: Vector2 = rect.get_center()
	var min_dim: float = minf(rect.size.x, rect.size.y)

	if will_clear:
		# Radiant gold/piece-color clear energy wash + soft luminous outer bloom!
		var clear_gold: Color = Color("#FFD94A").lerp(glow_base, 0.38)
		var bloom_size: float = min_dim * 1.48
		ci.draw_texture_rect(
			_soft_glow_texture,
			Rect2(center - Vector2(bloom_size, bloom_size) * 0.5, Vector2(bloom_size, bloom_size)),
			false,
			Color(clear_gold.r, clear_gold.g, clear_gold.b, 0.34 + pulse * 0.18)
		)

		# Luminous frosted-gold translucent interior (keeps x2/x3 tiles clear underneath!).
		var clear_fill: Color = Color(1.0, 0.98, 0.88, 1.0).lerp(clear_gold, 0.34)
		clear_fill.a = 0.32 + pulse * 0.14
		ci.draw_rect(inset_rect, clear_fill, true)

		# Upper frosted specular glass highlight band.
		var sheen_rect: Rect2 = Rect2(inset_rect.position, Vector2(inset_rect.size.x, inset_rect.size.y * 0.28))
		ci.draw_rect(sheen_rect, Color(1.0, 1.0, 1.0, 0.24 + pulse * 0.10), true)

		if special_type == SPECIAL_BOMB or special_type == SPECIAL_LIGHTNING:
			draw_special_tile(ci, rect.grow(-1.6), special_type, time_sec, 0.70 + pulse * 0.12)

		# Bright pulsing 2.8px white-gold outer frame + soft gold halo.
		var outer_halo: Color = Color(clear_gold.r, clear_gold.g, clear_gold.b, 0.68 + pulse * 0.28)
		var hot_border: Color = Color("#FFF4B8").lerp(Color.WHITE, 0.45 + pulse * 0.42)
		hot_border.a = 0.98
		ci.draw_rect(inset_rect.grow(1.1), outer_halo, false, 4.8, true)
		ci.draw_rect(inset_rect, hot_border, false, 2.8, true)
	else:
		# Soft outer bloom behind crisp frosted-white silhouette.
		var bloom_size: float = min_dim * 1.38
		ci.draw_texture_rect(
			_soft_glow_texture,
			Rect2(center - Vector2(bloom_size, bloom_size) * 0.5, Vector2(bloom_size, bloom_size)),
			false,
			Color(1.0, 1.0, 1.0, 0.16)
		)

		# Crisp frosted-white translucent cell silhouette (tinted by jewel color ONLY 15%!).
		var frosted: Color = Color.WHITE.lerp(glow_base, 0.15)
		frosted.a = 0.22
		ci.draw_rect(inset_rect, frosted, true)

		# Delicate frosted upper specular sheen band.
		var sheen_rect: Rect2 = Rect2(inset_rect.position, Vector2(inset_rect.size.x, inset_rect.size.y * 0.25))
		ci.draw_rect(sheen_rect, Color(1.0, 1.0, 1.0, 0.11), true)

		if special_type == SPECIAL_BOMB or special_type == SPECIAL_LIGHTNING:
			draw_special_tile(ci, rect.grow(-1.6), special_type, time_sec, 0.60)

		# Soft outer luminous rim bloom + razor-sharp 2.2px white outer frame!
		var outer_soft: Color = Color.WHITE.lerp(glow_base, 0.20)
		outer_soft.a = 0.28
		ci.draw_rect(inset_rect.grow(1.0), outer_soft, false, 4.2, true)
		ci.draw_rect(inset_rect, Color(1.0, 1.0, 1.0, 0.90), false, 2.2, true)


# ==============================================================================
# PRE-BAKED TEXTURE GENERATION (RUNS ONCE ON FIRST USE)
# ==============================================================================

static func _ensure_textures() -> void:
	if _textures_baked:
		return
	_textures_baked = true

	_jewel_textures.clear()
	for i: int in range(PALETTE.size()):
		_jewel_textures.append(_bake_beveled_tile_texture(PALETTE[i] as Dictionary))

	_empty_cell_textures.clear()
	_empty_cell_textures.append(_bake_empty_cell_texture(false))
	_empty_cell_textures.append(_bake_empty_cell_texture(true))

	_bomb_base_texture = _bake_beveled_tile_texture(BOMB_PALETTE)
	_lightning_base_texture = _bake_beveled_tile_texture(LIGHTNING_PALETTE)
	_soft_glow_texture = _bake_soft_glow_texture()


## Pixel-perfect 128x128 4-trapezoid beveled jewel tile with chamfered corners,
## smooth miter seams, glossy top sheen, specular ridge, top-left crystal diamond glint,
## and crisp dark recessed outer groove.
static func _bake_beveled_tile_texture(pal: Dictionary) -> ImageTexture:
	var s: int = TILE_TEX_SIZE
	var sf: float = float(s)
	var half: float = sf * 0.5

	var groove: float = 3.5
	var outer_min: float = groove
	var outer_max: float = sf - groove
	var chamfer: float = 5.2
	var bevel: float = 21.0
	var inner_min: float = outer_min + bevel
	var inner_max: float = outer_max - bevel
	var inner_span: float = inner_max - inner_min

	var glint_x: float = inner_min + 2.4
	var glint_y: float = inner_min + 2.4

	var c_top: Color = pal["top"] as Color
	var c_left: Color = pal["left"] as Color
	var c_ft: Color = pal["face_top"] as Color
	var c_fb: Color = pal["face_bot"] as Color
	var c_right: Color = pal["right"] as Color
	var c_bot: Color = pal["bottom"] as Color
	var c_rim: Color = pal["rim"] as Color

	var top_r: float = c_top.r
	var top_g: float = c_top.g
	var top_b: float = c_top.b
	var left_r: float = c_left.r
	var left_g: float = c_left.g
	var left_b: float = c_left.b
	var ft_r: float = c_ft.r
	var ft_g: float = c_ft.g
	var ft_b: float = c_ft.b
	var fb_r: float = c_fb.r
	var fb_g: float = c_fb.g
	var fb_b: float = c_fb.b
	var right_r: float = c_right.r
	var right_g: float = c_right.g
	var right_b: float = c_right.b
	var bot_r: float = c_bot.r
	var bot_g: float = c_bot.g
	var bot_b: float = c_bot.b
	var rim_r: float = c_rim.r
	var rim_g: float = c_rim.g
	var rim_b: float = c_rim.b

	# Dark recessed groove (#0D1226 @ 94% alpha)
	const GR_R: float = 0.051
	const GR_G: float = 0.071
	const GR_B: float = 0.149
	const GR_A: float = 0.94

	var data: PackedByteArray = PackedByteArray()
	data.resize(s * s * 4)

	var idx: int = 0
	for py: int in range(s):
		var cy: float = float(py) + 0.5
		var dy0: float = cy - outer_min
		var dy1: float = outer_max - cy
		var ly: float = cy - half
		var aly: float = absf(ly)
		var d_iy: float = minf(cy - inner_min, inner_max - cy)
		var v_face: float = clampf((cy - inner_min) / inner_span, 0.0, 1.0)
		var dy_box: float = minf(dy0, dy1)

		var face_row_r: float = ft_r + (fb_r - ft_r) * v_face
		var face_row_g: float = ft_g + (fb_g - ft_g) * v_face
		var face_row_b: float = ft_b + (fb_b - ft_b) * v_face

		var sheen_amt: float = 0.0
		if v_face < 0.36:
			var sn: float = 1.0 - v_face / 0.36
			sheen_amt = 0.24 * sn * sn

		var dist_top_r: float = absf(cy - inner_min)
		var dist_bot_c: float = absf(cy - inner_max)
		var d_glint_y: float = absf(cy - glint_y)

		for px: int in range(s):
			var cx: float = float(px) + 0.5
			var dx0: float = cx - outer_min
			var dx1: float = outer_max - cx
			var d_box: float = minf(minf(dx0, dx1), dy_box)
			var d_tl: float = (dx0 + dy0) - chamfer
			var d_tr: float = (dx1 + dy0) - chamfer
			var d_br: float = (dx1 + dy1) - chamfer
			var d_bl: float = (dx0 + dy1) - chamfer
			var d_outer: float = minf(d_box, minf(minf(d_tl, d_tr), minf(d_br, d_bl)))

			if d_outer <= -0.6:
				data[idx] = 13
				data[idx + 1] = 18
				data[idx + 2] = 38
				data[idx + 3] = 240
				idx += 4
				continue

			var lx: float = cx - half
			var alx: float = absf(lx)
			var d_ix: float = minf(cx - inner_min, inner_max - cx)
			var d_inner: float = minf(d_ix, d_iy)

			var pr: float = 0.0
			var pg: float = 0.0
			var pb: float = 0.0

			# Compute inner face color if inside or near inner edge
			var fr: float = face_row_r
			var fg: float = face_row_g
			var fb: float = face_row_b
			if d_inner > -1.2:
				if sheen_amt > 0.001:
					fr += (rim_r - fr) * sheen_amt
					fg += (rim_g - fg) * sheen_amt
					fb += (rim_b - fb) * sheen_amt
				# Subtle center convex crystal luster
				var ux: float = (cx - 64.0) * 0.020
				var vy: float = (cy - 54.0) * 0.020
				var rad2: float = ux * ux + vy * vy
				if rad2 < 1.0:
					var lus: float = (1.0 - rad2) * 0.08
					fr += (rim_r - fr) * lus
					fg += (rim_g - fg) * lus
					fb += (rim_b - fb) * lus

			if d_inner >= 1.2:
				pr = fr
				pg = fg
				pb = fb
			else:
				# Compute 4-trapezoid beveled side with anti-aliased 45-degree miter seams
				var vr: float = top_r if ly < 0.0 else bot_r
				var vg: float = top_g if ly < 0.0 else bot_g
				var vb: float = top_b if ly < 0.0 else bot_b
				var hr: float = left_r if lx < 0.0 else right_r
				var hg: float = left_g if lx < 0.0 else right_g
				var hb: float = left_b if lx < 0.0 else right_b

				var miter: float = clampf((aly - alx) * 0.72 + 0.5, 0.0, 1.0)
				var br: float = hr + (vr - hr) * miter
				var bg: float = hg + (vg - hg) * miter
				var bb: float = hb + (vb - hb) * miter

				# Gentle bevel shading gradient from outer rim toward inner ridge
				var depth_t: float = clampf(d_box / bevel, 0.0, 1.0)
				if ly < 0.0 and miter > 0.5:
					var top_bright: float = depth_t * 0.14
					br += (rim_r - br) * top_bright
					bg += (rim_g - bg) * top_bright
					bb += (rim_b - bb) * top_bright
				elif ly > 0.0 and miter > 0.5:
					var bot_deep: float = (1.0 - depth_t) * 0.12
					br *= (1.0 - bot_deep)
					bg *= (1.0 - bot_deep)
					bb *= (1.0 - bot_deep)

				# Outer top specular catch glint
				if dy0 >= 0.0 and dy0 < 2.6 and ly < 0.0 and miter > 0.5:
					var lip: float = (1.0 - dy0 / 2.6) * 0.48
					br += (rim_r - br) * lip
					bg += (rim_g - bg) * lip
					bb += (rim_b - bb) * lip

				# Polished top-left chamfer corner sheen
				if lx < 0.0 and ly < 0.0 and (dx0 + dy0) < (chamfer + 12.0):
					var corner_t: float = clampf(1.0 - (dx0 + dy0 - chamfer) / 12.0, 0.0, 1.0) * 0.42
					br += (rim_r - br) * corner_t
					bg += (rim_g - bg) * corner_t
					bb += (rim_b - bb) * corner_t
				elif lx > 0.0 and ly > 0.0 and (dx1 + dy1) < (chamfer + 12.0):
					var corner_d: float = clampf(1.0 - (dx1 + dy1 - chamfer) / 12.0, 0.0, 1.0) * 0.16
					br *= (1.0 - corner_d)
					bg *= (1.0 - corner_d)
					bb *= (1.0 - corner_d)

				if d_inner <= -1.2:
					pr = br
					pg = bg
					pb = bb
				else:
					var tf: float = clampf((d_inner + 0.7) / 1.4, 0.0, 1.0)
					pr = br + (fr - br) * tf
					pg = bg + (fg - bg) * tf
					pb = bb + (fb - bb) * tf

			# Crisp inner specular ridge lines (top & left) and subtle shadow creases (bottom & right)
			if dist_top_r < 2.3 and cx >= inner_min - 1.2 and cx <= inner_max + 1.2:
				var rt: float = (1.0 - dist_top_r / 2.3) * 0.84
				pr += (rim_r - pr) * rt
				pg += (rim_g - pg) * rt
				pb += (rim_b - pb) * rt

			var dist_left_r: float = absf(cx - inner_min)
			if dist_left_r < 1.9 and cy >= inner_min - 0.5 and cy <= inner_max + 0.5:
				var rl: float = (1.0 - dist_left_r / 1.9) * 0.40
				pr += (rim_r - pr) * rl
				pg += (rim_g - pg) * rl
				pb += (rim_b - pb) * rl

			if dist_bot_c < 1.8 and cx >= inner_min and cx <= inner_max + 0.8:
				var cb: float = (1.0 - dist_bot_c / 1.8) * 0.42
				pr += (bot_r - pr) * cb
				pg += (bot_g - pg) * cb
				pb += (bot_b - pb) * cb

			var dist_right_c: float = absf(cx - inner_max)
			if dist_right_c < 1.8 and cy >= inner_min and cy <= inner_max + 0.8:
				var cr: float = (1.0 - dist_right_c / 1.8) * 0.38
				pr += (bot_r - pr) * cr
				pg += (bot_g - pg) * cr
				pb += (bot_b - pb) * cr

			# Cut-crystal diamond glint at top-left inner corner
			if d_glint_y < 7.2:
				var d_glint: float = absf(cx - glint_x) + d_glint_y
				if d_glint < 7.2:
					var gt: float = 1.0 - d_glint / 7.2
					var gl: float = gt * gt * 0.78
					pr += (1.0 - pr) * gl
					pg += (1.0 - pg) * gl
					pb += (1.0 - pb) * gl

			# Anti-aliased composite against outer recessed dark groove
			var pa: float = 1.0
			if d_outer < 0.6:
				var t_out: float = clampf((d_outer + 0.6) / 1.2, 0.0, 1.0)
				pr = GR_R + (pr - GR_R) * t_out
				pg = GR_G + (pg - GR_G) * t_out
				pb = GR_B + (pb - GR_B) * t_out
				pa = GR_A + (1.0 - GR_A) * t_out

			data[idx] = clampi(int(pr * 255.0 + 0.5), 0, 255)
			data[idx + 1] = clampi(int(pg * 255.0 + 0.5), 0, 255)
			data[idx + 2] = clampi(int(pb * 255.0 + 0.5), 0, 255)
			data[idx + 3] = clampi(int(pa * 255.0 + 0.5), 0, 255)
			idx += 4

	var img: Image = Image.create_from_data(s, s, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Pixel-perfect 128x128 recessed navy grid cavity cell texture (alternating subtle tones).
static func _bake_empty_cell_texture(is_alt: bool) -> ImageTexture:
	var s: int = TILE_TEX_SIZE
	var sf: float = float(s)
	var groove: float = 3.2
	var inner_min: float = groove
	var inner_max: float = sf - groove
	var inner_span: float = inner_max - inner_min
	var corner_r: float = 4.2

	# Outer dark seam (#111731 @ 0.96)
	const SEAM_R: float = 0.067
	const SEAM_G: float = 0.090
	const SEAM_B: float = 0.192
	const SEAM_A: float = 0.96

	var base_c: Color = Color("#1F284E") if is_alt else Color("#1C2446")
	var base_r: float = base_c.r
	var base_g: float = base_c.g
	var base_b: float = base_c.b

	# Carved top/left inner shadow (#121833) and subtle bottom/right catch-light (#2F3D72)
	const SH_R: float = 0.071
	const SH_G: float = 0.094
	const SH_B: float = 0.200
	const CA_R: float = 0.184
	const CA_G: float = 0.239
	const CA_B: float = 0.447

	var data: PackedByteArray = PackedByteArray()
	data.resize(s * s * 4)

	var idx: int = 0
	var half_inner: float = inner_span * 0.5
	var half: float = sf * 0.5

	for py: int in range(s):
		var cy: float = float(py) + 0.5
		var dy0: float = cy - inner_min
		var dy1: float = inner_max - cy
		var v: float = clampf(dy0 / inner_span, 0.0, 1.0)
		var qy: float = maxf(absf(cy - half) - (half_inner - corner_r), 0.0)

		for px: int in range(s):
			var cx: float = float(px) + 0.5
			var dx0: float = cx - inner_min
			var dx1: float = inner_max - cx
			var qx: float = maxf(absf(cx - half) - (half_inner - corner_r), 0.0)
			var sdf: float = sqrt(qx * qx + qy * qy) - corner_r

			if sdf >= 0.6:
				data[idx] = 17
				data[idx + 1] = 23
				data[idx + 2] = 49
				data[idx + 3] = 245
				idx += 4
				continue

			# Subtle recessed cavity vertical depth shading
			var shade: float = 0.95 + 0.07 * v
			var pr: float = base_r * shade
			var pg: float = base_g * shade
			var pb: float = base_b * shade

			# Top & left carved inner shadow lip
			if dy0 < 4.2:
				var st: float = (1.0 - maxf(dy0, 0.0) / 4.2) * 0.78
				pr += (SH_R - pr) * st
				pg += (SH_G - pg) * st
				pb += (SH_B - pb) * st
			if dx0 < 4.2:
				var sl: float = (1.0 - maxf(dx0, 0.0) / 4.2) * 0.74
				pr += (SH_R - pr) * sl
				pg += (SH_G - pg) * sl
				pb += (SH_B - pb) * sl

			# Bottom & right subtle catch-light rim
			if dy1 < 2.6:
				var cb: float = (1.0 - maxf(dy1, 0.0) / 2.6) * 0.52
				pr += (CA_R - pr) * cb
				pg += (CA_G - pg) * cb
				pb += (CA_B - pb) * cb
			if dx1 < 2.6:
				var cr: float = (1.0 - maxf(dx1, 0.0) / 2.6) * 0.48
				pr += (CA_R - pr) * cr
				pg += (CA_G - pg) * cr
				pb += (CA_B - pb) * cr

			var pa: float = 1.0
			if sdf > -0.6:
				var t_in: float = clampf((0.6 - sdf) / 1.2, 0.0, 1.0)
				pr = SEAM_R + (pr - SEAM_R) * t_in
				pg = SEAM_G + (pg - SEAM_G) * t_in
				pb = SEAM_B + (pb - SEAM_B) * t_in
				pa = SEAM_A + (1.0 - SEAM_A) * t_in

			data[idx] = clampi(int(pr * 255.0 + 0.5), 0, 255)
			data[idx + 1] = clampi(int(pg * 255.0 + 0.5), 0, 255)
			data[idx + 2] = clampi(int(pb * 255.0 + 0.5), 0, 255)
			data[idx + 3] = clampi(int(pa * 255.0 + 0.5), 0, 255)
			idx += 4

	var img: Image = Image.create_from_data(s, s, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Pre-bakes a smooth white 64x64 radial Gaussian-like glow texture for silky GPU blooms.
static func _bake_soft_glow_texture() -> ImageTexture:
	var s: int = GLOW_TEX_SIZE
	var half: float = float(s) * 0.5
	var inv_r: float = 1.0 / (half - 0.5)
	var data: PackedByteArray = PackedByteArray()
	data.resize(s * s * 4)

	var idx: int = 0
	for py: int in range(s):
		var dy: float = (float(py) + 0.5 - half) * inv_r
		var dy2: float = dy * dy
		for px: int in range(s):
			var dx: float = (float(px) + 0.5 - half) * inv_r
			var r2: float = dx * dx + dy2
			var a: int = 0
			if r2 < 1.0:
				var fall: float = 1.0 - r2
				a = clampi(int(pow(fall, 2.35) * 255.0 + 0.5), 0, 255)
			data[idx] = 255
			data[idx + 1] = 255
			data[idx + 2] = 255
			data[idx + 3] = a
			idx += 4

	var img: Image = Image.create_from_data(s, s, false, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(img)


# ==============================================================================
# SPECIAL TILES & VECTOR HELPERS
# ==============================================================================

static func _draw_bomb_tile(ci: CanvasItem, rect: Rect2, time_sec: float, alpha: float) -> void:
	var pulse: float = 0.5 + 0.5 * sin(time_sec * 6.4)
	var mod: Color = Color(1.0 + pulse * 0.14, 1.0 + pulse * 0.10, 1.0 + pulse * 0.08, alpha)
	ci.draw_texture_rect(_bomb_base_texture, rect, false, mod)

	var min_dim: float = minf(rect.size.x, rect.size.y)
	var center: Vector2 = rect.get_center()

	# Pulsing crimson-amber danger glow + ring inside the dark metallic face.
	var halo_s: float = min_dim * (0.86 + pulse * 0.08)
	ci.draw_texture_rect(
		_soft_glow_texture,
		Rect2(center - Vector2(halo_s, halo_s) * 0.5, Vector2(halo_s, halo_s)),
		false,
		Color(1.0, 0.30, 0.12, (0.42 + pulse * 0.22) * alpha)
	)
	var ring_r: float = min_dim * 0.305
	ci.draw_circle(center, ring_r, Color(1.0, 0.56, 0.20, (0.56 + pulse * 0.38) * alpha), false, 2.0, true)

	# Iconic spherical bomb body.
	var bomb_center: Vector2 = center + Vector2(-min_dim * 0.05, min_dim * 0.065)
	var bomb_r: float = min_dim * 0.23

	ci.draw_circle(bomb_center, bomb_r + 1.6, Color(1.0, 0.45, 0.22, (0.76 + pulse * 0.22) * alpha))
	ci.draw_circle(bomb_center, bomb_r, Color(0.13, 0.13, 0.19, alpha))
	ci.draw_circle(bomb_center + Vector2(-bomb_r * 0.15, -bomb_r * 0.15), bomb_r * 0.72, Color(0.28, 0.26, 0.38, 0.76 * alpha))
	ci.draw_circle(bomb_center + Vector2(-bomb_r * 0.34, -bomb_r * 0.34), bomb_r * 0.27, Color(1.0, 0.93, 0.88, 0.94 * alpha))

	# Metallic fuse collar cap.
	var collar_dir: Vector2 = Vector2(0.72, -0.70).normalized()
	var collar_perp: Vector2 = Vector2(-collar_dir.y, collar_dir.x)
	var collar_base: Vector2 = bomb_center + collar_dir * (bomb_r * 0.84)
	var collar_tip: Vector2 = bomb_center + collar_dir * (bomb_r * 1.24)
	var collar_hw: float = bomb_r * 0.32
	ci.draw_colored_polygon(
		PackedVector2Array([
			collar_base - collar_perp * collar_hw,
			collar_base + collar_perp * collar_hw,
			collar_tip + collar_perp * (collar_hw * 0.85),
			collar_tip - collar_perp * (collar_hw * 0.85),
		]),
		Color(0.68, 0.58, 0.66, alpha)
	)

	# Curved braided wick arching up-right.
	var wick_p0: Vector2 = collar_tip
	var wick_p1: Vector2 = collar_tip + Vector2(min_dim * 0.055, -min_dim * 0.088)
	var wick_p2: Vector2 = collar_tip + Vector2(min_dim * 0.135, -min_dim * 0.082)
	var wick_p3: Vector2 = collar_tip + Vector2(min_dim * 0.165, -min_dim * 0.025)
	ci.draw_polyline(
		PackedVector2Array([wick_p0, wick_p1, wick_p2, wick_p3]),
		Color(0.96, 0.82, 0.56, alpha),
		maxf(2.0, min_dim * 0.048),
		true
	)

	# Animated flickering spark starburst at the fuse tip!
	var spark_pos: Vector2 = wick_p3
	var spark_flicker: float = 0.82 + 0.34 * sin(time_sec * 24.0)
	var spark_rot: float = time_sec * 4.5
	var outer_spike: float = min_dim * 0.145 * spark_flicker
	var inner_spike: float = min_dim * 0.046 * spark_flicker

	var spark_glow_s: float = outer_spike * 3.0
	ci.draw_texture_rect(
		_soft_glow_texture,
		Rect2(spark_pos - Vector2(spark_glow_s, spark_glow_s) * 0.5, Vector2(spark_glow_s, spark_glow_s)),
		false,
		Color(1.0, 0.62, 0.14, 0.72 * alpha)
	)

	var star_pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(8):
		var a: float = spark_rot + float(i) * (PI * 0.25)
		var rad: float = outer_spike if (i & 1) == 0 else inner_spike
		star_pts.append(spark_pos + Vector2(cos(a), sin(a)) * rad)
	ci.draw_colored_polygon(star_pts, Color(1.0, 0.80, 0.18, alpha))
	ci.draw_circle(spark_pos, min_dim * 0.058 * spark_flicker, Color(1.0, 1.0, 0.88, alpha))


static func _draw_lightning_tile(ci: CanvasItem, rect: Rect2, time_sec: float, alpha: float) -> void:
	var pulse: float = 0.5 + 0.5 * sin(time_sec * 7.2)
	var mod: Color = Color(1.0 + pulse * 0.10, 1.0 + pulse * 0.16, 1.0 + pulse * 0.20, alpha)
	ci.draw_texture_rect(_lightning_base_texture, rect, false, mod)

	var min_dim: float = minf(rect.size.x, rect.size.y)
	var center: Vector2 = rect.get_center()

	# Luminous inner plasma glow behind the bolt.
	var plasma_s: float = min_dim * (0.86 + pulse * 0.08)
	ci.draw_texture_rect(
		_soft_glow_texture,
		Rect2(center - Vector2(plasma_s, plasma_s) * 0.5, Vector2(plasma_s, plasma_s)),
		false,
		Color(0.14, 0.90, 1.0, (0.44 + pulse * 0.22) * alpha)
	)

	# Crackling animated electric arcs framed cleanly inside the dark indigo crystal chamber.
	var step_idx: int = int(floor(time_sec * 14.0))
	var arc_rect: Rect2 = rect.grow(-min_dim * 0.19)
	_draw_electric_arc(ci, arc_rect.position, Vector2(arc_rect.end.x, arc_rect.position.y), step_idx + 11, min_dim * 0.045, Color(0.45, 0.97, 1.0, 0.88 * alpha))
	_draw_electric_arc(ci, Vector2(arc_rect.position.x, arc_rect.end.y), arc_rect.end, step_idx + 29, min_dim * 0.045, Color(0.55, 0.86, 1.0, 0.82 * alpha))
	if (step_idx & 1) == 0:
		_draw_electric_arc(ci, arc_rect.position, Vector2(arc_rect.position.x, arc_rect.end.y), step_idx + 47, min_dim * 0.042, Color(0.76, 0.99, 1.0, 0.74 * alpha))
	else:
		_draw_electric_arc(ci, Vector2(arc_rect.end.x, arc_rect.position.y), arc_rect.end, step_idx + 61, min_dim * 0.042, Color(0.76, 0.99, 1.0, 0.74 * alpha))

	# Bold iconic white-gold lightning bolt cutting cleanly across the tile center!
	var s: float = min_dim * 0.35
	var bolt_norm: Array[Vector2] = [
		Vector2(0.18, -0.96),
		Vector2(-0.56, 0.06),
		Vector2(-0.04, 0.06),
		Vector2(-0.24, 0.96),
		Vector2(0.56, -0.10),
		Vector2(0.04, -0.10),
	]

	var aura_pts: PackedVector2Array = PackedVector2Array()
	var rim_pts: PackedVector2Array = PackedVector2Array()
	var core_pts: PackedVector2Array = PackedVector2Array()
	for v: Vector2 in bolt_norm:
		aura_pts.append(center + v * (s * 1.18))
		rim_pts.append(center + v * (s * 1.04))
		core_pts.append(center + v * (s * 0.84))

	ci.draw_colored_polygon(aura_pts, Color(0.15, 0.92, 1.0, (0.42 + pulse * 0.25) * alpha))
	ci.draw_colored_polygon(rim_pts, Color(1.0, 0.80, 0.14, alpha))
	ci.draw_colored_polygon(core_pts, Color(1.0, 0.99, 0.86, alpha))


static func _draw_electric_arc(
	ci: CanvasItem,
	a: Vector2,
	b: Vector2,
	seed_val: int,
	amp: float,
	col: Color
) -> void:
	var dir: Vector2 = b - a
	var length_ab: float = dir.length()
	if length_ab <= 1.0:
		return
	var normal: Vector2 = Vector2(-dir.y, dir.x) / length_ab
	var pts: PackedVector2Array = PackedVector2Array([a])
	var segments: int = 4
	for i: int in range(1, segments):
		var t: float = float(i) / float(segments)
		var h: float = sin(float(seed_val * 37 + i * 91) * 1.6180339)
		pts.append(a.lerp(b, t) + normal * (h * amp))
	pts.append(b)
	ci.draw_polyline(pts, col, 1.3, true)


static func _draw_clipped_diagonal_stripes(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var w: float = r.size.x
	var h: float = r.size.y
	if w <= 4.0 or h <= 4.0:
		return
	var step: float = maxf(9.0, minf(w, h) * 0.26)
	var stripe_w: float = step * 0.32
	var d: float = -h * 0.25
	while d < w + h:
		var pts: PackedVector2Array = _clip_diag_band_to_rect(r, d, d + stripe_w)
		if pts.size() >= 3:
			ci.draw_colored_polygon(pts, col)
		d += step


static func _clip_diag_band_to_rect(r: Rect2, c_min: float, c_max: float) -> PackedVector2Array:
	var poly: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(r.size.x, 0.0),
		Vector2(r.size.x, r.size.y),
		Vector2(0.0, r.size.y),
	]
	poly = _clip_poly_halfplane(poly, c_min, true)
	poly = _clip_poly_halfplane(poly, c_max, false)
	var out: PackedVector2Array = PackedVector2Array()
	for pt: Vector2 in poly:
		out.append(r.position + pt)
	return out


static func _clip_poly_halfplane(poly: Array[Vector2], threshold: float, keep_greater: bool) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var n: int = poly.size()
	if n == 0:
		return result
	for i: int in range(n):
		var curr: Vector2 = poly[i]
		var prev: Vector2 = poly[(i + n - 1) % n]
		var val_curr: float = curr.x + curr.y
		var val_prev: float = prev.x + prev.y
		var in_curr: bool = (val_curr >= threshold) if keep_greater else (val_curr <= threshold)
		var in_prev: bool = (val_prev >= threshold) if keep_greater else (val_prev <= threshold)

		if in_curr != in_prev:
			var denom: float = val_curr - val_prev
			if absf(denom) > 0.0001:
				var t: float = (threshold - val_prev) / denom
				result.append(prev.lerp(curr, t))
		if in_curr:
			result.append(curr)
	return result


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


static func _build_chamfered_pill_points(r: Rect2, c: float) -> PackedVector2Array:
	var ch: float = minf(c, minf(r.size.x, r.size.y) * 0.42)
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


static func _draw_chamfered_pill(ci: CanvasItem, r: Rect2, col: Color, chamfer: float) -> void:
	ci.draw_colored_polygon(_build_chamfered_pill_points(r, chamfer), col)


static func _draw_chamfered_pill_outline(ci: CanvasItem, r: Rect2, col: Color, chamfer: float, width: float) -> void:
	var pts: PackedVector2Array = _build_chamfered_pill_points(r, chamfer)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width, true)


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
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	var baseline_pos: Vector2 = Vector2(
		center.x - text_size.x * 0.5,
		center.y + (ascent - descent) * 0.46
	)
	ci.draw_string_outline(
		font,
		baseline_pos + Vector2(0.0, 1.5),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		outline_size,
		Color(0.0, 0.0, 0.0, 0.55)
	)
	ci.draw_string_outline(
		font,
		baseline_pos,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		outline_size,
		outline_color
	)
	ci.draw_string(
		font,
		baseline_pos,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		fill_color
	)
