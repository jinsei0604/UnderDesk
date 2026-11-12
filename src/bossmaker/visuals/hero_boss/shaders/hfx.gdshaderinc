// ヒーローのエフェクト共通の関数。2px（キャラのドット1個分）の格子へ揃えるための関数を含む。
const float HFX_BAYER[16] = {0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.};

float hfx_h(vec2 p){
	vec3 q = fract(vec3(p.xyx) * .1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float hfx_n(vec2 p){
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3. - 2. * f);
	return mix(mix(hfx_h(i), hfx_h(i + vec2(1., 0.)), f.x), mix(hfx_h(i + vec2(0., 1.)), hfx_h(i + vec2(1., 1.)), f.x), f.y);
}
float hfx_fbm(vec2 p, int o){
	float a = .5, s = 0.;
	for (int i = 0; i < o; i++) {
		s += a * hfx_n(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= .5;
	}
	return s / (1. - pow(.5, float(o)));
}
// UV を描画先の2px格子へ揃える（回転していても正しい）。
vec2 hfx_grid(vec2 uv, vec2 fc, float px){
	vec2 d = (floor(fc / px) + .5) * px - fc;
	return uv + dFdx(uv) * d.x + dFdy(uv) * d.y;
}
// 2px格子の組織的ディザの閾値（0..1）。消え際に半透明を使わず、点描で薄くする。
float hfx_bayer(vec2 fc, float px){
	vec2 c = mod(floor(fc / px), 4.);
	return (HFX_BAYER[int(c.x) + int(c.y) * 4] + .5) / 16.;
}
