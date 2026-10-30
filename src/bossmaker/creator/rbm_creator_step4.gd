class_name RBMCreatorStep4
extends Control

## RPG BOSS MAKER Phase 2 §5/§6/§22 — STEP 4の入口ラッパー。
##
## UI改善②/③: モード切替UI（切替ボタン＋ADVANCED→SIMPLEの確認ダイアログ）
## はこのクラスから完全に撤去し、RBMCreatorStep7Summary（最終確認画面）へ
## 移設した——STEP4は「Creator開始時に選んだモードのSTEP4専用画面をそのまま
## 表示するだけ」の入口ラッパーに専念する。役割は2つだけ:
## 1. draft.creator_modeに応じて、SIMPLE用のRBMCreatorStep4Actions（既存、
##    無改修）とADVANCED用のRBMCreatorStep4ActionPatterns（新規）のどちらか
##    一方だけをvisibleにする——両方とも常に生成・setup済みで、切替時に
##    作り直さない（既存Draftデータをそのまま両ビューが読み書きできる）。
## 2. RBMCreatorMainが要求するsetup/refresh/is_step_valid/validation_message
##    契約を、現在表示中のサブビューへ委譲するだけで満たす。
##
## モード切替自体のロジック（can_switch_to_simple_without_confirmation()/
## set_creator_mode()/discard_advanced_settings_and_revert_to_simple()）は
## RBMCreatorDraft側の既存メソッドを一切変更せずそのままSTEP7から呼ぶ——
## §22確定（SIMPLE→ADVANCEDは常に無確認、ADVANCED→SIMPLEはhas_advanced_
## only_settings()が真の場合のみ確認ダイアログを挟む）もこのまま維持される。

## 実機プレイ改善①§12/STEP7と同じ「左右余白のみ」パターン
## （RBMCreatorStep7Summary._build_ui()参照）。views_root
## （SIZE_EXPAND_FILLで実際の縦幅を得る）が上下いっぱいに広がるよう、
## PRESET_FULL_RECTで一旦上下ぴったりに揃えてから、水平方向の
## offset_left/offset_rightだけを上書きする——上下(offset_top/bottom)は
## PRESET_FULL_RECTが計算した0のまま変更しない。
const CONTENT_SIDE_MARGIN_PX := 80.0

var draft: RBMCreatorDraft
var main: Node

var _simple_view: RBMCreatorStep4Actions
var _advanced_view: RBMCreatorStep4ActionPatterns

func setup(p_draft: RBMCreatorDraft, p_main: Node) -> void:
	draft = p_draft
	main = p_main
	_build_ui()

func _build_ui() -> void:
	var views_root := Control.new()
	views_root.name = "Step4ViewsRoot"
	views_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	views_root.offset_left = CONTENT_SIDE_MARGIN_PX
	views_root.offset_right = -CONTENT_SIDE_MARGIN_PX
	add_child(views_root)

	_simple_view = RBMCreatorStep4Actions.new()
	_simple_view.name = "SimpleView"
	_simple_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	views_root.add_child(_simple_view)
	_simple_view.setup(draft, main)

	_advanced_view = RBMCreatorStep4ActionPatterns.new()
	_advanced_view.name = "AdvancedView"
	_advanced_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	views_root.add_child(_advanced_view)
	_advanced_view.setup(draft, main)

	## ボスの覚醒は SIMPLE でも HARDCORE と同じ設定（2026-10-29 ユーザー確定）。SIMPLE の一覧の「覚醒」から、
	## HARDCORE の画面の覚醒の設定（条件の2段階の選択・覚醒の入力欄）だけを開き、閉じたら SIMPLE の一覧へ戻す。
	_simple_view.awakening_requested.connect(_on_simple_awakening_requested)
	_advanced_view.awakening_only_closed.connect(_on_awakening_only_closed)

func _on_simple_awakening_requested() -> void:
	_advanced_view.open_awakening_only()
	if _advanced_view.is_awakening_only_open():
		_simple_view.visible = false
		_advanced_view.visible = true

func _on_awakening_only_closed() -> void:
	refresh()

## SIMPLE で覚醒の設定を開いている間だけ、HARDCORE の画面を出す（操作・Esc はその画面が受ける）。
func _current_view() -> Node:
	if draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED or _advanced_view.is_awakening_only_open():
		return _advanced_view
	return _simple_view

func refresh() -> void:
	var shown := _current_view()
	_simple_view.visible = shown == _simple_view
	_advanced_view.visible = shown == _advanced_view
	shown.refresh()

## Esc（PX-13、2026-10-18）を、この STEP の中の画面が受け取ったら true（RBMCreatorMain が STEP を戻らない）。
func escape() -> bool:
	var view := _current_view()
	return bool(view.call("escape")) if view.has_method("escape") else false

func is_step_valid() -> bool:
	return _mode_view().is_step_valid()

func validation_message() -> String:
	return _mode_view().validation_message()

func _mode_view() -> Node:
	return _advanced_view if draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED else _simple_view
