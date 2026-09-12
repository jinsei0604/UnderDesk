class_name RBMCreatorDraft
extends RefCounted

## Phase 1 Step 4 — SIMPLE Creator's "編集中データ" (in-progress boss/party
## configuration, kept across STEP 1-7 navigation and TEST BATTLE round trips
## per §10). Pure data + logic, no UI dependency — the step-view Controls
## (rbm_creator_step*.gd) read/write this object and never hold their own
## copy of the truth.
##
## §11: this class is the FIRST of the two required validation layers
## ("Creator側でも入力制限する + Definition Loaderでも最終検証"). to_definition()
## always produces exactly the schema RBMDefinitionLoader.resolve() expects
## (see src/bossmaker/README.md) — nothing here bypasses that second, final
## check; TEST BATTLE always calls RBMDefinitionLoader.start_battle() on the
## generated Definition (§12), never a private shortcut.
##
## §2-4/§5-1 etc.: numeric ranges and the known character/attribute/timing
## lists are never redefined here — they are read directly off
## RBMDefinitionLoader's own constants, so this file cannot silently drift
## out of sync with what Definition validation actually accepts.

const MAX_BOSS_NAME_LENGTH := 20
## Creator UI再設計 §1で64へ引き上げ済み（旧8）。新モデルでは通常行動/
## 指定行動/ADVANCED固定行動/ADVANCEDランダム候補のそれぞれが「使う場所で
## 新規作成」するため、1体のボスが必要とするスキル総数が旧モデル（共有・
## 再利用前提）より大きくなりやすい。RBMBattle/RBMDefinitionLoaderには
## スキル数の上限自体が存在しない（調査済み）ため、この64はゲームバランス上の
## 制約ではなく、異常なデータ増加を防ぐための内部安全上限として扱う
## （ユーザー向けには「64個まで」等の数値そのものは通常表示しない）。
const MAX_SKILLS := 64

## Phase 1 Step 7 §11/§13: 作者備考の最大文字数。将来変更可能な独立定数として
## 定義（指示書§11の明示要求）。
const MAX_AUTHOR_NOTES_LENGTH := 200

## CHALLENGE UI再設計 §10: 作者アカウントシステムは今回作らない——「ボスごとに
## 公開時に入力する」名前。表示用の短い名前という性質はboss_nameと同じため、
## 独自のポリシー（NGワード等、§10/§24で明示的にClaude Code側の独自判断を
## 禁止された範囲）を発明せず、その技術上の安全上限だけをMAX_BOSS_NAME_LENGTH
## と同じ値へ揃える。
const MAX_AUTHOR_NAME_LENGTH := 20

## Phase 1 Step 7 §14（公開設定の最終修正で7→6項目へ確定）: CHALLENGE
## 確認画面で個別に公開/非公開を切り替えられる情報カテゴリ一覧。「攻略側
## パーティ詳細」は当初この一覧に含めていたが、挑戦者自身が実際に使用する
## パーティ・使用可能スキルと完全に同一のデータであり§16により常時表示が
## 必須（非公開にしても表示へ反映できず「非公開にしたのに表示されている」
## 矛盾を生む）ため、キー自体を廃止した——攻略側パーティ・使用可能スキルは
## 公開設定を一切持たない。
##
## 実機プレイ改善③ item1: "win_condition"/"special_condition"を6→8項目へ
## 追加した。既存の`is_challenge_info_visible()`/`set_all_challenge_info_visible()`
## /`_restore_challenge_info_visibility()`（下記）がいずれもこの配列を汎用的に
## 走査するだけの実装のため、この2件を追加するだけでhide all/show all一括
## 操作・保存/読込（旧セーブは既存の「未知キーはtrueへデフォルト」仕組みで
## 安全に補完される）に自動的に組み込まれる——コード変更は配列へ2件足す
## ことだけで済んだ。
const CHALLENGE_INFO_VISIBILITY_KEYS: Array[String] = [
	"hp", "atk", "spd", "weak_attributes", "resist_attributes", "boss_skills",
	"win_condition", "special_condition",
]

# STEP 1
var boss_name: String = ""
var appearance_id: String = ""
var battle_background: String = "night"

# STEP 2
var hp: int = 1
var atk: int = 1
var spd: int = 1
var weak_attributes: Array[String] = []
var resist_attributes: Array[String] = []

# STEP 3 — ordered list of author-created boss skills. Each entry:
# {skill_id, name, type: "attack"|"self_heal"|"atk_self_buff",
#  # attack: target("single"|"all"), attribute, atk_multiplier
#  # self_heal: heal_mode("fixed"|"percent"), heal_fixed_amount, heal_percent
#  # atk_self_buff: buff_multiplier, duration_turns}
var skills: Array[Dictionary] = []
var _next_skill_ordinal: int = 1

# STEP 4
var normal_actions_enabled: bool = false
var normal_action_percentages: Dictionary = {}  # skill_id(String) -> float (0.0-100.0)
# Kept contiguous per (turn,timing) group by add_scripted_action(); array
# position within a group IS the display/authoring order (converted to an
# explicit 1,2,3... "order" only at to_definition() time).
var scripted_actions: Array[Dictionary] = []  # {turn:int, skill_id:String, timing:String}

# ---------------------------------------------------------------------------
# Phase 2 → HARDCORE「攻撃」全面再設計（2026-09-05）
# ---------------------------------------------------------------------------
##
## 新仕様: プレイヤー向けの「行動パターン」概念（複数条件・複数行動ステップ・
## 発動確率・Cooldownを持つ"パターン"を優先度順に組み立てる方式）を廃止し、
## 「ボスが使用する攻撃を作り、行動する順番に並べる」方式（action_sequence、
## 行動順に並んだ「配置スロット」の単純な配列）へ全面移行した。旧HARDCORE
## データ（action_patterns形式）との互換性は無い（ユーザー確定仕様——自動
## 変換しない、旧評価器を残さない、二重スキーマを維持しない。下記
## ADVANCED_AI_VERSIONの引き上げにより、RBMLocalStageRepositoryが旧version
## の保存データを読み込み時に拒否する）。
##
## SIMPLEの既存2フィールド（normal_action_percentages/scripted_actions、
## 上のSTEP 4節）は今回のHARDCORE再設計と無関係——一切変更していない。
## SIMPLE→HARDCORE切替時にこの2フィールドから自動変換して初期投入する
## 仕組み自体は維持するが、変換先の形（action_sequenceのスロット）が
## 新schemaへ変わっただけで、変換元のSIMPLE側フィールド自体は従来どおり
## 一切変更せず保持し続ける（下のset_creator_mode()参照）。
##
## 戦闘エンジン側（RBMBattle/RBMDefinitionLoader）は`creator_mode`自体を
## 一切参照しない——「boss_def["action_sequence"]が空でなければHARDCORE AI
## 評価（1ターン1スロットのラウンドロビン）を使い、空ならSIMPLEの既存
## _pick_boss_normal_action()/scripted_actions(replace)経路を使う」という、
## action_sequence配列そのものの有無だけで分岐する設計を維持した——これに
## よりSIMPLE専用の既存テストは一切触れない。
## turn_start_interrupt/turn_end_interruptはモードに関係なく常に既存のまま
## 独立して動作する（無改修）。

const CREATOR_MODE_SIMPLE := "simple"
const CREATOR_MODE_ADVANCED := "advanced"

## HARDCORE AI専用の仕様バージョン。保存全体のSAVE_FORMAT_VERSIONとは独立。
## 2026-09-05の全面再設計（action_patterns→action_sequence）に伴い1→2へ
## 引き上げた——RBMLocalStageRepository._validate_draft_shape()の既存の
## 厳密一致チェックにより、旧version(1)のHARDCORE保存データは読込時に
## 丸ごと拒否される（ユーザー確定仕様「旧versionのHARDCORE保存データは
## 新仕様として読み込まなくて構いません」「自動変換しない」）。SIMPLE専用の
## 保存データ（この値自体を保存しないか、advanced_ai_versionフィールドを
## 持たない）には一切影響しない。
const ADVANCED_AI_VERSION := 2

var creator_mode: String = CREATOR_MODE_SIMPLE

## 「行動順に配置された攻撃スロット」の配列——配列位置そのものが実行順を表す
## （旧action_patternsの「優先順位」とは意味が異なる。RBMBattle側は毎ターン
## 現在位置カーソルからこの配列を走査し、最初に発動可能なスロットを1つだけ
## 実行する。詳細はrbm_battle.gdの「HARDCORE新方式」節を参照）。
## 各エントリの形（authoring形=resolved形、変換の要らない単純な形のため
## 両者を分けていない）:
## {
##   "slot_id": String,                # 配置固有ID。使用回数の状態管理キー
##                                      # （skill_idではない——同じ攻撃性能を
##                                      # 複数配置してもそれぞれ独立して数える）
##   "kind": "skill" | "random",
##   "skill_id": String,                # kind=="skill"の時のみ意味を持つ
##   "mode": "even" | "manual",         # kind=="random"の時のみ意味を持つ
##   "candidates": Array[{"skill_id":String,"weight":float}],  # kind=="random"のみ
##   "conditions": Array[Dictionary],   # 各 {"type":String, ...type別フィールド}
##   "condition_logic": "AND" | "OR",   # conditions.size()>1の時のみ意味を持つ
##   "max_uses": int,                   # RBMActionPatternRules.UNLIMITED_USES(-1)=制限なし
## }
## 旧仕様にあった「1配置内の複数行動ステップの連続実行」「発動確率」
## 「Cooldown」「瞬間条件・瞬間発動後」は新仕様に一切存在しない（前者2つは
## §9/§18で明示的に廃止、瞬間条件はRBMActionPatternRules冒頭コメント参照）。
var action_sequence: Array[Dictionary] = []
var _next_slot_ordinal: int = 1

## 覚醒（Awakening）——通常のaction_sequenceとは完全に独立した、ボス1体に
## つき最大1つの特別イベント。通常行動ループ（1ターン1スロット）には一切
## 含まれず、通常行動回数も消費しない。空Dictionary({})が「未設定」を表す
## 唯一の状態——一度設定すると常に"conditions"/"condition_logic"キーを持つ
## ため、これ以降is_empty()だけで有無を判定できる。
## 著作形（保存・編集時にそのまま保持する形）:
##   {"conditions": Array（action_sequenceスロットの条件と全く同じ著作形）,
##    "condition_logic": "AND"|"OR",
##    "buff": {"buff_multiplier":float,"duration_turns":int} または {}（未追加）,
##    "heal": {"heal_mode":"fixed"|"percent","heal_fixed_amount":int,"heal_percent":float} または {}（未追加）}
## buff/healは既存のATK自己強化・自己回復と全く同じ入力形——専用の別計算は
## 持たない（resolved_heal_amount()/buffed_atk_preview()をそのまま再利用する）。
var awakening: Dictionary = {}

func has_awakening() -> bool:
	return not awakening.is_empty()

## 新規設定・編集どちらもこの1関数で置き換える（覚醒はid不要の単一設定の
## ため、add/updateを分ける必要が無い）。`data`は"conditions"/"condition_logic"
## を含む必要がある（"buff"/"heal"は省略時 {} 扱い）。
func set_awakening(data: Dictionary) -> void:
	awakening = {
		"conditions": (data.get("conditions", []) as Array).duplicate(true),
		"condition_logic": str(data.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)),
		"buff": (data.get("buff", {}) as Dictionary).duplicate(true),
		"heal": (data.get("heal", {}) as Dictionary).duplicate(true),
	}

func remove_awakening() -> void:
	awakening = {}

## to_definition()/battle_content_snapshot()共通の解決処理——著作形の
## heal_mode等をresolved_heal_amount()で最終heal_amountへ焼き込む
## （self_healスキルの_skills_for_definition()と全く同じ規則）。未設定なら
## 空Dictionaryを返す（呼び出し側はis_empty()でキー自体を省略する）。
func _resolved_awakening_for_definition() -> Dictionary:
	if awakening.is_empty():
		return {}
	var resolved := {
		"conditions": _normalized_conditions(awakening.get("conditions", [])),
		"condition_logic": str(awakening.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)),
	}
	var buff: Dictionary = awakening.get("buff", {})
	if not buff.is_empty():
		resolved["buff"] = {
			"buff_multiplier": float(buff.get("buff_multiplier", 1.0)),
			"duration_turns": int(buff.get("duration_turns", 1)),
		}
	var heal: Dictionary = awakening.get("heal", {})
	if not heal.is_empty():
		resolved["heal_amount"] = resolved_heal_amount(heal)
	return resolved

func can_add_action_slot() -> bool:
	return action_sequence.size() < RBMActionPatternRules.MAX_ACTION_SEQUENCE_SLOTS

## `slot`は"slot_id"以外の全フィールドを含む必要がある（クラス冒頭の形
## コメント参照）。生成したslot_idを返す（上限到達時は""）。
func add_action_slot(slot: Dictionary) -> String:
	if not can_add_action_slot():
		return ""
	var id := "action_slot_%d" % _next_slot_ordinal
	_next_slot_ordinal += 1
	var entry := slot.duplicate(true)
	entry["slot_id"] = id
	action_sequence.append(entry)
	return id

func update_action_slot(slot_id: String, new_data: Dictionary) -> void:
	for i in range(action_sequence.size()):
		if str(action_sequence[i].get("slot_id", "")) == slot_id:
			var entry := new_data.duplicate(true)
			entry["slot_id"] = slot_id
			action_sequence[i] = entry
			return

func remove_action_slot(slot_id: String) -> void:
	for i in range(action_sequence.size()):
		if str(action_sequence[i].get("slot_id", "")) == slot_id:
			action_sequence.remove_at(i)
			return

