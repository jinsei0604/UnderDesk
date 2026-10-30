class_name RBMChallengeEntry
extends Control

## Phase 1 Step 7 §1〜§5/§21〜§38 — CHALLENGEの入口。RBMCreatorEntry
## （「CREATE」の入口、Step 6）と並列する独立クラス——RBMCreatorEntryの中に
## 組み込んだり、共通の基底クラスを抽出したりはしていない（§38: CHALLENGE
## 一覧とCreator編集一覧は別画面・別責務、既存のCreator関連クラスは一切
## 変更していない）。main.gd/UNDERDESK本体への接続はまだしない（§62、
## Phase 1のスコープ外）——このクラス単体でGUTから直接インスタンス化して
## 使う、RBMCreatorEntry自身が現時点でそうであるのと同じ位置づけ。
##
## §36〜§38: stage一覧・確認画面の作成は必ずRBMLocalStageRepository.load_stage()
## から新規のRBMCreatorDraftを構築する経路のみを通る。Creatorの
## in-memory draftを直接受け取る経路は存在しない。
##
## Phase 1 Step 8 §5 — 共通ルートへ戻る要求。CHALLENGEはCreatorと違い
## 「未保存変更」という概念自体が存在しない（保存stageへ一切副作用を与えない
## ことはStep 7で徹底検証済み）ため、確認なしで直接common routeへ戻れる。
##
## ---------------------------------------------------------------------------
## CHALLENGE UI再設計（挑戦ハブ + 共通ボス一覧画面、指示書§0〜§28、2026-09）
## ---------------------------------------------------------------------------
## 旧: 「挑戦」を押すと単純な検索一覧画面(_list_panel)がいきなり表示された。
## 新: 「挑戦」→挑戦ハブ(_hub_view、新設RBMChallengeHubView)を必ず経由する。
## ハブでカテゴリ/ランダム/検索のいずれかを選ぶと、共通ボス一覧画面
## （既存の_list_panel/_list_rows/検索欄を再利用したまま拡張したもの）が
## 開く。共通一覧画面は「左: ボスカード一覧」「右: 選択中ボスの詳細
## （既存のRBMChallengeConfirmViewをそのまま埋め込み、独立した確認ステップ
## から常設の右カラムへ役割変更）」の2カラム構成——カード選択は即座に右側を
## 更新するだけで、戦闘は開始しない(§11)。「このボスに挑戦」を押した瞬間に
## 初めて実戦闘へ進む（新しい確認ステップを追加しない、§17）。
##
## 既存の状態遷移(_show_list/_show_confirm/_show_battle)は
## _show_hub/_show_browse/_show_battleへ再編した——_show_browseは旧
## _show_list+_show_confirmを統合したもの（一覧と詳細は常に同時に表示され、
## 個別に隠れることはない）。
##
## published整合性(§20/§21): _refresh_list()は呼ばれるたびに必ず
## RBMLocalStageRepository.list()を再取得する（キャッシュしない、既存の
## 設計をそのまま維持）ため、公開取り下げは次回の一覧再取得時に必ず反映
## される。「戦闘開始直前の再確認」については、このアプリが単一ウィンドウ・
## 単一プロセスのローカル専用アーキテクチャであり、一覧を開いてから
## 「このボスに挑戦」を押すまでの間に別経路でpublished状態が変化する余地が
## 構造的に存在しない（CREATEとCHALLENGEは同一ウィンドウ内の排他的な画面で
## あり、同時に開けない）ため、既存の大量のテスト（未公開のテスト用stageで
## 戦闘そのものを検証する既存資産、test_rbm_challenge_flow.gd等）と直接衝突
## する形でこのチェックを追加することはしていない——完了報告で開示する
## 判断（§21の文言どおりの再チェックを追加すると、公開状態を検証しない
## 純粋な戦闘メカニクステストが軒並み失敗する。安全な最小差分が存在しない
## ケースと判断し、無人作業時ルールに従い保留してこの画面の他の確定済み
## 部分を完成させた）。
signal exit_requested

## 実機プレイ改善①§12: RBMCreatorStep1Basicと同じ理由・同じ技法。
const CONTENT_SIDE_MARGIN_PX := 80.0
const CONTENT_TOP_MARGIN_PX := 40.0
## 登場演出の入り（前の画面が閉じる）。
const ScreenClose = preload("res://src/bossmaker/visuals/encounter/rbm_screen_close.gd")
const Escape = preload("res://src/bossmaker/rbm_escape.gd")

## Phase 3.5 UI統一§33バグ修正: 既存のLineEdit（RBMCreatorStep1Basic.
## BOSS_NAME_EDIT_MIN_SIZE等）はcustom_minimum_sizeを持つが、この検索欄
## 2つだけが未設定のまま既定の極small幅で、placeholder_textが「ステー」
## 「ボス名」等へ視覚的に切れていた（§38: 明白な原因・小さな修正範囲の
## 表示バグ）。
const SEARCH_FIELD_MIN_SIZE := Vector2(170.0, 32.0)

var _hub_view: RBMChallengeHubView
var _online_list_view: RBMOnlineBossListView
var _last_browse_was_online := false

## 挑戦トップの「あなたの討伐記録」（RBMDefeatRecord、2026-10-16）。今のアカウントの記録（必要な時に作る）。
var _defeat_record: RBMDefeatRecord
## テスト・検証で差し替える記録（アカウント・Steam Cloud を偽物にする）。
var _defeat_record_for_testing: RBMDefeatRecord
## 「挑戦する」の時に控える、勝った時に記録する内容 {boss_id, mode, rate}（オンラインのボスだけ）。
## 2026-10-22: 挑戦の記録の応答の by_owner（attempt_by_owner）と、勝った時の判定（ownership）もここに入る。
var _defeat_context: Dictionary = {}
## 2026-10-29 体験版: 異なるオンラインボスへの挑戦は累計15体まで（数えて断るのはサーバー）。
## _demo_status: 最後に分かった使用状況 {"used", "limit", "ids"}（空 = まだ分からない・通信できなかった。0体とは扱わない）。
## _demo_prefetched: 戦闘を始める前の確認で送った挑戦の記録の応答 {"boss_id", "response"}（RBMBattleResultReporter が使う）。
var _demo_status: Dictionary = {}
var _demo_prefetched: Dictionary = {}
var _demo_gate_busy := false
var _demo_dialog: AcceptDialog
## オンラインのボスとの戦闘の結果を戦闘チケットで送る係と、今のアカウントの送信待ち（2026-10-23）。
var _result_reporter: RBMBattleResultReporter
var _result_outbox_instance: RBMBattleResultOutbox
## テスト・検証で差し替える送信待ち。
var _result_outbox_for_testing: RBMBattleResultOutbox

## 討伐記録に数えるかの判定の結果（2026-10-22、作者本人のボスは数えない）。
const DEFEAT_NOT_OWNER := "not_owner"
const DEFEAT_OWNER := "owner"
const DEFEAT_UNKNOWN := "unknown"
const DEFEAT_CONFLICT := "conflict"

