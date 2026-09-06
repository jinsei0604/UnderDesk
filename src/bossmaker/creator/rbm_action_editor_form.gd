class_name RBMActionEditorForm
extends VBoxContainer

## Creator UI再設計 §9 — 「行動作成フォーム」共通コンポーネント。
## 旧RBMCreatorStep3Skillsのスキル編集フォーム（名前/種類/対象/属性/威力・
## 回復・強化の各フィールド＋即時プレビュー）を、そのまま独立した再利用可能な
## 部品として切り出したもの。呼び出し元（通常行動/指定行動/ADVANCED固定行動/
## ADVANCEDランダム候補、いずれも新STEP3「行動」画面の中）はすべてこの同じ
## フォームを開き、保存結果（新しいskill_id、または既存skill_idの更新）を
## savedシグナルで受け取るだけでよい——各画面が個別にフィールド構築コードを
## 複製しない。
##
## §26「使う場所で作る」の実装そのもの: 呼び出し元は「既存スキルから選ぶ」
## UIを一切持たず、常にこのフォームで「その場で新しい行動」を作る（編集時
## だけ既存skill_idの中身を書き換える）。draft.skills自体の形・skill_id方式・
## MAX_SKILLS判定はRBMCreatorDraft側から一切変更していない——ここは純粋な
## UI部品化。

signal saved(skill_id: String)
signal cancelled()

const ATTACK := "attack"
const SELF_HEAL := "self_heal"
const ATK_SELF_BUFF := "atk_self_buff"
const TYPE_LABELS := {ATTACK: "攻撃", SELF_HEAL: "自己回復", ATK_SELF_BUFF: "ATK自己強化"}

const SLIDER_MIN_SIZE := Vector2(320.0, 28.0)
const NAME_EDIT_MIN_SIZE := Vector2(360.0, 32.0)
const STAT_SPIN_MIN_SIZE_LARGE := Vector2(170.0, 32.0)
const STAT_SPIN_MIN_SIZE_DEFAULT := Vector2(120.0, 32.0)

var draft: RBMCreatorDraft
var _editing_skill_id: String = ""  # "" while creating a NEW action

var _actions_row: Control

var _title_label: Label
var _name_edit: LineEdit
var _type_option: OptionButton

var _attack_fields: Control
var _attack_target_option: OptionButton
var _attack_attribute_option: OptionButton
var _attack_multiplier_slider: HSlider
var _attack_multiplier_spin: SpinBox
var _attack_preview_label: Label

var _self_heal_fields: Control
var _self_heal_mode_option: OptionButton
var _self_heal_fixed_slider: HSlider
var _self_heal_fixed_spin: SpinBox
var _self_heal_fixed_preview_label: Label
var _self_heal_percent_slider: HSlider
var _self_heal_percent_spin: SpinBox
var _self_heal_percent_preview_label: Label

var _atk_buff_fields: Control
var _atk_buff_multiplier_slider: HSlider
var _atk_buff_multiplier_spin: SpinBox
var _atk_buff_preview_label: Label
var _atk_buff_duration_spin: SpinBox

var _syncing := false

## show_save_cancel_buttons: HARDCORE Creator新STEP3の「新しく攻撃を作る」
## 画面（§6）は、性能・発動条件・使用回数を1画面へまとめ、確定ボタンを
## 「攻撃を追加」1つだけにする必要がある——このフォーム自身の保存/
## キャンセルボタン行を非表示にし、呼び出し元がcurrent_action_data()経由で
## フィールド値を読み取ってから、条件・使用回数と一緒に独自のタイミングで
## draft.add_skill()/update_skill()を呼ぶ（savedシグナルは発行されない、
## 呼び出し元が自分で処理を完結させる設計）。既存の呼び出し元（SIMPLE
## 「行動」画面/ランダム攻撃内の「新しく攻撃を作る」）はfalseを渡さず、
## 引き続きこのフォーム自身の保存ボタン→savedシグナルの流れをそのまま使う
## ——このパラメータ追加はそれらの既存動作に一切影響しない。
func setup(p_draft: RBMCreatorDraft, show_save_cancel_buttons: bool = true) -> void:
	draft = p_draft
	_build_ui()
	_actions_row.visible = show_save_cancel_buttons
	visible = false

## show_save_cancel_buttons==falseで使う呼び出し元向けの公開ラッパー——
## 現在のフォーム入力内容をそのままskillデータ辞書として返す
## （_editor_action_data()と同一、保存ボタンを介さず値だけ読み取りたい
## 場合に使う）。
func current_action_data() -> Dictionary:
	return _editor_action_data()

