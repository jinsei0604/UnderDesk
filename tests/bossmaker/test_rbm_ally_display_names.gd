extends GutTest

## 攻略側キャラクターの表示名の統一(「属性・呼称」の短い表記)の回帰テスト。
##
## 少女キャラだけ「雷属性・少女ヒーラー」と役職が付いていて、他(炎属性・勇者/
## 氷属性・老執事/風属性・侍)と不統一だったため「雷属性・少女」へ揃えた。変更は
## 表示名(display_name)とその英訳だけで、内部ID・性能・スキル構成は不変。

var _saved_locale := "ja"

func before_each() -> void:
	_saved_locale = RBMLocale.current_locale()

func after_each() -> void:
	RBMLocale.set_locale(_saved_locale)
	await get_tree().process_frame

func _master(id: String) -> Dictionary:
	return RBMDataLoader.load_dict("res://data_bossmaker/allies/%s.json" % id)

func test_girl_display_name_is_short_and_consistent_with_the_other_allies() -> void:
	assert_eq(str(_master("healer").get("display_name", "")), "雷属性・少女")
	assert_eq(str(_master("hero").get("display_name", "")), "炎属性・勇者")
	assert_eq(str(_master("samurai").get("display_name", "")), "風属性・侍")
	assert_eq(str(_master("butler").get("display_name", "")), "氷属性・老執事")
	assert_false(str(_master("healer").get("display_name", "")).contains("ヒーラー"), "the role suffix is gone from the user-facing name")

func test_english_name_follows_the_same_pattern() -> void:
	RBMLocale.set_locale("en")
	assert_eq(TranslationServer.translate("雷属性・少女"), "Lightning Girl")
	assert_eq(TranslationServer.translate("炎属性・勇者"), "Fire Hero")
	assert_eq(TranslationServer.translate("風属性・侍"), "Wind Samurai")
	RBMLocale.set_locale("ja")
	assert_eq(TranslationServer.translate("雷属性・少女"), "雷属性・少女")

func test_only_the_display_name_changed_id_and_skills_are_intact() -> void:
	var healer := _master("healer")
	assert_eq(str(healer.get("id", "")), "healer", "internal id unchanged")
	assert_eq(str(healer.get("attribute", "")), "LIGHTNING")
	var skill_ids: Array = []
	for skill in healer.get("skills", []):
		skill_ids.append(str(skill.get("id", "")))
	for expected in ["healer_shock", "healer_heal_single", "healer_heal_all"]:
		assert_true(skill_ids.has(expected), "skill %s is still there" % expected)
	assert_true(RBMDefinitionLoader.KNOWN_ALLY_PATHS.has("healer"), "still registered under the same id")

func test_step4_party_card_and_header_use_the_new_name() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	creator.draft.boss_name = "表示名テスト"
	creator.draft.add_party_character("healer")
	creator.go_to_step(4)
	await get_tree().process_frame
	await get_tree().process_frame
	var card_button := creator.find_child("SelectCharacterButton_healer", true, false) as Button
	assert_not_null(card_button)
	assert_eq(card_button.text, "雷属性・少女")
	var header := creator.find_child("SelectedCharacterHeaderLabel", true, false) as Label
	assert_eq(header.text, "雷属性・少女")
