extends "res://src/bossmaker/visuals/rbm_musha_awakening.gd"
## 朽ちた機械武者の覚醒演出「封剣機構・解放」(承認済み 2026-09-27)。元の覚醒演出をそのまま再生し、毎コマの経過を
## 墨の層(rbm_musha_ink_director.gd。ステージから受け取る)へ渡す: ロックが外れた関節から墨が滲む → 足元に溜まり始める
## → 解放で墨が弾け、墨溜まりが広がる → 抜刀と同時に刀から墨が立ち昇る。表示専用。
var director

func play(stage: Control) -> Tween:
	if director == null and stage.has_method("musha_ink_director"):
		director = stage.musha_ink_director()
	return super.play(stage)

func _advance(t: float) -> void:
	super._advance(t)
	if is_instance_valid(director) and active:
		var shake := Motion.shake_offset(t, Motion.shake_force("awakening", t)).round()
		director.advance_awakening(t, shake)

func stop() -> void:
	if is_instance_valid(director):
		director.end_awakening()
	super.stop()
