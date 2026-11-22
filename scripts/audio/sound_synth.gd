class_name SoundSynth
extends Node

## Pure-GDScript native 44,100 Hz 16-bit PCM STEREO rising-pitch musical synthesizer & SFX engine for Kombo.
## Synthesizes all dry voices & filters natively at 44,100 Hz end-to-end (zero mirror aliasing!),
## paired with an alias-free 4-channel Hadamard FDN stereo plate reverb (180 Hz HPF send, 5.5 kHz
## pre-LPF, 22,050 Hz FDN core, 4-pole Butterworth 6.2 kHz anti-imaging wet filter) and gentle
## 14.5 kHz 2-pole Butterworth mastering silk LPF.

const SAMPLE_RATE: int = 44100
const TAU_OVER_SR: float = TAU / float(SAMPLE_RATE)
const MAX_SAFE_PEAK: float = 0.85
const FADE_IN_SEC: float = 0.0032
const MASTER_LPF_HZ: float = 14500.0

const VOICE_POOL_SIZE: int = 24
const TICK_POOL_SIZE: int = 4
const SCORE_TICK_THROTTLE_MS: int = 24
const ARPEGGIO_STAGGER_SEC: float = 0.035

## 16-step C Major Pentatonic ascending scale (C5 -> C8).
const COMBO_SCALE_HZ: Array[float] = [
	523.25,   # 1:  C5
	587.33,   # 2:  D5
	659.25,   # 3:  E5
	783.99,   # 4:  G5
	880.00,   # 5:  A5
	1046.50,  # 6:  C6
	1174.66,  # 7:  D6
	1318.51,  # 8:  E6
	1567.98,  # 9:  G6
	1760.00,  # 10: A6
	2093.00,  # 11: C7
	2349.32,  # 12: D7
	2637.02,  # 13: E7
	3135.96,  # 14: G7
	3520.00,  # 15: A7
	4186.01,  # 16: C8
]

const SPARKLE_BASE_HZ: float = 1046.50 # C6 crystalline stereo celesta bell

var _initialized: bool = false
var _muted: bool = false
var _last_score_tick_ms: int = -1000
var _last_process_usec: int = 0
var _synth_time_ms: float = 0.0
var _had_nonfinite_sample: bool = false

## Cached procedural 44.1 kHz 16-bit stereo AudioStreamWAV buffers.
var _combo_streams: Array[AudioStreamWAV] = []
var _sfx_streams: Dictionary = {}

## Polyphonic AudioStreamPlayer pools.
var _voice_pool: Array[AudioStreamPlayer] = []
var _voice_cursor: int = 0
var _tick_pool: Array[AudioStreamPlayer] = []
var _tick_cursor: int = 0

## Lightweight real-time scheduler for staggered arpeggiated chord blooms.
var _scheduled_notes: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	initialize()


func initialize() -> void:
	if _initialized:
		return
	var start_usec: int = Time.get_ticks_usec()
	_had_nonfinite_sample = false
	_build_voice_pools()
	_synthesize_all_buffers()
	_last_process_usec = Time.get_ticks_usec()
	_synth_time_ms = float(_last_process_usec - start_usec) / 1000.0
	_initialized = true


