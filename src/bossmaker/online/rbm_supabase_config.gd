class_name RBMSupabaseConfig
extends RefCounted

## Supabase最小接続PoC §2 — 接続情報（SUPABASE_URL/SUPABASE_PUBLISHABLE_KEY）
## の読み込み専用クラス。static funcのみ（RBMLocalStageRepositoryと同じ
##「新しいアーキテクチャ/autoloadを導入しない」既存方針を踏襲——このリポジ
## トリにはautoload/Singletonが1つも無く、utilityは全てstaticクラス）。
##
## 値の解決優先順位:
##   1. 環境変数（OS.get_environment、CI/自動テストでの上書きを想定）
##   2. ローカル設定ファイル（res://supabase_poc.local.env、.gitignore対象、
##      実値はコミットしない）
##   3. 配布版（書き出した版）だけ: 配布用の公開設定ファイル（res://supabase_public.env。
##      Project URL と Publishable key の2つだけ。2026-10-18、P0: ローカル設定ファイルは
##      書き出しに入らないため、配布版ではオンラインがすべて失敗していた）
##   4. どれにも無ければ空文字列（呼び出し側がエラーとして扱う）
## 3. を配布版だけにするのは、エディター・GUT・検証の道具が今までどおり「設定なし」で
## 動くように（ファイルがあっても、テストが本物の Supabase へ出ていかない）。
##
## Secret key/service_role keyはこのクラスが一切扱わない対象——読み込む
## キーは常にSUPABASE_URL/SUPABASE_PUBLISHABLE_KEYの2つのみ。さらに、どこから読んだ値でも
## 秘密の鍵（sb_secret_… や role が service_role の JWT）なら使わない（空として扱う）。

const ENV_URL_KEY := "SUPABASE_URL"
const ENV_KEY_KEY := "SUPABASE_PUBLISHABLE_KEY"

## res://直下——プロジェクトのgit管理ツリー内に置く（.gitignoreで除外する
## ため、user://のようなツリー外の場所に置く必要が無い。exampleファイルと
## 対にして「テンプレートは共有、実値はローカルのみ」を素直に表現する）。
const DEFAULT_LOCAL_CONFIG_PATH := "res://supabase_poc.local.env"

## テスト専用のフック: RBMLocalStageRepository.set_stages_dir_for_testing()
## と同じ既存の流儀——実際のsupabase_poc.local.env（開発者が実値を書く場所）
## へ一切触れずに、ローカル設定ファイルの読み込み挙動をテストできるように
## する。空文字列ならDEFAULT_LOCAL_CONFIG_PATHを使う（通常時の既定動作）。
static var _local_config_path_override: String = ""

## 配布用の公開設定ファイル。書き出しの設定（export_presets.cfg）の include_filter で pck に入れる。
## 作り方: tools/make_supabase_public_config.gd（ローカル設定ファイルか環境変数から、検査して書く）。
const DEFAULT_PUBLIC_CONFIG_PATH := "res://supabase_public.env"

## テスト専用のフック（配布用の公開設定ファイルの場所・配布版かどうか）。空文字列・-1 なら通常の動作。
static var _public_config_path_override: String = ""
static var _distribution_build_override: int = -1

static func public_config_path() -> String:
	return _public_config_path_override if not _public_config_path_override.is_empty() else DEFAULT_PUBLIC_CONFIG_PATH

static func set_public_config_path_for_testing(path: String) -> void:
	_public_config_path_override = path

## on: 1=配布版として扱う、0=エディターとして扱う、-1=本当の状態（OS.has_feature("template")）。
static func set_distribution_build_for_testing(on: int) -> void:
	_distribution_build_override = on

## 書き出した版（エクスポートテンプレートで動いている）か。
static func is_distribution_build() -> bool:
	if _distribution_build_override >= 0:
		return _distribution_build_override == 1
	return OS.has_feature("template")

static func local_config_path() -> String:
	return _local_config_path_override if not _local_config_path_override.is_empty() else DEFAULT_LOCAL_CONFIG_PATH

static func set_local_config_path_for_testing(path: String) -> void:
	_local_config_path_override = path

static func url() -> String:
	return _resolve(ENV_URL_KEY)

