class_name SkinShopOverlay
extends Control

## Tabbed Block Skin & Background Theme Shop Modal for Kombo by SOYA GAMES.
## Lets players spend earned run coins (and 2x Ad coins!) to unlock & equip:
## - BLOCKS tab: 5 handcrafted procedural block skins (Classic Gem, Warm Wood, Juicy Jelly, Cyber Neon, Royal Diamond)
## - BACKGROUNDS tab: 6 living shader backgrounds (Classic Swirl, Sweet Candy, Sakura Bloom, Cyber Grid, Deep Ocean, Starlight Galaxy)

signal skin_equipped(skin_id: String)
signal skin_unlocked(skin_id: String, remaining_coins: int)
signal background_equipped(bg_id: String)
signal background_unlocked(bg_id: String, remaining_coins: int)
signal closed()

const OVERLAY_SIZE := Vector2(540.0, 960.0)
const CARD_WIDTH := 464.0
const CARD_HEIGHT := 692.0

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
var _active_tab: int = 0 # 0 = BLOCKS, 1 = BACKGROUNDS
var _save_manager: SaveManager = null
var _backdrop_alpha: float = 0.0
var _card_alpha: float = 0.0
var _card_scale: float = 0.86
var _card_scale_vel: float = 0.0
var _card_y_offset: float = 18.0

var _card: _SkinShopCard
var _close_btn: _ShopCloseButton
var _tab_blocks_btn: _ShopTabButton
var _tab_bgs_btn: _ShopTabButton
var _skin_rows: Array[_ShopItemRow] = []
var _bg_rows: Array[_ShopItemRow] = []


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


func open_shop(save_mgr: SaveManager, start_tab: int = -1) -> void:
	_save_manager = save_mgr
	if start_tab == 0 or start_tab == 1:
		_active_tab = start_tab
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

	_tab_blocks_btn = _ShopTabButton.new()
	_tab_blocks_btn.name = "TabBlocksButton"
	_tab_blocks_btn.font = _font_extrabold
	_tab_blocks_btn.tab_label = "BLOCK SKINS"
	_tab_blocks_btn.accent_color = Color("#3CE8FF")
	_tab_blocks_btn.activated.connect(func() -> void: _switch_tab(0))
	_card.add_child(_tab_blocks_btn)

	_tab_bgs_btn = _ShopTabButton.new()
	_tab_bgs_btn.name = "TabBackgroundsButton"
	_tab_bgs_btn.font = _font_extrabold
	_tab_bgs_btn.tab_label = "BACKGROUNDS"
	_tab_bgs_btn.accent_color = Color("#FF74C2")
	_tab_bgs_btn.activated.connect(func() -> void: _switch_tab(1))
	_card.add_child(_tab_bgs_btn)

	_skin_rows.clear()
	var catalog := TilePainter.get_skin_catalog()
	for i in range(catalog.size()):
		var row := _ShopItemRow.new()
		row.name = "SkinRow_%d" % i
		row.font_extrabold = _font_extrabold
		row.font_bold = _font_bold
		row.is_background_item = false
		row.item_entry = catalog[i]
		row.size = Vector2(CARD_WIDTH - 36.0, 94.0)
		row.activated.connect(_on_skin_row_activated)
		_card.add_child(row)
		_skin_rows.append(row)

	_bg_rows.clear()
	var bg_catalog := TilePainter.get_background_catalog()
	for i in range(bg_catalog.size()):
		var row := _ShopItemRow.new()
		row.name = "BgRow_%d" % i
		row.font_extrabold = _font_extrabold
		row.font_bold = _font_bold
		row.is_background_item = true
		row.item_entry = bg_catalog[i]
		row.size = Vector2(CARD_WIDTH - 36.0, 80.0)
		row.activated.connect(_on_bg_row_activated)
		_card.add_child(row)
		_bg_rows.append(row)


func _switch_tab(tab_idx: int) -> void:
	if _active_tab == tab_idx:
		return
	_active_tab = tab_idx
	_refresh_rows()


