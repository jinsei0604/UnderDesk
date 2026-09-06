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

const CONDITION_LOGIC_LABELS := {"AND": "すべて満たす (AND)", "OR": "いずれかを満たす (OR)"}
const SLOT_KIND_LABELS := {SLOT_KIND_SKILL: "通常攻撃", SLOT_KIND_RANDOM: "ランダム攻撃"}
const RANDOM_MODE_LABELS := {RANDOM_MODE_EVEN: "均等", RANDOM_MODE_MANUAL: "自分で設定"}