## HARDCORE Creator新STEP3が、同じ1つのフォームインスタンスを文脈
## （新規作成/性能編集/ランダム候補新規作成）に応じて保存ボタン付き・
## 無しの両方で使い回すための動的切替（setup()時の固定値だけでは足りない
## ——1つのフォームを複数の画面から共有再利用する設計のため）。
func set_save_cancel_buttons_visible(is_visible: bool) -> void:
	_actions_row.visible = is_visible

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.name = "ActionEditorFormColumn"
	add_child(column)

	_title_label = Label.new()
	_title_label.name = "ActionEditorFormTitleLabel"
	column.add_child(_title_label)

	var name_row := HBoxContainer.new()
	column.add_child(name_row)
	var name_caption := Label.new()
	name_caption.text = "行動名"
	name_row.add_child(name_caption)
	_name_edit = LineEdit.new()
	_name_edit.name = "ActionNameEdit"
	_name_edit.custom_minimum_size = NAME_EDIT_MIN_SIZE
	name_row.add_child(_name_edit)

	var type_row := HBoxContainer.new()
	column.add_child(type_row)
	var type_caption := Label.new()
	type_caption.text = "種類"
	type_row.add_child(type_caption)
	_type_option = OptionButton.new()
	_type_option.name = "ActionTypeOption"
	_type_option.add_item(TYPE_LABELS[ATTACK], 0)
	_type_option.add_item(TYPE_LABELS[SELF_HEAL], 1)
	_type_option.add_item(TYPE_LABELS[ATK_SELF_BUFF], 2)
	_type_option.item_selected.connect(_on_type_selected)
	type_row.add_child(_type_option)

	_build_attack_fields(column)
	_build_self_heal_fields(column)
	_build_atk_buff_fields(column)

	_actions_row = HBoxContainer.new()
	column.add_child(_actions_row)
	var save_button := Button.new()
	save_button.name = "SaveActionButton"
	save_button.text = "保存"
	save_button.pressed.connect(_on_save_pressed)
	_actions_row.add_child(save_button)
	var cancel_button := Button.new()
	cancel_button.name = "CancelActionButton"
	cancel_button.text = "キャンセル"
	cancel_button.theme_type_variation = RBMUiTheme.VARIATION_SECONDARY_BUTTON
	cancel_button.pressed.connect(_on_cancel_pressed)
	_actions_row.add_child(cancel_button)

func _build_attack_fields(parent: Control) -> void:
	_attack_fields = VBoxContainer.new()
	_attack_fields.name = "AttackFields"
	parent.add_child(_attack_fields)

	var target_row := HBoxContainer.new()
	_attack_fields.add_child(target_row)
	var target_caption := Label.new()
	target_caption.text = "対象"
	target_row.add_child(target_caption)
	_attack_target_option = OptionButton.new()
	_attack_target_option.name = "AttackTargetOption"
	_attack_target_option.add_item("単体", 0)
	_attack_target_option.add_item("全体", 1)
	_attack_target_option.item_selected.connect(func(_i): _refresh_attack_preview())
	target_row.add_child(_attack_target_option)

	var attribute_row := HBoxContainer.new()
	_attack_fields.add_child(attribute_row)
	var attribute_caption := Label.new()
	attribute_caption.text = "属性"
	attribute_row.add_child(attribute_caption)
	_attack_attribute_option = OptionButton.new()
	_attack_attribute_option.name = "AttackAttributeOption"
	for i in range(RBMDefinitionLoader.VALID_ATTRIBUTES.size()):
		var attribute_id := str(RBMDefinitionLoader.VALID_ATTRIBUTES[i])
		_attack_attribute_option.add_item(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id)), i)
	_attack_attribute_option.item_selected.connect(func(_i): _refresh_attack_preview())
	attribute_row.add_child(_attack_attribute_option)

	var mult_row := HBoxContainer.new()
	_attack_fields.add_child(mult_row)
	var mult_caption := Label.new()
	mult_caption.text = "ATK倍率"
	mult_row.add_child(mult_caption)
	_attack_multiplier_slider = HSlider.new()
	_attack_multiplier_slider.name = "AttackMultiplierSlider"
	_attack_multiplier_slider.min_value = 0.0
	_attack_multiplier_slider.max_value = 100.0
	_attack_multiplier_slider.step = 0.01
	_attack_multiplier_slider.custom_minimum_size = SLIDER_MIN_SIZE
	mult_row.add_child(_attack_multiplier_slider)
	_attack_multiplier_spin = SpinBox.new()
	_attack_multiplier_spin.name = "AttackMultiplierSpin"
	_attack_multiplier_spin.min_value = 0.0
	_attack_multiplier_spin.max_value = 100.0
	_attack_multiplier_spin.step = 0.01
	_attack_multiplier_spin.custom_minimum_size = STAT_SPIN_MIN_SIZE_DEFAULT
	mult_row.add_child(_attack_multiplier_spin)
	_attack_multiplier_slider.value_changed.connect(_on_paired_value_changed.bind(_attack_multiplier_spin, "attack"))
	_attack_multiplier_spin.value_changed.connect(_on_paired_value_changed.bind(_attack_multiplier_slider, "attack"))

	_attack_preview_label = Label.new()
	_attack_preview_label.name = "AttackPreviewLabel"
	_attack_fields.add_child(_attack_preview_label)