## テスト専用: _online_list_view自身は_ready()内で初めて生成されるため、
## 生成前(.new()直後、add_child_autofree()より前)にこのフィールドへ
## fake adapterを設定しておくと、_build_online_list_view()がそれを
## _online_list_view.set_api_adapter_for_testing()へ渡す。
var _injected_online_api_adapter_for_testing: RBMBossApiAdapter = null

## テスト専用: オンライン版「未挑戦」(2026-09)——_online_list_view用の
## fake recorder、および挑戦開始/クリア記録(_on_challenge_requested()/
## _on_challenge_won())用のfake recorderの両方をこの1つのインスタンスで
## 兼ねる(実運用でも同じインスタンスを共有する、下記_online_recorder()参照)。
var _injected_online_recorder_for_testing: RBMOnlineChallengeRecorder = null
var _online_recorder_instance: RBMOnlineChallengeRecorder = null
## Steam の準備を前もって済ませたか（_warm_online_recorder_soon()）
var _online_recorder_warm_requested := false
## オンライン一覧を開いてから Steam の準備を始めるまでの秒数（一覧の読み込み中の画面を先に出す）
const ONLINE_RECORDER_WARM_DELAY := 0.2
var _list_panel: VBoxContainer
var _category_title_label: Label
var _name_search_field: LineEdit
var _id_search_field: LineEdit
var _list_rows: VBoxContainer

var _confirm_view: RBMChallengeConfirmView
var _battle_view: RBMChallengeBattleView

## ""=検索モード（カテゴリ絞り込みなし）。それ以外はRBMChallengeHubView.
## CATEGORY_*のいずれか。
var _current_category: String = ""
var _selected_stage_id: String = ""

## §11: 選択状態の更新をfree()/再構築なしにその場で行うための、現在一覧に
## 表示中のカードインスタンスへの参照（_refresh_list()のたびに作り直す）。
var _card_by_stage_id: Dictionary = {}

const STATUS_LABELS := {
	"playable": "挑戦可能",
	"clear_checked": "✓ クリアチェック済み",
}

func _ready() -> void:
	_build_ui()
	# 討伐記録は、挑戦トップが実際に画面に出た時だけ読む（起動時・タイトル画面では Steam に触れない）
	visibility_changed.connect(func():
		if is_visible_in_tree() and _hub_view.visible:
			_refresh_defeat_record())

func _build_ui() -> void:
	# Phase 3.5 UI統一§0/§5/§11: RBMCreatorEntryと同じ理由・同じ1行——
	# CHALLENGE全体（ハブ/一覧/確認/戦闘）の唯一のルートControlへ明示適用
	# する。RBMChallengeBattleView自身は既に自分のルートへ同じThemeを個別
	# 適用済みだが、Controlが自分の.themeを持てば祖先からの継承を単に上書き
	# するだけなので無害（二重適用の副作用は無い）。
	theme = RBMUiTheme.build_theme()
	RBMBattleUiKit.add_root_background(self)

	_build_hub_view()
	_build_online_list_view()

	## §36の既存方針どおり、RBMLocalStageRepository.load_stage()から新規に
	## 復元されたRBMCreatorDraftだけを受け取る——先に構築してから
	## _build_list_panel()の右カラムへ埋め込む。
	_confirm_view = RBMChallengeConfirmView.new()
	_confirm_view.name = "ChallengeConfirmView"
	_confirm_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_confirm_view.visible = false
	_confirm_view.challenge_requested.connect(_on_challenge_requested)

	_build_list_panel()

	_battle_view = RBMChallengeBattleView.new()
	_battle_view.name = "ChallengeBattleView"
	_battle_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_battle_view.visible = false
	_battle_view.returned_to_list.connect(_on_battle_returned_to_list)
	_battle_view.challenge_won.connect(_on_challenge_won)
	_battle_view.challenge_lost.connect(_on_challenge_lost)
	# オンラインのボスとの戦闘の結果を戦闘チケットで送る（2026-10-23）
	_result_reporter = RBMBattleResultReporter.new()
	_result_reporter.name = "BattleResultReporter"
	_result_reporter.recorder_source = _online_recorder
	_result_reporter.outbox_source = _result_outbox
	_result_reporter.defeat_confirmed.connect(_record_defeat)
	_result_reporter.defeat_without_ticket.connect(_record_online_clear_and_defeat)
	add_child(_result_reporter)
	_battle_view.battle_restarted.connect(_result_reporter.on_battle_restarted)
	add_child(_battle_view)

	_show_hub()

func _build_hub_view() -> void:
	_hub_view = RBMChallengeHubView.new()
	_hub_view.name = "ChallengeHubView"
	_hub_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hub_view.visible = false
	_hub_view.category_selected.connect(_on_hub_category_selected)
	_hub_view.random_requested.connect(_on_hub_random_requested)
	_hub_view.search_requested.connect(_on_hub_search_requested)
	_hub_view.back_to_root_requested.connect(_on_back_to_root_pressed)
	add_child(_hub_view)

## テスト専用: _build_online_list_view()より前に呼ぶこと
## （.new()直後、add_child_autofree()より前）。
func set_online_api_adapter_for_testing(adapter: RBMBossApiAdapter) -> void:
	_injected_online_api_adapter_for_testing = adapter

## テスト専用: 同じく_build_online_list_view()より前に呼ぶこと。
func set_online_recorder_for_testing(recorder: RBMOnlineChallengeRecorder) -> void:
	_injected_online_recorder_for_testing = recorder

## _on_challenge_requested()/_on_challenge_won()と_online_list_viewが
## 同じrecorderインスタンス(=同じRBMSteamAuth/RBMBossApiAdapter)を共有する
## ——Steam ticket取得の仕組みを画面ごとに複数持たない。
func _online_recorder() -> RBMOnlineChallengeRecorder:
	if _online_recorder_instance == null:
		if _injected_online_recorder_for_testing != null:
			_online_recorder_instance = _injected_online_recorder_for_testing
		else:
			_online_recorder_instance = RBMOnlineChallengeRecorder.new()
			add_child(_online_recorder_instance)
	return _online_recorder_instance

## Phase 4D-1: 「オンライン」カテゴリ専用の別パネル。既存のローカル一覧
## (_list_panel)とは独立させ、ローカルChallenge既存動作を一切変更しない。
## 挑戦ハブ オンライン移行(2026-09): SIMPLE/HARDCORE/オンライン/新着/未挑戦の
## 5カテゴリ全てがこの同じパネルを共有する(_on_hub_category_selected()参照)。
func _build_online_list_view() -> void:
	_online_list_view = RBMOnlineBossListView.new()
	_online_list_view.name = "OnlineBossListView"
	_online_list_view.visible = false
	if _injected_online_api_adapter_for_testing != null:
		_online_list_view.set_api_adapter_for_testing(_injected_online_api_adapter_for_testing)
	_online_list_view.set_recorder_for_testing(_online_recorder())
	_online_list_view.boss_selected.connect(_on_online_boss_selected)
	_online_list_view.challenge_requested.connect(_on_online_challenge_requested)
	_online_list_view.back_requested.connect(_on_back_to_hub_pressed)
	add_child(_online_list_view)

