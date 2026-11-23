extends SceneTree

## Headless automated test suite for Kombo Core Engine (Slice 1).
## Run with: godot --headless --path . --script res://tests/run_tests.gd

const TEST_SAVE_PATH := "user://kombo_unit_test_save.json"

var _passed := 0
var _failed := 0
var _current_test := ""


func _initialize() -> void:
	print("============================================================")
	print("KOMBO CORE ENGINE -- AUTOMATED TEST SUITE")
	print("============================================================")

	_run("01_piece_catalog_and_initial_setup", _test_piece_catalog_and_initial_setup)
	_run("02_placement_collision_and_consistent_preview", _test_placement_and_collision)
	_run("03_single_row_and_col_clear", _test_single_row_and_col_clear)
	_run("04_simultaneous_multi_line_clear_and_special_awards", _test_simultaneous_multi_line_clear)
	_run("05_bomb_detonation_no_origin_farming_and_line_check", _test_bomb_detonation)
	_run("06_lightning_cross_clear_no_empty_farming_and_hold_queue", _test_lightning_cross_clear)
	_run("07_hold_slot_signal_order_and_validate_before_mutate", _test_hold_slot_mechanics)
	_run("08_multiplier_tile_stacking_and_replenish", _test_multiplier_tiles)
	_run("09_combo_3_move_grace_window_and_soft_decay", _test_combo_grace_and_streak)
	_run("10_fever_countdown_5_to_0_refresh_2x_and_extinguish", _test_fever_mode)
	_run("11_smart_deal_weighted_random_slot_and_two_piece_solvency", _test_smart_deal_guarantee)
	_run("12_game_over_detection_and_hold_rescue", _test_game_over_and_hold_rescue)
	_run("13_high_score_just_beat_disk_throttling_and_malformed_json", _test_high_score_and_persistence)
	_run("14_full_gameplay_simulation_and_invariants", _test_full_gameplay_simulation)

	# Cleanup test save file if left behind.
	var cleanup_save := SaveManager.new(TEST_SAVE_PATH)
	cleanup_save.delete_save_file()

	print("============================================================")
	print("RESULTS: %d passed, %d failed" % [_passed, _failed])
	print("============================================================")

	quit(0 if _failed == 0 else 1)


func _run(test_name: String, fn: Callable) -> void:
	_current_test = test_name
	var failures_before := _failed
	fn.call()
	if _failed == failures_before:
		_passed += 1
		print("[PASS] %s" % test_name)
	else:
		print("[FAIL] %s" % test_name)


func _assert_true(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		printerr("  ASSERTION FAILED in %s: %s" % [_current_test, msg])


func _assert_eq(actual: Variant, expected: Variant, msg: String) -> void:
	if actual != expected:
		_failed += 1
		printerr("  ASSERTION FAILED in %s: %s (expected=%s, actual=%s)" % [
			_current_test, msg, str(expected), str(actual)
		])


func _assert_approx(actual: float, expected: float, eps: float, msg: String) -> void:
	if absf(actual - expected) > eps:
		_failed += 1
		printerr("  ASSERTION FAILED in %s: %s (expected=%.4f, actual=%.4f)" % [
			_current_test, msg, expected, actual
		])


func _make_controller(seed_val: int = 42) -> GameController:
	var sm := SaveManager.new(TEST_SAVE_PATH)
	sm.delete_save_file()
	var gc := GameController.new(sm, seed_val)
	gc.start_new_game(seed_val)
	return gc


func _fill_row_except(board: BoardState, y: int, skip_xs: Array[int], color_id: int = 2) -> void:
	for x in range(BoardState.GRID_SIZE):
		if not skip_xs.has(x):
			board.set_cell(x, y, true, color_id)


func _fill_col_except(board: BoardState, x: int, skip_ys: Array[int], color_id: int = 4) -> void:
	for y in range(BoardState.GRID_SIZE):
		if not skip_ys.has(y):
			board.set_cell(x, y, true, color_id)


# ------------------------------------------------------------------------------
# 01. PieceCatalog & Initial Setup
# ------------------------------------------------------------------------------
func _test_piece_catalog_and_initial_setup() -> void:
	_assert_true(PieceCatalog.get_shape_count() >= 19, "Catalog should have at least 19 classic shapes")
	_assert_eq(PieceCatalog.COLOR_COUNT, 7, "Should have 7 jewel colors")

	var required_shapes: Array[String] = [
		"dot_1x1", "h2", "v2", "h3", "v3", "h4", "v4", "h5", "v5",
		"sq2", "sq3", "l3_br", "l4_tall_r", "t4_down", "z4_h", "s4_h", "rect_2x3", "rect_3x2"
	]
	var all_ids := PieceCatalog.get_all_shape_ids()
	for req in required_shapes:
		_assert_true(all_ids.has(req), "Missing required shape: " + req)

	# Verify weighted selection respects PieceCatalog shape weights (sq2=1.8 vs l4_tall_r=0.45 -> 4:1 ratio).
	_assert_true(PieceCatalog.get_shape_weight("sq2") > PieceCatalog.get_shape_weight("l4_tall_r"), "sq2 weight > l4_tall_r")
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var sq2_hits := 0
	var l4_hits := 0
	var subset: Array[String] = ["sq2", "l4_tall_r"]
	for _i in range(400):
		var picked := PieceCatalog.create_weighted_piece_from_ids(subset, rng)
		if picked.id == "sq2":
			sq2_hits += 1
		elif picked.id == "l4_tall_r":
			l4_hits += 1
	_assert_true(sq2_hits > l4_hits * 2, "Weighted sampling favors sq2 over l4_tall_r (%d vs %d)" % [sq2_hits, l4_hits])

	var bomb := PieceCatalog.create_bomb_piece()
	_assert_eq(bomb.special_type, PieceCatalog.SPECIAL_BOMB, "Bomb piece special_type")
	_assert_eq(bomb.cell_count(), 1, "Bomb is 1x1")

	var lightning := PieceCatalog.create_lightning_piece()
	_assert_eq(lightning.special_type, PieceCatalog.SPECIAL_LIGHTNING, "Lightning piece special_type")
	_assert_eq(lightning.cell_count(), 1, "Lightning is 1x1")

	var gc := _make_controller(100)
	_assert_eq(gc.board.get_occupied_count(), 0, "New board starts empty")
	var mults := gc.board.get_active_multiplier_cells()
	_assert_eq(mults.size(), 3, "Game starts with 3 multiplier tiles")
	var x2_count := 0
	var x3_count := 0
	for m in mults:
		if int(m["value"]) == 2:
			x2_count += 1
		elif int(m["value"]) == 3:
			x3_count += 1
	_assert_eq(x2_count, 2, "Game starts with two x2 tiles")
	_assert_eq(x3_count, 1, "Game starts with one x3 tile")

	for i in range(GameController.TRAY_SIZE):
		_assert_true(gc.tray[i] != null, "Initial tray slot %d populated" % i)
	_assert_true(gc.hold_piece == null, "Hold starts empty")
	_assert_true(not gc.is_game_over, "New game is not game over")


# ------------------------------------------------------------------------------
# 02. Placement, Collision & Consistent Preview Schema
# ------------------------------------------------------------------------------
func _test_placement_and_collision() -> void:
	var gc := _make_controller(101)
	gc.board.clear_board()
	gc.board.set_multiplier(1, 1, 2)
	gc.tray[0] = PieceCatalog.create_piece_by_id("sq2", 3) # Emerald 2x2
	gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[2] = null

	# Consistent invalid preview schema when slot is empty, Hold is empty, or placement invalid
	var preview_keys: Array[String] = [
		"valid", "placed_cells", "cleared_rows", "cleared_cols", "blast_zone_cells", "hit_multipliers"
	]
	var inv_empty_tray := gc.preview_from_tray(2, Vector2i(0, 0))
	var inv_empty_hold := gc.preview_from_hold(Vector2i(0, 0))
	var inv_oob := gc.preview_from_tray(0, Vector2i(7, 7))
	for pdict in [inv_empty_tray, inv_empty_hold, inv_oob]:
		_assert_eq(pdict["valid"], false, "Invalid preview has valid=false")
		for k in preview_keys:
			_assert_true(pdict.has(k), "Invalid preview contains consistent key: " + k)

	# Out-of-bounds checks
	_assert_true(not gc.can_place_from_tray(0, Vector2i(-1, 0)), "Negative X invalid")
	_assert_true(not gc.can_place_from_tray(0, Vector2i(7, 0)), "2x2 at X=7 overflows board")
	_assert_true(not gc.can_place_from_tray(0, Vector2i(0, 7)), "2x2 at Y=7 overflows board")
	var invalid_res := gc.place_from_tray(0, Vector2i(7, 7))
	_assert_eq(invalid_res["valid"], false, "Invalid placement returns valid=false")
	_assert_true(gc.tray[0] != null, "Invalid placement keeps tray piece intact")

	# Non-mutating valid preview check
	var prev := gc.preview_from_tray(0, Vector2i(0, 0))
	_assert_eq(prev["valid"], true, "Preview at (0,0) valid")
	_assert_eq(gc.board.get_occupied_count(), 0, "Preview does not mutate board")

	# Valid placement covering multiplier tile at (1,1)
	var res := gc.place_from_tray(0, Vector2i(0, 0))
	_assert_eq(res["valid"], true, "Valid placement succeeds")
	_assert_eq((res["placed_cells"] as Array).size(), 4, "Placed 4 cells")
	_assert_eq(res["base_chips"], 100, "4 cells * 25 = 100 base chips")
	_assert_eq(res["points_earned"], 100, "100 points earned on non-clearing placement")
	_assert_eq(gc.board.get_color_id(1, 1), 3, "Placed cell stores Emerald color_id")
	_assert_eq(gc.board.get_multiplier(1, 1), 2, "Covered multiplier tile persists until cleared")
	_assert_true(gc.tray[0] == null, "Used tray slot becomes null")

	# Overlap collision check
	_assert_true(not gc.can_place_from_tray(1, Vector2i(1, 1)), "Cannot overlap occupied cell (1,1)")
	var overlap_res := gc.place_from_tray(1, Vector2i(1, 1))
	_assert_eq(overlap_res["valid"], false, "Overlapping placement rejected")


# ------------------------------------------------------------------------------
# 03. Single Row & Single Column Clear
# ------------------------------------------------------------------------------
func _test_single_row_and_col_clear() -> void:
	var gc := _make_controller(102)
	gc.board.clear_board()
	_fill_row_except(gc.board, 3, [5, 6], 1)
	gc.board.set_cell(0, 0, true, 6) # Innocent bystander block
	gc.tray[0] = PieceCatalog.create_piece_by_id("h2", 2)
	gc.tray[1] = PieceCatalog.create_piece_by_id("v2", 5)
	gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 0)

	var r1 := gc.place_from_tray(0, Vector2i(5, 3))
	_assert_eq(r1["valid"], true, "Row-completing placement valid")
	_assert_eq(r1["lines_cleared"], 1, "Cleared 1 line")
	_assert_eq(r1["cleared_rows"], [3] as Array[int], "Row 3 cleared")
	_assert_eq(r1["cleared_cols"], [] as Array[int], "No col cleared")
	_assert_eq(r1["base_chips"], 650, "2*25 placement + 600 line = 650 base chips")
	_assert_eq(r1["points_earned"], 650, "Combo 1 = x1.0 -> 650 pts")
	_assert_eq(r1["combo_grace_left"], ScoreEngine.COMBO_GRACE_MAX, "Grace set to 3 on clear")
	_assert_true(not gc.board.is_occupied(0, 3), "Row 3 is empty after clear")
	_assert_true(gc.board.is_occupied(0, 0), "Other row untouched")

	# Clear single column (col 2)
	gc.board.clear_board()
	_fill_col_except(gc.board, 2, [6, 7], 4)
	var r2 := gc.place_from_tray(1, Vector2i(2, 6))
	_assert_eq(r2["lines_cleared"], 1, "Cleared 1 column")
	_assert_eq(r2["cleared_cols"], [2] as Array[int], "Column 2 cleared")
	_assert_eq(r2["combo_streak"], 2, "Second consecutive clear increments combo to 2")
	_assert_approx(r2["combo_mult"], 1.5, 0.001, "Combo 2 mult is x1.5")
	_assert_eq(r2["points_earned"], 975, "round(650 * 1.5) = 975")
	_assert_true(not gc.board.is_occupied(2, 0), "Col 2 is empty after clear")


