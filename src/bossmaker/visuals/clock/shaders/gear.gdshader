shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 振り子の給仕長の歯車（2026-11-16）。線の輪ではなく、厚みのある真鍮の歯車として描く:
// 台形の歯（尖らせない）・外の輪・抜き穴と腕（スポーク）・軸。光の向きで縁の明暗（浮き彫り）、濃い輪郭、2px 格子。
// 座標は論理ドット。center・r（歯先の半径）・teeth・rot・spokes・squash（傾き）。dark で暗く（影の中の歯車）。
uniform vec2 size = vec2(100., 100.);
uniform vec2 center = vec2(50., 50.);
uniform float r = 40.;
uniform float teeth = 12.;
uniform float rot = 0.;
uniform float spokes = 5.;
uniform float squash = 1.;
uniform float fade = 1.;
uniform float dark = 0.;
uniform float glow = 0.;
uniform vec3 glow_col = vec3(.55, .95, 1.);
uniform vec3 brass_l = vec3(.98, .86, .55);
uniform vec3 brass = vec3(.78, .58, .28);
uniform vec3 brass_d = vec3(.40, .26, .11);
uniform vec3 ink = vec3(.10, .08, .08);

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = uv * size - center;
	vec2 q = vec2(p.x, p.y / max(squash, .05));
	float d = length(q);
	float a = atan(q.y, q.x);
	float h = max(2.5, r * .14);
	// 歯: 台形（上が平ら）。角を少し丸める
	float t = fract((a - rot) / 6.2832 * teeth);
	float tooth = smoothstep(.12, .26, t) * (1. - smoothstep(.56, .70, t));
	float R = r - h + h * tooth;
	float rim_in = r - h - max(3., r * .16);
	float hub = max(3., r * .2);
	vec4 col = vec4(0.);
	vec2 L = normalize(vec2(-1., -1.25));
	vec2 nd = normalize(q + vec2(.0001));
	bool body = d < R;
	// 抜き穴（輪と軸の間。腕は残す）
	float sa = fract((a - rot) / 6.2832 * spokes);
	float arm_w = max(2.4, r * .09) / max(d, 1.);
	bool arm = abs(sa - .5) * 6.2832 / spokes < arm_w;
	bool hole = d < rim_in && d > hub && !arm;
	if (body && !hole) {
		vec3 c = brass;
		// 外の縁: 光の側が明るい／内の縁（穴の外側）: 逆
		float lit = dot(nd, L);
		if (d > R - 2.2) { c = mix(c, lit > 0. ? brass_l : brass_d, abs(lit) * .9); }
		else if (d > rim_in && d < rim_in + 2.2) { c = mix(c, lit < 0. ? brass_l : brass_d, abs(lit) * .8); }
		else if (d < hub + 2.) { c = mix(c, lit > 0. ? brass_l : brass_d, abs(lit) * .7); }
		else { c = mix(c, brass_l, .15 * max(0., dot(q / r, L))); }
		// 軸の穴
		if (d < hub * .45) { c = ink; }
		// 輪郭
		if (d > R - 1.1 || (d > rim_in - .2 && d < rim_in + .9 && !arm) || (d < hub + .9 && d > hub - .2 && !arm)) { c = mix(c, ink, .75); }
		col = vec4(c * (1. - .6 * dark), 1.);
	}
	// 外の淡い光
	if (glow > 0. && col.a < .5 && d > R && d < r + 8.) {
		float g = 1. - (d - R) / (r + 8. - R);
		g = g * g * glow;
		if (g > hfx_bayer(FRAGCOORD.xy, 2.) * .9) { col = vec4(glow_col, .45 * g + .15); }
	}
	col.a *= fade;
	col.rgb *= col.a;
	COLOR = col;
}
