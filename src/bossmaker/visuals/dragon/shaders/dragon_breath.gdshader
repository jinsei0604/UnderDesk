shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 竜の息吹（2026-11-26 ユーザー承認）。口（UV.x=0）から先（UV.x=1）へ流れる炎の帯。UV.y が幅。
// 段階色 pal（0=冷えた煙 … 7=芯の白）へ落とし、外側だけ光を足す。2px 格子に揃えてドット絵に合わせる。
uniform vec3 pal[8];
// 炎の先端（0..1）と、口側の切れ目（終わりに 0→1 で口から離れていく）
uniform float head = 1.;
uniform float tail = 0.;
// 口と先での半幅（矩形の高さの半分に対する割合）
uniform float w0 = .12;
uniform float w1 = 1.;
uniform float flow = 0.;
uniform float speed = 6.;
uniform float seed = 0.;
// 長さ / 高さ（ノイズを縦横で同じ細かさにするため）
uniform float aspect = 4.;
uniform float rough = .32;
// 芯の熱さ（1 で口から先まで白く光る）
uniform float core = .55;
// 先ほど冷える割合
uniform float cool = .55;
uniform vec3 glow_col = vec3(1., .5, .2);
uniform float glow = .6;
uniform float fade = 1.;

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	float x = uv.x;
	float y = (uv.y - .5) * 2.;
	float w = mix(w0, w1, pow(clamp(x, 0., 1.), .72));
	// 流れの座標（口から先へ）。歪ませて炎の舌を作る
	vec2 q = vec2(x * aspect * 2.6 - flow * speed, y * 2.1 + seed);
	float warp = hfx_fbm(q * .6 + vec2(-flow * speed * .25, seed * .3), 3);
	float n = hfx_fbm(q + vec2(0., (warp - .5) * 1.8), 4);
	float n2 = hfx_fbm(q * 2.4 + vec2(-flow * speed * .7, seed * 1.7), 3);
	float edge = abs(y) / max(w, .001) + (n - .5) * rough * 2. + (n2 - .5) * rough * .7;
	float body = 1. - edge;
	// 先端は丸くちぎれ、口側の切れ目もちぎれる
	float front = (head - x) * 7. + (n - .5) * .9;
	float back_ = (x - tail) * 9. + (n2 - .5) * .7;
	float d = min(body, min(front, back_));
	COLOR = vec4(0.);
	if (d > 0.) {
		float t = clamp(d * 1.35, 0., 1.);
		float heat = pow(t, .58) * (1. - cool * x) * (.72 + core * .45) + (n2 - .5) * .34 - x * .1 + core * .18 * (1. - smoothstep(0., .35, x));
		int idx = int(floor(clamp(heat, 0., .999) * 8.));
		float a = fade;
		// 冷えた外側は点描で透かす（半透明の層を作らない）
		if (idx <= 1 && hfx_bayer(FRAGCOORD.xy, 2.) > .45 + .45 * t) { a = 0.; }
		if (fade < 1. && hfx_bayer(FRAGCOORD.xy, 2.) > fade) { a = 0.; }
		COLOR = vec4(pal[idx] * a, a);
	} else if (glow > 0.) {
		float g = exp(d * 3.2) * glow * fade * clamp(min(front, back_) + 1., 0., 1.);
		COLOR = vec4(glow_col * g * .5, 0.);
	}
}
