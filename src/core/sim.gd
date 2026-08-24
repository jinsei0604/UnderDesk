class_name UDSim
extends RefCounted
## Deterministic tick-based simulation (§7.2). All state is a pure function
## of (initial seed, player commands, tick count), so offline batch calculation
## and realtime progression share this exact code path (§7.1-4).
##
## 2026-07-15 redesign: dig -> cave exploration + turn-based combat. Idle
## auto-battle clears trash mobs stage by stage (tick()); a stage flagged
## as a boss gate halts advancement (trash still farms for exp/coins) until
## the player manually wins a turn-based boss fight (player commands
## start_boss_fight/resolve_boss_round/flee_boss_fight).
##
## 2026-08-18 「新企画v1」フェーズ0/1: 段階加入(join_at_docs)を廃止し、party
## は new_game() の時点で主人公+全companion_defsが揃う。ボス戦にREWIND
## (§10)と部位破壊(§8)を追加: start_boss_fight()が突入直前のスナップ
## ショット(boss_checkpoint)を取り、全滅または任意コマンドで
## rewind_boss_fight()がそこへ戻す。boss_intel(§12: 見た攻撃/破壊した
## 部位)だけはREWINDの対象外で、セーブを跨いで残る「プレイヤーの知識」。

signal document_discovered(doc_id: String)
signal item_found(item_id: String)

var tick_count: int = 0
var inventory: Dictionary = {}  # resource id -> int ("gold" only, in practice)
var minions: Array[UDMinion] = []
var discovered_documents: Array[String] = []
## Treasure-chest collectibles owned: item id -> count. Items stack up
## to a per-rank cap (UD.ITEM_RANK_CAPS) so spares can feed the altar
## and the guild exchange. The candidate pool and rank map are injected
## like the enemy/stage DBs and not serialized.
var items: Dictionary = {}
var item_pool: Array[String] = []
var item_ranks: Dictionary = {}  # item id -> "Z".."D"
## Coins offered at the altar so far, +1 party attack (party_atk_bonus())
## per level.
var altar_level: int = 0
## Every story companion, present from turn one (新企画v1 §1, 2026-08-18:
## the staged join-by-document-count system is gone — new_game() fills
## this from every def in companion_defs immediately). Order determines
## party slot: minions[i+1] corresponds to companions[i].
## Definitions are injected like the enemy/stage DBs, not serialized.
var companions: Array[String] = []
var companion_defs: Array = []  # [{ id, name_key, join_at_docs, base_hp, hp_per_level, ... }]
## Unlock conditions per document id (data/documents "conditions" field).
## Injected like the enemy/stage DBs and not serialized. A document whose
## conditions are unmet stays hidden until they hold (§7.3).
var doc_conditions: Dictionary = {}  # doc id -> { min_docs, requires_* }
## Shop purchases: id -> { "level": int, "effect": String }.
var upgrades: Dictionary = {}
var _rng := RandomNumberGenerator.new()

## --- Cave exploration + combat state ---------------------------------
var stage_index: int = 1
var enemy_id: String = ""
var enemy_hp: int = 0
## Shared party EXP bank, filled automatically by idle combat. Spent
## explicitly by the player (level_up_companion()) on whichever party
## member they choose — sidesteps "who fought"/kill-credit entirely.
var exp_pool: int = 0
var boss_active: bool = false
var boss_hp: int = 0
## Which enemy the active boss fight is against. Needed because a fight
## is no longer always "the current band's boss": a cleared gate can be
## re-challenged from any later stage, where the current band has no
## boss_id of its own.
var boss_enemy_id: String = ""
## --- REWIND + body-part destruction (新企画v1 §8/§10, 2026-08-18) -----
## Snapshot captured once by start_boss_fight() (party HP/SP, boss_hp,
## boss_part_hp, RNG state) and restored verbatim by rewind_boss_fight().
## Empty outside of a boss fight.
var boss_checkpoint: Dictionary = {}
## REWINDⅡ（新企画v1仕様書v2「REWINDⅡ」§2/§9/§10/§40、2026-08-28）:
## boss_checkpointと全く同じ形式の、独立した第2のスナップショット枠——
## プレイヤー自身が味方コマンド入力待ち中に一度だけ指定する「戻り先」。
## boss_checkpoint（通常REWINDの戻り先＝常に戦闘開始時点）とは完全に
## 別のスロットであり、両者を混同・使い回すことは禁止（§40）——通常
## REWINDの戻り先が途中地点へ書き換わることは絶対に無い。
var mid_checkpoint: Dictionary = {}
## 1戦闘につき最大1回だけ設定できる（§9「一度設定したら変更不可」）——
## trueになったら、その戦闘中は二度と別地点へ上書きできない。
## start_boss_fight()でfalseへリセットされる以外は、通常REWIND
## （rewind_boss_fight()）では意図的に一切触れない（§11/§12/§40）——
## 「一度設定した事実」は通常REWINDを挟んでもその戦闘全体を通じて
## 保持される。
var mid_checkpoint_set: bool = false
## 1戦闘につき最大1回だけ使用できる（§10「一度使用したら再使用不可」）
## ——trueになったら、その戦闘中はREWINDⅡを二度と使用できない。
## mid_checkpoint_setと全く同じ理由で通常REWINDでは一切触れない
## （§11）。
var mid_checkpoint_used: bool = false
## Remaining HP of each of the active boss's body parts (data/enemies'
## optional "parts" array), part id -> int. Empty for a boss with no
## parts data — such a boss works exactly as it did before this system.
var boss_part_hp: Dictionary = {}
## Part ids reduced to 0 HP this attempt. Destroying a part only takes
## it out of boss_hp's separate main pool indirectly (via the boss's own
## action list honoring requires_part_intact, see _boss_choose_action) —
## a part's own HP is a distinct pool from boss_hp, never subtracted
## from it. Reset to [] by rewind_boss_fight(); see boss_intel below for
## what persists through a rewind instead.
var boss_parts_destroyed: Array[String] = []
## What the player has learned about a boss so far this save (新企画v1
## §12): boss id -> {"attacks_seen": Array[String], "parts_destroyed_
## seen": Array[String]}. Deliberately NOT part of boss_checkpoint — the
## one thing REWIND does not undo.
var boss_intel: Dictionary = {}
## REWINDⅡの解放状態（新企画v1仕様書v2「REWINDⅡ」§3/§4/§36、
## 2026-08-28）。恒久進行データ——boss_intelと同じくREWIND/REWINDⅡの
## どちらでも巻き戻さない対象だが、意味は違う: boss_intelは「このボスに
## ついて学んだ知識」、こちらは「REWINDⅡという能力自体を使ってよいか」
## というゲーム全体の解放フラグ。正式な解放条件（ストーリー上のタイミング）
## はまだ決まっていないため、ここでは何によっても自動ではtrueにならない
## ——set_rewind2_unlocked()を明示的に呼んだ場合のみ変化する（将来の正式
## な解放イベント・テスト・デバッグ操作の共通の唯一の入口、§4/§37「正式
## 条件を勝手に固定しない」）。
var rewind2_unlocked: bool = false
## Phase 6「防御」(2026-08-25, 新企画v1): unit ids currently guarding —
## "1行動を消費する代わりに、次の自分の行動まで受けるダメージを軽減する"
## という戦術コマンド専用の一時状態（§最重要）。単一のグローバルboolでは
## なく配列にしたのは、複数キャラクターが同時に独立して防御状態を持てる
## ようにするため（§16）——1個のboolでは「誰が防御中か」を表現できない。
## 付与は_resolve_one_action()の"guard"分岐、解除は同じ関数の冒頭（その
## ユニット自身の次の行動が実際に解決される直前——防御を再選択した場合も
## 含め、どんな行動であれ必ず一旦クリアしてから改めて評価する、§4）と、
## _apply_enemy_counter()でHPが0になった瞬間（§17、戦闘不能で防御解除）
## の2箇所。boss_part_hp等と同じ「戦闘中だけの一時状態」のため、
## boss_checkpoint（REWIND対象、§18）・to_dict/from_dict（戦闘途中セーブの
## 再開整合性、既存のboss_part_hp等と同じ理由）の両方に含める一方、
## boss_intelとは違いREWINDで戦闘開始時点（=誰も防御していない）へ確実に
## 戻る（checkpoint自身に含まれるため）。
var guarding_units: Array[int] = []
## HP/SPポーション追加 (2026-08-25、§19): item id -> 残り個数。ボス戦
## ごとに与えられる有限の戦闘リソース——UDItemDB由来の恒久所持品
## （sim.items）とは完全に別物で、通常のインベントリへは一切統合しない。
## guarding_units/boss_part_hpと同じ「戦闘中だけの一時状態」のため、
## start_boss_fight()で毎回UD.BATTLE_ITEM_START_COUNTへリセットされ
## （前の戦闘の残数は持ち越さない、§18）、boss_checkpoint（REWIND対象、
## §16）・to_dict/from_dict（戦闘途中セーブの再開整合性）にも含める。
var battle_item_counts: Dictionary = {}  # item id -> int
## Boss Action Set (新企画v1 D2、2026-08-25、§7-27): このボスの
## "action_set.steps"配列のうち、次に発火すべきstepのインデックス。
## 0 = 未着手（前回のセットは既に完了済み、または一度も始まっていない）
## ——次にこのボスの"通常のSPD順の番"が来たら、steps[0](予兆)から新しい
## セットが始まる(§26/§27)。1以上のときは"次にこのボスの番が来たら
## steps[この値]を発火する"ことを意味する。そのstepが実際に発火する
## タイミングは、直前のstepが解決した"その瞬間"にturn_order自体へ確定的
## にspliceされた割り込みトークンの位置が決める(_schedule_boss_action_
## set_interrupt()参照——ally行動が実際に起こるたびに数える遅延カウント
## ダウン方式ではない)。これにより、NEXT5(peek_next_actors)は追加コード
## 無しで、予兆が解決した"その瞬間"から正しい未来位置を反映する
## (§18-20: UI側が別に予測・再計算する経路は無い、turn_orderという同じ
## 実データをそのまま読むだけ)。guarding_units等と同じ「戦闘中だけの
## 一時状態」——boss_checkpoint(REWIND対象、常に0=中立値)・to_dict/
## from_dict(戦闘途中セーブの再開整合性)の両方に含める。
var boss_action_set_step: int = 0
## --- SPD turn order (新戦闘進行システム v1 §6/§10/§11/§12, 2026-08-24) --
## The fixed cycling order every living combatant takes their turn in,
## generated once by _generate_turn_order() at start_boss_fight() (SPD is
## static for the whole encounter — no mid-fight leveling is possible, see
## _capture_checkpoint's doc comment on why level itself is excluded from
## REWIND — so there is nothing to regenerate this against later). One
## token per combatant: "ally:<unit_id>" or "enemy:<enemy_id>". §11
## explicitly retires the old "round" concept (every living unit + one
## boss counter) in favor of this continuous cycling list — there is no
## separate "round number" anywhere in this system.
var turn_order: Array[String] = []
## Index into turn_order. Invariant, maintained by _normalize_turn_cursor()
## after every write to this var or to turn_order: always points at a
## currently-living combatant (never a dead one) except in the impossible
## case where nobody in turn_order survives (combat always ends via win/
## wipe before that can happen).
var turn_cursor: int = 0
## Every trash + boss kill, ever. Monotonic (unlike exp_pool, which drains
## on level-ups) — UI uses it to scroll the cave backdrop as a sense of
## forward progress each time an enemy falls.
var total_kills: int = 0
## The shop's weapon shelf: a single equipped slot, not an inventory —
## buying a new weapon replaces whichever one you had (a classic "next
## tier" weapon shop, no separate equip step).
var equipped_weapon_id: String = ""
var weapon_level: int = 0
var stages: UDStageDB
var enemies: UDEnemyDB
var skills: UDSkillDB
var weapons: UDShopDB
## HP/SPポーション追加 (2026-08-25): battle_items自体はskillsと同じ
## 「注入されるカタログ」——battle_item_countsが実際の所持数(戦闘ごとの
## 一時状態、下記宣言)。
var battle_items: UDBattleItemDB


