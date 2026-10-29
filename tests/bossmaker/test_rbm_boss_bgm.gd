extends GutTest

## ボス専用BGM(rbm_boss_bgm.gd が曲を決め、rbm_battle_bgm.gd が戦闘画面で鳴らす)。
## 曲の決まり方: 上書き(BOSS_BGM) → bgm/<boss_id>/<boss_id>_normal.ogg / _awakened.ogg → 覚醒後が無ければ覚醒前 → 無し。
## 鳴り方: 戦闘の始まり(登場の後)に覚醒前 → 覚醒の演出の間は消す → 覚醒の表示で覚醒後 → 決着の命中で消す。
## 本番の対応表・命名規則は書き換えない(テストは差し替え用の table を使う)。

const MUSHA_NORMAL := "res://assets_bossmaker/audio/bgm/musha/musha_normal.ogg"
const MUSHA_AWAKENED := "res://assets_bossmaker/audio/bgm/musha/musha_awakened.ogg"
const BGM_ROOT := "res://assets_bossmaker/audio/bgm/"

class FakeBattle:
	extends RefCounted
	var is_awakened := false
	var battle_over := false

class FakeSession:
	extends RefCounted
	var battle: FakeBattle

class FakePresenter:
	extends Node
	signal entry_started(entry: Dictionary)
	signal entry_impact(entry: Dictionary)
	var playing := false
	func is_playing() -> bool:
		return playing

class FakeEncounter:
	extends Node
	var playing := false
	func is_playing() -> bool:
		return playing

class FakeSound:
	extends Node
	var muted := false

class FakeView:
	extends Control
	var session: FakeSession
	var _presenter: FakePresenter
	var _encounter: FakeEncounter
	var _battlefield_ally_row: Node
	var _boss_appearance_id := "appearance_musha"
	var sound: FakeSound

## 偽の戦闘画面に BGM を付ける。BGM は手で進める(_process を自動で動かさない)。
func _fake_view(appearance_id := "appearance_musha") -> FakeView:
	var view := FakeView.new()
	view._boss_appearance_id = appearance_id
	view._presenter = FakePresenter.new()
	view.add_child(view._presenter)
	view._encounter = FakeEncounter.new()
	view.add_child(view._encounter)
	var row := Node.new()
	var stage := Node.new()
	view.sound = FakeSound.new()
	view.sound.name = "RBMAudio"
	stage.add_child(view.sound)
	row.add_child(stage)
	row.set_meta("visual_stage", stage)
	view._battlefield_ally_row = row
	view.add_child(row)
	add_child_autofree(view)
	var bgm := RBMBattleBgm.attach(view)
	bgm.set_process(false)
	return view

func _start(view: FakeView) -> FakeBattle:
	view.session = FakeSession.new()
	view.session.battle = FakeBattle.new()
	return view.session.battle

func _bgm(view: Node) -> RBMBattleBgm:
	return view.get_node(RBMBattleBgm.NODE_NAME) as RBMBattleBgm

func _step(view: Node, seconds := 0.05) -> void:
	_bgm(view)._process(seconds)

# ---------------------------------------------------------------------------
# 曲の決まり方(rbm_boss_bgm.gd)
# ---------------------------------------------------------------------------

func test_the_musha_files_in_the_boss_folder_are_used_automatically() -> void:
	assert_eq(RBMBossBgm.path_for("musha", false), MUSHA_NORMAL, "覚醒前は bgm/musha/musha_normal.ogg")
	assert_eq(RBMBossBgm.path_for("musha", true), MUSHA_AWAKENED, "覚醒後は bgm/musha/musha_awakened.ogg")
	assert_eq(RBMBossBgm.path_for("musha_awakened", true), MUSHA_AWAKENED, "覚醒後の外見のID(_awakened)でも同じフォルダ")
	assert_eq(RBMBossBgm.convention_path("dragon", true), BGM_ROOT + "dragon/dragon_awakened.ogg", "命名規則: <boss_id>/<boss_id>_awakened.ogg")

