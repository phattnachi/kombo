extends Control

## Main scene orchestrator for Kombo.
## Wires GameController, SoundSynth, SwirlBg shader, HudView, BoardView,
## TrayAndHoldView, VfxLayer, and GameOverOverlay into a responsive 540x960
## portrait one-handed gameplay loop.

const LOGICAL_SIZE := Vector2(540.0, 960.0)
const SWIRL_SHADER_PATH := "res://shaders/swirl_bg.gdshader"

var controller: GameController
var run_persistence: RunPersistence
var ad_bridge: AdBridge
var sound_synth: SoundSynth
var bgm_manager: BgmManager

var swirl_bg: ColorRect
var swirl_mat: ShaderMaterial
var playfield_root: Control
var hud_view: HudView
var board_view: BoardView
var tray_view: TrayAndHoldView
var vfx_layer: VfxLayer
var game_over_overlay: GameOverOverlay
var revive_overlay: ReviveOverlay
var title_overlay: TitleOverlay
var gem_stage_select_overlay: GemStageSelectOverlay
var settings_overlay: SettingsOverlay
var how_to_play_overlay: HowToPlayOverlay
var studio_splash: StudioSplashOverlay

var _bg_heat: float = 0.0
var _bg_heat_target: float = 0.0
var _bg_speed: float = 0.58
var _bg_speed_target: float = 0.58
var _bg_pulse: float = 0.0
var _orb_tick_index: int = 0
var _playfield_base_pos: Vector2 = Vector2.ZERO
var _vibration_enabled: bool = true
var _audio_gesture_unlocked: bool = false
var is_game_paused: bool = false
var is_processing_ad: bool = false
var _sound_muted_by_ad: bool = false
var _pending_game_over_score: int = 0
var _pending_game_over_high: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if get_tree() != null:
		get_tree().set_quit_on_go_back(false)

	_build_scene_hierarchy()
	_init_controller_and_signals()
	_apply_saved_settings()
	_layout_responsive()
	start_fresh_run( -1, false)
	if title_overlay != null:
		playfield_root.visible = false
		_show_title_screen()
		if bgm_manager != null:
			bgm_manager.set_mode(BgmManager.Mode.TITLE)
	if studio_splash != null:
		studio_splash.start_splash()
	set_process(true)


func _exit_tree() -> void:
	_persist_active_run_if_needed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_responsive()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_persist_active_run_if_needed()
		if controller != null:
			controller.flush_save()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_navigation()


func _input(event: InputEvent) -> void:
	if _audio_gesture_unlocked:
		return
	var is_gesture := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		is_gesture = true
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		is_gesture = true
	elif event is InputEventKey and (event as InputEventKey).pressed:
		is_gesture = true
	if is_gesture:
		_audio_gesture_unlocked = true
		if bgm_manager != null:
			bgm_manager.ensure_started_on_gesture()


func _handle_back_navigation() -> void:
	if is_processing_ad:
		return
	if studio_splash != null and studio_splash.is_active():
		studio_splash.hide_immediate()
		return
	if how_to_play_overlay != null and how_to_play_overlay.is_open():
		how_to_play_overlay.close_guide(true)
		return
	if settings_overlay != null and settings_overlay.is_open():
		settings_overlay.close_settings(true)
		return
	if gem_stage_select_overlay != null and gem_stage_select_overlay.is_open():
		gem_stage_select_overlay.close_selector(true)
		return
	if revive_overlay != null and revive_overlay.is_open():
		_on_revive_declined()
		return
	if game_over_overlay != null and game_over_overlay.visible:
		_on_home_requested()
		return
	if playfield_root != null and playfield_root.visible and (title_overlay == null or not title_overlay.visible):
		_on_hud_settings_requested()
		return
	# Already on Title Screen -> persist cleanly and quit on Android Back.
	_persist_active_run_if_needed()
	if controller != null:
		controller.flush_save()
	if get_tree() != null:
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if is_processing_ad:
		return
	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.echo:
			if key_ev.keycode == KEY_R:
				if revive_overlay != null:
					revive_overlay.hide_overlay()
				if gem_stage_select_overlay != null and gem_stage_select_overlay.is_open():
					gem_stage_select_overlay.close_selector(false)
				if how_to_play_overlay != null and how_to_play_overlay.is_open():
					how_to_play_overlay.close_guide(false)
				if settings_overlay != null and settings_overlay.is_open():
					settings_overlay.close_settings(false)
				start_fresh_run()
			elif key_ev.keycode == KEY_M:
				var next_on := sound_synth.is_muted()
				_on_sfx_toggled(next_on)
				_on_bgm_toggled(next_on)
				if settings_overlay != null:
					settings_overlay.sync_states(not sound_synth.is_muted(), bgm_manager.is_bgm_enabled(), _vibration_enabled)
			elif key_ev.keycode == KEY_B:
				if bgm_manager != null:
					_on_bgm_toggled(not bgm_manager.is_bgm_enabled())
					if settings_overlay != null:
						settings_overlay.sync_states(not sound_synth.is_muted(), bgm_manager.is_bgm_enabled(), _vibration_enabled)
			elif key_ev.keycode == KEY_ESCAPE:
				if how_to_play_overlay != null and how_to_play_overlay.is_open():
					how_to_play_overlay.close_guide(true)
				elif settings_overlay != null and settings_overlay.is_open():
					settings_overlay.close_settings(true)
				elif gem_stage_select_overlay != null and gem_stage_select_overlay.is_open():
					gem_stage_select_overlay.close_selector(true)
				elif playfield_root != null and playfield_root.visible and (title_overlay == null or not title_overlay.visible) and (studio_splash == null or not studio_splash.visible) and (game_over_overlay == null or not game_over_overlay.visible):
					_on_hud_settings_requested()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)

	# Smoothly transition living swirl background heat & speed (only push shader uniforms when changed).
	var prev_heat := _bg_heat
	var prev_speed := _bg_speed
	var prev_pulse := _bg_pulse
	var heat_rate := 5.5 if _bg_heat_target > _bg_heat else 2.8
	_bg_heat = lerpf(_bg_heat, _bg_heat_target, clampf(dt * heat_rate, 0.0, 1.0))
	if absf(_bg_heat - _bg_heat_target) < 0.001:
		_bg_heat = _bg_heat_target
	_bg_speed = lerpf(_bg_speed, _bg_speed_target, clampf(dt * 4.2, 0.0, 1.0))
	if absf(_bg_speed - _bg_speed_target) < 0.001:
		_bg_speed = _bg_speed_target
	if _bg_pulse > 0.0:
		_bg_pulse = maxf(0.0, _bg_pulse - dt * 2.6)

	if swirl_mat != null:
		if absf(_bg_heat - prev_heat) > 0.0005:
			swirl_mat.set_shader_parameter("heat", _bg_heat)
		if absf(_bg_speed - prev_speed) > 0.0005:
			swirl_mat.set_shader_parameter("speed", _bg_speed)
		if absf(_bg_pulse - prev_pulse) > 0.0005:
			swirl_mat.set_shader_parameter("pulse", _bg_pulse)

	# Apply trauma screen shake to playfield without persistent drift.
	if playfield_root != null and vfx_layer != null:
		playfield_root.position = _playfield_base_pos + vfx_layer.get_shake_offset()


func start_fresh_run(seed_value: int = -1, clear_saved_classic: bool = true) -> void:
	if clear_saved_classic and run_persistence != null:
		run_persistence.clear_run(GameController.GameMode.CLASSIC)
	if vfx_layer != null:
		vfx_layer.clear_all()
		vfx_layer.set_fever_intensity(0.0)
	if game_over_overlay != null:
		game_over_overlay.hide_overlay()
	if revive_overlay != null:
		revive_overlay.hide_overlay()
	if board_view != null:
		board_view.clear_placement_preview()
		board_view.set_heat_level(0, false)

	_bg_heat_target = 0.0
	_bg_speed_target = 0.58
	_bg_pulse = 0.0
	if bgm_manager != null and (title_overlay == null or not title_overlay.visible):
		bgm_manager.set_mode(BgmManager.Mode.PLAYING)

	controller.start_new_game(seed_value)
	hud_view.clear_mode_badge()
	hud_view.set_initial_state(controller.score_engine.score, controller.score_engine.high_score)
	board_view.set_board_state(controller.board)
	tray_view.set_input_enabled(true)
	tray_view.set_heat_level(0, false)
	tray_view.sync_from_controller(controller)
	tray_view.animate_tray_refill()