# ------------------------------------------------------------------------------
# 04. Simultaneous Multi-Line Clears & Bomb / Lightning Awards
# ------------------------------------------------------------------------------
func _test_simultaneous_multi_line_clear() -> void:
	# 2-line clear -> Bomb awarded immediately into emptied tray slot
	var gc := _make_controller(103)
	gc.board.clear_board()
	_fill_row_except(gc.board, 4, [4], 1)
	_fill_col_except(gc.board, 4, [4], 2)
	gc.tray[0] = null
	gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[2] = null

	var r2 := gc.place_from_tray(1, Vector2i(4, 4))
	_assert_eq(r2["lines_cleared"], 2, "Cleared 2 lines (row 4 + col 4)")
	_assert_eq(r2["base_chips"], 1625, "25 placement + 1200 lines + 400 multi-line bonus = 1625")
	_assert_eq(r2["awarded_special"], PieceCatalog.SPECIAL_BOMB, "2-line clear awards BOMB")
	_assert_eq(r2["awarded_slot"], 1, "Bomb spawned right into emptied slot 1")
	_assert_eq(r2["tray_refilled"], false, "Tray must not refill while newly awarded Bomb occupies slot 1")
	_assert_true(gc.tray[1] != null and gc.tray[1].special_type == PieceCatalog.SPECIAL_BOMB, "Slot 1 holds Bomb")

	# 3-line clear -> Lightning awarded immediately into emptied tray slot
	gc.board.clear_board()
	_fill_row_except(gc.board, 2, [2, 3], 3)
	_fill_row_except(gc.board, 3, [2, 3], 3)
	_fill_col_except(gc.board, 2, [2, 3], 4)
	gc.tray[0] = PieceCatalog.create_piece_by_id("sq2", 5)
	gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 1)

	var r3 := gc.place_from_tray(0, Vector2i(2, 2))
	_assert_eq(r3["lines_cleared"], 3, "Cleared 3 lines (rows 2,3 + col 2)")
	_assert_eq(r3["line_chips"], 3000, "3*600 + 1200 bonus = 3000 line chips")
	_assert_eq(r3["awarded_special"], PieceCatalog.SPECIAL_LIGHTNING, "3-line clear awards LIGHTNING")
	_assert_eq(r3["awarded_slot"], 0, "Lightning spawned right into emptied slot 0")
	_assert_true(gc.tray[0] != null and gc.tray[0].special_type == PieceCatalog.SPECIAL_LIGHTNING, "Slot 0 holds Lightning")

	# 4-line clear -> +2600 multi-line bonus + Lightning
	gc.board.clear_board()
	_fill_row_except(gc.board, 5, [5, 6], 1)
	_fill_row_except(gc.board, 6, [5, 6], 1)
	_fill_col_except(gc.board, 5, [5, 6], 2)
	_fill_col_except(gc.board, 6, [5, 6], 2)
	gc.tray[2] = PieceCatalog.create_piece_by_id("sq2", 6)

	var r4 := gc.place_from_tray(2, Vector2i(5, 5))
	_assert_eq(r4["lines_cleared"], 4, "Cleared 4 lines simultaneously")
	_assert_eq(r4["line_chips"], 5000, "4*600 + 2600 bonus = 5000 line chips")
	_assert_eq(r4["awarded_special"], PieceCatalog.SPECIAL_LIGHTNING, "4-line clear awards LIGHTNING")


