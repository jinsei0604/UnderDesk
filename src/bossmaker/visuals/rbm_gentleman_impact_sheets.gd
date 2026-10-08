extends Node
## Keeps the gentleman's 2560x2240 impact sheets for one battle stage so an attack never decodes
## them on the frame it starts. Sheets are read in the background: the ones the boss's attacks use
## in its current form as soon as the boss is known, any other one when an attack starts (it is
## first drawn seconds later). At most MAX_SHEETS stay, the least recently used going first, and
## everything goes with the stage. Reads the battle, never changes it.
const Vfx=preload("res://src/bossmaker/visuals/rbm_gentleman_vfx.gd")
## The most one attack loaded at once before sheets were kept (3 sheets, about 66MB as RGBA8).
const MAX_SHEETS := 3
var _stage: Control
var _battle_id := 0
var _boss_id := ""
var _wanted: Dictionary={}
var _pending: Dictionary={}
var _held: Dictionary={}
## Held paths, least recently used first.
var _order: Array[String]=[]

func configure(stage: Control) -> void:
	_stage=stage

func _process(_delta: float) -> void:
	_collect()
	if is_instance_valid(_stage) and not _stage.is_playing():refresh()

## Re-plans the kept sheets when the battle or the boss form changes.
func refresh() -> void:
	var battle=_stage._battle
	var battle_id: int=battle.get_instance_id() if battle!=null else 0
	var boss_id: String=str(_stage._asset_ids.get("boss",""))
	if battle_id==_battle_id and boss_id==_boss_id:return
	_battle_id=battle_id;_boss_id=boss_id
	var planned: Array[String]=[]
	if battle!=null and boss_id in ["gentleman","gentleman_awakened"]:
		var awakened:=boss_id=="gentleman_awakened"
		for skill in battle.boss.skills:
			# Same split as RBMMotionCatalog.profile(): everything but heal/buff plays as an attack.
			if str(skill.get("effect",skill.get("type","damage"))) in ["heal","self_heal","buff_atk_self","atk_self_buff"]:continue
			var all: bool=str(skill.get("target","")) in ["ally_all","all"]
			var kind: String=("awakened_all" if all else "awakened_single") if awakened else ("all" if all else "single")
			for style in Vfx.IMPACT_STYLES.get(kind,[]):
				var path:=Vfx.impact_path(str(skill.get("attribute","NEUTRAL")),style)
				if not planned.has(path):planned.append(path)
	_wanted.clear()
	for path in _order.duplicate():
		if not planned.has(path):_release(path)
	for path in planned:
		if _held.size()+_pending.size()>=MAX_SHEETS and not _held.has(path) and not _pending.has(path):break
		_wanted[path]=true;_read(path,[])

## Called by a starting attack: a sheet not kept yet is still read in the background,
## well before the first frame that draws it.
func request(attribute: String, kind: String) -> void:
	var paths: Array[String]=[]
	for style in Vfx.IMPACT_STYLES.get(kind,[]):paths.append(Vfx.impact_path(attribute,style))
	for path in paths:
		_wanted[path]=true;_read(path,paths)

func texture(attribute: String, style: String) -> Texture2D:
	var path:=Vfx.impact_path(attribute,style)
	if not _held.has(path):
		var sheet: Texture2D
		if _pending.has(path):
			_pending.erase(path)
			sheet=ResourceLoader.load_threaded_get(path)
		if sheet==null:sheet=load(path)
		_wanted[path]=true;_hold(path,sheet,[path])
	_touch(path)
	return _held[path]

func _read(path: String, keep: Array[String]) -> void:
	if _held.has(path):
		_touch(path);return
	if _pending.has(path):return
	_make_room(keep)
	if ResourceLoader.load_threaded_request(path,"Texture2D")==OK:_pending[path]=true

func _hold(path: String, sheet: Texture2D, keep: Array[String]) -> void:
	_make_room(keep)
	_held[path]=sheet;_order.append(path)

## Releases the least recently used sheets that the starting attack does not need.
func _make_room(keep: Array[String]) -> void:
	var i:=0
	while _held.size()+_pending.size()>=MAX_SHEETS and i<_order.size():
		if keep.has(_order[i]):
			i+=1;continue
		_release(_order[i])

func _release(path: String) -> void:
	_held.erase(path);_order.erase(path);_wanted.erase(path)

func _touch(path: String) -> void:
	_order.erase(path);_order.append(path)

func _collect() -> void:
	if _pending.is_empty():return
	for path in _pending.keys():
		if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:continue
		_pending.erase(path)
		var sheet:=ResourceLoader.load_threaded_get(path) as Texture2D
		if sheet!=null and _wanted.has(path):_hold(path,sheet,[path])

func _exit_tree() -> void:
	# Every threaded request is collected once, or the loader would keep the sheet alive.
	for path in _pending:ResourceLoader.load_threaded_get(path)
	_pending.clear();_held.clear();_wanted.clear();_order.clear()
	_battle_id=0;_boss_id=""
