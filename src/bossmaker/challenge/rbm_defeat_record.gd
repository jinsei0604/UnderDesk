class_name RBMDefeatRecord
extends RefCounted

## 挑戦トップの「あなたの討伐記録」（2026-10-16 ユーザー依頼）。アカウントごとに、挑戦（CHALLENGE）で初めてクリアした
## ボスを1件ずつ覚え、3つの数を出す:
##   SIMPLE   … 初めてクリアした時に SIMPLE だったボスの数
##   HARDCORE … 初めてクリアした時に HARDCORE（作り込まれたボス戦、creator_mode = advanced）だったボスの数
##   難関      … 難関ボス討伐に認定されたボスの数（難易度とは別に数える。2026-10-23 から認定はサーバーが決める）
## 集計の決まり:
## - ボス固有ID（オンラインのボスID）で判定し、同じボスは何度クリアしても1件だけ（最初のクリアの内容で固定）。
## - 難関（2026-10-23 確定）: 作者本人を除いた正式な挑戦結果（勝ち・負け）50回以上・挑戦者10人以上・クリア率5%以下のボスを、
##   初めてクリアした時にほかの人のクリア率が5%以下だったプレイヤーだけに認定する。判定は DB（Supabase の記録の関数）が行い、
##   ゲームはクリアの記録の応答（hard_awarded）と list-my-hard-awards の一覧で受け取るだけ（手元では数えない・推測しない）。
##   初めてクリアした時に条件（50回・10人）に届いていなければ保留され、後で条件を満たすとさかのぼって認定される
##   （挑戦トップを開いた時に一覧で受け取る）。一度ついた難関は消さない（後でクリア率が変わっても、記録をまとめ直しても）。
##   rate は初めてクリアした時のクリア率（サーバーの値、無ければ挑戦を始めた時の一覧の値。-1 は不明）で、表示・記録用。
## - TEST BATTLE・クリアチェックは数えない（呼び出し元 RBMChallengeEntry が挑戦の勝利でだけ呼ぶ）。
## - ボスが削除・更新されても、取得した実績は消さない（ボスの存在を確かめない）。
## 保存（継続的なサーバー費用を増やさない）:
## - 手元: user://bossmaker/defeat_records/<アカウント>.json（stages の隣。テストでは保存先の差し替えに従う）。
## - Steam Cloud（使える時だけ）: defeat_records.json（Steam Cloud はアカウントごとに分かれる）。
## - 同期の競合: 手元と Steam Cloud を「ボスごとの和集合、同じボスはクリアした時刻が早い方」でまとめる（どちらから先に
##   読んでも同じ結果になる。消す操作は無いので、記録が失われない）。難関はどちらかで難関なら難関（消えない）。
##   ファイルの形式（項目: mode・rate・hard・at）は 2026-10-16 から変えていない。
## 戦闘・乱数・保存データ（ステージ）・オンラインの記録（Supabase）には触れない。

const FORMAT := "rbm_defeat_records"
const VERSION := 1
const SUBDIR_NAME := "defeat_records"
const CLOUD_FILE := "defeat_records.json"
## Steam のアカウントが分からない時（Steam を使っていない・テスト）の記録の持ち主。
const LOCAL_ACCOUNT := "local"

var account_id := LOCAL_ACCOUNT
## Steam Cloud（使わない時は null）。
var cloud: RBMSteamCloud = null
## 最後に読んだ・書いた記録（{format, version, account, bosses: {boss_id: {mode, rate, hard, at}}}）。
var data: Dictionary = {}
## 最後の Steam Cloud の状態（報告・検証用）: "unused" / "unavailable" / "synced" / "write_failed"
var cloud_state := "unused"

func _init(account: String = LOCAL_ACCOUNT, steam_cloud: RBMSteamCloud = null) -> void:
	account_id = sanitize_account(account)
	cloud = steam_cloud
	data = empty(account_id)

