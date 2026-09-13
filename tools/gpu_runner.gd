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
## 公開している必要がある:
##   func run_gpu_verification(tree: SceneTree) -> int
##   func run_gpu_verification(tree: SceneTree, output_dir: String) -> int
##   func run_gpu_verification(tree: SceneTree, output_dir: String, record_all: bool) -> int
##
## 正式な成功判定contract(2026-09-13制定): 「runnerのexit code 0 =
## 検証ツールが最後まで正常完了したことの保証」とするため、instance
## methodのtoolは追加で以下のプロパティを公開すること:
##   var _gpu_verification_completed := false
## run_gpu_verification()の最後(実際に処理が完走した場合にのみ到達する
## 行)でこれをtrueにしてからreturnする。
##
## 背景(PoCで確認済みの重要な落とし穴): run_gpu_verification()が実行時
## エラー(null参照等)で途中終了した場合でも、Godotは`-> int`宣言の
## 関数に対してnullではなく「その型のゼロ値」=0を暗黙に返す。そのため
## 戻り値が0であることは「正常に完了した0」なのか「エラーで中断した
## ゼロ値」なのかを区別できない。_gpu_verification_completedは、その
## 行より後のコードがエラー発生時には一切実行されないという既存の
## 確認済み挙動を利用して、これを確実に区別する。
##
## _gpu_verification_completedを持たないtool(未移行の旧toolを含む)は、
## この安全策の対象外であり、実際の成否に関わらずexit code 1として
## 扱われる(「安全側」——exit 0を検証成功の保証として使えない状態の
## ままexit 0を返すことは絶対にしない)。

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

	# 正式contract(完了フラグ)に対応しているかを、実行前に安全に判定する。
	# `in`演算子はプロパティが存在しない場合でも例外を投げずfalseを返す
	# ため、未対応toolに対しても安全。staticメソッドはinstance状態を
	# 持てないため対象外(将来static対応toolが必要になれば別途検討)。
	const COMPLETION_FLAG := "_gpu_verification_completed"
	var is_contract_compliant: bool = (not is_static) and (COMPLETION_FLAG in receiver)

	var result = null
	match arg_count:
		1:
			result = await receiver.run_gpu_verification(get_tree())
		2:
			result = await receiver.run_gpu_verification(get_tree(), output_dir)
		_:
			result = await receiver.run_gpu_verification(get_tree(), output_dir, record_all)

	var exit_code: int
	if not is_contract_compliant:
		printerr("gpu_runner: 対象toolは正式contract(%s)に未対応です。exit codeは検証結果を保証しないため、安全側としてexit 1を返します: %s" % [COMPLETION_FLAG, tool_path])
		exit_code = 1
	elif not bool(receiver.get(COMPLETION_FLAG)):
		printerr("gpu_runner: run_gpu_verification()が完了フラグ(%s)へ到達せず終了しました(実行時エラーの可能性)。失敗として扱います。" % COMPLETION_FLAG)
		exit_code = 1
	elif result is int:
		exit_code = result
	else:
		printerr("gpu_runner: run_gpu_verification()の戻り値がint型ではありません。未知の結果型を成功扱いしません。")
		exit_code = 1

	get_tree().quit(exit_code)

func _find_method_info(script: GDScript, method_name: String) -> Dictionary:
	for m in script.get_script_method_list():
		if m.get("name") == method_name:
			return m
	return {}
