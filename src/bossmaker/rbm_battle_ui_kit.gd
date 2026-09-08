class_name RBMBattleUiKit
extends RefCounted

## Phase 3.5 Step 4 — 戦闘UI・情報表示 第一次完成。
##
## TEST BATTLE / Clear Check / CHALLENGEの3画面が共有する「戦闘UIの語彙」
## （ログ/最新情報の日本語整形、状態表示ラベル、行動順、スキル詳細、対象の
## 弱点/耐性判定）と、3画面が同一構造で必要とする再利用可能なControl生成
## ヘルパーをここへ集約する。
##
## §21の指示（「可能な範囲で共通Battle UIコンポーネントへ整理」「戦闘ロジック
## の全面リファクタリング指示ではない」「リスクが想定以上に大きい場合は無理に
## 全面共通化せず報告」）を踏まえた設計判断:
## - RBMBattle/RBMCreatorTestSession/RBMChallengeSessionには一切触れない
##   （このクラスは読み取り専用——battle.party/battle.boss等の既存public
##   フィールドを読むだけで、状態を変更する呼び出しは一切行わない）。
## - このクラス自体はRefCountedのstatic関数群として実装し、3画面が持つ
##   セッション差分（REWINDの有無・確認ダイアログの文言・結果画面のボタン
##   構成等）には一切関与しない——それらは各Viewが従来どおり個別に持つ
##   （このファイル群が既に明示している「意図的な複製」方針を、セッション
##   固有の責務についてはそのまま踏襲する）。
## - 状態を持つ「累積戦闘ログ履歴」自体（Array[Dictionary]の保持・REWINDに
##   合わせた切り詰め）は、3画面それぞれが自分自身のインスタンス変数として
##   個別に持つ（4〜5行程度の極小ロジックのため、共有ステートフルオブジェクト
##   を新設するコストに見合わない）——ただしその中身をどう日本語へ整形するか
##   （このファイルの主要な役割）は完全に共通化する。
##
## Phase 3.5 Step 4 §10/§18: RBMBattleが返す各ログentryは、Step 4のこの回で
## 追加された"turn"キー（そのentryが実際に発生したcurrent_turn値、表示専用の
## 追加メタデータ——rbm_battle.gd._log_entry()参照）を必ず持つ。このファイルの
## 関数群はこの値を、REWIND後に「巻き戻した未来側のログ行」を正確に除去する
## ためだけに使う（表示テキスト自体には含めない）。

# =============================================================================
# 基礎ヘルパー（既存3Viewが個別に複製していたものの共通化）
# =============================================================================

