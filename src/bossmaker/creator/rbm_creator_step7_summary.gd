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
## 下部バーは「← 戻る」（左）／「保存」「オンライン公開」（右）のみ——RBMCreatorMain
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
## §24〜§27（公開機能、ユーザー確定仕様）: 保存は常に無条件で可能。
##
## 公開UI整理（ユーザー指示、2026-09-10）: ローカル公開（旧「公開」/
## 「公開を取り下げる」ボタン、RBMCreatorMain.press_publish()/
## press_unpublish()）はユーザー向けUIから廃止した——このSTEPからはもう
## 呼ばれない。ただし関数自体・draft.publish()/unpublish()/is_published()・
## ローカルCHALLENGE一覧側の可視化条件は一切削除・変更していない（既存の
## ローカル保存機能そのものは残す、という指示どおり）。UIには単一の
## オンライン公開ボタンだけが残り、未公開なら「オンライン公開」、
## オンライン公開中なら「公開を取り下げる」に表示・処理を切り替える
## （_refresh_publish_online_button()参照）。

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

## 公開UI整理: 公開系ボタンはこの1つだけ——未公開なら「オンライン公開」、
## オンライン公開中なら「公開を取り下げる」に文言・処理を切り替える。
## Clear Check判定はこのUI自身では持たず、draft.is_clear_check_currently_
## valid()を都度参照する(RBMOnlineBossPayload.build_for_publish()が公開
## 実行時に同じ判定を再度行う——ここは表示専用の重複)。
var _publish_online_button: Button
var _online_status_label: Label
var _online_unavailable_label: Label
var _boss_publisher: RBMBossPublisher

## オンライン公開状態そのもの（真偽値/online_boss_id）はdraft側
## （RBMCreatorDraft.is_online_published()/online_boss_id()、to_saved_dict()/
## restore_from_saved_dict()で保存/復元される）に持たせている——Creatorを
## 閉じて再度開いても「公開を取り下げる」/「オンライン公開」の出し分けが
## 復元される。完全にオンライン管理用メタデータとして扱い、
## battle_content_snapshot()/Clear Check判定には一切含めない
## （rbm_creator_draft.gd参照）。このビュー自身は状態を持たず、
## publish()/unpublish()成功のたびにdraft側を更新→即座に上書き保存する
## だけ（_persist_online_state()参照）。

## サーバー同期（ユーザー確定仕様、2026-09-11）: online_publishedは
## ローカルキャッシュに過ぎず、最終的な正はSupabase側。online_boss_idが
## 存在する保存済みstageをこの画面で初めて表示した時（＝Creatorで保存済み
## stageを開いた時）に一度だけget-boss経由でサーバー側の実際の公開状態を
## 確認し、キャッシュ/UIを同期する（_sync_online_state_from_server()参照）。
## 確認できなかった場合（通信失敗等）はローカル値を一切書き換えない——
## trueのままfalseにも、falseのままtrueにも絶対にしない。
var _online_state_synced := false

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
	## HFlowContainer（HBoxContainerではない）: 英語ロケールでは各ラベル
	## （"Publish Online"等）が日本語よりずっと長くなり、1行合計が1280px
	## 幅に収まらずビューポート右端で見切れる（切れる/はみ出す）ことが
	## 英語UI検証で判明したため、収まらない場合だけ自動折返しする
	## HFlowContainerへ変更した。日本語は1行に収まる長さのままなので、
	## 見た目・挙動は変えない。
	var bottom_bar := HFlowContainer.new()
	bottom_bar.name = "SummaryBottomBar"
	bottom_bar.add_theme_constant_override("h_separation", 16)
	bottom_bar.add_theme_constant_override("v_separation", 8)
	outer.add_child(bottom_bar)

	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.text = "← 戻る"
	back_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	back_button.pressed.connect(func(): main.press_back())
	bottom_bar.add_child(back_button)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(bottom_spacer)

	_save_button = Button.new()
	_save_button.name = "SaveButton"
	_save_button.text = "保存"
	_save_button.pressed.connect(func(): main.press_save())
	bottom_bar.add_child(_save_button)

	## Phase 4C→公開UI整理: 公開系はこのオンライン公開ボタン1つだけ。押した
	## 結果はSupabase/Steam認証まで進む——正式Steam AppID未発行の間は
	## is_steam_available()==falseとなるため、ボタン自体をdisabledにし
	## （クリックして失敗させない、ユーザー指示）、_online_unavailable_label
	## で理由を示す。
	_online_status_label = Label.new()
	_online_status_label.name = "OnlinePublishStatusLabel"
	bottom_bar.add_child(_online_status_label)

	_online_unavailable_label = Label.new()
	_online_unavailable_label.name = "OnlineUnavailableLabel"
	_online_unavailable_label.text = tr("オンライン公開は現在利用できません")
	_online_unavailable_label.add_theme_color_override("font_color", RBMUiTheme.COLOR_TEXT_SECONDARY)
	bottom_bar.add_child(_online_unavailable_label)

	_publish_online_button = Button.new()
	_publish_online_button.name = "PublishOnlineButton"
	_publish_online_button.text = tr("オンライン公開")
	_publish_online_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	_publish_online_button.pressed.connect(_on_publish_online_button_pressed)
	bottom_bar.add_child(_publish_online_button)

	_build_persistent_controls()

