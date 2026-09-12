class_name RBMDefinitionLoader
extends RefCounted

## Resolves a BossBattleDefinition into battle-ready data for RBMBattle. See
## src/bossmaker/README.md. RBMBattle itself remained fully unmodified through
## Step 3's first pass; the 指定行動 (scripted boss actions) requirement then
## needed a small, additive change to rbm_battle.gd's resolve_turn() (two new
## SPD-ignoring loops plus a "replace"-aware boss action path) — no existing
## battle-logic path changed as a result. This loader's own job (validating
## and translating a Definition into the Dictionary shapes RBMBattle expects)
## is unaffected either way.
##
## Step 3 修正指示 (Codex re-review) corrected a design mistake from the first
## Step 3 pass: the confirmed spec (v0.1-B §2/§3) has NO shared "boss master
## data" concept at all — every boss stat (HP/ATK/SPD/weak/resist) and every
## boss skill (of the 3 confirmed author-creatable types: attack/self_heal/
## atk_self_buff) is created by the Definition's author, per fight. So unlike
## the ALLY side (still master-referenced — data_bossmaker/allies/*.json, the
## 5 fixed characters of v0.1-A/B), the boss side now lives ENTIRELY inside
## the BossBattleDefinition itself; there is nothing left in
## data_bossmaker/enemies/*.json for a boss_id to resolve against, so THIS
## loader no longer reads that directory at all. (data_bossmaker/enemies/
## test_boss.json is still read directly by tests/bossmaker/test_rbm_battle.gd
## itself — Step 2's own fixture, unrelated to Definition resolution — so it
## is not unreferenced project-wide. frost_sentinel.json genuinely has no
## remaining reference anywhere. Neither file has been deleted.)

const MIN_PARTY_SIZE := 1
const MAX_PARTY_SIZE := 4

const BOSS_HP_MIN := 1
const BOSS_HP_MAX := 1000000
const BOSS_ATK_MIN := 1
const BOSS_ATK_MAX := 9999
const BOSS_SPD_MIN := 1
const BOSS_SPD_MAX := 500

const VALID_ATTRIBUTES: Array[String] = ["FIRE", "ICE", "LIGHTNING", "WIND", "NEUTRAL"]

## 実機プレイ改善③ item8/11: 内部の属性ID（VALID_ATTRIBUTES、保存JSON・
## Definition・enum変換には一切影響しない）と、ユーザー向け表示用の日本語
## ラベルを分離する唯一の対応表。表示側（STEP2弱点/耐性ボタン・STEP3属性
## 選択・STEP7/CHALLENGE確認画面のスキル詳細・弱点/耐性表示）は全てこの
## 1つの辞書を参照する——同じ属性が画面ごとに異なる表記にならないよう
## （§11「表記の一貫性」）、ここ1箇所だけを直せば全画面へ反映される設計。
const ATTRIBUTE_LABELS := {
	"FIRE": "炎",
	"ICE": "氷",
	"LIGHTNING": "雷",
	"WIND": "風",
	"NEUTRAL": "無",
}
const VALID_SCRIPTED_TIMINGS: Array[String] = ["replace", "turn_start_interrupt", "turn_end_interrupt"]

## Step 3 修正指示 §9: known ally master content is resolved ONLY through this
## fixed id -> path map — a character_id is never concatenated into a path
## string to build the actual load target, so an id can never influence which
## file gets read beyond exactly matching one of these five literal keys.
const KNOWN_ALLY_PATHS := {
	"hero": "res://data_bossmaker/allies/hero.json",
	"butler": "res://data_bossmaker/allies/butler.json",
	"healer": "res://data_bossmaker/allies/healer.json",
	"samurai": "res://data_bossmaker/allies/samurai.json",
	"tank": "res://data_bossmaker/allies/tank.json",
}

## Phase 3: per-stage ally customization.  These are technical safety limits,
## not balance limits.  The public Creator and the final Definition validation
## both use this single whitelist/range source.
const ALLY_OVERRIDE_INT_MAX := 1000000000
const ALLY_OVERRIDE_MULTIPLIER_MAX := 1000.0
const ALLY_STAT_OVERRIDE_FIELDS: Array[String] = ["hp", "atk", "spd", "max_sp"]
const ALLY_SKILL_OVERRIDE_FIELDS_BY_EFFECT := {
	"damage": ["atk_multiplier", "sp_cost"],
	"heal": ["heal_amount", "sp_cost"],
	"sp_recover_single_no_self": ["sp_amount", "sp_cost"],
	"sp_recover_all_no_self": ["sp_amount", "sp_cost"],
	"buff_atk_self": ["buff_multiplier", "duration_turns", "sp_cost"],
	"buff_next_attack": ["buff_multiplier", "sp_cost"],
	"counter_stance": ["atk_multiplier", "sp_cost"],
	"guard_redirect": ["sp_cost"],
	"guard_boost": ["duration_turns", "new_rate", "sp_cost"],
	"party_damage_reduction": ["duration_turns", "reduction_rate", "sp_cost"],
}

static func _is_finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))

static func _is_integral_number(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) == floor(float(value))

