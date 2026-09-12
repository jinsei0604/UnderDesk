class_name RBMCreatorMain
extends Control

## Phase 1 Step 4 — SIMPLE Creator root: STEP1〜7のステップ式ナビゲーション、
## §7-3の「最終確認へ戻る」表示条件、外見選択ページ、TEST BATTLEへの遷移を統括
## する。各STEPの実データ・検証ロジックはRBMCreatorDraft、TEST BATTLE/REWINDの
## 実ロジックはRBMCreatorTestSessionにあり、このクラス自身はナビゲーション状態
## （どのSTEPを表示中か、最終確認に到達済みか）だけを持つ（§17: 過剰な抽象化は
## しないが、責務は分離する）。

## Creator UI改修（STEP4統合+最終確認再設計、2026-09-05）§3/§13/§17/§18:
## 6 STEP→5 STEPへ再統合した——旧STEP5「使用可能スキル」を独立STEPとして
## 廃止し、そのロジック（draft.is_ally_skill_allowed()/set_ally_skill_allowed()/
## set_all_ally_skills_allowed()——いずれも無改修）を新STEP4「攻略パーティ」
## の「選択キャラクター設定」タブ内へ統合した。
## 新旧対応: 旧1外見と基本情報→新1、旧2能力→新2、旧3行動→新3、
## 旧4攻略パーティ→新4（使用可能スキルタブを統合）、旧5使用可能スキル→
## 廃止（統合先は新4）、旧6最終確認→新5。
##
## 注記: 各STEPビューのクラス名/ファイル名（RBMCreatorStep4/Step5Party/
## Step6PartySkills/Step7Summary等）は歴史的な名残として変更していない
## （Godotのグローバルclass_name登録・.uidの不要な churn を避けるため、
## §3で明示された既存方針をそのまま踏襲）——実際に何STEP目として振る舞うか
## は、下のstep_scripts配列内の並び順だけで決まる。RBMCreatorStep6PartySkills
## 自体は今後どのstep_scriptsにも含まれない（class_name自体は削除しない、
## 内部ロジックはRBMCreatorStep5Partyが直接draftのAPIを呼ぶ形で引き継いだ）。
const STEP_COUNT := 5

## Creator本体UI刷新（2026-09-04）§3、Creator UI改修（2026-09-05）§13/§17:
## 共通ヘッダーの右側「現在の工程名」。STEP_COUNT・step_scripts（_build_ui()
## 参照）と同じ並び順。STEP1〜4は共通フレーム（左STEPナビ＋中央＋右BOSS
## PROFILE）を持ち、STEP5（最終確認）のみ例外的にフレームを持たない
## （_refresh()/_build_ui()の_step_frame参照）。工程を追加/削除/統合したら
## この配列もSTEP_COUNTと同じ長さへ更新すること。
const STEP_NAMES := [
	"外見と基本情報", "能力", "行動", "攻略パーティ", "最終確認",
]

## Phase 1 Step 6 — 保存・再編集（§45/§46: 保存I/O自体はRBMLocalStageRepository
## 側の責務。ここは「どのstageを編集中か」「未保存変更があるか」というCreator
## セッション状態の統括のみを持つ）。

signal exited  ## §36: 未保存確認を解決した（または元々不要だった）後の、
                ## Creator画面自体からの実際の退出。RBMCreatorEntryが購読する。

## 実機プレイ改善③ item4: 保存成功画面の「クリエイター一覧に戻る」専用の
## 退出シグナル。既存のexitedとは意図的に別物——exitedはpress_exit_creator()
## の未保存変更確認フローを経由してCREATE TOP画面（_show_top()）へ戻るが、
## こちらは保存成功直後（既に未保存変更なし）から、確認フローを経由せず
## 保存済みボス一覧（_show_list()）へ直接戻るためだけに使う。
signal exited_to_saved_list

var _world_ui = preload("res://src/bossmaker/rbm_world_ui.gd").new()

var draft: RBMCreatorDraft = RBMCreatorDraft.new()
var current_step: int = 1
var has_reached_summary: bool = false

## §23/§30: 新規未保存なら空文字列。§34: ロードした保存済みstageのidを持つ。
var current_stage_id: String = ""

## §14/§19: 「最後に保存した」または「新規Creator起動直後」のfull_authoring_snapshot()。
## has_unsaved_changes()はこれと現在のdraftを比較するだけの、単一の比較ロジック
## （dirty flagではない、A→B→Aで自動的にfalseへ戻る、§19）。
var _reference_authoring_snapshot: Dictionary = {}

