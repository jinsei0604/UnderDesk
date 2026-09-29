extends RefCounted
## 朽ちた機械武者の覚醒後の常時オーラ(rbm_musha_aura.gd)が使うシェーダー定義。
## 表示専用。戦闘状態・乱数には一切触れない(時刻と座標だけから決まる)。
##
## - post : 戦場全体への影響(1枚の全面パス)。光が死ぬ(松明・明部)/色が死ぬ(低彩度・低輝度)/
##          空間圧(ごくわずかな収縮)/画面端の墨ビネット。武者本体はこの後で描かれるので影響を受けない。
## - blot : 足元の墨染み(低く地面を這う不規則な染み)。ボス用と味方用で半径だけ変える。
## - ally : 味方の見た目にだけ掛ける同じ低彩度・低輝度化(味方はpost層より前面に描かれるため)。

const NOISE_LIB := """
float h21(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float vnoise(vec2 p){
	vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(h21(i),h21(i+vec2(1.0,0.0)),f.x),mix(h21(i+vec2(0.0,1.0)),h21(i+vec2(1.0,1.0)),f.x),f.y);
}
float fbm(vec2 p){ return 0.55*vnoise(p)+0.30*vnoise(p*2.1+7.3)+0.15*vnoise(p*4.3+3.1); }
float bayer(vec2 p){
	int ix=int(mod(floor(p.x),4.0)); int iy=int(mod(floor(p.y),4.0));
	float m[16]=float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.);
	return (m[ix+iy*4]+0.5)/16.0;
}
"""

const POST := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 rect_px = vec2(1280.0, 720.0);
uniform vec2 center = vec2(640.0, 360.0);
uniform vec2 torch_a = vec2(-1000.0);
uniform vec2 torch_b = vec2(-1000.0);
uniform float torch_r = 74.0;
uniform float time = 0.0;
uniform float amount = 0.0;
uniform float jolt = 0.0;
uniform float comp = 0.0;
void fragment(){
	vec2 px=UV*rect_px;
	// 画面上の1画素あたりのローカル座標(拡大縮小・ウィンドウサイズに依らず、ローカルpx単位で効果を決める)。
	float sc=1.0/max(rect_px.x*abs(dFdx(UV.x)),0.0001);
	// 空間圧: 全体が武者へ向かってごくわずか(端で約2px)縮み、1px沈んで戻る。揺らさない。
	vec2 off=(px-center)*(0.0032*comp)+vec2(0.0,1.2*comp);
	vec3 c=texture(screen_tex,SCREEN_UV+off*sc*SCREEN_PIXEL_SIZE).rgb;
	float lum=dot(c,vec3(0.299,0.587,0.114));
	// 光が死ぬ: 松明そのものが力を失い、灰色の熾火へ沈む。眼が光る瞬間だけ一段沈む。
	float torch=max(1.0-smoothstep(0.0,torch_r,length(px-torch_a)),1.0-smoothstep(0.0,torch_r,length(px-torch_b)));
	c=mix(c,vec3(lum),amount*0.70*torch);
	c*=1.0-amount*(0.58+0.12*jolt)*torch;
	// 色が死ぬ: 背景・床の彩度を落として全体を少し沈める。明部ほど強く光を奪う。
	c=mix(c,vec3(lum),0.46*amount);
	c*=1.0-amount*(0.10+0.07*jolt);
	c*=1.0-amount*0.30*smoothstep(0.26,0.78,lum);
	// 墨が染み込む: 一様なフィルターにせず、まだらな暗い濃淡がゆっくり移ろう。
	float mott=smoothstep(0.40,0.74,fbm(UV*vec2(4.2,3.0)+vec2(time*0.010,-time*0.006)));
	c*=1.0-amount*0.17*mott;
	// 画面端の墨ビネット: 筆で擦ったような不規則な縁。重すぎず、ゆっくり呼吸する。中央は潰さない。
	vec2 q=(UV-0.5)*vec2(1.0,0.92);
	float dd=length(q);
	float ang=atan(q.y,q.x);
	float fing=0.6*vnoise(vec2(ang*7.0,dd*2.0+time*0.03))+0.4*vnoise(vec2(ang*19.0+3.0,dd*3.0));
	float blob=fbm(UV*vec2(5.0,3.5)+vec2(time*0.012,0.0));
	float edge=dd+(fing-0.5)*0.20+(blob-0.5)*0.15;
	float breathe=0.88+0.12*sin(time*0.55);
	float vin=smoothstep(0.42,0.78,edge)*0.88*breathe*(1.0+0.55*jolt);
	float vq=floor(clamp(vin,0.0,1.0)*6.0+bayer(floor(px/2.0)))/6.0;
	c=mix(c,vec3(0.006,0.007,0.012),clamp(vq,0.0,1.0)*amount);
	COLOR=vec4(c,1.0);
}"""

const BLOT := """shader_type canvas_item;
uniform float time = 0.0;
uniform float jolt = 0.0;
uniform vec2 c = vec2(0.0);
uniform vec2 rad = vec2(158.0, 24.0);
uniform float amount = 0.0;
uniform float fleck_k = 0.0;
uniform float phase = 0.0;
uniform vec2 origin = vec2(0.0);
varying vec2 wp;
void vertex(){ wp = VERTEX + origin; }
void fragment(){
	vec2 p=wp;
	float br=1.0+0.07*sin(time*0.62+phase)+0.10*jolt;
	vec2 v=(p-c)/(rad*br);
	float q=length(v);
	float nz=fbm(p*vec2(0.020,0.085)+vec2(time*0.018,-time*0.012));
	float nb=vnoise(p*vec2(0.05,0.16)+vec2(4.0,time*0.02));
	float edge=q+(nz-0.5)*0.85+(nb-0.5)*0.30;
	float soft=(1.0-smoothstep(0.40,1.0,edge))*amount;
	float qa=floor(soft*5.0+bayer(p))/5.0;
	float ring=step(1.0,edge)*(1.0-step(1.35,edge));
	float fleck=step(0.975,h21(floor(p/3.0)+vec2(3.0,9.0)))*ring*fleck_k;
	float a=max(qa,fleck*0.7*amount);
	COLOR=vec4(0.004,0.005,0.009,a);
}"""

const ALLY := """shader_type canvas_item;
uniform float amount = 0.0;
uniform float jolt = 0.0;
void fragment(){
	vec3 c=COLOR.rgb;
	float lum=dot(c,vec3(0.299,0.587,0.114));
	c=mix(c,vec3(lum),0.46*amount);
	c*=1.0-amount*(0.10+0.07*jolt);
	c*=1.0-amount*0.30*smoothstep(0.26,0.78,lum);
	COLOR=vec4(c,COLOR.a);
}"""

static var _shaders: Dictionary = {}

## 種類("post"/"blot"/"ally")ごとにShaderを1つだけ作って共有し、呼び出しごとに新しいMaterialを返す
## (uniformは各Materialが個別に持つ)。
static func material(kind: String) -> ShaderMaterial:
	if not _shaders.has(kind):
		var shader := Shader.new()
		match kind:
			"post":
				shader.code = _with_lib(POST)
			"blot":
				shader.code = _with_lib(BLOT)
			_:
				shader.code = ALLY
		_shaders[kind] = shader
	var m := ShaderMaterial.new()
	m.shader = _shaders[kind]
	return m

static func _with_lib(code: String) -> String:
	return code.replace("void fragment(){", NOISE_LIB + "void fragment(){")
