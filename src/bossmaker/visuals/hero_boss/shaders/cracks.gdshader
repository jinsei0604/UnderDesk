shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 地面の放射状のひび。着弾点から枝分かれしながら外へ走る線（網目にしない）。
uniform vec2 size = vec2(800., 520.);
uniform vec2 center = vec2(400., 260.);
uniform float reveal = 100.;
uniform float squash = .3;
uniform float seed = 0.;
uniform float line_w = .05;
uniform vec3 pal[4];
uniform vec3 glow_col = vec3(1., .2, .3);
uniform float glow = .6;
uniform float fade = 1.;
uniform float clip_y = 222.;

// 1本のひびの中心からの距離（1で線の縁）。範囲外は大きな値。
float layer(float ang, float r, float n, float s, float start, float width_px){
	float wander = (hfx_fbm(vec2(r * .016 + s, s * 3.), 3) - .5) * 1.5 + (hfx_n(vec2(r * .11, s + 5.)) - .5) * .32;
	float a = ang / 6.2832 * n + wander;
	float id = floor(a);
	float f = abs(fract(a) - .5);
	float len = reveal * (.4 + .75 * hfx_h(vec2(id, s)));
	float st = start * hfx_h(vec2(id, s + 3.));
	float keep = step(.32, hfx_h(vec2(id, s + 9.)));
	float result = 1e3;
	if (keep > .5 && r > st && r < len) {
		float taper = pow(1. - (r - st) / max(len - st, 1.), .6);
		float px = f * 6.2832 * r / n;
		result = px / max(width_px * taper, .3);
	}
	return result;
}

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = (uv * size - center) / vec2(1., squash);
	float r = length(p), ang = atan(p.y, p.x);
	float w = line_w * 60.;
	float d = min(layer(ang, r, 15., seed, 0., w), layer(ang, r, 37., seed + 11., reveal * .34, w * .55));
	COLOR = vec4(0.);
	if (uv.y * size.y > clip_y && d < 1.) {
		int idx = int(floor(clamp((1. - d) * 1.3, 0., .999) * 4.));
		COLOR = vec4(pal[idx] * fade, fade);
	} else if (glow > 0. && d < 6. && uv.y * size.y > clip_y) {
		COLOR = vec4(glow_col * exp(-(d - 1.) * .9) * glow * fade, 0.);
	}
}
