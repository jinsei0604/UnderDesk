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

## "name"は表示用文字列——"id"(appearance_slime等)は他の全画面が参照する
## 内部IDのため翻訳対象ではない。display_name()の戻り値へTranslationServer.translate()を適用する
## ことで、参照元すべてに一括で反映される。
##
## "supports_awakening": このボス外見が覚醒(Awakening)機能に対応しているか
## ——ゲームデザイン上の可否そのものであり、覚醒後アセットの実在
## (RBMVisualAssets.has_awakened_design())とは別概念(§3確定)。今回は
## どのボスを覚醒対応にするかまだ決定しないため、既存6体は全てfalseの
## まま——新しいボスを追加する際にこのキーをtrueにするだけで、Creator
## STEP3の覚醒選択・ボス選択画面の「覚醒可能」表示・覚醒後プレビュー
## 切替が自動的に有効になる(固定BOSS_IDS一覧やボス名による分岐は一切
## 増やさない)。
const ENTRIES: Array[Dictionary] = [
	{"id": "appearance_slime", "name": "スライム", "supports_awakening": false},
	{"id": "appearance_wolf", "name": "狼", "supports_awakening": false},
	{"id": "appearance_knight", "name": "騎士", "supports_awakening": false},
	{"id": "appearance_dragon", "name": "竜", "supports_awakening": false},
	{"id": "appearance_ghost", "name": "幽霊", "supports_awakening": false},
	{"id": "appearance_golem", "name": "ゴーレム", "supports_awakening": false},
]

static func all() -> Array[Dictionary]:
	return ENTRIES.duplicate(true)

static func by_id(id: String) -> Dictionary:
	for entry in ENTRIES:
		if str(entry.get("id", "")) == id:
			return entry
	return {}

## キー自体が無いエントリ(将来の防御的フォールバック)・存在しないid
## いずれもfalse扱い——「未指定は覚醒非対応」という後方互換の既定値。
static func supports_awakening(id: String) -> bool:
	return bool(by_id(id).get("supports_awakening", false))

static func display_name(id: String) -> String:
	var entry := by_id(id)
	return TranslationServer.translate(str(entry.get("name", ""))) if not entry.is_empty() else ""

## A small deterministic placeholder swatch color, distinct per entry.
static func placeholder_color(id: String) -> Color:
	var h: int = hash(id)
	return Color.from_hsv(fmod(float(h % 360000) / 1000.0, 360.0) / 360.0, 0.55, 0.85)
