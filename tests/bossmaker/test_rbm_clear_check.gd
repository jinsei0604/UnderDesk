extends GutTest

## RPG BOSS MAKER Phase 1 Step 5 — Clear Check tests (§27-32).
## Instantiates the real RBMCreatorMain Control tree (same established
## pattern as tests/bossmaker/test_rbm_creator_flow.gd) and drives Clear
## Check through its own public methods/buttons, not by scraping internals
## beyond what those methods already expose.
##
## §30's own guidance ("既存テストで共通機構自体が十分保証されている部分に
## ついて、全く同じテストを大量複製する必要はありません"): the underlying
## snapshot()/restore() primitive already has 17 dedicated tests
## (test_rbm_battle_snapshot.gd + test_rbm_creator_test_session.gd) covering
## RNG reproduction, scripted-action re-firing across all 3 timings, future-
## history discard, and repeated-cycle stress. This file focuses on Clear
## Check's own CONNECTION to that primitive, not re-proving the primitive
## itself.

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

## A boss trivially beaten in exactly 1 turn by a single plain "attack" — no
## boss skills/candidates at all, so _pick_boss_normal_action() never even
## consumes an RNG draw. The outcome is 100% deterministic without needing
## any seed control.
func _fill_easy_win_boss(creator: RBMCreatorMain) -> void:
	creator.draft.boss_name = "テストボス"
	creator.draft.hp = 1
	creator.draft.atk = 1
	creator.draft.spd = 1
	creator.draft.add_party_character("hero")

## A boss the lone party member cannot survive even once — a single (hence
## deterministic: only one candidate for _pick_boss_normal_action() to ever
## select, regardless of the RNG roll) attack skill dealing far more damage
## than hero's max_hp, even through 防御's halving.
## 実機プレイ改善①: spdは意図的にhero(100)より低い1へ設定している——新方式
## では防御は「宣言した瞬間から、次の自分の行動順まで」有効なだけで遡及
## 適用されないため、ボスの方が速いと勇者はTurn 1で防御を宣言する前に
## 無条件の直撃を受けてしまう（fixtureは「防御しても防げない」ことを示す
## 意図だったが、それ自体はhpの絶対量で既に保証されている）。勇者を先に
## 行動させることで、このfileの他のfixtureと同じ「勇者が防御を宣言してから
## ボスが応じる」という観測可能な順序を保つ。
func _fill_guaranteed_loss_boss(creator: RBMCreatorMain) -> void:
	creator.draft.boss_name = "強敵"
	creator.draft.hp = 1000000
	creator.draft.atk = 9999
	creator.draft.spd = 1
	var skill_id := creator.draft.add_skill({"name": "猛攻", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 100.0})
	creator.draft.normal_actions_enabled = true
	creator.draft.normal_action_percentages[skill_id] = 100.0
	creator.draft.add_party_character("hero")

