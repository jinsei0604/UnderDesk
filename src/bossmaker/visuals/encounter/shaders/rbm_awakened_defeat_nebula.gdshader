shader_type canvas_item;
render_mode unshaded;
#include "res://src/bossmaker/visuals/encounter/shaders/rbm_awakened_defeat_field.gdshaderinc"
void fragment() {
	vec2 p=UV*vec2(1280.0,720.0)-origin;
	float e=max(age-.70,0.0), q=smoothstep(0.0,.70,age);
	float spread=1.0-exp(-e*6.5);
	vec2 v=p/vec2(1.0,.76);
	float r=length(v), angle=atan(v.y,v.x);
	vec2 flow=vec2(cos(angle+.8),sin(angle+.8))*e*38.0;
	vec4 g=grain(v-flow);
	float n=mist(v-flow+(g.rg-.5)*52.0);
	vec3 col=vec3(.11,.045,.22);
	float alpha=0.0;
	if(age<.70) {
		float radius=mix(220.0,30.0,q);
		float gas=exp(-pow((r-radius)/(50.0+q*10.0),2.0));
		alpha=gas*smoothstep(.36,.68,n)*q*.75;
		col=mix(vec3(.19,.085,.34),vec3(.65,.38,.85),n);
		float core=exp(-dot(p/vec2(26.0,31.0),p/vec2(26.0,31.0)))*q*q;
		col=mix(col,vec3(1.0,.84,1.0),core);
		alpha=max(alpha,core);
	} else {
		float front=160.0+850.0*spread;
		float deform=sin(angle*3.0+.4)*.12+sin(angle*7.0)*.05;
		float envelope=1.0-smoothstep(front*.35,front,r*(1.0+deform));
		float center=1.0-smoothstep(0.0,330.0+spread*150.0,r);
		float erosion=smoothstep(.30,1.78,e)*.36;
		float gas=smoothstep(.28,.66,n+envelope*.30-erosion)*envelope;
		float hot=(1.0-smoothstep(.06,.52,e));
		float light=gas*(.50+center*.65);
		col=mix(vec3(.075,.035,.16),vec3(.41,.18,.60),sat(light));
		col=mix(col,vec3(.80,.47,.86),pow(sat((n-.3)*2.5),2.0)*center);
		col=mix(col,vec3(1.0,.91,1.0),pow(center,1.6)*hot);
		alpha=gas*(1.0-smoothstep(.35,1.65,e));
		// Broken pressure sheet leaves quickly; it never becomes a diagram-like orbit.
		float shell=exp(-pow((r-front*(.77+g.r*.20))/75.0,2.0))*smoothstep(.48,.7,n)*(1.0-smoothstep(.12,.40,e))*.4;
		col=mix(col,vec3(.76,.54,.90),shell);
		alpha=max(alpha,shell);
		float white_core=exp(-pow(r/(45.0+140.0*spread),2.0))*hot;
		col=mix(col,vec3(1.0,.93,1.0),white_core);
		alpha=max(alpha,white_core);
	}
	COLOR=vec4(stepped(col),alpha*step(0.0,age));
}
