class_name RBMSavedBossCard
extends RBMOnlineBossCard

## 保存したボス戦の一覧（ボス戦作成 → 保存したボス戦を編集、2026-10）のカード1枚。
## 挑戦側のオンライン一覧のカード（RBMOnlineBossCard）と同じ土台（大きさ・サムネイル・ボス名・選択中の見え方）で、
## 作者・挑戦者数・クリア率の代わりに、状態・ステージID・公開・覚醒・最終更新を見せる。
## 押すと pressed が出るだけ（詳細の表示・編集・削除は RBMCreatorEntry が行う）。
##
## entry: RBMCreatorEntry._saved_entries() の1件（RBMLocalStageRepository.list() の行に awakening を足したもの）。

const M := preload("res://src/bossmaker/challenge/rbm_menu_ui.gd")

## 状態の表示名と色（状態は文字で示し、色だけに頼らない、ACCESSIBILITY §3）。
const STATUS_LABELS := {
	"draft": "下書き",
	"playable": "挑戦可能",
	"clear_checked": "✓ クリアチェック済み",
}

var stage_id := ""

func setup_saved(entry: Dictionary) -> void:
	stage_id = str(entry.get("stage_id", ""))
	name = "StageRow_%s" % stage_id
	var shown := entry.duplicate()
	shown["id"] = stage_id
	if str(entry.get("boss_name", "")).is_empty():
		shown["boss_name"] = tr("（名前未設定）")
	setup(shown, "", 0)
	M.accessible_name(self, str(shown["boss_name"]))

static func status_color(status: String) -> Color:
	match status:
		"clear_checked":
			return S.EMPHASIS
		"playable":
			return S.SILVER
	return S.MUTED

static func status_text(status: String) -> String:
	return TranslationServer.translate(str(STATUS_LABELS.get(status, status)))

## 最終更新の短い表示: 今年なら MM/DD、それ以外は YYYY/MM/DD（端末の時刻帯）。
static func short_date_text(unix_time: int) -> String:
	if unix_time <= 0:
		return "—"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var date := Time.get_datetime_dict_from_unix_time(unix_time + bias)
	var now := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + bias)
	if int(date["year"]) == int(now["year"]):
		return "%02d/%02d" % [date["month"], date["day"]]
	return "%04d/%02d/%02d" % [date["year"], date["month"], date["day"]]

## 最終更新の詳しい表示: YYYY/MM/DD HH:MM（端末の時刻帯）。
static func full_date_text(unix_time: int) -> String:
	if unix_time <= 0:
		return "—"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var date := Time.get_datetime_dict_from_unix_time(unix_time + bias)
	return "%04d/%02d/%02d %02d:%02d" % [date["year"], date["month"], date["day"], date["hour"], date["minute"]]

func _build_details(entry: Dictionary, _category: String) -> void:
	var status := str(entry.get("status", "draft"))
	var status_label := S.label(self, status_text(status), Rect2(122, 36, 170, 22), 13, status_color(status), "StatusLabel")
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.clip_text = true
	var id_label := S.label(self, "ID %s" % str(entry.get("stage_id", "")), Rect2(262, 36, 140, 22), 12, S.MUTED, "StageIdLabel")
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	id_label.add_theme_font_override("font", S.number_font())

	var mode_tag := S.mode_tag(self, str(entry.get("creator_mode", RBMCreatorDraft.CREATOR_MODE_SIMPLE)), Vector2(122, 80))
	var x := 122.0 + mode_tag.get_combined_minimum_size().x + 6
	if bool(entry.get("online_published", false)):
		var published := M.tag(self, tr("公開中"), Vector2(x, 80), S.EMPHASIS, Color(S.ACCENT_SOFT, 0.9), Color(S.ACCENT, 0.07), false, "PublishedTag")
		x += published.get_combined_minimum_size().x + 6
	if bool(entry.get("awakening", false)):
		var awakening := M.tag(self, tr("覚醒"), Vector2(x, 80), Color("e0b070"), Color("7a5a2a"), Color("7a5a2a", 0.18), false, "AwakeningTag")
		x += awakening.get_combined_minimum_size().x + 6

	var caption := S.label(self, tr("最終更新"), Rect2(290, 60, 112, 18), 12, S.MUTED, "UpdatedCaption")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var date := S.label(self, short_date_text(int(entry.get("updated_unix_time", 0))), Rect2(290, 78, 112, 26), 14, S.SILVER, "UpdatedLabel")
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	date.add_theme_font_override("font", S.number_font())
	# 札が最終更新の日付に届く時（英語など文字が長い時）は、「最終更新 日付」を札の上の1行にまとめる。
	var date_width := date.get_combined_minimum_size().x
	if x > date.position.x + date.size.x - date_width - 6:
		date.position = Vector2(date.position.x, 57)
		date.size.y = 22
		caption.position = Vector2(150, 59)
		caption.size = Vector2(date.position.x + date.size.x - date_width - 8 - 150, 18)
