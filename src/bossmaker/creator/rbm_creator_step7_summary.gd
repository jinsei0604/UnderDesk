class_name RBMCreatorStep7Summary
extends Control

## Creator UI改修（STEP4統合+最終確認再設計、2026-09-05）§18〜§27: 新STEP5
## 「最終確認」——STEP1〜4共通フレーム（左STEPナビ＋右BOSS PROFILE）を使わない
## 明示的な例外。全画面専用レイアウトで4セクションのみを持つ:
## ①「作成内容」（STEP1〜4それぞれ名前＋[編集]のみ、要約情報は一切表示
## しない——STEP1〜4自身と右BOSS PROFILEパネルが既にその役割を担うため）
## ②「挑戦設定」（作者メッセージ＋情報公開設定、既存のまま）
## ③「動作確認」（任意のTEST BATTLE）
## ④「CLEAR CHECK」（未達成/達成済みの状態表示＋専用の開始ボタン、保存/
## 公開のボタン列とは独立したセクション）。
## 下部バーは「← 戻る」（左）／「保存」「公開」（右）のみ——RBMCreatorMain
## の共有_nav_row（戻る/最終確認へ戻る/次へ）はこのSTEPでは非表示にする
## （RBMCreatorMain._refresh()参照）ため、戻るはこの画面自身が持つ。
##
## §23で明示的に削除したもの: 作成モード（SIMPLE/HARDCORE）切替UI、
## 攻略パーティへの予想ダメージUI——いずれも「この画面から削除する」だけの
## 指示であり、機能自体をゲームから削除するかどうかは決定していない
## （切替ロジック自体はRBMCreatorDraft.set_creator_mode()等に無改修のまま
## 残置、予想ダメージもRBMCreatorDraft.party_damage_preview()等に無改修の
## まま残置——このファイルからの呼び出しを削除しただけ）。
##
## §24〜§27（公開機能、ユーザー確定仕様）: 保存は常に無条件で可能。公開は
## Clear Check達成時のみ可能で、実際にCHALLENGE側へ露出させる実効を持つ
## （RBMCreatorMain.press_publish()/press_unpublish()参照）。

const TIMING_LABELS := RBMCreatorStep4Actions.TIMING_LABELS
const TYPE_LABELS := RBMActionEditorForm.TYPE_LABELS

## Phase 1 Step 7 §14（公開設定の最終修正で7→6項目へ確定）、実機プレイ改善③
## item1（6→8項目）: CHALLENGE確認画面での表示/非表示設定ラベル。
const VISIBILITY_LABELS := {
	"hp": "HP",
	"atk": "ATK",
	"spd": "SPD",
	"weak_attributes": "弱点",
	"resist_attributes": "耐性",
	"boss_skills": "ボススキル詳細",
	"win_condition": "勝利条件",
	"special_condition": "特殊条件",
}

const CONTENT_SIDE_MARGIN_PX := 80.0

var draft: RBMCreatorDraft
var main: Node

var _content: VBoxContainer
var _test_battle_button: Button
var _clear_check_button: Button
var _clear_check_status_label: Label
var _save_button: Button
var _publish_button: Button
var _unpublish_button: Button
var _publish_status_label: Label

## Phase 4C: ローカル公開(_publish_button/_unpublish_button、既存仕様は
## 無改修)とは別の、オンライン公開専用の操作。RBMBossPublisherの状態を
## そのまま反映するだけ——独自のClear Check判定は持たない
## (RBMOnlineBossPayload.build_for_publish()が既存のis_clear_check_
## currently_valid()を再利用する)。
var _publish_online_button: Button
var _online_status_label: Label
var _boss_publisher: RBMBossPublisher

var _author_notes_edit: TextEdit
var _author_notes_count_label: Label
var _visibility_checkboxes: Dictionary = {}  # key(String) -> CheckBox

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

