class_name RBMPublicBossId
extends RefCounted

## 公開ID（2026-10-17 プレイ体験監査 PX-03、ユーザー確定）: オンライン公開ボスの id（サーバーが付ける UUID）の
## 先頭8文字（小文字の16進）。挑戦の一覧の詳細と、作者の保存したボス戦の詳細（オンライン公開中の時）に出し、
## 「ボスを検索」に入れるとそのボスを探せる（search-bosses がこの8文字で始まる id を探す）。
## 作者の保存一覧に出ている10桁の「ステージID」は手元の保存の番号で、サーバーには送っていない（別のもの）。

const LENGTH := 8

## boss_id（UUID）から公開IDを作る。UUID の形でなければ空。
static func from_boss_id(boss_id: String) -> String:
	var hex := boss_id.strip_edges().to_lower().replace("-", "")
	if hex.length() != 32 or not hex.is_valid_hex_number():
		return ""
	return hex.substr(0, LENGTH)