## SteamID64（数字）だけをそのまま使い、それ以外は LOCAL_ACCOUNT。
static func sanitize_account(account: String) -> String:
	var a := account.strip_edges()
	if a.is_empty() or not a.is_valid_int() or a.begins_with("-"):
		return LOCAL_ACCOUNT
	return a

static func empty(account: String) -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "account": account, "bosses": {}}

## 既存の正式なクリア率（オンライン一覧の行: unique_clearers ÷ unique_challengers）。分からない時は -1。
static func official_rate(summary: Dictionary) -> float:
	if not summary.has("unique_challengers") or not summary.has("unique_clearers"):
		return -1.0
	var challengers := int(summary["unique_challengers"])
	if challengers <= 0:
		return -1.0
	return clampf(float(summary["unique_clearers"]) / float(challengers), 0.0, 1.0)

static func mode_of(creator_mode: String) -> String:
	return RBMCreatorDraft.CREATOR_MODE_ADVANCED if creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED else RBMCreatorDraft.CREATOR_MODE_SIMPLE

## 2つの記録をまとめる: ボスごとの和集合。同じボスはクリアした時刻（at）が早い方（同じなら a）。
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := empty(str(a.get("account", b.get("account", LOCAL_ACCOUNT))))
	var bosses: Dictionary = {}
	for src in [a, b]:
		var entries: Dictionary = src.get("bosses", {}) if src.get("bosses", {}) is Dictionary else {}
		for boss_id in entries:
			var e = entries[boss_id]
			if not e is Dictionary or str(boss_id).is_empty():
				continue
			var entry := _normalized(e)
			if not bosses.has(boss_id):
				bosses[boss_id] = entry
				continue
			# 難関は、どちらかで難関なら難関のまま（一度ついた実績は消さない。2026-10-23）
			var hard: bool = bool(entry.hard) or bool(bosses[boss_id].hard)
			if int(entry.at) < int(bosses[boss_id].at):
				bosses[boss_id] = entry
			bosses[boss_id].hard = hard
	out["bosses"] = bosses
	return out

static func _normalized(e: Dictionary) -> Dictionary:
	var rate := float(e.get("rate", -1.0)) if e.get("rate", null) != null else -1.0
	return {"mode": mode_of(str(e.get("mode", ""))), "rate": rate, "hard": bool(e.get("hard", false)), "at": int(e.get("at", 0))}

## 3つの数: {simple, hardcore, hard}
static func counts_of(d: Dictionary) -> Dictionary:
	var out := {"simple": 0, "hardcore": 0, "hard": 0}
	var entries: Dictionary = d.get("bosses", {}) if d.get("bosses", {}) is Dictionary else {}
	for boss_id in entries:
		var e: Dictionary = entries[boss_id]
		if str(e.get("mode", "")) == RBMCreatorDraft.CREATOR_MODE_ADVANCED:
			out.hardcore += 1
		else:
			out.simple += 1
		if bool(e.get("hard", false)):
			out.hard += 1
	return out

func counts() -> Dictionary:
	return counts_of(data)

func has_boss(boss_id: String) -> bool:
	return (data.get("bosses", {}) as Dictionary).has(boss_id)

# ---------------------------------------------------------------------------
# 保存

static func records_dir() -> String:
	return RBMLocalStageRepository.stages_dir().get_base_dir() + "/" + SUBDIR_NAME

func local_path() -> String:
	return "%s/%s.json" % [records_dir(), account_id]

