extends SceneTree

## Supabase最小接続PoC §7 — 実際にネットワークへ出て接続確認を行う手動
## 検証スクリプト。tools/_ui_pass_shots/のSceneTreeスクリプトと同じ実行
## パターン（godot --path . -s res://tools/supabase_poc/verify_connection.gd）
## だが、こちらは画面キャプチャではなく実HTTP通信を行う。
##
## 通常のGUTテストスイート(tests/bossmaker/)には含めない——「実際の
## Supabase通信を毎回行うテストだけに依存しない」(§7)ため、オフラインで
## 検証できるロジック(RBMSupabaseResponse等)はGUT側、実ネットワークが
## 必要なこのend-to-end確認だけをここへ分離してある。
##
## 事前準備:
##   1. supabase/migrations/20260906000000_create_boss_connection_tests.sql
##      をSupabase SQL Editorで実行済みであること。
##   2. supabase_poc.local.env.example を supabase_poc.local.env として
##      コピーし、実際の SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY を入れて
##      あること（.gitignore対象、コミットされない）。
##
## 実行:
##   godot --headless --path . -s res://tools/supabase_poc/verify_connection.gd

func _init() -> void:
	print("Supabase 最小接続PoC — 接続確認を開始します")

	if not RBMSupabaseConfig.is_configured():
		printerr("設定が未完了です。supabase_poc.local.env に SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY を設定してください（supabase_poc.local.env.example を参照）。")
		quit(1)
		return

	var client := RBMSupabaseClient.new()
	root.add_child(client)
	await process_frame

	print("① TEST BOSS を Supabase へ POST します...")
	var boss_data := {
		"source": "godot_supabase_poc",
		"hp": 1000,
		"atk": 100,
		"spd": 50,
	}
	var insert_result: Dictionary = await client.insert_test_boss("TEST BOSS", boss_data)
	_print_result("POST", insert_result)

	if not bool(insert_result.get("ok", false)):
		printerr("POSTに失敗したため、GET確認へは進みません。")
		quit(1)
		return

	print("② Supabase から一覧を GET します...")
	var fetch_result: Dictionary = await client.fetch_test_bosses()
	_print_result("GET", fetch_result)

	if not bool(fetch_result.get("ok", false)):
		printerr("GETに失敗しました。")
		quit(1)
		return

	var rows: Array = fetch_result.get("rows", [])
	var found_test_boss := false
	var boss_data_round_trip_ok := false
	for row_variant in rows:
		if not (row_variant is Dictionary):
			continue
		var row: Dictionary = row_variant
		if str(row.get("name", "")) == "TEST BOSS":
			found_test_boss = true
			var restored_boss_data: Variant = row.get("boss_data", null)
			if restored_boss_data is Dictionary:
				var restored: Dictionary = restored_boss_data
				boss_data_round_trip_ok = (
					str(restored.get("source", "")) == "godot_supabase_poc"
					and int(restored.get("hp", -1)) == 1000
					and int(restored.get("atk", -1)) == 100
					and int(restored.get("spd", -1)) == 50
				)
			break

	print("③ TEST BOSS が取得結果に含まれているか: %s" % found_test_boss)
	print("④ boss_data がJSONとして正しく復元できたか: %s" % boss_data_round_trip_ok)

	if found_test_boss and boss_data_round_trip_ok:
		print("=== 接続確認 PASS ===")
		quit(0)
	else:
		printerr("=== 接続確認 FAIL ===")
		quit(1)

## §8: Publishable keyそのものは絶対に出力しない——resultのDictionaryは
## そもそもkeyの値を一切含まない（RBMSupabaseClient._headers()参照）ため、
## ここでresult全体をそのままprintしても安全。
func _print_result(label: String, result: Dictionary) -> void:
	print("[%s] ok=%s error_kind=%s http_status=%s message=%s supabase_message=%s supabase_code=%s rows=%d" % [
		label,
		result.get("ok", false),
		result.get("error_kind", ""),
		result.get("http_status", -1),
		result.get("message", ""),
		result.get("supabase_message", ""),
		result.get("supabase_code", ""),
		(result.get("rows", []) as Array).size(),
	])
