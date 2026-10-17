class_name RBMOnlineBossDetailPanel
extends Panel

## オンライン一覧(右側)の「選択中ボスの詳細」(2026-10)。
## 上部いっぱいに、そのボスの戦闘背景(戦闘画面と同じ決め方: RBMBattleBackgrounds.texture_for。
## 専用背景 backgrounds/<boss_id>/background.png があればそれ、無ければ作者が選んだ昼/夜の中庭)を
## 敷いてボスを立たせ、右にモード・名前・作者・公開日・勝利条件・ボスHP・弱点を並べる。
## 下に作者メッセージ・攻略パーティ・「挑戦する」。挑戦者数/クリア率は左のカードにあるので出さない。
## 状態: 未選択 / 取得中 / 取得失敗 / 表示。押された「挑戦する」はchallenge_pressedで知らせるだけ。

signal challenge_pressed()

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const STAGE_HEIGHT := 300.0
const INFO_X := 452.0
const BOSS_FIT := Vector2(330, 236)
const BOSS_CENTER_X := 220.0
const BOSS_FOOT_Y := 266.0
const PARTY_CHIP_SIZE := Vector2(80, 84)
const PARTY_CHIP_STEP := 88.0
const CTA_SIZE := Vector2(320, 52)
## 攻略パーティの枠に出す短い呼び名(正式名は長くて枠に収まらないため。仮の呼び名、2026-10)。
const PARTY_SHORT_NAMES := {
	"hero": "勇者", "butler": "老執事", "healer": "少女", "samurai": "侍", "tank": "ハンマー使い",
}

## ボスごとの背景の任意の上書きと命名規則(rbm_battle_backgrounds.gd)。戦闘画面
## (RBMFullscreenBattleUi.boss_backgrounds/background_convention)と同じ既定値で、テストでは差し替えられる。
var boss_backgrounds: Dictionary = RBMBattleBackgrounds.BOSS_BACKGROUNDS
var background_convention: String = RBMBattleBackgrounds.CONVENTION

var _content: Control

func _ready() -> void:
	add_theme_stylebox_override("panel", S.box(Color(S.PANEL, 0.96), S.PANEL_EDGE))
	clip_contents = true
	if _content == null:
		_ensure_content()
		show_empty(false)

func _ensure_content() -> void:
	if _content != null:
		return
	_content = Control.new()
	_content.name = "DetailContent"
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

func _clear() -> void:
	_ensure_content()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

func _width() -> float:
	return size.x if size.x > 0 else 772.0

func _height() -> float:
	return size.y if size.y > 0 else 612.0

## まだ何も選んでいない。with_hint=falseは一覧が無い時(取得中・空・失敗)で、選べるボスが無いので案内も出さない。
func show_empty(with_hint: bool) -> void:
	_clear()
	S.rect(_content, Rect2(1, 1, _width() - 2, STAGE_HEIGHT), S.INSET)
	S.corner_marks(_content, Rect2(14, 14, _width() - 28, STAGE_HEIGHT - 32), Color(S.SILVER, 0.35))
	if with_hint:
		var hint := S.label(_content, _empty_hint_text(), Rect2(0, 136, _width(), 30), 15, S.MUTED, "DetailHint")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## 選んだボスの詳細を取得している間。一覧の行に入っている名前・作者・モードはすぐ出す。
