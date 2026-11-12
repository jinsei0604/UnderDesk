extends "res://src/bossmaker/visuals/rbm_character_visual.gd"
## ヒーロー（hero_boss）の立ち絵。覚醒後（hero_boss_awakened）は常時の黒い炎のオーラ（2026-11-09 ユーザーが採用）をまとう。
## オーラは立ち絵の輪郭から焼いた距離（RBMHeroDarkAura）で描き、本体の絵は変えない。表示専用。

const AWAKENED_ID := "hero_boss_awakened"
## 覚醒後の立ち絵のコマ名（motion/exposures.json）
const AWAKENED_CEL := "omega"

var _aura: RBMHeroDarkAura
var _aura_t := 0.0

func setup(id: String, height: float) -> void:
	super.setup(id, height)
	if is_instance_valid(_aura):
		_aura.queue_free()
	_aura = null
	if id == AWAKENED_ID:
		_aura = RBMHeroDarkAura.new()
		_aura.name = "HeroDarkAura"
		_aura.show_behind_parent = true
		_aura.scale = Vector2.ONE * _pixel_scale
		add_child(_aura)
		_aura.setup("dark")
		_update_aura()

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(_aura) and is_visible_in_tree():
		_aura_t += delta
		_update_aura()

## 立ち絵を置いた範囲（frames.json の bbox、絵の画素）と足元から、オーラを合わせる。
func _update_aura() -> void:
	var top_left := Vector2.ZERO
	if not _pose_rects.is_empty():
		var box: Array = _pose_rects[0]["bbox"]
		top_left = Vector2(box[0], box[1])
	_aura.show_on(AWAKENED_CEL, top_left, _foot, 0.0, 1.0, _aura_t)
