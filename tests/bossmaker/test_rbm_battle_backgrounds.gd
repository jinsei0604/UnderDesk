extends GutTest

## ボスごとの専用戦闘背景(rbm_battle_backgrounds.gd)と、全画面戦闘UI
## (TEST BATTLE・クリアチェック・挑戦で共通)での使われ方。
## 背景の決まり方: 上書き(BOSS_BACKGROUNDS) → backgrounds/<boss_id>/background.png → 昼/夜。
## 素材の追加に依存せず確認するため、「専用背景あり」は既存の画像を代わりに使う。
##   ・命名規則: 各ボスの design.png(battle/<boss_id>/design.png)を background.png の代わりにする
##   ・上書き: テスト用の対応表に既存の画像を書く
## 本番の対応表・命名規則は書き換えない。また、後で本物の background.png を置いても
## 結果が変わらないよう、「専用背景なし」の確認は画像の無い場所を命名規則にして行う。
## GUT はエンジンのエラー(missing resource など)が出るとテストを失敗にするので、
## ここが通れば、専用背景が無い・パスが不正なときに読み込みエラーも出ていない。

const Backgrounds := preload("res://src/bossmaker/visuals/rbm_battle_backgrounds.gd")
## 上書きの代わりに使う、取り込み済みの既存の画像(中庭ではないもの)。
const STAND_IN := "res://assets_bossmaker/art/creator_top_background.png"
## 命名規則の代わり: battle/<boss_id>/design.png を backgrounds/<boss_id>/background.png に見立てる。
const DESIGN := "res://assets_bossmaker/battle/%s/design.png"
## どのボスの画像も無い命名規則(「専用背景なし」の確認用)。
const NOWHERE := "res://assets_bossmaker/battle/backgrounds/%s/__no_background_for_tests__.png"
const DAY := "res://assets_bossmaker/art/battle_courtyard_day.png"
const NIGHT := "res://assets_bossmaker/art/battle_courtyard_night.png"
const MUSHA_ONLY := {"musha": STAND_IN}
const NONE := {}

func _fill(draft: RBMCreatorDraft, appearance_id: String) -> RBMCreatorDraft:
	draft.appearance_id = appearance_id
	draft.boss_name = "Background QA"
	draft.hp = 3000
	draft.atk = 40
	draft.spd = 1
	if draft.party_character_ids.is_empty():
		for id in ["hero", "butler", "healer", "samurai"]:
			draft.add_party_character(id)
	if draft.skills.is_empty():
		var id := draft.add_skill({"name": "Background QA skill", "type": "attack", "target": "single", "attribute": "FIRE", "atk_multiplier": 1.0})
		draft.normal_actions_enabled = true
		draft.normal_action_percentages[id] = 100.0
	return draft

## 本物の TEST BATTLE / クリアチェック / 挑戦 の画面を開く(verify_battle_visuals_gpu.gd と同じ開き方)。
func _open(mode: String, appearance_id: String, table: Dictionary, time_of_day := "night", convention := NOWHERE) -> Control:
	var view: Control
	match mode:
		"test": view = RBMCreatorTestBattleView.new()
		"clear_check": view = RBMCreatorClearCheckView.new()
		_: view = RBMChallengeBattleView.new()
	add_child_autofree(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode != "challenge":
		view.setup(null)
	view._world_battle.boss_backgrounds = table
	view._world_battle.background_convention = convention
	view.battle_background = time_of_day
	await _start(view, mode, appearance_id)
	return view

func _start(view: Control, mode: String, appearance_id: String) -> void:
	view.set_boss_appearance(appearance_id)
	var definition := _fill(RBMCreatorDraft.new(), appearance_id).to_definition()
	if mode == "test":
		view.start(definition, 5)
	elif mode == "clear_check":
		view.start_battle(definition, 5)
	else:
		view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, appearance_id)
	await _frames()

func _frames(count := 4) -> void:
	for i in range(count):
		await get_tree().process_frame

func _bg(view: Control) -> TextureRect:
	return view._world_battle.background

# ---------------------------------------------------------------------------
# 対応表(rbm_battle_backgrounds.gd)
# ---------------------------------------------------------------------------

