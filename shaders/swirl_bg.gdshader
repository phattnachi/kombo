shader_type canvas_item;

// Mobile-optimized multi-theme procedural background shader for Kombo.
// Supports 6 distinct lightweight styles (bg_style 0..5) using pure arithmetic
// (zero heavy loops, zero texture fetches) for silky 60 FPS on mobile GPUs:
//   0 = Classic Swirl (Milestone evolving velvet waves)
//   1 = Sweet Candy (Pastel diagonal candy stripes, frosted donuts, sprinkles & stars)
//   2 = Sakura Bloom (Twilight Kyoto gradient, drifting cherry blossoms & lantern bokeh)
//   3 = Cyber Grid (Synthwave horizon glow & scrolling neon laser grid)
//   4 = Deep Ocean (Abyssal water caustics & rising translucent bubbles)
//   5 = Starlight Galaxy (Cosmic nebula aurora & multi-layer twinkling starfield)

uniform int bg_style = 0;
uniform vec4 color_deep : source_color = vec4(0.035, 0.055, 0.153, 1.0);   // #090E27
uniform vec4 color_mid : source_color = vec4(0.094, 0.145, 0.369, 1.0);    // #18255E
uniform vec4 color_accent : source_color = vec4(0.165, 0.259, 0.596, 1.0); // #2A4298
uniform vec4 color_fever : source_color = vec4(0.60, 0.13, 0.27, 1.0);     // Warm crimson-magenta FEVER tint
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.0, 4.0) = 0.65;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 render_swirl(vec2 p, float r2, float t) {
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
	return calm_col;
}

vec3 render_candy(vec2 uv, vec2 p, float t) {
	// Creamy berry-strawberry twilight base (rich contrast so dark 8x8 board & bright blocks pop!)
	vec3 base_top = vec3(0.32, 0.11, 0.25);
	vec3 base_bot = vec3(0.18, 0.08, 0.26);
	vec3 col = mix(base_top, base_bot, clamp(uv.y, 0.0, 1.0));

	// Soft diagonal candy-cane ribbons
	float diag = (p.x * 0.82 + p.y * 0.58) * 7.5 - t * 0.35;
	float stripe = smoothstep(-0.18, 0.18, sin(diag));
	vec3 stripe_col = mix(vec3(0.42, 0.14, 0.31), vec3(0.24, 0.13, 0.36), smoothstep(0.0, 1.0, uv.y));
	col = mix(col, stripe_col, stripe * 0.46);

	// Repeating tile grid of frosted donuts, candy lollipops & colorful sprinkles
	vec2 gp = vec2(p.x, p.y) * 3.6 + vec2(t * 0.14, -t * 0.22);
	vec2 id = floor(gp);
	vec2 gv = fract(gp) - 0.5;
	float h = hash21(id);
	vec2 jitter = (vec2(hash21(id + 7.1), hash21(id + 13.7)) - 0.5) * 0.34;
	vec2 d = gv - jitter;
	float dist = length(d);

	if (h < 0.42) {
		// Frosted Donut (ring + pink/mint/lemon icing)
		float ring = smoothstep(0.20, 0.175, dist) * smoothstep(0.068, 0.092, dist);
		float glaze = smoothstep(0.185, 0.16, dist) * smoothstep(0.082, 0.102, dist);
		vec3 dough = vec3(0.76, 0.50, 0.30);
		vec3 icing = (h < 0.15) ? vec3(0.98, 0.46, 0.72) : ((h < 0.29) ? vec3(0.40, 0.90, 0.82) : vec3(1.0, 0.84, 0.38));
		vec3 donut_col = mix(dough, icing, glaze * 0.88);
		// Cute glossy highlight arc on top-left of donut
		float gloss = smoothstep(0.055, 0.015, length(d - vec2(-0.06, -0.06)));
		donut_col += vec3(0.25) * gloss;
		col = mix(col, donut_col, ring * 0.44);
	} else if (h < 0.74) {
		// Wrapped Hard Candy / Peppermint Swirl
		float body = smoothstep(0.15, 0.125, dist);
		float ang = atan(d.y, d.x);
		float swirl_s = smoothstep(-0.1, 0.1, sin(ang * 3.0 + dist * 24.0 - t * 1.4));
		vec3 c_main = (h < 0.58) ? vec3(1.0, 0.38, 0.52) : vec3(0.36, 0.86, 1.0);
		vec3 candy_c = mix(vec3(1.0, 0.96, 0.98), c_main, swirl_s);
		// Candy wrapper wings
		float wx = abs(d.x);
		float wy = abs(d.y);
		float wing = smoothstep(0.24, 0.19, wx) * smoothstep(0.11, 0.14, wx) * smoothstep(0.095, 0.06, wy + (0.20 - wx) * 0.35);
		col = mix(col, c_main * 0.9, wing * 0.34);
		col = mix(col, candy_c, body * 0.42);
	} else {
		// Sugar Star & Sprinkles
		float ang = atan(d.y, d.x) + t * 0.4;
		float star_r = 0.085 + 0.042 * cos(ang * 5.0);
		float star = smoothstep(star_r + 0.018, star_r - 0.008, dist);
		vec3 star_c = (h < 0.87) ? vec3(1.0, 0.88, 0.42) : vec3(1.0, 0.62, 0.86);
		col = mix(col, star_c, star * 0.45);
	}

	// Second fine layer of floating pastel sprinkles
	vec2 sp = vec2(p.x, p.y) * 7.2 + vec2(-t * 0.10, -t * 0.32);
	vec2 sid = floor(sp);
	vec2 sgv = fract(sp) - 0.5;
	float sh = hash21(sid + 31.4);
	if (sh > 0.56) {
		float sa = sh * 6.283;
		float ca = cos(sa);
		float sa_s = sin(sa);
		vec2 sd = vec2(sgv.x * ca - sgv.y * sa_s, sgv.x * sa_s + sgv.y * ca);
		float capsule = smoothstep(0.045, 0.025, max(abs(sd.x) - 0.08, abs(sd.y)));
		vec3 sp_col = (sh < 0.70) ? vec3(1.0, 0.82, 0.32) : ((sh < 0.85) ? vec3(0.48, 0.94, 0.86) : vec3(1.0, 0.55, 0.78));
		col = mix(col, sp_col, capsule * 0.38);
	}

	return col;
}