## Creator本体UI刷新（2026-09-04）§3: STEP1〜6専用の共通ヘッダー
## （左：ボス作成｜現在の工程名、右：STEP n / 総数）。root_column直下、
## _steps_rootより前に置く——実際のスタイリング/構築はRBMCreatorUiKit.
## HeaderBarへ集約し、ここでは_refresh()で.textを更新するだけ。
var _header: RBMCreatorUiKit.HeaderBar
var _steps_root: Control
## Creator UI改修（2026-09-05）§4/§13: STEP1〜4共通フレーム一式。STEP5
## （最終確認）表示中は_step_nav_column/_boss_profile_panelを非表示にする
## だけで、HBoxContainerが自動的に_step_content_areaへ全幅を明け渡す
## （_refresh()参照）。
var _step_frame: HBoxContainer
var _step_nav_column: RBMCreatorUiKit.StepNavColumn
var _step_content_area: Control
var _boss_profile_panel: RBMCreatorUiKit.BossProfilePanel
var _step_views: Array = []  # index i -> STEP (i+1)'s view
var _status_label: Label
## 実機プレイ改善③ item3/5/6: STEP1-7専用の「戻る/最終確認へ戻る/次へ」を
## 持つ行。_show_only()内で_steps_root表示中だけ表示するよう切り替える
## （下記参照）——TEST BATTLE/CLEAR CHECK/保存/外見選択のいずれの画面でも
## 意味を持たないため。
var _nav_row: HBoxContainer
var _back_button: Button
var _next_button: Button
var _return_to_summary_button: Button

var _exit_button: Button
var _exit_confirm_panel: PanelContainer

var _appearance_picker: RBMCreatorAppearancePicker
var _test_battle_view: RBMCreatorTestBattleView
var _clear_check_view: RBMCreatorClearCheckView
var _save_view: RBMCreatorSaveView

func _ready() -> void:
	_build_ui()
	_reference_authoring_snapshot = draft.full_authoring_snapshot()
	_refresh()