# ------------------------------------------------------------------------------
# 05. Bomb Detonation: No Origin Double-Count / No Empty-Space Farming + Line Check
# ------------------------------------------------------------------------------
func _test_bomb_detonation() -> void:
	var gc := _make_controller(104)
	gc.board.clear_board()

	# A. Empty-space Bomb MUST NOT award blast chips, combo, or FEVER charge!
	gc.tray[0] = PieceCatalog.create_bomb_piece()
	gc.tray[1] = PieceCatalog.create_bomb_piece()
	gc.tray[2] = PieceCatalog.create_bomb_piece()
	var r_empty := gc.place_from_tray(0, Vector2i(3, 3))
	_assert_eq(r_empty["valid"], true, "Empty-space bomb placement valid")
	_assert_eq((r_empty["blast_cells"] as Array).size(), 0, "Origin excluded from blast_cells (0 destroyed)")
	_assert_eq((r_empty["cleared_cells"] as Array).size(), 1, "Bomb still consumes itself off board")
	_assert_true(not gc.board.is_occupied(3, 3), "Bomb origin cell empty after detonation")
	_assert_eq(r_empty["blast_chips"], 0, "0 blast chips on empty space")
	_assert_eq(r_empty["base_chips"], 25, "Only 25 placement chips on empty space")
	_assert_eq(r_empty["points_earned"], 25, "Only 25 pts earned on empty-space bomb")
	_assert_eq(r_empty["combo_streak"], 0, "Empty-space bomb does NOT increment combo")
	_assert_approx(r_empty["fever_charge"], 0.0, 0.001, "Empty-space bomb does NOT charge FEVER")

	# B. Empty-space Bomb over uncovered x2 MUST preserve x2 and NOT farm combo/FEVER!
	gc.board.clear_board()
	gc.board.set_multiplier(3, 3, 2)
	var prev_fizzle := gc.preview_from_tray(1, Vector2i(3, 3))
	_assert_eq((prev_fizzle["hit_multipliers"] as Array).size(), 0, "Preview does not claim x2 on empty-space Bomb fizzle")
	var r_mult_empty := gc.place_from_tray(1, Vector2i(3, 3))
	_assert_eq((r_mult_empty["blast_cells"] as Array).size(), 0, "Origin excluded from blast_cells")
	_assert_eq((r_mult_empty["hit_multipliers"] as Array).size(), 0, "Empty-space Bomb fizzle does NOT consume uncovered origin x2")
	_assert_approx(r_mult_empty["tile_mult"], 1.0, 0.001, "No x2 farming on empty-space Bomb")
	_assert_eq(r_mult_empty["points_earned"], 25, "Only 25 placement chips on empty-space Bomb over x2")
	_assert_eq(r_mult_empty["combo_streak"], 0, "Empty-space Bomb over x2 does NOT increment combo")
	_assert_approx(r_mult_empty["fever_charge"], 0.0, 0.001, "Empty-space Bomb over x2 does NOT charge FEVER")
	_assert_true(not gc.board.is_occupied(3, 3), "Bomb still consumed itself off board")
	_assert_eq(gc.board.get_multiplier(3, 3), 2, "Uncovered x2 under origin preserved after empty-space fizzle")

	# B2. Bomb over origin x2 that blasts >=1 adjacent block DOES trigger origin x2!
	gc.board.set_cell(3, 2, true, 1)
	var prev_hit := gc.preview_from_tray(2, Vector2i(3, 3))
	_assert_eq((prev_hit["hit_multipliers"] as Array).size(), 1, "Preview shows origin x2 when blasting adjacent block")
	var r_mult_real := gc.place_from_tray(2, Vector2i(3, 3))
	_assert_eq((r_mult_real["blast_cells"] as Array).size(), 1, "1 pre-existing adjacent block blasted")
	_assert_eq((r_mult_real["hit_multipliers"] as Array).size(), 1, "Origin x2 triggered when blasting real block")
	_assert_approx(r_mult_real["tile_mult"], 2.0, 0.001, "Origin x2 multiplier applied")
	_assert_eq(r_mult_real["points_earned"], 230, "(25 placement + 90 blast) * x2 = 230 pts")
	_assert_eq(r_mult_real["combo_streak"], 1, "Real blast increments combo")
	_assert_eq(gc.board.get_multiplier(3, 3), 1, "Origin x2 consumed on real blast")

	# C. Real detonation: 4 pre-existing neighbors + covered x2 + uncovered x3 + outside survivor
	gc = _make_controller(1041)
	gc.board.clear_board()
	gc.board.set_cell(2, 2, true, 1)
	gc.board.set_cell(3, 2, true, 2)
	gc.board.set_cell(4, 4, true, 3)
	gc.board.set_cell(2, 4, true, 4)
	gc.board.set_cell(5, 5, true, 6)
	gc.board.set_multiplier(2, 2, 2)
	gc.board.set_multiplier(4, 2, 3) # Uncovered empty cell inside 3x3
	gc.tray[0] = PieceCatalog.create_bomb_piece()
	gc.tray[1] = PieceCatalog.create_bomb_piece()
	gc.tray[2] = PieceCatalog.create_bomb_piece()

	var r1 := gc.place_from_tray(0, Vector2i(3, 3))
	_assert_eq(r1["valid"], true, "Bomb placement valid")
	_assert_eq(r1["special_triggered"], PieceCatalog.SPECIAL_BOMB, "Bomb triggered")
	_assert_eq((r1["blast_cells"] as Array).size(), 4, "Exactly 4 pre-existing neighbors in blast_cells (origin excluded)")
	_assert_eq((r1["cleared_cells"] as Array).size(), 5, "4 neighbors + origin in cleared_cells")
	_assert_eq(r1["blast_chips"], 360, "4 * 90 = 360 blast chips")
	_assert_eq(r1["base_chips"], 385, "25 placement + 360 blast = 385 base chips")
	_assert_approx(r1["tile_mult"], 2.0, 0.001, "Covered x2 inside 3x3 triggered")
	_assert_eq(r1["points_earned"], 770, "385 * 2.0 = 770 pts")
	_assert_eq(r1["combo_streak"], 1, "Destroying real blocks advances combo streak")
	_assert_true(not gc.board.is_occupied(3, 3), "Bomb cell itself cleared")
	_assert_true(not gc.board.is_occupied(2, 2), "3x3 neighbor cleared")
	_assert_true(gc.board.is_occupied(5, 5), "Outside 3x3 block preserved")
	_assert_eq(gc.board.get_multiplier(4, 2), 3, "Uncovered empty x3 multiplier tile NOT wasted by blast")

	# D. Corner detonation (0,0) safety check
	gc.board.set_cell(1, 0, true, 0)
	gc.board.set_cell(0, 1, true, 0)
	var r_corner := gc.place_from_tray(1, Vector2i(0, 0))
	_assert_eq(r_corner["valid"], true, "Corner bomb valid")
	_assert_eq((r_corner["blast_zone_cells"] as Array).size(), 4, "Corner 3x3 clamped to 2x2 (4 cells)")
	_assert_eq((r_corner["blast_cells"] as Array).size(), 2, "2 pre-existing corner neighbors destroyed")
	_assert_true(not gc.board.is_occupied(1, 0) and not gc.board.is_occupied(0, 1), "Corner neighbors cleared")

	# E. Bomb completing a row AND blasting adjacent blocks outside that row
	gc.board.clear_board()
	_fill_row_except(gc.board, 5, [3], 2)
	gc.board.set_cell(3, 4, true, 5)
	gc.board.set_cell(4, 6, true, 5)
	var r_combo := gc.place_from_tray(2, Vector2i(3, 5))
	_assert_eq(r_combo["lines_cleared"], 1, "Bomb completed row 5")
	_assert_eq(r_combo["cleared_rows"], [5] as Array[int], "Row 5 recorded in cleared_rows")
	_assert_eq((r_combo["blast_cells"] as Array).size(), 2, "Only 2 extra adjacent blocks outside row 5 in blast_cells")
	_assert_true(not gc.board.is_occupied(0, 5), "Completed row 5 fully cleared")
	_assert_true(not gc.board.is_occupied(3, 4) and not gc.board.is_occupied(4, 6), "3x3 adjacent blocks cleared")


# ------------------------------------------------------------------------------
# 06. Lightning Cross Clear, No Empty Farming & Hold Special Queue
# ------------------------------------------------------------------------------
func _test_lightning_cross_clear() -> void:
	var gc := _make_controller(105)
	gc.board.clear_board()

	# A. Empty-space Lightning MUST NOT farm blast chips, combo, or FEVER!
	gc.tray[0] = PieceCatalog.create_lightning_piece()
	gc.tray[1] = PieceCatalog.create_lightning_piece()
	gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
	var r_empty := gc.place_from_tray(0, Vector2i(4, 2))
	_assert_eq((r_empty["blast_cells"] as Array).size(), 0, "Empty-space Lightning has 0 blast_cells")
	_assert_eq(r_empty["blast_chips"], 0, "0 blast chips on empty space")
	_assert_eq(r_empty["points_earned"], 25, "Only 25 placement chips")
	_assert_eq(r_empty["combo_streak"], 0, "Empty-space Lightning does NOT increment combo")
	_assert_approx(r_empty["fever_charge"], 0.0, 0.001, "Empty-space Lightning does NOT charge FEVER")
	_assert_true(not gc.board.is_occupied(4, 2), "Lightning consumed itself off board")

	# B. Real cross clear: 6 scattered blocks along row 2 and col 4 + 1 off-cross block + x3 mult
	gc.board.clear_board()
	gc.board.set_cell(0, 2, true, 1)
	gc.board.set_cell(1, 2, true, 1)
	gc.board.set_cell(7, 2, true, 1)
	gc.board.set_cell(4, 0, true, 3)
	gc.board.set_cell(4, 6, true, 3)
	gc.board.set_cell(4, 7, true, 3)
	gc.board.set_cell(0, 0, true, 6) # Off-cross survivor
	gc.board.set_multiplier(4, 7, 3)

	var res := gc.place_from_tray(1, Vector2i(4, 2))
	_assert_eq(res["valid"], true, "Lightning placement valid")
	_assert_eq(res["special_triggered"], PieceCatalog.SPECIAL_LIGHTNING, "Lightning triggered")
	_assert_eq((res["blast_zone_cells"] as Array).size(), 15, "8 row + 8 col - 1 intersection = 15 zone cells")
	_assert_eq((res["blast_cells"] as Array).size(), 6, "Exactly 6 pre-existing cross blocks destroyed (origin excluded)")
	_assert_eq((res["cleared_cells"] as Array).size(), 7, "6 cross blocks + origin in cleared_cells")
	_assert_eq(res["lines_cleared"], 0, "Partial row/col does not falsely trigger free Bomb award")
	_assert_eq(res["awarded_special"], PieceCatalog.SPECIAL_NORMAL, "No infinite special loop")
	_assert_approx(res["tile_mult"], 3.0, 0.001, "x3 multiplier on col 4 triggered by Lightning")
	_assert_eq(res["base_chips"], 25 + 6 * 90, "25 placement + 540 blast = 565 base chips")
	_assert_eq(res["points_earned"], 1695, "565 * 3.0 = 1695 pts")
	_assert_eq(res["combo_streak"], 1, "Destroying real blocks increments combo")
	_assert_true(not gc.board.is_occupied(0, 2) and not gc.board.is_occupied(4, 7), "Row 2 & Col 4 wiped clean")
	_assert_true(gc.board.is_occupied(0, 0), "Off-cross cell untouched")

	# C. Special earned from Hold when all 3 tray slots are FULL goes into pending_specials
	gc.board.clear_board()
	_fill_row_except(gc.board, 1, [1], 2)
	_fill_col_except(gc.board, 1, [1], 2)
	gc.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
	gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)
	gc.hold_piece = PieceCatalog.create_piece_by_id("dot_1x1", 3)

	var r_hold_sp := gc.place_from_hold(Vector2i(1, 1))
	_assert_eq(r_hold_sp["awarded_special"], PieceCatalog.SPECIAL_BOMB, "2-line clear from Hold awards Bomb")
	_assert_eq(r_hold_sp["awarded_slot"], -1, "All 3 tray slots full -> queued into pending_specials")
	_assert_eq(gc.pending_specials.size(), 1, "pending_specials holds queued Bomb")

	gc.place_from_tray(0, Vector2i(0, 7))
	gc.place_from_tray(1, Vector2i(1, 7))
	var r_drain := gc.place_from_tray(2, Vector2i(2, 7))
	_assert_eq(r_drain["tray_refilled"], true, "Tray refilled after emptying 3 slots")
	_assert_true(gc.tray[0] != null and gc.tray[0].special_type == PieceCatalog.SPECIAL_BOMB, "Queued Bomb surfaced in refilled tray")


