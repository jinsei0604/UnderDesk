shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 爆炎の塊。玉を距離場で溶かし合わせ、こぶ状のノイズで表面を作り、光の向きで立体にして段階色へ落とす。
// blobs: xy=矩形内の位置, z=半径, w=熱さ（負なら pal_b の炎）
uniform vec2 size = vec2(800., 520.);
// 矩形の左上（ワールド矩形内の座標）。色が付きうる範囲だけ描くため、矩形を縮めた時に使う。
uniform vec2 origin = vec2(0.);
uniform vec4 blobs[48];
uniform int count = 0;
uniform vec3 pal_a[8];
uniform vec3 pal_b[8];
uniform float cool = 0.;
uniform float erode = 0.;
uniform float flow = 0.;
uniform float seed = 0.;
uniform float amp = 18.;
uniform float k = .09;
uniform float rim_mode = 0.;
uniform float rim_w = 16.;
uniform vec3 glow_col = vec3(1., .6, .2);
uniform float glow = 0.;
uniform float glow_r = 40.;
uniform float fade = 1.;
uniform float floor_tone = 0.;
uniform float lump_scale = 1.;
uniform float hot_gain = 1.;
uniform float tone_cap = 1.;
uniform float erode_noise = 1.;
// 細かいこぶの量（1で今まで通り）
uniform float detail = 1.;
// 中心からの距離で色を決める割合（0で今まで通り）
uniform float radial_heat = 0.;
uniform vec2 heat_center = vec2(0.);
uniform float heat_radius = 300.;
// 1で模様を中心から外へ向かう流れにする（0で今まで通り）
uniform float polar = 0.;
// 消える時に外側から先に消える量（0で今まで通り）
uniform float erode_radial = 0.;

float lumps(vec2 p0){
	if (polar > 0.) {
		vec2 v = p0 - heat_center;
		float r = length(v) + 1.;
		vec2 dir = v / r;
		float rl = log(r + 40.) * .9 - flow * .4;
		float a0 = abs(2. * hfx_n(dir * 5.2 + vec2(rl, rl * .6) + seed) - 1.);
		float b0 = abs(2. * hfx_n(dir * 12. + vec2(rl * 1.6, -rl) + seed * 2.) - 1.);
		float c0 = abs(2. * hfx_n(dir * 26. + vec2(-rl * 2., rl * 1.4) + seed * 3.) - 1.);
		return a0 * .66 + (b0 * .3 + c0 * .07) * detail;
	}
	vec2 p = p0 * lump_scale;
	float a = abs(2. * hfx_n(p * .034 + vec2(seed, flow * .6)) - 1.);
	float b = abs(2. * hfx_n(p * .083 + vec2(flow * .9, seed * 2.)) - 1.);
	float c = abs(2. * hfx_n(p * .19 + vec2(seed * 3., flow * 1.4)) - 1.);
	return a * .66 + (b * .3 + c * .07) * detail;
}

float field(vec2 p, out float heat, out float side){
	float s = 1e-6, hs = 0., bs = 0.;
	for (int i = 0; i < count; i++) {
		vec4 b = blobs[i];
		float d = length(p - b.xy) - b.z;
		float w = exp(-k * clamp(d, -160., 260.));
		s += w;
		hs += w * abs(b.w);
		bs += w * step(b.w, 0.);
	}
	heat = hs / s;
	side = bs / s;
	return -log(s) / k;
}

float surface(vec2 p, float d0, float h){
	float d = d0 - lumps(p) * amp;
	if (erode > 0.) {
		d += erode * (1. - h) * 76.;
		d += erode * (hfx_fbm(p * .022 + vec2(flow * .35, seed), 3) * 210. - 58.) * erode_noise;
		d += erode * erode_radial * clamp(length((p - heat_center) * vec2(1., 1.5)) / max(heat_radius, 1.), 0., 1.);
	}
	return d;
}

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = origin + uv * size;
	float h, side, _a, _b;
	float d0 = field(p, h, side);
	COLOR = vec4(0.);
	if (count > 0 && d0 < glow_r * 4. + amp) {
		float d = surface(p, d0, h);
		if (d <= 0.) {
			float dx = surface(p + vec2(3., 0.), field(p + vec2(3., 0.), _a, _b), h);
			float dy = surface(p + vec2(0., 3.), field(p + vec2(0., 3.), _a, _b), h);
			vec2 g = vec2(dx - d, dy - d) / 3.;
			vec3 n = normalize(vec3(g * 1.15, .55));
			float l = dot(n, normalize(vec3(-.2, -.78, .58)));
			float depth = clamp(-d / 70., 0., 1.);
			float L = lumps(p);
			float crease = 1. - smoothstep(0., .13, L);
			float tone = h * (.45 + .42 * depth) + .25 * l - crease * .1;
			if (radial_heat > 0.) {
				float rad = 1. - clamp(length((p - heat_center) * vec2(1., 1.5)) / max(heat_radius, 1.), 0., 1.);
				tone = mix(tone, tone + (rad - .42) * .9, radial_heat);
			}
			if (rim_mode > .5) {
				float rim = exp(d / rim_w) * .92 + .1 * l;
				float hot = smoothstep(.7, 1., h * (depth * .6 + .55)) * hot_gain;
				tone = max(rim, hot);
			}
			tone = min(max(tone - cool, floor_tone), tone_cap);
			int idx = int(floor(clamp(tone, 0., .999) * 8.));
			float pick = side + (hfx_n(p * .05 + vec2(seed, flow)) - .5) * .5;
			vec3 c = pick > .5 ? pal_b[idx] : pal_a[idx];
			float a = fade;
			COLOR = vec4(c * a, a);
		} else if (glow > 0.) {
			float gl = exp(-d / glow_r) * glow * fade;
			COLOR = vec4(glow_col * gl, 0.);
		}
	}
}