func _process(delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var real_dt: float = clampf(float(now_usec - _last_process_usec) / 1_000_000.0, 0.0, 0.05)
	_last_process_usec = now_usec
	var step_dt: float = clampf(maxf(real_dt, delta), 0.0, 0.05)
	if _scheduled_notes.is_empty():
		return
	if _muted:
		_scheduled_notes.clear()
		return

	var write_idx: int = 0
	for i: int in range(_scheduled_notes.size()):
		var entry: Dictionary = _scheduled_notes[i]
		var remaining: float = float(entry["delay"]) - step_dt
		if remaining <= 0.0:
			var stream: AudioStreamWAV = entry["stream"] as AudioStreamWAV
			if stream != null:
				_play_on_pool(
					stream,
					float(entry["volume_db"]),
					float(entry["pitch_scale"])
				)
		else:
			entry["delay"] = remaining
			_scheduled_notes[write_idx] = entry
			write_idx += 1
	_scheduled_notes.resize(write_idx)


# ==============================================================================
# Public Playback API
# ==============================================================================

func set_muted(muted: bool) -> void:
	_muted = muted
	if _muted:
		_scheduled_notes.clear()
		for p: AudioStreamPlayer in _voice_pool:
			if p.is_inside_tree() and p.playing:
				p.stop()
		for p: AudioStreamPlayer in _tick_pool:
			if p.is_inside_tree() and p.playing:
				p.stop()


func is_muted() -> bool:
	return _muted


func play_combo_clear(combo_step: int, lines_cleared: int = 1, fever_active: bool = false) -> void:
	if not _initialized:
		initialize()
	if _muted:
		return

	var step_idx: int = clampi(combo_step - 1, 0, COMBO_SCALE_HZ.size() - 1)
	var lines: int = maxi(lines_cleared, 1)
	var base_freq: float = COMBO_SCALE_HZ[step_idx]

	_play_on_pool(_combo_streams[step_idx], 0.0, 1.0)

	if lines >= 2 or fever_active:
		var sparkle: AudioStreamWAV = _sfx_streams["sparkle_bell"] as AudioStreamWAV
		var target_sparkle_hz: float = minf(base_freq * 2.0, 4186.01)
		var sparkle_pitch: float = clampf(target_sparkle_hz / SPARKLE_BASE_HZ, 0.5, 4.0)
		var sparkle_db: float = -5.5 if fever_active else -7.5
		_schedule_note(sparkle, 0.008, sparkle_db, sparkle_pitch)

	if lines >= 2:
		var chord_offsets: Array[int] = [2, 3]
		if lines >= 3:
			chord_offsets.append(5)
		if lines >= 4:
			chord_offsets.append(7)

		for n: int in range(chord_offsets.size()):
			var raw_idx: int = step_idx + chord_offsets[n]
			var note_idx: int = raw_idx
			if note_idx >= COMBO_SCALE_HZ.size():
				note_idx = clampi(
					COMBO_SCALE_HZ.size() - 5 + ((raw_idx - COMBO_SCALE_HZ.size()) % 5),
					0,
					COMBO_SCALE_HZ.size() - 1
				)
			var delay_sec: float = ARPEGGIO_STAGGER_SEC * float(n + 1)
			var vol_db: float = -2.4 - 0.7 * float(n)
			_schedule_note(_combo_streams[note_idx], delay_sec, vol_db, 1.0)

		if lines >= 3 or fever_active:
			var sparkle2: AudioStreamWAV = _sfx_streams["sparkle_bell"] as AudioStreamWAV
			var high_hz: float = minf(base_freq * 3.0, 4186.01)
			var high_pitch: float = clampf(high_hz / SPARKLE_BASE_HZ, 0.5, 4.0)
			var shimmer_delay: float = ARPEGGIO_STAGGER_SEC * float(chord_offsets.size()) + 0.016
			_schedule_note(sparkle2, shimmer_delay, -6.5, high_pitch)


func play_pickup() -> void:
	_play_named("pickup", -2.0, 1.0)


func play_place() -> void:
	_play_named("place", -0.5, 1.0)


func play_invalid() -> void:
	_play_named("invalid", -2.5, 1.0)


func play_hold_swap() -> void:
	_play_named("hold_swap", -1.5, 1.0)


func play_mult_hit(mult_value: int) -> void:
	if not _initialized:
		initialize()
	if _muted:
		return
	if mult_value <= 2:
		_play_on_pool(_sfx_streams["mult_x2"] as AudioStreamWAV, -0.5, 1.0)
	elif mult_value == 3:
		_play_on_pool(_sfx_streams["mult_x3"] as AudioStreamWAV, 0.0, 1.0)
	else:
		var extra_steps: int = mini(mult_value - 4, 6)
		var pitch: float = pow(1.059463094, float(extra_steps))
		_play_on_pool(_sfx_streams["mult_x4"] as AudioStreamWAV, 0.0, clampf(pitch, 1.0, 1.45))


func play_bomb_blast() -> void:
	_play_named("bomb_blast", 0.0, 1.0)


func play_lightning_zap() -> void:
	_play_named("lightning_zap", -0.5, 1.0)


func play_fever_ignite() -> void:
	_play_named("fever_ignite", 0.0, 1.0)


func play_score_tick(pitch_ratio: float = 1.0) -> void:
	if not _initialized:
		initialize()
	if _muted:
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_score_tick_ms < SCORE_TICK_THROTTLE_MS:
		return
	_last_score_tick_ms = now_ms

	var stream: AudioStreamWAV = _sfx_streams["score_tick"] as AudioStreamWAV
	var pitch: float = clampf(pitch_ratio, 0.75, 2.2)
	_play_on_tick_pool(stream, -2.0, pitch)


func play_game_over() -> void:
	_play_named("game_over", -1.0, 1.0)


func play_high_score() -> void:
	_play_named("high_score", 0.0, 1.0)


# ==============================================================================
# Diagnostic & Introspection Helpers
# ==============================================================================

func get_combo_stream(combo_step: int) -> AudioStreamWAV:
	if not _initialized:
		initialize()
	var idx: int = clampi(combo_step - 1, 0, _combo_streams.size() - 1)
	return _combo_streams[idx]


func get_sfx_stream(key: String) -> AudioStreamWAV:
	if not _initialized:
		initialize()
	return _sfx_streams.get(key, null) as AudioStreamWAV


func get_all_sfx_keys() -> Array[String]:
	if not _initialized:
		initialize()
	var keys: Array[String] = []
	for k: Variant in _sfx_streams.keys():
		keys.append(String(k))
	keys.sort()
	return keys


func get_combo_step_count() -> int:
	return COMBO_SCALE_HZ.size()


func get_combo_target_hz(combo_step: int) -> float:
	var idx: int = clampi(combo_step - 1, 0, COMBO_SCALE_HZ.size() - 1)
	return COMBO_SCALE_HZ[idx]


func get_synth_time_ms() -> float:
	return _synth_time_ms


func had_nonfinite_sample() -> bool:
	return _had_nonfinite_sample


# ==============================================================================
# Voice Pool Management
# ==============================================================================

func _build_voice_pools() -> void:
	_voice_pool.clear()
	_tick_pool.clear()
	for i: int in range(VOICE_POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Voice_%02d" % i
		player.bus = &"Master"
		add_child(player)
		_voice_pool.append(player)
	for i: int in range(TICK_POOL_SIZE):
		var tick_player: AudioStreamPlayer = AudioStreamPlayer.new()
		tick_player.name = "TickVoice_%02d" % i
		tick_player.bus = &"Master"
		add_child(tick_player)
		_tick_pool.append(tick_player)


func _play_named(key: String, volume_db: float, pitch_scale: float) -> void:
	if not _initialized:
		initialize()
	if _muted:
		return
	var stream: AudioStreamWAV = _sfx_streams.get(key, null) as AudioStreamWAV
	if stream != null:
		_play_on_pool(stream, volume_db, pitch_scale)


func _schedule_note(stream: AudioStreamWAV, delay_sec: float, volume_db: float, pitch_scale: float) -> void:
	if delay_sec <= 0.0:
		_play_on_pool(stream, volume_db, pitch_scale)
		return
	_scheduled_notes.append({
		"stream": stream,
		"delay": delay_sec,
		"volume_db": volume_db,
		"pitch_scale": pitch_scale,
	})


func _play_on_pool(stream: AudioStreamWAV, volume_db: float, pitch_scale: float) -> void:
	if _voice_pool.is_empty():
		return
	var chosen: AudioStreamPlayer = null
	for offset: int in range(_voice_pool.size()):
		var idx: int = (_voice_cursor + offset) % _voice_pool.size()
		var candidate: AudioStreamPlayer = _voice_pool[idx]
		if not candidate.playing:
			chosen = candidate
			_voice_cursor = (idx + 1) % _voice_pool.size()
			break
	if chosen == null:
		chosen = _voice_pool[_voice_cursor]
		_voice_cursor = (_voice_cursor + 1) % _voice_pool.size()

	chosen.stream = stream
	chosen.volume_db = volume_db
	chosen.pitch_scale = pitch_scale
	if chosen.is_inside_tree():
		chosen.play()


func _play_on_tick_pool(stream: AudioStreamWAV, volume_db: float, pitch_scale: float) -> void:
	if _tick_pool.is_empty():
		return
	var chosen: AudioStreamPlayer = _tick_pool[_tick_cursor]
	_tick_cursor = (_tick_cursor + 1) % _tick_pool.size()
	chosen.stream = stream
	chosen.volume_db = volume_db
	chosen.pitch_scale = pitch_scale
	if chosen.is_inside_tree():
		chosen.play()


# ==============================================================================
# Buffer Synthesis Catalog
# ==============================================================================

func _synthesize_all_buffers() -> void:
	_combo_streams.clear()
	_sfx_streams.clear()

	for step_idx: int in range(COMBO_SCALE_HZ.size()):
		_combo_streams.append(_synth_combo_note(COMBO_SCALE_HZ[step_idx], step_idx))

	_sfx_streams["sparkle_bell"] = _synth_sparkle_bell(SPARKLE_BASE_HZ)
	_sfx_streams["pickup"] = _synth_pickup()
	_sfx_streams["place"] = _synth_place()
	_sfx_streams["invalid"] = _synth_invalid()
	_sfx_streams["hold_swap"] = _synth_hold_swap()
	_sfx_streams["mult_x2"] = _synth_mult_hit(2)
	_sfx_streams["mult_x3"] = _synth_mult_hit(3)
	_sfx_streams["mult_x4"] = _synth_mult_hit(4)
	_sfx_streams["bomb_blast"] = _synth_bomb_blast()
	_sfx_streams["lightning_zap"] = _synth_lightning_zap()
	_sfx_streams["fever_ignite"] = _synth_fever_ignite()
	_sfx_streams["score_tick"] = _synth_score_tick()
	_sfx_streams["game_over"] = _synth_game_over()
	_sfx_streams["high_score"] = _synth_high_score()


# ==============================================================================
# 1. Combo 1 -> 16: Native 44.1 kHz, Glossy Tails (0.66-0.80s), x5+ Stereo Bloom
# ==============================================================================

func _synth_combo_note(freq_hz: float, step_idx: int) -> AudioStreamWAV:
	var step_num: int = step_idx + 1
	var step_t: float = float(step_idx) / float(maxi(COMBO_SCALE_HZ.size() - 1, 1))
	var duration: float = lerpf(0.66, 0.80, clampf(float(step_idx) / 7.0, 0.0, 1.0))

	var total: int = _even_samples(duration)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	# Dry excitation runs 0.42s then hands off smoothly into the alias-free Hadamard stereo plate tail.
	var active_n: int = mini(_even_samples(0.42), total)
	var tail_start: int = maxi(active_n - int(round(0.08 * float(SAMPLE_RATE))), 1)
	var tail_span: float = float(maxi(active_n - tail_start, 1))

	var atk_n: int = int(round(0.0032 * float(SAMPLE_RATE)))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))

	var mul_f1: float = exp(-1.0 / (lerpf(0.074, 0.080, step_t) * float(SAMPLE_RATE)))
	var mul_f2: float = exp(-1.0 / (lerpf(0.044, 0.040, step_t) * float(SAMPLE_RATE)))
	var mul_f3: float = exp(-1.0 / (lerpf(0.028, 0.024, step_t) * float(SAMPLE_RATE)))
	var mul_sub: float = exp(-1.0 / (0.026 * float(SAMPLE_RATE)))
	var mul_bounce: float = exp(-1.0 / (0.014 * float(SAMPLE_RATE)))
	var mul_mallet: float = exp(-1.0 / (0.0036 * float(SAMPLE_RATE)))
	var mul_snap: float = exp(-1.0 / (0.0026 * float(SAMPLE_RATE)))

	# Natural glossy harmonic taper up to 11.5 kHz (smooth air brilliance, zero abrupt 9.5 kHz hole!).
	var h2_gain: float = 0.25 * _smooth_hf_taper(freq_hz * 2.0, 8200.0, 11800.0)
	var h3_gain: float = 0.14 * _smooth_hf_taper(freq_hz * 3.0, 7800.0, 11500.0)
	var h4_gain: float = 0.06 * _smooth_hf_taper(freq_hz * 4.0, 7200.0, 11000.0)

	var sub_gain: float = 0.0
	if step_num >= 4:
		sub_gain = lerpf(0.18, 0.21, clampf(float(step_num - 4) / 6.0, 0.0, 1.0))

	var base_inc: float = freq_hz * TAU_OVER_SR
	var dc_base: float = cos(base_inc); var ds_base: float = sin(base_inc)
	var chorus_lfo_inc: float = (freq_hz * lerpf(0.0024, 0.0036, step_t)) * TAU_OVER_SR

	var dc_sub: float = cos((freq_hz * 0.5) * TAU_OVER_SR); var ds_sub: float = sin((freq_hz * 0.5) * TAU_OVER_SR)
	var c_sub: float = 1.0; var s_sub: float = 0.0

	var knock_hz: float = clampf(freq_hz * 2.1, 1200.0, 3400.0)
	var dc_kn: float = cos(knock_hz * TAU_OVER_SR); var ds_kn: float = sin(knock_hz * TAU_OVER_SR)
	var c_kn: float = 1.0; var s_kn: float = 0.0

	var dc_lfo: float = cos(chorus_lfo_inc); var ds_lfo: float = sin(chorus_lfo_inc)
	var c_lfo: float = 1.0; var s_lfo: float = 0.0

	# Native 44.1 kHz biquad bandpass for warm wooden-glass tactile mallet tap (3.2 - 5.2 kHz).
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9001 + step_idx * 37
	var snap_hz: float = lerpf(3200.0, 5000.0, step_t)
	var sw0: float = TAU * snap_hz / float(SAMPLE_RATE)
	var s_alpha: float = sin(sw0) / 3.4
	var s_inv: float = 1.0 / (1.0 + s_alpha)
	var sb0: float = s_alpha * s_inv
	var sa1: float = (-2.0 * cos(sw0)) * s_inv
	var sa2: float = (1.0 - s_alpha) * s_inv
	var sz1: float = 0.0; var sz2: float = 0.0

	var phase: float = 0.0
	var c1: float = 1.0; var s1: float = 0.0
	var head_n: int = mini(int(round(0.060 * float(SAMPLE_RATE))), tail_start)
	var e1: float = 1.0; var e2: float = 1.0; var e3: float = 1.0
	var e_sub: float = 1.0; var bounce: float = 0.015
	var e_mallet: float = 1.0; var e_snap: float = 1.0

	# Phase A (0..60ms): Attack ramp + mallet knock + tactile snap + pitch-bounce + warm sub anchor.
	for i: int in range(head_n):
		var gate: float = 1.0
		if i < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(i) * inv_atk))

		s1 = sin(phase); c1 = cos(phase)
		phase += base_inc * (1.0 + bounce)
		bounce *= mul_bounce

		var s2: float = 2.0 * s1 * c1
		var s3: float = s1 * (3.0 - 4.0 * s1 * s1)
		var s4: float = s2 * (2.0 * c1 * c1 - 1.0)
		var core: float = 0.62 * s1 * e1 + h2_gain * s2 * e2 + (h3_gain * s3 + h4_gain * s4) * e3

		var mallet_val: float = 0.0
		if e_mallet > 0.002:
			mallet_val = 0.14 * s_kn * e_mallet
			var nkn: float = c_kn * dc_kn - s_kn * ds_kn; s_kn = s_kn * dc_kn + c_kn * ds_kn; c_kn = nkn
			e_mallet *= mul_mallet

		var snap_val: float = 0.0
		if e_snap > 0.002:
			var w: float = rng.randf_range(-1.0, 1.0)
			var y: float = sb0 * w + sz1
			sz1 = -sa1 * y + sz2
			sz2 = -sb0 * w - sa2 * y
			snap_val = 0.24 * y * e_snap
			e_snap *= mul_snap

		var sub_val: float = 0.0
		if sub_gain > 0.0 and e_sub > 0.002:
			sub_val = sub_gain * s_sub * e_sub
			var nsub: float = c_sub * dc_sub - s_sub * ds_sub; s_sub = s_sub * dc_sub + c_sub * ds_sub; c_sub = nsub
			e_sub *= mul_sub

		var ch_e: float = 0.22 * e1
		left[i] = (core + ch_e * (s1 * c_lfo - c1 * s_lfo) + sub_val + mallet_val + snap_val * 0.92) * gate
		right[i] = (core + ch_e * (s1 * c_lfo + c1 * s_lfo) + sub_val + mallet_val * 0.95 + snap_val * 1.08) * gate

		var nlfo: float = c_lfo * dc_lfo - s_lfo * ds_lfo; s_lfo = s_lfo * dc_lfo + c_lfo * ds_lfo; c_lfo = nlfo
		e1 *= mul_f1; e2 *= mul_f2; e3 *= mul_f3

	# Phase B (60ms..tail_start): Lean branch-free trig-free stereo sustain.
	for i: int in range(head_n, tail_start):
		var nb: float = c1 * dc_base - s1 * ds_base; s1 = s1 * dc_base + c1 * ds_base; c1 = nb
		var core: float = 0.62 * s1 * e1 + h2_gain * (2.0 * s1 * c1) * e2
		if h3_gain > 0.0:
			core += h3_gain * (s1 * (3.0 - 4.0 * s1 * s1)) * e3
			e3 *= mul_f3
		var ch_e: float = 0.22 * e1
		left[i] = core + ch_e * (s1 * c_lfo - c1 * s_lfo)
		right[i] = core + ch_e * (s1 * c_lfo + c1 * s_lfo)
		var nlfo: float = c_lfo * dc_lfo - s_lfo * ds_lfo; s_lfo = s_lfo * dc_lfo + c_lfo * ds_lfo; c_lfo = nlfo
		e1 *= mul_f1; e2 *= mul_f2

	# Phase C (tail_start..active_n): Smooth cosine handoff into stereo plate reverb tail.
	for i: int in range(tail_start, active_n):
		var nb: float = c1 * dc_base - s1 * ds_base; s1 = s1 * dc_base + c1 * ds_base; c1 = nb
		var gate: float = 0.5 * (1.0 + cos(PI * float(i - tail_start) / tail_span))
		var ge: float = e1 * gate
		var core: float = 0.62 * s1 * ge
		var ch_e: float = 0.22 * ge
		left[i] = core + ch_e * (s1 * c_lfo - c1 * s_lfo)
		right[i] = core + ch_e * (s1 * c_lfo + c1 * s_lfo)
		var nlfo: float = c_lfo * dc_lfo - s_lfo * ds_lfo; s_lfo = s_lfo * dc_lfo + c_lfo * ds_lfo; c_lfo = nlfo
		e1 *= mul_f1

	# Combo 4: subtle stereo glow; Combo 5+ (e.g. combo_8): euphoric micro-staggered (+18ms/+34ms) stereo bloom!
	if step_num == 4:
		_add_stereo_bell(left, right, 0.014, freq_hz * 1.5, 0.068, 0.11, 0.14, 0.0, -0.58, 0.006)
		_add_stereo_bell(left, right, 0.026, freq_hz * 2.0, 0.068, 0.13, 0.12, 0.0, 0.58, 0.006)
	elif step_num >= 5:
		var fifth_hz: float = freq_hz * 1.5
		if fifth_hz > 9600.0:
			fifth_hz *= 0.5
		var oct_hz: float = freq_hz * 2.0
		if oct_hz > 10600.0:
			oct_hz *= 0.5
		var fifth_gain: float = lerpf(0.11, 0.13, clampf(float(step_num - 5) / 4.0, 0.0, 1.0))
		var oct_gain: float = lerpf(0.15, 0.20, clampf(float(step_num - 5) / 4.0, 0.0, 1.0))
		_add_stereo_bell(left, right, 0.018, fifth_hz, 0.076, fifth_gain, 0.16, 0.0, -0.72, 0.006)
		_add_stereo_bell(left, right, 0.034, oct_hz, 0.080, oct_gain, 0.12, 0.0, 0.76, 0.006)

	var rev_wet: float = lerpf(0.32, 0.44, clampf(float(step_idx) / 7.0, 0.0, 1.0))
	var rev_t60: float = lerpf(0.36, 0.42, clampf(float(step_idx) / 7.0, 0.0, 1.0))
	_apply_stereo_plate_reverb(left, right, rev_wet, rev_t60, 0.26)

	var target_peak: float = lerpf(0.80, 0.74, step_t)
	return _finalize_stereo_buffer(left, right, target_peak, FADE_IN_SEC, 0.022, MASTER_LPF_HZ)


