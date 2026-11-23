class_name SkinShopOverlay
extends Control

## Block Skin Shop & Theme Customizer Modal for Kombo by SOYA GAMES.
## Lets players spend earned run coins (and 2x Ad coins!) to unlock & equip
## handcrafted procedural block skins: Classic Gem, Warm Wood, Juicy Jelly,
## Cyber Neon, and Royal Diamond.

signal skin_equipped(skin_id: String)
signal skin_unlocked(skin_id: String, remaining_coins: int)
signal closed()

const OVERLAY_SIZE := Vector2(540.0, 960.0)
const CARD_WIDTH := 452.0
const CARD_HEIGHT := 648.0

const FONT_EXTRABOLD_PATH := "res://assets/fonts/Kanit-ExtraBold.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/Kanit-Bold.ttf"

var _font_extrabold: Font
var _font_bold: Font
var _radial_glow_tex: GradientTexture2D

var _sb_card_shadow: StyleBoxFlat
var _sb_card_lip: StyleBoxFlat
var _sb_card_body: StyleBoxFlat
var _sb_card_rim: StyleBoxFlat
var _sb_coin_pill: StyleBoxFlat

var _is_open: bool = false
var _save_manager: SaveManager = null
var _backdrop_alpha: float = 0.0
var _card_alpha: float = 0.0
var _card_scale: float = 0.86
var _card_scale_vel: float = 0.0
var _card_y_offset: float = 18.0

var _card: _SkinShopCard
var _close_btn: _ShopCloseButton
var _skin_rows: Array[_SkinRowButton] = []


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
		if ke.pressed and not ke.echo and ke.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_shop(true)


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
		close_shop(true)


func _process(delta: float) -> void:
	if not visible:
		return
	var dt := minf(delta, 0.05)
	var animating := (
		absf(_backdrop_alpha - 1.0) > 0.005
		or absf(_card_alpha - 1.0) > 0.005
		or absf(_card_y_offset) > 0.2
		or absf(_card_scale - 1.0) > 0.002
		or absf(_card_scale_vel) > 0.01
	)
	if not animating:
		return

	_backdrop_alpha = move_toward(_backdrop_alpha, 1.0, dt * 5.5)
	_card_alpha = move_toward(_card_alpha, 1.0, dt * 6.0)
	_card_y_offset = lerpf(_card_y_offset, 0.0, clampf(16.0 * dt, 0.0, 1.0))

	var cs := GameOverOverlay._step_spring(_card_scale, _card_scale_vel, 1.0, 290.0, 18.0, dt)
	_card_scale = cs.x
	_card_scale_vel = cs.y

	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


func open_shop(save_mgr: SaveManager) -> void:
	_save_manager = save_mgr
	_is_open = true
	_backdrop_alpha = 0.0
	_card_alpha = 0.0
	_card_scale = 0.84
	_card_scale_vel = 4.0
	_card_y_offset = 20.0

	_layout_contents()
	_refresh_rows()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_card_transform()
	queue_redraw()
	if _card != null:
		_card.queue_redraw()


func close_shop(emit_closed: bool = true) -> void:
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

	_sb_card_rim = StyleBoxFlat.new()
	_sb_card_rim.draw_center = false
	_sb_card_rim.set_corner_radius_all(24)
	_sb_card_rim.corner_detail = 10
	_sb_card_rim.set_border_width_all(3)
	_sb_card_rim.border_color = Color("#3CE8FF", 0.85)

	_sb_coin_pill = StyleBoxFlat.new()
	_sb_coin_pill.bg_color = Color("#0A122C", 0.94)
	_sb_coin_pill.set_corner_radius_all(14)
	_sb_coin_pill.corner_detail = 8
	_sb_coin_pill.set_border_width_all(2)
	_sb_coin_pill.border_color = Color("#FFD43B", 0.88)