static func ally_skill_override_fields(skill: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var allowed: Array = ALLY_SKILL_OVERRIDE_FIELDS_BY_EFFECT.get(str(skill.get("effect", "")), [])
	for field_variant in allowed:
		var field := str(field_variant)
		# A field may only be changed when this concrete master skill already owns
		# it.  The effect whitelist alone must never manufacture new semantics.
		if skill.has(field):
			out.append(field)
	return out

static func validate_ally_stat_override_value(field: String, value: Variant) -> bool:
	return ALLY_STAT_OVERRIDE_FIELDS.has(field) \
		and _is_integral_number(value) \
		and int(value) >= 1 \
		and int(value) <= ALLY_OVERRIDE_INT_MAX

static func validate_ally_skill_override_value(field: String, value: Variant) -> bool:
	match field:
		"atk_multiplier", "buff_multiplier":
			return _is_finite_number(value) and float(value) >= 0.0 and float(value) <= ALLY_OVERRIDE_MULTIPLIER_MAX
		"heal_amount", "sp_amount", "sp_cost":
			return _is_integral_number(value) and int(value) >= 0 and int(value) <= ALLY_OVERRIDE_INT_MAX
		"duration_turns":
			return _is_integral_number(value) and int(value) >= 1 and int(value) <= ALLY_OVERRIDE_INT_MAX
		"new_rate", "reduction_rate":
			return _is_finite_number(value) and float(value) >= 0.0 and float(value) <= 1.0
	return false

## Validates the saved Draft shape {character_id:{stats:{...},skills:{...}}}.
## Unknown ids/fields and non-canonical container types are rejected rather
## than ignored.  Integer-valued JSON floats (e.g. 10.0) are accepted because
## Godot's JSON parser represents JSON numbers as floats; 10.5 is rejected.
static func validate_ally_overrides(raw: Variant, errors: Array[String] = []) -> bool:
	if not (raw is Dictionary):
		errors.append("ally_overrides must be an object")
		return false
	var valid := true
	var overrides: Dictionary = raw
	for character_key in overrides.keys():
		if typeof(character_key) != TYPE_STRING or not KNOWN_ALLY_PATHS.has(str(character_key)):
			errors.append("ally_overrides has an unknown character_id: %s" % str(character_key))
			valid = false
			continue
		var character_id := str(character_key)
		var character_variant: Variant = overrides[character_key]
		if not (character_variant is Dictionary):
			errors.append("ally_overrides %s must be an object" % character_id)
			valid = false
			continue
		var character: Dictionary = character_variant
		for section_key in character.keys():
			if typeof(section_key) != TYPE_STRING or not ["stats", "skills"].has(str(section_key)):
				errors.append("ally_overrides %s has an unknown field: %s" % [character_id, str(section_key)])
				valid = false

		if character.has("stats"):
			if not (character["stats"] is Dictionary):
				errors.append("ally_overrides %s stats must be an object" % character_id)
				valid = false
			else:
				var stats: Dictionary = character["stats"]
				for field_key in stats.keys():
					var field := str(field_key)
					if typeof(field_key) != TYPE_STRING or not validate_ally_stat_override_value(field, stats[field_key]):
						errors.append("ally_overrides %s has an invalid stat %s" % [character_id, field])
						valid = false

		if character.has("skills"):
			if not (character["skills"] is Dictionary):
				errors.append("ally_overrides %s skills must be an object" % character_id)
				valid = false
				continue
			var master := RBMDataLoader.load_dict(str(KNOWN_ALLY_PATHS[character_id]))
			var master_skills := {}
			for skill_variant in master.get("skills", []):
				if skill_variant is Dictionary:
					var master_skill: Dictionary = skill_variant
					master_skills[str(master_skill.get("id", ""))] = master_skill
			var skill_overrides: Dictionary = character["skills"]
			for skill_key in skill_overrides.keys():
				var skill_id := str(skill_key)
				if typeof(skill_key) != TYPE_STRING or not master_skills.has(skill_id):
					errors.append("ally_overrides %s has an unknown skill_id: %s" % [character_id, skill_id])
					valid = false
					continue
				var skill_entry_variant: Variant = skill_overrides[skill_key]
				if not (skill_entry_variant is Dictionary):
					errors.append("ally_overrides %s skill %s must be an object" % [character_id, skill_id])
					valid = false
					continue
				var skill_entry: Dictionary = skill_entry_variant
				var master_skill: Dictionary = master_skills[skill_id]
				var allowed_fields := ally_skill_override_fields(master_skill)
				for field_key in skill_entry.keys():
					var field := str(field_key)
					if typeof(field_key) != TYPE_STRING or not allowed_fields.has(field) or not validate_ally_skill_override_value(field, skill_entry[field_key]):
						errors.append("ally_overrides %s skill %s has an invalid field %s" % [character_id, skill_id, field])
						valid = false
	return valid

static func resolve(definition: Dictionary) -> Dictionary:
	var errors: Array[String] = []

	var party_entries: Array = definition.get("party", [])
	if party_entries.size() < MIN_PARTY_SIZE or party_entries.size() > MAX_PARTY_SIZE:
		errors.append("party size must be between %d and %d (got %d)" % [MIN_PARTY_SIZE, MAX_PARTY_SIZE, party_entries.size()])

	var seen_character_ids := {}
	var ally_defs: Array[Dictionary] = []
	for entry_variant in party_entries:
		if not (entry_variant is Dictionary):
			errors.append("party entry is not an object")
			continue
		var entry: Dictionary = entry_variant
		var character_id := str(entry.get("character_id", ""))

		if seen_character_ids.has(character_id):
			errors.append("duplicate character_id in party: %s" % character_id)
			continue
		seen_character_ids[character_id] = true

		if not _is_safe_id(character_id):
			errors.append("character_id has an unsafe format: %s" % character_id)
			continue
		if not KNOWN_ALLY_PATHS.has(character_id):
			errors.append("unknown character_id: %s" % character_id)
			continue
		var master := RBMDataLoader.load_dict(KNOWN_ALLY_PATHS[character_id])
		if master.is_empty():
			errors.append("unknown character_id: %s" % character_id)
			continue
		ally_defs.append(_filter_ally_skills(master, entry, errors))

	var boss_entry: Dictionary = definition.get("boss", {})
	var boss_def := _resolve_author_boss(boss_entry, errors)

	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return {"ok": true, "ally_defs": ally_defs, "boss_def": boss_def}

static func start_battle(definition: Dictionary, rng_seed: int = 0) -> Dictionary:
	var resolved := resolve(definition)
	if not bool(resolved.get("ok", false)):
		return resolved
	var battle := RBMBattle.new(resolved["ally_defs"], resolved["boss_def"], rng_seed)
	return {"ok": true, "battle": battle}

## Step 3 修正指示 §9: rejects ids that could be used for path traversal. Ally
## lookup already never concatenates an id into a path at all (KNOWN_ALLY_PATHS
## is a fixed map, checked above), so this is a defense-in-depth format check
## on top of that, not the only thing standing between an id and a file path.
static func _is_safe_id(id: String) -> bool:
	if id.is_empty():
		return false
	if id.find("/") != -1 or id.find("\\") != -1 or id.find("..") != -1:
		return false
	return true

static func _filter_ally_skills(master: Dictionary, entry: Dictionary, errors: Array[String]) -> Dictionary:
	# Apply per-stage data only to a deep copy.  load_dict() currently returns a
	# fresh Dictionary, but this explicit copy is the invariant that protects the
	# fixed master even if loading is cached in the future.
	var resolved: Dictionary = master.duplicate(true)
	var master_skills: Array = resolved.get("skills", [])

	var local_overrides := {}
	if entry.has("stat_overrides"):
		local_overrides["stats"] = entry["stat_overrides"]
	if entry.has("skill_overrides"):
		local_overrides["skills"] = entry["skill_overrides"]
	if not local_overrides.is_empty():
		var character_id := str(master.get("id", ""))
		var wrapped := {character_id: local_overrides}
		var override_errors: Array[String] = []
		if validate_ally_overrides(wrapped, override_errors):
			var stats: Dictionary = local_overrides.get("stats", {})
			for field in stats.keys():
				resolved[str(field)] = int(stats[field])
			var skill_overrides: Dictionary = local_overrides.get("skills", {})
			for skill_variant in master_skills:
				if not (skill_variant is Dictionary):
					continue
				var skill: Dictionary = skill_variant
				var skill_id := str(skill.get("id", ""))
				if not skill_overrides.has(skill_id):
					continue
				var values: Dictionary = skill_overrides[skill_id]
				for field in values.keys():
					var field_name := str(field)
					if ["heal_amount", "sp_amount", "sp_cost", "duration_turns"].has(field_name):
						skill[field_name] = int(values[field])
					else:
						skill[field_name] = float(values[field])
		else:
			for message in override_errors:
				errors.append(message)

	var by_id := {}
	for skill in master_skills:
		by_id[str(skill.get("id", ""))] = skill
	var filtered: Array = []
	if entry.has("allowed_skill_ids"):
		if not (entry["allowed_skill_ids"] is Array):
			errors.append("character %s allowed_skill_ids must be an array" % str(master.get("id", "?")))
		else:
			var allowed: Array = entry["allowed_skill_ids"]
			for allowed_id_variant in allowed:
				if typeof(allowed_id_variant) != TYPE_STRING:
					errors.append("character %s allowed_skill_ids must contain strings" % str(master.get("id", "?")))
					continue
				var skill_id := str(allowed_id_variant)
				if not by_id.has(skill_id):
					errors.append("character %s does not own skill %s" % [str(master.get("id", "?")), skill_id])
					continue
				filtered.append(by_id[skill_id])
	else:
		filtered = master_skills.duplicate(true)
	resolved["skills"] = filtered
	return resolved

## Step 3 修正指示 §7/§8: the boss has no master data of its own any more --
## every field below comes from the Definition's own "boss" object, which the
## author fully authors. Out-of-range/unknown values are rejected outright
## (never clamped or defaulted to something plausible-looking).
static func _resolve_author_boss(boss_entry: Dictionary, errors: Array[String]) -> Dictionary:
	var boss_id := str(boss_entry.get("boss_id", ""))
	if not _is_safe_id(boss_id):
		errors.append("boss_id has an unsafe format: %s" % boss_id)

	var hp := _validate_ranged_stat(boss_entry, "hp", BOSS_HP_MIN, BOSS_HP_MAX, errors)
	var atk := _validate_ranged_stat(boss_entry, "atk", BOSS_ATK_MIN, BOSS_ATK_MAX, errors)
	var spd := _validate_ranged_stat(boss_entry, "spd", BOSS_SPD_MIN, BOSS_SPD_MAX, errors)
	# v0.1-C 多属性対応: a boss may have any number of weaknesses/resistances
	# (0 or more each) -- see _validate_optional_attribute_list_field below.
	# The single-value _validate_optional_attribute_field() call this replaced
	# stays intact and unchanged (it is still used for a skill's own single
	# attack attribute, which the confirmed spec does NOT extend to multiple).
	var weak_attributes := _validate_optional_attribute_list_field(boss_entry, "weak_attribute", "weak_attributes", errors)
	var resist_attributes := _validate_optional_attribute_list_field(boss_entry, "resist_attribute", "resist_attributes", errors)

	var skills_variant: Array = boss_entry.get("skills", [])
	var known_boss_skill_ids := {}
	var resolved_skills: Array = []
	for skill_variant in skills_variant:
		if not (skill_variant is Dictionary):
			errors.append("boss skill entry is not an object")
			continue
		var resolved_skill := _resolve_author_boss_skill(skill_variant, errors)
		if resolved_skill.is_empty():
			continue
		var skill_id := str(resolved_skill.get("id", ""))
		if known_boss_skill_ids.has(skill_id):
			errors.append("duplicate boss skill_id: %s" % skill_id)
			continue
		known_boss_skill_ids[skill_id] = true
		resolved_skills.append(resolved_skill)

	var normal_actions: Array = boss_entry.get("normal_actions", [])
	var resolved_candidates: Array = []
	for candidate_variant in normal_actions:
		if not (candidate_variant is Dictionary):
			errors.append("normal_actions entry is not an object")
			continue
		var candidate: Dictionary = candidate_variant
		var skill_id := str(candidate.get("skill_id", ""))
		if not known_boss_skill_ids.has(skill_id):
			errors.append("normal_actions references unknown boss skill_id: %s" % skill_id)
			continue
		var weight := float(candidate.get("weight", 1.0))
		# Step 3 最終修正指示 §3/§4: a negative weight has no meaningful
		# interpretation in a weighted-random pick and is always rejected --
		# unlike weight == 0 (a candidate that legitimately never gets picked
		# on its own, e.g. one only ever reachable via a scripted "replace"),
		# which stays valid.
		if weight < 0.0:
			errors.append("normal_actions weight must not be negative for %s: %f" % [skill_id, weight])
			continue
		resolved_candidates.append({"skill_id": skill_id, "weight": weight})

	# Having at least one normal_actions entry but a total weight of <= 0
	# would leave the boss with no reachable normal action at all on an
	# ordinary turn (Step 3 最終修正指示 §3/§4) -- unlike an EMPTY
	# normal_actions list (a boss that only ever acts via 指定行動, which is a
	# legitimate design and stays valid).
	if not resolved_candidates.is_empty():
		var total_weight := 0.0
		for candidate in resolved_candidates:
			total_weight += float(candidate["weight"])
		if total_weight <= 0.0:
			errors.append("normal_actions total weight must be greater than 0 when at least one candidate is configured (got %f)" % total_weight)

	var scripted_actions: Array = boss_entry.get("scripted_actions", [])
	var resolved_scripted: Array = []
	for scripted_variant in scripted_actions:
		if not (scripted_variant is Dictionary):
			errors.append("scripted_actions entry is not an object")
			continue
		var scripted: Dictionary = scripted_variant
		var skill_id := str(scripted.get("skill_id", ""))
		if not known_boss_skill_ids.has(skill_id):
			errors.append("scripted_actions references unknown boss skill_id: %s" % skill_id)
			continue
		var timing := str(scripted.get("timing", ""))
		if not VALID_SCRIPTED_TIMINGS.has(timing):
			errors.append("scripted_actions has an unknown timing: %s" % timing)
			continue
		if not scripted.has("turn"):
			errors.append("a scripted_actions entry is missing a turn number")
			continue
		var turn := int(scripted["turn"])
		# Step 3 最終修正指示 §3/§5: turns are 1-indexed (RBMBattle.current_turn
		# starts at 1) -- turn 0 or a negative turn can never actually occur,
		# so a scripted action targeting one is state-breaking, not merely an
		# unusual design choice.
		if turn < 1:
			errors.append("scripted_actions turn must be 1 or greater: %d" % turn)
			continue
		resolved_scripted.append({
			"turn": turn,
			"skill_id": skill_id,
			"timing": timing,
			"order": int(scripted.get("order", 0)),
		})

	# action_sequenceが未指定/空なら resolved_action_sequence も常に空配列
	# ——RBMBattle側は「resolved boss_def["action_sequence"]が空かどうか」
	# だけでSIMPLE経路（_pick_boss_normal_action()/scripted_actions replace）
	# とHARDCORE経路（1ターン1スロットのラウンドロビン評価器）を切り替える。
	# RBMCreatorDraft.creator_modeはこのDefinition解決レイヤーには一切現れ
	# ない（Creator UI表示専用のため、意図的にDefinitionへ含めていない——
	# RBMCreatorDraft.to_definition()参照）。
	var action_sequence: Array = boss_entry.get("action_sequence", [])
	var resolved_action_sequence := _resolve_action_sequence(action_sequence, known_boss_skill_ids, errors)

	# 覚醒（Awakening）: 通常actionsとは独立したトップレベルの特別イベント。
	# キー自体が無い（覚醒未設定、または覚醒実装以前の旧ボスデータ）なら
	# resolved_awakeningは常に空Dictionary——RBMBattle側は
	# "boss_def["awakening"]が空かどうか"だけで機構の有無を判定する。
	var resolved_awakening := _resolve_awakening(boss_entry, known_boss_skill_ids, errors)

	return {
		"id": boss_id,
		"display_name": str(boss_entry.get("boss_name", boss_id)),
		"hp": hp,
		"atk": atk,
		"spd": spd,
		# Singular keys kept EXACTLY as before (a single attribute-name String,
		# or null) for full backward compatibility with anything reading them
		# directly -- always just the first entry of the resolved list, never
		# an independent second source of truth (see _validate_optional_attribute_list_field).
		"weak_attribute": weak_attributes[0] if not weak_attributes.is_empty() else null,
		"resist_attribute": resist_attributes[0] if not resist_attributes.is_empty() else null,
		# v0.1-C: the full multi-attribute lists (each may be empty).
		"weak_attributes": weak_attributes,
		"resist_attributes": resist_attributes,
		"skills": resolved_skills,
		"normal_action_candidates": resolved_candidates,
		"scripted_actions": resolved_scripted,
		"action_sequence": resolved_action_sequence,
		"awakening": resolved_awakening,
	}

# ---------------------------------------------------------------------------
# HARDCORE Creator「攻撃（action_sequence）」の検証・解決
# ---------------------------------------------------------------------------
##
## 2026-09-05全面再設計: 旧「行動パターン」（action_patterns、複数条件・
## 複数行動ステップ・発動確率・Cooldownを持つ"パターン"）を廃止し、行動順に
## 並んだ「配置スロット」の単純な配列（action_sequence）へ全面移行した。
## 旧HARDCORE保存データとの互換性は無い（ユーザー確定仕様）——このセクション
## は新schemaのみを検証する。
##
## ここで受け取るaction_sequenceは既にRBMCreatorDraft側で「著作形→解決済み
## 形」への変換が済んでいる想定（ランダム攻撃の"mode"は既にweightへ解決済み、
## "mode"キー自体は存在しない——RBMCreatorDraft._resolved_action_slot_
## for_definition()参照）。既存のscripted_actions/normal_actionsと同じく、
## このレイヤーは「解決済み形の型・整合性チェック」だけを担当し、著作時
## だけの表現（heal_mode相当のもの）を意識しない。

## v0.1-B §9の全5固定味方キャラクターの全スキルidの和集合。「ボスが前回
## 受けたスキル」条件の妥当なスキルid一覧——このボスのDefinitionが実際に
## どのキャラクターをパーティに選んでいるかとは無関係に、ゲーム固定の味方
## ロースター全体から選べる（Creator UIのSTEP順序上、STEP3（攻撃編集）は
## STEP4（パーティ選択）より前に来るため、パーティがまだ決まっていない
## 時点でも条件を作成できる必要がある）。
static func _known_ally_skill_ids() -> Dictionary:
	var out := {}
	for character_id in KNOWN_ALLY_PATHS.keys():
		var master := RBMDataLoader.load_dict(str(KNOWN_ALLY_PATHS[character_id]))
		for skill in master.get("skills", []):
			out[str(skill.get("id", ""))] = true
	return out

## action_sequence全体（配列長そのもの）が安全上の上限を超えていないかを
## まず確認する——旧仕様は「1パターン内の行動数」という個別エントリ単位の
## 上限だったが、新schemaでは1スロット＝1攻撃で入れ子が無いため、上限は
## 配列全体の長さへそのまま対応する。
static func _resolve_action_sequence(raw: Array, known_boss_skill_ids: Dictionary, errors: Array[String]) -> Array:
	var resolved: Array = []
	if raw.size() > RBMActionPatternRules.MAX_ACTION_SEQUENCE_SLOTS:
		errors.append("action_sequence exceeds the max of %d slots (got %d)" % [RBMActionPatternRules.MAX_ACTION_SEQUENCE_SLOTS, raw.size()])
		return resolved
	var seen_slot_ids := {}
	var known_ally_skill_ids := {}
	var known_ally_skill_ids_loaded := false
	for slot_variant in raw:
		if not (slot_variant is Dictionary):
			errors.append("action_sequence entry is not an object")
			continue
		var slot: Dictionary = slot_variant

		var slot_id := str(slot.get("slot_id", ""))
		if not _is_safe_id(slot_id):
			errors.append("action_sequence entry has an unsafe slot_id: %s" % slot_id)
			continue
		if seen_slot_ids.has(slot_id):
			errors.append("duplicate action_sequence slot_id: %s" % slot_id)
			continue
		seen_slot_ids[slot_id] = true

		var conditions: Array = slot.get("conditions", [])
		if not (conditions is Array):
			errors.append("action_sequence %s has a non-array conditions" % slot_id)
			continue
		if conditions.size() > 1:
			var logic := str(slot.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC))
			if not RBMActionPatternRules.CONDITION_LOGIC_TYPES.has(logic):
				errors.append("action_sequence %s has an unknown condition_logic: %s" % [slot_id, logic])
				continue
		# 必要になるまで、5キャラクター分のマスターJSONを毎スロット再読込
		# しない（一度だけ読み、以後は同じDictionaryを使い回す）。
		if not known_ally_skill_ids_loaded:
			known_ally_skill_ids = _known_ally_skill_ids()
			known_ally_skill_ids_loaded = true
		var resolved_conditions: Variant = _resolve_conditions(slot_id, conditions, known_boss_skill_ids, known_ally_skill_ids, errors)
		if resolved_conditions == null:
			continue  # エラーは_resolve_conditions内で既に追加済み。

		var kind := str(slot.get("kind", ""))
		if not RBMActionPatternRules.SLOT_KINDS.has(kind):
			errors.append("action_sequence %s has an unknown kind: %s" % [slot_id, kind])
			continue

		var max_uses := int(slot.get("max_uses", RBMActionPatternRules.UNLIMITED_USES))
		if max_uses != RBMActionPatternRules.UNLIMITED_USES and max_uses < 0:
			errors.append("action_sequence %s max_uses must be -1 (unlimited) or 0 or greater: %d" % [slot_id, max_uses])
			continue

		var resolved_slot := {
			"slot_id": slot_id,
			"kind": kind,
			"conditions": resolved_conditions,
			"condition_logic": str(slot.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)),
			"max_uses": max_uses,
		}

		if kind == RBMActionPatternRules.SLOT_KIND_SKILL:
			var skill_id := str(slot.get("skill_id", ""))
			if not known_boss_skill_ids.has(skill_id):
				errors.append("action_sequence %s references unknown boss skill_id: %s" % [slot_id, skill_id])
				continue
			resolved_slot["skill_id"] = skill_id
		else:
			var resolved_candidates: Variant = _resolve_random_candidates(slot_id, slot.get("candidates", []), known_boss_skill_ids, errors)
			if resolved_candidates == null:
				continue  # エラーは_resolve_random_candidates内で既に追加済み。
			resolved_slot["candidates"] = resolved_candidates

		resolved.append(resolved_slot)
	return resolved