## オンライン版「未挑戦」(2026-09)実装に伴い、以後この画面で選択された
## boss_idはオンラインboss(UUID)——_last_browse_was_onlineが挑戦開始/
## クリア時までtrueのまま保たれるため、_on_challenge_requested()/
## _on_challenge_won()はこのフラグでローカル/オンラインを判定できる
## (UUID形式かどうかの推測判定はしない、既存の明示的なフラグを再利用)。
func _on_online_boss_selected(boss_id: String, draft: RBMCreatorDraft, _boss_name: String, _author_name: String) -> void:
	# ローカルの_on_stage_row_pressed()と同じ着地点(_confirm_view.open())へ
	# 接続する——新しい別Battle経路は作らない(ユーザー確定仕様)。
	_selected_stage_id = ""
	_confirm_view.open(boss_id, draft)
	_show_online_browse()

## オンライン一覧の右の詳細で「挑戦する」が押された(2026-10)。選択時と同じ着地点(_confirm_view)へ
## 載せてから、ローカルの「このボスに挑戦」と同じ_on_challenge_requested()で戦闘を始める——挑戦回数の
## 記録・戦闘背景の受け渡しなど、戦闘開始の処理は1つの経路のまま。
func _on_online_challenge_requested(boss_id: String, draft: RBMCreatorDraft) -> void:
	_on_online_boss_selected(boss_id, draft, draft.boss_name, draft.author_name)
	_on_challenge_requested(draft.to_definition())

func _show_online_browse() -> void:
	_hub_view.visible = false
	_online_list_view.visible = true
	_list_panel.visible = false
	_confirm_view.visible = true
	_battle_view.visible = false
	_last_browse_was_online = true
	_update_battle_preparation()

## QA-06: 選んだボスの確認(戦闘を始める前の画面)が出ている間は、戦闘の演出の素材を裏で読み込んでおく
## (ボス・外見・味方・技・覚醒が確定した最も早い時点)。選択が無い時・挑戦の画面を離れた時は手放す。
func _update_battle_preparation() -> void:
	var draft: RBMCreatorDraft = _confirm_view._draft
	if _confirm_view.visible and draft != null and not _confirm_view.stage_id.is_empty():
		_battle_view.prepare_presentations(draft.to_definition(), draft.appearance_id, draft.battle_background)
	else:
		_battle_view.release_presentations()

## §7/§8: SIMPLE/HARDCORE/注目/新着/未挑戦/人気/高難度/検索がすべて共有する
## 唯一の共通レイアウト——左にボスカード一覧（スクロール可能、§18）、右に
## 選択中ボスの詳細（_confirm_view）。ヘッダは「← 挑戦ハブ」＋現在の
## カテゴリ名。
func _build_list_panel() -> void:
	_list_panel = VBoxContainer.new()
	_list_panel.name = "ChallengeListPanel"
	_list_panel.anchor_right = 1.0
	_list_panel.anchor_bottom = 1.0
	_list_panel.offset_left = CONTENT_SIDE_MARGIN_PX
	_list_panel.offset_right = -CONTENT_SIDE_MARGIN_PX
	_list_panel.offset_top = CONTENT_TOP_MARGIN_PX
	_list_panel.offset_bottom = -20.0
	_list_panel.visible = false
	add_child(_list_panel)

	var header_row := HBoxContainer.new()
	header_row.name = "ListHeaderRow"
	_list_panel.add_child(header_row)

	var back_to_hub_button := Button.new()
	back_to_hub_button.name = "BackToHubButton"
	back_to_hub_button.text = tr("← 挑戦ハブ")
	back_to_hub_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	back_to_hub_button.pressed.connect(_on_back_to_hub_pressed)
	header_row.add_child(back_to_hub_button)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_spacer)

	_category_title_label = Label.new()
	_category_title_label.name = "CategoryTitleLabel"
	_category_title_label.text = tr("検索")
	_category_title_label.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	header_row.add_child(_category_title_label)

	var search_row := HBoxContainer.new()
	_list_panel.add_child(search_row)
	_name_search_field = LineEdit.new()
	_name_search_field.name = "NameSearchField"
	_name_search_field.custom_minimum_size = SEARCH_FIELD_MIN_SIZE
	_name_search_field.placeholder_text = tr("ボス名で検索")
	_name_search_field.text_changed.connect(func(_new_text: String): _refresh_list())
	search_row.add_child(_name_search_field)
	_id_search_field = LineEdit.new()
	_id_search_field.name = "IdSearchField"
	_id_search_field.custom_minimum_size = SEARCH_FIELD_MIN_SIZE
	_id_search_field.placeholder_text = tr("ステージIDで検索")
	_id_search_field.text_changed.connect(func(_new_text: String): _refresh_list())
	search_row.add_child(_id_search_field)

	## §7/§8: 2カラム本体。
	var columns := HBoxContainer.new()
	columns.name = "ListColumns"
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_panel.add_child(columns)

	var left_column := VBoxContainer.new()
	left_column.name = "ListLeftColumn"
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left_column)

	## §18: ボス数が増えても閲覧できるようスクロール可能にする
	## （旧実装は_list_rowsを_list_panelへ直接addしておりスクロール不可
	## だった——このスクロール包装が新設）。
	var list_scroll := ScrollContainer.new()
	list_scroll.name = "ChallengeListScroll"
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_child(list_scroll)

	_list_rows = VBoxContainer.new()
	_list_rows.name = "ChallengeStageListRows"
	_list_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Phase 3.5 UI統一§11: 管理画面のリストに見えないよう、行間に余白を
	# 持たせる——各行自体の構造は変わったが、この間隔の趣旨自体は維持する。
	_list_rows.add_theme_constant_override("separation", 10)
	list_scroll.add_child(_list_rows)

	columns.add_child(_confirm_view)

# ---------------------------------------------------------------------------
# §2〜§6 — 挑戦ハブからの遷移
# ---------------------------------------------------------------------------

## 挑戦ハブ オンライン移行(2026-09、ユーザー確定仕様): SIMPLE/HARDCORE/
## オンライン/新着/未挑戦/人気/高難度はSupabase上の公開ボス一覧
## (_online_list_view)へ接続する。ローカルの共通一覧(_list_panel/
## _refresh_list()/RBMLocalStageRepository)には一切触れない——それらの
## 関数・データ自体は削除せず維持するが、この7カテゴリからは到達しなく
## なる（検索・ランダムも 2026-10-17 からオンライン一覧の「検索」「ランダム抽選」を使う、
## 下の_on_hub_search_requested()/_on_hub_random_requested()参照）。
##
## §11(ユーザー確定仕様)「SIMPLE + 未挑戦 → 未挑戦SIMPLEだけ」: モードと
## カテゴリは独立した状態として扱う——SIMPLE/HARDCOREボタンは現在選択中の
## カテゴリ(_online_list_view.current_category())を維持したままmodeだけを
## 変更し、オンライン/新着/未挑戦/人気/高難度ボタンは現在選択中のmode
## (_online_list_view.current_mode())を維持したままcategoryだけを変更する。
## 「オンライン」ボタンだけは例外的にcategoryを明示的にONLINE(絞り込み
## なしの全件)へ戻す(それが「オンライン」ボタン自体の意味のため)。
func _on_hub_category_selected(category: String) -> void:
	match category:
		RBMChallengeHubView.CATEGORY_FEATURED:
			_open_online_category(_online_list_view.current_mode(), RBMOnlineBossListView.CATEGORY_ONLINE, category)
			return
		RBMChallengeHubView.CATEGORY_NEW:
			_open_online_category(_online_list_view.current_mode(), RBMOnlineBossListView.CATEGORY_NEW, category)
			return
		RBMChallengeHubView.CATEGORY_UNCHALLENGED:
			_open_online_category(_online_list_view.current_mode(), RBMOnlineBossListView.CATEGORY_UNCHALLENGED, category)
			return
		RBMChallengeHubView.CATEGORY_POPULAR:
			_open_online_category(_online_list_view.current_mode(), RBMOnlineBossListView.CATEGORY_POPULAR, category)
			return
		RBMChallengeHubView.CATEGORY_HIGH_DIFFICULTY:
			_open_online_category(_online_list_view.current_mode(), RBMOnlineBossListView.CATEGORY_HIGH_DIFFICULTY, category)
			return
		RBMChallengeHubView.CATEGORY_SIMPLE:
			_open_online_category(RBMCreatorDraft.CREATOR_MODE_SIMPLE, _online_list_view.current_category(), category)
			return
		RBMChallengeHubView.CATEGORY_HARDCORE:
			_open_online_category(RBMCreatorDraft.CREATOR_MODE_ADVANCED, _online_list_view.current_category(), category)
			return