func _synth_sparkle_bell(freq_hz: float) -> AudioStreamWAV:
	var total: int = _even_samples(0.56)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	_add_stereo_bell(left, right, 0.0, freq_hz, 0.068, 0.80, 0.22, 0.08, -0.28, 0.005)
	_add_stereo_bell(left, right, 0.016, freq_hz * 2.0, 0.058, 0.38, 0.12, 0.0, 0.34, 0.006)
	_apply_stereo_plate_reverb(left, right, 0.32, 0.28, 0.30)
	return _finalize_stereo_buffer(left, right, 0.74, FADE_IN_SEC, 0.022, 0.0)


# ==============================================================================
# 2. Tactile UI & Placement SFX (Native 44.1 kHz Stereo)
# ==============================================================================

func _synth_pickup() -> AudioStreamWAV:
	var total: int = _even_samples(0.110)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	var active_n: int = _even_samples(0.068)
	var f_start: float = 320.0
	var f_ratio: float = 520.0 / f_start
	var inv_active: float = 1.0 / float(maxi(active_n - 1, 1))
	var atk_n: int = int(round(0.003 * float(SAMPLE_RATE)))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var tail_start: int = active_n - int(round(0.020 * float(SAMPLE_RATE)))
	var tail_span: float = float(maxi(active_n - tail_start, 1))

	var mul_body: float = exp(-1.0 / (0.013 * float(SAMPLE_RATE)))
	var mul_h2: float = exp(-1.0 / (0.009 * float(SAMPLE_RATE)))
	var mul_pop: float = exp(-1.0 / (0.003 * float(SAMPLE_RATE)))

	var p_l: float = 0.0; var p_r: float = 0.0
	var dc_pop: float = cos(1520.0 * TAU_OVER_SR); var ds_pop: float = sin(1520.0 * TAU_OVER_SR)
	var c_pop: float = 1.0; var s_pop: float = 0.0
	var e_body: float = 1.0; var e_h2: float = 1.0; var e_pop: float = 1.0

	for i: int in range(active_n):
		var u: float = float(i) * inv_active
		var gate: float = 1.0
		if i < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(i) * inv_atk))
		elif i >= tail_start:
			gate = 0.5 * (1.0 + cos(PI * float(i - tail_start) / tail_span))

		var freq: float = f_start * pow(f_ratio, u)
		var sl: float = sin(p_l); var cl: float = cos(p_l)
		var sr: float = sin(p_r); var cr: float = cos(p_r)
		var pop: float = 0.14 * s_pop * e_pop

		left[i] = (0.72 * sl * e_body + 0.24 * (2.0 * sl * cl) * e_h2 + pop * 1.05) * gate
		right[i] = (0.72 * sr * e_body + 0.24 * (2.0 * sr * cr) * e_h2 + pop * 0.95) * gate

		p_l += (freq * 0.997) * TAU_OVER_SR
		p_r += (freq * 1.003) * TAU_OVER_SR
		var nt: float = c_pop * dc_pop - s_pop * ds_pop; s_pop = s_pop * dc_pop + c_pop * ds_pop; c_pop = nt
		e_body *= mul_body; e_h2 *= mul_h2; e_pop *= mul_pop

	_apply_stereo_plate_reverb(left, right, 0.08, 0.065, 0.55)
	return _finalize_stereo_buffer(left, right, 0.62, FADE_IN_SEC, 0.016, 0.0)


func _synth_place() -> AudioStreamWAV:
	var total: int = _even_samples(0.180)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	var active_n: int = _even_samples(0.092)
	var atk_n: int = int(round(0.003 * float(SAMPLE_RATE)))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var tail_start: int = active_n - int(round(0.024 * float(SAMPLE_RATE)))
	var tail_span: float = float(maxi(active_n - tail_start, 1))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 202601
	var sw0: float = TAU * 2450.0 / float(SAMPLE_RATE)
	var s_alpha: float = sin(sw0) / 3.4
	var s_inv: float = 1.0 / (1.0 + s_alpha)
	var sb0: float = s_alpha * s_inv
	var sa1: float = (-2.0 * cos(sw0)) * s_inv
	var sa2: float = (1.0 - s_alpha) * s_inv
	var sz1: float = 0.0; var sz2: float = 0.0

	var mul_pitch: float = exp(-1.0 / (0.014 * float(SAMPLE_RATE)))
	var mul_body: float = exp(-1.0 / (0.017 * float(SAMPLE_RATE)))
	var mul_wood: float = exp(-1.0 / (0.010 * float(SAMPLE_RATE)))
	var mul_click: float = exp(-1.0 / (0.0025 * float(SAMPLE_RATE)))

	var p_body: float = 0.0
	var dc_wl: float = cos(362.0 * TAU_OVER_SR); var ds_wl: float = sin(362.0 * TAU_OVER_SR)
	var dc_wr: float = cos(370.0 * TAU_OVER_SR); var ds_wr: float = sin(370.0 * TAU_OVER_SR)
	var dc_ck: float = cos(2500.0 * TAU_OVER_SR); var ds_ck: float = sin(2500.0 * TAU_OVER_SR)
	var c_wl: float = 1.0; var s_wl: float = 0.0
	var c_wr: float = 1.0; var s_wr: float = 0.0
	var c_ck: float = 1.0; var s_ck: float = 0.0

	var p_env: float = 1.0; var e_body: float = 1.0; var e_wood: float = 1.0; var e_click: float = 1.0

	for i: int in range(active_n):
		var gate: float = 1.0
		if i < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(i) * inv_atk))
		elif i >= tail_start:
			gate = 0.5 * (1.0 + cos(PI * float(i - tail_start) / tail_span))

		var freq: float = 82.0 + 74.0 * p_env
		var s1: float = sin(p_body); var c1: float = cos(p_body)
		var body: float = (0.76 * s1 + 0.22 * (2.0 * s1 * c1)) * e_body

		var w: float = rng.randf_range(-1.0, 1.0)
		var y: float = sb0 * w + sz1
		sz1 = -sa1 * y + sz2
		sz2 = -sb0 * w - sa2 * y
		var snap: float = (0.20 * s_ck + 0.18 * y) * e_click

		left[i] = (body + 0.26 * s_wl * e_wood + snap * 1.06) * gate
		right[i] = (body + 0.26 * s_wr * e_wood + snap * 0.94) * gate

		p_body += freq * TAU_OVER_SR
		var nt: float = c_wl * dc_wl - s_wl * ds_wl; s_wl = s_wl * dc_wl + c_wl * ds_wl; c_wl = nt
		nt = c_wr * dc_wr - s_wr * ds_wr; s_wr = s_wr * dc_wr + c_wr * ds_wr; c_wr = nt
		nt = c_ck * dc_ck - s_ck * ds_ck; s_ck = s_ck * dc_ck + c_ck * ds_ck; c_ck = nt
		p_env *= mul_pitch; e_body *= mul_body; e_wood *= mul_wood; e_click *= mul_click

	_apply_stereo_plate_reverb(left, right, 0.09, 0.075, 0.58)
	return _finalize_stereo_buffer(left, right, 0.78, FADE_IN_SEC, 0.020, MASTER_LPF_HZ)


func _synth_invalid() -> AudioStreamWAV:
	var total: int = _even_samples(0.30)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	_add_stereo_sub_thump(left, right, 0.000, 162.0, 116.0, 0.019, 0.88, -0.14)
	_add_stereo_sub_thump(left, right, 0.074, 134.0, 92.0, 0.022, 0.78, 0.14)
	_apply_stereo_plate_reverb(left, right, 0.08, 0.085, 0.65)
	return _finalize_stereo_buffer(left, right, 0.56, FADE_IN_SEC, 0.022, 0.0)


func _synth_hold_swap() -> AudioStreamWAV:
	var total: int = _even_samples(0.30)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	_add_resonant_whoosh(left, right, 0.000, 0.115, 520.0, 2400.0, 0.28, -0.55, 0.55, 202604)
	_add_stereo_bell(left, right, 0.022, 880.00, 0.024, 0.44, 0.20, 0.06, -0.32, 0.004)
	_add_stereo_bell(left, right, 0.058, 1318.51, 0.030, 0.54, 0.18, 0.06, 0.34, 0.004)
	_apply_stereo_plate_reverb(left, right, 0.18, 0.13, 0.44)
	return _finalize_stereo_buffer(left, right, 0.68, FADE_IN_SEC, 0.022, MASTER_LPF_HZ)


func _synth_mult_hit(tier: int) -> AudioStreamWAV:
	var duration: float = 0.48 if tier <= 2 else (0.54 if tier == 3 else 0.60)
	var total: int = _even_samples(duration)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	var base_hz: float = 1318.51 if tier <= 2 else (1760.00 if tier == 3 else 2093.00)

	_add_stereo_sub_thump(left, right, 0.0, 235.0, 102.0, 0.016, 0.36, 0.0)
	_add_stereo_coin_ping(left, right, 0.0, base_hz, 0.054, 0.84, 0.0)

	if tier == 3:
		_add_stereo_coin_ping(left, right, 0.028, 2637.02, 0.052, 0.56, 0.38)
	elif tier >= 4:
		_add_stereo_coin_ping(left, right, 0.024, 2637.02, 0.054, 0.54, -0.42)
		_add_stereo_coin_ping(left, right, 0.050, 3135.96, 0.058, 0.50, 0.44)

	_apply_stereo_plate_reverb(left, right, 0.26, 0.22, 0.38)
	var peak: float = 0.80 if tier <= 2 else (0.83 if tier == 3 else 0.84)
	return _finalize_stereo_buffer(left, right, peak, FADE_IN_SEC, 0.022, 0.0)


func _synth_score_tick() -> AudioStreamWAV:
	var total: int = _even_samples(0.052)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	var active_n: int = _even_samples(0.038)
	var atk_n: int = int(round(0.003 * float(SAMPLE_RATE)))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var mul1: float = exp(-1.0 / (0.0044 * float(SAMPLE_RATE)))
	var mul2: float = exp(-1.0 / (0.0024 * float(SAMPLE_RATE)))

	var dc1l: float = cos(1564.0 * TAU_OVER_SR); var ds1l: float = sin(1564.0 * TAU_OVER_SR)
	var dc1r: float = cos(1572.0 * TAU_OVER_SR); var ds1r: float = sin(1572.0 * TAU_OVER_SR)
	var dc2: float = cos(3136.0 * TAU_OVER_SR); var ds2: float = sin(3136.0 * TAU_OVER_SR)
	var c1l: float = 1.0; var s1l: float = 0.0
	var c1r: float = 1.0; var s1r: float = 0.0
	var c2: float = 1.0; var s2: float = 0.0
	var e1: float = 1.0; var e2: float = 1.0

	for i: int in range(active_n):
		var gate: float = 1.0
		if i < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(i) * inv_atk))
		var glint: float = 0.24 * s2 * e2
		left[i] = (0.76 * s1l * e1 + glint) * gate
		right[i] = (0.76 * s1r * e1 + glint) * gate
		var nt: float = c1l * dc1l - s1l * ds1l; s1l = s1l * dc1l + c1l * ds1l; c1l = nt
		nt = c1r * dc1r - s1r * ds1r; s1r = s1r * dc1r + c1r * ds1r; c1r = nt
		nt = c2 * dc2 - s2 * ds2; s2 = s2 * dc2 + c2 * ds2; c2 = nt
		e1 *= mul1; e2 *= mul2

	return _finalize_stereo_buffer(left, right, 0.48, FADE_IN_SEC, 0.010, 0.0)


# ==============================================================================
# 3. Hero Powerup & Event SFX (Native 44.1 kHz, Alias-Free, Jet-Black EOF Tail)
# ==============================================================================

