shader_type canvas_item;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 画面全体の最後の処理: 衝撃波の屈折・画面の断裂・放射ブラー・色ずれ・ノイズの乱れ・色調・周辺減光・二色のインパクトコマ・閃光。
uniform sampler2D scr : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec4 rings[6];
uniform int ring_count = 0;
uniform float ring_squash = .34;
uniform float ring_w = .035;
uniform float chroma = 0.;
uniform vec2 focus = vec2(.5);
uniform float radial = 0.;
uniform vec2 split_p = vec2(.5);
uniform vec2 split_dir = vec2(.7, .7);
uniform float split_amt = 0.;
uniform float split_gap = 0.;
// 裂け目が届いている位置（split_p から split_dir の向きに測る。大きければ全部裂ける）
uniform float split_head = 99.;
uniform float split_soft = .18;
// 短い斬線。a: xy=基準の点 zw=向き / b: x=ずれ y=線の太さ z=先頭 w=後端
uniform vec4 cuts_a[6];
uniform vec4 cuts_b[6];
uniform int cut_count = 0;
uniform vec3 split_col = vec3(1., .9, .85);
uniform float corrupt = 0.;
uniform float time = 0.;
uniform float desat = 0.;
uniform vec3 tint = vec3(1.);
uniform float vig = 0.;
uniform vec3 vig_col = vec3(0.);
uniform float vig_r = .35;
uniform float impact = 0.;
uniform vec3 impact_hi = vec3(1., .98, .9);
uniform vec3 impact_lo = vec3(.05, .08, .24);
uniform float impact_cut = .34;
uniform float flash = 0.;
uniform vec3 flash_col = vec3(1.);

vec3 pick(vec2 uv){
	return texture(scr, uv).rgb;
}

void fragment(){
	vec2 uv = SCREEN_UV;
	vec2 off = vec2(0.);
	const float ASPECT = 1.7778;
	for (int i = 0; i < ring_count; i++) {
		vec4 r = rings[i];
		vec2 d = (uv - r.xy) * vec2(ASPECT, 1.);
		d.y /= ring_squash;
		float l = length(d) + .0001;
		float b = exp(-pow((l - r.z) / ring_w, 2.));
		off -= d / l * b * r.w;
	}
	float gap = 0.;
	if (split_amt > 0. || split_gap > 0.) {
		vec2 n = normalize(vec2(-split_dir.y, split_dir.x));
		vec2 q = (uv - split_p) * vec2(ASPECT, 1.);
		float along = dot(q, split_dir);
		float s = dot(q, n);
		s += (hfx_n(vec2(along * 26., 3.)) - .5) * .012;
		// 刃先のすぐ後ろから開き始める
		float opened = smoothstep(0., split_soft, split_head - along);
		off += normalize(split_dir) * sign(s) * split_amt * opened * vec2(1. / ASPECT, 1.);
		float g_w = split_gap * opened;
		if (g_w > .0002) {
			gap = 1. - smoothstep(g_w * .7, g_w, abs(s));
		}
	}
	for (int i = 0; i < cut_count; i++) {
		vec2 cdir = cuts_a[i].zw;
		vec2 cq = (uv - cuts_a[i].xy) * vec2(ASPECT, 1.);
		float calong = dot(cq, cdir);
		float cs = dot(cq, vec2(-cdir.y, cdir.x)) + (hfx_n(vec2(calong * 26., float(i) + 5.)) - .5) * .012;
		float copen = smoothstep(cuts_b[i].w, cuts_b[i].w + .1, calong) * (1. - smoothstep(cuts_b[i].z - .1, cuts_b[i].z, calong));
		float cfall = 1. - smoothstep(.1, .35, abs(cs));
		off += cdir * sign(cs) * cuts_b[i].x * copen * cfall * vec2(1. / ASPECT, 1.);
		float cg = cuts_b[i].y * copen;
		if (cg > .0002) {
			gap = max(gap, 1. - smoothstep(cg * .7, cg, abs(cs)));
		}
	}
	if (corrupt > 0.) {
		float row = floor(uv.y * 46.);
		float sel = hfx_h(vec2(row, floor(time * 7.)));
		off.x += step(1. - corrupt * .5, sel) * (hfx_h(vec2(row, floor(time * 7.) + 2.)) - .5) * .05 * corrupt;
	}
	vec2 fuv = uv + off;
	// 画面の外を読まないよう、端へ近づくほどずらしを弱める
	vec2 edge = min(uv, 1. - uv);
	fuv = mix(uv, fuv, smoothstep(0., .07, min(edge.x, edge.y)));
	vec3 c;
	if (radial > .001) {
		c = vec3(0.);
		for (int i = 0; i < 10; i++) {
			c += pick(mix(fuv, focus, float(i) / 9. * radial));
		}
		c /= 10.;
	} else {
		c = pick(fuv);
	}
	if (chroma > 0.) {
		vec2 dir = (uv - focus) * chroma;
		c.r = pick(fuv + dir).r;
		c.b = pick(fuv - dir).b;
	}
	float g = dot(c, vec3(.3, .59, .11));
	c = mix(c, vec3(g), desat);
	c *= tint;
	if (vig > 0.) {
		float v = smoothstep(vig_r, vig_r + .5, length((uv - focus) * vec2(1.25, 1.)));
		c = mix(c, vig_col, v * vig);
	}
	if (impact > 0.) {
		float l = dot(c, vec3(.3, .59, .11));
		vec3 two = l > impact_cut ? impact_hi : impact_lo;
		c = mix(c, two, impact);
	}
	c = mix(c, split_col, gap);
	c = mix(c, flash_col, flash);
	COLOR = vec4(c, 1.);
}