func _build_ui() -> void:
	var root_column := VBoxContainer.new()
	## Step 8 最終修正 §1: このControl(RBMCreatorMain)自身へrootとして加えた
	## VBoxContainerに実際のサイズが割り当てられていなかった（bareなControlは
	## 子のminimum sizeを自動で親へ伝播せず、自分自身も親の矩形を自動で
	## 埋めない）ため、SIZE_EXPAND_FILLを持つ_steps_root以下のレイアウトが
	## 常にほぼ0サイズのまま計算され、STEP内容とnav_row/exit_row等が同じ位置
	## に重なって描画されていた。root_columnをRBMCreatorMain自身の矩形いっぱい
	## に固定するだけで、以下の子要素の並び・機能・Draft反映ロジックには
	## 一切触れずにこの重なりを解消できる。
	root_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_column)

	## Creator本体UI刷新（2026-09-04）§3: 共通ヘッダーはSTEP1〜6のどの工程
	## でも同じ位置（root_columnの最上段）に固定表示する。_status_label/
	## _steps_root/_nav_row/exit_rowの既存の縦積み順自体は変更せず、その
	## 先頭へ追加するだけ——既存の各画面の相対位置関係（STEP内容が戻る/
	## 次への上に来る等、Step 8のレイアウト回帰テストが検証する順序）には
	## 影響しない。
	_header = RBMCreatorUiKit.HeaderBar.new()
	_header.name = "CreatorHeaderBar"
	root_column.add_child(_header)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	root_column.add_child(_status_label)

	_steps_root = Control.new()
	_steps_root.name = "StepsRoot"
	_steps_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	## Creator本体UI刷新（2026-09-04）§2/§13: STEP1〜6専用の共通デザイン
	## システム（濃紺/青灰色/銀、金は使用しない）を、_steps_root（STEP1〜6
	## の6ビューだけが属するControl）へのみ適用する——TEST BATTLE/Clear
	## Check/保存/外見選択ピッカーは_steps_rootの外側（root_columnの兄弟）
	## のため、引き続き既存のRBMUiTheme（RBMCreatorEntry.theme経由の
	## カスケード）を使い続ける。詳細はRBMCreatorUiKitのクラス冒頭コメント
	## 参照。
	_steps_root.theme = RBMCreatorUiKit.build_theme()
	root_column.add_child(_steps_root)

	## Creator UI改修（2026-09-05）§4/§6/§7/§8: STEP1〜4共通フレーム
	## （左STEPナビ＋中央ワークスペース＋右BOSS PROFILE）。STEP5（最終確認）
	## だけはこのフレーム自体を使わない明示的な例外——_refresh()が
	## _step_nav_column/_boss_profile_panelのvisibleをcurrent_step==
	## STEP_COUNTで切り替えるだけで、HBoxContainerが非表示の子を自動的に
	## レイアウトから除外するため、_step_content_areaはSTEP5の時だけ
	## 追加コード無しでウィンドウ幅いっぱいに広がる（STEP1〜4の各ビュー自身
	## の内部構成・validation・draft読み書きには一切触れていない）。
	_step_frame = HBoxContainer.new()
	_step_frame.name = "StepFrame"
	_step_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_steps_root.add_child(_step_frame)

	_step_nav_column = RBMCreatorUiKit.StepNavColumn.new()
	_step_frame.add_child(_step_nav_column)
	var translated_step_names: Array = []
	for step_name in STEP_NAMES.slice(0, 4):
		translated_step_names.append(tr(step_name))
	_step_nav_column.setup(translated_step_names, go_to_step)

	_step_content_area = Control.new()
	_step_content_area.name = "StepContentArea"
	_step_content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_frame.add_child(_step_content_area)

	_boss_profile_panel = RBMCreatorUiKit.BossProfilePanel.new()
	_step_frame.add_child(_boss_profile_panel)

	var step_scripts: Array = [
		RBMCreatorStep1Basic, RBMCreatorStep2Stats,
		RBMCreatorStep4, RBMCreatorStep5Party,
		RBMCreatorStep7Summary,
	]
	for i in range(step_scripts.size()):
		var view = step_scripts[i].new()
		view.name = "Step%d" % (i + 1)
		## §1: 各STEPビュー自身もbareなControlのため、親へ加えただけでは
		## 親の矩形いっぱいには広がらない——STEP5のScrollContainer
		## (SIZE_EXPAND_FILL)のような内部要素が実際の表示領域を得られる
		## よう、表示中のSTEPビュー自身を親の矩形いっぱいに固定する。
		## STEP自身の内部構成（VBoxContainerで縦に積むだけの既存パターン）
		## は変更しない。最終確認(STEP_COUNT)は_step_content_area経由でも
		## nav/profileが非表示になった結果ウィンドウ幅いっぱいの領域を
		## 得るため、フルスクリーン専用の別parentは不要——親をこの1種類に
		## 統一する。
		view.set_anchors_preset(Control.PRESET_FULL_RECT)
		_step_content_area.add_child(view)
		view.setup(draft, self)
		_step_views.append(view)

	## Creator本体UI刷新（2026-09-04）§10: 下部ナビゲーション（戻る/最終確認
	## へ戻る/次へ）はroot_column直下（_steps_rootの外側）に位置するため、
	## _steps_root.themeのカスケードが届かない——RBMCreatorUiKit.style_*関数
	## で個別にStyleBox/文字色を上書きする。「戻る」「最終確認へ戻る」は
	## 副操作として控えめな配色、「次へ」は主要操作としてわずかに強い銀/
	## 青銀の枠・背景（金は使用しない）。無効時（_back_button.disabled等）
	## はテーマのdisabledステートがそのまま視覚的な区別を担う。
	_nav_row = HBoxContainer.new()
	_nav_row.name = "StepNavRow"
	root_column.add_child(_nav_row)
	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = tr("戻る")
	RBMCreatorUiKit.style_secondary_button(_back_button)
	_back_button.pressed.connect(press_back)
	_nav_row.add_child(_back_button)
	_return_to_summary_button = Button.new()
	_return_to_summary_button.name = "ReturnToSummaryButton"
	_return_to_summary_button.text = tr("最終確認へ戻る")
	RBMCreatorUiKit.style_secondary_button(_return_to_summary_button)
	_return_to_summary_button.pressed.connect(press_return_to_summary)
	_nav_row.add_child(_return_to_summary_button)
	_next_button = Button.new()
	_next_button.name = "NextButton"
	_next_button.text = tr("次へ")
	RBMCreatorUiKit.style_primary_nav_button(_next_button)
	_next_button.pressed.connect(press_next)
	_nav_row.add_child(_next_button)

	## §29/§36: Creator画面自体からの退出導線。STEP1-7のナビゲーション文脈
	## (_steps_root表示中)でのみ表示する——TEST BATTLE/CLEAR CHECK/保存の
	## サブ画面からの「Creatorに戻る」は各ビュー自身の既存の戻る導線が担い、
	## ここでは扱わない（§_show_only参照）。
	##
	## Creator本体UIコンセプト確定パス（2026-09-05）§1: このボタン/ダイアログ
	## も_steps_rootの外側（root_columnの兄弟）にあるため_steps_root.theme
	## のカスケードが届かず、旧RBMUiTheme（暖色の銅アクセント）のまま残って
	## いた——上の_nav_row（戻る/最終確認へ戻る/次へ）と同じ理由・同じ対処
	## （RBMCreatorUiKit.style_*関数で個別上書き）で統一する。処理・確認
	## フロー自体は無改修。
	var exit_row := HBoxContainer.new()
	root_column.add_child(exit_row)
	_exit_button = Button.new()
	_exit_button.name = "ExitCreatorButton"
	_exit_button.text = tr("Creator一覧へ戻る")
	RBMCreatorUiKit.style_secondary_button(_exit_button)
	_exit_button.pressed.connect(press_exit_creator)
	exit_row.add_child(_exit_button)

	_exit_confirm_panel = PanelContainer.new()
	_exit_confirm_panel.name = "ExitConfirmPanel"
	_exit_confirm_panel.visible = false
	## §1: 未保存確認ダイアログは、他STEPの「ボス名」「外見」等のカードと
	## 同じPanelContainer（_steps_root.themeが定義するpanelスタイルはこの
	## Control自体には届かないため、カード同様のStyleBoxFlatを個別付与）で
	## 囲み、地の濃紺へ直接テキストが浮くだけの見た目から、Creator本体の
	## 他パネルと同じ「囲まれたカード」に統一する——確認内容・ボタン構成は
	## 無改修。
	_exit_confirm_panel.add_theme_stylebox_override("panel", RBMCreatorUiKit.panel_box())
	root_column.add_child(_exit_confirm_panel)
	var exit_confirm_column := VBoxContainer.new()
	exit_confirm_column.name = "ExitConfirmColumn"
	exit_confirm_column.add_theme_constant_override("separation", 12)
	_exit_confirm_panel.add_child(exit_confirm_column)
	var exit_confirm_label := Label.new()
	exit_confirm_label.name = "ExitConfirmLabel"
	exit_confirm_label.text = tr("変更内容が保存されていません。\n保存せず終了すると変更内容は失われます。")
	exit_confirm_label.add_theme_color_override("font_color", RBMCreatorUiKit.COLOR_TEXT_PRIMARY)
	exit_confirm_column.add_child(exit_confirm_label)
	var exit_confirm_row := HBoxContainer.new()
	exit_confirm_row.add_theme_constant_override("separation", 10)
	exit_confirm_column.add_child(exit_confirm_row)
	var exit_confirm_save_button := Button.new()
	exit_confirm_save_button.name = "ExitConfirmSaveButton"
	exit_confirm_save_button.text = tr("保存する")
	RBMCreatorUiKit.style_primary_nav_button(exit_confirm_save_button)
	exit_confirm_save_button.pressed.connect(_on_exit_confirm_save_pressed)
	exit_confirm_row.add_child(exit_confirm_save_button)
	var exit_confirm_discard_button := Button.new()
	exit_confirm_discard_button.name = "ExitConfirmDiscardButton"
	exit_confirm_discard_button.text = tr("保存せず終了")
	RBMCreatorUiKit.style_secondary_button(exit_confirm_discard_button)
	exit_confirm_discard_button.pressed.connect(_on_exit_confirm_discard_pressed)
	exit_confirm_row.add_child(exit_confirm_discard_button)
	var exit_confirm_cancel_button := Button.new()
	exit_confirm_cancel_button.name = "ExitConfirmCancelButton"
	exit_confirm_cancel_button.text = tr("キャンセル")
	RBMCreatorUiKit.style_secondary_button(exit_confirm_cancel_button)
	exit_confirm_cancel_button.pressed.connect(_on_exit_confirm_cancel_pressed)
	exit_confirm_row.add_child(exit_confirm_cancel_button)

	_appearance_picker = RBMCreatorAppearancePicker.new()
	_appearance_picker.name = "AppearancePicker"
	_appearance_picker.visible = false
	_appearance_picker.confirmed.connect(_on_appearance_confirmed)
	_appearance_picker.cancelled.connect(_on_appearance_cancelled)
	root_column.add_child(_appearance_picker)

	_test_battle_view = RBMCreatorTestBattleView.new()
	_test_battle_view.name = "TestBattleView"
	_test_battle_view.visible = false
	_test_battle_view.setup(self)
	_test_battle_view.return_to_creator_requested.connect(_on_test_battle_return_to_creator)
	root_column.add_child(_test_battle_view)

	_clear_check_view = RBMCreatorClearCheckView.new()
	_clear_check_view.name = "ClearCheckView"
	_clear_check_view.visible = false
	_clear_check_view.setup(self)
	_clear_check_view.return_to_creator_requested.connect(_on_clear_check_return_to_creator)
	root_column.add_child(_clear_check_view)

	_save_view = RBMCreatorSaveView.new()
	_save_view.name = "SaveView"
	_save_view.visible = false
	_save_view.setup(self)
	_save_view.return_to_creator_requested.connect(_on_save_return_to_creator)
	_save_view.return_to_creator_list_requested.connect(_on_save_return_to_creator_list)
	root_column.add_child(_save_view)

