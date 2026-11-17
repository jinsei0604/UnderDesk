shader_type canvas_item;
render_mode blend_premul_alpha;
#include "res://src/bossmaker/visuals/hero_boss/shaders/hfx.gdshaderinc"
// 振り子の給仕長の文字盤（2026-11-16）。平らな楕円の線ではなく、厚みのある真鍮の懐中時計の盤として描く。
// 真鍮の縁（光の向きで浮き彫りの明暗・下側に厚みの側面）・白磁の文字盤（左上が明るい）・時の目盛り（12・3・6・9 は太く）・
// ブレゲ針（先の手前に丸い輪。尖った三角の矢にしない）・中心の留め具・ガラスの照り返し。
// glow で縁の外に淡い光、crack でガラスのひび、shatter で盤がかけらに分かれて抜けていく。
// 2026-11-16 ユーザー「ひび割れが少し不自然」: うねる線をやめ、本物のガラスのように、ひびは真っすぐな線のつながり（かけらの境目と同じ線）で
// crack_at の一点から外へ広がる。かけらが抜ける時もそのひびの線で分かれる（ひびと砕け方がそろう）。
// 座標は論理ドット（2px 格子）。center・r・squash（傾き: 1＝正面）・rot（盤の回転）。
uniform vec2 size = vec2(200., 200.);
uniform vec2 center = vec2(100., 100.);
uniform float r = 60.;
uniform float squash = 1.;
uniform float rot = 0.;
uniform float thick = 4.;
uniform float hour = 0.;
uniform float minute = 0.;
uniform float second = -1.;
uniform float glow = 0.;
uniform vec3 glow_col = vec3(.55, .95, 1.);
uniform float crack = 0.;
uniform float shatter = 0.;
// ひびの始まる点（盤の半径を1とした座標）とかけらの大きさ（半径に対する割合）
uniform vec2 crack_at = vec2(.3, -.35);
uniform float piece = .34;
uniform float seed = 0.;
uniform float fade = 1.;
uniform float dark = 0.;
uniform vec3 brass_l = vec3(.98, .86, .55);
uniform vec3 brass = vec3(.80, .62, .30);
uniform vec3 brass_d = vec3(.42, .28, .12);
uniform vec3 face_l = vec3(.98, .96, .90);
uniform vec3 face_d = vec3(.80, .74, .62);
uniform vec3 ink = vec3(.10, .09, .12);
uniform vec3 steel = vec3(.12, .16, .30);
uniform vec3 sec_col = vec3(.78, .16, .14);
// plain = 1: 文字盤も針も無い真鍮の円盤（振り子のおもり）。中に彫った輪だけ
uniform float plain = 0.;
// hot_mark: 光らせる時の目盛り（0＝12時〜11。-1 で無し）。その時刻が「定められた時」であることを示す
uniform float hot_mark = -1.;
uniform vec3 hot_col = vec3(.55, .95, 1.);
uniform float hot = 1.;

float h1(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 h2v(vec2 p){ return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453); }

// ボロノイ: x（かけらの単位の座標）→ (一番近い点までの距離, 二番目までの距離, かけらの番号 x, y)。境目は真っすぐな線になる
// 境目の2点も返す版（ひびの線の向きと、どのかけら同士の境目かを知るため）
void vor2(vec2 x, float sd, out vec2 id1, out vec2 id2, out vec2 p1, out vec2 p2){
	vec2 n = floor(x);
	vec2 f = fract(x);
	float d1 = 8.;
	float d2 = 8.;
	id1 = vec2(0.); id2 = vec2(0.); p1 = vec2(0.); p2 = vec2(0.);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 pt = g + .15 + .7 * h2v(n + g + sd);
			float dd = length(pt - f);
			if (dd < d1) { d2 = d1; id2 = id1; p2 = p1; d1 = dd; id1 = n + g; p1 = n + pt; }
			else if (dd < d2) { d2 = dd; id2 = n + g; p2 = n + pt; }
		}
	}
}

vec4 vor(vec2 x, float sd){
	vec2 n = floor(x);
	vec2 f = fract(x);
	float d1 = 8.;
	float d2 = 8.;
	vec2 id = vec2(0.);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = .15 + .7 * h2v(n + g + sd);
			float dd = length(g + o - f);
			if (dd < d1) { d2 = d1; d1 = dd; id = n + g; }
			else if (dd < d2) { d2 = dd; }
		}
	}
	return vec4(d1, d2, id);
}

