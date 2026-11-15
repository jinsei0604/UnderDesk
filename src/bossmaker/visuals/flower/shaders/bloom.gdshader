shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 花（2026-11-13 白磁のカラーの指摘「花の形が安っぽい」「平面に見える」→ 立体の花）。
// 花びらを地面に寝かせた図ではなく、立体として描く: 外・中・内の3段の花びらが根元から起き上がり（内の段ほど立つ＝お椀形）、
// 斜め上から見下ろした形で画面へ写す。重なりは奥行きで決める（手前の花びらが奥を隠す。手前の内の段は芯を少し隠す）。
// 明暗は花びらの向きと光（左上手前から）で決め、手前で起きた花びらは裏側が見える（少し暗い）。
// 開花（open）は閉じた蕾から花びらが外へ倒れていく動き（外の段から順に）。枯れ（wither）は花びらが垂れて縮み、縁がほつれ、枯れ色へ。
// crumble（0〜1）で点描で崩れて消える。花びらは先の丸いしずく形（尖らせない）。2px 格子・8段の色・点描・縁の輪郭。
uniform vec2 size = vec2(240., 160.);
uniform vec2 center = vec2(120., 80.);
uniform float radius = 60.;
uniform float open = 1.;
uniform float rot = 0.;
// 見下ろす角度の sin（小さいほど寝た角度から見る）
uniform float squash = .45;
uniform float petals = 10.;
uniform float wither = 0.;
uniform float crumble = 0.;
uniform float fade = 1.;
uniform float glow = 0.;
uniform float seed = 0.;
// 花びらの細さ（半幅 ÷ 長さ）
uniform float slender = .3;
// 開ききった時の起き上がり（度）: 外・中・内
uniform vec3 tilt = vec3(10., 32., 54.);
uniform vec3 pal[8];
uniform vec3 pal_w[8];
uniform vec3 core_a = vec3(1., .86, .36);
uniform vec3 core_b = vec3(.78, .5, .12);
uniform float core_k = 1.;
uniform vec3 outline_col = vec3(.12, .1, .08);
uniform vec3 glow_col = vec3(1., .95, .8);

