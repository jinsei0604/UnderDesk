shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 地面から天へ貫く光の柱。下辺が地面。
uniform vec3 pal[6];
uniform float width = .5;
uniform float flow = 0.;
uniform float seed = 0.;
uniform float flare = .5;
uniform vec3 glow_col = vec3(1., .8, .4);
uniform float glow = .7;
uniform float fade = 1.;

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	float x = (uv.x - .5) * 2.;
	float y = 1. - uv.y;
	float w = width * (1. + flare * pow(1. - y, 5.) * 1.6 + .12 * sin(y * 9. - flow * 8.));
	float edge = (hfx_fbm(vec2(y * 7. - flow * 3.5, seed + sign(x) * 3.), 3) - .5) * .42 * w;
	float t = 1. - (abs(x) + edge) / max(w, .001);
	COLOR = vec4(0.);
	if (t > 0.) {
		t += (hfx_fbm(vec2(x * 8., y * 2.5 - flow * 4. + seed), 2) - .5) * .35;
		int idx = int(floor(clamp(t * 1.5, 0., .999) * 6.));
		float a = fade * smoothstep(0., .08, y);
		COLOR = vec4(pal[idx] * a, a);
	} else if (glow > 0.) {
		float g = pow(max(1. + t * .55, 0.), 3.) * glow * fade * (1. - smoothstep(.55, 1., abs(x))) * smoothstep(0., .16, y);
		COLOR = vec4(glow_col * g, 0.);
	}
}
