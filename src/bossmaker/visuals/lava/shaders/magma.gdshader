shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 溶岩（2026-11-13 溶岩の巨人の作り直し）。2px 格子・8段の色（LAVA: 黒 → 赤 → 橙 → 黄 → 白）・縁の濃い輪郭。
// mode 0 = 溜まり: 地面に広がる楕円（縁は波打つ）。冷えた黒い岩の板（ボロノイ）と、その隙間で光る溶岩。crust で冷えて固まる。
// mode 1 = 柱・奔流: center から dir の向きへ reach×grow 伸びる溶岩の流れ（太さ width、先は丸い塊、根元は広がる）。
//          流れに沿って明るい筋が動き、冷えた塊が混じる。柱は dir=(0,-1)、炉からの奔流は相手への向き。
uniform vec2 size = vec2(200., 200.);
uniform int mode = 0;
uniform vec2 center = vec2(100., 100.);
uniform float radius = 60.;
uniform float squash = .32;
uniform float crust = .3;
// 溜まりの流れる先端（矩形の中の x。これより左はまだ届いていない。先端は明るい）。-1e5 なら全部
uniform float front = -100000.;
// 縁を明るくする量（地面の溜まりは縁が新しい溶岩で明るい。玉は弱く）
uniform float rim_hot = 1.;
// 玉として光を当てる（左上から。0 で平ら）
uniform float sphere = 0.;
uniform vec2 dir = vec2(0., -1.);
uniform float reach = 100.;
uniform float grow = 1.;
uniform float width = 14.;
uniform float flow = 0.;
uniform float seed = 0.;
uniform float heat = 1.;
uniform float fade = 1.;
uniform vec3 pal[8];
uniform vec3 outline_col = vec3(.08, .04, .03);

// ボロノイ: x=いちばん近い点までの距離, y=2番目, z=セルの番号の乱数
vec3 voro(vec2 p){
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 9., d2 = 9., id = 0.;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hfx_h(i + g + seed), hfx_h(i + g + seed + 7.3)) * .8 + .1;
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; id = hfx_h(i + g + 3.1); }
			else if (d < d2) { d2 = d; }
		}
	}
	return vec3(d1, d2, id);
}

vec3 tone_col(float t){
	return pal[clamp(int(floor(t * 8.)), 0, 7)];
}

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = uv * size - center;
	float bay = hfx_bayer(FRAGCOORD.xy, 2.);
	vec4 col = vec4(0.);
	if (mode == 0) {
		vec2 q = p / vec2(1., squash);
		float r = length(q);
		float ang = atan(q.y, q.x);
		float R = radius * (.82 + .32 * hfx_fbm(vec2(ang * 1.6 + seed, flow * .2), 3));
		float fx = p.x + center.x - front + (hfx_fbm(vec2(p.y * .08 + seed, flow * .5), 2) - .5) * 26.;
		if (r < R && fx > 0.) {
			// 岩の板（ゆっくり外へ流れる）。隙間ほど熱い。縁へ行くほど新しい溶岩で明るい
			vec3 v = voro(q * .085 * vec2(1., mix(1.6, 1., sphere)) - normalize(q + .001) * flow * .15);
			float gap = v.y - v.x;
			float molten = 1. - smoothstep(0., .1 + .22 * (1. - crust), gap);
			float edge_k = smoothstep(.55, 1., r / R);
			float plate = .1 + .16 * v.z + .22 * (1. - crust) * (1. - smoothstep(0., .5, gap));
			float t = mix(plate, .78 + .2 * (1. - crust), molten);
			// 所々で溶けて光る斑（板の大きさがそろいすぎないように）
			float hot = smoothstep(.56, .74, hfx_fbm(q * .035 + vec2(seed * 3.1, flow * .12), 3)) * (1. - crust * .7);
			t = max(t, mix(t, .72, hot));
			t = mix(t, max(t, .62 - .3 * crust), edge_k * (1. - crust * .6) * rim_hot);
			if (sphere > 0.) {
				vec2 nq = q / R;
				vec3 nn = vec3(nq, sqrt(max(0., 1. - dot(nq, nq))));
				float lam = clamp(dot(nn, normalize(vec3(-.5, -.6, .65))), 0., 1.);
				t = mix(t, t * (.45 + .75 * lam) + .12 * pow(lam, 6.) * (1. - molten), sphere);
				// 縁の細い光（球の輪郭の熱）
				t = max(t, sphere * (.5 - .2 * crust) * smoothstep(.86, 1., r / R));
			}
			// 流れる先端は新しい溶岩で明るい
			t = max(t, (.78 - .3 * crust) * (1. - smoothstep(0., 10., fx)) * step(-99999., front));
			t *= mix(.55, 1., heat);
			t += (hfx_n(q * .3 + flow * 2.) - .5) * .12 + (bay - .5) * .08;
			vec3 c = tone_col(clamp(t, 0., .999));
			if (R - r < 1.6 || fx < 1.6) { c = mix(outline_col, c, .25); }
			col = vec4(c, 1.);
		}
	} else {
		vec2 d = normalize(dir);
		vec2 n = vec2(-d.y, d.x);
		vec2 bq = p;
		float u = dot(bq, d);
		float v = dot(bq, n);
		float L = reach * grow;
		float wv = width * (1. + .7 * pow(max(0., 1. - u / max(width * 2.5, 1.)), 2.) + .12 * sin(u * .14 - flow * 9. + seed));
		float wob = (hfx_fbm(vec2(u * .06 - flow * 3., seed + sign(v) * 3.), 3) - .5) * .5 * wv;
		float head = length(vec2(u - L, v)) / (wv * 1.25);
		bool inside = (u > -2. && u < L && abs(v) + wob < wv) || head < 1.;
		if (inside && L > 1.) {
			float across = clamp((abs(v) + wob) / wv, 0., 1.);
			float fl = hfx_fbm(vec2(v * .12, u * .045 - flow * 4.), 3);
			float t = .2 + .52 * pow(1. - across, 1.5) + (fl - .5) * .62;
			// 流れに沿う明るい筋
			t += .16 * smoothstep(.62, .8, hfx_n(vec2(v * .25 + seed, u * .03 - flow * 5.)));
			// 冷えた塊（流れに乗って動く暗い板）
			vec3 vv = voro(vec2(v * .1, (u - flow * 120.) * .07));
			float lump = step(.55, vv.z) * smoothstep(.6, .25, vv.x);
			t = mix(t, .14 + .1 * vv.z, lump * .85 * (.4 + .6 * across));
			if (head < 1.) { t = max(t, .4 + .35 * (1. - head)); }
			t *= mix(.55, 1., heat);
			t += (bay - .5) * .08;
			vec3 c = tone_col(clamp(t, 0., .999));
			float e_body = (u > -2. && u < L) ? wv - (abs(v) + wob) : 0.;
			float e_head = (1. - head) * wv * 1.25;
			if (max(e_body, e_head) < 1.6) { c = mix(outline_col, c, .25); }
			col = vec4(c, 1.);
		}
	}
	col.a *= fade;
	col.rgb *= fade;
	COLOR = col;
}
