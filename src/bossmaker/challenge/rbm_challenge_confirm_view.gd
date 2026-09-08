class_name RBMChallengeConfirmView
extends Control

## Phase 1 Step 7 §6〜§20 — CHALLENGE挑戦確認画面。stage一覧から1件選んだ
## 直後に必ずこの画面を経由する（§6: 選択→即戦闘開始はしない）。
##
## §36: このビューはRBMLocalStageRepository.load_stage()で新規に復元された
## RBMCreatorDraftインスタンスだけを受け取る。Creator側の（保存されていない
## 可能性がある）in-memory draftへの参照は一切受け取らない——open()の唯一の
## 呼び出し元RBMChallengeEntry._on_stage_row_pressed()がRepositoryから毎回
## 新規Draftを生成して渡すため、この分離は構造上保証されている。
##
## CHALLENGE UI再設計（挑戦ハブ + 共通ボス一覧画面、2026-09）§7〜§17:
## このクラスの役割を「独立した全画面確認ステップ」から「共通ボス一覧画面の
## 右側詳細パネル」へ変更した——選択と同時に即座にこのビューが更新され、
## 一覧（RBMChallengeEntry._list_panel）と常に横並びで表示され続ける。
## 「戻る」の概念自体が変わった（一覧へ戻るのではなく挑戦ハブへ戻る、
## その導線はRBMChallengeEntry._list_panel自身のヘッダへ移した）ため、
## 旧ConfirmBackButton/back_requestedは廃止した——「新しい『挑戦確認画面』を
## 作らない」(§17)の趣旨どおり、独立した確認ステップという概念自体を無くす。
## §12/§13: 大きなボス画像・作者名・モード（SIMPLE/HARDCORE）を追加。
## 挑戦者数・クリア率は一覧カード側に常時表示されるため、ここには一切
## 表示しない（重複表示禁止、§13）。

signal challenge_requested(definition: Dictionary)

const STATUS_LABELS := {
	"draft": "下書き",
	"playable": "挑戦可能",
	# 実機プレイ改善③ item8: "✓ CLEAR CHECKED"を日本語化（STEP7の
	# "✓ クリアチェック済み"と表記を統一——§11表記の一貫性）。
	"clear_checked": "✓ クリアチェック済み",
}

## CHALLENGE UI再設計: 独立した全画面確認ステップだった頃の80pxという値は
## 「ウィンドウ全体の左右余白」向けだった。埋め込み先（共通一覧画面の右
## カラム）が既に自分自身の余白を持つため、ここは軽い内部パディングだけに
## 縮める。
const CONTENT_SIDE_MARGIN_PX := 16.0

var stage_id: String = ""
var _draft: RBMCreatorDraft = null