func _synth_bomb_blast() -> AudioStreamWAV:
	# Native 44.1 kHz 1.02s stereo blast:
	#   - Massive chest-hitting sub-bass drop (115 -> 34 Hz sustaining ~300ms, smoothly decaying
	#     below -80 dBFS by 0.85s so < 100 Hz right edge is dead black silent!)
	#   - Warm 4-pole low-passed blast rumble body (750 -> 95 Hz over 360ms)
	#   - Dense overlapping cluster of 28 chaotic/descending glossy crystal/ceramic shards
	#     tightly packed in 0.025s..0.24s (2.0-9.2 kHz natural brilliance, >= 3.2ms attacks)
	#   - Alias-free Hadamard FDN stereo plate reverb (180 Hz HPF send keeps sub-bass ultra-tight!)
	var duration: float = 1.02
	var total: int = _even_samples(duration)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 202607

	var atk_n: int = int(round(0.0032 * float(SAMPLE_RATE)))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))

	# Sub-bass & warm rumble finish smoothly by 0.78s (reaching < -85 dBFS well before 0.85s!).
	var boom_n: int = _even_samples(0.78)
	var boom_tail_start: int = int(round(0.54 * float(SAMPLE_RATE)))
	var boom_tail_span: float = float(maxi(boom_n - boom_tail_start, 1))

	var mul_sub_pitch: float = exp(-1.0 / (0.062 * float(SAMPLE_RATE)))
	var mul_sub_env: float = exp(-1.0 / (0.095 * float(SAMPLE_RATE)))
	var mul_punch: float = exp(-1.0 / (0.016 * float(SAMPLE_RATE)))
	var mul_noise_env: float = exp(-1.0 / (0.098 * float(SAMPLE_RATE)))
	var mul_cutoff: float = exp(-1.0 / (0.115 * float(SAMPLE_RATE)))

	var p_sub: float = 0.0
	var dc_p: float = cos(132.0 * TAU_OVER_SR); var ds_p: float = sin(132.0 * TAU_OVER_SR)
	var c_p: float = 1.0; var s_p: float = 0.0

	var sub_pitch: float = 1.0; var sub_env: float = 1.0; var punch_env: float = 1.0
	var noise_env: float = 1.0; var cutoff_env: float = 1.0

	var lp_l1: float = 0.0; var lp_l2: float = 0.0; var lp_l3: float = 0.0; var lp_l4: float = 0.0
	var lp_r1: float = 0.0; var lp_r2: float = 0.0; var lp_r3: float = 0.0; var lp_r4: float = 0.0

	for i: int in range(boom_n):
		var gate: float = 1.0
		if i < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(i) * inv_atk))
		elif i >= boom_tail_start:
			var u_rel: float = float(i - boom_tail_start) / boom_tail_span
			var c_rel: float = 0.5 * (1.0 + cos(PI * u_rel))
			gate = c_rel * c_rel # Smooth squared-cosine taper guarantees < -85 dBFS by 0.78s!

		var sub_hz: float = 34.0 + 81.0 * sub_pitch
		var s_sub: float = sin(p_sub); var c_sub: float = cos(p_sub)
		var s_sub2: float = 2.0 * s_sub * c_sub
		var s_sub3: float = s_sub * (3.0 - 4.0 * s_sub * s_sub)
		var sub_raw: float = (s_sub + 0.18 * s_sub2 * sub_pitch - 0.10 * s_sub3) * 1.42
		var sub_val: float = _fast_tanh(sub_raw) * sub_env * 0.94
		var chest_snap: float = s_p * punch_env * 0.30

		# Mid-body ceramic/wood crackle punch (420 -> 980 Hz glue over first 85ms connecting sub to gem shatter).
		var mid_glue: float = sin(p_sub * 6.2 + s_p * 1.4) * punch_env * punch_env * 0.24

		# Warm 4-pole low-passed blast rumble (750 -> 95 Hz over 360ms).
		var cutoff_hz: float = 95.0 + 655.0 * cutoff_env
		var a: float = clampf(TAU * cutoff_hz / (TAU * cutoff_hz + float(SAMPLE_RATE)), 0.008, 0.32)

		var wl: float = rng.randf_range(-1.0, 1.0)
		var wr: float = 0.55 * wl + 0.45 * rng.randf_range(-1.0, 1.0)
		lp_l1 += a * (wl - lp_l1); lp_l2 += a * (lp_l1 - lp_l2); lp_l3 += a * (lp_l2 - lp_l3); lp_l4 += a * (lp_l3 - lp_l4)
		lp_r1 += a * (wr - lp_r1); lp_r2 += a * (lp_r1 - lp_r2); lp_r3 += a * (lp_r2 - lp_r3); lp_r4 += a * (lp_r3 - lp_r4)

		left[i] += (sub_val + chest_snap + mid_glue + lp_l4 * noise_env * 1.85) * gate
		right[i] += (sub_val + chest_snap + mid_glue + lp_r4 * noise_env * 1.85) * gate

		p_sub += sub_hz * TAU_OVER_SR
		var nt: float = c_p * dc_p - s_p * ds_p; s_p = s_p * dc_p + c_p * ds_p; c_p = nt
		sub_pitch *= mul_sub_pitch; sub_env *= mul_sub_env; punch_env *= mul_punch
		noise_env *= mul_noise_env; cutoff_env *= mul_cutoff

	# Dense overlapping cluster of 28 chaotic/descending glossy crystal/ceramic shards in 0.025s..0.240s!
	var shard_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	shard_rng.seed = 7742
	for idx: int in range(28):
		var u: float = float(idx) / 27.0
		var t_pos: float = clampf(0.024 + 0.215 * (u * u * 0.55 + u * 0.45) + shard_rng.randf_range(-0.003, 0.003), 0.022, 0.242)
		var hi_band: float = lerpf(8600.0, 4200.0, u)
		var lo_band: float = lerpf(4200.0, 2000.0, u)
		var shard_hz: float = shard_rng.randf_range(lo_band, hi_band)
		var pan: float = shard_rng.randf_range(-0.92, 0.92)
		var shard_gain: float = lerpf(0.24, 0.08, u) * shard_rng.randf_range(0.78, 1.18)
		var shard_dur: float = shard_rng.randf_range(0.028, 0.052)
		_add_crystal_shatter_grain(
			left, right, t_pos, shard_hz, shard_dur, shard_gain, pan, 4100 + idx * 29
		)

	# 180 Hz HPF reverb send keeps <100 Hz sub-bass ultra-tight while shards bloom in lush stereo plate!
	_apply_stereo_plate_reverb(left, right, 0.36, 0.38, 0.38)
	return _finalize_stereo_buffer(left, right, 0.84, FADE_IN_SEC, 0.11, MASTER_LPF_HZ)


func _synth_lightning_zap() -> AudioStreamWAV:
	# Native 44.1 kHz tight band-shaped electric whip-crack (0.00-0.095s, 1.8-9.2 kHz natural brilliance,
	# smooth flutter pulses, ZERO Nyquist aliasing!) + 0ms sub-thump melting seamlessly into
	# shimmering stereo electric-chime power chord + upward harp arpeggio decaying cleanly by 0.96s!
	var duration: float = 0.96
	var total: int = _even_samples(duration)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	_add_stereo_sub_thump(left, right, 0.000, 158.0, 40.0, 0.056, 0.72, 0.0)

	var whip_n: int = _even_samples(0.115)
	var atk_n: int = int(round(0.0032 * float(SAMPLE_RATE)))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var rel_start: int = int(round(0.058 * float(SAMPLE_RATE)))
	var rel_span: float = float(maxi(whip_n - rel_start, 1))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 202609

	var mul_sweep: float = exp(-1.0 / (0.026 * float(SAMPLE_RATE)))
	var mul_whip: float = exp(-1.0 / (0.036 * float(SAMPLE_RATE)))

	var p_tone_l: float = 0.0; var p_tone_r: float = 0.0
	var dc_fl1: float = cos(82.0 * TAU_OVER_SR); var ds_fl1: float = sin(82.0 * TAU_OVER_SR)
	var dc_fl2: float = cos(148.0 * TAU_OVER_SR); var ds_fl2: float = sin(148.0 * TAU_OVER_SR)
	var c_fl1: float = 1.0; var s_fl1: float = 0.0
	var c_fl2: float = 1.0; var s_fl2: float = 0.0

	var sweep_env: float = 1.0; var whip_env: float = 1.0
	# Two cascaded bandpass stages (smooth 4-pole band shaping 2.0-8.8 kHz, zero 14-22 kHz leak!).
	var zl1: float = 0.0; var zl2: float = 0.0; var zl3: float = 0.0; var zl4: float = 0.0
	var zr1: float = 0.0; var zr2: float = 0.0; var zr3: float = 0.0; var zr4: float = 0.0
	var inv_whip: float = 1.0 / float(maxi(whip_n - 1, 1))

	for i: int in range(whip_n):
		var u: float = float(i) * inv_whip
		var gate: float = 1.0
		if i < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(i) * inv_atk))
		elif i >= rel_start:
			gate = 0.5 * (1.0 + cos(PI * float(i - rel_start) / rel_span))

		var flutter: float = 0.52 + 0.30 * s_fl1 + 0.18 * s_fl2

		var bp_hz: float = 1950.0 + 6250.0 * sweep_env
		var w0: float = TAU * bp_hz / float(SAMPLE_RATE)
		var alpha: float = sin(w0) / 3.0
		var inv_a0: float = 1.0 / (1.0 + alpha)
		var b0: float = alpha * inv_a0
		var a1: float = (-2.0 * cos(w0)) * inv_a0
		var a2: float = (1.0 - alpha) * inv_a0

		var wl: float = rng.randf_range(-1.0, 1.0)
		var yl1: float = b0 * wl + zl1; zl1 = -a1 * yl1 + zl2; zl2 = -b0 * wl - a2 * yl1
		var yl2: float = b0 * yl1 + zl3; zl3 = -a1 * yl2 + zl4; zl4 = -b0 * yl1 - a2 * yl2

		var wr: float = rng.randf_range(-1.0, 1.0)
		var yr1: float = b0 * wr + zr1; zr1 = -a1 * yr1 + zr2; zr2 = -b0 * wr - a2 * yr1
		var yr2: float = b0 * yr1 + zr3; zr3 = -a1 * yr2 + zr4; zr4 = -b0 * yr1 - a2 * yr2

		var tone_hz: float = 1150.0 + 3050.0 * sweep_env
		var pan: float = lerpf(-0.55, 0.55, u)
		var gl: float = 1.0 - 0.45 * pan
		var gr: float = 1.0 + 0.45 * pan

		var w_env: float = whip_env * flutter * gate
		left[i] += gl * (0.68 * yl2 + 0.32 * sin(p_tone_l)) * w_env
		right[i] += gr * (0.68 * yr2 + 0.32 * sin(p_tone_r)) * w_env

		p_tone_l += (tone_hz * 0.994) * TAU_OVER_SR
		p_tone_r += (tone_hz * 1.006) * TAU_OVER_SR
		var nt: float = c_fl1 * dc_fl1 - s_fl1 * ds_fl1; s_fl1 = s_fl1 * dc_fl1 + c_fl1 * ds_fl1; c_fl1 = nt
		nt = c_fl2 * dc_fl2 - s_fl2 * ds_fl2; s_fl2 = s_fl2 * dc_fl2 + c_fl2 * ds_fl2; c_fl2 = nt
		sweep_env *= mul_sweep
		whip_env *= mul_whip

	# Shimmering stereo electric-chime power chord + upward harp arpeggio!
	_add_lush_brass_bell_voice(left, right, 0.014, 523.25, 0.105, 0.36, -0.32, 0.0055)
	_add_lush_brass_bell_voice(left, right, 0.024, 783.99, 0.105, 0.34, 0.32, 0.0055)
	_add_lush_brass_bell_voice(left, right, 0.036, 1046.50, 0.108, 0.32, -0.46, 0.0055)
	_add_lush_brass_bell_voice(left, right, 0.048, 1318.51, 0.108, 0.28, 0.46, 0.0055)
	_add_stereo_bell(left, right, 0.062, 1567.98, 0.102, 0.25, 0.18, 0.0, -0.60, 0.0055)
	_add_stereo_bell(left, right, 0.078, 2093.00, 0.105, 0.23, 0.14, 0.0, 0.62, 0.0055)

	_apply_stereo_plate_reverb(left, right, 0.36, 0.38, 0.32)
	return _finalize_stereo_buffer(left, right, 0.84, FADE_IN_SEC, 0.095, MASTER_LPF_HZ)


