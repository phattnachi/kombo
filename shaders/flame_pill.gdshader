shader_type canvas_item;

// Kombo Round 2 — Balatro-inspired seamless melted roaring pill flames.
// Overlays the pill's top lip (UV.y = 0.76..1.0) so the pill body literally melts
// upward into tall, sharp, jagged multi-tongue fire with a blazing white-hot core
// and rising detached ember sparks — ZERO dark seam, ZERO rectangular clipping,
// and strictly invisible when intensity <= 0.001.

uniform vec4 base_color : source_color = vec4(0.95, 0.18, 0.14, 1.0);
uniform vec4 outer_color : source_color = vec4(1.0, 0.34, 0.08, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.93, 0.38, 1.0);
uniform float intensity : hint_range(0.0, 1.5) = 0.0;
uniform float flame_speed = 3.4;
uniform float seed_offset = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float flame_fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.54;
	mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p = rot * p * 2.06 + vec2(2.3, 9.1);
		amp *= 0.48;
	}
	return v;
}

void fragment() {
	if (intensity <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		// y_up = 0.0 at bottom of flame rect (inside pill upper face), 1.0 at top.
		// Pill top lip sits around y_up = 0.226 (14px into 62px tall rect).
		float y_up = 1.0 - UV.y;
		float x_c = (UV.x - 0.5) * 2.0; // -1.0 .. +1.0
		float norm_i = clamp(intensity, 0.0, 1.5);
		float heat_t = clamp(norm_i / 1.45, 0.0, 1.0);
		float t = TIME * flame_speed + seed_offset;

		// Rising height normalized above the pill's top lip.
		float h = clamp((y_up - 0.16) / 0.84, 0.0, 1.0);

		// Dynamic lateral whip & flame curl (grows stronger toward jagged tips).
		float sway_n = flame_fbm(vec2(x_c * 1.55 + seed_offset * 0.7, y_up * 1.85 - t * 0.92)) - 0.5;
		float curl_n = (value_noise(vec2(x_c * 3.8 + 4.1, y_up * 3.4 - t * 1.65)) - 0.5) * 0.24;
		float sway = (sway_n * (0.48 + 0.24 * heat_t) + curl_n) * smoothstep(0.04, 0.75, h);
		float xw = x_c + sway;

		// Vertically-stretched turbulent fire noise for sharp upward-licking forks.
		float n_main  = flame_fbm(vec2(xw * 2.85 + seed_offset, y_up * 1.65 - t * 1.28));
		float n_sharp = flame_fbm(vec2(xw * 6.40 + 7.3 - seed_offset, y_up * 2.95 - t * 2.15));
		float n_flick = value_noise(vec2(xw * 10.5 + 2.7, y_up * 4.60 - t * 2.85));
		float turb = n_main * 0.50 + n_sharp * 0.34 + n_flick * 0.16;

		// Sharp ridged multi-tongue crown (deep valleys prevent blobby flat tops!).
		float tongue_a = pow(abs(sin(xw * 4.4 + t * 1.7 + n_main * 1.8)), 0.75);
		float tongue_b = pow(abs(sin(xw * 7.8 - t * 2.5 + n_sharp * 2.1)), 0.85);
		float tongue_c = pow(abs(cos(xw * 11.4 + t * 3.1 - n_main * 1.4)), 1.1);
		float ridges = (tongue_a * 0.48 + tongue_b * 0.34 + tongue_c * 0.18) - 0.52;

		// Horizontal confinement:
		// Below pill top lip (y_up < 0.24), stay strictly inside pill width (0.885) so zero fire leaks sideways.
		// Above pill lip, allow wild licking tongues to flare slightly outward while tapering into forks.
		float pill_half_w = 0.885;
		float base_corner = smoothstep(0.0, 0.14, y_up);
		float allowed_w = mix(pill_half_w - (1.0 - base_corner) * 0.04, mix(0.92, 0.64, pow(h, 1.05)), smoothstep(0.14, 0.30, y_up));
		float x_dist = abs(x_c + sway * smoothstep(0.16, 0.45, y_up) * 0.34);
		float x_mask = 1.0 - smoothstep(allowed_w * 0.72, allowed_w + 0.05, x_dist);

		// Strict soft boundary guard so no flame tip ever clips flat against rect edges.
		float edge_guard = smoothstep(1.0, 0.89, y_up) * smoothstep(1.0, 0.88, abs(x_c));

		// Flame vertical reach scales cleanly from medium Combo roar to towering FEVER inferno.
		float reach = clamp(0.32 + norm_i * 0.43, 0.32, 0.94);
		float v_falloff = 1.0 - pow(h / max(reach, 0.01), 0.92);

		// Solid molten root strictly along the pill top lip (y_up = 0.10 .. 0.32) for 100% seamless melt.
		float root_width = 1.0 - smoothstep(pill_half_w - 0.05, pill_half_w + 0.01, abs(x_c));
		float lip_anchor = smoothstep(0.02, 0.16, y_up) * (1.0 - smoothstep(0.22, 0.42, y_up)) * root_width;

		// Scalar fire potential field with sharp valley carving at upper heights.
		float ridge_boost = ridges * (0.58 + 0.24 * heat_t) * smoothstep(0.05, 0.55, h);
		float field = (v_falloff * 0.78 + (turb - 0.36) * 1.38 + ridge_boost) * x_mask * edge_guard;
		field = max(field, lip_anchor * (0.68 + 0.24 * heat_t));

		// Smooth melt-out into the pill face below y_up = 0.16 so there is zero sharp horizontal line inside the pill.
		float bottom_melt = smoothstep(0.02, 0.17, y_up);
		float pill_clip_below = mix(root_width, 1.0, smoothstep(0.18, 0.26, y_up));

		// Razor-crisp Balatro stepped graphic fire bands (zero murky smoke!).
		float outer_mask = smoothstep(0.21, 0.248, field) * bottom_melt * pill_clip_below;
		float mid_mask   = smoothstep(0.38, 0.43, field) * bottom_melt * pill_clip_below;
		float core_mask  = smoothstep(0.56, 0.62, field) * smoothstep(0.06, 0.20, y_up) * pill_clip_below;

		// Blazing incandescent white-hot heart right at the melted lip & rising center tongues!
		float center_focus = 1.0 - smoothstep(0.28, 0.82, abs(x_c));
		float hot_height = smoothstep(mix(0.42, 0.68, heat_t), 0.12, h);
		float hot_mask = smoothstep(0.68 - 0.12 * heat_t, 0.76 - 0.10 * heat_t, field) * hot_height * (0.65 + 0.35 * center_focus) * smoothstep(0.08, 0.21, y_up) * pill_clip_below;

		// Vivid detached rising ember sparks & flying fire droplets popping above the tongues!
		float spark_zone = smoothstep(0.24, 0.54, h) * smoothstep(0.96, 0.74, y_up) * (1.0 - smoothstep(0.60, 0.94, abs(x_c))) * edge_guard;
		float spark_grid_a = value_noise(vec2(xw * 12.5 + 17.3 + seed_offset, y_up * 11.0 - t * 2.9));
		float spark_grid_b = value_noise(vec2(xw * 18.5 - 8.1 + seed_offset * 1.4, y_up * 15.0 - t * 3.7));
		float spark_thresh = mix(0.875, 0.805, heat_t);
		float spark_a = smoothstep(spark_thresh, spark_thresh + 0.025, spark_grid_a * (0.58 + 0.60 * spark_zone));
		float spark_b = smoothstep(spark_thresh + 0.015, spark_thresh + 0.038, spark_grid_b * (0.54 + 0.66 * spark_zone));
		float spark_mask = max(spark_a, spark_b) * smoothstep(0.25, 0.65, norm_i);

		float combined_alpha = max(outer_mask, spark_mask);

		// Hyper-vivid 4-band Balatro palette:
		// Lower base matches pill base_color seamlessly -> outer_color -> mid -> core -> white-hot!
		vec3 root_outer = mix(base_color.rgb, outer_color.rgb, smoothstep(0.12, 0.38, y_up));
		vec3 vivid_outer = root_outer * 1.06;
		vec3 mid_tone = mix(outer_color.rgb, core_color.rgb, 0.52);
		vec3 white_hot = mix(core_color.rgb, vec3(1.0, 1.0, 0.97), 0.84);

		vec3 col = vivid_outer;
		col = mix(col, mid_tone, mid_mask);
		col = mix(col, core_color.rgb, core_mask);
		col = mix(col, white_hot, hot_mask);

		// Sparks glow blazing bright core-to-white!
		vec3 spark_col = mix(core_color.rgb, white_hot, 0.55);
		col = mix(col, spark_col, spark_mask * (1.0 - outer_mask));

		// Subtle FEVER brilliance surge.
		col *= 1.0 + clamp(norm_i - 0.85, 0.0, 0.65) * 0.20;

		float intensity_fade = smoothstep(0.0, 0.14, norm_i);
		float final_alpha = combined_alpha * intensity_fade * outer_color.a * COLOR.a;

		COLOR = vec4(col, final_alpha);
	}
}
