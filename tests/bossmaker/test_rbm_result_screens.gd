extends GutTest

## 戦闘の結果・クリアチェックの開始・保存の画面（2026-10-18 ユーザーの決定: 戦闘の結果は案C「シネマティック」、
## クリアチェックと保存は案A「王道RPG」）の回帰テスト。
## - 挑戦・TEST BATTLE: 見出しは CLEAR / DEFEAT（VICTORY ではない）、「○○を倒した！」・数字の行、ボタンは下の帯の右に
##   枠付きで（試作の文字だけのボタンは薄くて見づらかった）
## - クリアチェック: 見出し CLEAR! / FAILED…、成功の一言は「クリアチェックが完了しました。」、成功の時は「もう一度挑戦」を出さない
## - 開始の画面: ボスの肖像・会話の窓・「▶」のメニュー（開始するが上）、公開の条件の文は事実どおり
## - 保存の画面: 「ぼうけんのしょ」は出さない、保存するボスの窓、公開の案内はクリアチェックを通って未公開の時だけ
## - 新しい文の英語が翻訳の表にある
## 戦闘の計算・乱数・保存の形には触れない（画面の表示だけを確かめる）。

var _dir := ""

func before_each() -> void:
	_dir = "user://bossmaker_test_result_screens/stages"
	RBMLocalStageRepository.set_stages_dir_for_testing(_dir)
	_clear_dir(_dir)

func after_each() -> void:
	_clear_dir(_dir)
	RBMLocalStageRepository.set_stages_dir_for_testing("")
	await get_tree().process_frame

func _clear_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))

func _btn(root: Node, node_name: String) -> Button:
	return root.find_child(node_name, true, false) as Button

func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame

## 結果の画面の飾りが出そろうまで待つ（後から出る飾りは出る時に作る。案Cの制作者の行が 1.9 秒、案Aの味方が 1.4 秒）。
func _settle() -> void:
	await _frames()
	await get_tree().create_timer(2.4).timeout
	await _frames()

func _draft(boss_name: String, strong: bool) -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	_setup(draft, boss_name, strong)
	return draft

## strong: 必ず負けるボス（test_rbm_clear_check.gd の _fill_guaranteed_loss_boss と同じ形）。それ以外は一撃で倒せるボス。
func _setup(draft: RBMCreatorDraft, boss_name: String, strong: bool) -> void:
	draft.boss_name = boss_name
	draft.hp = 99999 if strong else 1
	draft.atk = 9999 if strong else 1
	draft.spd = 1
	if strong:
		var skill_id := draft.add_skill({"name": "猛攻", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 100.0})
		draft.normal_actions_enabled = true
		draft.normal_action_percentages[skill_id] = 100.0
	draft.add_party_character("hero")

func _new_main() -> RBMCreatorMain:
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	# 実際のゲームと同じく画面全体の大きさにする（位置・画面の中かを確かめるため）
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	return main

func _fill(main: RBMCreatorMain, strong: bool) -> void:
	_setup(main.draft, "結果テストボス", strong)

## 決着するまで「通常攻撃」を押す（強いボスは1ターンでは決着しない）。
func _fight_until_over(view: Control) -> void:
	for i in 40:
		if view.session == null or view.session.battle == null or view.session.battle.battle_over:
			return
		var b := _btn(view, "AttackButton")
		if b == null:
			return
		b.pressed.emit()

func _deco(view: Control) -> Control:
	return (view.get("_outcome_area") as Control).get_node_or_null("ResultDecoration") as Control

func _text_of(root: Node, node_name: String) -> String:
	var l := root.find_child(node_name, true, false) as Label
	return l.text if l != null else "<none>"

func _all_texts(root: Node) -> String:
	var out := PackedStringArray()
	for n in root.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	for n in root.find_children("*", "Button", true, false):
		out.append((n as Button).text)
	return "\n".join(out)

func _inside_screen(c: Control) -> bool:
	return c.is_visible_in_tree() and Rect2(0, 0, 1280, 720).encloses(c.get_global_rect())

