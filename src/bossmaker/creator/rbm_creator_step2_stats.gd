class_name RBMCreatorStep2Stats
extends Control

## Phase 1 Step 4 §2 — STEP 2: HP/ATK/SPD (slider+数値入力を完全同期) + 弱点/耐性
## 複数選択（同属性を反対側へ選ぶと自動的に元側解除）.
##
## 能力工程は常時編集。変更を作成中データへ即時反映し、保存は最終確認で行う。
##
## §2-4: ranges come straight from RBMDefinitionLoader's own constants, never
## redefined here.

## 実機プレイ改善①§10: HSliderの実測クリック可能幅が8×16pxまで潰れていた
## （root原因は_build_synced_row()側のコメント参照）ことへの直接対処。
## RBMConstants（バトルコア、UI非依存という設計原則——src/bossmaker/README.md
## 「coreはGodotノード非依存」）へは置かず、UI専用のこのファイル内に留める。
const CREATOR_SLIDER_MIN_SIZE := Vector2(320.0, 28.0)

## 実機プレイ改善①§12: RBMCreatorStep1Basicと同じ理由・同じ技法。
const CONTENT_SIDE_MARGIN_PX := 80.0
const CONTENT_TOP_MARGIN_PX := 40.0

## 実機プレイ改善② item4: SpinBoxもHSliderと全く同じ理由（上記
## CREATOR_SLIDER_MIN_SIZEのコメント参照）でcustom_minimum_sizeを持たない
## 限りテーマ既定の最小サイズまで潰れ、現在値・最大桁数が見切れたり
## 上下スピンボタンと数字が重なったりする。BOSS_HP_MAX=99,999（5桁）は
## BOSS_ATK_MAX=9,999（4桁）/BOSS_SPD_MAX=500（3桁）より明確に多い桁数を
## 要求するため、HPだけ専用の広い幅を持たせる（値の範囲自体は変更しない）。
const STAT_SPIN_MIN_SIZE_HP := Vector2(170.0, 32.0)
const STAT_SPIN_MIN_SIZE_DEFAULT := Vector2(120.0, 32.0)

var draft: RBMCreatorDraft
var main: Node

var _hp_slider: HSlider
var _hp_spin: SpinBox
var _atk_slider: HSlider
var _atk_spin: SpinBox
var _spd_slider: HSlider
var _spd_spin: SpinBox
var _weak_buttons: Dictionary = {}   # attribute(String) -> Button
var _resist_buttons: Dictionary = {}

var _edit_panel: Control

## Display values synchronized from the draft.
var _staged_hp := 0
var _staged_atk := 0
var _staged_spd := 0
var _staged_weak: Array = []
var _staged_resist: Array = []

