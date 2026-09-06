class_name RBMCreatorAppearanceCatalog
extends RefCounted

## Phase 1 Step 4 §1-2/§1-3 — "完成済みボス外見" catalog for STEP 1's appearance
## picker.
##
## No boss-appearance art exists anywhere in this project yet (Step 1-3 built
## zero art, RPG BOSS MAKER's own asset pipeline doesn't exist). These are
## placeholder entries (id + display name only, rendered as a flat colored
## swatch) so the actual REQUIRED structure — a grid, current-selection
## highlighting, "将来素材数が増えても追加しやすい構造" — is real, functional,
## and testable end to end, rather than invented/faked art. Swapping in real
## textures later means adding a texture-path field per entry and having the
## grid view read it; no structural change to this catalog or its consumers.
## See the completion report's flagged items for the disclosure of this
## judgment call.
##
## Deliberately independent of UDArtLibrary/UD.* — see src/bossmaker/README.md
## ("RBM は UD に依存しない").

const ENTRIES: Array[Dictionary] = [
	{"id": "appearance_slime", "name": "スライム"},
	{"id": "appearance_wolf", "name": "狼"},
	{"id": "appearance_knight", "name": "騎士"},
	{"id": "appearance_dragon", "name": "竜"},
	{"id": "appearance_ghost", "name": "幽霊"},
	{"id": "appearance_golem", "name": "ゴーレム"},
]

static func all() -> Array[Dictionary]:
	return ENTRIES.duplicate(true)

static func by_id(id: String) -> Dictionary:
	for entry in ENTRIES:
		if str(entry.get("id", "")) == id:
			return entry
	return {}

static func display_name(id: String) -> String:
	var entry := by_id(id)
	return str(entry.get("name", "")) if not entry.is_empty() else ""

## A small deterministic placeholder swatch color, distinct per entry.
static func placeholder_color(id: String) -> Color:
	var h: int = hash(id)
	return Color.from_hsv(fmod(float(h % 360000) / 1000.0, 360.0) / 360.0, 0.55, 0.85)