func test_a_background_png_in_the_boss_folder_is_used_automatically() -> void:
	assert_eq(Backgrounds.convention_path("musha"), "res://assets_bossmaker/battle/backgrounds/musha/background.png")
	assert_eq(Backgrounds.convention_path("musha_awakened"), "res://assets_bossmaker/battle/backgrounds/musha/background.png", "awakened: the same file")
	assert_eq(Backgrounds.convention_path(""), "")
	for boss_id in ["musha", "golem", "knight"]:
		var path: String = DESIGN % boss_id
		assert_eq(Backgrounds.path_for(boss_id, "night", NONE, DESIGN), path, boss_id)
		assert_eq(Backgrounds.path_for(boss_id, "day", NONE, DESIGN), path, "%s: whatever the time of day" % boss_id)
		assert_eq(Backgrounds.texture_for(boss_id, "night", NONE, DESIGN), load(path), boss_id)
	# 覚醒後も同じ背景(musha_awakened/ の画像ではなく musha/ の画像)
	assert_eq(Backgrounds.path_for("musha_awakened", "night", NONE, DESIGN), DESIGN % "musha")
	# 画像の無いボスは昼/夜の標準背景
	assert_eq(Backgrounds.path_for("not_a_boss", "night", NONE, DESIGN), NIGHT)
	assert_eq(Backgrounds.path_for("", "day", NONE, DESIGN), DAY)

func test_an_override_wins_then_the_boss_folder_then_the_day_night_background() -> void:
	assert_eq(Backgrounds.path_for("musha", "night", MUSHA_ONLY, DESIGN), STAND_IN, "1. the override")
	assert_eq(Backgrounds.path_for("musha", "night", NONE, DESIGN), DESIGN % "musha", "2. no override: the boss folder")
	assert_eq(Backgrounds.path_for("musha", "night", {"musha": "musha/not_yet.png"}, DESIGN), DESIGN % "musha", "2. an unusable override falls to the boss folder")
	assert_eq(Backgrounds.path_for("golem", "night", MUSHA_ONLY, DESIGN), DESIGN % "golem", "2. another boss's override does not apply")
	assert_eq(Backgrounds.path_for("not_a_boss", "night", MUSHA_ONLY, DESIGN), NIGHT, "3. neither: day/night")
	assert_eq(Backgrounds.path_for("musha", "day", {"musha": "musha/not_yet.png"}, NOWHERE), DAY, "3. nothing usable at all")

func test_an_override_is_used_for_its_boss_whatever_the_time_of_day() -> void:
	assert_eq(Backgrounds.path_for("musha", "night", MUSHA_ONLY, NOWHERE), STAND_IN)
	assert_eq(Backgrounds.path_for("musha", "day", MUSHA_ONLY, NOWHERE), STAND_IN)
	assert_eq(Backgrounds.texture_for("musha", "night", MUSHA_ONLY, NOWHERE), load(STAND_IN))

func test_the_awakened_boss_keeps_the_same_background() -> void:
	assert_eq(Backgrounds.path_for("musha_awakened", "night", MUSHA_ONLY, NOWHERE), STAND_IN)
	assert_eq(Backgrounds.path_for("golem_awakened", "night", MUSHA_ONLY, NOWHERE), NIGHT)

func test_a_boss_without_a_dedicated_background_uses_the_standard_one() -> void:
	for boss_id in ["golem", "wolf", "", "not_a_boss"]:
		assert_eq(Backgrounds.path_for(boss_id, "day", MUSHA_ONLY, NOWHERE), DAY, boss_id)
		assert_eq(Backgrounds.path_for(boss_id, "night", MUSHA_ONLY, NOWHERE), NIGHT, boss_id)
		assert_eq(Backgrounds.texture_for(boss_id, "night", MUSHA_ONLY, NOWHERE), load(NIGHT), boss_id)
		assert_eq(Backgrounds.path_for(boss_id, "night", NONE, NOWHERE), NIGHT, boss_id)

func test_the_standard_background_follows_the_day_night_choice_as_before() -> void:
	assert_eq(Backgrounds.standard_path("day"), DAY)
	assert_eq(Backgrounds.standard_path("night"), NIGHT)
	assert_eq(Backgrounds.standard_path(""), NIGHT, "anything but day is night, as before")
	assert_eq(Backgrounds.standard_path("invalid"), NIGHT)

func test_a_file_name_is_looked_up_in_the_backgrounds_folder() -> void:
	assert_eq(Backgrounds.configured_path("musha", {"musha": "musha/background.png"}), "res://assets_bossmaker/battle/backgrounds/musha/background.png")
	assert_eq(Backgrounds.configured_path("musha", {"musha": STAND_IN}), STAND_IN, "a res:// path is used as it is")
	assert_eq(Backgrounds.configured_path("musha", {"musha": ""}), "")
	assert_eq(Backgrounds.configured_path("golem", {"musha": STAND_IN}), "")

