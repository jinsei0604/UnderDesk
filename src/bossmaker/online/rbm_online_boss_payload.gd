class_name RBMOnlineBossPayload
extends RefCounted

## Phase 4B/4C/4D — Creator Draft ⇄ オンライン送信用payloadの変換。
##
## 「Creator → Draft → Clear Check → online payload」を明確に分離する
## (ユーザー確定仕様)。ローカル保存(RBMLocalStageRepository)と同じ
## draft.to_saved_dict()を土台にしつつ、オンラインへ送る意味がない
## フィールド(author_notes=著作者の私的メモ、published/published_at_unix_time
## =ローカルChallenge一覧用のローカルフラグ)を取り除く。
##
## battle_hashはdraft.battle_content_snapshot()(既存のClear Check比較専用
## スナップショット——boss_name/appearance_id/battle_background等の非戦闘
## 要素は最初から含まれていない)から計算する。これにより、演出/表示だけの
## 変更ではbattle_hashが変わらず、戦闘内容の変更でのみ変わる
## (battle_content_snapshot()自体の既存契約をそのまま利用)。

const SCHEMA_VERSION := 1

## 現在このクライアントが読める最大schema_version。未知の(これより大きい)
## versionを持つオンラインボスは、そのままBattleへ流さず安全に拒否する
## (§4B-3/§4E-8「対応していないボスデータとして安全に拒否」)。
const MAX_SUPPORTED_SCHEMA_VERSION := 1

const _LOCAL_ONLY_FIELDS := ["author_notes", "published", "published_at_unix_time"]

## 公開直前に呼ぶ。Clear Check未達成、または現在の戦闘内容がClear Check
## 成功時のsnapshotと一致しない場合は送信前に拒否する
## (§4C-1/§4C-2、ユーザー確定仕様)。
##
## is_clear_check_currently_valid()自体が「has_ever_cleared() and
## battle_content_snapshot() == _clear_check_success_snapshot」を既に
## 検証している(rbm_creator_draft.gd参照)ため、§4C-2が求める「現在の
## battle_content_snapshotとClear Check成功時のsnapshotの一致確認」は
## この1回のチェックで両方満たされる——同じ比較を独立した2つ目のエラー
## 種別として重複実装しない(重複させると片方が到達不能な死んだ分岐に
## なることを確認済み)。
##
## 戻り値: {"ok": true, "payload": Dictionary} または
##         {"ok": false, "error": "clear_check_not_valid"}
static func build_for_publish(draft: RBMCreatorDraft) -> Dictionary:
	if not draft.is_clear_check_currently_valid():
		return {"ok": false, "error": "clear_check_not_valid"}

	var proven_snapshot := draft.clear_check_snapshot_for_save()
	var draft_fields := draft.to_saved_dict()
	for field in _LOCAL_ONLY_FIELDS:
		draft_fields.erase(field)

	var payload := {
		"schema_version": SCHEMA_VERSION,
		"boss_name": draft.boss_name,
		"author_name": draft.author_name,
		"draft_fields": draft_fields,
		"clear_check_success_snapshot": proven_snapshot,
		"battle_hash": RBMCanonicalJson.hash_of(proven_snapshot),
	}
	return {"ok": true, "payload": payload}

## ダウンロードしたオンラインpayloadから、既存Challenge経路
## (Draft.to_definition() → RBMDefinitionLoader.resolve() → RBMBattle)へ
## そのまま渡せるRBMCreatorDraftを再構築する。新しい別Battleエンジンは
## 作らない(ユーザー確定仕様)。
##
## 呼び出し前に必ずvalidate_for_challenge()を通すこと——この関数自体は
## 型検証を行わない(restore_from_saved_dict()自身の安全なフォールバック
## にのみ依存する)。
static func reconstruct_draft(payload: Dictionary) -> RBMCreatorDraft:
	var draft := RBMCreatorDraft.new()
	draft.restore_from_saved_dict(payload.get("draft_fields", {}))
	# ローカルChallenge(RBMChallengeEntry._on_stage_row_pressed())と同じ
	# 2段階復元——draft_fields(著作フィールド)だけでなく、Clear Check達成
	# snapshotも復元する。これが無いとdraft.has_ever_cleared()等、Challenge
	# 側UIが参照しうるClear Check関連の状態がオンラインpayloadだけ欠落する。
	draft.restore_clear_check_snapshot(payload.get("clear_check_success_snapshot", {}))
	return draft

## 挑戦前の安全確認。schema_version確認 → 型検証(RBMLocalStageRepositoryの
## 既存validationを再利用) → battle_hash再計算・突合、の順に行う。
## 戻り値: {"ok": true, "draft": RBMCreatorDraft} または
##   {"ok": false, "error": "unsupported_schema_version" | "invalid_payload_shape"
##                | "hash_mismatch" | "definition_invalid", "details": ...}
static func validate_for_challenge(payload: Dictionary) -> Dictionary:
	if not (payload is Dictionary):
		return {"ok": false, "error": "invalid_payload_shape"}

	var schema_version_variant: Variant = payload.get("schema_version", null)
	if typeof(schema_version_variant) != TYPE_INT and typeof(schema_version_variant) != TYPE_FLOAT:
		return {"ok": false, "error": "unsupported_schema_version"}
	var schema_version := int(schema_version_variant)
	if schema_version < 1 or schema_version > MAX_SUPPORTED_SCHEMA_VERSION:
		return {"ok": false, "error": "unsupported_schema_version"}

	var draft_fields_variant: Variant = payload.get("draft_fields", null)
	if not (draft_fields_variant is Dictionary):
		return {"ok": false, "error": "invalid_payload_shape"}
	var draft_fields: Dictionary = draft_fields_variant
	if not RBMLocalStageRepository.validate_draft_shape_for_online(draft_fields):
		return {"ok": false, "error": "invalid_payload_shape"}

	var stored_hash := str(payload.get("battle_hash", ""))
	if stored_hash.is_empty():
		return {"ok": false, "error": "invalid_payload_shape"}

	var draft := reconstruct_draft(payload)
	var recomputed_hash := RBMCanonicalJson.hash_of(draft.battle_content_snapshot())
	if recomputed_hash != stored_hash:
		return {"ok": false, "error": "hash_mismatch"}

	var resolved := RBMDefinitionLoader.resolve(draft.to_definition())
	if not bool(resolved.get("ok", false)):
		return {"ok": false, "error": "definition_invalid", "details": resolved.get("errors", [])}

	return {"ok": true, "draft": draft}