func find_action_slot(slot_id: String) -> Dictionary:
	for slot in action_sequence:
		if str(slot.get("slot_id", "")) == slot_id:
			return slot
	return {}

## §20「作者はドラッグ等によって並び順を変更できる」——直接の配列位置スワップ
## （direction: -1で上、+1で下）。攻撃性能・発動条件・使用回数はスロット
## 1つのDictionaryとしてまとめて移動するため、組み合わせが崩れることはない。
func move_action_slot(slot_id: String, direction: int) -> bool:
	var index := -1
	for i in range(action_sequence.size()):
		if str(action_sequence[i].get("slot_id", "")) == slot_id:
			index = i
			break
	var target := index + direction
	if index < 0 or target < 0 or target >= action_sequence.size():
		return false
	var tmp: Dictionary = action_sequence[index]
	action_sequence[index] = action_sequence[target]
	action_sequence[target] = tmp
	return true

## ランダム攻撃「自分で設定」の場合、候補確率の合計が100%であることを
## 要求する（既存のnormal_action_percentages・SIMPLE側と同じ検証方針を、
## 各ランダムスロットへ個別に適用する）。
func action_step_manual_percentage_total(slot: Dictionary) -> float:
	var total := 0.0
	for candidate in slot.get("candidates", []):
		total += float(candidate.get("weight", 0.0))
	return total

## STEP 3 (HARDCORE)の入力検証。SIMPLE側のstep4_is_valid()とは独立
## （creator_modeがADVANCEDの時のみCreator UIが参照する）。
## - action_sequenceが0件でも有効（「このボスは行動しません」という、SIMPLE
##   でも許容されている状態と同じ扱い——旧「0パターンでも有効」を踏襲）
## - conditions.size()>1の時のみcondition_logicが既知の値であること
## - "自分で設定"の各ランダムスロットは確率合計100%であること
## - 参照するボススキルskill_idが現存すること（削除済みskill_id混入の防止、
##   通常はremove_skill()側のクリーンアップで発生し得ないはずだが、
##   Draft状態の内部整合性を保証する最終防衛線として持つ）
func step4_advanced_is_valid() -> bool:
	if creator_mode != CREATOR_MODE_ADVANCED:
		return true
	for slot in action_sequence:
		if int(slot.get("conditions", []).size()) > 1 and not RBMActionPatternRules.CONDITION_LOGIC_TYPES.has(str(slot.get("condition_logic", ""))):
			return false
		if str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_SKILL:
			if find_skill(str(slot.get("skill_id", ""))).is_empty():
				return false
		elif str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_RANDOM:
			var candidates: Array = slot.get("candidates", [])
			if candidates.is_empty():
				return false
			for candidate in candidates:
				if find_skill(str(candidate.get("skill_id", ""))).is_empty():
					return false
			if str(slot.get("mode", "")) == RBMActionPatternRules.RANDOM_MODE_MANUAL:
				if absf(action_step_manual_percentage_total(slot) - 100.0) >= 0.05:
					return false
		else:
			return false
	return true

## Clear Check/CHALLENGE確認画面に出す「このボスにはランダム行動が設定
## されています。挑戦ごとに行動が変化する場合があります。」の表示条件。
## HARDCORE側は「発動確率」が廃止されたため、候補が2つ以上あるランダム
## スロットの存在だけを見る（旧・確率100%未満のパターンという判定条件は
## 対応する概念が新schemaに存在しないため削除——確認で判明した仕様変更の
## 直接の帰結、意図的な削除であってバグではない）。SIMPLE側は無改修
## （normal_actions_enabled かつ 重み>0のスキルが2つ以上）。
func has_random_action_variance() -> bool:
	if creator_mode == CREATOR_MODE_ADVANCED:
		for slot in action_sequence:
			if str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_RANDOM:
				if (slot.get("candidates", []) as Array).size() > 1:
					return true
		return false
	if not normal_actions_enabled:
		return false
	var candidate_count := 0
	for skill in skills:
		if float(normal_action_percentages.get(str(skill.get("skill_id", "")), 0.0)) > 0.0:
			candidate_count += 1
			if candidate_count > 1:
				return true
	return false

# ---------------------------------------------------------------------------
# Phase 2 — SIMPLE ⇄ ADVANCED 切替 (確定A・§21・§22)
# ---------------------------------------------------------------------------

## 「HARDCORE専用の設定」＝SIMPLE側に対応する表現が一切存在しない構造。
## SIMPLE側で表現できる最大の形は「①無条件、または単一のturn_at条件
## （scripted_actionsのreplaceに相当）」×「②kind==skill、またはkind==random
## かつmode=="manual"」×「③使用回数は制限なし」の組み合わせのみ——それ以外
## （turn_at以外の条件・複数条件・使用回数に制限がある等）はすべてHARDCORE
## 専用として扱う。旧仕様にあった「発動確率/Cooldownが既定値か」「1配置内の
## 行動ステップ数が1か」という2つのチェックは、新schemaにその概念自体が
## 存在しない（前者は§9で廃止、後者は元々スロット1つ＝攻撃1つのため常に真）
## ため削除した。
func _is_slot_simple_representable(slot: Dictionary) -> bool:
	var conditions: Array = slot.get("conditions", [])
	if conditions.size() > 1:
		return false
	if conditions.size() == 1:
		if str(conditions[0].get("type", "")) != "turn_at":
			return false
	var kind := str(slot.get("kind", ""))
	if kind != RBMActionPatternRules.SLOT_KIND_SKILL and kind != RBMActionPatternRules.SLOT_KIND_RANDOM:
		return false
	if int(slot.get("max_uses", RBMActionPatternRules.UNLIMITED_USES)) != RBMActionPatternRules.UNLIMITED_USES:
		return false
	return true

func has_advanced_only_settings() -> bool:
	for slot in action_sequence:
		if not _is_slot_simple_representable(slot):
			return true
	return false

## SIMPLE→HARDCOREへの切替。action_sequenceが現在空の場合のみ、
## normal_action_percentages（重み>0のスキルをまとめて「条件なし＋ランダム
## 行動（自分で設定）」の1スロットへ）とscripted_actions中のreplaceタイミング
## 分を自動変換して初期投入する（具体的な変換内容は
## _prospective_simple_conversion_authoring_slots()参照）。
## 既にaction_sequenceへ何か存在する場合（2回目以降のHARDCORE切替、または
## 既にHARDCORE編集済み）は変換をスキップし、既存の内容をそのまま維持する
## （「切替直後の戦闘内容が変化しない」ことだけを要求しており、既存HARDCORE
## 編集内容を再変換で上書きしてはならない）。
func set_creator_mode(mode: String) -> void:
	if mode != CREATOR_MODE_SIMPLE and mode != CREATOR_MODE_ADVANCED:
		return
	if mode == CREATOR_MODE_ADVANCED and action_sequence.is_empty():
		_auto_populate_action_sequence_from_simple()
	elif mode == CREATOR_MODE_SIMPLE:
		# 旧実装はcreator_modeだけを書き換え、action_sequenceを残す場合が
		# あった——SIMPLEに戻ったつもりでもRBMDefinitionLoader/RBMBattleは
		# 「action_sequenceが空かどうか」だけを見て分岐する（creator_mode
		# 自体は戦闘エンジンから一切参照されない、このファイル冒頭コメント
		# 参照）ため、「SIMPLE画面なのに裏でHARDCORE AIが動く」という不変
		# 条件違反になっていた。SIMPLE状態ではHARDCORE専用設定
		# （action_sequence）が一切存在しないことを常に保証するため、
		# SIMPLEへの遷移では無条件にaction_sequenceを空にする——呼び出し元
		# （Creator UI）は、この破棄が安全（現在のaction_sequenceがSIMPLE側
		# フィールドと完全に等価）かどうかを、遷移前に必ず
		# can_switch_to_simple_without_confirmation()で確認し、等価でなければ
		# 先に確認ダイアログを経由させる責務を持つ（下記参照）——ここではもう
		# 安全性を判断せず、常に破棄する。
		action_sequence.clear()
	creator_mode = mode

## 変換順が重要: SIMPLEの既存挙動では、scripted_actionsの"replace"はその
## ターンにおいて常にnormal_action_percentagesの抽選より優先される（無条件で
## 差し替える、_resolve_boss_turn_actions()の既存実装）。HARDCORE側は
## 「上にあるスロットが先に発動可能かどうか判定される」ため、これを近似
## するにはturn_at条件つきのスロットを**先に**追加し、無条件（条件なし）の
## ランダム行動スロットを**最後**（フォールバック）に置く必要がある。
##
## 重要な既知の制約（実装時に確認済み、報告書に記載）: SIMPLEの"replace"は
## 同一ターンに複数スキルが設定されていれば全件をその同じターン内で実行する
## ——旧HARDCORE（行動パターン）はこれを「1パターン内の複数行動ステップの
## 連続実行」として忠実に再現できていたが、新HARDCORE仕様は「1ターン＝1
## スロット」が原則（§18で明示的に旧方式を廃止）のため、この変換は同一ターン
## の複数replaceスキルをそれぞれ**別々の**turn_at:Tスロットへ変換する。結果、
## 変換直後の1回目のトリガーではそのうちの1つ（走査順で最初に見つかった
## もの）だけが実際にそのターンに発動し、他は同じ`turn_at:T`条件を持ったまま
## 二度とそのターン番号に戻らないため、以後永久に発動しない——SIMPLE本来の
## 「同一ターンの全スキルが揃って発動する」挙動を新HARDCOREの実行モデルの下
## では完全には再現できない、という構造的な制約（新方式のラウンドロビン
## 単一実行原則そのものに起因し、この変換関数の実装上の不備ではない）。
## この関数自体は現状の仕様どおり変換を行う——「変換前後で内容が完全一致
## するかどうか」を見るcan_switch_to_simple_without_confirmation()の判定は、
## 変換関数の出力同士を比較するだけなのでこの制約の影響を受けず正しく動作
## する。
##
## この関数はプロスペクティブ（副作用なし、add_action_slotを呼ばず
## authoring形の配列を返すだけ）——_auto_populate_action_sequence_from_simple()
## （実際にDraftへ追加する）と、can_switch_to_simple_without_confirmation()/
## battle_content_snapshot()（「今のSIMPLE設定を変換したら何が得られるか」を
## 副作用なく問い合わせたいだけの用途）の両方から共有する単一の正。
func _prospective_simple_conversion_authoring_slots() -> Array:
	var out: Array = []
	var replace_skill_ids_by_turn := {}  # int(turn) -> Array[String]
	var turn_order: Array = []  # 初出順（決定論的な出力順のため）。
	for entry in scripted_actions:
		if str(entry.get("timing", "")) != "replace":
			continue
		var turn := int(entry.get("turn", 1))
		if not replace_skill_ids_by_turn.has(turn):
			replace_skill_ids_by_turn[turn] = []
			turn_order.append(turn)
		(replace_skill_ids_by_turn[turn] as Array).append(str(entry.get("skill_id", "")))
	for turn in turn_order:
		for skill_id in (replace_skill_ids_by_turn[turn] as Array):
			out.append({
				"kind": RBMActionPatternRules.SLOT_KIND_SKILL,
				"skill_id": skill_id,
				"conditions": [{"type": "turn_at", "turn": turn}],
				"condition_logic": RBMActionPatternRules.DEFAULT_CONDITION_LOGIC,
				"max_uses": RBMActionPatternRules.UNLIMITED_USES,
			})
	if normal_actions_enabled:
		var candidates: Array = []
		for skill in skills:
			var skill_id := str(skill.get("skill_id", ""))
			var weight := float(normal_action_percentages.get(skill_id, 0.0))
			if weight > 0.0:
				candidates.append({"skill_id": skill_id, "weight": weight})
		if not candidates.is_empty():
			out.append({
				"kind": RBMActionPatternRules.SLOT_KIND_RANDOM,
				"mode": RBMActionPatternRules.RANDOM_MODE_MANUAL,
				"candidates": candidates,
				"conditions": [],
				"condition_logic": RBMActionPatternRules.DEFAULT_CONDITION_LOGIC,
				"max_uses": RBMActionPatternRules.UNLIMITED_USES,
			})
	return out

func _auto_populate_action_sequence_from_simple() -> void:
	for slot in _prospective_simple_conversion_authoring_slots():
		add_action_slot(slot)

## slot_idは編集画面のCRUD用の内部識別子であり、使用回数の状態管理キー
## として戦闘セッション内でのみ意味を持つ（RBMBattle._slot_use_counts参照）
## ——保存データの一致判定（等価判定・Clear Check比較）ではいずれも
## slot_idを無視した内容だけを見る（旧pattern_idの扱いをそのまま踏襲）。
func _slots_without_slot_id(slots: Array) -> Array:
	var out: Array = []
	for slot_variant in slots:
		var slot: Dictionary = (slot_variant as Dictionary).duplicate(true)
		slot.erase("slot_id")
		out.append(slot)
	return out

## 現在のSIMPLE側フィールドから今この瞬間に自動変換したら得られるはずの
## 内容を、実際のaction_sequenceと同じ解決済み形（_resolved_action_slot_
## for_definition()、"mode"をweightへ解決済み）・slot_id除去済みで返す。
## can_switch_to_simple_without_confirmation()とbattle_content_snapshot()の
## 両方が、この単一の正を比較対象として共有する。
func _resolved_prospective_simple_conversion_slots() -> Array:
	var out: Array = []
	for slot in _prospective_simple_conversion_authoring_slots():
		out.append(_resolved_action_slot_for_definition(slot))
	return _slots_without_slot_id(out)