static func new_game(
	p_enemies: UDEnemyDB,
	p_stages: UDStageDB,
	rng_seed: int,
	p_item_pool: Array[String] = [],
	p_companion_defs: Array = [],
	p_doc_conditions: Dictionary = {},
	p_item_ranks: Dictionary = {},
	p_skills: UDSkillDB = null,
	p_weapons: UDShopDB = null,
	p_battle_items: UDBattleItemDB = null,
) -> UDSim:
	var sim := UDSim.new()
	sim.enemies = p_enemies
	sim.stages = p_stages
	sim.skills = p_skills if p_skills != null else UDSkillDB.from_dicts([])
	sim.weapons = p_weapons if p_weapons != null else UDShopDB.from_dicts([])
	sim.battle_items = p_battle_items if p_battle_items != null else UDBattleItemDB.from_dicts([])
	sim.item_pool = p_item_pool
	sim.companion_defs = p_companion_defs
	sim.doc_conditions = p_doc_conditions
	sim.item_ranks = p_item_ranks
	sim._rng.seed = rng_seed
	sim.inventory[UD.RES_GOLD] = 0
	# 新企画v1 §1: 全5人が最初から仲間 — 段階加入(join_at_docs)は廃止。
	# companions は起動時に注入された companion_defs の並び順そのまま
	# (companion_1..4 = 円/ヴァルド/司馬燿/サユ)、party slot 0 が主人公。
	for def: Variant in p_companion_defs:
		sim.companions.append(str((def as Dictionary)["id"]))
	for i in sim.companions.size() + 1:
		sim.minions.append(sim._new_unit_at_level(i, 1))
	return sim


func advance(ticks: int) -> void:
	for i in ticks:
		tick()


func tick() -> void:
	tick_count += 1
	if not boss_active:
		_auto_battle()


## --- Growth: per-unit stats computed from level, not stored ----------

## Which growth curve a party slot uses: the protagonist (slot 0) has a
## fixed curve in UD.*; companions (slot >= 1) use their own data file.
## Falls back to UD.FALLBACK_GROWTH if the slot has no matching def yet
## (should not normally happen).
func _growth_def_for_unit(unit: UDMinion) -> Dictionary:
	if unit.id == 0:
		return {
			"base_hp": UD.PROTAGONIST_BASE_HP, "hp_per_level": UD.PROTAGONIST_HP_PER_LEVEL,
			"base_sp": UD.PROTAGONIST_BASE_SP, "sp_per_level": UD.PROTAGONIST_SP_PER_LEVEL,
			"base_atk": UD.PROTAGONIST_BASE_ATK, "atk_per_level": UD.PROTAGONIST_ATK_PER_LEVEL,
			"base_def": UD.PROTAGONIST_BASE_DEF, "def_per_level": UD.PROTAGONIST_DEF_PER_LEVEL,
			"base_spd": UD.PROTAGONIST_BASE_SPD, "spd_per_level": UD.PROTAGONIST_SPD_PER_LEVEL,
			"skills": UD.PROTAGONIST_SKILLS,
		}
	var companion_index := unit.id - 1
	if companion_index >= 0 and companion_index < companions.size():
		var companion_id := companions[companion_index]
		for def: Variant in companion_defs:
			if str((def as Dictionary)["id"]) == companion_id:
				return def as Dictionary
	return UD.FALLBACK_GROWTH


func unit_max_hp(unit: UDMinion) -> int:
	var g := _growth_def_for_unit(unit)
	return int(g["base_hp"]) + (unit.level - 1) * int(g["hp_per_level"])


func unit_max_sp(unit: UDMinion) -> int:
	var g := _growth_def_for_unit(unit)
	return int(g["base_sp"]) + (unit.level - 1) * int(g["sp_per_level"])


func unit_atk(unit: UDMinion) -> int:
	var g := _growth_def_for_unit(unit)
	return int(g["base_atk"]) + (unit.level - 1) * int(g["atk_per_level"])


func unit_def(unit: UDMinion) -> int:
	var g := _growth_def_for_unit(unit)
	return int(g["base_def"]) + (unit.level - 1) * int(g["def_per_level"])


## 新戦闘進行システム v1 §6/§7 (2026-08-24): SPDはunit_max_hp/unit_atk/
## unit_def同様レベル依存の計算値だが、既存3値と違い.get(...,0)で読む
## ——SPDは既存スキーマへ後から追加した新フィールドで、companion jsonが
## 元々の設計時から常にbase_hp等を持っていたのとは違い、SPDを知らない
## まま書かれた辞書（既存テストのローカルfixture等）がまだ残っている
## ため、欠けていたら0扱いにして安全側に倒す（鉄則3のd.get(key,default)
## 思想を、セーブ互換ではなくコード側スキーマ成長に適用したもの）。
func unit_spd(unit: UDMinion) -> int:
	var g := _growth_def_for_unit(unit)
	return int(g.get("base_spd", 0)) + (unit.level - 1) * int(g.get("spd_per_level", 0))


func unit_skills(unit: UDMinion) -> Array[String]:
	var g := _growth_def_for_unit(unit)
	var known: Array[String] = []
	for id: Variant in g.get("skills", []) as Array:
		known.append(str(id))
	return known


func _new_unit_at_level(id: int, level: int) -> UDMinion:
	var unit := UDMinion.create(id, level, 1, 1)
	unit.hp = unit_max_hp(unit)
	unit.sp = unit_max_sp(unit)
	return unit


func _unit_by_id(unit_id: int) -> UDMinion:
	for unit in minions:
		if unit.id == unit_id:
			return unit
	return null


## Shared ledger bonuses (shop upgrades, altar) added on top of every
## living unit's own level-derived ATK/DEF — same "base + upgrades +
## altar" shape dig_power() used to have.
func party_atk_bonus() -> int:
	var bonus := 0
	bonus += UDSim._effect_levels_in(upgrades, "atk_add")
	bonus += altar_level
	bonus += weapon_atk_bonus()
	return bonus


func weapon_atk_bonus() -> int:
	if equipped_weapon_id == "" or not weapons.has_good(equipped_weapon_id):
		return 0
	var def := weapons.get_good(equipped_weapon_id)
	return int(def["base_atk"]) + int(def["atk_per_level"]) * (weapon_level - 1)


func party_def_bonus() -> int:
	var bonus := 0
	bonus += UDSim._effect_levels_in(upgrades, "def_add")
	return bonus


func effective_atk(unit: UDMinion) -> int:
	return unit_atk(unit) + party_atk_bonus()


func effective_def(unit: UDMinion) -> int:
	return unit_def(unit) + party_def_bonus()


## Sum of every living party member's effective attack — the idle trash
## loop's damage-per-tick (deterministic, no rng).
func party_atk_total() -> int:
	var total := 0
	for unit in minions:
		if unit.hp > 0:
			total += effective_atk(unit)
	return total


## --- Idle auto-battle (tick-driven, risk-free trash combat) ----------

func _auto_battle() -> void:
	var stage := stages.stage_for_index(stage_index)
	if enemy_id == "":
		# Spawn only this tick: a freshly spawned enemy takes its first hit
		# next tick, so the idle view always has at least one tick to show
		# it at full HP instead of it dying invisibly the instant it appears
		# (which would otherwise happen for every enemy once party attack
		# outgrows its HP — an increasingly common case as the party levels).
		_spawn_trash(stage)
		return
	var def := enemies.get_enemy(enemy_id)
	# RPG_SYSTEM_DESIGN_v5 §5.1: idle-mode trash dies to a single hit
	# regardless of its stats — enemy HP/ATK/DEF only matter in manual
	# battles (they're designed as boss-fight companions). This keeps
	# idle pacing independent of the real chapter-scaled stat table
	# (hp 100 vs a low-level party would otherwise take minutes a kill).
	enemy_hp = 0
	_grant_kill_rewards(def, stage)
	enemy_id = ""
	if stages.is_boss_stage(stage_index):
		return  # Gate: halt here. Trash keeps farming exp/coins until the
		# player wins the manual boss fight (start_boss_fight/resolve_boss_round).
	stage_index += 1


func _spawn_trash(stage: Dictionary) -> void:
	var pool: Array = stage.get("trash_pool", [])
	if pool.is_empty():
		enemy_id = ""
		enemy_hp = 0
		return
	enemy_id = str(pool[_rng.randi_range(0, pool.size() - 1)])
	enemy_hp = int(enemies.get_enemy(enemy_id)["hp"])


func _grant_kill_rewards(def: Dictionary, stage: Dictionary) -> void:
	total_kills += 1
	exp_pool += int(def.get("exp", 0))
	inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + int(def.get("coins", 0))
	_roll_document(stage)
	_roll_special_find()


## --- Manual boss fight (turn-based, player commands) -----------------

## Opens a boss encounter: the current gate's boss when standing at an
## undefeated gate, otherwise a REMATCH against the most recent cleared
## gate's boss (repeatable at will - a rematch pays rewards again but
## never advances the stage, see resolve_boss_round). The party is healed
## to full and a REWIND checkpoint (§10) is captured at this exact
## moment — start_boss_fight() is always "full strength, attempt zero".
func start_boss_fight() -> bool:
	if boss_active:
		ensure_battle_item_defaults()
		return false
	var stage := stages.stage_for_index(stage_index)
	var boss_id := str(stage.get("boss_id", ""))
	if boss_id == "":
		boss_id = stages.last_boss_id_at_or_below(stage_index)
	if boss_id == "":
		return false
	_heal_party_full()
	boss_active = true
	boss_enemy_id = boss_id
	var def := enemies.get_enemy(boss_id)
	boss_hp = int(def["hp"])
	boss_part_hp = _initial_part_hp(def)
	boss_parts_destroyed = []
	guarding_units = []
	# HP/SPポーション追加 (2026-08-25、§3/§18): 毎回この戦闘専用に
	# フルへリセット——前の戦闘の残数は持ち越さない。
	battle_item_counts = {}
	for item_id in battle_items.all_ids():
		battle_item_counts[item_id] = UD.BATTLE_ITEM_START_COUNT
	# Boss Action Set (D2、2026-08-25、§26): 毎回この戦闘の最初から——
	# 前の戦闘で途中だったセットの進行は持ち越さない。
	boss_action_set_step = 0
	# 新戦闘進行システム v1 §10/§12 (2026-08-24): boss_active/boss_enemy_id
	# 確定後（_generate_turn_orderがboss_enemy_idを読むため）に生成。
	# everyone is alive right after _heal_party_full() above, so cursor 0
	# is already valid, but _normalize_turn_cursor() is called anyway for
	# defensive consistency with rewind_boss_fight()'s equivalent call.
	turn_order = _generate_turn_order()
	turn_cursor = 0
	_normalize_turn_cursor()
	boss_checkpoint = _capture_checkpoint()
	# REWINDⅡ (新企画v1仕様書v2「REWINDⅡ」§13、2026-08-28): 解放状態
	# (rewind2_unlocked)は恒久データなのでここでは触れない——「その戦闘で
	# 設定したか/使ったか」だけを毎回まっさらへ戻す。前の戦闘のmid_
	# checkpointを持ち越さない。
	mid_checkpoint = {}
	mid_checkpoint_set = false
	mid_checkpoint_used = false
	return true


## バグ修正 (2026-08-26、実機報告「ポーションを1個も持っていない」):
## この機能(HP/SPポーション)より前に保存されたセーブを読み込んだ場合
## など、battle_item_countsにまだ一度も登録されていないアイテムIDが
## 残っていることがある(古いd.get(...,{})はそのアイテムを単に含まない
## 空の辞書として復元されるため)。既に使用済みの他アイテムの残数には
## 一切触れず、"まだ数えられていない"アイテムIDだけを基本所持数へ
## 補充する——start_boss_fight()自身の"boss_activeなら早期return"分岐
## から呼ばれる(新しい戦闘としての初期化はしない、あくまで補充のみ)
## のに加え、main.gd側の"既にアクティブな戦闘へ戻るだけの場合は
## start_boss_fight()自体を呼ばない"経路(_on_fight_button())からも
## _show_boss_panel()経由で直接呼べるよう公開する。
func ensure_battle_item_defaults() -> void:
	for item_id in battle_items.all_ids():
		if not battle_item_counts.has(item_id):
			battle_item_counts[item_id] = UD.BATTLE_ITEM_START_COUNT


