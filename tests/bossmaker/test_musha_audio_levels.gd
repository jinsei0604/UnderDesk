extends GutTest
## 朽ちた機械武者の完成トラックの音量が、既存の音と揃っていること(回帰テスト)。
##
## 実測: 各WAVの「最も大きい100msのRMS」(dBFS)を、実際に鳴らす時の補正ゲイン
## (RBMMushaMotion.TRACK_GAIN_DB)込みで、同種の既存の音と比べる。録音そのものは
## 変えず、再生ゲインだけで揃える。
const Catalog = preload("res://src/bossmaker/rbm_audio_catalog.gd")
const Motion = preload("res://src/bossmaker/visuals/rbm_musha_motion.gd")
## RBMAudio.play_sound()の基準音量(volume_db = BASE + gain)。
const BASE_DB := -9.0

## 「最も大きい100msのRMS」と「サンプルのピーク」(いずれもdBFS)。
func _levels(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, path)
	var bytes := f.get_buffer(f.get_length())
	var pos := 12
	var channels := 2
	var rate := 48000
	var data_at := -1
	var data_len := 0
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		if id == "fmt ":
			channels = bytes.decode_u16(pos + 10)
			rate = bytes.decode_u32(pos + 12)
			assert_eq(bytes.decode_u16(pos + 22), 16, "16-bit PCM: " + path)
		elif id == "data":
			data_at = pos + 8
			data_len = size
			break
		pos += 8 + size + (size % 2)
	assert_gte(data_at, 0, "data chunk: " + path)
	var frames := data_len / (2 * channels)
	var window := int(rate * 0.1)
	var peak := 0.0
	var loudest := 0.0
	var acc := 0.0
	var n := 0
	for i in range(frames):
		var v := 0.0
		for c in range(channels):
			v += float(bytes.decode_s16(data_at + (i * channels + c) * 2)) / 32768.0
		v /= channels
		peak = maxf(peak, absf(v))
		acc += v * v
		n += 1
		if n >= window:
			loudest = maxf(loudest, acc / n)
			acc = 0.0
			n = 0
	return {"loudest_db": 10.0 * log(maxf(loudest, 1e-12)) / log(10.0), "peak_db": 20.0 * log(maxf(peak, 1e-6)) / log(10.0)}

func _played_loudest(key: String) -> float:
	return float(_levels(Catalog.FILES[key]).loudest_db) + Motion.track_gain(key)

func test_the_normal_single_matches_the_existing_dedicated_boss_track() -> void:
	var reference := float(_levels(Catalog.FILES["dragon_normal_breath"]).loudest_db)
	assert_almost_eq(_played_loudest("musha_single"), reference, 1.0, "musha single vs the dragon's normal breath")
	assert_almost_eq(_played_loudest("musha_aoe"), reference, 1.0, "musha all-attack vs the dragon's normal breath")

func test_awakening_tracks_sit_in_the_range_of_the_dragon_awakening_tracks() -> void:
	var dragon: Array = []
	for key in ["dragon_awakened_breath", "dragon_awakened_meteors", "dragon_awakening"]:
		dragon.append(float(_levels(Catalog.FILES[key]).loudest_db))
	var low: float = dragon.min() - 1.5
	var high: float = dragon.max() + 1.5
	for key in ["musha_awakening", "musha_awakened_single", "musha_awakened_aoe"]:
		var level := _played_loudest(key)
		assert_between(level, low, high, "%s (%.1f dB) is inside the existing awakening tracks' range [%.1f, %.1f]" % [key, level, low, high])

func test_the_relative_balance_of_the_approved_tracks_is_kept() -> void:
	# 承認済みの音の強弱(覚醒後の全体 > 覚醒後の単体 > 通常)は、一律ゲインなので変わらない。
	var raw := {}
	for key in ["musha_single", "musha_awakened_single", "musha_awakened_aoe"]:
		raw[key] = float(_levels(Catalog.FILES[key]).loudest_db)
	assert_gt(_played_loudest("musha_awakened_aoe"), _played_loudest("musha_awakened_single"))
	assert_gt(_played_loudest("musha_awakened_single"), _played_loudest("musha_single"))
	for key in raw:
		assert_almost_eq(_played_loudest(key) - float(raw[key]), 3.0, 0.001)

func test_support_tracks_match_the_existing_support_cues() -> void:
	var reference := (float(_levels(Catalog.FILES["heal_hp"]).loudest_db) + float(_levels(Catalog.FILES["buff_atk"]).loudest_db)) / 2.0
	assert_almost_eq(_played_loudest("musha_buff"), reference, 1.5, "buff vs the existing support cues")
	assert_almost_eq(_played_loudest("musha_heal"), reference, 1.5, "heal vs the existing support cues")
	assert_eq(Motion.track_gain("musha_buff"), Motion.track_gain("musha_heal"), "buff and heal stay identical apart from colour")

func test_no_track_clips_after_the_gain_is_applied() -> void:
	for key in Motion.TRACK_GAIN_DB:
		var peak := float(_levels(Catalog.FILES[key]).peak_db) + BASE_DB + Motion.track_gain(key)
		assert_lt(peak, -1.0, "%s peaks at %.1f dBFS after gain" % [key, peak])

func test_every_gain_is_for_a_registered_track_and_nothing_else_is_boosted() -> void:
	for key in Motion.TRACK_GAIN_DB:
		assert_true(Catalog.FILES.has(key), key)
	assert_eq(Motion.track_gain("fire_cast"), 0.0, "other sounds are not touched")

func test_presentations_play_the_tracks_with_their_gain() -> void:
	# 実際にRBMAudioへ渡るゲインを、再生履歴ではなくプレイヤーの音量で確認する。
	var audio: Node = load("res://src/bossmaker/rbm_audio.gd").new()
	add_child_autofree(audio)
	await get_tree().process_frame
	for key in Motion.TRACK_GAIN_DB:
		audio.play_sound(key, Motion.track_gain(key))
		var expected := BASE_DB + Motion.track_gain(key)
		var found := false
		for player in audio._players:
			if player.playing and absf(player.volume_db - expected) < 0.001:
				found = true
		assert_true(found, "%s plays at %.1f dB" % [key, expected])
	audio.stop_all()