vec3 render_sakura(vec2 uv, vec2 p, float t) {
	// Twilight Kyoto plum-violet to rose-dusk gradient
	vec3 sky_top = vec3(0.08, 0.05, 0.19);
	vec3 sky_mid = vec3(0.22, 0.09, 0.26);
	vec3 sky_bot = vec3(0.34, 0.14, 0.28);
	vec3 col = mix(sky_top, sky_mid, smoothstep(0.0, 0.58, uv.y));
	col = mix(col, sky_bot, smoothstep(0.55, 1.0, uv.y));

	// Warm moonlit lantern glow behind upper-right
	float moon_d = length(p - vec2(0.24, -0.42));
	col += vec3(0.32, 0.15, 0.24) * (0.45 / (1.0 + moon_d * moon_d * 5.0));

	// Soft warm lantern bokeh orbs
	vec2 bp = p * 2.6 + vec2(0.0, t * 0.08);
	vec2 bid = floor(bp);
	vec2 bgv = fract(bp) - 0.5;
	float bh = hash21(bid + 19.3);
	if (bh > 0.45) {
		vec2 boff = (vec2(hash21(bid + 3.1), hash21(bid + 9.7)) - 0.5) * 0.4;
		float bd = length(bgv - boff);
		float bokeh = smoothstep(0.24, 0.05, bd);
		col += vec3(0.95, 0.58, 0.72) * bokeh * 0.12;
	}

	// Drifting 5-petal sakura blossoms (2 parallax depths)
	for (int layer = 0; layer < 2; layer++) {
		float scale = (layer == 0) ? 4.4 : 6.8;
		float spd = (layer == 0) ? 0.34 : 0.22;
		vec2 lp = p * scale + vec2(-t * spd * 0.75 + sin(p.y * 2.2 + t) * 0.18, -t * spd);
		vec2 id = floor(lp);
		vec2 gv = fract(lp) - 0.5;
		float h = hash21(id + float(layer) * 41.7);
		if (h > 0.46) {
			vec2 off = (vec2(hash21(id + 5.2), hash21(id + 11.8)) - 0.5) * 0.42;
			vec2 d = gv - off;
			float rot = t * (0.7 + h * 0.8) + h * 6.283;
			float cr = cos(rot);
			float sr = sin(rot);
			d = vec2(d.x * cr - d.y * sr, d.x * sr + d.y * cr);
			float dist = length(d);
			float ang = atan(d.y, d.x);
			float petal_r = 0.085 + 0.048 * cos(ang * 5.0);
			float blossom = smoothstep(petal_r + 0.02, petal_r - 0.015, dist);
			float center = smoothstep(0.035, 0.01, dist);
			vec3 p_col = mix(vec3(1.0, 0.74, 0.86), vec3(1.0, 0.90, 0.55), center * 0.85);
			col = mix(col, p_col, blossom * ((layer == 0) ? 0.44 : 0.28));
		}
	}
	return col;
}