func _build_card() -> void:
	_card = _SkinShopCard.new()
	_card.name = "SkinShopCard"
	_card.overlay = self
	_card.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	add_child(_card)

	_close_btn = _ShopCloseButton.new()
	_close_btn.name = "ShopCloseButton"
	_close_btn.font = _font_extrabold
	_close_btn.size = Vector2(40.0, 40.0)
	_close_btn.activated.connect(func() -> void: close_shop(true))
	_card.add_child(_close_btn)

	_skin_rows.clear()
	var catalog := TilePainter.get_skin_catalog()
	for i in range(catalog.size()):
		var row := _SkinRowButton.new()
		row.name = "SkinRow_%d" % i
		row.font_extrabold = _font_extrabold
		row.font_bold = _font_bold
		row.skin_entry = catalog[i]
		row.row_index = i
		row.size = Vector2(CARD_WIDTH - 36.0, 96.0)
		row.activated.connect(_on_skin_row_activated)
		_card.add_child(row)
		_skin_rows.append(row)


func _layout_contents() -> void:
	if _card == null:
		return
	_card.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	_card.pivot_offset = _card.size * 0.5
	if _close_btn != null:
		_close_btn.position = Vector2(CARD_WIDTH - 56.0, 16.0)

	var y_top := 104.0
	var gap := 10.0
	for i in range(_skin_rows.size()):
		_skin_rows[i].position = Vector2(18.0, y_top + float(i) * (96.0 + gap))


func _refresh_rows() -> void:
	var wallet := _save_manager.coins if _save_manager != null else 0
	var eq := _save_manager.equipped_skin if _save_manager != null else TilePainter.get_active_skin()
	for row in _skin_rows:
		var sid := String(row.skin_entry.get("id", "jewel"))
		var unlocked := _save_manager.is_skin_unlocked(sid) if _save_manager != null else (sid == "jewel")
		var cost := int(row.skin_entry.get("cost", 0))
		row.configure_state(unlocked, eq == sid, wallet >= cost)
	if _card != null:
		_card.queue_redraw()


func _on_skin_row_activated(skin_id: String, cost: int) -> void:
	if _save_manager == null:
		TilePainter.set_active_skin(skin_id)
		skin_equipped.emit(skin_id)
		_refresh_rows()
		return

	if _save_manager.is_skin_unlocked(skin_id):
		_save_manager.equip_skin(skin_id)
		TilePainter.set_active_skin(skin_id)
		skin_equipped.emit(skin_id)
		_refresh_rows()
	elif _save_manager.coins >= cost:
		if _save_manager.unlock_skin(skin_id, cost):
			TilePainter.set_active_skin(skin_id)
			skin_unlocked.emit(skin_id, _save_manager.coins)
			skin_equipped.emit(skin_id)
			_refresh_rows()


func _apply_card_transform() -> void:
	if _card == null:
		return
	var vp := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	_card.pivot_offset = _card.size * 0.5
	_card.position = (vp - _card.size) * 0.5 + Vector2(0.0, _card_y_offset)
	_card.scale = Vector2(_card_scale, _card_scale)
	_card.modulate = Color(1.0, 1.0, 1.0, _card_alpha)


func _draw() -> void:
	if not visible:
		return
	var vp := size if (size.x > 10.0 and size.y > 10.0) else OVERLAY_SIZE
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.03, 0.09, 0.80 * _backdrop_alpha), true)


