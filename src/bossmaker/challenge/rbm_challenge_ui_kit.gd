class_name RBMChallengeUiKit
extends RefCounted

## CHALLENGE UI再設計（挑戦ハブ + 共通ボス一覧画面、指示書§0〜§28） —
## ハブ/共通一覧/カード表示が共有する、UI非依存の純粋なデータ処理
## （フィルタ・並び替え・抽選）と、カード等の小さな共有Control構築ヘルパー。
##
## 設計方針: このファイル自身はsrc/bossmaker/creator/の確定済みコードへ
## 一切触れない（RBMChallengeEntry既存のヘッダコメントの方針を踏襲）。
## RBMBattleUiKit（戦闘画面専用の共有UIキット）とは責務を分離し、こちらは
## 「ボスを探す・選ぶ」ロビー系画面専用の共有キットとして新設した。
##
## entryは全てRBMLocalStageRepository.list()が返すDictionary形式
## （stage_id/boss_name/appearance_id/status/published/author_name/
## creator_mode/published_at_unix_time/challenge_count/clear_count）を
## そのまま扱う——このクラス自身はRepository/Draftを一切importしない
## 純粋関数の集合。
##
## CHALLENGE discovery 最終調整: challenger_count（人数）→challenge_count
## （回数）へ改名した——同一ユーザーの複数回挑戦もそれぞれ加算される
## 「延べ回数」であって「人数」ではないため、名称を実際の意味へ一致させた。

const MODE_SIMPLE := "simple"
const MODE_ADVANCED := "advanced"

# ---------------------------------------------------------------------------
# §20: published整合性——全カテゴリ/検索/ランダムの共通の前提条件。
# ---------------------------------------------------------------------------

static func filter_published(entries: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		if bool(entry.get("published", false)):
			out.append(entry)
	return out

# ---------------------------------------------------------------------------
# §4-A/§4-B: SIMPLE / HARDCORE
# ---------------------------------------------------------------------------

static func filter_by_mode(entries: Array[Dictionary], mode: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		if str(entry.get("creator_mode", MODE_SIMPLE)) == mode:
			out.append(entry)
	return out

## SIMPLE/HARDCORE等、ユーザーへ見せる表示ラベル。creator_mode自身の内部値
## ("simple"/"advanced")とは独立——他画面（Creatorのモード選択等）が既に
## 使っている語彙と揃える（"advanced"の表示名は既存UIで一貫して"HARDCORE"）。
static func mode_display_text(creator_mode: String) -> String:
	return "HARDCORE" if creator_mode == MODE_ADVANCED else "SIMPLE"

# ---------------------------------------------------------------------------
# §4-D: 新着——公開日時の新しい順。
# ---------------------------------------------------------------------------

static func sort_by_published_at_desc(entries: Array[Dictionary]) -> Array[Dictionary]:
	var out := entries.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("published_at_unix_time", 0)) > int(b.get("published_at_unix_time", 0))
	)
	return out

# ---------------------------------------------------------------------------
# §4-E: 未挑戦——挑戦回数0のみ。
# ---------------------------------------------------------------------------

static func filter_unchallenged(entries: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		if int(entry.get("challenge_count", 0)) == 0:
			out.append(entry)
	return out

# ---------------------------------------------------------------------------
# §4-F: 人気——挑戦回数の多い順。
# ---------------------------------------------------------------------------

static func sort_by_challenge_count_desc(entries: Array[Dictionary]) -> Array[Dictionary]:
	var out := entries.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("challenge_count", 0)) > int(b.get("challenge_count", 0))
	)
	return out

# ---------------------------------------------------------------------------
# §4-G: 高難度——補正クリア率(内部の順位決定専用) = (クリア回数+1)/(挑戦回数+2)
# が低い順。一覧へユーザー表示する「クリア率」は通常の実クリア率
# （clear_count/challenge_count、挑戦回数0なら0%）を必ず使う——補正値は
# ランキングの並び替えにのみ使用し、表示しない。
# ---------------------------------------------------------------------------

static func corrected_clear_rate(entry: Dictionary) -> float:
	var challenges := int(entry.get("challenge_count", 0))
	var clears := int(entry.get("clear_count", 0))
	return float(clears + 1) / float(challenges + 2)