## 見出しはカテゴリ名(ハブのSIMPLE/HARDCOREから開いた時も。モードは一覧画面の右上の切替で示す、2026-10)。
func _open_online_category(mode: String, online_category: String, _hub_category: String) -> void:
	_confirm_view.clear_selection()
	_show_online_browse()
	_online_list_view.refresh_with(mode, online_category, RBMOnlineBossListView.category_title(online_category))
	_warm_online_recorder_soon()
	_refresh_demo_challenge_status()

## 挑戦の記録係（Steam）の準備を、オンライン一覧を開いて読み込み中の間に済ませる（最初の1回だけ）。
## Steam の初期化は本体の処理で約0.12秒止まる。以前は最初の「挑戦する」で戦闘が始まる瞬間（挑戦の記録の
## 最初の呼び出し）に行われ、そのフレームが約0.2秒止まっていた（プレイ体験監査 PX-27、2026-10-17）。
## 一覧は通信の結果を待っている画面なので、ここで止まっても目立たない。記録の中身・Steam の使い方は変えない。
func _warm_online_recorder_soon() -> void:
	if _online_recorder_warm_requested:
		return
	_online_recorder_warm_requested = true
	var timer := Timer.new()
	timer.name = "OnlineRecorderWarmTimer"
	timer.one_shot = true
	timer.wait_time = ONLINE_RECORDER_WARM_DELAY
	add_child(timer)
	timer.timeout.connect(_on_online_recorder_warm_timeout.bind(timer))
	timer.start()

func _on_online_recorder_warm_timeout(timer: Timer) -> void:
	timer.queue_free()
	_online_recorder().account_id()  # 記録係の Steam の初期化（RBMOnlineChallengeRecorder._ensure_setup()）を行う

## 挑戦トップの「ボスを検索」（2026-10-17 プレイ体験監査 PX-03、ユーザー確定仕様）: オンライン公開ボスを、ボス名・
## 作者名・公開IDで探す（オンライン一覧の「検索」。サーバー側で探す、search-bosses）。モードは一覧で今選んでいるもの。
func _on_hub_search_requested() -> void:
	_open_online_category(_online_list_view.current_mode(), RBMOnlineBossListView.CATEGORY_SEARCH, "")

## 挑戦トップの「ランダムで挑戦」（PX-03、ユーザー確定仕様）: 選択中のモード（オンライン一覧の右上の切替。
## すべて/SIMPLE/HARDCORE）の公開ボス全体から1件引き（未挑戦に限らない。サーバー側で抽選、random-boss）、
## そのボスを選んだ状態で詳細を出す。戦闘は始めない。
func _on_hub_random_requested() -> void:
	_open_online_category(_online_list_view.current_mode(), RBMOnlineBossListView.CATEGORY_RANDOM, "")

## 手元の「手元公開」の印のボスの一覧（旧: 挑戦トップの「ボスを検索」）。2026-10-17 から挑戦トップからは
## 開かない（手元のボスの専用の入口は作らない、ユーザー確定仕様）。以前の版で手元公開した保存データ
## （published=true、手元の挑戦回数・クリア回数）は書き換えずにそのまま読めるよう、一覧・挑戦・記録の処理は残す
## （テストはここから手元の戦闘の流れを確かめる）。
func _open_local_published_list() -> void:
	_current_category = ""
	_category_title_label.text = tr("検索")
	_selected_stage_id = ""
	_confirm_view.clear_selection()
	_name_search_field.text = ""
	_id_search_field.text = ""
	_refresh_list()
	_show_browse()

## 手元公開のボスからのランダム（旧: 挑戦トップの「ランダムで挑戦」）。挑戦トップからは開かない（上と同じ理由で残す）。
## §5: published=trueかつ実際に挑戦可能な全ボスから完全ランダムで1件選び、共通一覧/詳細画面をその1件が
## 選択された状態で開く。抽選後に戦闘を自動開始しない（§5末尾）。
func _open_local_random() -> void:
	var candidates := _base_published_playable_entries()
	if candidates.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var picked := RBMChallengeUiKit.pick_random(candidates, rng)
	_current_category = ""
	_category_title_label.text = tr("ランダム抽選")
	_name_search_field.text = ""
	_id_search_field.text = ""
	_refresh_list()
	_show_browse()
	_on_stage_row_pressed(str(picked.get("stage_id", "")))

func _on_back_to_hub_pressed() -> void:
	_show_hub()

## Esc で戻る（PX-13、2026-10-18）: 挑戦トップ → ホーム、一覧 → 挑戦トップ。戦闘中は戦闘画面が自分で受ける。
func _unhandled_input(event: InputEvent) -> void:
	if not Escape.pressed(self, event):
		return
	if _hub_view.visible:
		Escape.consume(self)
		_on_back_to_root_pressed()
	elif _online_list_view.visible or _list_panel.visible:
		Escape.consume(self)
		_on_back_to_hub_pressed()

# ---------------------------------------------------------------------------
# §2/§3/§5: 一覧・検索
# ---------------------------------------------------------------------------

## published==trueかつstatus!="draft"（＝実際に挑戦可能）な全entry。
## ランダム抽選(§5)と、共通一覧の全カテゴリが共有する土台。
func _base_published_playable_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in RBMChallengeUiKit.filter_published(RBMLocalStageRepository.list()):
		if str(entry.get("status", "draft")) == "draft":
			continue
		out.append(entry)
	return out