func start_daily_run(date_key: String = "") -> bool:
	var res := controller.start_daily_challenge(date_key, true)
	if not bool(res.get("started", false)):
		return false

	if vfx_layer != null:
		vfx_layer.clear_all()
		vfx_layer.set_fever_intensity(0.0)
	if game_over_overlay != null:
		game_over_overlay.hide_overlay()
	if revive_overlay != null:
		revive_overlay.hide_overlay()
	if board_view != null:
		board_view.clear_placement_preview()
		board_view.set_heat_level(0, false)

	_bg_heat_target = 0.0
	_bg_speed_target = 0.58
	_bg_pulse = 0.0
	if bgm_manager != null:
		bgm_manager.set_mode(BgmManager.Mode.PLAYING)

	var dkey := String(res.get("date_key", DailyChallenge.get_today_date_key()))
	var short_date := DailyChallenge.format_display_date(dkey, false)
	hud_view.set_daily_badge(true, short_date, int(res.get("attempt_number", 1)), DailyChallenge.MAX_DAILY_ATTEMPTS)
	hud_view.set_initial_state(controller.score_engine.score, controller.score_engine.high_score)
	board_view.set_board_state(controller.board)
	tray_view.set_input_enabled(true)
	tray_view.set_heat_level(0, false)
	tray_view.sync_from_controller(controller)
	tray_view.animate_tray_refill()
	_persist_active_run_if_needed()
	return true


func start_sprint_run(seed_value: int = -1) -> void:
	if run_persistence != null:
		run_persistence.clear_run(GameController.GameMode.SPRINT)
	if vfx_layer != null:
		vfx_layer.clear_all()
		vfx_layer.set_fever_intensity(0.0)
	if game_over_overlay != null:
		game_over_overlay.hide_overlay()
	if revive_overlay != null:
		revive_overlay.hide_overlay()
	if board_view != null:
		board_view.clear_placement_preview()
		board_view.set_heat_level(0, false)

	_bg_heat_target = 0.0
	_bg_speed_target = 0.72
	_bg_pulse = 0.0
	if bgm_manager != null:
		bgm_manager.set_mode(BgmManager.Mode.PLAYING)

	controller.start_sprint_game(seed_value)
	hud_view.set_sprint_badge(true, controller.sprint_moves_left, controller.sprint_moves_limit)
	hud_view.set_initial_state(controller.score_engine.score, controller.score_engine.high_score)
	board_view.set_board_state(controller.board)
	tray_view.set_input_enabled(true)
	tray_view.set_heat_level(0, false)
	tray_view.sync_from_controller(controller)
	tray_view.animate_tray_refill()


func start_gem_hunt_run(seed_value: int = -1, start_stage: int = 1) -> void:
	if run_persistence != null:
		run_persistence.clear_run(GameController.GameMode.GEM_HUNT)
	if vfx_layer != null:
		vfx_layer.clear_all()
		vfx_layer.set_fever_intensity(0.0)
	if game_over_overlay != null:
		game_over_overlay.hide_overlay()
	if revive_overlay != null:
		revive_overlay.hide_overlay()
	if board_view != null:
		board_view.clear_placement_preview()
		board_view.set_heat_level(0, false)

	_bg_heat_target = 0.0
	_bg_speed_target = 0.64
	_bg_pulse = 0.0
	if bgm_manager != null:
		bgm_manager.set_mode(BgmManager.Mode.PLAYING)

	controller.start_gem_hunt_game(seed_value, start_stage)
	hud_view.set_gem_hunt_badge(
		true,
		controller.gem_hunt_stage,
		controller.gem_hunt_targets_left,
		controller.gem_hunt_targets_total,
		controller.score_engine.stage_mult
	)
	hud_view.set_initial_state(controller.score_engine.score, controller.score_engine.high_score)
	board_view.set_board_state(controller.board)
	tray_view.set_input_enabled(true)
	tray_view.set_heat_level(0, false)
	tray_view.sync_from_controller(controller)
	tray_view.animate_tray_refill()


func _persist_active_run_if_needed() -> void:
	if controller == null or run_persistence == null:
		return
	if controller.is_game_over:
		run_persistence.clear_run(controller.game_mode)
	elif controller.should_persist_run():
		run_persistence.save_run(controller.game_mode, controller.export_run_state())


func _try_resume_saved_mode(mode: int) -> bool:
	if run_persistence == null or controller == null:
		return false
	var today := DailyChallenge.get_today_date_key()
	var saved := run_persistence.get_saved_run(mode, today)
	if saved.is_empty():
		return false
	if not controller.restore_run_state(saved):
		run_persistence.clear_run(mode)
		return false

	if vfx_layer != null:
		vfx_layer.clear_all()
	if game_over_overlay != null:
		game_over_overlay.hide_overlay()
	if revive_overlay != null:
		revive_overlay.hide_overlay()
	if board_view != null:
		board_view.clear_placement_preview()
		board_view.set_board_state(controller.board)
		board_view.set_heat_level(controller.score_engine.combo_streak, controller.score_engine.fever_active)

	hud_view.set_initial_state(controller.score_engine.score, controller.score_engine.high_score)
	if controller.is_daily_mode():
		var short_d := DailyChallenge.format_display_date(controller.daily_date_key, false)
		hud_view.set_daily_badge(true, short_d, controller.daily_attempt_number, DailyChallenge.MAX_DAILY_ATTEMPTS)
	elif controller.is_sprint_mode():
		hud_view.set_sprint_badge(true, controller.sprint_moves_left, controller.sprint_moves_limit)
	elif controller.is_gem_hunt_mode():
		hud_view.set_gem_hunt_badge(
			true,
			controller.gem_hunt_stage,
			controller.gem_hunt_targets_left,
			controller.gem_hunt_targets_total,
			controller.score_engine.stage_mult
		)
	else:
		hud_view.clear_mode_badge()

	var se := controller.score_engine
	var cur_mult := se.get_current_combo_mult() * se.get_current_fever_mult() * maxf(1.0, se.stage_mult)
	hud_view.set_preview_mult(se.combo_streak, se.fever_active, se.fever_charge, se.fever_turns_left, 0, cur_mult)

	tray_view.set_input_enabled(true)
	tray_view.set_heat_level(se.combo_streak, se.fever_active)
	tray_view.sync_from_controller(controller)
	tray_view.animate_tray_refill()
	_update_atmosphere(se.combo_streak, se.fever_active, false, false)
	return true


func _show_title_screen() -> void:
	if title_overlay != null:
		title_overlay.show_title(
			controller.save_manager.high_score,
			_build_daily_title_info(),
			_build_sprint_title_info(),
			_build_gem_hunt_title_info(),
			_build_classic_title_info()
		)


func _build_classic_title_info() -> Dictionary:
	var live_resume := (controller.game_mode == GameController.GameMode.CLASSIC and controller.should_persist_run())
	if live_resume:
		return {"can_resume": true, "score": controller.score_engine.score}
	if run_persistence != null:
		var sum := run_persistence.get_run_summary(GameController.GameMode.CLASSIC)
		if bool(sum.get("has_run", false)):
			return {"can_resume": true, "score": int(sum.get("score", 0))}
	return {"can_resume": false, "score": 0}


