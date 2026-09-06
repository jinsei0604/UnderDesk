extends GutTest

## RPG BOSS MAKER Phase 1 Step 7 — CHALLENGEの統合テスト。RBMChallengeEntry
## （一覧・検索・確認・戦闘の統括）を実際のControlツリーとしてインスタンス化
## し、公開メソッド/シグナル経由で駆動する（このプロジェクト既存の"実UIを
## 本物のまま動かす"規約、test_rbm_creator_save_load.gd等と同じ）。
##
## 実プレイヤーのuser://保存ライブラリを一切汚さないよう、専用のテスト用
## ディレクトリへ差し替えて実行する。

const TEST_DIR := "user://bossmaker_test_challenge/stages"

func before_each() -> void:
	RBMLocalStageRepository.set_stages_dir_for_testing(TEST_DIR)

func after_each() -> void:
	_remove_recursive(TEST_DIR)
	RBMLocalStageRepository.set_stages_dir_for_testing("")

func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := path + "/" + entry
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

func _new_entry() -> RBMChallengeEntry:
	var entry := RBMChallengeEntry.new()
	add_child_autofree(entry)
	return entry

func _new_creator() -> RBMCreatorMain:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	return creator

# ---------------------------------------------------------------------------
# fixtures
# ---------------------------------------------------------------------------

func _basic_playable_draft(boss_name: String = "テストボス") -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1000
	draft.atk = 100
	draft.spd = 50
	draft.add_skill({"name": "斬撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	draft.add_party_character("hero")
	return draft

func _save_playable_boss(boss_name: String = "テストボス") -> String:
	var result := RBMLocalStageRepository.save_new(_basic_playable_draft(boss_name))
	return str(result.get("stage_id", ""))

## Creator UI改修（2026-09-05）§24〜§27（公開機能、ユーザー確定仕様）:
## 「Definitionとして正常＝自動的に挑戦可能」という旧来の契約は、公開状態
## から分離された——CHALLENGE一覧への露出にはClear Check達成"かつ"明示的な
## 公開の両方が必要（Clear Check達成だけでも自動公開しない）。この専用
## ヘルパーは、実際にCHALLENGE一覧へ表示させる必要がある少数のテスト
## （検索/一覧表示系）専用——_save_playable_boss()自身は「保存済みだが
## 未公開」という、他の多くのテスト（確認画面の直接表示・未クリア文言等）
## が引き続き必要とする状態のまま無改修で維持する。
func _save_published_boss(boss_name: String = "テストボス") -> String:
	var draft := _basic_playable_draft(boss_name)
	draft.record_clear_check_success()
	assert_true(draft.publish(), "sanity: Clear Check達成済みのため公開できること")
	var result := RBMLocalStageRepository.save_new(draft)
	return str(result.get("stage_id", ""))

## §2: 空パーティのままではRBMDefinitionLoader.resolve()が失敗する
## （MIN_PARTY_SIZE=1未満）——is_playable()==falseの"下書き"stageを作る。
func _save_unplayable_draft(boss_name: String = "未完成ボス") -> String:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	var result := RBMLocalStageRepository.save_new(draft)
	return str(result.get("stage_id", ""))

## §30: 挑戦者側が確実に1ターン目で勝利する(boss.hp=1)stage。
func _save_boss_that_dies_in_one_hit(boss_name: String = "一撃ボス") -> String:
	var draft := _basic_playable_draft(boss_name)
	draft.hp = 1
	var result := RBMLocalStageRepository.save_new(draft)
	return str(result.get("stage_id", ""))

## §30: 挑戦者側が確実に1ターン目で敗北する(boss ATKが極端に高い)stage。
func _save_boss_that_wins_immediately(boss_name: String = "即死ボス") -> String:
	var draft := RBMCreatorDraft.new()
	draft.boss_name = boss_name
	draft.hp = 1000000
	draft.atk = 9999
	draft.spd = 500
	var atk_id := draft.add_skill({"name": "即死級攻撃", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 50.0})
	draft.normal_actions_enabled = true
	draft.normal_action_percentages[atk_id] = 100.0
	draft.add_party_character("hero")
	var result := RBMLocalStageRepository.save_new(draft)
	return str(result.get("stage_id", ""))

func _open_confirm(entry: RBMChallengeEntry, stage_id: String) -> void:
	entry._on_stage_row_pressed(stage_id)

## 実機プレイ改善①: 「全員分の行動予約」＋「行動開始」ボタンは廃止された
## ——act_attack()は選択と同時に即座に解決し、続けてボスの番等の自動解決分
## までまとめて進める（RBMChallengeSession.resolve_ally_action()の仕様）。
func _win_immediately(view: RBMChallengeBattleView) -> void:
	view.act_attack(0)

# ---------------------------------------------------------------------------
# §2/§3/§5 — CHALLENGE一覧・検索
# ---------------------------------------------------------------------------

## Creator UI改修（2026-09-05）§24〜§27: 保存しただけ（Clear Check未達成・
## 未公開）ではCHALLENGE一覧に一切表示されない——旧来の「Definitionとして
## 正常なら自動的に挑戦可能」という契約は公開状態から分離された
## （ユーザー確定仕様のテスト項目2「保存しただけではCHALLENGEに表示
## されない」）。
func test_list_excludes_playable_but_unpublished_stages() -> void:
	_save_playable_boss("未公開ボス")
	var entry := _new_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 0, "saving alone (without an explicit publish) must never expose a stage to CHALLENGE")

func test_list_excludes_unplayable_draft_stages() -> void:
	_save_unplayable_draft("下書きボス")
	var entry := _new_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 0, "draft (unplayable) stages must never appear in CHALLENGE list")

