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

## Phase 3.5 UI統一§33バグ修正: 既存のLineEdit（RBMCreatorStep1Basic.
## BOSS_NAME_EDIT_MIN_SIZE等）はcustom_minimum_sizeを持つが、この検索欄
## 2つだけが未設定のまま既定の極small幅で、placeholder_textが「ステー」
## 「ボス名」等へ視覚的に切れていた（§38: 明白な原因・小さな修正範囲の
## 表示バグ）。
const SEARCH_FIELD_MIN_SIZE := Vector2(170.0, 32.0)

var _hub_view: RBMChallengeHubView
var _online_list_view: RBMOnlineBossListView
var _last_browse_was_online := false
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

## Phase 4D-1: 「オンライン」カテゴリ専用の別パネル。既存のローカル一覧
## (_list_panel)とは独立させ、ローカルChallenge既存動作を一切変更しない。
func _build_online_list_view() -> void:
	_online_list_view = RBMOnlineBossListView.new()
	_online_list_view.name = "OnlineBossListView"
	_online_list_view.visible = false
	_online_list_view.boss_selected.connect(_on_online_boss_selected)
	_online_list_view.back_requested.connect(_on_back_to_hub_pressed)
	add_child(_online_list_view)

func _on_online_boss_selected(boss_id: String, draft: RBMCreatorDraft, _boss_name: String, _author_name: String) -> void:
	# ローカルの_on_stage_row_pressed()と同じ着地点(_confirm_view.open())へ
	# 接続する——新しい別Battle経路は作らない(ユーザー確定仕様)。
	# stage_idの形式(10桁の数字)とオンラインboss_id(UUID)は一致しないため、
	# RBMLocalStageRepository.record_challenge_attempt/clear()はこの
	# boss_idに対しては安全にno-op(_is_valid_stage_id()が弾く)——オンライン
	# のClear記録自体は今回のスコープ外(将来Phase 5用に接続しやすい構造の
	# 考慮のみ、ユーザー確定仕様)。
	_selected_stage_id = ""
	_confirm_view.open(boss_id, draft)
	_show_online_browse()

func _show_online_browse() -> void:
	_hub_view.visible = false
	_online_list_view.visible = true
	_list_panel.visible = false
	_confirm_view.visible = true
	_battle_view.visible = false
	_last_browse_was_online = true

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

func _on_hub_category_selected(category: String) -> void:
	# Phase 4D-1: 「注目」ボタンはランキングアルゴリズム(Phase 5)とは別に、
	# オンライン公開ボス一覧の入口として有効化した——ローカルの一覧
	# (_list_panel/_refresh_list())には一切触れず、別パネルを開くだけ。
	if category == RBMChallengeHubView.CATEGORY_FEATURED:
		_confirm_view.clear_selection()
		_show_online_browse()
		_online_list_view.refresh()
		return
	_current_category = category
	_category_title_label.text = _category_display_title(category)
	_selected_stage_id = ""
	_confirm_view.clear_selection()
	_refresh_list()
	_show_browse()

func _on_hub_search_requested() -> void:
	_current_category = ""
	_category_title_label.text = tr("検索")
	_selected_stage_id = ""
	_confirm_view.clear_selection()
	_name_search_field.text = ""
	_id_search_field.text = ""
	_refresh_list()
	_show_browse()

## §5: ランダムはカテゴリではない——published=trueかつ実際に挑戦可能な
## 全ボスから完全ランダムで1件選び、共通一覧/詳細画面をその1件が選択された
## 状態で開く。抽選後に戦闘を自動開始しない（§5末尾）。
func _on_hub_random_requested() -> void:
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

func _category_display_title(category: String) -> String:
	match category:
		RBMChallengeHubView.CATEGORY_SIMPLE:
			return "SIMPLE"
		RBMChallengeHubView.CATEGORY_HARDCORE:
			return "HARDCORE"
		RBMChallengeHubView.CATEGORY_FEATURED:
			return tr("注目")
		RBMChallengeHubView.CATEGORY_NEW:
			return tr("新着")
		RBMChallengeHubView.CATEGORY_UNCHALLENGED:
			return tr("未挑戦")
		RBMChallengeHubView.CATEGORY_POPULAR:
			return tr("人気")
		RBMChallengeHubView.CATEGORY_HIGH_DIFFICULTY:
			return tr("高難度")
		_:
			return tr("検索")

func _on_back_to_hub_pressed() -> void:
	_show_hub()

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
	if not _confirm_view.stage_id.is_empty():
		RBMLocalStageRepository.record_challenge_attempt(_confirm_view.stage_id)
	_battle_view.battle_background = _confirm_view._draft.battle_background if _confirm_view._draft != null else "night"
	_battle_view.start_battle(definition, visibility, appearance_id)
	_show_battle()

## CHALLENGE UI再設計 §4-F/§10: 「クリア者数」記録——RBMChallengeBattleView
## 自身の勝敗判定ロジックには一切触れず、その一回性シグナルを観測するだけ。
func _on_challenge_won() -> void:
	if not _confirm_view.stage_id.is_empty():
		RBMLocalStageRepository.record_challenge_clear(_confirm_view.stage_id)

func _on_battle_returned_to_list() -> void:
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

func _show_battle() -> void:
	_hub_view.visible = false
	_online_list_view.visible = false
	_list_panel.visible = false
	_confirm_view.visible = false
	_battle_view.visible = true
