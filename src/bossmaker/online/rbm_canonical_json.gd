class_name RBMCanonicalJson
extends RefCounted

## Phase 4B — 決定論的なJSON直列化。battle_hash計算専用に使う。
##
## なぜ必要か: 通常のJSON.stringify(dictionary)はDictionaryのキー挿入順を
## そのまま出力するため、意味的に同じ内容でも構築経路が変わるとテキストが
## 変わり、そこから作るhashも変わってしまう(ユーザー確定仕様「Dictionary
## 順序等でhashが変わらないよう、canonical serializationを使用する」)。
##
## 方式: Dictionaryのキーを再帰的に文字列ソートしてから直列化する。Arrayは
## 要素の並び順が意味を持つ場面がある(action_sequence等)ため、並び順を
## 変更せずそのまま直列化する。プリミティブ値(String/int/float/bool/null)
## はGodot標準のJSON.stringify()へ委譲し、独自のフォーマットは持たない
## (数値の書式ゆれ等をこのプロジェクトで再発明しない)。
##
## 用途: battle_hashはGodotクライアント側でのみ計算・比較する(公開時に
## Makerのクライアントが計算してサーバーへ送り、挑戦時にChallengerの
## クライアントがダウンロードしたpayloadから再計算して突き合わせる)。
## Edge Function(Deno/TypeScript)側はこの値を不透明な文字列として保存
## するだけで、独自に再計算しない——GDScriptとDenoで数値直列化の細部
## (float表記等)を厳密に一致させ続ける必要をそもそも作らないための設計。

static func stringify(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			return _stringify_dictionary(value)
		TYPE_ARRAY:
			return _stringify_array(value)
		_:
			return JSON.stringify(value)

static func _stringify_dictionary(dict: Dictionary) -> String:
	var keys: Array = dict.keys()
	var string_keys: Array[String] = []
	for key in keys:
		string_keys.append(str(key))
	string_keys.sort()
	var parts: Array[String] = []
	for key in string_keys:
		parts.append("%s:%s" % [JSON.stringify(key), stringify(dict[key])])
	return "{%s}" % ",".join(parts)

static func _stringify_array(array: Array) -> String:
	var parts: Array[String] = []
	for element in array:
		parts.append(stringify(element))
	return "[%s]" % ",".join(parts)

## SHA-256 hex digest of the canonical serialization. Used as battle_hash.
static func hash_of(value: Variant) -> String:
	return stringify(value).sha256_text()