# ---------------------------------------------------------------------------
# navigation
# ---------------------------------------------------------------------------

func _current_view() -> Node:
	return _step_views[current_step - 1]

func go_to_step(step: int) -> void:
	if step < 1 or step > STEP_COUNT:
		return
	current_step = step
	_refresh()

## §7-1: STEP 7's per-section "編集" buttons all call this.
func edit_step(step: int) -> void:
	go_to_step(step)

## §7-2: a simple linear advance -- editing from STEP N and pressing "次へ"
## always goes to STEP N+1, never forced back to STEP 7, regardless of
## whether STEP 7 was already reached.
func press_next() -> bool:
	if not _current_view().is_step_valid():
		return false
	if current_step >= STEP_COUNT:
		return false
	current_step += 1
	if current_step == STEP_COUNT:
		has_reached_summary = true
	_refresh()
	return true

func press_back() -> void:
	if current_step <= 1:
		return
	current_step -= 1
	_refresh()

## §7-3: only usable once STEP 7 has been reached at least once.
func press_return_to_summary() -> bool:
	if not has_reached_summary:
		return false
	current_step = STEP_COUNT
	_refresh()
	return true

# ---------------------------------------------------------------------------
# appearance picker (§1-3)
# ---------------------------------------------------------------------------

func open_appearance_picker() -> void:
	_appearance_picker.open(draft.appearance_id)
	_show_only(_appearance_picker)