func test_a_boss_without_its_own_bgm_keeps_playing_without_music() -> void:
	for id in ["golem", "slime", ""]:
		assert_eq(RBMBossBgm.path_for(id, false), "", "%s: 専用の曲が無いボスは今までどおり BGM なし" % id)
		assert_eq(RBMBossBgm.path_for(id, true), "")

func test_the_awakened_state_falls_back_to_the_normal_track() -> void:
	var table := {"testboss": {"normal": "musha/musha_normal.ogg"}}
	assert_eq(RBMBossBgm.path_for("testboss", false, table), MUSHA_NORMAL)
	assert_eq(RBMBossBgm.path_for("testboss", true, table), MUSHA_NORMAL, "覚醒後の曲が無いボスは、覚醒後も覚醒前の曲を続ける")

func test_the_override_table_wins_and_a_bad_path_falls_back() -> void:
	var table := {"musha": {"normal": "musha/musha_awakened.ogg", "awakened": "musha/__missing__.ogg", "awakened_db": -3.0}}
	assert_eq(RBMBossBgm.path_for("musha", false, table), MUSHA_AWAKENED, "上書きは命名規則より優先する")
	assert_eq(RBMBossBgm.path_for("musha", true, table), MUSHA_AWAKENED, "読めない上書きは命名規則の曲に戻す")
	assert_eq(RBMBossBgm.volume_db("musha", true, table), -3.0 + RBMBossBgm.ALL_DB)
	assert_eq(RBMBossBgm.volume_db("musha", false, table), RBMBossBgm.ALL_DB, "書かなければ曲のままの音量(＋全体の調整)")
	assert_eq(RBMBossBgm.volume_db("golem", false), RBMBossBgm.ALL_DB)

## 2026-10-17 ユーザー: BGM が小さすぎる → 2曲とも曲全体の大きさを REFERENCE_LUFS(-24)にそろえて鳴らす(曲のファイルは変えない)。
## 測った大きさ: 覚醒前 -34.3 LUFS・覚醒後 -37.9 LUFS(覚醒後のほうが小さい仕上がり)。
func test_the_musha_tracks_are_played_at_the_reference_loudness() -> void:
	assert_eq(RBMBossBgm.REFERENCE_LUFS, -24.0)
	assert_eq(RBMBossBgm.ALL_DB, -3.0, "2026-10-17 ユーザー: 攻撃の効果音と合わせるため、全体をほんの少し下げる")
	assert_almost_eq(RBMBossBgm.volume_db("musha", false) - RBMBossBgm.ALL_DB, RBMBossBgm.REFERENCE_LUFS - (-34.3), 0.05, "覚醒前 +10.3dB")
	assert_almost_eq(RBMBossBgm.volume_db("musha", true) - RBMBossBgm.ALL_DB, RBMBossBgm.REFERENCE_LUFS - (-37.9), 0.05, "覚醒後 +13.9dB(覚醒前と同じ大きさに)")
	# 曲の最大の値(覚醒前 -17.4dBFS・覚醒後 -20.2dBFS)に足しても音割れしない
	assert_lt(-17.4 + RBMBossBgm.volume_db("musha", false), -3.0)
	assert_lt(-20.2 + RBMBossBgm.volume_db("musha", true), -3.0)