## Phase 3.5 Step 4で導入した永続コンテナ（毎refresh()で作り直さず、中身の
## Buttonだけを毎回総入れ替えするパターン——_main_command_row/_skill_list_
## panel/turn_order_panelの各List等）の子を安全にクリアするための共通
## ヘルパー。
## 単純にqueue_free()だけだと、次フレームまで実際にはツリーに残るため、
## 同一フレーム内でrefresh()が2回呼ばれた場合に新しい同名の子（"AttackButton"
## 等、固定名）が旧・削除待ちの子と衝突し、Godotが新しい方を自動リネーム
## してしまう（RBMChallengeEntry._refresh_list()が既に踏み、free()で解決
## 済みの既知のクラスの不具合）。
## 単純にfree()だけだと、逆に「まさにそのButtonのpressed信号ハンドラの中で、
## そのButton自身を含む親の子をクリアする」という、このファイル群の全
## コマンドボタン（act_attack等）に共通する呼び出しパターンで
## "Attempted to free a locked object (calling or emitting)"実行時エラーに
## なる（シグナル発火中のオブジェクトは直接freeできないというGodotの制約）。
## remove_child()（即座にツリーから外す——名前衝突を回避）と、実際の破棄は
## 次のアイドル処理まで遅延させるqueue_free()（シグナル発火中のfreeを回避）
## を組み合わせることで、両方の問題を同時に解決する。
static func clear_children_safely(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

## Phase 3.5 タイトル画面UI新設 §9/§10: 各戦闘View（TEST/Clear Check/
## CHALLENGE）自身のルートはbareなControlで、元々自前の背景を一切持たない
## （StyleBoxを描くPanel/PanelContainerではないため）。Theme適用だけでは
## この根本のルートControlに背景色は付かず、実スクリーンショットで確認した
## ところGodotの既定clear color（無地グレー、タイトル画面の背景やパネルの
## 濃紺と全く馴染まない）がそのまま透けて見えていた——タイトル画面の
## _title_background_fallbackと同じ考え方で、各Viewのルートへこの共有
## ヘルパーで同じCOLOR_BACKGROUNDを敷く（新しい色を増やさず、既存の背景色を
## 再利用するだけ）。
static func add_root_background(parent: Control) -> ColorRect:
	var bg := ColorRect.new()
	bg.name = "RootBackground"
	bg.color = RBMUiTheme.COLOR_BACKGROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	return bg

static func unit_by_id(battle: RBMBattle, unit_id: int) -> RBMUnit:
	for unit in battle.party:
		if unit.id == unit_id:
			return unit
	return null

static func find_skill_on_unit(unit: RBMUnit, skill_id: String) -> Dictionary:
	for skill in unit.skills:
		if str(skill.get("id", "")) == skill_id:
			return skill
	return {}

static func actor_display_name(actor, battle: RBMBattle) -> String:
	if str(actor) == "boss":
		return battle.boss.display_name
	var unit := unit_by_id(battle, int(actor))
	return unit.display_name if unit != null else "？"

## entryの行動者が使ったskill_idから、その行動者(actor)自身のスキル一覧を
## 検索する（ボスならboss.skills、味方ならそのunitのskills）。
static func find_skill_for_actor(actor, skill_id: String, battle: RBMBattle) -> Dictionary:
	var unit: RBMUnit = battle.boss if str(actor) == "boss" else unit_by_id(battle, int(actor))
	if unit == null:
		return {}
	return find_skill_on_unit(unit, skill_id)

# =============================================================================
# 弱点/耐性判定 (§9/§11: ログ/最新情報には「弱点！」等の発動有無のみを表示し、
# 倍率(×1.2/×0.8)は一切表示しない)
# =============================================================================

## skill(attacker側が使った、attribute フィールドを持つ攻撃スキル)がtargetに
## 命中した際、弱点/耐性のどちらに触れたかを返す（"weak"/"resist"/""）。
## RBMConstants.attribute_multiplier_for_lists()と同じ判定基準を、表示専用に
## 再利用する（RBMBattle自身の判定結果を再計算するのではなく、同じ入力—
## skillのattribute・targetのweak_attributes/resist_attributes—から同じ結論を
## 導く。数値計算そのもの(ダメージ量)には一切関与しない）。
static func attribute_hit_kind(skill: Dictionary, target: RBMUnit) -> String:
	if not skill.has("attribute"):
		return ""
	var attribute: RBMConstants.Attribute = RBMConstants.attribute_from_name(str(skill.get("attribute", "NEUTRAL")))
	if target.weak_attributes.has(attribute):
		return "weak"
	if target.resist_attributes.has(attribute):
		return "resist"
	return ""

# =============================================================================
# ログ/最新戦闘情報の日本語整形 (§9/§10/§11)
# =============================================================================

const REASON_LABELS := {
	"unspecified_action": "行動が指定されていません",
	"invalid_action": "不正な行動です",
	"unknown_skill": "不明なスキルです",
	"invalid_target": "対象が無効です",
	"insufficient_sp": "SPが足りません",
	"target_downed": "対象は戦闘不能です",
}

const AMOUNT_UNIT_BY_EFFECT := {
	"heal": "回復",
	"sp_recover_single_no_self": "SP回復",
	"sp_recover_all_no_self": "SP回復",
}

## 1件のログentryを構造化して返す。
##   actor_name: String
##   headline: String — "氷属性単体魔法" / "通常攻撃" / "防御" / "行動失敗（理由）" / "行動しなかった"
##   result_lines: Array[String] — 「弱点！」「ボスに184ダメージ」等、0件以上
## §9で明示的に禁止された内容（SP増減数値・弱点/耐性倍率・内部計算式）は
## どのフィールドにも一切含めない。
static func describe_entry(entry: Dictionary, battle: RBMBattle) -> Dictionary:
	var actor_name := actor_display_name(entry.get("actor"), battle)
	if bool(entry.get("failed", false)):
		var reason := str(entry.get("reason", ""))
		return {
			"actor_name": actor_name,
			"headline": "行動失敗（%s）" % str(REASON_LABELS.get(reason, reason)),
			"result_lines": [],
		}
	var action := str(entry.get("action", ""))
	match action:
		"attack":
			return {
				"actor_name": actor_name,
				"headline": "通常攻撃",
				"result_lines": ["%s に %d ダメージ" % [actor_display_name(entry.get("target", "boss"), battle), int(entry.get("amount", 0))]],
			}
		"defend":
			return {"actor_name": actor_name, "headline": "防御", "result_lines": []}
		"none":
			return {"actor_name": actor_name, "headline": "行動しなかった", "result_lines": []}
		"skill":
			return _describe_skill_entry(entry, actor_name, battle)
		_:
			return {"actor_name": actor_name, "headline": "", "result_lines": []}

static func _describe_skill_entry(entry: Dictionary, actor_name: String, battle: RBMBattle) -> Dictionary:
	var actor = entry.get("actor")
	var skill_id := str(entry.get("skill_id", ""))
	var skill := find_skill_for_actor(actor, skill_id, battle)
	var headline := str(skill.get("display_name", skill_id))
	var result_lines: Array[String] = []

	if entry.has("hits"):
		# ボスの全体攻撃: hits = {unit_id -> amount}。各対象ごとに弱点/耐性を
		# 個別判定する（対象ごとに違う場合があるため一括では扱えない）。
		var hits: Dictionary = entry["hits"]
		for uid in hits.keys():
			var hit: Dictionary = hits[uid] if hits[uid] is Dictionary else {"target": uid, "amount": hits[uid]}
			var target := unit_by_id(battle, int(hit.get("target", uid)))
			if target != null:
				_append_weak_resist_line(result_lines, skill, target)
			result_lines.append("%s に %d ダメージ" % [actor_display_name(hit.get("target", uid), battle), int(hit.get("amount", 0))])
			if bool(hit.get("counter", false)):
				result_lines.append("攻撃を防いだ！ 反撃！ %s に %d ダメージ" % [battle.boss.display_name, int(hit.get("reflected", 0))])
	elif entry.has("healed"):
		var healed: Dictionary = entry["healed"]
		for uid in healed.keys():
			result_lines.append("%s に %d 回復" % [actor_display_name(uid, battle), int(healed[uid])])
	elif entry.has("recovered"):
		var recovered: Dictionary = entry["recovered"]
		for uid in recovered.keys():
			result_lines.append("%s に %d SP回復" % [actor_display_name(uid, battle), int(recovered[uid])])
	elif entry.has("amount"):
		var unit_label := str(AMOUNT_UNIT_BY_EFFECT.get(str(skill.get("effect", "")), "ダメージ"))
		var target_variant = entry.get("target")
		var target_unit: RBMUnit = null
		if target_variant != null and str(target_variant) != "boss":
			target_unit = unit_by_id(battle, int(target_variant))
		elif str(target_variant) == "boss":
			target_unit = battle.boss
		if target_unit != null and unit_label == "ダメージ":
			_append_weak_resist_line(result_lines, skill, target_unit)
		if entry.has("target"):
			result_lines.append("%s に %d %s" % [actor_display_name(entry["target"], battle), int(entry["amount"]), unit_label])
		else:
			result_lines.append("%d %s" % [int(entry["amount"]), unit_label])
	elif entry.has("protecting"):
		result_lines.append("%s をかばう" % actor_display_name(entry["protecting"], battle))

	# カウンター（ブロック＋反射）: §11「カウンター発動」。ブロックした事実と
	# 反射ダメージの両方を表示する。反射側の弱点/耐性は、反射に使われた
	# active_counter_skillのattributeを直接は追跡していないため（entry自体が
	# 保持しない）、今回は反射ダメージの数値のみを表示する——数値を捏造せず、
	# 確実に取得できる情報だけを表示する方針。
	if bool(entry.get("counter", false)) and bool(entry.get("blocked", false)):
		result_lines.append("%s の攻撃を防いだ！" % ("ボス" if str(actor) != "boss" else "味方"))
		if entry.has("reflected"):
			result_lines.append("反撃！ %s に %d ダメージ" % [actor_display_name("boss", battle), int(entry["reflected"])])

	return {"actor_name": actor_name, "headline": headline, "result_lines": result_lines}

static func _append_weak_resist_line(result_lines: Array, skill: Dictionary, target: RBMUnit) -> void:
	match attribute_hit_kind(skill, target):
		"weak":
			result_lines.append("弱点！")
		"resist":
			result_lines.append("耐性！")
		_:
			pass

## §9: 最新戦闘情報——直近の1バッチの最後の"意味のある"entryを、2〜3行程度の
## 簡潔なブロックとして整形する。バッチの末尾が「行動可能なスキルが無い等で
## ボスが何もしなかった」（action=="none"、_pick_boss_normal_action()が
## candidates空で{}を返した場合の"actor":"boss","action":"none"）で終わる
## ケースがあり、これをそのまま採用すると「最新の戦闘情報: ボスは行動
## しなかった」という無意味な表示になってしまう——末尾から遡って
## action!="none"の最初のentryを採用し、見当たらなければ（全entryが
## none、通常起こり得ない極端なケース）最後のentryへフォールバックする。
static func format_latest_info(entries: Array, battle: RBMBattle) -> String:
	if entries.is_empty():
		return ""
	var chosen: Dictionary = entries[-1]
	for i in range(entries.size() - 1, -1, -1):
		if str((entries[i] as Dictionary).get("action", "")) != "none":
			chosen = entries[i]
			break
	var described := describe_entry(chosen, battle)
	var lines: Array[String] = []
	lines.append("%s：%s" % [described["actor_name"], described["headline"]])
	if not (described["result_lines"] as Array).is_empty():
		lines.append("")
		for line in described["result_lines"]:
			lines.append(str(line))
	return "\n".join(lines)

## §10/§11: 累積ログ——1バッチに含まれる全entryを、行動宣言＋"→"付き結果行
## の並びとして整形する（履歴ウィンドウが複数バッチ分をそのまま連結して
## 表示できるよう、フラットなArray[String]で返す）。
static func format_log_lines_for_batch(entries: Array, battle: RBMBattle) -> Array[String]:
	var lines: Array[String] = []
	for entry in entries:
		var described := describe_entry(entry, battle)
		lines.append("%s：%s" % [described["actor_name"], described["headline"]])
		for line in described["result_lines"]:
			lines.append("→ %s" % str(line))
	return lines

## §10: 累積ログ全体（複数ターンにまたがる、REWINDで既に未来側が除去済みの
## history配列）を、"TURN N"見出し付きでまとめてテキスト化する。
## history内の各entryは"turn"キー（rbm_battle.gd._log_entry()が付与）を必ず
## 持つ——このキーは見出しのグルーピングにのみ使い、本文には出力しない。
static func format_log_window_text(history: Array[Dictionary], battle: RBMBattle) -> String:
	if history.is_empty():
		return "まだ戦闘記録がありません"
	var blocks: Array[String] = []
	var current_turn := -1
	var current_lines: Array[String] = []
	for entry in history:
		var entry_turn := int(entry.get("turn", 1))
		if entry_turn != current_turn:
			if current_turn != -1:
				blocks.append("TURN %d\n\n%s" % [current_turn, "\n".join(current_lines)])
			current_turn = entry_turn
			current_lines = []
		var described := describe_entry(entry, battle)
		current_lines.append("%s：%s" % [described["actor_name"], described["headline"]])
		for line in described["result_lines"]:
			current_lines.append("→ %s" % str(line))
	if current_turn != -1:
		blocks.append("TURN %d\n\n%s" % [current_turn, "\n".join(current_lines)])
	return "\n\n".join(blocks)

## REWINDで戻った先(target_turn)より後のターンのログ行を除去した、新しい
## history配列を返す（§18「巻き戻した未来側のログが残らないようにする」の
## 直接実装）。target_turn自体は「まだ何も処理されていない、そのTurnの
## 純粋な開始地点」を指すため、target_turn以降のentryはすべて除去する
## （< target_turnのentryだけを残す）。
static func history_truncated_for_rewind(history: Array[Dictionary], target_turn: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in history:
		if int(entry.get("turn", 1)) < target_turn:
			out.append(entry)
	return out

# =============================================================================
# 行動順 (§7/§8)
# =============================================================================

const TURN_ORDER_STATUS_ACTED := "acted"
const TURN_ORDER_STATUS_CURRENT := "current"
const TURN_ORDER_STATUS_UPCOMING := "upcoming"

## battle.turn_order（SPD順、戦闘開始時に一度だけ確定・以後変化しない）と
## battle.round_cursor()（現在のラウンドで何番目まで処理済みか）から、
## 「単純な固定SPD一覧」ではなく実際の戦闘状態と矛盾しない行動順リストを
## 構築する。各要素: {display_name, status, is_boss, is_downed}。
## round_cursorはUI（Session経由でadvance_to_next_decision()を回した後）へ
## 制御が戻る時点で、必ず「生存する味方の入力待ち」か「battle_over」の
## いずれかで静止している（rbm_battle.gdクラス冒頭コメント参照）——このため
## 「acted」/「current」/「upcoming」の3値だけで現在の状態を過不足なく
## 表現できる。
static func turn_order_entries(battle: RBMBattle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cursor := battle.round_cursor()
	for i in range(battle.turn_order.size()):
		var token: String = battle.turn_order[i]
		var is_boss := token == "boss"
		var unit: RBMUnit = battle.boss if is_boss else unit_by_id(battle, int(token.substr(5)))
		if unit == null:
			continue
		var status := TURN_ORDER_STATUS_UPCOMING
		if i < cursor:
			status = TURN_ORDER_STATUS_ACTED
		elif i == cursor and not battle.battle_over:
			status = TURN_ORDER_STATUS_CURRENT
		out.append({
			"display_name": unit.display_name,
			"status": status,
			"is_boss": is_boss,
			"is_downed": unit.is_downed(),
		})
	return out

# =============================================================================
# 状態表示 (§4/§5: 味方/ボス詳細ウィンドウの「現在の状態」)
# =============================================================================

## 現在有効なtimed_effect（"atk_buff"等）の残りターン数——RBMConstants.
## timed_effect_active()と同じ基準（applied_at_turn+duration_turns-1が最後の
## 有効ターン）。
static func _remaining_turns(effects: Dictionary, key: String, current_turn: int) -> int:
	if not RBMConstants.timed_effect_active(effects, key, current_turn):
		return 0
	var entry: Dictionary = effects[key]
	return int(entry["applied_at_turn"]) + int(entry["duration_turns"]) - current_turn

## §4: 味方1人の「現在の状態」——内部変数名(is_defending/timed_effects等)を
## 一切表示せず、プレイヤーが理解できる日本語の状態名＋残りターンのみを返す。
## 状態が1つも無ければ空配列（呼び出し側が「現在の状態：なし」を表示する）。
static func unit_state_lines(unit: RBMUnit, battle: RBMBattle) -> Array[String]:
	var lines: Array[String] = []
	if RBMConstants.timed_effect_active(unit.timed_effects, "atk_buff", battle.current_turn):
		var mult := float(RBMConstants.timed_effect_value(unit.timed_effects, "atk_buff", battle.current_turn, 1.0))
		lines.append("ATK強化 ×%s　残り%dターン" % [_format_multiplier(mult), _remaining_turns(unit.timed_effects, "atk_buff", battle.current_turn)])
	if unit.is_defending:
		lines.append("防御")
	if RBMConstants.timed_effect_active(battle.party_timed_effects, "guard_boost", battle.current_turn):
		lines.append("防御強化　残り%dターン" % _remaining_turns(battle.party_timed_effects, "guard_boost", battle.current_turn))
	if RBMConstants.timed_effect_active(battle.party_timed_effects, "iron_wall", battle.current_turn):
		lines.append("鉄壁　残り%dターン" % _remaining_turns(battle.party_timed_effects, "iron_wall", battle.current_turn))
	if unit.next_attack_bonus_multiplier != 1.0:
		lines.append("居合の構え")
	if unit.counter_pending_this_turn:
		lines.append("カウンター待機")
	if unit.protecting_ally_id != -1:
		var protected_unit := unit_by_id(battle, unit.protecting_ally_id)
		if protected_unit != null:
			lines.append("%s をかばう" % protected_unit.display_name)
	# かばう対象: 自分が「かばわれている」側かどうか(他ユニットのprotecting_ally_idが自分)。
	for other in battle.party:
		if other.id != unit.id and other.protecting_ally_id == unit.id and not other.is_downed():
			lines.append("%s にかばわれている" % other.display_name)
	return lines

## §5: ボスの「現在の状態」——このエンジンでボスが実際に持ちうる時限効果は
## atk_buff（buff_atk_selfスキル由来）のみ（防御/防御強化/鉄壁はRBMBattle.
## _damage_reduction_multiplier()により味方専用の仕組みで、ボスには構造的に
## 適用され得ない——存在しないゲームルールをここで新設・表示しない）。
static func boss_state_lines(battle: RBMBattle) -> Array[String]:
	var lines: Array[String] = []
	var boss := battle.boss
	if RBMConstants.timed_effect_active(boss.timed_effects, "atk_buff", battle.current_turn):
		var mult := float(RBMConstants.timed_effect_value(boss.timed_effects, "atk_buff", battle.current_turn, 1.0))
		lines.append("ATK強化 ×%s　残り%dターン" % [_format_multiplier(mult), _remaining_turns(boss.timed_effects, "atk_buff", battle.current_turn)])
	return lines

static func _format_multiplier(value: float) -> String:
	# 1.75 -> "1.75", 2.0 -> "2" の見た目差はプレイヤーへの実害が無いため、
	# 単純に小数点以下2桁までを表示しつつ末尾の不要な0/.を削る。
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text

# =============================================================================
# スキル詳細 (§16)
# =============================================================================

const ATTRIBUTE_DISPLAY_NAMES := {
	"FIRE": "炎", "ICE": "氷", "LIGHTNING": "雷", "WIND": "風", "NEUTRAL": "無",
}

const SKILL_TARGET_DISPLAY_NAMES := {
	"boss": "ボス",
	"ally_all": "味方全体",
	"ally_chosen": "味方単体（自分含む）",
	"ally_chosen_no_self": "味方単体（自分以外）",
	"ally_random_single": "味方単体（ランダム）",
}

## §16: 現在のマスターデータに実在するフィールドだけを使い、スキル1つの
## 詳細を表示用の行配列として返す。存在しないフィールドは行ごと省略する
## （推測・捏造しない）。is_allyがtrueの時だけSP消費を表示する（ボス
## スキルはSPを消費しない——RBMDataLoader.unit_from_boss_def()参照）。
static func skill_detail_lines(skill: Dictionary, is_ally: bool) -> Array[String]:
	var lines: Array[String] = []
	if is_ally and skill.has("sp_cost"):
		lines.append("消費SP：%d" % int(skill["sp_cost"]))
	if skill.has("target"):
		var target_key := str(skill["target"])
		lines.append("対象：%s" % str(SKILL_TARGET_DISPLAY_NAMES.get(target_key, target_key)))
	if skill.has("attribute"):
		lines.append("属性：%s" % str(ATTRIBUTE_DISPLAY_NAMES.get(str(skill["attribute"]), str(skill["attribute"]))))
	if skill.has("atk_multiplier"):
		lines.append("威力：%s倍" % _format_multiplier(float(skill["atk_multiplier"])))
	if skill.has("heal_amount"):
		lines.append("回復量：%d" % int(skill["heal_amount"]))
	if skill.has("sp_amount"):
		lines.append("回復SP：%d" % int(skill["sp_amount"]))
	if skill.has("buff_multiplier"):
		lines.append("効果：ATK ×%s" % _format_multiplier(float(skill["buff_multiplier"])))
	if skill.has("duration_turns"):
		lines.append("効果時間：%dターン" % int(skill["duration_turns"]))
	match str(skill.get("effect", "")):
		"buff_next_attack":
			lines.append("効果：次の攻撃スキルのダメージを強化（居合の構え）")
		"counter_stance":
			lines.append("効果：次に受ける攻撃を無効化し反撃（カウンター待機）")
		"guard_boost":
			lines.append("効果：味方全体の防御軽減率を強化（防御強化）")
		"party_damage_reduction":
			lines.append("効果：味方全体のダメージを継続軽減（鉄壁）")
		"guard_redirect":
			lines.append("効果：指定した味方への攻撃をかばう")
		_:
			pass
	return lines

# =============================================================================
# スキルコマンド行 (§15)
# =============================================================================

## §15/Phase 3.5 Step 3: SP不足なら選択不可＋テキストへ補足——Step 3で確定した
## 唯一の判定条件(unit.sp < sp_cost)をそのまま踏襲する。
static func skill_is_disabled(skill: Dictionary, unit: RBMUnit) -> bool:
	var sp_cost := int(skill.get("sp_cost", 0))
	return unit.has_sp_resource() and unit.sp < sp_cost

static func skill_row_text(skill: Dictionary, unit: RBMUnit) -> String:
	var sp_cost := int(skill.get("sp_cost", 0))
	var display_name := str(skill.get("display_name", skill.get("id", "")))
	var suffix := "（SP不足）" if skill_is_disabled(skill, unit) else ""
	return "%s　SP %d%s" % [display_name, sp_cost, suffix]

# =============================================================================
# 再利用可能なControl生成ヘルパー (§21: 「可能な範囲で共通Battle UI
# コンポーネントへ整理」)
# =============================================================================
#
# 各Viewは以下の関数を呼んでControlを構築するが、シグナルの配線・
# セッション駆動（session.resolve_ally_action()等）・REWIND/確認ダイアログ
# 等のモード固有ロジックはすべて各View自身が引き続き所有する——このセクション
# はあくまで「同じ構造のControl木を毎回同じ規則で組み立てる」役割のみを
# 共通化したもので、状態を持つ共有コンポーネント（シグナルを自前で発火する
# ウィジェットクラス等）は新設していない（§21「戦闘ロジックの全面リファクタ
# リング指示ではない」を踏まえたスコープ判断）。

## Phase 3.5 UI統一§18/§19: 「名前／標準ProgressBar／HP文字／標準
## ProgressBar／SP文字」という開発UI的な縦積みを、小型RPGステータス領域
## （顔アイコン枠＋名前を横に並べた見出し行、その下にHP/SPを数値付きの
## 細いバーとして重ねて表示）へ再構成する。既存の名前付きLabel/ProgressBar
## （PartyRow_%d/PartyRowName_%d/PartyRowHP_%d/PartyRowHPBar_%d/
## PartyRowSP_%d/PartyRowSPBar_%d）はv0.1〜Phase 3.5 Step 3以前からの複数の
## 既存テストがこの正確な名前・.textの内容に依存しているため無改修のまま
## 維持する——変わるのは木構造上の親子関係と見た目（StyleBox/配置）のみ。
## on_click: Callable — 引数(unit_id:int)を受け取り、味方詳細ウィンドウを
## 開く（各Viewが自分のopen_ally_detail()等を.bind()して渡す）。
static func build_party_card(unit: RBMUnit, on_click: Callable) -> Control:
	var card := PanelContainer.new()
	card.name = "PartyRow_%d" % unit.id
	card.custom_minimum_size = Vector2(168, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	# バグ修正: 共有Panel StyleBoxの既定16px余白（詳細ウィンドウ等の大きな
	# パネル向け）をそのまま継承すると、パーティ人数分だけ縦に嵩んで戦闘
	# 画面下部を圧迫する（§33）。コンパクトなステータス領域向けの軽量な
	# 余白へ差し替える——形（角丸・枠線色）自体は共有Panelと同じまま。
	card.add_theme_stylebox_override("panel", _compact_panel_box())
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			on_click.call(unit.id)
	)
	if unit.is_downed():
		card.modulate = Color(1.0, 1.0, 1.0, 0.55)

	var body := VBoxContainer.new()
	body.name = "PartyRowBody_%d" % unit.id
	card.add_child(body)

	var header := HBoxContainer.new()
	header.name = "PartyRowHeader_%d" % unit.id
	body.add_child(header)

	# §18: 「将来の顔アイコン領域」——正式ドット絵が無い間は暗い額縁のみ。
	header.add_child(build_portrait(unit.character_id, 32.0, "PartyRowPortrait_%d" % unit.id))

	var name_label := Label.new()
	name_label.name = "PartyRowName_%d" % unit.id
	name_label.text = "%s%s" % [unit.display_name, "（戦闘不能）" if unit.is_downed() else ""]
	name_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(name_label)

	var hp_row := HBoxContainer.new()
	body.add_child(hp_row)
	var hp_label := Label.new()
	hp_label.name = "PartyRowHP_%d" % unit.id
	hp_label.text = "HP %d / %d" % [unit.hp, unit.max_hp]
	hp_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	hp_row.add_child(hp_label)

	var hp_bar := ProgressBar.new()
	hp_bar.name = "PartyRowHPBar_%d" % unit.id
	hp_bar.theme_type_variation = RBMUiTheme.VARIATION_HP_BAR
	hp_bar.custom_minimum_size = Vector2(0, 10)
	hp_bar.max_value = maxf(1.0, float(unit.max_hp))
	hp_bar.value = float(unit.hp)
	hp_bar.show_percentage = false
	body.add_child(hp_bar)

	if unit.has_sp_resource():
		var sp_row := HBoxContainer.new()
		body.add_child(sp_row)
		var sp_label := Label.new()
		sp_label.name = "PartyRowSP_%d" % unit.id
		sp_label.text = "SP %d / %d" % [unit.sp, unit.max_sp]
		sp_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
		sp_row.add_child(sp_label)

		var sp_bar := ProgressBar.new()
		sp_bar.name = "PartyRowSPBar_%d" % unit.id
		sp_bar.theme_type_variation = RBMUiTheme.VARIATION_SP_BAR
		sp_bar.custom_minimum_size = Vector2(0, 10)
		sp_bar.max_value = maxf(1.0, float(unit.max_sp))
		sp_bar.value = float(unit.sp)
		sp_bar.show_percentage = false
		body.add_child(sp_bar)
	else:
		# §19の既存契約（"SP -"というテキストを持つPartyRowSP_%dラベルが
		# 常に存在する）を維持する——SP資源を持たないユニットでもバーを
		## 持たないだけでラベル自体は変わらず表示する。
		var sp_label := Label.new()
		sp_label.name = "PartyRowSP_%d" % unit.id
		sp_label.text = "SP -"
		sp_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
		body.add_child(sp_label)

	return card

## パーティカード・戦場のプレースホルダー枠等、コンパクトな要素向けの軽量
## Panel StyleBox——形（角丸・枠線色）は共有Panelと同じまま、余白だけ
## 詳細ウィンドウ向けの16pxから6pxへ縮める。
static func _compact_panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = RBMUiTheme.COLOR_PANEL
	box.set_corner_radius_all(RBMUiTheme.CORNER_RADIUS)
	box.set_content_margin_all(6.0)
	box.border_width_left = RBMUiTheme.BORDER_WIDTH
	box.border_width_right = RBMUiTheme.BORDER_WIDTH
	box.border_width_top = RBMUiTheme.BORDER_WIDTH
	box.border_width_bottom = RBMUiTheme.BORDER_WIDTH
	box.border_color = RBMUiTheme.COLOR_PANEL_BORDER
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

## §16/§17/§18: 戦場・カード双方で使う、将来Sprite/Textureへ差し替え可能な
## プレースホルダー枠。現在は正式アートが存在しないため、Panelの暗い額縁
## （既存の共有Panel StyleBox、新しい配色は増やさない）だけで表現する——
## AI画像は生成しない。中身を持たない空の額縁のまま、将来ここへ
## TextureRectを追加するだけで差し替えられる構造にしてある。
static func build_portrait(asset_id: String, portrait_size: float, node_name: String) -> Control:
	var portrait := TextureRect.new()
	portrait.name = node_name
	portrait.custom_minimum_size = Vector2(portrait_size, portrait_size)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := RBMVisualAssets.texture(asset_id)
	if texture != null:
		var image := texture.get_image()
		# get_image() can return null for a texture whose import settings make it
		# non-CPU-readable (e.g. VRAM compression) -- fall back to the uncropped
		# texture rather than crashing on a null Image.
		if image == null:
			portrait.texture = texture
			return portrait
		var used := image.get_used_rect()
		var side := mini(used.size.x, int(used.size.y * 0.50))
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(used.position.x + (used.size.x - side) * 0.5, used.position.y, side, side)
		portrait.texture = atlas
	return portrait

static func build_portrait_placeholder(size: float, node_name: String, asset_id: String = "") -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = node_name
	frame.custom_minimum_size = Vector2(size, size)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not asset_id.is_empty():
		var sprite := TextureRect.new()
		sprite.texture = RBMVisualAssets.texture(asset_id)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(sprite)
	return frame

# =============================================================================
# 戦場内のキャラクター配置 (§15/§16/§17)
# =============================================================================

## §15/§16: 戦場内へBOSSを上部中央・味方をその下へ横並びで配置する
## （HP/ATK/SPD等はここへ一切常設しない——それらは既存のbuild_party_card
## 側の担当のまま）。boss_labelは呼び出し元が既に構築・クリックハンドラを
## 配線済みのLabel（既存の"BossLabel"、name/クリック契約は無改修）を
## そのままこの新しい階層へ受け取って配置するだけ——ここで新規に作らない。
## 戻り値のstage["ally_row"]へrefresh_battlefield_ally_row()を毎refresh()
## 呼び出す。
static func build_battlefield_stage(parent: Control, boss_label: Label) -> Dictionary:
	var stage := VBoxContainer.new()
	stage.name = "BattlefieldStage"
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 0)
	parent.add_child(stage)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(boss_label)
	var visual_stage := RBMBattleStage.new()
	visual_stage.name = "BattleVisualStage"
	visual_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(visual_stage)
	# Stable compatibility handle used by the three battle views.
	var ally_row := HBoxContainer.new()
	ally_row.name = "BattlefieldAllyRow"
	ally_row.visible = false
	ally_row.set_meta("visual_stage", visual_stage)
	stage.add_child(ally_row)
	return {"stage": stage, "ally_row": ally_row, "visual_stage": visual_stage}

## §16: 戦場内の味方1体分——アイコン枠＋名前のみ（HP/SP等は表示しない、
## build_party_card側の下部ステータス領域が既にその役割を持つ）。クリックで
## 味方詳細を開く（build_party_cardと同じon_click契約）。
static func build_battlefield_ally_presence(unit: RBMUnit, on_click: Callable) -> Control:
	var column := VBoxContainer.new()
	column.name = "BattlefieldAlly_%d" % unit.id
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_STOP
	column.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			on_click.call(unit.id)
	)
	if unit.is_downed():
		column.modulate = Color(1.0, 1.0, 1.0, 0.4)

	var portrait_wrap := CenterContainer.new()
	column.add_child(portrait_wrap)
	portrait_wrap.add_child(build_portrait_placeholder(56.0, "BattlefieldAllyPortrait_%d" % unit.id))

	var name_label := Label.new()
	name_label.name = "BattlefieldAllyName_%d" % unit.id
	name_label.text = unit.display_name
	name_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)

	return column

