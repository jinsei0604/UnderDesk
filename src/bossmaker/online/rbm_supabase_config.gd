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
##   3. どちらにも無ければ空文字列（呼び出し側がエラーとして扱う）
##
## Secret key/service_role keyはこのクラスが一切扱わない対象——読み込む
## キーは常にSUPABASE_URL/SUPABASE_PUBLISHABLE_KEYの2つのみ。

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
	var from_env := OS.get_environment(key)
	if not from_env.is_empty():
		return from_env
	return _read_local_file().get(key, "")

## 「KEY=value」形式（.envと同じ、指示書のテンプレート表記どおり）を1行ずつ
## 読むだけの最小限のパーサー——Godot標準のConfigFileはINIの[section]見出し
## を要求し指示書の"SUPABASE_URL="という平坦な表記と噛み合わないため、
## ライブラリを追加せず自前の数行で対応する。
## 空行・"#"始まりの行はコメントとして無視する。値の前後空白は取り除く。
static func _read_local_file() -> Dictionary:
	var result: Dictionary = {}
	var path := local_config_path()
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