func _build_gem_hunt_title_info() -> Dictionary:
	var sm := controller.save_manager
	var can_resume := controller.is_gem_hunt_mode() and controller.should_persist_run()
	var active_stage := controller.gem_hunt_stage
	var targets_left := controller.gem_hunt_targets_left
	if not can_resume and run_persistence != null:
		var sum := run_persistence.get_run_summary(GameController.GameMode.GEM_HUNT)
		if bool(sum.get("has_run", false)):
			can_resume = true
			active_stage = int(sum.get("gem_hunt_stage", 1))
			targets_left = int(sum.get("gem_hunt_targets_left", 0))
	return {
		"best_stage": sm.gem_hunt_best_stage,
		"best_score": sm.gem_hunt_high_score,
		"can_resume": can_resume,
		"active_stage": active_stage,
		"targets_left": targets_left,
	}


func _build_sprint_title_info() -> Dictionary:
	var sm := controller.save_manager
	var can_resume := controller.is_sprint_mode() and controller.should_persist_run()
	var m_left := controller.sprint_moves_left
	if not can_resume and run_persistence != null:
		var sum := run_persistence.get_run_summary(GameController.GameMode.SPRINT)
		if bool(sum.get("has_run", false)):
			can_resume = true
			m_left = int(sum.get("sprint_moves_left", GameController.SPRINT_TOTAL_MOVES))
	return {
		"sprint_high_score": sm.sprint_high_score,
		"sprint_best_combo": sm.sprint_best_combo,
		"can_resume": can_resume,
		"moves_left": m_left,
	}


func _build_daily_title_info() -> Dictionary:
	var today := DailyChallenge.get_today_date_key()
	var sm := controller.save_manager
	sm.sync_daily_date(today)
	var can_resume := controller.is_daily_mode() and not controller.is_game_over and controller.daily_date_key == today
	var active_att := controller.daily_attempt_number
	if not can_resume and run_persistence != null:
		var sum := run_persistence.get_run_summary(GameController.GameMode.DAILY, today)
		if bool(sum.get("has_run", false)):
			can_resume = true
			active_att = int(sum.get("daily_attempt_number", 1))
	return {
		"date_key": today,
		"attempts_left": sm.get_daily_attempts_left(today),
		"daily_best_score": sm.daily_best_score,
		"daily_best_combo": sm.daily_best_combo,
		"daily_streak": sm.daily_streak,
		"can_resume": can_resume,
		"active_attempt": active_att,
	}


func _build_scene_hierarchy() -> void:
	# 1. Full-screen living swirling shader background.
	swirl_bg = ColorRect.new()
	swirl_bg.name = "SwirlBg"
	swirl_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	swirl_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swirl_bg.color = Color("#18255E")
	if ResourceLoader.exists(SWIRL_SHADER_PATH):
		var sh := load(SWIRL_SHADER_PATH) as Shader
		if sh != null:
			swirl_mat = ShaderMaterial.new()
			swirl_mat.shader = sh
			swirl_mat.set_shader_parameter("heat", 0.0)
			swirl_mat.set_shader_parameter("speed", 0.58)
			swirl_mat.set_shader_parameter("pulse", 0.0)
			swirl_bg.material = swirl_mat
	add_child(swirl_bg)

	# 2. Centered 540x960 logical portrait playfield container.
	playfield_root = Control.new()
	playfield_root.name = "PlayfieldRoot"
	playfield_root.size = LOGICAL_SIZE
	playfield_root.custom_minimum_size = LOGICAL_SIZE
	playfield_root.mouse_filter = Control.MOUSE_FILTER_PASS
	playfield_root.clip_contents = false
	add_child(playfield_root)

	hud_view = HudView.new()
	hud_view.name = "HudView"
	hud_view.position = Vector2.ZERO
	hud_view.size = Vector2(540.0, 190.0)
	playfield_root.add_child(hud_view)

	board_view = BoardView.new()
	board_view.name = "BoardView"
	board_view.position = BoardView.DEFAULT_RECT.position
	board_view.size = BoardView.DEFAULT_RECT.size
	playfield_root.add_child(board_view)

	tray_view = TrayAndHoldView.new()
	tray_view.name = "TrayAndHoldView"
	tray_view.position = TrayAndHoldView.DEFAULT_RECT.position
	tray_view.size = TrayAndHoldView.DEFAULT_RECT.size
	tray_view.set_board_view(board_view)
	playfield_root.add_child(tray_view)

	# 3. High-performance single-pass VFX overlay above board/HUD/tray.
	vfx_layer = VfxLayer.new()
	vfx_layer.name = "VfxLayer"
	vfx_layer.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vfx_layer.position = Vector2.ZERO
	vfx_layer.size = LOGICAL_SIZE
	vfx_layer.z_index = 60
	playfield_root.add_child(vfx_layer)

	# 4. Full-screen Game Over celebration modal, Revive modal & Title Screen overlay.
	game_over_overlay = GameOverOverlay.new()
	game_over_overlay.name = "GameOverOverlay"
	game_over_overlay.z_index = 100
	add_child(game_over_overlay)

	revive_overlay = ReviveOverlay.new()
	revive_overlay.name = "ReviveOverlay"
	revive_overlay.z_index = 105
	add_child(revive_overlay)

	title_overlay = TitleOverlay.new()
	title_overlay.name = "TitleOverlay"
	title_overlay.z_index = 120
	add_child(title_overlay)

	gem_stage_select_overlay = GemStageSelectOverlay.new()
	gem_stage_select_overlay.name = "GemStageSelectOverlay"
	gem_stage_select_overlay.z_index = 132
	add_child(gem_stage_select_overlay)

	settings_overlay = SettingsOverlay.new()
	settings_overlay.name = "SettingsOverlay"
	settings_overlay.z_index = 135
	add_child(settings_overlay)

	how_to_play_overlay = HowToPlayOverlay.new()
	how_to_play_overlay.name = "HowToPlayOverlay"
	how_to_play_overlay.z_index = 140
	add_child(how_to_play_overlay)

	studio_splash = StudioSplashOverlay.new()
	studio_splash.name = "StudioSplashOverlay"
	studio_splash.z_index = 150
	add_child(studio_splash)

	# 5. Procedural stereo rising-pitch audio synth, BGM manager & SDK-ready AdBridge.
	ad_bridge = AdBridge.new()
	ad_bridge.name = "AdBridge"
	add_child(ad_bridge)

	sound_synth = SoundSynth.new()
	sound_synth.name = "SoundSynth"
	add_child(sound_synth)

	bgm_manager = BgmManager.new()
	bgm_manager.name = "BgmManager"
	add_child(bgm_manager)


func _layout_responsive() -> void:
	if playfield_root == null:
		return
	var vp_size := size
	if vp_size.x < 10.0 or vp_size.y < 10.0:
		vp_size = LOGICAL_SIZE
	_playfield_base_pos = Vector2(
		roundf((vp_size.x - LOGICAL_SIZE.x) * 0.5),
		roundf((vp_size.y - LOGICAL_SIZE.y) * 0.5)
	)
	playfield_root.position = _playfield_base_pos


