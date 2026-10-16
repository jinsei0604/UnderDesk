class_name RBMFakeSteamCloud
extends RBMSteamCloud

## GUT・検証用の Steam Cloud（本物の Steam に触れない）。ファイルはこのオブジェクトの中だけに持つ。
## 別の PC の Steam Cloud（同じアカウント）を表すには、同じオブジェクトを2つの記録係で共有する。

var available := true
var fail_writes := false
var files: Dictionary = {}
var writes := 0

func is_available() -> bool:
	return available

func read_text(file_name: String) -> String:
	return str(files.get(file_name, "")) if available else ""

func write_text(file_name: String, text: String) -> bool:
	if not available or fail_writes:
		return false
	files[file_name] = text
	writes += 1
	return true
