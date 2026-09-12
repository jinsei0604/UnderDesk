extends RefCounted
## Approved 2026-09-12: reusable attribute accents, never actor/debris tint.
const COLORS := {
	"NEUTRAL": Color("b7bbc2"),
	"FIRE": Color("ef4847"),
	"ICE": Color("509cf5"),
	"LIGHTNING": Color("f2cd55"),
	"WIND": Color("a4f255"),
}
static func color_for(attribute: String) -> Color:
	return COLORS.get(attribute,COLORS["NEUTRAL"])
