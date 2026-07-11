class_name UD
extends RefCounted
## UNDERDESK core constants (§12-1: no magic numbers).

const SAVE_VERSION: int = 4

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

## Prestige (§5.5): burying the shaft at this depth or deeper grants
## crystals, one per row beyond the threshold.
const PRESTIGE_MIN_DEPTH: int = 12
const PRESTIGE_START_COINS_PER_LEVEL: int = 100

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
const MINI_LEFT_MARGIN: int = 100
const MINI_BOTTOM_MARGIN: int = 20
## Centered window opened by clicking the strip: reading and management.
const NORMAL_WINDOW_SIZE := Vector2i(1152, 648)

const SUPPORTED_LOCALES: Array[String] = ["ja", "en"]
