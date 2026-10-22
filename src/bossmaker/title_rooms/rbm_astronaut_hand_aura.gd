extends "res://src/bossmaker/visuals/rbm_astronaut_vfx.gd"
# Inherit the shipped, pixel-snapped cross-star/orbit drawing primitives.
# Four stars and one hand-sized orbit, instead of 36 stars / 9 full-body ribbons.
var intensity: float = 0.0
func _draw() -> void:
	if intensity <= 0.0: return
	glow(Vector2.ZERO,Vector2(65,50),ink("292659"),intensity*.26)
	var orbit: Array = []
	for j in range(33):
		orbit.append(Vector2(cos(j*TAU/32)*55,sin(j*TAU/32)*25).rotated(-.62))
	line(orbit,ink("4a64b5",intensity*.65),1)
	for i in range(4):
		var a: float = age*.85+i*1.8
		var p: Vector2 = Vector2(cos(a)*(7+i)*5,sin(a)*(5+i%2)*5).round()
		star(p,4 if i%2 else 7,ink("e9f5ff" if i==0 else "ada4f4",intensity*(.70+.20*sin(age*3+i))))
	star(Vector2(0,-2),3,ink("827afa",intensity*.85))