## 戻り値: 検証成功時は解決済みconditions配列、失敗時はnull（エラーは
## errorsへ追加済み）。GDScriptには「配列だが失敗を示すセンチネル」を
## 表現する良い方法が無いため、Variant戻り値でnullを失敗として使う
## （呼び出し側の`== null`チェックで判別）。旧仕様にあった瞬間条件タイプ
## （_instantサフィックス）はRBMActionPatternRules.NORMAL_CONDITION_TYPESが
## 既に持たなくなったため、下のmatchにその型が来ることはない（来ても
## 未知タイプとして最初のhas()チェックで拒否される）。
static func _resolve_conditions(slot_id: String, raw: Array, known_boss_skill_ids: Dictionary, known_ally_skill_ids: Dictionary, errors: Array[String]) -> Variant:
	var resolved: Array = []
	for condition_variant in raw:
		if not (condition_variant is Dictionary):
			errors.append("action_sequence %s has a non-object condition" % slot_id)
			return null
		var condition: Dictionary = condition_variant
		var condition_type := str(condition.get("type", ""))
		if not RBMActionPatternRules.NORMAL_CONDITION_TYPES.has(condition_type):
			errors.append("action_sequence %s has an unknown condition type: %s" % [slot_id, condition_type])
			return null
		match condition_type:
			"hp_at_most", "hp_at_least":
				var percent := float(condition.get("percent", -1.0))
				if percent < 0.0 or percent > 100.0:
					errors.append("action_sequence %s condition %s percent out of range [0,100]: %f" % [slot_id, condition_type, percent])
					return null
				resolved.append({"type": condition_type, "percent": percent})
			"hp_between":
				var percent_min := float(condition.get("percent_min", -1.0))
				var percent_max := float(condition.get("percent_max", -1.0))
				if percent_min < 0.0 or percent_min > 100.0 or percent_max < 0.0 or percent_max > 100.0 or percent_min > percent_max:
					errors.append("action_sequence %s condition hp_between has an invalid range: %f..%f" % [slot_id, percent_min, percent_max])
					return null
				resolved.append({"type": condition_type, "percent_min": percent_min, "percent_max": percent_max})
			"turn_at", "turn_at_least", "turn_at_most":
				var turn := int(condition.get("turn", 0))
				if turn < 1:
					errors.append("action_sequence %s condition %s turn must be 1 or greater: %d" % [slot_id, condition_type, turn])
					return null
				resolved.append({"type": condition_type, "turn": turn})
			"turn_every_n":
				var n := int(condition.get("n", 0))
				if n < 1:
					errors.append("action_sequence %s condition turn_every_n n must be 1 or greater: %d" % [slot_id, n])
					return null
				resolved.append({"type": condition_type, "n": n})
			"turn_between":
				var turn_min := int(condition.get("turn_min", 0))
				var turn_max := int(condition.get("turn_max", 0))
				if turn_min < 1 or turn_max < 1 or turn_min > turn_max:
					errors.append("action_sequence %s condition turn_between has an invalid range: %d..%d" % [slot_id, turn_min, turn_max])
					return null
				resolved.append({"type": condition_type, "turn_min": turn_min, "turn_max": turn_max})
			"allies_at_most", "allies_at_least", "allies_exactly":
				var count := int(condition.get("count", -1))
				if count < 0:
					errors.append("action_sequence %s condition %s count must not be negative: %d" % [slot_id, condition_type, count])
					return null
				resolved.append({"type": condition_type, "count": count})
			"character_alive", "character_downed":
				var character_id := str(condition.get("character_id", ""))
				if not KNOWN_ALLY_PATHS.has(character_id):
					errors.append("action_sequence %s condition %s has an unknown character_id: %s" % [slot_id, condition_type, character_id])
					return null
				resolved.append({"type": condition_type, "character_id": character_id})
			"last_boss_skill":
				var boss_skill_id := str(condition.get("skill_id", ""))
				if not known_boss_skill_ids.has(boss_skill_id):
					errors.append("action_sequence %s condition last_boss_skill references unknown boss skill_id: %s" % [slot_id, boss_skill_id])
					return null
				resolved.append({"type": condition_type, "skill_id": boss_skill_id})
			"last_received_skill":
				var ally_skill_id := str(condition.get("skill_id", ""))
				if not known_ally_skill_ids.has(ally_skill_id):
					errors.append("action_sequence %s condition %s references unknown ally skill_id: %s" % [slot_id, condition_type, ally_skill_id])
					return null
				resolved.append({"type": condition_type, "skill_id": ally_skill_id})
			"last_received_attribute":
				var attribute := str(condition.get("attribute", ""))
				if not VALID_ATTRIBUTES.has(attribute):
					errors.append("action_sequence %s condition %s has an unknown attribute: %s" % [slot_id, condition_type, attribute])
					return null
				resolved.append({"type": condition_type, "attribute": attribute})
			"weak_hit":
				resolved.append({"type": condition_type})
			_:
				# NORMAL_CONDITION_TYPESの網羅チェックを既に通過しているため
				# 到達しない——静的解析のための形式的なフォールバックのみ。
				errors.append("action_sequence %s has an unhandled condition type: %s" % [slot_id, condition_type])
				return null
	return resolved