func _on_appearance_confirmed(appearance_id: String) -> void:
	draft.appearance_id = appearance_id
	_show_only(_steps_root)
	_refresh()

func _on_appearance_cancelled() -> void:
	_show_only(_steps_root)

# ---------------------------------------------------------------------------
# STEP 6 needs to know when STEP 5's party changes; STEP 3/STEP 7 need to
# know when skills change -- both simply trigger a full refresh, since every
# step view reads straight from the shared `draft` (no per-step caching to
# invalidate beyond the visible Controls themselves).
#
## Creator UI再設計後: on_skills_changed()は「新STEP3(行動)のどこか
## （通常行動/指定行動/ADVANCED行動パターン）でスキルが作成/更新/削除
## された」たびに呼ばれる（旧・専用の「ボススキル作成」STEP3からの通知、
## という意味は無くなったが、フック自体・呼び出し契約は変えていない）。
# ---------------------------------------------------------------------------

func on_party_changed() -> void:
	_refresh()

func on_skills_changed() -> void:
	_refresh()

# ---------------------------------------------------------------------------
# TEST BATTLE (§8/§12)
# ---------------------------------------------------------------------------

## §12: always validates via RBMDefinitionLoader before ever constructing a
## battle. Returns {"ok":true} on success (and switches to the TEST BATTLE
## view), or {"ok":false,"errors":[...]} on failure (stays on STEP 7, no
## battle is ever constructed) — the raw validation-error strings are exposed
## for the caller to translate into a readable message (§12: "内部validation
## 文字列をそのまま露出する必要はありませんが、原因を特定できること").
func press_test_battle() -> Dictionary:
	var definition := draft.to_definition()
	var resolved := RBMDefinitionLoader.resolve(definition)
	if not bool(resolved.get("ok", false)):
		# 実機プレイ改善③ item8/11: "TEST BATTLE"混在表記を統一して日本語化
		# （STEP7の「テストバトル」ボタンと表記を揃える）。
		_status_label.text = tr("テストバトルを開始できません（設定を確認してください）")
		return resolved
	_test_battle_view.start(definition)
	_show_only(_test_battle_view)
	return {"ok": true}

func _on_test_battle_return_to_creator() -> void:
	_show_only(_steps_root)
	go_to_step(STEP_COUNT)

# ---------------------------------------------------------------------------
# CLEAR CHECK (Phase 1 Step 5, §4/§5)
# ---------------------------------------------------------------------------

## §4/§5: opens the Clear Check confirmation screen. No Definition is
## generated/validated at this point yet — that only happens when the
## confirm screen's own "開始" is pressed (press_clear_check_start()).
func press_clear_check() -> void:
	_clear_check_view.open(draft)
	_show_only(_clear_check_view)

## §5「開始」: always validates via RBMDefinitionLoader before ever
## constructing a battle (mirrors press_test_battle() exactly, §12 applied to
## Clear Check). Returns {"ok":true} and actually starts the Clear Check
## battle on success, or {"ok":false,"errors":[...]} on failure (stays on the
## confirm screen, no battle/session is ever constructed). rng_seed is
## test-only plumbing (default -1 = random, matching
## RBMCreatorClearCheckView.start_battle()'s own default) — normal Creator
## usage never passes one.
func press_clear_check_start(rng_seed: int = -1) -> Dictionary:
	var definition := draft.to_definition()
	var resolved := RBMDefinitionLoader.resolve(definition)
	if not bool(resolved.get("ok", false)):
		return resolved
	_clear_check_view.start_battle(definition, rng_seed)
	return {"ok": true}

## §11/§14/§15: mid-battle abort, victory, and defeat's own "Creatorに戻る"
## all funnel through here — Draft (including any Clear Check success
## record) is untouched by navigation alone.
func _on_clear_check_return_to_creator() -> void:
	_show_only(_steps_root)
	go_to_step(STEP_COUNT)

# ---------------------------------------------------------------------------
# 保存 (Phase 1 Step 6, §23/§24/§25/§26/§38/§39/§40)
# ---------------------------------------------------------------------------