## 「詳細設定を削除してSIMPLEに変更」が選ばれた時だけ呼ぶ。action_sequence
## を丸ごと破棄する——SIMPLE側フィールド（normal_action_percentages/
## scripted_actions）はHARDCORE編集中も一切変更していないため（このファイル
## 内、HARDCORE専用の全メソッドがaction_sequenceだけを触りSIMPLE側
## フィールドへは書き込まないことを確認済み）、破棄するだけでSIMPLE側が
## 自動的に元の状態のまま有効に戻る。逆変換ロジックは不要。
func discard_advanced_settings_and_revert_to_simple() -> void:
	action_sequence.clear()
	creator_mode = CREATOR_MODE_SIMPLE

## 「現在のaction_sequence（slot_id除く）」が「今この瞬間にSIMPLE側
## フィールドから自動変換したら得られる内容（slot_id除く）」と完全に一致
## する場合のみ、無確認での切替を許可する——一致していれば、SIMPLE側
## フィールドは元々一切変更されていないため、単純にaction_sequenceを破棄
## するだけで安全に戻せる（逆変換の必要が無い）。一致しない場合（本当に
## HARDCORE専用の内容が存在する）は確認対象のまま。
func can_switch_to_simple_without_confirmation() -> bool:
	var current := _slots_without_slot_id(_action_sequence_for_definition())
	return current == _resolved_prospective_simple_conversion_slots()

# ---------------------------------------------------------------------------
# STEP 5
# ---------------------------------------------------------------------------

var party_character_ids: Array[String] = []

# STEP 6 — character_id(String) -> Array[String] of that character's own
# master skill_ids currently enabled for this fight. Populated with "all
# skills on" the moment a character is added to the party (§6-3 default).
var ally_allowed_skill_ids: Dictionary = {}

## Phase 3: sparse per-stage differences from the immutable ally masters.
## Kept while the character/skill is temporarily unavailable and while the
## Creator is in SIMPLE mode; only HARDCORE (internal mode "advanced") emits
## these values into a battle Definition.
## {character_id:{"stats":{field:value},"skills":{skill_id:{field:value}}}}
var ally_overrides: Dictionary = {}

## Phase 1 Step 7 §11〜§20 — CHALLENGE向けの著作メタ情報（作者備考・情報公開
## 設定）。どちらも「著作内容」の一部としてto_saved_dict()/full_authoring_snapshot()
## に含まれ未保存変更判定の対象になるが、battle_content_snapshot()（Step 5、
## Clear Check比較専用）には一切含めない（§20: 変更してもClear Check成功を
## 無効化しない）。
var author_notes: String = ""

## CHALLENGE UI再設計 §10: ボスごとに公開時入力する作者名。著作内容の一部
## として保存・復元されるが、Clear Check比較(battle_content_snapshot())には
## 一切影響しない——author_notesと同じ扱い。
var author_name: String = ""

var challenge_info_visibility: Dictionary = {
	"hp": true, "atk": true, "spd": true,
	"weak_attributes": true, "resist_attributes": true,
	"boss_skills": true, "win_condition": true, "special_condition": true,
}

## Phase 1 Step 5 §18/§20 — Clear Check's success record, held directly on
## the Draft (no separate Manager class). An empty Dictionary means "never
## cleared yet"; battle_content_snapshot() always returns a Dictionary with
## at least its 7 fixed top-level keys present, so this is never confused
## with a genuine (but somehow all-empty) snapshot. Never cleared/reset by
## anything except a NEW success (record_clear_check_success()) — a failed
## re-attempt, a mid-battle abort, or the content simply no longer matching
## must all leave this exactly as it was (§16/§17), including cases where
## the content later comes back to match it again.
var _clear_check_success_snapshot: Dictionary = {}

## Creator UI再設計 §24〜§27（公開機能の正式仕様、ユーザー確定）——
## 「保存」とは独立した、CHALLENGE側への露出そのものを制御する真にステート
## フルなフラグ（is_clear_check_currently_valid()等のような都度再導出の
## ライブ値ではない）。明示的なpublish()/unpublish()でしか立ち上がらず、
## Clear Check達成状態が失われた場合はsync_published_with_clear_check()を
## 都度呼ぶことで一方向に（trueからfalseへのみ）自動的に取り下がる——
## 「A→B→A」で条件が元に戻っても、公開自体は作者が再度押すまで自動復活
## しない（既存の「A→B→Aで自動復元」哲学から意図的に外れる、ユーザー確定
## 仕様の一部）。to_saved_dict()/full_authoring_snapshot()/
## restore_from_saved_dict()の対象——battle_content_snapshot()（Clear Check
## 比較専用）には含めない（公開状態の変更自体はClear Check成功可否に
## 影響しない）。
var _published: bool = false

## CHALLENGE UI再設計 §4-D（新着カテゴリ）: 公開日時。既存の
## created_unix_time/updated_unix_time（Repository側、著作内容ではない）を
## 公開日時として流用しない、というユーザー指示のとおり、これは_published
## 自身と対になる新規フィールド。
##
## CHALLENGE discovery 最終調整 §2（仕様変更）: 「初回公開日時」として固定する
## ——publish()は_published_at_unix_timeが未設定（0、＝一度も公開されたことが
## ない）の時だけ「今」を書き込み、既に値がある場合は一切上書きしない。
## 取り下げ→再公開しても同じ値を保持し続けるため、新着カテゴリの並び順は
## 再公開のたびに変動しない（旧仕様は再公開のたびに更新していたが、
## 「取り下げ→再公開で新着上位へ戻る」という抜け道を防ぐため撤回した）。
var _published_at_unix_time: int = 0

func is_published() -> bool:
	return _published

func published_at_unix_time() -> int:
	return _published_at_unix_time

## Clear Check達成済みの場合のみ公開できる（ユーザー確定仕様）。
func publish() -> bool:
	if not is_clear_check_currently_valid():
		return false
	_published = true
	# §2: 初回公開時（_published_at_unix_timeがまだ0）のみ日時を設定する。
	# 取り下げ→再公開の2回目以降のpublish()呼び出しでは意図的に上書きしない。
	if _published_at_unix_time == 0:
		_published_at_unix_time = int(Time.get_unix_time_from_system())
	return true

## 公開取り下げ——Clear Check達成状態自体（_clear_check_success_snapshot）
## には一切触れない（ユーザー確定仕様: 「Clear Check達成状態自体は、公開を
## 取り下げただけでは失わせない」）。_published_at_unix_time自体もここでは
## クリアしない——§2の「初回公開日時」仕様どおり、取り下げでは消えず、
## 再公開時にも上書きされず同じ値のまま保持され続ける。
func unpublish() -> void:
	_published = false

## 公開後にClear Checkを無効化する変更が行われた場合、publishedも自動的に
## falseへ戻す（ユーザー確定仕様）。RBMCreatorMain._refresh()から都度呼ぶ
## ことで、UI操作のたびにこの一方向の是正が働く——is_clear_check_currently_
## valid()自体は既存のライブ再導出のまま無改修、この関数はpublishedという
## 別のステートフルな値をそれに追従させるためだけに存在する。
func sync_published_with_clear_check() -> void:
	if _published and not is_clear_check_currently_valid():
		_published = false

# ---------------------------------------------------------------------------
# オンライン公開状態の永続化（公開UI整理、2026-09-10、ユーザー確定仕様）
# ---------------------------------------------------------------------------
## RBMBossPublisher/RBMBossApiAdapter経由のオンライン公開状態を、この
## ローカルstageのメタデータとして保存/復元できるようにする——Creatorを
## 閉じて再度開いた時に「公開を取り下げる」/「オンライン公開」のどちらを
## 出すべきか判定できなかった問題（セッション内変数だけで持っていたため）
## への対応。
##
## 完全に「オンライン管理用メタデータ」として扱う——上記の_published（ローカル
## 公開、CHALLENGE一覧の可視化に使う既存フィールド、無改修）とは別物であり、
## どちらもbattle_content_snapshot()（Clear Check比較専用）には一切含めない
## （§17参照）。Supabase/Steamの既存publish/unpublish仕様自体も変更しない
## ——ここはその結果をローカルへ書き残すだけ。
var _online_boss_id: String = ""
var _online_published: bool = false

func online_boss_id() -> String:
	return _online_boss_id

func is_online_published() -> bool:
	return _online_published

## publish成功時にUI層（RBMCreatorStep7Summary）から呼ぶ。boss_idは
## RBMBossPublisher.last_boss_id()——再publish時にこの同じidを渡せば
## サーバ側は新規重複投稿ではなく既存レコードを更新する。
func set_online_boss_id(boss_id: String) -> void:
	_online_boss_id = boss_id

## publish/unpublish成功時にUI層から呼ぶ。unpublish成功時はboss_idには
## 触れず、この値だけをfalseへ更新する（ユーザー確定仕様「同じonline_boss_id
## は保持してよい」）。
func set_online_published(published: bool) -> void:
	_online_published = published

# ---------------------------------------------------------------------------
# STEP 1
# ---------------------------------------------------------------------------

func step1_is_valid() -> bool:
	return boss_name.length() >= 1 and boss_name.length() <= MAX_BOSS_NAME_LENGTH

# ---------------------------------------------------------------------------
# STEP 2
# ---------------------------------------------------------------------------

func step2_is_valid() -> bool:
	return hp >= RBMDefinitionLoader.BOSS_HP_MIN and hp <= RBMDefinitionLoader.BOSS_HP_MAX \
		and atk >= RBMDefinitionLoader.BOSS_ATK_MIN and atk <= RBMDefinitionLoader.BOSS_ATK_MAX \
		and spd >= RBMDefinitionLoader.BOSS_SPD_MIN and spd <= RBMDefinitionLoader.BOSS_SPD_MAX

## §2-7: selecting an attribute on one side automatically removes it from the
## other side (never both an error and a no-op — the OTHER selection simply
## moves). Returns nothing; both arrays are mutated in place.
func toggle_weak_attribute(attribute: String) -> void:
	if weak_attributes.has(attribute):
		weak_attributes.erase(attribute)
		return
	resist_attributes.erase(attribute)
	weak_attributes.append(attribute)

func toggle_resist_attribute(attribute: String) -> void:
	if resist_attributes.has(attribute):
		resist_attributes.erase(attribute)
		return
	weak_attributes.erase(attribute)
	resist_attributes.append(attribute)

# ---------------------------------------------------------------------------
# STEP 3
# ---------------------------------------------------------------------------

func can_add_skill() -> bool:
	return skills.size() < MAX_SKILLS

## `skill` must already contain every author-facing field for its own `type`
## (see the class-level shape comment) EXCEPT skill_id, which is generated
## here. Returns the generated skill_id, or "" if the 8-skill cap is reached.
##
## Creator UI再設計: 以前はここで無条件にnormal_action_percentages[id]=0.0を
## 先付けしていた（旧モデルでは全スキルが暗黙に通常行動候補だったため）。
## 新モデル（§26「使う場所で作る」）では、通常行動として作られたスキルだけが
## このdictへエントリを持つ——それ以外（指定行動/ADVANCED経由で作られた
## スキル）はエントリを持たない、という区別自体を「通常行動画面に何を
## 表示するか」の判定に使う（RBMCreatorStep3Actions._rebuild_normal_list()
## 参照）。この変更は既存の読み取り側すべてが`.get(skill_id, 0.0)`という
## デフォルト付きアクセスのため安全——エントリが無い＝0.0という扱いは
## normal_action_percentage_total()/_normal_actions_for_definition()/保存・
## 復元のいずれでも変わらない（値が変わるわけではなく、辞書に載るか
## 載らないかだけの違い）。通常行動として使う場合は、呼び出し元
## （RBMCreatorStep3Actions）がadd_skill()成功直後に明示的に
## normal_action_percentages[新id] = 0.0を書き込む。
func add_skill(skill: Dictionary) -> String:
	if not can_add_skill():
		return ""
	var id := "boss_skill_%d" % _next_skill_ordinal
	_next_skill_ordinal += 1
	var entry := skill.duplicate(true)
	entry["skill_id"] = id
	skills.append(entry)
	return id

func update_skill(skill_id: String, new_data: Dictionary) -> void:
	for i in range(skills.size()):
		if str(skills[i].get("skill_id", "")) == skill_id:
			var entry := new_data.duplicate(true)
			entry["skill_id"] = skill_id
			skills[i] = entry
			return

func remove_skill(skill_id: String) -> void:
	for i in range(skills.size()):
		if str(skills[i].get("skill_id", "")) == skill_id:
			skills.remove_at(i)
			break
	normal_action_percentages.erase(skill_id)
	var kept: Array[Dictionary] = []
	for entry in scripted_actions:
		if str(entry.get("skill_id", "")) != skill_id:
			kept.append(entry)
	scripted_actions = kept
	_remove_boss_skill_from_action_sequence(skill_id)