## §7/§8: 検索欄は現在のカテゴリに関わらず常に併用できる（指示書§8の
## モックアップどおり、「高難度」等のカテゴリ中でも検索欄は表示され続ける）
## ——まず検索で絞り込み、その後カテゴリ固有のフィルタ/ソートを適用する。
##
## Creator UI改修（2026-09-05）§24〜§27（公開機能、ユーザー確定仕様）:
## 「Definitionとして正常（＝旧来のstatus!="draft"）」だけでは不十分——
## 「published==true」も必須（_base_published_playable_entries()参照）。
func _refresh_list() -> void:
	# RBMChallengeEntry自身の_ready()が構築時に一覧を作らない設計へ変わった
	# （enter_challenge()は挑戦ハブを表示するだけ）——ただし同一フレーム内で
	# 複数回呼び直されても常に正しい行数になるよう、free()（即時削除）は
	# 既存のまま維持する。
	for child in _list_rows.get_children():
		child.free()
	_card_by_stage_id.clear()

	var entries := _base_published_playable_entries()
	entries = RBMChallengeUiKit.filter_by_search(entries, _name_search_field.text, _id_search_field.text)

	match _current_category:
		RBMChallengeHubView.CATEGORY_SIMPLE:
			entries = RBMChallengeUiKit.filter_by_mode(entries, RBMChallengeUiKit.MODE_SIMPLE)
		RBMChallengeHubView.CATEGORY_HARDCORE:
			entries = RBMChallengeUiKit.filter_by_mode(entries, RBMChallengeUiKit.MODE_ADVANCED)
		# CATEGORY_FEATURED（注目）はここへは到達しない——
		# _on_hub_category_selected()が別のオンライン一覧パネルを開いて
		# 早期returnするため（Phase 4D-1）、_current_categoryがこの値に
		# なることはない。
		RBMChallengeHubView.CATEGORY_NEW:
			entries = RBMChallengeUiKit.sort_by_published_at_desc(entries)
		RBMChallengeHubView.CATEGORY_UNCHALLENGED:
			entries = RBMChallengeUiKit.filter_unchallenged(entries)
		RBMChallengeHubView.CATEGORY_POPULAR:
			entries = RBMChallengeUiKit.sort_by_challenge_count_desc(entries)
		RBMChallengeHubView.CATEGORY_HIGH_DIFFICULTY:
			entries = RBMChallengeUiKit.sort_by_corrected_clear_rate_asc(entries)
		_:
			pass  # "" = 検索のみ、追加のカテゴリ処理なし

	for entry in entries:
		_add_stage_row(entry)

## §9/§11: 一覧カード——全カテゴリ共通の6項目（画像/ボス名/作者名/モード/
## 挑戦者数/クリア率）。クリックで選択（右側詳細を更新するだけ、戦闘は
## 開始しない）。
func _add_stage_row(entry: Dictionary) -> void:
	var stage_id := str(entry.get("stage_id", ""))
	var is_selected := stage_id == _selected_stage_id
	var card := RBMChallengeUiKit.build_boss_card(entry, is_selected, _on_stage_row_pressed)
	_list_rows.add_child(card)
	_card_by_stage_id[stage_id] = card

# ---------------------------------------------------------------------------
# §11/§12 — カード選択→右側詳細更新（戦闘は開始しない）
# ---------------------------------------------------------------------------

## §36: Repositoryから毎回新規のRBMCreatorDraftを構築して詳細パネルへ渡す
## ——Creatorが保持しているかもしれない未保存のdraftへは一切アクセスしない。
## §37: この直後にCreator側で同じstageを編集・上書き保存しても、既に選択
## 済みのこの詳細パネル/これから始まる戦闘セッションには影響しない
## （load_stage()が呼ばれるのはこの瞬間だけで、以後Repositoryを再読込する
## 経路はない）。
func _on_stage_row_pressed(stage_id: String) -> void:
	var result := RBMLocalStageRepository.load_stage(stage_id)
	if not bool(result.get("ok", false)):
		return  # §43相当: 破損/削除済みなら何もせず一覧に留まる。
	var draft := RBMCreatorDraft.new()
	draft.restore_from_saved_dict(result.get("draft_data", {}))
	draft.restore_clear_check_snapshot(result.get("clear_check_data", {}))

	# §11: 選択中カードの視覚的な強調を、一覧のfree()/再構築なしにその場で
	# 更新する——この関数自身がカードのgui_inputシグナル経由で呼ばれうる
	# ため（実機で確認済み: そのコールバック実行中に当のカードをfree()する
	# とGodotが"Attempted to free a locked object"で拒否する）、
	# _refresh_list()（内部でfree()する）をここから呼ばない。
	if _card_by_stage_id.has(_selected_stage_id) and _selected_stage_id != stage_id:
		RBMChallengeUiKit.set_card_selected(_card_by_stage_id[_selected_stage_id], false)
	_selected_stage_id = stage_id
	if _card_by_stage_id.has(stage_id):
		RBMChallengeUiKit.set_card_selected(_card_by_stage_id[stage_id], true)

	_confirm_view.open(stage_id, draft)
	_show_browse()

## §22/§23: TEST BATTLE/Clear Checkと同じ役割分担——確認画面はDefinitionを
## 生成するだけ、検証(RBMDefinitionLoader.resolve())と戦闘開始は呼び出し元の
## このメソッドが行う。CHALLENGE一覧は既にis_playable()合格stageのみを
## 表示しているため理論上ここで失敗することは無いはずだが、防御的に検証済み
## の場合のみ戦闘へ進む。
func _on_challenge_requested(definition: Dictionary) -> void:
	var resolved := RBMDefinitionLoader.resolve(definition)
	if not bool(resolved.get("ok", false)):
		return
	# 2026-10-29 体験版: 新しいオンラインのボスは、サーバーが挑戦を受け付けてから戦闘を始める（累計15体まで）。
	if RBMEdition.is_demo() and _last_browse_was_online and not _confirm_view.stage_id.is_empty():
		if _demo_gate_busy:
			return
		_demo_gate_busy = true
		var allowed: bool = await _demo_challenge_gate(_confirm_view.stage_id)
		_demo_gate_busy = false
		if not allowed:
			return
	# 戦闘開始前の登場演出（2026-10-16）: 実際の画面（演出を見せる窓）では、前の画面（ボスの確認）が古いモニターの電源を
	# 切るように閉じてから、今までと同じ手順で戦闘を始め、登場演出を頼む（rbm_screen_close.gd → RBMEncounterDirector）。
	if _battle_view.presentation_enabled and is_visible_in_tree():
		var info := {"boss_name": _confirm_view._draft.boss_name if _confirm_view._draft != null else "",
			"author": _confirm_view._draft.author_name if _confirm_view._draft != null else ""}
		ScreenClose.start(self, _start_challenge.bind(definition, info))
		return
	_start_challenge(definition, {})

