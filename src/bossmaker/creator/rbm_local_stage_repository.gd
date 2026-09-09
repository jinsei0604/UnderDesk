class_name RBMLocalStageRepository
extends RefCounted

## Phase 1 Step 6 — ローカル保存I/O層（1 stage = 1 JSONファイル、
## user://bossmaker/stages/<stage_id>.json）。全メソッドstatic、インスタンス化
## しない（RBMDataLoader/UDSaveManagerと同じ、このプロジェクトの既存ユーティリ
## ティクラス規約）。
##
## §45: 保存I/OはCreator UIへ直接散らさない——RBMCreatorMainはこのクラスの
## static funcだけを呼び、FileAccess/DirAccess/JSONへ直接触れない。
##
## §7: BossBattleDefinitionはここへ保存しない。draft.to_saved_dict()（生の
## 著作フィールド）とdraft.clear_check_snapshot_for_save()（過去の証明）だけを
## 保存する。DefinitionはRBMCreatorDraft.to_definition()からいつでも純粋関数的
## に再生成できるため、ここで別途保存すると二重管理・鮮度ズレの原因になる。
##
## §22: draft/playable/clear_checkedという状態フラグはJSONへ保存しない。
## list()がロードのたびに都度算出する（RBMDefinitionLoader.resolve()と
## draft.is_clear_check_currently_valid()はどちらも副作用のない純粋計算で、
## キャッシュする必要がない）。

const SAVE_FORMAT_VERSION := 2
const LEGACY_SAVE_FORMAT_VERSION := 1
const DEFAULT_STAGES_DIR := "user://bossmaker/stages"

## §48テスト専用のフック: 実プレイヤーのローカル保存ライブラリへ一切触れずに
## テストできるよう、保存先を差し替え可能にする。空文字列なら
## DEFAULT_STAGES_DIRを使う（通常プレイ時の既定動作）。
static var _stages_dir_override: String = ""

static func stages_dir() -> String:
	return _stages_dir_override if not _stages_dir_override.is_empty() else DEFAULT_STAGES_DIR

static func set_stages_dir_for_testing(path: String) -> void:
	_stages_dir_override = path

# ---------------------------------------------------------------------------
# stage_id (§3/§4/§53)
# ---------------------------------------------------------------------------

static func _random_stage_id() -> String:
	var digits := ""
	for i in range(10):
		digits += str(randi_range(0, 9))
	return digits

## §53テスト専用のtestability seam: 空でなければこの配列の先頭を1つ消費して
## 候補として使う（本番プレイでは常に空のまま、_random_stage_id()の乱数生成
## だけを使う——本番挙動は一切変更していない）。これにより
## generate_unique_stage_id()の「1回目の候補が既存stage_idと衝突した場合に
## 再生成する」分岐そのものを、大量試行に頼らず決定論的にテストできる。
static var _forced_candidates_for_testing: Array[String] = []

static func set_forced_candidates_for_testing(candidates: Array[String]) -> void:
	_forced_candidates_for_testing = candidates.duplicate()

static func _next_id_candidate() -> String:
	if not _forced_candidates_for_testing.is_empty():
		return _forced_candidates_for_testing.pop_front()
	return _random_stage_id()

## §4: 各桁を0〜9のランダム数字として生成し10文字連結、ローカルstage_id集合と
## 照合して衝突していれば再生成する。
static func generate_unique_stage_id() -> String:
	var candidate := _next_id_candidate()
	while exists(candidate):
		candidate = _next_id_candidate()
	return candidate

static func _is_valid_stage_id(id: String) -> bool:
	if id.length() != 10:
		return false
	for i in range(id.length()):
		if not id[i].is_valid_int():
			return false
	return true

static func exists(stage_id: String) -> bool:
	if not _is_valid_stage_id(stage_id):
		return false
	return FileAccess.file_exists(_stage_path(stage_id))

static func _stage_path(stage_id: String) -> String:
	return "%s/%s.json" % [stages_dir(), stage_id]

# ---------------------------------------------------------------------------
# atomic save (§2/§15/§61): tempへ書き込み -> rename で本番ファイルへ置換。
# 書き込み途中でクラッシュしても既存の本番ファイルは無傷のまま残る。
# ---------------------------------------------------------------------------

## 最終レビュー対応§3-2テスト専用のtestability seam: trueの間、
## _atomic_write()はrenameへ到達する直前で必ず失敗を模擬する（実際に
## dir.rename()を呼ばず、tmpファイルもそのまま残す——「renameを試みて
## エラーが返った」場合ではなく「renameへ到達する前に処理が中断した」
## 場合を忠実に再現するため、既存の失敗経路のようなtmp削除はしない）。
## 本番プレイでは常にfalseのまま、通常のtmp書き込み->rename経路を使う。
static var _force_rename_failure_for_testing: bool = false

static func set_force_rename_failure_for_testing(force: bool) -> void:
	_force_rename_failure_for_testing = force