func _init_controller_and_signals() -> void:
	controller = GameController.new()
	run_persistence = RunPersistence.new()

	controller.move_resolved.connect(_on_move_resolved)
	controller.tray_refilled.connect(_on_tray_refilled)
	controller.hold_changed.connect(_on_hold_changed)
	controller.game_over_triggered.connect(_on_game_over_triggered)
	controller.state_changed.connect(_on_state_changed)

	tray_view.drag_started.connect(_on_drag_started)
	tray_view.drag_moved.connect(_on_drag_moved)
	tray_view.drag_dropped_on_board.connect(_on_drag_dropped_on_board)
	tray_view.drag_dropped_on_hold.connect(_on_drag_dropped_on_hold)
	tray_view.drag_cancelled.connect(_on_drag_cancelled)
	tray_view.hold_tapped.connect(_on_hold_tapped)

	hud_view.audio_toggled.connect(_on_audio_toggled)
	hud_view.restart_requested.connect(_on_restart_requested)
	hud_view.home_requested.connect(_on_home_requested)
	hud_view.settings_requested.connect(_on_hud_settings_requested)
	hud_view.score_tick_requested.connect(func(pitch: float) -> void: sound_synth.play_score_tick(pitch))
	game_over_overlay.play_again_pressed.connect(_on_restart_requested)
	game_over_overlay.home_pressed.connect(_on_home_requested)
	game_over_overlay.share_pressed.connect(_on_daily_share_pressed)
	game_over_overlay.stages_pressed.connect(_on_open_gem_stage_select)
	game_over_overlay.double_reward_pressed.connect(_on_double_reward_requested)
	revive_overlay.revive_pressed.connect(_on_revive_requested)
	revive_overlay.decline_pressed.connect(_on_revive_declined)
	ad_bridge.ad_state_changed.connect(_on_ad_state_changed)
	title_overlay.play_pressed.connect(_on_title_play_pressed)
	title_overlay.daily_pressed.connect(_on_title_daily_pressed)
	title_overlay.sprint_pressed.connect(_on_title_sprint_pressed)
	title_overlay.gem_hunt_pressed.connect(_on_open_gem_stage_select)
	title_overlay.settings_pressed.connect(_on_title_settings_requested)
	title_overlay.how_to_play_pressed.connect(_on_how_to_play_requested)
	gem_stage_select_overlay.stage_selected.connect(_on_gem_stage_selected)
	gem_stage_select_overlay.resume_pressed.connect(_on_gem_stage_resume_pressed)
	gem_stage_select_overlay.closed.connect(func() -> void: sound_synth.play_pickup())
	settings_overlay.sfx_toggled.connect(_on_sfx_toggled)
	settings_overlay.bgm_toggled.connect(_on_bgm_toggled)
	settings_overlay.vibration_toggled.connect(_on_vibration_toggled)
	settings_overlay.how_to_play_pressed.connect(_on_how_to_play_requested)
	settings_overlay.replay_pressed.connect(_on_restart_requested)
	settings_overlay.home_pressed.connect(_on_home_requested)
	settings_overlay.closed.connect(_on_settings_closed)
	how_to_play_overlay.closed.connect(_on_how_to_play_closed)
	vfx_layer.score_orb_arrived.connect(_on_score_orb_arrived)


# ==============================================================================
# DRAG & INTERACTION HANDLERS
# ==============================================================================

func _on_drag_started(_source_type: String, _slot_idx: int, _piece: PieceCatalog.Piece) -> void:
	sound_synth.play_pickup()


func _on_drag_moved(global_pos: Vector2, source_type: String, slot_idx: int, piece: PieceCatalog.Piece) -> void:
	if piece == null or controller.is_game_over:
		board_view.clear_placement_preview()
		return
	var origin_cell := board_view.global_pos_to_origin_cell(global_pos, piece)
	if origin_cell.x < 0 or origin_cell.y < 0:
		board_view.clear_placement_preview()
		return
	var preview: Dictionary
	if source_type == "hold":
		preview = controller.preview_from_hold(origin_cell)
	else:
		preview = controller.preview_from_tray(slot_idx, origin_cell)

	if bool(preview.get("valid", false)):
		board_view.set_placement_preview(piece, origin_cell, preview)
	else:
		board_view.clear_placement_preview()


func _on_drag_dropped_on_board(source_type: String, slot_idx: int, origin_cell: Vector2i) -> void:
	board_view.clear_placement_preview()
	var res: Dictionary
	if source_type == "hold":
		res = controller.place_from_hold(origin_cell)
	else:
		res = controller.place_from_tray(slot_idx, origin_cell)

	if not bool(res.get("valid", false)):
		sound_synth.play_invalid()


func _on_drag_dropped_on_hold(slot_idx: int) -> void:
	board_view.clear_placement_preview()
	if controller.hold_from_tray(slot_idx):
		sound_synth.play_hold_swap()
	else:
		sound_synth.play_invalid()


func _on_drag_cancelled() -> void:
	board_view.clear_placement_preview()


func _on_hold_tapped() -> void:
	sound_synth.play_pickup()


func _apply_saved_settings() -> void:
	var sm := controller.save_manager
	var sfx_on := sm.sfx_enabled if sm != null else true
	var bgm_on := sm.bgm_enabled if sm != null else true
	_vibration_enabled = sm.vibration_enabled if sm != null else true

	sound_synth.set_muted(not sfx_on)
	if bgm_manager != null:
		bgm_manager.set_muted(false)
		bgm_manager.set_bgm_enabled(bgm_on)
	hud_view.set_muted(not sfx_on and not bgm_on)


func _persist_settings() -> void:
	if controller != null and controller.save_manager != null:
		var sfx_on := not sound_synth.is_muted()
		var bgm_on := bgm_manager.is_bgm_enabled() if bgm_manager != null else true
		controller.save_manager.update_settings(sfx_on, bgm_on, _vibration_enabled)


func _vibrate(duration_ms: int) -> void:
	if _vibration_enabled and duration_ms > 0:
		Input.vibrate_handheld(duration_ms)


func _on_audio_toggled(muted: bool) -> void:
	_on_sfx_toggled(not muted)
	_on_bgm_toggled(not muted)


func _on_hud_settings_requested() -> void:
	sound_synth.play_pickup()
	if tray_view != null:
		tray_view.set_input_enabled(false)
	if board_view != null:
		board_view.clear_placement_preview()
	if settings_overlay != null:
		var replay_lbl := "Replay"
		var replay_ok := true
		if controller.is_daily_mode():
			var left := controller.save_manager.get_daily_attempts_left(controller.daily_date_key)
			replay_ok = left > 0
			replay_lbl = ("Retry (%d)" % left) if replay_ok else "0 Left"
		settings_overlay.open_settings(
			not sound_synth.is_muted(),
			bgm_manager.is_bgm_enabled() if bgm_manager != null else true,
			_vibration_enabled,
			true,
			replay_lbl,
			replay_ok
		)


func _on_title_settings_requested() -> void:
	sound_synth.play_pickup()
	if settings_overlay != null:
		settings_overlay.open_settings(
			not sound_synth.is_muted(),
			bgm_manager.is_bgm_enabled() if bgm_manager != null else true,
			_vibration_enabled,
			false
		)


func _on_settings_closed() -> void:
	sound_synth.play_pickup()
	if playfield_root != null and playfield_root.visible and not controller.is_game_over and tray_view != null:
		tray_view.set_input_enabled(true)


func _on_how_to_play_requested() -> void:
	sound_synth.play_pickup()
	if tray_view != null:
		tray_view.set_input_enabled(false)
	if board_view != null:
		board_view.clear_placement_preview()
	if how_to_play_overlay != null:
		how_to_play_overlay.open_guide()


func _on_how_to_play_closed() -> void:
	sound_synth.play_pickup()
	if playfield_root != null and playfield_root.visible and not controller.is_game_over and tray_view != null:
		tray_view.set_input_enabled(true)


func _on_sfx_toggled(enabled: bool) -> void:
	sound_synth.set_muted(not enabled)
	if enabled:
		sound_synth.play_pickup()
	hud_view.set_muted(sound_synth.is_muted() and (bgm_manager == null or not bgm_manager.is_bgm_enabled()))
	_persist_settings()


func _on_bgm_toggled(enabled: bool) -> void:
	if bgm_manager != null:
		bgm_manager.set_muted(false)
		bgm_manager.set_bgm_enabled(enabled)
	sound_synth.play_pickup()
	hud_view.set_muted(sound_synth.is_muted() and (bgm_manager == null or not bgm_manager.is_bgm_enabled()))
	_persist_settings()


func _on_vibration_toggled(enabled: bool) -> void:
	_vibration_enabled = enabled
	sound_synth.play_pickup()
	if _vibration_enabled:
		_vibrate(25)
	_persist_settings()


