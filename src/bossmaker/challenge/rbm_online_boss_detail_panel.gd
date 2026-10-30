class_name RBMOnlineBossDetailPanel
extends Panel

## オンライン一覧(右側)の「選択中ボスの詳細」(2026-10)。
## 上部いっぱいに、そのボスの戦闘背景(戦闘画面と同じ決め方: RBMBattleBackgrounds.texture_for。
## 専用背景 backgrounds/<boss_id>/background.png があればそれ、無ければ作者が選んだ昼/夜の中庭)を
## 敷いてボスを立たせ、右にモード・名前・作者・公開日・勝利条件・ボスHP・弱点を並べる。
## 下に作者メッセージ・攻略パーティ・「挑戦する」。挑戦者数/クリア率は左のカードにあるので出さない。
## 状態: 未選択 / 取得中 / 取得失敗 / 表示。押された「挑戦する」はchallenge_pressedで知らせるだけ。
## 2026-10-28: 表示の時は2ページ（1=今までの基本情報、2=詳細情報）。右端の中央の右向き矢印で2ページ目、
## 2ページ目の左端の中央の左向き矢印で戻る。別のボスを選んだら1ページ目に戻す。2ページ目は STEP5 の情報公開設定
## （draft.is_challenge_info_visible、挑戦確認画面と同じ判定）どおりに、非公開の項目は値を作らず「？？？」／「非公開」だけを出す。

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
## ページ送りの矢印（右端・左端の中央）と、1ページ目の右の行が矢印に重ならないように空ける幅。
const PAGE_ARROW_SIZE := Vector2(30, 60)
const PAGE_ARROW_GAP := 34.0
## 2ページ目の中身の左右（左の矢印の分を空ける）。
const PAGE2_LEFT := 56.0
## 攻略パーティの枠に出す短い呼び名(正式名は長くて枠に収まらないため。仮の呼び名、2026-10)。
const PARTY_SHORT_NAMES := {
	"hero": "勇者", "butler": "老執事", "healer": "少女", "samurai": "侍", "tank": "ハンマー使い",
}

## ボスごとの背景の任意の上書きと命名規則(rbm_battle_backgrounds.gd)。戦闘画面
## (RBMFullscreenBattleUi.boss_backgrounds/background_convention)と同じ既定値で、テストでは差し替えられる。
var boss_backgrounds: Dictionary = RBMBattleBackgrounds.BOSS_BACKGROUNDS
var background_convention: String = RBMBattleBackgrounds.CONVENTION

var _content: Control
## 表示中のボス（ページを切り替えて描き直すため）と、今のページ（1 か 2）。
var _summary: Dictionary = {}
var _draft: RBMCreatorDraft
var _page := 1

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
	_page = 1
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
	# 別のボスになったら基本情報（1ページ目）へ戻す。同じボスの描き直しならページはそのまま。
	if _draft == null or str(summary.get("id", "")) != str(_summary.get("id", "")) or summary.get("id", null) == null:
		_page = 1
	_summary = summary
	_draft = draft
	if _page == 2 and _detail_page_enabled():
		_show_detail_page(summary, draft)
		return
	_page = 1
	_clear()
	_build_stage(draft)
	_build_header(summary)
	_build_header_extras(summary, draft)
	var y := 146.0
	var arrow_room := PAGE_ARROW_GAP if _detail_page_enabled() else 0.0
	for row in _detail_rows(summary, draft):
		S.label(_content, row["caption"], Rect2(INFO_X, y, _caption_width(), 26), 13, _caption_color())
		var value := S.label(_content, row["value"], Rect2(INFO_X + _caption_width() + 4, y, _width() - INFO_X - 20 - arrow_room - _caption_width() - 4, 26), 15, row.get("color", S.SILVER), row["name"])
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value.clip_text = true
		if bool(row.get("latin", false)):
			value.add_theme_font_override("font", S.number_font())
		y += 32
	var status := _status_line(summary, draft)
	S.label(_content, status[0], Rect2(INFO_X, y + 6, _width() - INFO_X - 20 - arrow_room, 24), 13, status[1], "DetailClearCheck")

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
	if _detail_page_enabled():
		_page_arrow("right", "DetailNextPageButton", tr("次へ"), _width() - PAGE_ARROW_SIZE.x - 6.0, 2)

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
		{"caption": captions[1], "value": draft.win_condition_text() if draft.is_challenge_info_visible("win_condition") else tr("非公開"), "name": "DetailWinConditionValue"},
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