## §24〜§27: Clear Check達成"だけ"では自動公開しない（ユーザー確定仕様の
## テスト項目3「Clear Check達成だけではCHALLENGEに表示されない」）——
## 公開は作者が明示的にpublish()（最終確認画面の[公開]ボタン相当）を
## 押した場合のみ。
func test_list_excludes_clear_checked_but_unpublished_stages() -> void:
	var draft := _basic_playable_draft("クリア済み未公開ボス")
	draft.record_clear_check_success()
	RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 0, "achieving Clear Check alone must not auto-publish a stage")

## §24〜§27: Clear Check達成後に明示的に公開したstageだけがCHALLENGE一覧に
## 表示される（ユーザー確定仕様のテスト項目4）。
func test_list_includes_published_stages() -> void:
	_save_published_boss("公開済みボス")
	var entry := _new_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 1, "an explicitly published stage must appear in CHALLENGE")

func test_list_search_by_boss_name_is_case_insensitive_partial_match() -> void:
	_save_published_boss("Dragon King")
	_save_published_boss("Slime")
	var entry := _new_entry()
	entry._name_search_field.text = "dragon"
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 1)

func test_list_search_by_stage_id_is_exact_match_only() -> void:
	var id_a := _save_published_boss("A")
	_save_published_boss("B")
	var entry := _new_entry()
	entry._id_search_field.text = id_a
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 1)
	entry._id_search_field.text = id_a.substr(0, 5)
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 0, "stage_id search must be an exact 10-digit match, not a partial one")

## CHALLENGE UI再設計 §9: 一覧カードは全カテゴリ共通の6項目（画像/ボス名/
## 作者名/モード/挑戦者数/クリア率）を必ず表示する——旧「クリアチェック
## 済み」バッジは新カード仕様に含まれないため退役し、実際に新カードが
## 持つ具体的な情報を検証するテストへ置き換えた。
func test_list_card_shows_the_six_mandated_fields() -> void:
	var draft := _basic_playable_draft("カード項目確認")
	draft.set_author_name("KASA")
	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	draft.action_sequence.clear()
	draft.add_action_slot({"kind": RBMActionPatternRules.SLOT_KIND_SKILL, "skill_id": str(draft.skills[0].get("skill_id", "")), "conditions": [], "condition_logic": "AND", "max_uses": -1})
	draft.record_clear_check_success()
	assert_true(draft.publish())
	var result := RBMLocalStageRepository.save_new(draft)
	var stage_id := str(result.get("stage_id", ""))
	RBMLocalStageRepository.record_challenge_attempt(stage_id)
	RBMLocalStageRepository.record_challenge_attempt(stage_id)
	RBMLocalStageRepository.record_challenge_clear(stage_id)

	var entry := _new_entry()
	entry._refresh_list()
	var card: PanelContainer = entry._list_rows.get_child(0)
	assert_eq(card.name, "BossCard_%s" % stage_id)
	var name_label: Label = card.find_child("BossCardNameLabel_%s" % stage_id, true, false)
	assert_eq(name_label.text, "カード項目確認")
	var author_label: Label = card.find_child("BossCardAuthorLabel_%s" % stage_id, true, false)
	assert_true(author_label.text.contains("KASA"))
	var mode_label: Label = card.find_child("BossCardModeLabel_%s" % stage_id, true, false)
	assert_eq(mode_label.text, "HARDCORE")
	var challenge_count_label: Label = card.find_child("BossCardChallengeCountLabel_%s" % stage_id, true, false)
	assert_true(challenge_count_label.text.contains("2"), "2 recorded attempts must show as 挑戦 2回, a count of times not people")
	assert_true(challenge_count_label.text.contains("回"), "must read as a count of attempts (回), never a headcount (人/者)")
	var clear_rate_label: Label = card.find_child("BossCardClearRateLabel_%s" % stage_id, true, false)
	assert_true(clear_rate_label.text.contains("50.0%"), "1 clear out of 2 attempts must show the real (uncorrected) 50% clear rate")

# ---------------------------------------------------------------------------
# §6/§7 — 挑戦確認画面: 選択即戦闘開始しない
# ---------------------------------------------------------------------------

func test_selecting_a_stage_shows_the_confirm_screen_not_the_battle_immediately() -> void:
	var stage_id := _save_playable_boss()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	assert_true(entry._confirm_view.visible)
	assert_false(entry._battle_view.visible)

func test_confirm_screen_shows_boss_name_appearance_and_stage_id() -> void:
	var draft := _basic_playable_draft("確認ボス")
	draft.appearance_id = "appearance_dragon"
	var result := RBMLocalStageRepository.save_new(draft)
	var stage_id := str(result.get("stage_id", ""))
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	assert_true(entry._confirm_view._boss_name_label.text.contains("確認ボス"))
	assert_true(entry._confirm_view._stage_id_label.text.contains(stage_id))
	assert_true(entry._confirm_view._appearance_label.text.contains(RBMCreatorAppearanceCatalog.display_name("appearance_dragon")))