## §38/§39: STEP 7の「保存」ボタンから呼ばれる。実際の書き込みはまだ行わず、
## RBMCreatorSaveViewが新規/既存の別で異なるボタン構成を表示する。
func press_save() -> void:
	_save_view.open()
	_show_only(_save_view)

## §23/§25: 新規stageの初回保存、および既存stageを開いている場合の
## 「新しいボスとして保存」——どちらもRepository視点では同一操作（新しい
## stage_idを発行し、既存ファイルには一切触れない）。成功したら
## current_stage_idを新しいidへ切り替え、未保存変更判定の基準snapshotを
## 更新する。
func press_save_as_new() -> Dictionary:
	var result := RBMLocalStageRepository.save_new(draft)
	if bool(result.get("ok", false)):
		current_stage_id = str(result.get("stage_id", ""))
		_reference_authoring_snapshot = draft.full_authoring_snapshot()
	return result

## §24: 上書き保存。current_stage_idが空（新規未保存stage）の場合は失敗を返す
## ——RBMCreatorSaveView.open()がボタンの出し分けで到達しないようにしている
## が、直接呼ばれた場合の防御でもある。
func press_overwrite_save() -> Dictionary:
	if current_stage_id.is_empty():
		return {"ok": false, "error": "no_current_stage"}
	var result := RBMLocalStageRepository.overwrite(current_stage_id, draft)
	if bool(result.get("ok", false)):
		_reference_authoring_snapshot = draft.full_authoring_snapshot()
	return result

## §26: 新規保存/新しいボスとして保存の直前にRBMCreatorSaveViewが呼ぶ同名
## 警告用チェック。上書き保存では呼ばれない（自分自身と同名なのは当然の
## ため警告不要、§26末尾）。
func boss_name_already_saved_elsewhere() -> bool:
	return RBMLocalStageRepository.boss_name_exists(draft.boss_name)

# ---------------------------------------------------------------------------
# 公開 (Creator UI改修§24〜§27、ユーザー確定仕様)
# ---------------------------------------------------------------------------

## 公開は「他プレイヤーから挑戦できる状態にする」実効を持つ操作——
## CHALLENGE側(RBMLocalStageRepository.list()を参照するrbm_challenge_entry.gd)
## は保存ファイル上のpublishedフィールドだけを見るため、この操作自体が
## 必ずディスクへの保存を伴う（未保存のClear Check達成のみの状態から直接
## 公開した場合はここで新規保存、既存stageなら上書き保存）。保存に失敗
## した場合はdraft.published自体も取り消す——メモリ上は公開済みなのに
## ディスク上は反映されていない、という不整合を残さないため。
func press_publish() -> Dictionary:
	if not draft.publish():
		return {"ok": false, "error": "clear_check_not_valid"}
	var result := press_overwrite_save() if not current_stage_id.is_empty() else press_save_as_new()
	if not bool(result.get("ok", false)):
		draft.unpublish()
	_refresh()
	return result

## 公開取り下げ——Clear Check達成状態自体には触れない（ユーザー確定仕様）。
## 取り下げも同様にディスクへ即座に反映する（未保存の場合は取り下げる対象
## 自体が存在しないため、current_stage_idが空なら何もしない）。
func press_unpublish() -> Dictionary:
	if current_stage_id.is_empty():
		return {"ok": false, "error": "no_current_stage"}
	draft.unpublish()
	var result := press_overwrite_save()
	_refresh()
	return result

func _on_save_return_to_creator() -> void:
	_show_only(_steps_root)
	go_to_step(STEP_COUNT)

## 実機プレイ改善③ item4: 保存成功画面の「クリエイター一覧に戻る」専用の
## ハンドラ。STEP7へは一切戻さず、exited_to_saved_listをそのまま外側
## （RBMCreatorEntry）へ伝播するだけ——保存済みボス一覧の実際の表示・
## 再取得はRBMCreatorEntry._show_list()（既存、無改修）に委ねる。
func _on_save_return_to_creator_list() -> void:
	exited_to_saved_list.emit()

# ---------------------------------------------------------------------------
# Creator入口からの開始 (Phase 1 Step 6, §29/§30/§31/§34/§35)
# ---------------------------------------------------------------------------
##
## draftオブジェクトの「参照」自体は差し替えない——STEP1-7の各ビューは
## setup()時に受け取ったdraft参照を自分で保持しているため（RBMCreatorMain自身
## の既存ヘッダコメント「各STEPビューはそこへ直接読み書きする」）、参照を
## 差し替えるとビュー側の参照が古いままになりUI二重構築のリスクも生む。
## 代わりに既存のdraftオブジェクトの「フィールド」だけをrestore_from_saved_dict()
## /restore_clear_check_snapshot()で書き換える。