## ボススキル削除時、action_sequence内の参照も追随して整理する（既存
## remove_skill()のscripted_actionsクリーンアップと同じ精神）。新schemaでは
## スロットが入れ子のactions配列を持たないため、旧実装の「ステップだけを
## 取り除きactionsが空になったらパターンごと削除」というロジックは「スロット
## そのものを取り除く」という単純な形へ縮小した:
## - kind=="skill"のスロットがそのskillを直接使うなら、そのスロットごと
##   配列から取り除く（§19: 「作成済み攻撃の再利用」設計により、他の配置
##   （別のスロット）が同じskill_idを引き続き参照していても、この関数は
##   常に「今remove_skill()が呼ばれたその特定のskill_id」だけを対象にする
##   ——is_boss_skill_referenced()/remove_skill_if_unreferenced()が呼び出し元
##   側で「本当に他から参照されなくなったか」を判定してから初めてこの
##   remove_skill()自体が呼ばれる設計のため、ここでは無条件に取り除いて
##   よい）。
## - kind=="random"のスロットのcandidatesにそのskill_idがあれば候補から除く
##   （候補が0件になればそのスロットごと取り除く）。
## - last_boss_skill条件がそのskill_idを参照していれば条件ごと取り除く
##   （conditionsが結果的に空になっても、そのスロット自体は無条件スロット
##   として引き続き有効——削除しない）。
func _remove_boss_skill_from_action_sequence(skill_id: String) -> void:
	var kept_slots: Array[Dictionary] = []
	for slot_variant in action_sequence:
		var slot: Dictionary = slot_variant
		if str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_SKILL:
			if str(slot.get("skill_id", "")) == skill_id:
				continue  # この配置そのものが消えたskillを指していた——スロットごと削除。
		elif str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_RANDOM:
			var kept_candidates: Array = []
			for candidate in slot.get("candidates", []):
				if str(candidate.get("skill_id", "")) != skill_id:
					kept_candidates.append(candidate)
			if kept_candidates.is_empty():
				continue  # 候補が1つも残らなくなったランダム攻撃は無意味なため削除。
			slot = slot.duplicate(true)
			slot["candidates"] = kept_candidates
		var kept_conditions: Array = []
		for condition in slot.get("conditions", []):
			if str(condition.get("type", "")) == "last_boss_skill" and str(condition.get("skill_id", "")) == skill_id:
				continue
			kept_conditions.append(condition)
		if kept_conditions.size() != (slot.get("conditions", []) as Array).size():
			slot = slot.duplicate(true)
			slot["conditions"] = kept_conditions
		kept_slots.append(slot)
	action_sequence = kept_slots

func find_skill(skill_id: String) -> Dictionary:
	for skill in skills:
		if str(skill.get("skill_id", "")) == skill_id:
			return skill
	return {}

## 「あるskill_idがDraft内のどこかから参照されているか」を判定する唯一の正。
## 呼び出し元（SIMPLE通常行動/指定行動削除、HARDCORE攻撃の編集/削除の
## いずれも）はこの1関数だけを使う——各画面が個別に「action_sequenceだけ
## 見る」ような部分的判定をコピーして持たない。§19「作成済み攻撃の再利用」
## により、この判定は複数の配置スロットから同時に参照されているケースを
## 正しく扱う（1つの配置を消しても他の配置がまだ参照していれば
## trueのまま——skillの実体は削除されない）。確認する参照元は明示的に
## 列挙する（新しい参照箇所が将来追加されたら、ここへ1件足すだけで全呼び
## 出し元へ自動的に反映される）:
## - SIMPLE normal_action_percentages
## - SIMPLE scripted_actions
## - HARDCORE action_sequence の固定攻撃スロット（kind:"skill"）
## - HARDCORE action_sequence のランダム攻撃候補（kind:"random"のcandidates）
## - HARDCORE条件の last_boss_skill
## 呼び出し元は、削除しようとしている「その1箇所の参照」自体は判定前に
## 既に取り除いておくこと（でなければ自分自身の参照によって常にtrueへ
## なってしまう——remove_skill_if_unreferenced()自身のコメント参照）。
func is_boss_skill_referenced(skill_id: String) -> bool:
	if skill_id.is_empty():
		return false
	if normal_action_percentages.has(skill_id):
		return true
	for entry in scripted_actions:
		if str(entry.get("skill_id", "")) == skill_id:
			return true
	for slot in action_sequence:
		if str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_SKILL:
			if str(slot.get("skill_id", "")) == skill_id:
				return true
		elif str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_RANDOM:
			for candidate in slot.get("candidates", []):
				if str(candidate.get("skill_id", "")) == skill_id:
					return true
		for condition in slot.get("conditions", []):
			if str(condition.get("type", "")) == "last_boss_skill" and str(condition.get("skill_id", "")) == skill_id:
				return true
	return false

## 未参照（is_boss_skill_referenced()==false）なら削除する。参照が1つでも
## 残っていれば何もしない——呼び出し元は「このskill_idはもう使われていない
## かもしれない」というだけの情報を渡せばよく、安全性の判定自体は上の
## is_boss_skill_referenced()へ一本化されている。呼び出し元は、削除対象の
## 「その1箇所の参照」自体を先に取り除いてから呼ぶこと（例: normal_action_
## percentagesから該当エントリをeraseしてから呼ぶ、配置スロットを削除して
## から呼ぶ、編集後の新しい配置内容をdraftへ反映してから呼ぶ、等）——でなければ
## 自分自身の参照が残ったままのため常に「参照あり」と判定され、決して
## 削除されない。remove_skill()自体は他の全構造（normal_action_percentages/
## scripted_actions/action_sequence）へのクリーンアップも冪等に行うため、
## 既に取り除き済みの箇所へ重ねて呼んでも安全（既存のremove_skill()仕様どおり）。
func remove_skill_if_unreferenced(skill_id: String) -> void:
	if skill_id.is_empty():
		return
	if is_boss_skill_referenced(skill_id):
		return
	remove_skill(skill_id)

## STEP 3 §3-3: no party exists yet, so no attribute multiplier applies —
## boss ATK × skill multiplier only, via the real shared damage-formula core
## (RBMBattle.compute_damage_amount), never a hand-duplicated copy (§3-4).
func baseline_attack_damage(skill: Dictionary) -> int:
	return RBMBattle.compute_damage_amount(float(atk), float(skill.get("atk_multiplier", 1.0)), 1.0, 1.0, 1.0)

## §3-5 fixed-mode: "何%相当か" live readout.
func heal_percent_of_current_max_hp(skill: Dictionary) -> float:
	if hp <= 0:
		return 0.0
	return float(skill.get("heal_fixed_amount", 0)) / float(hp) * 100.0

## §3-5 percent-mode: "何HP回復するか" live readout, and the actual value
## written into the generated Definition's heal_amount for either mode.
func resolved_heal_amount(skill: Dictionary) -> int:
	if str(skill.get("heal_mode", "fixed")) == "percent":
		return int(round(float(hp) * float(skill.get("heal_percent", 0.0)) / 100.0))
	return int(skill.get("heal_fixed_amount", 0))

## §3-6: ボスATK × 強化倍率.
func buffed_atk_preview(skill: Dictionary) -> int:
	return int(round(float(atk) * float(skill.get("buff_multiplier", 1.0))))

func atk_self_buff_skills() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for skill in skills:
		if str(skill.get("type", "")) == "atk_self_buff":
			out.append(skill)
	return out

func attack_skills() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for skill in skills:
		if str(skill.get("type", "")) == "attack":
			out.append(skill)
	return out

# ---------------------------------------------------------------------------
# STEP 4
# ---------------------------------------------------------------------------

func normal_action_percentage_total() -> float:
	var total := 0.0
	for skill in skills:
		total += float(normal_action_percentages.get(str(skill.get("skill_id", "")), 0.0))
	return total

func step4_is_valid() -> bool:
	if not normal_actions_enabled:
		return true
	return absf(normal_action_percentage_total() - 100.0) < 0.05

## §4-3: distributes 100.0% evenly across every current skill with no
## floating-point drift — computed in integer units of 0.1% (1000 units =
## 100.0%) so the sum is always exactly 100.0 regardless of skill count.
##
## Creator UI再設計: この既存メソッドは「全draft.skillsが対象」という旧
## モデル契約のまま無改修で残してある（既存テストがこの契約のまま検証
## 済みのため）。新UIの通常行動画面はこれを直接呼ばない——代わりに下の
## equalize_normal_action_percentages_among_normal_actions()を使う（対象を
## normal_action_percentages.keys()＝実際に通常行動として作られたスキルだけに
## 絞るため、指定行動/ADVANCED経由のスキルを誤って通常行動候補へ巻き込まない）。
func equalize_normal_action_percentages() -> void:
	if skills.is_empty():
		return
	var count := skills.size()
	var total_units := 1000
	var base_units := total_units / count
	var remainder := total_units - base_units * count
	for i in range(count):
		var units := base_units
		if i < remainder:
			units += 1
		normal_action_percentages[str(skills[i].get("skill_id", ""))] = float(units) / 10.0

## Creator UI再設計 §6/§8: 新STEP3「行動」の通常行動画面が呼ぶ「均等にする」
## ——normal_action_percentages.keys()（＝通常行動として作られたスキルのみ）
## だけを対象に均等分配する。上のequalize_normal_action_percentages()と丸め
## 処理自体は同一（整数0.1%単位で必ず合計100.0%になる）だが、対象範囲だけが
## 異なる（意図的に別メソッドとして分離、既存メソッド・既存テストは無改修）。
func equalize_normal_action_percentages_among_normal_actions() -> void:
	var normal_skill_ids: Array = normal_action_percentages.keys()
	if normal_skill_ids.is_empty():
		return
	var count := normal_skill_ids.size()
	var total_units := 1000
	var base_units := total_units / count
	var remainder := total_units - base_units * count
	for i in range(count):
		var units := base_units
		if i < remainder:
			units += 1
		normal_action_percentages[str(normal_skill_ids[i])] = float(units) / 10.0

## §4-5: inserted at the end of its own (turn,timing) group so same-group
## entries always stay contiguous in the array — move_scripted_action() below
## relies on this invariant to only ever swap within a group.
func add_scripted_action(turn: int, skill_id: String, timing: String) -> void:
	var insert_at := scripted_actions.size()
	for i in range(scripted_actions.size() - 1, -1, -1):
		var entry: Dictionary = scripted_actions[i]
		if int(entry.get("turn", -1)) == turn and str(entry.get("timing", "")) == timing:
			insert_at = i + 1
			break
	scripted_actions.insert(insert_at, {"turn": turn, "skill_id": skill_id, "timing": timing})

func remove_scripted_action(index: int) -> void:
	if index < 0 or index >= scripted_actions.size():
		return
	scripted_actions.remove_at(index)

## §4-6: swaps `index` with its immediate neighbor in `direction` (-1 up, +1
## down) — but only if that neighbor shares the same (turn,timing) group.
## Returns false (a no-op) at a group boundary or array edge.
func move_scripted_action(index: int, direction: int) -> bool:
	var target := index + direction
	if index < 0 or index >= scripted_actions.size() or target < 0 or target >= scripted_actions.size():
		return false
	var a: Dictionary = scripted_actions[index]
	var b: Dictionary = scripted_actions[target]
	if int(a.get("turn", -1)) != int(b.get("turn", -2)) or str(a.get("timing", "")) != str(b.get("timing", "!")):
		return false
	var tmp: Dictionary = scripted_actions[index]
	scripted_actions[index] = scripted_actions[target]
	scripted_actions[target] = tmp
	return true

## Scripted actions sharing the same (turn,timing), in their current
## authoring order — for STEP 4's grouped display/reorder UI.
func scripted_actions_grouped() -> Dictionary:
	var groups := {}
	for i in range(scripted_actions.size()):
		var entry: Dictionary = scripted_actions[i]
		var key := "%d|%s" % [int(entry.get("turn", 0)), str(entry.get("timing", ""))]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(i)
	return groups

# ---------------------------------------------------------------------------
# STEP 5
# ---------------------------------------------------------------------------

func step5_is_valid() -> bool:
	return party_character_ids.size() >= RBMDefinitionLoader.MIN_PARTY_SIZE \
		and party_character_ids.size() <= RBMDefinitionLoader.MAX_PARTY_SIZE

func add_party_character(character_id: String) -> bool:
	if not RBMDefinitionLoader.KNOWN_ALLY_PATHS.has(character_id):
		return false
	if party_character_ids.has(character_id):
		return false
	if party_character_ids.size() >= RBMDefinitionLoader.MAX_PARTY_SIZE:
		return false
	party_character_ids.append(character_id)
	if not ally_allowed_skill_ids.has(character_id):
		ally_allowed_skill_ids[character_id] = all_master_skill_ids(character_id)
	return true

func remove_party_character(character_id: String) -> void:
	party_character_ids.erase(character_id)

func all_master_skill_ids(character_id: String) -> Array[String]:
	var out: Array[String] = []
	if not RBMDefinitionLoader.KNOWN_ALLY_PATHS.has(character_id):
		return out
	var def := RBMDataLoader.load_dict(str(RBMDefinitionLoader.KNOWN_ALLY_PATHS[character_id]))
	for skill in def.get("skills", []):
		out.append(str(skill.get("id", "")))
	return out

func master_character_def(character_id: String) -> Dictionary:
	if not RBMDefinitionLoader.KNOWN_ALLY_PATHS.has(character_id):
		return {}
	return RBMDataLoader.load_dict(str(RBMDefinitionLoader.KNOWN_ALLY_PATHS[character_id]))

func _master_ally_skill(character_id: String, skill_id: String) -> Dictionary:
	var master := master_character_def(character_id)
	for skill_variant in master.get("skills", []):
		if skill_variant is Dictionary and str((skill_variant as Dictionary).get("id", "")) == skill_id:
			return skill_variant
	return {}

func _prune_ally_override(character_id: String) -> void:
	if not ally_overrides.has(character_id):
		return
	var character: Dictionary = ally_overrides[character_id]
	if character.has("stats") and (character["stats"] as Dictionary).is_empty():
		character.erase("stats")
	if character.has("skills"):
		var skills: Dictionary = character["skills"]
		for skill_id in skills.keys():
			if (skills[skill_id] as Dictionary).is_empty():
				skills.erase(skill_id)
		if skills.is_empty():
			character.erase("skills")
	if character.is_empty():
		ally_overrides.erase(character_id)

