class_name RBMActionPatternRules
extends RefCounted

## RPG BOSS MAKER — HARDCORE Creator「攻撃（action_sequence）」の共有語彙・上限値。
##
## 新仕様（2026-09-05全面再設計）: 旧「行動パターン」概念（プレイヤーが複数の
## 条件・複数行動ステップ・発動確率・Cooldownを持つ"パターン"を優先度順に
## 組み立てる方式）を完全に廃止し、「ボスが使用する攻撃を作り、行動する順番に
## 並べる」方式（RBMCreatorDraft.action_sequence、行動順に並んだ「配置スロット」
## の単純な配列）へ全面移行した。このクラスのファイル名/クラス名は歴史的名残
## として変更していない（Godotのグローバルclass_name登録・.uidの不要なchurn
## を避けるため、既存プロジェクト規約どおり）——中身は新方式「スロット」の
## 語彙のみを持つ。
##
## 旧実装との主な違い:
## - 「瞬間条件」（〜になった瞬間、対応するイベントキュー・§7の2択post_instant
##   behavior）は新仕様に一切存在しない——新HARDCOREの実装依頼（33節）が
##   これに一度も言及していないこと、瞬間条件が「行動パターン」固有の機能
##   だったこと（行動パターン自体が廃止対象）、瞬間条件の「1回のボス行動
##   機会内で複数ステップを連続実行する」という前提が新仕様の「1ターン＝
##   1スロット」の原則（§18で明示的に廃止対象）と両立しないことから、今回
##   完全に削除した。通常条件（NORMAL_CONDITION_TYPES）のみを各スロットが
##   直接持つ形で存続する。
## - 「発動確率」「Cooldown」を完全に廃止（§9で明示指定）。使用回数のみ
##   スロット単位で残す。
## - 「1パターン内の複数行動ステップ」（actions配列）という入れ子構造も
##   廃止——1スロット＝1攻撃（固定skill、またはランダム候補群）のみを持つ。
## - このクラスは判定ロジックを一切持たない（旧実装から変わらない方針）。
##   判定はRBMBattleが行う。ここは両者（Creator UI側の型リスト・ラベル表示、
##   RBMDefinitionLoader側の検証、RBMBattle側の「発動可能か」判定）が共有する
##   定数の単一の正だけを持つ。

## 通常条件（ボスの通常行動選択＝毎ターンのスロット走査時に、現在の状態を
## そのまま判定する）。旧実装にあった瞬間条件タイプ（hp_at_most_instant等）
## は削除済み——このリストが条件タイプの唯一の正になった。
const NORMAL_CONDITION_TYPES: Array[String] = [
	"hp_at_most", "hp_at_least", "hp_between",
	"turn_at", "turn_at_least", "turn_at_most", "turn_every_n", "turn_between",
	"allies_at_most", "allies_at_least", "allies_exactly",
	"character_alive", "character_downed",
	"last_boss_skill", "last_received_skill", "last_received_attribute", "weak_hit",
]

## 通常攻撃(action_sequence、ランダム攻撃スロット含む)側のCreator UIの
## 「条件の種類」ドロップダウンに表示する選択肢——検証用のNORMAL_CONDITION_
## TYPES(旧保存データとの後方互換のため全型をそのまま残す、意味的
## validationは変更しない)とは別に、UIが「新規に選べる」型だけを絞り込む。
## turn_between(「○〜○ターンのあいだ」)は分かりにくいため新規選択肢からは
## 除外するが、既存データのturn_between条件はNORMAL_CONDITION_TYPES・
## RBMBattleの条件判定・RBMActionPatternSummaryの表示のいずれからも削除
## していない——引き続き正しく読み込み・判定・表示される（新規に選べなく
## なるだけ）。
## 2026-10-29 ユーザー確定: 新しく選べるのは4カテゴリ（ボスHP・ターン・攻略側生存人数・特定キャラクターの状態）の
## 11種類だけ（下の CONDITION_CATEGORIES）。それ以外の旧条件は、保存済みのデータでは消さずに使い続ける。
const NORMAL_ACTION_UI_CONDITION_TYPES: Array[String] = [
	"hp_at_most", "hp_at_least",
	"turn_at", "turn_at_least", "turn_at_most", "turn_every_n",
	"allies_at_most", "allies_at_least", "allies_exactly",
	"character_alive", "character_downed",
]