var _content: VBoxContainer
var _empty_state_label: Label
var _detail_content: VBoxContainer
var _preview_swatch: TextureRect
var _boss_name_label: Label
var _author_label: Label
var _mode_label: Label
var _appearance_label: Label
var _stage_id_label: Label
var _clear_check_label: Label
var _win_condition_label: Label
var _special_condition_label: Label
var _author_notes_label: Label
var _random_notice_label: Label
var _stats_label: Label
var _weak_label: Label
var _resist_label: Label
var _boss_skills_section: VBoxContainer
var _party_section: VBoxContainer
var _challenge_button: Button

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	## Step 8 最終修正 §4: scroll（挑戦確認内容）とbutton_row（戻る/挑戦する）
	## を、このControl(RBMChallengeConfirmView)自身へ直接の兄弟として加えて
	## いたため、両者ともbareなControlの子として(0,0)付近に独立して重なって
	## 描画され、ボス/パーティ情報がほぼ見えなくなっていた（"戻る"/"挑戦する"
	## だけが見える、という報告どおりの症状）。RBMCreatorStep7Summaryと同じ
	## 修正——1つのVBoxContainerで両者を包み、「内容はスクロールし、下部の
	## ボタン行は常に固定表示される」構造にする。scroll/_content/button_row
	## 自身の構築・中身・_refresh()のロジックは無改修。
	var outer := VBoxContainer.new()
	outer.name = "ConfirmOuter"
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	## 実機プレイ改善①§12: RBMCreatorStep7Summaryのouterと同じ理由・同じ技法
	## ——上下のoffsetには一切触れず(scroll/button_rowの縦方向構造を保つ)、
	## 水平方向のoffset_left/offset_rightだけを追加する。
	outer.offset_left = CONTENT_SIDE_MARGIN_PX
	outer.offset_right = -CONTENT_SIDE_MARGIN_PX
	add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## §26実機確認で発見: 横スクロールを許したまま（既定のSCROLL_MODE_AUTO）
	## だと、ScrollContainerは子の幅を自身の可視幅に制約せず「必要なら横に
	## 伸ばして横スクロールバーを出す」——結果、autowrap_mode設定済みの
	## Label（作者メッセージ等）が折り返す基準となる有限の幅を一度も
	## 受け取れず、1行のまま右端で見切れる（横スクロールバーがそれを覆い
	## 隠す）。横スクロールを禁止し、子の幅を可視幅へ強制することで、
	## 既存のautowrap設定がここで初めて機能する。
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_content = VBoxContainer.new()
	_content.name = "ChallengeConfirmContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	## §11: 一覧でまだ何も選択していない間に表示する空状態。detail_content
	## と排他的にvisibleを切り替える（両方をContentへ直接の子として持つ）。
	_empty_state_label = Label.new()
	_empty_state_label.name = "ConfirmEmptyStateLabel"
	_empty_state_label.text = "左の一覧からボスを選択してください"
	_empty_state_label.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	_content.add_child(_empty_state_label)

	_detail_content = VBoxContainer.new()
	_detail_content.name = "ConfirmDetailContent"
	_detail_content.visible = false
	_content.add_child(_detail_content)

	# §12: 大きなボス画像・ボス名・作者名・SIMPLE/HARDCOREの識別ブロック。
	# RBMBattleUiKit.build_portrait_placeholder()は既存の「将来Texture差替え
	# 可能な空の額縁」ヘルパー（一覧カードの小サムネイルと同じ関数、サイズ
	# だけ大きくする）。
	var preview_frame := RBMBattleUiKit.build_portrait_placeholder(160.0, "ConfirmBossImage")
	_detail_content.add_child(preview_frame)
	_preview_swatch = TextureRect.new()
	_preview_swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_swatch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_swatch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_swatch.name = "ConfirmBossImageSwatch"
	_preview_swatch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_frame.add_child(_preview_swatch)

	_boss_name_label = _add_label_to(_detail_content, "")
	_boss_name_label.theme_type_variation = RBMUiTheme.VARIATION_SECTION_LABEL
	_author_label = _add_label_to(_detail_content, "")
	_author_label.name = "ConfirmAuthorLabel"
	_mode_label = _add_label_to(_detail_content, "")
	_mode_label.name = "ConfirmModeLabel"

	# Phase 3.5 UI統一§12: 「同じ大きさのLabelが延々と積まれた壁」ではなく、
	# 論理的なまとまりごとに細い区切り＋小見出しを挿入する——既存Label群の
	# 名前・順序・追加ロジックには一切触れず、新しいHSeparator/見出しLabelを
	# 間に挿む「追加専用」の変更のみ（§36で確認済み: 既存テストはこの画面の
	# 内容をfind_child/get_children()の全走査か件数比較でしか読まないため、
	# 兄弟の増加そのものは何も壊さない）。
	_add_confirm_section_header("ボス情報")
	_appearance_label = _add_label("")
	_stage_id_label = _add_label("")
	_clear_check_label = _add_label("")
	_win_condition_label = _add_label("")
	_special_condition_label = _add_label("")
	_author_notes_label = _add_label("")
	## §25: Clear Check側(RBMCreatorClearCheckView)と同じ表示条件
	## （RBMCreatorDraft.has_random_action_variance()）で、CHALLENGE挑戦確認
	## 画面にも同じ通知文を表示する。
	_random_notice_label = _add_label("このボスにはランダム行動が設定されています。挑戦ごとに行動が変化する場合があります。")
	_random_notice_label.name = "RandomActionNoticeLabel"

	_add_confirm_section_header("ボス性能")
	_stats_label = _add_label("")
	_weak_label = _add_label("")
	_resist_label = _add_label("")

	_boss_skills_section = VBoxContainer.new()
	_boss_skills_section.name = "BossSkillsSection"
	_detail_content.add_child(_boss_skills_section)

	_party_section = VBoxContainer.new()
	_party_section.name = "PartySection"
	_detail_content.add_child(_party_section)

	## §17: 「このボスに挑戦」のみ——独立した確認ステップという概念自体を
	## 廃止したため、旧「戻る」ボタン(ConfirmBackButton)は無くなった。
	_challenge_button = Button.new()
	_challenge_button.name = "ChallengeStartButton"
	_challenge_button.text = "このボスに挑戦"
	_challenge_button.pressed.connect(_on_challenge_pressed)
	outer.add_child(_challenge_button)

