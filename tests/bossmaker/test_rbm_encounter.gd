extends GutTest
## 戦闘開始前の登場演出・勝利演出（src/bossmaker/visuals/encounter/、RBMEncounterDirector）の契約テスト。
## 見た目・時間・音の良し悪しは実GPU（tools/verify_encounter_gpu.gd）と動画で確かめる。ここでは次を確かめる:
## - 宣言した素材がすべてあり、各スクリプトが鳴らす音はすべて宣言されている（再生中に初めて読まないため）
## - 9体すべてに登場と勝利があり、覚醒した後の形は正しい倒れ方へ振り分けられる
## - 操作の流れで頼まれない戦闘（テスト・ほかの検証）は今までどおり（すぐ開幕へ進み、結果パネル・記録も今までどおり）
## - 勝利演出の間だけ結果パネルと決着の音を止め、中断すれば元の見た目へ戻る。戦闘の状態とゲーム全体の時間は変えない
## - 事前読み込みは、挑戦・クリアチェックの画面の時だけ登場・勝利の素材を計画に加える
## - 前の画面が閉じる層は、閉じ終わった時に呼び出し元の処理を1回だけ呼び、外せば残らない
const IntroPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_intro_player.gd")
const VictoryPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd")
const EncounterAssets = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_assets.gd")
const Overlay = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_overlay.gd")
const Banner = preload("res://src/bossmaker/visuals/encounter/rbm_victory_banner.gd")
const ScreenClose = preload("res://src/bossmaker/visuals/encounter/rbm_screen_close.gd")
const Warmup = preload("res://src/bossmaker/visuals/rbm_presentation_warmup.gd")
const BOSSES := ["slime", "wolf", "knight", "dragon", "ghost", "golem", "musha", "astronaut", "gentleman"]
const ALLIES := ["hero", "butler", "healer", "samurai", "tank"]

func after_each() -> void:
	Engine.time_scale = 1.0
	await get_tree().process_frame