## A boss that takes exactly 3 turns of straight "attack" to defeat (hp=500,
## hero atk=240/turn) while itself dealing non-lethal, single-candidate
## (deterministic) damage back — enough turns to make REWIND meaningfully
## testable (rewind back after reaching turn 2/3, replay).
func _fill_multi_turn_boss(creator: RBMCreatorMain) -> void:
	creator.draft.boss_name = "多ターンボス"
	creator.draft.hp = 500
	creator.draft.atk = 50
	creator.draft.spd = 1
	var skill_id := creator.draft.add_skill({"name": "反撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.normal_actions_enabled = true
	creator.draft.normal_action_percentages[skill_id] = 100.0
	creator.draft.add_party_character("hero")

## 実機プレイ改善①: 旧resolve_turn(ally_actions)一括APIの廃止に伴い、
## かつて_attack_all()/_defend_all()が組み立てていた「全員分の行動辞書」は
## 不要になった——新方式は入力待ちの味方1人ずつをact_attack()/act_defend()
## で解決し、内部で自動的に他の自動解決分（ボスの番など）まで進める。
## このファイルの各fixtureはいずれも単一パーティ（"hero"のみ）のため、
## 「そのラウンドで入力待ちの唯一の味方」を解決する呼び出し1回が、旧
## _attack_all()/_defend_all()の1ラウンド分と等価になる。

# ---------------------------------------------------------------------------
# §27 — Clear Check開始
# ---------------------------------------------------------------------------

func test_step7_has_test_battle_and_clear_check_buttons() -> void:
	var creator := _new_creator()
	var step7: RBMCreatorStep7Summary = creator._step_views[4]
	assert_not_null(step7.find_child("TestBattleButton", true, false))
	assert_not_null(step7.find_child("ClearCheckButton", true, false))

func test_clear_check_button_opens_confirmation_screen() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	creator.press_clear_check()
	assert_true(creator._clear_check_view.visible)
	assert_true(creator._clear_check_view._confirm_panel.visible)
	assert_false(creator._clear_check_view._battle_panel.visible)
	assert_eq(creator._clear_check_view._confirm_boss_name_label.text, "テストボス")

func test_confirm_back_returns_to_step7_without_starting_battle_and_keeps_draft() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	creator.press_clear_check()
	creator._clear_check_view._on_confirm_back_pressed()
	assert_true(creator._steps_root.visible)
	assert_false(creator._clear_check_view.visible)
	assert_eq(creator.current_step, RBMCreatorMain.STEP_COUNT)
	assert_null(creator._clear_check_view.session, "no battle/session was ever constructed")
	assert_eq(creator.draft.boss_name, "テストボス", "draft is untouched")

func test_confirm_start_passes_definition_validation_and_starts_battle() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	creator.press_clear_check()
	var result := creator.press_clear_check_start()
	assert_true(bool(result.get("ok", false)))
	assert_true(creator._clear_check_view._battle_panel.visible)
	assert_false(creator._clear_check_view._confirm_panel.visible)
	assert_true(creator._clear_check_view.session.start_ok())

func test_confirm_start_with_invalid_definition_does_not_start_battle() -> void:
	var creator := _new_creator()
	creator.draft.boss_name = "X"
	creator.draft.add_skill({"name": "S", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	# no party at all -> RBMDefinitionLoader must reject this.
	creator.press_clear_check()
	var result := creator.press_clear_check_start()
	assert_false(bool(result.get("ok", true)))
	assert_true((result["errors"] as Array).size() > 0)
	assert_false(creator._clear_check_view._battle_panel.visible)
	assert_null(creator._clear_check_view.session)

func test_clear_check_battle_uses_creator_settings_as_is() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start(1)
	var battle := creator._clear_check_view.session.battle
	assert_eq(battle.boss.max_hp, 500, "boss HP is exactly the Creator-configured value, no Clear-Check-only adjustment")
	assert_eq(battle.boss.atk, 50)
	assert_eq(battle.party[0].display_name, "炎属性・勇者", "the configured party (hero) is used as-is")

## Codex最終レビュー対応①: a real TEST BATTLE win must never register as a
## Clear Check success — proven end to end through the actual TEST BATTLE
## path (RBMCreatorMain.press_test_battle() -> RBMCreatorTestBattleView -> a
## genuine resolve_turn() that actually wins -> the public
## draft.is_clear_check_currently_valid()/has_ever_cleared() judgment paths),
## not merely by checking that no "record_clear_check_success" call exists in
## the TEST BATTLE view's source.
func test_test_battle_victory_never_registers_as_clear_check_success() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	assert_false(creator.draft.has_ever_cleared(), "sanity: Clear Check has never succeeded on this draft")

	var result := creator.press_test_battle()
	assert_true(bool(result.get("ok", false)), "errors: %s" % str(result.get("errors", [])))
	var view := creator._test_battle_view
	view.act_attack(view.session.battle.party[0].id)

	assert_true(view.session.battle.battle_over, "sanity: the TEST BATTLE actually ended")
	assert_eq(view.session.battle.winner, "ally", "sanity: the TEST BATTLE was actually won")
	assert_false(creator.draft.has_ever_cleared(), "a real TEST BATTLE win must never mark Clear Check as ever having succeeded")
	assert_false(creator.draft.is_clear_check_currently_valid(), "and the public 'is it currently clear-checked' judgment path must also report false")

# ---------------------------------------------------------------------------
# §28 — 成功・失敗
# ---------------------------------------------------------------------------

func test_clear_check_success_via_real_win_condition() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start()
	var view := creator._clear_check_view
	view.act_attack(view.session.battle.party[0].id)
	assert_true(view.session.battle.battle_over)
	assert_eq(view.session.battle.winner, "ally")
	assert_true(creator.draft.has_ever_cleared())
	assert_true(creator.draft.is_clear_check_currently_valid())
	# 実機プレイ改善③ item8: "CLEAR CHECK COMPLETE"/"FAILED"を日本語化。
	assert_eq(view._outcome_label.text, "クリアチェック成功")

## §28-2: structural guarantee that RBMCreatorClearCheckView never
## independently reimplements a boss.hp<=0 win check — it must decide success
## by reading RBMBattle.battle_over/winner only (the exact fields
## RBMBattle._check_battle_over() already sets, per the Step 5 investigation).
## Scoped specifically to _check_clear_check_success()'s own body (the ONE
## place record_clear_check_success() is ever called — 実機プレイ改善①以降、
## 旧_on_resolve_turn_pressed()から改称・抽出された関数）rather than the whole
## file — the file legitimately displays "boss.hp" elsewhere (refresh()'s HP
## label) and legitimately calls is_downed() elsewhere (filtering which
## ALLY units to show target/command buttons for), neither of which is a win
## -check reimplementation; scanning the whole file would false-positive on
## both.
func test_clear_check_never_independently_checks_boss_hp() -> void:
	var path := "res://src/bossmaker/creator/rbm_creator_clear_check_view.gd"
	var source := FileAccess.get_file_as_string(path)
	var start := source.find("func _check_clear_check_success()")
	assert_true(start != -1, "sanity: the function exists")
	var next_func := source.find("\nfunc ", start + 1)
	var body := source.substr(start, next_func - start)
	assert_true(body.contains("battle.winner"), "must decide success by reading the battle system's own winner field")
	assert_true(body.contains("battle_over"), "must gate on the battle system's own battle_over flag")
	assert_false(body.contains("boss.hp"), "must not independently inspect the boss's own HP to decide victory")
	assert_false(body.contains("is_downed()"), "must not re-derive victory from is_downed() itself -- only from the battle system's own winner/battle_over result")

## Creator UI改修（STEP4統合+最終確認再設計、2026-09-05）§19: 「CLEAR CHECK」
## セクションは、ボタン自身のtextを状態で切り替えるのではなく、専用の状態
## ラベル（未達成/達成済み）＋常に同じ文言の開始ボタンへ分離された。
func test_step7_shows_clear_check_completed_after_success() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start()
	var view := creator._clear_check_view
	view.act_attack(view.session.battle.party[0].id)
	view._on_return_pressed()
	assert_true(creator._steps_root.visible)
	var step7: RBMCreatorStep7Summary = creator._step_views[4]
	step7.refresh()
	assert_eq(step7._clear_check_status_label.text, "達成済み")
	assert_eq(step7._clear_check_button.text, "クリアチェックを開始", "the button itself always keeps the same label; achievement is shown by the status label")

func test_clear_check_defeat_does_not_record_success() -> void:
	var creator := _new_creator()
	_fill_guaranteed_loss_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start()
	var view := creator._clear_check_view
	view.act_defend(view.session.battle.party[0].id)
	assert_true(view.session.battle.battle_over)
	assert_eq(view.session.battle.winner, "boss")
	assert_false(creator.draft.has_ever_cleared())
	assert_eq(view._outcome_label.text, "クリアチェック失敗")
	assert_true(view._retry_button.visible, "failure screen shows もう一度挑戦")

func test_defeat_retry_starts_fresh_turn_1_battle() -> void:
	var creator := _new_creator()
	_fill_guaranteed_loss_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start()
	var view := creator._clear_check_view
	view.act_defend(view.session.battle.party[0].id)
	assert_true(view.session.battle.battle_over)

	view._on_retry_pressed()
	assert_false(view.session.battle.battle_over, "a brand new battle has started")
	assert_eq(view.session.battle.current_turn, 1)
	assert_eq(view.session.battle.party[0].hp, view.session.battle.party[0].max_hp, "full HP -- a fresh battle, not the old one")
	assert_eq(view.session.reachable_turns(), [1], "REWIND history reset to just Turn 1 -- the previous attempt's history was not carried over")

func test_defeat_return_to_creator_preserves_draft() -> void:
	var creator := _new_creator()
	_fill_guaranteed_loss_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start()
	var view := creator._clear_check_view
	view.act_defend(view.session.battle.party[0].id)
	view._on_return_pressed()
	assert_true(creator._steps_root.visible)
	assert_eq(creator.current_step, RBMCreatorMain.STEP_COUNT)
	assert_eq(creator.draft.boss_name, "強敵", "draft preserved after a defeat + Creatorに戻る")
	assert_false(creator.draft.has_ever_cleared())

func test_success_outcome_screen_has_only_return_button() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start()
	var view := creator._clear_check_view
	view.act_attack(view.session.battle.party[0].id)
	assert_false(view._retry_button.visible, "§14: no もう一度挑戦 on the success screen")
	assert_true(view._return_button.visible)

# ---------------------------------------------------------------------------
# §29 — Clear Check状態（比較対象/対象外/パーティ順序）
# ---------------------------------------------------------------------------

func _win_clear_check(creator: RBMCreatorMain) -> void:
	creator.press_clear_check()
	creator.press_clear_check_start()
	var view := creator._clear_check_view
	view.act_attack(view.session.battle.party[0].id)
	view._on_return_pressed()

func test_clear_check_success_invalidated_by_hp_change_and_restored_when_reverted() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	_win_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	creator.draft.hp = 2
	assert_true(creator.draft.has_ever_cleared(), "the RECORD itself is never deleted by a mismatch")
	assert_false(creator.draft.is_clear_check_currently_valid(), "HP changed -> currently invalid")

	creator.draft.hp = 1
	assert_true(creator.draft.is_clear_check_currently_valid(), "reverted to the exact cleared value -> valid again, with no special restore step")

func test_clear_check_success_invalidated_by_atk_change() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	_win_clear_check(creator)
	creator.draft.atk = 2
	assert_false(creator.draft.is_clear_check_currently_valid())

func test_clear_check_success_invalidated_by_spd_change() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	_win_clear_check(creator)
	creator.draft.spd = 2
	assert_false(creator.draft.is_clear_check_currently_valid())

func test_clear_check_success_invalidated_by_weak_attribute_change() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	_win_clear_check(creator)
	creator.draft.toggle_weak_attribute("FIRE")
	assert_false(creator.draft.is_clear_check_currently_valid())
	creator.draft.toggle_weak_attribute("FIRE")
	assert_true(creator.draft.is_clear_check_currently_valid(), "reverted -> valid again")

func test_clear_check_success_invalidated_by_resist_attribute_change() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	_win_clear_check(creator)
	creator.draft.toggle_resist_attribute("ICE")
	assert_false(creator.draft.is_clear_check_currently_valid())

func test_clear_check_success_invalidated_by_boss_skill_performance_change() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	_win_multi_turn_clear_check(creator)
	var skill_id := str(creator.draft.skills[0]["skill_id"])
	creator.draft.update_skill(skill_id, {"name": "反撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 2.0})
	assert_false(creator.draft.is_clear_check_currently_valid(), "changing a skill's own atk_multiplier invalidates")
	creator.draft.update_skill(skill_id, {"name": "反撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	assert_true(creator.draft.is_clear_check_currently_valid(), "reverted the skill's values exactly -> restored")

## Codex最終レビュー対応②: deleting a boss skill and recreating one with
## IDENTICAL user-facing values must invalidate Clear Check (add_skill()
## always assigns a brand-new skill_id, per RBMCreatorDraft.battle_content_snapshot()'s
## own confirmed design), while editing the SAME skill in place
## (update_skill(), which never changes skill_id) through an A->B->A round
## trip must still restore success. Both paths exercised in one test so the
## distinction the confirmed spec draws between them is explicit.
func test_skill_delete_and_recreate_with_identical_values_invalidates_but_in_place_edit_restores() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	var skill_data := {"name": "爪撃", "type": "attack", "target": "single", "attribute": "FIRE", "atk_multiplier": 2.5}
	var original_skill_id := creator.draft.add_skill(skill_data.duplicate(true))
	_win_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	# A -> B -> A via update_skill() (same skill_id throughout) -- must restore.
	creator.draft.update_skill(original_skill_id, {"name": "爪撃", "type": "attack", "target": "single", "attribute": "FIRE", "atk_multiplier": 9.0})
	assert_false(creator.draft.is_clear_check_currently_valid(), "sanity: editing the value invalidates")
	creator.draft.update_skill(original_skill_id, skill_data.duplicate(true))
	assert_true(creator.draft.is_clear_check_currently_valid(), "reverted via update_skill() (same skill_id) -> restored")

	# Delete + recreate with IDENTICAL user-facing values -- must NOT restore
	# (a genuinely new skill_id is assigned).
	creator.draft.remove_skill(original_skill_id)
	var recreated_skill_id := creator.draft.add_skill(skill_data.duplicate(true))
	assert_ne(recreated_skill_id, original_skill_id, "sanity: a genuinely new skill_id was assigned by add_skill()")
	assert_false(creator.draft.is_clear_check_currently_valid(), "delete+recreate with identical values is still treated as a DIFFERENT skill (different skill_id) -- Clear Check stays invalid, per the confirmed §a decision")

func test_clear_check_success_invalidated_by_normal_action_percentage_change() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	_win_multi_turn_clear_check(creator)
	var skill_id := str(creator.draft.skills[0]["skill_id"])
	creator.draft.normal_action_percentages[skill_id] = 50.0
	assert_false(creator.draft.is_clear_check_currently_valid())

func test_clear_check_success_invalidated_by_normal_action_order_change() -> void:
	# §22: normal_actions order is derived from draft.skills' own array order
	# (_normal_actions_for_definition() iterates it in order) -- reordering
	# draft.skills without changing membership/percentages must still
	# invalidate, since _pick_boss_normal_action()'s cumulative-weight scan
	# is order-sensitive for a fixed RNG roll.
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	# both weights nonzero -- 0% would never appear in _normal_actions_for_definition()'s
	# output at all, making a skills[] reorder invisible to the comparison. Both
	# skills deal well under hero's max_hp per hit, so the fixture stays
	# reliably winnable by straight-attacking regardless of which the RNG picks.
	var second_id := creator.draft.add_skill({"name": "咆哮", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 0.5})
	creator.draft.normal_action_percentages[second_id] = 50.0
	_win_multi_turn_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	var tmp: Dictionary = creator.draft.skills[0]
	creator.draft.skills[0] = creator.draft.skills[1]
	creator.draft.skills[1] = tmp
	assert_false(creator.draft.is_clear_check_currently_valid(), "reordering draft.skills (and hence normal_actions' array order) invalidates even though membership/percentages are unchanged")

func test_clear_check_success_invalidated_by_scripted_action_change() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	_win_multi_turn_clear_check(creator)
	var skill_id := str(creator.draft.skills[0]["skill_id"])
	creator.draft.add_scripted_action(1, skill_id, "turn_start_interrupt")
	assert_false(creator.draft.is_clear_check_currently_valid())

## Codex最終レビュー対応③ (turn): changes to an EXISTING scripted action's own
## turn -- not merely adding a brand-new one -- must invalidate, and
## reverting it back must restore success. scripted_actions entries have no
## id of their own to edit in place (RBMCreatorDraft's own schema:
## {turn,skill_id,timing}, no identity field), so remove_scripted_action() +
## add_scripted_action() with the new value IS the genuine Creator-side path
## for changing one -- not raw Dictionary mutation.
func test_clear_check_success_invalidated_by_scripted_action_turn_change_and_reverting_restores() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	var skill_id := creator.draft.add_skill({"name": "咆哮", "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": 1, "heal_percent": 0.0})
	creator.draft.add_scripted_action(3, skill_id, "replace")
	_win_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	creator.draft.remove_scripted_action(0)
	creator.draft.add_scripted_action(4, skill_id, "replace")
	assert_false(creator.draft.is_clear_check_currently_valid(), "Turn 3 -> Turn 4 invalidates")

	creator.draft.remove_scripted_action(0)
	creator.draft.add_scripted_action(3, skill_id, "replace")
	assert_true(creator.draft.is_clear_check_currently_valid(), "reverted back to Turn 3 -> restored")

## Codex最終レビュー対応③ (timing): same as the turn-change test above, but
## for an existing scripted action's timing.
func test_clear_check_success_invalidated_by_scripted_action_timing_change_and_reverting_restores() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	var skill_id := creator.draft.add_skill({"name": "咆哮", "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": 1, "heal_percent": 0.0})
	creator.draft.add_scripted_action(1, skill_id, "replace")
	_win_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	creator.draft.remove_scripted_action(0)
	creator.draft.add_scripted_action(1, skill_id, "turn_start_interrupt")
	assert_false(creator.draft.is_clear_check_currently_valid(), "replace -> turn_start_interrupt invalidates")

	creator.draft.remove_scripted_action(0)
	creator.draft.add_scripted_action(1, skill_id, "replace")
	assert_true(creator.draft.is_clear_check_currently_valid(), "reverted timing -> restored")

## Codex最終レビュー対応③ (order): two scripted actions sharing the same
## (turn,timing) group, reordered via the genuine ↑/↓ path
## (RBMCreatorDraft.move_scripted_action(), exactly what STEP 4's UI buttons
## call) -- §22: execution order within a group is compared content, so
## swapping it must invalidate, and swapping back must restore.
func test_clear_check_success_invalidated_by_scripted_action_order_change_and_reverting_restores() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	var skill_a := creator.draft.add_skill({"name": "咆哮A", "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": 1, "heal_percent": 0.0})
	var skill_b := creator.draft.add_skill({"name": "咆哮B", "type": "self_heal", "heal_mode": "fixed", "heal_fixed_amount": 1, "heal_percent": 0.0})
	creator.draft.add_scripted_action(1, skill_a, "turn_start_interrupt")
	creator.draft.add_scripted_action(1, skill_b, "turn_start_interrupt")
	_win_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	assert_true(creator.draft.move_scripted_action(1, -1), "swap b above a using the genuine ↑ reorder path")
	assert_false(creator.draft.is_clear_check_currently_valid(), "reordering the same-group scripted actions invalidates")

	assert_true(creator.draft.move_scripted_action(0, 1), "move back down -- restores the original order")
	assert_true(creator.draft.is_clear_check_currently_valid(), "reverted order -> restored")

func test_clear_check_success_invalidated_by_party_member_change() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	_win_clear_check(creator)
	creator.draft.remove_party_character("hero")
	creator.draft.add_party_character("butler")
	assert_false(creator.draft.is_clear_check_currently_valid(), "a different party member entirely -> invalid")

func test_clear_check_success_invalidated_by_allowed_skill_ids_change() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	_win_clear_check(creator)
	creator.draft.set_ally_skill_allowed("hero", "hero_slash", false)
	assert_false(creator.draft.is_clear_check_currently_valid())
	creator.draft.set_ally_skill_allowed("hero", "hero_slash", true)
	assert_true(creator.draft.is_clear_check_currently_valid(), "reverted -> restored (note: this also proves a pure toggle-off-then-on, which reorders allowed_skill_ids to the end, does NOT itself invalidate -- skill-list order has no battle-mechanical effect)")

func test_clear_check_success_kept_when_only_boss_name_changes() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	_win_clear_check(creator)
	creator.draft.boss_name = "改名後のボス"
	assert_true(creator.draft.is_clear_check_currently_valid(), "boss name is explicitly not battle content (§20)")

func test_clear_check_success_kept_when_only_appearance_changes() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	_win_clear_check(creator)
	creator.draft.appearance_id = "wolf"
	assert_true(creator.draft.is_clear_check_currently_valid(), "appearance is explicitly not battle content (§20)")

func test_clear_check_success_invalidated_when_party_order_changes() -> void:
	var creator := _new_creator()
	creator.draft.boss_name = "テストボス"
	creator.draft.hp = 1
	creator.draft.atk = 1
	creator.draft.spd = 1
	creator.draft.add_party_character("hero")
	creator.draft.add_party_character("butler")
	_win_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	# reorder without changing membership or any allowed_skill_ids.
	creator.draft.party_character_ids = ["butler", "hero"]
	assert_false(creator.draft.is_clear_check_currently_valid(), "equal-SPD action order makes party array order part of battle content")

func _win_multi_turn_clear_check(creator: RBMCreatorMain) -> void:
	creator.press_clear_check()
	creator.press_clear_check_start(1)
	var view := creator._clear_check_view
	while not view.session.battle.battle_over:
		view.act_attack(view.session.battle.party[0].id)
	assert_eq(view.session.battle.winner, "ally", "sanity: the fixture is actually winnable via straight attacking")
	view._on_return_pressed()

## §29-17: a GENUINE loss (not merely an abort) on a RE-attempt against the
## exact same (already-cleared) content must not erase the success record.
## _fill_multi_turn_boss is winnable by attacking every turn, but if the
## party only ever 防御s, the boss (hero's own higher SPD means hero acts
## first each turn, so it is never damaged at all) outlasts hero's slowly
## dwindling HP -- a real, content-preserving, deterministic defeat with no
## draft changes required (hero max_hp=650, 50 boss atk halved by defend to
## 25/turn -> exactly 26 turns to 0).
func test_re_clear_check_genuine_defeat_preserves_past_success() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	_win_multi_turn_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	creator.press_clear_check()
	creator.press_clear_check_start(2)
	var view := creator._clear_check_view
	var session := view.session
	var guard := 0
	while not session.battle.battle_over and guard < 100:
		view.act_defend(session.battle.party[0].id)
		guard += 1
	assert_true(session.battle.battle_over, "sanity: the fixture actually resolves to a loss within a bounded number of turns")
	assert_eq(session.battle.winner, "boss", "sanity: this re-attempt is a genuine defeat, not a win")
	assert_true(creator.draft.is_clear_check_currently_valid(), "§16/§29-17: a genuine defeat on a re-attempt (content unchanged) must not erase the earlier success record")

## §29-18: a mid-battle abort ("Creatorに戻る" before the battle ends) on a
## re-attempt must likewise not erase the earlier success record.
func test_re_clear_check_mid_battle_abort_preserves_past_success() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	_win_multi_turn_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	creator.press_clear_check()
	creator.press_clear_check_start(2)
	var view := creator._clear_check_view
	view._on_return_pressed()  # abort without playing at all
	assert_true(creator.draft.is_clear_check_currently_valid(), "an aborted re-attempt (no win) must not erase the earlier success record")

# ---------------------------------------------------------------------------
# §30 — REWIND（Clear Checkモードとの接続）
# ---------------------------------------------------------------------------

func test_clear_check_rewind_restores_turn_hp_and_reaches_turn_1() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start(1)
	var view := creator._clear_check_view
	var session := view.session

	var turn1_hero_hp := session.battle.party[0].hp
	view.act_attack(session.battle.party[0].id)
	view.act_attack(session.battle.party[0].id)
	assert_eq(session.reachable_turns(), [1, 2, 3], "any reached turn is selectable, matching Step 4 TEST BATTLE's own REWIND list")
	assert_ne(session.battle.party[0].hp, turn1_hero_hp, "sanity: HP actually changed by turn 3")

	view.rewind_to(1)
	assert_eq(session.battle.current_turn, 1)
	assert_eq(session.battle.party[0].hp, turn1_hero_hp, "HP restored to Turn 1's start")
	assert_eq(session.reachable_turns(), [1], "future history (turns 2-3) discarded")
	assert_false(session.battle.battle_over)

func test_clear_check_rewind_reproduces_rng_and_refires_scripted_actions() -> void:
	# §30's own guidance: connection-testing, not re-proving the primitive.
	# One scripted turn_start_interrupt heal, rewound and replayed -- mirrors
	# test_rbm_battle_snapshot.gd's own dedicated coverage of this exact
	# mechanism, but driven through RBMCreatorClearCheckView this time.
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	var skill_id := str(creator.draft.skills[0]["skill_id"])
	creator.draft.add_scripted_action(1, skill_id, "turn_start_interrupt")
	creator.press_clear_check()
	creator.press_clear_check_start(1)
	var view := creator._clear_check_view
	var session := view.session
	var turn1_snapshot_reachable := session.reachable_turns()
	assert_eq(turn1_snapshot_reachable, [1])

	view.act_defend(session.battle.party[0].id)
	assert_eq(session.battle.current_turn, 2, "turn resolved and advanced (the scripted turn_start_interrupt + the normal action both fired)")

	view.rewind_to(1)
	assert_eq(session.battle.current_turn, 1)
	assert_eq(session.reachable_turns(), [1])
	# replaying with the SAME input must reproduce the SAME turn transition
	# (RNG state restored) -- if it did not, the boss's own action selection
	# could differ turn over turn even though there is only 1 candidate here,
	# so the meaningful proof is simply that resolving again succeeds and
	# behaves identically without erroring or drifting off Turn 2.
	view.act_defend(session.battle.party[0].id)
	assert_eq(session.battle.current_turn, 2, "the scripted action re-fired and the turn resolved again after REWIND, not treated as already-consumed")

## Codex最終レビュー対応④: the test above uses a boss with only ONE possible
## normal-action candidate, so a broken RNG restoration could coincidentally
## still land on the same result. This fixture has TWO real candidates with
## very different damage (0.5x vs 3.0x atk_multiplier), so a wrong RNG value
## after REWIND would visibly diverge into a DIFFERENT resulting HP, not just
## happen to match. Asserts the actual, observed battle outcome (resulting
## HP) reproduces exactly -- not merely that the internal RNG state Dictionary
## looks identical.
## 実機プレイ改善①: spdは意図的にhero(100)より低い1へ設定している
## （_fill_guaranteed_loss_boss()と同じ理由）——ボスの方が速いと、勇者が
## act_defend()を1回呼ぶだけでTurn 1の無条件直撃(構築時のadvance()で自動
## 解決済み)とTurn 2の防御軽減済み直撃の"2発分"がまとめて観測されてしまい、
## このテストが検証したい「1回の行動で軽減された1発のダメージ」を測れなく
## なる。勇者を先に行動させることで、防御宣言の直後にボスの1発だけが
## 軽減されて命中する、という単純な1対1の観測に戻す。
func _fill_branching_rng_boss(creator: RBMCreatorMain) -> void:
	creator.draft.boss_name = "分岐ボス"
	creator.draft.hp = 100000
	creator.draft.atk = 100
	creator.draft.spd = 1
	var weak_id := creator.draft.add_skill({"name": "弱撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 0.5})
	var strong_id := creator.draft.add_skill({"name": "強撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 3.0})
	creator.draft.normal_actions_enabled = true
	creator.draft.normal_action_percentages[weak_id] = 50.0
	creator.draft.normal_action_percentages[strong_id] = 50.0
	creator.draft.add_party_character("hero")

func test_clear_check_rewind_reproduces_a_genuinely_rng_branching_battle_outcome() -> void:
	var creator := _new_creator()
	_fill_branching_rng_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start(1)
	var view := creator._clear_check_view
	var session := view.session
	var hero_max_hp: int = session.battle.party[0].max_hp

	view.act_defend(session.battle.party[0].id)
	var first_hp: int = session.battle.party[0].hp
	assert_true(first_hp < hero_max_hp, "sanity: the boss's action actually dealt damage")
	# sanity: confirm this fixture genuinely CAN branch into two different
	# outcomes -- 100 atk * (0.5x or 3.0x) * 0.5 (defend) = 25 or 150 damage.
	var possible_hps: Array = [hero_max_hp - 25, hero_max_hp - 150]
	assert_true(possible_hps.has(first_hp), "the observed HP (%d) must be one of the two genuinely different possible outcomes: %s" % [first_hp, str(possible_hps)])

	view.rewind_to(1)
	assert_eq(session.battle.current_turn, 1)
	view.act_defend(session.battle.party[0].id)
	var second_hp: int = session.battle.party[0].hp
	assert_eq(second_hp, first_hp, "REWIND -> replay with the same input must reproduce the EXACT same RNG-branching outcome, not merely a coincidentally-matching one")

func test_clear_check_rewind_does_not_affect_win_or_loss_outcome() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start()
	var view := creator._clear_check_view
	var session := view.session
	var start_snapshot := session.reachable_turns()
	assert_eq(start_snapshot, [1])

	# REWIND to the only reachable turn (a no-op restore) several times --
	# §7: "REWIND使用回数はClear Checkの合否へ影響しない".
	for i in range(5):
		view.rewind_to(1)

	view.act_attack(session.battle.party[0].id)
	assert_eq(session.battle.winner, "ally")
	assert_true(creator.draft.has_ever_cleared(), "§7/§28: REWINDing beforehand never disqualifies an eventual win")

func test_clear_check_win_after_rewind_still_records_success() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start(1)
	var view := creator._clear_check_view
	var session := view.session

	view.act_attack(session.battle.party[0].id)
	view.rewind_to(1)
	while not session.battle.battle_over:
		view.act_attack(session.battle.party[0].id)
	assert_eq(session.battle.winner, "ally")
	assert_true(creator.draft.has_ever_cleared(), "a win reached via a REWIND-then-replay path still records Clear Check success")

# ---------------------------------------------------------------------------
# §31 — 最初からやり直す
# ---------------------------------------------------------------------------

func test_restart_button_requires_confirmation_before_resetting() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start(1)
	var view := creator._clear_check_view
	var session := view.session
	view.act_attack(session.battle.party[0].id)
	var turn_before := session.battle.current_turn

	view._on_restart_pressed()
	assert_true(view._restart_confirm.visible, "pressing the button alone must not reset immediately -- a confirmation appears first")
	assert_eq(session.battle.current_turn, turn_before, "nothing changed yet")

	view._on_restart_cancel_pressed()
	assert_false(view._restart_confirm.visible)
	assert_eq(session.battle.current_turn, turn_before, "キャンセルで現在の戦闘のまま")

func test_restart_confirmed_resets_to_turn_1_with_fresh_state_new_seed_and_cleared_history() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start(1)
	var view := creator._clear_check_view
	var session := view.session
	view.act_attack(session.battle.party[0].id)
	view.act_attack(session.battle.party[0].id)
	assert_eq(session.reachable_turns(), [1, 2, 3])
	# sanity: both sides had actually taken damage before the restart, so the
	# post-restart full-HP assertions below are a real reset, not a no-op.
	assert_true(session.battle.party[0].hp < session.battle.party[0].max_hp)
	assert_true(session.battle.boss.hp < session.battle.boss.max_hp)

	view._on_restart_pressed()
	view._on_restart_confirmed()

	assert_false(view._restart_confirm.visible)
	assert_eq(session.battle.current_turn, 1, "Turn 1")
	assert_eq(session.battle.party[0].hp, session.battle.party[0].max_hp, "HP/SP/etc. reset to a fresh battle's initial state")
	assert_eq(session.battle.boss.hp, session.battle.boss.max_hp)
	assert_eq(session.reachable_turns(), [1], "REWIND history reinitialized")
	assert_false(session.battle.battle_over)
	# "new RNG seed" is checked directly in the next test.

func test_restart_confirmed_uses_a_new_rng_seed() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start(1)
	var view := creator._clear_check_view
	var seed_before := view.session.battle.rng.seed
	view._on_restart_pressed()
	view._on_restart_confirmed()
	# session.restart() reseeds via randi() -- astronomically unlikely to
	# coincide with the fixed seed=1 this test started from.
	assert_ne(view.session.battle.rng.seed, seed_before, "§9: a brand new random seed, not the same fixed one the test started with")

func test_restart_from_a_cleared_draft_does_not_erase_the_success_record() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	_win_multi_turn_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	creator.press_clear_check()
	creator.press_clear_check_start(2)
	var view := creator._clear_check_view
	view.act_attack(view.session.battle.party[0].id)
	view._on_restart_pressed()
	view._on_restart_confirmed()
	assert_true(creator.draft.is_clear_check_currently_valid(), "§9/§16: restarting mid-attempt (content unchanged) never erases an existing success record")

# ---------------------------------------------------------------------------
# §32 — 中断
# ---------------------------------------------------------------------------

func test_mid_battle_return_to_creator_aborts_without_success_and_keeps_draft() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	creator.press_clear_check()
	creator.press_clear_check_start(1)
	var view := creator._clear_check_view
	view.act_attack(view.session.battle.party[0].id)
	assert_false(view.session.battle.battle_over, "sanity: still mid-battle")

	view._on_return_pressed()
	assert_true(creator._steps_root.visible, "back on the STEP views")
	assert_eq(creator.current_step, RBMCreatorMain.STEP_COUNT, "specifically STEP 7")
	assert_eq(creator.draft.boss_name, "多ターンボス", "draft preserved")
	assert_false(creator.draft.has_ever_cleared(), "an abort mid-battle is never a success")

func test_mid_battle_return_to_creator_preserves_an_existing_past_success() -> void:
	var creator := _new_creator()
	_fill_multi_turn_boss(creator)
	_win_multi_turn_clear_check(creator)
	assert_true(creator.draft.is_clear_check_currently_valid())

	creator.press_clear_check()
	creator.press_clear_check_start(3)
	var view := creator._clear_check_view
	view.act_attack(view.session.battle.party[0].id)
	view._on_return_pressed()
	assert_true(creator.draft.is_clear_check_currently_valid(), "§11/§16: aborting a re-attempt never deletes a prior success record")

# ---------------------------------------------------------------------------
# Phase 2 §25: ランダム行動notice
# ---------------------------------------------------------------------------

func test_random_action_notice_hidden_for_simple_mode_boss() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	creator.press_clear_check()
	assert_false(creator._clear_check_view._confirm_random_notice_label.visible)

## 2026-09-05全面再設計: has_random_action_variance()のHARDCORE側判定は
## 「kind==randomのスロットが2件以上の候補を持つか」だけになった（旧
## trigger_probability<100による変動という概念は撤去済み——新schemaに
## trigger_probability自体が存在しない）。固定攻撃スロット1件だけでは
## 変動が無い。
func test_random_action_notice_hidden_for_advanced_boss_with_no_variance() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	var skill_id := creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.action_sequence.clear()
	creator.draft.add_action_slot({"kind": "skill", "skill_id": skill_id, "conditions": [], "condition_logic": "AND", "max_uses": -1})
	creator.press_clear_check()
	assert_false(creator._clear_check_view._confirm_random_notice_label.visible, "a fixed single-skill slot has no run-to-run variance")

func test_random_action_notice_shown_for_slot_with_two_or_more_random_candidates() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	var skill_a := creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	var skill_b := creator.draft.add_skill({"name": "咆哮", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 0.5})
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.action_sequence.clear()
	creator.draft.add_action_slot({
		"kind": "random", "mode": "even",
		"candidates": [{"skill_id": skill_a, "weight": 50.0}, {"skill_id": skill_b, "weight": 50.0}],
		"conditions": [], "condition_logic": "AND", "max_uses": -1,
	})
	creator.press_clear_check()
	assert_true(creator._clear_check_view._confirm_random_notice_label.visible)

## 境界値確認: ランダム攻撃であっても候補がちょうど1件しか無ければ実際には
## 選択の余地(変動)が無い——has_random_action_variance()の">1"比較の
## 境界を直接確認する（旧「発動確率50%」テストが担っていた"3つ目の
## 独立したシナリオ"としての役割を、新schemaで実際に意味を持つこの境界
## テストへ置き換えたもの）。
func test_random_action_notice_hidden_for_random_slot_with_only_one_candidate() -> void:
	var creator := _new_creator()
	_fill_easy_win_boss(creator)
	var skill_id := creator.draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	creator.draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	creator.draft.action_sequence.clear()
	creator.draft.add_action_slot({
		"kind": "random", "mode": "even",
		"candidates": [{"skill_id": skill_id, "weight": 100.0}],
		"conditions": [], "condition_logic": "AND", "max_uses": -1,
	})
	creator.press_clear_check()
	assert_false(creator._clear_check_view._confirm_random_notice_label.visible, "候補が1件だけのランダム攻撃には変動が無い")