## §8: 未クリアであることを危険/非推奨のニュアンスなしに伝える固定文言。
func test_confirm_screen_shows_uncleared_message_for_never_cleared_stage() -> void:
	var stage_id := _save_playable_boss()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	# 実機プレイ改善③ item8/11: "Clear Check"混在表記を統一して日本語化。
	assert_eq(entry._confirm_view._clear_check_label.text, "このボス戦はクリアチェックされていません")

func test_confirm_screen_shows_clear_checked_mark_for_cleared_stage() -> void:
	var draft := _basic_playable_draft("済確認")
	draft.record_clear_check_success()
	var result := RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	_open_confirm(entry, str(result.get("stage_id", "")))
	assert_true(entry._confirm_view._clear_check_label.text.contains("クリアチェック済み"))

## §9/§10: 勝利条件・特殊条件は常に表示され、公開設定を非公開にしても隠れない。
func test_confirm_screen_always_shows_win_condition_and_special_condition_even_when_all_hidden() -> void:
	var draft := _basic_playable_draft("非公開ボス")
	draft.set_all_challenge_info_visible(false)
	var result := RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	_open_confirm(entry, str(result.get("stage_id", "")))
	assert_false(entry._confirm_view._win_condition_label.text.is_empty())
	assert_true(entry._confirm_view._win_condition_label.text.contains("勝利条件"))
	assert_true(entry._confirm_view._special_condition_label.text.contains("特殊条件"))

## §16: 作者備考は常に表示。
func test_confirm_screen_shows_author_notes() -> void:
	var draft := _basic_playable_draft("備考ボス")
	draft.set_author_notes("氷属性の攻撃に注意")
	var result := RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	_open_confirm(entry, str(result.get("stage_id", "")))
	assert_true(entry._confirm_view._author_notes_label.text.contains("氷属性の攻撃に注意"))

## Phase 2 §25: ランダム行動notice（Clear Check側と同一条件、
## test_rbm_clear_check.gdのnoticeテストと対になる）。
func test_confirm_screen_hides_random_action_notice_for_simple_mode_boss() -> void:
	var stage_id := _save_playable_boss("シンプルボス")
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	assert_false(entry._confirm_view._random_notice_label.visible)

