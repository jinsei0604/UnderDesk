extends GutTest

## ローカライズ監査（2026-09-11）で発見した個別の翻訳漏れの回帰テスト
## (RBMGameRoot全体の再生成ロジックの回帰はtest_rbm_locale_switch.gd側)。
##
## 重要: RBMLocaleはグローバルなautoloadであり、TranslationServer自体も
## プロセス全体で共有される——このテストが変更したロケールを他のテストへ
## 波及させないよう、必ずbefore_each()で元の値を退避し、after_each()で
## 復元する。

var _saved_locale := "ja"

func before_each() -> void:
	_saved_locale = RBMLocale.current_locale()

func after_each() -> void:
	RBMLocale.set_locale(_saved_locale)

## rbm_creator_step4_actions.gd _on_scripted_when_next_pressed(): 既存の
## 指定行動を編集する際のフォームタイトルが"指定行動を編集"という生の
## 日本語文字列で渡されており、rbm_action_editor_form.gd open_for_editing()
## の「titleが空文字でなければそのまま使う」仕様のせいでtr()フォールバック
## が一切効かず、Englishロケールでも常に日本語のまま表示されていた
## （新規作成側のopen_for_new(tr("指定行動を作る"))は元から正しかった）。
##
## RBMCreatorStep4（_step_views[2]、STEP3「行動」）は入口ラッパーで、
## SIMPLEモードの実処理はその_simple_view（RBMCreatorStep4Actions）が
## 持つ——直接キャストせず一段掘り下げる必要がある。
func test_editing_a_scripted_action_shows_a_translated_title_in_english() -> void:
	RBMLocale.set_locale("en")
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	var skill_id: String = main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	main.draft.add_scripted_action(1, skill_id, "replace")
	main.go_to_step(3)
	var wrapper := main._step_views[2] as RBMCreatorStep4
	var step: RBMCreatorStep4Actions = wrapper.get("_simple_view")
	step.refresh()

	# The "編集" button on an existing scripted-action row ultimately sets
	# _pending_scripted_editing_index then calls this same handler -- calling
	# it directly here is the same stable access path other Creator tests
	# already use for private _on_*_pressed handlers rather than re-deriving
	# the click chain through find_child().
	step.set("_pending_scripted_editing_index", 0)
	step.call("_on_scripted_when_next_pressed")

	var form: RBMActionEditorForm = step.get("_form")
	assert_eq(form.get("_title_label").text, "Edit Scripted Action")
	await get_tree().process_frame

func test_editing_a_scripted_action_shows_the_japanese_title_in_japanese() -> void:
	RBMLocale.set_locale("ja")
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	var skill_id: String = main.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	main.draft.add_scripted_action(1, skill_id, "replace")
	main.go_to_step(3)
	var wrapper := main._step_views[2] as RBMCreatorStep4
	var step: RBMCreatorStep4Actions = wrapper.get("_simple_view")
	step.refresh()

	step.set("_pending_scripted_editing_index", 0)
	step.call("_on_scripted_when_next_pressed")

	var form: RBMActionEditorForm = step.get("_form")
	assert_eq(form.get("_title_label").text, "指定行動を編集")
	await get_tree().process_frame

## rbm_creator_step5_party.gd _add_skill_override_editor(): ADVANCEDモードの
## 「性能調整」タブで表示するスキルの上書きフィールド名（倍率/回復量/
## SP消費等）がtr()を通さず生の日本語文字列を直接.textへ設定していた
## （src/bossmaker/challenge/rbm_challenge_confirm_view.gdの同じラベル
## 辞書は既に正しくtr()を通していた——Creator側だけの漏れ）。
func test_skill_override_field_labels_translate_to_english() -> void:
	RBMLocale.set_locale("en")
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	main.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	main.draft.add_party_character("hero")
	main.go_to_step(4)
	var step := main._step_views[3] as RBMCreatorStep5Party
	step.refresh()
	(step.find_child("SelectCharacterButton_hero", true, false) as Button).pressed.emit()
	(step.find_child("PerformanceTabButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame

	var label := step.find_child("AllySkillOverrideLabel_hero_hero_slash_atk_multiplier", true, false) as Label
	assert_not_null(label)
	assert_eq(label.text, "Multiplier")

func test_skill_override_field_labels_stay_japanese_in_japanese() -> void:
	RBMLocale.set_locale("ja")
	var main := RBMCreatorMain.new()
	add_child_autofree(main)
	main.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	main.draft.add_party_character("hero")
	main.go_to_step(4)
	var step := main._step_views[3] as RBMCreatorStep5Party
	step.refresh()
	(step.find_child("SelectCharacterButton_hero", true, false) as Button).pressed.emit()
	(step.find_child("PerformanceTabButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame

	var label := step.find_child("AllySkillOverrideLabel_hero_hero_slash_atk_multiplier", true, false) as Label
	assert_not_null(label)
	assert_eq(label.text, "倍率")
