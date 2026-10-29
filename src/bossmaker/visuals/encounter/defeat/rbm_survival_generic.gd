extends "res://src/bossmaker/visuals/encounter/rbm_defeat_base.gd"
## 耐久成功の共通の演出（表示専用。2026-10-29 ユーザー確定）。HARDCORE の勝利条件「指定ターンを生き残る」で勝った時、
## 撃破の演出（とどめのスロー・ボスが倒れる）の代わりに使う。ボスは倒れず、本番の見た目のまま立っている。
## この後は通常の勝利と同じく、味方の反応・ファンファーレ・文字（「耐久成功！」）→ 結果パネル（RBMVictoryPlayer）。
## ボスごとの耐久勝利専用の退場モーションは、RBMVictoryPlayer.SURVIVAL にボスの素材 ID とスクリプトを足せば差し替わる
## （このスクリプトと同じく rbm_defeat_base.gd を継承し、final_blow()/begin()/advance()/duration() を書く）。

## この演出で鳴らす音（事前読み込みの宣言）。共通の音（ファンファーレ等）は RBMVictoryPlayer.COMMON_SOUNDS。
const SOUNDS: Array = []

## ボスは倒れないので、本番のボスの見た目を隠さず、何も描かない。
func final_blow() -> void:
	pass

func final_advance(_t: float, _dt: float) -> void:
	pass

func begin() -> void:
	pass

## 味方の反応が始まるまでの短い間（決着の後、ひと呼吸）。
func duration() -> float:
	return 0.6