## Starting HP for each of a boss def's optional body parts (新企画v1
## §8, data/enemies "parts" array). {} for a boss with none.
func _initial_part_hp(def: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for entry: Variant in def.get("parts", []) as Array:
		var part := entry as Dictionary
		result[str(part["id"])] = int(part["hp"])
	return result


## Only the fight-scoped fields (HP/SP) per unit, keyed by str(unit.id) —
## deliberately NOT unit.to_dict() (which also carries level, a permanent-
## progress field REWIND must never touch, 新企画v1仕様書 v2 §11/§29-12).
##
## REWINDⅡ調査で発覚した2件のバグ修正（新企画v1仕様書v2「REWINDⅡ」
## §16/§18、2026-08-28）: この関数は元々「戦闘開始時点でしか呼ばれない」
## という前提のもと、boss_action_set_stepを現在値ではなく常に0のハード
## コードで保存し、boss_parts_destroyedを一切保存していなかった——戦闘
## 開始時点はどちらも必ず中立値（0・空配列）なので、通常REWINDにとっては
## 偶然正しく動いていただけだった。この関数を任意の時点（REWINDⅡの
## 「今この瞬間」）から呼べる汎用スナップショットへ格上げするため、両方
## とも実際の現在値をそのまま保存するよう修正——戦闘開始時点から呼んだ
## 場合は両方とも元々中立値のままなので、通常REWINDの結果は一切変わらない
## （§17で明示的に要求されている既存テストでの確認対象）。
func _capture_checkpoint() -> Dictionary:
	var unit_hp_sp: Dictionary = {}
	for unit in minions:
		unit_hp_sp[str(unit.id)] = {"hp": unit.hp, "sp": unit.sp}
	return {
		"unit_hp_sp": unit_hp_sp,
		"boss_hp": boss_hp,
		"boss_part_hp": boss_part_hp.duplicate(),
		# バグ修正 (2026-08-28、§16): 破壊済み部位も、その瞬間の実際の値を
		# そのまま保存する——戦闘開始時点は必ず空配列なので通常REWINDには
		# 影響しないが、途中の瞬間（REWINDⅡ）ではこれが無いと部位HPだけ
		# 戻り破壊フラグだけ残る、という矛盾した状態になっていた。
		"boss_parts_destroyed": boss_parts_destroyed.duplicate(),
		# Phase 6 (2026-08-25、§18): 誰も防御していない戦闘開始時点の状態
		# （常に空配列）を保存——boss_part_hp等と同じ扱い。
		"guarding_units": guarding_units.duplicate(),
		# HP/SPポーション追加 (2026-08-25、§16): 戦闘開始時点のフル所持数
		# （UD.BATTLE_ITEM_START_COUNT）を保存——boss_part_hp等と同じ扱い。
		"battle_item_counts": battle_item_counts.duplicate(),
		# バグ修正 (2026-08-28、§18): ハードコードされた0ではなく、その瞬間
		# の実際の進行度をそのまま保存する——戦闘開始時点は必ず0（誰も予兆
		# していない）なので通常REWINDには影響しないが、途中の瞬間では
		# これが無いと進行中のAction Setが常に未着手へ巻き戻ってしまう。
		"boss_action_set_step": boss_action_set_step,
		# 64-bit RNG state as strings (鉄則4): a raw int here would risk the
		# usual JSON-float corruption once this dict is serialized.
		"rng_seed": str(_rng.seed),
		"rng_state": str(_rng.state),
		# 新戦闘進行システム v1 §48 (2026-08-24): REWIND後にNEXT表示等の
		# 途中の行動順が残らないよう、順序そのもの（生成し直しても同じ
		# 結果になるが、checkpointの他フィールドと同じ「戦闘開始時点の
		# 値をそのまま保存・復元する」統一パターンに合わせた）とカーソル
		# 位置を両方保存する。
		"turn_order": turn_order.duplicate(),
		"turn_cursor": turn_cursor,
	}


## Leaves the boss encounter entirely without resolving it (no penalty):
## the party returns to idle-farming trash at the gate. Distinct from
## rewind_boss_fight() below, which restarts the same attempt instead of
## exiting it.
func flee_boss_fight() -> bool:
	if not boss_active:
		return false
	boss_active = false
	boss_hp = 0
	boss_enemy_id = ""
	boss_part_hp = {}
	boss_parts_destroyed = []
	guarding_units = []
	battle_item_counts = {}
	boss_action_set_step = 0
	boss_checkpoint = {}
	# REWINDⅡ (新企画v1仕様書v2「REWINDⅡ」§13、2026-08-28): 戦闘を離脱する
	# 以上、他の全ての戦闘専用フィールドと同じく持ち越さない——次の
	# start_boss_fight()でも改めてリセットされるが、boss_checkpoint等と
	# 同じ「離脱時点でクリアする」パターンに揃える。rewind2_unlockedは
	# 恒久データなのでここでは触れない。
	mid_checkpoint = {}
	mid_checkpoint_set = false
	mid_checkpoint_used = false
	turn_order = []
	turn_cursor = 0
	return true


## Shared restore body for REWIND and REWINDⅡ alike（新企画v1仕様書v2
## 「REWINDⅡ」§25、2026-08-28、rewind_boss_fight()から切り出し）:
## boss_checkpointから読むか mid_checkpoint から読むかだけが違う、全く
## 同じ手順——current_actor/NEXT5/防御/RNG決定論性のいずれも、この関数が
## turn_order・turn_cursor・guarding_units・_rngを正しく書き戻しさえ
## すれば、既存の導出ロジック（current_actor_token()・peek_next_actors()
## 等）から自動的に正しい状態になる（§26/§27で明示的に要求されている
## とおり、current_actor/NEXT5専用の保存領域は存在しない）。
func _restore_from_checkpoint(snapshot: Dictionary) -> void:
	# In-place HP/SP restore on the EXISTING minion objects, not a
	# minions.clear()+rebuild — a rebuilt-from-dict unit would only be as
	# safe as UDMinion.to_dict()/from_dict()'s field list, and that list
	# also includes level (see _capture_checkpoint()'s doc comment).
	# .get(...,{}) throughout tolerates a checkpoint from an older shape or
	# a unit id it doesn't recognize by simply leaving that unit's current
	# HP/SP untouched, rather than failing the whole rewind.
	var unit_hp_sp := snapshot.get("unit_hp_sp", {}) as Dictionary
	for unit in minions:
		var saved := unit_hp_sp.get(str(unit.id), {}) as Dictionary
		if not saved.is_empty():
			unit.hp = int(saved["hp"])
			unit.sp = int(saved["sp"])
	boss_hp = int(snapshot["boss_hp"])
	boss_part_hp = (snapshot["boss_part_hp"] as Dictionary).duplicate()
	# バグ修正 (2026-08-28、§16/§17): 無条件の空配列ではなく、スナップ
	# ショット自身が持つ値から復元する——戦闘開始時点のcheckpointは元々
	# 必ず空配列なので通常REWINDの結果は変わらない。旧shapeのcheckpoint
	# （このフィールドが導入される前に保存されたもの）は.get(...,[])で
	# 従来どおり空配列として扱う（鉄則3のd.get慣習）。
	boss_parts_destroyed = []
	for part_id: Variant in snapshot.get("boss_parts_destroyed", []) as Array:
		boss_parts_destroyed.append(str(part_id))
	# Phase 6 (2026-08-25、§18/§19): checkpoint自身がその時点の値
	# （戦闘開始時点なら常に空配列）を持つため、無条件に読み戻すだけで
	# 良い——.get(...,[])は旧shapeのcheckpoint（このシステムより前に
	# 保存されたもの）を許容するd.get慣習と同じ。
	guarding_units = []
	for unit_id: Variant in snapshot.get("guarding_units", []) as Array:
		guarding_units.append(int(unit_id))
	# HP/SPポーション追加 (2026-08-25、§16/§17): checkpoint自身がその時点
	# の所持数を持つため、無条件に読み戻すだけで良い——同じd.get慣習。
	battle_item_counts = {}
	for item_id: Variant in (snapshot.get("battle_item_counts", {}) as Dictionary).keys():
		battle_item_counts[str(item_id)] = int((snapshot["battle_item_counts"] as Dictionary)[item_id])
	# Boss Action Set (D2、2026-08-25、§32-33): checkpoint自身がその時点
	# の進行度を持つため、無条件に読み戻すだけで良い——同じd.get慣習。
	# これにより、予兆済み・味方1行動だけ消化済み、のようなセット進行の
	# 途中状態も正しくその時点へ戻る。
	boss_action_set_step = int(snapshot.get("boss_action_set_step", 0))
	_rng.seed = (snapshot["rng_seed"] as String).to_int()
	_rng.state = (snapshot["rng_state"] as String).to_int()
	# 新戦闘進行システム v1 §48 (2026-08-24): 「REWIND後にNEXT順が残らない
	# ように」——その時点の順序・カーソルへ戻す。snapshotに無い場合
	# （このシステムより前に保存されたcheckpoint、鉄則3のd.get慣習と
	# 同じ「旧shapeを許容する」考え方）は、その場でturn_orderを作り直す
	# ことで同じ効果（戦闘開始時相当の状態）を得るフォールバック。
	if snapshot.has("turn_order"):
		turn_order = []
		for token: Variant in snapshot["turn_order"] as Array:
			turn_order.append(str(token))
		turn_cursor = int(snapshot.get("turn_cursor", 0))
	else:
		turn_order = _generate_turn_order()
		turn_cursor = 0
	_normalize_turn_cursor()


## Rewinds the CURRENT boss encounter to the checkpoint start_boss_fight()
## captured: party HP/SP, boss HP, and part durability all return to what
## they were at the start of this attempt (新企画v1 §10 — REWIND always
## returns to the start of the fight, never a mid-fight moment). The
## encounter stays active (boss_active is untouched) — this restarts the
## same fight, it does not leave it, unlike flee_boss_fight() above. Two
## triggers call this exact same command: automatically from resolve_
## boss_round() on a party wipe, and the player's own "REWIND" command at
## any point mid-fight (deliberately bailing out of a bad plan costs
## nothing extra over an accidental wipe). What does NOT come back:
## boss_intel (what the player has learned this save, §12 — the one
## thing REWIND does not undo), REWINDⅡ's own mid_checkpoint/
## mid_checkpoint_set/mid_checkpoint_used（新企画v1仕様書v2「REWINDⅡ」
## §11/§12/§40 — 通常REWINDはmid_checkpoint関連の3フィールドに一切
## 触れない。REWINDⅡを設定・使用した事実は、通常REWINDを挟んでも
## その戦闘全体を通じて保持される）、and anything outside the fight
## itself (coins, items, documents, level).
func rewind_boss_fight() -> bool:
	if not boss_active or boss_checkpoint.is_empty():
		return false
	_restore_from_checkpoint(boss_checkpoint)
	return true


## REWINDⅡ（新企画v1仕様書v2「REWINDⅡ」§2/§10/§23、2026-08-28）:
## プレイヤーが事前にset_mid_checkpoint()で指定した1地点へ、1戦闘につき
## 1回だけ戻る上位REWIND——通常のrewind_boss_fight()と全く同じ復元手順
## （_restore_from_checkpoint）を、boss_checkpointではなくmid_checkpoint
## に対して適用するだけ（§40「同じチェックポイントを使い回さない」を
## 満たすため、2つの独立したスナップショットのどちらを渡すかだけが
## 違う）。使用後はmid_checkpoint_usedをtrueにし、この戦闘中は二度と
## 使用できなくする（§10）——mid_checkpoint_set自体は変更しない
## （§8「設定は最大1回」を維持したまま、"設定済みだが既に使用済み"と
## いう状態を表現する）。
func use_rewind2() -> bool:
	if not boss_active or not mid_checkpoint_set or mid_checkpoint_used:
		return false
	_restore_from_checkpoint(mid_checkpoint)
	mid_checkpoint_used = true
	return true


## REWINDⅡ（新企画v1仕様書v2「REWINDⅡ」§2/§9/§19/§20、2026-08-28）:
## 「今この瞬間」をREWINDⅡの戻り先として指定する——1戦闘につき最大1回
## だけ（§9、一度設定したら別地点へ上書きできない）。呼び出せるのは
## rewind2_unlocked（恒久の解放フラグ、§3/§4/§36）がtrueで、かつ現在の
## 行動順が生存中の味方を指している間だけ（§19/§20「味方current_actorの
## コマンド入力待ち中のみ」）——敵行動中・演出中・対象選択途中等では
## current_actor_token()は"ally:"では絶対に始まらない（敵の番、または
## 戦闘終了直後で行動順が空）ため、この1つのガードで自然に排除される。
## 「対象選択途中」「スキル一覧途中」等のUI階層状態自体はsim側に存在
## しない一時状態（main.gd側の_battle_phase）のため、実際の入力待ち
## タイミングでだけこのコマンドを呼ぶ責務はUI側にある——他の全プレイヤー
## コマンド（resolve_player_action等）と同じ、既存の役割分担のまま。
func set_mid_checkpoint() -> bool:
	if not boss_active or not rewind2_unlocked or mid_checkpoint_set:
		return false
	if not current_actor_token().begins_with("ally:"):
		return false
	mid_checkpoint = _capture_checkpoint()
	mid_checkpoint_set = true
	return true


## REWINDⅡの解放状態を変更する唯一の入口（新企画v1仕様書v2「REWINDⅡ」
## §3/§4/§37、2026-08-28）——正式なストーリー上の解放イベントはまだ
## 実装されていないため、テスト・将来の正式な解放条件・デバッグ操作の
## いずれもこの1関数を呼ぶ形に統一する（コード内に「◯◯を倒したら解放」
## のような正式条件を今回は一切固定しない、§4）。恒久データ（§36）——
## boss_active/boss_checkpoint等の戦闘専用フィールドとは無関係に、
## いつでも呼べる。
func set_rewind2_unlocked(unlocked: bool) -> void:
	rewind2_unlocked = unlocked


func _boss_def() -> Dictionary:
	return enemies.get_enemy(boss_enemy_id)


## 新戦闘進行システム v1 Phase 1 (2026-08-24): 「味方全員入力→まとめて
## resolve_boss_round」から「SPD順に1体ずつ即行動」への移行の土台として、
## この関数の内部を3つの再利用可能な部品(_resolve_one_action/_apply_boss_
## win/_apply_enemy_counter)へ切り出した。resolve_boss_round自身の外部
## 挙動・戻り値の形は一切変更していない(既存33件のテスト・main.gdの旧
## 呼び出し元は無改修のまま動く、後方互換のための「まとめて呼ぶ版」として
## 残置)——新しい単発API(resolve_player_action/resolve_enemy_action、下記)
## は、この関数とは別に、同じ3部品を単体で呼ぶだけの薄いラッパーとして
## 追加した。どちらの経路も同じ計算コードを通るため、ダメージ式の二重化
## は発生しない。
##
## Resolves exactly one round: every living unit's action (in order),
## then the boss's counter-attack on one target. `actions` is
## [{ "unit_id": int, "action": "attack"|"skill", "skill_id": String,
## "target_part": String }], one entry per living unit (units without an
## entry simply do nothing this round). `target_part` (新企画v1 §8,
## optional) names a body part from the boss's data; omitted or "" hits
## the boss's main HP exactly like before this system existed. Always
## resolves atomically — a party wipe here is handled by rewinding to
## the checkpoint within this same call (see below), never by leaving
## anything half-applied.
##
## The returned "log" (2026-07-19, added for the battle motion sequencer)
## is one entry per unit that actually acted this round, in `actions`
## order: {unit_id, action, skill_id, effect, target_type, target_id,
## target_part, amount}. It is a pure by-value report of what already
## happened — the round is still resolved atomically in this one call,
## nothing about it is deferred or replayable — so it needs no save-schema
## changes (it is a return value, not sim state) and does not change
## determinism: two sims fed identical actions from identical seeds
## produce identical logs because every field in it is derived from
## values already covered by the existing determinism tests. UI code uses
## it to *time* when an already-known result is revealed on screen (see
## main.gd), not to decide anything. A round that ends in a party wipe
## also carries "rewound": true — the sim has already rewound itself back
## to the checkpoint by the time this call returns, so boss_active/
## boss_hp/boss_part_hp already reflect the restarted attempt, not the
## moment of death.
func resolve_boss_round(actions: Array) -> Dictionary:
	if not boss_active:
		return {}
	var boss := _boss_def()
	var log: Array[Dictionary] = []
	for entry: Variant in actions:
		var log_entry := _resolve_one_action(entry as Dictionary, boss)
		if not log_entry.is_empty():
			log.append(log_entry)
	if boss_hp <= 0:
		_apply_boss_win(boss)
		return {"won": true, "lost": false, "log": log}
	var boss_counter := _apply_enemy_counter(boss)
	if _party_wiped():
		rewind_boss_fight()
		return {
			"won": false, "lost": true, "rewound": true,
			"log": log, "boss_counter": boss_counter,
		}
	return {"won": false, "lost": false, "log": log, "boss_counter": boss_counter}


## Resolves ONE party member's ONE action (attack or skill) — SP cost,
## damage/heal, body-part routing, log entry — and nothing else: no enemy
## reaction, no other unit is touched. This is the real Phase-1 primitive
## the new turn-based UI (Phase 3/4) will call directly; resolve_boss_round
## above is now just a thin "call this for every queued unit, then call
## resolve_enemy_action once" loop kept for backward compatibility.
## Returns {} on a bad call (fight inactive, unknown/dead unit) — mirrors
## resolve_boss_round's existing "{} means nothing happened" convention.
## On a kill, this already runs the exact same win handling
## resolve_boss_round used to inline (_apply_boss_win) and returns
## {"won":true, "log":[entry]} — the caller does not need to separately
## ask "did the boss just die?".
## 新戦闘進行システム v1 §22/§43 (2026-08-24): unit_idがcurrent_actor_
## token()と一致しない呼び出しは{}で拒否する——味方全員が同時に入力
## できた旧方式と違い、新方式は「今まさにその1体の番」以外の行動を
## 受け付けてはならない（誤ってUI側が順序を無視して呼んでも、行動順
## 自体が壊れることはなく、ただ何も起きない安全側の失敗になる）。
func resolve_player_action(
		unit_id: int, action: String, skill_id: String = "",
		target_id: int = -1, target_part: String = "") -> Dictionary:
	if not boss_active:
		return {}
	if current_actor_token() != "ally:%d" % unit_id:
		return {}
	var unit := _unit_by_id(unit_id)
	if unit == null or unit.hp <= 0:
		return {}
	var boss := _boss_def()
	var raw_action: Dictionary = {"unit_id": unit_id, "action": action, "skill_id": skill_id}
	if target_id != -1:
		raw_action["target_id"] = target_id
	if target_part != "":
		raw_action["target_part"] = target_part
	var log_entry := _resolve_one_action(raw_action, boss)
	if boss_hp <= 0:
		_apply_boss_win(boss)
		return {"won": true, "lost": false, "log": ([log_entry] if not log_entry.is_empty() else [])}
	_advance_turn_cursor()
	return {"won": false, "lost": false, "log": ([log_entry] if not log_entry.is_empty() else [])}


## Resolves the named enemy's ONE action — the boss picks and applies
## exactly one counter-attack, nothing else happens. `enemy_id` must be
## the active fight's boss (only one enemy exists today, see the class
## doc comment's §17 note in CLAUDE.md) — a mismatched or missing id is a
## no-op {} return, same convention as resolve_player_action. A party
## wipe here rewinds within this same call exactly as it always has
## (§10/§42, unchanged behavior — only the CALLER, not the sim, changes
## in later phases to defer showing this until the attack's own animation
## finishes, per the new 実装指示書 §44/§45; that UI-side sequencing is
## explicitly Phase 7's job, not this function's).
## Boss Action Set (D2、2026-08-25、§7-27): 実際の行動選択・turn_order
## の取り扱いは_resolve_boss_turn()へ委譲——action_setを持つボスと持た
## ないボス（既存の全ボス）の両方をここから区別なく呼べる。返り値は
## "boss_counter"(実ダメージ)/"boss_telegraph"(予兆、0ダメージ)/
## "boss_fizzle"(不発、0ダメージ)のいずれか1つに"won"/"lost"を足した形。
func resolve_enemy_action(enemy_id: String) -> Dictionary:
	if not boss_active or enemy_id != boss_enemy_id:
		return {}
	if current_actor_token() != "enemy:%s" % enemy_id:
		return {}
	var boss := _boss_def()
	var outcome := _resolve_boss_turn(boss)
	if _party_wiped():
		rewind_boss_fight()
		outcome["won"] = false
		outcome["lost"] = true
		outcome["rewound"] = true
		return outcome
	outcome["won"] = false
	outcome["lost"] = false
	return outcome


## Boss Action Set (D2、2026-08-25、§7-27): このボスの通常のSPD順の番
## (action_setが無ければ既存のランダム選択そのまま、あれば常にsteps[0]
## から新しいセットを開始する、§7-9)と、以前turn_orderへspliceした
## 割り込みスロットに実際に到達した番(boss_action_set_stepが0より大きい
## 場合)の両方をここで一本化して扱う——呼び出し元(resolve_enemy_action)
## からは区別を隠す。turn_order/turn_cursorの調整もここで完結させる
## （割り込みスロットは自分自身を消費してから元の形へ戻る、§26/§27）。
func _resolve_boss_turn(boss: Dictionary) -> Dictionary:
	var action_set := boss.get("action_set", {}) as Dictionary
	var steps := action_set.get("steps", []) as Array
	if boss_action_set_step > 0 and boss_action_set_step < steps.size():
		# 本来のSPD順の番ではなく、以前spliceした割り込みスロットに実際に
		# 到達した瞬間——このスロット自体を消費し、turn_orderを元の形へ
		# 戻す(§26/§27。今後のこのボスの通常ターンは、増えたぶんが既に
		# 除かれた元の並びへ自然に復帰する)。
		turn_order.remove_at(turn_cursor)
		if not turn_order.is_empty():
			turn_cursor = turn_cursor % turn_order.size()
		var step := steps[boss_action_set_step] as Dictionary
		var result := _resolve_action_set_step(step)
		if boss_action_set_step + 1 < steps.size():
			boss_action_set_step += 1
			# §18-20: 次のstepの割り込み位置も、今この瞬間に確定的に
			# schedule——turn_cursorは既にremove_atで「次に実際に来る
			# トークン」を指しているため、そこを起点にする。
			_schedule_boss_action_set_interrupt(
				turn_cursor, int((steps[boss_action_set_step] as Dictionary).get("gap", 0)))
		else:
			boss_action_set_step = 0
		_normalize_turn_cursor()
		return result
	if not steps.is_empty() and _action_set_start_condition_met(
			action_set.get("start_condition", {}) as Dictionary):
		# 通常のSPD順で到来した、このボスの本来の番——action_setを持つ
		# ボスは常にstep 0(予兆)から新しいセットを始める(§7-9)。ただし
		# start_conditionが満たされない場合はここへ入らず、下の通常行動
		# 選択(RNG)へフォールスルーする(§3-§8、2026-08-31)。
		var step := steps[0] as Dictionary
		var result := _resolve_action_set_step(step)
		if steps.size() > 1:
			boss_action_set_step = 1
			# §18-20: 予兆が解決した"この瞬間"に、次の割り込みの発生位置を
			# 今すぐturn_orderへ確定的にsplice——ally行動が実際に起こる
			# たびに数える遅延カウントダウンではない。これによりpeek_
			# next_actors()(NEXT5)は追加コード無しで、予兆解決の瞬間から
			# 正しい未来位置を反映する。turn_cursorはまだ予兆自身の位置
			# （ボス自身のトークン、"ally:"では始まらない）のままなので、
			# 呼び出し側が+1する必要はない——歩行ループが自然に次の
			# トークンから数え始める。
			_schedule_boss_action_set_interrupt(
				turn_cursor, int((steps[1] as Dictionary).get("gap", 0)))
		_advance_turn_cursor()
		return result
	# action_setを持たない全ての既存ボス、またはaction_setはあるが
	# start_conditionが満たされず今回は開始できないボス(§6: 棍棒action_set
	# を無理に始めず、既存の_boss_choose_action()自身のcandidateフィルタ
	# ——同じrequires_part_intactを見る——が選べる代替行動があればそれを
	# 選び、無ければ既存のフラットattackへ自動的にフォールバックする。
	# steps[0]（予兆）を一切発火しないため、turn_orderへの割り込みspliceも
	# 発生せず、NEXT5(peek_next_actors)には実際に起こらない行動が一切
	# 表示されない(§8、追加コード不要で構造的に満たされる)——従来通りの
	# ランダム行動選択(_boss_choose_action経由、RNGを消費する)。
	var boss_counter := _apply_enemy_counter(boss)
	_advance_turn_cursor()
	return {"boss_counter": boss_counter}


## Boss Action Set (D2、2026-08-25、§10-13/§18-20): start_indexから
## turn_orderを歩き、生存中の味方スロットをgap個数えた直後の位置へ
## 割り込みトークンを確定的にsplice——ally行動が実際に起こるたびに
## 数える遅延カウントダウン方式ではなく、今すぐ計算して即座に配置する
## ことで、NEXT5(peek_next_actors)が追加コード無しで「予兆が解決した
## その瞬間」から正しい未来位置を反映できるようにする(§18)。
## start_index自身がまだ生存中の味方トークンなら、それ自体を1件目として
## 数える(interrupt消費直後のturn_cursorがその条件に当たる——次のstepの
## gapは「これから来る味方の行動」を数えるべきで、直前のstepの位置を
## スキップして数え始めるべきではない)。start_indexがボス自身の
## トークン(予兆解決直後のturn_cursor)なら"ally:"で始まらないため、
## 単に最初の一歩で読み飛ばされるだけで同じ関数がそのまま両方の
## 呼び出しパターンを正しく処理する。攻撃/スキル/防御/どうぐの種類は
## 問わない(turn_orderの各要素はunit種別しか持たず、行動の種類自体を
## 記録しないため構造的に区別しようがない、§10-13/§21/§22)。KO済みの
## スロットは_token_is_living()が偽を返すため自動的に数えない(§12)。
func _schedule_boss_action_set_interrupt(start_index: int, gap: int) -> void:
	if turn_order.is_empty():
		return
	var index := posmod(start_index, turn_order.size())
	var remaining := gap
	var guard := 0
	while guard < turn_order.size() * 2 + 2:
		if turn_order[index].begins_with("ally:") and _token_is_living(turn_order[index]):
			remaining -= 1
			if remaining <= 0:
				break
		index = (index + 1) % turn_order.size()
		guard += 1
	var insert_at := index + 1
	turn_order.insert(insert_at, "enemy:%s" % boss_enemy_id)
	# バグ修正 (2026-08-25、headlessトレースで発見): 上のwalkはmodulo付きで
	# turn_cursorより手前(配列の物理インデックスとしては小さい値)へ折り
	# 返すことがある(例: cursor=3の位置からgap分だけ数えた結果、配列を
	# 一周してindex 0や1に戻ってくる)。この場合、挿入位置がまだ動いて
	# いないturn_cursorの"手前"に来てしまい、以後のturn_cursorが指す
	# 実際の要素が1つずれる（挿入によって配列全体が右へシフトするため）。
	# 挿入位置がturn_cursor以下なら、turn_cursor自体も+1して同じ論理要素
	# を指し続けるよう補正する——このボスの予兆自身の_advance_turn_
	# cursor()呼び出しがまだ後に続くため、ここで補正しておかないと予兆の
	# 直後の行動者が丸ごとズレる。
	if insert_at <= turn_cursor:
		turn_cursor += 1


## Boss Action Set 開始条件 (§3-§9、2026-08-31、実機報告「右腕破壊済みなの
## に予兆が発生する」への対応): action_setがこのボスの通常SPD順の番から
## "そもそも始まってよいか"を、steps[0](予兆)を発火する前に判定する——
## _resolve_action_set_step()のrequires_part_intact(§4/§5の"実行時判定"、
## 個々のstepが実際に発生する直前に確認、既存のまま無改修)とは別の、
## "開始時判定"（§5: 両方が必要——開始済みのセットが途中で部位を壊されて
## 不発になるのと、そもそも始まらないのは別の挙動）。cave_troll専用に
## しないため(§7)、"requires_part_intact"というキー名も個々のboss idや
## 部位名を一切知らない汎用チェックとして実装——data側(action_set.
## start_condition)がどの部位・どのキーを使うかを完全に決める。空dict
## (start_conditionキー自体が無いaction_set)は常に真を返し、既存の全て
## のaction_set（このキーを持たない）の挙動を変えない。将来HP閾値や状態
## フラグ等、別の条件種別を足す場合はこの関数へ新しいkeyのチェックを
## 追加するだけでよい(呼び出し元_resolve_boss_turn()はこの関数のシグ
## ネチャを変える必要が無い)。
func _action_set_start_condition_met(start_condition: Dictionary) -> bool:
	var requires := str(start_condition.get("requires_part_intact", ""))
	if requires != "" and boss_parts_destroyed.has(requires):
		return false
	return true


## Boss Action Set (D2、2026-08-25、§15/§23-24): 1つのstepを実際に発火
## する。"deals_damage":falseは予兆(0ダメージ、対象を一切叩かない)。
## "requires_part_intact"は既存の"actions"配列と全く同じ意味の任意項目
## ——ここで"今まさに"確認する(§24: 予兆時点の状態を固定保存せず、実際
## にこのstepが発生する直前の最新状態を見る。boss_parts_destroyedは
## プレイヤーの行動で刻々と変わりうるため、これが正しさの核心)。破壊
## 済みなら不発(0ダメージ)。RNGは一切消費しない(§30、id/powerとも
## data由来の固定値)。
func _resolve_action_set_step(step: Dictionary) -> Dictionary:
	var action := step.get("action", {}) as Dictionary
	var action_id := str(action.get("id", "attack"))
	if not bool(action.get("deals_damage", true)):
		_record_boss_action_seen(action_id)
		return {"boss_telegraph": {"action_id": action_id}}
	var requires := str(action.get("requires_part_intact", ""))
	if requires != "" and boss_parts_destroyed.has(requires):
		_record_boss_action_seen(action_id)
		return {"boss_fizzle": {"action_id": action_id}}
	var chosen := {"id": action_id, "power": int(action.get("power", 0))}
	return {"boss_counter": _apply_chosen_boss_action(chosen)}


## --- SPD turn order (新戦闘進行システム v1 §6/§10/§11/§12) --------------

## Builds the fixed SPD-descending cycle every combatant currently
## enrolled in the fight (every party unit, dead or alive at this exact
## moment, plus the active boss) takes turns in. Called once by
## start_boss_fight() — SPD does not change mid-fight (see turn_order's
## declaration comment), so this never needs to run again until the next
## encounter. Tie-break (実装指示書 §51, deterministic — never randomized):
## equal SPD favors an ally over the enemy; allies tie-break by ascending
## unit_id (protagonist=0 first, then companion_1..4 in join order — the
## same stable seating main.gd's UD.BATTLE_CARD_COMPANION_ORDER already
## uses); enemies tie-break by enemy_id string compare (今のところ敵は
## 常に1体なのでこの分岐へは到達しないが、複数敵対応時にそのまま機能
## するよう用意しておく).
func _generate_turn_order() -> Array[String]:
	var entries: Array[Dictionary] = []
	for unit in minions:
		entries.append({"token": "ally:%d" % unit.id, "spd": unit_spd(unit), "tiebreak": unit.id})
	if boss_active:
		var boss := _boss_def()
		entries.append({
			"token": "enemy:%s" % boss_enemy_id,
			"spd": int(boss.get("spd", 0)),
			"tiebreak": boss_enemy_id,
		})
	entries.sort_custom(_turn_entry_is_before)
	var order: Array[String] = []
	for entry in entries:
		order.append(str(entry["token"]))
	return order


## SPD降順。同値なら味方優先(§51)。味方同士はunit_id昇順、敵同士は
## enemy_id文字列比較。
func _turn_entry_is_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["spd"]) != int(b["spd"]):
		return int(a["spd"]) > int(b["spd"])
	var a_is_ally := str(a["token"]).begins_with("ally:")
	var b_is_ally := str(b["token"]).begins_with("ally:")
	if a_is_ally != b_is_ally:
		return a_is_ally
	if a_is_ally:
		return int(a["tiebreak"]) < int(b["tiebreak"])
	return str(a["tiebreak"]) < str(b["tiebreak"])