func _synth_fever_ignite() -> AudioStreamWAV:
	# Native 44.1 kHz immediate t=0.00s celebratory downbeat (36ms warm golden low-pass swell)
	# + punchy C2/C3 sub-bass bloom + warm orchestral brassy Maj9 foundation chord (C3..D5)
	# + soaring ascending glossy bell/harp sparkle (C5 -> E5 -> G5 -> B5 -> D6 -> G6, 6.5ms attacks)
	# + subtle soft warm fire-crackle shimmer (< 6.5 kHz) + alias-free stereo plate tail fading by 1.86s!
	var duration: float = 1.86
	var total: int = _even_samples(duration)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	_add_warm_fire_bloom(left, right, 0.000, 0.48, 1250.0, 180.0, 0.30, 6299, 0.036)

	_add_stereo_sub_thump(left, right, 0.000, 130.81, 65.41, 0.190, 0.56, 0.0)
	_add_lush_brass_bell_voice(left, right, 0.004, 130.81, 0.200, 0.34, 0.00, 0.012)  # C3
	_add_lush_brass_bell_voice(left, right, 0.006, 196.00, 0.200, 0.26, -0.22, 0.012) # G3
	_add_lush_brass_bell_voice(left, right, 0.010, 261.63, 0.205, 0.30, 0.22, 0.012)  # C4
	_add_lush_brass_bell_voice(left, right, 0.016, 329.63, 0.205, 0.28, -0.34, 0.012) # E4
	_add_lush_brass_bell_voice(left, right, 0.022, 392.00, 0.205, 0.28, 0.34, 0.012)  # G4
	_add_lush_brass_bell_voice(left, right, 0.028, 493.88, 0.200, 0.24, -0.44, 0.014) # B4
	_add_lush_brass_bell_voice(left, right, 0.034, 587.33, 0.205, 0.26, 0.44, 0.014)  # D5

	_add_stereo_bell(left, right, 0.042, 523.25, 0.195, 0.32, 0.24, 0.10, -0.50, 0.0065)
	_add_stereo_bell(left, right, 0.105, 659.25, 0.195, 0.32, 0.22, 0.09, 0.50, 0.0065)
	_add_stereo_bell(left, right, 0.170, 783.99, 0.195, 0.34, 0.20, 0.08, -0.58, 0.0065)
	_add_stereo_bell(left, right, 0.235, 987.77, 0.195, 0.32, 0.18, 0.06, 0.58, 0.0065)
	_add_stereo_bell(left, right, 0.300, 1174.66, 0.195, 0.34, 0.18, 0.05, -0.66, 0.0065)
	_add_stereo_bell(left, right, 0.368, 1567.98, 0.190, 0.32, 0.16, 0.00, 0.66, 0.0065)

	var em_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	em_rng.seed = 6543
	for idx: int in range(14):
		var u: float = float(idx) / 13.0
		var t_pos: float = 0.050 + 0.62 * u + em_rng.randf_range(-0.012, 0.012)
		var pan: float = em_rng.randf_range(-0.80, 0.80)
		var hz: float = lerpf(4200.0, 2100.0, u) * em_rng.randf_range(0.85, 1.15)
		var gain: float = lerpf(0.085, 0.020, u)
		_add_warm_ember_shimmer(left, right, t_pos, hz, 0.022, gain, pan, 6500 + idx * 41)

	_apply_stereo_plate_reverb(left, right, 0.38, 0.56, 0.34)
	return _finalize_stereo_buffer(left, right, 0.84, FADE_IN_SEC, 0.024, MASTER_LPF_HZ)


func _synth_game_over() -> AudioStreamWAV:
	var total: int = _even_samples(1.16)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	_add_warm_stereo_rhodes(left, right, 0.00, 659.25, 0.105, 0.50, -0.22, false)
	_add_warm_stereo_rhodes(left, right, 0.15, 587.33, 0.105, 0.48, 0.22, false)
	_add_warm_stereo_rhodes(left, right, 0.30, 523.25, 0.110, 0.48, -0.18, false)
	_add_warm_stereo_rhodes(left, right, 0.45, 392.00, 0.115, 0.52, 0.00, true)

	_add_warm_stereo_rhodes(left, right, 0.00, 261.63, 0.118, 0.26, -0.35, false)
	_add_warm_stereo_rhodes(left, right, 0.30, 220.00, 0.120, 0.26, 0.35, false)
	_add_warm_stereo_rhodes(left, right, 0.45, 261.63, 0.122, 0.30, -0.30, false)
	_add_warm_stereo_rhodes(left, right, 0.45, 329.63, 0.118, 0.24, 0.30, false)

	_apply_stereo_plate_reverb(left, right, 0.32, 0.30, 0.42)
	return _finalize_stereo_buffer(left, right, 0.76, FADE_IN_SEC, 0.024, 0.0)


func _synth_high_score() -> AudioStreamWAV:
	var total: int = _even_samples(1.28)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(total)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(total)

	_add_lush_brass_bell_voice(left, right, 0.000, 523.25, 0.085, 0.42, -0.25, 0.006)
	_add_lush_brass_bell_voice(left, right, 0.088, 659.25, 0.085, 0.44, 0.25, 0.006)
	_add_lush_brass_bell_voice(left, right, 0.176, 783.99, 0.092, 0.46, -0.20, 0.006)

	_add_stereo_sub_thump(left, right, 0.270, 135.0, 52.0, 0.068, 0.42, 0.0)
	_add_lush_brass_bell_voice(left, right, 0.270, 523.25, 0.130, 0.38, -0.30, 0.006)
	_add_lush_brass_bell_voice(left, right, 0.270, 783.99, 0.128, 0.34, 0.30, 0.006)
	_add_lush_brass_bell_voice(left, right, 0.270, 1046.50, 0.132, 0.42, 0.00, 0.006)
	_add_lush_brass_bell_voice(left, right, 0.282, 1318.51, 0.130, 0.32, 0.45, 0.006)

	_add_stereo_bell(left, right, 0.355, 1318.51, 0.110, 0.24, 0.18, 0.05, -0.55, 0.006)
	_add_stereo_bell(left, right, 0.435, 1567.98, 0.112, 0.24, 0.16, 0.00, 0.55, 0.006)
	_add_stereo_bell(left, right, 0.520, 2093.00, 0.115, 0.28, 0.12, 0.00, 0.00, 0.006)

	_apply_stereo_plate_reverb(left, right, 0.34, 0.34, 0.36)
	return _finalize_stereo_buffer(left, right, 0.84, FADE_IN_SEC, 0.024, 0.0)


# ==============================================================================
# Native 44.1 kHz Trig-Free Phasor Voice & Biquad Band-Limited Building Blocks
# ==============================================================================

func _fast_tanh(x: float) -> float:
	var c: float = clampf(x, -2.8, 2.8)
	var c2: float = c * c
	return c * (27.0 + c2) / (27.0 + 9.0 * c2)


func _smooth_hf_taper(hz: float, start_hz: float, end_hz: float) -> float:
	if hz <= start_hz:
		return 1.0
	if hz >= end_hz:
		return 0.0
	var u: float = (hz - start_hz) / (end_hz - start_hz)
	return 0.5 * (1.0 + cos(PI * u))


func _add_stereo_sub_thump(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	start_sec: float,
	f_start: float,
	f_end: float,
	decay_tau: float,
	gain: float,
	pan: float
) -> void:
	var start_idx: int = int(round(start_sec * float(SAMPLE_RATE)))
	var length: int = int(round(minf(decay_tau * 5.2, 1.05) * float(SAMPLE_RATE)))
	var end_idx: int = mini(start_idx + length, left.size())
	var count: int = end_idx - start_idx
	if count <= 8:
		return

	var atk_n: int = mini(int(round(0.0035 * float(SAMPLE_RATE))), int(float(count) * 0.25))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var rel_start: int = count - mini(int(round(0.055 * float(SAMPLE_RATE))), int(float(count) * 0.35))
	var rel_span: float = float(maxi(count - rel_start, 1))

	var mul_env: float = exp(-1.0 / (decay_tau * float(SAMPLE_RATE)))
	var mul_pitch: float = exp(-1.0 / (minf(decay_tau * 0.40, 0.032) * float(SAMPLE_RATE)))

	var gl: float = gain * sqrt(0.5 * (1.0 - clampf(pan, -1.0, 1.0))) * 1.41421356
	var gr: float = gain * sqrt(0.5 * (1.0 + clampf(pan, -1.0, 1.0))) * 1.41421356

	var phase: float = 0.0
	var env: float = 1.0
	var p_env: float = 1.0

	for k: int in range(count):
		var gate: float = 1.0
		if k < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(k) * inv_atk))
		elif k >= rel_start:
			gate = 0.5 * (1.0 + cos(PI * float(k - rel_start) / rel_span))

		var freq: float = f_end + (f_start - f_end) * p_env
		var s1: float = sin(phase); var c1: float = cos(phase)
		var val: float = _fast_tanh((0.84 * s1 + 0.16 * (2.0 * s1 * c1)) * 1.25) * env * gate
		var idx: int = start_idx + k
		left[idx] += gl * val
		right[idx] += gr * val

		phase += freq * TAU_OVER_SR
		env *= mul_env
		p_env *= mul_pitch


func _add_stereo_bell(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	start_sec: float,
	freq_hz: float,
	decay_tau: float,
	gain: float,
	h2_weight: float,
	h3_weight: float,
	pan: float,
	attack_sec: float
) -> void:
	var start_idx: int = int(round(start_sec * float(SAMPLE_RATE)))
	var length: int = int(round(minf(decay_tau * 4.5, 0.88) * float(SAMPLE_RATE)))
	var end_idx: int = mini(start_idx + length, left.size())
	var count: int = end_idx - start_idx
	if count <= 8:
		return

	var atk_n: int = mini(int(round(maxf(attack_sec, 0.0035) * float(SAMPLE_RATE))), int(float(count) * 0.25))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var rel_start: int = count - mini(int(round(0.065 * float(SAMPLE_RATE))), int(float(count) * 0.35))
	var rel_span: float = float(maxi(count - rel_start, 1))

	var mul1: float = exp(-1.0 / (decay_tau * float(SAMPLE_RATE)))
	var mul2: float = exp(-1.0 / (decay_tau * 0.52 * float(SAMPLE_RATE)))
	var mul3: float = exp(-1.0 / (decay_tau * 0.30 * float(SAMPLE_RATE)))

	var gl: float = gain * sqrt(0.5 * (1.0 - clampf(pan, -1.0, 1.0))) * 1.41421356
	var gr: float = gain * sqrt(0.5 * (1.0 + clampf(pan, -1.0, 1.0))) * 1.41421356

	var dc: float = cos(freq_hz * TAU_OVER_SR); var ds: float = sin(freq_hz * TAU_OVER_SR)
	var dcd: float = cos((freq_hz * 0.0030) * TAU_OVER_SR); var dsd: float = sin((freq_hz * 0.0030) * TAU_OVER_SR)
	var c: float = 1.0; var s: float = 0.0
	var cd: float = 1.0; var sd: float = 0.0

	var safe_h2: float = h2_weight * _smooth_hf_taper(freq_hz * 2.0, 8200.0, 11800.0)
	var safe_h3: float = h3_weight * _smooth_hf_taper(freq_hz * 3.0, 7800.0, 11500.0)
	var e1: float = 1.0; var e2: float = 1.0; var e3: float = 1.0

	for k: int in range(count):
		var gate: float = 1.0
		if k < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(k) * inv_atk))
		elif k >= rel_start:
			gate = 0.5 * (1.0 + cos(PI * float(k - rel_start) / rel_span))

		var sl: float = s * cd - c * sd
		var sr: float = s * cd + c * sd
		var harm: float = safe_h2 * (2.0 * s * c) * e2
		if safe_h3 > 0.0:
			harm += safe_h3 * (s * (3.0 - 4.0 * s * s)) * e3
			e3 *= mul3

		var idx: int = start_idx + k
		left[idx] += gl * (0.78 * sl * e1 + harm) * gate
		right[idx] += gr * (0.78 * sr * e1 + harm) * gate

		var nt: float = c * dc - s * ds; s = s * dc + c * ds; c = nt
		nt = cd * dcd - sd * dsd; sd = sd * dcd + cd * dsd; cd = nt
		e1 *= mul1; e2 *= mul2