vec3 tone_col(float t, float w){
	int i = clamp(int(floor(t * 8.)), 0, 7);
	return mix(pal[i], pal_w[i], w);
}

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = uv * size - center;
	float bay = hfx_bayer(FRAGCOORD.xy, 2.);
	float sq = clamp(squash, .15, .95);
	float cb = sqrt(1. - sq * sq);
	vec3 V = vec3(0., cb, sq);
	vec3 Lt = normalize(vec3(-.55, .35, .8));
	float best = -1e9;
	bool hit = false;
	// 当たった花びらの情報
	float h_u = 0.; float h_across = 0.; float h_lam = 0.; float h_back = 0.; float h_edge = 9.; float h_depth = 0.; float h_var = 0.;
	for (int L = 0; L < 3; L++) {
		float k = float(L);
		float depthk = k / 2.;                    // 外=0, 中=.5, 内=1
		float lo = clamp(open * 1.7 - depthk * .7, 0., 1.);
		if (lo <= 0.) { continue; }
		lo = 1. - pow(1. - lo, 3.);
		float n = petals - 2. * floor(depthk * 1.01);
		float seg = 6.2831853 / n;
		float lenk = mix(1., .56, depthk);
		float len = radius * lenk * (.4 + .6 * lo) * (1. - .25 * wither);
		float r0 = radius * mix(.1, .03, depthk);
		float a_open = L == 0 ? tilt.x : (L == 1 ? tilt.y : tilt.z);
		// 開く: 立った蕾（80度）から開いた角度へ倒れる。枯れると垂れる（先が下がる）
		float alpha = radians(mix(80., a_open, lo) - 45. * wither);
		float ca = cos(alpha);
		float sa = sin(alpha);
		for (int i = 0; i < 12; i++) {
			if (float(i) >= n) { break; }
			float ang = rot + k * .33 + float(i) * seg;
			float c0 = cos(ang);
			float s0 = sin(ang);
			vec2 base = r0 * vec2(c0, s0 * sq);
			vec2 A = len * vec2(ca * c0, ca * s0 * sq - sa * cb);
			vec2 W = vec2(-s0, c0 * sq);
			float det = A.x * W.y - A.y * W.x;
			if (abs(det) < .05) { continue; }
			vec2 d = p - base;
			float u = (d.x * W.y - d.y * W.x) / det;
			float w = (A.x * d.y - A.y * d.x) / det;
			if (u <= 0. || u >= 1.) { continue; }
			float var_ = hfx_h(vec2(float(i) + k * 13., seed));
			float prof = u < .5 ? sin(u / .5 * 1.5708) : sqrt(max(0., 1. - pow((u - .5) / .5, 2.)));
			prof = mix(prof, prof * prof, .25);
			float hw = len * slender * (.6 + .4 * lo) * prof * (.86 + .28 * var_) * (1. - .3 * wither);
			hw *= 1. - wither * .45 * hfx_n(vec2(u * 9. + float(i) * 7., seed + k));
			if (abs(w) >= hw) { continue; }
			// 奥行き（見る人へ近いほど大きい）
			float gy = base.y / max(sq, .001) + u * len * ca * s0 + w * c0;
			float gz = u * len * sa;
			float depth = gy * cb + gz * sq;
			if (depth <= best) { continue; }
			best = depth;
			hit = true;
			vec3 nrm = vec3(-sa * c0, -sa * s0, ca);
			float facing = dot(nrm, V);
			vec3 nv = facing >= 0. ? nrm : -nrm;
			h_u = u;
			h_across = abs(w) / hw;
			h_lam = clamp(dot(nv, Lt), 0., 1.);
			h_back = facing < 0. ? 1. : 0.;
			float lw = length(W);
			float la = length(A);
			h_edge = min((hw - abs(w)) * lw, (1. - u) * la);
			h_depth = depthk;
			h_var = var_;
		}
	}
	vec4 col = vec4(0.);
	// 芯: 内の段の真ん中に立つ（手前の内の段の花びらに少し隠れる）
	float o3 = clamp(open * 1.7 - .7, 0., 1.);
	vec2 cc = vec2(0., -radius * .2 * cb);
	float cr = radius * .12 * (.4 + .6 * o3) * core_k * (1. - .4 * wither);
	vec2 cq = (p - cc) / vec2(1., .9);
	float core_depth = radius * .2 * sq + radius * .06;
	if (cr > .5 && length(cq) < cr && core_depth > best) {
		float ck = length(cq) / cr;
		float spot = step(.72, hfx_h(floor((p + 300.) / 2.) + seed));
		vec3 c = mix(core_a, core_b, smoothstep(.2, 1., ck + (cq.y > 0. ? .25 : -.1)));
		c = mix(c, core_a * 1.1, spot * .5);
		c = mix(c, vec3(.35, .25, .18), wither * .7);
		if (ck > .76) { c = mix(outline_col, c, .3); }
		col = vec4(c, 1.);
	} else if (hit) {
		// 明るさ: 根元は暗く先へ明るい・光の当たり方・縁が暗い・中央の筋・裏側は暗い・外の段ほど少し暗い
		float tone = .06 + .42 * smoothstep(0., .85, h_u) + .34 * h_lam + .12 * (1. - h_across) - .24 * smoothstep(.6, 1., h_across);
		tone -= .26 * (1. - smoothstep(0., .22, h_u));
		tone -= .14 * h_back;
		tone -= .06 * (1. - h_depth);
		tone += (h_var - .5) * .08;
		tone += .1 * (1. - smoothstep(0., .5, abs(h_u - .78) * 4.)) * (1. - h_across) * (1. - h_back);
		tone -= .12 * (1. - smoothstep(.06, .16, h_across)) * step(.12, h_u) * step(h_u, .82);
		tone += (bay - .5) * .1;
		vec3 pc = tone_col(clamp(tone, 0., .999), wither);
		if (h_edge < 1.5) { pc = mix(outline_col, pc, .2); }
		col = vec4(pc, 1.);
	}
	// 芯の光
	if (glow > 0.) {
		float g = glow * (1. - smoothstep(0., radius * .55, length((p - cc) / vec2(1., .8))));
		col.rgb = col.rgb + glow_col * g * .8;
		col.a = max(col.a, g * .7);
	}
	// 崩れる（点描）
	if (crumble > 0. && hfx_n((p + seed * 37.) * .18) * .7 + bay * .3 < crumble * 1.05) { col = vec4(0.); }
	col.a *= fade;
	col.rgb *= fade;
	COLOR = col;
}