## build_battlefield_stage()が返したally_rowを、毎refresh()の呼び出しで
## 現在のbattle.partyへ合わせて作り直す（人数はCreatorの選択次第で変わる
## ため、build_party_cardと同じ理由でrefreshのたび作り直す設計）。
static func refresh_battlefield_ally_row(ally_row: Control, battle: RBMBattle, on_click: Callable) -> void:
	var visual_stage: Node = ally_row.get_meta("visual_stage", null) as Node
	if is_instance_valid(visual_stage):
		visual_stage.set_state(battle.presentation_state())
		return
	clear_children_safely(ally_row)
	for unit in battle.party:
		ally_row.add_child(build_battlefield_ally_presence(unit, on_click))

## §7/§8: 行動順パネルの外枠だけを1回生成する。中身はrefresh_turn_order_panel()
## が毎refresh()呼び出しで作り直す。横並びにはしない（VBoxContainerのみ）。
static func build_turn_order_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.name = "TurnOrderPanel"
	panel.custom_minimum_size = Vector2(120, 0)
	var title := Label.new()
	title.name = "TurnOrderTitleLabel"
	title.text = "行動順"
	title.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	panel.add_child(title)
	var list := VBoxContainer.new()
	list.name = "TurnOrderList"
	panel.add_child(list)
	return panel