func _layout_contents() -> void:
	if _card == null:
		return
	_card.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	_card.pivot_offset = _card.size * 0.5
	if _close_btn != null:
		_close_btn.position = Vector2(CARD_WIDTH - 56.0, 16.0)

	var tab_w := (CARD_WIDTH - 46.0) * 0.5
	if _tab_blocks_btn != null:
		_tab_blocks_btn.position = Vector2(18.0, 82.0)
		_tab_blocks_btn.size = Vector2(tab_w, 40.0)
	if _tab_bgs_btn != null:
		_tab_bgs_btn.position = Vector2(18.0 + tab_w + 10.0, 82.0)
		_tab_bgs_btn.size = Vector2(tab_w, 40.0)

	var y_top := 134.0
	for i in range(_skin_rows.size()):
		_skin_rows[i].position = Vector2(18.0, y_top + float(i) * (94.0 + 10.0))
	for i in range(_bg_rows.size()):
		_bg_rows[i].position = Vector2(18.0, y_top + float(i) * (80.0 + 9.0))


func _refresh_rows() -> void:
	var wallet := _save_manager.coins if _save_manager != null else 0
	var eq_skin := _save_manager.equipped_skin if _save_manager != null else TilePainter.get_active_skin()
	var eq_bg := _save_manager.equipped_background if _save_manager != null else TilePainter.get_active_background()

	if _tab_blocks_btn != null:
		_tab_blocks_btn.set_selected(_active_tab == 0)
	if _tab_bgs_btn != null:
		_tab_bgs_btn.set_selected(_active_tab == 1)

	for row in _skin_rows:
		row.visible = (_active_tab == 0)
		var sid := String(row.item_entry.get("id", "jewel"))
		var unlocked := _save_manager.is_skin_unlocked(sid) if _save_manager != null else (sid == "jewel")
		var cost := int(row.item_entry.get("cost", 0))
		row.configure_state(unlocked, eq_skin == sid, wallet >= cost)

	for row in _bg_rows:
		row.visible = (_active_tab == 1)
		var bid := String(row.item_entry.get("id", "swirl"))
		var unlocked := _save_manager.is_background_unlocked(bid) if _save_manager != null else (bid == "swirl")
		var cost := int(row.item_entry.get("cost", 0))
		row.configure_state(unlocked, eq_bg == bid, wallet >= cost)

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


func _on_bg_row_activated(bg_id: String, cost: int) -> void:
	if _save_manager == null:
		TilePainter.set_active_background(bg_id)
		background_equipped.emit(bg_id)
		_refresh_rows()
		return

	if _save_manager.is_background_unlocked(bg_id):
		_save_manager.equip_background(bg_id)
		TilePainter.set_active_background(bg_id)
		background_equipped.emit(bg_id)
		_refresh_rows()
	elif _save_manager.coins >= cost:
		if _save_manager.unlock_background(bg_id, cost):
			TilePainter.set_active_background(bg_id)
			background_unlocked.emit(bg_id, _save_manager.coins)
			background_equipped.emit(bg_id)
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
		overlay._sb_card_rim.border_color = Color("#FF74C2", 0.85) if overlay._active_tab == 1 else Color("#3CE8FF", 0.85)
		overlay._sb_card_rim.draw(cid, face_rect)

		# Header Title
		GameOverOverlay._draw_left_outlined_text(
			self,
			overlay._font_extrabold,
			Vector2(22.0, 35.0),
			"SKINS & THEMES",
			24,
			Color("#FFF4A8"),
			Color("#09102A"),
			6,
			2.0
		)
		GameOverOverlay._draw_left_outlined_text(
			self,
			overlay._font_bold,
			Vector2(22.0, 61.0),
			"CUSTOMIZE BLOCKS & BACKGROUNDS",
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


class _ShopTabButton extends Control:
	signal activated()

	var font: Font
	var tab_label: String = "BLOCKS"
	var accent_color: Color = Color("#3CE8FF")
	var _selected: bool = false
	var _hovered: bool = false
	var _sb: StyleBoxFlat

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())
		_sb = StyleBoxFlat.new()
		_sb.set_corner_radius_all(12)
		_sb.corner_detail = 8
		_sb.set_border_width_all(2)

	func set_selected(sel: bool) -> void:
		_selected = sel
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
			accept_event()
			activated.emit()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if _selected:
			_sb.bg_color = accent_color.darkened(0.55)
			_sb.border_color = accent_color.lerp(Color.WHITE, 0.35)
		else:
			_sb.bg_color = Color("#182552") if _hovered else Color("#0D1536")
			_sb.border_color = Color(0.32, 0.44, 0.76, 0.55)
		_sb.draw(get_canvas_item(), rect)
		GameOverOverlay._draw_centered_outlined_text(
			self,
			font,
			rect.get_center(),
			tab_label,
			15,
			Color("#FFFFFF") if _selected else Color("#95A8D6"),
			Color("#08102A"),
			4,
			1.2
		)


