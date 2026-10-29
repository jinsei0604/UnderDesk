class_name RBMDemoCarryOver
extends RefCounted

## 体験版のデータを製品版へ引き継ぐ（2026-10-28）。製品版だけが使う（体験版では何もしない）。
## 体験版の保存（RBMEdition.DEMO_DATA_ROOT）は製品版と同じ保存フォルダの中の別の置き場にあるので、そこから写す:
## - 保存したボス戦（stages/<stage_id>.json）と挑戦の記録（stage_stats）: 製品版に同じ stage_id が無いものだけを写す
##   （製品版のファイルは上書き・削除しない）。オンラインに公開したボスは公開の id ごと写るので、製品版から管理できる
##   （公開の持ち主は Steam のアカウントなので、体験版と製品版で同じ）。
## - 討伐記録（defeat_records/<アカウント>.json）: 製品版の記録と「ボスごとの和集合・早い方」でまとめる（RBMDefeatRecord.merge）。
## 体験版の側のファイルは消さない・変えない。引き継いだ後の製品版の保存の数には上限が無い。
## 引き継いだ記録（製品版の置き場の demo_carry_over.json）: 自動で尋ねたか（「あとで」を選んだ後は自動では尋ねない。
## ホームの「体験版から引き継ぐ」でいつでも引き継げる）と、引き継いだ stage_id（製品版で消しても、もう一度は写さない）。

const STAGES := "stages"
const STAGE_STATS := RBMLocalStageRepository.STAGE_STATS_SUBDIR_NAME
const MARKER_FILE := "demo_carry_over.json"

static func _demo_root() -> String:
	return RBMEdition.demo_root()

static func _full_stages_dir() -> String:
	return RBMLocalStageRepository.stages_dir()

static func marker_path() -> String:
	return _full_stages_dir().get_base_dir() + "/" + MARKER_FILE

static func _marker() -> Dictionary:
	var parsed = JSON.parse_string(_read(marker_path())) if FileAccess.file_exists(marker_path()) else null
	var marker: Dictionary = parsed if parsed is Dictionary else {}
	if not (marker.get("imported_stage_ids") is Array):
		marker["imported_stage_ids"] = []
	marker["prompted"] = bool(marker.get("prompted", false))
	return marker

static func _save_marker(marker: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(marker_path().get_base_dir())
	RBMLocalStageRepository._atomic_write(marker_path(), JSON.stringify(marker))

## 自動の確認を一度出したか（「引き継ぐ」でも「あとで」でも、以後は自動では尋ねない）。
static func was_prompted() -> bool:
	return bool(_marker()["prompted"])

static func mark_prompted() -> void:
	var marker := _marker()
	marker["prompted"] = true
	_save_marker(marker)

## まだ引き継いでいない体験版のボス戦か（製品版に同じ stage_id が無く、前に引き継いでもいない）。
static func _should_copy(file_name: String, imported: Array) -> bool:
	return not imported.has(file_name.get_basename()) and not FileAccess.file_exists(_full_stages_dir() + "/" + file_name)

## 引き継げるもの（製品版に無いボス戦の数・討伐記録のファイルの数）。製品版で、体験版の保存がある時だけ 0 より大きい。
static func pending() -> Dictionary:
	var result := {"stages": 0, "defeat_records": 0}
	if RBMEdition.is_demo():
		return result
	var imported: Array = _marker()["imported_stage_ids"]
	for file_name in _json_files(_demo_root() + "/" + STAGES):
		if _should_copy(file_name, imported):
			result["stages"] += 1
	for file_name in _json_files(_demo_root() + "/" + RBMDefeatRecord.SUBDIR_NAME):
		var demo_records := RBMDefeatRecord._parse(_read(_demo_root() + "/" + RBMDefeatRecord.SUBDIR_NAME + "/" + file_name))
		var full_records := RBMDefeatRecord._parse(_read(RBMDefeatRecord.records_dir() + "/" + file_name))
		if not (demo_records.get("bosses", {}) as Dictionary).is_empty() and not RBMDefeatRecord._same_bosses(RBMDefeatRecord.merge(full_records, demo_records), full_records):
			result["defeat_records"] += 1
	return result

static func has_pending() -> bool:
	var p := pending()
	return int(p["stages"]) > 0 or int(p["defeat_records"]) > 0

## 引き継ぐ。戻り値: {"ok", "stages": 写したボス戦の数, "defeat_records": まとめた記録のファイルの数, "failed": 写せなかった数}。
static func import_all() -> Dictionary:
	var result := {"ok": true, "stages": 0, "defeat_records": 0, "failed": 0}
	if RBMEdition.is_demo():
		return result
	DirAccess.make_dir_recursive_absolute(_full_stages_dir())
	var marker := _marker()
	var imported: Array = marker["imported_stage_ids"]
	for file_name in _json_files(_demo_root() + "/" + STAGES):
		var target := _full_stages_dir() + "/" + file_name
		if not _should_copy(file_name, imported):
			continue
		var text := _read(_demo_root() + "/" + STAGES + "/" + file_name)
		var parsed = JSON.parse_string(text)
		if not (parsed is Dictionary) or not RBMLocalStageRepository._validate_payload_shape(parsed):
			result["failed"] += 1
			continue
		if RBMLocalStageRepository._atomic_write(target, text):
			result["stages"] += 1
			imported.append(file_name.get_basename())
			_copy_stats(file_name)
		else:
			result["failed"] += 1
	DirAccess.make_dir_recursive_absolute(RBMDefeatRecord.records_dir())
	for file_name in _json_files(_demo_root() + "/" + RBMDefeatRecord.SUBDIR_NAME):
		var demo_records := RBMDefeatRecord._parse(_read(_demo_root() + "/" + RBMDefeatRecord.SUBDIR_NAME + "/" + file_name))
		if (demo_records.get("bosses", {}) as Dictionary).is_empty():
			continue
		var path := RBMDefeatRecord.records_dir() + "/" + file_name
		var full_records := RBMDefeatRecord._parse(_read(path))
		var merged := RBMDefeatRecord.merge(full_records, demo_records)
		if RBMDefeatRecord._same_bosses(merged, full_records):
			continue
		if RBMLocalStageRepository._atomic_write(path, JSON.stringify(merged)):
			result["defeat_records"] += 1
		else:
			result["failed"] += 1
	marker["imported_stage_ids"] = imported
	marker["prompted"] = true
	_save_marker(marker)
	result["ok"] = int(result["failed"]) == 0
	return result

static func _copy_stats(stage_file: String) -> void:
	var source := _demo_root() + "/" + STAGE_STATS + "/" + stage_file
	var target_dir := _full_stages_dir().get_base_dir() + "/" + STAGE_STATS
	if not FileAccess.file_exists(source) or FileAccess.file_exists(target_dir + "/" + stage_file):
		return
	DirAccess.make_dir_recursive_absolute(target_dir)
	RBMLocalStageRepository._atomic_write(target_dir + "/" + stage_file, _read(source))

static func _json_files(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			files.append(file_name)
	return files

static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""
