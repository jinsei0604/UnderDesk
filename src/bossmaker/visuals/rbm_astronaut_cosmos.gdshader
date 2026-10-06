shader_type canvas_item;
render_mode unshaded;
uniform vec2 canvas_size = vec2(640.0, 360.0);
uniform vec2 center = vec2(492.0, 225.0);
uniform float age = 0.0;
uniform float reach = 72.0;
uniform float strength = .7;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
	vec2 p=floor(UV*canvas_size/2.0)*2.0-center;
	vec2 q=vec2(p.x*.96+p.y*.28, p.y*1.25-p.x*.20)/reach;
	float r=length(q);
	float a=atan(q.y,q.x);
	float clouds=noise(q*5.0+vec2(age*.04,0))*.55+noise(q*13.0-vec2(0,age*.08))*.3+noise(q*31.0)*.15;
	float arms=pow(.5+.5*sin(a*3.0-r*13.0+age*.28),3.0);
	float field=exp(-r*r*2.8)*smoothstep(.24,.78,clouds)*(.3+arms*.85);
	vec3 deep=vec3(.07,.09,.31), blue=vec3(.29,.43,.85), violet=vec3(.43,.25,.68);
	vec3 color=mix(deep,mix(blue,violet,noise(q*4.0)),smoothstep(.15,.7,field));
	color+=vec3(.26,.29,.36)*pow(field,2.0);
	COLOR=vec4(color,clamp(field*strength*2.5,0.0,.82));
}
