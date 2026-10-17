class_name RBMSavedBossDetailPanel
extends RBMOnlineBossDetailPanel

## 保存したボス戦の一覧（2026-10）の右側「選択中のボス戦の詳細」。挑戦側のオンライン一覧の詳細
## （RBMOnlineBossDetailPanel）と同じ形（戦闘背景にボスを立たせ、右にモード・名前・作者と情報の行、
## 下に作者メッセージ・攻略パーティ）で、行の中身と下の操作だけを差し替える:
##   行 = ステージID・最終更新・ボスHP・公開、行の下 = 状態（クリアチェック済み／挑戦可能／下書き）、
##   下の操作 = 「編集する」（主な行動、中央）と「削除」（左下、控えめな赤）。
## 押された操作は edit_pressed / delete_pressed で知らせるだけ（開く・削除の確認は RBMCreatorEntry が行う）。
##
## summary: RBMCreatorEntry._saved_entries() の1件（stage_id/boss_name/author_name/creator_mode/status/
## published/updated_unix_time/awakening）。

signal edit_pressed()
signal delete_pressed()

const M := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")
const DELETE_BUTTON_SIZE := Vector2(112, 44)

func _empty_hint_text() -> String:
	return tr("左の一覧から編集するボス戦を選んでください")

func _build_header_extras(summary: Dictionary, _draft: RBMCreatorDraft) -> void:
	if not bool(summary.get("awakening", false)):
		return
	var mode_tag := _content.get_node_or_null("ModeTag") as Label
	var x := INFO_X + (mode_tag.get_combined_minimum_size().x + 6 if mode_tag != null else 0.0)
	M.tag(_content, tr("覚醒あり"), Vector2(x, 22), Color("e0b070"), Color("7a5a2a"), Color("7a5a2a", 0.18), false, "DetailAwakeningTag")

func _row_captions() -> Array:
	return [tr("ステージID"), tr("最終更新"), tr("ボスHP"), tr("公開状態")]

## オンライン公開中なら、挑戦する人が検索に使う公開ID（2026-10-17 PX-03）。手元のステージIDとは別のもの。
func _public_id(summary: Dictionary) -> String:
	if not bool(summary.get("online_published", false)):
		return ""
	return RBMPublicBossId.from_boss_id(str(summary.get("online_boss_id", "")))

## 作者自身の保存データなので、挑戦する人への公開設定（？？？）に関係なくHPをそのまま見せる。
func _detail_rows(summary: Dictionary, draft: RBMCreatorDraft) -> Array:
	var captions := _row_captions()
	var published := bool(summary.get("online_published", false))  # オンラインの公開状態（PX-05）
	return [
		{"caption": captions[0], "value": str(summary.get("stage_id", "")), "name": "DetailStageIdValue", "latin": true},
		{"caption": captions[1], "value": RBMSavedBossCard.full_date_text(int(summary.get("updated_unix_time", 0))), "name": "DetailUpdatedValue", "latin": true},
		{"caption": captions[2], "value": str(draft.hp), "name": "DetailBossHpValue"},
		{"caption": captions[3], "value": tr("公開中") if published else tr("非公開"), "name": "DetailPublishStateValue", "color": S.EMPHASIS if published else S.SILVER},
	]

## 小さな見出しの文字は、地との明暗差が足りる色にする（ACCESSIBILITY §2）。
func _caption_color() -> Color:
	return S.MUTED

func _status_line(summary: Dictionary, _draft: RBMCreatorDraft) -> Array:
	match str(summary.get("status", "draft")):
		"clear_checked":
			return [tr("✓ クリアチェック済み"), S.ACCENT_SOFT.lightened(0.25)]
		"playable":
			return [tr("挑戦可能（クリアチェック前）"), S.MUTED]
	return [tr("下書き（未完成の項目があります）"), S.MUTED]

func _party_note_text() -> String:
	return tr("挑戦する人が使う固定メンバー")

func _build_empty_party() -> void:
	S.label(_content, tr("（まだ選ばれていません）"), Rect2(16, 446, 400, 28), 14, S.MUTED, "DetailPartyEmpty")

func _build_actions() -> void:
	var edit := _build_primary_button(tr("編集する"), "DetailEditButton", func(): edit_pressed.emit())
	var delete := Button.new()
	delete.name = "DetailDeleteButton"
	delete.text = tr("削除")
	delete.add_theme_font_size_override("font_size", 15)
	M.danger_style(delete)
	delete.pressed.connect(func(): delete_pressed.emit())
	_content.add_child(delete)
	delete.size = Vector2(maxf(DELETE_BUTTON_SIZE.x, delete.get_combined_minimum_size().x), DELETE_BUTTON_SIZE.y)
	delete.position = Vector2(16, edit.position.y + (edit.size.y - DELETE_BUTTON_SIZE.y) / 2.0)

## 開けなかった時（ファイルが壊れている・消えている）。行の内容は出さず、理由だけを見せる。
func show_open_error(summary: Dictionary) -> void:
	show_error(summary, tr("このボス戦を開けませんでした。\nファイルが壊れている可能性があります。"))
