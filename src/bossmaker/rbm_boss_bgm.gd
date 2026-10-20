class_name RBMBossBgm
extends RefCounted

## ボス専用BGMの選び方(音の専用)。戦闘の状態・乱数・行動順・保存データは読まず、変えない。
## 鳴らすのは rbm_battle_bgm.gd(TEST BATTLE・クリアチェック・挑戦の画面が1つずつ持つ)。
##
## 曲の決まり方(上から順に、使えるものを使う):
##   1. BOSS_BGM に書いた上書き(特別なパスを使いたいときだけ)
##   2. 命名規則: assets_bossmaker/audio/bgm/<boss_id>/<boss_id>_normal.ogg(覚醒前・覚醒の無いボスの1曲)
##                assets_bossmaker/audio/bgm/<boss_id>/<boss_id>_awakened.ogg(覚醒後)
##   3. 覚醒後の曲が無いときは覚醒前の曲を続ける。どちらも無いボスは今までどおり BGM なし(エラーにしない)。
##
## 曲の追加手順(例: 竜の覚醒前・覚醒後):
##   1. dragon_normal.ogg・dragon_awakened.ogg を assets_bossmaker/audio/bgm/dragon/ に置く
##   2. Godot で取り込み、.import の loop を true にする(assets_bossmaker/audio/bgm/README.md)
##   3. 曲の大きさ(LUFS)を測り、BOSS_BGM に音量の調整を書く(REFERENCE_LUFS にそろえる。下の musha が例)
## これだけで竜の戦闘に使われる。戦闘のコードは触らなくてよい。

const ROOT := "res://assets_bossmaker/audio/bgm/"
## 命名規則の曲(1つ目と2つ目の %s に boss_id、3つ目に "normal" か "awakened" が入る)。
const CONVENTION := "res://assets_bossmaker/audio/bgm/%s/%s_%s.ogg"
const NORMAL := "normal"
const AWAKENED := "awakened"
## 曲ごとの大きさをそろえる目安(曲全体のラウドネス)。曲ごとの音量の調整 = REFERENCE_LUFS − その曲の LUFS。
## 測り方: ffmpeg -i <曲> -af ebur128 -f null - の最後の「I:」。
const REFERENCE_LUFS := -24.0
## 全部のボスの BGM をまとめて上げ下げする(dB)。曲ごとの調整に足す。
## 2026-10-17 ユーザー: 攻撃の効果音と合わせるため、ほんの少し下げる(-3dB。実際に鳴る大きさは -27 LUFS 相当)。
const ALL_DB := -3.0
## boss_id(RBMVisualAssets.APPEARANCES の値) → 曲ごとの設定。書いた項目だけが使われる。
##   "normal_db" / "awakened_db": 曲を鳴らす音量の調整(dB。曲のファイルは変えない。書かなければ 0)
##   "normal" / "awakened": 命名規則と違うパスを使う時だけ(ROOT からの相対パスか res:// から始まるパス)
const BOSS_BGM := {
	# 朽ちた機械武者(2026-10-17 測定: 覚醒前 -34.3 LUFS・覚醒後 -37.9 LUFS → -24 LUFS にそろえる)
	"musha": {"normal_db": 10.3, "awakened_db": 13.9},
}

## 上書きに書いたのに使えなかったパス(警告は1パスにつき1回だけ)。
static var _warned: Dictionary = {}

static func state_name(awakened: bool) -> String:
	return AWAKENED if awakened else NORMAL

## 命名規則の曲のパス(ファイルがあるかは見ない)。boss_id が空なら空文字。
static func convention_path(boss_id: String, awakened: bool, convention: String = CONVENTION) -> String:
	var base := _base_id(boss_id)
	return "" if base.is_empty() else convention % [base, base, state_name(awakened)]

## 上書きとして書かれているパス(res:// から)。未設定なら空文字。
static func configured_path(boss_id: String, awakened: bool, table: Dictionary = BOSS_BGM) -> String:
	var entry: Variant = table.get(_base_id(boss_id), {})
	if not entry is Dictionary:
		return ""
	var value: Variant = (entry as Dictionary).get(state_name(awakened), "")
	if not value is String:
		return ""
	var path := (value as String).strip_edges()
	if path.is_empty():
		return ""
	return path if path.begins_with("res://") else ROOT + path

## 鳴らす曲のパス。上書き → 命名規則 →(覚醒後なら)覚醒前の曲 → 無し(空文字)。
static func path_for(boss_id: String, awakened: bool, table: Dictionary = BOSS_BGM, convention: String = CONVENTION) -> String:
	var path := _usable(boss_id, awakened, table, convention)
	if path.is_empty() and awakened:
		path = _usable(boss_id, false, table, convention)
	return path

## 曲を鳴らす音量の調整(dB)。曲ごとの "normal_db" / "awakened_db"(無ければ 0)に ALL_DB を足す。
## 覚醒後の曲が無く覚醒前の曲を続ける時は、覚醒前の曲の値を使う(rbm_battle_bgm.gd)。
static func volume_db(boss_id: String, awakened: bool, table: Dictionary = BOSS_BGM) -> float:
	var entry: Variant = table.get(_base_id(boss_id), {})
	var value: Variant = (entry as Dictionary).get(state_name(awakened) + "_db", 0.0) if entry is Dictionary else 0.0
	return (float(value) if value is float or value is int else 0.0) + ALL_DB

## 曲を読み、戦闘の間ループするようにする(取り込みの設定を忘れていても途切れないように)。
static func load_stream(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path, "AudioStream"):
		return null
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	return stream

static func _usable(boss_id: String, awakened: bool, table: Dictionary, convention: String) -> String:
	var override := configured_path(boss_id, awakened, table)
	if not override.is_empty():
		if ResourceLoader.exists(override, "AudioStream"):
			return override
		if not _warned.has(override):
			_warned[override] = true
			push_warning("上書き設定のボスBGM %s を曲として読めないため、命名規則の曲を使います" % override)
	var named := convention_path(boss_id, awakened, convention)
	if not named.is_empty() and ResourceLoader.exists(named, "AudioStream"):
		return named
	return ""

static func _base_id(boss_id: String) -> String:
	return boss_id.trim_suffix(RBMVisualAssets.AWAKENED_SUFFIX)