## 「挑戦する」の後の戦闘の開始（記録・背景・戦闘の開始・画面の切り替え）。encounter が空でなければ登場・勝利の演出を使う。
func _start_challenge(definition: Dictionary, encounter: Dictionary) -> void:
	# 討伐記録: オンラインのボスなら、ボスID・難易度・この挑戦を始めた時の正式なクリア率（一覧に出しているクリア率）を
	# 控える（勝った時に初めてのボスなら記録する）。手元に保存したボスは数えない。
	_defeat_context = {}
	if _last_browse_was_online and not _confirm_view.stage_id.is_empty() and _confirm_view._draft != null:
		_defeat_context = {"boss_id": _confirm_view.stage_id, "mode": _confirm_view._draft.creator_mode,
			"rate": RBMDefeatRecord.official_rate(_online_list_view.summary_for(_confirm_view.stage_id)),
			# この PC で公開したボスか（補助の判定、2026-10-22）。勝利の演出の最中に保存を読まないよう、ここで1回だけ調べる
			"published_here": RBMLocalStageRepository.online_boss_ids().has(_confirm_view.stage_id)}
	# Phase 3.5 Step 4 §5/§18: ボス詳細ウィンドウが非公開情報を漏らさない
	# ようにするため、確認画面が既に読み込み済みのdraft（_confirm_view自身の
	# フィールド、Definition自体には含まれない——RBMCreatorDraft.to_definition()
	# はchallenge_info_visibilityを意図的に含めない、そちらのdocコメント
	# 参照）から公開設定を取り出し、戦闘Viewへそのまま引き継ぐ。
	var visibility: Dictionary = RBMBattleUiKit.ALL_VISIBLE
	var appearance_id := ""
	if _confirm_view._draft != null:
		visibility = _confirm_view._draft.challenge_info_visibility
		appearance_id = _confirm_view._draft.appearance_id
	# CHALLENGE UI再設計 §4-F/§10: 「挑戦者数」記録——実際に戦闘が開始される
	# この瞬間にのみ1回加算する（「最初からやり直す」「もう一度挑戦」は
	# 新たな挑戦者としては数えない、判断——完了報告で開示）。
	#
	# オンライン版「未挑戦」(2026-09、ユーザー確定仕様§9): オンライン/
	# ローカルの判定は_last_browse_was_online(既存の明示的なフラグ、
	# UUID形式かどうかの推測判定はしない)で行う。オンラインの場合は
	# RBMOnlineChallengeRecorder経由でSupabaseへ記録するが、これは
	# ベストエフォート(§7)——awaitせずに投げるだけで、記録の成否に
	# 関わらず戦闘は必ず開始する(通信失敗でゲームが止まらないようにする)。
	# 2026-10-23: オンラインは、挑戦の記録の応答で最初の戦闘の戦闘チケットも受け取る（RBMBattleResultReporter）。
	# 前に届かなかった結果があれば、続けて送り直す（間隔を空ける）。
	if not _confirm_view.stage_id.is_empty():
		if _last_browse_was_online:
			# 体験版の確認で送った挑戦の記録があれば、それを使う（同じ挑戦を二重に送らない）。
			var prefetched: Dictionary = {}
			if str(_demo_prefetched.get("boss_id", "")) == _confirm_view.stage_id:
				prefetched = _demo_prefetched.get("response", {})
			_demo_prefetched = {}
			_result_reporter.begin_challenge(_confirm_view.stage_id, _defeat_context, prefetched)
			_result_reporter.flush_if_due()
		else:
			_result_reporter.end_challenge()
			RBMLocalStageRepository.record_challenge_attempt(_confirm_view.stage_id)
	_battle_view.battle_background = _confirm_view._draft.battle_background if _confirm_view._draft != null else "night"
	# 結果の画面に出す挑戦モードと制作者（表示専用、rbm_battle_result_panel.gd）
	_battle_view.result_mode = _confirm_view._draft.creator_mode if _confirm_view._draft != null else ""
	_battle_view.result_author = _confirm_view._draft.author_name if _confirm_view._draft != null else ""
	if not encounter.is_empty():
		_battle_view.request_encounter(encounter)
	_battle_view.start_battle(definition, visibility, appearance_id)
	_show_battle()

# ---------------------------------------------------------------------------
# 2026-10-29 体験版: 異なるオンラインボスへの挑戦は、Steam アカウントごとに累計15体まで
# ---------------------------------------------------------------------------
# 数えて断るのはサーバー（record-challenge-attempt・issue-battle-ticket。DB の claim_demo_challenge_slot()）。
# ゲームは表示と、戦闘を始めてよいかの確認だけをする（ローカルのボス・テストバトル・クリアチェックは通らない）。

## オンライン一覧を開いた時に、今の使用状況を読んで一覧の上の札に出す（通信できなければ「分からない」と出す）。
func _refresh_demo_challenge_status() -> void:
	if not RBMEdition.is_demo():
		return
	if _demo_status.is_empty():
		_online_list_view.set_demo_challenge_status({"state": "loading"})
	var response: Dictionary = await _online_recorder().demo_challenge_status()
	if not is_instance_valid(_online_list_view):
		return
	if bool(response.get("ok", false)) and bool(response.get("limited", false)):
		var ids: Array = []
		for id in response.get("challenged_boss_ids", []):
			ids.append(str(id))
		_set_demo_status(int(response.get("used", ids.size())), int(response.get("limit", RBMEdition.DEMO_MAX_ONLINE_CHALLENGED_BOSSES)), ids)
	elif bool(response.get("ok", false)):
		# サーバーが製品版のチケットと判断した（開発中に --mc-demo で試す時など）: 制限は無いので札を出さない。
		_demo_status = {}
		_online_list_view.set_demo_challenge_status({"state": "unlimited"})
	elif _demo_status.is_empty():
		_online_list_view.set_demo_challenge_status({"state": "unknown"})

func _set_demo_status(used: int, limit: int, ids: Array) -> void:
	_demo_status = {"used": used, "limit": limit, "ids": ids}
	_online_list_view.set_demo_challenge_status({"state": "ok", "used": used, "limit": limit})

## 体験版のオンラインのボスとの戦闘を始めてよいか。挑戦済みのボスは確かめずに始める（何度でも挑戦できる）。
## 新しいボス（または使用状況が分からない時）は、先に挑戦の記録を送り、サーバーが受け付けた時だけ始める
## （その応答は RBMBattleResultReporter へ渡すので、挑戦は二重に送らない）。断られた・通信できなかった時は始めない
## （枠を使ったかどうか分からないまま戦闘だけ始めることはしない。同じボスで送り直しても、サーバーは二重に数えない）。
func _demo_challenge_gate(boss_id: String) -> bool:
	_demo_prefetched = {}
	var known_ids: Array = _demo_status.get("ids", [])
	if known_ids.has(boss_id):
		return true
	var limit := int(_demo_status.get("limit", RBMEdition.DEMO_MAX_ONLINE_CHALLENGED_BOSSES))
	# 15体に達していて、挑戦済みのボスを全部知っている（一覧の時に読んだ）時だけ、サーバーへ送らずに案内を出す。
	# 知らない挑戦済みのボスがある時は、サーバーに確かめる（挑戦済みのボスを手元で止めない）。
	var used := int(_demo_status.get("used", 0))
	if not _demo_status.is_empty() and used >= limit and known_ids.size() >= used:
		_show_demo_limit_notice()
		return false
	var response: Dictionary = await _online_recorder().record_challenge_attempt(boss_id)
	if bool(response.get("ok", false)):
		_demo_prefetched = {"boss_id": boss_id, "response": response}
		if response.has("demo_used"):
			var ids := known_ids.duplicate()
			if not ids.has(boss_id):
				ids.append(boss_id)
			_set_demo_status(int(response.get("demo_used", ids.size())), int(response.get("demo_limit", limit)), ids)
		return true
	match str(response.get("error_kind", "")):
		"demo_challenge_limit":
			_set_demo_status(int(response.get("demo_used", limit)), int(response.get("demo_limit", limit)), known_ids)
			_show_demo_limit_notice()
		"not_found":
			_show_demo_notice(tr("挑戦を始められませんでした"), [tr("このボスは公開が終わっているため、挑戦できません。")])
		_:
			_show_demo_notice(tr("挑戦を始められませんでした"), [
				tr("通信できなかったため、新しいボスへの挑戦を確認できませんでした。"),
				tr("時間をおいて、もう一度お試しください。"),
			])
	return false