## §7/§20: 「単純な固定SPD一覧ではなく、現在の戦闘状態に対応した実際の
## 行動順」——turn_order_entries()（既に行動した/現在入力待ち/これから行動
## する、をbattle.round_cursor()から正しく判定済み）をそのまま描画するだけ。
## Phase 3.5 UI統一§20: 「ただの白文字一覧」から、行ごとに細い枠を持つ
## コンパクトなRPGターン順表示へ再構成——将来「▶ [顔アイコン]」へ移行できる
## よう、各行はPanelContainer（将来アイコンを追加する余地）＋▶インジケータ
## ＋名前の横並びにする。現在行動中の行だけ、既存の共有Panel StyleBoxとは
## 別の、ごく細い銅アクセント枠を追加する（巨大な発光は使わない、§20明示
## 禁止）。既に行動済み/戦闘不能のユニットは引き続きmodulateで減光する——
## 「○○の番です」のような別テキストは一切出力しない（§8、無改修）。
static func refresh_turn_order_panel(panel: Control, battle: RBMBattle) -> void:
	var list: Control = panel.get_node("TurnOrderList")
	clear_children_safely(list)
	for entry in turn_order_entries(battle):
		var is_current: bool = entry["status"] == TURN_ORDER_STATUS_CURRENT

		var row := PanelContainer.new()
		row.name = "TurnOrderRow_%s" % str(entry["display_name"])
		# バグ修正（実装後の実GPUスクリーンショットで発見）: 共有Panel
		# StyleBoxの既定content_margin（PANEL_CONTENT_MARGIN=16px、詳細
		# ウィンドウ等の大きなパネル向け）を全行が継承すると、3行だけでも
		# 縦に大きく積み上がり、戦闘画面下部のコマンド行が画面外へ押し出
		# されて切れる（§33で明示禁止）。全行（現在行動中かどうかに関わらず）
		# へ明示的に軽量なStyleBoxを適用し、共有Panelの重い余白を継承しない
		# ようにする。
		row.add_theme_stylebox_override("panel", _turn_order_current_box() if is_current else _turn_order_row_box())

		var content := HBoxContainer.new()
		row.add_child(content)

		var indicator := Label.new()
		indicator.text = "▶" if is_current else "　"
		indicator.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
		content.add_child(indicator)

		var name_text: String = entry["display_name"]
		if entry["is_downed"]:
			name_text = "%s（戦闘不能）" % name_text
		var name_label := Label.new()
		name_label.text = name_text
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.tooltip_text = name_text
		name_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
		content.add_child(name_label)

		if entry["status"] == TURN_ORDER_STATUS_ACTED or entry["is_downed"]:
			row.modulate = Color(1.0, 1.0, 1.0, 0.5)
		list.add_child(row)