## Whose turn it is right now — "" outside an active fight or before
## turn_order has ever been generated. turn_cursor is maintained as an
## invariant (see its declaration) to always already point at a living
## combatant, so this never needs to skip anything itself.
func current_actor_token() -> String:
	if turn_order.is_empty():
		return ""
	return turn_order[turn_cursor]


func _token_is_living(token: String) -> bool:
	if token.begins_with("ally:"):
		var unit := _unit_by_id(int(token.substr(5)))
		return unit != null and unit.hp > 0
	if token.begins_with("enemy:"):
		return boss_active and token.substr(6) == boss_enemy_id and boss_hp > 0
	return false


## Restores turn_cursor's living-combatant invariant after turn_order or
## turn_cursor was just written from outside (start_boss_fight/
## rewind_boss_fight) — a no-op when the entry already there is alive
## (always true right after start_boss_fight(), since the party was just
## fully healed and the boss just spawned).
func _normalize_turn_cursor() -> void:
	if turn_order.is_empty():
		return
	if not _token_is_living(turn_order[turn_cursor]):
		var steps := 0
		while steps < turn_order.size():
			turn_cursor = (turn_cursor + 1) % turn_order.size()
			steps += 1
			if _token_is_living(turn_order[turn_cursor]):
				break
	_clear_guard_for_current_actor()