## 置いた曲(今後足す曲も)が、取り込みの設定でループすること・命名規則どおりであること。
func test_every_boss_bgm_file_is_named_by_the_rule_and_imported_as_a_loop() -> void:
	var found := 0
	for folder in DirAccess.get_directories_at(BGM_ROOT):
		for file in DirAccess.get_files_at(BGM_ROOT + folder):
			if not file.ends_with(".ogg"):
				continue
			found += 1
			assert_true(file in ["%s_normal.ogg" % folder, "%s_awakened.ogg" % folder], "%s/%s は <boss_id>_normal.ogg か <boss_id>_awakened.ogg" % [folder, file])
			var config := ConfigFile.new()
			assert_eq(config.load(BGM_ROOT + folder + "/" + file + ".import"), OK, "%s は取り込まれている" % file)
			assert_true(bool(config.get_value("params", "loop", false)), "%s の取り込みの設定は loop=true" % file)
			var offset := float(config.get_value("params", "loop_offset", 0.0))
			var length := (load(BGM_ROOT + folder + "/" + file) as AudioStream).get_length()
			assert_true(offset >= 0.0 and offset < length - 1.0, "%s のループの戻り先は曲の中(%.3f 秒)" % [file, offset])
	assert_gte(found, 2)

## 2026-10-17 ユーザー: 「違和感がなく、曲をできるだけ削らず、途中で切れたように聞こえない」戻り先。曲の終わり(本編と同じ厚さの
## 盛り上げ)から静かな前奏(1小節目)へ戻ると音の分布が 14〜15dB 変わり切れたように聞こえるため、作曲どおりの「8小節目の盛り上げ →
## 9小節目」と同じつながりになる9小節目の頭(154BPM で 12.4675 秒)のすぐ後の、段差の小さい点へ戻す。前奏は戦闘の最初の1回だけ。
func test_the_musha_tracks_loop_back_to_the_start_of_bar_nine() -> void:
	var bar9 := 8 * 4 * 60.0 / 154.0
	var normal := RBMBossBgm.load_stream(MUSHA_NORMAL) as AudioStreamOggVorbis
	var awakened := RBMBossBgm.load_stream(MUSHA_AWAKENED) as AudioStreamOggVorbis
	assert_almost_eq(normal.loop_offset, 12.4688, 0.00001, "覚醒前: 9小節目の頭の 1.3 ミリ秒後")
	assert_almost_eq(awakened.loop_offset, 12.46965, 0.00001, "覚醒後: 9小節目の頭の 2.1 ミリ秒後")
	for stream in [normal, awakened]:
		assert_between((stream as AudioStreamOggVorbis).loop_offset - bar9, 0.0, 0.003, "9小節目の頭から 3 ミリ秒以内")

func test_the_musha_tracks_loop_and_keep_their_length() -> void:
	for path in [MUSHA_NORMAL, MUSHA_AWAKENED]:
		var stream := RBMBossBgm.load_stream(path) as AudioStreamOggVorbis
		assert_not_null(stream)
		assert_true(stream.loop, "%s はループする" % path.get_file())
		assert_almost_eq(stream.get_length(), 99.74, 0.01, "曲の長さは渡された曲のまま(154BPM・64小節)")

# ---------------------------------------------------------------------------
# 鳴り方(rbm_battle_bgm.gd)
# ---------------------------------------------------------------------------

func test_the_normal_track_starts_with_the_battle_and_uses_the_music_bus() -> void:
	var view := _fake_view()
	_step(view)
	assert_eq(_bgm(view).current_track(), "", "戦闘が始まるまでは鳴らさない")
	_start(view)
	_step(view)
	var bgm := _bgm(view)
	assert_eq(bgm.current_track(), MUSHA_NORMAL, "戦闘が始まったら覚醒前の曲")
	assert_true(bgm.player.playing)
	assert_eq(bgm.player.bus, "Music")
	assert_gte(AudioServer.get_bus_index("Music"), 0, "Music バスがある")
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")), &"Master", "Music バスは Master へ送る")

func test_the_intro_plays_before_the_music_starts() -> void:
	var view := _fake_view()
	view._encounter.playing = true
	_start(view)
	_step(view)
	assert_eq(_bgm(view).current_track(), "", "登場演出の間は鳴らさない")
	view._encounter.playing = false
	_step(view)
	assert_eq(_bgm(view).current_track(), MUSHA_NORMAL, "登場が終わったら覚醒前の曲")

