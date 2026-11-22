shader_type canvas_item;

// Ultra-lightweight mobile-cool background shader for Kombo.
// Zero per-pixel trig loops — renders a silky deep-indigo radial gradient
// that shifts smoothly with combo/FEVER heat & pulse at <5% GPU fragment cost.

uniform vec4 color_deep : source_color = vec4(0.035, 0.055, 0.153, 1.0);   // #090E27
uniform vec4 color_mid : source_color = vec4(0.094, 0.145, 0.369, 1.0);    // #18255E
uniform vec4 color_accent : source_color = vec4(0.165, 0.259, 0.596, 1.0); // #2A4298
uniform vec4 color_fever : source_color = vec4(0.60, 0.13, 0.27, 1.0);     // Warm crimson-magenta FEVER tint
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.0, 4.0) = 0.65;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV - vec2(0.5, 0.46);
	p.y *= 1.7778;
	float r2 = dot(p, p);

	float center_glow = clamp(1.0 - r2 * 0.85, 0.0, 1.0);
	float diag_wave = clamp(0.5 + 0.35 * (p.x * 0.7 - p.y * 0.45), 0.0, 1.0);

	vec3 calm_mid = mix(color_deep.rgb, color_mid.rgb, center_glow);
	vec3 calm_acc = mix(calm_mid, color_accent.rgb, center_glow * diag_wave * 0.55);

	vec3 fever_mid = mix(vec3(0.09, 0.03, 0.12), color_fever.rgb, center_glow);
	vec3 col = mix(calm_acc, fever_mid, heat * 0.68);
	col += vec3(0.10, 0.14, 0.28) * (pulse * center_glow);

	float vig = clamp(1.10 - r2 * 0.42, 0.42, 1.0);
	COLOR = vec4(col * vig, 1.0);
}