## 戻り値: 検証成功時は解決済みcandidates配列、失敗時はnull。
static func _resolve_random_candidates(slot_id: String, raw_candidates: Array, known_boss_skill_ids: Dictionary, errors: Array[String]) -> Variant:
	if raw_candidates.is_empty():
		errors.append("action_sequence %s is a random slot with no candidates" % slot_id)
		return null
	var resolved_candidates: Array = []
	var total_weight := 0.0
	for candidate_variant in raw_candidates:
		if not (candidate_variant is Dictionary):
			errors.append("action_sequence %s has a non-object random candidate" % slot_id)
			return null
		var candidate: Dictionary = candidate_variant
		var skill_id := str(candidate.get("skill_id", ""))
		if not known_boss_skill_ids.has(skill_id):
			errors.append("action_sequence %s random candidate references unknown boss skill_id: %s" % [slot_id, skill_id])
			return null
		var weight := float(candidate.get("weight", 0.0))
		# normal_actionsの既存weightバリデーションと同じ方針（負の重みは
		# 意味を持たないため拒否、0はそのまま許容——「均等」変換後は常に1.0
		# なので実質manualステップのみがここへ到達する）。
		if weight < 0.0:
			errors.append("action_sequence %s random candidate weight must not be negative for %s: %f" % [slot_id, skill_id, weight])
			return null
		total_weight += weight
		resolved_candidates.append({"skill_id": skill_id, "weight": weight})
	if total_weight <= 0.0:
		errors.append("action_sequence %s random candidates total weight must be greater than 0 (got %f)" % [slot_id, total_weight])
		return null
	return resolved_candidates

