shader_type canvas_item;

// Kombo — Balatro-inspired organic domain-warped marbled fluid swirl background.
// Transitions seamlessly across Calm (0.0), Combo Heat (0.5), and FEVER (1.0),
// with reactive clear-pulse luminescence and a studio vignette framing the 8x8 board.

uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.1, 4.0) = 0.6;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	// Aspect-corrected coordinates so fluid swirls stay isotropic on portrait 540x960 screens.
	float aspect = clamp(SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.0001), 0.35, 3.0);
	vec2 centered = UV - vec2(0.5, 0.5);
	vec2 p = vec2(centered.x * aspect, centered.y);

	float t = TIME * speed * (1.0 + heat * 0.78);
	float pulse_c = clamp(pulse, 0.0, 1.0);

	// Polar vortex twist around a gently breathing off-center eye (Balatro paint vortex feel).
	vec2 eye = vec2(0.06 * sin(t * 0.31), -0.05 + 0.05 * cos(t * 0.23));
	vec2 dp = p - eye;
	float r = length(dp);
	float ang = atan(dp.y, dp.x);
	float swirl_twist = (2.15 + heat * 0.95 + pulse_c * 0.25) * exp(-r * 1.15) - t * 0.18;
	vec2 uv = vec2(cos(ang + swirl_twist), sin(ang + swirl_twist)) * (r * 3.15);

	// Iterative Balatro-style organic marbled paint folding (5 lightweight trig steps).
	vec2 uv2 = vec2(uv.x + uv.y, uv.y - uv.x);
	float mt = t * 0.55;
	for (int i = 0; i < 5; i++) {
		uv2 += sin(max(uv.x, uv.y)) + uv * 0.52;
		uv += 0.52 * vec2(
			cos(5.112 + 0.42 * uv2.y + mt * 0.34),
			sin(0.42 * uv2.x - mt * 0.28)
		);
		uv -= 0.44 * vec2(
			cos(uv.x + uv.y),
			sin(uv.x * 0.711 - uv.y)
		);
	}

	// Marbled 3-band paint contrast + crisp glowing energy shear veins.
	float paint_len = length(uv);
	float wave_a = 0.5 + 0.5 * sin(paint_len * 1.18 - mt * 0.42 + 0.45 * cos(uv.x - uv.y));
	float wave_b = 0.5 + 0.5 * cos(uv.x * 0.92 + uv.y * 0.78 + mt * 0.26);

	float c1p = clamp(smoothstep(0.14, 0.72, wave_a * 0.72 + wave_b * 0.28), 0.0, 1.0);
	float c2p = clamp(smoothstep(0.48, 0.94, wave_a * 0.65 + wave_b * 0.35), 0.0, 1.0);

	// Sharp silk energy veins tracing the fluid fold ridges.
	float fold_crease = abs(sin(uv.x * 0.85 - uv.y * 0.78 + mt * 0.20));
	float vein_mask = pow(1.0 - fold_crease, 5.2);

	// --- 3-Stage Color Palettes ---
	// Calm (heat = 0.0): Luminous vibrant royal sapphire-cobalt swirl so dark recessed 8x8 board pops cleanly!
	vec3 calm_dark   = vec3(0.1180, 0.1920, 0.4980); // #1E317F
	vec3 calm_mid    = vec3(0.1725, 0.2863, 0.6902); // #2C49B0
	vec3 calm_bright = vec3(0.2431, 0.3882, 0.8471); // #3E63D8
	vec3 calm_vein   = vec3(0.4157, 0.6078, 0.9882); // Silky sky-cerulean sheen highlight

	// Combo Heat (heat = 0.5): Electric indigo-violet with vivid cyan energy veins (#241C6E, #3B289E, #184C8F)
	vec3 combo_dark   = vec3(0.1059, 0.0784, 0.3412); // Deep indigo trough
	vec3 combo_mid    = vec3(0.1412, 0.1098, 0.4314); // #241C6E
	vec3 combo_bright = vec3(0.2314, 0.1569, 0.6196); // #3B289E
	vec3 combo_cyan   = vec3(0.0941, 0.2980, 0.5608); // #184C8F
	vec3 combo_vein   = vec3(0.1451, 0.7804, 0.9804); // Electric cyan energy vein

	// FEVER (heat = 1.0): Molten crimson, burnt orange, deep obsidian (#1D0A1A, #8C1626, #D93D1A)
	vec3 fever_dark   = vec3(0.1137, 0.0392, 0.1020); // #1D0A1A
	vec3 fever_mid    = vec3(0.5490, 0.0863, 0.1490); // #8C1626
	vec3 fever_bright = vec3(0.8510, 0.2392, 0.1020); // #D93D1A
	vec3 fever_vein   = vec3(1.0000, 0.6275, 0.1804); // Molten solar-orange crest

	float h_low  = smoothstep(0.0, 0.5, heat);
	float h_high = smoothstep(0.5, 1.0, heat);

	// Blend cyan pools subtly into combo heat midtones as well as sharp cyan veins.
	vec3 combo_mid_rich = mix(combo_mid, combo_cyan, smoothstep(0.35, 0.85, wave_b) * 0.55);

	vec3 col_dark   = mix(mix(calm_dark,   combo_dark,     h_low), fever_dark,   h_high);
	vec3 col_mid    = mix(mix(calm_mid,    combo_mid_rich, h_low), fever_mid,    h_high);
	vec3 col_bright = mix(mix(calm_bright, combo_bright,   h_low), fever_bright, h_high);
	vec3 col_vein   = mix(mix(calm_vein,   combo_vein,     h_low), fever_vein,   h_high);

	// Marbled 3-stop blend with velvety trough depth.
	vec3 col = mix(col_dark, col_mid, c1p);
	col = mix(col, col_bright, c2p * 0.92);

	// Glowing energy veins along swirl creases (amplified in Combo Heat, FEVER, and clear pulse).
	float combo_peak = sin(clamp(heat, 0.0, 1.0) * 3.14159265); // Peaks cleanly at heat = 0.5
	float vein_power = 0.20 + combo_peak * 0.42 + h_high * 0.28 + pulse_c * 0.52;
	col = mix(col, col_vein, clamp(vein_mask * vein_power, 0.0, 0.90));

	// Clear-pulse luminescence bloom radiating behind the 8x8 center board.
	float center_bloom = exp(-dot(centered * vec2(1.15, 0.95), centered * vec2(1.15, 0.95)) * 3.4);
	col += col_vein * (pulse_c * 0.28 * (0.40 + 0.60 * center_bloom + 0.50 * vein_mask));

	// Studio vignette: gentle framing when calm (preserves bright figure-ground board pop!), richer during FEVER.
	vec2 vig_uv = centered * vec2(1.12, 1.05);
	float vignette = 1.0 - smoothstep(0.22, 0.82, dot(vig_uv, vig_uv)) * (0.22 + heat * 0.14);
	col *= vignette;

	// Micro anti-banding dither.
	col += (hash12(FRAGCOORD.xy) - 0.5) / 255.0;

	COLOR = vec4(clamp(col, 0.0, 1.0), COLOR.a);
}
