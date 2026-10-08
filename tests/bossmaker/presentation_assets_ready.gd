extends RefCounted
## 演出の契約テストの補助(QA-06)。演出の時刻・後始末・音などの契約は、事前読み込みが素材を読み終えた状態
## (通常のゲームの状態)で検証する。読み終えていない時、ステージは演出の開始を素材が揃うまで待つ
## (rbm_battle_stage.gd の _start_dedicated()。その動きは test_rbm_presentation_warmup.gd が検証する)。
## ここでは、指定したボス(覚醒の前後)の演出と味方の専用の技が宣言する素材(warm_paths())をすべて読み、
## 参照を返す。テストはその参照を持っている間だけ、素材が読み終えた状態になる。

static func hold(boss_ids: Array) -> Array:
	var held: Array = []
	var tables := {"single": RBMBattleStage.BOSS_SINGLE_PRESENTATIONS, "all": RBMBattleStage.BOSS_ALL_PRESENTATIONS, "support": RBMBattleStage.BOSS_SUPPORT_PRESENTATIONS}
	for boss_id in boss_ids:
		for asset_id in [str(boss_id), str(boss_id) + "_awakened"]:
			for kind in tables:
				_hold(held, tables[kind].get(asset_id), asset_id, kind)
		_hold(held, RBMBattleStage.BOSS_AWAKENING_PRESENTATIONS.get(str(boss_id)), str(boss_id), "awakening")
	for skill_id in RBMBattleStage.SKILL_PRESENTATIONS:
		var entry: Dictionary = RBMBattleStage.SKILL_PRESENTATIONS[skill_id]
		_hold(held, entry.get("script"), str(entry.get("actor", "")), str(entry.get("kind", "")))
	return held

static func _hold(held: Array, script: Variant, asset_id: String, kind: String) -> void:
	if not script is Script:
		return
	var declares := false
	for method in (script as Script).get_script_method_list():
		if str(method.name) == "warm_paths":
			declares = true
	if not declares:
		return
	for path in (script as Script).call("warm_paths", asset_id, kind):
		if ResourceLoader.exists(str(path)):
			held.append(load(str(path)))
