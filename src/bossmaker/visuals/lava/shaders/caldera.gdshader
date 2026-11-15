shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 火口（2026-11-14 溶岩の巨人の覚醒後全体）。地面の楕円が下から赤く光り始め（open=0）、沈んで開いた火口になる（open=1）。
// 中は渦を巻いて流れる溶岩（網目・点・穴の模様は使わない。流れる明暗の筋だけ）、縁は崩れた暗い岩で内側が照らされる、外の地面はほのかに赤い。
// 2px 格子・8段の色（pal: LAVA）・点描。
uniform vec2 size = vec2(400., 200.);
uniform vec2 center = vec2(200., 100.);
uniform float radius = 120.;
uniform float squash = .3;
uniform float open = 1.;
uniform float heat = 1.;
uniform float flow = 0.;
uniform float seed = 0.;
uniform float fade = 1.;
uniform vec3 pal[8];
uniform vec3 rock_dark = vec3(.07, .04, .04);
uniform vec3 rock_lit = vec3(.32, .14, .08);
uniform vec3 glow_col = vec3(1., .4, .1);

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = uv * size - center;
	float bay = hfx_bayer(FRAGCOORD.xy, 2.);
	vec2 q = p / vec2(1., squash);
	float r = length(q);
	float ang = atan(q.y, q.x);
	float R = radius * (.9 + .16 * hfx_fbm(vec2(ang * 1.8 + seed, 3.), 3));
	float Rin = R * (1. - .16 * open);
	vec4 col = vec4(0.);
	if (r < Rin && open > .02) {
		// 中: 渦を巻いて流れる溶岩
		float sw = ang + flow * .35 + r * .012;
		vec2 sq = vec2(cos(sw), sin(sw)) * r;
		float n1 = hfx_fbm(sq * .03 + vec2(seed, flow * .4), 3);
		float n2 = hfx_fbm(sq * .06 + vec2(n1 * 1.4, -flow * .8 + seed), 3);
		float t = .35 + .45 * (1. - r / Rin) * open + .4 * (n2 - .5) + .1 * heat;
		// 縁へ行くほど冷えて暗い筋
		t -= .3 * smoothstep(.55, .72, n1) * smoothstep(.4, 1., r / Rin);
		t = mix(.18, t, open);
		t += (bay - .5) * .08;
		vec3 c = pal[clamp(int(floor(clamp(t, 0., .999) * 8.)), 0, 7)];
		if (Rin - r < 1.6) { c = mix(rock_dark, c, .3); }
		col = vec4(c, 1.);
	} else if (r < R && open > .02) {
		// 縁: 崩れた暗い岩、内側ほど溶岩に照らされる
		float k = (r - Rin) / max(R - Rin, .001);
		float rough = hfx_n(vec2(ang * 22. + seed, r * .3));
		vec3 c = mix(rock_lit, rock_dark, smoothstep(.0, .8, k) + (rough - .5) * .3);
		c = mix(c, glow_col * .7, (1. - k) * .5 * heat);
		col = vec4(c, 1.);
	} else if (r < R * 1.6) {
		// 外の地面がほのかに赤い（下から照らされる・開く前は中も光る）
		float gk = (1. - smoothstep(R * (1. - open * .2) * .6, R * 1.6, r)) * heat * (.35 + .4 * (1. - open));
		gk *= .8 + .2 * hfx_n(q * .05 + flow);
		col = vec4(glow_col * gk * .6, 0.);
	}
	col *= fade;
	COLOR = col;
}