func _on_restart_requested() -> void:
	if gem_stage_select_overlay != null:
		gem_stage_select_overlay.close_selector(false)
	if how_to_play_overlay != null:
		how_to_play_overlay.close_guide(false)
	if settings_overlay != null:
		settings_overlay.close_settings(false)
	if studio_splash != null:
		studio_splash.hide_immediate()
	if title_overlay != null:
		title_overlay.hide_immediate()
	if playfield_root != null:
		playfield_root.visible = true
	if controller.is_daily_mode():
		if not start_daily_run(controller.daily_date_key):
			_on_home_requested()
	elif controller.is_sprint_mode():
		start_sprint_run()
	elif controller.is_gem_hunt_mode():
		start_gem_hunt_run(-1, controller.gem_hunt_stage)
	else:
		start_fresh_run()


func _on_home_requested() -> void:
	_persist_active_run_if_needed()
	if gem_stage_select_overlay != null:
		gem_stage_select_overlay.close_selector(false)
	if how_to_play_overlay != null:
		how_to_play_overlay.close_guide(false)
	if settings_overlay != null:
		settings_overlay.close_settings(false)
	sound_synth.play_pickup()
	if tray_view != null:
		tray_view.set_input_enabled(false)
	if board_view != null:
		board_view.clear_placement_preview()
	if vfx_layer != null:
		vfx_layer.set_fever_intensity(0.0)
	if game_over_overlay != null:
		game_over_overlay.hide_overlay()
	if revive_overlay != null:
		revive_overlay.hide_overlay()
	if playfield_root != null:
		playfield_root.visible = false
	_bg_heat_target = 0.0
	_bg_speed_target = 0.58
	_bg_pulse = 0.0
	if bgm_manager != null:
		bgm_manager.set_mode(BgmManager.Mode.TITLE)
	_show_title_screen()


func _on_title_play_pressed() -> void:
	var live_classic := (controller.game_mode == GameController.GameMode.CLASSIC and controller.should_persist_run())
	if live_classic:
		if playfield_root != null:
			playfield_root.visible = true
		if tray_view != null:
			tray_view.set_input_enabled(true)
		_update_atmosphere(controller.score_engine.combo_streak, controller.score_engine.fever_active, false, false)
		sound_synth.play_combo_clear(4, 2, false)
		tray_view.animate_tray_refill()
		return

	if playfield_root != null:
		playfield_root.visible = true
	if _try_resume_saved_mode(GameController.GameMode.CLASSIC):
		sound_synth.play_combo_clear(5, 2, false)
		return

	start_fresh_run(-1, false)
	sound_synth.play_combo_clear(4, 2, false)


func _on_open_gem_stage_select() -> void:
	sound_synth.play_pickup()
	if game_over_overlay != null and game_over_overlay.visible:
		game_over_overlay.hide_overlay()
		if playfield_root != null:
			playfield_root.visible = false
		if vfx_layer != null:
			vfx_layer.set_fever_intensity(0.0)
		_bg_heat_target = 0.0
		_bg_speed_target = 0.58
		_bg_pulse = 0.0
		if bgm_manager != null:
			bgm_manager.set_mode(BgmManager.Mode.TITLE)
		_show_title_screen()
	var info := _build_gem_hunt_title_info()
	var resume_score := 0
	if controller.is_gem_hunt_mode() and controller.should_persist_run():
		resume_score = controller.score_engine.score
	elif run_persistence != null:
		var sum := run_persistence.get_run_summary(GameController.GameMode.GEM_HUNT)
		if bool(sum.get("has_run", false)):
			resume_score = int(sum.get("score", 0))
	if gem_stage_select_overlay != null:
		gem_stage_select_overlay.open_selector(
			int(info.get("best_stage", 1)),
			int(info.get("best_score", 0)),
			bool(info.get("can_resume", false)),
			int(info.get("active_stage", 1)),
			int(info.get("targets_left", 0)),
			resume_score
		)


func _on_gem_stage_selected(stage_num: int) -> void:
	if title_overlay != null:
		title_overlay.hide_immediate()
	if playfield_root != null:
		playfield_root.visible = true
	start_gem_hunt_run(-1, stage_num)
	sound_synth.play_combo_clear(5, 2, false)


func _on_gem_stage_resume_pressed() -> void:
	if title_overlay != null:
		title_overlay.hide_immediate()
	if controller.is_gem_hunt_mode() and controller.should_persist_run():
		if playfield_root != null:
			playfield_root.visible = true
		if tray_view != null:
			tray_view.set_input_enabled(true)
		_update_atmosphere(controller.score_engine.combo_streak, controller.score_engine.fever_active, false, false)
		sound_synth.play_combo_clear(5, 2, false)
		tray_view.animate_tray_refill()
		return

	if playfield_root != null:
		playfield_root.visible = true
	if _try_resume_saved_mode(GameController.GameMode.GEM_HUNT):
		sound_synth.play_combo_clear(5, 2, false)
		return

	start_gem_hunt_run(-1, controller.save_manager.gem_hunt_best_stage)
	sound_synth.play_combo_clear(5, 2, false)


func _on_title_sprint_pressed() -> void:
	if controller.is_sprint_mode() and controller.should_persist_run():
		if playfield_root != null:
			playfield_root.visible = true
		if tray_view != null:
			tray_view.set_input_enabled(true)
		_update_atmosphere(controller.score_engine.combo_streak, controller.score_engine.fever_active, false, false)
		sound_synth.play_combo_clear(5, 2, false)
		tray_view.animate_tray_refill()
		return

	if playfield_root != null:
		playfield_root.visible = true
	if _try_resume_saved_mode(GameController.GameMode.SPRINT):
		sound_synth.play_combo_clear(6, 2, false)
		return

	start_sprint_run()
	sound_synth.play_combo_clear(6, 2, false)


func _on_title_daily_pressed() -> void:
	var today := DailyChallenge.get_today_date_key()
	var sm := controller.save_manager
	sm.sync_daily_date(today)

	# Resume in-progress Daily run (live in memory OR persisted across app close!) without burning another attempt!
	if controller.is_daily_mode() and not controller.is_game_over and controller.daily_date_key == today:
		if title_overlay != null:
			title_overlay.hide_immediate()
		if playfield_root != null:
			playfield_root.visible = true
		if tray_view != null:
			tray_view.set_input_enabled(true)
		_update_atmosphere(controller.score_engine.combo_streak, controller.score_engine.fever_active, false, false)
		sound_synth.play_combo_clear(4, 2, false)
		tray_view.animate_tray_refill()
		return

	if run_persistence != null and run_persistence.has_saved_run(GameController.GameMode.DAILY, today):
		if title_overlay != null:
			title_overlay.hide_immediate()
		if playfield_root != null:
			playfield_root.visible = true
		if _try_resume_saved_mode(GameController.GameMode.DAILY):
			sound_synth.play_combo_clear(5, 2, false)
			return

	if sm.get_daily_attempts_left(today) > 0:
		if title_overlay != null:
			title_overlay.hide_immediate()
		if playfield_root != null:
			playfield_root.visible = true
		if start_daily_run(today):
			sound_synth.play_combo_clear(5, 2, false)
		return

	# All 3 Daily tries completed -> show today's Daily Summary & Copy Result card!
	sound_synth.play_pickup()
	game_over_overlay.show_daily_over(
		sm.daily_best_score,
		sm.daily_best_score,
		sm.daily_best_combo,
		false,
		today,
		DailyChallenge.MAX_DAILY_ATTEMPTS,
		0,
		sm.daily_streak,
		true
	)