vec3 render_cyber(vec2 uv, vec2 p, float t) {
	// Deep synthwave obsidian-purple sky + neon sunset horizon
	vec3 top_c = vec3(0.035, 0.02, 0.12);
	vec3 hor_c = vec3(0.24, 0.05, 0.32);
	vec3 bot_c = vec3(0.04, 0.03, 0.16);
	float horizon = 0.46;
	vec3 col = (uv.y < horizon)
		? mix(top_c, hor_c, smoothstep(0.0, horizon, uv.y))
		: mix(hor_c * 0.72, bot_c, smoothstep(horizon, 1.0, uv.y));

	// Retro synth sun glow right on horizon
	float sun_d = length(vec2(p.x, p.y + 0.04));
	float sun_disc = smoothstep(0.26, 0.24, sun_d) * smoothstep(0.08, -0.14, p.y);
	float sun_bars = smoothstep(-0.15, 0.15, sin((p.y + 0.2) * 58.0));
	vec3 sun_col = mix(vec3(1.0, 0.20, 0.65), vec3(1.0, 0.84, 0.22), clamp((-p.y + 0.22) * 2.4, 0.0, 1.0));
	col = mix(col, sun_col, sun_disc * mix(0.45, 0.85, sun_bars) * 0.55);
	col += vec3(0.48, 0.08, 0.42) * (0.28 / (1.0 + sun_d * sun_d * 6.5));

	// Glowing perspective neon grid below horizon
	if (uv.y >= horizon - 0.02) {
		float gy = max(0.025, uv.y - horizon + 0.035);
		float gx = (uv.x - 0.5) / gy;
		float gz = 0.55 / gy + t * 1.15;

		float lx = abs(fract(gx * 0.65 + 0.5) - 0.5);
		float lz = abs(fract(gz * 0.55) - 0.5);
		float grid_x = smoothstep(0.045, 0.008, lx);
		float grid_z = smoothstep(0.055, 0.010, lz);
		float grid = max(grid_x, grid_z) * smoothstep(horizon - 0.01, horizon + 0.14, uv.y);

		vec3 neon_c = mix(vec3(0.10, 0.92, 1.0), vec3(1.0, 0.22, 0.82), smoothstep(0.48, 0.95, uv.y));
		col += neon_c * grid * 0.48;
	}

	// Crisp glowing horizon laser beam
	float hline = smoothstep(0.018, 0.0, abs(uv.y - horizon));
	col += vec3(0.20, 0.95, 1.0) * hline * 0.42;

	// Subtle upper-sky neon stars
	if (uv.y < horizon) {
		vec2 sp = p * 9.0;
		vec2 sid = floor(sp);
		vec2 sgv = fract(sp) - 0.5;
		float sh = hash21(sid + 8.8);
		if (sh > 0.78) {
			float sd = length(sgv);
			float tw = 0.55 + 0.45 * sin(t * 2.8 + sh * 25.0);
			col += vec3(0.55, 0.95, 1.0) * smoothstep(0.09, 0.01, sd) * tw * 0.45;
		}
	}
	return col;
}

vec3 render_ocean(vec2 uv, vec2 p, float t) {
	// Deep abyssal sapphire to sunlit turquoise surface
	vec3 top_c = vec3(0.04, 0.26, 0.40);
	vec3 mid_c = vec3(0.02, 0.14, 0.28);
	vec3 bot_c = vec3(0.015, 0.055, 0.16);
	vec3 col = mix(top_c, mid_c, smoothstep(0.0, 0.55, uv.y));
	col = mix(col, bot_c, smoothstep(0.50, 1.0, uv.y));

	// Shimmering underwater sun-rays & caustic ripples
	float ray = sin(p.x * 7.0 + p.y * 2.2 + t * 0.55) * 0.5 + 0.5;
	float ray2 = sin(p.x * 11.5 - p.y * 3.0 - t * 0.42) * 0.5 + 0.5;
	float caustic = smoothstep(0.42, 0.96, ray * ray2);
	float depth_fade = clamp(1.05 - uv.y * 0.85, 0.15, 1.0);
	col += vec3(0.14, 0.72, 0.86) * caustic * depth_fade * 0.42;

	// Gentle underwater wave bands
	float wv = sin(p.y * 5.2 + sin(p.x * 3.4 + t * 0.65) * 0.8 - t * 0.45);
	col += vec3(0.06, 0.34, 0.52) * smoothstep(0.35, 0.95, wv) * 0.22;

	// Rising translucent bubbles (2 layers)
	for (int layer = 0; layer < 2; layer++) {
		float scale = (layer == 0) ? 4.8 : 7.8;
		float spd = (layer == 0) ? 0.38 : 0.25;
		vec2 bp = p * scale + vec2(sin(p.y * 3.0 + t) * 0.15, t * spd);
		vec2 id = floor(bp);
		vec2 gv = fract(bp) - 0.5;
		float h = hash21(id + float(layer) * 29.1);
		if (h > 0.52) {
			vec2 off = (vec2(hash21(id + 4.3), hash21(id + 17.6)) - 0.5) * 0.42;
			vec2 d = gv - off;
			float rad = 0.075 + h * 0.065;
			float dist = length(d);
			float rim = smoothstep(rad + 0.015, rad - 0.008, dist) * smoothstep(rad * 0.52, rad * 0.86, dist);
			float spec = smoothstep(rad * 0.35, 0.0, length(d - vec2(-rad * 0.34, -rad * 0.34)));
			col += vec3(0.45, 0.92, 1.0) * (rim * 0.36 + spec * 0.48);
		}
	}
	return col;
}

