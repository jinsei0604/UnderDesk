shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 金環の聖獣／日蝕の獅皇の日蝕の光輪。黒い円盤（月）と、縁から揺らめく光冠（炎のような帯）。2px 格子・段階色。
// size: 矩形の大きさ（論理ドット）、center・radius: 円盤、corona: 光冠の長さ、power: 強さ、flow: 時間、bite: 円盤のずれ（0で皆既）
uniform vec2 size = vec2(240., 240.);
uniform vec2 center = vec2(120., 120.);
uniform float radius = 50.;
uniform float corona = 40.;
uniform float power = 1.;
uniform float flow = 0.;
uniform float seed = 0.;
uniform vec2 bite = vec2(0.);
uniform vec3 pal[6];
// 恐ろしい色（深紅と黒）。dread で pal から移る
uniform vec3 pal2[6];
uniform float dread = 0.;
// 太陽の面の明るさ（0で面なし。月に隠れていない所だけ光る）
uniform float sun_fill = 0.;
uniform vec3 sun_col = vec3(1., .86, .5);
uniform vec3 disc_col = vec3(.02, .01, .03);
uniform float rim = 1.;
uniform float fade = 1.;
// 月の大きさ（太陽に対する割合。1未満で金の輪が残る金環日食）
uniform float moon_k = 1.;
// 欠ける量（0〜1）: 上から左右へ回り込むように、輪と光冠が欠けて消えていく。縁は少しぎざぎざにほどける
uniform float wane = 0.;
// 月の円盤の濃さ（輪が欠けて消える時に、黒い円盤だけが残らないように一緒に薄くする）
uniform float disc_fade = 1.;

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = uv * size - center;
	float r = length(p);
	float ang = atan(p.y, p.x);
	// 光冠: 角度ごとに長さが揺らぐ炎の帯（尖った線にしない。丸い塊が流れる）
	float n1 = hfx_fbm(vec2(ang * 3.2 + seed, r * .045 - flow * 1.4), 3);
	float n2 = hfx_n(vec2(ang * 7. - flow * .6 + seed * 2., r * .08 - flow * 2.));
	float len = corona * (.55 + .75 * n1 + .25 * n2) * power;
	float d = r - radius;
	vec4 col = vec4(0.);
	// 欠けた所（角度で上から両側へ。0=上、1=下まで全部）
	float side_a = abs(atan(p.x, -p.y)) / 3.14159;
	float gone = step(side_a + (hfx_n(vec2(ang * 9. + seed, floor(flow * 6.))) - .5) * .08, wane * 1.08);
	bool cut = wane > 0. && gone > .5 && r > radius * moon_k - 1.;
	if (d > 0. && d < len) {
		float u = d / max(len, .001);
		float tone = (1. - u) * (.75 + .35 * n2);
		tone = clamp(tone, 0., .999);
		int idx = int(floor(tone * 6.));
		float a = smoothstep(1., .7, u) * fade;
		vec3 pc = mix(pal[idx], pal2[idx], step(hfx_bayer(FRAGCOORD.xy, 2.), dread));
		col = vec4(pc * a, a);
	}
	// 縁の細い光
	float edge = 1. - smoothstep(0., 3., abs(d));
	if (edge > 0.) {
		vec3 rc = mix(pal[5], pal2[5], dread) * rim;
		col.rgb = mix(col.rgb, rc * fade, edge * .9);
		col.a = max(col.a, edge * fade * rim);
	}
	// 太陽の面（月に隠れていない所だけ）: 中心ほど白く、縁は金
	if (r < radius - 1. && sun_fill > 0.) {
		float k = r / radius;
		vec3 sc = mix(vec3(1., .98, .9), sun_col, smoothstep(.2, 1., k));
		sc = mix(sc, mix(pal[4], pal2[4], dread), smoothstep(.75, 1., k) * .6);
		col = vec4(sc * sun_fill * fade, sun_fill * fade);
	}
	// 円盤（月）: 少しずらすと欠けた日蝕になる
	float rd = length(p - bite);
	// 月は太陽と光冠に重なる所だけ見える（明るい空では月そのものは見えない）
	if (rd < radius * moon_k - 1. && r < radius + len * .9) {
		col = vec4(disc_col * fade * disc_fade, fade * disc_fade);
	}
	// 欠けた所: 金の輪と光冠を消す（月の円盤だけ残る）
	if (cut) {
		col = rd < radius * moon_k - 1. ? vec4(disc_col * fade * disc_fade, fade * disc_fade) : vec4(0.);
	}
	COLOR = col;
}