func set_ally_stat_override(character_id: String, field: String, value: Variant) -> bool:
	var master := master_character_def(character_id)
	if master.is_empty() or not RBMDefinitionLoader.validate_ally_stat_override_value(field, value):
		return false
	var normalized := int(value)
	if normalized == int(master.get(field, 0)):
		if ally_overrides.has(character_id):
			var current: Dictionary = ally_overrides[character_id]
			if current.has("stats"):
				(current["stats"] as Dictionary).erase(field)
			_prune_ally_override(character_id)
		return true
	if not ally_overrides.has(character_id):
		ally_overrides[character_id] = {}
	var character: Dictionary = ally_overrides[character_id]
	if not character.has("stats"):
		character["stats"] = {}
	(character["stats"] as Dictionary)[field] = normalized
	return true

func set_ally_skill_override(character_id: String, skill_id: String, field: String, value: Variant) -> bool:
	var master_skill := _master_ally_skill(character_id, skill_id)
	if master_skill.is_empty() \
		or not RBMDefinitionLoader.ally_skill_override_fields(master_skill).has(field) \
		or not RBMDefinitionLoader.validate_ally_skill_override_value(field, value):
		return false
	var normalized: Variant = int(value) if ["heal_amount", "sp_amount", "sp_cost", "duration_turns"].has(field) else float(value)
	var master_value: Variant = int(master_skill.get(field, 0)) if normalized is int else float(master_skill.get(field, 0.0))
	if normalized == master_value:
		if ally_overrides.has(character_id):
			var current: Dictionary = ally_overrides[character_id]
			if current.has("skills") and (current["skills"] as Dictionary).has(skill_id):
				((current["skills"] as Dictionary)[skill_id] as Dictionary).erase(field)
			_prune_ally_override(character_id)
		return true
	if not ally_overrides.has(character_id):
		ally_overrides[character_id] = {}
	var character: Dictionary = ally_overrides[character_id]
	if not character.has("skills"):
		character["skills"] = {}
	var skills: Dictionary = character["skills"]
	if not skills.has(skill_id):
		skills[skill_id] = {}
	(skills[skill_id] as Dictionary)[field] = normalized
	return true

func reset_ally_character_stats(character_id: String) -> void:
	if ally_overrides.has(character_id):
		(ally_overrides[character_id] as Dictionary).erase("stats")
		_prune_ally_override(character_id)

func reset_ally_skill(character_id: String, skill_id: String) -> void:
	if ally_overrides.has(character_id):
		var character: Dictionary = ally_overrides[character_id]
		if character.has("skills"):
			(character["skills"] as Dictionary).erase(skill_id)
		_prune_ally_override(character_id)

func reset_all_ally_overrides() -> void:
	ally_overrides.clear()

## Creator UI再設計 §15 — パーティカードの「CUSTOM」表示専用の派生判定。
## 新しい概念/ステートを追加するものではなく、既存の2つの状態
## （ally_overrides——空エントリはset_ally_stat_override()等が_prune_ally_
## override()で常に取り除くため、キーの存在自体が「標準値と異なる」ことの
## 直接証拠になる／ally_allowed_skill_ids——マスター全スキルの集合と現在の
## 許可集合が一致しない）を都度比較するだけの読み取り専用ヘルパー。
func is_ally_customized(character_id: String) -> bool:
	if ally_overrides.has(character_id):
		return true
	if not ally_allowed_skill_ids.has(character_id):
		return false
	var allowed: Array = ally_allowed_skill_ids[character_id]
	var all_ids := all_master_skill_ids(character_id)
	if allowed.size() != all_ids.size():
		return true
	for skill_id in all_ids:
		if not allowed.has(skill_id):
			return true
	return false

## Returns the full master shape with sparse differences applied to a deep
## duplicate.  This accessor intentionally ignores creator_mode so HARDCORE UI
## can retain/show values while SIMPLE is active without leaking them to battle.
func hardcore_character_def(character_id: String) -> Dictionary:
	var resolved := master_character_def(character_id).duplicate(true)
	if resolved.is_empty() or not ally_overrides.has(character_id):
		return resolved
	var character: Dictionary = ally_overrides[character_id]
	var stats: Dictionary = character.get("stats", {})
	for field in stats.keys():
		resolved[str(field)] = int(stats[field])
	var skill_overrides: Dictionary = character.get("skills", {})
	for skill_variant in resolved.get("skills", []):
		if not (skill_variant is Dictionary):
			continue
		var skill: Dictionary = skill_variant
		var skill_id := str(skill.get("id", ""))
		if not skill_overrides.has(skill_id):
			continue
		var values: Dictionary = skill_overrides[skill_id]
		for field in values.keys():
			skill[str(field)] = values[field]
	return resolved

func effective_character_def(character_id: String) -> Dictionary:
	if creator_mode == CREATOR_MODE_ADVANCED:
		return hardcore_character_def(character_id)
	return master_character_def(character_id)

# ---------------------------------------------------------------------------
# STEP 6
# ---------------------------------------------------------------------------

func step6_is_valid() -> bool:
	return true  # §6-2: 0 skills per character is always valid.

func is_ally_skill_allowed(character_id: String, skill_id: String) -> bool:
	var allowed: Array = ally_allowed_skill_ids.get(character_id, [])
	return allowed.has(skill_id)

func set_ally_skill_allowed(character_id: String, skill_id: String, allowed: bool) -> void:
	if not ally_allowed_skill_ids.has(character_id):
		ally_allowed_skill_ids[character_id] = []
	var list: Array = ally_allowed_skill_ids[character_id]
	if allowed and not list.has(skill_id):
		list.append(skill_id)
	elif not allowed and list.has(skill_id):
		list.erase(skill_id)

func set_all_ally_skills_allowed(character_id: String, allowed: bool) -> void:
	ally_allowed_skill_ids[character_id] = all_master_skill_ids(character_id) if allowed else []

func set_all_party_skills_allowed(allowed: bool) -> void:
	for character_id in party_character_ids:
		set_all_ally_skills_allowed(character_id, allowed)

# ---------------------------------------------------------------------------
# Phase 1 Step 7 — 作者備考・情報公開設定 (§11〜§20)
# ---------------------------------------------------------------------------

## §11/§13: 200文字を超える入力は末尾で切り詰める（STEP 1のboss_name同様、
## API自体が上限を超える値を一切受け付けない設計——UI側のmax_length設定に
## 加えてのDraft側の保証）。
func set_author_notes(text: String) -> void:
	author_notes = text.left(MAX_AUTHOR_NOTES_LENGTH)

## CHALLENGE UI再設計 §10: boss_nameと同じ「末尾で切り詰めるだけ」の技術上の
## 安全上限のみ——空欄可否・NGワード等の独自ポリシーは実装しない（§10/§24）。
func set_author_name(text: String) -> void:
	author_name = text.left(MAX_AUTHOR_NAME_LENGTH)

func is_challenge_info_visible(key: String) -> bool:
	return bool(challenge_info_visibility.get(key, true))

## §14: 個別トグル。
func set_challenge_info_visible(key: String, visible: bool) -> void:
	if not CHALLENGE_INFO_VISIBILITY_KEYS.has(key):
		return
	challenge_info_visibility[key] = visible

## §15: 「すべて公開」「すべて非公開」の一括操作。
func set_all_challenge_info_visible(visible: bool) -> void:
	for key in CHALLENGE_INFO_VISIBILITY_KEYS:
		challenge_info_visibility[key] = visible

# ---------------------------------------------------------------------------
# STEP 7 — real per-character damage preview (§7-4/§7-5)
# ---------------------------------------------------------------------------

## character_id(String) -> predicted damage, using the real
## RBMConstants.attribute_multiplier_for_lists() against each currently-selected
## character's REAL weak/resist attribute list (loaded via the same
## RBMDataLoader.unit_from_ally_def() the real battle uses). `buff_multiplier`
## folds an ATK自己強化's multiplier into the effective ATK the same way the
## real battle's atk_buff timed effect does. Deliberately assumes an
## undefended target with no party-wide reduction active — there is no live
## battle-turn context to know otherwise before TEST BATTLE even starts
## (§7-6 only lists Definition-fixed factors, not situational battle state).
func party_damage_preview(skill: Dictionary, buff_multiplier: float = 1.0) -> Dictionary:
	var out := {}
	var attack_attribute := RBMConstants.attribute_from_name(str(skill.get("attribute", "NEUTRAL")))
	var effective_atk := float(atk) * buff_multiplier
	for character_id in party_character_ids:
		var master := master_character_def(character_id)
		if master.is_empty():
			continue
		var unit := RBMDataLoader.unit_from_ally_def(master, 0)
		# v0.1-C: uses the exact same list-based multiplier function real
		# battle damage now uses (RBMBattle._compute_and_apply_damage), not
		# just an equivalent single-value one, so this preview can never
		# silently drift from real battle behavior as multi-attribute support
		# evolves.
		var attribute_mult := RBMConstants.attribute_multiplier_for_lists(attack_attribute, unit.weak_attributes, unit.resist_attributes)
		out[character_id] = RBMBattle.compute_damage_amount(effective_atk, float(skill.get("atk_multiplier", 1.0)), attribute_mult, 1.0, 1.0)
	return out

# ---------------------------------------------------------------------------
# Definition generation (§11) — always the exact schema
# RBMDefinitionLoader.resolve() expects; see src/bossmaker/README.md.
# ---------------------------------------------------------------------------

func to_definition() -> Dictionary:
	var boss := {
		"boss_id": _generate_boss_id(),
		"boss_name": boss_name,
		"hp": hp,
		"atk": atk,
		"spd": spd,
		"skills": _skills_for_definition(),
		"normal_actions": _normal_actions_for_definition(),
		"scripted_actions": _scripted_actions_for_definition(),
		# action_sequenceが空ならこのキー自体を省略する（既存の「シリアライズ
		# されたDefinitionにキーが無ければ何も設定していない」という慣習
		# ——normal_actionsが空配列になり得るのとは異なり、こちらは「HARDCORE
		# 機構が一切存在しないSIMPLE専用Definition」を明確に表現するため、
		# あえて空配列すら書かない）。RBMDefinitionLoader/RBMBattleは
		# 「action_sequenceキーの有無」ではなく「解決後の配列が空かどうか」で
		# 分岐するため、実際の挙動には影響しないが、SIMPLE専用Definitionの
		# シリアライズ結果が変化しないことを保証するための選択。
	}
	var sequence := _action_sequence_for_definition()
	if not sequence.is_empty():
		boss["action_sequence"] = sequence
		boss["advanced_ai_version"] = ADVANCED_AI_VERSION
	# v0.1-C 多属性対応: the engine now supports any number of weak/resist
	# attributes per unit (RBMUnit.weak_attributes/resist_attributes,
	# RBMConstants.attribute_multiplier_for_lists) -- every attribute STEP 2
	# selected is written through, not just the first. RBMDefinitionLoader
	# accepts this plural key (preferred) or the legacy singular
	# weak_attribute/resist_attribute key (still supported for old Definitions).
	if not weak_attributes.is_empty():
		boss["weak_attributes"] = weak_attributes.duplicate()
	if not resist_attributes.is_empty():
		boss["resist_attributes"] = resist_attributes.duplicate()
	# 覚醒: 通常actionsとは独立したトップレベルキー。未設定ならキー自体を
	# 省略する（action_sequenceと同じ「存在しない=機構が一切存在しない」慣習）。
	var resolved_awakening := _resolved_awakening_for_definition()
	if not resolved_awakening.is_empty():
		boss["awakening"] = resolved_awakening

	var party: Array = []
	for character_id in party_character_ids:
		var party_entry := {
			"character_id": character_id,
			"allowed_skill_ids": (ally_allowed_skill_ids.get(character_id, []) as Array).duplicate(),
		}
		# SIMPLE must remain byte-for-byte master-driven even though retained
		# HARDCORE values stay on the Draft for a later mode switch back.
		if creator_mode == CREATOR_MODE_ADVANCED and ally_overrides.has(character_id):
			var character_override: Dictionary = ally_overrides[character_id]
			if character_override.has("stats") and not (character_override["stats"] as Dictionary).is_empty():
				party_entry["stat_overrides"] = (character_override["stats"] as Dictionary).duplicate(true)
			if character_override.has("skills") and not (character_override["skills"] as Dictionary).is_empty():
				party_entry["skill_overrides"] = (character_override["skills"] as Dictionary).duplicate(true)
		party.append(party_entry)

	return {"boss": boss, "party": party}

func _generate_boss_id() -> String:
	# Just an author-chosen label under the corrected Step 3 design (no
	# shared master boss data exists to look this id up against) — derived
	# from the name plus a stable per-draft counter start so two drafts with
	# the same name never collide within one Creator session.
	var slug := boss_name.strip_edges().to_lower().replace(" ", "_")
	if slug.is_empty():
		slug = "boss"
	return "%s_%d" % [slug, _next_skill_ordinal]

func _skills_for_definition() -> Array:
	var out: Array = []
	for skill in skills:
		var entry := {
			"skill_id": str(skill.get("skill_id", "")),
			"name": str(skill.get("name", "")),
			"type": str(skill.get("type", "")),
		}
		match entry["type"]:
			"attack":
				entry["target"] = str(skill.get("target", "single"))
				entry["attribute"] = str(skill.get("attribute", "NEUTRAL"))
				entry["atk_multiplier"] = float(skill.get("atk_multiplier", 0.0))
			"self_heal":
				entry["heal_amount"] = resolved_heal_amount(skill)
			"atk_self_buff":
				entry["buff_multiplier"] = float(skill.get("buff_multiplier", 0.0))
				entry["duration_turns"] = int(skill.get("duration_turns", 1))
			_:
				pass
		out.append(entry)
	return out

func _normal_actions_for_definition() -> Array:
	var out: Array = []
	if not normal_actions_enabled:
		return out
	for skill in skills:
		var skill_id := str(skill.get("skill_id", ""))
		var pct := float(normal_action_percentages.get(skill_id, 0.0))
		if pct > 0.0:
			out.append({"skill_id": skill_id, "weight": pct})
	return out

