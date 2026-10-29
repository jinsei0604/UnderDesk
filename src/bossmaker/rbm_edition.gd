class_name RBMEdition
extends RefCounted

## 製品版／体験版の切り替え（2026-10-28）。プロジェクトは1つのまま、体験版の書き出しプリセットの
## Custom Features に "demo" を入れた時だけ体験版になる。エディターでの実行・製品版の書き出しは常に製品版（既定）。
## 開発中に体験版を試す時は起動の引数に `--mc-demo`（`-- --mc-demo`）を付ける。
##
## 体験版の制限（ユーザーの指示）: ボスは竜・スライム・幽霊・機械武者の4体、作成は SIMPLE だけ（HARDCORE は製品版限定）、
## 手元の保存は5体まで、オンライン公開は1人2体まで（公開中を非公開・削除すれば入れ替えられる）。オンラインで挑戦できるのは
## 体験版の4体の SIMPLE ボスだけ（一覧・ランキングも同じ範囲）。プレイ時間の制限は無い。
## 保存先は製品版と別（data_root()）。製品版は体験版の保存を引き継げる（RBMDemoCarryOver）。
## サーバーも体験版のチケットを見分けて同じ制限をかける（supabase/functions/_shared/edition.ts）。

const FEATURE_TAG := "demo"
const DEV_ARGUMENT := "--mc-demo"
const DEMO_APPEARANCES: Array[String] = ["appearance_dragon", "appearance_slime", "appearance_ghost", "appearance_musha"]
const DEMO_MAX_LOCAL_SAVES := 5
const DEMO_MAX_ONLINE_PUBLISHED := 2
## サーバーへ体験版であることを伝える値（一覧の ?edition= と、本文の "edition"）。本人確認ではない
## （サーバーは Steam のチケットがどちらのアプリのものかで判断する）。
const DEMO_EDITION := "demo"
## 手元の保存の置き場。製品版は今までどおり user://bossmaker（変えない）。
const FULL_DATA_ROOT := "user://bossmaker"
const DEMO_DATA_ROOT := "user://bossmaker_demo"

## テスト用: -1=実際の判定、0=製品版、1=体験版。
static var _override := -1

static func is_demo() -> bool:
	if _override >= 0:
		return _override == 1
	# 起動の引数 --mc-demo は開発中（書き出していない版）だけ。書き出した版では引数で版を変えられない（製品版を体験版に
	# したり、体験版の制限を外したりできない。体験版の書き出しは "demo" の機能タグで決まる）。
	return OS.has_feature(FEATURE_TAG) or (not OS.has_feature("template") and OS.get_cmdline_user_args().has(DEV_ARGUMENT))

static func set_demo_for_testing(on: bool) -> void:
	_override = 1 if on else 0

static func reset_for_testing() -> void:
	_override = -1

## 手元の保存（stages・討伐記録・挑戦の記録・送信待ち・設定）の置き場。GUT（自動テスト）の中では本物の置き場に書かない。
static func data_root() -> String:
	if RBMLocalStageRepository.running_under_gut():
		return RBMLocalStageRepository.GUT_DEFAULT_ROOT + ("/demo" if is_demo() else "")
	return DEMO_DATA_ROOT if is_demo() else FULL_DATA_ROOT

## 体験版の置き場（製品版が引き継ぐ時に読む）。GUT の中ではテスト用の置き場。
static func demo_root() -> String:
	if RBMLocalStageRepository.running_under_gut():
		return RBMLocalStageRepository.GUT_DEFAULT_ROOT + "/demo"
	return DEMO_DATA_ROOT

static func allows_appearance(appearance_id: String) -> bool:
	return not is_demo() or DEMO_APPEARANCES.has(appearance_id)

static func allows_creator_mode(creator_mode: String) -> bool:
	return not is_demo() or creator_mode != RBMCreatorDraft.CREATOR_MODE_ADVANCED

## オンラインのボス（一覧の行・公開データ）が体験版で挑戦できる範囲か。行の creator_mode・appearance_id で判断する。
static func allows_online_boss(creator_mode: String, appearance_id: String) -> bool:
	if not is_demo():
		return true
	return creator_mode != RBMCreatorDraft.CREATOR_MODE_ADVANCED and DEMO_APPEARANCES.has(appearance_id)