## Phase 6「防御」(2026-08-25、§4): 「次に自分の行動順を迎える"直前"まで
## 維持する」——効果は自分の番が実際に来た時点で既に切れている、という
## 読み(仕様書の例で言う「円の次の行動が始まるタイミングで解除」の
## タイミングそのもの)を採用し、current_actor_token()が確定する唯一の
## 場所であるこの関数の末尾で、その行動者(味方の場合のみ)の古い防御
## 状態を先取りしてクリアする——_advance_turn_cursor()経由の通常進行に
## 加え、start_boss_fight/rewind_boss_fight/from_dictがこの関数を直接
## 呼ぶ経路もまとめて1箇所でカバーする。これにより例えば下部UIの
## 「防御中」表示が、本人の黄色いcurrent_actor強調と同時に(まだ何も
## 選んでいないのに)出続けるという紛らわしい状態を作らない。
## _resolve_one_action()冒頭の同種のerase（そのユニット自身の行動解決の
## 直前）は、legacy resolve_boss_round()のようにこの関数を経由しない
## 経路への保険としてそのまま残す——二重に呼んでもArray.erase()は無害。
func _clear_guard_for_current_actor() -> void:
	var token := current_actor_token()
	if token.begins_with("ally:"):
		guarding_units.erase(int(token.substr(5)))


## Hands the turn to whoever is next in turn_order, skipping anyone who
## has since died (§33 「戦闘不能キャラクターは行動できないため、行動
## 回数としてもカウントしません」— a dead combatant's slot in the cycle is
## silently passed over, never given a turn of its own). Called by
## resolve_player_action/resolve_enemy_action only on their non-terminal
## path — a kill (won) or a wipe (rewound, which re-normalizes the cursor
## itself) both skip this on purpose.
func _advance_turn_cursor() -> void:
	if turn_order.is_empty():
		return
	turn_cursor = (turn_cursor + 1) % turn_order.size()
	_normalize_turn_cursor()


## Phase 5 (NEXT5、2026-08-25): current_actor_token()の"次の"count件を、
## 一切状態を変えずに(RNG不使用、turn_cursor不変)覗き見る。実際の戦闘
## 進行(_advance_turn_cursor/_normalize_turn_cursor)と全く同じ「死んだ
## combatantのスロットは silently skip する」ルールで歩くため、NEXT表示
## と実際の行動順は構造的に一致する——UI側が独自にSPDを再計算して予測
## する経路は無い(§18/§19/§20)。現在の行動者自身は含めない(turn_cursor
## の位置を跨いだ時点でループを止める)。生存者がcount未満しかいない
## 場合は無理に埋めず、実際に存在する分だけを返す(§26)。
func peek_next_actors(count: int) -> Array[String]:
	var result: Array[String] = []
	if turn_order.is_empty() or count <= 0:
		return result
	var index := turn_cursor
	var steps := 0
	while result.size() < count and steps < turn_order.size():
		index = (index + 1) % turn_order.size()
		steps += 1
		if index == turn_cursor:
			break
		if _token_is_living(turn_order[index]):
			result.append(turn_order[index])
	return result


