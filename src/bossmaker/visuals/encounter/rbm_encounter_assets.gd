extends RefCounted
## 登場・勝利の演出が読む素材の宣言（表示専用）。事前読み込み（rbm_presentation_warmup.gd）が、ほかの演出スクリプトと同じ
## warm_paths(asset_id, kind) の形で問い合わせる（ボス・味方ごとの知識は演出側に置く）。
## kind:
##   "intro"        … ボスの登場（ボスの12ポーズ・ボス専用のコマ絵・登場の音）
##   "intro_ally"   … 味方の身構えのポーズ（登場の中で使う）
##   "final_blow"   … とどめの命中の瞬間（とどめの音・ボスの被弾の姿勢）
##   "victory"      … ボスの倒れ方・勝利の共通の音（ファンファーレなど）
##   "victory_ally" … 味方の勝利の動き（Codex の中割りのコマの1枚絵）
## 戦闘の状態・乱数・保存データは読まない。
const IntroPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_intro_player.gd")
const VictoryPlayer = preload("res://src/bossmaker/visuals/encounter/rbm_victory_player.gd")
const AllyFrames = preload("res://src/bossmaker/visuals/encounter/rbm_encounter_ally_frames.gd")
const Choreo = preload("res://src/bossmaker/visuals/encounter/rbm_intro_choreo.gd")
const Assets = preload("res://src/bossmaker/visuals/rbm_visual_assets.gd")

static func warm_paths(asset_id: String, kind: String) -> Array[String]:
	match kind:
		"intro":
			return IntroPlayer.warm_paths(asset_id, [])
		"intro_ally":
			var out: Array[String] = []
			if Choreo.READY_POSE.has(asset_id):
				out.append(Assets.frame_path(asset_id, int(Choreo.READY_POSE[asset_id])))
			return out
		"final_blow":
			return VictoryPlayer.final_blow_paths(asset_id)
		"victory":
			return VictoryPlayer.warm_paths(asset_id, [])
		"victory_ally":
			return AllyFrames.warm_paths([asset_id])
	var none: Array[String] = []
	return none