## 案Cの下の帯のボタン: 帯の中・画面の中・枠付き（下地のある見た目）・読める大きさ。
func _assert_bar_button(b: Button, primary: bool, what: String) -> void:
	assert_true(_inside_screen(b), what + ": 画面の中")
	assert_gte(b.get_global_rect().position.y, 720.0 - 92.0, what + ": 下の黒い帯の中")
	var normal := b.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(normal, what + ": 枠と下地のあるボタン（文字だけではない）")
	if normal != null:
		assert_gt(normal.bg_color.a, 0.5, what + ": 下地がある")
		assert_gt(normal.get_border_width(SIDE_LEFT), 0, what + ": 枠がある")
	assert_gte(b.get_theme_font_size("font_size"), 20 if primary else 18, what + ": 読める大きさ")
	assert_eq(b.get_theme_color("font_color"), RBMChallengeListStyle.TEXT, what + ": 明るい文字")

# =============================================================================
# 挑戦（案C）
# =============================================================================

func test_challenge_victory_shows_clear_headline_stats_and_bar_buttons() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	view.result_mode = RBMCreatorDraft.CREATOR_MODE_SIMPLE
	view.result_author = "テスト作者"
	view.start_battle(_draft("一撃のボス", false).to_definition())
	_fight_until_over(view)
	await _settle()
	assert_true(view.session.battle.battle_over and view.session.battle.winner == "ally", "sanity: 一撃で勝つ")
	assert_true(view._outcome_area.visible)
	assert_eq(view._outcome_label.text, "CLEAR", "見出しは CLEAR（VICTORY ではない）")
	assert_eq(view._outcome_label.get_theme_font_size("font_size"), 76, "大きな見出し")
	var deco := _deco(view)
	assert_not_null(deco, "結果の画面の飾りが出る")
	assert_eq(_text_of(deco, "ResultSubtitle"), "一撃のボス を倒した！")
	var stats := _text_of(deco, "ResultStats")
	assert_true(stats.contains("撃破ターン") and stats.contains("1"), "撃破ターンの数字: " + stats)
	assert_true(stats.contains("SIMPLE"), "挑戦モード: " + stats)
	assert_false(stats.contains("クリアタイム"), "勝利演出が無い時はクリアタイムを作らない")
	assert_eq(_text_of(deco, "ResultAuthor"), "制作  テスト作者")
	assert_not_null(deco.find_child("BottomBar", true, false), "下の黒い帯")
	_assert_bar_button(view._retry_button, true, "もう一度挑戦")
	_assert_bar_button(view._return_button, false, "挑戦一覧へ")
	assert_lt(view._retry_button.position.x, view._return_button.position.x, "主の操作（もう一度挑戦）が左、挑戦一覧へが右")
	assert_eq(view._retry_button.text, "もう一度挑戦")
	assert_eq(view._return_button.text, "挑戦一覧へ")

func test_challenge_defeat_shows_defeat_and_fallen_turn() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	view.start_battle(_draft("強いボス", true).to_definition())
	_fight_until_over(view)
	await _settle()
	assert_true(view.session.battle.battle_over and view.session.battle.winner == "boss", "sanity: 負ける")
	assert_eq(view._outcome_label.text, "DEFEAT")
	var deco := _deco(view)
	assert_eq(_text_of(deco, "ResultSubtitle"), "全滅してしまった……")
	assert_true(_text_of(deco, "ResultStats").contains("倒れたターン"))
	assert_null(deco.find_child("ResultAuthor", true, false), "制作者が分からない時は行を作らない")
	_assert_bar_button(view._retry_button, true, "もう一度挑戦（負け）")

func test_result_decoration_is_rebuilt_once_and_removed_when_hidden() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	await get_tree().process_frame
	view.start_battle(_draft("一撃のボス", false).to_definition())
	_fight_until_over(view)
	await _settle()
	view.refresh()
	view.refresh()
	await _frames()
	var decos := view._outcome_area.find_children("ResultDecoration", "", false, false)
	assert_eq(decos.size(), 1, "何度 refresh しても飾りは1つ")
	view._do_restart()
	await _frames()
	assert_false(view._outcome_area.visible)
	assert_null(_deco(view), "結果を閉じたら飾りは残らない")
	assert_eq(view._outcome_area.modulate.a, 1.0)

# =============================================================================
# TEST BATTLE（案C）
# =============================================================================

