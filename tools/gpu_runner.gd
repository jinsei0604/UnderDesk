extends Node

## GPU/Visual検証ツール群の正式共通起動基盤(2026-09-13新設)。
##
## 背景: 個々のtools/verify_*.gd / tools/_ui_pass_shots/capture_*.gdを
## `godot --path . -s res://tools/xxx.gd`で直接起動する旧方式は、`-s`が
## 指定スクリプトをautoload登録より前にコンパイルするため、autoload
## (RBMLocale等)を静的参照するクラス(RBMGameRoot等)を扱うツールで
## Compile Errorになる。
##
## このrunnerは通常のGodot Scene(位置引数指定)として起動することで、
## エンジンの通常の起動シーケンス(autoload登録を含む)を経てから
## _ready()に到達する。その後、対象の検証スクリプトをdynamic loadして
## 明示的entry point(run_gpu_verification)を1回だけ呼び出す。
## 新しいSceneTreeの手動生成や、生きているSceneTreeへのset_script()に
## よるスクリプト差し替えは行わない。
##
## 正式実行例:
##   godot --path . res://tools/gpu_runner.tscn -- \
##     --tool=res://tools/verify_world_ui_install_gpu.gd \
##     --output=<dir> [--record-all]
##
## 対象スクリプトは以下のいずれかのシグネチャでrun_gpu_verification()を
## 公開している必要がある(instance method / static funcのどちらでも可):
##   func run_gpu_verification(tree: SceneTree) -> void
##   func run_gpu_verification(tree: SceneTree, output_dir: String) -> ...
##   func run_gpu_verification(tree: SceneTree, output_dir: String, record_all: bool) -> int

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	var tool_path := ""
	var output_dir := ""
	var record_all := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tool="):
			tool_path = arg.substr("--tool=".length())
		elif arg.begins_with("--output="):
			output_dir = arg.substr("--output=".length())
		elif arg == "--record-all":
			record_all = true

	if tool_path == "":
		printerr("gpu_runner: --tool=<res://...> を指定してください")
		get_tree().quit(1)
		return

	if not ResourceLoader.exists(tool_path):
		printerr("gpu_runner: 指定されたtoolが存在しません: %s" % tool_path)
		get_tree().quit(1)
		return

	var tool_script = load(tool_path)
	if tool_script == null or not (tool_script is GDScript):
		printerr("gpu_runner: toolのロードに失敗しました(GDScriptとして読み込めません): %s" % tool_path)
		get_tree().quit(1)
		return

	var method_info := _find_method_info(tool_script, "run_gpu_verification")
	if method_info.is_empty():
		printerr("gpu_runner: 対象toolにrun_gpu_verification()が見つかりません(共通runner未対応のtoolです): %s" % tool_path)
		get_tree().quit(1)
		return

	var arg_count: int = method_info.get("args", []).size()
	var is_static: bool = (int(method_info.get("flags", 0)) & METHOD_FLAG_STATIC) != 0
	var receiver = tool_script if is_static else tool_script.new()

	var result = null
	match arg_count:
		1:
			result = await receiver.run_gpu_verification(get_tree())
		2:
			result = await receiver.run_gpu_verification(get_tree(), output_dir)
		_:
			result = await receiver.run_gpu_verification(get_tree(), output_dir, record_all)

	var exit_code: int = int(result) if result is int else 0
	get_tree().quit(exit_code)

func _find_method_info(script: GDScript, method_name: String) -> Dictionary:
	for m in script.get_script_method_list():
		if m.get("name") == method_name:
			return m
	return {}