func show_loading(summary: Dictionary) -> void:
	_clear()
	S.rect(_content, Rect2(1, 1, _width() - 2, STAGE_HEIGHT), S.INSET)
	var waiting := S.label(_content, tr("読み込み中..."), Rect2(0, 130, 430, 30), 15, S.MUTED, "DetailLoading")
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	S.corner_marks(_content, Rect2(14, 14, 412, STAGE_HEIGHT - 32), Color(S.SILVER, 0.35))
	_build_header(summary)
	var y := 146.0
	for caption in _row_captions():
		S.label(_content, caption, Rect2(INFO_X, y, _caption_width(), 26), 13, S.DIM)
		S.rect(_content, Rect2(INFO_X + _caption_width() + 4, y + 8, 120, 12), S.SKELETON)
		y += 32
	S.section_title(_content, tr("作者メッセージ"), Vector2(16, 310))
	var message_box := _message_box()
	S.rect(message_box, Rect2(16, 21, 420, 14), S.SKELETON)
	_build_party_title()
	for i in range(4):
		var chip := Panel.new()
		chip.position = Vector2(16 + PARTY_CHIP_STEP * i, 440)
		chip.size = PARTY_CHIP_SIZE
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel", S.box(Color("0b1116"), Color("1c2830")))
		_content.add_child(chip)
	var button := _build_challenge_button()
	button.text = tr("読み込み中...")
	button.icon = null
	button.disabled = true

## 詳細を取得できなかった。もう一度同じカードを押せば取り直せる。
func show_error(summary: Dictionary, message: String) -> void:
	_clear()
	S.rect(_content, Rect2(1, 1, _width() - 2, STAGE_HEIGHT), S.INSET)
	S.corner_marks(_content, Rect2(14, 14, 412, STAGE_HEIGHT - 32), Color(S.SILVER, 0.35))
	# 折り返しを有効にしてから文を入れる（先に文を入れると幅が1行の長さまで広がり、後から戻せない。
	# 理由の文が長くても枠の中で折り返す。PX-14）
	var error := S.label(_content, "", Rect2(30, 92, 370, 116), 14, S.HARD, "DetailError")
	error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.text = message
	_build_header(summary)

func show_boss(summary: Dictionary, draft: RBMCreatorDraft) -> void:
	_clear()
	_build_stage(draft)
	_build_header(summary)
	_build_header_extras(summary, draft)
	var y := 146.0
	for row in _detail_rows(summary, draft):
		S.label(_content, row["caption"], Rect2(INFO_X, y, _caption_width(), 26), 13, _caption_color())
		var value := S.label(_content, row["value"], Rect2(INFO_X + _caption_width() + 4, y, _width() - INFO_X - 20 - _caption_width() - 4, 26), 15, row.get("color", S.SILVER), row["name"])
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value.clip_text = true
		if bool(row.get("latin", false)):
			value.add_theme_font_override("font", S.number_font())
		y += 32
	var status := _status_line(summary, draft)
	S.label(_content, status[0], Rect2(INFO_X, y + 6, _width() - INFO_X - 20, 24), 13, status[1], "DetailClearCheck")

	S.section_title(_content, tr("作者メッセージ"), Vector2(16, 310))
	var message_box := _message_box()
	var message := S.label(message_box, draft.author_notes if not draft.author_notes.is_empty() else tr("（なし）"), Rect2(16, 4, message_box.size.x - 32, 48), 15, S.TEXT if not draft.author_notes.is_empty() else S.MUTED, "DetailMessage")
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_build_party_title()
	var x := 16.0
	for character_id in draft.party_character_ids:
		_party_chip(str(character_id), draft, Vector2(x, 440))
		x += PARTY_CHIP_STEP
	if draft.party_character_ids.is_empty():
		_build_empty_party()
	_build_actions()

# ---------------------------------------------------------------------------
# 保存したボス戦の一覧（RBMSavedBossDetailPanel、2026-10）が同じ詳細の形のまま差し替える部分。
# ここにある既定の内容が、挑戦側のオンライン一覧の表示そのもの。

func _empty_hint_text() -> String:
	return tr("左の一覧からボスを選択してください")

## モードの札の右に足す札（オンライン一覧では無し）。
func _build_header_extras(_summary: Dictionary, _draft: RBMCreatorDraft) -> void:
	pass