func _scripted_actions_for_definition() -> Array:
	var out: Array = []
	var next_order := {}
	for entry in scripted_actions:
		var key := "%d|%s" % [int(entry.get("turn", 0)), str(entry.get("timing", ""))]
		var order: int = int(next_order.get(key, 0)) + 1
		next_order[key] = order
		out.append({
			"turn": int(entry.get("turn", 1)),
			"skill_id": str(entry.get("skill_id", "")),
			"timing": str(entry.get("timing", "")),
			"order": order,
		})
	return out

## action_sequenceをそのままDefinition形へ変換する。conditionsはauthoring形
## =resolved形（変換の要らない単純な形）のため、ここではフィールドの型
## 正規化と配列順序（＝実行順）の保持のみを行う。
func _action_sequence_for_definition() -> Array:
	var out: Array = []
	for slot in action_sequence:
		out.append(_resolved_action_slot_for_definition(slot))
	return out

## 著作形（"mode"を持つ）→戦闘/Clear Check比較用の解決済み形（"mode"を持たず
## 最終weightのみ）への変換。restore_clear_check_snapshot()（既に解決済みの
## 保存データを読む）やrestore_from_saved_dict()（著作形をそのまま保つ）は
## これを使わない、別の専用関数を持つ（下記参照）——用途に応じて別関数を
## 分けている理由はそれぞれのコメントを参照。
func _resolved_action_slot_for_definition(slot: Dictionary) -> Dictionary:
	var kind := str(slot.get("kind", ""))
	var resolved := {
		"slot_id": str(slot.get("slot_id", "")),
		"kind": kind,
		"conditions": _normalized_conditions(slot.get("conditions", [])),
		"condition_logic": str(slot.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)),
		"max_uses": int(slot.get("max_uses", RBMActionPatternRules.UNLIMITED_USES)),
	}
	if kind == RBMActionPatternRules.SLOT_KIND_RANDOM:
		resolved["candidates"] = _resolved_random_candidates(slot)
	else:
		resolved["skill_id"] = str(slot.get("skill_id", ""))
	return resolved

## 条件タイプごとに意味のあるフィールドだけを型正規化して残す——余分な
## キーが元Dictionaryに混入していても出力へ持ち越さない（他の_*_for_definition()
## 系メソッドと同じ、明示的なフィールド列挙による正規化方針）。旧仕様に
## あった瞬間条件タイプ（_instantサフィックス）はRBMActionPatternRules.
## NORMAL_CONDITION_TYPESから既に削除済みのため、ここにもその型は現れない
## （残っていても不明タイプとして下のmatchの"_"分岐へ落ちるだけで安全）。
func _normalized_conditions(raw: Array) -> Array:
	var out: Array = []
	for condition_variant in raw:
		var condition: Dictionary = condition_variant
		var condition_type := str(condition.get("type", ""))
		var normalized := {"type": condition_type}
		match condition_type:
			"hp_at_most", "hp_at_least":
				normalized["percent"] = float(condition.get("percent", 0.0))
			"hp_between":
				normalized["percent_min"] = float(condition.get("percent_min", 0.0))
				normalized["percent_max"] = float(condition.get("percent_max", 100.0))
			"turn_at", "turn_at_least", "turn_at_most":
				normalized["turn"] = int(condition.get("turn", 1))
			"turn_every_n":
				normalized["n"] = int(condition.get("n", 1))
			"turn_between":
				normalized["turn_min"] = int(condition.get("turn_min", 1))
				normalized["turn_max"] = int(condition.get("turn_max", 1))
			"allies_at_most", "allies_at_least", "allies_exactly":
				normalized["count"] = int(condition.get("count", 0))
			"character_alive", "character_downed":
				normalized["character_id"] = str(condition.get("character_id", ""))
			"last_boss_skill":
				normalized["skill_id"] = str(condition.get("skill_id", ""))
			"last_received_skill":
				normalized["skill_id"] = str(condition.get("skill_id", ""))
			"last_received_attribute":
				normalized["attribute"] = str(condition.get("attribute", "NEUTRAL"))
			"weak_hit":
				pass  # フィールドなし。
			_:
				pass  # 未知タイプはRBMDefinitionLoader側で拒否される——ここでは通すだけ。
		out.append(normalized)
	return out

## §13: "均等"/"自分で設定"の区別はあくまで著作時のUI上の入力モード
## （STEP3のself_healのheal_mode:"fixed"/"percent"と同じ位置づけ）——実際の
## 抽選に使う最終的な重みへここで解決してしまう（"均等"なら候補数で等分、
## "自分で設定"なら著作された重みをそのまま使う）。これにより戦闘エンジン
## （RBMBattle）は常に「候補ごとのweightの配列」という単一の形だけを扱えば
## よく、mode分岐を持つ必要がない。"mode"自体はDefinition/battle_content_
## snapshotの出力には含まれない（著作形にのみ残る、下のrestore_from_saved_
## dict()系参照）。
func _resolved_random_candidates(slot: Dictionary) -> Array:
	var raw_candidates: Array = slot.get("candidates", [])
	var is_even := str(slot.get("mode", RBMActionPatternRules.RANDOM_MODE_EVEN)) == RBMActionPatternRules.RANDOM_MODE_EVEN
	var candidates: Array = []
	for candidate in raw_candidates:
		var weight := 1.0 if is_even else float(candidate.get("weight", 0.0))
		candidates.append({"skill_id": str(candidate.get("skill_id", "")), "weight": weight})
	return candidates

# ---------------------------------------------------------------------------
# Phase 1 Step 5 — Clear Check (§18-23)
# ---------------------------------------------------------------------------

## §19/§20/§21/§22: the exact "battle content" subset Clear Check compares --
## deliberately narrower than to_definition()'s full output. Excludes
## boss_id/boss_name (§20: explicitly not battle content) and appearance_id
## (§20: never part of any Definition-derived shape in the first place, so no
## special exclusion code is even needed for it). Phase 3: party is an ordered
## Array because equal-SPD allies act in party order.  Each character's own
## allowed_skill_ids remains sorted (its order has no battle-mechanical effect --
## rbm_battle.gd's only consumer of a skill list is _find_skill()'s by-id
## linear lookup -- so a pure reorder, e.g. from unchecking then rechecking a
## skill, must not force a re-Clear-Check). weak_attributes/resist_attributes
## are likewise sorted (RBMConstants.attribute_multiplier_for_lists() only
## ever does Array.has() membership checks). §22: normal_actions and
## scripted_actions reuse to_definition()'s own private array-generation
## methods VERBATIM, so their ORDER is preserved exactly as Definition
## generation itself produces it -- normal_actions' array order can change
## which specific RNG roll picks which skill (_pick_boss_normal_action()'s
## cumulative-weight scan is order-sensitive), and scripted_actions carries
## its own "order" field governing same-(turn,timing)-group execution order.
## Boss skills are compared via _skills_for_definition()'s own resolved
## output (heal_amount already computed, matching exactly what
## RBMBattle._apply_boss_skill() actually consumes) rather than the raw
## authoring-shape skills[] Dictionary, keyed by skill_id. skill_id is
## deliberately INCLUDED (confirmed user decision, Step 5 completion report
## follow-up, 2026-08-29 — see src/bossmaker/README.md's own "Step 5" section
## for the full writeup): editing an existing skill's values in place
## (update_skill(), which never changes skill_id) restores Clear Check
## success when reverted to the exact original values, but deleting and
## recreating a skill assigns a brand-new skill_id, so an otherwise-identical
## recreated skill is treated as a DIFFERENT skill and requires a fresh Clear
## Check — matching normal_actions/scripted_actions' own existing reliance on
## skill_id as their link to a specific skill.
##
## Phase 1 Step 7 §44: author_notes/challenge_info_visibility are deliberately
## EXCLUDED here (same exclusion category as boss_id/boss_name/appearance_id
## above) — they affect only what a CHALLENGE confirm screen shows, never
## actual battle mechanics, so editing either must never invalidate an
## existing Clear Check success.
## `creator_mode`自体はここへ含めない——SIMPLE/HARDCOREという表示モードを
## 切り替えただけでは戦闘定義が変化していないため、Clear Checkを失効させて
## はならない（§23）。比較対象は実際に戦闘結果へ影響するaction_sequenceの
## 解決済み内容のみ（配列順序＝実行順のため、_action_sequence_for_definition()
## と同じ生成ロジックをそのまま使い順序を保持する——normal_actions/
## scripted_actionsの既存の順序保持方針と一貫させる）。
##
## この関数自体はcreator_modeを一切参照せず、SIMPLE状態（action_sequence==[]）
## と、その直後のHARDCORE状態（自動変換済み、内容はSIMPLE側フィールドの
## 複製そのもの）の両方が常に同じ正規化結果を返すよう統一する——モード切替
## だけでは比較結果が変化しない（既存のDictionary比較方式は無改修のまま
## 維持、新しいハッシュ機構は導入しない）。
##
## §23確定: 旧HARDCORE（action_patterns形式）のClear Check成功記録は今回の
## 全面再設計により失効して構わない——battle_content_snapshotの形自体が
## 変わった（"action_patterns"キー→"action_sequence"キー、内容の形も
## スロット方式へ変更）ため、旧記録との==比較は自然に一致しなくなる
## （新しいマイグレーションコードを追加する必要はない、ユーザー確定仕様）。
func battle_content_snapshot() -> Dictionary:
	return {
		"hp": hp, "atk": atk, "spd": spd,
		"weak_attributes": _sorted_string_copy(weak_attributes),
		"resist_attributes": _sorted_string_copy(resist_attributes),
		"skills": _skills_by_id_for_snapshot(),
		"normal_actions": _normal_actions_for_definition(),
		"scripted_actions": _scripted_actions_for_definition(),
		"action_sequence": _normalized_action_sequence_for_snapshot(),
		"awakening": _resolved_awakening_for_definition(),
		"party": _party_by_character_id_for_snapshot(),
	}

## action_sequenceが空（SIMPLE、またはHARDCOREへ切り替えたが自動変換対象が
## 無かった場合）なら、現在のSIMPLE側フィールドから今この瞬間に変換したら
## 得られるはずの内容を比較対象とする——HARDCOREへ切り替えた直後の実際の
## action_sequence（自動変換済み）と全く同じ値になる。空でなければ、現在の
## action_sequence自体（slot_id除く）をそのまま使う——HARDCORE独自の設定が
## 実際に追加されていれば、この時点で上のプロスペクティブな内容とは一致
## しなくなり、比較結果は正しく変化する。
func _normalized_action_sequence_for_snapshot() -> Array:
	if action_sequence.is_empty():
		return _resolved_prospective_simple_conversion_slots()
	return _slots_without_slot_id(_action_sequence_for_definition())

func _sorted_string_copy(values: Array) -> Array:
	var out: Array = values.duplicate()
	out.sort()
	return out

func _skills_by_id_for_snapshot() -> Dictionary:
	var out := {}
	for entry in _skills_for_definition():
		out[str(entry.get("skill_id", ""))] = entry
	return out

func _party_by_character_id_for_snapshot() -> Array:
	var out: Array = []
	for character_id in party_character_ids:
		out.append(_party_snapshot_entry(character_id, ally_allowed_skill_ids.get(character_id, [])))
	return out

func _party_snapshot_entry(character_id: String, allowed_raw: Array) -> Dictionary:
	var effective := effective_character_def(character_id)
	var allowed := _sorted_string_copy(allowed_raw)
	var skill_values := {}
	for skill_variant in effective.get("skills", []):
		if not (skill_variant is Dictionary):
			continue
		var skill: Dictionary = skill_variant
		var skill_id := str(skill.get("id", ""))
		if not allowed.has(skill_id):
			continue
		var values := {}
		for field in RBMDefinitionLoader.ally_skill_override_fields(skill):
			values[field] = int(skill[field]) if ["heal_amount", "sp_amount", "sp_cost", "duration_turns"].has(field) else float(skill[field])
		skill_values[skill_id] = values
	return {
		"character_id": character_id,
		"hp": int(effective.get("hp", 1)),
		"atk": int(effective.get("atk", 1)),
		"spd": int(effective.get("spd", 1)),
		"max_sp": int(effective.get("max_sp", 1)),
		"allowed_skill_ids": allowed,
		"skill_values": skill_values,
	}

## §14: call exactly when the battle system's own win condition has fired
## (RBMBattle.winner == "ally", via RBMBattle.battle_over/winner — never an
## independently re-implemented boss.hp<=0 check). Idempotent: calling it
## again with unchanged content produces byte-identical content, so an extra
## call is harmless, but callers should only invoke this at the moment of an
## actual victory (see RBMCreatorClearCheckView).
func record_clear_check_success() -> void:
	_clear_check_success_snapshot = battle_content_snapshot().duplicate(true)

func has_ever_cleared() -> bool:
	return not _clear_check_success_snapshot.is_empty()

## §17: re-derived live every call, never cached -- editing away from the
## cleared content and then back to the EXACT same content ("A→B→A") makes
## this true again automatically, with no special-cased "restore" logic
## required anywhere else.
func is_clear_check_currently_valid() -> bool:
	return has_ever_cleared() and battle_content_snapshot() == _clear_check_success_snapshot

## 現在選択中の外見(appearance_id)が覚醒(Awakening)機能に対応しているか
## ——ゲームデザイン上の可否そのもの。覚醒後アセットが実際に存在するか
## (RBMVisualAssets.has_awakened_design())とは別概念のため、混同しない
## （§3確定）。
func supports_awakening() -> bool:
	return RBMCreatorAppearanceCatalog.supports_awakening(appearance_id)