## §14: ユーザーに見せる実際のクリア率（0.0〜1.0）。挑戦回数0は0%
## （「まだ誰にもクリアされていない」を「クリア率100%」のように見せない）。
static func real_clear_rate(entry: Dictionary) -> float:
	var challenges := int(entry.get("challenge_count", 0))
	if challenges <= 0:
		return 0.0
	return float(entry.get("clear_count", 0)) / float(challenges)

static func sort_by_corrected_clear_rate_asc(entries: Array[Dictionary]) -> Array[Dictionary]:
	var out := entries.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return corrected_clear_rate(a) < corrected_clear_rate(b)
	)
	return out

# ---------------------------------------------------------------------------
# §4-C: 注目——「最近伸びているボス」。
#
# 実装前調査の結果: 既存コードに「注目」を算出する正式ロジックは一切存在
# しない（このプロジェクト全体で「挑戦者数」「クリア率」の概念自体が今回
# 新設したものであり、まして「伸び率」のような時系列データは尚更存在しない）。
# 指示書§4-C/§24/無人作業時ルールの明示指示どおり、Claude Code側で独自の
# 算出式を決定していない——ここは意図的な恒等関数（並び替えなし）のまま
# 保留し、将来正式なロジックが決まった時にこの関数の中身だけを差し替えれば
# ハブ/一覧側のコードは一切変更不要な構造にしてある。完了報告で開示。
# ---------------------------------------------------------------------------

static func sort_by_featured(entries: Array[Dictionary]) -> Array[Dictionary]:
	return entries.duplicate()

# ---------------------------------------------------------------------------
# §5: ランダム——カテゴリではない。publishedかつ実際に挑戦可能
# （list()自体が既にis_playable()合格のみを含むため、渡されるentries自体が
# 既にその前提を満たす——呼び出し元がfilter_published()した結果をそのまま
# 渡すだけでよい）な全ボスから、重み付けなしの完全ランダムで1件。
# ---------------------------------------------------------------------------

## rngを明示的に受け取る（テストで決定論的に検証できるようにするため、
## グローバルなrandi()に暗黙依存しない——このプロジェクト全体の「乱数は
## 明示的なRNGソースから」という規約とは別の理由だが、同じ精神——テスト
## 容易性のための明示的注入）。
static func pick_random(entries: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	if entries.is_empty():
		return {}
	var index := rng.randi_range(0, entries.size() - 1)
	return entries[index]

# ---------------------------------------------------------------------------
# §19: 検索——既存ロジックを維持（ボス名: 大文字小文字非依存の部分一致、
# stage_id: 完全一致のみ）。RBMChallengeEntryの既存_refresh_list()が持って
# いた判定式をそのまま関数化しただけ——新しい検索仕様（作者名検索等）は
# 追加しない（§6/§24）。
# ---------------------------------------------------------------------------

static func filter_by_search(entries: Array[Dictionary], name_query: String, id_query: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in entries:
		var boss_name := str(entry.get("boss_name", ""))
		var stage_id := str(entry.get("stage_id", ""))
		if not name_query.is_empty() and not boss_name.to_lower().contains(name_query.to_lower()):
			continue
		if not id_query.is_empty() and stage_id != id_query:
			continue
		out.append(entry)
	return out

# ---------------------------------------------------------------------------
# §3/§9: カード構築——文字ベースのみ（アイコン/絵文字は追加しない）。
# 将来アイコンを追加しやすいよう、画像領域はRBMBattleUiKit.
# build_portrait_placeholder()（既存、将来ここへTextureRectを足すだけで
# 差し替え可能な空の額縁）をそのまま流用する。
# ---------------------------------------------------------------------------

## §9: 一覧カード。全カテゴリで同一の6項目（画像/ボス名/作者名/モード/
## 挑戦回数/クリア率）を常に表示——カテゴリによって項目を隠さない。
## on_clickはstage_id(String)を1引数で受け取るCallable。
static func build_boss_card(entry: Dictionary, is_selected: bool, on_click: Callable) -> PanelContainer:
	var stage_id := str(entry.get("stage_id", ""))
	var card := PanelContainer.new()
	card.name = "BossCard_%s" % stage_id
	card.custom_minimum_size = Vector2(0, 96)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _card_box(is_selected))
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			on_click.call(stage_id)
	)

	var row := HBoxContainer.new()
	row.name = "BossCardRow_%s" % stage_id
	card.add_child(row)

	row.add_child(RBMBattleUiKit.build_portrait_placeholder(72.0, "BossCardImage_%s" % stage_id, RBMVisualAssets.boss_asset(str(entry.get("appearance_id", "")))))

	var info := VBoxContainer.new()
	info.name = "BossCardInfo_%s" % stage_id
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name_label := Label.new()
	name_label.name = "BossCardNameLabel_%s" % stage_id
	name_label.text = str(entry.get("boss_name", ""))
	name_label.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	info.add_child(name_label)

	var author_label := Label.new()
	author_label.name = "BossCardAuthorLabel_%s" % stage_id
	author_label.text = "by %s" % _author_display_text(entry)
	author_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	info.add_child(author_label)

	var mode_label := Label.new()
	mode_label.name = "BossCardModeLabel_%s" % stage_id
	mode_label.text = mode_display_text(str(entry.get("creator_mode", MODE_SIMPLE)))
	mode_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	info.add_child(mode_label)

	var stats_row := HBoxContainer.new()
	stats_row.name = "BossCardStatsRow_%s" % stage_id
	info.add_child(stats_row)

	# CHALLENGE discovery 最終調整 §1: 「挑戦者 12」（人数のように読める）
	# ではなく「挑戦 12回」（延べ回数だと分かる）表記へ変更。
	var challenge_count_label := Label.new()
	challenge_count_label.name = "BossCardChallengeCountLabel_%s" % stage_id
	challenge_count_label.text = TranslationServer.translate("挑戦 %d回") % int(entry.get("challenge_count", 0))
	challenge_count_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	stats_row.add_child(challenge_count_label)

	var clear_rate_label := Label.new()
	clear_rate_label.name = "BossCardClearRateLabel_%s" % stage_id
	clear_rate_label.text = TranslationServer.translate("クリア率 %s") % _percent_text(real_clear_rate(entry))
	clear_rate_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	stats_row.add_child(clear_rate_label)

	return card

