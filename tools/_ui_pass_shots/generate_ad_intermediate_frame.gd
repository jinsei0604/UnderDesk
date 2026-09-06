extends SceneTree

## 緊急修正パス（2026-09-03、9回目）②謎の横移動: A↔D遷移の中間フレーム
## 「AD」を生成する。
##
## 【調査結果】D自身の絵（姿勢）は正当——肩・胴体・骨盤・コート裾が
## 一貫して同じ方向へ緩やかに増加するカスケード（肩最大・裾に向かって
## 減少）、かつ膝から下・足の位置は完全固定（native全frame一致）——
## これは物理的に自然な「上半身が重心移動で傾き、足は接地したまま」
## という体重移動そのもの。実GPU・実背景合成の目視比較（torso_A_vs_D.png）
## でも、輪郭が破綻する・穴が開く等の異常は見られなかった。
##
## しかし、AとDの間に中間フレームが1枚も無く、単純な1回のtexture
## 差し替え（1描画フレームで即座に切り替わる）で表示されるため、実際の
## 変位量自体は小さい（実画面px平均で肩1.65px/胴体骨盤1.98px/コート裾
## 2.15px、8回目セッションの実測値）にもかかわらず、体全体が同じ方向へ
## 一斉に、経過時間ゼロで切り替わる——これが「自然な体重移動」ではなく
## 「スプライトが瞬間移動した」ように見える原因だと判断した（ユーザー
## 指示書の想定どおり、Dの絵ではなくA→D遷移そのものが原因）。
##
## 【対応】新しい絵は描き起こさず、既存のwarpパイプライン
## （_apply_full_body_warp、D生成時と全く同じ関数・同じ帯域定義）を
## そのまま流用し、D自身のソース画像(d_src)に対してD本番の50%の
## 変位量でwarpした「AD」を1枚だけ追加する。A→AD→D→AD→Aという
## 4段階遷移にすることで、瞬間移動に見えていた一回のジャンプを
## 2回の半分幅ジャンプへ分割する（新規の補間ロジック・Tween等は
## 追加しない、離散フレーム切り替えのみという既存方針を維持）。
##
## 追加修正パス（2026-09-03、11回目）「頭・首の連動」対応: D本番と
## 同じ head_band_d / head_amp_d（骨盤→肩の重心移動を頭まで延長する
## 水平dxのみ）を、AD_FRACTION=0.5で追加する——A→AD→Dで頭の位置も
## 中間段階を経て連続的に変化するようにした（頭だけA→D間で一段跳びに
## なることを避けるため）。d_regionのyの開始も300→50へ拡張し、頭部
## （帽子頂点native y=72付近）まで届くようにした。

const ORIG_DIR := "res://tools/_ui_pass_shots/originals/"
const OUT_PATH := "res://assets_bossmaker/art/creator_guide_idle_ad.png"
const DISPLAY_ALIGN := 2

## D本番生成時（generate_amplified_idle_frames.gd）と同一の帯域定義・
## 同一のDE_AMP_MULT=1.5。ADはこの50%の変位量で warp する。
const DE_AMP_MULT := 1.5
const AD_FRACTION := 0.5

func _init() -> void:
	var d_src := _load_raw(ORIG_DIR + "creator_guide_idle_d_posture.png")

	var d_region := Rect2i(150, 50, 670, 1300)
	var d_center_x := 470.0

	var shoulder_band := {"center_y": 460.0, "half_h": 140.0}
	var pelvis_band := {"center_y": 750.0, "half_h": 220.0}
	var d_hem_band := {"center_y": 1020.0, "half_h": 170.0}
	# D本番（generate_amplified_idle_frames.gd）と同一の頭部帯域・振幅。
	var head_band_d := {"center_y": 140.0, "half_h": 280.0}
	var head_amp_d := 2.6

	var leg_band_y := {"center_y": 1030.0, "half_h": 110.0}
	var weight_leg_x := {"center_x": 460.0, "half_x": 85.0}
	var relax_leg_x := {"center_x": 310.0, "half_x": 85.0}

	var weight_leg_amp := (0.6 * DE_AMP_MULT + 0.1 * (DE_AMP_MULT - 1.0)) * AD_FRACTION
	var relax_leg_amp := (2.6 * DE_AMP_MULT + 0.6 * (DE_AMP_MULT - 1.0)) * AD_FRACTION

	var ad := d_src.duplicate()
	_apply_full_body_warp(ad, d_src, d_region, {
		"shoulder": {"band": shoulder_band, "amp_x": 3.0 * DE_AMP_MULT * AD_FRACTION, "tilt": 1.8 * DE_AMP_MULT * AD_FRACTION, "center_x": d_center_x, "half_x": 220.0},
		"pelvis": {"band": pelvis_band, "amp_x": 3.5 * DE_AMP_MULT * AD_FRACTION, "center_x": d_center_x},
		"hem": {"band": d_hem_band, "amp_x": 2.0 * DE_AMP_MULT * AD_FRACTION, "tilt": 3.0 * DE_AMP_MULT * AD_FRACTION, "center_x": d_center_x, "half_x": 220.0},
		"head": {"band": head_band_d, "amp_x": head_amp_d * AD_FRACTION},
		"legs": [
			{"band_y": leg_band_y, "band_x": weight_leg_x, "amp_x": weight_leg_amp},
			{"band_y": leg_band_y, "band_x": relax_leg_x, "amp_x": relax_leg_amp},
		],
	})

	ad.save_png(ProjectSettings.globalize_path(OUT_PATH))
	print("saved %s" % OUT_PATH)
	quit()

