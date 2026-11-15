shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 喪華のカラー女王の覚醒後の常時オーラ（喪華の深紅紫。2026-11-14 ユーザー「覚醒後はオーラ。それぞれのボスに合った色で」）。日蝕の獅皇の太陽のオーラと同じ作り方で、色はつなぎ（rbm_flower_sun_aura.gd）が渡す。
// 色は体に近いほど明るく、外へ行くほど濃い色へ移るグラデーション（pal の6色。2px 格子の点描で段を混ぜる）。外側に薄い光（glow_col）。
// TEXTURE: r=上へ伸びやすい距離、g=全方向で同じ距離（どちらも64ドットで1）、b・a=一番近い体の点の位置。
uniform float flow = 0.;
uniform float power = 1.;
uniform float reach = 30.;
uniform float max_r = 28.;
uniform float seed = 0.;
uniform vec2 world_origin = vec2(0.);
uniform vec3 pal[6];
uniform vec3 glow_col = vec3(1., .62, .2);
uniform float glow = .3;

void fragment(){
	vec2 ts = vec2(textureSize(TEXTURE, 0));
	vec2 px = floor(UV * ts) + .5;
	vec4 f = texture(TEXTURE, px / ts);
	float d = f.r * 64.;
	float iso = f.g * 64.;
	COLOR = vec4(0.);
	if (power > .001 && d < 63.) {
		vec2 src = f.ba * (ts - 1.) + .5;
		vec2 q = src + world_origin;
		float wav = (hfx_n(vec2(d * .09 - flow * 1.6, q.x * .05 + seed)) - .5) * 7.;
		float n1 = hfx_fbm(vec2((q.x + wav) * .2 + seed, q.y * .05 - d * .012 + flow * .9), 3);
		float n2 = hfx_fbm(vec2((q.x + wav) * .47 - seed, q.y * .11 + flow * 1.7), 2);
		float tongue = clamp((n1 - .4) * 3. + (n2 - .5) * .5, 0., 1.);
		float foot = .3 + .7 * smoothstep(0., 30., ts.y - 8. - src.y);
		float r = min(power * (6. + reach * tongue * tongue) * foot, max_r);
		vec2 w_ = px + world_origin;
		float n3 = hfx_fbm(vec2(w_.x * .16, w_.y * .09 + flow * 2.2), 2);
		float rim = r - d - abs(px.x - src.x + (n3 - .5) * 10.) * .9 + (n3 - .5) * 6. * smoothstep(2., 14., d);
		if (rim > 0.) {
			// 体に近いほど明るい（d が小さい）。炎の先（rim が小さい）ほど暗い紅へ
			float k = clamp(1. - d / max(r, 1.), 0., 1.);
			float tone = k * .75 + clamp(rim / 8., 0., 1.) * .3 + (hfx_n(vec2(q.x * .3, q.y * .2 - flow * 2.)) - .5) * .15;
			tone = clamp(tone, 0., .999) * 6.;
			float fi = floor(tone);
			// 段の境目を 2px 格子の点描で混ぜる
			if (fract(tone) > hfx_bayer(FRAGCOORD.xy, 2.)) { fi += 1.; }
			int idx = int(clamp(fi, 0., 5.));
			if (iso < 1.5) { idx = max(idx - 1, 0); }
			COLOR = vec4(pal[idx], 1.);
		} else if (glow > 0. && rim > -16.) {
			float g = exp(rim / 6.) * glow * clamp(power, 0., 1.);
			COLOR = vec4(glow_col * g, 0.);
		}
	}
}