## §11: 選択状態が変わるたびに一覧全体をfree()/再構築するのではなく、既存の
## カードインスタンスのスタイルだけをその場で更新する——RBMChallengeEntry.
## _on_stage_row_pressed()はカード自身のgui_inputシグナル経由で呼ばれうる
## ため、そのコールバック実行中に当のカード自身をfree()しようとすると
## Godotが「シグナル発行中のオブジェクトをfreeできない」というエラーで
## 拒否する（実機で確認済み）。スタイル差し替えのみなら、そのcall stack内
## からでも安全に行える。
static func set_card_selected(card: PanelContainer, is_selected: bool) -> void:
	card.add_theme_stylebox_override("panel", _card_box(is_selected))

static func _author_display_text(entry: Dictionary) -> String:
	var author_name := str(entry.get("author_name", ""))
	return author_name if not author_name.is_empty() else TranslationServer.translate("（未設定）")

static func _percent_text(rate: float) -> String:
	return "%.1f%%" % (rate * 100.0)

static func _card_box(is_selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = RBMUiTheme.COLOR_SECONDARY if is_selected else RBMUiTheme.COLOR_PANEL
	box.set_corner_radius_all(RBMUiTheme.CORNER_RADIUS)
	box.set_content_margin_all(8.0)
	box.border_width_left = RBMUiTheme.BORDER_WIDTH
	box.border_width_right = RBMUiTheme.BORDER_WIDTH
	box.border_width_top = RBMUiTheme.BORDER_WIDTH
	box.border_width_bottom = RBMUiTheme.BORDER_WIDTH
	box.border_color = RBMUiTheme.COLOR_ACCENT if is_selected else RBMUiTheme.COLOR_PANEL_BORDER
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

## §3: カテゴリ選択カード（ハブ画面）。文字ベースのみ——画像領域を一切持た
## ない（将来アイコンを追加する際は、この関数を拡張するかRBMBattleUiKit.
## build_portrait_placeholder()相当を追加する形になる想定だが、現時点では
## 意図的に何も表示しない、§3の明示要求）。
## CHALLENGE discovery 最終調整 §3: disabledはオプション引数（既定false、
## 全ての既存呼び出し元は無改修のまま）——「注目」のような未実装カテゴリを
## 準備中として無効化するために追加した。RBMUiThemeは既にButtonの
## "disabled"スタイルボックス/font_disabled_colorを定義済み（他の全画面が
## 使っている既存の無効状態の見た目をそのまま流用、新しい見た目は作らない）。
static func build_category_button(text: String, node_name: String, on_pressed: Callable, disabled: bool = false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(160, 64)
	button.pressed.connect(on_pressed)
	button.disabled = disabled
	return button