## 覚醒が設定されているのに、現在の外見が覚醒非対応の場合は不正
## ——通常はCreator STEP3が「覚醒対応の外見でなければ種類選択肢自体を
## disabledにする」ため到達しないが、覚醒設定後に外見だけを非対応の
## ものへ変更した場合にこの不整合が起こりうる。旧ボスデータ
## (awakening未設定)には一切影響しない（has_awakening()がfalseの間は
## 常にtrue）。
func is_awakening_appearance_valid() -> bool:
	return not has_awakening() or supports_awakening()

## §17/§21: whether the current Draft would pass RBMDefinitionLoader.resolve()
## right now (Step 6's "挑戦可能" vs "下書き" distinction). Never cached, never
## persisted to a save file (§22) -- always this same live re-derivation.
## 覚醒×外見の整合性(is_awakening_appearance_valid())もここで合わせて
## 見る——新規作成/公開用validationの唯一の共通ゲートに一本化するため
## （is_playable()はTest Battle可否・Clear Check到達・公開のいずれもが
## 最終的に依存する単一の判定関数）。
func is_playable() -> bool:
	return is_awakening_appearance_valid() and bool(RBMDefinitionLoader.resolve(to_definition()).get("ok", false))

# ---------------------------------------------------------------------------
# Phase 1 Step 6 — ローカル保存・再編集 (§7/§8/§9/§13/§14/§15/§46)
# ---------------------------------------------------------------------------
##
## §7: BossBattleDefinitionは保存しない（to_definition()からいつでも純粋関数的
## に再生成できるため）。保存の正はこのDraft自身が持つ生の著作フィールドで、
## to_saved_dict()/full_authoring_snapshot()/restore_from_saved_dict()は
## いずれもこの生フィールド（skillsは_skills_for_definition()の解決済み形では
## なく、著作時のheal_mode/heal_fixed_amount/heal_percent等をそのまま持つ）を
## 対象とする。battle_content_snapshot()（Step 5、Clear Check比較専用）とは
## 別物で、そちらは一切変更していない。

## §8: 完全復元に必要な生の著作フィールドすべてをそのまま持つDictionary。
## 順序が意味を持つフィールド（skills/scripted_actions/party_character_ids）
## は一切ソートせず、配列としてそのまま複製する——JSON配列はGodotの
## JSON.stringify()/parse_string()を通しても順序を保持する。
func to_saved_dict() -> Dictionary:
	return {
		"boss_name": boss_name,
		"appearance_id": appearance_id,
		"battle_background": battle_background,
		"hp": hp, "atk": atk, "spd": spd,
		"weak_attributes": weak_attributes.duplicate(),
		"resist_attributes": resist_attributes.duplicate(),
		"skills": skills.duplicate(true),
		"next_skill_ordinal": _next_skill_ordinal,
		"normal_actions_enabled": normal_actions_enabled,
		"normal_action_percentages": normal_action_percentages.duplicate(true),
		"scripted_actions": scripted_actions.duplicate(true),
		"party_character_ids": party_character_ids.duplicate(),
		"ally_allowed_skill_ids": ally_allowed_skill_ids.duplicate(true),
		"ally_overrides": ally_overrides.duplicate(true),
		"author_notes": author_notes,
		"author_name": author_name,
		"challenge_info_visibility": challenge_info_visibility.duplicate(true),
		# フィールド自体が存在しない旧stage（HARDCORE機能が無かった頃に保存
		# されたもの）はcreator_mode="simple"・action_sequence=[]へ安全に
		# フォールバックする（restore_from_saved_dict()参照）——既存SIMPLE
		# 専用stageは引き続き正しく読み込める。
		"creator_mode": creator_mode,
		"action_sequence": action_sequence.duplicate(true),
		"next_slot_ordinal": _next_slot_ordinal,
		# フィールド自体が存在しない旧stage（覚醒機能が無かった頃に保存された
		# もの）はawakening={}（未設定）へ安全にフォールバックする
		# （restore_from_saved_dict()参照）。
		"awakening": awakening.duplicate(true),
		# HARDCORE AIサブシステム自体のバージョン印——stage JSON自体に保存する
		# ことで、読込側（RBMLocalStageRepository._validate_draft_shape()）が
		# 「この保存ファイルが前提とするHARDCORE AIサブシステムの版」を検証
		# できる。2026-09-05の全面再設計（action_patterns→action_sequence）に
		# 伴いADVANCED_AI_VERSIONを1→2へ引き上げたため、旧version(1)の
		# HARDCORE保存データ（旧action_patterns形式）はこのバージョン不一致
		# により読込時に丸ごと拒否される（ユーザー確定仕様、自動変換しない）。
		# フィールド欠落＝Phase 2以前のSIMPLE専用旧stage互換としてv1扱い
		# （SIMPLE専用データには一切影響しない）。
		"advanced_ai_version": ADVANCED_AI_VERSION,
		# Creator UI再設計 §24〜§27: 公開状態そのもの。フィールド自体が存在
		# しない旧保存データはfalse（未公開）へ安全にフォールバックする
		# （restore_from_saved_dict()参照、ユーザー確定仕様「既存データを
		# 自動的に公開済みにしない」）。
		"published": _published,
		# CHALLENGE UI再設計 §4-D: フィールド自体が存在しない旧保存データは
		# 0（＝新着ソートで最も古い扱い）へ安全にフォールバックする。
		"published_at_unix_time": _published_at_unix_time,
		# 公開UI整理（2026-09-10）: オンライン公開管理用メタデータ。フィールド
		# 自体が存在しない旧保存データは""/falseへ安全にフォールバックする
		# （restore_from_saved_dict()参照）——古いsaveを自動的にオンライン
		# 公開済み扱いにはしない。
		"online_boss_id": _online_boss_id,
		"online_published": _online_published,
	}

## §15/§16/§18: 保存によって失われうるユーザー設定・状態すべてを含む、未保存
## 変更判定専用のスナップショット（Step 5のbattle_content_snapshot()より広い
## 範囲——boss_name/appearance_id/_next_skill_ordinal/normal_actions_enabled
## やClear Check成功snapshot自体も含む）。stage_idは著作内容ではないため
## 意図的に含めない（§18）。§16: Clear Check成功snapshotをここへ含めることで、
## 「内容変更なしでClear Checkだけ成功した」場合も未保存変更ありとして検知
## される（確定仕様）。
func full_authoring_snapshot() -> Dictionary:
	var snapshot := to_saved_dict()
	snapshot["clear_check_success_snapshot"] = _clear_check_success_snapshot.duplicate(true)
	return snapshot

## §10: Clear Check証明をRepositoryが保存できるよう複製して返す
## （_clear_check_success_snapshotはprivate慣習のフィールドのため、保存I/O層
## からの読み取り専用アクセスをこの経由に限定する）。
func clear_check_snapshot_for_save() -> Dictionary:
	return _clear_check_success_snapshot.duplicate(true)

## §12/§13: JSON.parse_string()はGodot 4.7上ではすべての数値をfloatとして返す
## （実機検証済み、Step 6技術調査報告§9）。ここでフィールドの意味的な型
## （hp/atk/spd/_next_skill_ordinal等は整数、atk_multiplier等は小数）に応じて
## 明示的にint()/float()を適用し正規化する——独自の丸め仕様は追加しない
## （int()/float()という、このプロジェクト全体が既に使っている標準キャスト
## のみ）。JSONパース結果を直接varへ代入する経路は存在しない。
func restore_from_saved_dict(data: Dictionary) -> void:
	boss_name = str(data.get("boss_name", ""))
	appearance_id = str(data.get("appearance_id", ""))
	battle_background = "day" if data.get("battle_background", "night") == "day" else "night"
	hp = int(data.get("hp", 1))
	atk = int(data.get("atk", 1))
	spd = int(data.get("spd", 1))
	weak_attributes = _typed_string_array(data.get("weak_attributes", []))
	resist_attributes = _typed_string_array(data.get("resist_attributes", []))
	skills = _restore_skills(data.get("skills", []))
	_next_skill_ordinal = int(data.get("next_skill_ordinal", 1))
	normal_actions_enabled = bool(data.get("normal_actions_enabled", false))
	normal_action_percentages = _restore_normal_action_percentages(data.get("normal_action_percentages", {}))
	scripted_actions = _restore_scripted_actions(data.get("scripted_actions", []))
	party_character_ids = _typed_string_array(data.get("party_character_ids", []))
	ally_allowed_skill_ids = _restore_ally_allowed_skill_ids(data.get("ally_allowed_skill_ids", {}))
	ally_overrides = _restore_ally_overrides(data.get("ally_overrides", {}))
	# §19: フィールド自体が存在しない旧stage（Step 7以前に保存されたもの）は
	# author_notes=""・すべて公開のデフォルトへ安全にフォールバックする。
	author_notes = str(data.get("author_notes", "")).left(MAX_AUTHOR_NOTES_LENGTH)
	author_name = str(data.get("author_name", "")).left(MAX_AUTHOR_NAME_LENGTH)
	challenge_info_visibility = _restore_challenge_info_visibility(data.get("challenge_info_visibility", {}))
	# 旧stage（フィールド自体が存在しない）は"simple"/空配列へ安全にフォール
	# バックする。不正な値（将来別途拡張された値・破損データ）が保存されて
	# いた場合もCREATOR_MODE_SIMPLE/CREATOR_MODE_ADVANCED以外は一律"simple"
	# へ丸める——存在しないモードのままCreatorが起動する事態を避けるための
	# 最終防衛線。なお旧version(1、旧action_patterns形式)のHARDCORE保存データ
	# はRBMLocalStageRepository._validate_draft_shape()のadvanced_ai_version
	# 厳密一致チェックにより、この関数へ到達する前に読込自体が拒否される
	# （ユーザー確定仕様）——ここでの"action_sequence"読み取りは常に新schema
	# 前提でよい。
	var saved_mode := str(data.get("creator_mode", CREATOR_MODE_SIMPLE))
	creator_mode = saved_mode if saved_mode == CREATOR_MODE_SIMPLE or saved_mode == CREATOR_MODE_ADVANCED else CREATOR_MODE_SIMPLE
	action_sequence = _restore_action_sequence(data.get("action_sequence", []))
	_next_slot_ordinal = int(data.get("next_slot_ordinal", 1))
	# 覚醒: フィールド自体が存在しない旧stage（この機能以前に保存されたもの）
	# はawakening={}（未設定）へ安全にフォールバックする——他の任意フィールド
	# と同じ「存在しなければ安全なデフォルト」の慣習。
	awakening = _restore_awakening(data.get("awakening", {}))
	# §24〜§27（公開機能）: フィールド自体が存在しない旧stageはfalseへ安全に
	# フォールバックする——ユーザー確定仕様「既存データを自動的に公開済みに
	# しない」。
	_published = bool(data.get("published", false))
	_published_at_unix_time = int(data.get("published_at_unix_time", 0))
	# 公開UI整理（2026-09-10）: フィールド自体が存在しない旧stageは""/falseへ
	# 安全にフォールバックする（未公開として扱う）。
	_online_boss_id = str(data.get("online_boss_id", ""))
	_online_published = bool(data.get("online_published", false))

## §10/§11: Clear Check証明の復元。空Dictionary(未クリア)ならそのまま
## _clear_check_success_snapshot = {}（has_ever_cleared()がfalseのまま）。
## 保存された内容はbattle_content_snapshot()と同じ形（skillsはskill_idキーの
## Dictionary、resolved済みのheal_amount/atk_multiplier等を持つ）なので、
## そちらと同じ数値フィールドをint()/float()で正規化する。
func restore_clear_check_snapshot(raw: Dictionary) -> void:
	if raw.is_empty():
		_clear_check_success_snapshot = {}
		return
	var normalized_skills := {}
	var raw_skills: Dictionary = raw.get("skills", {})
	for skill_id in raw_skills.keys():
		var entry_variant: Variant = raw_skills[skill_id]
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var normalized: Dictionary = {
			"skill_id": str(entry.get("skill_id", "")),
			"name": str(entry.get("name", "")),
			"type": str(entry.get("type", "")),
		}
		match str(normalized["type"]):
			"attack":
				normalized["target"] = str(entry.get("target", "single"))
				normalized["attribute"] = str(entry.get("attribute", "NEUTRAL"))
				normalized["atk_multiplier"] = float(entry.get("atk_multiplier", 0.0))
			"self_heal":
				normalized["heal_amount"] = int(entry.get("heal_amount", 0))
			"atk_self_buff":
				normalized["buff_multiplier"] = float(entry.get("buff_multiplier", 0.0))
				normalized["duration_turns"] = int(entry.get("duration_turns", 1))
		normalized_skills[str(skill_id)] = normalized

	var normalized_normal_actions: Array = []
	for entry_variant in raw.get("normal_actions", []):
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		normalized_normal_actions.append({
			"skill_id": str(entry.get("skill_id", "")),
			"weight": float(entry.get("weight", 0.0)),
		})

	var normalized_scripted_actions: Array = []
	for entry_variant in raw.get("scripted_actions", []):
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		normalized_scripted_actions.append({
			"turn": int(entry.get("turn", 1)),
			"skill_id": str(entry.get("skill_id", "")),
			"timing": str(entry.get("timing", "")),
			"order": int(entry.get("order", 0)),
		})

	var normalized_party := _normalized_clear_check_party(raw.get("party", {}))

	# 保存されたclear_check_snapshotのaction_sequenceは、記録された時点で
	# 既にbattle_content_snapshot()＝_action_sequence_for_definition()の
	# 解決済み形（"mode"は既にweightへ解決済み、candidatesは既に最終的な
	# {"skill_id","weight"}の形）で保存されている——_resolved_action_slot_
	# for_definition()（Draft著作形、"mode"フィールドを見てeven/manualを
	# 都度解決する）をそのまま再利用すると、解決済みデータには"mode"キーが
	# 存在しないため常に既定の"even"（均等）として誤って再解決され、保存
	# されていたmanualの重みを握りつぶしてしまう。そのため専用の
	# _normalized_clear_check_action_sequence()（型正規化のみ、mode解決を
	# 一切行わない）を使う——skills/normal_actions/scripted_actionsが既に
	# この節で個別の専用正規化ロジックを持っているのと同じ設計。
	## §23確定: 旧HARDCORE（"action_patterns"キー、旧schema）で記録された
	## Clear Check成功記録は今回失効して構わない——ここでは新キー
	## "action_sequence"のみを読む（旧キーからの移行読み取りは行わない）。
	var normalized_action_sequence := _normalized_clear_check_action_sequence(raw.get("action_sequence", []))
	# 覚醒: 記録された時点で既にbattle_content_snapshot()＝
	# _resolved_awakening_for_definition()の解決済み形（conditions/
	# condition_logic/buff/heal_amount、"mode"のような著作専用フィールドは
	# 持たない）で保存されている——action_sequenceと違い再解決の問題が無い
	# ため、_normalized_conditions()を再利用しつつ型正規化だけを行う。
	## §23と同じ方針: 覚醒実装以前に記録されたClear Check成功記録には
	## このキー自体が存在しない——raw.get("awakening",{})が空Dictionaryの
	## ままなら_normalized_clear_check_awakening()も空Dictionaryを返し、
	## 「覚醒未設定のまま記録された」既存の成功記録は今後もそのまま有効。
	var normalized_awakening := _normalized_clear_check_awakening(raw.get("awakening", {}))

	_clear_check_success_snapshot = {
		"hp": int(raw.get("hp", 0)),
		"atk": int(raw.get("atk", 0)),
		"spd": int(raw.get("spd", 0)),
		"weak_attributes": _sorted_string_copy(raw.get("weak_attributes", [])),
		"resist_attributes": _sorted_string_copy(raw.get("resist_attributes", [])),
		"skills": normalized_skills,
		"normal_actions": normalized_normal_actions,
		"scripted_actions": normalized_scripted_actions,
		"action_sequence": normalized_action_sequence,
		"awakening": normalized_awakening,
		"party": normalized_party,
	}