func _show_demo_limit_notice() -> void:
	_show_demo_notice(tr("体験版のオンライン挑戦"), [
		tr("体験版で新しく挑戦できるボスは15体までです"),
		tr("挑戦済みのボスには何度でも再挑戦できます"),
		tr("製品版では、さらに多くのボスに挑戦できます"),
	])

## 体験版の案内（閉じるだけ）。見た目はホームの確認と同じ紺＋水色。
func _show_demo_notice(title_text: String, lines: Array) -> void:
	var style = preload("res://src/bossmaker/rbm_battle_hud_style.gd")
	if _demo_dialog == null:
		_demo_dialog = AcceptDialog.new()
		_demo_dialog.name = "DemoChallengeNotice"
		_demo_dialog.exclusive = true
		_demo_dialog.transient = true
		_demo_dialog.borderless = true  # 標準の灰色のタイトルの帯を出さない（見出しは本文の先頭に入れる）
		_demo_dialog.dialog_autowrap = true
		_demo_dialog.min_size = Vector2i(600, 240)
		_demo_dialog.add_theme_stylebox_override("panel", style._box(Color("091521"), style.CYAN_DIM, 1, -1, Vector4(24, 24, 24, 24)))
		add_child(_demo_dialog)
		style.label(_demo_dialog.get_label(), 17, style.TEXT)
		style.button(_demo_dialog.get_ok_button(), 16)
		_demo_dialog.get_ok_button().custom_minimum_size = Vector2(144, 44)
	_demo_dialog.title = title_text
	_demo_dialog.ok_button_text = tr("閉じる")
	_demo_dialog.dialog_text = "%s\n\n%s" % [title_text, "\n".join(lines)]
	_demo_dialog.popup_centered(Vector2i(600, 240))

## CHALLENGE UI再設計 §4-F/§10: 「クリア者数」記録——RBMChallengeBattleView
## 自身の勝敗判定ロジックには一切触れず、その一回性シグナルを観測するだけ。
## オンライン版「未挑戦」(2026-09): 挑戦開始時と同じ判定・同じベスト
## エフォート方針(§7)——記録API失敗でも勝利処理自体は正常に完了する。
func _on_challenge_won() -> void:
	if not _confirm_view.stage_id.is_empty():
		if _last_browse_was_online:
			# 2026-10-23: 戦闘チケットで結果を送り（送信待ちに入れてから）、応答（作者本人か・難関の認定）で討伐記録を決める。
			# 勝利の処理・結果の画面は待たない（await しない）。チケットが無ければ旧来のクリアの記録で決める。
			_result_reporter.on_battle_decided(true)
		else:
			RBMLocalStageRepository.record_challenge_clear(_confirm_view.stage_id)

## 旧来のクリアの記録（ベストエフォート）。応答を待ってから討伐記録を決める（2026-10-22）。2026-10-23 からは、
## 戦闘チケットの無い勝ち（通信できずに始めた戦闘・旧版のサーバー）と、サーバーが数えられないと答えた勝ちだけ。
## サーバーの clear_count は増えるが、挑戦者数・クリア率・難関ボス討伐には数えない。
func _record_online_clear_and_defeat(boss_id: String, context: Dictionary) -> void:
	var response: Dictionary = await _online_recorder().record_challenge_clear(boss_id)
	_record_defeat(context, server_by_owner(response), server_hard_awarded(response), server_first_clear_rate(response))

## 負けで決着した時（2026-10-23）: オンラインのボスなら、戦闘チケットで負けの結果を送る（挑戦者数・クリア率・難関ボス討伐の
## 「挑戦結果」。結果の画面は待たない）。手元に保存したボス・途中でやめた戦闘は送らない。討伐記録には関係しない。
func _on_challenge_lost() -> void:
	if _last_browse_was_online and not _confirm_view.stage_id.is_empty():
		_result_reporter.on_battle_decided(false)

## 討伐記録（RBMDefeatRecord）: 挑戦で勝った時、初めてのボスなら記録する（同じボスは何度勝っても1件）。
## TEST BATTLE・クリアチェックはこの経路を通らないので数えない。
## 2026-10-22: 自分が作ったボスは数えない。defeat_ownership() が「作者ではない」と決めた時だけ記録する。
## 2026-10-23: 難関はサーバーの認定（hard_awarded）だけでつける。rate はサーバーが残した初回クリア時のクリア率（無ければ
## 挑戦を始めた時の一覧の値）。
func _record_defeat(context: Dictionary, clear_by_owner: Variant, hard_awarded: bool = false, server_rate: Variant = null) -> void:
	if context.is_empty():
		return
	# 保存先を分けていないテスト（ヘッドレス）は、開発機の記録に書かない
	if _defeat_record_for_testing == null and DisplayServer.get_name() == "headless" and RBMLocalStageRepository._stages_dir_override.is_empty():
		return
	var decision := defeat_ownership([context.get("attempt_by_owner", null), clear_by_owner], bool(context.get("published_here", false)))
	context["ownership"] = decision
	if decision != DEFEAT_NOT_OWNER:
		return
	var rate: float = float(server_rate) if server_rate != null else float(context.rate)
	# 送り直した結果は、その戦闘の時刻で記録する（Steam Cloud との統合は早い方を残すため。2026-10-23）
	_defeat_book().record_clear(str(context.boss_id), str(context.mode), rate, int(context.get("at", -1)), hard_awarded)
	if is_visible_in_tree() and _hub_view.visible:
		_refresh_defeat_record()

## クリアの記録の応答から、難関ボス討伐に認定されているか（成功していて true の時だけ true）。
static func server_hard_awarded(response: Dictionary) -> bool:
	return bool(response.get("ok", false)) and response.get("hard_awarded", false) is bool and bool(response.get("hard_awarded", false))

## クリアの記録の応答から、初めてクリアした時のクリア率（成功していて数の時だけ。ほかは null）。
static func server_first_clear_rate(response: Dictionary) -> Variant:
	if not bool(response.get("ok", false)):
		return null
	var value: Variant = response.get("first_clear_rate", null)
	if value is float or value is int:
		return clampf(float(value), 0.0, 1.0)
	return null

## 挑戦・クリアの記録の応答から by_owner を取り出す。成功していて真偽値がある時だけその値、ほかは null（分からない）。
static func server_by_owner(response: Dictionary) -> Variant:
	if not bool(response.get("ok", false)):
		return null
	var value: Variant = response.get("by_owner", null)
	return value if value is bool else null