## The exact per-unit "attack"/"skill" resolution resolve_boss_round used
## to inline in its actions loop — extracted so resolve_player_action can
## call the identical code for a single action. Returns {} for a dead/
## missing unit (the caller decides whether that's worth logging — the
## old loop just used `continue`, so both call sites treat {} as "skip").
func _resolve_one_action(action: Dictionary, boss: Dictionary) -> Dictionary:
	var unit := _unit_by_id(int(action["unit_id"]))
	if unit == null or unit.hp <= 0:
		return {}
	# Phase 6「防御」(2026-08-25、§4): 「防御は、次に自分の行動順を迎える
	# 直前まで維持する」——このユニット自身のどんな行動が実際に解決される
	# 直前でも必ず一旦クリアする(No-opなら何もしない、Array.eraseの既定
	# 挙動)。防御を再選択した場合は、下のmatch節が末尾で改めて追加する
	# ため、"防御を選び続ける"間は途切れず効果が続く。他ユニットの行動や
	# 敵の行動ではここを一切通らないため、他キャラの防御には影響しない
	# (§9)。
	guarding_units.erase(unit.id)
	var target_part := str(action.get("target_part", ""))
	match str(action.get("action", "attack")):
		"attack":
			var amount := maxi(1, effective_atk(unit) - int(boss["def"]))
			_apply_boss_damage(amount, target_part)
			return {
				"unit_id": unit.id, "action": "attack", "skill_id": "",
				"effect": "damage", "target_type": "enemy",
				"target_id": boss_enemy_id, "target_part": target_part,
				"amount": amount,
			}
		"skill":
			var skill_id := str(action.get("skill_id", ""))
			# バグ修正 (2026-08-25、実機報告「円がラピッドスラッシュを使え
			# る」への対応): _apply_skill()自身が既にunit_skills(unit).has(
			# skill_id)で所有権を確認しSPを消費させずamount 0を返すが、この
			# 関数はその判定結果を見ずに"成功した行動"としてログを組み立てて
			# しまっていた——UI側の入力管理にバグがあり誤った(unit_id,
			# skill_id)の組み合わせが届いた場合でも、simの入口でここを弾く
			# ことで「誰も持っていないスキルの行動ログ」自体が生成されない
			# ようにする（この行動は何も起きなかったものとして扱う——死亡
			# ユニットの早期returnと同じ扱い）。
			if not unit_skills(unit).has(skill_id):
				return {}
			var target_id := int(action.get("target_id", unit.id))
			var amount := _apply_skill(unit, skill_id, target_id, target_part)
			var skill_effect := ""
			var skill_target_type := "enemy"
			if skills.has_skill(skill_id):
				var skill := skills.get_skill(skill_id)
				skill_effect = str(skill.get("effect", "damage"))
				skill_target_type = str(skill.get("target", "enemy"))
			return {
				"unit_id": unit.id, "action": "skill", "skill_id": skill_id,
				"effect": skill_effect, "target_type": skill_target_type,
				"target_id": (target_id if skill_target_type == "ally" else boss_enemy_id),
				"target_part": (target_part if skill_target_type == "enemy" else ""),
				"amount": amount,
			}
		"guard":
			# Phase 6「防御」(2026-08-25、§1/§2/§25): 対象選択なし・SPD/行動順は
			# 一切変更しない・1行動を消費するだけ——ダメージ軽減は_apply_
			# enemy_counter()側でguarding_units.has()を見て適用する（§6、
			# 既存ATK/DEF計算そのものは変更しない）。
			guarding_units.append(unit.id)
			return {
				"unit_id": unit.id, "action": "guard", "skill_id": "",
				"effect": "guard", "target_type": "", "target_id": -1, "target_part": "",
				"amount": 0,
			}
		"item":
			# HP/SPポーション追加 (2026-08-25、§1/§9): 呼び出し元
			# (resolve_player_action)は3番目の位置引数を常に"skill_id"という
			# キーでaction辞書へ詰める——item使用時はこのスロットを"どの
			# アイテムを使うか"の運び役として再利用する（新しいパラメータを
			# 追加せず、既存のtarget_part同様「文脈によって意味が変わる」
			# 既存パターンを踏襲）。返り値のログ自体は"item_id"という専用
			# キー名で持つ（UI側の可読性のため、入力の運び方とは独立）。
			var item_id := str(action.get("skill_id", ""))
			if not battle_items.has_item(item_id) or int(battle_item_counts.get(item_id, 0)) <= 0:
				return {}
			var target_id := int(action.get("target_id", unit.id))
			var target := _unit_by_id(target_id)
			# §11: 戦闘不能キャラクターへは使用不可（蘇生しない）。
			if target == null or target.hp <= 0:
				return {}
			var item_def := battle_items.get_item(item_id)
			var heal_stat := str(item_def.get("heal_stat", "hp"))
			# heal_percentはdata/battle_items/*.json由来——コード側に回復率を
			# ハードコードしない（追加仕様§2）。
			var heal_percent := float(item_def.get("heal_percent", 0.0))
			var amount := 0
			var effect := ""
			if heal_stat == "hp":
				var max_hp := unit_max_hp(target)
				# 仕様変更 (2026-08-26、ユーザー指示「アイテムを必要として
				# いなくても使えるようにして。特殊条件でポーションを使う
				# をしなければいけないボスを作る予定」): 満タン相手でも
				# 使用自体は常に許可する——将来「HPが減っているかどうかに
				# 関わらず、ポーションを使うこと自体が特殊ボスの発動条件」
				# という仕組みを作る前提。旧§12の「満タンなら早期return」
				# は撤回（既にmini(max_hp,...)クランプがあるため、満タン
				# 相手に使うと単にamount=0になるだけで、行動自体・個数
				# 消費は正常に発生する——0回復の"floor 1"保証は"実際に
				# 回復の余地がある場合のみ"適用対象なので、満タン時は
				# そのまま素通りする）。
				var requested := maxi(1, int(round(float(max_hp) * heal_percent)))
				var before := target.hp
				target.hp = mini(max_hp, before + requested)
				amount = target.hp - before
				effect = "heal"
			elif heal_stat == "sp":
				var max_sp := unit_max_sp(target)
				var requested := maxi(1, int(round(float(max_sp) * heal_percent)))
				var before := target.sp
				target.sp = mini(max_sp, before + requested)
				amount = target.sp - before
				effect = "heal_sp"
			else:
				return {}
			battle_item_counts[item_id] = int(battle_item_counts.get(item_id, 0)) - 1
			return {
				"unit_id": unit.id, "action": "item", "skill_id": "", "item_id": item_id,
				"effect": effect, "target_type": "ally", "target_id": target_id,
				"target_part": "", "amount": amount,
			}
		_:
			return {}


## The exact post-actions win handling resolve_boss_round used to inline
## (reward grant, stage advance, boss deactivation) — extracted so
## resolve_player_action can run the identical sequence the instant ITS
## single action drops boss_hp to 0, instead of waiting for a whole
## round's worth of other units to act first.
func _apply_boss_win(boss: Dictionary) -> void:
	var stage := stages.stage_for_index(stage_index)
	_grant_kill_rewards(boss, stage)
	# Only an undefeated gate advances the stage; a rematch against an
	# already-cleared gate's boss farms rewards but stays put.
	if str(stage.get("boss_id", "")) == boss_enemy_id:
		stage_index += 1
	boss_active = false
	boss_hp = 0
	boss_enemy_id = ""
	boss_part_hp = {}
	boss_parts_destroyed = []
	guarding_units = []
	battle_item_counts = {}
	boss_action_set_step = 0
	boss_checkpoint = {}


## The exact "boss picks one action and hits its target" logic
## resolve_boss_round used to inline after the actions loop — extracted so
## resolve_enemy_action can call it standalone. Returns {} (not a target-
## less dict) when there is no living target to hit at all (should not
## normally happen — combat ends on a wipe — kept as a defensive no-op,
## matching the old `if target != null:` guard's effect).
func _apply_enemy_counter(boss: Dictionary) -> Dictionary:
	return _apply_chosen_boss_action(_boss_choose_action(boss))


## Boss Action Set (D2、2026-08-25): _apply_enemy_counter()の実際の
## ダメージ適用部分を、事前に選ばれたactionを受け取るだけの形へ抽出——
## 通常のランダム選択(_boss_choose_action、RNGを消費)経由でも、
## action_setの強攻撃step(RNG不使用、data駆動の固定id/power)経由でも
## 全く同じ計算(ATK/DEF・防御軽減・最低1フロア・KOで防御解除・boss_intel
## 記録)を1箇所だけに保つ。chosenは{"id":String, "power":int}の最小形。
func _apply_chosen_boss_action(chosen: Dictionary) -> Dictionary:
	var target := _boss_target()
	if target == null:
		return {}
	var counter_amount := maxi(1, int(chosen.get("power", 0)) - effective_def(target))
	# Phase 6「防御」(2026-08-25、§5/§6/§7): 既存のATK/DEF計算(上のcounter_
	# amount)が確定した"後"に適用する——既存計算そのものは無改修。軽減後、
	# 現在のダメージルールが持つ「最低1」フロア(maxi(1,...))を同じ形で
	# 再適用するだけで、新しい最低ダメージ仕様を発明していない(§7)。
	# プロトタイプとして50%固定(§5、将来調整予定)。
	if guarding_units.has(target.id):
		counter_amount = maxi(1, counter_amount / 2)
	target.hp = maxi(0, target.hp - counter_amount)
	# Phase 6 (2026-08-25、§17): 戦闘不能になった瞬間に防御状態を解除
	# ——将来の蘇生システムで戦闘不能前の防御が残らないようにする。
	if target.hp <= 0:
		guarding_units.erase(target.id)
	_record_boss_action_seen(str(chosen.get("id", "attack")))
	return {
		"target_unit_id": target.id, "amount": counter_amount,
		"action_id": str(chosen.get("id", "attack")),
	}


## Routes damage to a body part's own durability pool when a valid,
## not-yet-destroyed part is targeted (新企画v1 §8) — otherwise (no part
## chosen, an already-destroyed part, or an unknown part id) it hits the
## boss's main HP exactly like before this system existed. A part and
## boss_hp are separate pools: destroying every part does not by itself
## reduce boss_hp — only boss_hp reaching 0 wins the fight (§7); parts
## instead change what the boss can still DO (see _boss_choose_action).
func _apply_boss_damage(amount: int, target_part: String) -> void:
	if target_part != "" and boss_part_hp.has(target_part) \
			and not boss_parts_destroyed.has(target_part):
		boss_part_hp[target_part] = int(boss_part_hp[target_part]) - amount
		if int(boss_part_hp[target_part]) <= 0:
			boss_part_hp[target_part] = 0
			boss_parts_destroyed.append(target_part)
			_record_boss_part_destroyed(target_part)
		return
	boss_hp -= amount


## Picks one of the boss's available actions this round (新企画v1 §8),
## honoring requires_part_intact gating against boss_parts_destroyed — an
## action naming a part the player has already broken is off the
## candidate list this and every future round of this attempt. A boss
## with no "actions" data in its def (every boss except the ones this
## system has been added to so far) falls back to a single unnamed
## "attack" action using its flat atk stat, unaffected by this system.
func _boss_choose_action(boss: Dictionary) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for entry: Variant in boss.get("actions", []) as Array:
		var action := entry as Dictionary
		var requires := str(action.get("requires_part_intact", ""))
		if requires != "" and boss_parts_destroyed.has(requires):
			continue
		candidates.append(action)
	if candidates.is_empty():
		return {"id": "attack", "power": int(boss.get("atk", 0))}
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _boss_intel_entry(boss_id: String) -> Dictionary:
	if boss_intel.has(boss_id):
		return boss_intel[boss_id] as Dictionary
	return {"attacks_seen": [], "parts_destroyed_seen": []}


## Only named (data-driven) actions are worth recording — the universal
## flat-atk fallback ("attack") is not information about this specific
## boss.
func _record_boss_action_seen(action_id: String) -> void:
	if action_id == "" or action_id == "attack":
		return
	var entry := _boss_intel_entry(boss_enemy_id)
	var seen := entry["attacks_seen"] as Array
	if not seen.has(action_id):
		seen.append(action_id)
	boss_intel[boss_enemy_id] = entry


func _record_boss_part_destroyed(part_id: String) -> void:
	var entry := _boss_intel_entry(boss_enemy_id)
	var seen := entry["parts_destroyed_seen"] as Array
	if not seen.has(part_id):
		seen.append(part_id)
	boss_intel[boss_enemy_id] = entry


## target_id is the ally to heal for an "ally"-target skill (defaults to
## the caster — self-heal — when omitted, matching the behavior before
## ally targeting existed). target_part (新企画v1 §8) only matters for a
## "damage" skill — see _apply_boss_damage(). Returns the amount of
## damage/healing actually applied (0 for an insufficient-SP no-op or an
## effect with no numeric result yet, e.g. buff_atk/buff_def/debuff/
## special) — 2026-07-19, added so resolve_boss_round's log can report a
## real number for the motion sequencer to show instead of just
## "something happened".
func _apply_skill(
		unit: UDMinion, skill_id: String, target_id: int = -1, target_part: String = "") -> int:
	if not skills.has_skill(skill_id) or not unit_skills(unit).has(skill_id):
		return 0
	var skill := skills.get_skill(skill_id)
	# sp_cost: null means "not balanced yet" (RPG_SYSTEM_DESIGN_v5 skills
	# not yet given a number) — treated as free rather than guessing a
	# figure; once real data supplies a cost this reads it normally.
	var raw_cost: Variant = skill.get("sp_cost", 0)
	var cost := 0 if raw_cost == null else int(raw_cost)
	if unit.sp < cost:
		return 0
	unit.sp -= cost
	var power := int(skill.get("power", 0))
	match str(skill.get("effect", "damage")):
		"damage":
			var amount := maxi(1, power - int(_boss_def()["def"]))
			_apply_boss_damage(amount, target_part)
			return amount
		"heal":
			var target := _unit_by_id(target_id) if target_id != -1 else unit
			if target == null or target.hp <= 0:
				target = unit
			# Same floor as the damage branch above, applied to "power"
			# instead of "power - def" (heals have no defense to net
			# against): most companion heals still have no "power" set
			# (RPG_SYSTEM_DESIGN_v5 numbers pending), and healing for 0 is
			# indistinguishable from the skill silently failing. This is a
			# floor, not an invented balance number — a skill with a real
			# power value is unaffected (maxi(1, 10) == 10).
			# The RETURNED amount is the actual hp delta after clamping to
			# max, not the requested/floored amount — a target already at
			# full hp has nothing to gain, and the caller (the boss-fight UI)
			# used to show a phantom "+1" heal popup on a full-hp ally
			# because it trusted the pre-clamp floor value instead of what
			# actually changed (2026-07-26 user report).
			var before_hp := target.hp
			var requested := maxi(1, power)
			target.hp = mini(unit_max_hp(target), before_hp + requested)
			return target.hp - before_hp
		_:
			# buff_atk / buff_def / debuff / special intentionally left as
			# a future extension — no lasting per-encounter modifier state
			# exists yet, so these skills consume SP and otherwise no-op.
			return 0


