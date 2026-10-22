uniform sampler2D density_tex : repeat_enable, filter_linear;
uniform vec2 origin = vec2(820.0,330.0);
uniform float age = -10.0;
float sat(float v) { return clamp(v,0.0,1.0); }
float rnd(float x) { return fract(sin(x*127.1+73.2)*43758.5453); }
vec4 grain(vec2 p) { return texture(density_tex,p/512.0); }
float mist(vec2 p) {
	vec4 a=grain(p); vec4 b=grain(p*2.13+vec2(31.0,97.0));
	return a.r*.55+a.g*.22+b.b*.17+b.a*.06;
}
vec3 stepped(vec3 c) { return floor(c*40.0+.5)/40.0; }