# ------------------------------------------------------------------------------
# 07. Hold Slot, Strict Signal Ordering & Validate-Before-Mutate
# ------------------------------------------------------------------------------
func _test_hold_slot_mechanics() -> void:
	var gc := _make_controller(106)
	gc.board.clear_board()
	gc.tray[0] = PieceCatalog.create_piece_by_id("h3", 0)
	gc.tray[1] = PieceCatalog.create_piece_by_id("sq2", 1)
	gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)

	# Store tray[0] into empty Hold
	var h1 := gc.hold_from_tray(0)
	_assert_eq(h1["success"], true, "Hold store succeeded")
	_assert_eq(h1["swapped"], false, "First hold is a store, not swap")
	_assert_true(gc.tray[0] == null, "Tray slot 0 emptied")
	_assert_eq(gc.hold_piece.id, "h3", "Hold now holds h3")
	_assert_true(gc.hold_used_this_turn, "hold_used_this_turn set to true")

	# Validate-before-mutate: invalid placement must NOT touch hold_used_this_turn or turn_count!
	var turns_before := gc.turn_count
	var bad_place := gc.place_from_tray(1, Vector2i(7, 7))
	_assert_eq(bad_place["valid"], false, "OOB placement rejected")
	_assert_true(gc.hold_used_this_turn, "Invalid placement preserves hold_used_this_turn=true")
	_assert_eq(gc.turn_count, turns_before, "Invalid placement does NOT increment turn_count")
	var bad_hold_place := gc.place_from_hold(Vector2i(7, 0))
	_assert_eq(bad_hold_place["valid"], false, "OOB hold placement rejected")
	_assert_true(gc.hold_used_this_turn, "Invalid hold placement preserves hold_used_this_turn=true")
	_assert_eq(gc.turn_count, turns_before, "Invalid hold placement does NOT increment turn_count")
	_assert_true(gc.hold_piece != null and gc.hold_piece.id == "h3", "Invalid hold placement preserves hold_piece")

	# Anti-stall guard: cannot swap again before placing
	_assert_true(not gc.can_hold_from_tray(1), "Second hold blocked before placing")
	var h_blocked := gc.hold_from_tray(1)
	_assert_eq(h_blocked["success"], false, "Second hold rejected")
	_assert_eq(h_blocked["reason"], "already_used_this_turn", "Correct rejection reason")

	# Place tray[2] -> resets hold_used_this_turn
	var pl := gc.place_from_tray(2, Vector2i(0, 0))
	_assert_eq(pl["valid"], true, "Placed tray[2]")
	_assert_true(not gc.hold_used_this_turn, "Placement resets hold_used_this_turn")

	# Swap tray[1] (sq2) with Hold (h3)
	var h2 := gc.hold_from_tray(1)
	_assert_eq(h2["success"], true, "Swap succeeded")
	_assert_eq(h2["swapped"], true, "Reported swapped=true")
	_assert_eq(gc.tray[1].id, "h3", "Tray[1] received h3")
	_assert_eq(gc.hold_piece.id, "sq2", "Hold received sq2")
	_assert_true(gc.hold_used_this_turn, "Swap consumes hold_used_this_turn")

	# Strict signal ordering on place_from_hold: hold_changed BEFORE move_resolved, game_over_triggered, state_changed
	var signal_log: Array[String] = []
	gc.hold_changed.connect(func(_p: PieceCatalog.Piece) -> void: signal_log.append("hold_changed"))
	gc.tray_refilled.connect(func(_t: Array) -> void: signal_log.append("tray_refilled"))
	gc.move_resolved.connect(func(_r: Dictionary) -> void: signal_log.append("move_resolved"))
	gc.game_over_triggered.connect(func(_s: int, _h: int) -> void: signal_log.append("game_over_triggered"))
	gc.state_changed.connect(func() -> void: signal_log.append("state_changed"))

	var pl_hold := gc.place_from_hold(Vector2i(5, 5))
	_assert_eq(pl_hold["valid"], true, "Direct placement from Hold succeeded")
	_assert_true(gc.hold_piece == null, "Hold emptied after direct placement")
	_assert_true(not gc.hold_used_this_turn, "Direct placement from Hold resets hold_used_this_turn")
	_assert_true(gc.board.is_occupied(5, 5) and gc.board.is_occupied(6, 6), "Hold sq2 placed on board")
	_assert_eq(signal_log, ["hold_changed", "move_resolved", "state_changed"] as Array[String], "Exact signal order on place_from_hold")

	# Signal order when place_from_hold triggers Game Over too!
	signal_log.clear()
	gc.board.clear_board()
	for y in range(BoardState.GRID_SIZE):
		for x in range(BoardState.GRID_SIZE):
			if (x + y) % 2 == 0:
				gc.board.set_cell(x, y, true, 0)
	gc.tray[0] = PieceCatalog.create_piece_by_id("sq3", 1)
	gc.tray[1] = PieceCatalog.create_piece_by_id("sq3", 2)
	gc.tray[2] = null
	gc.hold_piece = PieceCatalog.create_piece_by_id("dot_1x1", 3)
	var go_hold := gc.place_from_hold(Vector2i(1, 0))
	_assert_eq(go_hold["game_over"], true, "Placing hold piece triggered Game Over")
	_assert_eq(
		signal_log,
		["hold_changed", "move_resolved", "game_over_triggered", "state_changed"] as Array[String],
		"hold_changed fires BEFORE move_resolved, game_over_triggered, and state_changed"
	)

	# Signal order on start_new_game(): hold_changed BEFORE tray_refilled and state_changed
	signal_log.clear()
	gc.start_new_game(1061)
	_assert_eq(
		signal_log,
		["hold_changed", "tray_refilled", "state_changed"] as Array[String],
		"start_new_game emits hold_changed BEFORE tray_refilled and state_changed"
	)

	# Holding the last remaining piece when Hold is empty triggers automatic 3-piece refill
	var gc2 := _make_controller(1062)
	gc2.board.clear_board()
	gc2.tray[0] = null
	gc2.tray[1] = PieceCatalog.create_piece_by_id("h3", 0)
	gc2.tray[2] = null
	gc2.hold_piece = null
	var h3 := gc2.hold_from_tray(1)
	_assert_eq(h3["success"], true, "Holding last tray piece succeeded")
	_assert_eq(h3["tray_refilled"], true, "Emptying tray via Hold triggered automatic 3-piece refill")
	_assert_eq(gc2.hold_piece.id, "h3", "Last piece moved into Hold")
	_assert_true(gc2.tray[0] != null and gc2.tray[1] != null and gc2.tray[2] != null, "3 fresh pieces dealt")


