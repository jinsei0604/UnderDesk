shader_type canvas_item;
render_mode unshaded;
uniform float age = 0.0;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform int mode = 0;
uniform vec4 hue : source_color = vec4(1.0,0.25,0.1,1.0);
void fragment(){
 vec2 uv=floor(UV*vec2(90.0,90.0))/vec2(90.0,90.0);
 vec2 p=(uv-vec2(.5,.66))*vec2(2.,2.);
 float angle=atan(p.y,p.x), r=length(p*vec2(1.,.8));
 float side=abs(p.x);
 float vertical=1.-smoothstep(.05,.8,abs(p.y+.25));
 float f=sin(p.y*19.+age*3.7+sin(p.x*17.-age*2.))*0.5+0.5;
 float body=smoothstep(.20,.38,side)*(1.-smoothstep(.42,.8,side));
 float power=0.;
 if(mode==0){
  float edge=.32+.07*sin(p.y*13.+age*6.)+.05*sin(p.y*29.-age*4.);
  power=exp(-abs(side-edge)*12.)*vertical*(.60+.45*f);
 }else if(mode==1){
  float edge=.36+floor((p.y+.4)*7.)*.018;
  power=exp(-abs(side-edge)*18.)*vertical*(.65+.25*sin(p.y*23.-age*1.1));
 }else if(mode==2){
  float halo=exp(-abs(length((p-vec2(0.,-.30))*vec2(1.,.7))-.40)*30.);
  power=halo*(.5+.25*sin(angle*7.+age*1.5))+body*vertical*.22;
 }else if(mode==3){
  float spiral=abs(sin(angle*2.-r*19.+age*3.));
  power=pow(spiral,16.)*smoothstep(.26,.35,r)*(1.-smoothstep(.45,.68,r))*.8;
 }else{
  float edge=.52+.035*sin(p.y*25.+age*1.2);
  power=exp(-abs(side-edge)*22.)*vertical*1.25;
  power+=exp(-abs(length(p*vec2(1.,2.8))-.48)*32.)*.35;
 }
 float base=exp(-length((p-vec2(0.,.30))*vec2(1.5,7.)) * 4.)*.3;
 power=(power+base)*intensity;
 power=floor(power*12.)/12.;
 COLOR=vec4(mix(hue.rgb,vec3(1.,.96,.83),smoothstep(.45,.9,power)*.55),min(.60,power*.65));
 if(mode==4){
  // Neutral pressure keeps a dark outer contour readable against pale stone.
  float edge=.52+.035*sin(p.y*25.+age*1.2);
  float rim=exp(-abs(side-edge-.065)*32.)*vertical*intensity;
  COLOR.rgb=mix(COLOR.rgb,vec3(.20,.22,.26),clamp(rim*.85,0.,.8));
  COLOR.a=max(COLOR.a,rim*.52);
 }
}