func _add_lush_brass_bell_voice(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	start_sec: float,
	freq_hz: float,
	decay_tau: float,
	gain: float,
	pan: float,
	attack_sec: float
) -> void:
	var start_idx: int = int(round(start_sec * float(SAMPLE_RATE)))
	var length: int = int(round(minf(decay_tau * 4.5, 0.90) * float(SAMPLE_RATE)))
	var end_idx: int = mini(start_idx + length, left.size())
	var count: int = end_idx - start_idx
	if count <= 8:
		return

	var atk_n: int = mini(int(round(maxf(attack_sec, 0.005) * float(SAMPLE_RATE))), int(float(count) * 0.25))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var rel_start: int = count - mini(int(round(0.080 * float(SAMPLE_RATE))), int(float(count) * 0.35))
	var rel_span: float = float(maxi(count - rel_start, 1))

	var mul_body: float = exp(-1.0 / (decay_tau * float(SAMPLE_RATE)))
	var mul_bright: float = exp(-1.0 / (decay_tau * 0.50 * float(SAMPLE_RATE)))
	var mul_bloom: float = exp(-1.0 / (0.026 * float(SAMPLE_RATE)))

	var gl: float = gain * sqrt(0.5 * (1.0 - clampf(pan, -1.0, 1.0))) * 1.41421356
	var gr: float = gain * sqrt(0.5 * (1.0 + clampf(pan, -1.0, 1.0))) * 1.41421356

	var dc: float = cos(freq_hz * TAU_OVER_SR); var ds: float = sin(freq_hz * TAU_OVER_SR)
	var dcd: float = cos((freq_hz * 0.0036) * TAU_OVER_SR); var dsd: float = sin((freq_hz * 0.0036) * TAU_OVER_SR)
	var c: float = 1.0; var s: float = 0.0
	var cd: float = 1.0; var sd: float = 0.0

	var g2: float = 0.34 * _smooth_hf_taper(freq_hz * 2.0, 8200.0, 11800.0)
	var g3: float = 0.20 * _smooth_hf_taper(freq_hz * 3.0, 7800.0, 11500.0)
	var g4: float = 0.10 * _smooth_hf_taper(freq_hz * 4.0, 7200.0, 11000.0)

	var e_body: float = 1.0; var e_bright: float = 1.0; var bloom_rem: float = 1.0

	for k: int in range(count):
		var gate: float = 1.0
		if k < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(k) * inv_atk))
		elif k >= rel_start:
			gate = 0.5 * (1.0 + cos(PI * float(k - rel_start) / rel_span))

		var sl: float = s * cd - c * sd
		var sr: float = s * cd + c * sd
		var s2: float = 2.0 * s * c
		var s3: float = s * (3.0 - 4.0 * s * s)
		var s4: float = s2 * (2.0 * c * c - 1.0)
		var harm: float = (g2 * s2 + g3 * s3 + g4 * s4) * ((0.30 + 0.70 * (1.0 - bloom_rem)) * e_bright)

		var idx: int = start_idx + k
		left[idx] += gl * (0.68 * sl * e_body + harm) * gate
		right[idx] += gr * (0.68 * sr * e_body + harm) * gate

		var nt: float = c * dc - s * ds; s = s * dc + c * ds; c = nt
		nt = cd * dcd - sd * dsd; sd = sd * dcd + cd * dsd; cd = nt
		e_body *= mul_body; e_bright *= mul_bright; bloom_rem *= mul_bloom


func _add_warm_stereo_rhodes(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	start_sec: float,
	freq_hz: float,
	decay_tau: float,
	gain: float,
	pan: float,
	use_vibrato: bool
) -> void:
	var start_idx: int = int(round(start_sec * float(SAMPLE_RATE)))
	var length: int = int(round(minf(decay_tau * 4.8, 0.65) * float(SAMPLE_RATE)))
	var end_idx: int = mini(start_idx + length, left.size())
	var count: int = end_idx - start_idx
	if count <= 8:
		return

	var atk_n: int = mini(int(round(0.008 * float(SAMPLE_RATE))), int(float(count) * 0.25))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var rel_start: int = count - mini(int(round(0.068 * float(SAMPLE_RATE))), int(float(count) * 0.35))
	var rel_span: float = float(maxi(count - rel_start, 1))

	var mul1: float = exp(-1.0 / (decay_tau * float(SAMPLE_RATE)))
	var mul2: float = exp(-1.0 / (decay_tau * 0.42 * float(SAMPLE_RATE)))

	var gl: float = gain * sqrt(0.5 * (1.0 - clampf(pan, -1.0, 1.0))) * 1.41421356
	var gr: float = gain * sqrt(0.5 * (1.0 + clampf(pan, -1.0, 1.0))) * 1.41421356

	var e1: float = 1.0; var e2: float = 1.0

	if not use_vibrato:
		var dcl: float = cos((freq_hz * 0.9982) * TAU_OVER_SR); var dsl: float = sin((freq_hz * 0.9982) * TAU_OVER_SR)
		var dcr: float = cos((freq_hz * 1.0018) * TAU_OVER_SR); var dsr: float = sin((freq_hz * 1.0018) * TAU_OVER_SR)
		var cl: float = 1.0; var sl: float = 0.0
		var cr: float = 1.0; var sr: float = 0.0
		for k: int in range(count):
			var gate: float = 1.0
			if k < atk_n:
				gate = 0.5 * (1.0 - cos(PI * float(k) * inv_atk))
			elif k >= rel_start:
				gate = 0.5 * (1.0 + cos(PI * float(k - rel_start) / rel_span))
			var idx: int = start_idx + k
			left[idx] += gl * (0.78 * sl * e1 + 0.19 * (2.0 * sl * cl) * e2 + 0.04 * (sl * (3.0 - 4.0 * sl * sl)) * e2) * gate
			right[idx] += gr * (0.78 * sr * e1 + 0.19 * (2.0 * sr * cr) * e2 + 0.04 * (sr * (3.0 - 4.0 * sr * sr)) * e2) * gate
			var nt: float = cl * dcl - sl * dsl; sl = sl * dcl + cl * dsl; cl = nt
			nt = cr * dcr - sr * dsr; sr = sr * dcr + cr * dsr; cr = nt
			e1 *= mul1; e2 *= mul2
	else:
		var p: float = 0.0
		var dc_v: float = cos(4.6 * TAU_OVER_SR); var ds_v: float = sin(4.6 * TAU_OVER_SR)
		var cv: float = 1.0; var sv: float = 0.0
		var dc_d: float = cos((freq_hz * 0.0018) * TAU_OVER_SR); var ds_d: float = sin((freq_hz * 0.0018) * TAU_OVER_SR)
		var cd: float = 1.0; var sd: float = 0.0
		var base_inc: float = freq_hz * TAU_OVER_SR
		for k: int in range(count):
			var gate: float = 1.0
			if k < atk_n:
				gate = 0.5 * (1.0 - cos(PI * float(k) * inv_atk))
			elif k >= rel_start:
				gate = 0.5 * (1.0 + cos(PI * float(k - rel_start) / rel_span))
			var s1: float = sin(p); var c1: float = cos(p)
			var sl1: float = s1 * cd - c1 * sd
			var sr1: float = s1 * cd + c1 * sd
			var h23: float = (0.19 * (2.0 * s1 * c1) + 0.04 * (s1 * (3.0 - 4.0 * s1 * s1))) * e2
			var idx: int = start_idx + k
			left[idx] += gl * (0.78 * sl1 * e1 + h23) * gate
			right[idx] += gr * (0.78 * sr1 * e1 + h23) * gate
			p += base_inc * (1.0 + 0.0026 * sv)
			var nt: float = cv * dc_v - sv * ds_v; sv = sv * dc_v + cv * ds_v; cv = nt
			nt = cd * dc_d - sd * ds_d; sd = sd * dc_d + cd * ds_d; cd = nt
			e1 *= mul1; e2 *= mul2


func _add_stereo_coin_ping(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	start_sec: float,
	freq_hz: float,
	decay_tau: float,
	gain: float,
	pan: float
) -> void:
	var start_idx: int = int(round(start_sec * float(SAMPLE_RATE)))
	var length: int = int(round(minf(decay_tau * 5.0, 0.30) * float(SAMPLE_RATE)))
	var end_idx: int = mini(start_idx + length, left.size())
	var count: int = end_idx - start_idx
	if count <= 8:
		return

	var atk_n: int = mini(int(round(0.0032 * float(SAMPLE_RATE))), int(float(count) * 0.25))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var rel_start: int = count - mini(int(round(0.040 * float(SAMPLE_RATE))), int(float(count) * 0.35))
	var rel_span: float = float(maxi(count - rel_start, 1))

	var mul1: float = exp(-1.0 / (decay_tau * float(SAMPLE_RATE)))
	var mul2: float = exp(-1.0 / (decay_tau * 0.58 * float(SAMPLE_RATE)))
	var mul3: float = exp(-1.0 / (decay_tau * 0.32 * float(SAMPLE_RATE)))

	var gl: float = gain * sqrt(0.5 * (1.0 - clampf(pan, -1.0, 1.0))) * 1.41421356
	var gr: float = gain * sqrt(0.5 * (1.0 + clampf(pan, -1.0, 1.0))) * 1.41421356

	var dc1l: float = cos((freq_hz * 0.9968) * TAU_OVER_SR); var ds1l: float = sin((freq_hz * 0.9968) * TAU_OVER_SR)
	var dc1r: float = cos((freq_hz * 1.0032) * TAU_OVER_SR); var ds1r: float = sin((freq_hz * 1.0032) * TAU_OVER_SR)
	var dc2: float = cos(minf(freq_hz * 2.0, 11200.0) * TAU_OVER_SR); var ds2: float = sin(minf(freq_hz * 2.0, 11200.0) * TAU_OVER_SR)
	var dc3: float = cos(minf(freq_hz * 2.756, 11600.0) * TAU_OVER_SR); var ds3: float = sin(minf(freq_hz * 2.756, 11600.0) * TAU_OVER_SR)

	var c1l: float = 1.0; var s1l: float = 0.0
	var c1r: float = 1.0; var s1r: float = 0.0
	var c2: float = 1.0; var s2: float = 0.0
	var c3: float = 1.0; var s3: float = 0.0

	var g2: float = 0.32 * _smooth_hf_taper(freq_hz * 2.0, 8200.0, 11800.0)
	var g3: float = 0.22 * _smooth_hf_taper(freq_hz * 2.756, 8000.0, 11800.0)
	var e1: float = 1.0; var e2: float = 1.0; var e3: float = 1.0

	for k: int in range(count):
		var gate: float = 1.0
		if k < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(k) * inv_atk))
		elif k >= rel_start:
			gate = 0.5 * (1.0 + cos(PI * float(k - rel_start) / rel_span))

		var hi: float = g2 * s2 * e2 + g3 * s3 * e3
		var idx: int = start_idx + k
		left[idx] += gl * (0.74 * s1l * e1 + hi * 1.04) * gate
		right[idx] += gr * (0.74 * s1r * e1 + hi * 0.96) * gate

		var nt: float = c1l * dc1l - s1l * ds1l; s1l = s1l * dc1l + c1l * ds1l; c1l = nt
		nt = c1r * dc1r - s1r * ds1r; s1r = s1r * dc1r + c1r * ds1r; c1r = nt
		nt = c2 * dc2 - s2 * ds2; s2 = s2 * dc2 + c2 * ds2; c2 = nt
		nt = c3 * dc3 - s3 * ds3; s3 = s3 * dc3 + c3 * ds3; c3 = nt
		e1 *= mul1; e2 *= mul2; e3 *= mul3