func _normalized_clear_check_awakening(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	var normalized := {
		"conditions": _normalized_conditions(raw.get("conditions", [])),
		"condition_logic": str(raw.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)),
	}
	var buff: Variant = raw.get("buff", {})
	if buff is Dictionary and not (buff as Dictionary).is_empty():
		normalized["buff"] = {
			"buff_multiplier": float(buff.get("buff_multiplier", 1.0)),
			"duration_turns": int(buff.get("duration_turns", 1)),
		}
	if raw.has("heal_amount"):
		normalized["heal_amount"] = int(raw["heal_amount"])
	return normalized

func _normalized_clear_check_party(raw_party: Variant) -> Array:
	var out: Array = []
	if raw_party is Dictionary:
		# v1 snapshots stored a character_id -> allowed_skill_ids Dictionary and
		# therefore did not preserve party order or fixed master performance.  The
		# v1 Draft still carries the saved party order; rebuild the new effective
		# representation from it so existing clear-checked stages remain valid.
		var legacy: Dictionary = raw_party
		for character_id in party_character_ids:
			var allowed: Array = legacy.get(character_id, [])
			out.append(_party_snapshot_entry(character_id, allowed))
		return out
	if not (raw_party is Array):
		return out
	for entry_variant in raw_party:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var skill_values := {}
		var raw_values: Dictionary = entry.get("skill_values", {})
		for skill_id in raw_values.keys():
			var values_variant: Variant = raw_values[skill_id]
			if not (values_variant is Dictionary):
				continue
			var values: Dictionary = values_variant
			var normalized_values := {}
			for field in values.keys():
				var field_name := str(field)
				normalized_values[field_name] = int(values[field]) if ["heal_amount", "sp_amount", "sp_cost", "duration_turns"].has(field_name) else float(values[field])
			skill_values[str(skill_id)] = normalized_values
		out.append({
			"character_id": str(entry.get("character_id", "")),
			"hp": int(entry.get("hp", 1)),
			"atk": int(entry.get("atk", 1)),
			"spd": int(entry.get("spd", 1)),
			"max_sp": int(entry.get("max_sp", 1)),
			"allowed_skill_ids": _sorted_string_copy(entry.get("allowed_skill_ids", [])),
			"skill_values": skill_values,
		})
	return out

func _typed_string_array(raw: Array) -> Array[String]:
	var out: Array[String] = []
	for value in raw:
		out.append(str(value))
	return out

## §8/§9: authoring-shape skills[]の各エントリを、typeごとの意味的な型
## （self_healのheal_fixed_amountはint、heal_percentはfloat、等）へ正規化して
## 復元する。to_definition()が読む解決済み形（_skills_for_definition()）とは
## 別物で、著作フィールド（heal_mode等）を失わずに保つのが目的（§7）。
func _restore_skills(raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry_variant in raw:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var normalized: Dictionary = {
			"skill_id": str(entry.get("skill_id", "")),
			"name": str(entry.get("name", "")),
			"type": str(entry.get("type", "")),
		}
		match str(normalized["type"]):
			"attack":
				normalized["target"] = str(entry.get("target", "single"))
				normalized["attribute"] = str(entry.get("attribute", "NEUTRAL"))
				normalized["atk_multiplier"] = float(entry.get("atk_multiplier", 0.0))
			"self_heal":
				normalized["heal_mode"] = str(entry.get("heal_mode", "fixed"))
				normalized["heal_fixed_amount"] = int(entry.get("heal_fixed_amount", 0))
				normalized["heal_percent"] = float(entry.get("heal_percent", 0.0))
			"atk_self_buff":
				normalized["buff_multiplier"] = float(entry.get("buff_multiplier", 0.0))
				normalized["duration_turns"] = int(entry.get("duration_turns", 1))
		out.append(normalized)
	return out

func _restore_normal_action_percentages(raw: Dictionary) -> Dictionary:
	var out := {}
	for skill_id in raw.keys():
		out[str(skill_id)] = float(raw[skill_id])
	return out

## §7: 著作時のscripted_actions形（{turn,skill_id,timing}、orderフィールドは
## 持たない——orderは配列位置から_scripted_actions_for_definition()が都度
## 生成する）をそのまま復元する。配列順序自体がグループ内実行順を表すため、
## 走査順のまま復元する（ソートしない）。
func _restore_scripted_actions(raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry_variant in raw:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		out.append({
			"turn": int(entry.get("turn", 1)),
			"skill_id": str(entry.get("skill_id", "")),
			"timing": str(entry.get("timing", "")),
		})
	return out

## to_saved_dict()が保存する著作形（"mode"を含む、_restore_skills()の
## heal_mode等と同じ位置づけ）をそのまま型正規化して復元する——
## _resolved_action_slot_for_definition()（"mode"をweightへ解決してしまう
## 別関数）とは意図的に別物。ここでmode解決を行うと、保存→読込のたびに
## ランダム攻撃の"自分で設定"入力（各候補の個別重み）がUI上"均等"表示へ
## 巻き戻ってしまう回帰バグになるため、著作フィールドはそのまま保持する。
func _restore_action_sequence(raw: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry_variant in raw:
		if entry_variant is Dictionary:
			out.append(_restored_action_slot_authoring(entry_variant))
	return out

func _restored_action_slot_authoring(slot: Dictionary) -> Dictionary:
	var kind := str(slot.get("kind", RBMActionPatternRules.SLOT_KIND_SKILL))
	var restored := {
		"slot_id": str(slot.get("slot_id", "")),
		"kind": kind,
		"conditions": _normalized_conditions(slot.get("conditions", [])),
		"condition_logic": str(slot.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)),
		"max_uses": int(slot.get("max_uses", RBMActionPatternRules.UNLIMITED_USES)),
	}
	if kind == RBMActionPatternRules.SLOT_KIND_RANDOM:
		var candidates: Array = []
		for candidate in slot.get("candidates", []):
			candidates.append({"skill_id": str(candidate.get("skill_id", "")), "weight": float(candidate.get("weight", 0.0))})
		restored["mode"] = str(slot.get("mode", RBMActionPatternRules.RANDOM_MODE_EVEN))
		restored["candidates"] = candidates
	else:
		restored["skill_id"] = str(slot.get("skill_id", ""))
	return restored

## 覚醒の著作形をそのまま型正規化して復元する——_restored_action_slot_
## authoring()と同じ位置づけ（heal_mode等の著作専用フィールドはそのまま
## 保持し、resolved_heal_amount()等による解決はto_definition()/battle_
## content_snapshot()側だけで行う）。raw自体が空Dictionaryなら「未設定」
## としてそのまま{}を返す。
func _restore_awakening(raw: Dictionary) -> Dictionary:
	if raw.is_empty():
		return {}
	var restored := {
		"conditions": _normalized_conditions(raw.get("conditions", [])),
		"condition_logic": str(raw.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)),
		"buff": {},
		"heal": {},
	}
	var buff_raw: Variant = raw.get("buff", {})
	if buff_raw is Dictionary and not (buff_raw as Dictionary).is_empty():
		restored["buff"] = {
			"buff_multiplier": float(buff_raw.get("buff_multiplier", 1.0)),
			"duration_turns": int(buff_raw.get("duration_turns", 1)),
		}
	var heal_raw: Variant = raw.get("heal", {})
	if heal_raw is Dictionary and not (heal_raw as Dictionary).is_empty():
		restored["heal"] = {
			"heal_mode": str(heal_raw.get("heal_mode", "fixed")),
			"heal_fixed_amount": int(heal_raw.get("heal_fixed_amount", 0)),
			"heal_percent": float(heal_raw.get("heal_percent", 0.0)),
		}
	return restored

## restore_clear_check_snapshot()専用: 保存されたclear_check_snapshotの
## action_sequenceは記録時点で既に解決済み形（"mode"を持たない、candidatesは
## 最終weightのみ）——ここでは型正規化だけを行い、mode解決は一切行わない
## （このファイル冒頭の理由コメント参照）。is_clear_check_currently_valid()
## はbattle_content_snapshot()（現在値、_normalized_action_sequence_for_
## snapshot()経由でslot_idを常に除去する）と_clear_check_success_snapshot
## （この関数の戻り値）を==で比較するため、slot_idはこちらでも同じく除去
## して比較対象から一貫して外す（旧pattern_idと同じ理由）。
func _normalized_clear_check_action_sequence(raw: Array) -> Array:
	var out: Array = []
	for slot_variant in raw:
		if not (slot_variant is Dictionary):
			continue
		var slot: Dictionary = slot_variant
		var kind := str(slot.get("kind", RBMActionPatternRules.SLOT_KIND_SKILL))
		var normalized := {
			"kind": kind,
			"conditions": _normalized_conditions(slot.get("conditions", [])),
			"condition_logic": str(slot.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)),
			"max_uses": int(slot.get("max_uses", RBMActionPatternRules.UNLIMITED_USES)),
		}
		if kind == RBMActionPatternRules.SLOT_KIND_RANDOM:
			var candidates: Array = []
			for candidate in slot.get("candidates", []):
				candidates.append({"skill_id": str(candidate.get("skill_id", "")), "weight": float(candidate.get("weight", 0.0))})
			normalized["candidates"] = candidates
		else:
			normalized["skill_id"] = str(slot.get("skill_id", ""))
		out.append(normalized)
	return out

func _restore_ally_allowed_skill_ids(raw: Dictionary) -> Dictionary:
	var out := {}
	for character_id in raw.keys():
		out[str(character_id)] = _typed_string_array(raw[character_id])
	return out

func _restore_ally_overrides(raw: Dictionary) -> Dictionary:
	# Repository validation rejects malformed v2 data before this point.  Keep
	# direct Draft restoration defensive as well: normalize only whitelisted
	# values through the same public setters, which also removes master-equal
	# values and produces the canonical sparse representation.
	var restored := ally_overrides
	ally_overrides = {}
	if not RBMDefinitionLoader.validate_ally_overrides(raw):
		return {}
	for character_id_variant in raw.keys():
		var character_id := str(character_id_variant)
		var character: Dictionary = raw[character_id_variant]
		var stats: Dictionary = character.get("stats", {})
		for field in stats.keys():
			set_ally_stat_override(character_id, str(field), stats[field])
		var skills: Dictionary = character.get("skills", {})
		for skill_id in skills.keys():
			var values: Dictionary = skills[skill_id]
			for field in values.keys():
				set_ally_skill_override(character_id, str(skill_id), str(field), values[field])
	var out := ally_overrides.duplicate(true)
	ally_overrides = restored
	return out

## §19: 保存されたDictionaryに個々のキーが欠けていても（旧stage・将来の
## キー追加どちらでも）常に「公開」をデフォルトとする——CHALLENGE_INFO_VISIBILITY_KEYS
## の6項目それぞれについて個別にbool()正規化する（保存されたraw自体を
## そのまま採用しない。余分な未知キーが混じっていても無視される——この
## 「既知キーだけを走査する」設計のおかげで、公開設定の最終修正前に生成
## された旧"party_details"付きの7項目形式データも、この1件だけ静かに
## 無視されて残り6項目は正しく復元される。追加の互換コードは不要だった）。
func _restore_challenge_info_visibility(raw: Dictionary) -> Dictionary:
	var out := {}
	for key in CHALLENGE_INFO_VISIBILITY_KEYS:
		out[key] = bool(raw.get(key, true))
	return out