## CHALLENGE UI再設計: _detail_content（選択が無い間はvisible=falseになる
## サブコンテナ）へ追加する——_content自身へ直接追加すると、空状態
## （何も選択していない間）でも表示され続けてしまう。
func _add_label(text: String) -> Label:
	return _add_label_to(_detail_content, text)

func _add_label_to(parent: Control, text: String) -> Label:
	var label := _wrapped_label(text)
	parent.add_child(label)
	return label

## §26実機確認で発見: _refresh_boss_skills_section()/_refresh_party_section()
## /_add_hardcore_party_performance()は毎回子を全破棄して作り直す動的な
## セクションのため、_add_label()系ヘルパーを経由せずLabel.new()を直接
## 生成していた——結果、これらのLabelだけautowrap_modeが設定されず、
## 長いスキル一覧行（複数キャラ分のスキル名をカンマ区切りで連結）が
## 折り返さずパネル右端で見切れていた。以後はこの一点だけを経由させ、
## 動的セクションの全Labelにも_add_label_to()と同じ折り返しを適用する。
func _wrapped_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	return label

## Phase 3.5 UI統一§12: セクション区切り（細い枠線＋小見出し）。
## RBMBattleUiKit._add_state_section_header()と同じ語彙（HSeparator＋
## SmallLabel）をこの画面向けに複製——RBMBattleUiKitは戦闘UI専用ヘルパーの
## ため、Creator/Challenge側の確認画面から直接呼ぶのは責務が違う（既存の
## 「意図的な複製」方針を踏襲）。
func _add_confirm_section_header(text: String) -> void:
	var separator := HSeparator.new()
	_detail_content.add_child(separator)
	var header := Label.new()
	header.text = text
	header.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	_detail_content.add_child(header)

## §36: p_draftはRepositoryから復元されたばかりの新規インスタンスであること
## が前提（呼び出し元の設計で保証、このメソッド自体は受け取ったものをそのまま
## 表示するだけ）。
func open(p_stage_id: String, draft: RBMCreatorDraft) -> void:
	stage_id = p_stage_id
	_draft = draft
	_refresh()

## §11: まだ何も選択していない状態（一覧の初期表示、または公開取り下げ等で
## 選択中のstageが無効化された場合）。
func clear_selection() -> void:
	stage_id = ""
	_draft = null
	if _empty_state_label != null:
		_empty_state_label.visible = true
		_detail_content.visible = false
	# §26実機確認で発見: 未選択状態でも「このボスに挑戦」が常時クリック可能
	# に見えており（押しても_on_challenge_pressedのnullガードで無反応になる
	# だけ）、押せそうに見えて実は何も起きないボタンは紛らわしいUI不具合。
	# 選択状態と完全に連動させ、未選択中は隠す。
	if _challenge_button != null:
		_challenge_button.visible = false