## Target for the boss's counter-attack: the lowest-HP living unit (reads
## as the boss "finishing off" whoever is most hurt).
func _boss_target() -> UDMinion:
	var target: UDMinion = null
	for unit in minions:
		if unit.hp <= 0:
			continue
		if target == null or unit.hp < target.hp:
			target = unit
	return target


func _party_wiped() -> bool:
	for unit in minions:
		if unit.hp > 0:
			return false
	return true


func _heal_party_full() -> void:
	for unit in minions:
		unit.hp = unit_max_hp(unit)
		unit.sp = unit_max_sp(unit)


## --- Leveling (player command: spends the shared exp_pool) -----------

static func exp_cost_for_level(level: int) -> int:
	return int(round(UD.EXP_BASE * pow(UD.EXP_MULT, level - 1)))


## Spends the banked exp_pool to raise one party member a level, fully
## healing them. Returns false when unaffordable or the unit is unknown.
func level_up_companion(unit_id: int) -> bool:
	var unit := _unit_by_id(unit_id)
	if unit == null:
		return false
	var cost := UDSim.exp_cost_for_level(unit.level)
	if exp_pool < cost:
		return false
	exp_pool -= cost
	unit.level += 1
	unit.hp = unit_max_hp(unit)
	unit.sp = unit_max_sp(unit)
	return true


func upgrade_level(id: String) -> int:
	if not upgrades.has(id):
		return 0
	return int((upgrades[id] as Dictionary).get("level", 0))


static func upgrade_cost(good: Dictionary, level: int) -> int:
	return int(round(float(good["base_cost"]) * pow(float(good["cost_mult"]), level)))


## Buys one level of a shop good. Returns false when maxed or unaffordable.
func buy_upgrade(good: Dictionary) -> bool:
	var id := str(good["id"])
	var level := upgrade_level(id)
	if level >= int(good["max_level"]):
		return false
	var cost := UDSim.upgrade_cost(good, level)
	if int(inventory.get(UD.RES_GOLD, 0)) < cost:
		return false
	inventory[UD.RES_GOLD] = int(inventory[UD.RES_GOLD]) - cost
	var effect := str(good.get("effect", ""))
	upgrades[id] = {"level": level + 1, "effect": effect}
	return true


## --- Weapon shop (buy replaces the equipped weapon; upgrade levels it) -

static func weapon_upgrade_cost(weapon: Dictionary, level: int) -> int:
	return int(round(
		float(weapon["upgrade_base_cost"]) * pow(float(weapon["upgrade_cost_mult"]), level)
	))


## Buying a weapon you don't already have equipped replaces the current
## one outright (fresh at level 1) — a shop shelf, not an inventory.
func buy_weapon(weapon_id: String) -> bool:
	if not weapons.has_good(weapon_id) or weapon_id == equipped_weapon_id:
		return false
	var def := weapons.get_good(weapon_id)
	var cost := int(def["buy_cost"])
	if int(inventory.get(UD.RES_GOLD, 0)) < cost:
		return false
	inventory[UD.RES_GOLD] = int(inventory[UD.RES_GOLD]) - cost
	equipped_weapon_id = weapon_id
	weapon_level = 1
	return true


## Levels up whichever weapon is currently equipped. False with nothing
## equipped, already maxed, or unaffordable.
func upgrade_weapon() -> bool:
	if equipped_weapon_id == "" or not weapons.has_good(equipped_weapon_id):
		return false
	var def := weapons.get_good(equipped_weapon_id)
	if weapon_level >= int(def["max_level"]):
		return false
	var cost := UDSim.weapon_upgrade_cost(def, weapon_level)
	if int(inventory.get(UD.RES_GOLD, 0)) < cost:
		return false
	inventory[UD.RES_GOLD] = int(inventory[UD.RES_GOLD]) - cost
	weapon_level += 1
	return true


## --- Item shop (coins <-> collection items, priced by rank) -----------

## False on an unknown item, a full rank cap, or unaffordable.
func buy_item(item_id: String) -> bool:
	if not item_ranks.has(item_id):
		return false
	if item_count(item_id) >= item_cap(item_id):
		return false
	var cost := int(UD.ITEM_BUY_COST_BY_RANK.get(item_rank(item_id), 0))
	if cost <= 0 or int(inventory.get(UD.RES_GOLD, 0)) < cost:
		return false
	inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) - cost
	_add_item(item_id, 1)
	return true


## False when fewer than `count` are owned.
func sell_item(item_id: String, count: int = 1) -> bool:
	if count <= 0 or item_count(item_id) < count:
		return false
	var value := int(UD.ITEM_SELL_VALUE_BY_RANK.get(item_rank(item_id), 0))
	items[item_id] = item_count(item_id) - count
	inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + value * count
	return true


static func _effect_levels_in(entries: Dictionary, effect: String) -> int:
	var total := 0
	for id: Variant in entries.keys():
		var entry := entries[id] as Dictionary
		if str(entry.get("effect", "")) == effect:
			total += int(entry.get("level", 0))
	return total


## Extra document drop chance from the altar facility. The "survey" shop
## upgrade that used to grant this is retired (2026-07-15, shop redesign:
## pickaxe/survey folded into the weapon system and the altar) — its
## per-level bonus now rides altar_level instead, alongside altar's
## existing +1 atk/level (party_atk_bonus()). _effect_levels_in() still
## reads any doc_chance_add already banked in upgrades so a save with
## survey levels bought before the retirement keeps that bonus frozen
## rather than losing it outright.
func document_chance_bonus() -> float:
	var bonus := 0.0
	bonus += UDSim._effect_levels_in(upgrades, "doc_chance_add") * UD.UPGRADE_DOC_CHANCE
	bonus += float(altar_level) * UD.UPGRADE_DOC_CHANCE
	return bonus


func _roll_document(stage: Dictionary) -> void:
	var chance := float(stage.get("document_chance", 0.0))
	if chance > 0.0:
		chance += document_chance_bonus()
	if chance <= 0.0:
		return
	var roll := _rng.randf()
	var pool: Array = []
	for doc_id: Variant in stage.get("documents", []) as Array:
		if not discovered_documents.has(doc_id) and _doc_unlocked(str(doc_id)):
			pool.append(doc_id)
	if roll >= chance or pool.is_empty():
		return
	var doc_id: String = pool[_rng.randi_range(0, pool.size() - 1)]
	discovered_documents.append(doc_id)
	document_discovered.emit(doc_id)


## True when every unlock condition on the document holds. Conditions are
## a pure function of sim state, so gating stays deterministic and
## offline-equivalent. Documents without conditions are always available.
func _doc_unlocked(doc_id: String) -> bool:
	if not doc_conditions.has(doc_id):
		return true
	var cond := doc_conditions[doc_id] as Dictionary
	if discovered_documents.size() < int(cond.get("min_docs", 0)):
		return false
	for companion_id: Variant in cond.get("requires_companions", []) as Array:
		if not companions.has(str(companion_id)):
			return false
	for item_id: Variant in cond.get("requires_items", []) as Array:
		if item_count(str(item_id)) <= 0:
			return false
	return true


func item_count(item_id: String) -> int:
	return int(items.get(item_id, 0))


func item_rank(item_id: String) -> String:
	return str(item_ranks.get(item_id, UD.ITEM_DEFAULT_RANK))


func item_cap(item_id: String) -> int:
	return int(UD.ITEM_RANK_CAPS.get(item_rank(item_id), 0))


## Distinct collectibles owned at least once (collection progress).
func distinct_items() -> int:
	var total := 0
	for item_id: Variant in items.keys():
		if int(items[item_id]) > 0:
			total += 1
	return total


func _add_item(item_id: String, amount: int) -> void:
	items[item_id] = mini(item_count(item_id) + amount, item_cap(item_id))


## Rare finds on enemy defeat: a chest always pays coins and also holds a
## random collection item still under its rank cap; a nugget pays far
## more than a normal kill.
func _roll_special_find() -> void:
	var roll := _rng.randf()
	if roll < UD.CHEST_CHANCE:
		inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + UD.CHEST_COINS
		var pool: Array[String] = []
		for item_id in item_pool:
			if item_count(item_id) < item_cap(item_id):
				pool.append(item_id)
		if not pool.is_empty():
			var item_id: String = pool[_rng.randi_range(0, pool.size() - 1)]
			_add_item(item_id, 1)
			item_found.emit(item_id)
	elif roll < UD.CHEST_CHANCE + UD.NUGGET_CHANCE:
		inventory[UD.RES_GOLD] = int(inventory.get(UD.RES_GOLD, 0)) + UD.NUGGET_COINS


## --- Altar offerings -----------------------------------------------
## Coins (and, at higher levels, a collection item) buy permanent-for-
## this-run attack (party_atk_bonus()). Player command: deterministic, no rng.

func altar_built() -> bool:
	return upgrade_level("altar") > 0


func guild_built() -> bool:
	return upgrade_level("tavern") > 0


func dorm_built() -> bool:
	return upgrade_level("dorm") > 0


func altar_offer_cost() -> int:
	return int(round(
		UD.ALTAR_OFFER_BASE_COST * pow(UD.ALTAR_OFFER_COST_MULT, altar_level)
	))


## Rank of the item the NEXT offering consumes ("" while coins suffice).
func altar_required_item_rank() -> String:
	var next_level := altar_level + 1
	var required := ""
	var best_tier := -1
	for tier: Variant in UD.ALTAR_ITEM_RANK_TIERS.keys():
		if next_level >= int(tier) and int(tier) > best_tier:
			best_tier = int(tier)
			required = str(UD.ALTAR_ITEM_RANK_TIERS[tier])
	return required


## Offers coins (plus item_id when a rank is required) for +1 attack.
func offer_at_altar(item_id: String = "") -> bool:
	if not altar_built():
		return false
	var cost := altar_offer_cost()
	if int(inventory.get(UD.RES_GOLD, 0)) < cost:
		return false
	var required_rank := altar_required_item_rank()
	if required_rank != "":
		if item_id == "" or item_count(item_id) <= 0:
			return false
		if item_rank(item_id) != required_rank:
			return false
	inventory[UD.RES_GOLD] = int(inventory[UD.RES_GOLD]) - cost
	if required_rank != "":
		items[item_id] = item_count(item_id) - 1
	altar_level += 1
	return true


## --- Guild exchange --------------------------------------------------
## Receiving one item of rank R consumes UD.ITEM_EXCHANGE_COSTS[R] items
## of the rank directly below (Z←S×3, S←A×5, A←B×7, B←C×10). C/D rank
## items cannot be exchanged for — they come out of chests. The consume
## map is chosen by the caller (UI/network layer); the sim only enforces
## the rules, so the same command serves local and future Steam trades.

func rank_below(rank: String) -> String:
	var index := UD.ITEM_RANKS.find(rank)
	if index < 0 or index + 1 >= UD.ITEM_RANKS.size():
		return ""
	return UD.ITEM_RANKS[index + 1]


func exchange_item(target_id: String, consume: Dictionary) -> bool:
	if not item_pool.has(target_id):
		return false
	var target_rank := item_rank(target_id)
	if not UD.ITEM_EXCHANGE_COSTS.has(target_rank):
		return false
	if item_count(target_id) >= item_cap(target_id):
		return false
	var required := int(UD.ITEM_EXCHANGE_COSTS[target_rank])
	var fodder_rank := rank_below(target_rank)
	var offered := 0
	for consume_id: Variant in consume.keys():
		var id := str(consume_id)
		var count := int(consume[consume_id])
		if count <= 0 or id == target_id:
			return false
		if item_rank(id) != fodder_rank:
			return false
		if item_count(id) < count:
			return false
		offered += count
	if offered != required:
		return false
	for consume_id: Variant in consume.keys():
		var id := str(consume_id)
		items[id] = item_count(id) - int(consume[consume_id])
	_add_item(target_id, 1)
	return true