func test_missing_or_invalid_dedicated_backgrounds_fall_back_without_errors() -> void:
	var bad := [
		"musha/__missing_background_for_tests__.png",  # 実背景の有無に依存しない不存在パス
		"res://assets_bossmaker/battle/backgrounds/musha/none.png",
		"res://no_such_folder/bg.png",
		"res://assets_bossmaker/audio/boss_impact_mass.wav",  # 画像ではない
		"res://src/bossmaker/visuals/rbm_battle_backgrounds.gd",  # 画像ではない
		"C:/Windows/win.ini",
		"user://bg.png",
		"musha/",
		"   ",
		42,
		null,
		["musha/background.png"],
	]
	for entry in bad:
		var table := {"musha": entry}
		assert_eq(Backgrounds.path_for("musha", "night", table, NOWHERE), NIGHT, str(entry))
		assert_eq(Backgrounds.path_for("musha", "day", table, NOWHERE), DAY, str(entry))
		assert_eq(Backgrounds.texture_for("musha", "night", table, NOWHERE), load(NIGHT), str(entry))
	# 命名規則の場所に画像が無いのは普通の状態(警告もエラーも出さない)。
	for boss_id in ["musha", "golem", "../musha", "a b", "%"]:
		assert_eq(Backgrounds.path_for(boss_id, "night", NONE, NOWHERE), NIGHT, boss_id)

func test_the_real_bosses_follow_the_documented_order() -> void:
	# 本物の上書き・命名規則で、実際のボスが「上書き → <boss_id>/background.png → 昼/夜」になる。
	# 画像を置いても、上書きを書いても、このテストは変えなくてよい。
	for boss_id in Backgrounds.BOSS_BACKGROUNDS:
		# 上書きに書いたのに画像が無い・取り込まれていない・綴りが違う、をここで見つける。
		var override := Backgrounds.configured_path(boss_id)
		assert_true(override.is_empty() or ResourceLoader.exists(override, "Texture2D"), "%s: %s is an imported image" % [boss_id, override])
	for boss_id in RBMVisualAssets.BOSS_IDS:
		var expected := NIGHT
		var override := Backgrounds.configured_path(boss_id)
		var named := Backgrounds.convention_path(boss_id)
		if not override.is_empty() and ResourceLoader.exists(override, "Texture2D"):
			expected = override
		elif ResourceLoader.exists(named, "Texture2D"):
			expected = named
		assert_eq(Backgrounds.path_for(boss_id, "night"), expected, boss_id)
		assert_eq(Backgrounds.path_for(boss_id + "_awakened", "night"), expected, boss_id + " (awakened)")

# ---------------------------------------------------------------------------
# 全画面戦闘UI(TEST BATTLE・クリアチェック・挑戦で共通)
# ---------------------------------------------------------------------------

func test_every_battle_screen_shows_the_boss_dedicated_background() -> void:
	for mode in ["test", "clear_check", "challenge"]:
		var view := await _open(mode, "appearance_musha", MUSHA_ONLY)
		assert_eq(_bg(view).texture, load(STAND_IN), mode)
		assert_eq(view._world_battle.current_background_path, STAND_IN, mode)
		assert_eq(view._world_battle.current_background, "night", "%s: the day/night choice is still read" % mode)

func test_every_battle_screen_uses_the_background_png_in_the_boss_folder_automatically() -> void:
	for mode in ["test", "clear_check", "challenge"]:
		var view := await _open(mode, "appearance_musha", NONE, "day", DESIGN)
		assert_eq(_bg(view).texture, load(DESIGN % "musha"), mode)
		assert_eq(view._world_battle.current_background_path, DESIGN % "musha", mode)
		# 同じ画面で別のボスへ: 前のボスの画像は残らない
		await _start(view, mode, "appearance_golem")
		assert_eq(_bg(view).texture, load(DESIGN % "golem"), "%s: switched to the golem's own" % mode)

func test_every_battle_screen_shows_the_standard_background_without_a_dedicated_one() -> void:
	for mode in ["test", "clear_check", "challenge"]:
		for time_of_day in ["day", "night"]:
			var view := await _open(mode, "appearance_musha", NONE, time_of_day)
			assert_eq(_bg(view).texture, load(DAY if time_of_day == "day" else NIGHT), "%s %s" % [mode, time_of_day])
			assert_eq(view._world_battle.current_background, time_of_day)

func test_battle_screens_use_the_real_overrides_and_naming_rule_by_default() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	assert_eq(view._world_battle.boss_backgrounds, Backgrounds.BOSS_BACKGROUNDS)
	assert_eq(view._world_battle.background_convention, Backgrounds.CONVENTION)
	await _start(view, "challenge", "appearance_musha")
	assert_eq(_bg(view).texture, Backgrounds.texture_for("musha", "night"))

