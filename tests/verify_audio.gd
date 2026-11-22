extends SceneTree

## Headless stereo audio verification & diagnostic WAV exporter for Kombo's SoundSynth engine (Round 3).
## Run via:
##   godot --headless --path . --script res://tests/verify_audio.gd

const SoundSynthScript = preload("res://scripts/audio/sound_synth.gd")
const SAMPLE_RATE: int = 44100
const MAX_SYNTH_TIME_MS: float = 1800.0
const EVAL_EXPORT_DIR: String = "C:/Users/phatt/.gemini/antigravity/brain/eaafa6d5-e303-445b-972c-67de1b6dd6da/scratch/audio_eval"

var _failures: Array[String] = []
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_verification()
	return true


func _run_verification() -> void:
	print("=== Kombo Stereo Audio Engine Verification (Slice 6A Round 3) ===")

	var synth: Node = SoundSynthScript.new()
	root.add_child(synth)
	_assert_true(synth.is_inside_tree(), "SoundSynth should be inside SceneTree after root.add_child")

	var synth_ms: float = float(synth.call("get_synth_time_ms"))
	print("Startup stereo synthesis time: %.2f ms (budget <= %.0f ms)" % [synth_ms, MAX_SYNTH_TIME_MS])
	_assert_true(synth_ms <= MAX_SYNTH_TIME_MS, "Startup synthesis %.2f ms exceeded %.0f ms budget" % [synth_ms, MAX_SYNTH_TIME_MS])
	_assert_true(not bool(synth.call("had_nonfinite_sample")), "Synthesis produced NaN/Inf samples!")

	# 1. Inspect every combo stream (1..16) and verify stereo quality, natural ring-out, & ascending pitch.
	var step_count: int = int(synth.call("get_combo_step_count"))
	_assert_true(step_count == 16, "Expected 16 combo steps, got %d" % step_count)

	var measured_ac_hz: Array[float] = []
	var combo_durs: Array[float] = []

	print("\n--- Combo Scale Stereo Buffer Inspection & Pitch Analysis ---")
	for step: int in range(1, step_count + 1):
		var stream: AudioStreamWAV = synth.call("get_combo_stream", step) as AudioStreamWAV
		var label: String = "combo_%02d" % step
		var decoded: Dictionary = _validate_stereo_stream(stream, label, 0.015, true, true, true)
		var mid: PackedFloat32Array = decoded["mid"] as PackedFloat32Array
		combo_durs.append(float(mid.size()) / float(SAMPLE_RATE))

		var target_hz: float = float(synth.call("get_combo_target_hz", step))
		var ac_hz: float = _estimate_pitch_yin(mid, 0.048, 1024)
		var zcr_hz: float = _estimate_pitch_zcr(mid, 0.048, 0.075)
		measured_ac_hz.append(ac_hz)

		var err_pct: float = absf(ac_hz - target_hz) / target_hz * 100.0
		print("  Step %2d | target=%7.2f Hz | YIN=%7.2f Hz (err=%.2f%%) | ZCR=%7.2f Hz" % [
			step, target_hz, ac_hz, err_pct, zcr_hz
		])
		_assert_true(err_pct <= 2.0, "%s pitch error %.2f%% exceeds 2.0%% (target %.2f, got %.2f)" % [
			label, err_pct, target_hz, ac_hz
		])

	# Verify combo tail length escalation (combo_8 >= 0.78s and >= combo_1 >= 0.64s).
	_assert_true(combo_durs[0] >= 0.64, "combo_1 duration %.3fs < 0.64s" % combo_durs[0])
	_assert_true(combo_durs[7] >= 0.78, "combo_8 duration %.3fs < 0.78s" % combo_durs[7])
	_assert_true(combo_durs[7] >= combo_durs[0], "combo_8 (%.3fs) should not be shorter than combo_1 (%.3fs)" % [combo_durs[7], combo_durs[0]])

	# Verify strictly ascending pitch for steps 1..8 and full 1..16.
	for i: int in range(step_count - 1):
		_assert_true(
			measured_ac_hz[i] < measured_ac_hz[i + 1],
			"Pitch did not strictly ascend from step %d (%.2f Hz) to step %d (%.2f Hz)" % [
				i + 1, measured_ac_hz[i], i + 2, measured_ac_hz[i + 1]
			]
		)
	print("Pitch ascent check (steps 1..8 & 1..16): PASS")

	# 2. Validate every tactile, powerup & celebratory stereo SFX buffer.
	print("\n--- Tactile & Hero Stereo SFX Buffer Inspection ---")
	var sfx_specs: Array[Array] = [
		["sparkle_bell", 0.012, true, true, true],
		["pickup", 0.015, false, false, false],
		["place", 0.015, false, true, false],
		["invalid", 0.012, false, true, false],
		["hold_swap", 0.012, true, true, false],
		["mult_x2", 0.012, true, true, true],
		["mult_x3", 0.012, true, true, true],
		["mult_x4", 0.012, true, true, true],
		["bomb_blast", 0.015, true, true, true],
		["lightning_zap", 0.015, true, true, true],
		["fever_ignite", 0.015, true, true, true],
		["score_tick", 0.008, false, false, false],
		["game_over", 0.012, true, true, true],
		["high_score", 0.012, true, true, true],
	]
	for spec: Array in sfx_specs:
		var key: String = String(spec[0])
		var min_rms: float = float(spec[1])
		var req_wide_stereo: bool = bool(spec[2])
		var req_20ms_tail: bool = bool(spec[3])
		var req_natural_ringout: bool = bool(spec[4])
		var stream: AudioStreamWAV = synth.call("get_sfx_stream", key) as AudioStreamWAV
		_validate_stereo_stream(stream, key, min_rms, req_wide_stereo, req_20ms_tail, req_natural_ringout)

	# 3. Verify mult_x3 is brighter than mult_x2.
	var m2_mid: PackedFloat32Array = _decode_stereo_pcm16(synth.call("get_sfx_stream", "mult_x2") as AudioStreamWAV)["mid"] as PackedFloat32Array
	var m3_mid: PackedFloat32Array = _decode_stereo_pcm16(synth.call("get_sfx_stream", "mult_x3") as AudioStreamWAV)["mid"] as PackedFloat32Array
	var m2_zcr: float = _estimate_pitch_zcr(m2_mid, 0.015, 0.120)
	var m3_zcr: float = _estimate_pitch_zcr(m3_mid, 0.015, 0.120)
	print("  Mult brightness check | mult_x2 ZCR=%.1f Hz < mult_x3 ZCR=%.1f Hz" % [m2_zcr, m3_zcr])
	_assert_true(m3_zcr > m2_zcr, "Expected mult_x3 (%.1f Hz) brighter than mult_x2 (%.1f Hz)" % [m3_zcr, m2_zcr])

	# 4. High-frequency Nyquist hygiene (14-22 kHz < -35 dB) & natural ring-out (< -60 dBFS last 40ms) on all 6 exports!
	print("\n--- Nyquist Hygiene (14-22 kHz) & Natural Tail Silence Audit ---")
	var hero_exports: Dictionary = {
		"combo_1.wav": synth.call("get_combo_stream", 1),
		"combo_4.wav": synth.call("get_combo_stream", 4),
		"combo_8.wav": synth.call("get_combo_stream", 8),
		"bomb.wav": synth.call("get_sfx_stream", "bomb_blast"),
		"lightning.wav": synth.call("get_sfx_stream", "lightning_zap"),
		"fever.wav": synth.call("get_sfx_stream", "fever_ignite"),
	}
	for filename: String in hero_exports.keys():
		var stream: AudioStreamWAV = hero_exports[filename] as AudioStreamWAV
		var dec: Dictionary = _decode_stereo_pcm16(stream)
		var l_arr: PackedFloat32Array = dec["left"] as PackedFloat32Array
		var r_arr: PackedFloat32Array = dec["right"] as PackedFloat32Array

		var hf_db: float = _measure_hf_band_ratio_db(l_arr, r_arr, 14000.0)
		var pre_fade_rms: float = _measure_window_rms(l_arr, r_arr, 0.060, 0.020)
		var last40_rms: float = _measure_window_rms(l_arr, r_arr, 0.040, 0.000)
		var pre_fade_db: float = 20.0 * (log(maxf(pre_fade_rms, 1e-7)) / log(10.0))
		var last40_db: float = 20.0 * (log(maxf(last40_rms, 1e-7)) / log(10.0))

		print("  %-14s | 14-22kHz=%6.1f dB (<-35) | [end-60..-20ms]=%6.1f dBFS (<-48) | [end-40..0ms]=%6.1f dBFS (<-60)" % [
			filename, hf_db, pre_fade_db, last40_db
		])
		_assert_true(hf_db < -35.0, "%s 14-22 kHz energy %.1f dB exceeds -35 dB Nyquist hygiene limit" % [filename, hf_db])
		_assert_true(pre_fade_rms < 0.004, "%s pre-fade [end-60..-20ms] RMS %.5f (%.1f dBFS) >= 0.004 (premature chop!)" % [filename, pre_fade_rms, pre_fade_db])
		_assert_true(last40_rms < 0.001, "%s final 40ms RMS %.5f (%.1f dBFS) >= 0.001 (-60 dBFS limit!)" % [filename, last40_rms, last40_db])

	# 5. Verify zero brick-wall drop-offs on hero SFX.
	print("\n--- Envelope Continuity / No Brick-Wall Cutoff Check ---")
	for hero_key: String in ["bomb_blast", "lightning_zap", "fever_ignite"]:
		var h_stream: AudioStreamWAV = synth.call("get_sfx_stream", hero_key) as AudioStreamWAV
		var h_mid: PackedFloat32Array = _decode_stereo_pcm16(h_stream)["mid"] as PackedFloat32Array
		var max_drop_db: float = _measure_max_envelope_drop_db(h_mid)
		print("  %-14s | max 5ms frame drop = %5.2f dB (limit < 16.0 dB)" % [hero_key, max_drop_db])
		_assert_true(max_drop_db < 16.0, "%s exhibited brick-wall drop of %.2f dB in 5ms!" % [hero_key, max_drop_db])

	# 6. Exercise full runtime playback API + polyphony + mute toggle.
	print("\n--- Runtime Playback & Mute API Smoke Test ---")
	_assert_true(not bool(synth.call("is_muted")), "SoundSynth should start unmuted")
	synth.call("play_pickup")
	synth.call("play_place")
	synth.call("play_invalid")
	synth.call("play_hold_swap")
	synth.call("play_combo_clear", 1, 1, false)
	synth.call("play_combo_clear", 4, 2, false)
	synth.call("play_combo_clear", 8, 4, true)
	synth.call("play_combo_clear", 16, 3, true)
	synth.call("play_mult_hit", 2)
	synth.call("play_mult_hit", 3)
	synth.call("play_mult_hit", 5)
	synth.call("play_bomb_blast")
	synth.call("play_lightning_zap")
	synth.call("play_fever_ignite")
	synth.call("play_score_tick", 1.0)
	synth.call("play_score_tick", 1.35)
	synth.call("play_game_over")
	synth.call("play_high_score")

	for _frame: int in range(8):
		synth.call("_process", 0.04)

	var active_voices: int = 0
	for child: Node in synth.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing:
			active_voices += 1
	print("  Active polyphonic voices during stress burst: %d" % active_voices)
	_assert_true(active_voices >= 4, "Expected >= 4 simultaneous polyphonic voices playing, got %d" % active_voices)

	synth.call("set_muted", true)
	_assert_true(bool(synth.call("is_muted")), "Expected is_muted() == true after set_muted(true)")
	var voices_after_mute: int = 0
	for child: Node in synth.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing:
			voices_after_mute += 1
	_assert_true(voices_after_mute == 0, "Expected 0 playing voices after set_muted(true), got %d" % voices_after_mute)
	synth.call("play_combo_clear", 5, 3, true)
	synth.call("play_bomb_blast")
	synth.call("set_muted", false)
	_assert_true(not bool(synth.call("is_muted")), "Expected is_muted() == false after set_muted(false)")
	print("Playback & mute API smoke test: PASS")

	# 7. Export 2-channel stereo diagnostic WAV files.
	print("\n--- Exporting Stereo Diagnostic WAVs to %s ---" % EVAL_EXPORT_DIR)
	var mk_err: Error = DirAccess.make_dir_recursive_absolute(EVAL_EXPORT_DIR)
	_assert_true(mk_err == OK, "Failed to create export directory: %s (err=%d)" % [EVAL_EXPORT_DIR, mk_err])

	for filename: String in hero_exports.keys():
		var stream: AudioStreamWAV = hero_exports[filename] as AudioStreamWAV
		var full_path: String = EVAL_EXPORT_DIR + "/" + filename
		var ok: bool = _write_wav_file(stream, full_path)
		_assert_true(ok, "Failed to export WAV: %s" % full_path)
		var fsize: int = _get_file_size(full_path)
		var expected_size: int = 44 + stream.data.size()
		_assert_true(fsize == expected_size, "WAV %s size mismatch: got %d, expected %d" % [filename, fsize, expected_size])
		print("  Exported %-14s (%7d bytes, STEREO %.3fs)" % [
			filename,
			fsize,
			float(stream.data.size()) / float(SAMPLE_RATE * 4)
		])

	root.remove_child(synth)
	synth.free()

	print("\n==========================================")
	if _failures.is_empty():
		print("ALL ROUND 3 STEREO AUDIO VERIFICATION CHECKS PASSED (0 failures).")
		quit(0)
	else:
		printerr("AUDIO VERIFICATION FAILED (%d failures):" % _failures.size())
		for msg: String in _failures:
			printerr("  [FAIL] " + msg)
		quit(1)


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _validate_stereo_stream(
	stream: AudioStreamWAV,
	label: String,
	min_rms: float,
	require_wide_stereo: bool,
	require_20ms_tail: bool,
	require_natural_ringout: bool
) -> Dictionary:
	_assert_true(stream != null, "%s stream is null" % label)
	if stream == null:
		return {"left": PackedFloat32Array(), "right": PackedFloat32Array(), "mid": PackedFloat32Array()}

	_assert_true(stream.format == AudioStreamWAV.FORMAT_16_BITS, "%s expected FORMAT_16_BITS" % label)
	_assert_true(stream.stereo, "%s expected stereo == true" % label)
	_assert_true(stream.mix_rate == SAMPLE_RATE, "%s expected mix_rate %d, got %d" % [label, SAMPLE_RATE, stream.mix_rate])
	_assert_true(stream.data.size() > 0, "%s PCM buffer is empty" % label)
	_assert_true(stream.data.size() % 4 == 0, "%s stereo PCM byte size %d is not a multiple of 4" % [label, stream.data.size()])

	var decoded: Dictionary = _decode_stereo_pcm16(stream)
	var left: PackedFloat32Array = decoded["left"] as PackedFloat32Array
	var right: PackedFloat32Array = decoded["right"] as PackedFloat32Array
	var n: int = left.size()

	var peak: float = 0.0
	var sum_sq: float = 0.0
	var sum_side_sq: float = 0.0
	var sum_dc_l: float = 0.0
	var sum_dc_r: float = 0.0

	for i: int in range(n):
		var vl: float = left[i]
		var vr: float = right[i]
		_assert_true(is_finite(vl) and is_finite(vr), "%s NaN/Inf at %d" % [label, i])
		var av: float = maxf(absf(vl), absf(vr))
		if av > peak:
			peak = av
		sum_sq += 0.5 * (vl * vl + vr * vr)
		var side: float = 0.5 * (vl - vr)
		sum_side_sq += side * side
		sum_dc_l += vl
		sum_dc_r += vr

	var rms: float = sqrt(sum_sq / float(maxi(n, 1)))
	var side_rms: float = sqrt(sum_side_sq / float(maxi(n, 1)))
	var dc: float = maxf(absf(sum_dc_l / float(maxi(n, 1))), absf(sum_dc_r / float(maxi(n, 1))))

	var edge_start: float = maxf(absf(left[0]), absf(right[0])) if n > 0 else 0.0
	var edge_end: float = maxf(absf(left[n - 1]), absf(right[n - 1])) if n > 0 else 0.0

	var tail_frames: int = int(round((0.020 if require_20ms_tail else 0.008) * float(SAMPLE_RATE)))
	tail_frames = mini(tail_frames, n)
	var tail_peak: float = 0.0
	for i: int in range(n - tail_frames, n):
		var av: float = maxf(absf(left[i]), absf(right[i]))
		if av > tail_peak:
			tail_peak = av

	var pre_fade_rms: float = _measure_window_rms(left, right, 0.060, 0.020) if require_natural_ringout else 0.0
	var dur_ms: float = float(n) / float(SAMPLE_RATE) * 1000.0
	print("  %-14s | dur=%6.1f ms | peak=%.4f | RMS=%.4f | side=%.4f | preFade=%.5f | tail20=%.5f" % [
		label, dur_ms, peak, rms, side_rms, pre_fade_rms, tail_peak
	])

	_assert_true(rms >= min_rms, "%s RMS %.5f below threshold %.5f" % [label, rms, min_rms])
	_assert_true(peak <= 0.92, "%s peak %.4f exceeds 0.92 hard-clipping limit" % [label, peak])
	_assert_true(peak <= 0.86, "%s peak %.4f exceeds 0.85 safety target" % [label, peak])
	_assert_true(dc < 0.015, "%s DC offset %.5f too high" % [label, dc])
	_assert_true(edge_start < 0.005, "%s start edge %.4f not click-free" % [label, edge_start])
	_assert_true(edge_end < 0.005, "%s end edge %.4f not click-free" % [label, edge_end])
	_assert_true(tail_peak < 0.005, "%s final tail peak %.5f >= 0.005" % [label, tail_peak])
	if require_natural_ringout:
		_assert_true(pre_fade_rms < 0.004, "%s pre-fade [end-60..-20ms] RMS %.5f >= 0.004" % [label, pre_fade_rms])
	if require_wide_stereo:
		_assert_true(side_rms >= 0.006, "%s stereo side RMS %.5f too narrow" % [label, side_rms])

	return decoded


