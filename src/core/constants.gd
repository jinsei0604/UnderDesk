class_name UD
extends RefCounted
## UNDERDESK core constants (§12-1: no magic numbers).

const SAVE_VERSION: int = 8

## Simulation tick length (§7.1: timer-driven, not per-frame).
const TICK_SECONDS: float = 2.0
## Offline catch-up cap: 24 hours of 2-second ticks (§7.1-4).
const MAX_OFFLINE_TICKS: int = 43200

## Extra document drop chance per level of the survey shop upgrade.
const UPGRADE_DOC_CHANCE: float = 0.05

const RES_GOLD: String = "gold"

## Party unit growth (2026-07-15 redesign: dig -> cave exploration +
## turn-based combat). Companions have their own data-driven growth curve
## (data/companions/*.json: base_hp/hp_per_level/etc.); the protagonist
## (party slot 0) is not a companion definition, so its curve lives here.
const PROTAGONIST_BASE_HP: int = 24
const PROTAGONIST_HP_PER_LEVEL: int = 5
const PROTAGONIST_BASE_MP: int = 6
const PROTAGONIST_MP_PER_LEVEL: int = 1
const PROTAGONIST_BASE_ATK: int = 5
const PROTAGONIST_ATK_PER_LEVEL: int = 1
const PROTAGONIST_BASE_DEF: int = 3
const PROTAGONIST_DEF_PER_LEVEL: int = 1
## Fallback growth for a party slot with no matching definition (should
## not normally be hit — see UDSim._growth_def_for_unit()).
const FALLBACK_GROWTH: Dictionary = {
	"base_hp": 10, "hp_per_level": 2, "base_mp": 0, "mp_per_level": 0,
	"base_atk": 3, "atk_per_level": 1, "base_def": 1, "def_per_level": 1,
}

## EXP cost to level up from `level` to `level + 1` (banked in the shared
## exp_pool, spent explicitly by the player via level_up_companion() —
## same base*mult^level shape as UDSim.upgrade_cost()).
const EXP_BASE: int = 10
const EXP_MULT: float = 1.35

## Collection item ranks, best first (guild trading, altar offerings).
const ITEM_RANKS: Array[String] = ["Z", "S", "A", "B", "C", "D"]
const ITEM_DEFAULT_RANK: String = "D"
## Per-rank carry caps: rarer items stack lower.
const ITEM_RANK_CAPS: Dictionary = {
	"Z": 10, "S": 50, "A": 100, "B": 200, "C": 500, "D": 500,
}
## Guild exchange: receiving one item of rank R consumes this many items
## of the rank directly below (Z←S×3, S←A×5, A←B×7, B←C×10).
## C and D have no exchange requirement.
const ITEM_EXCHANGE_COSTS: Dictionary = {"Z": 3, "S": 5, "A": 7, "B": 10}

## Shop item trading (buy_item/sell_item): coins per rank. Sell is well
## below buy so the two can't be arbitraged into a free coin loop.
const ITEM_BUY_COST_BY_RANK: Dictionary = {
	"Z": 4000, "S": 800, "A": 300, "B": 120, "C": 50, "D": 20,
}
const ITEM_SELL_VALUE_BY_RANK: Dictionary = {
	"Z": 1500, "S": 300, "A": 100, "B": 40, "C": 15, "D": 5,
}

## Altar offerings (§5.2 rework): each offering costs scaling coins and
## grants +1 attack (party-wide bonus, UDSim.party_atk_bonus()). From these
## altar levels on, the offering also consumes one collection item of the
## given rank.
const ALTAR_OFFER_BASE_COST: int = 40
const ALTAR_OFFER_COST_MULT: float = 1.4
const ALTAR_ITEM_RANK_TIERS: Dictionary = {
	5: "D", 10: "C", 15: "B", 20: "A", 25: "S", 30: "Z",
}

## Special finds rolled on each enemy defeated.
const CHEST_CHANCE: float = 0.02
const NUGGET_CHANCE: float = 0.03
const NUGGET_COINS: int = 25
## Every chest pays this; an unowned collection item also drops while
## any remain (the collection grows with updates, ~100 items planned).
const CHEST_COINS: int = 10

## The protagonist explores alone at first; story companions join later.
const INITIAL_MINION_COUNT: int = 1
## Protagonist + up to 4 story companions (data/companions/).
const MINION_MAX: int = 5
const MINION_NAMES: Array[String] = ["主人公", "仲間・一", "仲間・二", "仲間・三", "仲間・四"]

const AUTOSAVE_INTERVAL_SECONDS: float = 60.0
const SAVE_BACKUP_GENERATIONS: int = 3

## Resident-window fps budget (§7.1-2).
const FPS_ACTIVE: int = 60
const FPS_IDLE: int = 10

## Strip heights. 48px is the taskbar-look default; taller options remain
## for players who want a wider view of the dig.
const WINDOW_HEIGHTS: Array[int] = [48, 120, 180, 240]
const DEFAULT_WINDOW_HEIGHT_INDEX: int = 0
## Mini strip footprint: bottom-LEFT of the screen (the right side is
## busy with volume / Wi-Fi tray icons), floating about 1cm above the
## bottom edge so it does not sit on the taskbar itself.
const MINI_WINDOW_WIDTH: int = 320
const MINI_LEFT_MARGIN: int = 204
const MINI_BOTTOM_MARGIN: int = 12
## Centered window opened by clicking the strip: reading and management.
const NORMAL_WINDOW_SIZE := Vector2i(1152, 648)

const SUPPORTED_LOCALES: Array[String] = ["ja", "en"]

## First-run tutorial (§10): rotating hints over the first ~10 minutes
## whose whole message is that idling is the intended way to play.
const TUTORIAL_TICKS: int = 300
const TUTORIAL_HINT_CYCLE_TICKS: int = 10
const TUTORIAL_HINT_KEYS: Array[String] = [
	"TUT_HINT_1", "TUT_HINT_2", "TUT_HINT_3",
]

## Foreshadowing metadata on documents (story bible §5.1). A document may
## carry surface / mid / payoff variants of the same foreshadow thread.
const REVEAL_STAGES: Array[String] = ["surface", "mid", "payoff"]
## Optional unlock conditions on documents (§7.3 "ID＋条件"). All listed
## requirements must hold before the document can be unearthed.
const DOC_CONDITION_KEYS: Array[String] = [
	"min_docs", "requires_companions", "requires_items",
]