func _load_raw(path: String) -> Image:
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	return img

func _round_display_aligned(value: float) -> int:
	return int(round(value / float(DISPLAY_ALIGN))) * DISPLAY_ALIGN

func _falloff_1d(v: float, center: float, half_width: float) -> float:
	var dist := absf(v - center)
	if dist >= half_width:
		return 0.0
	return 0.5 * (1.0 + cos(PI * dist / half_width))

func _apply_full_body_warp(out: Image, source_frame: Image, region: Rect2i, spec: Dictionary) -> void:
	var shoulder: Dictionary = spec["shoulder"]
	var pelvis: Dictionary = spec["pelvis"]
	var hem: Dictionary = spec["hem"]
	var legs: Array = spec["legs"]
	# 頭・首の連動（11回目セッション、新規、AD用）: 存在しなければ無効
	# （既存呼び出し元との後方互換）。dxのみ、tiltは持たない。
	var head: Dictionary = spec.get("head", {})

	for y in range(region.position.y, region.position.y + region.size.y):
		var shoulder_f := _falloff_1d(float(y), shoulder["band"]["center_y"], shoulder["band"]["half_h"])
		var pelvis_f := _falloff_1d(float(y), pelvis["band"]["center_y"], pelvis["band"]["half_h"])
		var hem_f := _falloff_1d(float(y), hem["band"]["center_y"], hem["band"]["half_h"])
		var head_f := 0.0
		if not head.is_empty():
			head_f = _falloff_1d(float(y), head["band"]["center_y"], head["band"]["half_h"])

		for x in range(region.position.x, region.position.x + region.size.x):
			var dx := 0.0
			var dy := 0.0

			if head_f > 0.0:
				dx += float(head["amp_x"]) * head_f

			if shoulder_f > 0.0:
				dx += float(shoulder["amp_x"]) * shoulder_f
				var lateral: float = clampf((float(x) - float(shoulder["center_x"])) / float(shoulder["half_x"]), -1.0, 1.0)
				dy += float(shoulder["tilt"]) * lateral * shoulder_f

			if pelvis_f > 0.0:
				dx += float(pelvis["amp_x"]) * pelvis_f

			if hem_f > 0.0:
				dx += float(hem["amp_x"]) * hem_f
				var lateral_h: float = clampf((float(x) - float(hem["center_x"])) / float(hem["half_x"]), -1.0, 1.0)
				dy += float(hem["tilt"]) * lateral_h * hem_f

			for leg in legs:
				var fy: float = _falloff_1d(float(y), leg["band_y"]["center_y"], leg["band_y"]["half_h"])
				if fy <= 0.0:
					continue
				var fx: float = _falloff_1d(float(x), leg["band_x"]["center_x"], leg["band_x"]["half_x"])
				if fx <= 0.0:
					continue
				dx += float(leg["amp_x"]) * fy * fx

			var dx_i := _round_display_aligned(dx)
			var dy_i := _round_display_aligned(dy)
			if dx_i == 0 and dy_i == 0:
				continue
			var src_x := x - dx_i
			var src_y := y - dy_i
			if src_x < 0 or src_x >= source_frame.get_width() or src_y < 0 or src_y >= source_frame.get_height():
				continue
			out.set_pixel(x, y, source_frame.get_pixel(src_x, src_y))
