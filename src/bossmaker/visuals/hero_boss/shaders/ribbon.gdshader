shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 斬撃・光線・触手の帯。UV.x が長さ方向、UV.y が幅（-1..1）。段階色の芯＋外側の光。
uniform vec3 pal[6];
uniform float head = 1.;
uniform float tail = 0.;
uniform float body = .55;
uniform float taper = .7;
uniform float skew = 1.;
uniform float rough = 0.;
uniform float rough_freq = 18.;
uniform float streak = .25;
uniform float flow = 0.;
uniform float seed = 0.;
uniform float gain = 1.1;
uniform float core_shift = 0.;
uniform float glow = .6;
uniform vec3 glow_col = vec3(.3, .7, 1.);
uniform float fade = 1.;
uniform float root_len = 0.;

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	float s = (uv.x - tail) / max(head - tail, .0005);
	COLOR = vec4(0.);
	if (s > 0. && s < 1. && fade > 0.) {
		float env = pow(sin(3.14159 * pow(s, skew)), taper);
		if (root_len > 0.) { env *= .05 + .95 * smoothstep(0., root_len, uv.x - tail); }
		float tear = 1. + rough * (hfx_fbm(vec2(uv.x * rough_freq + flow * .4, seed + (uv.y > 0. ? 7. : 0.)), 3) - .5) * 2.;
		float w = max(body * env * tear, .0001);
		float x = uv.y - core_shift * w;
		float t = 1. - abs(x) / w;
		if (t > 0.) {
			t += streak * (hfx_fbm(vec2(uv.x * 7. - flow * 2., uv.y * 11. + seed), 2) - .5);
			int idx = int(floor(clamp(t * gain, 0., .999) * 6.));
			float a = fade;
			COLOR = vec4(pal[idx] * a, a);
		} else if (glow > 0.) {
			float g = pow(max(1. - (abs(x) - w) / max(1. - w, .001), 0.), 2.6) * glow * env * fade * smoothstep(.02, .22, body);
			COLOR = vec4(glow_col * g, 0.);
		}
	}
}
