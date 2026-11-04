shader_type canvas_item;
// 朽ちた機械武者の登場（rbm_intro_musha.gd）で画面を覆う墨（表示専用。色は時刻と座標だけから決まり、戦闘の状態・乱数には触れない）。
// 多角形の UV = 画面上の位置 / 画面の大きさ（rbm_intro_musha_ink.gd が全面を1枚の多角形で描く）。
// - 一滴が弾けて広がる: cover 0→1 で center から指のような縁と周りの小さな滴ごと広がって画面を呑む
// - 墨の濃淡: ほとんど黒。わずかな溜まりのむら・紙の繊維・やわらかい濡れた艶だけで墨に見せる（大きな濃淡は付けない）
// - 渦: churn で武者の方へわずかに引き込まれて震える
// - 3本の切れ目から弾けて開く: hole 0→1 で、斬った線（hole_line1〜3）からぎざぎざの縁で一気に開く

uniform vec2 screen = vec2(1280.0, 720.0);
uniform float pix = 2.0;              // ドット絵に合わせた格子（px）
uniform float time = 0.0;
uniform float cover = 0.0;
uniform vec2 center = vec2(640.0, 330.0);
uniform float churn = 0.0;
uniform float hole = 0.0;
uniform vec4 hole_line1 = vec4(0.0, 0.0, 1280.0, 0.0);
uniform vec4 hole_line2 = vec4(0.0, 0.0, 1280.0, 0.0);
uniform vec4 hole_line3 = vec4(0.0, 0.0, 1280.0, 0.0);
uniform vec3 ink_dark = vec3(0.008, 0.008, 0.014);
uniform vec3 ink_light = vec3(0.045, 0.044, 0.060);
uniform vec3 halo = vec3(0.24, 0.235, 0.25);  // にじみの外側の薄い墨
uniform float sheen = 1.5;            // 濡れた艶
uniform float rim = 0.6;              // にじみの縁の濃さ

float h21(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
// oct: 重ねる数（大きな形は少なくても見た目が変わらないので、場所ごとに減らして軽くする）
float fbm(vec2 p, int oct){
	const mat2 R = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	float v = 0.0; float a = 0.52; float n = 0.0;
	for (int i = 0; i < oct; i++) { v += a * vnoise(p); n += a; p = R * p * 2.03 + vec2(3.1, 7.7); a *= 0.5; }
	return v / n;
}
float rn(vec2 p){ return vnoise(mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80)) * p); }
vec2 rot(vec2 v, float a){ float c = cos(a); float s = sin(a); return vec2(c * v.x - s * v.y, s * v.x + c * v.y); }

void fragment(){
	vec2 p = floor(UV * screen / pix) * pix + pix * 0.5;
	// --- 一滴が弾けて広がる ---
	vec2 d0 = p - center; float r = length(d0); float an = atan(d0.y, d0.x);
	float R = cover * 900.0;
	float fing = pow(vnoise(vec2(an * 9.0, 1.3)), 3.0) * 0.55 + (vnoise(vec2(an * 23.0, 7.1)) - 0.5) * 0.14;
	float edge = R * (0.80 + fing) - r + (vnoise(p / 9.0) - 0.5) * 10.0;
	vec2 cell = floor(p / 46.0);
	for (int j = -1; j <= 1; j++) { for (int i = -1; i <= 1; i++) {
		vec2 c = cell + vec2(float(i), float(j));
		vec2 sp = (c + 0.15 + 0.7 * vec2(h21(c), h21(c + 17.0))) * 46.0;
		float sr = 3.0 + 12.0 * pow(h21(c + 5.0), 3.0);
		float on = step(length(sp - center), R * 1.30) * step(0.55, h21(c + 9.0));
		edge = max(edge, on * (sr - length(p - sp)) - (1.0 - on) * 999.0);
	}}
	// --- 墨の濃淡 ---
	vec2 q = p;
	if (churn > 0.0) {
		vec2 vc[2] = vec2[2](vec2(470.0, 300.0), vec2(860.0, 420.0));
		for (int i = 0; i < 2; i++) {
			vec2 d = q - vc[i];
			float ang = (i == 0 ? 1.0 : -0.8) * churn * (1.4 + time * 0.9) * exp(-length(d) / 330.0);
			q = vc[i] + rot(d, ang);
		}
	}
	float big = fbm(q / 170.0 + vec2(time * 0.012, -time * 0.008), 4);
	float fib = rn(vec2(p.x / 2.5, p.y / 22.0)) * 0.6 + rn(vec2(p.x / 19.0, p.y / 2.2)) * 0.4;
	vec3 col = mix(ink_light, ink_dark, smoothstep(0.30, 0.70, big));
	col *= 0.93 + 0.12 * fib;
	// 濡れた艶: 大きくやわらかい照り（ゆっくり動く）と、照りの中のごく細かいきらめき
	float gl = fbm(q / 260.0 + vec2(time * 0.020, time * 0.012), 3);
	float shine = smoothstep(0.56, 0.82, gl);
	col += vec3(0.028, 0.030, 0.040) * shine * sheen;
	col += vec3(0.05, 0.05, 0.06) * shine * step(0.985, rn(p / 3.0 + time * 0.5)) * sheen;
	float a = 0.0;
	if (edge > 0.0) {
		a = 1.0;
		// にじみの縁: 墨が溜まって濃くなる線
		if (edge < 5.0) { col = mix(col, ink_dark * 0.25, rim); }
		else if (edge < 26.0) { col = mix(col, ink_light * 1.35, rim * 0.35 * (1.0 - (edge - 5.0) / 21.0)); }
	} else if (edge > -18.0) {
		// 縁の外: 紙に吸われた薄い墨（繊維の向きに細かく毛羽立つ）
		float fiber = rn(vec2(p.x / 2.0, p.y / 9.0)) * 0.5 + rn(vec2(p.x / 9.0, p.y / 2.0)) * 0.5;
		float k = 1.0 + edge / 18.0;
		a = 0.62 * k * smoothstep(0.30, 0.70, fiber + k * 0.35 - 0.2) * rim;
		col = halo;
	}
	// --- 3本の切れ目から弾けて開く ---
	if (hole > 0.0) {
		float gap = hole * 560.0;
		float v = -999.0;
		vec4 ls[3] = vec4[3](hole_line1, hole_line2, hole_line3);
		for (int i = 0; i < 3; i++) {
			vec2 a1 = ls[i].xy; vec2 d1 = normalize(ls[i].zw - a1);
			float al = dot(p - a1, d1);
			float di = abs(d1.x * (p.y - a1.y) - d1.y * (p.x - a1.x));
			float jag = (fbm(p / 38.0 + float(i) * 4.1, 3) - 0.5) * 110.0 + pow(vnoise(vec2(al / 22.0, 1.0 + float(i) * 3.0)), 3.0) * 160.0 * hole;
			v = max(v, gap + jag - di);
		}
		if (v > 0.0) { a = 0.0; }
		else if (v > -5.0) { col *= 0.5; }
	}
	COLOR = vec4(col, a * COLOR.a);
}