## Reentrancy guard: refresh() programmatically writes .value onto BOTH the
## slider and its paired spinbox to keep them in sync, which itself re-fires
## value_changed on whichever control was just written. Without this guard,
## a value that HSlider/SpinBox internally round/step to a slightly different
## float than what was requested (a real risk near a Range's min/max/step
## boundaries) can make the "already equal, skip" check in _sync_control()
## never actually converge, so the two controls keep re-triggering each other
## forever. Setting this true for the duration of refresh()'s own writes, and
## having every value_changed handler bail out immediately while it's true,
## cuts the loop off unconditionally after one level, regardless of any float
## precision mismatch. (Discovered by an actual runaway hang while testing
## this exact drag-a-slider scenario — not a hypothetical risk.)
var _syncing := false

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
	## Creator本体UIコンセプト確定パス（2026-09-05）§5/§6: STEP1と同じ
	## 「十分な余白」規則をSTEP2にも適用する（RBMCreatorStep1Basic._build_ui()
	## と同じ値・同じ理由）。
	column.add_theme_constant_override("separation", 24)
	add_child(column)

	var card := PanelContainer.new()
	card.name = "StatsCard"
	column.add_child(card)
	var card_column := VBoxContainer.new()
	card_column.add_theme_constant_override("separation", 10)
	card.add_child(card_column)

	## §6: STEP1と同じCreator共通UI Kitのセクション見出し（本文より一段
	## 大きく、左に小さな銀アクセント）——各STEPで別々のデザインを作らない
	## （§8）。
	card_column.add_child(RBMCreatorUiKit.build_section_title(tr("ボス能力")))

	_edit_panel = VBoxContainer.new()
	_edit_panel.name = "StatsEditPanel"
	_edit_panel.visible = true
	## §6「項目同士が詰まりすぎない」: HP/ATK/SPDの各グループ・弱点/耐性・
	## 決定行の間に明確な間隔を持たせる。
	_edit_panel.add_theme_constant_override("separation", 18)
	card_column.add_child(_edit_panel)

	var hp_row := _build_synced_row(_edit_panel, "HP", RBMDefinitionLoader.BOSS_HP_MIN, RBMDefinitionLoader.BOSS_HP_MAX, STAT_SPIN_MIN_SIZE_HP)
	_hp_slider = hp_row[0]
	_hp_spin = hp_row[1]
	_hp_slider.value_changed.connect(_on_hp_control_changed)
	_hp_spin.value_changed.connect(_on_hp_control_changed)

	var atk_row := _build_synced_row(_edit_panel, "ATK", RBMDefinitionLoader.BOSS_ATK_MIN, RBMDefinitionLoader.BOSS_ATK_MAX, STAT_SPIN_MIN_SIZE_DEFAULT)
	_atk_slider = atk_row[0]
	_atk_spin = atk_row[1]
	_atk_slider.value_changed.connect(_on_atk_control_changed)
	_atk_spin.value_changed.connect(_on_atk_control_changed)

	var spd_row := _build_synced_row(_edit_panel, "SPD", RBMDefinitionLoader.BOSS_SPD_MIN, RBMDefinitionLoader.BOSS_SPD_MAX, STAT_SPIN_MIN_SIZE_DEFAULT)
	_spd_slider = spd_row[0]
	_spd_spin = spd_row[1]
	_spd_slider.value_changed.connect(_on_spd_control_changed)
	_spd_spin.value_changed.connect(_on_spd_control_changed)

	## §6: 弱点/耐性も、HP/ATK/SPDと同じ「小さな見出し→内容」の縦積みへ
	## 統一する（旧実装は見出しとボタン列が横1行に詰め込まれていた）。
	var weak_group := VBoxContainer.new()
	weak_group.name = "WeakGroup"
	weak_group.add_theme_constant_override("separation", 6)
	_edit_panel.add_child(weak_group)
	var weak_caption := Label.new()
	weak_caption.name = "WeakCaptionLabel"
	weak_caption.text = tr("弱点")
	weak_caption.theme_type_variation = RBMCreatorUiKit.VARIATION_SMALL_LABEL
	weak_group.add_child(weak_caption)
	var weak_row := HBoxContainer.new()
	weak_row.name = "WeakRow"
	weak_row.add_theme_constant_override("separation", 8)
	weak_group.add_child(weak_row)
	# 実機プレイ改善③ item8: ボタン自体のname/内部値(attribute)は引き続き
	# 英語ID（"FIRE"等）のまま——表示テキストだけRBMDefinitionLoader.
	# ATTRIBUTE_LABELS経由の日本語ラベルへ変換する。
	for attribute in RBMDefinitionLoader.VALID_ATTRIBUTES:
		var button := Button.new()
		button.name = "Weak_%s" % attribute
		button.text = tr(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute, attribute)))
		button.toggle_mode = true
		button.pressed.connect(_on_weak_button_pressed.bind(attribute))
		weak_row.add_child(button)
		_weak_buttons[attribute] = button

	var resist_group := VBoxContainer.new()
	resist_group.name = "ResistGroup"
	resist_group.add_theme_constant_override("separation", 6)
	_edit_panel.add_child(resist_group)
	var resist_caption := Label.new()
	resist_caption.name = "ResistCaptionLabel"
	resist_caption.text = tr("耐性")
	resist_caption.theme_type_variation = RBMCreatorUiKit.VARIATION_SMALL_LABEL
	resist_group.add_child(resist_caption)
	var resist_row := HBoxContainer.new()
	resist_row.name = "ResistRow"
	resist_row.add_theme_constant_override("separation", 8)
	resist_group.add_child(resist_row)
	for attribute in RBMDefinitionLoader.VALID_ATTRIBUTES:
		var button := Button.new()
		button.name = "Resist_%s" % attribute
		button.text = tr(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute, attribute)))
		button.toggle_mode = true
		button.pressed.connect(_on_resist_button_pressed.bind(attribute))
		resist_row.add_child(button)
		_resist_buttons[attribute] = button

	var note := Label.new()
	note.text = tr("数値・属性の変更はその場で反映されます。保存は最終確認から行えます。")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size",14)
	_edit_panel.add_child(note)