## CHALLENGE UI再設計 §4-E/§4-F（挑戦者数・クリア者数のサイドカーストア）
## 実装時に発見・修正した実機バグ: この関数は元々"DirAccess.open(stages_dir())"
## を決め打ちしていた——これはstages_dir()以外のディレクトリへは一度も
## 書き込んだことが無い既存コードの間は無害だったが、新設のstage_stats/
## サイドカー（stages_dir()とは別ディレクトリ）へこの関数をそのまま再利用
## した際、Windows実機で実際に危険な副作用を引き起こすことをheadless再現
## スクリプトで確認した: dir(stages_dir()に固定)に対しdir.rename(bare_name)
## を呼ぶと、rename元(tmp)が実際にはdirの外（stage_stats/）にあるため
## renameは失敗する(err!=OK)のに、**dirの中に同名の別ファイルが実在すれば
## （ここでは同じstage_idを共有するstages/<id>.jsonという本物のstageファイル
## が該当）、そのファイルが黙って削除される**——rename失敗時に対象ファイルは
## 無傷のはずという既存の前提（このファイル自身の設計コメント・
## test_atomic_save_a_stray_tmp_write_never_corrupts_the_production_file等の
## 既存テストが検証している保証）が、呼び出し元のパスがstages_dir()の外に
## ある場合には成立しないと判明した。
## 修正: DirAccess自体をpath自身の実際の親ディレクトリ(path.get_base_dir())
## から開く——stages_dir()決め打ちをやめ、真に「そのpathが属するディレクトリ
## の中だけでrenameする」形にした。stages_dir()配下への既存の全呼び出し
## （path.get_base_dir()は結局stages_dir()と一致する）は無改修のまま同じ
## 経路を通るため、既存のsave_new()/overwrite()の実際の書き込み挙動に
## 変化は無い（回帰テストで確認済み）。
static func _atomic_write(path: String, text: String) -> bool:
	var target_dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(target_dir)
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	if _force_rename_failure_for_testing:
		return false
	var dir := DirAccess.open(target_dir)
	if dir == null:
		DirAccess.remove_absolute(tmp_path)
		return false
	var rename_err := dir.rename(tmp_path.get_file(), path.get_file())
	if rename_err != OK:
		DirAccess.remove_absolute(tmp_path)
		return false
	return true

# ---------------------------------------------------------------------------
# CHALLENGE UI再設計 §4-E/§4-F/§10: 挑戦回数・クリア回数。
#
# 調査結果（実装前調査§8/§9/§10）: このプロジェクトには「挑戦回数」
# 「クリア回数」「クリア率」を記録する仕組みが一切存在しなかった
# （src/bossmaker/全体をgrepしても該当ゼロ）。指示書§F/§Gは「既存の定義を
# 変更しない」ことを求めているが、そもそも定義自体が存在しないため、
# §24/無人作業時ルールの「安全な最小差分で追加できる場合は実装してよい」に
# 従い、以下の最小限の仕組みを新設した——完了報告で開示する判断:
#
# ・「挑戦回数」= そのstageで実際に戦闘が開始された回数（一覧/確認画面から
#   「このボスに挑戦」を押した回数、同じユーザーの複数回挑戦もそれぞれ
#   加算される「人数」ではなく「回数」）。同一セッション内の「最初から
#   やり直す」は新たな挑戦としてカウントしない（同じ試行の継続とみなす、
#   判断——完了報告で開示）。CHALLENGE discovery 最終調整（後日追加）:
#   フィールド名を「挑戦者数（challenger_count）」から「挑戦回数
#   （challenge_count）」へ改名した——旧名は「人数」を連想させ実際の
#   意味（延べ回数）と一致していなかったため。
# ・「クリア回数」= そのうち実際に勝利で終わった回数。
#
# 重要な設計上の理由: この2つのカウンタを、既存のstage定義JSON（stages_dir
# 配下の<id>.json、draft.to_saved_dict()が書く場所）へ含めなかった。
# test_rbm_challenge_flow.gd の
# test_winning/losing/restarting/quitting_a_challenge_leaves_the_saved_json_
# byte_for_byte_unchanged が、CHALLENGE側の戦闘結果によって保存stage JSONが
# 一切書き換わらないことを既に厳密に検証済み（§22「既存Challenge Sessionを
# 不要に変更しない」と整合する、意図的な既存の設計保証）——挑戦/クリアの
# たびにdraft経由でstage JSONを上書きする設計にすると、この保証を壊す。
# そのためstages_dir()とは別のサイドカーディレクトリへ完全に独立した小さな
# JSONとして記録する（1 stage_id = 1ファイル、既存のstages/と同じ形）。
# stages_dir()のテスト用差し替え(_stages_dir_override)をそのまま流用して
# 派生させるため、既存の全テストのディレクトリ分離もそのまま引き継がれる。
# ---------------------------------------------------------------------------

const STAGE_STATS_SUBDIR_NAME := "stage_stats"

static func _stage_stats_dir() -> String:
	return stages_dir().get_base_dir() + "/" + STAGE_STATS_SUBDIR_NAME

static func _stage_stats_path(stage_id: String) -> String:
	return "%s/%s.json" % [_stage_stats_dir(), stage_id]