## 右側の行: caption（見出し）・value（値）・name（値のノード名）、任意で color・latin（数字の書体）。
func _detail_rows(summary: Dictionary, draft: RBMCreatorDraft) -> Array:
	var captions := _row_captions()
	return [
		{"caption": captions[0], "value": S.local_published_date_text(str(summary.get("published_at", ""))), "name": "DetailPublishedValue"},
		{"caption": captions[1], "value": tr("ボスのHPを0にする") if draft.is_challenge_info_visible("win_condition") else tr("非公開"), "name": "DetailWinConditionValue"},
		{"caption": captions[2], "value": str(draft.hp) if draft.is_challenge_info_visible("hp") else tr("？？？"), "name": "DetailBossHpValue"},
		{"caption": captions[3], "value": _weak_text(draft), "name": "DetailWeakValue"},
	]

func _caption_color() -> Color:
	return S.DIM

## 行の下の一行（文字・色）。
func _status_line(_summary: Dictionary, draft: RBMCreatorDraft) -> Array:
	var checked := draft.is_clear_check_currently_valid()
	return [tr("✓ クリアチェック済み") if checked else tr("このボス戦はクリアチェックされていません"), S.ACCENT_SOFT.lightened(0.25) if checked else S.MUTED]

func _party_note_text() -> String:
	return tr("作者が決めた固定メンバーで挑戦します")

## 攻略パーティが空の時（オンラインの公開ボスは必ずパーティを持つので何も出さない）。
func _build_empty_party() -> void:
	pass

## 下の操作（オンライン一覧では「挑戦する」）。
func _build_actions() -> void:
	_build_challenge_button()

# ---------------------------------------------------------------------------

func _build_stage(draft: RBMCreatorDraft) -> void:
	var stage := Control.new()
	stage.name = "DetailStage"
	stage.position = Vector2(1, 1)
	stage.size = Vector2(_width() - 2, STAGE_HEIGHT)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(stage)
	var boss_asset := RBMVisualAssets.boss_asset(draft.appearance_id)
	var background := TextureRect.new()
	background.name = "DetailStageBackground"
	background.texture = RBMBattleBackgrounds.texture_for(boss_asset, draft.battle_background, boss_backgrounds, background_convention)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.size = stage.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	# 文字を載せる右側と、下の欄へつながる下端だけを沈める(背景の絵柄は左側でそのまま見せる)。
	S.gradient_rect(stage, Rect2(Vector2.ZERO, stage.size), Color(S.PANEL, 0.0), Color(S.PANEL, 0.94), true, 0.38, 0.62)
	S.gradient_rect(stage, Rect2(0, stage.size.y - 70, stage.size.x, 70), Color(S.PANEL, 0.0), Color(S.PANEL, 1.0))
	var sprite := S.fitted_sprite(boss_asset, BOSS_FIT)
	if sprite != null:
		S.floor_shadow(stage, Rect2(BOSS_CENTER_X - 120, BOSS_FOOT_Y - 19, 240, 30))
		var boss := TextureRect.new()
		boss.name = "DetailStageBoss"
		boss.texture = sprite
		boss.size = S.fitted_size(sprite, BOSS_FIT)
		boss.position = Vector2(BOSS_CENTER_X - boss.size.x / 2.0, BOSS_FOOT_Y - boss.size.y)
		boss.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		boss.stretch_mode = TextureRect.STRETCH_SCALE
		boss.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		boss.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(boss)
	S.corner_marks(_content, Rect2(14, 14, 412, STAGE_HEIGHT - 32), Color(S.SILVER, 0.85))

## モード・ボス名・作者(一覧の行に入っている分)。
func _build_header(summary: Dictionary) -> void:
	var info_width := _width() - INFO_X - 20
	S.mode_tag(_content, str(summary.get("creator_mode", RBMCreatorDraft.CREATOR_MODE_SIMPLE)), Vector2(INFO_X, 22))
	# 公開ID（2026-10-17 PX-03）: モードの札の行の右端に小さく。「ボスを検索」に入れるとこのボスを探せる。
	var public_id := _public_id(summary)
	if not public_id.is_empty():
		var id_label := S.label(_content, tr("公開ID %s") % public_id, Rect2(INFO_X, 20, info_width, 26), 13, S.MUTED, "DetailPublicId")
		id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		id_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var title := S.label(_content, str(summary.get("boss_name", "")), Rect2(INFO_X, 50, info_width, 44), 28 if _is_japanese() else 24, S.TEXT, "DetailBossName")
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	var author := str(summary.get("author_name", ""))
	var author_label := S.label(_content, tr("by %s") % (author if not author.is_empty() else tr("（未設定）")), Rect2(INFO_X, 96, info_width, 24), 15, S.MUTED, "DetailAuthor")
	author_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	author_label.clip_text = true
	S.rect(_content, Rect2(INFO_X, 132, info_width, 1), S.PANEL_EDGE)