func test_awakening_silences_the_normal_track_then_starts_the_awakened_track() -> void:
	var view := _fake_view()
	var battle := _start(view)
	_step(view)
	var bgm := _bgm(view)
	# 行動が決まると戦闘はすぐ覚醒まで進むが、表示は演出が追いつくまで覚醒前のまま。
	battle.is_awakened = true
	view._presenter.playing = true
	_step(view)
	assert_eq(bgm.current_track(), MUSHA_NORMAL, "覚醒の演出が始まるまでは覚醒前の曲のまま")
	view._presenter.entry_started.emit({"action": "awakening", "actor": "boss"})
	_step(view, 0.3)
	assert_true(bgm.player.playing, "消している途中")
	assert_lt(bgm.player.volume_db, RBMBossBgm.volume_db("musha", false) - 3.0, "覚醒の演出が始まったら曲を小さくしていく")
	_step(view, 0.4)
	assert_eq(bgm.current_track(), "", "覚醒の演出の間は曲を消す(%.1f秒で)" % RBMBattleBgm.FADE_AWAKENING)
	view._presenter.entry_impact.emit({"action": "awakening", "actor": "boss", "visual_state": {"is_awakened": true}})
	_step(view)
	assert_eq(bgm.current_track(), MUSHA_AWAKENED, "覚醒が表示されたら覚醒後の曲")
	assert_almost_eq(bgm.player.volume_db, RBMBossBgm.volume_db("musha", true), 0.01, "覚醒後の曲は覚醒後の曲の音量で頭から")
	assert_eq(view.find_children("*", "AudioStreamPlayer", true, false).size(), 1, "再生器は1つだけ(2曲が同時に鳴らない)")
	view._presenter.playing = false
	_step(view)
	assert_eq(bgm.current_track(), MUSHA_AWAKENED, "覚醒後は戦闘が終わるまで覚醒後の曲")

func test_the_final_blow_fades_the_music_out_and_a_restart_plays_from_the_top() -> void:
	var view := _fake_view()
	var battle := _start(view)
	_step(view)
	var bgm := _bgm(view)
	battle.battle_over = true
	view._presenter.playing = true
	_step(view)
	assert_eq(bgm.current_track(), MUSHA_NORMAL, "とどめの命中までは鳴らす")
	view._presenter.entry_impact.emit({"action": "attack", "visual_state": {"battle_over": true, "winner": "ally"}})
	_step(view, 0.6)
	assert_true(bgm.player.playing, "とどめの命中から消していく")
	_step(view, 0.7)
	assert_eq(bgm.current_track(), "", "決着の後(勝利・敗北の演出と結果)は鳴らさない")
	view._presenter.playing = false
	_step(view)
	assert_eq(bgm.current_track(), "")
	# やり直し: 新しい戦闘
	_start(view)
	_step(view)
	assert_eq(bgm.current_track(), MUSHA_NORMAL, "やり直したら覚醒前の曲を頭から")
	assert_lt(bgm.player.get_playback_position(), 1.0)

func test_rewind_plays_the_track_of_the_state_it_returns_to() -> void:
	var view := _fake_view()
	var battle := _start(view)
	battle.is_awakened = true
	_step(view)
	var bgm := _bgm(view)
	assert_eq(bgm.current_track(), MUSHA_AWAKENED, "演出の無い時は、表示している状態(覚醒後)の曲")
	battle.is_awakened = false
	_step(view, 0.3)
	assert_eq(bgm.current_track(), MUSHA_NORMAL, "REWIND で覚醒前へ戻ったら覚醒前の曲")