func _add_crystal_shatter_grain(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	start_sec: float,
	freq_hz: float,
	dur_sec: float,
	gain: float,
	pan: float,
	seed_val: int
) -> void:
	# Native 44.1 kHz glossy ceramic/crystal micro-shard (2.0-10.5 kHz, 4-pole band-shaped grit, >= 3.2ms attack).
	var start_idx: int = int(round(start_sec * float(SAMPLE_RATE)))
	var length: int = int(round(dur_sec * float(SAMPLE_RATE)))
	var end_idx: int = mini(start_idx + length, left.size())
	var count: int = end_idx - start_idx
	if count <= 16:
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val

	var atk_n: int = mini(int(round(0.0032 * float(SAMPLE_RATE))), int(float(count) * 0.30))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var rel_start: int = int(float(count) * 0.55)
	var rel_span: float = float(maxi(count - rel_start, 1))

	var mul_env: float = exp(-1.0 / (dur_sec * 0.30 * float(SAMPLE_RATE)))
	var mul_grit: float = exp(-1.0 / (0.0045 * float(SAMPLE_RATE)))

	var safe_f1: float = clampf(freq_hz, 1800.0, 8800.0)
	var safe_f2: float = clampf(safe_f1 * 1.24, 2200.0, 10400.0)
	var w0: float = TAU * clampf(safe_f1 * 0.88, 1600.0, 7400.0) / float(SAMPLE_RATE)
	var alpha: float = sin(w0) / 3.4
	var inv_a0: float = 1.0 / (1.0 + alpha)
	var b0: float = alpha * inv_a0
	var a1: float = (-2.0 * cos(w0)) * inv_a0
	var a2: float = (1.0 - alpha) * inv_a0

	var gl: float = gain * sqrt(0.5 * (1.0 - clampf(pan, -1.0, 1.0))) * 1.41421356
	var gr: float = gain * sqrt(0.5 * (1.0 + clampf(pan, -1.0, 1.0))) * 1.41421356

	var dc1: float = cos(safe_f1 * TAU_OVER_SR); var ds1: float = sin(safe_f1 * TAU_OVER_SR)
	var dc2: float = cos(safe_f2 * TAU_OVER_SR); var ds2: float = sin(safe_f2 * TAU_OVER_SR)
	var c1: float = 1.0; var s1: float = 0.0
	var c2: float = 1.0; var s2: float = 0.0
	var env: float = 1.0; var e_grit: float = 1.0
	var z1: float = 0.0; var z2: float = 0.0; var z3: float = 0.0; var z4: float = 0.0

	for k: int in range(count):
		var gate: float = 1.0
		if k < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(k) * inv_atk))
		elif k >= rel_start:
			gate = 0.5 * (1.0 + cos(PI * float(k - rel_start) / rel_span))

		var w: float = rng.randf_range(-1.0, 1.0)
		var y1: float = b0 * w + z1; z1 = -a1 * y1 + z2; z2 = -b0 * w - a2 * y1
		var y2: float = b0 * y1 + z3; z3 = -a1 * y2 + z4; z4 = -b0 * y1 - a2 * y2

		var val: float = ((0.58 * s1 + 0.32 * s2) * env + 0.36 * y2 * e_grit) * gate
		var idx: int = start_idx + k
		left[idx] += gl * val
		right[idx] += gr * val

		var nt: float = c1 * dc1 - s1 * ds1; s1 = s1 * dc1 + c1 * ds1; c1 = nt
		nt = c2 * dc2 - s2 * ds2; s2 = s2 * dc2 + c2 * ds2; c2 = nt
		env *= mul_env; e_grit *= mul_grit


func _add_warm_ember_shimmer(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	start_sec: float,
	freq_hz: float,
	dur_sec: float,
	gain: float,
	pan: float,
	seed_val: int
) -> void:
	var start_idx: int = int(round(start_sec * float(SAMPLE_RATE)))
	var length: int = int(round(dur_sec * float(SAMPLE_RATE)))
	var end_idx: int = mini(start_idx + length, left.size())
	var count: int = end_idx - start_idx
	if count <= 16:
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val

	var atk_n: int = mini(int(round(0.0042 * float(SAMPLE_RATE))), int(float(count) * 0.35))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var rel_start: int = int(float(count) * 0.50)
	var rel_span: float = float(maxi(count - rel_start, 1))

	var mul_env: float = exp(-1.0 / (dur_sec * 0.32 * float(SAMPLE_RATE)))
	var safe_hz: float = clampf(freq_hz, 1400.0, 5600.0)
	var w0: float = TAU * safe_hz / float(SAMPLE_RATE)
	var alpha: float = sin(w0) / 3.4
	var inv_a0: float = 1.0 / (1.0 + alpha)
	var b0: float = alpha * inv_a0
	var a1: float = (-2.0 * cos(w0)) * inv_a0
	var a2: float = (1.0 - alpha) * inv_a0

	var gl: float = gain * sqrt(0.5 * (1.0 - clampf(pan, -1.0, 1.0))) * 1.41421356
	var gr: float = gain * sqrt(0.5 * (1.0 + clampf(pan, -1.0, 1.0))) * 1.41421356

	var dc: float = cos(safe_hz * TAU_OVER_SR); var ds: float = sin(safe_hz * TAU_OVER_SR)
	var c: float = 1.0; var s: float = 0.0
	var env: float = 1.0
	var z1: float = 0.0; var z2: float = 0.0; var z3: float = 0.0; var z4: float = 0.0

	for k: int in range(count):
		var gate: float = 1.0
		if k < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(k) * inv_atk))
		elif k >= rel_start:
			gate = 0.5 * (1.0 + cos(PI * float(k - rel_start) / rel_span))

		var w: float = rng.randf_range(-1.0, 1.0)
		var y1: float = b0 * w + z1; z1 = -a1 * y1 + z2; z2 = -b0 * w - a2 * y1
		var y2: float = b0 * y1 + z3; z3 = -a1 * y2 + z4; z4 = -b0 * y1 - a2 * y2

		var val: float = (0.62 * y2 + 0.42 * s) * env * gate
		var idx: int = start_idx + k
		left[idx] += gl * val
		right[idx] += gr * val

		var nt: float = c * dc - s * ds; s = s * dc + c * ds; c = nt
		env *= mul_env


func _add_resonant_whoosh(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	start_sec: float,
	dur_sec: float,
	hz_start: float,
	hz_end: float,
	gain: float,
	pan_start: float,
	pan_end: float,
	seed_val: int
) -> void:
	var start_idx: int = int(round(start_sec * float(SAMPLE_RATE)))
	var length: int = int(round(dur_sec * float(SAMPLE_RATE)))
	var end_idx: int = mini(start_idx + length, left.size())
	var count: int = end_idx - start_idx
	if count <= 16:
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val

	var inv_count: float = 1.0 / float(maxi(count - 1, 1))
	var zl1: float = 0.0; var zl2: float = 0.0
	var zr1: float = 0.0; var zr2: float = 0.0

	for k: int in range(count):
		var u: float = float(k) * inv_count
		var s_u: float = sin(PI * u)
		var env: float = s_u * s_u * (0.35 + 0.65 * u)
		var hz: float = lerpf(hz_start, hz_end, u * u)
		var w0: float = TAU * clampf(hz, 200.0, 5000.0) / float(SAMPLE_RATE)
		var alpha: float = sin(w0) / 3.0
		var inv_a0: float = 1.0 / (1.0 + alpha)
		var b0: float = alpha * inv_a0
		var a1: float = (-2.0 * cos(w0)) * inv_a0
		var a2: float = (1.0 - alpha) * inv_a0

		var wl: float = rng.randf_range(-1.0, 1.0)
		var wr: float = 0.55 * wl + 0.45 * rng.randf_range(-1.0, 1.0)
		var yl: float = b0 * wl + zl1; zl1 = -a1 * yl + zl2; zl2 = -b0 * wl - a2 * yl
		var yr: float = b0 * wr + zr1; zr1 = -a1 * yr + zr2; zr2 = -b0 * wr - a2 * yr

		var pan: float = lerpf(pan_start, pan_end, u)
		var idx: int = start_idx + k
		left[idx] += gain * (1.0 - 0.5 * pan) * yl * env
		right[idx] += gain * (1.0 + 0.5 * pan) * yr * env


func _add_warm_fire_bloom(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	start_sec: float,
	dur_sec: float,
	hz_start: float,
	hz_end: float,
	gain: float,
	seed_val: int,
	attack_sec: float = 0.010
) -> void:
	var start_idx: int = int(round(start_sec * float(SAMPLE_RATE)))
	var length: int = int(round(dur_sec * float(SAMPLE_RATE)))
	var end_idx: int = mini(start_idx + length, left.size())
	var count: int = end_idx - start_idx
	if count <= 16:
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val

	var atk_n: int = mini(int(round(maxf(attack_sec, 0.006) * float(SAMPLE_RATE))), int(float(count) * 0.25))
	var inv_atk: float = 1.0 / float(maxi(atk_n - 1, 1))
	var rel_start: int = count - mini(int(round(0.11 * float(SAMPLE_RATE))), int(float(count) * 0.35))
	var rel_span: float = float(maxi(count - rel_start, 1))

	var mul_env: float = exp(-1.0 / (0.105 * float(SAMPLE_RATE)))
	var mul_cut: float = exp(-1.0 / (0.088 * float(SAMPLE_RATE)))
	var env: float = 1.0; var cut_env: float = 1.0

	var l1: float = 0.0; var l2: float = 0.0; var l3: float = 0.0; var l4: float = 0.0
	var r1: float = 0.0; var r2: float = 0.0; var r3: float = 0.0; var r4: float = 0.0

	for k: int in range(count):
		var gate: float = 1.0
		if k < atk_n:
			gate = 0.5 * (1.0 - cos(PI * float(k) * inv_atk))
		elif k >= rel_start:
			gate = 0.5 * (1.0 + cos(PI * float(k - rel_start) / rel_span))

		var hz: float = hz_end + (hz_start - hz_end) * cut_env
		var a: float = clampf(TAU * hz / (TAU * hz + float(SAMPLE_RATE)), 0.008, 0.42)

		var wl: float = rng.randf_range(-1.0, 1.0)
		var wr: float = 0.60 * wl + 0.40 * rng.randf_range(-1.0, 1.0)
		l1 += a * (wl - l1); l2 += a * (l1 - l2); l3 += a * (l2 - l3); l4 += a * (l3 - l4)
		r1 += a * (wr - r1); r2 += a * (r1 - r2); r3 += a * (r2 - r3); r4 += a * (r3 - r4)

		var idx: int = start_idx + k
		var sc: float = gain * 1.50 * env * gate
		left[idx] += l4 * sc
		right[idx] += r4 * sc

		env *= mul_env
		cut_env *= mul_cut


# ==============================================================================
# Alias-Free 4-Channel Hadamard FDN Stereo Plate Reverb
# (180 Hz HPF Send + 5.5 kHz Pre-LPF -> 22.05 kHz FDN -> 4-Pole 6.2 kHz Anti-Imaging LPF)
# ==============================================================================