## §20: 現在行動中の行だけに使う、ごく細い銅アクセント枠——共有Panel
## StyleBoxを複製し、塗り色を透明にして枠線色だけアクセントへ差し替える
## （「巨大な発光は禁止」を踏まえ、光彩・グラデーションは一切使わない）。
static func _turn_order_current_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(RBMUiTheme.COLOR_ACCENT, 0.12)
	box.set_corner_radius_all(RBMUiTheme.CORNER_RADIUS)
	box.set_content_margin_all(4.0)
	box.border_width_left = RBMUiTheme.BORDER_WIDTH
	box.border_width_right = RBMUiTheme.BORDER_WIDTH
	box.border_width_top = RBMUiTheme.BORDER_WIDTH
	box.border_width_bottom = RBMUiTheme.BORDER_WIDTH
	box.border_color = RBMUiTheme.COLOR_ACCENT
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

## 通常（現在行動中でない）行の軽量StyleBox——現在行動中の行と全く同じ
## content_margin(4px)を使い、塗り/枠だけ透明にする（形は完全に統一、
## §10「全く別デザインにはしない」の精神をここでも踏襲）。
static func _turn_order_row_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.set_corner_radius_all(RBMUiTheme.CORNER_RADIUS)
	box.set_content_margin_all(4.0)
	box.border_width_left = RBMUiTheme.BORDER_WIDTH
	box.border_width_right = RBMUiTheme.BORDER_WIDTH
	box.border_width_top = RBMUiTheme.BORDER_WIDTH
	box.border_width_bottom = RBMUiTheme.BORDER_WIDTH
	box.border_color = Color(0, 0, 0, 0)
	box.shadow_size = 0
	box.anti_aliasing = false
	return box