func to_dict() -> Dictionary:
	var minion_dicts: Array = []
	for minion in minions:
		minion_dicts.append(minion.to_dict())
	return {
		"version": UD.SAVE_VERSION,
		"tick_count": tick_count,
		# RNG seed/state are 64-bit; store as strings to survive JSON floats.
		"rng_seed": str(_rng.seed),
		"rng_state": str(_rng.state),
		"inventory": inventory.duplicate(),
		"minions": minion_dicts,
		"discovered_documents": discovered_documents.duplicate(),
		"items": items.duplicate(),
		"altar_level": altar_level,
		"companions": companions.duplicate(),
		"upgrades": upgrades.duplicate(true),
		"stage_index": stage_index,
		"enemy_id": enemy_id,
		"enemy_hp": enemy_hp,
		"exp_pool": exp_pool,
		"boss_active": boss_active,
		"boss_hp": boss_hp,
		"boss_enemy_id": boss_enemy_id,
		"boss_part_hp": boss_part_hp.duplicate(),
		"boss_parts_destroyed": boss_parts_destroyed.duplicate(),
		# Phase 6「防御」(2026-08-25、§20): 戦闘中だけの一時状態だが、
		# boss_part_hp等と同じ理由（戦闘途中セーブの再開整合性）で含める。
		"guarding_units": guarding_units.duplicate(),
		# HP/SPポーション追加 (2026-08-25): 同じ理由で含める。
		"battle_item_counts": battle_item_counts.duplicate(),
		# Boss Action Set (D2、2026-08-25): 戦闘途中セーブの再開整合性の
		# ため、同じ理由で含める。
		"boss_action_set_step": boss_action_set_step,
		"boss_checkpoint": boss_checkpoint.duplicate(true),
		"boss_intel": boss_intel.duplicate(true),
		"turn_order": turn_order.duplicate(),
		"turn_cursor": turn_cursor,
		"total_kills": total_kills,
		"equipped_weapon_id": equipped_weapon_id,
		"weapon_level": weapon_level,
		# REWINDⅡ (新企画v1仕様書v2「REWINDⅡ」§14/§15/§36、2026-08-28):
		# 解放状態(rewind2_unlocked)は恒久データ、mid_checkpoint関連の3
		# フィールドは戦闘途中セーブの再開整合性のため——boss_checkpoint
		# 等の既存フィールドと全く同じadditiveパターン。
		"rewind2_unlocked": rewind2_unlocked,
		"mid_checkpoint": mid_checkpoint.duplicate(true),
		"mid_checkpoint_set": mid_checkpoint_set,
		"mid_checkpoint_used": mid_checkpoint_used,
	}


static func from_dict(
	d: Dictionary,
	p_enemies: UDEnemyDB,
	p_stages: UDStageDB,
	p_item_pool: Array[String] = [],
	p_companion_defs: Array = [],
	p_doc_conditions: Dictionary = {},
	p_item_ranks: Dictionary = {},
	p_skills: UDSkillDB = null,
	p_weapons: UDShopDB = null,
	p_battle_items: UDBattleItemDB = null,
) -> UDSim:
	var sim := UDSim.new()
	sim.enemies = p_enemies
	sim.stages = p_stages
	sim.skills = p_skills if p_skills != null else UDSkillDB.from_dicts([])
	sim.weapons = p_weapons if p_weapons != null else UDShopDB.from_dicts([])
	sim.battle_items = p_battle_items if p_battle_items != null else UDBattleItemDB.from_dicts([])
	sim.item_pool = p_item_pool
	sim.companion_defs = p_companion_defs
	sim.doc_conditions = p_doc_conditions
	sim.item_ranks = p_item_ranks
	sim.tick_count = int(d["tick_count"])
	sim._rng.seed = (d["rng_seed"] as String).to_int()
	sim._rng.state = (d["rng_state"] as String).to_int()
	for res: Variant in (d["inventory"] as Dictionary).keys():
		sim.inventory[res] = int(d["inventory"][res])
	for minion_dict: Variant in d["minions"] as Array:
		sim.minions.append(UDMinion.from_dict(minion_dict))
	for doc_id: Variant in d["discovered_documents"] as Array:
		sim.discovered_documents.append(doc_id)
	# v4 -> v5: the collection became stackable. Old saves hold a plain
	# id array (one of each); new saves hold id -> count.
	var saved_items: Variant = d.get("items", {})
	if saved_items is Array:
		for item_id: Variant in saved_items as Array:
			sim.items[str(item_id)] = 1
	else:
		for item_id: Variant in (saved_items as Dictionary).keys():
			sim.items[str(item_id)] = int((saved_items as Dictionary)[item_id])
	sim.altar_level = int(d.get("altar_level", 0))
	for companion_id: Variant in d.get("companions", []) as Array:
		sim.companions.append(str(companion_id))
	for id: Variant in (d.get("upgrades", {}) as Dictionary).keys():
		var entry := d["upgrades"][id] as Dictionary
		sim.upgrades[id] = {
			"level": int(entry.get("level", 0)),
			"effect": str(entry.get("effect", "")),
		}
	# v5 -> v6: altar/tavern/dorm stopped being placeable rooms and
	# became one-time facility unlocks that live in the same "upgrades"
	# ledger as shop purchases. A room built in the old save carries
	# its unlock straight over (same effect, level 1).
	for room_dict: Variant in d.get("rooms", []) as Array:
		var rd := room_dict as Dictionary
		var facility_id := str(rd.get("id", ""))
		if facility_id in ["altar", "tavern", "dorm"] and not sim.upgrades.has(facility_id):
			sim.upgrades[facility_id] = {"level": 1, "effect": str(rd.get("effect", ""))}
	# v3 -> v4: the minion crew becomes protagonist + story companions.
	# Rebuild the party; companions re-join on the next ticks from the
	# document count.
	if int(d.get("version", 1)) < 4:
		sim.minions.clear()
		sim.minions.append(sim._new_unit_at_level(0, 1))
		sim.companions.clear()
	# Companions whose definitions were removed (placeholder characters)
	# leave the party; the crew is rebuilt when the roster changed. Runs
	# whenever the save holds any companion — even if every definition was
	# removed (known_ids empty) — so a lingering one is pruned to solo.
	if not sim.companions.is_empty():
		var known_ids: Array[String] = []
		for def: Variant in p_companion_defs:
			known_ids.append(str((def as Dictionary)["id"]))
		var kept: Array[String] = []
		for companion_id in sim.companions:
			if known_ids.has(companion_id):
				kept.append(companion_id)
		if kept.size() != sim.companions.size() \
				or sim.minions.size() != kept.size() + 1:
			sim.companions = kept
			sim.minions.clear()
			for i in kept.size() + 1:
				sim.minions.append(sim._new_unit_at_level(i, 1))
	# v7 -> v8: the dig turned into cave exploration + combat, a
	# completely different core loop. The old grid/jobs/dig_policy have
	# no equivalent and are simply not read above; battle state starts
	# fresh at stage 1 while everything the player earned (coins, items,
	# documents, companions, upgrades, altar level) is preserved. Every
	# party unit resets to level 1 at full HP/MP (their old dig-era
	# dicts carried no level/hp/mp, so this also covers "no such key").
	if int(d.get("version", 1)) < 8:
		sim.stage_index = 1
		sim.enemy_id = ""
		sim.enemy_hp = 0
		sim.exp_pool = 0
		sim.boss_active = false
		sim.boss_hp = 0
		for unit in sim.minions:
			unit.level = 1
			unit.hp = sim.unit_max_hp(unit)
			unit.sp = sim.unit_max_sp(unit)
		# Bought upgrade levels are kept, but their "effect" string was
		# baked in at purchase time under the old dig-era names — rename
		# in place so e.g. an already-bought pickaxe level still does
		# something (atk) instead of silently becoming inert.
		const OLD_EFFECT_RENAMES := {
			"dig_power_add": "atk_add",
		}
		for id: Variant in sim.upgrades.keys():
			var entry := sim.upgrades[id] as Dictionary
			var old_effect := str(entry.get("effect", ""))
			if OLD_EFFECT_RENAMES.has(old_effect):
				entry["effect"] = OLD_EFFECT_RENAMES[old_effect]
	else:
		sim.stage_index = int(d.get("stage_index", 1))
		sim.enemy_id = str(d.get("enemy_id", ""))
		sim.enemy_hp = int(d.get("enemy_hp", 0))
		sim.exp_pool = int(d.get("exp_pool", 0))
		sim.boss_active = bool(d.get("boss_active", false))
		sim.boss_hp = int(d.get("boss_hp", 0))
		sim.boss_enemy_id = str(d.get("boss_enemy_id", ""))
		# A save from before rematches existed can be mid-fight without
		# recording which boss: derive it from the gate it must be at.
		if sim.boss_active and sim.boss_enemy_id == "":
			sim.boss_enemy_id = str(
				p_stages.stage_for_index(sim.stage_index).get("boss_id", ""))
			if sim.boss_enemy_id == "":
				sim.boss_active = false
				sim.boss_hp = 0
		# 新企画v1 §8/§10 (2026-08-18): all optional/additive — a save from
		# before this system existed simply has none, same as a boss with
		# no "parts" data in its def.
		for part_id: Variant in (d.get("boss_part_hp", {}) as Dictionary).keys():
			sim.boss_part_hp[str(part_id)] = int((d["boss_part_hp"] as Dictionary)[part_id])
		for part_id: Variant in d.get("boss_parts_destroyed", []) as Array:
			sim.boss_parts_destroyed.append(str(part_id))
		# Phase 6「防御」(2026-08-25): additive, same "an older save simply
		# has none" pattern as boss_part_hp above.
		for unit_id: Variant in d.get("guarding_units", []) as Array:
			sim.guarding_units.append(int(unit_id))
		# HP/SPポーション追加 (2026-08-25): additive, same pattern.
		for item_id: Variant in (d.get("battle_item_counts", {}) as Dictionary).keys():
			sim.battle_item_counts[str(item_id)] = int((d["battle_item_counts"] as Dictionary)[item_id])
		# Boss Action Set (D2、2026-08-25): additive, same "an older save
		# simply has none (0, i.e. no set in progress)" pattern.
		sim.boss_action_set_step = int(d.get("boss_action_set_step", 0))
		sim.boss_checkpoint = (d.get("boss_checkpoint", {}) as Dictionary).duplicate(true)
		# REWINDⅡ (新企画v1仕様書v2「REWINDⅡ」§14/§15、2026-08-28): additive,
		# 同じ"an older save simply has none"パターン——旧セーブは解放前
		# (false)・未設定/未使用(false/false)として読める。mid_checkpoint
		# 自体はboss_checkpointと全く同じ形状のDictionaryなのでduplicate
		# (true)で丸ごと読むだけで良い。
		sim.rewind2_unlocked = bool(d.get("rewind2_unlocked", false))
		sim.mid_checkpoint = (d.get("mid_checkpoint", {}) as Dictionary).duplicate(true)
		sim.mid_checkpoint_set = bool(d.get("mid_checkpoint_set", false))
		sim.mid_checkpoint_used = bool(d.get("mid_checkpoint_used", false))
		for boss_id: Variant in (d.get("boss_intel", {}) as Dictionary).keys():
			var intel_entry := (d["boss_intel"] as Dictionary)[boss_id] as Dictionary
			var attacks_seen: Array[String] = []
			for a: Variant in intel_entry.get("attacks_seen", []) as Array:
				attacks_seen.append(str(a))
			var parts_seen: Array[String] = []
			for p: Variant in intel_entry.get("parts_destroyed_seen", []) as Array:
				parts_seen.append(str(p))
			sim.boss_intel[str(boss_id)] = {
				"attacks_seen": attacks_seen, "parts_destroyed_seen": parts_seen,
			}
		# 新戦闘進行システム v1 (2026-08-24): additive, same "an older save
		# simply has none" pattern as boss_part_hp above. A save written
		# before this system existed but mid an active fight (boss_active
		# true) gets a freshly generated order instead of an empty one — an
		# active fight always needs a real turn order to function under the
		# new system, same fallback rewind_boss_fight() uses for an old-
		# shaped checkpoint.
		for token: Variant in d.get("turn_order", []) as Array:
			sim.turn_order.append(str(token))
		sim.turn_cursor = int(d.get("turn_cursor", 0))
		if sim.boss_active and sim.turn_order.is_empty():
			sim.turn_order = sim._generate_turn_order()
			sim.turn_cursor = 0
		sim._normalize_turn_cursor()
		sim.total_kills = int(d.get("total_kills", 0))
		sim.equipped_weapon_id = str(d.get("equipped_weapon_id", ""))
		sim.weapon_level = int(d.get("weapon_level", 0))
	# v8 -> v9 (新企画v1 §1, 2026-08-18): companions no longer gate on
	# join_at_docs — every companion definition is present in the party
	# from the very start. An old save (whose companions array may hold
	# 0-3 of the 4 defs, mid-way through the old staged join) is
	# normalized to the full roster, same "rebuild party structure, keep
	# everything else" judgment as v7 -> v8 above (coins, items,
	# documents, upgrades, altar level are untouched).
	if int(d.get("version", 1)) < 9:
		var known_ids: Array[String] = []
		for def: Variant in p_companion_defs:
			known_ids.append(str((def as Dictionary)["id"]))
		sim.companions = known_ids
		sim.minions.clear()
		for i in known_ids.size() + 1:
			sim.minions.append(sim._new_unit_at_level(i, 1))
	return sim