func _refresh() -> void:
	if _draft == null:
		_empty_state_label.visible = true
		_detail_content.visible = false
		if _challenge_button != null:
			_challenge_button.visible = false
		return
	_empty_state_label.visible = false
	_detail_content.visible = true
	_challenge_button.visible = true

	_boss_name_label.text = _draft.boss_name
	# §10: 作者名は「ボスごとに公開時入力」——空欄は他の未入力フィールドと
	# 同じ語彙「（未設定）」で表示する。
	_author_label.text = "by %s" % (_draft.author_name if not _draft.author_name.is_empty() else "（未設定）")
	_mode_label.text = RBMChallengeUiKit.mode_display_text(_draft.creator_mode)
	if _draft.appearance_id.is_empty():
		_preview_swatch.texture = null
	else:
		_preview_swatch.texture = RBMVisualAssets.texture(RBMVisualAssets.boss_asset(_draft.appearance_id))
	_appearance_label.text = "外見: %s" % (RBMCreatorAppearanceCatalog.display_name(_draft.appearance_id) if not _draft.appearance_id.is_empty() else "（未選択）")
	_stage_id_label.text = "ステージID: %s" % stage_id

	# §8: 未クリアであることを危険・非推奨のニュアンスなしにそのまま伝える。
	_clear_check_label.text = STATUS_LABELS["clear_checked"] if _draft.is_clear_check_currently_valid() else "このボス戦はクリアチェックされていません"

	# 実機プレイ改善③ item1/3: 勝利条件・特殊条件も他の6項目と同じ公開設定
	# パターンで作者が非公開にできる——あえて情報を隠し、作者メッセージ側で
	# ヒントを与える遊び方を可能にするため。旧§9/§10の「現在のDefinition/
	# RBMBattleには特殊勝利条件の概念自体がまだ存在しないため、通常勝利条件
	# のみを表示する」という前提自体は無改修——_win_condition_text()/
	# _special_condition_text()（下記）はどちらも今も固定文字列を返すだけ
	# （将来特殊条件システムが追加された際にこの関数の中身だけ差し替えれば
	# 反映できる構造も無改修のまま維持）。
	_win_condition_label.text = "勝利条件: %s" % (_win_condition_text() if _draft.is_challenge_info_visible("win_condition") else "非公開")
	_special_condition_label.text = "特殊条件: %s" % (_special_condition_text() if _draft.is_challenge_info_visible("special_condition") else "非公開")

	# §16: 作者メッセージは常に表示（空なら「なし」）。
	# 実機プレイ改善② item1: 表示名を「作者備考」→「作者メッセージ」へ変更
	# （内部フィールド名author_notesは既存セーブ互換のため無改修）。
	_author_notes_label.text = "作者メッセージ: %s" % (_draft.author_notes if not _draft.author_notes.is_empty() else "（なし）")
	_random_notice_label.visible = _draft.has_random_action_variance()

	_refresh_stat_lines()
	_refresh_boss_skills_section()
	_refresh_party_section()

## §9: 現在のRBMBattle唯一の勝利条件（boss.hp<=0、RBMBattle._check_battle_over()
## 参照）をそのまま説明するだけの固定文字列。
func _win_condition_text() -> String:
	return "ボスのHPを0にする"

## §10: 現在のDefinition/RBMBattleに特殊条件の概念が無いため常に「なし」。
## 将来特殊条件システムが追加された際、この関数の中身だけを差し替えれば
## 確認画面へ反映できる構造にしてある（CHALLENGE側の他のコードは変更不要）。
func _special_condition_text() -> String:
	return "なし"