## Fixed four skills share the full right column with turn order.
## Keep the helper name for callers, but no scroll viewport clips the fourth skill.
static func wrap_skill_list_scroll(command_area: Control, skill_list_panel: Control) -> void:
	command_area.add_child(skill_list_panel)
	skill_list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

static func build_battle_message(parent: Control) -> Label:
	var panel := PanelContainer.new()
	panel.name = "LatestInfoPanel"
	panel.custom_minimum_size.y = 112
	panel.add_theme_stylebox_override("panel", _turn_order_row_box())
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.name = "LatestInfoScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var label := Label.new()
	label.name = "LogLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(label)
	return label

## Bound the log body, leaving its close header permanently outside scrolling.
static func fit_log_window(window: Dictionary, scroll: ScrollContainer) -> void:
	var panel: Control = window["panel"]
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 140
	panel.offset_right = -140
	panel.offset_top = 70
	panel.offset_bottom = -70
	(window["close_button"] as Button).text = "閉じる ×"
	(window["close_button"] as Button).custom_minimum_size = Vector2(112, 44)
	(window["content"] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

## §4/§5/§6: 詳細ウィンドウ（味方/ボス共通の枠組み）を1つ生成する。
## overlay: 全画面を覆う半透明の背景（mouse_filter=STOP、背後の通常攻撃/
## スキル/防御/対象選択等の戦闘操作を一切通さない——戦闘そのものを停止する
## 新しいゲーム仕様は追加せず、UI入力層だけで誤操作を防ぐという§6の要求を
## そのまま満たす）。パネル自身もmouse_filter=STOPのため、パネル内クリックは
## そこで吸収されoverlay自身のgui_inputへは伝播しない——結果、パネル外
## クリックの時だけoverlayのgui_inputが発火し自動的に閉じる（§6「パネル外
## クリック→閉じる」）。「×」ボタンでも同様に閉じる（§6）。
## 戻り値: {overlay, panel, title_label, close_button, content}
static func build_detail_overlay(parent: Control, window_name: String) -> Dictionary:
	var overlay := Control.new()
	overlay.name = "%sOverlay" % window_name
	overlay.z_index = 100
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	parent.add_child(overlay)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.5)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.name = "%sPanel" % window_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_CENTER)
	# §33/§26バグ修正: Control.grow_horizontal/verticalの既定値は
	# GROW_DIRECTION_END——PRESET_CENTERはanchorを画面中央(0.5,0.5)へ
	# 置くだけで、既定のGROWのままだと中身の実サイズ分だけ右下方向へだけ
	# 伸びてしまい、パネルの左上角が画面中央に来る（＝右下寄りに見える）
	# 結果になっていた（headlessプローブで実測: position(640,360)、真の
	# 中央配置ではなかった）。BOTHへ明示することで、中身のサイズに関わらず
	# 画面中央を軸に対称に広がる——味方/ボス詳細・戦闘ログ、3画面全てが
	# この1関数を共有するため、ここ1箇所の修正で全て直る。
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(360, 0)
	overlay.add_child(panel)

	var body := VBoxContainer.new()
	body.name = "%sBody" % window_name
	panel.add_child(body)

	var header := HBoxContainer.new()
	header.name = "%sHeader" % window_name
	body.add_child(header)
	var title_label := Label.new()
	title_label.name = "%sTitleLabel" % window_name
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	header.add_child(title_label)
	var close_button := Button.new()
	close_button.name = "%sCloseButton" % window_name
	close_button.text = "×"
	close_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	close_button.pressed.connect(func(): overlay.visible = false)
	header.add_child(close_button)

	var content := VBoxContainer.new()
	content.name = "%sContent" % window_name
	body.add_child(content)

	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			overlay.visible = false
	)

	return {"overlay": overlay, "panel": panel, "title_label": title_label, "close_button": close_button, "content": content}