func test_an_invalid_dedicated_background_still_starts_the_battle_on_the_standard_one() -> void:
	var view := await _open("challenge", "appearance_musha", {"musha": "musha/not_yet.png"})
	assert_eq(_bg(view).texture, load(NIGHT))
	assert_not_null(view.session)
	assert_not_null(view.session.battle, "the battle is running")

func test_switching_to_another_boss_does_not_keep_the_previous_background() -> void:
	var view := await _open("challenge", "appearance_musha", MUSHA_ONLY)
	assert_eq(_bg(view).texture, load(STAND_IN))
	await _start(view, "challenge", "appearance_golem")
	assert_eq(_bg(view).texture, load(NIGHT), "golem has no dedicated background")
	await _start(view, "challenge", "appearance_musha")
	assert_eq(_bg(view).texture, load(STAND_IN))
	view.battle_background = "day"
	await _start(view, "challenge", "appearance_golem")
	assert_eq(_bg(view).texture, load(DAY))
	# 戦闘中に外見だけ差し替えても(検証ツールなど)、背景はそのボスへ付いていく。
	view.set_boss_appearance("appearance_musha")
	await _frames(1)
	assert_eq(_bg(view).texture, load(STAND_IN))

func test_the_creator_test_battle_and_clear_check_follow_the_draft_boss() -> void:
	var main := RBMCreatorMain.new()
	main.size = Vector2(1280, 720)
	add_child_autofree(main)
	await _frames(2)
	for battle_view in [main._test_battle_view, main._clear_check_view]:
		battle_view._world_battle.boss_backgrounds = MUSHA_ONLY
		battle_view._world_battle.background_convention = NOWHERE
	_fill(main.draft, "appearance_musha")
	main.draft.battle_background = "day"
	assert_true(bool(main.press_test_battle().get("ok", false)))
	await _frames()
	assert_eq(_bg(main._test_battle_view).texture, load(STAND_IN))
	main._on_test_battle_return_to_creator()
	main.draft.appearance_id = "appearance_golem"
	assert_true(bool(main.press_test_battle().get("ok", false)))
	await _frames()
	assert_eq(_bg(main._test_battle_view).texture, load(DAY), "the previous boss's background is gone")
	main._on_test_battle_return_to_creator()
	main.press_clear_check()
	assert_true(bool(main.press_clear_check_start(5).get("ok", false)))
	await _frames()
	assert_eq(_bg(main._clear_check_view).texture, load(DAY))
	main.draft.appearance_id = "appearance_musha"
	main.press_clear_check()
	assert_true(bool(main.press_clear_check_start(5).get("ok", false)))
	await _frames()
	assert_eq(_bg(main._clear_check_view).texture, load(STAND_IN))

func test_restarting_the_battle_keeps_the_right_background() -> void:
	var challenge := await _open("challenge", "appearance_musha", MUSHA_ONLY)
	challenge._on_restart_confirmed()
	await _frames()
	assert_eq(_bg(challenge).texture, load(STAND_IN))
	var clear := await _open("clear_check", "appearance_musha", MUSHA_ONLY)
	clear._on_restart_confirmed()
	await _frames()
	assert_eq(_bg(clear).texture, load(STAND_IN))
	var test_view := await _open("test", "appearance_golem", MUSHA_ONLY, "day")
	test_view.retry()
	await _frames()
	assert_eq(_bg(test_view).texture, load(DAY))

func test_the_background_stays_behind_the_boss_allies_effects_and_ui() -> void:
	var view := await _open("challenge", "appearance_musha", MUSHA_ONLY)
	var stage: Control = view._world_battle.stage
	var bg := _bg(view)
	assert_eq(bg.get_parent(), stage)
	assert_eq(bg.get_index(), 0, "the first child of the stage: drawn before everything on it")
	assert_eq(bg.z_index, 0)
	assert_true(bg.z_as_relative)
	assert_false(bg.top_level)
	assert_eq(bg.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for key in stage._visuals:
		assert_gt((stage._visuals[key] as CanvasItem).z_index, bg.z_index, "actor %s is in front" % key)
	assert_gt((stage.get_meta("battle_hud") as CanvasItem).z_index, bg.z_index, "the UI is in front")
	# 武者の墨の層・常時オーラは今までどおり(オーラはこの背景を背景として見つける)。
	assert_not_null(stage.musha_ink_director())
	assert_eq(stage._musha_aura._find_background(), bg)

func test_the_background_choice_does_not_touch_the_battle() -> void:
	var with_dedicated := await _open("test", "appearance_musha", MUSHA_ONLY)
	var standard := await _open("test", "appearance_musha", NONE)
	assert_ne(_bg(with_dedicated).texture, _bg(standard).texture)
	assert_eq(with_dedicated.session.battle.snapshot(), standard.session.battle.snapshot(), "same battle, whatever the background")