## §5/§6: 「HP」のような見出しを上段に、[HSlider][現在値SpinBox]を下段に
## 並べる——添付の基本構造どおり「項目名 → 現在値とスライダー」という
## 縦の読み順にする（旧実装は見出し・スライダー・数値が1行に詰め込まれて
## いた）。スライダーはSIZE_EXPAND_FILLで行の余白いっぱいに広がるように
## し（既存のcustom_minimum_size=CREATOR_SLIDER_MIN_SIZEはそのまま最小
## 保証として維持、操作のしやすさをさらに広げる）、SpinBox（現在値の数値
## 表示・直接編集）は既存の固定幅のまま右側に添える。値/最小値/最大値/
## step/シグナル配線・spin_min_size引数の意味は無改修。
func _build_synced_row(parent: Control, label_text: String, min_value: int, max_value: int, spin_min_size: Vector2 = STAT_SPIN_MIN_SIZE_DEFAULT) -> Array:
	var group := VBoxContainer.new()
	group.name = "%sGroup" % label_text
	group.add_theme_constant_override("separation", 4)
	parent.add_child(group)

	## Step 8 最終修正 §2: label_text引数を受け取っていながら、生成した
	## Labelへ一度も.textとして設定していなかった（row.name/slider.name/
	## spin.nameには使われていたが、実際に画面へ表示されるLabelは空のまま
	## だった）——HP/ATK/SPDの各行にキャプションが表示されていなかった
	## 直接の原因。
	var caption := Label.new()
	caption.name = "%sCaptionLabel" % label_text
	caption.text = label_text
	caption.theme_type_variation = RBMCreatorUiKit.VARIATION_SMALL_LABEL
	group.add_child(caption)

	var row := HBoxContainer.new()
	row.name = "%sRow" % label_text
	row.add_theme_constant_override("separation", 16)
	group.add_child(row)

	var slider := HSlider.new()
	slider.name = "%sSlider" % label_text
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 1
	## 実機プレイ改善①§10: 実際にドラッグ操作できなかった直接の原因を
	## --write-movie経由の合成マウスドラッグ調査で特定した——HSlider自身の
	## mouse_filter（既定STOP=0で問題なし）でも、他Controlとの重なりでもなく、
	## 「rectサイズ」そのものだった。custom_minimum_sizeで明確な最小サイズ
	## を直接与えることで、祖先チェーンの余剰幅計算に依存せず、常に十分な
	## ドラッグ可能領域を保証する（他のControl・Container構造・HP/ATK/SPDの
	## 値範囲・Draft反映ロジックには一切触れていない）。
	slider.custom_minimum_size = CREATOR_SLIDER_MIN_SIZE
	## Creator本体UIコンセプト確定パス §5: 最小サイズは変更せず、行の余白
	## いっぱいまでSIZE_EXPAND_FILLで広げる——「操作性重視」でドラッグ領域を
	## さらに広く取る（SpinBox側は既存の固定幅のまま、余白を専有しない）。
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var spin := SpinBox.new()
	spin.name = "%sSpin" % label_text
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1
	spin.update_on_text_changed = true
	spin.custom_minimum_size = spin_min_size
	row.add_child(spin)
	return [slider, spin]

func _on_hp_control_changed(v: float) -> void:
	if _syncing: return
	draft.hp = clampi(int(v),RBMDefinitionLoader.BOSS_HP_MIN,RBMDefinitionLoader.BOSS_HP_MAX)
	_updated()

func _on_atk_control_changed(v: float) -> void:
	if _syncing: return
	draft.atk = clampi(int(v),RBMDefinitionLoader.BOSS_ATK_MIN,RBMDefinitionLoader.BOSS_ATK_MAX)
	_updated()

func _on_spd_control_changed(v: float) -> void:
	if _syncing: return
	draft.spd = clampi(int(v),RBMDefinitionLoader.BOSS_SPD_MIN,RBMDefinitionLoader.BOSS_SPD_MAX)
	_updated()

func _sync_stat_controls() -> void:
	_syncing = true
	_hp_slider.value = _staged_hp
	_hp_spin.value = _staged_hp
	_atk_slider.value = _staged_atk
	_atk_spin.value = _staged_atk
	_spd_slider.value = _staged_spd
	_spd_spin.value = _staged_spd
	_syncing = false

func _on_weak_button_pressed(attribute: String) -> void:
	draft.toggle_weak_attribute(attribute)
	_updated()

func _on_resist_button_pressed(attribute: String) -> void:
	draft.toggle_resist_attribute(attribute)
	_updated()

func _sync_attribute_buttons() -> void:
	for attribute in _weak_buttons.keys():
		(_weak_buttons[attribute] as Button).button_pressed = _staged_weak.has(attribute)
	for attribute in _resist_buttons.keys():
		(_resist_buttons[attribute] as Button).button_pressed = _staged_resist.has(attribute)

func set_hp(value: int) -> void:
	draft.hp = clampi(value, RBMDefinitionLoader.BOSS_HP_MIN, RBMDefinitionLoader.BOSS_HP_MAX)
	refresh()

func set_atk(value: int) -> void:
	draft.atk = clampi(value, RBMDefinitionLoader.BOSS_ATK_MIN, RBMDefinitionLoader.BOSS_ATK_MAX)
	refresh()

func set_spd(value: int) -> void:
	draft.spd = clampi(value, RBMDefinitionLoader.BOSS_SPD_MIN, RBMDefinitionLoader.BOSS_SPD_MAX)
	refresh()

func toggle_weak(attribute: String) -> void:
	draft.toggle_weak_attribute(attribute)
	refresh()

func toggle_resist(attribute: String) -> void:
	draft.toggle_resist_attribute(attribute)
	refresh()

## Always derive displayed control values from the current draft.
func refresh() -> void:
	_staged_hp = draft.hp
	_staged_atk = draft.atk
	_staged_spd = draft.spd
	_staged_weak = draft.weak_attributes.duplicate()
	_staged_resist = draft.resist_attributes.duplicate()
	_sync_stat_controls()
	_sync_attribute_buttons()

func is_step_valid() -> bool:
	return draft.step2_is_valid()

func validation_message() -> String:
	return tr("HP/ATK/SPDを範囲内に設定してください")


func _updated() -> void:
	refresh()
	draft.sync_published_with_clear_check()
	if main != null and is_instance_valid(main._boss_profile_panel):
		main._boss_profile_panel.update(draft)
		main._status_label.text = "" if is_step_valid() else validation_message()