## 戦闘の冒頭で覚醒する時: 登場の間に戦闘はもう覚醒しているが、覚醒の演出を見せるまでは覚醒後の曲にしない。
func test_an_awakening_at_the_start_waits_for_its_presentation() -> void:
	var view := _fake_view()
	view._encounter.playing = true
	var battle := _start(view)
	battle.is_awakened = true
	_step(view)
	var bgm := _bgm(view)
	assert_eq(bgm.current_track(), "", "登場の間は鳴らさない")
	# 登場が終わり、同じ処理の中で冒頭の演出(覚醒を含む)が始まる。
	view._encounter.playing = false
	view._presenter.playing = true
	_step(view)
	assert_eq(bgm.current_track(), MUSHA_NORMAL, "冒頭の覚醒の演出までは覚醒前の曲")
	view._presenter.entry_started.emit({"action": "awakening"})
	_step(view, 0.7)
	assert_eq(bgm.current_track(), "")
	view._presenter.entry_impact.emit({"action": "awakening", "visual_state": {"is_awakened": true}})
	_step(view)
	assert_eq(bgm.current_track(), MUSHA_AWAKENED)

func test_the_music_stops_when_the_screen_is_hidden() -> void:
	var view := _fake_view()
	_start(view)
	_step(view)
	var bgm := _bgm(view)
	_step(view, 5.0)
	view.visible = false
	_step(view)
	assert_false(bgm.player.playing, "画面が隠れたら(戦闘を出たら)すぐ止める")
	# 次の戦闘: 前の曲の続きを鳴らさず、頭から
	view.visible = true
	_start(view)
	_step(view)
	assert_eq(bgm.current_track(), MUSHA_NORMAL)
	assert_lt(bgm.player.get_playback_position(), 1.0, "次の戦闘は頭から(前の曲の続きを鳴らさない)")

func test_a_muted_battle_preview_plays_no_music() -> void:
	var view := _fake_view()
	view.sound.muted = true
	_start(view)
	_step(view)
	assert_eq(_bgm(view).current_track(), "", "戦闘の音を消したプレビュー(ホーム画面のモニター)では鳴らさない")
	assert_true(_bgm(view)._streams.is_empty(), "鳴らさない画面では曲を読まない")

## ホーム画面のモニターは戦闘を始める前に BGM を使わない設定にする（効果音を消すのは冒頭の演出の後なので）。
func test_a_disabled_bgm_plays_and_loads_nothing() -> void:
	var view := _fake_view()
	_bgm(view).enabled = false
	_start(view)
	_step(view)
	assert_eq(_bgm(view).current_track(), "", "使わない設定の画面では鳴らさない")
	assert_true(_bgm(view)._streams.is_empty(), "曲も読まない")

## 覚醒後の曲が無いボスは覚醒後も覚醒前の曲を続け、音量も覚醒前の曲の値のまま。
func test_a_boss_without_an_awakened_track_keeps_the_normal_track_and_its_volume() -> void:
	var view := _fake_view("appearance_golem")
	_bgm(view).table = {"golem": {"normal": "musha/musha_normal.ogg", "normal_db": 5.0, "awakened_db": 9.0}}
	var battle := _start(view)
	_step(view)
	assert_eq(_bgm(view).current_track(), MUSHA_NORMAL)
	assert_almost_eq(_bgm(view).player.volume_db, 5.0 + RBMBossBgm.ALL_DB, 0.01)
	battle.is_awakened = true
	_step(view, 0.3)
	assert_eq(_bgm(view).current_track(), MUSHA_NORMAL, "覚醒後も同じ曲")
	assert_almost_eq(_bgm(view).player.volume_db, 5.0 + RBMBossBgm.ALL_DB, 0.01, "音量も覚醒前の曲の値")

func test_a_boss_without_its_own_bgm_plays_nothing_in_battle() -> void:
	var view := _fake_view("appearance_golem")
	var battle := _start(view)
	_step(view)
	assert_eq(_bgm(view).current_track(), "", "専用の曲が無いボスは BGM なし(今までどおり)")
	battle.is_awakened = true
	_step(view)
	assert_eq(_bgm(view).current_track(), "")