# ---------------------------------------------------------------------------
# 覚醒（Awakening）の検証・解決
# ---------------------------------------------------------------------------
##
## 通常のaction_sequenceとは独立したトップレベルの特別イベント（ボス1体に
## つき最大1つ、1戦闘につき1回だけ発動、通常行動ループには含まれない——
## RBMBattle._maybe_trigger_awakening()参照）。条件の語彙・検証は
## action_sequenceスロットと完全に同一のため_resolve_conditions()をそのまま
## 再利用し、覚醒専用の別条件システムは持たない。buff/healも既存の
## atk_self_buff/self_heal skillと同じ形・同じ検証方針（buff_multiplier>=0・
## duration_turns>0・heal_amount>=0）を踏襲する。
##
## boss_entryに"awakening"キー自体が無ければ（覚醒未設定、または覚醒実装
## 以前の旧ボスデータ）常に空Dictionaryを返す——他の全フィールドと同じ
## 「フィールド欠落は安全なデフォルト」の慣習。
static func _resolve_awakening(boss_entry: Dictionary, known_boss_skill_ids: Dictionary, errors: Array[String]) -> Dictionary:
	if not boss_entry.has("awakening"):
		return {}
	if not (boss_entry["awakening"] is Dictionary):
		errors.append("awakening is not an object")
		return {}
	var awakening: Dictionary = boss_entry["awakening"]
	if awakening.is_empty():
		return {}

	var conditions: Array = awakening.get("conditions", [])
	if not (conditions is Array):
		errors.append("awakening has a non-array conditions")
		return {}
	if conditions.size() > 1:
		var logic := str(awakening.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC))
		if not RBMActionPatternRules.CONDITION_LOGIC_TYPES.has(logic):
			errors.append("awakening has an unknown condition_logic: %s" % logic)
			return {}
	var known_ally_skill_ids := _known_ally_skill_ids()
	var resolved_conditions: Variant = _resolve_conditions("awakening", conditions, known_boss_skill_ids, known_ally_skill_ids, errors)
	if resolved_conditions == null:
		return {}

	var resolved := {
		"conditions": resolved_conditions,
		"condition_logic": str(awakening.get("condition_logic", RBMActionPatternRules.DEFAULT_CONDITION_LOGIC)),
	}

	# 自己強化(buff)・HP回復(heal)はどちらも省略可能——「変身だけの覚醒」を
	# 許可するため、どちらのキーも無くて構わない（他の全フィールドと同じ
	# 「省略時は無効」慣習、"最低1つ設定必須"というvalidationは追加しない）。
	if awakening.has("buff") and awakening["buff"] is Dictionary and not (awakening["buff"] as Dictionary).is_empty():
		var buff: Dictionary = awakening["buff"]
		if not buff.has("buff_multiplier"):
			errors.append("awakening buff requires buff_multiplier")
			return {}
		if not buff.has("duration_turns"):
			errors.append("awakening buff requires duration_turns")
			return {}
		var buff_multiplier := float(buff["buff_multiplier"])
		if buff_multiplier < 0.0:
			errors.append("awakening buff buff_multiplier must not be negative: %f" % buff_multiplier)
			return {}
		var duration_turns := int(buff["duration_turns"])
		if duration_turns <= 0:
			errors.append("awakening buff duration_turns must be positive: %d" % duration_turns)
			return {}
		resolved["buff"] = {"buff_multiplier": buff_multiplier, "duration_turns": duration_turns}

	if awakening.has("heal_amount"):
		var heal_amount := float(awakening["heal_amount"])
		if heal_amount < 0.0:
			errors.append("awakening heal_amount must not be negative: %f" % heal_amount)
			return {}
		if heal_amount > 0.0:
			resolved["heal_amount"] = heal_amount
	return resolved

