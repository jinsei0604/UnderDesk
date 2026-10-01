class_name RBMBattleBackgrounds
extends RefCounted

## 戦闘背景の選び方(表示専用)。戦闘の状態・乱数・行動順・保存データは読まず、変えない。
##
## TEST BATTLE・クリアチェック・挑戦(ホーム画面のモニターも挑戦画面を使う)は、どれも
## rbm_fullscreen_battle_ui.gd がここを通して背景を決めるので、同じボスなら同じ背景になる。
##
## 背景の決まり方(上から順に、使えるものを使う。覚醒後も同じ背景):
##   1. BOSS_BACKGROUNDS に書いた上書き(特別なパスを使いたいときだけ。普段は空)
##   2. 命名規則: assets_bossmaker/battle/backgrounds/<boss_id>/background.png
##   3. Creator の「昼/夜」で選んだ標準背景(中庭)
## 専用背景が無いのは正常な状態で、エラーにしない。
##
## 専用背景の追加手順(例: 朽ちた機械武者):
##   1. 画像を assets_bossmaker/battle/backgrounds/musha/background.png として置く
##   2. Godot エディタを一度開いて画像を取り込む(.import ができる)
## これだけで武者の戦闘に使われる。このファイルや他のボス・戦闘のコードは触らなくてよい。

const ROOT := "res://assets_bossmaker/battle/backgrounds/"
## 命名規則の背景(%s に boss_id が入る)。
const CONVENTION := "res://assets_bossmaker/battle/backgrounds/%s/background.png"
## 標準背景(Creator の「昼/夜」。"day" 以外はすべて夜)。
const STANDARD := {
	"day": "res://assets_bossmaker/art/battle_courtyard_day.png",
	"night": "res://assets_bossmaker/art/battle_courtyard_night.png",
}
## 任意の上書き: boss_id(RBMVisualAssets.APPEARANCES の値) → 背景のパス。命名規則の背景より優先する。
## ROOT からの相対パスか、res:// から始まるパスを書く。例: "musha": "musha/background_winter.png"
## 書いたパスが使えないときは、命名規則の背景 → 標準背景の順に使う。
const BOSS_BACKGROUNDS := {}

## 上書きに書いたのに使えなかったパス(警告は1パスにつき1回だけ)。
static var _warned: Dictionary = {}

static func standard_path(time_of_day: String) -> String:
	return str(STANDARD["day"]) if time_of_day == "day" else str(STANDARD["night"])

## 上書きとして書かれているパス(res:// から)。未設定なら空文字。
static func configured_path(boss_id: String, table: Dictionary = BOSS_BACKGROUNDS) -> String:
	var entry: Variant = table.get(_base_id(boss_id), "")
	if not entry is String:
		return ""
	var path := (entry as String).strip_edges()
	if path.is_empty():
		return ""
	return path if path.begins_with("res://") else ROOT + path

## 命名規則の背景のパス(ファイルがあるかは見ない)。boss_id が空なら空文字。
static func convention_path(boss_id: String, convention: String = CONVENTION) -> String:
	var base := _base_id(boss_id)
	return "" if base.is_empty() else convention % base

## 使う背景のパス。上書き → 命名規則 → 標準背景の順。
static func path_for(boss_id: String, time_of_day: String, table: Dictionary = BOSS_BACKGROUNDS, convention: String = CONVENTION) -> String:
	var override := configured_path(boss_id, table)
	if not override.is_empty():
		if _load(override) != null:
			return override
		if not _warned.has(override):
			_warned[override] = true
			push_warning("上書き設定の戦闘背景 %s を画像として読めないため、命名規則の背景か標準背景を使います" % override)
	var named := convention_path(boss_id, convention)
	if _load(named) != null:
		return named
	return standard_path(time_of_day)

## 使う背景の画像。上書き → 命名規則 → 標準背景の順。
static func texture_for(boss_id: String, time_of_day: String, table: Dictionary = BOSS_BACKGROUNDS, convention: String = CONVENTION) -> Texture2D:
	return _load(path_for(boss_id, time_of_day, table, convention))

static func _base_id(boss_id: String) -> String:
	return boss_id.trim_suffix(RBMVisualAssets.AWAKENED_SUFFIX)

## 画像として読めるときだけ読む(無いファイルを load してエラーを出さない)。
static func _load(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		return null
	return load(path) as Texture2D
