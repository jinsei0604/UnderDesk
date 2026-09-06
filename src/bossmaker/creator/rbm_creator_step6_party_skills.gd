class_name RBMCreatorStep6PartySkills
extends Control

## Phase 1 Step 4 §6 — STEP 6（新STEP5）: 味方使用可能スキル（STEP 4選択
## キャラのみ、性能編集不可、そのボス戦で使用可能かのON/OFFのみ）。
##
## §15（カードUI具体仕様）: パーティに入っているキャラクターごとに1枚の
## カードを表示する。通常表示は各スキルの「使用可/使用不可」要約のみ——
## ON/OFFチェックボックスは「編集」を押した時だけそのキャラのカード内へ
## 展開する。編集中はドラフトへ直接書き込まず、決定で確定・キャンセルで
## 編集開始時点の状態へ戻す（キャラクターごとに独立した一時退避Dictionaryを
## 持つため、複数キャラを同時に編集していても互いに干渉しない）。ボス行動の
## 「その場で新規作成」とは無関係——味方スキルは既存固定マスターのみを扱う
## （新規スキル作成UIはこの画面に存在しない）。

## 実機プレイ改善①§12: RBMCreatorStep1Basicと同じ理由・同じ技法。
const CONTENT_SIDE_MARGIN_PX := 80.0
const CONTENT_TOP_MARGIN_PX := 40.0

var draft: RBMCreatorDraft
var main: Node

var _character_sections: VBoxContainer
var _empty_state_label: Label

## 実機プレイ改善③ item9: この画面はdata_bossmaker/allies/*.jsonの生の
## "effect"/"target"文字列をそのまま表示していた（例: "damage", "heal",
## "buff_atk_self" / "boss", "ally_chosen", "ally_all"）——RBMBattle自身が
## 実際に消費するこれらの内部enum風文字列は無改修のまま、表示専用のラベルへ
## 変換する対応表をこのファイル内に閉じて持つ（他の画面はこれらのフィールド
## を生表示していないため、共有辞書ではなくこのファイル専用とした）。編集
## パネル内のスキル詳細行でのみ使用（§15-2: 通常表示は使用可/不可のみ）。
const EFFECT_LABELS := {
	"damage": "攻撃",
	"heal": "HP回復",
	"buff_atk_self": "攻撃力強化",
	"buff_next_attack": "次の攻撃強化",
	"counter_stance": "反撃態勢",
	"guard_boost": "防御強化",
	"guard_redirect": "かばう",
	"party_damage_reduction": "被ダメージ軽減（全体）",
	"sp_recover_all_no_self": "SP回復（全体）",
	"sp_recover_single_no_self": "SP回復（単体）",
}

const TARGET_LABELS := {
	"boss": "ボス",
	"ally_chosen": "味方単体",
	"ally_chosen_no_self": "味方単体（自分以外）",
	"ally_all": "味方全体",
}

## §15-3「編集」中だけ有効な一時退避値——character_id -> {skill_id -> bool}。
## 決定を押すまでdraft.allowed_ally_skillsは一切変更しない。character_idは
## 現在編集中のキャラクターだけがキーとして存在する。
var _editing_ids: Dictionary = {}  # character_id -> true
var _staged_allowed: Dictionary = {}  # character_id -> {skill_id -> bool}

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.anchor_right = 1.0
	column.offset_left = CONTENT_SIDE_MARGIN_PX
	column.offset_right = -CONTENT_SIDE_MARGIN_PX
	column.offset_top = CONTENT_TOP_MARGIN_PX
	add_child(column)
	_empty_state_label = Label.new()
	_empty_state_label.name = "EmptyPartyLabel"
	_empty_state_label.text = "攻略パーティにキャラクターがいません。先に攻略パーティを選んでください。"
	column.add_child(_empty_state_label)

	_character_sections = VBoxContainer.new()
	_character_sections.name = "CharacterSections"
	column.add_child(_character_sections)