class _SkinShopCard extends Control:
	var overlay: SkinShopOverlay

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		if overlay == null:
			return
		var cid := get_canvas_item()
		var rect := Rect2(Vector2.ZERO, size)
		var lip_h := 7.0
		var face_rect := Rect2(0.0, 0.0, size.x, size.y - lip_h)

		overlay._sb_card_shadow.draw(cid, Rect2(Vector2(0.0, 12.0), size).grow(4.0))
		overlay._sb_card_lip.draw(cid, rect)
		overlay._sb_card_body.draw(cid, face_rect)
		overlay._sb_card_rim.draw(cid, face_rect)

		# Header Title
		GameOverOverlay._draw_left_outlined_text(
			self,
			overlay._font_extrabold,
			Vector2(24.0, 36.0),
			"BLOCK SKINS",
			26,
			Color("#FFF4A8"),
			Color("#09102A"),
			6,
			2.0
		)
		GameOverOverlay._draw_left_outlined_text(
			self,
			overlay._font_bold,
			Vector2(24.0, 62.0),
			"UNLOCK WITH COINS  •  WATCH ×2 AD AT GAME OVER!",
			11,
			Color("#8CE8FF"),
			Color("#08102A"),
			3,
			1.0
		)

		# Top-right Coin Balance Pill (left of Close button)
		var coins_val := overlay._save_manager.coins if overlay._save_manager != null else 0
		var coin_txt := HudView.format_comma_int(coins_val)
		var pill_w := clampf(52.0 + float(coin_txt.length()) * 10.5, 96.0, 176.0)
		var pill_rect := Rect2(size.x - 66.0 - pill_w, 16.0, pill_w, 40.0)
		overlay._sb_coin_pill.draw(cid, pill_rect)

		var coin_c := Vector2(pill_rect.position.x + 20.0, pill_rect.get_center().y)
		draw_circle(coin_c, 10.0, Color("#B85D00"))
		draw_circle(coin_c, 8.2, Color("#FFD43B"))
		draw_circle(coin_c + Vector2(-2.0, -2.0), 3.0, Color("#FFF8C4"))
		GameOverOverlay._draw_left_outlined_text(
			self,
			overlay._font_extrabold,
			Vector2(coin_c.x + 15.0, pill_rect.get_center().y),
			coin_txt,
			17,
			Color("#FFE866"),
			Color("#2B1400"),
			4,
			1.2
		)