func _build_self_heal_fields(parent: Control) -> void:
	_self_heal_fields = VBoxContainer.new()
	_self_heal_fields.name = "SelfHealFields"
	parent.add_child(_self_heal_fields)

	var mode_row := HBoxContainer.new()
	_self_heal_fields.add_child(mode_row)
	var mode_caption := Label.new()
	mode_caption.text = "回復方式"
	mode_row.add_child(mode_caption)
	_self_heal_mode_option = OptionButton.new()
	_self_heal_mode_option.name = "SelfHealModeOption"
	_self_heal_mode_option.add_item("固定値", 0)
	_self_heal_mode_option.add_item("最大HP割合", 1)
	_self_heal_mode_option.item_selected.connect(_on_heal_mode_selected)
	mode_row.add_child(_self_heal_mode_option)

	var fixed_row := HBoxContainer.new()
	_self_heal_fields.add_child(fixed_row)
	var fixed_caption := Label.new()
	fixed_caption.text = "固定回復量"
	fixed_row.add_child(fixed_caption)
	_self_heal_fixed_slider = HSlider.new()
	_self_heal_fixed_slider.name = "SelfHealFixedSlider"
	_self_heal_fixed_slider.min_value = 0
	_self_heal_fixed_slider.max_value = 1000000
	_self_heal_fixed_slider.step = 1
	_self_heal_fixed_slider.custom_minimum_size = SLIDER_MIN_SIZE
	fixed_row.add_child(_self_heal_fixed_slider)
	_self_heal_fixed_spin = SpinBox.new()
	_self_heal_fixed_spin.name = "SelfHealFixedSpin"
	_self_heal_fixed_spin.min_value = 0
	_self_heal_fixed_spin.max_value = 1000000
	_self_heal_fixed_spin.step = 1
	_self_heal_fixed_spin.custom_minimum_size = STAT_SPIN_MIN_SIZE_LARGE
	fixed_row.add_child(_self_heal_fixed_spin)
	_self_heal_fixed_slider.value_changed.connect(_on_paired_value_changed.bind(_self_heal_fixed_spin, "self_heal"))
	_self_heal_fixed_spin.value_changed.connect(_on_paired_value_changed.bind(_self_heal_fixed_slider, "self_heal"))
	_self_heal_fixed_preview_label = Label.new()
	_self_heal_fixed_preview_label.name = "SelfHealFixedPreviewLabel"
	_self_heal_fields.add_child(_self_heal_fixed_preview_label)

	var percent_row := HBoxContainer.new()
	_self_heal_fields.add_child(percent_row)
	var percent_caption := Label.new()
	percent_caption.text = "回復割合(%)"
	percent_row.add_child(percent_caption)
	_self_heal_percent_slider = HSlider.new()
	_self_heal_percent_slider.name = "SelfHealPercentSlider"
	_self_heal_percent_slider.min_value = 0.0
	_self_heal_percent_slider.max_value = 100.0
	_self_heal_percent_slider.step = 0.1
	_self_heal_percent_slider.custom_minimum_size = SLIDER_MIN_SIZE
	percent_row.add_child(_self_heal_percent_slider)
	_self_heal_percent_spin = SpinBox.new()
	_self_heal_percent_spin.name = "SelfHealPercentSpin"
	_self_heal_percent_spin.min_value = 0.0
	_self_heal_percent_spin.max_value = 100.0
	_self_heal_percent_spin.step = 0.1
	_self_heal_percent_spin.custom_minimum_size = STAT_SPIN_MIN_SIZE_DEFAULT
	percent_row.add_child(_self_heal_percent_spin)
	_self_heal_percent_slider.value_changed.connect(_on_paired_value_changed.bind(_self_heal_percent_spin, "self_heal"))
	_self_heal_percent_spin.value_changed.connect(_on_paired_value_changed.bind(_self_heal_percent_slider, "self_heal"))
	_self_heal_percent_preview_label = Label.new()
	_self_heal_percent_preview_label.name = "SelfHealPercentPreviewLabel"
	_self_heal_fields.add_child(_self_heal_percent_preview_label)