## GUT専用: 実Steam/実Supabaseへ触れないfakeへ差し替える。
func set_boss_publisher_for_testing(publisher: RBMBossPublisher) -> void:
	_boss_publisher = publisher

func _ensure_boss_publisher() -> void:
	if _boss_publisher == null:
		_boss_publisher = RBMBossPublisher.new()
		add_child(_boss_publisher)

## ボタン1つで未公開/公開済みの両方を扱う——現在の状態(draft.is_online_
## published())を見て実際の処理を振り分けるだけの薄いディスパッチャ。
func _on_publish_online_button_pressed() -> void:
	if draft.is_online_published():
		_on_unpublish_online_pressed()
	else:
		_on_publish_online_pressed()

func _on_publish_online_pressed() -> void:
	_ensure_boss_publisher()
	if _boss_publisher.current_state() == RBMBossPublisher.PublishState.REQUESTING_TICKET or \
			_boss_publisher.current_state() == RBMBossPublisher.PublishState.UPLOADING:
		return
	_online_status_label.text = tr("公開中...")
	var ok: bool = await _boss_publisher.publish(draft, draft.online_boss_id())
	if ok:
		draft.set_online_boss_id(_boss_publisher.last_boss_id())
		draft.set_online_published(true)
		_persist_online_state()
		_online_status_label.text = tr("オンライン公開に成功しました。")
	else:
		_online_status_label.text = _online_publish_failure_message(_boss_publisher.last_error_kind(), _boss_publisher.last_error_message())
	_refresh_publish_online_button()

## ソフト取り下げ——RBMBossApiAdapter.unpublish()（DB上のデータは削除せず
## is_published=falseへ戻す既存のサーバ側実装）へ接続する。boss_idは
## 直前に成功したpublish()から得たものをそのまま使う——再度publish()を
## 呼べば同じboss_idを渡すため、サーバ側は既存レコードを復活させる形に
## なる（新規重複投稿にはならない）。
func _on_unpublish_online_pressed() -> void:
	_ensure_boss_publisher()
	if _boss_publisher.current_state() == RBMBossPublisher.PublishState.REQUESTING_TICKET or \
			_boss_publisher.current_state() == RBMBossPublisher.PublishState.UPLOADING:
		return
	_online_status_label.text = tr("取り下げ中...")
	var ok: bool = await _boss_publisher.unpublish(draft.online_boss_id())
	if ok:
		# online_boss_idはそのまま保持する（ユーザー確定仕様）——falseに
		# するのは公開状態だけ、同じidで再度publish()できるようにする。
		draft.set_online_published(false)
		_persist_online_state()
		_online_status_label.text = tr("オンライン公開を取り下げました。")
	else:
		_online_status_label.text = _online_publish_failure_message(_boss_publisher.last_error_kind(), _boss_publisher.last_error_message())
	_refresh_publish_online_button()

## publish()/unpublish()成功直後、online_boss_id/online_publishedを即座に
## ディスクへ書き残す——ローカル公開のpress_publish()と同じ「未保存のまま
## でも実効を持つ操作は自動的に保存する」既存方針を踏襲する（保存自体は
## 通常のRBMLocalStageRepository.overwrite()/save_new()、save形式・
## Clear Check・battle_hashには一切触れない、著作フィールドの1つが増えた
## だけ）。
func _persist_online_state() -> void:
	if main.current_stage_id.is_empty():
		main.press_save_as_new()
	else:
		main.press_overwrite_save()