## §14/§18: HP/ATK/SPD/弱点/耐性を、公開設定に応じて実値か「？？？」で表示。
func _refresh_stat_lines() -> void:
	var hp_text := str(_draft.hp) if _draft.is_challenge_info_visible("hp") else "？？？"
	var atk_text := str(_draft.atk) if _draft.is_challenge_info_visible("atk") else "？？？"
	var spd_text := str(_draft.spd) if _draft.is_challenge_info_visible("spd") else "？？？"
	_stats_label.text = "HP %s / ATK %s / SPD %s" % [hp_text, atk_text, spd_text]

	# 実機プレイ改善③ item8/11: 属性名はRBMDefinitionLoader.ATTRIBUTE_LABELS
	# 経由の日本語ラベルで表示する（STEP2/STEP3/STEP7と同じ1つの対応表）。
	if _draft.is_challenge_info_visible("weak_attributes"):
		_weak_label.text = "弱点: %s" % (", ".join(_attribute_labels(_draft.weak_attributes)) if not _draft.weak_attributes.is_empty() else "なし")
	else:
		_weak_label.text = "弱点: ？？？"

	if _draft.is_challenge_info_visible("resist_attributes"):
		_resist_label.text = "耐性: %s" % (", ".join(_attribute_labels(_draft.resist_attributes)) if not _draft.resist_attributes.is_empty() else "なし")
	else:
		_resist_label.text = "耐性: ？？？"

func _attribute_labels(attributes: Array) -> Array:
	var labels: Array = []
	for attribute in attributes:
		var attribute_id := str(attribute)
		labels.append(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id)))
	return labels

## §14/§18: ボススキル詳細は個別項目ごとではなく、公開/非公開の単位で
## カテゴリ全体を切り替える（「非公開」という1行を表示し、個々のスキル内容
## そのものは一切見せない）。
func _refresh_boss_skills_section() -> void:
	for child in _boss_skills_section.get_children():
		child.queue_free()
	var header := _wrapped_label("ボススキル")
	header.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	_boss_skills_section.add_child(header)
	if not _draft.is_challenge_info_visible("boss_skills"):
		_boss_skills_section.add_child(_wrapped_label("非公開"))
		return
	if _draft.skills.is_empty():
		_boss_skills_section.add_child(_wrapped_label("（なし）"))
		return
	for skill in _draft.skills:
		_boss_skills_section.add_child(_wrapped_label("・%s" % str(skill.get("name", ""))))
		_boss_skills_section.add_child(_wrapped_label("  %s" % _skill_detail_text(skill)))

## §14「ボススキル詳細」: 公開時はRBMCreatorStep7Summary._add_skill_summary()
## と同等の粒度（種類/対象/属性/倍率、または回復方式/回復量、または強化倍率/
## 持続ターン）で見せる——スキル名だけでは「詳細」の名に見合わないため。
## RBMCreatorStep7Summaryとは別クラスとして意図的に複製している（このsrc/
## bossmaker/challenge/自体がsrc/bossmaker/creator/の確定済みコードに一切
## 触れない設計方針、このファイル冒頭コメント参照）。
func _skill_detail_text(skill: Dictionary) -> String:
	var type := str(skill.get("type", ""))
	match type:
		"attack":
			var target_label := "単体" if str(skill.get("target", "single")) == "single" else "全体"
			var attribute_id := str(skill.get("attribute", "NEUTRAL"))
			return "攻撃 / %s / %s / ATK ×%.2f" % [target_label, str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute_id, attribute_id)), float(skill.get("atk_multiplier", 0.0))]
		"self_heal":
			var mode := str(skill.get("heal_mode", "fixed"))
			if mode == "percent":
				return "回復 / 最大HPの%.1f%%（HP %d回復相当）" % [float(skill.get("heal_percent", 0.0)), _draft.resolved_heal_amount(skill)]
			return "回復 / HP %d回復" % int(skill.get("heal_fixed_amount", 0))
		"atk_self_buff":
			return "自己強化 / ATK ×%.2f / %dターン" % [float(skill.get("buff_multiplier", 1.0)), int(skill.get("duration_turns", 1))]
		_:
			return type