func _row_captions() -> Array:
	return [tr("公開日"), tr("勝利条件"), tr("ボスHP"), tr("弱点")]

## 見出しの右上に出す公開ID（オンラインの一覧の行の id から。無ければ出さない）。
func _public_id(summary: Dictionary) -> String:
	return RBMPublicBossId.from_boss_id(str(summary.get("id", "")))

func _caption_width() -> float:
	return 92.0 if _is_japanese() else 112.0

func _is_japanese() -> bool:
	return TranslationServer.get_locale().begins_with("ja")

func _weak_text(draft: RBMCreatorDraft) -> String:
	if not draft.is_challenge_info_visible("weak_attributes"):
		return tr("？？？")
	if draft.weak_attributes.is_empty():
		return tr("なし")
	var labels: Array = []
	for attribute in draft.weak_attributes:
		labels.append(tr(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(str(attribute), str(attribute)))))
	return ", ".join(labels)

func _message_box() -> Panel:
	var message_box := Panel.new()
	message_box.name = "DetailMessageBox"
	message_box.position = Vector2(16, 340)
	message_box.size = Vector2(_width() - 32, 56)
	message_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_box.add_theme_stylebox_override("panel", S.box(S.INSET, Color("1a2830")))
	_content.add_child(message_box)
	return message_box

func _build_party_title() -> void:
	S.section_title(_content, tr("攻略パーティ"), Vector2(16, 408))
	S.label(_content, _party_note_text(), Rect2(150, 408, _width() - 166, 28), 12, _caption_color(), "DetailPartyNote")

func _party_chip(character_id: String, draft: RBMCreatorDraft, at: Vector2) -> void:
	var chip := Panel.new()
	chip.name = "DetailPartyChip_%s" % character_id
	chip.position = at
	chip.size = PARTY_CHIP_SIZE
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", S.box(S.INSET, Color("22313a")))
	_content.add_child(chip)
	var face := TextureRect.new()
	face.texture = S.fitted_sprite(character_id, Vector2(64, 56))
	face.position = Vector2(8, 4)
	face.size = Vector2(64, 56)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(face)
	var short_name := str(PARTY_SHORT_NAMES.get(character_id, ""))
	var display := tr(short_name) if not short_name.is_empty() else tr(str(draft.master_character_def(character_id).get("display_name", character_id)))
	var name_label := S.label(chip, display, Rect2(0, 62, PARTY_CHIP_SIZE.x, 18), 11, S.MUTED, "PartyName")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true

func _build_challenge_button() -> Button:
	return _build_primary_button(tr("挑戦する"), "DetailChallengeButton", func(): challenge_pressed.emit())

## 下の中央の主な行動のボタン（区切り線の下、青い枠）。
func _build_primary_button(text: String, node_name: String, on_pressed: Callable) -> Button:
	S.rect(_content, Rect2(16, 536, _width() - 32, 1), S.PANEL_EDGE)
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.icon = preload("res://src/bossmaker/rbm_world_ui.gd").new().icon("right", S.ACCENT)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.size = CTA_SIZE
	button.position = Vector2((_width() - CTA_SIZE.x) / 2.0, _height() - 66)
	button.add_theme_font_size_override("font_size", 20)
	S.button_style(button, true)
	button.pressed.connect(on_pressed)
	_content.add_child(button)
	return button
