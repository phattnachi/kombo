shader_type canvas_item;

// Kombo — Diagonal glossy jewel sheen sweep + soft outer aura pulse.
// Built for special blocks (Bomb, Lightning), multiplier badges, and glowing HUD accents.

uniform vec4 glow_color : source_color = vec4(1.0, 0.86, 0.30, 1.0);
uniform float pulse_speed : hint_range(0.2, 8.0) = 2.4;
uniform float pulse_strength : hint_range(0.0, 1.5) = 0.62;
uniform float sheen_speed : hint_range(0.2, 5.0) = 1.25;
uniform float sheen_width : hint_range(0.04, 0.5) = 0.17;
uniform float sheen_strength : hint_range(0.0, 1.5) = 0.72;
uniform float rim_thickness : hint_range(0.02, 0.35) = 0.16;

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;

	// Diagonal crystal sheen sweep with twin highlight ribbons and a refined rest beat.
	float sweep_phase = fract(TIME * sheen_speed * 0.42 + 0.34);
	float sweep_pos = mix(-0.35, 1.72, sweep_phase);
	float diag = UV.x * 0.74 + UV.y * 0.56;

	float d_main = abs(diag - sweep_pos);
	float main_band = 1.0 - smoothstep(sheen_width * 0.18, sheen_width, d_main);
	float d_sub = abs(diag - (sweep_pos - sheen_width * 1.18));
	float sub_band = (1.0 - smoothstep(sheen_width * 0.10, sheen_width * 0.42, d_sub)) * 0.48;
	float sheen = (main_band + sub_band) * sheen_strength;

	// Smooth rounded outer rim aura (zero harsh corner pinching).
	vec2 edge_d = min(UV, vec2(1.0) - UV);
	float edge_x = 1.0 - smoothstep(0.0, rim_thickness, edge_d.x);
	float edge_y = 1.0 - smoothstep(0.0, rim_thickness, edge_d.y);
	float rim_factor = clamp(max(edge_x, edge_y) + 0.35 * edge_x * edge_y, 0.0, 1.0);
	rim_factor = pow(rim_factor, 1.9);

	// Soft breathing radial heart glow.
	float center_dist = length((UV - vec2(0.5)) * 2.0);
	float core_aura = (1.0 - smoothstep(0.10, 1.10, center_dist)) * 0.20;

	float wave = 0.58 + 0.42 * sin(TIME * pulse_speed * 3.14159265);
	float aura_amt = (rim_factor * 0.90 + core_aura) * wave * pulse_strength;

	// Keep glow richly saturated in glow_color while sheen flashes luminous warm white.
	vec3 sheen_col = mix(vec3(1.0, 1.0, 1.0), glow_color.rgb, 0.28) * sheen;
	vec3 aura_col = glow_color.rgb * aura_amt;

	vec3 final_rgb = base.rgb + sheen_col + aura_col;
	COLOR = vec4(final_rgb, base.a);
}
