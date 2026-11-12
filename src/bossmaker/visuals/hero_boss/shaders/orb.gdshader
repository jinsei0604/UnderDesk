shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 圧縮されたエネルギーの球。外殻は渦を巻き、周りに棘の光冠を持つ。
uniform vec3 pal[8];
uniform float radius = .4;
uniform float flow = 0.;
uniform float seed = 0.;
uniform float spike = .35;
uniform vec3 glow_col = vec3(.3, .7, 1.);
uniform float glow = .8;
uniform float fade = 1.;

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = (uv - .5) * 2.;
	float r = length(p), ang = atan(p.y, p.x);
	float swirl = hfx_fbm(vec2(ang * 1.9 + r * 5. - flow * 2.6, r * 6. - flow * 1.4 + seed), 3);
	float crown = pow(hfx_n(vec2(ang * 6. + seed, flow * 3.)), 2.) * spike;
	float R = radius * (1. + crown * .5 + (swirl - .5) * .22);
	float t = 1. - r / max(R, .001);
	COLOR = vec4(0.);
	if (t > 0.) {
		float tone = pow(t, .55) * .85 + (swirl - .5) * .6 * (1. - t);
		int idx = int(floor(clamp(tone, 0., .999) * 8.));
		float a = fade;
		COLOR = vec4(pal[idx] * a, a);
	} else if (glow > 0.) {
		float g = exp(t * 3.6) * glow * fade * (1. - smoothstep(.72, 1., r));
		COLOR = vec4(glow_col * g, 0.);
	}
}