## CHALLENGE discovery 最終調整 §1: 「挑戦者数（人数）」ではなく「挑戦回数」
## を数えているため、キー名をchallenger_count→challenge_countへ整理した
## （このサイドカーは前回タスクで追加したばかりで、まだ他のどの永続データ
## とも意味的に結び付いていないため安全に改名できる）。ただし前回タスク
## 実行中に既にディスクへ書かれたstage_stats/<id>.jsonが残っている場合に
## 備え、新キーが無ければ旧キーへフォールバックして読む——移行専用の
## 読み込み分岐であり、以後の書き込みは常に新キーだけを使う。
##
## 破損/未作成なら安全な既定値（0/0、＝「まだ誰も挑戦していない」）を返す
## ——他の全読込処理と同じ「壊れていても静かにフォールバックする」方針。
static func read_stage_stats(stage_id: String) -> Dictionary:
	var default_stats := {"challenge_count": 0, "clear_count": 0}
	if not _is_valid_stage_id(stage_id):
		return default_stats
	var path := _stage_stats_path(stage_id)
	if not FileAccess.file_exists(path):
		return default_stats
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return default_stats
	var parsed: Variant = json.get_data()
	if not (parsed is Dictionary):
		return default_stats
	var data: Dictionary = parsed
	# 新キーが無ければ旧キー（challenger_count）から移行して読む。
	var raw_challenge_count: Variant = data.get("challenge_count", data.get("challenger_count", 0))
	var challenge_count := int(raw_challenge_count) if _is_numeric(raw_challenge_count) else 0
	var clear_count := int(data.get("clear_count", 0)) if _is_numeric(data.get("clear_count", 0)) else 0
	return {"challenge_count": maxi(0, challenge_count), "clear_count": maxi(0, clear_count)}