# ---------------------------------------------------------------------------
# ページ送り（2026-10-28）: 1ページ目=基本情報（上の show_boss）、2ページ目=詳細情報。

## 2ページ目を持つか（保存したボス戦の一覧は作者自身のボスなので持たない）。
func _detail_page_enabled() -> bool:
	return true

func current_page() -> int:
	return _page

## 表示中のボスのページを切り替える（ボスを表示していない時は何もしない）。
func show_page(page: int) -> void:
	if _draft == null or not _detail_page_enabled():
		return
	_page = clampi(page, 1, 2)
	if _page == 2:
		_show_detail_page(_summary, _draft)
	else:
		show_boss(_summary, _draft)

## 右端（→）・左端（←）の中央の矢印。
func _page_arrow(direction: String, node_name: String, tooltip: String, x: float, target_page: int) -> Button:
	var button := Button.new()
	button.name = node_name
	button.tooltip_text = tooltip
	button.icon = preload("res://src/bossmaker/rbm_world_ui.gd").new().icon(direction, S.ACCENT)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.size = PAGE_ARROW_SIZE
	button.position = Vector2(x, (_height() - PAGE_ARROW_SIZE.y) / 2.0)
	S.button_style(button, true)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 16
		style.content_margin_bottom = 16
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(show_page.bind(target_page))
	_content.add_child(button)
	return button

## 2ページ目: 能力（HP・ATK・SPD）・弱点・耐性・勝利条件・ボススキル詳細。
## 非公開の項目は値を作らない（文字列にする前に is_challenge_info_visible で分ける）。
func _show_detail_page(summary: Dictionary, draft: RBMCreatorDraft) -> void:
	_clear()
	var left := PAGE2_LEFT
	var width := _width() - left * 2.0
	S.mode_tag(_content, str(summary.get("creator_mode", RBMCreatorDraft.CREATOR_MODE_SIMPLE)), Vector2(left, 22))
	var title := S.label(_content, str(summary.get("boss_name", "")), Rect2(left, 50, width, 40), 24 if _is_japanese() else 22, S.TEXT, "DetailPage2BossName")
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	S.rect(_content, Rect2(left, 96, width, 1), S.PANEL_EDGE)

	# 能力: 3つの枠に HP・ATK・SPD。
	S.section_title(_content, tr("能力"), Vector2(left, 108))
	var stat_w := (width - 16.0) / 3.0
	var stats := [["HP", "hp", draft.hp], ["ATK", "atk", draft.atk], ["SPD", "spd", draft.spd]]
	for i in stats.size():
		var key := str(stats[i][1])
		var box := Panel.new()
		box.name = "DetailStat_%s" % key
		box.position = Vector2(left + (stat_w + 8.0) * i, 140)
		box.size = Vector2(stat_w, 58)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_stylebox_override("panel", S.box(S.INSET, Color("1a2830")))
		_content.add_child(box)
		S.label(box, str(stats[i][0]), Rect2(14, 0, 60, 58), 14, S.DIM).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var shown := draft.is_challenge_info_visible(key)
		var value := S.label(box, str(stats[i][2]) if shown else tr("？？？"), Rect2(70, 0, stat_w - 84, 58), 24, S.TEXT if shown else S.MUTED, "DetailStatValue_%s" % key)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.clip_text = true
		if shown:
			value.add_theme_font_override("font", S.number_font())

	# 弱点・耐性・勝利条件（見出しと値の2列）。「特殊条件」は 2026-10-29 に外した（勝利条件と紛らわしい）。
	var rows := [
		[tr("弱点"), _attribute_text(draft, "weak_attributes", draft.weak_attributes), "DetailPage2Weak", draft.is_challenge_info_visible("weak_attributes")],
		[tr("耐性"), _attribute_text(draft, "resist_attributes", draft.resist_attributes), "DetailPage2Resist", draft.is_challenge_info_visible("resist_attributes")],
		[tr("勝利条件"), draft.win_condition_text() if draft.is_challenge_info_visible("win_condition") else tr("非公開"), "DetailPage2WinCondition", draft.is_challenge_info_visible("win_condition")],
	]
	var y := 214.0
	var caption_w := _caption_width()
	for row in rows:
		S.label(_content, str(row[0]), Rect2(left, y, caption_w, 26), 13, S.DIM)
		var hidden := not bool(row[3])
		var value := S.label(_content, str(row[1]), Rect2(left + caption_w + 4, y, width - caption_w - 4, 26), 15, S.MUTED if hidden else S.SILVER, str(row[2]))
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value.clip_text = true
		y += 30

	# ボススキル詳細（非公開なら1行だけ。多い時は枠の中で送る）。
	S.section_title(_content, tr("ボススキル"), Vector2(left, y + 8))
	var skills_box := Panel.new()
	skills_box.name = "DetailSkillsBox"
	skills_box.position = Vector2(left, y + 40)
	skills_box.size = Vector2(width, 528.0 - (y + 40))
	skills_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skills_box.add_theme_stylebox_override("panel", S.box(S.INSET, Color("1a2830")))
	_content.add_child(skills_box)
	var scroll := ScrollContainer.new()
	scroll.name = "DetailSkillsScroll"
	scroll.position = Vector2(12, 8)
	scroll.size = skills_box.size - Vector2(24, 16)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	skills_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "DetailSkillsList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	if not draft.is_challenge_info_visible("boss_skills"):
		_skill_line(list, tr("非公開"), 15, S.MUTED, "DetailSkillsHidden")
	elif draft.skills.is_empty():
		_skill_line(list, tr("（なし）"), 15, S.MUTED, "DetailSkillsNone")
	else:
		for skill in draft.skills:
			_skill_line(list, tr("・%s") % str(skill.get("name", "")), 15, S.TEXT)
			_skill_line(list, "    %s" % _boss_skill_detail_text(skill, draft), 13, S.MUTED)

	_build_actions()
	_page_arrow("left", "DetailPrevPageButton", tr("戻る"), 6.0, 1)