func _on_daily_share_pressed() -> void:
	var dkey := controller.daily_date_key if not controller.daily_date_key.is_empty() else DailyChallenge.get_today_date_key()
	var sm := controller.save_manager
	var run_score := controller.score_engine.score if (controller.is_daily_mode() and controller.score_engine.score > 0) else sm.daily_best_score
	var combo := maxi(controller.score_engine.best_combo, sm.daily_best_combo) if controller.is_daily_mode() else sm.daily_best_combo
	var attempt_num := controller.daily_attempt_number if controller.daily_attempt_number > 0 else maxi(1, sm.daily_attempts_used)
	var share_txt := DailyChallenge.build_share_text(
		dkey,
		run_score,
		sm.daily_best_score,
		combo,
		attempt_num,
		sm.daily_streak
	)
	DisplayServer.clipboard_set(share_txt)
	sound_synth.play_combo_clear(6, 2, false)


# ==============================================================================
# CONTROLLER EVENT -> VFX / HUD / AUDIO ORCHESTRATION
# ==============================================================================

func _on_state_changed() -> void:
	board_view.refresh()
	tray_view.sync_from_controller(controller)


func _on_tray_refilled(_tray: Array) -> void:
	tray_view.animate_tray_refill()


func _on_hold_changed(_hold_piece: PieceCatalog.Piece) -> void:
	tray_view.sync_from_controller(controller)
	_persist_active_run_if_needed()


func _on_move_resolved(result: Dictionary) -> void:
	if not bool(result.get("valid", false)):
		return

	var placed_cells: Array[Vector2i] = []
	for c in (result.get("placed_cells", []) as Array):
		if c is Vector2i:
			placed_cells.append(c as Vector2i)

	var cleared_rows: Array = result.get("cleared_rows", []) as Array
	var cleared_cols: Array = result.get("cleared_cols", []) as Array
	var blast_cells: Array = result.get("blast_cells", []) as Array
	var cleared_cells: Array = result.get("cleared_cells", []) as Array
	var cleared_colors: Dictionary = result.get("cleared_cell_colors", {}) as Dictionary
	var hit_multipliers: Array = result.get("hit_multipliers", []) as Array

	var lines_cleared := int(result.get("lines_cleared", 0))
	var combo_streak := int(result.get("combo_streak", 0))
	var fever_active := bool(result.get("fever_active", false))
	var fever_just_ignited := bool(result.get("fever_just_ignited", false))
	var points_earned := int(result.get("points_earned", 0))
	var special_triggered := int(result.get("special_triggered", PieceCatalog.SpecialType.NORMAL))
	var awarded_special := int(result.get("awarded_special", PieceCatalog.SpecialType.NORMAL))
	var awarded_slot := int(result.get("awarded_slot", -1))
	var just_beat_pb := bool(result.get("just_beat_high_score", false))

	# 1. Tactile placement feedback.
	board_view.animate_placed_cells(placed_cells)
	sound_synth.play_place()
	_vibrate(14)

	# 2. Update HUD & heat atmosphere.
	hud_view.apply_move_result(result)
	if controller.is_sprint_mode():
		var m_left := int(result.get("sprint_moves_left", controller.sprint_moves_left))
		var m_limit := int(result.get("sprint_moves_limit", controller.sprint_moves_limit))
		hud_view.set_sprint_badge(true, m_left, m_limit)
		if m_left == 10:
			vfx_layer.spawn_floating_text(Vector2(270.0, 232.0), "FINAL 10 MOVES!", Color("#FFE45C"), 26, -2.0, Color("#5A168F"))
			sound_synth.play_mult_hit(2)
		elif m_left == 5:
			vfx_layer.spawn_floating_text(Vector2(270.0, 232.0), "FINAL 5 MOVES!", Color("#FFF4B8"), 28, 2.5, Color("#B81D18"))
			sound_synth.play_mult_hit(3)
			_vibrate(32)
	elif controller.is_gem_hunt_mode():
		hud_view.set_gem_hunt_badge(
			true,
			controller.gem_hunt_stage,
			controller.gem_hunt_targets_left,
			controller.gem_hunt_targets_total,
			controller.score_engine.stage_mult
		)
		var cracked: Array = result.get("cracked_targets", []) as Array
		for c_pos in cracked:
			if c_pos is Vector2i:
				var pf_pos := _cell_center_in_playfield(c_pos as Vector2i)
				vfx_layer.spawn_cell_shatter(pf_pos, 5, board_view.get_cell_size(), 4)
				vfx_layer.spawn_floating_text(pf_pos + Vector2(0.0, -14.0), "CRACK!", Color("#D8FCFF"), 18, -3.0, Color("#0A4C7A"))
		if not cracked.is_empty():
			sound_synth.play_mult_hit(2)
		if bool(result.get("stage_cleared", false)):
			var cleared_stg := int(result.get("cleared_stage", 1))
			var next_stg := int(result.get("next_stage", cleared_stg + 1))
			var stg_bonus := int(result.get("stage_bonus", 500))
			var next_mult := float(result.get("stage_mult", 1.25))
			board_view.trigger_clear_flash(1.0, Color("#48F4FF"))
			vfx_layer.spawn_floating_text(Vector2(270.0, 380.0), "STAGE %d CLEAR! +%s" % [cleared_stg, HudView.format_comma_int(stg_bonus)], Color("#FFF6A8"), 30, -2.0, Color("#0E5E8A"))
			var m_clean := ("%.2f" % next_mult).rstrip("0").rstrip(".")
			vfx_layer.spawn_floating_text(Vector2(270.0, 444.0), "STAGE %d  •  ×%s MULT" % [next_stg, m_clean], Color("#7CF9FF"), 22, 1.5, Color("#132A6B"))
			sound_synth.play_high_score()
			_vibrate(65)
			if bgm_manager != null:
				bgm_manager.duck(4.5, 0.45, 0.75)
			tray_view.animate_tray_refill()
	board_view.set_heat_level(combo_streak, fever_active)
	tray_view.set_heat_level(combo_streak, fever_active)
	_update_atmosphere(combo_streak, fever_active, lines_cleared > 0 or not blast_cells.is_empty(), fever_just_ignited)

	var cell_size := board_view.get_cell_size()
	var board_inner_local := Rect2(
		board_view.position + board_view.get_board_inner_rect().position,
		board_view.get_board_inner_rect().size
	)
	var board_center_local := board_inner_local.get_center()

	# 3. Special block detonation VFX & SFX.
	var blast_origin := result.get("blast_origin", Vector2i(-1, -1)) as Vector2i
	if special_triggered == PieceCatalog.SpecialType.BOMB and blast_origin.x >= 0:
		var origin_local := _cell_center_in_playfield(blast_origin)
		vfx_layer.spawn_bomb_explosion(origin_local, cell_size)
		board_view.trigger_clear_flash(1.0, Color("#FF7A1F"))
		sound_synth.play_bomb_blast()
		_vibrate(55)
		if bgm_manager != null:
			bgm_manager.duck(3.2, 0.16, 0.45)
	elif special_triggered == PieceCatalog.SpecialType.LIGHTNING and blast_origin.x >= 0:
		var origin_local := _cell_center_in_playfield(blast_origin)
		vfx_layer.spawn_lightning_cross(origin_local, board_inner_local, cell_size)
		board_view.trigger_clear_flash(1.0, Color("#18D5FF"))
		sound_synth.play_lightning_zap()
		_vibrate(55)
		if bgm_manager != null:
			bgm_manager.duck(3.2, 0.16, 0.45)

	# 4. Line clear sweep + jewel shatter + score popups + flying orbs.
	var did_clear := lines_cleared > 0 or not blast_cells.is_empty()
	if did_clear:
		var accent := Color("#FFE055") if fever_active else (Color("#24E8FF") if combo_streak >= 2 else Color("#7CF5FF"))
		if lines_cleared > 0:
			vfx_layer.spawn_line_clear(board_inner_local, cleared_rows, cleared_cols, cell_size, accent)
			board_view.trigger_clear_flash(minf(1.0, 0.55 + float(lines_cleared) * 0.2), accent)

		var orb_origins: Array[Vector2] = []
		var centroid := Vector2.ZERO
		var count := 0
		for cell_v in cleared_cells:
			if cell_v is Vector2i:
				var cell_pos := cell_v as Vector2i
				var center_pf := _cell_center_in_playfield(cell_pos)
				var color_id := int(cleared_colors.get(cell_pos, 1))
				if color_id >= 0:
					vfx_layer.spawn_cell_shatter(center_pf, color_id, cell_size, 5 if cleared_cells.size() <= 16 else 4)
				centroid += center_pf
				count += 1
				if count % maxi(1, int(cleared_cells.size() / 8)) == 0:
					orb_origins.append(center_pf)

		if count > 0:
			centroid /= float(count)
		else:
			centroid = board_center_local
		if orb_origins.is_empty():
			orb_origins.append(centroid)

		# Multiplier tile pops & metallic pings!
		for m_item in hit_multipliers:
			var m_cell := m_item.get("cell", Vector2i(3, 3)) as Vector2i
			var m_val := int(m_item.get("value", 2))
			vfx_layer.spawn_multiplier_pop(_cell_center_in_playfield(m_cell), m_val)
			sound_synth.play_mult_hit(m_val)

		# Rising-pitch combo chime!
		sound_synth.play_combo_clear(maxi(1, combo_streak), maxi(1, lines_cleared), fever_active)
		if special_triggered == PieceCatalog.SpecialType.NORMAL:
			_vibrate(clampi(22 + lines_cleared * 6, 22, 40))

		# Bold Balatro score pop & flying orbs converging on top Hero Score!
		var pop_size := clampi(32 + int(float(points_earned) / 700.0), 32, 46)
		var pop_bg := Color("#E83B28") if fever_active else Color("#1464D8")
		var pop_text := "+%s!" % HudView.format_comma_int(points_earned) if points_earned >= 1200 else "+%s" % HudView.format_comma_int(points_earned)
		vfx_layer.spawn_floating_text(
			centroid + Vector2(0.0, -18.0),
			pop_text,
			Color("#FFF8B8") if fever_active else Color("#FFFFFF"),
			pop_size,
			-3.8 if (combo_streak % 2 == 0) else 3.8,
			pop_bg
		)

		var score_target_pf := Vector2(270.0, 48.0)
		_orb_tick_index = 0
		vfx_layer.spawn_score_orbs(orb_origins, score_target_pf, points_earned, accent)

		# Dramatic multi-line / combo / FEVER banner callout!
		if lines_cleared >= 2 or combo_streak >= 2 or fever_just_ignited:
			vfx_layer.spawn_combo_banner(board_center_local, combo_streak, lines_cleared, fever_just_ignited)

	# 5. Special block reward burst into tray slot!
	if awarded_special != PieceCatalog.SpecialType.NORMAL and awarded_slot >= 0:
		tray_view.animate_special_award(awarded_slot)
		var slot_badge := "BOMB EARNED!" if awarded_special == PieceCatalog.SpecialType.BOMB else "LIGHTNING EARNED!"
		var slot_col := Color("#FF8F33") if awarded_special == PieceCatalog.SpecialType.BOMB else Color("#3CEBFF")
		var slot_bg := Color("#8F1E18") if awarded_special == PieceCatalog.SpecialType.BOMB else Color("#18448F")
		vfx_layer.spawn_floating_text(
			Vector2(270.0, 650.0),
			slot_badge,
			slot_col,
			24,
			0.0,
			slot_bg
		)

	# 6. FEVER ignition & one-shot New Record celebration!
	if fever_just_ignited:
		sound_synth.play_fever_ignite()
		_vibrate(65)
		if bgm_manager != null:
			bgm_manager.duck(4.5, 0.35, 0.70)
	if just_beat_pb:
		sound_synth.play_high_score()
		if bgm_manager != null:
			bgm_manager.duck(4.5, 0.45, 0.75)
		vfx_layer.spawn_floating_text(Vector2(270.0, 126.0), "NEW RECORD!", Color("#FFE45C"), 26, -2.5, Color("#A85B00"))

	# 7. Throttled auto-persist (save every 6 turns, on stage clear, or on game over to prevent per-move disk/IndexedDB lag).
	if controller.is_game_over or bool(result.get("stage_cleared", false)) or (controller.turn_count % 6 == 0):
		_persist_active_run_if_needed()