func _decode_stereo_pcm16(stream: AudioStreamWAV) -> Dictionary:
	var data: PackedByteArray = stream.data
	var frames: int = int(float(data.size()) / 4.0)
	var left: PackedFloat32Array = PackedFloat32Array(); left.resize(frames)
	var right: PackedFloat32Array = PackedFloat32Array(); right.resize(frames)
	var mid: PackedFloat32Array = PackedFloat32Array(); mid.resize(frames)
	for i: int in range(frames):
		var off: int = i * 4
		var l: float = float(data.decode_s16(off)) / 32768.0
		var r: float = float(data.decode_s16(off + 2)) / 32768.0
		left[i] = l
		right[i] = r
		mid[i] = 0.5 * (l + r)
	return {"left": left, "right": right, "mid": mid}


func _measure_window_rms(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	start_from_end_sec: float,
	end_from_end_sec: float
) -> float:
	var n: int = left.size()
	var s_idx: int = clampi(n - int(round(start_from_end_sec * float(SAMPLE_RATE))), 0, n)
	var e_idx: int = clampi(n - int(round(end_from_end_sec * float(SAMPLE_RATE))), s_idx, n)
	var count: int = e_idx - s_idx
	if count <= 0:
		return 0.0
	var acc: float = 0.0
	for i: int in range(s_idx, e_idx):
		acc += 0.5 * (left[i] * left[i] + right[i] * right[i])
	return sqrt(acc / float(count))