## サーバー同期（ユーザー確定仕様、2026-09-11）: RBMBossPublisher.
## check_online_published()（get-boss、Steamチケット不要）でサーバー側の
## 実際の公開状態を確認し、ローカルキャッシュ(draft.is_online_published())
## と食い違っていれば更新して保存する。確認できなかった場合
## ("unknown" — 通信失敗/タイムアウト/5xx/その他の4xx等）はローカル値・
## online_boss_idとも一切書き換えず、確認できなかった旨だけ表示する
## （「非公開と確認できた」と「サーバーへ接続できなかった」を混同しない、
## 最重要のユーザー確定仕様）。
func _sync_online_state_from_server() -> void:
	_ensure_boss_publisher()
	_online_status_label.text = tr("オンライン状態を確認中...")
	var result := await _boss_publisher.check_online_published(draft.online_boss_id())
	match str(result.get("state", "unknown")):
		"published":
			if not draft.is_online_published():
				draft.set_online_published(true)
				_persist_online_state()
			_online_status_label.text = tr("オンライン公開中")
		"not_published":
			if draft.is_online_published():
				draft.set_online_published(false)
				_persist_online_state()
			_online_status_label.text = tr("オンライン未公開")
		_:
			_online_status_label.text = tr("オンライン状態を確認できません")
	_refresh_publish_online_button()

## ボタンの文言/disabled、利用不可メッセージの表示切替をまとめる。
## Steam利用不可時はクリックして失敗させるのではなくdisabledにする
## （ユーザー指示）。公開済み状態からの取り下げは、内容編集でClear Check
## が無効化されていても押せるようにする（取り下げ自体をブロックしない）。
func _refresh_publish_online_button() -> void:
	_ensure_boss_publisher()
	var steam_ok := _boss_publisher.is_steam_available()
	_online_unavailable_label.visible = not steam_ok
	if draft.is_online_published():
		_publish_online_button.text = tr("公開を取り下げる")
		_publish_online_button.disabled = not steam_ok
	else:
		_publish_online_button.text = tr("オンライン公開")
		_publish_online_button.disabled = not steam_ok or not draft.is_clear_check_currently_valid()

## §4C-7: 公開中/公開成功/認証失敗/通信失敗/validation失敗/Steam利用不可/
## 正式Steam認証未設定を、ユーザーへ分かる形で表示する。大規模なUI再設計
## はしない——既存の1行ラベルへ短い日本語文を出すだけ。
func _online_publish_failure_message(error_kind: String, detail: String) -> String:
	match error_kind:
		"clear_check_not_valid":
			return tr("クリアチェックを再確認してください。")
		"steam_unavailable":
			return tr("Steamが利用できません。Steamを起動してログインしてください。")
		"steam_not_logged_on":
			return tr("Steamにログインしていません。")
		"steam_ticket_request_failed", "steam_ticket_failed":
			return tr("Steam認証チケットの取得に失敗しました。")
		"not_configured":
			return tr("オンライン公開はまだ準備中です（正式Steam認証の設定待ち）。")
		"forbidden":
			return tr("この投稿を更新する権限がありません。")
		"not_found":
			return tr("投稿先が見つかりませんでした。")
		"network_error", "http_5xx":
			return tr("通信に失敗しました。しばらくしてからもう一度お試しください。")
		"http_4xx", "invalid_payload", "payload_too_large":
			return tr("送信内容に問題がありました。")
		_:
			return tr("オンライン公開に失敗しました（%s）。") % (error_kind if detail.is_empty() else detail)

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

	if _online_status_label.text.is_empty():
		_online_status_label.text = tr("オンライン公開中") if draft.is_online_published() else tr("オンライン未公開")
	_refresh_publish_online_button()

	## この画面を初めて表示した時（＝保存済みstageをCreatorで開いた直後を
	## 含む）に一度だけ、online_boss_idがあればサーバー側の実際の公開状態を
	## 確認する。_online_state_syncedを先に立ててから非同期処理へ入るため、
	## 完了前にrefresh()が再度呼ばれても二重に問い合わせない。
	if not _online_state_synced and not draft.online_boss_id().is_empty():
		_online_state_synced = true
		_sync_online_state_from_server()

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
	var bottom: HFlowContainer = find_child("SummaryBottomBar",true,false)
	if bottom == null: return
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