## 既存プログラム的API（テスト/呼び出し元向け）——実UIの「編集→決定」フロー
## とは独立して常に即座にドラフトへ反映する、既存の挙動をそのまま維持。
func set_skill_allowed(character_id: String, skill_id: String, allowed: bool) -> void:
	draft.set_ally_skill_allowed(character_id, skill_id, allowed)
	refresh()

func set_all_for_character(character_id: String, allowed: bool) -> void:
	draft.set_all_ally_skills_allowed(character_id, allowed)
	refresh()

func _on_edit_pressed(character_id: String) -> void:
	_editing_ids[character_id] = true
	var master := draft.master_character_def(character_id)
	var snapshot := {}
	for skill in master.get("skills", []):
		var skill_id := str(skill.get("id", ""))
		snapshot[skill_id] = draft.is_ally_skill_allowed(character_id, skill_id)
	_staged_allowed[character_id] = snapshot
	refresh()

func _on_staged_skill_toggled(character_id: String, skill_id: String, pressed: bool) -> void:
	if not _staged_allowed.has(character_id):
		return
	(_staged_allowed[character_id] as Dictionary)[skill_id] = pressed

func _on_staged_all_pressed(character_id: String, allowed: bool) -> void:
	if not _staged_allowed.has(character_id):
		return
	var master := draft.master_character_def(character_id)
	var snapshot: Dictionary = _staged_allowed[character_id]
	for skill in master.get("skills", []):
		snapshot[str(skill.get("id", ""))] = allowed
	refresh()

func _on_confirm_pressed(character_id: String) -> void:
	if _staged_allowed.has(character_id):
		var snapshot: Dictionary = _staged_allowed[character_id]
		for skill_id in snapshot.keys():
			draft.set_ally_skill_allowed(character_id, str(skill_id), bool(snapshot[skill_id]))
	_editing_ids.erase(character_id)
	_staged_allowed.erase(character_id)
	refresh()

func _on_cancel_pressed(character_id: String) -> void:
	_editing_ids.erase(character_id)
	_staged_allowed.erase(character_id)
	refresh()

func refresh() -> void:
	# §15-4: STEP4でパーティから外されたキャラクターの編集状態が残り続けない
	# ようにする（表示上は元よりカード自体が生成されないため実害は無いが、
	# 内部状態を空のまま保たない）。
	for character_id in _editing_ids.keys().duplicate():
		if not draft.party_character_ids.has(character_id):
			_editing_ids.erase(character_id)
			_staged_allowed.erase(character_id)

	_empty_state_label.visible = draft.party_character_ids.is_empty()
	# queue_free()だけだと実際のツリー離脱は次のアイドルフレームまで遅延する
	# ため、同一フレーム内で「まだ残っている旧ノードと同じname」を持つ新規
	# ノードをadd_child()すると、Godotが名前衝突を検知して新ノードを
	# 自動リネームしてしまう（例: "PartySkillCard_hero"のまま残そうとした
	# 新カードが意図せず"@PanelContainer@NNN"になる）——remove_child()で
	# ツリーから即座に切り離してからqueue_free()することで、free()を直接
	# 呼ばず（このメソッドはボタン自身のpressedシグナル経由で呼ばれることが
	# あり、呼び出し元ノードを伝播中のシグナル内で直接.free()するのは
	# Godot的に危険）名前衝突だけを確実に解消する。
	for child in _character_sections.get_children():
		_character_sections.remove_child(child)
		child.queue_free()
	for character_id in draft.party_character_ids:
		_build_character_card(character_id)

func _build_character_card(character_id: String) -> void:
	var master := draft.master_character_def(character_id)
	var card := PanelContainer.new()
	card.name = "PartySkillCard_%s" % character_id
	_character_sections.add_child(card)
	var card_column := VBoxContainer.new()
	card.add_child(card_column)

	var name_label := Label.new()
	name_label.text = str(master.get("display_name", character_id))
	card_column.add_child(name_label)

	var skills_caption := Label.new()
	skills_caption.text = "使用可能スキル"
	card_column.add_child(skills_caption)

	if _editing_ids.has(character_id):
		_build_edit_panel(card_column, character_id, master)
	else:
		_build_normal_panel(card_column, character_id, master)

