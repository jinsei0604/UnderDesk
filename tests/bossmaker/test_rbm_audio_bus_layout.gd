extends GutTest

## ゲーム全体の音量（default_bus_layout.tres。Godot が起動時に読む）。
## 2026-10-17 ユーザーが B 案（全体 +3dB、BGM と効果音のつり合いはそのまま）に決定。Godot ではバスの音量はエフェクトの後に
## かかるので、+3dB は Master のリミッターの入口（pre_gain）でかけ、出口は上限 -1dB に抑える（音割れの安全網）。
## Master の音量は 0dB のまま（今後の音量の設定は、ここを 0dB 以下で動かす）。

func test_the_master_bus_raises_everything_by_3db_with_a_minus_1db_ceiling() -> void:
	assert_eq(ProjectSettings.get_setting("audio/buses/default_bus_layout"), "res://default_bus_layout.tres")
	assert_eq(AudioServer.get_bus_name(0), "Master")
	assert_eq(AudioServer.get_bus_volume_db(0), 0.0, "Master の音量は 0dB（+3dB はリミッターの入口でかける）")
	assert_eq(AudioServer.get_bus_effect_count(0), 1)
	var limiter := AudioServer.get_bus_effect(0, 0) as AudioEffectHardLimiter
	assert_not_null(limiter, "Master の最後にリミッター")
	assert_true(AudioServer.is_bus_effect_enabled(0, 0))
	assert_eq(limiter.pre_gain_db, 3.0, "全体 +3dB（B 案）")
	assert_eq(limiter.ceiling_db, -1.0, "出口は -1dB まで")

func test_the_music_bus_is_part_of_the_layout_and_sends_to_master() -> void:
	var music := AudioServer.get_bus_index("Music")
	assert_gt(music, 0, "BGM 用の Music バスは設定のファイルにある（実行時に作らなくてよい）")
	assert_eq(AudioServer.get_bus_send(music), &"Master")
	assert_eq(AudioServer.get_bus_volume_db(music), 0.0)
	assert_eq(RBMBattleBgm.ensure_bus(), "Music")
	assert_eq(AudioServer.get_bus_index("Music"), music, "ensure_bus は同じバスを使う（増やさない）")

## 覚醒後の武者の全体攻撃の刀の音（専用の再生器）は、全体の +3dB でも出口の上限を超えないよう -6dB 下げた。
## 音源の一番大きい部分（ノト・連打の部分はどちらも -0.9dBFS）＋ 再生の音量 ＋ 全体の +3dB で確かめる。
func test_the_musha_awakened_aoe_blade_sounds_fit_under_the_ceiling() -> void:
	var presentation := load("res://src/bossmaker/visuals/rbm_musha_awakened_frame_presentation.gd")
	var extra: float = presentation.get_script_constant_map().get("EXTRA_GAIN_DB", 0.0)
	assert_eq(extra, -6.0)
	var master_gain := (AudioServer.get_bus_effect(0, 0) as AudioEffectHardLimiter).pre_gain_db
	var flurry := -0.9 + 0.0 + extra + master_gain
	assert_lt(flurry, -3.0, "連打 1 回は出口で -3.9dBFS（重なっても余裕がある）")
	var source := FileAccess.get_file_as_string("res://src/bossmaker/visuals/rbm_musha_awakened_frame_presentation.gd")
	assert_true(source.contains("pl.volume_db = db + EXTRA_GAIN_DB"), "抜刀・振り・連打に -6dB")
	assert_true(source.contains("_noto_player.volume_db = NOTO_GAIN_DB"), "ノトは専用の値")
	var noto: float = presentation.get_script_constant_map().get("NOTO_GAIN_DB", 99.0)
	assert_eq(noto, -5.0, "ノトは +3dB → -5dB(本体の音の一番大きい所に重なるので、ほかの刀の音よりさらに 2dB 下げた)")
	assert_lt(-0.9 + noto + master_gain, -2.5, "ノト単体は出口で -2.9dBFS")