class _ShopItemRow extends Control:
	signal activated(item_id: String, cost: int)

	var font_extrabold: Font
	var font_bold: Font
	var is_background_item: bool = false
	var item_entry: Dictionary = {}

	var _is_unlocked: bool = false
	var _is_equipped: bool = false
	var _can_afford: bool = false
	var _hovered: bool = false
	var _pressed: bool = false

	var _sb_body: StyleBoxFlat
	var _sb_btn: StyleBoxFlat
	var _sb_thumb: StyleBoxFlat

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

		_sb_thumb = StyleBoxFlat.new()
		_sb_thumb.set_corner_radius_all(10)
		_sb_thumb.corner_detail = 6
		_sb_thumb.set_border_width_all(2)

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
						activated.emit(String(item_entry.get("id", "jewel")), int(item_entry.get("cost", 0)))
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
					activated.emit(String(item_entry.get("id", "jewel")), int(item_entry.get("cost", 0)))

	func _draw() -> void:
		var cid := get_canvas_item()
		var item_id := String(item_entry.get("id", "jewel"))
		var item_name := String(item_entry.get("name", "CLASSIC GEM"))
		var item_sub := String(item_entry.get("subtitle", ""))
		var cost := int(item_entry.get("cost", 0))
		var accent := item_entry.get("accent", Color("#2979FF")) as Color

		var bg := Color("#162352") if not _is_equipped else Color("#12383C")
		if _hovered:
			bg = bg.lightened(0.08)
		var rim := Color("#2CE880") if _is_equipped else (accent.lerp(Color.WHITE, 0.25) if _is_unlocked else Color(0.32, 0.44, 0.72, 0.55))
		_sb_body.bg_color = bg
		_sb_body.border_color = rim
		_sb_body.draw(cid, Rect2(Vector2.ZERO, size))

		if is_background_item:
			_draw_background_preview(cid, item_id, Rect2(12.0, (size.y - 54.0) * 0.5, 96.0, 54.0), accent)
		else:
			var sample_colors: Array[int] = [0, 1, 4]
			if item_id == "wood":
				sample_colors = [2, 1, 3]
			elif item_id == "jelly":
				sample_colors = [0, 6, 5]
			elif item_id == "neon":
				sample_colors = [5, 6, 0]
			elif item_id == "diamond":
				sample_colors = [1, 5, 6]
			var tile_s := 32.0
			var start_x := 12.0
			var tile_y := (size.y - tile_s) * 0.5
			for k in range(3):
				var tex := TilePainter.get_skin_preview_texture(item_id, sample_colors[k])
				if tex != null:
					draw_texture_rect(tex, Rect2(start_x + float(k) * (tile_s + 4.0), tile_y, tile_s, tile_s), false)

		# Item Name & Subtitle
		var text_x := 120.0 if is_background_item else 126.0
		var name_y := size.y * 0.36
		var sub_y := size.y * 0.68
		GameOverOverlay._draw_left_outlined_text(
			self,
			font_extrabold,
			Vector2(text_x, name_y),
			item_name,
			16 if is_background_item else 18,
			Color("#FFF7B2") if _is_equipped else Color("#FFFFFF"),
			Color("#08102A"),
			4,
			1.4
		)
		GameOverOverlay._draw_left_outlined_text(
			self,
			font_bold,
			Vector2(text_x, sub_y),
			item_sub,
			11 if is_background_item else 12,
			Color("#9CE8FF") if _is_unlocked else Color("#8D9CC4"),
			Color("#08102A"),
			3,
			1.0
		)

		# Action Button on Right
		var btn_h := 40.0 if is_background_item else 44.0
		var btn_rect := Rect2(size.x - 126.0, (size.y - btn_h) * 0.5, 114.0, btn_h)
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
			draw_circle(cc, 7.0, Color("#8C4400") if _can_afford else Color("#394568"))
			draw_circle(cc, 5.6, Color("#FFD43B") if _can_afford else Color("#6C7A9E"))
			draw_circle(cc + Vector2(-1.4, -1.4), 1.9, Color("#FFF8C4") if _can_afford else Color("#9AA8C8"))
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
				14 if is_background_item else 15,
				btn_text_col,
				Color("#091028"),
				4,
				1.4
			)

	func _draw_background_preview(cid: RID, bg_id: String, r: Rect2, accent: Color) -> void:
		var inner := r.grow(-2.0)
		if bg_id == "candy":
			_sb_thumb.bg_color = Color("#4D1A3E")
			_sb_thumb.border_color = Color("#FF8AC8")
			_sb_thumb.draw(cid, r)
			# Diagonal pastel candy ribbons
			for s in range(4):
				var sx := inner.position.x + float(s) * 24.0
				draw_line(Vector2(sx, inner.end.y), Vector2(sx + 18.0, inner.position.y), Color("#FF6EB8", 0.30), 6.0, true)
			# Cute Frosted Pink Donut (left)
			var dc := Vector2(inner.position.x + 24.0, inner.get_center().y)
			draw_circle(dc, 12.5, Color("#D68F52"))
			draw_circle(dc, 11.2, Color("#FF6EB4"))
			draw_circle(dc, 4.5, Color("#4D1A3E"))
			draw_circle(dc + Vector2(-4.0, -5.0), 2.2, Color("#FFF4FA", 0.85))
			# Mint Swirl Candy (right)
			var cc := Vector2(inner.end.x - 24.0, inner.get_center().y + 3.0)
			draw_circle(cc, 9.5, Color("#56EED8"))
			draw_arc(cc, 6.0, 0.2, PI * 1.6, 12, Color("#FFFFFF"), 2.0, true)
			draw_circle(cc, 2.5, Color("#FF6699"))
			# Yellow sugar star & sprinkles
			draw_circle(Vector2(inner.get_center().x + 4.0, inner.position.y + 13.0), 3.4, Color("#FFE45C"))
			draw_line(Vector2(inner.get_center().x - 6.0, inner.end.y - 10.0), Vector2(inner.get_center().x + 1.0, inner.end.y - 13.0), Color("#6BF2FF"), 2.4, true)
			draw_line(Vector2(inner.position.x + 48.0, inner.position.y + 24.0), Vector2(inner.position.x + 54.0, inner.position.y + 29.0), Color("#FFE45C"), 2.4, true)
		elif bg_id == "sakura":
			_sb_thumb.bg_color = Color("#2C1036")
			_sb_thumb.border_color = Color("#FFA4D4")
			_sb_thumb.draw(cid, r)
			draw_circle(Vector2(inner.end.x - 20.0, inner.position.y + 16.0), 11.0, Color("#FFCCE6", 0.22))
			# Two 5-petal sakura blossoms
			for pos in [Vector2(inner.position.x + 26.0, inner.get_center().y + 2.0), Vector2(inner.end.x - 24.0, inner.get_center().y - 3.0)]:
				for k in range(5):
					var a := float(k) * TAU / 5.0
					draw_circle(pos + Vector2(cos(a), sin(a)) * 6.0, 4.4, Color("#FF9CD0"))
				draw_circle(pos, 3.0, Color("#FFE875"))
			draw_circle(Vector2(inner.get_center().x, inner.end.y - 11.0), 2.5, Color("#FFB8E0", 0.8))
		elif bg_id == "cyber":
			_sb_thumb.bg_color = Color("#120933")
			_sb_thumb.border_color = Color("#22F2FF")
			_sb_thumb.draw(cid, r)
			# Synth sun + horizon beam
			var hy := inner.position.y + inner.size.y * 0.52
			var sun_c := Vector2(inner.get_center().x, hy - 2.0)
			draw_arc(sun_c, 13.0, PI, TAU, 16, Color("#FF46A2"), 7.0, true)
			draw_line(Vector2(inner.position.x, hy), Vector2(inner.end.x, hy), Color("#26F2FF"), 2.0, true)
			# Perspective neon grid lines
			for g in range(-2, 3):
				draw_line(
					Vector2(inner.get_center().x + float(g) * 10.0, hy),
					Vector2(inner.get_center().x + float(g) * 26.0, inner.end.y),
					Color("#26F2FF", 0.72),
					1.4,
					true
				)
			draw_line(Vector2(inner.position.x, hy + 8.0), Vector2(inner.end.x, hy + 8.0), Color("#FF3EB5", 0.65), 1.3, true)
			draw_line(Vector2(inner.position.x, hy + 18.0), Vector2(inner.end.x, hy + 18.0), Color("#FF3EB5", 0.85), 1.5, true)
		elif bg_id == "ocean":
			_sb_thumb.bg_color = Color("#072E4A")
			_sb_thumb.border_color = Color("#36EBFF")
			_sb_thumb.draw(cid, r)
			# Underwater caustic waves
			draw_arc(Vector2(inner.position.x + 28.0, inner.position.y + 30.0), 22.0, -2.5, -0.5, 14, Color("#2ED8F5", 0.45), 3.0, true)
			draw_arc(Vector2(inner.end.x - 24.0, inner.position.y + 38.0), 22.0, -2.6, -0.6, 14, Color("#4CF2FF", 0.42), 3.0, true)
			# Rising translucent bubbles
			for b in [
				[Vector2(inner.position.x + 22.0, inner.end.y - 16.0), 6.5],
				[Vector2(inner.get_center().x + 2.0, inner.position.y + 18.0), 5.0],
				[Vector2(inner.end.x - 20.0, inner.get_center().y + 6.0), 7.5],
			]:
				var bc: Vector2 = b[0]
				var br: float = b[1]
				draw_arc(bc, br, 0.0, TAU, 16, Color("#98F8FF", 0.88), 1.7, true)
				draw_circle(bc + Vector2(-br * 0.35, -br * 0.35), br * 0.25, Color("#FFFFFF", 0.9))
		elif bg_id == "galaxy":
			_sb_thumb.bg_color = Color("#0B0724")
			_sb_thumb.border_color = Color("#C87DFF")
			_sb_thumb.draw(cid, r)
			# Aurora nebula stripe
			draw_line(Vector2(inner.position.x + 6.0, inner.end.y - 8.0), Vector2(inner.end.x - 6.0, inner.position.y + 10.0), Color("#7D3CFF", 0.42), 14.0, true)
			draw_line(Vector2(inner.position.x + 12.0, inner.end.y - 4.0), Vector2(inner.end.x - 10.0, inner.position.y + 14.0), Color("#26D8FF", 0.30), 7.0, true)
			# 4-point hero stars
			for sp in [Vector2(inner.position.x + 24.0, inner.position.y + 16.0), Vector2(inner.end.x - 22.0, inner.end.y - 16.0)]:
				draw_line(sp + Vector2(-7.0, 0.0), sp + Vector2(7.0, 0.0), Color("#FFF3A6"), 2.0, true)
				draw_line(sp + Vector2(0.0, -7.0), sp + Vector2(0.0, 7.0), Color("#FFF3A6"), 2.0, true)
				draw_circle(sp, 2.4, Color("#FFFFFF"))
			draw_circle(Vector2(inner.get_center().x, inner.get_center().y), 2.2, Color("#8CEEFF"))
		else:
			# Classic Milestone Swirl
			_sb_thumb.bg_color = Color("#122058")
			_sb_thumb.border_color = accent
			_sb_thumb.draw(cid, r)
			draw_arc(inner.get_center(), 16.0, 0.2, PI * 1.4, 18, Color("#3CE8FF", 0.78), 3.4, true)
			draw_arc(inner.get_center(), 9.0, PI * 0.8, TAU + 0.4, 16, Color("#7B8BFF", 0.85), 2.8, true)


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