class _SkinRowButton extends Control:
	signal activated(skin_id: String, cost: int)

	var font_extrabold: Font
	var font_bold: Font
	var skin_entry: Dictionary = {}
	var row_index: int = 0

	var _is_unlocked: bool = false
	var _is_equipped: bool = false
	var _can_afford: bool = false
	var _hovered: bool = false
	var _pressed: bool = false

	var _sb_body: StyleBoxFlat
	var _sb_btn: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; _pressed = false; queue_redraw())

		_sb_body = StyleBoxFlat.new()
		_sb_body.set_corner_radius_all(16)
		_sb_body.corner_detail = 8
		_sb_body.set_border_width_all(2)

		_sb_btn = StyleBoxFlat.new()
		_sb_btn.set_corner_radius_all(12)
		_sb_btn.corner_detail = 8
		_sb_btn.set_border_width_all(2)

	func configure_state(unlocked: bool, equipped: bool, affordable: bool) -> void:
		_is_unlocked = unlocked
		_is_equipped = equipped
		_can_afford = affordable
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_pressed = true
					queue_redraw()
				else:
					var hit := _pressed and Rect2(Vector2.ZERO, size).has_point(mb.position)
					_pressed = false
					queue_redraw()
					if hit:
						accept_event()
						activated.emit(String(skin_entry.get("id", "jewel")), int(skin_entry.get("cost", 0)))
		elif event is InputEventScreenTouch:
			var st := event as InputEventScreenTouch
			if st.pressed:
				_pressed = true
				queue_redraw()
			else:
				var hit := _pressed and Rect2(Vector2.ZERO, size).has_point(st.position)
				_pressed = false
				queue_redraw()
				if hit:
					accept_event()
					activated.emit(String(skin_entry.get("id", "jewel")), int(skin_entry.get("cost", 0)))

	func _draw() -> void:
		var cid := get_canvas_item()
		var sid := String(skin_entry.get("id", "jewel"))
		var sname := String(skin_entry.get("name", "CLASSIC GEM"))
		var ssub := String(skin_entry.get("subtitle", ""))
		var cost := int(skin_entry.get("cost", 0))
		var accent := skin_entry.get("accent", Color("#2979FF")) as Color

		var bg := Color("#162352") if not _is_equipped else Color("#12383C")
		if _hovered:
			bg = bg.lightened(0.08)
		var rim := Color("#2CE880") if _is_equipped else (accent.lerp(Color.WHITE, 0.25) if _is_unlocked else Color(0.32, 0.44, 0.72, 0.55))
		_sb_body.bg_color = bg
		_sb_body.border_color = rim
		_sb_body.draw(cid, Rect2(Vector2.ZERO, size))

		# Draw 3 live mini preview blocks (34x34 each) using this skin's baked textures!
		var sample_colors: Array[int] = [0, 1, 4]
		if sid == "wood":
			sample_colors = [2, 1, 3]
		elif sid == "jelly":
			sample_colors = [0, 6, 5]
		elif sid == "neon":
			sample_colors = [5, 6, 0]
		elif sid == "diamond":
			sample_colors = [1, 5, 6]

		var tile_s := 34.0
		var start_x := 14.0
		var tile_y := (size.y - tile_s) * 0.5
		for k in range(3):
			var tex := TilePainter.get_skin_preview_texture(sid, sample_colors[k])
			if tex != null:
				draw_texture_rect(
					tex,
					Rect2(start_x + float(k) * (tile_s + 4.0), tile_y, tile_s, tile_s),
					false
				)

		# Skin Name & Subtitle
		var text_x := 134.0
		GameOverOverlay._draw_left_outlined_text(
			self,
			font_extrabold,
			Vector2(text_x, 36.0),
			sname,
			18,
			Color("#FFF7B2") if _is_equipped else Color("#FFFFFF"),
			Color("#08102A"),
			4,
			1.5
		)
		GameOverOverlay._draw_left_outlined_text(
			self,
			font_bold,
			Vector2(text_x, 62.0),
			ssub,
			12,
			Color("#9CE8FF") if _is_unlocked else Color("#8D9CC4"),
			Color("#08102A"),
			3,
			1.0
		)

		# Action Button on Right
		var btn_rect := Rect2(size.x - 128.0, (size.y - 44.0) * 0.5, 116.0, 44.0)
		var btn_label := ""
		var btn_text_col := Color.WHITE
		var show_coin_icon := false
		if _is_equipped:
			_sb_btn.bg_color = Color("#16B84E")
			_sb_btn.border_color = Color("#A8FFBE")
			btn_label = "EQUIPPED"
			btn_text_col = Color("#FFFDF0")
		elif _is_unlocked:
			_sb_btn.bg_color = Color("#1878E8")
			_sb_btn.border_color = Color("#8CE8FF")
			btn_label = "USE"
			btn_text_col = Color("#FFFFFF")
		elif _can_afford:
			_sb_btn.bg_color = Color("#E0820E")
			_sb_btn.border_color = Color("#FFF08A")
			btn_label = HudView.format_comma_int(cost)
			btn_text_col = Color("#FFFCE0")
			show_coin_icon = true
		else:
			_sb_btn.bg_color = Color("#1C2444")
			_sb_btn.border_color = Color("#465480")
			btn_label = HudView.format_comma_int(cost)
			btn_text_col = Color("#8A98BF")
			show_coin_icon = true

		_sb_btn.draw(cid, btn_rect)
		if show_coin_icon:
			var cc := Vector2(btn_rect.position.x + 17.0, btn_rect.get_center().y)
			draw_circle(cc, 7.2, Color("#8C4400") if _can_afford else Color("#394568"))
			draw_circle(cc, 5.8, Color("#FFD43B") if _can_afford else Color("#6C7A9E"))
			draw_circle(cc + Vector2(-1.4, -1.4), 2.0, Color("#FFF8C4") if _can_afford else Color("#9AA8C8"))
			var fsz := 14 if btn_label.length() >= 7 else 15
			GameOverOverlay._draw_centered_outlined_text(
				self,
				font_extrabold,
				Vector2(btn_rect.get_center().x + 8.0, btn_rect.get_center().y),
				btn_label,
				fsz,
				btn_text_col,
				Color("#091028"),
				4,
				1.3
			)
		else:
			GameOverOverlay._draw_centered_outlined_text(
				self,
				font_extrabold,
				btn_rect.get_center(),
				btn_label,
				15,
				btn_text_col,
				Color("#091028"),
				4,
				1.4
			)


class _ShopCloseButton extends Control:
	signal activated()
	var font: Font
	var _sb: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_sb = StyleBoxFlat.new()
		_sb.bg_color = Color("#1E2B5E")
		_sb.set_corner_radius_all(12)
		_sb.set_border_width_all(2)
		_sb.border_color = Color("#5874C8")

	func _gui_input(event: InputEvent) -> void:
		if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
			accept_event()
			activated.emit()

	func _draw() -> void:
		_sb.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		GameOverOverlay._draw_centered_outlined_text(self, font, size * 0.5, "×", 22, Color("#E4EEFF"), Color("#08102A"), 4, 1.4)