func _on_score_orb_arrived(points_chunk: int) -> void:
	hud_view.trigger_score_orb_impact(points_chunk)
	_orb_tick_index += 1
	sound_synth.play_score_tick(1.05 + minf(0.85, float(_orb_tick_index) * 0.06))
	if vfx_layer != null:
		vfx_layer.add_trauma(0.045)
	if _orb_tick_index % 3 == 1:
		_vibrate(8)


func _on_game_over_triggered(final_score: int, high_score: int) -> void:
	_pending_game_over_score = final_score
	_pending_game_over_high = high_score
	tray_view.set_input_enabled(false)
	board_view.clear_placement_preview()

	# Offer 1x per-run Second Chance Revive if eligible (board locked & not yet used).
	if controller.can_revive() and revive_overlay != null:
		sound_synth.play_invalid()
		_vibrate(45)
		if bgm_manager != null:
			bgm_manager.duck(3.2, 0.35, 0.70)
		revive_overlay.show_revive_offer(
			final_score,
			controller.score_engine.combo_streak,
			controller.score_engine.fever_active,
			controller.hold_piece != null,
			_get_current_mode_badge_name()
		)
		return

	_finalize_game_over(final_score, high_score)


func _finalize_game_over(final_score: int, high_score: int) -> void:
	if revive_overlay != null:
		revive_overlay.hide_overlay()
	if run_persistence != null:
		run_persistence.clear_run(controller.game_mode)
	tray_view.set_input_enabled(false)
	board_view.clear_placement_preview()

	var coin_res := controller.credit_end_of_run_coins()
	var is_new_best := final_score > controller.score_engine.session_starting_high_score and final_score > 0
	if controller.is_sprint_mode() and controller.sprint_completed:
		if is_new_best:
			sound_synth.play_high_score()
		else:
			sound_synth.play_combo_clear(8, 3, true)
	else:
		sound_synth.play_game_over()
	if bgm_manager != null:
		bgm_manager.set_mode(BgmManager.Mode.GAME_OVER)
		bgm_manager.duck(4.0, 0.55, 0.90)
	if controller.is_daily_mode():
		var dkey := controller.daily_date_key
		var sm := controller.save_manager
		game_over_overlay.show_daily_over(
			final_score,
			maxi(final_score, sm.daily_best_score),
			controller.score_engine.best_combo,
			is_new_best,
			dkey,
			controller.daily_attempt_number,
			sm.get_daily_attempts_left(dkey),
			sm.daily_streak,
			false
		)
	elif controller.is_sprint_mode():
		var sm := controller.save_manager
		var moves_used := controller.sprint_moves_limit - controller.sprint_moves_left
		game_over_overlay.show_sprint_over(
			final_score,
			maxi(final_score, sm.sprint_high_score),
			controller.score_engine.best_combo,
			is_new_best,
			moves_used,
			controller.sprint_moves_limit,
			controller.sprint_completed
		)
	elif controller.is_gem_hunt_mode():
		var sm := controller.save_manager
		game_over_overlay.show_gem_hunt_over(
			final_score,
			maxi(final_score, sm.gem_hunt_high_score),
			controller.score_engine.best_combo,
			is_new_best,
			controller.gem_hunt_stage,
			maxi(controller.gem_hunt_stage, sm.gem_hunt_best_stage)
		)
	else:
		game_over_overlay.show_game_over(final_score, high_score, controller.score_engine.best_combo, is_new_best)

	game_over_overlay.set_reward_info(
		int(coin_res.get("base_coins", 10)),
		int(coin_res.get("wallet_coins", 0)),
		controller.can_double_reward(),
		controller.has_used_double_reward
	)