func test_confirm_screen_shows_random_action_notice_for_boss_with_random_step() -> void:
	var draft := _basic_playable_draft("ランダムボス")
	var skill_b := draft.add_skill({"name": "咆哮", "type": "attack", "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 0.5})
	draft.set_creator_mode(RBMCreatorDraft.CREATOR_MODE_ADVANCED)
	draft.action_sequence.clear()
	draft.add_action_slot({
		"kind": "random", "mode": "even",
		"candidates": [{"skill_id": str(draft.skills[0].get("skill_id", "")), "weight": 50.0}, {"skill_id": skill_b, "weight": 50.0}],
		"conditions": [], "condition_logic": "AND", "max_uses": -1,
	})
	var result := RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	_open_confirm(entry, str(result.get("stage_id", "")))
	assert_true(entry._confirm_view._random_notice_label.visible)

# ---------------------------------------------------------------------------
# §14/§18 — 情報公開設定
# ---------------------------------------------------------------------------

func test_confirm_screen_shows_real_stats_when_visible() -> void:
	var draft := _basic_playable_draft("公開ボス")
	draft.hp = 4242
	var result := RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	_open_confirm(entry, str(result.get("stage_id", "")))
	assert_true(entry._confirm_view._stats_label.text.contains("4242"))

func test_confirm_screen_masks_hp_atk_spd_individually() -> void:
	var draft := _basic_playable_draft("HP非公開ボス")
	draft.hp = 4242
	draft.set_challenge_info_visible("hp", false)
	var result := RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	_open_confirm(entry, str(result.get("stage_id", "")))
	assert_false(entry._confirm_view._stats_label.text.contains("4242"), "hidden HP must not leak the real value")
	assert_true(entry._confirm_view._stats_label.text.contains("？？？"))
	assert_true(entry._confirm_view._stats_label.text.contains(str(draft.atk)), "hiding hp alone must not also hide atk")

func test_confirm_screen_masks_weak_and_resist_attributes_independently() -> void:
	var draft := _basic_playable_draft("弱点非公開ボス")
	draft.toggle_weak_attribute("FIRE")
	draft.toggle_resist_attribute("ICE")
	draft.set_challenge_info_visible("weak_attributes", false)
	var result := RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	_open_confirm(entry, str(result.get("stage_id", "")))
	assert_true(entry._confirm_view._weak_label.text.contains("？？？"))
	# 実機プレイ改善③ item8/11: 属性は日本語ラベル（"ICE"→「氷」）で表示される。
	assert_true(entry._confirm_view._resist_label.text.contains("氷"), "resist must stay visible independently of weak's own toggle")

func test_confirm_screen_masks_boss_skills_as_a_single_category_not_individually() -> void:
	var draft := _basic_playable_draft("スキル非公開ボス")
	draft.set_challenge_info_visible("boss_skills", false)
	var result := RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	_open_confirm(entry, str(result.get("stage_id", "")))
	var texts: Array = []
	for child in entry._confirm_view._boss_skills_section.get_children():
		texts.append((child as Label).text)
	assert_true(texts.has("非公開"))
	assert_false(String("\n".join(texts)).contains("斬撃"), "the real skill name must never leak while hidden")

## §14: 公開時は「詳細」の名にふさわしく、スキル名だけでなく種類/対象/属性/
## 倍率まで見せること。
func test_confirm_screen_shows_full_skill_mechanics_when_boss_skills_visible() -> void:
	var stage_id := _save_playable_boss("スキル公開ボス")
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	var texts: Array = []
	for child in entry._confirm_view._boss_skills_section.get_children():
		texts.append((child as Label).text)
	var joined := String("\n".join(texts))
	assert_true(joined.contains("斬撃"))
	assert_true(joined.contains("ATK"), "public boss_skills must show the real multiplier/mechanics, not just the flavor name")

## 公開設定の最終修正（7→6項目）: 「攻略側パーティ詳細」というキー自体を
## 廃止した。挑戦者自身のパーティ・使用可能スキルは、いかなる公開設定にも
## 紐づかず常に表示される——「すべて非公開」で他の6項目をすべて隠しても、
## パーティ情報だけは一切影響を受けないことを直接確認する（§8項目5）。
func test_confirm_screen_always_shows_the_challengers_own_party_even_after_hide_all() -> void:
	var draft := _basic_playable_draft("すべて非公開ボス")
	draft.set_all_challenge_info_visible(false)
	var result := RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	_open_confirm(entry, str(result.get("stage_id", "")))
	assert_gt(entry._confirm_view._party_section.get_child_count(), 1, "party section must still list the actual party member(s), even with every other category hidden")

# ---------------------------------------------------------------------------
# §21〜§26 — CHALLENGE戦闘: 実RBMBattleを使う、REWIND無し、Clear Check非記録
# ---------------------------------------------------------------------------

func test_pressing_challenge_starts_a_real_battle_using_the_saved_definition() -> void:
	var stage_id := _save_playable_boss("戦闘開始ボス")
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	assert_true(entry._battle_view.visible)
	assert_not_null(entry._battle_view.session.battle)
	assert_eq(entry._battle_view.session.battle.boss.display_name, "戦闘開始ボス")

func test_challenge_battle_view_has_no_rewind_ui() -> void:
	var stage_id := _save_playable_boss()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	assert_false(entry._battle_view.has_method("rewind_to"))
	assert_false(entry._battle_view.has_node("RewindList"))

## §30: 勝敗はRBMBattle.battle_over/winnerだけで判定される——一撃で倒せる
## 極端なボスに対し、通常攻撃1回で実際に勝利することを直接確認する
## （独自のboss.hp<=0判定を書いていないことの間接証明にもなる：もし壊れて
## いれば実バトルの結果自体がここで食い違う）。
func test_winning_a_real_battle_shows_clear_outcome() -> void:
	var stage_id := _save_boss_that_dies_in_one_hit()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	_win_immediately(entry._battle_view)
	assert_true(entry._battle_view.session.battle.battle_over)
	assert_eq(entry._battle_view.session.battle.winner, "ally")
	# 実機プレイ改善③ item8: "CLEAR!"/"DEFEAT"は「クリア！」/「敗北」へ日本語化。
	assert_eq(entry._battle_view._outcome_label.text, "クリア！")
	assert_true(entry._battle_view._outcome_area.visible)

func test_losing_a_real_battle_shows_defeat_outcome() -> void:
	var stage_id := _save_boss_that_wins_immediately()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	assert_true(entry._battle_view.session.battle.battle_over)
	assert_eq(entry._battle_view.session.battle.winner, "boss")
	assert_eq(entry._battle_view._outcome_label.text, "敗北")

## §25: CHALLENGEの勝利はClear Check成功として記録されない
## （TEST BATTLEの既存の扱いをそのまま踏襲——新しい仕様ではなく確認事項）。
func test_winning_a_challenge_never_records_clear_check_success() -> void:
	var stage_id := _save_boss_that_dies_in_one_hit("Clear Check非記録ボス")
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	var draft_before_battle := entry._confirm_view._draft
	assert_false(draft_before_battle.has_ever_cleared(), "sanity")
	entry._confirm_view._on_challenge_pressed()
	_win_immediately(entry._battle_view)
	assert_false(draft_before_battle.has_ever_cleared(), "a CHALLENGE win must never call record_clear_check_success()")
	# 保存ファイル自体も無傷であることを合わせて確認する（CHALLENGEはRepository
	# を一切書き換えない）。
	var reloaded := RBMLocalStageRepository.load_stage(stage_id)
	var reloaded_draft := RBMCreatorDraft.new()
	reloaded_draft.restore_clear_check_snapshot(reloaded.get("clear_check_data", {}))
	assert_false(reloaded_draft.has_ever_cleared())

# ---------------------------------------------------------------------------
# §27/§28 — 最初からやり直す（確認あり）
# ---------------------------------------------------------------------------

func test_restart_button_shows_a_confirmation_before_acting() -> void:
	var stage_id := _save_playable_boss()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view._on_restart_pressed()
	assert_true(entry._battle_view._restart_confirm.visible)
	assert_eq(entry._battle_view.session.battle.current_turn, 1, "must not have actually restarted yet -- only the confirmation is showing")

func test_restart_cancel_leaves_battle_state_untouched() -> void:
	var stage_id := _save_playable_boss()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	var turn_after_one_action := entry._battle_view.session.battle.current_turn
	entry._battle_view._on_restart_pressed()
	entry._battle_view._on_restart_cancel_pressed()
	assert_false(entry._battle_view._restart_confirm.visible)
	assert_eq(entry._battle_view.session.battle.current_turn, turn_after_one_action)

func test_restart_confirmed_resets_to_turn_1_and_full_hp() -> void:
	var stage_id := _save_playable_boss()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	entry._battle_view._on_restart_pressed()
	entry._battle_view._on_restart_confirmed()
	assert_false(entry._battle_view._restart_confirm.visible)
	assert_eq(entry._battle_view.session.battle.current_turn, 1)
	assert_eq(entry._battle_view.session.battle.boss.hp, entry._battle_view.session.battle.boss.max_hp)

# ---------------------------------------------------------------------------
# §29 — 挑戦をやめる（確認あり、勝敗どちらにも記録されない）
# ---------------------------------------------------------------------------

func test_quit_button_shows_a_confirmation_before_returning_to_list() -> void:
	var stage_id := _save_playable_boss()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view._on_quit_pressed()
	assert_true(entry._battle_view._quit_confirm.visible)
	assert_true(entry._battle_view.visible, "must still be on the battle screen -- only the confirmation is showing")

func test_quit_cancel_stays_on_the_battle_screen() -> void:
	var stage_id := _save_playable_boss()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view._on_quit_pressed()
	entry._battle_view._on_quit_cancel_pressed()
	assert_false(entry._battle_view._quit_confirm.visible)
	assert_true(entry._battle_view.visible)

func test_quit_confirmed_returns_to_the_challenge_list() -> void:
	var stage_id := _save_playable_boss()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view._on_quit_pressed()
	entry._battle_view._on_quit_confirmed()
	assert_true(entry._list_panel.visible)
	assert_false(entry._battle_view.visible)

## §29: 途中でやめても勝敗どちらにも記録されない——draftのClear Check
## snapshotが未クリアのまま、保存ファイルも無傷。
func test_quitting_mid_battle_is_never_recorded_as_a_win_or_a_loss() -> void:
	var stage_id := _save_playable_boss("途中退出ボス")
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	var draft_before_battle := entry._confirm_view._draft
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	entry._battle_view._on_quit_pressed()
	entry._battle_view._on_quit_confirmed()
	assert_false(draft_before_battle.has_ever_cleared())

# ---------------------------------------------------------------------------
# §32/§33/§34 — 結果画面: 勝利・敗北どちらも「もう一度挑戦」を確認なしで表示
# ---------------------------------------------------------------------------

func test_win_result_screen_shows_both_retry_and_return_to_list_buttons() -> void:
	var stage_id := _save_boss_that_dies_in_one_hit()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	_win_immediately(entry._battle_view)
	assert_true(entry._battle_view._retry_button.visible)
	assert_true(entry._battle_view._return_button.visible)

func test_lose_result_screen_shows_both_retry_and_return_to_list_buttons() -> void:
	var stage_id := _save_boss_that_wins_immediately()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	assert_true(entry._battle_view._retry_button.visible)
	assert_true(entry._battle_view._return_button.visible)

## §34: 結果画面からの「もう一度挑戦」は確認なしで即座に再挑戦できる
## （戦闘途中の「最初からやり直す」とは違い、既に決着済みで失うものが
## 無いため）。
func test_retry_from_result_screen_needs_no_confirmation() -> void:
	var stage_id := _save_boss_that_dies_in_one_hit()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	_win_immediately(entry._battle_view)
	entry._battle_view._on_retry_pressed()
	assert_false(entry._battle_view._restart_confirm.visible, "no confirmation dialog should ever appear for a from-result retry")
	assert_eq(entry._battle_view.session.battle.current_turn, 1)
	assert_false(entry._battle_view.session.battle.battle_over)
	assert_false(entry._battle_view._outcome_area.visible)

func test_return_to_list_from_result_screen_goes_back_to_the_challenge_list() -> void:
	var stage_id := _save_boss_that_dies_in_one_hit()
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	_win_immediately(entry._battle_view)
	entry._battle_view._on_return_pressed()
	assert_true(entry._list_panel.visible)

# ---------------------------------------------------------------------------
# §36/§37/§58 — Creatorの未保存変更からの分離
# ---------------------------------------------------------------------------

## 明示的な6段階シナリオ: stage Aを保存 → Creatorで開く → 内容をBへ編集
## （保存しない） → CHALLENGE開始 → CHALLENGEは保存済みのA内容を使うこと。
func test_challenge_uses_the_saved_content_not_an_unsaved_creator_edit() -> void:
	var stage_id := _save_playable_boss("保存済みA")
	var creator := _new_creator()
	var load_result := creator.start_loaded(stage_id)
	assert_true(bool(load_result.get("ok", false)), "sanity")
	# Creator上でだけ内容をB相当へ編集する（保存しない）。
	creator.draft.boss_name = "未保存B"
	creator.draft.hp = 99999
	assert_true(creator.has_unsaved_changes(), "sanity: the edit really is unsaved")

	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	assert_eq(entry._confirm_view._draft.boss_name, "保存済みA", "CHALLENGE must read from the SAVED content, never the in-memory Creator draft")
	assert_ne(entry._confirm_view._draft.hp, 99999)

	entry._confirm_view._on_challenge_pressed()
	assert_eq(entry._battle_view.session.battle.boss.display_name, "保存済みA", "the actual battle definition must also be the saved content")

# ---------------------------------------------------------------------------
# §23/§37/§59 — 進行中セッションのDefinitionは固定される
# ---------------------------------------------------------------------------

## 進行中のCHALLENGEセッション開始後にCreatorで同じstageを上書き保存しても、
## 既に開始済みの戦闘セッションは影響を受けない（Definitionはセッション開始
## 時点で1回だけ複製・固定される）。
func test_an_in_progress_challenge_session_is_unaffected_by_a_concurrent_overwrite_save() -> void:
	var stage_id := _save_playable_boss("進行中固定")
	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	var hp_at_start := entry._battle_view.session.battle.boss.max_hp

	var creator := _new_creator()
	creator.start_loaded(stage_id)
	creator.draft.hp = 555555
	RBMLocalStageRepository.overwrite(stage_id, creator.draft)

	assert_eq(entry._battle_view.session.battle.boss.max_hp, hp_at_start, "an already-running CHALLENGE session's Definition must never be re-read from disk mid-session")

	# restart()すら、セッション開始時に固定されたDefinitionを使い続ける
	# （再ロードする経路が無いことの追加確認）。
	entry._battle_view.session.restart()
	assert_eq(entry._battle_view.session.battle.boss.max_hp, hp_at_start)

# ---------------------------------------------------------------------------
# Codex最終レビュー指摘対応 §5〜§8 — 実UI経由のマスク同期・具体表示・戻る
# ---------------------------------------------------------------------------

## §5/§6: 実際のSTEP7 CheckBox一括ボタン（すべて非公開→すべて公開）で
## draftを操作した直後、その同じdraftインスタンスをCHALLENGE確認画面へ渡すと
## 実際のマスク表示（？？？/非公開↔実値）へ反映されること。
func test_confirm_screen_reflects_a_real_step7_hide_all_then_show_all_button_press() -> void:
	var creator := RBMCreatorMain.new()
	add_child_autofree(creator)
	creator.draft.boss_name = "実UI公開設定ボス"
	creator.draft.hp = 4242
	creator.draft.atk = 313
	creator.draft.spd = 271
	creator.draft.toggle_weak_attribute("FIRE")
	creator.draft.toggle_resist_attribute("ICE")
	creator.draft.add_skill({"name": "極秘炎撃", "type": "attack", "target": "all", "attribute": "FIRE", "atk_multiplier": 7.25})
	creator.draft.add_party_character("hero")
	creator.go_to_step(5)
	var step7: RBMCreatorStep7Summary = creator._step_views[4]
	var hide_all_button: Button = step7.find_child("HideAllVisibilityButton", true, false)
	assert_not_null(hide_all_button, "sanity")
	hide_all_button.pressed.emit()

	var confirm_view := RBMChallengeConfirmView.new()
	add_child_autofree(confirm_view)
	confirm_view.open("0000000000", creator.draft)

	assert_true(confirm_view._stats_label.text.contains("HP ？？？"), "hidden HP must have its own placeholder")
	assert_false(confirm_view._stats_label.text.contains("HP 4242"), "hidden HP must not leak its real value")
	assert_true(confirm_view._stats_label.text.contains("ATK ？？？"), "hidden ATK must have its own placeholder")
	assert_false(confirm_view._stats_label.text.contains("ATK 313"), "hidden ATK must not leak its real value")
	assert_true(confirm_view._stats_label.text.contains("SPD ？？？"), "hidden SPD must have its own placeholder")
	assert_false(confirm_view._stats_label.text.contains("SPD 271"), "hidden SPD must not leak its real value")
	# 実機プレイ改善③ item8/11: 属性は日本語ラベル（"FIRE"→「炎」/"ICE"→「氷」）
	# で表示されるため、leak-checkも実際に表示され得るラベルへ合わせる。
	assert_eq(confirm_view._weak_label.text, "弱点: ？？？", "hidden weakness must have its own placeholder")
	assert_false(confirm_view._weak_label.text.contains("炎"), "hidden weakness must not leak its real content")
	assert_eq(confirm_view._resist_label.text, "耐性: ？？？", "hidden resistance must have its own placeholder")
	assert_false(confirm_view._resist_label.text.contains("氷"), "hidden resistance must not leak its real content")
	var boss_skill_texts: Array = []
	for child in confirm_view._boss_skills_section.get_children():
		boss_skill_texts.append((child as Label).text)
	var hidden_boss_skills := String("\n".join(boss_skill_texts))
	assert_true(boss_skill_texts.has("非公開"), "hidden boss skills must show the private marker")
	assert_false(hidden_boss_skills.contains("極秘炎撃"), "hidden boss skills must not leak the real skill name")
	assert_false(hidden_boss_skills.contains("攻撃"), "hidden boss skills must not leak the real skill type")
	assert_false(hidden_boss_skills.contains("全体"), "hidden boss skills must not leak the real target")
	assert_false(hidden_boss_skills.contains("炎"), "hidden boss skills must not leak the real attribute")
	assert_false(hidden_boss_skills.contains("7.25"), "hidden boss skills must not leak the real multiplier/detail")

	var show_all_button: Button = step7.find_child("ShowAllVisibilityButton", true, false)
	assert_not_null(show_all_button, "sanity")
	show_all_button.pressed.emit()
	confirm_view.open("0000000000", creator.draft)

	assert_true(confirm_view._stats_label.text.contains("HP 4242"), "show all must restore the real HP")
	assert_true(confirm_view._stats_label.text.contains("ATK 313"), "show all must restore the real ATK")
	assert_true(confirm_view._stats_label.text.contains("SPD 271"), "show all must restore the real SPD")
	assert_eq(confirm_view._weak_label.text, "弱点: 炎", "show all must restore the real weakness")
	assert_eq(confirm_view._resist_label.text, "耐性: 氷", "show all must restore the real resistance")
	var public_boss_skill_texts: Array = []
	for child in confirm_view._boss_skills_section.get_children():
		public_boss_skill_texts.append((child as Label).text)
	var public_boss_skills := String("\n".join(public_boss_skill_texts))
	assert_true(public_boss_skills.contains("極秘炎撃"), "show all must restore the real boss skill name")
	assert_true(public_boss_skills.contains("攻撃"), "show all must restore the real boss skill type")
	assert_true(public_boss_skills.contains("全体"), "show all must restore the real boss skill target")
	assert_true(public_boss_skills.contains("炎"), "show all must restore the real boss skill attribute")
	assert_true(public_boss_skills.contains("7.25"), "show all must restore the real boss skill multiplier/detail")

## §7: 「すべて非公開」後でも、挑戦確認画面のパーティ・スキル欄に具体的な
## キャラクター名・スキル名が表示されること——Containerの子ノード数だけで
## なく、実際のマスターデータ（既存のBoss Maker専用マスター"hero"）から
## 導出した期待文字列がLabel.textへ含まれることを直接検証する。
func test_party_and_skill_names_are_concretely_shown_even_after_hide_all() -> void:
	var draft := _basic_playable_draft("具体表示ボス")
	draft.set_all_challenge_info_visible(false)
	var master := draft.master_character_def("hero")
	var expected_name := str(master.get("display_name", "hero"))
	var allowed: Array = draft.ally_allowed_skill_ids.get("hero", [])
	assert_false(allowed.is_empty(), "sanity: hero must have at least one allowed skill by default")
	var first_skill_id := str(allowed[0])
	var expected_skill_name := ""
	for skill in master.get("skills", []):
		if str(skill.get("id", "")) == first_skill_id:
			expected_skill_name = str(skill.get("display_name", ""))
			break
	assert_false(expected_skill_name.is_empty(), "sanity")

	var result := RBMLocalStageRepository.save_new(draft)
	var entry := _new_entry()
	_open_confirm(entry, str(result.get("stage_id", "")))

	var party_texts: Array = []
	for child in entry._confirm_view._party_section.get_children():
		party_texts.append((child as Label).text)
	var joined := String("\n".join(party_texts))
	assert_true(joined.contains(expected_name), "the real character display_name must appear even with hide-all active")
	assert_true(joined.contains(expected_skill_name), "the real skill display_name must appear even with hide-all active")

## §8: CHALLENGE一覧→選択→確認画面まで実際に進め、実際の「戻る」ボタンの
## pressedシグナルを発火して戻る（戻る関数を直接呼ぶのではなく実signal経由）。
## CHALLENGE UI再設計 §7/§11/§17: 独立した確認ステップという概念自体が
## 廃止された（一覧と詳細は常に横並びで同時表示される）ため、旧
## ConfirmBackButton（確認画面→一覧のみへ戻る）は退役した。「戻る」の
## 役割は共通一覧画面自身のヘッダにある「← 挑戦ハブ」(BackToHubButton)へ
## 移った——一覧+詳細の組から挑戦ハブへ戻る、という新しい導線を検証する。
func test_back_to_hub_button_real_press_returns_to_the_hub_without_starting_a_battle() -> void:
	var stage_id := _save_published_boss("戻るテストボス")
	var entry := _new_entry()
	entry.enter_challenge()
	assert_true(entry._hub_view.visible, "sanity: enter_challenge()は挑戦ハブを表示する")

	_open_confirm(entry, stage_id)
	assert_true(entry._list_panel.visible, "sanity: 選択すると一覧+詳細画面が表示される")
	assert_true(entry._confirm_view.visible, "sanity")
	assert_false(entry._battle_view.visible, "sanity")

	assert_null(entry._confirm_view.find_child("ConfirmBackButton", true, false), "the old standalone-confirm-step back button must no longer exist")

	var back_to_hub_button: Button = entry._list_panel.find_child("BackToHubButton", true, false)
	assert_not_null(back_to_hub_button, "sanity")
	back_to_hub_button.pressed.emit()

	assert_true(entry._hub_view.visible, "the real ← 挑戦ハブ button must return to the hub")
	assert_false(entry._list_panel.visible, "the list+detail screen must be hidden")
	assert_false(entry._confirm_view.visible)
	assert_false(entry._battle_view.visible)
	assert_null(entry._battle_view.session, "no battle session must have been started")

	# ハブから同じカテゴリ検索へ戻ると、一覧は健在なまま（無傷）であること。
	entry._on_hub_search_requested()
	assert_eq(entry._list_rows.get_child_count(), 1, "the stage list must still be intact/populated")

# ---------------------------------------------------------------------------
# Codex最終レビュー指摘対応 §11〜§16 — 保存JSON全体のバイト単位不変性
# ---------------------------------------------------------------------------

func _read_stage_bytes(stage_id: String) -> PackedByteArray:
	var path := "%s/%s.json" % [TEST_DIR, stage_id]
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "stage file must exist: %s" % path)
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return bytes

## §12: 勝利後も保存JSONがバイト単位で完全不変。
func test_winning_a_challenge_leaves_the_saved_json_byte_for_byte_unchanged() -> void:
	var stage_id := _save_boss_that_dies_in_one_hit("JSON不変勝利ボス")
	var bytes_before := _read_stage_bytes(stage_id)

	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	_win_immediately(entry._battle_view)
	assert_true(entry._battle_view.session.battle.battle_over, "sanity")
	assert_eq(entry._battle_view.session.battle.winner, "ally", "sanity")

	var bytes_after := _read_stage_bytes(stage_id)
	assert_eq(bytes_after, bytes_before, "a CHALLENGE win must never write anything back to the saved stage file")

## §13: 敗北後も保存JSONがバイト単位で完全不変。
func test_losing_a_challenge_leaves_the_saved_json_byte_for_byte_unchanged() -> void:
	var stage_id := _save_boss_that_wins_immediately("JSON不変敗北ボス")
	var bytes_before := _read_stage_bytes(stage_id)

	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	assert_true(entry._battle_view.session.battle.battle_over, "sanity")
	assert_eq(entry._battle_view.session.battle.winner, "boss", "sanity")

	var bytes_after := _read_stage_bytes(stage_id)
	assert_eq(bytes_after, bytes_before, "a CHALLENGE loss must never write anything back to the saved stage file")

## §14: 「最初からやり直す」→確認→restart後も保存JSONがバイト単位で完全不変。
func test_restarting_mid_challenge_leaves_the_saved_json_byte_for_byte_unchanged() -> void:
	var stage_id := _save_playable_boss("JSON不変restartボス")
	var bytes_before := _read_stage_bytes(stage_id)

	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	entry._battle_view._on_restart_pressed()
	entry._battle_view._on_restart_confirmed()

	var bytes_after := _read_stage_bytes(stage_id)
	assert_eq(bytes_after, bytes_before, "restarting a CHALLENGE must never write anything back to the saved stage file")

## §15: 「挑戦をやめる」→確認→一覧後も保存JSONがバイト単位で完全不変。
func test_quitting_mid_challenge_leaves_the_saved_json_byte_for_byte_unchanged() -> void:
	var stage_id := _save_playable_boss("JSON不変quitボス")
	var bytes_before := _read_stage_bytes(stage_id)

	var entry := _new_entry()
	_open_confirm(entry, stage_id)
	entry._confirm_view._on_challenge_pressed()
	entry._battle_view.act_attack(0)
	entry._battle_view._on_quit_pressed()
	entry._battle_view._on_quit_confirmed()

	var bytes_after := _read_stage_bytes(stage_id)
	assert_eq(bytes_after, bytes_before, "quitting a CHALLENGE must never write anything back to the saved stage file")

# ---------------------------------------------------------------------------
# Codex最終レビュー指摘対応 §17 — 一覧の破損/未対応version統合テスト
# ---------------------------------------------------------------------------

## Repository単体では既に十分検証済み（test_rbm_local_stage_repository.gd）
## だが、CHALLENGE一覧への接続として軽量に再確認する。
func test_list_excludes_corrupt_and_unsupported_version_stages_alongside_a_healthy_one() -> void:
	_save_published_boss("健全ボス")

	# 破損stage: 不正なJSON本文を直接書き込む。
	var corrupt_id := "1111111111"
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	var corrupt_file := FileAccess.open("%s/%s.json" % [TEST_DIR, corrupt_id], FileAccess.WRITE)
	corrupt_file.store_string("{ this is not valid JSON")
	corrupt_file.close()

	# 未対応version: version 3のペイロードを直接書き込む。
	var draft := _basic_playable_draft("未対応versionボス")
	var version2_id := "2222222222"
	var payload := {
		"save_format_version": 3, "stage_id": version2_id,
		"created_unix_time": 1000, "updated_unix_time": 1000,
		"draft": draft.to_saved_dict(), "clear_check_success_snapshot": {},
	}
	var version2_file := FileAccess.open("%s/%s.json" % [TEST_DIR, version2_id], FileAccess.WRITE)
	version2_file.store_string(JSON.stringify(payload))
	version2_file.close()

	var entry := _new_entry()
	entry._refresh_list()
	assert_eq(entry._list_rows.get_child_count(), 1, "only the healthy playable stage must appear; corrupt and unsupported-version stages must be silently excluded")