## §4: 味方詳細ウィンドウの中身を、既存のcontent(VBoxContainer、
## build_detail_overlay()が返したもの)へ作り直す。
static func refresh_ally_detail_content(content: Control, unit: RBMUnit, battle: RBMBattle) -> void:
	clear_children_safely(content)
	_add_detail_line(content, "HP　%d / %d" % [unit.hp, unit.max_hp])
	if unit.has_sp_resource():
		_add_detail_line(content, "SP　%d / %d" % [unit.sp, unit.max_sp])
	_add_detail_line(content, "ATK　%d" % unit.atk)
	_add_detail_line(content, "SPD　%d" % unit.spd)
	_add_state_section_header(content)
	var states := unit_state_lines(unit, battle)
	if states.is_empty():
		_add_detail_line(content, "現在の状態：なし")
	else:
		for line in states:
			_add_detail_line(content, line)

## §5: ボス詳細ウィンドウの中身。visibility(Dictionary、キーは
## RBMCreatorDraft.challenge_info_visibilityと同じ"hp"/"atk"/"spd"/
## "weak_attributes"/"resist_attributes"/"boss_skills")に応じて非公開項目を
## 「？？？」で伏せる——CHALLENGE以外（TEST/Clear Check）は常に全項目trueの
## Dictionaryを渡すことで、作者確認用途の「常に実値」という既存仕様を保つ
## （RBMCreatorDraft.challenge_info_visibilityの既定値と同じ全trueを、
## 呼び出し側のデフォルト引数として明示する）。
const ALL_VISIBLE := {
	"hp": true, "atk": true, "spd": true,
	"weak_attributes": true, "resist_attributes": true, "boss_skills": true,
}

