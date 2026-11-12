shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 地面を横断する亀裂。UV.x が長さ方向で、origin から head まで開く。
uniform vec2 size = vec2(800., 180.);
uniform float origin = .3;
uniform float head_l = 0.;
uniform float head_r = 0.;
uniform float open_w = 10.;
uniform float seed = 0.;
uniform float flow = 0.;
uniform vec3 pal[6];
uniform vec3 glow_col = vec3(1., .15, .25);
uniform float glow = .8;
uniform float fade = 1.;

float centre(float x){
	return (hfx_fbm(vec2(x * 7. + seed, 2.), 3) - .5) * size.y * .55
		+ (hfx_n(vec2(x * 34. + seed, 9.)) - .5) * 7.;
}

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	float y = (uv.y - .5) * size.y - centre(uv.x);
	float side = uv.x < origin ? (origin - uv.x) / max(origin - head_l, .001) : (uv.x - origin) / max(head_r - origin, .001);
	float along = clamp(1. - side, 0., 1.);
	float vary = .62 + .76 * hfx_n(vec2(uv.x * 24. + seed, 5.));
	float w = open_w * pow(along, .55) * vary;
	float t = 1. - abs(y) / max(w, .01);
	float branch = 0.;
	if (side < 1.) {
		float bx = uv.x * 18. + seed;
		float bid = floor(bx);
		float tilt = (hfx_h(vec2(bid, seed)) - .5) * 2.;
		float bf = (fract(bx) - .5) * 2.;
		float line = y - tilt * size.y * .36 * abs(bf) * sign(bf + tilt);
		branch = (1. - abs(line) / (1.1 + along)) * (1. - abs(bf));
	}
	COLOR = vec4(0.);
	if (side < 1.) {
		float a = fade;
		if (t > 0.) {
			int idx = int(floor(clamp(t * 1.15, 0., .999) * 6.));
			COLOR = vec4(pal[idx] * a, a);
		} else if (branch > .25) {
			COLOR = vec4(pal[branch > .55 ? 2 : 1] * a, a);
		} else if (glow > 0.) {
			COLOR = vec4(glow_col * exp(-(abs(y) - w) / 14.) * glow * fade * along, 0.);
		}
	}
}