static func _write_stage_stats(stage_id: String, stats: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(_stage_stats_dir())
	return _atomic_write(_stage_stats_path(stage_id), JSON.stringify(stats))

## §17（挑戦開始の瞬間、CHALLENGE UI層からのみ呼ばれる）。存在しないstage_id
## でも静かにfalseを返すだけ（既存の他の防御的APIと同じ流儀）。
static func record_challenge_attempt(stage_id: String) -> bool:
	var stats := read_stage_stats(stage_id)
	stats["challenge_count"] = int(stats["challenge_count"]) + 1
	return _write_stage_stats(stage_id, stats)

## §17（実際の勝利確定の瞬間、CHALLENGE UI層からのみ呼ばれる）。
static func record_challenge_clear(stage_id: String) -> bool:
	var stats := read_stage_stats(stage_id)
	stats["clear_count"] = int(stats["clear_count"]) + 1
	return _write_stage_stats(stage_id, stats)

# ---------------------------------------------------------------------------
# save (§23/§24/§25/§28)
# ---------------------------------------------------------------------------

## §23/§25: 新規stage_idを発行し、既存のどのファイルにも一切触れずに新しい
## JSONを1つ書き出す（初回保存にも「新しいボスとして保存」にも使う——両者は
## Repository視点では同一の操作。current_stage_idの切り替えはRBMCreatorMain側
## の責務）。
static func save_new(draft: RBMCreatorDraft) -> Dictionary:
	var stage_id := generate_unique_stage_id()
	var now := int(Time.get_unix_time_from_system())
	var payload := _build_payload(stage_id, now, now, draft)
	if not _atomic_write(_stage_path(stage_id), JSON.stringify(payload)):
		return {"ok": false, "error": "write_failed"}
	return {"ok": true, "stage_id": stage_id, "created_unix_time": now, "updated_unix_time": now}

## §24: stage_id/created_unix_timeを維持し、updated_unix_timeとdraft内容
## （Clear Check snapshotを含む）だけを現在値へ更新する。
static func overwrite(stage_id: String, draft: RBMCreatorDraft) -> Dictionary:
	if not _is_valid_stage_id(stage_id):
		return {"ok": false, "error": "invalid_stage_id"}
	var now := int(Time.get_unix_time_from_system())
	var created_unix_time := now
	var existing := load_stage(stage_id)
	if bool(existing.get("ok", false)):
		created_unix_time = int(existing.get("created_unix_time", now))
	var payload := _build_payload(stage_id, created_unix_time, now, draft)
	if not _atomic_write(_stage_path(stage_id), JSON.stringify(payload)):
		return {"ok": false, "error": "write_failed"}
	return {"ok": true, "stage_id": stage_id, "created_unix_time": created_unix_time, "updated_unix_time": now}

static func _build_payload(stage_id: String, created_unix_time: int, updated_unix_time: int, draft: RBMCreatorDraft) -> Dictionary:
	return {
		"save_format_version": SAVE_FORMAT_VERSION,
		"stage_id": stage_id,
		"created_unix_time": created_unix_time,
		"updated_unix_time": updated_unix_time,
		"draft": draft.to_saved_dict(),
		"clear_check_success_snapshot": draft.clear_check_snapshot_for_save(),
	}

# ---------------------------------------------------------------------------
# load (§34/§43/§61)
# ---------------------------------------------------------------------------

## 最終レビュー対応①/②: 保存データとして安全に復元できるかの防御的検証
## （Definition validationとは別物——名前空欄/パーティ0/スキル0のような
## 「ゲームとして未完成」な下書きは、正しい型さえ持っていれば引き続き合格
## する）。
##
## 実機検証（Godot 4.7）: 型の合わないVariantをint()/float()/bool()で変換
## した結果を、静的にint/float/bool型付けされたクラス変数へ代入すると、
## 単なるコンソールERRORでは済まずプロセスがハング/内部破損する（int(Array)
## を`var hp:int`へ代入して再現、強制終了時にメモリ管理層のBUG/RID leakが
## 連鎖するほどの深刻な状態になることを確認済み）。typed Array/Dictionary
## 引数へ型の合わないVariantを直接渡すのも同様に危険。str()代入のみを行う
## フィールド（boss_name/appearance_id等）はどのVariantを渡しても安全な
## ことを確認済みのため対象外——コンテナ型（Array/Dictionary）に加え、
## restore_from_saved_dict()が実際にint()/float()/bool()で静的型付き
## フィールドへ変換代入する数値・真偽値フィールドも検証対象に含めている
## （指示書の文言は「コンテナ型確認」だが、この実機で確認済みの同種の
## クラッシュ経路を放置しないという「クラッシュを防ぐ」という目的そのもの
## を優先した——完了報告で開示）。
static func _is_numeric(value: Variant) -> bool:
	var t := typeof(value)
	return t == TYPE_INT or t == TYPE_FLOAT

## フィールドが存在しないなら合格（.get(key,default)の安全なデフォルトに
## 委ねる、下書きの未完成を壊さないため）。存在する場合だけ型を見る。
static func _optional_string_ok(entry: Dictionary, field: String) -> bool:
	return not entry.has(field) or typeof(entry[field]) == TYPE_STRING

static func _optional_numeric_ok(entry: Dictionary, field: String) -> bool:
	return not entry.has(field) or _is_numeric(entry[field])

static func _validate_string_array(raw: Array) -> bool:
	for value in raw:
		if typeof(value) != TYPE_STRING:
			return false
	return true

## トップレベル: root自体は呼び出し元で既にDictionaryと確認済み。
## save_format_version/stage_id/created_unix_time/updated_unix_time/draft/
## clear_check_success_snapshotの存在と型を確認する。
static func _validate_payload_shape(data: Dictionary) -> bool:
	if not data.has("save_format_version") or not _is_numeric(data["save_format_version"]):
		return false
	# 最終レビュー対応①: int()で切り捨ててから比較しない——1.5がint(1.5)==1
	# で誤って受理されるバグを避けるため、float同士の完全一致だけを見る
	# （1と1.0はfloat比較でも等しいため、正規のversion 1は引き続き受理される）。
	# v1 is read-only-compatible and is normalized in memory.  Every new write
	# uses v2; unknown/fractional versions remain rejected.
	var version := float(data["save_format_version"])
	if version != float(LEGACY_SAVE_FORMAT_VERSION) and version != float(SAVE_FORMAT_VERSION):
		return false
	if not data.has("stage_id") or typeof(data["stage_id"]) != TYPE_STRING:
		return false
	if not data.has("created_unix_time") or not _is_numeric(data["created_unix_time"]):
		return false
	if not data.has("updated_unix_time") or not _is_numeric(data["updated_unix_time"]):
		return false
	if not data.has("draft") or not (data["draft"] is Dictionary):
		return false
	if not data.has("clear_check_success_snapshot") or not (data["clear_check_success_snapshot"] is Dictionary):
		return false
	if not _validate_draft_shape(data["draft"]):
		return false
	if version == float(SAVE_FORMAT_VERSION) and not (data["draft"] as Dictionary).has("ally_overrides"):
		return false
	return _validate_clear_check_snapshot_shape(data["clear_check_success_snapshot"], int(version))

## draft: RBMCreatorDraft.restore_from_saved_dict()がArray/Dictionaryとして
## 扱う各フィールドの型に加え、その中身（各要素/各値）の型も確認する。
## フィールド自体が存在しない場合は.get(key,default)の安全なデフォルトに
## 委ねる（下書きが未完成でも復元可能な理由そのもの）——「存在するが型が
## 違う」場合だけを拒否する。ゲームとしての意味validation（HP範囲・属性名の
## 妥当性・turn>=1等）はここでは一切行わない（既存Definition validationの
## 責務のまま）。
static func _validate_draft_shape(draft_data: Dictionary) -> bool:
	for field in ["weak_attributes", "resist_attributes", "party_character_ids"]:
		if draft_data.has(field):
			if not (draft_data[field] is Array) or not _validate_string_array(draft_data[field]):
				return false
	if draft_data.has("skills"):
		if not (draft_data["skills"] is Array) or not _validate_draft_skills_array(draft_data["skills"]):
			return false
	if draft_data.has("scripted_actions"):
		if not (draft_data["scripted_actions"] is Array) or not _validate_scripted_actions_array(draft_data["scripted_actions"]):
			return false
	if draft_data.has("normal_action_percentages"):
		if not (draft_data["normal_action_percentages"] is Dictionary) or not _validate_normal_action_percentages(draft_data["normal_action_percentages"]):
			return false
	if draft_data.has("ally_allowed_skill_ids"):
		if not (draft_data["ally_allowed_skill_ids"] is Dictionary) or not _validate_ally_allowed_skill_ids(draft_data["ally_allowed_skill_ids"]):
			return false
	if draft_data.has("ally_overrides") and not RBMDefinitionLoader.validate_ally_overrides(draft_data["ally_overrides"]):
		return false
	for field in ["hp", "atk", "spd", "next_skill_ordinal"]:
		if draft_data.has(field) and not _is_numeric(draft_data[field]):
			return false
	if draft_data.has("normal_actions_enabled") and typeof(draft_data["normal_actions_enabled"]) != TYPE_BOOL:
		return false
	# Phase 1 Step 7 §46: 作者備考・情報公開設定の型確認。フィールド自体が
	# 存在しない旧stageは常に合格（restore側が安全なデフォルトへフォール
	# バックする）。
	if not _optional_string_ok(draft_data, "author_notes"):
		return false
	# CHALLENGE UI再設計 §10/§4-D: 作者名・公開日時も他の任意フィールドと同じ
	# 「存在すれば型を確認」方針。
	if not _optional_string_ok(draft_data, "author_name"):
		return false
	if not _optional_numeric_ok(draft_data, "published_at_unix_time"):
		return false
	if draft_data.has("challenge_info_visibility"):
		if not (draft_data["challenge_info_visibility"] is Dictionary) or not _validate_challenge_info_visibility(draft_data["challenge_info_visibility"]):
			return false
	# HARDCORE Creator: creator_mode/action_sequence/next_slot_ordinal。
	# フィールド自体が存在しない旧stage（この仕様以前に保存されたもの）は
	# 常に合格（restore_from_saved_dict()が"simple"/空配列/1へ安全に
	# フォールバックする）——ここでも他フィールドと同じ「存在すれば型を
	# 確認、意味validationはしない」方針を踏襲する。
	if not _optional_string_ok(draft_data, "creator_mode"):
		return false
	# Creator UI再設計 §24〜§27（公開機能）: フィールド自体が存在しない旧
	# stageは常に合格（restore側がfalseへ安全にフォールバックする）。
	if draft_data.has("published") and typeof(draft_data["published"]) != TYPE_BOOL:
		return false
	if not _optional_numeric_ok(draft_data, "next_slot_ordinal"):
		return false
	if draft_data.has("action_sequence"):
		if not (draft_data["action_sequence"] is Array) or not _validate_action_sequence_array(draft_data["action_sequence"]):
			return false
	# Codex最終差分レビュー⑥の修正: advanced_ai_versionはHARDCORE AI
	# サブシステム自体のバージョン印（RBMCreatorDraft.ADVANCED_AI_VERSION、
	# 保存全体のsave_format_versionとは独立、rbm_creator_draft.gd参照）。
	# フィールド自体が存在しない旧stage（この仕様以前に保存されたもの）は
	# v1互換として常に合格させる——他の全フィールドと同じ「存在
	# しなければ安全なデフォルトへフォールバックする」慣習のまま。ただし
	# フィールドが存在する場合は、save_format_versionの既存の厳密一致
	# チェックと同じ方針で、現在の実装が理解できるちょうどそのバージョン
	# のみを受理し、それ以外（旧HARDCORE行動パターン仕様・将来のバージョン
	# ・破損データ）は黙って現行版として解釈せず拒否する——2026-09-05の
	# 全面再設計により、旧「行動パターン」仕様（action_patterns/瞬間条件/
	# 発動確率/Cooldown）のデータは自動変換せず、この厳密拒否によって
	# ロード自体を弾く（§22確定、旧HARDCORE保存データの互換維持は不要）。
	# DefinitionLoaderの意味validationとは別の、Repository層自身が担う
	# 「安全に読み込める形か」の最終防衛線。
	if draft_data.has("advanced_ai_version"):
		if not _is_numeric(draft_data["advanced_ai_version"]):
			return false
		if float(draft_data["advanced_ai_version"]) != float(RBMCreatorDraft.ADVANCED_AI_VERSION):
			return false
	return true

## HARDCORE Creator: action_sequence配列の各エントリ（配置スロット）の型
## 確認。「意味のある値（条件タイプが既知か・turn>=1か等）」はここでは
## 一切検証しない——RBMDefinitionLoaderの責務のまま（既存のskills/
## scripted_actions等と同じ役割分担）。ここは「安全に読み込める形か」だけ
## を見る。
static func _validate_action_sequence_array(raw: Array) -> bool:
	for entry_variant in raw:
		if not (entry_variant is Dictionary):
			return false
		var entry: Dictionary = entry_variant
		if not _optional_string_ok(entry, "slot_id"):
			return false
		if not _optional_string_ok(entry, "kind"):
			return false
		if not _optional_string_ok(entry, "condition_logic"):
			return false
		if not _optional_string_ok(entry, "skill_id"):
			return false
		if not _optional_numeric_ok(entry, "max_uses"):
			return false
		if entry.has("conditions"):
			if not (entry["conditions"] is Array) or not _validate_action_sequence_conditions_array(entry["conditions"]):
				return false
		if entry.has("candidates"):
			if not (entry["candidates"] is Array) or not _validate_action_sequence_candidates_array(entry["candidates"]):
				return false
	return true

## §6/§7の全条件タイプが使いうるフィールドを、typeの値を信用せず全種
## 「存在すれば型を確認」する（_validate_draft_skills_array()と同じ、
## typeフィールド自体が壊れている可能性を考慮した設計）。
static func _validate_action_sequence_conditions_array(raw: Array) -> bool:
	for entry_variant in raw:
		if not (entry_variant is Dictionary):
			return false
		var entry: Dictionary = entry_variant
		for field in ["type", "character_id", "skill_id", "attribute"]:
			if not _optional_string_ok(entry, field):
				return false
		for field in ["percent", "percent_min", "percent_max", "turn", "n", "turn_min", "turn_max", "count"]:
			if not _optional_numeric_ok(entry, field):
				return false
	return true

## §12確定: ランダム攻撃スロットの候補は「参照するskill_idと抽選重み」
## だけを持つ——候補自身の条件・使用回数という概念は存在しない。
static func _validate_action_sequence_candidates_array(raw: Array) -> bool:
	for candidate_variant in raw:
		if not (candidate_variant is Dictionary):
			return false
		var candidate: Dictionary = candidate_variant
		if not _optional_string_ok(candidate, "skill_id"):
			return false
		if not _optional_numeric_ok(candidate, "weight"):
			return false
	return true

## Phase 1 Step 7 §46: キーはString、値はBool（restore_from_saved_dict()が
## bool()で正規化するため、その入力として安全な型かをここで確認する）。
static func _validate_challenge_info_visibility(raw: Dictionary) -> bool:
	for key in raw.keys():
		if typeof(key) != TYPE_STRING:
			return false
		if typeof(raw[key]) != TYPE_BOOL:
			return false
	return true

## _restore_skills()の著作フィールド一式——共通(skill_id/name/type)＋
## attack系(target/attribute/atk_multiplier)＋self_heal系(heal_mode/
## heal_fixed_amount/heal_percent)＋atk_self_buff系(buff_multiplier/
## duration_turns)を、typeの値を信用せず全フィールドとも「存在すれば型を
## 確認」する（typeフィールド自体が壊れている可能性を考慮し、typeの値で
## 分岐してから確認する設計は取らない）。
static func _validate_draft_skills_array(raw: Array) -> bool:
	for entry_variant in raw:
		if not (entry_variant is Dictionary):
			return false
		var entry: Dictionary = entry_variant
		for field in ["skill_id", "name", "type", "target", "attribute", "heal_mode"]:
			if not _optional_string_ok(entry, field):
				return false
		for field in ["atk_multiplier", "heal_fixed_amount", "heal_percent", "buff_multiplier", "duration_turns"]:
			if not _optional_numeric_ok(entry, field):
				return false
	return true

## _restore_scripted_actions()の著作フィールド(skill_id/timing/turn)、
## およびClear Check snapshot側が追加で持つorderも共用（Draft著作形には
## orderが無いため常にIF PRESENTで安全）。
static func _validate_scripted_actions_array(raw: Array) -> bool:
	for entry_variant in raw:
		if not (entry_variant is Dictionary):
			return false
		var entry: Dictionary = entry_variant
		for field in ["skill_id", "timing"]:
			if not _optional_string_ok(entry, field):
				return false
		for field in ["turn", "order"]:
			if not _optional_numeric_ok(entry, field):
				return false
	return true

## _restore_normal_action_percentages(): キーはJSONオブジェクトキーである
## 以上必ずString（JSON仕様上保証されるが念のため確認）、値は数値。
static func _validate_normal_action_percentages(raw: Dictionary) -> bool:
	for key in raw.keys():
		if typeof(key) != TYPE_STRING:
			return false
		if not _is_numeric(raw[key]):
			return false
	return true

## _restore_ally_allowed_skill_ids(): キーはString、値はArray、配列要素は
## すべてString（_typed_string_array()がstr()で吸収する前段として、要素が
## そもそもArray/Dictionaryのような入れ子でないことを確認する）。
static func _validate_ally_allowed_skill_ids(raw: Dictionary) -> bool:
	for key in raw.keys():
		if typeof(key) != TYPE_STRING:
			return false
		if not (raw[key] is Array) or not _validate_string_array(raw[key]):
			return false
	return true

# ---------------------------------------------------------------------------
# Clear Check snapshot (battle_content_snapshot()と同じ形、Step 5から無改修)
# のネスト内部を、restore_clear_check_snapshot()/is_clear_check_currently_valid()
# が安全に扱える型かどうかだけ確認する。
# ---------------------------------------------------------------------------

static func _validate_clear_check_skill_entry(entry_variant: Variant) -> bool:
	if not (entry_variant is Dictionary):
		return false
	var entry: Dictionary = entry_variant
	for field in ["skill_id", "name", "type", "target", "attribute"]:
		if not _optional_string_ok(entry, field):
			return false
	for field in ["atk_multiplier", "heal_amount", "buff_multiplier", "duration_turns"]:
		if not _optional_numeric_ok(entry, field):
			return false
	return true

static func _validate_clear_check_skills_dict(raw: Dictionary) -> bool:
	for key in raw.keys():
		if typeof(key) != TYPE_STRING:
			return false
		if not _validate_clear_check_skill_entry(raw[key]):
			return false
	return true

static func _validate_clear_check_normal_actions(raw: Array) -> bool:
	for entry_variant in raw:
		if not (entry_variant is Dictionary):
			return false
		var entry: Dictionary = entry_variant
		if not _optional_string_ok(entry, "skill_id"):
			return false
		if not _optional_numeric_ok(entry, "weight"):
			return false
	return true

static func _validate_clear_check_party(raw: Dictionary) -> bool:
	for key in raw.keys():
		if typeof(key) != TYPE_STRING:
			return false
		if not (raw[key] is Array) or not _validate_string_array(raw[key]):
			return false
	return true

static func _validate_clear_check_party_v2(raw: Array) -> bool:
	var seen := {}
	for entry_variant in raw:
		if not (entry_variant is Dictionary):
			return false
		var entry: Dictionary = entry_variant
		for key in entry.keys():
			if typeof(key) != TYPE_STRING or not ["character_id", "hp", "atk", "spd", "max_sp", "allowed_skill_ids", "skill_values"].has(str(key)):
				return false
		if typeof(entry.get("character_id", null)) != TYPE_STRING:
			return false
		var character_id := str(entry["character_id"])
		if seen.has(character_id) or not RBMDefinitionLoader.KNOWN_ALLY_PATHS.has(character_id):
			return false
		seen[character_id] = true
		for field in RBMDefinitionLoader.ALLY_STAT_OVERRIDE_FIELDS:
			if not entry.has(field) or not RBMDefinitionLoader.validate_ally_stat_override_value(field, entry[field]):
				return false
		if not (entry.get("allowed_skill_ids", null) is Array) or not _validate_string_array(entry["allowed_skill_ids"]):
			return false
		if not (entry.get("skill_values", null) is Dictionary):
			return false
		var master := RBMDataLoader.load_dict(str(RBMDefinitionLoader.KNOWN_ALLY_PATHS[character_id]))
		var master_skills := {}
		for skill_variant in master.get("skills", []):
			if skill_variant is Dictionary:
				var skill: Dictionary = skill_variant
				master_skills[str(skill.get("id", ""))] = skill
		var allowed: Array = entry["allowed_skill_ids"]
		var seen_allowed := {}
		for allowed_id_variant in allowed:
			var allowed_id := str(allowed_id_variant)
			if seen_allowed.has(allowed_id) or not master_skills.has(allowed_id):
				return false
			seen_allowed[allowed_id] = true
		var skill_values: Dictionary = entry["skill_values"]
		if skill_values.size() != allowed.size():
			return false
		for allowed_id in allowed:
			if not skill_values.has(str(allowed_id)):
				return false
		for skill_key in skill_values.keys():
			var skill_id := str(skill_key)
			if typeof(skill_key) != TYPE_STRING or not allowed.has(skill_id) or not master_skills.has(skill_id):
				return false
			if not (skill_values[skill_key] is Dictionary):
				return false
			var values: Dictionary = skill_values[skill_key]
			var master_skill: Dictionary = master_skills[skill_id]
			var expected_fields := RBMDefinitionLoader.ally_skill_override_fields(master_skill)
			if values.size() != expected_fields.size():
				return false
			for field in values.keys():
				if typeof(field) != TYPE_STRING or not expected_fields.has(str(field)) or not RBMDefinitionLoader.validate_ally_skill_override_value(str(field), values[field]):
					return false
	return true

## 空Dictionaryは「未クリア」を意味し常に正常（has_ever_cleared()==falseの
## 唯一の合図）。空でない場合のみ、battle_content_snapshot()が実際に生成
## する形（本ファイルSTEP 5節参照、無改修）に合わせて各フィールドを確認する。
static func _validate_clear_check_snapshot_shape(snapshot: Dictionary, save_version: int = SAVE_FORMAT_VERSION) -> bool:
	if snapshot.is_empty():
		return true
	for field in ["hp", "atk", "spd"]:
		if snapshot.has(field) and not _is_numeric(snapshot[field]):
			return false
	for field in ["weak_attributes", "resist_attributes"]:
		if snapshot.has(field):
			if not (snapshot[field] is Array) or not _validate_string_array(snapshot[field]):
				return false
	if snapshot.has("skills"):
		if not (snapshot["skills"] is Dictionary) or not _validate_clear_check_skills_dict(snapshot["skills"]):
			return false
	if snapshot.has("normal_actions"):
		if not (snapshot["normal_actions"] is Array) or not _validate_clear_check_normal_actions(snapshot["normal_actions"]):
			return false
	if snapshot.has("scripted_actions"):
		if not (snapshot["scripted_actions"] is Array) or not _validate_scripted_actions_array(snapshot["scripted_actions"]):
			return false
	if snapshot.has("party"):
		if save_version == LEGACY_SAVE_FORMAT_VERSION:
			if not (snapshot["party"] is Dictionary) or not _validate_clear_check_party(snapshot["party"]):
				return false
		else:
			if not (snapshot["party"] is Array) or not _validate_clear_check_party_v2(snapshot["party"]):
				return false
	return true

## 生Dictionary（draft用/Clear Check snapshot用）のまま返す——Draftオブジェクト
## を新規構築しない。呼び出し側（RBMCreatorMain）が既に保持している
## RBMCreatorDraftインスタンスへrestore_from_saved_dict()/
## restore_clear_check_snapshot()で書き戻すことで、STEPビュー群が保持する
## draft参照を一切差し替えずに済む（UI二重構築を避けるための設計）。
##
## §43: 壊れたJSON・存在しないファイルはクラッシュせず{"ok":false}を返す。
## 名前を"load"ではなく"load_stage"にしているのはGDScriptの組み込み
## load(path)（Resourceローダー）との衝突を避けるため。
## Phase 4B: オンラインボスpayload内のdraft_fieldsは、この保存ファイル形式
## と同じ「著作フィールドのDictionary」を再利用する(RBMOnlineBossPayload
## 参照)。信用できないオンラインデータの型検証にも、ローカル保存ファイル
## 用に既にあるこの検証をそのまま使う——同じ形の危険(壊れたArray/
## Dictionary、型の合わないint/float)を防ぐロジックを重複させないため。
## 意味検証(スキルIDが実在するか等)はここでは行わない——
## RBMDefinitionLoader.resolve()が呼ばれた時点で別途検証される。
static func validate_draft_shape_for_online(draft_data: Dictionary) -> bool:
	return _validate_draft_shape(draft_data)

static func load_stage(stage_id: String) -> Dictionary:
	if not _is_valid_stage_id(stage_id):
		return {"ok": false, "error": "invalid_stage_id"}
	var path := _stage_path(stage_id)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "not_found"}
	var text := FileAccess.get_file_as_string(path)
	# §43: 壊れたファイルは想定内の正常系として静かに処理する——JSON.parse_string()
	# (static)は失敗時にエンジンコンソールへERRORログを出す仕様だが、
	# JSON.new().parse()(instance)は同じ失敗をError戻り値だけで通知しログを
	# 出さない（実機確認済み）。壊れたセーブが1件あるだけでコンソールに
	# ERRORが出続けるのは「クラッシュしない」以上に「静かに処理する」という
	# 意図から外れるため、こちらを使う。
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "error": "corrupt"}
	var parsed: Variant = json.get_data()
	if not (parsed is Dictionary):
		return {"ok": false, "error": "corrupt"}
	var data: Dictionary = parsed
	if not _validate_payload_shape(data):
		return {"ok": false, "error": "invalid_shape"}
	var version := int(data.get("save_format_version", LEGACY_SAVE_FORMAT_VERSION))
	var draft_data: Dictionary = (data.get("draft", {}) as Dictionary).duplicate(true)
	# v1 predates ally customization.  Even a hand-edited/forward-written v1
	# file must therefore resolve exactly like an original v1 stage: master ally
	# performance only.  New writes are always v2 and never rewrite old files in
	# bulk; this is an in-memory compatibility normalization at load time.
	if version == LEGACY_SAVE_FORMAT_VERSION:
		draft_data.erase("ally_overrides")
	return {
		"ok": true,
		"stage_id": stage_id,
		"draft_data": draft_data,
		"clear_check_data": data.get("clear_check_success_snapshot", {}),
		"save_format_version": version,
		"created_unix_time": int(data.get("created_unix_time", 0)),
		"updated_unix_time": int(data.get("updated_unix_time", 0)),
	}