## RBMCreatorMain._build_ui()はSTEP1〜5すべてのビューへ即座にsetup()を呼ぶ
## が、refresh()自身は「現在表示中のSTEPのビュー」にしか呼ばれない
## （current_step初期値1のため、最終確認画面へ一度も遷移していない起動
## 直後はこのビューのrefresh()がまだ一度も呼ばれていない状態がありうる、
## test_rbm_clear_check.gd:test_step7_has_test_battle_and_clear_check_buttons
## 参照）。TestBattleButton/ClearCheckButton/ClearCheckStatusLabelは
## setup()直後から実在している必要があるため、_content配下の他セクション
## （refresh()のたび作り直す）とは別に、この3つだけをここで一度だけ生成し
## 永続させる——refresh()側は_move_into()で該当セクションへ配置し直す
## だけで、ノード自体の生成・シグナル接続はやり直さない。
func _build_persistent_controls() -> void:
	_test_battle_button = Button.new()
	_test_battle_button.name = "TestBattleButton"
	_test_battle_button.text = "テストバトル"
	_test_battle_button.pressed.connect(func(): main.press_test_battle())

	_clear_check_status_label = Label.new()
	_clear_check_status_label.name = "ClearCheckStatusLabel"

	_clear_check_button = Button.new()
	_clear_check_button.name = "ClearCheckButton"
	_clear_check_button.text = "クリアチェックを開始"
	_clear_check_button.pressed.connect(func(): main.press_clear_check())

	## setup()直後、まだ一度もrefresh()が呼ばれていない間もfind_child()経由で
	## 発見できるよう、いったんこのControl自身へ直接の子として加えておく
	## （まだどのセクションにも属していない一時的な置き場所）——最初の
	## refresh()が_move_into()で本来の「動作確認」/「CLEAR CHECK」セクション
	## へ確実に移す。
	add_child(_test_battle_button)
	add_child(_clear_check_status_label)
	add_child(_clear_check_button)

## queue_free()予定の旧セクションから、まだ生きている永続コントロールだけを
## 救出して新しいセクションへ移す——remove_child()直後のqueue_free()と
## 同じ既存規約（名前衝突防止）に加え、reparent()自身は「現在の親から
## 出す→新しい親へ入れる」を1回で行うため、旧親が既にツリーから
## remove_child()済みの状態（次のqueue_free()待ち）でも安全に機能する。
func _move_into(control: Control, new_parent: Control) -> void:
	if control.get_parent() != null:
		control.reparent(new_parent)
	else:
		new_parent.add_child(control)

func _build_ui() -> void:
	## §3（旧実装からの継続的な既知の教訓）: scroll（確認内容）とbottom_bar
	## （戻る/保存/公開ボタン列）を、このControl自身へ直接の兄弟として加える
	## とbareなControlの子として重なって描画されるため、1つのVBoxContainer
	## で両者を包む——scroll自身のSIZE_EXPAND_FILLも、親がbare Controlでは
	## 伝播先が無く機能しない。
	var outer := VBoxContainer.new()
	outer.name = "SummaryOuter"
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = CONTENT_SIDE_MARGIN_PX
	outer.offset_right = -CONTENT_SIDE_MARGIN_PX
	add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	_content = VBoxContainer.new()
	_content.name = "SummaryContent"
	_content.add_theme_constant_override("separation", 16)
	scroll.add_child(_content)

	## §19: 「← 戻る」（左）／「保存」「公開」（右）。RBMCreatorMainの共有
	## 戻る/次へ行はこのSTEPでは非表示になる（RBMCreatorMain._refresh()の
	## on_summary分岐参照）ため、この画面専用の戻るボタンを持つ。
	var bottom_bar := HBoxContainer.new()
	bottom_bar.name = "SummaryBottomBar"
	outer.add_child(bottom_bar)

	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.text = "← 戻る"
	back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	back_button.pressed.connect(func(): main.press_back())
	bottom_bar.add_child(back_button)

	## ユーザー確定仕様（公開機能）: STEP5は現在の公開状態（公開中/未公開）を
	## 常に一目で分かる形で示す——保存/公開ボタンと同じ固定バー内に置き、
	## 挑戦設定セクションをスクロールしていても見える。
	_publish_status_label = Label.new()
	_publish_status_label.name = "PublishStatusLabel"
	bottom_bar.add_child(_publish_status_label)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(bottom_spacer)

	_save_button = Button.new()
	_save_button.name = "SaveButton"
	_save_button.text = "保存"
	_save_button.pressed.connect(func(): main.press_save())
	bottom_bar.add_child(_save_button)

	## §25/§27: 公開はClear Check達成済みの場合のみ有効（disabled=trueで
	## クリック自体を防ぐ）。公開中は代わりに「公開を取り下げる」を表示する
	## （refresh()がvisibleを排他的に切り替える）。
	_publish_button = Button.new()
	_publish_button.name = "PublishButton"
	_publish_button.text = "公開"
	_publish_button.pressed.connect(func(): main.press_publish())
	bottom_bar.add_child(_publish_button)

	_unpublish_button = Button.new()
	_unpublish_button.name = "UnpublishButton"
	_unpublish_button.text = "公開を取り下げる"
	_unpublish_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_unpublish_button.pressed.connect(func(): main.press_unpublish())
	bottom_bar.add_child(_unpublish_button)

	## Phase 4C: ローカル公開(上記_publish_button)とは別のオンライン公開。
	## Clear Check判定は共有する(disabled条件はrefresh()で_publish_buttonと
	## 同じ式を使う)が、押した結果はSupabase/Steam認証まで進む——正式
	## Steam AppID未発行の間は必ず失敗し(steam_unavailable/not_configured
	## 等)、成功扱いにならない(ユーザー確定仕様)。
	_online_status_label = Label.new()
	_online_status_label.name = "OnlinePublishStatusLabel"
	bottom_bar.add_child(_online_status_label)

	_publish_online_button = Button.new()
	_publish_online_button.name = "PublishOnlineButton"
	_publish_online_button.text = "オンライン公開"
	_publish_online_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_publish_online_button.pressed.connect(_on_publish_online_pressed)
	bottom_bar.add_child(_publish_online_button)

	_build_persistent_controls()

## GUT専用: 実Steam/実Supabaseへ触れないfakeへ差し替える。
func set_boss_publisher_for_testing(publisher: RBMBossPublisher) -> void:
	_boss_publisher = publisher

func _ensure_boss_publisher() -> void:
	if _boss_publisher == null:
		_boss_publisher = RBMBossPublisher.new()
		add_child(_boss_publisher)

func _on_publish_online_pressed() -> void:
	_ensure_boss_publisher()
	if _boss_publisher.current_state() == RBMBossPublisher.PublishState.REQUESTING_TICKET or \
			_boss_publisher.current_state() == RBMBossPublisher.PublishState.UPLOADING:
		return
	_online_status_label.text = "公開中..."
	var ok: bool = await _boss_publisher.publish(draft)
	if ok:
		_online_status_label.text = "オンライン公開に成功しました。"
	else:
		_online_status_label.text = _online_publish_failure_message(_boss_publisher.last_error_kind(), _boss_publisher.last_error_message())

## §4C-7: 公開中/公開成功/認証失敗/通信失敗/validation失敗/Steam利用不可/
## 正式Steam認証未設定を、ユーザーへ分かる形で表示する。大規模なUI再設計
## はしない——既存の1行ラベルへ短い日本語文を出すだけ。
func _online_publish_failure_message(error_kind: String, detail: String) -> String:
	match error_kind:
		"clear_check_not_valid":
			return "クリアチェックを再確認してください。"
		"steam_unavailable":
			return "Steamが利用できません。Steamを起動してログインしてください。"
		"steam_not_logged_on":
			return "Steamにログインしていません。"
		"steam_ticket_request_failed", "steam_ticket_failed":
			return "Steam認証チケットの取得に失敗しました。"
		"not_configured":
			return "オンライン公開はまだ準備中です（正式Steam認証の設定待ち）。"
		"forbidden":
			return "この投稿を更新する権限がありません。"
		"not_found":
			return "投稿先が見つかりませんでした。"
		"network_error", "http_5xx":
			return "通信に失敗しました。しばらくしてからもう一度お試しください。"
		"http_4xx", "invalid_payload", "payload_too_large":
			return "送信内容に問題がありました。"
		_:
			return "オンライン公開に失敗しました（%s）。" % (error_kind if detail.is_empty() else detail)

## §6/§13相当: STEP1〜4が既に使っているRBMCreatorUiKit.build_section_title()
## （本文より一段大きく、左に小さな銀アクセント）をこの画面でも再利用する
## ——_steps_root.theme経由でこのSTEPも同じCreator本体UIパレットの
## カスケードを受けているため、見た目は他のSTEPと自然に統一される。
func _section_title(text: String) -> Control:
	return RBMCreatorUiKit.build_section_title(text)

func _add_label(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

# ---------------------------------------------------------------------------
# 「作成内容」— §20/§21: STEP1〜4それぞれ、名前＋[編集]のみ。
# ---------------------------------------------------------------------------

func _build_creation_content_section() -> void:
	var section := VBoxContainer.new()
	section.name = "CreationContentSection"
	_content.add_child(section)
	section.add_child(_section_title("作成内容"))
	for i in range(RBMCreatorMain.STEP_COUNT - 1):
		var row := HBoxContainer.new()
		row.name = "CreationStepRow_%d" % (i + 1)
		section.add_child(row)
		var name_label := Label.new()
		name_label.name = "CreationStepNameLabel_%d" % (i + 1)
		name_label.text = str(RBMCreatorMain.STEP_NAMES[i])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var edit_button := Button.new()
		edit_button.name = "EditStepButton_%d" % (i + 1)
		edit_button.text = "編集"
		edit_button.pressed.connect(func(): main.edit_step(i + 1))
		row.add_child(edit_button)

# ---------------------------------------------------------------------------
# 「動作確認」— §19: 任意のTEST BATTLE。
# ---------------------------------------------------------------------------

func _build_test_battle_section() -> void:
	var section := VBoxContainer.new()
	section.name = "TestBattleSection"
	_content.add_child(section)
	section.add_child(_section_title("動作確認"))
	_move_into(_test_battle_button, section)

# ---------------------------------------------------------------------------
# 「CLEAR CHECK」— §19/§4: 未達成/達成済みの状態表示＋専用の開始ボタン
# （保存/公開のボタン列とは独立したセクション）。
# ---------------------------------------------------------------------------

func _build_clear_check_section() -> void:
	var section := VBoxContainer.new()
	section.name = "ClearCheckSection"
	_content.add_child(section)
	section.add_child(_section_title("CLEAR CHECK"))
	## §4: draft.is_clear_check_currently_valid()は都度再導出されるライブ値
	## （キャッシュしない）——編集で無効化→元の内容へ戻せば自動的に「達成済み」
	## 表示へ戻る既存契約（§17）をそのまま維持する。
	_clear_check_status_label.text = "達成済み" if draft.is_clear_check_currently_valid() else "未達成"
	_move_into(_clear_check_status_label, section)
	_move_into(_clear_check_button, section)

func refresh() -> void:
	_refresh_background_selector()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	_build_creation_content_section()
	_content.add_child(HSeparator.new())
	_build_challenge_settings_section()
	_content.add_child(HSeparator.new())
	_build_test_battle_section()
	_content.add_child(HSeparator.new())
	_build_clear_check_section()

	_publish_button.disabled = not draft.is_clear_check_currently_valid()
	_publish_button.visible = not draft.is_published()
	_unpublish_button.visible = draft.is_published()
	_publish_status_label.text = "公開中" if draft.is_published() else "未公開"

	# Phase 4C-1: オンライン公開もローカル公開と同じClear Checkゲートを使う
	# (RBMOnlineBossPayload.build_for_publish()が実際の判定を行う——ここは
	# ボタンのdisabled表示だけの重複、ゲート自体は1箇所にしかない)。
	_publish_online_button.disabled = not draft.is_clear_check_currently_valid()
	if _online_status_label.text.is_empty():
		_online_status_label.text = "オンライン未公開"

# ---------------------------------------------------------------------------
# 「挑戦設定」— Phase 1 Step 7 §11〜§20/§39〜§42（既存、無改修のまま
# このSTEPへ引き継ぐ）: CHALLENGE向けの作者メッセージ・情報公開設定。
# ---------------------------------------------------------------------------

func _build_challenge_settings_section() -> void:
	var section := VBoxContainer.new()
	section.name = "ChallengeSettingsSection"
	_content.add_child(section)
	section.add_child(_section_title("挑戦設定"))

	var notes_label := Label.new()
	notes_label.text = "作者メッセージ（挑戦確認画面に表示されます）"
	section.add_child(notes_label)

	_author_notes_edit = TextEdit.new()
	_author_notes_edit.name = "AuthorNotesEdit"
	_author_notes_edit.text = draft.author_notes
	_author_notes_edit.custom_minimum_size = Vector2(0, 80)
	_author_notes_edit.text_changed.connect(_on_author_notes_text_changed)
	section.add_child(_author_notes_edit)

	_author_notes_count_label = Label.new()
	_author_notes_count_label.name = "AuthorNotesCountLabel"
	section.add_child(_author_notes_count_label)
	_update_author_notes_count_label()

	var visibility_header := Label.new()
	visibility_header.text = "情報公開設定（挑戦確認画面での表示/非表示）"
	section.add_child(visibility_header)

	var bulk_row := HBoxContainer.new()
	section.add_child(bulk_row)
	var show_all_button := Button.new()
	show_all_button.name = "ShowAllVisibilityButton"
	show_all_button.text = "すべて公開"
	show_all_button.pressed.connect(_on_show_all_visibility_pressed)
	bulk_row.add_child(show_all_button)
	var hide_all_button := Button.new()
	hide_all_button.name = "HideAllVisibilityButton"
	hide_all_button.text = "すべて非公開"
	hide_all_button.pressed.connect(_on_hide_all_visibility_pressed)
	bulk_row.add_child(hide_all_button)

	_visibility_checkboxes.clear()
	for key in RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS:
		var checkbox := CheckBox.new()
		checkbox.name = "VisibilityCheckBox_%s" % key
		checkbox.text = str(VISIBILITY_LABELS.get(key, key))
		checkbox.button_pressed = draft.is_challenge_info_visible(key)
		checkbox.toggled.connect(_on_visibility_toggled.bind(key))
		section.add_child(checkbox)
		_visibility_checkboxes[key] = checkbox

func _on_author_notes_text_changed() -> void:
	if _author_notes_edit.text.length() > RBMCreatorDraft.MAX_AUTHOR_NOTES_LENGTH:
		_author_notes_edit.text = _author_notes_edit.text.left(RBMCreatorDraft.MAX_AUTHOR_NOTES_LENGTH)
		var last_line := _author_notes_edit.get_line_count() - 1
		_author_notes_edit.set_caret_line(last_line)
		_author_notes_edit.set_caret_column(_author_notes_edit.get_line(last_line).length())
	draft.set_author_notes(_author_notes_edit.text)
	_update_author_notes_count_label()

func _update_author_notes_count_label() -> void:
	_author_notes_count_label.text = "%d / %d 文字" % [draft.author_notes.length(), RBMCreatorDraft.MAX_AUTHOR_NOTES_LENGTH]

func _on_visibility_toggled(pressed: bool, key: String) -> void:
	draft.set_challenge_info_visible(key, pressed)

func _on_show_all_visibility_pressed() -> void:
	draft.set_all_challenge_info_visible(true)
	_sync_visibility_checkboxes()

func _on_hide_all_visibility_pressed() -> void:
	draft.set_all_challenge_info_visible(false)
	_sync_visibility_checkboxes()

func _sync_visibility_checkboxes() -> void:
	for key in _visibility_checkboxes.keys():
		var checkbox: CheckBox = _visibility_checkboxes[key]
		checkbox.button_pressed = draft.is_challenge_info_visible(key)

func is_step_valid() -> bool:
	return true

func validation_message() -> String:
	return ""

func _refresh_background_selector() -> void:
	var bottom: HBoxContainer = find_child("SummaryBottomBar",true,false)
	if bottom == null: return
	bottom.add_theme_constant_override("separation",16)
	var row := bottom.get_node_or_null("BackgroundTimeSelector")
	if row == null:
		row = HBoxContainer.new()
		row.name = "BackgroundTimeSelector"
		row.add_theme_constant_override("separation",8)
		bottom.add_child(row)
		bottom.move_child(row,2)
		var caption := Label.new()
		caption.text = "戦闘背景"
		row.add_child(caption)
		for value in ["day","night"]:
			var button := Button.new()
			button.name = "DayBackgroundButton" if value == "day" else "NightBackgroundButton"
			button.text = "昼" if value == "day" else "夜"
			button.toggle_mode = true
			button.custom_minimum_size = Vector2(76,44)
			button.pressed.connect(func():
				draft.battle_background = value
				_refresh_background_selector()
			)
			row.add_child(button)
	row.get_node("DayBackgroundButton").set_pressed_no_signal(draft.battle_background == "day")
	row.get_node("NightBackgroundButton").set_pressed_no_signal(draft.battle_background == "night")