## 自分が作ったボスかの判定（2026-10-22）。サーバーの答え（by_owner。Steam で確かめた本人とボスの作者を DB が比べた結果）を
## 正とし、この PC で公開したボス（published_here）も作者とみなす。
##   作者だという答えが1つでもある・この PC で公開した → owner（ただし「作者ではない」という答えとも食い違えば conflict）
##   サーバーの答えが1つも無い → unknown
##   答えがすべて「作者ではない」で、この PC で公開したボスでもない → not_owner（これだけ討伐記録に数える）
static func defeat_ownership(server_answers: Array, published_here: bool) -> String:
	var says_owner := published_here
	var says_not_owner := false
	for answer in server_answers:
		if answer is bool:
			if answer:
				says_owner = true
			else:
				says_not_owner = true
	if says_owner and says_not_owner:
		return DEFEAT_CONFLICT
	if says_owner:
		return DEFEAT_OWNER
	if says_not_owner:
		return DEFEAT_NOT_OWNER
	return DEFEAT_UNKNOWN

## 今のアカウントの討伐記録。本物の Steam（アカウント・Steam Cloud）は、ゲームとして動いている時（窓があり、
## 保存先をテスト用に差し替えていない）だけ使う。それ以外は手元の LOCAL_ACCOUNT の記録だけ。
func _defeat_book() -> RBMDefeatRecord:
	if _defeat_record_for_testing != null:
		return _defeat_record_for_testing
	var real_steam := _uses_real_steam_records()
	var account := _online_recorder().account_id() if real_steam else RBMDefeatRecord.LOCAL_ACCOUNT
	if _defeat_record == null or _defeat_record.account_id != RBMDefeatRecord.sanitize_account(account):
		_defeat_record = RBMDefeatRecord.new(account, RBMSteamCloud.new() if real_steam else null)
	return _defeat_record

## テスト・検証用: 討伐記録を差し替える（偽のアカウント・偽の Steam Cloud）。
func set_defeat_record_for_testing(record: RBMDefeatRecord) -> void:
	_defeat_record_for_testing = record

## 挑戦トップに今のアカウントの討伐記録を出す。
func _refresh_defeat_record() -> void:
	var book := _defeat_book()
	book.load_records()
	_hub_view.set_defeat_counts(book.counts())
	# 届かなかった戦闘の結果があれば送り直す（間隔を空ける。2026-10-23）。応答で討伐記録が増えたら数を出し直す
	_result_reporter.flush_if_due()
	_maybe_sync_hard_awards(book)

## 今のアカウントの、戦闘の結果の送信待ち（2026-10-23）。討伐記録と同じアカウントの決め方。保存先を分けていない
## ヘッドレスのテストは、ファイルに書かずにメモリにだけ持つ（開発機の記録に書かない）。
func _result_outbox() -> RBMBattleResultOutbox:
	if _result_outbox_for_testing != null:
		return _result_outbox_for_testing
	var real_steam := _uses_real_steam_records()
	var account := RBMDefeatRecord.sanitize_account(_online_recorder().account_id() if real_steam else RBMDefeatRecord.LOCAL_ACCOUNT)
	var persist := real_steam or not RBMLocalStageRepository._stages_dir_override.is_empty()
	if _result_outbox_instance == null or _result_outbox_instance.account_id != account or _result_outbox_instance.persistent != persist:
		_result_outbox_instance = RBMBattleResultOutbox.new(account, persist)
	return _result_outbox_instance

## テスト・検証用: 送信待ちを差し替える。
func set_result_outbox_for_testing(outbox: RBMBattleResultOutbox) -> void:
	_result_outbox_for_testing = outbox

## 難関ボス討伐の認定を受け取りに行く最短の間隔（2026-10-23。Supabase の無料枠への負荷を抑える）。
const HARD_AWARD_SYNC_INTERVAL_MSEC := 10 * 60 * 1000
var _hard_award_sync_at_msec := -1
var _hard_award_sync_running := false

## 難関がまだついていない記録がある時だけ、サーバーの認定（さかのぼった認定を含む）を受け取りに行く（2026-10-23）。
## 本物の Steam を使う時（ゲーム）か、テスト・検証が記録を差し替えた時だけ。間隔を空け、同時に2回は行かない。
func _maybe_sync_hard_awards(book: RBMDefeatRecord) -> void:
	if _hard_award_sync_running or not book.has_unawarded_entries():
		return
	if _defeat_record_for_testing == null and not _uses_real_steam_records():
		return
	if _hard_award_sync_at_msec >= 0 and Time.get_ticks_msec() - _hard_award_sync_at_msec < HARD_AWARD_SYNC_INTERVAL_MSEC:
		return
	_hard_award_sync_at_msec = Time.get_ticks_msec()
	_sync_hard_awards(book)

func _sync_hard_awards(book: RBMDefeatRecord) -> void:
	_hard_award_sync_running = true
	var response: Dictionary = await _online_recorder().list_my_hard_awards()
	_hard_award_sync_running = false
	if not bool(response.get("ok", false)) or not (response.get("boss_ids", null) is Array):
		return
	if book.mark_hard(response["boss_ids"]) > 0 and is_inside_tree() and _hub_view.visible:
		_hub_view.set_defeat_counts(book.counts())

## 討伐記録に本物の Steam（アカウント・Steam Cloud）を使うか: ゲームとして動いている時（窓があり、保存先をテスト用に差し替えていない）。
func _uses_real_steam_records() -> bool:
	return DisplayServer.get_name() != "headless" and RBMLocalStageRepository._stages_dir_override.is_empty()

func _on_battle_returned_to_list() -> void:
	# 戦闘チケットの控えを閉じる（届いていない結果は送信待ちに残る。2026-10-23）
	_result_reporter.end_challenge()
	# Phase 4D-1: オンライン一覧経由で挑戦した場合は、戦闘終了後もオンライン
	# 一覧側へ戻す(ローカルの_list_panelへ迷い込ませない)。
	if _last_browse_was_online:
		_show_online_browse()
	else:
		_show_browse()

# ---------------------------------------------------------------------------
# Step 8 §5: 共通ルートとの接続
# ---------------------------------------------------------------------------

func _on_back_to_root_pressed() -> void:
	_battle_view.release_presentations()
	exit_requested.emit()

## §5: 共通ルートがCHALLENGEへ入るたびに呼ぶ公開エントリポイント。
## CHALLENGE UI再設計 §2: 「挑戦」を押すといきなり一覧/検索画面へ遷移させず、
## 挑戦ハブを必ず表示する。
func enter_challenge() -> void:
	_show_hub()

# ---------------------------------------------------------------------------

func _show_hub() -> void:
	_hub_view.visible = true
	_online_list_view.visible = false
	_list_panel.visible = false
	_confirm_view.visible = false
	_battle_view.visible = false
	_update_battle_preparation()
	if is_visible_in_tree():
		_refresh_defeat_record()

## §7〜§17: 一覧と詳細は常に同時に表示される（旧_show_list/_show_confirmの
## 統合）——選択の有無はConfirmViewの空状態/詳細表示の切り替えでのみ表現し、
## 画面遷移としては扱わない。
func _show_browse() -> void:
	_hub_view.visible = false
	_online_list_view.visible = false
	_list_panel.visible = true
	_confirm_view.visible = true
	_battle_view.visible = false
	_last_browse_was_online = false
	_update_battle_preparation()

func _show_battle() -> void:
	_hub_view.visible = false
	_online_list_view.visible = false
	_list_panel.visible = false
	_confirm_view.visible = false
	_battle_view.visible = true