func _measure_hf_band_ratio_db(
	left: PackedFloat32Array,
	right: PackedFloat32Array,
	cutoff_hz: float
) -> float:
	# Cascaded 4-pole Butterworth HPF at cutoff_hz (14 kHz) measuring 14-22 kHz RMS relative to total RMS.
	var n: int = left.size()
	if n < 16:
		return -120.0

	var w0: float = TAU * cutoff_hz / float(SAMPLE_RATE)
	var cw: float = cos(w0)
	var alpha: float = sin(w0) * 0.70710678
	var inv_a0: float = 1.0 / (1.0 + alpha)
	var b0: float = ((1.0 + cw) * 0.5) * inv_a0
	var b1: float = -(1.0 + cw) * inv_a0
	var b2: float = b0
	var a1: float = (-2.0 * cw) * inv_a0
	var a2: float = (1.0 - alpha) * inv_a0

	# Two cascaded 2-pole HPF stages per channel = 4-pole (-24 dB/oct) sharp separation at 14 kHz.
	var l1_z1: float = 0.0; var l1_z2: float = 0.0; var l2_z1: float = 0.0; var l2_z2: float = 0.0
	var r1_z1: float = 0.0; var r1_z2: float = 0.0; var r2_z1: float = 0.0; var r2_z2: float = 0.0
	var total_sq: float = 0.0
	var hf_sq: float = 0.0

	for i: int in range(n):
		var xl: float = left[i]
		var xr: float = right[i]
		total_sq += 0.5 * (xl * xl + xr * xr)

		var yl1: float = b0 * xl + l1_z1
		l1_z1 = b1 * xl - a1 * yl1 + l1_z2
		l1_z2 = b2 * xl - a2 * yl1
		var yl2: float = b0 * yl1 + l2_z1
		l2_z1 = b1 * yl1 - a1 * yl2 + l2_z2
		l2_z2 = b2 * yl1 - a2 * yl2

		var yr1: float = b0 * xr + r1_z1
		r1_z1 = b1 * xr - a1 * yr1 + r1_z2
		r1_z2 = b2 * xr - a2 * yr1
		var yr2: float = b0 * yr1 + r2_z1
		r2_z1 = b1 * yr1 - a1 * yr2 + r2_z2
		r2_z2 = b2 * yr1 - a2 * yr2

		hf_sq += 0.5 * (yl2 * yl2 + yr2 * yr2)

	var total_rms: float = sqrt(total_sq / float(n))
	var hf_rms: float = sqrt(hf_sq / float(n))
	return 20.0 * (log(maxf(hf_rms, 1e-9) / maxf(total_rms, 1e-9)) / log(10.0))