static func _validate_ranged_stat(entry: Dictionary, key: String, min_value: int, max_value: int, errors: Array[String]) -> int:
	if not entry.has(key):
		errors.append("boss %s is required" % key)
		return min_value
	var value := int(entry[key])
	if value < min_value or value > max_value:
		errors.append("boss %s out of range [%d,%d]: %d" % [key, min_value, max_value, value])
	return value

## For the boss's OWN weak/resist attribute — genuinely optional (a boss may
## have neither). Absence is not an error; an unrecognized value is.
static func _validate_optional_attribute_field(entry: Dictionary, key: String, errors: Array[String]) -> Variant:
	if not entry.has(key):
		return null
	var value := str(entry[key])
	if not VALID_ATTRIBUTES.has(value):
		errors.append("boss %s is not a known attribute: %s" % [key, value])
		return null
	return value

## v0.1-C 多属性対応: reads the boss's weak/resist attribute set for either
## Definition shape -- the new `<plural_key>` array (preferred, if present: a
## list of attribute-name Strings, each validated against VALID_ATTRIBUTES
## exactly as the single-value field always was) or the legacy single-value
## `<singular_key>` field (treated as a one-element list, per the confirmed
## backward-compatibility requirement: an old "weak_attribute":"FIRE"
## Definition must keep behaving exactly as it always has). Absence of both
## keys is not an error -- an empty list simply means "no weakness"/"no
## resistance", same as null always meant for the single-value field. Per the
## confirmed spec, this engine does not reject/arbitrate an attribute that
## happens to appear in both the weak and resist lists at once -- Creator-side
## authoring already prevents that, and inventing a new conflict rule here is
## explicitly out of scope.
static func _validate_optional_attribute_list_field(entry: Dictionary, singular_key: String, plural_key: String, errors: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if entry.has(plural_key):
		var raw: Array = entry[plural_key]
		for value_variant in raw:
			var value := str(value_variant)
			if not VALID_ATTRIBUTES.has(value):
				errors.append("boss %s is not a known attribute: %s" % [plural_key, value])
				continue
			out.append(value)
		return out
	if entry.has(singular_key):
		var value := str(entry[singular_key])
		if not VALID_ATTRIBUTES.has(value):
			errors.append("boss %s is not a known attribute: %s" % [singular_key, value])
			return out
		out.append(value)
	return out

## v0.1-B §3: attack / self_heal / atk_self_buff are the only 3 author-creatable
## boss skill types. Translates the author-facing schema into the exact
## internal skill-effect shape RBMBattle already understands and has since
## Step 2 ("attack"->"damage", "self_heal"->"heal", "atk_self_buff" stays
## "buff_atk_self" verbatim) -- no engine change was needed for this part.
static func _resolve_author_boss_skill(skill: Dictionary, errors: Array[String]) -> Dictionary:
	var skill_id := str(skill.get("skill_id", ""))
	if skill_id.is_empty():
		errors.append("a boss skill is missing skill_id")
		return {}
	var name := str(skill.get("name", skill_id))
	var skill_type := str(skill.get("type", ""))

	match skill_type:
		"attack":
			if not skill.has("target"):
				errors.append("boss skill %s (attack) requires a target" % skill_id)
				return {}
			var target_word := str(skill["target"])
			var target: String
			match target_word:
				"single":
					target = "ally_random_single"
				"all":
					target = "ally_all"
				_:
					errors.append("boss skill %s has an invalid target: %s" % [skill_id, target_word])
					return {}
			if not skill.has("attribute"):
				errors.append("boss skill %s (attack) requires an attribute" % skill_id)
				return {}
			var attribute: Variant = _validate_optional_attribute_field(skill, "attribute", errors)
			if attribute == null:
				return {}
			if not skill.has("atk_multiplier"):
				errors.append("boss skill %s (attack) requires atk_multiplier" % skill_id)
				return {}
			var atk_multiplier := float(skill["atk_multiplier"])
			# Step 3 最終修正指示 §3/§4: no author-facing upper bound is defined
			# yet, but a negative multiplier would make damage negative (i.e.
			# healing the target via an "attack") -- a state-breaking value,
			# not a legitimate design choice, so it is rejected outright.
			# atk_multiplier == 0 (a deliberately harmless attack) stays valid.
			if atk_multiplier < 0.0:
				errors.append("boss skill %s (attack) atk_multiplier must not be negative: %f" % [skill_id, atk_multiplier])
				return {}
			return {
				"id": skill_id, "display_name": name, "effect": "damage",
				"target": target, "attribute": attribute,
				"atk_multiplier": atk_multiplier,
			}
		"self_heal":
			if not skill.has("heal_amount"):
				errors.append("boss skill %s (self_heal) requires heal_amount" % skill_id)
				return {}
			var heal_amount := float(skill["heal_amount"])
			if heal_amount < 0.0:
				errors.append("boss skill %s (self_heal) heal_amount must not be negative: %f" % [skill_id, heal_amount])
				return {}
			return {
				"id": skill_id, "display_name": name, "effect": "heal",
				"heal_amount": heal_amount,
			}
		"atk_self_buff":
			if not skill.has("buff_multiplier"):
				errors.append("boss skill %s (atk_self_buff) requires buff_multiplier" % skill_id)
				return {}
			if not skill.has("duration_turns"):
				errors.append("boss skill %s (atk_self_buff) requires duration_turns" % skill_id)
				return {}
			var buff_multiplier := float(skill["buff_multiplier"])
			if buff_multiplier < 0.0:
				errors.append("boss skill %s (atk_self_buff) buff_multiplier must not be negative: %f" % [skill_id, buff_multiplier])
				return {}
			var duration_turns := int(skill["duration_turns"])
			# duration_turns <= 0 would mean the buff is active for zero or a
			# negative number of turns -- meaningless, unlike a legitimate 0x
			# multiplier, so this one IS rejected even at exactly 0.
			if duration_turns <= 0:
				errors.append("boss skill %s (atk_self_buff) duration_turns must be positive: %d" % [skill_id, duration_turns])
				return {}
			return {
				"id": skill_id, "display_name": name, "effect": "buff_atk_self",
				"buff_multiplier": buff_multiplier,
				"duration_turns": duration_turns,
			}
		_:
			errors.append("boss skill %s has an unknown type: %s" % [skill_id, skill_type])
			return {}