## 覚醒(Awakening)側の新しく選べる条件。2026-10-29 ユーザー確定: 行動と同じ4カテゴリ（下の CONDITION_CATEGORIES）。
## 旧6種類のうち「前回受けたスキル」「前回受けた属性」は新しく選べなくした（保存済みの条件は消さず、読み込み・判定も今までどおり）。
const AWAKENING_UI_CONDITION_TYPES: Array[String] = [
	"hp_at_most", "hp_at_least",
	"turn_at", "turn_at_least", "turn_at_most", "turn_every_n",
	"allies_at_most", "allies_at_least", "allies_exactly",
	"character_alive", "character_downed",
]

## 発動条件の2段階の選び方（2026-10-29 ユーザー確定）。第1段階はカテゴリ（4つ）、第2段階はカテゴリごとの比較方法と値。
## 行動（条件で分岐の行）と覚醒の両方で使う。ここに無い条件（ボスHPの範囲・○〜○ターン・前回の行動/受けたスキル/属性/弱点）は
## 新しく選べないが、保存済みのデータでは消さずに読み込み・判定・表示を続ける（NORMAL_CONDITION_TYPES は変えない）。
## compare_labels は types と同じ順（表示用、tr() で訳す）。
const CONDITION_CATEGORIES := [
	{"id": "boss_hp", "label": "ボスHP", "types": ["hp_at_most", "hp_at_least"], "compare_labels": ["以下", "以上"]},
	{"id": "turn", "label": "ターン", "types": ["turn_at", "turn_at_least", "turn_at_most", "turn_every_n"], "compare_labels": ["ちょうど", "以降", "まで", "ごと"]},
	{"id": "allies", "label": "攻略側生存人数", "types": ["allies_at_most", "allies_at_least", "allies_exactly"], "compare_labels": ["以下", "以上", "ちょうど"]},
	{"id": "character", "label": "特定キャラクターの状態", "types": ["character_alive", "character_downed"], "compare_labels": ["生存", "戦闘不能"]},
]

## 条件の種類が、どのカテゴリの何番目の比較方法か（新しく選べない種類なら [-1, -1]）。
static func condition_category_position(condition_type: String) -> Array:
	for i in range(CONDITION_CATEGORIES.size()):
		var types: Array = CONDITION_CATEGORIES[i]["types"]
		var j := types.find(condition_type)
		if j >= 0:
			return [i, j]
	return [-1, -1]

const CONDITION_LOGIC_TYPES: Array[String] = ["AND", "OR"]

## 1つのスロット内では単一のAND/ORのみ（ネスト条件は実装しない、旧仕様を
## 踏襲）。
const DEFAULT_CONDITION_LOGIC := "AND"

## action_sequence全体（配置スロットの総数）に対する安全上の上限。旧
## MAX_ACTIONS_PER_PATTERN（1パターン内の行動数の上限）と同じ「異常なデータ
## 増加を防ぐ安全上限」という設計意図をそのまま踏襲し、新モデルでは
## 「ボスが持つ攻撃スロットの総数」という自然に対応する対象へ引き継いだ
## （値20も既存のまま——ゲームバランス上の制約ではなく内部安全上限）。
const MAX_ACTION_SEQUENCE_SLOTS := 20

## スロットの種類。固定攻撃(skill)か、複数の作成済み攻撃から抽選する
## ランダム攻撃(random)か。
const SLOT_KIND_SKILL := "skill"
const SLOT_KIND_RANDOM := "random"
const SLOT_KINDS: Array[String] = [SLOT_KIND_SKILL, SLOT_KIND_RANDOM]

## ランダム攻撃の確率設定方式（旧仕様を維持——§13「既存のランダム抽選処理を
## 再利用」、evenm/manualやweight設定は既存正式仕様として必要と明示された）。
const RANDOM_MODE_EVEN := "even"
const RANDOM_MODE_MANUAL := "manual"
const RANDOM_MODES: Array[String] = [RANDOM_MODE_EVEN, RANDOM_MODE_MANUAL]

## 使用回数「制限なし」を表すセンチネル（旧仕様を維持）。
const UNLIMITED_USES := -1

