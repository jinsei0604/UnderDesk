shader_type canvas_item;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 白磁のカラーの登場（2026-11-14 ユーザー案「花びらが最初は少し → だんだん多く → 全画面を覆い隠す → 晴れる」）。
// 画面いっぱいに舞う花びら（奥・中・手前の3層。手前ほど大きく速い）。cover 0〜1 で数が増え、1 で隙間なく画面を覆う。
// 花びらは先の丸いしずく形（尖らせない）・濃い縁・根元から先へ明るく・回りながら裏返る（幅が変わる）。2px 格子。
// 数が増える・減る時は、1枚ずつ薄くなって現れる／消える（急に出たり消えたりしない）。
// 2026-11-15 ユーザー「花びらがありすぎて気持ち悪い」: 小さな花びらが数千枚すき間なく並んで集合体に見えた
// → 枚数を約1/20に（最も多い時でも見えるのは数十枚）、花びらを大きく（手前はカメラのすぐ前を横切る大きな花びら）。
//   画面を覆う時は、奥の小さな花びらを淡い花びらのもや（大きなまだら）で隠し、その上を中と手前の大きな花びらだけが舞う。
uniform vec2 size = vec2(720., 440.);
uniform float cover = 0.;
uniform float travel = 0.;
uniform float time = 0.;
uniform float fade = 1.;
uniform vec3 c_white = vec3(.984, .973, .933);
uniform vec3 c_ivory = vec3(.91, .886, .816);
uniform vec3 c_blush = vec3(.957, .847, .863);
uniform vec3 c_shade = vec3(.80, .82, .76);
uniform vec3 c_line = vec3(.30, .36, .29);

float h1(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 h2(vec2 p){ return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }

// 花びらの幅の形（0〜1 の長さの位置 → 0〜1 の半幅）。先は丸い。
float prof(float x){
	return x < .62 ? sin(x / .62 * 1.5708) : sqrt(max(0., 1. - pow((x - .62) / .38, 2.)));
}

// 1層ぶん。res に重ねる（奥から手前へ呼ぶ）。
void layer(vec2 p, float cell, float speed, float salt, float prob, float sz, inout vec4 res){
	if (prob <= 0.) { return; }
	vec2 q = p + vec2(travel * speed, 0.);
	vec2 id0 = floor(q / cell);
	float best = -1.;
	vec4 col = vec4(0.);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = id0 + vec2(float(i), float(j));
			float r = h1(id + salt);
			float a = clamp((prob - r) / .08, 0., 1.);
			if (a <= 0.) { continue; }
			vec2 o = h2(id + salt * 1.7);
			vec2 c = (id + .2 + .6 * o) * cell + vec2(0., sin(time * (1.2 + o.x) + id.x * 1.3) * cell * .22);
			float ang = o.y * 6.2832 + time * (1.4 + 2.4 * o.x) * (o.x > .5 ? 1. : -1.);
			float flip = abs(cos(time * (1.6 + 2.6 * o.y) + id.y * 2.1));
			vec2 u = vec2(cos(ang), sin(ang));
			vec2 n = vec2(-u.y, u.x);
			float L = cell * sz * (.8 + .4 * o.x);
			float W = L * .62 * (.3 + .7 * flip);
			vec2 d = q - c;
			float xl = dot(d, u) + L * .5;
			float yl = abs(dot(d, n));
			// 縁（外側 1px。大きな花びらは途切れて点線に見えないよう 1.7px）を含む大きさで当たりを見る
			float ow = cell > 60. ? 1.7 : 1.;
			float xo = (xl + ow) / (L + 2. * ow);
			if (xo < 0. || xo > 1.) { continue; }
			float wo = prof(xo) * (W * .5 + ow);
			if (yl > wo) { continue; }
			float z = r + float(j + 1) * .001;
			if (z < best) { continue; }
			best = z;
			float x = xl / L;
			float wi = (x >= 0. && x <= 1.) ? prof(x) * W * .5 : -1.;
			vec3 base = (fract(r * 37.) < .14) ? c_blush : c_ivory;
			vec3 cc = mix(base, c_white, clamp(x, 0., 1.));
			// 裏返って細く見える時と片側は少し影
			cc = mix(cc, c_shade, (1. - flip) * .4 + step(0., dot(d, n)) * .1);
			// 大きな花びら: 縁へ向かって少し反って暗く・中ほどに細い筋（平らな紙に見せない）
			float side = wi > 0. ? yl / wi : 1.;
			cc = mix(cc, c_shade, .28 * smoothstep(.55, 1., side) * step(40., cell));
			if (cell > 60. && yl < 1.3 && x > .1 && x < .68) { cc = mix(cc, c_shade, .3); }
			// 輪郭: 大きな花びらは濃すぎない色（切り絵に見せない）
			if (yl > wi) { cc = cell > 100. ? mix(c_line, c_shade, .45) : c_line; }
			col = vec4(cc, a);
		}
	}
	if (best >= 0.) {
		res.rgb = mix(res.rgb, col.rgb, col.a);
		res.a = res.a + col.a * (1. - res.a);
	}
}

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = uv * size;
	float k = clamp(cover, 0., 1.);
	// 奥: 覆う直前に、花びらの隙間を淡い花びらの色で埋める（全画面が花びらで埋まって見えるように）
	vec4 res = vec4(0.);
	// 奥: 小さめの花びら（最初の数枚はここから）
	layer(p, 46., .7, 3.1, min(.42, .03 + .9 * k * k), .5 + .1 * k, res);
	// 花びらのもや（覆う直前から。大きなまだらで、平らな幕にしない）。奥の花びらを隠す
	// 全体を半透明で重ねると灰色の霧に、なめらかなまだらで埋めると牛柄のかたまりに見えたので、網点（2px の格子）で少しずつ埋める（まだらで場所ごとに早い遅いをつける）
	float k2 = smoothstep(.62, .97, k);
	float m0 = hfx_fbm(p * .008 + vec2(travel * .003, 4.1), 3);
	// 雑音の値は真ん中に寄るので 0〜1 に広げ、埋まり始めから埋まり切るまでをゆっくりにする
	float m0n = clamp((m0 - .3) / .4, 0., 1.);
	float th = .6 * hfx_bayer(FRAGCOORD.xy, 2.) + .4 * m0n;
	float fill = step(th, k2 * 1.1 - .05) * .97;
	float m1 = hfx_fbm(p * .011 + vec2(travel * .004, time * .05), 3);
	float m2 = hfx_fbm(p * .028 + vec2(travel * .009, 1.7), 2);
	vec3 hz = mix(c_ivory, c_white, smoothstep(.3, .7, m1));
	hz = mix(hz, c_shade, .16 * smoothstep(.5, .8, m2));
	hz = mix(hz, c_blush, .14 * smoothstep(.3, .6, m1 * m2 * 1.6));
	res.rgb = mix(res.rgb, hz, fill);
	res.a = res.a + fill * (1. - res.a);
	// 中: 大きめの花びら
	layer(p, 86., 1., 7.3, clamp(1.1 * k - .25, 0., .5), .62 + .1 * k, res);
	// 手前: カメラのすぐ前を横切る大きな花びら（覆う時の主役）
	layer(p, 170., 1.5, 11.9, clamp(1.9 * k - .95, 0., .9), .8 + .1 * k, res);
	COLOR = vec4(res.rgb, res.a * fade);
}