static func publishable_key() -> String:
	return _resolve(ENV_KEY_KEY)

## §8: 「URL未設定」「Publishable key未設定」を個別に区別できるようにする
## ——呼び出し側（RBMSupabaseClient）がこの2つを別々に呼んで判定する。
static func is_configured() -> bool:
	return not url().is_empty() and not publishable_key().is_empty()

static func _resolve(key: String) -> String:
	var value := _resolve_raw(key)
	if key == ENV_KEY_KEY and is_secret_key(value):
		# 秘密の鍵は、どこから来ても送らない（ゲームの中に入れてはいけない鍵）
		push_warning("RBMSupabaseConfig: a secret/service_role key was supplied; it is ignored (only the publishable key may be used).")
		return ""
	return value

static func _resolve_raw(key: String) -> String:
	var from_env := OS.get_environment(key)
	if not from_env.is_empty():
		return from_env
	var from_local: String = _read_local_file().get(key, "")
	if not from_local.is_empty():
		return from_local
	if is_distribution_build():
		return _read_file(public_config_path()).get(key, "")
	return ""

## どこから読んだか（"env"・"local"・"public"・""）。値は返さない（記録・確認の表示用）。
static func source() -> String:
	if not OS.get_environment(ENV_URL_KEY).is_empty():
		return "env"
	if not str(_read_local_file().get(ENV_URL_KEY, "")).is_empty():
		return "local"
	if is_distribution_build() and not str(_read_file(public_config_path()).get(ENV_URL_KEY, "")).is_empty():
		return "public"
	return ""

## 秘密の鍵か（sb_secret_… の新しい形式、または role が service_role の JWT）。
static func is_secret_key(key: String) -> bool:
	if key.begins_with("sb_secret_"):
		return true
	return _jwt_role(key) == "service_role"

## 配布物に入れてよい公開用の鍵か（sb_publishable_… の新しい形式、または role が anon の JWT）。
static func is_public_key(key: String) -> bool:
	if key.begins_with("sb_publishable_") and key.length() > "sb_publishable_".length():
		return true
	return _jwt_role(key) == "anon"

## 配布用の公開設定として書いてよい値か。良ければ空文字列、だめなら理由（値そのものは含めない）。
static func public_values_problem(url: String, key: String) -> String:
	if url.is_empty():
		return "SUPABASE_URL is empty"
	if not url.begins_with("https://"):
		return "SUPABASE_URL must start with https://"
	if key.is_empty():
		return "SUPABASE_PUBLISHABLE_KEY is empty"
	if is_secret_key(key):
		return "SUPABASE_PUBLISHABLE_KEY is a secret/service_role key; never ship it"
	if not is_public_key(key):
		return "SUPABASE_PUBLISHABLE_KEY is not a publishable key (sb_publishable_... or an anon JWT)"
	return ""

## JWT の payload の role（JWT でなければ ""）。署名は確かめない（種類を見分けるだけ）。
static func _jwt_role(token: String) -> String:
	var parts := token.split(".")
	if parts.size() != 3:
		return ""
	var b64 := parts[1].replace("-", "+").replace("_", "/")
	while b64.length() % 4 != 0:
		b64 += "="
	var raw := Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		return ""
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if parsed is Dictionary:
		return str((parsed as Dictionary).get("role", ""))
	return ""

## 「KEY=value」形式（.envと同じ、指示書のテンプレート表記どおり）を1行ずつ
## 読むだけの最小限のパーサー——Godot標準のConfigFileはINIの[section]見出し
## を要求し指示書の"SUPABASE_URL="という平坦な表記と噛み合わないため、
## ライブラリを追加せず自前の数行で対応する。
## 空行・"#"始まりの行はコメントとして無視する。値の前後空白は取り除く。
static func _read_local_file() -> Dictionary:
	return _read_file(local_config_path())

static func _read_file(path: String) -> Dictionary:
	var result: Dictionary = {}
	if not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var separator_index := line.find("=")
		if separator_index <= 0:
			continue
		var key := line.substr(0, separator_index).strip_edges()
		var value := line.substr(separator_index + 1).strip_edges()
		result[key] = value
	return result
