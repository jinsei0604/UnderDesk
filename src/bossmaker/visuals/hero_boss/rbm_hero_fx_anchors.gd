class_name RBMHeroFxAnchors
extends RefCounted
## 立ち絵ごとの「エフェクトが付く場所」（足元中央からの相対、論理ドット）。
## 基準はコマの矩形の下辺中央。正式コマ（motion/cels.png）に合わせてある。モーションが更新されたら、ここの数値だけ合わせ直す。
## chest=胸の灯 / head=バイザー / tip=武器の先 / root=武器の根元

const POSES := {
	"normal": {"chest": Vector2(0, -67), "head": Vector2(2, -82)},
	"omega": {"chest": Vector2(0, -67), "head": Vector2(0, -82)},
	"blade0": {"chest": Vector2(0, -66), "head": Vector2(0, -82), "tip": Vector2(10, -66)},
	"blade1": {"chest": Vector2(2, -66), "head": Vector2(2, -82), "tip": Vector2(19, -70)},
	"blade2": {"chest": Vector2(2, -64), "head": Vector2(0, -78), "tip": Vector2(15, -69)},
	"blade3": {"chest": Vector2(-4, -58), "head": Vector2(-6, -74), "tip": Vector2(-37, -48)},
	"blade4": {"chest": Vector2(-2, -60), "head": Vector2(-2, -78), "tip": Vector2(-47, -91)},
	"blade5": {"chest": Vector2(0, -62), "head": Vector2(0, -80), "tip": Vector2(-40, -90)},
	"stances1": {"chest": Vector2(-6, -55), "head": Vector2(-6, -74), "tip": Vector2(-44, -54)},
	"array0": {"chest": Vector2(0, -66), "head": Vector2(2, -83)},
	"array1": {"chest": Vector2(0, -66), "head": Vector2(2, -83)},
	"array2": {"chest": Vector2(0, -66), "head": Vector2(2, -83), "tip": Vector2(0, -74)},
	"array3": {"chest": Vector2(-3, -64), "head": Vector2(-4, -80), "tip": Vector2(-39, -65)},
	"array4": {"chest": Vector2(2, -62), "head": Vector2(2, -80), "tip": Vector2(-36, -59)},
	"array5": {"chest": Vector2(0, -66), "head": Vector2(2, -83), "tip": Vector2(-30, -62)},
	"release0": {"chest": Vector2(2, -60), "head": Vector2(2, -78)},
	"release1": {"chest": Vector2(-2, -38), "head": Vector2(-6, -55)},
	"release2": {"chest": Vector2(-6, -36), "head": Vector2(-10, -54)},
	"release3": {"chest": Vector2(0, -68), "head": Vector2(0, -86)},
	"release4": {"chest": Vector2(-2, -66), "head": Vector2(-4, -82)},
	"shear0": {"chest": Vector2(0, -67), "head": Vector2(0, -82), "tip": Vector2(-30, -22)},
	"shear1": {"chest": Vector2(-4, -58), "head": Vector2(-4, -74), "tip": Vector2(-40, -40)},
	"shear2": {"chest": Vector2(0, -60), "head": Vector2(0, -76), "tip": Vector2(0, -46)},
	"shear3": {"chest": Vector2(2, -58), "head": Vector2(-2, -76), "tip": Vector2(26, -66)},
	"shear4": {"chest": Vector2(0, -60), "head": Vector2(0, -78), "tip": Vector2(-50, -86)},
	"shear5": {"chest": Vector2(0, -66), "head": Vector2(0, -82), "tip": Vector2(0, -50)},
	"verdict0": {"chest": Vector2(0, -67), "head": Vector2(-4, -82), "tip": Vector2(30, -60)},
	"verdict1": {"chest": Vector2(-14, -67), "head": Vector2(-18, -82), "tip": Vector2(51, -114), "root": Vector2(10, -82)},
	"verdict2": {"chest": Vector2(-14, -44), "head": Vector2(-22, -56), "tip": Vector2(54, -83), "root": Vector2(-10, -74)},
	"verdict3": {"chest": Vector2(14, -66), "head": Vector2(8, -82), "tip": Vector2(-61, -2), "root": Vector2(-14, -38)},
	"verdict4": {"chest": Vector2(14, -50), "head": Vector2(6, -66), "tip": Vector2(-52, -1), "root": Vector2(-12, -38)},
	"verdict5": {"chest": Vector2(0, -67), "head": Vector2(0, -82)},
	# 正式採用で増えたコマ。array_standing_palms の tip は前へ伸ばした両手。
	"array_standing_palms": {"chest": Vector2(-8, -61), "head": Vector2(-9, -78), "tip": Vector2(-38, -71)},
	"bridge0": {"chest": Vector2(-10, -52), "head": Vector2(-10, -68)},
	"bridge2": {"chest": Vector2(-5, -44), "head": Vector2(-18, -59)},
	"spring": {"chest": Vector2(-18, -52), "head": Vector2(-23, -67), "tip": Vector2(51, -105), "root": Vector2(5, -64)},
	"overhead": {"chest": Vector2(2, -43), "head": Vector2(-4, -60), "tip": Vector2(4, -126), "root": Vector2(18, -66)},
	"sweep": {"chest": Vector2(13, -42), "head": Vector2(4, -56), "tip": Vector2(-41, -74), "root": Vector2(24, -65)},
}

static func point(pose: String, which: String, foot: Vector2) -> Vector2:
	var p: Dictionary = POSES.get(pose, POSES["normal"])
	if p.has(which):
		return foot + Vector2(p[which])
	return foot + Vector2(p["chest"])
