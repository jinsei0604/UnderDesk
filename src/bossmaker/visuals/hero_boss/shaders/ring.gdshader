shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 地面を走る衝撃波。楕円で、ノイズで千切れた帯。
uniform vec2 size = vec2(800., 520.);
uniform vec2 center = vec2(400., 260.);
uniform float radius = 40.;
uniform float thick = 8.;
uniform float squash = .32;
uniform float breakup = .5;
uniform float seed = 0.;
uniform vec3 pal[4];
uniform float glow = .5;
uniform vec3 glow_col = vec3(.3, .7, 1.);
uniform float fade = 1.;

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = (uv * size - center) / vec2(1., squash);
	float r = length(p), ang = atan(p.y, p.x);
	float n = hfx_fbm(vec2(cos(ang), sin(ang)) * 2.4 + vec2(seed), 3);
	float w = thick * (1. + (n - .5) * 2.6 * breakup);
	float t = 1. - abs(r - radius) / max(w, .1);
	t -= breakup * smoothstep(.56, .78, hfx_fbm(vec2(ang * 3.5 + seed * 3., radius * .012), 2)) * .9;
	COLOR = vec4(0.);
	if (t > 0.) {
		int idx = int(floor(clamp(t * 1.25, 0., .999) * 4.));
		float a = fade;
		COLOR = vec4(pal[idx] * a, a);
	} else if (glow > 0.) {
		float g = exp(-max(abs(r - radius) - w, 0.) / (w * 2.2 + 4.)) * glow * fade;
		COLOR = vec4(glow_col * g * .7, 0.);
	}
}
