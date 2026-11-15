shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 噴火の柱（2026-11-14 溶岩の巨人の覚醒・覚醒後全体）。地面（base）から上へ噴き上がる炎と溶岩の柱。
// 中心は白熱、うねる炎が上へ流れ（二重にゆがめた雑音）、外側と頭は黒い煙。頭は丸くふくらむ（尖らせない）。根元は広がる。
// 2px 格子・8段の色（pal: 黒煙 → 赤 → 橙 → 黄 → 白）・点描・縁の輪郭。
uniform vec2 size = vec2(200., 400.);
uniform vec2 base = vec2(100., 380.);
uniform float width = 40.;
uniform float height = 300.;
uniform float grow = 1.;
uniform float flow = 0.;
uniform float seed = 0.;
uniform float heat = 1.;
uniform float smoke = .6;
uniform float fade = 1.;
uniform vec3 pal[8];
uniform vec3 outline_col = vec3(.06, .03, .03);
// 2026-11-15 追加（既定値は承認済みの技と同じ見た目）。溶岩の巨人の覚醒後の撃破で「柱が変に見切れている」:
// flare = 根元の広がり（煙突の口から出す時は小さく）／round_top = 1 で伸び始めの頭も丸く（根元の広がりが頭まで届いて上が平らな箱に見えた）
// soft_base = 1 で根元の下端を地面の楕円の手前の縁に沿わせる（真横の一直線で切れて見えた）
// lift = 柱の下端が浮き上がる高さ（噴火が止まって柱が地面から離れ、上へ抜けていく。下端はちぎれた煙のふち）
uniform float flare = .9;
uniform float round_top = 0.;
uniform float soft_base = 0.;
uniform float lift = 0.;
// spread = 上へ行くほど広がる割合（煙突の炎は大きく広げる）
uniform float spread = .35;

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = uv * size;
	float bay = hfx_bayer(FRAGCOORD.xy, 2.);
	float x = p.x - base.x;
	float y = base.y - p.y;
	float H = height * grow;
	vec4 col = vec4(0.);
	if (H > 2.) {
		float yn = clamp(y / max(H, 1.), 0., 1.);
		float wob = (hfx_fbm(vec2(y * .025 - flow * 2.4, seed), 3) - .5) * width * .7;
		float fl = flare * exp(-max(y, 0.) / (width * .5));
		fl *= mix(1., clamp((H - y) / (width * 1.5), 0., 1.), round_top);
		float w = width * (1. + spread * yn + .18 * sin(y * .045 - flow * 7.)) * (1. + fl);
		float xe = x - wob * yn;
		float ybot = -2. - soft_base * .28 * sqrt(max(0., w * w - xe * xe));
		float lb = lift > 0. ? lift + (hfx_fbm(vec2(xe * .05 + seed * 3., flow * 1.3), 3) - .5) * width * 1.1 : -1e5;
		float bottom = max(ybot, lb);
		float head = length(vec2(xe / (width * 1.7), (y - H) / (width * 1.25)));
		head += (hfx_fbm(vec2(atan(y - H, xe) * 2. + seed, flow * 1.5), 3) - .5) * .5;
		// 根元の下端は網点でほどく（切り抜いた縁に見せない）
		bool in_body = y > bottom + bay * 4. * soft_base && y < H && abs(xe) < w;
		// 頭が下端より下に出ない条件は lift・soft_base を使う時だけ（既定値では承認済みの技と同じ）
		if (in_body || (head < 1. && (lift + soft_base <= 0. || y > bottom))) {
			float core = in_body ? 1. - clamp(abs(xe) / max(w, 1.), 0., 1.) : .3 * (1. - head);
			vec2 q = vec2(xe / width, y / width);
			float n1 = hfx_fbm(q * vec2(1.4, .55) + vec2(seed, -flow * 3.), 3);
			float n2 = hfx_fbm(q * vec2(2.8, 1.1) + vec2(n1 * 1.6 + seed * 2., -flow * 5.), 3);
			float t = .22 + .58 * pow(core, .8) + .45 * (n2 - .5) + .12 * heat;
			// 外側と頭は黒い煙
			float sm = smoke * (smoothstep(.45, 1., 1. - core) * smoothstep(.2, .9, yn) + (in_body ? 0. : .5));
			// 浮き上がった下端は煙になって消える
			sm += lift > 0. ? .9 * (1. - smoothstep(0., width * 1.4, y - lb)) : 0.;
			t -= .55 * sm;
			t += (bay - .5) * .1;
			vec3 c = pal[clamp(int(floor(clamp(t, 0., .999) * 8.)), 0, 7)];
			float e_body = in_body ? w - abs(xe) : 0.;
			if (max(e_body, (1. - head) * width) < 1.6) { c = mix(outline_col, c, .25); }
			col = vec4(c, 1.);
		}
	}
	col *= fade;
	COLOR = col;
}
