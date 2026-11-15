shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 溶けた溶岩の液体（2026-11-14 溶岩の巨人。指摘「溶岩の形が集合体すぎて気持ち悪い」→ 網目・点・穴の模様を使わない）。
// いくつもの丸（balls: x, y, 半径, 熱）がなめらかに溶け合う形（メタボール）。丸が離れると首が細く伸びてちぎれる（垂れる・滴る）。
// 内側ほど熱く明るい・左上からの光とつや・流れに沿う暗い筋（縁ほど冷えて暗い）・縁の濃い輪郭・周りのほのかな光。2px 格子・8段の色・点描。
uniform vec2 size = vec2(200., 200.);
uniform vec4 balls[32];
uniform int count = 0;
uniform float thresh = 1.;
uniform float flow = 0.;
uniform float seed = 0.;
uniform float fade = 1.;
uniform float glow = .5;
uniform float heat = 1.;
// 縦の潰し（1未満で地面に平たく広がる溜まり）
uniform float squash = 1.;
uniform vec3 pal[8];
uniform vec3 outline_col = vec3(.08, .03, .02);
uniform vec3 glow_col = vec3(1., .45, .12);

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = uv * size;
	float bay = hfx_bayer(FRAGCOORD.xy, 2.);
	float f = 0.;
	vec2 g = vec2(0.);
	float hs = 0.;
	for (int i = 0; i < 32; i++) {
		if (i >= count) { break; }
		vec4 b = balls[i];
		vec2 d = (p - b.xy) / vec2(1., squash);
		float dd = dot(d, d) + 1.;
		float q = b.z * b.z / dd;
		f += q;
		g += -2. * q * d / dd;
		hs += q * b.w;
	}
	vec4 col = vec4(0.);
	if (f >= thresh) {
		float h = clamp(hs / max(f, 1e-4), 0., 1.) * heat;
		float depth = clamp((f - thresh) / (thresh * 1.8), 0., 1.);
		vec3 n = normalize(vec3(-g * 7., 1.));
		float lam = clamp(dot(n, normalize(vec3(-.5, -.7, .6))), 0., 1.);
		float fl = hfx_fbm(p * vec2(.045, .028) + vec2(seed, -flow * 1.3), 3);
		float streak = smoothstep(.5, .68, fl) * (1. - .55 * depth) * (1. - .45 * h);
		float t = .2 + .4 * depth * (.4 + .6 * h) + .24 * lam - .44 * streak;
		t += (hfx_n(p * .18 + vec2(0., flow * 3.)) - .5) * .1 + (bay - .5) * .08;
		vec3 c = pal[clamp(int(floor(clamp(t, 0., .999) * 8.)), 0, 7)];
		float spec = pow(lam, 14.) * (1. - streak);
		c = mix(c, vec3(1., .96, .82), step(.5, spec) * .85);
		if (f < thresh * 1.14) { c = mix(outline_col, c, .28); }
		col = vec4(c, 1.);
	} else if (glow > 0.) {
		float gk = smoothstep(thresh * .3, thresh, f) * glow * heat;
		col = vec4(glow_col * gk * .55, 0.);
	}
	col *= fade;
	COLOR = col;
}
