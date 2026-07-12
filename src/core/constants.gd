class_name UD
extends RefCounted
## UNDERDESK core constants (§12-1: no magic numbers).

const SAVE_VERSION: int = 5

## Simulation tick length (§7.1: timer-driven, not per-frame).
const TICK_SECONDS: float = 2.0
## Offline catch-up cap: 24 hours of 2-second ticks (§7.1-4).
const MAX_OFFLINE_TICKS: int = 43200

const GRID_WIDTH: int = 60
const GRID_INITIAL_HEIGHT: int = 8
## Rows appended below when digging approaches the bottom.
const GRID_EXPAND_ROWS: int = 4

## Home depot on the surface row where minions deposit resources.
const DEPOT_POS := Vector2i(30, 0)

enum Terrain { AIR = 0, SOIL = 1, ROCK = 2, WETROCK = 3, RUINSTONE = 4 }

## Maps data-file terrain names to enum values.
const TERRAIN_BY_NAME: Dictionary = {
	"AIR": Terrain.AIR,
	"SOIL": Terrain.SOIL,
	"ROCK": Terrain.ROCK,
	"WETROCK": Terrain.WETROCK,
	"RUINSTONE": Terrain.RUINSTONE,
}

## Each altar raises the document drop chance by this much (§5.3 pacing).
const DOC_CHANCE_PER_ALTAR: float = 0.05
## Extra document drop chance while the lush-vein daily anomaly is active.
const DAILY_DOC_CHANCE_BONUS: float = 0.1
## Extra document drop chance per level of the survey shop upgrade.
const UPGRADE_DOC_CHANCE: float = 0.05

const RES_SOIL: String = "soil"
const RES_STONE: String = "stone"
const RES_ORE: String = "ore"
const RES_MAGIC_STONE: String = "magic_stone"
const RES_FOOD: String = "food"
const RES_GOLD: String = "gold"
const ALL_RESOURCES: Array[String] = [
	RES_SOIL, RES_STONE, RES_ORE, RES_MAGIC_STONE, RES_FOOD, RES_GOLD,
]

## §4: dig commands are direction-level policies, not per-cell orders.
enum DigPolicy { NONE = 0, DOWN = 1, WIDEN = 2 }

## Economy: hauled resources convert to coins on deposit (shop currency).
const COIN_VALUES: Dictionary = {
	RES_SOIL: 1,
	RES_STONE: 2,
	RES_ORE: 5,
	RES_MAGIC_STONE: 10,
	RES_FOOD: 1,
	RES_GOLD: 1,
}

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

## Altar offerings (§5.2 rework): each offering costs scaling coins and
## grants +1 dig power. From these altar levels on, the offering also
## consumes one collection item of the given rank.
const ALTAR_OFFER_BASE_COST: int = 40
const ALTAR_OFFER_COST_MULT: float = 1.4
const ALTAR_ITEM_RANK_TIERS: Dictionary = {
	5: "D", 10: "C", 15: "B", 20: "A", 25: "S", 30: "Z",
}

## Special finds rolled on each completed dig.
const CHEST_CHANCE: float = 0.02
const NUGGET_CHANCE: float = 0.03
const NUGGET_COINS: int = 25
## Every chest pays this; an unowned collection item also drops while
## any remain (the collection grows with updates, ~100 items planned).
const CHEST_COINS: int = 10

const MINION_DIG_POWER: int = 1
## The protagonist digs alone at first; story companions join later.
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