// 針: 中心から dir の向きへ長さ L。w0 根元の半幅。ブレゲの輪（mo の位置、半径 mr）。返り値 x: 内側の度合い（>0 で内）、y: 縁
vec2 hand(vec2 q, float ang, float L, float w0, float mo, float mr){
	vec2 dir = vec2(sin(ang), -cos(ang));
	vec2 n = vec2(-dir.y, dir.x);
	float al = dot(q, dir);
	float pe = abs(dot(q, n));
	float inside = -1.;
	if (al > -L * .16 && al < L) {
		float u = clamp(al / L, 0., 1.);
		float w = mix(w0, w0 * .35, u);
		// 先は短く細る（丸く終わる）
		if (u > .86) { w *= 1. - smoothstep(.86, 1., u) * .7; }
		inside = w - pe;
	}
	// 小さな盤（顔の時計など）では先の輪を付けない（黒い塊に見えた）
	if (mr > 1.2) {
		float ring = length(q - dir * L * mo);
		float moon = min(ring - mr * .55, mr - ring);
		inside = max(inside, moon);
	}
	return vec2(inside, 0.);
}

void fragment(){
	vec2 uv = hfx_grid(UV, FRAGCOORD.xy, 2.);
	vec2 p = uv * size - center;
	float cs = cos(-rot), sn = sin(-rot);
	vec2 pr = vec2(cs * p.x - sn * p.y, sn * p.x + cs * p.y);
	vec2 q = vec2(pr.x, pr.y / max(squash, .05));
	float d = length(q) / r;
	vec4 col = vec4(0.);
	vec2 L = normalize(vec2(-1., -1.25));
	// かけら（ひびの線で分かれる）。ひびの始まりに近いかけらから先に抜ける
	float ps = r * piece;
	vec4 vo = vor(q / ps, seed);
	vec2 cell = vo.zw;
	float from_hit = clamp(length((cell + .5) * ps / r - crack_at) / 1.8, 0., 1.);
	float hv = clamp(.45 * h1(cell + seed) + .55 * from_hit, 0., 1.) * .92 + .04;
	float gone = step(hv, shatter);
	// ひびの線（かけらの境目）までの距離（画素）と、その線を見せるか
	vec2 id1; vec2 id2; vec2 p1; vec2 p2;
	vor2(q / ps, seed, id1, id2, p1, p2);
	vec2 xn = q / ps;
	vec2 nrm = normalize(p2 - p1 + vec2(.0001));
	float edge_px = abs(dot(xn - (p1 + p2) * .5, nrm)) * ps;
	// ガラスのひびらしく: 割れた点から外へ伸びる長いひび（線が割れた点の方を向く）を主に、横のつなぎは所々だけ
	vec2 hit_q = crack_at * r / ps;
	vec2 radial = normalize(xn - hit_q + vec2(.0001));
	float along = abs(dot(nrm, radial));
	float pair = h1(id1 + id2 + seed * 3.1);
	bool shown_edge = (along < .5 && pair < .9) || pair < .22;
	// 厚みの側面（傾いている時だけ見える、下側の帯）
	vec2 qs = vec2(pr.x, (pr.y - thick * (1. - squash) * 2.2) / max(squash, .05));
	float ds = length(qs) / r;
	if (d > 1. && ds <= 1.) {
		float sh = .5 + .5 * (qs.x / r);
		col = vec4(mix(brass_d, brass, .35 + .4 * sh) * (1. - .45 * dark), 1.);
		if (ds > .96) { col.rgb = mix(col.rgb, ink, .6); }
	}
	if (d <= 1.) {
		vec2 nd = normalize(q + vec2(.0001));
		float a = atan(q.x, -q.y);
		if (d > .84) {
			// 真鍮の縁: 外半分は光の側が明るく、内半分は逆（浮き彫り）
			float k = (d - .84) / .16;
			float lit = dot(nd, L) * (k > .5 ? 1. : -1.);
			vec3 c = mix(brass, brass_l, smoothstep(.0, .8, lit));
			c = mix(c, brass_d, smoothstep(.0, -.8, lit));
			// 外の縁の刻み（ローレット）
			if (d > .95 && fract(a / 6.2832 * 72.) < .45) { c = mix(c, brass_d, .45); }
			if (d > .975 || (d > .84 && d < .86)) { c = mix(c, ink, .7); }
			col = vec4(c * (1. - .45 * dark), 1.);
		} else {
			if (plain > .5) {
				float pl = dot(q / r, L);
				vec3 pc = mix(brass_d, brass_l, clamp(.5 + .7 * pl, 0., 1.));
				if (abs(d - .5) < 1.2 / r + .01) { pc = mix(pc, ink, .5); }
				if (d < .14) { pc = mix(brass_l, brass, .5); }
				col = vec4(pc * (1. - .45 * dark), 1.);
			} else {
			// 白磁の文字盤: 左上が明るく、縁の近くは影
			float lit = dot(q / r, L);
			vec3 c = mix(face_d, face_l, clamp(.55 + .6 * lit, 0., 1.));
			c = mix(c, face_d * .85, smoothstep(.74, .84, d));
			// 文字の輪
			if (abs(d - .78) < .012 + 1. / r) { c = mix(c, ink, .7); }
			// 時の目盛り
			float seg = a / 6.2832 * 12.;
			float fi = floor(seg + .5);
			float off = abs(seg - fi) * 6.2832 / 12. * d * r;
			bool quarter = mod(fi, 3.) < .5;
			// 目盛りの太さは盤の大きさに合わせる（小さな盤は 12・3・6・9 だけ。太いと歯車の歯に見えた）
			float mw = quarter ? clamp(r * .028, .7, 1.9) : clamp(r * .016, .5, 1.1);
			bool show_mark = quarter || r >= 30.;
			if (show_mark && d > (quarter ? .6 : .64) && d < .76 && off < mw) { c = ink; }
			if (hot_mark >= 0. && abs(mod(fi, 12.) - hot_mark) < .5 && d > .52 && d < .8 && off < mw * 2.2 + 1.) { c = mix(c, hot_col, hot); }
			// 分の点
			float ms = a / 6.2832 * 60.;
			if (abs(d - .81) < 1.2 / r && abs(ms - floor(ms + .5)) * 6.2832 / 60. * d * r < .8 && r > 30.) { c = mix(c, ink, .6); }
			col = vec4(c * (1. - .55 * dark), 1.);
			// 針（時・分・秒）
			bool tiny = r < 14.;
			vec2 hh = hand(q, hour, r * .5, tiny ? .55 : r * .05 + .6, .74, tiny ? 0. : r * .075);
			vec2 hm = hand(q, minute, r * .72, tiny ? .45 : r * .04 + .5, .8, tiny ? 0. : r * .06);
			float steel_in = max(hh.x, hm.x);
			if (steel_in > -1.) {
				vec3 sc = steel;
				if (steel_in > 0.) { col.rgb = mix(sc, vec3(.55, .65, .9), .25 * step(1.2, steel_in)); }
				else if (!tiny) { col.rgb = mix(col.rgb, ink, .85); }
			}
			if (second >= 0.) {
				vec2 dir = vec2(sin(second), -cos(second));
				float al = dot(q, dir);
				float pe = abs(dot(q, vec2(-dir.y, dir.x)));
				if (al > -r * .2 && al < r * .78 && pe < .9) { col.rgb = sec_col; }
			}
			// 中心の留め具
			if (d < .07) { col.rgb = d < .045 ? mix(brass_l, brass, step(0., dot(q, -L))) : ink; }
			// ガラスの照り返し（左上の細い弧）
			if (d > .5 && d < .66 && a < -1.75 && a > -2.6) { col.rgb = mix(col.rgb, vec3(1.), .35); }
			// ガラスのひび: かけらの境目の真っすぐな線が、始まりの点から外へ伸びていく。始まりの近くは細かいひびも入る
			if (crack > 0.) {
				float dd = length(q / r - crack_at);
				float jit = hfx_fbm(q / r * 3. + seed, 2) * .35;
				bool reached = dd + jit < crack * 1.7 && shown_edge;
				if (reached && edge_px < 1.0) { col.rgb = mix(col.rgb, vec3(1.), .85); }
				else if (reached && edge_px < 2.0) { col.rgb = mix(col.rgb, ink, .5); }
				// 小さな盤では細かいひびを出さない（白い星のように見えた）
				else if (dd + jit < crack * .45 && r >= 20.) {
					vec4 fine = vor(q / (ps * .42), seed + 5.);
					float fe = (fine.y - fine.x) * ps * .42 * .5;
					if (fe < .8) { col.rgb = mix(col.rgb, vec3(1.), .6); }
				}
			}
			}
		}
		if (gone > .5) { col = vec4(0.); }
		else if (shatter > 0.) {
			// 抜ける直前のかけらの縁が光る（ひびの線に沿って）
			if (hv - shatter < .08 && edge_px < 2.5) { col.rgb = mix(col.rgb, glow_col, .7); }
		}
	}
	// 縁の外の淡い光（時が止まる・動く時）
	if (glow > 0. && col.a < .5 && d > 1. && d < 1.35) {
		float g = (1. - (d - 1.) / .35);
		g *= g * glow * (1. - shatter);
		float bay = hfx_bayer(FRAGCOORD.xy, 2.);
		if (g > bay * .9) { col = vec4(glow_col, .55 * g + .2); }
	}
	col.a *= fade;
	col.rgb *= col.a;
	COLOR = col;
}