## 公開設定の最終修正（7→6項目）: 挑戦者が実際に使用するパーティ・使用可能
## スキルは、いかなる公開設定にも紐づかず常に表示する——攻略側パーティ・
## 使用可能スキルは`RBMCreatorDraft.CHALLENGE_INFO_VISIBILITY_KEYS`に一切
## 含まれておらず（旧「攻略側パーティ詳細」キーは削除済み）、この関数自体が
## `is_challenge_info_visible()`を一度も参照しないことでそれを保証している。
func _refresh_party_section() -> void:
	for child in _party_section.get_children():
		child.queue_free()
	var header := _wrapped_label("挑戦者が使用するパーティ・使用可能スキル")
	header.name = "PartySectionHeader"
	header.theme_type_variation = RBMUiTheme.VARIATION_SMALL_LABEL
	_party_section.add_child(header)
	if _draft.party_character_ids.is_empty():
		_party_section.add_child(_wrapped_label("（なし）"))
		return
	for character_id in _draft.party_character_ids:
		var master := _draft.master_character_def(character_id)
		var allowed: Array = _draft.ally_allowed_skill_ids.get(character_id, [])
		var names: Array = []
		for skill in master.get("skills", []):
			if allowed.has(str(skill.get("id", ""))):
				names.append(str(skill.get("display_name", "")))
		var row := _wrapped_label("・%s: %s" % [str(master.get("display_name", character_id)), (", ".join(names) if not names.is_empty() else "（なし）")])
		row.name = "PartyMemberRow_%s" % character_id
		_party_section.add_child(row)
		if _draft.creator_mode == RBMCreatorDraft.CREATOR_MODE_ADVANCED:
			_add_hardcore_party_performance(character_id, master, allowed)

func _add_hardcore_party_performance(character_id: String, master: Dictionary, allowed: Array) -> void:
	var effective := _draft.effective_character_def(character_id)
	# 挑戦者が必要なのは実戦で使われる値。標準値との重複比較は表示しない。
	var stats := _wrapped_label("  HP %d / ATK %d / SPD %d / Max SP %d" % [
		int(effective.get("hp", 1)), int(effective.get("atk", 1)),
		int(effective.get("spd", 1)), int(effective.get("max_sp", 1)),
	])
	stats.name = "PartyPerformanceStats_%s" % character_id
	_party_section.add_child(stats)
	var effective_skills := {}
	for skill_variant in effective.get("skills", []):
		if skill_variant is Dictionary:
			effective_skills[str((skill_variant as Dictionary).get("id", ""))] = skill_variant
	for master_skill_variant in master.get("skills", []):
		if not (master_skill_variant is Dictionary):
			continue
		var master_skill: Dictionary = master_skill_variant
		var skill_id := str(master_skill.get("id", ""))
		if not allowed.has(skill_id):
			continue
		var effective_skill: Dictionary = effective_skills.get(skill_id, master_skill)
		var parts: Array[String] = []
		for field in RBMDefinitionLoader.ally_skill_override_fields(master_skill):
			var field_label: String = str({
				"atk_multiplier": "倍率", "heal_amount": "回復量", "sp_amount": "SP回復量",
				"sp_cost": "SP消費", "buff_multiplier": "強化倍率", "duration_turns": "効果時間",
				"new_rate": "防御軽減率", "reduction_rate": "被ダメージ軽減率",
			}.get(field, field))
			if ["atk_multiplier", "buff_multiplier", "new_rate", "reduction_rate"].has(field):
				parts.append("%s %.2f" % [field_label, float(effective_skill[field])])
			else:
				parts.append("%s %d" % [field_label, int(effective_skill[field])])
		var skill_line := _wrapped_label("    %s: %s" % [str(master_skill.get("display_name", skill_id)), " / ".join(parts)])
		skill_line.name = "PartyPerformanceSkill_%s_%s" % [character_id, skill_id]
		_party_section.add_child(skill_line)

## §22: Definitionそのものはここで生成するが、RBMDefinitionLoader.resolve()
## による最終検証は呼び出し元（RBMChallengeEntry）が行う——TEST BATTLE/Clear
## Checkと同じ「検証はowner側の責務」という既存の役割分担を踏襲する。
func _on_challenge_pressed() -> void:
	if _draft == null:
		return
	challenge_requested.emit(_draft.to_definition())

