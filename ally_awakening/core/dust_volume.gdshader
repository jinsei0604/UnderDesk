shader_type canvas_item;
render_mode unshaded;
uniform float age=0.;
uniform float amount=0.;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){
 vec2 p=floor(UV*vec2(250,90))/vec2(250,90);
 float x=abs(p.x-.5)*2.;
 float n=noise(vec2(x*12.-age*3.,p.y*7.+age));
 float n2=noise(vec2(x*28.-age*5.,p.y*20.));
 float roof=.62-.28*n;
 float band=smoothstep(roof,roof+.17,p.y)*(1.-smoothstep(.82,.98,p.y));
 float sides=smoothstep(.12,.38,x)*(1.-smoothstep(.65,.98,x));
 float a=band*sides*amount*(.35+.5*n);
 vec3 c=mix(vec3(.21,.20,.23),vec3(.63,.60,.55),n*.65+n2*.2);
 COLOR=vec4(c,a);
}