func _build_atk_buff_fields(parent: Control) -> void:
	_atk_buff_fields = VBoxContainer.new()
	_atk_buff_fields.name = "AtkBuffFields"
	parent.add_child(_atk_buff_fields)

	var mult_row := HBoxContainer.new()
	_atk_buff_fields.add_child(mult_row)
	var mult_caption := Label.new()
	mult_caption.text = "強化倍率"
	mult_row.add_child(mult_caption)
	_atk_buff_multiplier_slider = HSlider.new()
	_atk_buff_multiplier_slider.name = "AtkBuffMultiplierSlider"
	_atk_buff_multiplier_slider.min_value = 1.0
	_atk_buff_multiplier_slider.max_value = 100.0
	_atk_buff_multiplier_slider.step = 0.01
	_atk_buff_multiplier_slider.custom_minimum_size = SLIDER_MIN_SIZE
	mult_row.add_child(_atk_buff_multiplier_slider)
	_atk_buff_multiplier_spin = SpinBox.new()
	_atk_buff_multiplier_spin.name = "AtkBuffMultiplierSpin"
	_atk_buff_multiplier_spin.min_value = 1.0
	_atk_buff_multiplier_spin.max_value = 100.0
	_atk_buff_multiplier_spin.step = 0.01
	_atk_buff_multiplier_spin.custom_minimum_size = STAT_SPIN_MIN_SIZE_DEFAULT
	mult_row.add_child(_atk_buff_multiplier_spin)
	_atk_buff_multiplier_slider.value_changed.connect(_on_paired_value_changed.bind(_atk_buff_multiplier_spin, "atk_buff"))
	_atk_buff_multiplier_spin.value_changed.connect(_on_paired_value_changed.bind(_atk_buff_multiplier_slider, "atk_buff"))
	_atk_buff_preview_label = Label.new()
	_atk_buff_preview_label.name = "AtkBuffPreviewLabel"
	_atk_buff_fields.add_child(_atk_buff_preview_label)

	var duration_row := HBoxContainer.new()
	_atk_buff_fields.add_child(duration_row)
	var duration_caption := Label.new()
	duration_caption.text = "持続ターン"
	duration_row.add_child(duration_caption)
	_atk_buff_duration_spin = SpinBox.new()
	_atk_buff_duration_spin.name = "AtkBuffDurationSpin"
	_atk_buff_duration_spin.min_value = 1
	_atk_buff_duration_spin.max_value = 99
	_atk_buff_duration_spin.step = 1
	duration_row.add_child(_atk_buff_duration_spin)

func _on_paired_value_changed(v: float, paired: Range, preview_key: String) -> void:
	if _syncing:
		return
	_syncing = true
	paired.value = v
	_syncing = false
	match preview_key:
		"attack":
			_refresh_attack_preview()
		"self_heal":
			_refresh_self_heal_preview()
		"atk_buff":
			_refresh_atk_buff_preview()

# ---------------------------------------------------------------------------
# open / close
# ---------------------------------------------------------------------------

## §5〜§10「その場で作る」——常にここから開始する。draft.can_add_skill()が
## falseの場合は呼び出し元が「＋作る」ボタン自体を無効化しておくべきだが、
## 念のためここでも二重に防御する（無条件で作成しない）。
func open_for_new(title: String = "行動を作る") -> void:
	if not draft.can_add_skill():
		return
	_editing_skill_id = ""
	_title_label.text = title
	_load_from_skill({"name": "", "type": ATTACK, "target": "single", "attribute": "NEUTRAL", "atk_multiplier": 1.0})
	visible = true

func open_for_editing(skill_id: String, title: String = "行動を編集") -> void:
	var skill := draft.find_skill(skill_id)
	if skill.is_empty():
		return
	_editing_skill_id = skill_id
	_title_label.text = title
	_load_from_skill(skill)
	visible = true