func test_test_battle_victory_uses_clear_and_back_to_creator() -> void:
	var main := await _new_main()
	_fill(main, false)
	main.draft.boss_name = "一撃のボス"
	var view := main._test_battle_view
	assert_true(bool(main.press_test_battle().get("ok", false)), "sanity")
	await _frames()
	_fight_until_over(view)
	await _settle()
	assert_eq((view._outcome_area.get_node("OutcomeLabel") as Label).text, "CLEAR")
	assert_eq(view._return_button.text, "作成画面へ戻る", "日本語の画面に「Creator」を混ぜない")
	var deco := _deco(view)
	assert_eq(_text_of(deco, "ResultSubtitle"), "一撃のボス を倒した！")
	assert_null(deco.find_child("ResultAuthor", true, false), "TEST BATTLE は制作者の行を出さない")
	_assert_bar_button(view._retry_button, true, "もう一度テスト")
	_assert_bar_button(view._return_button, false, "作成画面へ戻る")

# =============================================================================
# クリアチェック（案A）
# =============================================================================

func test_clear_check_success_shows_rpg_result_with_completed_note() -> void:
	var main := await _new_main()
	_fill(main, false)
	main.press_clear_check()
	assert_true(bool(main.press_clear_check_start().get("ok", false)), "sanity")
	var view := main._clear_check_view
	_fight_until_over(view)
	await _settle()
	assert_true(view.session.battle.winner == "ally", "sanity")
	var deco := _deco(view)
	assert_eq(_text_of(deco, "ResultTitle"), "CLEAR!")
	assert_eq(view._outcome_label.text, "クリアチェック成功")
	assert_eq(_text_of(deco, "ResultNote"), "クリアチェックが完了しました。", "成功の一言（2026-10-18 ユーザーの指定）")
	assert_false(_all_texts(view).contains("このボスは倒せることを確かめました"))
	assert_eq(_text_of(deco, "WindowTitle"), "戦闘結果")
	assert_false(view._retry_button.visible, "成功の時は「もう一度挑戦」を出さない（今までどおり）")
	assert_eq(view._return_button.text, "最終確認へ（保存・公開）")
	assert_not_null(deco.find_child("MenuCursor", true, false), "「▶」で選ぶメニュー")
	assert_true(_inside_screen(view._return_button))

func test_clear_check_failure_offers_retry_and_advice() -> void:
	var main := await _new_main()
	_fill(main, true)
	main.press_clear_check()
	assert_true(bool(main.press_clear_check_start().get("ok", false)), "sanity")
	var view := main._clear_check_view
	_fight_until_over(view)
	await _settle()
	assert_true(view.session.battle.winner == "boss", "sanity")
	var deco := _deco(view)
	assert_eq(_text_of(deco, "ResultTitle"), "FAILED…")
	assert_eq(view._outcome_label.text, "クリアチェック失敗")
	assert_eq(_text_of(deco, "ResultNote"), "ボスが強すぎる時は、能力（HP・ATK）か行動を見直しましょう")
	assert_true(view._retry_button.visible)
	assert_eq(view._return_button.text, "作成画面へ戻る")
	assert_lt(view._retry_button.position.y, view._return_button.position.y, "もう一度挑戦が上、戻るが下")
	assert_true(_inside_screen(view._retry_button) and _inside_screen(view._return_button))

func test_clear_check_start_screen_is_rpg_dialog_with_start_first() -> void:
	var main := await _new_main()
	_fill(main, false)
	main.press_clear_check()
	await _frames()
	var view := main._clear_check_view
	assert_true(view._confirm_panel.visible)
	assert_eq(view._confirm_panel.get_global_rect(), Rect2(0, 0, 1280, 720), "開始の画面は画面全体")
	assert_eq(view._confirm_boss_name_label.text, "結果テストボス")
	assert_not_null(view._confirm_panel.find_child("ConfirmPortraitWindow", true, false))
	assert_not_null(view._confirm_panel.find_child("ConfirmDialogWindow", true, false))
	assert_not_null(view._confirm_panel.find_child("Backdrop", true, false), "ボスの戦闘背景を敷く")
	var start := _btn(view, "ConfirmStartButton")
	var back := _btn(view, "ConfirmBackButton")
	assert_eq(start.text, "開始する")
	assert_lt(start.position.y, back.position.y, "主の操作（開始する）が上、戻るが下（保存の画面と同じ並び）")
	var texts := _all_texts(view._confirm_panel)
	assert_true(texts.contains("クリアチェックを通ると、オンラインに公開できます"), "公開の条件（保存はクリアチェック無しでもできる）")
	assert_false(texts.contains("保存・公開できます"), "保存にクリアチェックが要るような文にしない")
	assert_false(view._confirm_random_notice_label.visible, "ランダムな行動が無いボスでは出さない")
	# 出方の途中で開き直しても、窓の位置はずれず、背景も重ならない。メニューが出たら「開始する」にフォーカス。
	view._on_confirm_back_pressed()
	main.press_clear_check()
	await _frames(2)
	main.press_clear_check()
	await get_tree().create_timer(2.1).timeout
	assert_eq(view._confirm_panel.find_child("ConfirmBackdrop", true, false).get_child_count(), 2, "背景の絵と幕だけ（開くたびに足さない）")
	assert_eq(view._confirm_portrait.position, Vector2(70, 70), "肖像の窓は決まった位置")
	assert_eq(view._confirm_menu.position, Vector2(880, 320), "メニューの窓は決まった位置")
	assert_true(start.has_focus(), "最初のフォーカスは「開始する」（メニューが出た後）")

