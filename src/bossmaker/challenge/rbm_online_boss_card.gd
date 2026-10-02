class_name RBMOnlineBossCard
extends Button

## オンライン一覧(左側)のボスカード1枚(2026-10)。サムネイル・ボス名・作者名・SIMPLE/HARDCOREの札・
## 挑戦者数・クリア率を見せる。カテゴリごとの違い:
##   新着 = 作者名の右に公開日、人気 = 順位+挑戦者数を強調、高難度 = 順位+クリア率を強調。
## 押すとpressedが出るだけ(詳細の取得・挑戦の開始は一覧画面が行う)。
## 状態の見え方: 選択中 = 青い枠・淡い発光・左端の青線 / マウスを重ねた時 = 少し明るく銀の枠 /
## キーボード・パッドの操作対象 = 外側の白い枠(RBMChallengeListStyle.focus_ring)。

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const SIZE := Vector2(412, 116)
const THUMBNAIL_FIT := Vector2(86, 86)

var boss_id := ""
var _selected := false

## boss: list-bosses等の1行(id/boss_name/author_name/published_at/creator_mode/appearance_id/
## unique_challengers/unique_clearers)。rank: 人気/高難度の順位(それ以外は0=出さない)。
func setup(boss: Dictionary, category: String, rank: int) -> void:
	boss_id = str(boss.get("id", ""))
	custom_minimum_size = SIZE
	text = ""
	_apply_styles()
	_build(boss, category, rank)

func set_selected(selected: bool) -> void:
	_selected = selected
	_apply_styles()
	var bar := get_node_or_null("SelectedBar") as CanvasItem
	if bar != null:
		bar.visible = selected

func is_selected() -> bool:
	return _selected

func _apply_styles() -> void:
	var normal := S.box(S.CARD, S.CARD_EDGE)
	var hover := S.box(S.CARD_HOVER, Color(S.SILVER, 0.55))
	if _selected:
		normal = S.box(S.CARD_SELECTED, Color(S.ACCENT, 0.75))
		normal.shadow_color = Color(S.ACCENT, 0.16)
		normal.shadow_size = 6
		hover = normal
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", hover)
	add_theme_stylebox_override("hover_pressed", hover)
	add_theme_stylebox_override("focus", S.focus_ring())

func _build(boss: Dictionary, category: String, rank: int) -> void:
	var thumbnail := Panel.new()
	thumbnail.name = "Thumbnail"
	thumbnail.position = Vector2(10, 10)
	thumbnail.size = Vector2(96, 96)
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumbnail.add_theme_stylebox_override("panel", S.box(Color("070b0f"), Color("1d2a31")))
	add_child(thumbnail)
	S.rect(thumbnail, Rect2(1, 70, 94, 25), Color("0f1a20"))
	var sprite := TextureRect.new()
	sprite.name = "ThumbnailSprite"
	sprite.texture = S.fitted_sprite(RBMVisualAssets.boss_asset(str(boss.get("appearance_id", ""))), THUMBNAIL_FIT)
	sprite.position = Vector2(5, 5)
	sprite.size = Vector2(86, 88)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumbnail.add_child(sprite)

	if rank > 0:
		var top := rank <= 3
		var badge := Label.new()
		badge.name = "RankBadge"
		badge.text = str(rank)
		badge.position = Vector2(4, 4)
		badge.custom_minimum_size = Vector2(30, 24)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_font_override("font", S.number_font())
		badge.add_theme_font_size_override("font_size", 15)
		badge.add_theme_color_override("font_color", S.TEXT if top else S.MUTED)
		badge.add_theme_stylebox_override("normal", S.box(Color("0f2a30") if top else S.PANEL, Color(S.ACCENT, 0.8) if top else Color("3a4a53")))
		add_child(badge)

	var name_label := S.label(self, str(boss.get("boss_name", "")), Rect2(122, 10, 280, 28), 18, S.TEXT, "NameLabel")
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	var author := str(boss.get("author_name", ""))
	var author_label := S.label(self, tr("by %s") % (author if not author.is_empty() else tr("（未設定）")), Rect2(122, 36, 200, 22), 13, S.MUTED, "AuthorLabel")
	author_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	author_label.clip_text = true
	if category == RBMOnlineBossListView.CATEGORY_NEW:
		var date := S.label(self, S.local_published_date_text(str(boss.get("published_at", ""))), Rect2(292, 36, 110, 22), 13, S.SILVER, "DateLabel")
		date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		date.add_theme_font_override("font", S.number_font())
	S.mode_tag(self, str(boss.get("creator_mode", RBMCreatorDraft.CREATOR_MODE_SIMPLE)), Vector2(122, 80))

	# 数値が無い応答(更新前のサーバー)や挑戦者0人では「—」にして、0人・0%と誤って見せない。
	var has_counts := boss.has("unique_challengers")
	var challengers := int(boss.get("unique_challengers", 0))
	var challengers_text := tr("%d人") % challengers if has_counts else "—"
	var rate_text := "—"
	if has_counts and boss.has("unique_clearers") and challengers > 0:
		rate_text = "%.1f%%" % (float(boss["unique_clearers"]) / float(challengers) * 100.0)
	_stat(tr("挑戦者"), challengers_text, Vector2(250, 66), "Challengers", category == RBMOnlineBossListView.CATEGORY_POPULAR)
	_stat(tr("クリア率"), rate_text, Vector2(330, 66), "ClearRate", category == RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY)

	var bar := S.rect(self, Rect2(0, 8, 3, SIZE.y - 16), S.ACCENT, "SelectedBar")
	bar.visible = _selected

func _stat(caption: String, value: String, at: Vector2, node_prefix: String, emphasized: bool) -> void:
	S.label(self, caption, Rect2(at.x, at.y, 80, 16), 11, S.ACCENT_SOFT.lightened(0.2) if emphasized else S.DIM, node_prefix + "Caption")
	var value_label := S.label(self, value, Rect2(at.x, at.y + 16, 80, 24), 18 if emphasized else 16, S.EMPHASIS if emphasized else S.SILVER, node_prefix + "Value")
	value_label.add_theme_font_override("font", S.number_font())
