shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 体から立ち上る炎。下から pal_b（闇）へ侵食させられる。矩形の下辺中央が足元。
uniform vec3 pal_a[6];
uniform vec3 pal_b[6];
uniform float power = 1.;
uniform float width = .34;
uniform float flow = 0.;
uniform float seed = 0.;
uniform float corrupt = 0.;
uniform float glow = .5;
uniform vec3 glow_col = vec3(.25, .6, 1.);
uniform vec3 glow_col_b = vec3(.7, .05, .15);

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	float x = (uv.x - .5) * 2.;
	float y = 1. - uv.y;
	float n1 = hfx_fbm(vec2(x * 2.6 + seed, y * 2.4 - flow * 1.5), 3);
	float n2 = hfx_fbm(vec2(x * 7.5 - seed, y * 1.3 - flow * 3.1), 3);
	float wob = (hfx_n(vec2(y * 3. - flow * 2., seed)) - .5) * .28 * y;
	float top = max(power, .001);
	float w = width * pow(max(1. - y / top, 0.), 1.05) * (.34 + 1.02 * smoothstep(0., .2, y));
	float tongue = hfx_fbm(vec2(sign(x) * 3. + seed, y * 5.5 - flow * 3.2), 3);
	w *= .55 + 1.1 * tongue;
	float rid = 1. - abs(2. * hfx_fbm(vec2(x * 5.5 + wob * 3., y * 2.3 - flow * 2.7 + seed), 3) - 1.);
	float f = (1. - abs(x - wob) / max(w, .001)) * .72 + (rid - .56) * (.62 + y * 1.5) + (n1 - .5) * .7 + (n2 - .5) * .6 * y;
	f *= smoothstep(0., .05, y);
	float bite = corrupt * 1.5 + (hfx_fbm(vec2(x * 4. + seed, y * 4. - flow * 2.), 3) - .5) * .9 - y * (1.2 - corrupt);
	COLOR = vec4(0.);
	if (y < top + .1 && f > 0.) {
		int idx = int(floor(clamp(f * .8, 0., .999) * 6.));
		COLOR = vec4(bite > .35 ? pal_b[idx] : pal_a[idx], 1.);
	} else if (glow > 0.) {
		float g = pow(max(1. + f * 1.1, 0.), 3.) * glow * smoothstep(0., .04, y) * (1. - smoothstep(top, top + .3, y));
		COLOR = vec4(mix(glow_col, glow_col_b, smoothstep(.2, .6, corrupt)) * g * .55, 0.);
	}
}