func _apply_stereo_plate_reverb(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	wet: float,
	t60_sec: float,
	damp: float
) -> void:
	var n: int = left.size()
	var half_n: int = int(float(n) * 0.5)
	if half_n < 16 or wet <= 0.0001:
		return

	var half_sr: float = float(SAMPLE_RATE) * 0.5
	var len0: int = 293 # 13.29ms
	var len1: int = 433 # 19.64ms
	var len2: int = 627 # 28.44ms
	var len3: int = 839 # 38.05ms

	var d0: PackedFloat32Array = PackedFloat32Array(); d0.resize(len0)
	var d1: PackedFloat32Array = PackedFloat32Array(); d1.resize(len1)
	var d2: PackedFloat32Array = PackedFloat32Array(); d2.resize(len2)
	var d3: PackedFloat32Array = PackedFloat32Array(); d3.resize(len3)

	var safe_t60: float = maxf(t60_sec, 0.05)
	var g0: float = exp(-6.907755 * (float(len0) / half_sr) / safe_t60) * 0.5
	var g1: float = exp(-6.907755 * (float(len1) / half_sr) / safe_t60) * 0.5
	var g2: float = exp(-6.907755 * (float(len2) / half_sr) / safe_t60) * 0.5
	var g3: float = exp(-6.907755 * (float(len3) / half_sr) / safe_t60) * 0.5

	var damp_keep: float = clampf(damp, 0.12, 0.72)
	var damp_in: float = 1.0 - damp_keep

	# Input send conditioning at 44.1 kHz: 5.5 kHz 2-pole pre-LPF + 180 Hz 1-pole HPF (keeps sub-bass ultra-tight!).
	var pre_a: float = clampf(TAU * 5500.0 / (TAU * 5500.0 + float(SAMPLE_RATE)), 0.1, 0.65)
	var hpf_r: float = exp(-TAU * 180.0 / half_sr) # 180 Hz Abbey-Road reverb send HPF!

	# 4-pole Butterworth anti-imaging LPF at 6.2 kHz (fs = 44,100 Hz) on the upsampled wet return!
	# Exact 4th-order Butterworth pole Q values: Q1 = 0.5411961, Q2 = 1.3065630 (-95 dB @ 18-22 kHz!).
	var w_ai: float = TAU * 6200.0 / float(SAMPLE_RATE)
	var cw_ai: float = cos(w_ai)
	var sw_ai: float = sin(w_ai)

	var al1: float = sw_ai / (2.0 * 0.5411961)
	var inv1: float = 1.0 / (1.0 + al1)
	var b0_1: float = ((1.0 - cw_ai) * 0.5) * inv1
	var b1_1: float = (1.0 - cw_ai) * inv1
	var a1_1: float = (-2.0 * cw_ai) * inv1
	var a2_1: float = (1.0 - al1) * inv1

	var al2: float = sw_ai / (2.0 * 1.3065630)
	var inv2: float = 1.0 / (1.0 + al2)
	var b0_2: float = ((1.0 - cw_ai) * 0.5) * inv2
	var b1_2: float = (1.0 - cw_ai) * inv2
	var a1_2: float = (-2.0 * cw_ai) * inv2
	var a2_2: float = (1.0 - al2) * inv2

	# State registers for input pre-LPF, 180 Hz send HPF, FDN lines, and 4-pole wet anti-imaging LPF.
	var pl1: float = 0.0; var pl2: float = 0.0; var pr1: float = 0.0; var pr2: float = 0.0
	var hp_xl: float = 0.0; var hp_yl: float = 0.0; var hp_xr: float = 0.0; var hp_yr: float = 0.0

	var i0: int = 0; var i1: int = 0; var i2: int = 0; var i3: int = 0
	var lp0: float = 0.0; var lp1: float = 0.0; var lp2: float = 0.0; var lp3: float = 0.0
	var prev_wl: float = 0.0; var prev_wr: float = 0.0
	var wet_scale: float = wet * 0.85

	var l1_z1: float = 0.0; var l1_z2: float = 0.0; var l2_z1: float = 0.0; var l2_z2: float = 0.0
	var r1_z1: float = 0.0; var r1_z2: float = 0.0; var r2_z1: float = 0.0; var r2_z2: float = 0.0

	for k: int in range(half_n):
		var s_idx: int = k * 2

		# Pre-LPF 2-pole @ 5.5 kHz on both 44.1 kHz input samples before 2:1 decimation.
		var raw_l0: float = left[s_idx]; var raw_r0: float = right[s_idx]
		pl1 += pre_a * (raw_l0 - pl1); pl2 += pre_a * (pl1 - pl2)
		pr1 += pre_a * (raw_r0 - pr1); pr2 += pre_a * (pr1 - pr2)
		var raw_l1: float = left[s_idx + 1]; var raw_r1: float = right[s_idx + 1]
		pl1 += pre_a * (raw_l1 - pl1); pl2 += pre_a * (pl1 - pl2)
		pr1 += pre_a * (raw_r1 - pr1); pr2 += pre_a * (pr1 - pr2)

		# 180 Hz send HPF keeps <100 Hz sub-bass completely out of the reverb tail!
		hp_yl = hpf_r * (hp_yl + pl2 - hp_xl); hp_xl = pl2
		hp_yr = hpf_r * (hp_yr + pr2 - hp_xr); hp_xr = pr2
		var in_l: float = hp_yl
		var in_r: float = hp_yr

		# 4-channel Hadamard FDN step @ 22,050 Hz.
		lp0 = damp_in * d0[i0] + damp_keep * lp0
		lp1 = damp_in * d1[i1] + damp_keep * lp1
		lp2 = damp_in * d2[i2] + damp_keep * lp2
		lp3 = damp_in * d3[i3] + damp_keep * lp3

		var s01_p: float = lp0 + lp1; var s01_m: float = lp0 - lp1
		var s23_p: float = lp2 + lp3; var s23_m: float = lp2 - lp3
		var mono_mid: float = 0.5 * (in_l + in_r)
		var side: float = 0.5 * (in_l - in_r)
		d0[i0] = (s01_p + s23_p) * g0 + in_l * 0.55 + side * 0.25
		d1[i1] = (s01_m + s23_m) * g1 + in_r * 0.55 - side * 0.25
		d2[i2] = (s01_p - s23_p) * g2 + mono_mid * 0.50 - in_r * 0.20
		d3[i3] = (s01_m - s23_m) * g3 + mono_mid * 0.50 - in_l * 0.20

		i0 += 1; if i0 >= len0: i0 = 0
		i1 += 1; if i1 >= len1: i1 = 0
		i2 += 1; if i2 >= len2: i2 = 0
		i3 += 1; if i3 >= len3: i3 = 0

		var wl: float = (lp0 + lp2 - 0.35 * lp1) * wet_scale
		var wr: float = (lp1 + lp3 - 0.35 * lp0) * wet_scale

		# Upsample wet return to 44.1 kHz & IMMEDIATELY pass through 4-pole 6.2 kHz anti-imaging LPF!
		var ul0: float = 0.5 * (prev_wl + wl)
		var yl_a: float = b0_1 * ul0 + l1_z1; l1_z1 = b1_1 * ul0 - a1_1 * yl_a + l1_z2; l1_z2 = b0_1 * ul0 - a2_1 * yl_a
		var yl_b: float = b0_2 * yl_a + l2_z1; l2_z1 = b1_2 * yl_a - a1_2 * yl_b + l2_z2; l2_z2 = b0_2 * yl_a - a2_2 * yl_b
		left[s_idx] = raw_l0 + yl_b

		var ur0: float = 0.5 * (prev_wr + wr)
		var yr_a: float = b0_1 * ur0 + r1_z1; r1_z1 = b1_1 * ur0 - a1_1 * yr_a + r1_z2; r1_z2 = b0_1 * ur0 - a2_1 * yr_a
		var yr_b: float = b0_2 * yr_a + r2_z1; r2_z1 = b1_2 * yr_a - a1_2 * yr_b + r2_z2; r2_z2 = b0_2 * yr_a - a2_2 * yr_b
		right[s_idx] = raw_r0 + yr_b

		yl_a = b0_1 * wl + l1_z1; l1_z1 = b1_1 * wl - a1_1 * yl_a + l1_z2; l1_z2 = b0_1 * wl - a2_1 * yl_a
		yl_b = b0_2 * yl_a + l2_z1; l2_z1 = b1_2 * yl_a - a1_2 * yl_b + l2_z2; l2_z2 = b0_2 * yl_a - a2_2 * yl_b
		left[s_idx + 1] = raw_l1 + yl_b

		yr_a = b0_1 * wr + r1_z1; r1_z1 = b1_1 * wr - a1_1 * yr_a + r1_z2; r1_z2 = b0_1 * wr - a2_1 * yr_a
		yr_b = b0_2 * yr_a + r2_z1; r2_z1 = b1_2 * yr_a - a1_2 * yr_b + r2_z2; r2_z2 = b0_2 * yr_a - a2_2 * yr_b
		right[s_idx + 1] = raw_r1 + yr_b

		prev_wl = wl
		prev_wr = wr


# ==============================================================================
# Native 44.1 kHz Stereo Mastering Pipeline (Gentle 14.5 kHz 2-Pole Silk LPF)
# ==============================================================================

func _even_samples(duration_sec: float) -> int:
	var n: int = int(round(duration_sec * float(SAMPLE_RATE)))
	if n % 2 != 0:
		n += 1
	return maxi(n, 64)


func _finalize_stereo_buffer(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	target_peak: float,
	fade_in_sec: float,
	fade_out_sec: float,
	master_lpf_hz: float
) -> AudioStreamWAV:
	var total: int = mini(left.size(), right.size())
	var safe_target: float = minf(target_peak, MAX_SAFE_PEAK)
	var max_fade_n: int = int(float(total) / 3.0)
	var fade_in_n: int = mini(int(round(fade_in_sec * float(SAMPLE_RATE))), max_fade_n)
	var fade_out_n: int = mini(int(round(fade_out_sec * float(SAMPLE_RATE))), max_fade_n)

	# Pass 1: Gentle 2-pole Butterworth silk LPF @ 14.5 kHz + 28 Hz DC-blocking HPF (zero DC floor in silent tails!) + linked stereo peak.
	var peak: float = 0.0
	var dc_r_coef: float = exp(-TAU * 28.0 / float(SAMPLE_RATE))
	var hp_xl: float = 0.0; var hp_yl: float = 0.0
	var hp_xr: float = 0.0; var hp_yr: float = 0.0

	if master_lpf_hz > 100.0:
		var w0: float = TAU * clampf(master_lpf_hz, 2000.0, 18000.0) / float(SAMPLE_RATE)
		var cw: float = cos(w0)
		var alpha: float = sin(w0) * 0.70710678
		var inv_a0: float = 1.0 / (1.0 + alpha)
		var b0: float = ((1.0 - cw) * 0.5) * inv_a0
		var b1: float = (1.0 - cw) * inv_a0
		var a1: float = (-2.0 * cw) * inv_a0
		var a2: float = (1.0 - alpha) * inv_a0

		var zl1: float = 0.0; var zl2: float = 0.0
		var zr1: float = 0.0; var zr2: float = 0.0

		for i: int in range(total):
			var xl: float = left[i]
			var yl: float = b0 * xl + zl1
			zl1 = b1 * xl - a1 * yl + zl2
			zl2 = b0 * xl - a2 * yl

			var xr: float = right[i]
			var yr: float = b0 * xr + zr1
			zr1 = b1 * xr - a1 * yr + zr2
			zr2 = b0 * xr - a2 * yr

			# 28 Hz causal DC-blocker (eliminates asymmetric sweep DC step cleanly without injecting tail floor!).
			hp_yl = dc_r_coef * (hp_yl + yl - hp_xl); hp_xl = yl
			hp_yr = dc_r_coef * (hp_yr + yr - hp_xr); hp_xr = yr

			left[i] = hp_yl; right[i] = hp_yr
			var av: float = absf(hp_yl)
			if av > peak:
				peak = av
			av = absf(hp_yr)
			if av > peak:
				peak = av
	else:
		for i: int in range(total):
			var vl: float = left[i]
			var vr: float = right[i]
			hp_yl = dc_r_coef * (hp_yl + vl - hp_xl); hp_xl = vl
			hp_yr = dc_r_coef * (hp_yr + vr - hp_xr); hp_xr = vr
			left[i] = hp_yl; right[i] = hp_yr
			var av: float = absf(hp_yl)
			if av > peak:
				peak = av
			av = absf(hp_yr)
			if av > peak:
				peak = av

	if not is_finite(peak):
		_had_nonfinite_sample = true
		peak = 0.0
		for i: int in range(total):
			if not is_finite(left[i]):
				left[i] = 0.0
			if not is_finite(right[i]):
				right[i] = 0.0
			peak = maxf(peak, maxf(absf(left[i]), absf(right[i])))

	# Smooth raised-cosine fade-in & clean fade-out to true digital zero (leaving dead-black silence at EOF).
	if fade_in_n > 1:
		var inv_fi: float = PI / float(fade_in_n - 1)
		for i: int in range(fade_in_n):
			var w_in: float = 0.5 * (1.0 - cos(float(i) * inv_fi))
			left[i] *= w_in
			right[i] *= w_in
	var pad_zero_n: int = mini(int(round(0.055 * float(SAMPLE_RATE))), maxi(0, total / 8)) if total >= int(0.85 * float(SAMPLE_RATE)) else 0
	var fo_end: int = total - pad_zero_n
	if fade_out_n > 1 and fo_end > fade_out_n:
		var inv_fo: float = PI / float(fade_out_n - 1)
		var fo_start: int = fo_end - fade_out_n
		for i: int in range(fo_start, fo_end):
			var w_out: float = 0.5 * (1.0 - cos(float(fo_end - 1 - i) * inv_fo))
			left[i] *= w_out
			right[i] *= w_out
	for i: int in range(fo_end, total):
		left[i] = 0.0
		right[i] = 0.0

	# Pass 2: Linked stereo normalize (<= 0.85) & encode 44.1 kHz 16-bit PCM stereo.
	var scale: float = safe_target / maxf(peak, 0.00001)
	var scale_i16: float = scale * 32767.0

	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(total * 4)
	for i: int in range(total):
		var off: int = i * 4
		pcm.encode_s16(off, clampi(int(round(left[i] * scale_i16)), -32767, 32767))
		pcm.encode_s16(off + 2, clampi(int(round(right[i] * scale_i16)), -32767, 32767))

	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = true
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = pcm
	return wav