# =============================================================================
# 保存（案A）
# =============================================================================

func test_save_screen_has_no_adventure_log_and_shows_the_boss_window() -> void:
	var main := await _new_main()
	_fill(main, false)
	main.press_save()
	await _frames()
	var save := main._save_view
	assert_eq(save.get_global_rect(), Rect2(0, 0, 1280, 720), "保存の画面は画面全体")
	assert_false(_all_texts(save).contains("ぼうけんのしょ"), "「ぼうけんのしょ」は出さない（2026-10-18 ユーザーの指定）")
	assert_eq(_text_of(save._choice_panel, "SaveTitleLabel"), "保存")
	assert_eq(save._boss_name_label.text, "結果テストボス")
	assert_eq(_text_of(save, "ClearCheckStatus"), "・未達成")
	assert_eq(_text_of(save, "PublishStatus"), "・オンライン未公開")
	assert_true(save._save_new_button.visible)
	assert_true(_inside_screen(save._save_new_button) and _inside_screen(save._back_button))
	assert_lt(save._save_new_button.position.y, save._back_button.position.y, "保存するが上、戻るが下")
	save._on_save_new_pressed()
	await _frames()
	assert_true(save._success_panel.visible)
	assert_eq(_text_of(save._success_panel, "SaveSuccessTitleLabel"), "保存しました")
	assert_eq(save._success_stage_id_label.text, "ステージID：%s" % main.current_stage_id)
	assert_false(save._publish_hint_label.visible, "クリアチェックを通っていない時は公開の案内を出さない")
	assert_true(_inside_screen(save._success_return_button))
	assert_false(_all_texts(save).contains("ぼうけんのしょ"))

func test_save_same_name_confirmation_uses_the_same_menu() -> void:
	var main := await _new_main()
	_fill(main, false)
	main.press_save()
	main._save_view._on_save_new_pressed()
	var second := await _new_main()
	_fill(second, false)
	second.press_save()
	second._save_view._on_save_new_pressed()
	await _frames()
	var save := second._save_view
	assert_true(save._same_name_panel.visible, "sanity: 同じ名前の確認")
	assert_eq(_text_of(save._same_name_panel, "SameNameTitleLabel"), "保存")
	assert_not_null(save._same_name_panel.find_child("MenuCursor", true, false), "「▶」で選ぶメニュー")
	assert_lt(save._same_name_confirm_button.position.y, save._same_name_cancel_button.position.y)
	assert_true(_inside_screen(save._same_name_confirm_button) and _inside_screen(save._same_name_cancel_button))

# =============================================================================
# 英語
# =============================================================================

func test_new_texts_have_english() -> void:
	var en := TranslationServer.get_translation_object("en")
	assert_not_null(en, "sanity: 英語の表")
	for key in ["撃破ターン", "クリアタイム", "倒れたターン", "全滅してしまった……", "戦闘結果", "挑戦モード", "クリアチェックが完了しました。",
			"ボスが強すぎる時は、能力（HP・ATK）か行動を見直しましょう", "最終確認へ（保存・公開）", "作成画面へ戻る", "試練の確認",
			"このボスを、作った設定のまま倒せるかを確かめます。", "REWIND が使えます", "ランダムに選ぶ行動があります",
			"クリアチェックを通ると、オンラインに公開できます", "開始する", "保存するボス", "クリアチェック達成済み",
			"最終確認の画面の「オンライン公開」で公開できます", "%s を倒した！", "制作"]:
		var text := str(en.get_message(key))
		assert_false(text.is_empty() or text == key, "英語がある: " + key)