## 演出の進行役は、出来事ごとに「始めた」→「命中」の順で知らせる(BGM はこれで覚醒の演出の始まりを知る)。
func test_the_presenter_announces_each_entry_before_its_impact() -> void:
	var presenter := RBMBattlePresenter.new()
	add_child_autofree(presenter)
	var order: Array = []
	presenter.entry_started.connect(func(e): order.append("start:" + str(e.get("action"))))
	presenter.entry_impact.connect(func(e): order.append("impact:" + str(e.get("action"))))
	presenter.play([{"action": "awakening", "visual_state": {}}, {"action": "attack", "visual_state": {}}], null)
	for i in range(4):
		await get_tree().process_frame
	assert_eq(order, ["start:awakening", "impact:awakening", "start:attack", "impact:attack"])

# ---------------------------------------------------------------------------
# 本物の TEST BATTLE・クリアチェック・挑戦の画面
# ---------------------------------------------------------------------------

func _draft(appearance_id: String, awaken := false) -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.appearance_id = appearance_id
	draft.boss_name = "BGM QA"
	draft.hp = 3000
	draft.atk = 1
	draft.spd = 1
	for id in ["hero", "butler", "healer", "samurai"]:
		draft.add_party_character(id)
	var skill := draft.add_skill({"name": "BGM QA skill", "type": "attack", "target": "single", "attribute": "FIRE", "atk_multiplier": 1.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[skill] = 100.0
	if awaken:
		# 最初の攻撃でボスのHPが減ったら覚醒する(条件なしだと戦闘の冒頭で覚醒してしまう)。
		draft.set_awakening({"conditions": [{"type": "hp_at_most", "percent": 99.9}], "condition_logic": "AND", "buff": {}, "heal": {}})
	return draft

func _open(mode: String, appearance_id: String, awaken := false) -> Control:
	var view: Control
	match mode:
		"test": view = RBMCreatorTestBattleView.new()
		"clear_check": view = RBMCreatorClearCheckView.new()
		_: view = RBMChallengeBattleView.new()
	add_child_autofree(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mode != "challenge":
		view.setup(null)
	view.set_boss_appearance(appearance_id)
	var definition := _draft(appearance_id, awaken).to_definition()
	if mode == "test":
		view.start(definition, 5)
	elif mode == "clear_check":
		view.start_battle(definition, 5)
	else:
		view.start_battle(definition, RBMBattleUiKit.ALL_VISIBLE, appearance_id)
	for i in range(4):
		await get_tree().process_frame
	return view

func test_every_battle_screen_plays_the_musha_track_and_no_track_for_other_bosses() -> void:
	for mode in ["test", "clear_check", "challenge"]:
		var musha := await _open(mode, "appearance_musha")
		assert_eq(_bgm(musha).current_track(), MUSHA_NORMAL, "%s: 武者の戦闘は覚醒前の曲" % mode)
		var golem := await _open(mode, "appearance_golem")
		assert_eq(_bgm(golem).current_track(), "", "%s: ゴーレムは今までどおり BGM なし" % mode)
		musha.queue_free()
		golem.queue_free()
		await get_tree().process_frame

func test_a_real_awakening_switches_to_the_awakened_track_in_every_battle_screen() -> void:
	for mode in ["test", "clear_check", "challenge"]:
		var view := await _open(mode, "appearance_musha", true)
		assert_eq(_bgm(view).current_track(), MUSHA_NORMAL, "%s: 覚醒前" % mode)
		var unit_id := int(view.session.battle.party[0].id)
		view.act_attack(unit_id)
		# 演出の無い画面では、前の曲を短く消してから覚醒後の曲にする。実時間で待つ。
		await get_tree().create_timer(RBMBattleBgm.FADE_SWITCH + 0.35).timeout
		await get_tree().process_frame
		assert_true(view.session.battle.is_awakened, "%s: 覚醒が成立した(HP 99.9%%以下)" % mode)
		assert_eq(_bgm(view).current_track(), MUSHA_AWAKENED, "%s: 覚醒後の曲に切り替わる" % mode)
		view.queue_free()
		await get_tree().process_frame