func _build_normal_panel(parent: Control, character_id: String, master: Dictionary) -> void:
	for skill in master.get("skills", []):
		var skill_id := str(skill.get("id", ""))
		var row := HBoxContainer.new()
		parent.add_child(row)
		var label := Label.new()
		label.name = "SkillStatusLabel_%s_%s" % [character_id, skill_id]
		var allowed := draft.is_ally_skill_allowed(character_id, skill_id)
		label.text = "%s   %s" % [str(skill.get("display_name", skill_id)), "使用可" if allowed else "使用不可"]
		row.add_child(label)

	var edit_button := Button.new()
	edit_button.name = "EditPartySkillsButton_%s" % character_id
	edit_button.text = "編集"
	edit_button.pressed.connect(_on_edit_pressed.bind(character_id))
	parent.add_child(edit_button)

func _build_edit_panel(parent: Control, character_id: String, master: Dictionary) -> void:
	var staged: Dictionary = _staged_allowed.get(character_id, {})

	var bulk_row := HBoxContainer.new()
	parent.add_child(bulk_row)
	var on_button := Button.new()
	on_button.name = "AllOnButton_%s" % character_id
	on_button.text = "すべてON"
	on_button.pressed.connect(_on_staged_all_pressed.bind(character_id, true))
	bulk_row.add_child(on_button)
	var off_button := Button.new()
	off_button.name = "AllOffButton_%s" % character_id
	off_button.text = "すべてOFF"
	off_button.pressed.connect(_on_staged_all_pressed.bind(character_id, false))
	bulk_row.add_child(off_button)

	for skill in master.get("skills", []):
		var skill_id := str(skill.get("id", ""))
		var row := HBoxContainer.new()
		parent.add_child(row)
		var check := CheckButton.new()
		check.name = "SkillCheck_%s_%s" % [character_id, skill_id]
		check.button_pressed = bool(staged.get(skill_id, draft.is_ally_skill_allowed(character_id, skill_id)))
		# CheckButton.toggled(pressed) supplies `pressed` as its own
		# runtime arg -- Callable.bind() APPENDS bound args after that, so
		# a plain .bind(character_id, skill_id) here would call
		# _on_staged_skill_toggled(pressed, character_id, skill_id), not the
		# (character_id, skill_id, pressed) order this method expects.
		# Use an explicit closure instead so the argument order matches.
		check.toggled.connect(func(pressed: bool): _on_staged_skill_toggled(character_id, skill_id, pressed))
		row.add_child(check)
		var label := Label.new()
		var effect_id := str(skill.get("effect", ""))
		var target_id := str(skill.get("target", ""))
		var target_text := str(TARGET_LABELS.get(target_id, target_id)) if not target_id.is_empty() else "-"
		label.text = "%s（%s、対象:%s、SP消費%s）" % [
			str(skill.get("display_name", skill_id)), str(EFFECT_LABELS.get(effect_id, effect_id)),
			target_text, str(skill.get("sp_cost", 0)),
		]
		row.add_child(label)

	var confirm_row := HBoxContainer.new()
	parent.add_child(confirm_row)
	var confirm_button := Button.new()
	confirm_button.name = "ConfirmPartySkillsButton_%s" % character_id
	confirm_button.text = "決定"
	confirm_button.pressed.connect(_on_confirm_pressed.bind(character_id))
	confirm_row.add_child(confirm_button)
	var cancel_button := Button.new()
	cancel_button.name = "CancelPartySkillsButton_%s" % character_id
	cancel_button.text = "キャンセル"
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(_on_cancel_pressed.bind(character_id))
	confirm_row.add_child(cancel_button)

func is_step_valid() -> bool:
	return draft.step6_is_valid()

func validation_message() -> String:
	return ""

