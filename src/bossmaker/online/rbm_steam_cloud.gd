class_name RBMSteamCloud
extends RefCounted

## Steam Cloud（ISteamRemoteStorage）だけに触れる薄いラッパー（RBMSteamAdapter と同じ方針）。
## Steam Cloud のファイルは Steam のアカウントごとに分かれて保存され、別の PC でも同じアカウントなら同じ物を読める。
## 使えるのは次の全部を満たす時だけ: GodotSteam が読み込まれている・Steam にログインしている・
## そのアカウントで Steam Cloud が有効・このアプリの Steam Cloud が有効（Steamworks のアプリ管理で容量を設定してあること）。
## 使えない時は is_available() が false を返すだけで、読み書きはしない（呼び出し側は手元の保存だけで動く）。
## GUT では本物の Steam に触れないよう、RBMFakeSteamCloud（同じ公開面）へ差し替える。

func _steam() -> Object:
	return Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null

func is_available() -> bool:
	# AppID が無ければ、このゲームは Steam を初期化しない。初期化していない Steam に loggedOn() を聞くと、
	# GodotSteam が毎回誤り（Steam may not be initialized）をログに出すので、聞かずに「使えない」とする（2026-10-18）
	if not RBMSteamConfig.is_configured():
		return false
	var steam := _steam()
	if steam == null:
		return false
	if not bool(steam.loggedOn()):
		return false
	return bool(steam.isCloudEnabledForAccount()) and bool(steam.isCloudEnabledForApp())

## ファイルの中身（UTF-8 の文字列）。無い・読めない時は空文字。
func read_text(file_name: String) -> String:
	var steam := _steam()
	if steam == null or not bool(steam.fileExists(file_name)):
		return ""
	var size := int(steam.getFileSize(file_name))
	if size <= 0:
		return ""
	var result: Dictionary = steam.fileRead(file_name, size)
	var buf: PackedByteArray = result.get("buf", PackedByteArray())
	if buf.is_empty():
		return ""
	return buf.get_string_from_utf8()

## 書き込み（成功したら true）。
func write_text(file_name: String, text: String) -> bool:
	var steam := _steam()
	if steam == null:
		return false
	var data := text.to_utf8_buffer()
	return bool(steam.fileWrite(file_name, data, data.size()))
