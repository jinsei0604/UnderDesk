shader_type canvas_item;
render_mode unshaded;
uniform float age=0.0;
uniform float power=1.0;
void fragment(){
 vec2 p=floor(UV*vec2(140.0,180.0))*2.0-vec2(140.0,180.0);
 vec2 d=p/vec2(103.0,160.0);
 float r=length(d)+0.001;float a=atan(d.y,d.x);
 float swirl=r+0.16*sin(a*5.0+age*1.8)+0.09*sin(p.y*0.1-p.x*0.075+age*2.1);
 float mantle=exp(-pow((swirl-0.72)/0.30,2.0));
 vec2 w=p+vec2(8.0*sin(p.y*0.055+age*0.48),5.0*sin(p.x*0.075-age*0.37)+age*13.0);
 float cloud=clamp(0.52+0.26*sin(w.x*0.062+w.y*0.081)+0.14*sin(w.x*0.14-w.y*0.12+age*0.18)+0.08*sin(w.x*0.29+w.y*0.22),0.0,1.0);
 float density=mantle*(0.32+0.85*cloud)*exp(-pow(r/1.3,5.0));
 float light=clamp(pow(cloud,1.6)*0.9+max(0.0,mantle-0.5)*0.35,0.0,1.0);
 vec3 ink=mix(vec3(0.058,0.039,0.105),vec3(0.439,0.392,0.639),light);
 COLOR=vec4(ink,floor(clamp(density*power*0.7,0.0,0.85)*42.0)/42.0);
}