# ---------------------------------------------------------------------------
# list (§17/§22/§32): boss_name/appearance_id/statusを都度算出して返す軽量
# サマリー一覧。ボス名/stage_id検索はUI側（RBMCreatorEntry）がこの結果を
# フィルタするだけで実現する——Repository自身は検索メソッドを持たない
# （§45が列挙するメソッド一覧に検索が含まれていないことと一致）。
# ---------------------------------------------------------------------------

static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(stages_dir()):
		return out
	for file_name in DirAccess.get_files_at(stages_dir()):
		if not file_name.ends_with(".json"):
			continue
		var stage_id := file_name.get_basename()
		if not _is_valid_stage_id(stage_id):
			continue
		var result := load_stage(stage_id)
		if not bool(result.get("ok", false)):
			continue  # §43: 壊れたstageは一覧から静かに除外、他stageは無傷
		var draft := RBMCreatorDraft.new()
		draft.restore_from_saved_dict(result.get("draft_data", {}))
		draft.restore_clear_check_snapshot(result.get("clear_check_data", {}))
		var status := "draft"
		if draft.is_playable():
			status = "clear_checked" if draft.is_clear_check_currently_valid() else "playable"
		# Creator UI再設計 §24〜§27（公開機能）: ファイル単体の内容だけからでも
		# 「公開済みのまま内容編集でClear Check無効化」という不整合が理論上
		# 起こりえない設計だが（RBMCreatorMain._refresh()が保存前に必ず
		# sync_published_with_clear_check()を通す）、Repository自身の最終
		# 防衛線として都度呼んでおく——CHALLENGE側の一覧表示はこの結果に
		# 直接依存する。
		draft.sync_published_with_clear_check()
		# CHALLENGE UI再設計 §4/§9/§10: ハブ・共通一覧・カードが必要とする
		# フィールドをここへ追加する——author_name/creator_mode/
		# published_at_unix_timeはdraft自身（著作内容）から、challenge_count/
		# clear_countは完全に別のサイドカーストア（read_stage_stats()、上記
		# 参照）から。既存の呼び出し元は既存キーだけを読むため無影響
		# （published追加時と同じ、追加専用の変更）。
		var stats := read_stage_stats(stage_id)
		out.append({
			"stage_id": stage_id,
			"boss_name": draft.boss_name,
			"appearance_id": draft.appearance_id,
			"status": status,
			"published": draft.is_published(),
			"created_unix_time": int(result.get("created_unix_time", 0)),
			"updated_unix_time": int(result.get("updated_unix_time", 0)),
			"author_name": draft.author_name,
			"creator_mode": draft.creator_mode,
			"published_at_unix_time": draft.published_at_unix_time(),
			"challenge_count": int(stats.get("challenge_count", 0)),
			"clear_count": int(stats.get("clear_count", 0)),
		})
	return out

## §26: 新規保存/新しいボスとして保存の直前に呼ぶ同名警告用チェック。
## 大文字小文字を無視した完全一致（部分一致ではない）——"Dragon"/"dragon"/
## "DRAGON"はすべて同名として扱う。§33の検索（ボス名部分一致・大文字小文字
## 非依存）とは別の判定軸で、こちらは常に文字列全体の一致のみを見る。
static func boss_name_exists(boss_name: String) -> bool:
	var target := boss_name.to_lower()
	for entry in list():
		if str(entry.get("boss_name", "")).to_lower() == target:
			return true
	return false

# ---------------------------------------------------------------------------
# delete (§41/§42/§60)
# ---------------------------------------------------------------------------

static func delete(stage_id: String) -> bool:
	if not _is_valid_stage_id(stage_id):
		return false
	var path := _stage_path(stage_id)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK
