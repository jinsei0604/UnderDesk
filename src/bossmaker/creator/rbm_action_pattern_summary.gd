class_name RBMActionPatternSummary
extends RefCounted

## RPG BOSS MAKER — HARDCORE Creator「攻撃（action_sequence）」の表示用共通
## フォーマッタ。STEP3「攻撃」一覧・STEP6「最終確認」の両方がこれを使う——
## 同じ変換ロジックを2箇所に複製しない。ファイル名/クラス名は歴史的名残
## として変更していない（既存プロジェクト規約どおり、Godotのグローバル
## class_name登録・.uidの不要なchurnを避けるため）——中身は新方式「攻撃
## スロット」の語彙のみを持つ。
##
## RBMActionPatternRules自体（語彙の共有定数）・RBMBattle自体（判定ロジック
## 本体）は一切変更していない。ここは既存の公開定数（CONDITION_TYPE_LABELS
## 等）を読むだけの、完全に純粋な表示専用ヘルパー。
##
## 2026-09-05全面再設計: 瞬間条件（〜になった瞬間、発動後の2択）・発動確率・
## Cooldown・複数行動ステップの"→"チェーン表示は新仕様に一切存在しないため
## 削除した（RBMActionPatternRules冒頭コメント参照）。

## 通常条件のみ（瞬間条件のmatch枝は削除済み）。last_boss_skill条件のみ、
## 既存スキルを指し示す参照が本質的に必要（唯一の例外、実装前調査報告書の
## とおり）。
static func condition_line(condition: Dictionary, draft: RBMCreatorDraft) -> String:
	var condition_type := str(condition.get("type", ""))
	match condition_type:
		"hp_at_most":
			return "ボスHPが%d%%以下" % int(condition.get("percent", 0))
		"hp_at_least":
			return "ボスHPが%d%%以上" % int(condition.get("percent", 0))
		"hp_between":
			return "ボスHPが%d%%〜%d%%のあいだ" % [int(condition.get("percent_min", 0)), int(condition.get("percent_max", 0))]
		"turn_at":
			return "%dターン目" % int(condition.get("turn", 0))
		"turn_at_least":
			return "%dターン目以降" % int(condition.get("turn", 0))
		"turn_at_most":
			return "%dターン目まで" % int(condition.get("turn", 0))
		"turn_every_n":
			return "%dターンごと" % int(condition.get("n", 0))
		"turn_between":
			return "%d〜%dターン目のあいだ" % [int(condition.get("turn_min", 0)), int(condition.get("turn_max", 0))]
		"allies_at_most":
			return "攻略側の生存人数が%d人以下" % int(condition.get("count", 0))
		"allies_at_least":
			return "攻略側の生存人数が%d人以上" % int(condition.get("count", 0))
		"allies_exactly":
			return "攻略側の生存人数がちょうど%d人" % int(condition.get("count", 0))
		"character_alive":
			return "%sが生存している" % character_display_name(str(condition.get("character_id", "")), draft)
		"character_downed":
			return "%sが戦闘不能になっている" % character_display_name(str(condition.get("character_id", "")), draft)
		"last_boss_skill":
			return "前回使った行動が「%s」" % str(draft.find_skill(str(condition.get("skill_id", ""))).get("name", "?"))
		"last_received_skill":
			return "前回受けた行動が「%s」" % ally_skill_display_name(str(condition.get("skill_id", "")))
		"last_received_attribute":
			return "前回受けた攻撃の属性が%s" % attribute_label(str(condition.get("attribute", "")))
		"weak_hit":
			return "前回受けた攻撃が弱点だった"
		_:
			return str(RBMActionPatternRules.CONDITION_TYPE_LABELS.get(condition_type, condition_type))

## 条件要約の1行。条件が無ければ「条件：なし」を明示的に返す（§3/§27
## モックアップの一覧行は常に「条件：〜」を持つ仕様——旧実装は空文字＝
## 行自体を作らないだったが、新STEP3の一覧表示に合わせて既定文言化した）。
static func when_line(conditions: Array, condition_logic: String, draft: RBMCreatorDraft) -> String:
	if conditions.is_empty():
		return "条件：なし"
	var parts: Array = []
	for condition in conditions:
		parts.append(condition_line(condition, draft))
	var joiner := " または " if condition_logic == "OR" else " かつ "
	return "条件：%s" % joiner.join(parts)

## 使用回数の1行（§3/§27モックアップの「使用回数：〜」表示）。
static func uses_line(max_uses: int) -> String:
	if max_uses == RBMActionPatternRules.UNLIMITED_USES:
		return "使用回数：制限なし"
	return "使用回数：%d回" % max_uses

## §6の攻撃性能表示（"攻撃 / 単体 / 火 / 威力120"のような1行）。
## rbm_creator_step4_actions.gd（SIMPLE専用、§24により無改修対象）の
## _skill_detail_line()と同じフォーマットを踏襲するが、意図的に独立した
## 実装として持つ——SIMPLE側の既存コードへ触れるリスクを避けるため。
static func skill_performance_line(skill: Dictionary) -> String:
	var type := str(skill.get("type", ""))
	match type:
		"attack":
			var target_label := "単体" if str(skill.get("target", "single")) == "single" else "全体"
			var attribute_id := str(skill.get("attribute", "NEUTRAL"))
			var power := int(round(float(skill.get("atk_multiplier", 1.0)) * 100.0))
			return "攻撃 / %s / %s / 威力%d" % [str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id)), target_label, power]
		"self_heal":
			var mode_label := "最大HP割合" if str(skill.get("heal_mode", "fixed")) == "percent" else "固定値"
			if str(skill.get("heal_mode", "fixed")) == "percent":
				return "自己回復 / %s / 最大HPの%.1f%%" % [mode_label, float(skill.get("heal_percent", 0.0))]
			return "自己回復 / %s / HP%d" % [mode_label, int(skill.get("heal_fixed_amount", 0))]
		"atk_self_buff":
			return "ATK自己強化 / ATK×%.2f / %dターン" % [float(skill.get("buff_multiplier", 1.0)), int(skill.get("duration_turns", 1))]
		_:
			return type

## kind=="skill"ならそのスキル名、kind=="random"なら候補名一覧をまとめた
## 1行。§12確定: ランダム候補は「参照している作成済み攻撃の性能」だけを
## 名前として表示する——候補側の条件・使用回数という概念は存在しない。
static func slot_action_name(slot: Dictionary, draft: RBMCreatorDraft) -> String:
	if str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_RANDOM:
		var candidates: Array = slot.get("candidates", [])
		var names: Array = []
		for candidate in candidates:
			names.append(str(draft.find_skill(str(candidate.get("skill_id", ""))).get("name", "?")))
		return "ランダム攻撃（%s）" % (", ".join(names) if not names.is_empty() else "候補なし")
	return str(draft.find_skill(str(slot.get("skill_id", ""))).get("name", "?"))

## §3/§27の一覧行そのものを組み立てる材料を1つの辞書として返す（実際の
## UIノード構築は呼び出し側＝STEP3新UI/STEP6要約に委ねる——このクラスは
## 文字列だけを作る、純粋な表示ヘルパーという既存方針を踏襲）。
## kind=="random"の時のperformanceは候補名一覧、kind=="skill"の時は
## 参照している作成済み攻撃自身の性能行。
static func slot_summary(slot: Dictionary, draft: RBMCreatorDraft, index: int) -> Dictionary:
	var name_line: String
	var performance_line: String
	if str(slot.get("kind", "")) == RBMActionPatternRules.SLOT_KIND_RANDOM:
		name_line = "ランダム攻撃"
		var candidates: Array = slot.get("candidates", [])
		var names: Array = []
		for candidate in candidates:
			names.append(str(draft.find_skill(str(candidate.get("skill_id", ""))).get("name", "?")))
		performance_line = "候補：%s" % (", ".join(names) if not names.is_empty() else "なし")
	else:
		var skill := draft.find_skill(str(slot.get("skill_id", "")))
		name_line = str(skill.get("name", "?"))
		performance_line = skill_performance_line(skill)
	return {
		"ordinal": index + 1,
		"kind": str(slot.get("kind", RBMActionPatternRules.SLOT_KIND_SKILL)),
		"name": name_line,
		"performance": performance_line,
		"condition": when_line(slot.get("conditions", []), str(slot.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)), draft),
		"uses": uses_line(int(slot.get("max_uses", RBMActionPatternRules.UNLIMITED_USES))),
	}

# ---------------------------------------------------------------------------
# 味方スキル名解決（last_received_skill用）。
# 現在のパーティ選択(STEP4/旧STEP5)に関わらず、常に5キャラ固定マスターの
# 全スキルを対象にする。
# ---------------------------------------------------------------------------

static func all_known_ally_skill_ids() -> Array:
	var out: Array = []
	for character_id in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		var master := RBMDataLoader.load_dict(str(RBMDefinitionLoader.KNOWN_ALLY_PATHS[character_id]))
		for skill in master.get("skills", []):
			out.append(str(skill.get("id", "")))
	return out

static func ally_skill_display_name(skill_id: String) -> String:
	for character_id in RBMDefinitionLoader.KNOWN_ALLY_PATHS.keys():
		var master := RBMDataLoader.load_dict(str(RBMDefinitionLoader.KNOWN_ALLY_PATHS[character_id]))
		for skill in master.get("skills", []):
			if str(skill.get("id", "")) == skill_id:
				return "%s（%s）" % [str(skill.get("display_name", skill_id)), str(master.get("display_name", character_id))]
	return skill_id

static func character_display_name(character_id: String, draft: RBMCreatorDraft) -> String:
	var master := draft.master_character_def(character_id)
	return str(master.get("display_name", character_id)) if not master.is_empty() else character_id

static func attribute_label(attribute_id: String) -> String:
	return str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id))
