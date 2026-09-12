extends GutTest

## ローカライズ監査（2026-09-11）で発見した実バグの回帰テスト:
## RBMCreatorEntry/RBMChallengeEntryはRBMGameRoot._ready()で一度だけ生成
## され、以後は表示/非表示の切替だけで使い回される(§4/§5)。STEP1〜5・
## 保存/公開/確認ダイアログのボタン文言はいずれも「生成時点でのtr()呼び
## 出し結果」がそのまま.textへ書き込まれるため、生成時点のロケールが
## 既にen(前回セッションでEnglishのまま終了し、次回起動時にその設定を
## 読み込んだ場合)だと、以後どれだけRBMLocale.locale_changedが発生しても
## Creator/Challenge側の表示は英語のまま更新されない実バグを実GPU確認
## 済み(チェックリスト#3/#9相当)。
##
## 修正: RBMGameRoot._on_locale_changed()が、ロケール変更のたびに
## creator_entry/challenge_entryを作り直す(_rebuild_creator_and_challenge_
## entries_for_current_locale()参照)。ロケール切替ボタン自体は_title_screen
## の子であり、Creator/Challengeが表示されている間は押せない(既存の
## _show_only()による排他表示、かつCreator側は未保存確認を経てからしか
## タイトルへ戻れない)ため、切替が発生し得るのは常に両Entryが非表示かつ
## 保持すべき進行中の状態が無い瞬間だけ——安全に作り直せる。
##
## 重要: RBMLocaleはグローバルなautoloadであり、TranslationServer自体も
## プロセス全体で共有される——このテストが変更したロケールを他のテストへ
## 波及させないよう、また実際のuser://bossmaker/settings.jsonを汚さない
## よう、必ずbefore_each()で元の値を退避し、after_each()で復元する。

var _saved_locale := "ja"

func before_each() -> void:
	_saved_locale = RBMLocale.current_locale()

func after_each() -> void:
	RBMLocale.set_locale(_saved_locale)

func _btn(node: Node, button_name: String) -> Button:
	var found: Button = node.find_child(button_name, true, false)
	assert_not_null(found, "expected a real Button node named %s under %s" % [button_name, node])
	return found

func _enter_simple_creator(root: RBMGameRoot) -> RBMCreatorMain:
	_btn(root, "CreateModeButton").pressed.emit()
	_btn(root.creator_entry, "NewBossButton").pressed.emit()
	_btn(root.creator_entry, "ChooseSimpleModeButton").pressed.emit()
	return root.creator_entry.main

func test_switching_locale_rebuilds_creator_and_challenge_entries() -> void:
	RBMLocale.set_locale("en")
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	var old_creator_id := root.creator_entry.get_instance_id()
	var old_challenge_id := root.challenge_entry.get_instance_id()

	RBMLocale.set_locale("ja")
	await get_tree().process_frame

	assert_ne(root.creator_entry.get_instance_id(), old_creator_id, "creator_entry must be rebuilt fresh so its tr() calls re-run under the new locale")
	assert_ne(root.challenge_entry.get_instance_id(), old_challenge_id, "challenge_entry must be rebuilt fresh so its tr() calls re-run under the new locale")
	assert_false(root.creator_entry.visible, "the rebuild must not itself reveal Creator (title screen stays showing)")
	assert_false(root.challenge_entry.visible, "the rebuild must not itself reveal Challenge (title screen stays showing)")
	assert_true(root._menu_panel.visible, "the title screen itself must be unaffected by the rebuild")

func test_creator_shows_japanese_after_switching_from_a_stale_english_startup_locale() -> void:
	# Reproduces the reported bug directly: the app happens to start in
	# English (e.g. a previously-saved preference), matching a real
	# RBMLocale._ready() load — then the player switches to Japanese on the
	# title screen BEFORE ever entering Creator for the first time.
	RBMLocale.set_locale("en")
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame

	RBMLocale.set_locale("ja")
	await get_tree().process_frame

	var main := _enter_simple_creator(root)
	await get_tree().process_frame
	main.go_to_step(5)
	var summary: Control = main._step_views[4]
	assert_eq(_btn(summary, "BackButton").text, "戻る")
	assert_eq(_btn(summary, "BackToCreatorListButton").text, "クリエイター一覧へ戻る")
	assert_eq(_btn(summary, "SaveButton").text, "保存")

func test_creator_shows_english_after_switching_from_japanese_startup_locale() -> void:
	# The already-working direction (Godot's own live re-translation
	# already handles ja-at-build-time correctly) -- kept as a regression
	# guard so a future change can't quietly break this direction while
	# fixing the other one.
	RBMLocale.set_locale("ja")
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame

	RBMLocale.set_locale("en")
	await get_tree().process_frame

	var main := _enter_simple_creator(root)
	await get_tree().process_frame
	main.go_to_step(5)
	var summary: Control = main._step_views[4]
	assert_eq(_btn(summary, "BackToCreatorListButton").text, "Back to Creator List")
	assert_eq(_btn(summary, "SaveButton").text, "Save")

func test_navigation_still_works_normally_after_a_locale_triggered_rebuild() -> void:
	RBMLocale.set_locale("en")
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame
	RBMLocale.set_locale("ja")
	await get_tree().process_frame

	var main := _enter_simple_creator(root)
	assert_true(main.visible, "the freshly rebuilt Creator must still support the normal SIMPLE entry flow")
	assert_eq(main.current_step, 1)
	assert_eq(main.draft.creator_mode, RBMCreatorDraft.CREATOR_MODE_SIMPLE)

func test_switching_locale_back_and_forth_does_not_get_stuck() -> void:
	# Pattern #9 from the audit checklist: ja -> en -> ja must not leave
	# a broken/mixed display.
	RBMLocale.set_locale("ja")
	var root := RBMGameRoot.new()
	add_child_autofree(root)
	await get_tree().process_frame

	RBMLocale.set_locale("en")
	await get_tree().process_frame
	RBMLocale.set_locale("ja")
	await get_tree().process_frame

	var main := _enter_simple_creator(root)
	main.go_to_step(5)
	var summary: Control = main._step_views[4]
	assert_eq(_btn(summary, "BackToCreatorListButton").text, "クリエイター一覧へ戻る")
	assert_eq(_btn(summary, "SaveButton").text, "保存")