func _definition(appearance: String, hp: int = 1) -> Dictionary:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = appearance
	draft.boss_name = "Encounter QA"
	draft.hp = hp
	draft.atk = 40
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]:
		draft.add_party_character(id)
	var id := draft.add_skill({"name": "QA attack", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[id] = 100.0
	return draft.to_definition()

func test_every_declared_encounter_asset_exists() -> void:
	var count := 0
	for boss in BOSSES + ["dragon_awakened", "astronaut_awakened", "musha_awakened", "gentleman_awakened"]:
		for kind in ["intro", "final_blow", "victory"]:
			for path in EncounterAssets.warm_paths(boss, kind):
				assert_true(ResourceLoader.exists(path), "%s %s: %s" % [boss, kind, path])
				count += 1
	for ally in ALLIES:
		for kind in ["intro_ally", "victory_ally"]:
			var paths := EncounterAssets.warm_paths(ally, kind)
			assert_false(paths.is_empty(), "%s %s declares its frames" % [ally, kind])
			for path in paths:
				assert_true(ResourceLoader.exists(path), "%s %s: %s" % [ally, kind, path])
	assert_gt(count, 200)

func test_every_boss_has_an_intro_and_a_victory_and_awakened_forms_get_the_right_defeat() -> void:
	for boss in BOSSES:
		assert_true(IntroPlayer.has_intro(boss), boss + " intro")
		assert_true(VictoryPlayer.has_victory(boss), boss + " victory")
		assert_eq(VictoryPlayer.defeat_script(boss), VictoryPlayer.DEFEAT[boss])
	# 覚醒後の12ポーズで描ける倒れ方はそのまま、覚醒前のコマ絵に依存する倒れ方（武者・紳士）は共通の倒れ方
	assert_eq(VictoryPlayer.defeat_script("dragon_awakened"), VictoryPlayer.DEFEAT["dragon"])
	assert_eq(VictoryPlayer.defeat_script("astronaut_awakened"), VictoryPlayer.DEFEAT["astronaut"])
	assert_eq(VictoryPlayer.defeat_script("musha_awakened"), VictoryPlayer.GENERIC)
	assert_eq(VictoryPlayer.defeat_script("gentleman_awakened"), VictoryPlayer.GENERIC)
	assert_null(VictoryPlayer.defeat_script(""))
	assert_false(IntroPlayer.has_intro(""))

func test_every_sound_a_script_plays_is_declared_for_the_warmup() -> void:
	var dirs := ["res://src/bossmaker/visuals/encounter/intro/", "res://src/bossmaker/visuals/encounter/defeat/"]
	var re := RegEx.create_from_string("\"((?:enc|game):[a-z_0-9]+)\"")
	for dir in dirs:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var script: GDScript = load(dir + f)
			var declared: Array = script.get_script_constant_map().get("SOUNDS", [])
			for m in re.search_all(script.source_code):
				assert_true(declared.has(m.get_string(1)), "%s plays %s and declares it" % [f, m.get_string(1)])
	# 全ボス共通の音（題字・とどめ・ファンファーレ・味方の小さな音）
	for key in IntroPlayer.Choreo.COMMON_SOUNDS + VictoryPlayer.COMMON_SOUNDS:
		assert_true(ResourceLoader.exists(IntroPlayer.Audio.path_of(key)), key)

func test_the_title_fits_the_longest_boss_name_and_author() -> void:
	var font := Overlay.jp_font()
	var name := "あ".repeat(RBMCreatorDraft.MAX_BOSS_NAME_LENGTH)
	var author := "い".repeat(RBMCreatorDraft.MAX_AUTHOR_NAME_LENGTH)
	var size := Overlay.fit_size(font, name, author, "制作")
	var credit_w := 22.0 + font.get_string_size("制作  " + author, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	assert_lte(72.0 + font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + credit_w, 1280.0 - 40.0 + 1.0, "name + credit fit (size %d)" % size)
	assert_eq(Overlay.fit_size(font, "スライム", "mina", "制作"), 50, "short names keep the full size")

func test_clear_time_reads_minutes_and_seconds() -> void:
	assert_eq(Banner.time_text(0.4), "0:00")
	assert_eq(Banner.time_text(61.6), "1:02")
	assert_eq(Banner.time_text(600.0), "10:00")

func test_battles_started_without_a_request_behave_as_before() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	view.presentation_enabled = false
	var wins := [0]
	view.challenge_won.connect(func(): wins[0] += 1)
	# 頼まれても、演出を見せない窓（テスト）では使わない。頼まれなければもちろん使わない。
	view.request_encounter({"boss_name": "QA", "author": "qa"})
	view.start_battle(_definition("appearance_golem"), RBMBattleUiKit.ALL_VISIBLE, "appearance_golem")
	assert_false(view._encounter.active)
	assert_false(view._is_busy())
	assert_eq(view._encounter_request, {}, "the request is used once")
	for i in 20:
		if view.session.battle.battle_over:
			break
		view.act_attack(view.session.pending_ally_id())
	assert_true(view.session.battle.battle_over)
	assert_true(view._outcome_area.visible, "the result shows at once as before")
	assert_eq(wins[0], 1)

func test_a_victory_holds_only_the_result_and_cancel_restores_everything() -> void:
	var view := RBMChallengeBattleView.new()
	add_child_autofree(view)
	view.presentation_enabled = false
	view.start_battle(_definition("appearance_golem"), RBMBattleUiKit.ALL_VISIBLE, "appearance_golem")
	for i in 20:
		if view.session.battle.battle_over:
			break
		view.act_attack(view.session.pending_ally_id())
	assert_true(view.session.battle.battle_over)
	var director: RBMEncounterDirector = view._encounter
	var stage: Control = view._battlefield_ally_row.get_meta("visual_stage")
	var boss_visual: Control = stage._visuals["boss"]
	var state_before := JSON.stringify(view.session.battle.presentation_state())
	# 操作の流れで始めた戦闘として、決着の命中を受け取る（presenter の entry_impact と同じ形）
	director.begin_battle({"boss_name": "QA", "author": "qa"})
	director.on_impact({"visual_state": view.session.battle.presentation_state()})
	assert_true(director.holds_outcome())
	assert_true(director.is_playing())
	view._se_outcome_played = false
	var audio := view.get_node_or_null("RBMAudio")
	var before: int = audio.history.size() if audio != null else 0
	view.refresh()
	assert_false(view._outcome_area.visible, "the result waits for the victory")
	if audio != null:
		assert_false(audio.history.slice(before).has("victory"), "no decisive victory jingle during the victory")
	assert_true(director.on_presentation_finished())
	assert_false(boss_visual.visible, "the defeat draws the boss itself")
	for i in 5:
		await get_tree().process_frame
	assert_eq(Engine.time_scale, 1.0, "the whole game's time is never changed")
	director.cancel()
	await get_tree().process_frame
	assert_false(director.holds_outcome())
	assert_false(director.is_playing())
	view.refresh()
	assert_true(view._outcome_area.visible)
	assert_true(boss_visual.visible)
	assert_eq(stage.scale, Vector2.ONE)
	assert_eq(stage.position, Vector2.ZERO)
	for n in stage.get_children():
		assert_false(str(n.name).begins_with("Victory"), "no victory layer remains: " + str(n.name))
	assert_eq(JSON.stringify(view.session.battle.presentation_state()), state_before, "the battle state is untouched")

func test_the_warmup_plans_encounter_assets_only_for_challenge_and_clear_check_stages() -> void:
	var session := RBMCreatorTestSession.new(_definition("appearance_golem", 3000), 5)
	var plans := {}
	for with_meta in [false, true]:
		var stage := RBMBattleStage.new()
		stage.size = Vector2(1280, 720)
		stage.set_meta("fullscreen_formation", true)
		if with_meta:
			stage.set_meta("encounter_presentations", true)
		add_child_autofree(stage)
		stage.configure(session.battle, "appearance_golem")
		var warm = stage._presentation_warmup
		plans[with_meta] = warm.plan_from({"battle": session.battle, "boss_id": "golem", "party": ["hero", "butler", "healer", "samurai"]})
	var intro := EncounterAssets.warm_paths("golem", "intro")
	var victory := EncounterAssets.warm_paths("golem", "victory")
	assert_false(plans[false].has(IntroPlayer.Audio.path_of("enc:golem_slam")), "TEST BATTLE does not read the intro")
	assert_false(plans[false].has(IntroPlayer.Audio.path_of("enc:fanfare_b")), "TEST BATTLE does not read the victory")
	for path in intro + victory:
		assert_true(plans[true].has(path), "challenge/clear check read " + path)
	# 登場は戦闘を開くと同時に流れるので先に読み、勝利は後に読む
	assert_lt(plans[true].find(IntroPlayer.Audio.path_of("enc:golem_slam")), plans[true].find(IntroPlayer.Audio.path_of("enc:fanfare_b")))

func test_the_screen_close_calls_back_once_and_is_released() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var calls := [0]
	var layer = ScreenClose.start(host, func(): calls[0] += 1)
	await get_tree().process_frame
	assert_eq(ScreenClose.active_count(get_tree()), 1)
	layer._process(ScreenClose.DURATION * 0.5)
	assert_eq(calls[0], 0, "not before the close ends")
	layer._process(ScreenClose.DURATION)
	layer._process(0.1)
	assert_eq(calls[0], 1, "once when the close ends")
	ScreenClose.release_all(get_tree())
	await get_tree().process_frame
	assert_eq(ScreenClose.active_count(get_tree()), 0)

func test_the_stage_motion_speed_changes_only_the_current_motion() -> void:
	var stage := RBMBattleStage.new()
	add_child_autofree(stage)
	stage.set_motion_speed(0.3)   # 動きが無い時は何もしない
	var tw := stage.create_tween()
	tw.tween_interval(1.0)
	stage._tween = tw
	stage.set_motion_speed(0.3)
	assert_eq(Engine.time_scale, 1.0)
	stage.set_motion_speed(1.0)
	tw.kill()
	stage._tween = null