static func refresh_boss_detail_content(content: Control, battle: RBMBattle, visibility: Dictionary = ALL_VISIBLE) -> void:
	clear_children_safely(content)
	var boss := battle.boss
	_add_detail_line(content, "HP　%s" % (("%d / %d" % [boss.hp, boss.max_hp]) if bool(visibility.get("hp", true)) else "？？？"))
	_add_detail_line(content, "ATK　%s" % (str(boss.atk) if bool(visibility.get("atk", true)) else "？？？"))
	_add_detail_line(content, "SPD　%s" % (str(boss.spd) if bool(visibility.get("spd", true)) else "？？？"))
	_add_detail_line(content, "弱点　%s" % (_attribute_list_text(boss.weak_attributes) if bool(visibility.get("weak_attributes", true)) else "？？？"))
	_add_detail_line(content, "耐性　%s" % (_attribute_list_text(boss.resist_attributes) if bool(visibility.get("resist_attributes", true)) else "？？？"))
	_add_state_section_header(content)
	var states := boss_state_lines(battle)
	if states.is_empty():
		_add_detail_line(content, "現在の状態：なし")
	else:
		for line in states:
			_add_detail_line(content, line)

## Phase 3.5 UI統一§26: ASCII罫線「──」による自作の区切りではなく、実際の
## HSeparator Node（RBMUiThemeで統一済みの細い枠線色）＋見出しLabelで区切る
## ——「装飾過多は禁止」を踏まえ、罫線1本＋文字のみに留める。
static func _add_state_section_header(content: Control) -> void:
	var separator := HSeparator.new()
	content.add_child(separator)
	var state_title := Label.new()
	state_title.text = "現在の状態"
	state_title.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	content.add_child(state_title)

static func _attribute_list_text(attributes: Array) -> String:
	if attributes.is_empty():
		return "なし"
	var names: Array[String] = []
	for attribute in attributes:
		names.append(str(ATTRIBUTE_DISPLAY_NAMES.get(RBMConstants.attribute_name(attribute), "？")))
	return "、".join(names)

static func _add_detail_line(content: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	content.add_child(label)