# ------------------------------------------------------------------------------
# 08. Multiplier Tile Stacking (x2 * x3 = x6) & Replenishment
# ------------------------------------------------------------------------------
func _test_multiplier_tiles() -> void:
	var gc := _make_controller(107)
	gc.board.clear_board()
	gc.board.set_multiplier(2, 5, 2)
	gc.board.set_multiplier(6, 5, 3)

	gc.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
	gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)
	gc.place_from_tray(0, Vector2i(2, 5))
	gc.place_from_tray(1, Vector2i(6, 5))
	_assert_eq(gc.board.get_multiplier(2, 5), 2, "x2 tile persists under placed block")
	_assert_eq(gc.board.get_multiplier(6, 5), 3, "x3 tile persists under placed block")

	for x in range(1, 8):
		gc.board.set_cell(x, 5, true, 3)

	var res := gc.place_from_tray(2, Vector2i(0, 5))
	_assert_eq(res["lines_cleared"], 1, "Row 5 cleared")
	_assert_eq((res["hit_multipliers"] as Array).size(), 2, "Hit both x2 and x3 multipliers")
	_assert_approx(res["tile_mult"], 6.0, 0.001, "x2 * x3 stacks multiplicatively to x6.0")
	_assert_eq(res["base_chips"], 625, "25 placement + 600 line = 625")
	_assert_eq(res["points_earned"], 3750, "625 * 6.0 = 3750 pts")
	_assert_eq(gc.board.get_multiplier(2, 5), 1, "Consumed x2 multiplier reset to 1")
	_assert_eq(gc.board.get_multiplier(6, 5), 1, "Consumed x3 multiplier reset to 1")

	var spawned: Array = res["spawned_multipliers"]
	_assert_true(spawned.size() >= 1 and spawned.size() <= 2, "Replenished 1-2 multiplier tiles after clear")
	_assert_true(gc.board.get_active_multiplier_cells().size() <= BoardState.MAX_ACTIVE_MULTIPLIERS, "Active multipliers capped at 3")


# ------------------------------------------------------------------------------
# 09. Authentic 3-Move Combo Grace Window, Escalation & Soft FEVER Decay
# ------------------------------------------------------------------------------
func _test_combo_grace_and_streak() -> void:
	var gc := _make_controller(108)
	var expected_mults: Array[float] = [1.0, 1.5, 2.0, 2.5, 3.0]

	# Escalate 1..5 across consecutive clears
	for step in range(5):
		gc.board.clear_board()
		_fill_row_except(gc.board, 0, [0], 1)
		gc.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
		gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
		gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)
		var res := gc.place_from_tray(0, Vector2i(0, 0))
		_assert_eq(res["combo_streak"], step + 1, "Combo streak step %d" % (step + 1))
		_assert_eq(res["combo_grace_left"], 3, "Combo grace refreshed to 3 on clear")
		_assert_approx(res["combo_mult"], expected_mults[step], 0.001, "Combo mult step %d" % (step + 1))
	_assert_eq(gc.score_engine.best_combo, 5, "best_combo recorded peak of 5")

	# Now test 3-move grace window with setup moves (fresh controller, non-FEVER)
	var gc2 := _make_controller(1082)
	gc2.board.clear_board()
	_fill_row_except(gc2.board, 0, [0], 1)
	gc2.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc2.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
	gc2.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)
	gc2.place_from_tray(0, Vector2i(0, 0)) # Combo 1, charge=0.34

	gc2.board.clear_board()
	_fill_row_except(gc2.board, 0, [0], 1)
	var c2 := gc2.place_from_tray(1, Vector2i(0, 0)) # Combo 2, grace=3, charge=0.68
	_assert_eq(c2["combo_streak"], 2, "Combo is 2")
	_assert_eq(c2["combo_grace_left"], 3, "Grace is 3")
	_assert_approx(c2["fever_charge"], 0.68, 0.001, "FEVER charge is 0.68")

	# 2 setup placements MUST preserve combo=2 and fever_charge=0.68!
	gc2.board.clear_board()
	gc2.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc2.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
	gc2.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)

	var s1 := gc2.place_from_tray(0, Vector2i(7, 7))
	_assert_eq(s1["combo_streak"], 2, "Setup move 1 preserves combo=2")
	_assert_eq(s1["combo_grace_left"], 2, "Setup move 1 decrements grace 3 -> 2")
	_assert_approx(s1["fever_charge"], 0.68, 0.001, "Setup move 1 preserves fever_charge=0.68")

	var s2 := gc2.place_from_tray(1, Vector2i(6, 7))
	_assert_eq(s2["combo_streak"], 2, "Setup move 2 preserves combo=2")
	_assert_eq(s2["combo_grace_left"], 1, "Setup move 2 decrements grace 2 -> 1")
	_assert_approx(s2["fever_charge"], 0.68, 0.001, "Setup move 2 preserves fever_charge=0.68")

	# Clearing on move 3 extends combo to 3!
	_fill_row_except(gc2.board, 1, [0], 1)
	var c3 := gc2.place_from_tray(2, Vector2i(0, 1))
	_assert_eq(c3["combo_streak"], 3, "Clearing within 3-move grace extends combo to 3")
	_assert_eq(c3["combo_grace_left"], 3, "Clearing resets grace to 3")
	_assert_approx(c3["combo_mult"], 2.0, 0.001, "Combo 3 mult = x2.0")

	# Now test expiry after 3 consecutive non-clearing moves (non-FEVER soft decay!)
	var gc3 := _make_controller(1083)
	gc3.board.clear_board()
	_fill_row_except(gc3.board, 0, [0], 1)
	gc3.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc3.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
	gc3.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)
	gc3.place_from_tray(0, Vector2i(0, 0)) # charge 0.34
	gc3.board.clear_board()
	_fill_row_except(gc3.board, 0, [0], 1)
	gc3.place_from_tray(1, Vector2i(0, 0)) # combo=2, grace=3, charge=0.68

	gc3.board.clear_board()
	gc3.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc3.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
	gc3.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)
	gc3.place_from_tray(0, Vector2i(0, 7)) # grace 2
	gc3.place_from_tray(1, Vector2i(1, 7)) # grace 1
	var expired := gc3.place_from_tray(2, Vector2i(2, 7)) # grace 0 -> reset!
	_assert_eq(expired["combo_streak"], 0, "3rd non-clearing move resets combo to 0")
	_assert_eq(expired["combo_grace_left"], 0, "Grace is 0 after expiry")
	_assert_approx(expired["fever_charge"], 0.33, 0.001, "Non-active FEVER decays softly by 0.35 (0.68 -> 0.33)")

	# 4th non-clearing move (idle, not in combo): decays gently by 0.15
	gc3.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	var idle := gc3.place_from_tray(0, Vector2i(3, 7))
	_assert_approx(idle["fever_charge"], 0.18, 0.001, "Idle non-clearing move decays fever_charge by 0.15 (0.33 -> 0.18)")