## §29/§30: まっさらな新規Draftとして開始する。current_stage_idは空、
## 参照snapshotは初期状態そのもの——A→B→Aで未保存変更なしへ戻る通常の
## 比較ロジックと完全に同じ土台になる（§19）。
func start_new() -> void:
	draft.restore_from_saved_dict({})
	draft.restore_clear_check_snapshot({})
	current_stage_id = ""
	current_step = 1
	has_reached_summary = false
	_reference_authoring_snapshot = draft.full_authoring_snapshot()
	# 状態遷移不具合修正: RBMCreatorMainはRBMCreatorEntryが1つだけ保持し続け、
	# 破棄・再構築されない（同ファイルのクラス冒頭コメント参照）——つまり
	# _show_only()で切り替わる内部サブビュー(_steps_root/_appearance_picker/
	# _test_battle_view/_clear_check_view/_save_view)の「今どれが表示中か」
	# という一時的なUI状態は、前回のセッションを終えた時点のまま次回まで
	# 残り続ける。特に保存成功画面からの「クリエイター一覧に戻る」
	# (_on_save_return_to_creator_list())はCreator自体を非表示にするだけで
	# 内部を_steps_rootへ戻していなかったため、次にこの関数(=新しい編集
	# セッションの開始点)が呼ばれた時に保存成功画面が残留表示されていた。
	# 「新しい編集セッションを開始する」ことの一部として、内部サブビューを
	# 必ず_steps_rootへ戻す——draft自体（永続データ）には一切触れない。
	_show_only(_steps_root)
	_refresh()

## §31/§34/§43: 保存済みstageを開く。RBMLocalStageRepository.load_stage()が
## {"ok":false}を返した場合（壊れたJSON・存在しないid等）はDraftへ一切触れず
## そのまま返す——呼び出し側（RBMCreatorEntry）は一覧画面に留まればよく、
## ゲームがクラッシュすることも他のstageに影響が及ぶこともない。
func start_loaded(stage_id: String) -> Dictionary:
	var result := RBMLocalStageRepository.load_stage(stage_id)
	if not bool(result.get("ok", false)):
		return result
	draft.restore_from_saved_dict(result.get("draft_data", {}))
	draft.restore_clear_check_snapshot(result.get("clear_check_data", {}))
	current_stage_id = stage_id
	# 実機プレイ改善② item2: 保存済みstageを編集する場合、STEP1では
	# なくSTEP7（最終確認）から開始する——保存済みのボスは既に一通り
	# 完成しているため、まず全体を確認してから必要な箇所だけSTEP7の
	# 「編集」ボタン（edit_step()）またはpress_back()の戻る連鎖で
	# STEP6→STEP5→…と辿って直せば良い、という想定。「新しいボス戦を
	# 作る」（start_new()、上記）は引き続きSTEP1から開始する——この
	# 変更対象はstart_loaded()のみ。has_reached_summary=trueにするのは
	# 「STEP7を最初に見せる」こと自体がまさに「最終確認へ到達済み」の
	# 状態そのものであるため（press_return_to_summary()やSTEP7以外の
	# STEPで表示される「最終確認へ戻る」ボタンの表示条件と整合させる）。
	current_step = STEP_COUNT
	has_reached_summary = true
	# §34-7: 保存時authoring snapshotは「復元後Draftから」生成する——保存
	# ファイル自体に別途埋め込まれた値を読むのではなく、restore直後のdraftを
	# そのままfull_authoring_snapshot()した結果を使うことで、ロード直後は
	# 必ず未保存変更なしになる（§34末尾の要件）。
	_reference_authoring_snapshot = draft.full_authoring_snapshot()
	# 状態遷移不具合修正: start_new()と同じ理由——このRBMCreatorMainインスタンス
	# は使い回されるため、前回セッションで表示していたサブビュー(特に保存
	# 成功画面)が残ったままになりうる。新しい編集セッションの開始点として、
	# 必ず_steps_rootへ戻す。
	_show_only(_steps_root)
	_refresh()
	return {"ok": true}

# ---------------------------------------------------------------------------
# Creator退出・未保存変更 (Phase 1 Step 6, §14/§19/§36/§37)
# ---------------------------------------------------------------------------

## §14/§19: dirty flagではなく、現在のdraftと「最後に保存した/新規起動直後の」
## 参照snapshotとのライブ比較——A→B→Aで自動的にfalseへ戻る（Step 5の
## is_clear_check_currently_valid()と同じ設計哲学）。
func has_unsaved_changes() -> bool:
	return draft.full_authoring_snapshot() != _reference_authoring_snapshot

## §36/§37: Creator画面自体からの退出要求。未保存変更が無ければ即座に
## exitedを発火、あれば確認パネルを表示する。
func press_exit_creator() -> void:
	if has_unsaved_changes():
		_exit_confirm_panel.visible = true
	else:
		exited.emit()