func _skill_line(list: VBoxContainer, text: String, font_size: int, color: Color, node_name: String = "") -> void:
	var line := Label.new()
	if not node_name.is_empty():
		line.name = node_name
	line.text = text
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", font_size)
	line.add_theme_color_override("font_color", color)
	list.add_child(line)

func _attribute_text(draft: RBMCreatorDraft, key: String, attributes: Array) -> String:
	if not draft.is_challenge_info_visible(key):
		return tr("？？？")
	if attributes.is_empty():
		return tr("なし")
	var labels: Array = []
	for attribute in attributes:
		labels.append(tr(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(str(attribute), str(attribute)))))
	return ", ".join(labels)

## ボススキル1つの詳細（挑戦確認画面 RBMChallengeConfirmView._skill_detail_text と同じ粒度・同じ文言）。
func _boss_skill_detail_text(skill: Dictionary, draft: RBMCreatorDraft) -> String:
	match str(skill.get("type", "")):
		"attack":
			var target_label := tr("単体") if str(skill.get("target", "single")) == "single" else tr("全体")
			var attribute_id := str(skill.get("attribute", "NEUTRAL"))
			return tr("攻撃 / %s / %s / ATK ×%.2f") % [target_label, tr(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id))), float(skill.get("atk_multiplier", 0.0))]
		"self_heal":
			if str(skill.get("heal_mode", "fixed")) == "percent":
				return tr("回復 / 最大HPの%.1f%%（HP %d回復相当）") % [float(skill.get("heal_percent", 0.0)), draft.resolved_heal_amount(skill)]
			return tr("回復 / HP %d回復") % int(skill.get("heal_fixed_amount", 0))
		"atk_self_buff":
			return tr("自己強化 / ATK ×%.2f / %dターン") % [float(skill.get("buff_multiplier", 1.0)), int(skill.get("duration_turns", 1))]
		_:
			return str(skill.get("type", ""))