# ------------------------------------------------------------------------------
# 10. FEVER Countdown (5 -> 4 -> 3 -> 2 -> 1 -> 0), Refresh, 2x Bonus & Extinguish
# ------------------------------------------------------------------------------
func _test_fever_mode() -> void:
	var gc := _make_controller(109)

	# 3 clears -> ignite FEVER on move 3 (with an x2 tile)
	gc.board.clear_board()
	_fill_row_except(gc.board, 0, [0], 1)
	gc.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	var m1 := gc.place_from_tray(0, Vector2i(0, 0))
	_assert_approx(m1["fever_charge"], 0.34, 0.001, "Move 1 fever charge = 0.34")
	_assert_eq(m1["fever_active"], false, "Move 1 not yet in FEVER")

	gc.board.clear_board()
	_fill_row_except(gc.board, 0, [0], 1)
	var m2 := gc.place_from_tray(1, Vector2i(0, 0))
	_assert_approx(m2["fever_charge"], 0.68, 0.001, "Move 2 fever charge = 0.68")
	_assert_eq(m2["fever_active"], false, "Move 2 not yet in FEVER")

	# Move 3: base=625, combo=3 (x2.0), tile=x2.0, fever=x2.0 -> total_mult=8.0 -> 5000 pts!
	gc.board.clear_board()
	_fill_row_except(gc.board, 0, [0], 1)
	gc.board.set_multiplier(4, 0, 2)
	var m3 := gc.place_from_tray(2, Vector2i(0, 0))
	_assert_eq(m3["fever_active"], true, "Move 3 ignites FEVER")
	_assert_eq(m3["fever_just_ignited"], true, "Move 3 reports fever_just_ignited=true")
	_assert_eq(m3["fever_turns_left"], 5, "FEVER starts with 5 turns")
	_assert_approx(m3["fever_charge"], 1.0, 0.001, "FEVER charge is 1.0 on ignition")
	_assert_approx(m3["fever_mult"], 2.0, 0.001, "FEVER adds x2.0 multiplier")
	_assert_approx(m3["total_mult"], 8.0, 0.001, "combo(2.0)*tile(2.0)*fever(2.0) = 8.0")
	_assert_eq(m3["points_earned"], 5000, "625 * 8.0 = 5000 pts")

	# Clear while in FEVER: 5 -> 6 (and next clear stays capped at 6!)
	gc.board.clear_board()
	_fill_row_except(gc.board, 0, [0], 1)
	gc.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	var m4 := gc.place_from_tray(0, Vector2i(0, 0))
	_assert_eq(m4["fever_just_ignited"], false, "Already in FEVER")
	_assert_eq(m4["fever_turns_left"], 6, "Clearing in FEVER refreshes 5 -> 6")
	_assert_approx(m4["fever_charge"], 1.0, 0.001, "FEVER charge remains 1.0 on clear")

	gc.board.clear_board()
	_fill_row_except(gc.board, 0, [0], 1)
	var m5 := gc.place_from_tray(1, Vector2i(0, 0))
	_assert_eq(m5["fever_turns_left"], 6, "FEVER turns capped at 6")

	# Non-clearing countdown: 6 -> 5 -> 4 -> 3
	gc.board.clear_board()
	gc.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	var d1 := gc.place_from_tray(0, Vector2i(0, 7)) # 6 -> 5
	_assert_eq(d1["fever_active"], true, "FEVER still active at 5 turns left")
	_assert_eq(d1["fever_turns_left"], 5, "Countdown 6 -> 5")
	_assert_approx(d1["fever_charge"], 1.0, 0.001, "charge clampf(5/5) = 1.0")
	_assert_eq(d1["fever_extinguished"], false, "Not extinguished")

	var d2 := gc.place_from_tray(1, Vector2i(1, 7)) # 5 -> 4
	_assert_eq(d2["fever_active"], true, "FEVER still active at 4 turns left")
	_assert_eq(d2["fever_turns_left"], 4, "Countdown 5 -> 4")
	_assert_approx(d2["fever_charge"], 0.8, 0.001, "charge 4/5 = 0.8")

	var d3 := gc.place_from_tray(2, Vector2i(2, 7)) # 4 -> 3
	_assert_eq(d3["fever_active"], true, "FEVER still active at 3 turns left")
	_assert_eq(d3["fever_turns_left"], 3, "Countdown 4 -> 3")
	_assert_approx(d3["fever_charge"], 0.6, 0.001, "charge 3/5 = 0.6")

	# Mid-countdown clear refreshes 3 -> 4 with monotonic charge 4/5 = 0.8 (NOT jumping to 1.0!)
	gc.board.clear_board()
	_fill_row_except(gc.board, 0, [0], 1)
	gc.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	var ref := gc.place_from_tray(0, Vector2i(0, 0))
	_assert_eq(ref["fever_active"], true, "FEVER active on mid-countdown clear")
	_assert_eq(ref["fever_turns_left"], 4, "Clear refreshed FEVER 3 -> 4")
	_assert_approx(ref["fever_charge"], 0.8, 0.001, "Monotonic FEVER charge at 4 turns = 0.8")
	_assert_approx(ref["fever_mult"], 2.0, 0.001, "Clear gets x2.0 FEVER bonus")

	# Drain 4 -> 3 (0.6) -> 2 (0.4) -> 1 (0.2), then clear 1 line -> 2 turns (0.4, NOT 1.0!)
	gc.board.clear_board()
	var drain_to_one_turns: Array[int] = [3, 2, 1]
	var drain_to_one_charges: Array[float] = [0.6, 0.4, 0.2]
	for idx in range(3):
		gc.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
		gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
		gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
		var step := gc.place_from_tray(0, Vector2i(idx, 6))
		_assert_eq(step["fever_turns_left"], drain_to_one_turns[idx], "Drain-to-1 step %d turns_left" % idx)
		_assert_approx(step["fever_charge"], drain_to_one_charges[idx], 0.001, "Drain-to-1 step %d charge" % idx)
		_assert_eq(step["fever_active"], true, "Drain-to-1 step %d stays active" % idx)
		_assert_eq(step["fever_extinguished"], false, "Drain-to-1 step %d not extinguished" % idx)

	# Clear at 1 turn left (0.2) -> 2 turns left (0.4, NOT 1.0!)
	gc.board.clear_board()
	_fill_row_except(gc.board, 0, [0], 1)
	gc.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	var ref_low := gc.place_from_tray(0, Vector2i(0, 0))
	_assert_eq(ref_low["fever_active"], true, "FEVER remains active after clear at 1 turn left")
	_assert_eq(ref_low["fever_turns_left"], 2, "Clear refreshed FEVER 1 -> 2")
	_assert_approx(ref_low["fever_charge"], 0.4, 0.001, "Monotonic FEVER charge at 2 turns = 0.4 (NOT 1.0)")

	# Drain remaining 2 -> 1 (0.2) -> 0 (0.0, extinguish ONLY at 0!)
	gc.board.clear_board()
	gc.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	var fin1 := gc.place_from_tray(0, Vector2i(0, 6))
	_assert_eq(fin1["fever_turns_left"], 1, "Drain 2 -> 1")
	_assert_approx(fin1["fever_charge"], 0.2, 0.001, "Charge at 1 turn = 0.2")
	_assert_eq(fin1["fever_active"], true, "Still active at 1 turn")
	_assert_eq(fin1["fever_extinguished"], false, "Not extinguished at 1 turn")

	var fin0 := gc.place_from_tray(1, Vector2i(1, 6))
	_assert_eq(fin0["fever_turns_left"], 0, "Drain 1 -> 0")
	_assert_approx(fin0["fever_charge"], 0.0, 0.001, "Charge at 0 turns = 0.0")
	_assert_eq(fin0["fever_active"], false, "Extinguished at 0 turns")
	_assert_eq(fin0["fever_extinguished"], true, "Reports fever_extinguished=true at 0 turns")

	# Multi-line bonus accelerates FEVER ignition: 3-line (+0.64) + 2-line (+0.49) -> ignites in 2 moves!
	gc.board.clear_board()
	_fill_row_except(gc.board, 1, [1, 2], 1)
	_fill_row_except(gc.board, 2, [1, 2], 1)
	_fill_col_except(gc.board, 1, [1, 2], 1)
	gc.tray[0] = PieceCatalog.create_piece_by_id("sq2", 0)
	gc.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
	gc.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)
	var fast1 := gc.place_from_tray(0, Vector2i(1, 1))
	_assert_approx(fast1["fever_charge"], 0.64, 0.001, "3-line clear adds 0.34 + 2*0.15 = 0.64")
	_assert_eq(fast1["fever_active"], false, "Not yet ignited after 1 move")

	gc.board.clear_board()
	_fill_row_except(gc.board, 4, [4], 2)
	_fill_col_except(gc.board, 4, [4], 2)
	var fast2 := gc.place_from_tray(1, Vector2i(4, 4))
	_assert_eq(fast2["fever_active"], true, "2-line clear (+0.49) ignites FEVER on move 2")
	_assert_eq(fast2["fever_just_ignited"], true, "Multi-line fast ignition confirmed")


# ------------------------------------------------------------------------------
# 11. Smart Deal: Random Slot Replacement, Weighted Sampling & 2-Piece Solvency
# ------------------------------------------------------------------------------
func _test_smart_deal_guarantee() -> void:
	# A. Single 1x1 hole: every deal fits AND fitting piece isn't hardcoded to slot 0!
	var gc := _make_controller(110)
	gc.board.clear_board()
	for y in range(BoardState.GRID_SIZE):
		for x in range(BoardState.GRID_SIZE):
			if not (x == 3 and y == 3):
				gc.board.set_cell(x, y, true, (x + y) % PieceCatalog.COLOR_COUNT)

	var slot_hits: Array[int] = [0, 0, 0]
	for trial in range(45):
		gc.deal_fresh_tray()
		var any_fits := false
		for s in range(GameController.TRAY_SIZE):
			var p := gc.tray[s]
			if p != null and gc.board.can_piece_fit_anywhere(p):
				any_fits = true
				slot_hits[s] += 1
		_assert_true(any_fits, "Single-hole trial %d MUST include at least 1 fitting piece" % trial)
	_assert_true(
		slot_hits[0] > 0 and slot_hits[1] > 0 and slot_hits[2] > 0,
		"Smart deal distributes fitting piece randomly across all 3 slots (%s)" % str(slot_hits)
	)

	# B. Legal checkerboard board (zero pre-existing full rows/cols, only isolated 1x1 spaces):
	# Smart deal MUST guarantee 2-piece solvency so player is never death-trapped on 1 move!
	var gc2 := _make_controller(1102)
	gc2.board.clear_board()
	for y in range(BoardState.GRID_SIZE):
		for x in range(BoardState.GRID_SIZE):
			if (x + y) % 2 == 0:
				gc2.board.set_cell(x, y, true, 0)
	for trial in range(30):
		gc2.deal_fresh_tray()
		var fitting_count := 0
		for s in range(GameController.TRAY_SIZE):
			if gc2.tray[s] != null and gc2.board.can_piece_fit_anywhere(gc2.tray[s]):
				fitting_count += 1
		_assert_true(
			fitting_count >= 2,
			"2-piece solvency trial %d must deal >= 2 playable pieces on checkerboard board (got %d)" % [trial, fitting_count]
		)