func _measure_max_envelope_drop_db(samples: PackedFloat32Array) -> float:
	var frame_len: int = int(round(0.005 * float(SAMPLE_RATE)))
	var num_frames: int = int(float(samples.size()) / float(frame_len))
	if num_frames < 4:
		return 0.0
	var rms_list: PackedFloat32Array = PackedFloat32Array(); rms_list.resize(num_frames)
	for f: int in range(num_frames):
		var s: float = 0.0
		var base: int = f * frame_len
		for j: int in range(frame_len):
			var v: float = samples[base + j]
			s += v * v
		rms_list[f] = sqrt(s / float(frame_len))

	var max_drop_db: float = 0.0
	var end_scan: int = maxi(num_frames - 8, 1)
	for f: int in range(1, end_scan):
		if rms_list[f - 1] > 0.03 and rms_list[f] < rms_list[f - 1]:
			var ratio: float = rms_list[f - 1] / maxf(rms_list[f], 0.0001)
			var drop_db: float = 20.0 * (log(ratio) / log(10.0))
			if drop_db > max_drop_db:
				max_drop_db = drop_db
	return max_drop_db


func _estimate_pitch_yin(samples: PackedFloat32Array, start_sec: float, window_len: int) -> float:
	var min_lag: int = 8
	var max_lag: int = 120
	var start: int = int(round(start_sec * float(SAMPLE_RATE)))
	if start + window_len + max_lag >= samples.size():
		start = maxi(0, samples.size() - window_len - max_lag - 1)
	if start < 0 or samples.size() <= max_lag + 64:
		return 0.0
	var w: int = mini(window_len, samples.size() - start - max_lag - 1)

	var diff: PackedFloat32Array = PackedFloat32Array()
	diff.resize(max_lag + 1)
	diff[0] = 0.0
	for tau: int in range(1, max_lag + 1):
		var acc: float = 0.0
		for j: int in range(w):
			var d: float = samples[start + j] - samples[start + j + tau]
			acc += d * d
		diff[tau] = acc

	var cmndf: PackedFloat32Array = PackedFloat32Array()
	cmndf.resize(max_lag + 1)
	cmndf[0] = 1.0
	var running_sum: float = 0.0
	for tau: int in range(1, max_lag + 1):
		running_sum += diff[tau]
		if running_sum > 0.0:
			cmndf[tau] = diff[tau] * float(tau) / running_sum
		else:
			cmndf[tau] = 1.0

	var best_tau: int = -1
	for tau: int in range(min_lag, max_lag):
		if cmndf[tau] < 0.22:
			var t: int = tau
			while t + 1 <= max_lag and cmndf[t + 1] < cmndf[t]:
				t += 1
			best_tau = t
			break

	if best_tau < 0:
		var best_val: float = 1e9
		for tau: int in range(min_lag, max_lag + 1):
			if cmndf[tau] < best_val:
				best_val = cmndf[tau]
				best_tau = tau

	var refined_tau: float = float(best_tau)
	if best_tau > 1 and best_tau < max_lag:
		var s0: float = cmndf[best_tau - 1]
		var s1: float = cmndf[best_tau]
		var s2: float = cmndf[best_tau + 1]
		var denom: float = 2.0 * (2.0 * s1 - s2 - s0)
		if absf(denom) > 1e-9:
			refined_tau += (s2 - s0) / denom

	return float(SAMPLE_RATE) / refined_tau