func _load_from_skill(skill: Dictionary) -> void:
	_name_edit.text = str(skill.get("name", ""))
	var type_id := str(skill.get("type", ATTACK))
	_type_option.select([ATTACK, SELF_HEAL, ATK_SELF_BUFF].find(type_id))
	_attack_target_option.select(0 if str(skill.get("target", "single")) == "single" else 1)
	var attribute_index: int = RBMDefinitionLoader.VALID_ATTRIBUTES.find(str(skill.get("attribute", "NEUTRAL")))
	_attack_attribute_option.select(maxi(0, attribute_index))
	_attack_multiplier_spin.value = float(skill.get("atk_multiplier", 1.0))
	_self_heal_mode_option.select(0 if str(skill.get("heal_mode", "fixed")) == "fixed" else 1)
	_self_heal_fixed_spin.value = float(skill.get("heal_fixed_amount", 0))
	_self_heal_percent_spin.value = float(skill.get("heal_percent", 0.0))
	_atk_buff_multiplier_spin.value = float(skill.get("buff_multiplier", 1.0))
	_atk_buff_duration_spin.value = float(skill.get("duration_turns", 1))
	_on_type_selected(_type_option.selected)
	_on_heal_mode_selected(_self_heal_mode_option.selected)
	_refresh_all_previews()

func _on_type_selected(index: int) -> void:
	var type_id: String = [ATTACK, SELF_HEAL, ATK_SELF_BUFF][index]
	_attack_fields.visible = type_id == ATTACK
	_self_heal_fields.visible = type_id == SELF_HEAL
	_atk_buff_fields.visible = type_id == ATK_SELF_BUFF

func _on_heal_mode_selected(index: int) -> void:
	var percent_mode := index == 1
	_self_heal_fixed_slider.editable = not percent_mode
	_self_heal_fixed_spin.editable = not percent_mode
	_self_heal_percent_slider.editable = percent_mode
	_self_heal_percent_spin.editable = percent_mode

func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()

## 新規作成時はdraft.add_skill()を呼び新しいskill_idを発行、編集時は
## draft.update_skill()でskill_idを変えずに中身だけ更新する——どちらも
## RBMCreatorDraft側の既存APIをそのまま使うだけで、保存形式・Clear Check・
## MAX_SKILLS判定は無改修。
func _on_save_pressed() -> void:
	var data := _editor_action_data()
	if _editing_skill_id.is_empty():
		var new_id := draft.add_skill(data)
		if new_id.is_empty():
			return  # MAX_SKILLS上限（呼び出し元のボタン無効化をすり抜けた場合の防御）
		visible = false
		saved.emit(new_id)
	else:
		draft.update_skill(_editing_skill_id, data)
		visible = false
		saved.emit(_editing_skill_id)

func _editor_action_data() -> Dictionary:
	var type_id: String = [ATTACK, SELF_HEAL, ATK_SELF_BUFF][_type_option.selected]
	var data := {"name": _name_edit.text, "type": type_id}
	match type_id:
		ATTACK:
			data["target"] = "single" if _attack_target_option.selected == 0 else "all"
			data["attribute"] = str(RBMDefinitionLoader.VALID_ATTRIBUTES[_attack_attribute_option.selected])
			data["atk_multiplier"] = _attack_multiplier_spin.value
		SELF_HEAL:
			data["heal_mode"] = "fixed" if _self_heal_mode_option.selected == 0 else "percent"
			data["heal_fixed_amount"] = int(_self_heal_fixed_spin.value)
			data["heal_percent"] = _self_heal_percent_spin.value
		ATK_SELF_BUFF:
			data["buff_multiplier"] = _atk_buff_multiplier_spin.value
			data["duration_turns"] = int(_atk_buff_duration_spin.value)
	return data

# ---------------------------------------------------------------------------
# live previews
# ---------------------------------------------------------------------------

func _refresh_all_previews() -> void:
	_refresh_attack_preview()
	_refresh_self_heal_preview()
	_refresh_atk_buff_preview()

func _refresh_attack_preview() -> void:
	var skill := {"atk_multiplier": _attack_multiplier_spin.value}
	_attack_preview_label.text = "基準ダメージ: %d" % draft.baseline_attack_damage(skill)

func _refresh_self_heal_preview() -> void:
	var fixed_skill := {"heal_mode": "fixed", "heal_fixed_amount": int(_self_heal_fixed_spin.value)}
	_self_heal_fixed_preview_label.text = "最大HPの%.1f%%相当" % draft.heal_percent_of_current_max_hp(fixed_skill)
	var percent_skill := {"heal_mode": "percent", "heal_percent": _self_heal_percent_spin.value}
	_self_heal_percent_preview_label.text = "%d HP回復" % draft.resolved_heal_amount(percent_skill)

func _refresh_atk_buff_preview() -> void:
	var skill := {"buff_multiplier": _atk_buff_multiplier_spin.value}
	_atk_buff_preview_label.text = "強化後ATK: %d" % draft.buffed_atk_preview(skill)