# ------------------------------------------------------------------------------
# 12. Game Over Detection & Hold Rescue Edge Cases
# ------------------------------------------------------------------------------
func _test_game_over_and_hold_rescue() -> void:
	var gc := _make_controller(111)
	gc.board.clear_board()
	for y in range(BoardState.GRID_SIZE):
		for x in range(BoardState.GRID_SIZE):
			if (x + y) % 2 == 0:
				gc.board.set_cell(x, y, true, 0)

	# Case A: 2 unplayable sq3 pieces, Hold empty -> Game Over
	gc.tray[0] = PieceCatalog.create_piece_by_id("sq3", 1)
	gc.tray[1] = PieceCatalog.create_piece_by_id("sq3", 2)
	gc.tray[2] = null
	gc.hold_piece = null
	gc.hold_used_this_turn = false
	_assert_true(not gc.can_continue(), "Case A: 2 unplayable pieces with empty Hold = Game Over")

	# Case B: 1 unplayable sq3 in tray, playable dot_1x1 in Hold -> NOT Game Over
	gc.tray[0] = PieceCatalog.create_piece_by_id("sq3", 1)
	gc.tray[1] = null
	gc.tray[2] = null
	gc.hold_piece = PieceCatalog.create_piece_by_id("dot_1x1", 3)
	_assert_true(gc.can_continue(), "Case B: playable Hold piece keeps player alive")

	# Case C: Hold Rescue! 1 unplayable sq3 in tray, Hold empty, hold_used_this_turn == false
	gc.tray[0] = PieceCatalog.create_piece_by_id("sq3", 1)
	gc.tray[1] = null
	gc.tray[2] = null
	gc.hold_piece = null
	gc.hold_used_this_turn = false
	gc.is_game_over = false
	_assert_true(gc.can_continue(), "Case C: Hold Rescue keeps player alive")
	var rescue := gc.hold_from_tray(0)
	_assert_eq(rescue["success"], true, "Hold Rescue action succeeded")
	_assert_eq(rescue["tray_refilled"], true, "Hold Rescue dealt 3 fresh pieces")
	_assert_eq(rescue["game_over"], false, "Smart deal after Hold Rescue guaranteed survival")

	# Case D: 1 unplayable sq3 in tray, Hold empty, BUT hold_used_this_turn == true -> Game Over
	gc.tray[0] = PieceCatalog.create_piece_by_id("sq3", 1)
	gc.tray[1] = null
	gc.tray[2] = null
	gc.hold_piece = null
	gc.hold_used_this_turn = true
	_assert_true(not gc.can_continue(), "Case D: already used Hold this turn -> Game Over")

	# Case E: 1 unplayable sq3 in tray AND unplayable sq3 in Hold -> Game Over
	gc.tray[0] = PieceCatalog.create_piece_by_id("sq3", 1)
	gc.hold_piece = PieceCatalog.create_piece_by_id("sq3", 4)
	gc.hold_used_this_turn = false
	_assert_true(not gc.can_continue(), "Case E: both tray and Hold unplayable -> Game Over")


# ------------------------------------------------------------------------------
# 13. High Score One-Shot Event, Disk Throttling & Malformed JSON Guard
# ------------------------------------------------------------------------------
func _test_high_score_and_persistence() -> void:
	# A. Starting from 0: no disk hammering on low moves; milestone save at >=500; flush on new_game
	var sm1 := SaveManager.new(TEST_SAVE_PATH)
	sm1.delete_save_file()
	var gc1 := GameController.new(sm1, 112)
	gc1.start_new_game(112)
	_assert_eq(sm1.save_count, 0, "Starting fresh from 0 performs 0 disk writes")

	gc1.board.clear_board()
	gc1.tray[0] = PieceCatalog.create_piece_by_id("sq2", 0)
	gc1.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
	gc1.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)
	var m_low := gc1.place_from_tray(0, Vector2i(0, 0)) # 100 pts
	_assert_eq(m_low["is_new_high_score"], true, "First run score > 0 sets is_new_high_score=true")
	_assert_eq(m_low["just_beat_high_score"], false, "First run from 0 does NOT fire just_beat_high_score")
	_assert_eq(sm1.save_count, 0, "Low score (<2500) does NOT hammer disk")

	# Jump over 2500-point milestone in one x6 clear (3750 pts -> total 3850)
	gc1.board.clear_board()
	_fill_row_except(gc1.board, 2, [0], 1)
	gc1.board.set_multiplier(3, 2, 2)
	gc1.board.set_multiplier(5, 2, 3)
	var m_mile := gc1.place_from_tray(1, Vector2i(0, 2)) # +3750 -> 3850
	_assert_eq(m_mile["new_score"], 3850, "Score reached 3850")
	_assert_eq(sm1.save_count, 1, "Crossing 2500-point milestone triggers 1 disk save")

	# Another small move (+25 -> 3875) must NOT hammer disk!
	gc1.board.clear_board()
	var m_small := gc1.place_from_tray(2, Vector2i(0, 0))
	_assert_eq(m_small["new_score"], 3875, "Score is 3875")
	_assert_eq(sm1.save_count, 1, "Small increment after milestone does NOT write to disk")

	# Starting a new game flushes unsaved tail (3875) cleanly!
	gc1.start_new_game(113)
	_assert_eq(sm1.high_score, 3875, "start_new_game flushed unsaved 3875 PB to SaveManager")
	_assert_eq(sm1.save_count, 2, "Flush wrote updated 3875 record to disk")
	_assert_eq(gc1.score_engine.session_starting_high_score, 3875, "Session starting high score is 3875")

	# B. Subsequent run: just_beat_high_score fires ONCE when strictly exceeding 3875!
	gc1.board.clear_board()
	gc1.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	gc1.tray[1] = PieceCatalog.create_piece_by_id("dot_1x1", 1)
	gc1.tray[2] = PieceCatalog.create_piece_by_id("dot_1x1", 2)
	var under := gc1.place_from_tray(0, Vector2i(0, 0)) # 25 pts <= 3875
	_assert_eq(under["is_new_high_score"], false, "Below 3875 -> is_new_high_score=false")
	_assert_eq(under["just_beat_high_score"], false, "Below 3875 -> just_beat_high_score=false")
	_assert_eq(sm1.save_count, 2, "No disk write below PB")

	# Clear with x2*x3 + 1 line = 3750 pts -> total 3775 (still below 3875!)
	gc1.board.clear_board()
	_fill_row_except(gc1.board, 3, [0], 1)
	gc1.board.set_multiplier(2, 3, 2)
	gc1.board.set_multiplier(4, 3, 3)
	var close := gc1.place_from_tray(1, Vector2i(0, 3)) # 3775
	_assert_eq(close["new_score"], 3775, "Score is 3775 (still below 3875)")
	_assert_eq(close["just_beat_high_score"], false, "Still below 3875")

	# Clear another line -> 3775 + 938 = 4713 > 3875 -> FIRES just_beat_high_score ONCE & saves immediately!
	gc1.board.clear_board()
	_fill_row_except(gc1.board, 3, [0], 1)
	var beat := gc1.place_from_tray(2, Vector2i(0, 3))
	_assert_true(int(beat["new_score"]) > 3875, "Strictly exceeded 3875")
	_assert_eq(beat["is_new_high_score"], true, "is_new_high_score=true after beating PB")
	_assert_eq(beat["just_beat_high_score"], true, "just_beat_high_score fires ONCE when crossing prior PB")
	_assert_eq(sm1.save_count, 3, "Crossing prior PB saves immediately to disk")

	# Next move above PB: is_new_high_score stays true, just_beat_high_score MUST be false!
	gc1.board.clear_board()
	gc1.tray[0] = PieceCatalog.create_piece_by_id("dot_1x1", 0)
	var after_beat := gc1.place_from_tray(0, Vector2i(0, 0))
	_assert_eq(after_beat["is_new_high_score"], true, "is_new_high_score remains true for Game Over PB check")
	_assert_eq(after_beat["just_beat_high_score"], false, "just_beat_high_score is strictly one-shot per run")
	_assert_eq(sm1.save_count, 3, "No extra disk write immediately after PB beat")

	# Reload from disk in fresh SaveManager
	var sm2 := SaveManager.new(TEST_SAVE_PATH)
	_assert_eq(sm2.high_score, int(beat["new_score"]), "Reloaded high_score matches saved PB")
	_assert_eq(sm2.best_combo, 2, "Reloaded best_combo matches saved peak")

	# C. Malformed JSON type guard & crash immunity
	var malformed_payloads: Array[String] = [
		'{"high_score": null, "best_combo": [1, 2, 3]}',
		'{"high_score": {"nested": 99}, "best_combo": "invalid"}',
		'{"high_score": true, "best_combo": false}',
		'{"high_score": -420, "best_combo": -5}',
		'{broken json',
		'',
	]
	for payload in malformed_payloads:
		var f := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
		f.store_string(payload)
		f.close()
		var sm_bad := SaveManager.new(TEST_SAVE_PATH)
		_assert_eq(sm_bad.high_score, 0, "Malformed JSON safely defaults high_score=0 for: " + payload)
		_assert_eq(sm_bad.best_combo, 0, "Malformed JSON safely defaults best_combo=0 for: " + payload)

	# Valid float JSON numbers (standard JSON number type) parse cleanly and clamp >= 0
	var f_valid := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	f_valid.store_string('{"high_score": 1234.0, "best_combo": 7.0}')
	f_valid.close()
	var sm_valid := SaveManager.new(TEST_SAVE_PATH)
	_assert_eq(sm_valid.high_score, 1234, "JSON float high_score parses cleanly")
	_assert_eq(sm_valid.best_combo, 7, "JSON float best_combo parses cleanly")

	# Huge finite float JSON numbers clamp safely to 9e15 without int64 overflow
	var f_huge := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	f_huge.store_string('{"high_score": 1e30, "best_combo": 1e30}')
	f_huge.close()
	var sm_huge := SaveManager.new(TEST_SAVE_PATH)
	_assert_eq(sm_huge.high_score, 9000000000000000, "Huge JSON float 1e30 clamps safely to 9e15")
	_assert_eq(sm_huge.best_combo, 9000000000000000, "Huge JSON float best_combo clamps safely to 9e15")

	# D. Unlockable Block Skins & Coin Wallet Persistence
	var sm_skins := SaveManager.new(TEST_SAVE_PATH)
	sm_skins.delete_save_file()
	_assert_true(sm_skins.is_skin_unlocked("jewel"), "Default 'jewel' skin unlocked from start")
	_assert_eq(sm_skins.equipped_skin, "jewel", "Default equipped skin is 'jewel'")
	_assert_true(not sm_skins.is_skin_unlocked("wood"), "'wood' skin locked initially")
	_assert_true(not sm_skins.unlock_skin("wood", 150), "Cannot unlock 'wood' with 0 coins")
	sm_skins.add_coins(400)
	_assert_eq(sm_skins.coins, 400, "Added 400 coins to wallet")
	_assert_true(sm_skins.unlock_skin("wood", 150), "Unlocked 'wood' for 150 coins")
	_assert_eq(sm_skins.coins, 250, "250 coins remaining after unlocking 'wood'")
	_assert_true(sm_skins.is_skin_unlocked("wood"), "'wood' is now unlocked")
	_assert_true(sm_skins.equip_skin("wood"), "Equipped 'wood' skin")
	_assert_eq(sm_skins.equipped_skin, "wood", "equipped_skin updated to 'wood'")

	var sm_skins_reload := SaveManager.new(TEST_SAVE_PATH)
	_assert_eq(sm_skins_reload.coins, 250, "Reloaded coin balance persisted (250)")
	_assert_true(sm_skins_reload.is_skin_unlocked("wood"), "Reloaded 'wood' unlock state persisted")
	_assert_eq(sm_skins_reload.equipped_skin, "wood", "Reloaded equipped_skin persisted ('wood')")
	_assert_eq(TilePainter.get_skin_catalog().size(), 5, "TilePainter exposes 5 block skins")
	TilePainter.set_active_skin("neon")
	_assert_eq(TilePainter.get_active_skin(), "neon", "TilePainter active skin switched to 'neon'")
	TilePainter.set_active_skin("jewel")

	# D2. Unlockable Patterned Backgrounds Persistence
	_assert_eq(TilePainter.get_background_catalog().size(), 6, "TilePainter exposes 6 background themes (Swirl + 5 patterned)")
	_assert_true(sm_skins_reload.is_background_unlocked("swirl"), "Default 'swirl' background unlocked")
	_assert_true(not sm_skins_reload.is_background_unlocked("candy"), "'candy' background locked initially")
	sm_skins_reload.add_coins(25000)
	_assert_true(sm_skins_reload.unlock_background("candy", 20000), "Unlocked 'candy' background for 20,000 coins")
	_assert_eq(sm_skins_reload.equipped_background, "candy", "'candy' equipped on unlock")
	var sm_bg_reload := SaveManager.new(TEST_SAVE_PATH)
	_assert_true(sm_bg_reload.is_background_unlocked("candy"), "'candy' unlock persisted")
	_assert_eq(sm_bg_reload.equipped_background, "candy", "'candy' equipped state persisted")
	TilePainter.set_active_background("candy")
	_assert_eq(TilePainter.get_active_background(), "candy", "TilePainter active background switched to 'candy'")
	TilePainter.set_active_background("swirl")

	# E. Notifications Setting Persistence & Localized Reminder Templates
	_assert_eq(sm_skins_reload.notifications_enabled, true, "Notifications default to enabled")
	sm_skins_reload.update_settings(true, true, true, false)
	var sm_notif_reload := SaveManager.new(TEST_SAVE_PATH)
	_assert_eq(sm_notif_reload.notifications_enabled, false, "Notifications toggle persists across reload")
	var nm := NotificationManager.new()
	var th_msgs := nm.get_localized_reminders("th_TH")
	var en_msgs := nm.get_localized_reminders("en_US")
	_assert_eq(th_msgs.size(), 3, "Thai localized reminders has 3 scheduled entries")
	_assert_eq(en_msgs.size(), 3, "English localized reminders has 3 scheduled entries")
	_assert_true(String(th_msgs[0]["title"]).contains("เล่นเร็วๆ"), "Thai quick-break notification title present")
	nm.free()