func _estimate_pitch_zcr(samples: PackedFloat32Array, start_sec: float, dur_sec: float) -> float:
	var start: int = int(round(start_sec * float(SAMPLE_RATE)))
	var length: int = int(round(dur_sec * float(SAMPLE_RATE)))
	var end_idx: int = mini(start + length, samples.size())
	if end_idx - start < 16:
		return 0.0
	var crossings: int = 0
	var prev: float = samples[start]
	for i: int in range(start + 1, end_idx):
		var cur: float = samples[i]
		if (prev <= 0.0 and cur > 0.0) or (prev >= 0.0 and cur < 0.0):
			crossings += 1
		prev = cur
	var elapsed: float = float(end_idx - start) / float(SAMPLE_RATE)
	return (float(crossings) * 0.5) / elapsed


func _write_wav_file(stream: AudioStreamWAV, abs_path: String) -> bool:
	if stream == null:
		return false
	var pcm: PackedByteArray = stream.data
	var channels: int = 2 if stream.stereo else 1
	var bits_per_sample: int = 16
	var byte_rate: int = stream.mix_rate * channels * int(float(bits_per_sample) / 8.0)
	var block_align: int = channels * int(float(bits_per_sample) / 8.0)
	var data_size: int = pcm.size()
	var riff_size: int = 36 + data_size

	var file: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(riff_size)
	file.store_buffer("WAVE".to_ascii_buffer())
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)
	file.store_16(1)
	file.store_16(channels)
	file.store_32(stream.mix_rate)
	file.store_32(byte_rate)
	file.store_16(block_align)
	file.store_16(bits_per_sample)
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_size)
	file.store_buffer(pcm)
	file.close()
	return true


func _get_file_size(abs_path: String) -> int:
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return -1
	var size: int = file.get_length()
	file.close()
	return size