vec3 render_galaxy(vec2 uv, vec2 p, float t) {
	// Deep cosmic obsidian-violet void
	vec3 col = mix(vec3(0.03, 0.02, 0.09), vec3(0.06, 0.03, 0.14), uv.y);

	// Diagonal aurora nebula ribbon (violet + cyan + gold dust)
	float diag = p.x * 0.72 + p.y * 0.68;
	float neb_w = sin(diag * 3.6 + sin(p.y * 2.8 - t * 0.28) * 1.15);
	float neb_mask = smoothstep(-0.35, 0.85, neb_w) * smoothstep(1.1, 0.1, abs(p.x - p.y * 0.45));
	vec3 neb_col = mix(vec3(0.32, 0.11, 0.58), vec3(0.10, 0.48, 0.74), smoothstep(-0.4, 0.5, sin(p.y * 2.4 + t * 0.22)));
	col += neb_col * neb_mask * 0.48;

	// Warm golden stardust core
	float dust = sin(p.x * 4.5 - p.y * 3.8 + t * 0.2) * cos(p.y * 4.2 + p.x * 2.5 - t * 0.18);
	col += vec3(0.68, 0.46, 0.18) * smoothstep(0.45, 0.98, dust) * 0.22;

	// Multi-layer twinkling starfield + sparkling 4-point hero stars
	for (int layer = 0; layer < 2; layer++) {
		float scale = (layer == 0) ? 5.5 : 10.5;
		vec2 sp = p * scale + vec2(t * ((layer == 0) ? 0.04 : 0.02), -t * 0.03);
		vec2 id = floor(sp);
		vec2 gv = fract(sp) - 0.5;
		float h = hash21(id + float(layer) * 53.9);
		if (h > 0.58) {
			vec2 off = (vec2(hash21(id + 2.7), hash21(id + 14.1)) - 0.5) * 0.52;
			vec2 d = gv - off;
			float tw = 0.55 + 0.45 * sin(t * (2.2 + h * 3.0) + h * 40.0);
			float core = smoothstep(0.065, 0.01, length(d));
			float flare = 0.0;
			if (layer == 0 && h > 0.82) {
				flare = smoothstep(0.18, 0.0, abs(d.x)) * smoothstep(0.028, 0.0, abs(d.y))
					+ smoothstep(0.18, 0.0, abs(d.y)) * smoothstep(0.028, 0.0, abs(d.x));
			}
			vec3 star_c = (h > 0.88) ? vec3(1.0, 0.90, 0.58) : ((h > 0.72) ? vec3(0.70, 0.92, 1.0) : vec3(0.96, 0.84, 1.0));
			col += star_c * (core * 0.75 + flare * 0.45) * tw;
		}
	}
	return col;
}

void fragment() {
	vec2 p = UV - vec2(0.5, 0.48);
	p.y *= 1.7778;

	float r2 = dot(p, p);
	float t = TIME * (0.20 + speed * 0.16 + heat * 0.24);

	vec3 calm_col;
	if (bg_style == 1) {
		calm_col = render_candy(UV, p, t);
	} else if (bg_style == 2) {
		calm_col = render_sakura(UV, p, t);
	} else if (bg_style == 3) {
		calm_col = render_cyber(UV, p, t);
	} else if (bg_style == 4) {
		calm_col = render_ocean(UV, p, t);
	} else if (bg_style == 5) {
		calm_col = render_galaxy(UV, p, t);
	} else {
		calm_col = render_swirl(p, r2, t);
	}

	// Dynamic Combo / FEVER heat overlay works harmoniously on EVERY background style!
	float fever_wave = 0.5 + 0.5 * sin(p.x * 3.0 + p.y * 2.5 - t * 1.4);
	vec3 fever_col = mix(color_fever.rgb * 0.55, vec3(0.88, 0.34, 0.16), fever_wave * 0.55);
	vec3 col = mix(calm_col, fever_col, heat * (bg_style == 0 ? 0.62 : 0.42));

	float center_glow = 1.0 / (1.0 + r2 * 2.3);
	col += vec3(0.09, 0.13, 0.28) * (pulse * center_glow);

	float vig = clamp(1.12 - r2 * 0.44, 0.42, 1.0);
	COLOR = vec4(col * vig, 1.0);
}