## HARDCORE「通常行動」（2026-10-28 ユーザー確定仕様）: 戦闘のターン番号ごとの設定表
## （RBMCreatorDraft.turn_actions）。N ターン目には必ず N 番目の設定を使い、最後の設定の
## 次は1番目へ戻って繰り返す。各ターンの決め方は次の3つのどれか1つ（条件と使用率は
## 同じターンで組み合わせない）:
##   fixed       … 行動を1つ確定で使う
##   random      … 2つ以上の候補から使用率で抽選する
##   conditional … 上から順に条件を見て、最初に満たした行動を使う。どれも満たさなければ「それ以外」
## 使用回数の制限は無い。旧方式（action_sequence）は読み込み・戦闘の互換のためだけに残す。
const TURN_MODE_FIXED := "fixed"
const TURN_MODE_RANDOM := "random"
const TURN_MODE_CONDITIONAL := "conditional"
const TURN_MODES: Array[String] = [TURN_MODE_FIXED, TURN_MODE_RANDOM, TURN_MODE_CONDITIONAL]
const TURN_MODE_LABELS := {TURN_MODE_FIXED: "確定", TURN_MODE_RANDOM: "使用率で抽選", TURN_MODE_CONDITIONAL: "条件で分岐"}
## HARDCORE 限定の勝利条件（2026-10-29 ユーザー確定）。行動の発動条件とは別のもの（挑戦者がどうすれば勝つか）。
##   defeat_boss   … ボスを撃破する（通常、HP0 で勝利。保存データに勝利条件が無い時もこれ）
##   survive_turns … 指定ターンを生き残る（turns ターン目の終わりに味方が1人でも生きていれば勝利。ボスは HP0 でも行動する）
const VICTORY_DEFEAT_BOSS := "defeat_boss"
const VICTORY_SURVIVE_TURNS := "survive_turns"
const SURVIVE_TURNS_MIN := 1
const SURVIVE_TURNS_MAX := 99
const SURVIVE_TURNS_DEFAULT := 10

## 設定できるターンの数と、1ターンの候補・条件の数の安全上の上限（ゲームバランスの制約ではない）。
const MAX_TURN_ACTIONS := 20
const MAX_TURN_ENTRIES := 10

## Creator UI表示専用ラベル。RBMDefinitionLoader.ATTRIBUTE_LABELSと同じ
## 位置づけ——内部の条件タイプ文字列（保存JSON/Definition/RBMBattleの
## evaluate分岐が参照する値）には一切影響しない、表示だけの日本語訳を
## この1箇所に集約する。
const CONDITION_TYPE_LABELS := {
	"hp_at_most": "ボスHP ○%以下",
	"hp_at_least": "ボスHP ○%以上",
	"hp_between": "ボスHP ○%〜○%のあいだ",
	"turn_at": "○ターン目",
	"turn_at_least": "○ターン以降",
	"turn_at_most": "○ターンまで",
	"turn_every_n": "○ターンごと",
	"turn_between": "○〜○ターンのあいだ",
	"allies_at_most": "攻略側生存人数 ○人以下",
	"allies_at_least": "攻略側生存人数 ○人以上",
	"allies_exactly": "攻略側生存人数 ○人",
	"character_alive": "特定キャラクターが生存している",
	"character_downed": "特定キャラクターが戦闘不能",
	"last_boss_skill": "前回のボス行動が特定スキル",
	"last_received_skill": "前回受けたスキルが特定スキル",
	"last_received_attribute": "前回受けた属性が特定属性",
	"weak_hit": "前回受けた攻撃が弱点だった",
}

## これらも表示専用ラベル——キー(AND/OR、SLOT_KIND_*、RANDOM_MODE_*)は
## 内部IDのため翻訳対象ではない。呼び出し側で.get()の結果へtr()を適用する。
const CONDITION_LOGIC_LABELS := {"AND": "すべて満たす (AND)", "OR": "いずれかを満たす (OR)"}
const SLOT_KIND_LABELS := {SLOT_KIND_SKILL: "通常攻撃", SLOT_KIND_RANDOM: "ランダム攻撃"}
const RANDOM_MODE_LABELS := {RANDOM_MODE_EVEN: "均等", RANDOM_MODE_MANUAL: "自分で設定"}
