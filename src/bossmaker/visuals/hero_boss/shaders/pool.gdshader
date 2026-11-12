shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 足元から地面へ広がる闇の侵食。縁は紅く、内側に脈が走る。
uniform vec2 size = vec2(800., 520.);
uniform vec2 center = vec2(400., 260.);
uniform float radius = 60.;
uniform float squash = .3;
uniform float seed = 0.;
uniform float flow = 0.;
uniform vec3 pal[5];
uniform float fade = 1.;
uniform float clip_y = 222.;

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = (uv * size - center) / vec2(1., squash);
	float r = length(p), ang = atan(p.y, p.x);
	float n = hfx_fbm(vec2(cos(ang), sin(ang)) * 3.2 + vec2(seed, flow * .3), 4);
	float tendril = pow(hfx_n(vec2(ang * 7. + seed, 1.)), 3.) * .9;
	float d = r / max(radius * (.68 + n * .62 + tendril), 1.) - 1.;
	COLOR = vec4(0.);
	float a = fade;
	if (d < 0.) {
		int idx = 0;
		if (d > -.05) { idx = 4; }
		else if (d > -.11) { idx = 3; }
		else if (d > -.2) { idx = 2; }
		else {
			float v = abs(2. * hfx_fbm(p * .045 + vec2(seed, flow * .5), 3) - 1.);
			idx = v < .06 ? 2 : (v < .14 ? 1 : 0);
		}
		COLOR = vec4(pal[idx] * a, a);
	}
}