# ------------------------------------------------------------------------------
# 14. Full Multi-Game Simulation & MoveResult Schema / Invariants
# ------------------------------------------------------------------------------
func _test_full_gameplay_simulation() -> void:
	var required_result_keys: Array[String] = [
		"valid", "placed_cells", "cleared_rows", "cleared_cols", "blast_cells",
		"lines_cleared", "base_chips", "combo_streak", "combo_grace_left", "combo_mult",
		"tile_mult", "hit_multipliers", "fever_active", "fever_just_ignited",
		"fever_extinguished", "fever_mult", "total_mult", "points_earned", "new_score",
		"is_new_high_score", "just_beat_high_score", "awarded_special", "awarded_slot",
		"game_over",
	]

	var total_moves := 0
	var total_lines := 0
	var checked_schema := false

	for game_seed in range(200, 205):
		var gc := _make_controller(game_seed)
		var moves_in_game := 0
		while not gc.is_game_over and moves_in_game < 120:
			var moved := false
			var best_source := -2
			var best_origin := Vector2i(-1, -1)
			var best_lines := -1

			for s in range(GameController.TRAY_SIZE):
				var p := gc.get_tray_piece(s)
				if p == null:
					continue
				var placements := gc.board.get_valid_placements(p)
				for orig in placements:
					var prev := gc.preview_from_tray(s, orig)
					var lines := (prev["cleared_rows"] as Array).size() + (prev["cleared_cols"] as Array).size()
					if lines > best_lines:
						best_lines = lines
						best_source = s
						best_origin = orig
						if lines >= 2:
							break

			if gc.hold_piece != null:
				var hold_placements := gc.board.get_valid_placements(gc.hold_piece)
				for orig in hold_placements:
					var prev := gc.preview_from_hold(orig)
					var lines := (prev["cleared_rows"] as Array).size() + (prev["cleared_cols"] as Array).size()
					if lines > best_lines:
						best_lines = lines
						best_source = -1
						best_origin = orig
						if lines >= 2:
							break

			if best_source >= 0:
				var res := gc.place_from_tray(best_source, best_origin)
				_assert_eq(res["valid"], true, "Simulated tray placement must succeed")
				if not checked_schema:
					for k in required_result_keys:
						_assert_true(res.has(k), "MoveResult missing required key: " + k)
					checked_schema = true
				total_lines += int(res["lines_cleared"])
				moved = true
			elif best_source == -1:
				var res := gc.place_from_hold(best_origin)
				_assert_eq(res["valid"], true, "Simulated hold placement must succeed")
				total_lines += int(res["lines_cleared"])
				moved = true
			else:
				var rescue_slot := -1
				for s in range(GameController.TRAY_SIZE):
					if gc.can_hold_from_tray(s):
						rescue_slot = s
						break
				_assert_true(rescue_slot >= 0, "If not game_over and no piece fits, Hold Rescue must be legal")
				var hres := gc.hold_from_tray(rescue_slot)
				_assert_eq(hres["success"], true, "Hold Rescue succeeded in simulation")
				moved = true

			# Verify core invariants after every move
			for y in range(BoardState.GRID_SIZE):
				var row_count := 0
				for x in range(BoardState.GRID_SIZE):
					if gc.board.is_occupied(x, y):
						row_count += 1
				_assert_true(row_count < BoardState.GRID_SIZE, "No uncleared full row should remain")
			for x in range(BoardState.GRID_SIZE):
				var col_count := 0
				for y in range(BoardState.GRID_SIZE):
					if gc.board.is_occupied(x, y):
						col_count += 1
				_assert_true(col_count < BoardState.GRID_SIZE, "No uncleared full col should remain")

			_assert_true(
				gc.board.get_active_multiplier_cells().size() <= BoardState.MAX_ACTIVE_MULTIPLIERS,
				"Active multipliers capped at MAX_ACTIVE_MULTIPLIERS"
			)

			var any_tray := false
			for s in range(GameController.TRAY_SIZE):
				if gc.tray[s] != null:
					any_tray = true
					break
			_assert_true(any_tray, "Tray is never left completely empty after a move")

			if moved:
				moves_in_game += 1
				total_moves += 1

	_assert_true(total_moves >= 50, "Simulation executed substantial number of valid turns (%d)" % total_moves)
	_assert_true(total_lines > 0, "Simulation cleared lines (%d)" % total_lines)
	_assert_true(checked_schema, "Verified complete MoveResult schema")
