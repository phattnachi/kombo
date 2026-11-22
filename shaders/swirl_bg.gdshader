shader_type canvas_item;

// Mobile-optimized smooth Balatro swirl shader for Kombo.
// Uses direct 2x2 rotation matrix (zero atan/exp/pow) with 2-octave fold
// for crisp, velvety deep-indigo waves at minimal mobile GPU cost.

uniform vec4 color_deep : source_color = vec4(0.035, 0.055, 0.153, 1.0);   // #090E27
uniform vec4 color_mid : source_color = vec4(0.094, 0.145, 0.369, 1.0);    // #18255E
uniform vec4 color_accent : source_color = vec4(0.165, 0.259, 0.596, 1.0); // #2A4298
uniform vec4 color_fever : source_color = vec4(0.60, 0.13, 0.27, 1.0);     // Warm crimson-magenta FEVER tint
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.0, 4.0) = 0.65;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV - vec2(0.5, 0.48);
	p.y *= 1.7778;

	float r2 = dot(p, p);
	float t = TIME * (0.20 + speed * 0.16 + heat * 0.24);

	float twist = (1.55 + heat * 0.85) / (1.0 + r2 * 1.15) - t * 0.26;
	float s_tw = sin(twist);
	float c_tw = cos(twist);
	vec2 q = vec2(p.x * c_tw - p.y * s_tw, p.x * s_tw + p.y * c_tw) * 2.15;

	q += 0.45 * vec2(cos(q.y * 1.35 + t * 0.85), sin(q.x * 1.35 - t * 0.75));
	q += 0.24 * vec2(cos(q.y * 2.10 + t * 1.10), sin(q.x * 2.10 - t * 0.95));

	float wave = sin(q.x * 1.25 + sin(q.y * 1.20 + t)) * cos(q.y * 1.15 - cos(q.x * 1.10 - t * 0.7));
	float ribbon = smoothstep(-0.62, 0.68, wave);
	float fold = clamp(1.0 - abs(wave + 0.12 * sin(q.x - q.y + t)), 0.0, 1.0);
	float f2 = fold * fold;
	float crest = f2 * f2 * 0.42;

	vec3 calm_col = mix(color_deep.rgb, color_mid.rgb, ribbon);
	calm_col = mix(calm_col, color_accent.rgb, crest);

	vec3 fever_base = mix(vec3(0.09, 0.03, 0.12), color_fever.rgb, ribbon);
	vec3 fever_col = mix(fever_base, vec3(0.88, 0.34, 0.16), crest * 1.35);

	vec3 col = mix(calm_col, fever_col, heat * 0.68);
	float center_glow = 1.0 / (1.0 + r2 * 2.3);
	col += vec3(0.09, 0.13, 0.28) * (pulse * center_glow);

	float vig = clamp(1.12 - r2 * 0.44, 0.38, 1.0);
	COLOR = vec4(col * vig, 1.0);
}