func _get_current_mode_badge_name() -> String:
	if controller.is_daily_mode():
		return "DAILY CHALLENGE"
	if controller.is_sprint_mode():
		return "20-TURN SPRINT (%d LEFT)" % controller.sprint_moves_left
	if controller.is_gem_hunt_mode():
		return "GEM HUNT • STAGE %d" % controller.gem_hunt_stage
	return "CLASSIC 8×8"


# ==============================================================================
# AD-READY LIFECYCLE HOOKS (PAUSE / RESUME / MUTE / UNMUTE / DECOUPLED REWARDS)
# ==============================================================================

func pause_game() -> void:
	is_game_paused = true
	if tray_view != null:
		tray_view.set_input_enabled(false)
	if board_view != null:
		board_view.clear_placement_preview()
	if playfield_root != null:
		playfield_root.process_mode = Node.PROCESS_MODE_DISABLED
	_persist_active_run_if_needed()
	if controller != null:
		controller.flush_save()


func pauseGame() -> void:
	pause_game()


func resume_game() -> void:
	is_game_paused = false
	if playfield_root != null:
		playfield_root.process_mode = Node.PROCESS_MODE_INHERIT
	var modal_blocking := (
		(title_overlay != null and title_overlay.visible)
		or (game_over_overlay != null and game_over_overlay.visible)
		or (revive_overlay != null and revive_overlay.is_open())
		or (settings_overlay != null and settings_overlay.is_open())
		or (how_to_play_overlay != null and how_to_play_overlay.is_open())
		or (gem_stage_select_overlay != null and gem_stage_select_overlay.is_open())
	)
	if playfield_root != null and playfield_root.visible and not controller.is_game_over and not modal_blocking and tray_view != null:
		tray_view.set_input_enabled(true)


func resumeGame() -> void:
	resume_game()


func mute_sound() -> void:
	_sound_muted_by_ad = true
	if sound_synth != null:
		sound_synth.set_muted(true)
	if bgm_manager != null:
		bgm_manager.set_muted(true)


func muteSound() -> void:
	mute_sound()


func unmute_sound() -> void:
	_sound_muted_by_ad = false
	var sfx_on := controller.save_manager.sfx_enabled if (controller != null and controller.save_manager != null) else true
	if sound_synth != null:
		sound_synth.set_muted(not sfx_on)
	if bgm_manager != null:
		bgm_manager.set_muted(false)


func unmuteSound() -> void:
	unmute_sound()


## Decoupled Revive Reward Grant (safe to call directly in tests OR from Ad SDK adViewed callback).
func grant_revive() -> bool:
	var res := controller.apply_revive()
	if not bool(res.get("revived", false)):
		return false

	if revive_overlay != null:
		revive_overlay.hide_overlay()
	if game_over_overlay != null:
		game_over_overlay.hide_overlay()

	# Shatter VFX on every cleared rescue block while preserving x2/x3, HOLD, Score & FEVER!
	var cleared_cells: Array = res.get("cleared_cells", []) as Array
	var cleared_colors: Dictionary = res.get("cleared_cell_colors", {}) as Dictionary
	var cell_size := board_view.get_cell_size()
	for cv in cleared_cells:
		if cv is Vector2i:
			var cp := cv as Vector2i
			var pf_pos := _cell_center_in_playfield(cp)
			var col_id := int(cleared_colors.get(cp, 2))
			if col_id >= 0:
				vfx_layer.spawn_cell_shatter(pf_pos, col_id, cell_size, 4)

	board_view.refresh()
	board_view.trigger_clear_flash(1.0, Color("#3CF27E"))
	tray_view.sync_from_controller(controller)
	tray_view.animate_tray_refill()
	tray_view.set_input_enabled(true)

	var se := controller.score_engine
	board_view.set_heat_level(se.combo_streak, se.fever_active)
	tray_view.set_heat_level(se.combo_streak, se.fever_active)
	_update_atmosphere(se.combo_streak, se.fever_active, true, false)

	vfx_layer.spawn_floating_text(Vector2(270.0, 390.0), "REVIVED!", Color("#A8FFBC"), 36, -2.0, Color("#0A6B3B"))
	vfx_layer.spawn_floating_text(Vector2(270.0, 448.0), "CENTER CLEARED  •  NEW BLOCKS", Color("#E8FFF0"), 17, 1.0, Color("#0E3A5C"))
	sound_synth.play_high_score()
	_vibrate(60)
	if bgm_manager != null:
		bgm_manager.duck(3.5, 0.25, 0.55)
	_persist_active_run_if_needed()
	return true


func grantRevive() -> bool:
	return grant_revive()


## Decoupled ×2 End-of-Run Reward Grant (safe to call directly OR from Ad SDK adViewed callback).
func grant_double_reward() -> bool:
	var res := controller.apply_double_reward()
	if not bool(res.get("granted", false)):
		return false

	var total_run := int(res.get("total_run_coins", 0))
	var wallet := int(res.get("wallet_coins", 0))
	if game_over_overlay != null:
		game_over_overlay.apply_double_reward_visual(total_run, wallet)

	sound_synth.play_high_score()
	_vibrate(45)
	if bgm_manager != null:
		bgm_manager.duck(3.5, 0.30, 0.60)
	return true


func grantDoubleReward() -> bool:
	return grant_double_reward()


func _on_ad_state_changed(processing: bool) -> void:
	is_processing_ad = processing
	if revive_overlay != null:
		revive_overlay.set_processing_ad(processing)
	if game_over_overlay != null:
		game_over_overlay.set_processing_ad(processing)


func _on_revive_requested() -> void:
	if is_processing_ad or not controller.can_revive():
		return
	if ad_bridge != null:
		ad_bridge.request_rewarded_ad(
			"revive",
			Callable(self, "grant_revive"),
			Callable(self, "pause_game"),
			Callable(self, "resume_game"),
			Callable(self, "mute_sound"),
			Callable(self, "unmute_sound")
		)
	else:
		grant_revive()


func _on_revive_declined() -> void:
	if is_processing_ad:
		return
	sound_synth.play_pickup()
	_finalize_game_over(_pending_game_over_score, _pending_game_over_high)


func _on_double_reward_requested() -> void:
	if is_processing_ad or not controller.can_double_reward():
		return
	if ad_bridge != null:
		ad_bridge.request_rewarded_ad(
			"double_reward",
			Callable(self, "grant_double_reward"),
			Callable(self, "pause_game"),
			Callable(self, "resume_game"),
			Callable(self, "mute_sound"),
			Callable(self, "unmute_sound")
		)
	else:
		grant_double_reward()


func _update_atmosphere(combo_streak: int, fever_active: bool, did_clear: bool, fever_just_ignited: bool) -> void:
	if fever_active:
		_bg_heat_target = 1.0
		_bg_speed_target = 1.95
		vfx_layer.set_fever_intensity(1.0)
		if bgm_manager != null:
			bgm_manager.set_mode(BgmManager.Mode.FEVER)
	elif combo_streak >= 2:
		_bg_heat_target = clampf(0.32 + float(combo_streak - 2) * 0.14, 0.32, 0.68)
		_bg_speed_target = 0.95 + float(combo_streak - 2) * 0.14
		vfx_layer.set_fever_intensity(0.0)
		if bgm_manager != null:
			bgm_manager.set_mode(BgmManager.Mode.PLAYING)
	else:
		_bg_heat_target = 0.0
		_bg_speed_target = 0.58
		vfx_layer.set_fever_intensity(0.0)
		if bgm_manager != null:
			bgm_manager.set_mode(BgmManager.Mode.PLAYING)

	if fever_just_ignited:
		_bg_pulse = 1.0
	elif did_clear:
		_bg_pulse = maxf(_bg_pulse, 0.65)


func _cell_center_in_playfield(cell: Vector2i) -> Vector2:
	var r := board_view.get_cell_rect(cell.y, cell.x)
	return board_view.position + r.get_center()
