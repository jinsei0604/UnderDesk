extends GutTest

## 翻訳の取り違えの見張り（2026-11-24）。src の .gd に書いた日本語の tr("…")（文脈つき tr("…", "…") も）が、
## 翻訳表（localization/ui_strings.csv）に同じキーで入っていて、英語に訳されることを確かめる。
## キーが1文字でも違うと（改行の有無など）訳が見つからず、英語の画面に日本語のまま出る。
## 見つかった例: 製品版の「体験版のデータが見つかりました…」（翻訳表だけ改行入り）・STEP4 の「追加」「行動の追加方法を選んでください」。
## ロケールは before_each で退避し、after_each で戻す（RBMLocale・TranslationServer はプロセス全体で共有）。

var _saved_locale := "ja"
var _saved_translation_locale := "ja"

func before_each() -> void:
	_saved_locale = RBMLocale.current_locale()
	_saved_translation_locale = TranslationServer.get_locale()

func after_each() -> void:
	RBMLocale.set_locale(_saved_locale)
	TranslationServer.set_locale(_saved_translation_locale)

func _gd_files(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var path := dir.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_gd_files(path, out)
		elif name.ends_with(".gd"):
			out.append(path)
		name = d.get_next()

func _has_japanese(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		if (c >= 0x3040 and c <= 0x30FF) or (c >= 0x4E00 and c <= 0x9FFF):
			return true
	return false

func test_every_japanese_tr_literal_in_src_has_an_english_translation() -> void:
	var files: Array = []
	_gd_files("res://src", files)
	assert_gt(files.size(), 100, "src の .gd が読めている")
	var re := RegEx.new()
	# tr("キー") と tr("キー", "文脈")。文字列の中の \" も読む
	re.compile("\\btr\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"\\s*(?:,\\s*\"((?:[^\"\\\\]|\\\\.)*)\")?\\s*\\)")
	TranslationServer.set_locale("en")
	var checked := 0
	var missing: Array[String] = []
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			var key := m.get_string(1).c_unescape()
			if not _has_japanese(key):
				continue
			var context := m.get_string(2).c_unescape() if m.get_group_count() >= 2 else ""
			checked += 1
			if String(TranslationServer.translate(key, context)) == key:
				var line := text.substr(0, m.get_start()).count("\n") + 1
				missing.append("%s:%d %s" % [path, line, key.replace("\n", "\\n").left(60)])
	assert_gt(checked, 400, "日本語の tr() を数百件見ている")
	assert_eq(missing.size(), 0, "英語の訳が無い tr():\n" + "\n".join(missing))