## §36「保存する」: 通常の保存フロー（STEP7の保存ボタンと同じ画面）へ進む。
## 既存stageだからといって自動上書きはしない——ユーザーが上書き/新しい
## ボスとして保存を選べる既存の保存画面（RBMCreatorSaveView）にそのまま
## 委ねる。保存後は保存画面自身の「Creatorに戻る」でSTEP7へ戻るだけで、
## 退出自体は自動継続しない（保存ボタンを押しただけで強制的にCreator
## 全体から追い出すのは通常の「保存」操作として不自然なため）。
func _on_exit_confirm_save_pressed() -> void:
	_exit_confirm_panel.visible = false
	press_save()

## §36「保存せず終了」: 編集中の変更を破棄してCreator自体を退出する。
func _on_exit_confirm_discard_pressed() -> void:
	_exit_confirm_panel.visible = false
	exited.emit()

## §36「キャンセル」: 何も起こさずCreatorへ戻る。
func _on_exit_confirm_cancel_pressed() -> void:
	_exit_confirm_panel.visible = false

# ---------------------------------------------------------------------------

func _show_only(node: Control) -> void:
	_steps_root.visible = (node == _steps_root)
	_appearance_picker.visible = (node == _appearance_picker)
	_test_battle_view.visible = (node == _test_battle_view)
	_clear_check_view.visible = (node == _clear_check_view)
	_save_view.visible = (node == _save_view)
	_exit_button.visible = (node == _steps_root)
	# 実機プレイ改善③ item3/5/6: STEP1-7専用の「戻る/最終確認へ戻る/次へ」
	# ナビゲーション行は、これまで_show_only()の対象外でTEST BATTLE/CLEAR
	# CHECK/保存/外見選択のどの画面でも常に表示され続けていた（root_column
	# の中で_steps_rootとは独立した兄弟要素のため）——STEP1-7自体を表示して
	# いる時だけ表示する。
	_nav_row.visible = (node == _steps_root)
	## Creator本体UI刷新（2026-09-04）§3: 共通ヘッダーはSTEP1〜6（_steps_root
	## 表示中）でのみ意味を持つ——TEST BATTLE/Clear Check/保存/外見選択では
	## _nav_row/_exit_buttonと同様に隠す（「STEP n / 総数」がそれらの画面
	## では実際の現在位置を表さないため）。
	_header.visible = (node == _steps_root)
	if node != _steps_root:
		_exit_confirm_panel.visible = false

func _refresh() -> void:
	## Creator UI改修（2026-09-05）§24〜§27: 「公開後にClear Checkを無効化
	## する変更が行われたら自動的に非公開へ戻す」——Creator内のあらゆる操作
	## が最終的にこの共通_refresh()を通るため、単一の呼び出し点でこの一方向
	## の是正を都度働かせる（draft側の他の状態と同じ「都度再導出」哲学、
	## published自体の詳細はRBMCreatorDraft.sync_published_with_clear_check()
	## 参照）。
	draft.sync_published_with_clear_check()
	for i in range(_step_views.size()):
		_step_views[i].visible = (i + 1 == current_step)
	_current_view().refresh()
	_back_button.disabled = current_step <= 1
	_return_to_summary_button.visible = has_reached_summary and current_step != STEP_COUNT
	_next_button.visible = current_step < STEP_COUNT
	## Creator UI改修（2026-09-05）§4/§13/§19: STEP5（最終確認）は共通フレーム
	## （左STEPナビ／右BOSS PROFILE）を持たない明示的な例外、かつ「← 戻る /
	## [保存][公開]」という専用の下部バーを自分自身の内容として持つため、
	## 共有の_nav_row（戻る/最終確認へ戻る/次へ）自体もSTEP5では隠す
	## （§19のASCIIモックアップに無い「次へ」「STEP n/総数」の重複表示を
	## 避ける——_headerは引き続き表示する、こちらは常設のタイトルバーで
	## モックアップが定める中央コンテンツ領域の外側にあるため）。
	var on_summary := current_step == STEP_COUNT
	_step_nav_column.visible = not on_summary
	_boss_profile_panel.visible = not on_summary
	_nav_row.visible = not on_summary
	if not on_summary:
		_step_nav_column.set_current_step(current_step)
		_boss_profile_panel.update(draft)
	var view = _current_view()
	_status_label.text = "" if view.is_step_valid() else view.validation_message()
	## Creator本体UI刷新（2026-09-04）§3: 現在の工程名とSTEP n / 総数は、
	## 実際の工程数・現在位置から都度算出する（デザイン例の固定文言を
	## 埋め込まない）。
	_header.title_label.text = tr("ボス作成 ｜ %s") % tr(STEP_NAMES[current_step - 1])
	_header.step_label.text = "STEP %d / %d" % [current_step, STEP_COUNT]
	_refresh_world_ui.call_deferred()


func _refresh_world_ui() -> void:
	_world_ui.creator_layout(self)
	_world_ui.creator_selection(self)
	_world_ui.walk(self)
	for battle_view in [_test_battle_view, _clear_check_view]:
		if battle_view.get_parent() != self:
			battle_view.reparent(self)
			battle_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