static func _parse(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return {}
	# 壊れた記録は想定内（エラーを出力しない読み方。読めなければ空）
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary or str(parsed.get("format", "")) != FORMAT:
		return {}
	return parsed

func _read_local() -> Dictionary:
	var path := local_path()
	if not FileAccess.file_exists(path):
		return {}
	var parsed := _parse(FileAccess.get_file_as_string(path))
	if parsed.is_empty():
		# 壊れた手元の記録は消さずに脇へ避ける（後で書き直す時に上書きしない）
		DirAccess.rename_absolute(path, path + ".corrupt.%d" % int(Time.get_unix_time_from_system()))
	return parsed

func _write_local(d: Dictionary) -> bool:
	return RBMLocalStageRepository._atomic_write(local_path(), JSON.stringify(d, "\t", false))

## 手元と Steam Cloud を読んでまとめる（どちらかに無い分は、もう一方へ書き戻す）。
func load_records() -> Dictionary:
	var local := _read_local()
	var merged := merge(local, empty(account_id))
	merged["account"] = account_id
	var remote := {}
	var cloud_ok := cloud != null and cloud.is_available()
	if cloud != null:
		cloud_state = "synced" if cloud_ok else "unavailable"
	if cloud_ok:
		remote = _parse(cloud.read_text(CLOUD_FILE))
		if not remote.is_empty() and str(remote.get("account", account_id)) != account_id:
			remote = {}   # 別のアカウントの記録は混ぜない（Steam Cloud はアカウントごとなので通常は起きない）
		merged = merge(merged, remote)
		merged["account"] = account_id
	data = merged
	if not _same_bosses(merged, local):
		_write_local(merged)
	if cloud_ok and not _same_bosses(merged, remote) and not (merged.bosses as Dictionary).is_empty():
		if not cloud.write_text(CLOUD_FILE, JSON.stringify(merged, "	", false)):
			cloud_state = "write_failed"
	return data

static func _same_bosses(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(merge(a, {}).bosses, "", true) == JSON.stringify(merge(b, {}).bosses, "", true)

## 挑戦で勝った時に呼ぶ。初めてのボスなら記録して true、もう記録があれば何もしないで false。
## rate: その挑戦を始めた時の正式なクリア率（分からない時は -1）。
func record_clear(boss_id: String, creator_mode: String, rate: float, at_unix: int = -1, hard_awarded: bool = false) -> bool:
	if boss_id.is_empty():
		return false
	load_records()
	if has_boss(boss_id):
		# 再クリアは数えない。ただしサーバーが難関に認定していれば、さかのぼって難関をつける（2026-10-23）
		if hard_awarded:
			mark_hard([boss_id])
		return false
	var at := at_unix if at_unix >= 0 else int(Time.get_unix_time_from_system())
	# 難関はサーバーの認定（hard_awarded）だけで決める（2026-10-23。手元でクリア率から決めない）
	(data.bosses as Dictionary)[boss_id] = {"mode": mode_of(creator_mode), "rate": rate if rate >= 0.0 else -1.0, "hard": hard_awarded, "at": at}
	_save_everywhere()
	return true

## サーバーが認定した難関ボス討伐（list-my-hard-awards の一覧・クリアの記録の応答）を、もう記録があるボスにつける（2026-10-23）。
## 記録が無いボス（勝っていない・作者本人のボス・判定できなかった勝利）にはつけない。難関を消すことはしない。
## 戻り値: 新しく難関になったボスの数。
func mark_hard(boss_ids: Array) -> int:
	load_records()
	var changed := 0
	var bosses: Dictionary = data.get("bosses", {})
	for boss_id in boss_ids:
		var entry: Variant = bosses.get(str(boss_id), null)
		if entry is Dictionary and not bool((entry as Dictionary).get("hard", false)):
			(entry as Dictionary)["hard"] = true
			changed += 1
	if changed > 0:
		_save_everywhere()
	return changed

## 難関がまだついていない記録があるか（挑戦トップがサーバーの認定を受け取りに行くかの判断）。
func has_unawarded_entries() -> bool:
	var bosses: Dictionary = data.get("bosses", {})
	for boss_id in bosses:
		if not bool((bosses[boss_id] as Dictionary).get("hard", false)):
			return true
	return false

func _save_everywhere() -> void:
	_write_local(data)
	if cloud != null:
		if cloud.is_available():
			cloud_state = "synced" if cloud.write_text(CLOUD_FILE, JSON.stringify(data, "\t", false)) else "write_failed"
		else:
			cloud_state = "unavailable"
