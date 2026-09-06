extends SceneTree

## §8回目セッション: 横ズレ再修正＋中間フレーム追加＋タイミング再設計。
##
## 【今回の実GPU調査で新たに判明した横ズレの真因】前回(7回目)までの
## ネイティブ解像度でのピクセル差分調査では、A→B/A→C/A→D/A→Eいずれも
## シルエット境界が「連続的」に動いており、輪郭が破綻するような穴/ノッチは
## 見つからなかった（diff可視化で確認済み）。しかし実際にRBMCreatorEntry
## 経由でGUIDE_CHARACTER_SCALE=0.50（ネイティブ→画面が正確に2:1の
## ダウンスケール）で表示した状態のBefore/After screenshotを直接比較した
## ところ、B/Cの差分が輪郭だけでなく上着の内部（縫い目・ハイライト等）
## にまで「散らばったノイズ」として現れることを確認した。
##
## 原因: `_apply_vbands`等のwarpはdy_i(またはdx_i)を`int(round(...))`で
## 「最も近い整数」に丸めているため、Y方向に連続的に変化するfalloff値が
## 奇数/偶数どちらの整数に丸まるかは行ごとに（またはX方向にも）不規則に
## 入れ替わる。画面には2:1の最近傍縮小（GUIDE_CHARACTER_SCALE=0.50）が
## かかるため、実際に画面へ出力される情報は「ネイティブの偶数行/偶数列」
## だけであり、奇数行は縮小時に単純に捨てられる。ところが、ある画面画素の
## 参照元ネイティブ行(2*y_screen - dy_i)は、dy_iが偶数か奇数かによって
## 「常に偶数行を参照する」か「常に奇数行を参照する」かが決まってしまう
## ——dy_iが行ごとに不規則に偶数/奇数を行き来すると、隣接する画面画素が
## 参照するネイティブ行の偶奇も不規則に入れ替わり、実在の細かい線画差分
## (縫い目・ハイライト等、偶数行と奇数行で微妙に異なる)を拾ってしまい、
## 「合板全体がちらつくノイズ」に見えていた。
##
## 【今回の修正】dx_i/dy_iを「最も近い整数」ではなく「最も近い偶数
## （=表示スケール0.50の逆数である2の倍数）」へ丸めるよう統一した
## （_round_display_aligned）。これにより2*y_screen-dy_iは常に偶数の
## ネイティブ行を参照し続け、画面画素の参照元の偶奇が入れ替わらない
## ——「奇数/偶数どちらを見るか運任せ」という散らばりノイズの発生源を
## 構造的に排除した。実GPU screenshotのbefore/after差分（前後をmagenta
## で強調表示）で、この変更の前後を直接比較し、散らばりノイズが明確に
## 減少したことを確認した。
##
## 【中間フレームの追加】呼吸A→B→C→B→Aを、各遷移1回の全振幅スワップ
## から、A→AB→B→BC→C→BC→B→AB→A（8段階、テクスチャ実体は5枚:
## A/AB/B/BC/C）へ拡張した。中間フレームは新しい絵を描き起こすのでは
## なく、既存のwarpパイプラインを流用——AB'はB自身のソース(b_src、
## 実際の手描き素材)を「Bの最終振幅の半分」で warp、BC'はC自身のソース
## (c_src)を「BとCの振幅の中間値」でwarpするだけで生成する（新規絵・
## 新規ブレンドは一切行わない、常に単一ソース画像からの離散warpのみ）。

const ORIG_DIR := "res://tools/_ui_pass_shots/originals/"
const OUT_ROOT := "res://tools/_ui_pass_shots/out/"
const DISPLAY_SCALE := 0.50
const DISPLAY_ALIGN := 2  # 1.0/DISPLAY_SCALE。warpのdx_i/dy_iをこの倍数へ丸める。

## 通常呼吸(A/B/C/AB/BC)専用の候補倍率一覧。7回目までに採用された2.0倍を
## そのまま維持する（動き幅を今回さらに縮めない、という方針を踏襲）。
const BREATH_CANDIDATE_MULTS: Array[float] = [2.0]

## D/Eは今回も一律増幅しない——前回採用済みの1.5倍のまま固定（回帰確認用）。
const DE_AMP_MULT := 1.5

func _init() -> void:
	var a := _load_raw(ORIG_DIR + "creator_guide_idle_a.png")
	var b_src := _load_raw(ORIG_DIR + "creator_guide_idle_b.png")
	var c_src := _load_raw(ORIG_DIR + "creator_guide_idle_c.png")
	var d_src := _load_raw(ORIG_DIR + "creator_guide_idle_d_posture.png")
	var e_src := _load_raw(ORIG_DIR + "creator_guide_idle_e_hand.png")

	_repair_row(b_src, 595, 594)
	_repair_row(c_src, 594, 593)
	_repair_row(c_src, 595, 596)

	for mult in BREATH_CANDIDATE_MULTS:
		_generate_candidate(mult, a, b_src, c_src, d_src, e_src)

	print("all candidates generated")
	quit()

## 最も近い「DISPLAY_ALIGNの倍数」の整数へ丸める（DISPLAY_ALIGN=2なら
## 最も近い偶数）。表示スケール0.50（=ネイティブ2px→画面1px）の
## 最近傍縮小と噛み合わせ、画面へ実際に出力される行/列が常に同じ偶奇の
## ネイティブ行/列だけを参照するようにする——これが今回の横ズレ修正の核心。
func _round_display_aligned(value: float) -> int:
	return int(round(value / float(DISPLAY_ALIGN))) * DISPLAY_ALIGN

func _generate_candidate(breath_mult: float, a: Image, b_src: Image, c_src: Image, d_src: Image, e_src: Image) -> void:
	var out_dir := "%sbreath_%sx/" % [OUT_ROOT, str(breath_mult).replace(".", "_")]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	# ================================================================
	# B'/C'/AB'/BC': 胸・肩（主動作）＋袖付け根・コート上部＋コート裾
	# （secondary）。全帯域にX方向のゲート（x_flat_left/x_flat_right/
	# x_taper、範囲外は厳密に0）を持つ——7回目で確立した「肩の実際の幅は
	# 満額、腕の付け根手前だけなめらかに遮断する」台形型窓を維持。
	#
	# 追加修正パス（2026-09-03、11回目）「頭・首の連動」対応: yの開始を
	# 300→50へ拡張し、頭部（帽子頂点native y=72付近）まで含めるように
	# した——既存のchest/torso/hem帯域はy<300でも元々ゼロ寄与のまま
	# なので、区間を広げても既存の胸・肩・裾の動きには一切影響しない
	# （head_bandだけがこの拡張範囲を実際に使う）。
	# ================================================================
	var full_region := Rect2i(150, 50, 670, 1200)  # x:150-820, y:50-1250

	var chest_band := {
		"center_y": 460.0, "half_h": 140.0,
		"x_flat_left": 220.0, "x_flat_right": 680.0, "x_taper": 60.0,
	}
	var torso_band := {
		"center_y": 760.0, "half_h": 220.0,
		"x_flat_left": 160.0, "x_flat_right": 780.0, "x_taper": 40.0,
	}
	var hem_band := {
		"center_y": 1020.0, "half_h": 130.0,
		"x_center": 470.0, "x_half": 330.0,
		"x_var": 0.30,
	}
	# 頭・首の連動（11回目セッション、新規）: 帽子頂点(y=72)〜首(y=300)
	# あたりを覆う帯域。center_y=140・half_h=280として、頭部の実際の
	# 範囲内ではfalloff値が0.39〜1.0の間に収まる（試作時に center_y=180
	# ・half_h=220だと帽子頂点でf=0.51程度しかなく、B相当の振幅では
	# 表示丸め(2の倍数のみ)の閾値をわずかに下回って「頭の上部だけ動かず
	# 下部だけ動く」まだら状態になっていたため広げて調整した）。
	# y=420でゼロへ収束し、chest_bandが本格的に効き始める領域(半値位置
	# y=320)とはわずかに重なるが、実測（後述のBC重心リボン検証）で
	# 10回目セッションで較正したB→BCの均等ジャンプ修正への悪影響が
	# ないことを確認済み。X方向のゲートは持たない（頭部全体・幅いっぱいに
	# 均等適用、横方向の動きは追加しないという方針のためdxは一切使わず
	# dyのみ）。
	var head_band := {
		"center_y": 140.0, "half_h": 280.0,
	}

	# B自身の最終振幅（breath_mult適用後）。
	var chest_amp_b := 2.5 * breath_mult
	var torso_amp_b := 1.0 * breath_mult
	var hem_amp_b := 0.8 * breath_mult
	# C自身の最終振幅。
	var chest_amp_c := 5.5 * breath_mult
	var torso_amp_c := 2.2 * breath_mult
	var hem_amp_c := 2.0 * breath_mult

	# 頭部の追従振幅（11回目セッション、新規）。胸・肩よりはるかに小さい
	# ——実画面移動量0.5〜1.0px程度という指示に対応するnative値を、
	# 表示スケール0.50倍のalign丸み(2の倍数のみ)を踏まえて選定した。
	#
	# 試作時の反省: head_bandのfalloffは頭部の実際の範囲内でも0.39〜1.0
	# まで変動するため、振幅を「ピーク(y=140付近)だけがぎりぎり閾値を
	# 超える」程度に抑えると、頭頂部や首寄りの行だけ0のまま・中央付近の
	# 数行だけ2pxシフトする「まだら」な見た目になってしまう（実測で確認
	# 済み）。これを避けるため、head_amp_bはfalloffの最小値(0.39、
	# y=300付近)でもnative2pxの閾値(dy>=1.0)を確実に超える値
	# （1.0/0.39≈2.57）を採用し、頭部全体が「ゼロか、一様なnative2px
	# シフトか」の二値になるよう設計した——ピーク付近だけ動く・端だけ
	# 動かないという不自然な部分的シフトを避けるための判断。
	#
	# 段階的な複数レベル（例: B=2px, C=4px）も検討したが、falloffの幅
	# （0.39倍〜1.0倍という2.57倍の比）に対し丸め単位が2px刻みしかない
	# ため、「頭部全体で一様にnative4pxに達する」振幅と「頭部全体で
	# 一様にnative2pxに留める」振幅を両立できない（前者に必要な振幅は
	# 後者では既にピーク付近でnative6pxを超えてしまう）。そのため
	# B/BC/Cはいずれも同じ振幅とし、「静止(A/AB)→一様な小さな追従
	# (B/BC/C)」という二値の進行に単純化した。AB(=head_amp_bの50%)は
	# ピーク直下の数行でのみnative2pxへ丸められる可能性があるが、頭頂部・
	# 首寄りではゼロのままで、AB自体が「ごく小さい追従の始まり」という
	# 中間キーフレームである以上、この程度の局所的な兆しは許容範囲と
	# 判断した。
	var head_amp_b := 2.6
	var head_amp_c := 2.6

	var b2 := b_src.duplicate()
	_apply_vbands(b2, b_src, full_region, [
		{"band": chest_band, "amp": chest_amp_b},
		{"band": torso_band, "amp": torso_amp_b},
		{"band": hem_band, "amp": hem_amp_b},
		{"band": head_band, "amp": head_amp_b},
	])

	var c2 := c_src.duplicate()
	_apply_vbands(c2, c_src, full_region, [
		{"band": chest_band, "amp": chest_amp_c},
		{"band": torso_band, "amp": torso_amp_c},
		{"band": hem_band, "amp": hem_amp_c},
		{"band": head_band, "amp": head_amp_c},
	])

	# AB': B自身の素材(b_src)を、Bの最終振幅の半分でwarpする——A→Bの
	# 1回の全振幅スワップを2段階に分割する中間キーフレーム。
	var ab2 := b_src.duplicate()
	_apply_vbands(ab2, b_src, full_region, [
		{"band": chest_band, "amp": chest_amp_b * 0.5},
		{"band": torso_band, "amp": torso_amp_b * 0.5},
		{"band": hem_band, "amp": hem_amp_b * 0.5},
		{"band": head_band, "amp": head_amp_b * 0.5},
	])

	# BC': C自身の素材(c_src)を、BとCの振幅の中間値でwarpする——B→Cの
	# 1回の全振幅スワップを2段階に分割する中間キーフレーム。
	#
	# 追加修正パス（2026-09-03、10回目）②「体の横位置ズレ」対応:
	# chest_bandだけは「B/Cの振幅の単純平均(50%)」ではなく、実測で
	# 求めた重み(約8.3%)を使う。原因は、b_src(Bの原画)とc_src(Cの原画)
	# という別々の手描き原画をまたぐ地点で、同じ振幅パラメータでも
	# 実際のピクセル変位量（襟元リボンという斜め輪郭を持つ意匠の見かけの
	# 横移動量）がb_src/c_src間で線形に対応しないことが判明したため
	# （リボンの重心Xをbrute-force sweepで実測: b_src側は振幅5.0で
	# +0.80px、c_src側は同じ振幅5.0基準でも+0.82pxの原画間ベース差が
	# 先にあり、さらにc_src側は振幅5.0→8.0の間で追加+2.05px相応の
	# 応答があるため、単純平均(8.0)を使うとB→BCの1段階だけに合計2.87px
	# もの変位が集中し、隣接するAB→B(+0.19px)やBC→C(+0.73px)と比べて
	# 明らかに不釣り合いな「ジャンプ」に見えていた）。B→BC→Cの3点が
	# リボン重心Xでほぼ等間隔になるようchest_bandの重み付けだけを実測で
	# 較正した（sweep実測: chest_amp=5.5でbow_x=495.45、目標の真の
	# 中間値495.42とほぼ完全一致——B→BC=+1.83px, BC→C=+1.77pxと
	# 均等になることを確認済み）。torso_band/hem_bandは腰バックルの
	# 重心Xで検証した結果、単純平均のままで既に不自然なジャンプが
	# 無かったため変更していない——chest_bandのこの1箇所のみの補正。
	var chest_amp_bc := chest_amp_b + 0.25 * breath_mult
	var bc2 := c_src.duplicate()
	_apply_vbands(bc2, c_src, full_region, [
		{"band": chest_band, "amp": chest_amp_bc},
		{"band": torso_band, "amp": (torso_amp_b + torso_amp_c) * 0.5},
		{"band": hem_band, "amp": (hem_amp_b + hem_amp_c) * 0.5},
		{"band": head_band, "amp": (head_amp_b + head_amp_c) * 0.5},
	])

	# ================================================================
	# D': 今回は回帰確認のみ——前回採用済みの1.5倍設定を無改修のまま
	# 再生成（丸め方式のみ_round_display_alignedへ統一）。
	#
	# 追加修正パス（2026-09-03、11回目）「頭・首の連動」対応: d_regionの
	# yの開始を300→50へ拡張し、新設のhead(D用)帯域が頭部（帽子頂点
	# native y=72付近）まで届くようにした——既存のshoulder/pelvis/hem/
	# legsは元々y<300でゼロ寄与のため、区間拡張自体はD本来の重心移動量に
	# 一切影響しない。
	# ================================================================
	var d_region := Rect2i(150, 50, 670, 1300)
	var d_center_x := 470.0

	var shoulder_band := {"center_y": 460.0, "half_h": 140.0}
	var pelvis_band := {"center_y": 750.0, "half_h": 220.0}
	var d_hem_band := {"center_y": 1020.0, "half_h": 170.0}
	# 頭・首の連動（D用、新規）: 骨盤→胴体→肩と繋がってきた重心移動の
	# 続きとして、頭にもごく小さい水平方向の追従を持たせる——item16の
	# 「首を大きく傾げる必要はない」に対応し、tilt(Y方向のせん断)は
	# 使わずdxのみ。shoulder(amp_x=3.0*1.5=4.5)と同じ正符号（＝同じ
	# 傾き方向、骨盤→肩の連鎖をそのまま延長する向き）を採用。
	# 帯域形状は呼吸用head_bandと全く同じ(center_y=140, half_h=280)に
	# 揃え、振幅も同じ2.6を採用——頭部の実際の範囲内(y=72〜300)で
	# falloffが最小(0.39付近)になる地点でもnative2pxの閾値を確実に
	# 超えるようにし、呼吸時と同様「頭部全体で一様なnative2px
	# （画面1px）シフト」にした（ピーク付近だけ動く・端だけ動かない
	# という部分的な不自然さを避けるため、呼吸用head_bandの較正結果を
	# そのまま転用した）。
	var head_band_d := {"center_y": 140.0, "half_h": 280.0}
	var head_amp_d := 2.6

	var leg_band_y := {"center_y": 1030.0, "half_h": 110.0}
	var weight_leg_x := {"center_x": 460.0, "half_x": 85.0}
	var relax_leg_x := {"center_x": 310.0, "half_x": 85.0}

	var weight_leg_amp := 0.6 * DE_AMP_MULT + 0.1 * (DE_AMP_MULT - 1.0)
	var relax_leg_amp := 2.6 * DE_AMP_MULT + 0.6 * (DE_AMP_MULT - 1.0)

	var d2 := d_src.duplicate()
	_apply_full_body_warp(d2, d_src, d_region, {
		"shoulder": {"band": shoulder_band, "amp_x": 3.0 * DE_AMP_MULT, "tilt": 1.8 * DE_AMP_MULT, "center_x": d_center_x, "half_x": 220.0},
		"pelvis": {"band": pelvis_band, "amp_x": 3.5 * DE_AMP_MULT, "center_x": d_center_x},
		"hem": {"band": d_hem_band, "amp_x": 2.0 * DE_AMP_MULT, "tilt": 3.0 * DE_AMP_MULT, "center_x": d_center_x, "half_x": 220.0},
		"head": {"band": head_band_d, "amp_x": head_amp_d},
		"legs": [
			{"band_y": leg_band_y, "band_x": weight_leg_x, "amp_x": weight_leg_amp},
			{"band_y": leg_band_y, "band_x": relax_leg_x, "amp_x": relax_leg_amp},
		],
	})

	# ================================================================
	# E': 今回は回帰確認のみ——前回採用済みの1.5倍設定を無改修のまま
	# 再生成（丸め方式のみ_round_display_alignedへ統一）。
	# ================================================================
	var wrist_anchor := Vector2(705.0, 500.0)
	var hand_radius := 170.0
	var hand_disp := Vector2(3.0, -3.5) * DE_AMP_MULT

	var cuff_band_y := {"center_y": 480.0, "half_h": 90.0}
	var cuff_band_x := {"center_x": 660.0, "half_x": 100.0}
	var cuff_disp := Vector2(1.2, -1.2) * DE_AMP_MULT

	var hand_region := Rect2i(600, 320, 380, 240)
	var e2 := e_src.duplicate()
	_apply_hand_and_cuff(e2, e_src, hand_region, wrist_anchor, hand_radius, hand_disp, cuff_band_y, cuff_band_x, cuff_disp)

	ab2.save_png(ProjectSettings.globalize_path(out_dir + "ab_prime.png"))
	b2.save_png(ProjectSettings.globalize_path(out_dir + "b_prime.png"))
	bc2.save_png(ProjectSettings.globalize_path(out_dir + "bc_prime.png"))
	c2.save_png(ProjectSettings.globalize_path(out_dir + "c_prime.png"))
	d2.save_png(ProjectSettings.globalize_path(out_dir + "d_prime.png"))
	e2.save_png(ProjectSettings.globalize_path(out_dir + "e_prime.png"))

	print("breath candidate %sx generated -> %s" % [breath_mult, out_dir])

	_build_strip([a, ab2, b2, bc2, c2, d2, e2], out_dir + "compare_display_scale.png", DISPLAY_SCALE)
	_build_zoom_strip([a, ab2, b2, bc2, c2, d2, e2], Rect2i(150, 550, 670, 810), out_dir + "zoom_lowerbody.png")
	_build_zoom_strip([a, ab2, b2, bc2, c2, d2, e2], Rect2i(280, 330, 380, 260), out_dir + "zoom_shoulder.png")
	_build_zoom_strip([a, ab2, b2, bc2, c2, d2, e2], Rect2i(600, 320, 380, 240), out_dir + "zoom_hand.png")
	_build_zoom_strip([a, ab2, b2, bc2, c2, d2, e2], Rect2i(600, 380, 260, 200), out_dir + "zoom_sleeve_base.png")

func _load_raw(path: String) -> Image:
	var img := Image.new()
	img.load(ProjectSettings.globalize_path(path))
	return img

func _repair_row(img: Image, target_y: int, source_y: int) -> void:
	for x in range(img.get_width()):
		img.set_pixel(x, target_y, img.get_pixel(x, source_y))

func _falloff_1d(v: float, center: float, half_width: float) -> float:
	var dist := absf(v - center)
	if dist >= half_width:
		return 0.0
	return 0.5 * (1.0 + cos(PI * dist / half_width))

## bandの合成重みを返す: X方向ゲート×左右非対称の重み(x_var、無ければ1.0)。
func _x_weight(band: Dictionary, x: float) -> float:
	var gate := 1.0
	var center_for_var := 0.0
	var half_for_var := 1.0
	if band.has("x_flat_left"):
		var flat_left: float = band["x_flat_left"]
		var flat_right: float = band["x_flat_right"]
		var taper: float = band["x_taper"]
		if x < flat_left:
			gate = _falloff_1d(x, flat_left, taper)
		elif x > flat_right:
			gate = _falloff_1d(x, flat_right, taper)
		else:
			gate = 1.0
		center_for_var = (flat_left + flat_right) * 0.5
		half_for_var = (flat_right - flat_left) * 0.5 + taper
	elif band.has("x_center"):
		gate = _falloff_1d(x, float(band["x_center"]), float(band["x_half"]))
		center_for_var = float(band["x_center"])
		half_for_var = float(band["x_half"])
	if gate <= 0.0:
		return 0.0
	if not band.has("x_var"):
		return gate
	var lateral: float = clampf((x - center_for_var) / half_for_var, -1.0, 1.0)
	return gate * (1.0 + float(band["x_var"]) * lateral)

func _apply_vbands(out: Image, source_frame: Image, region: Rect2i, bands: Array) -> void:
	for y in range(region.position.y, region.position.y + region.size.y):
		var base_contribs: Array = []
		for entry in bands:
			var band: Dictionary = entry["band"]
			var f := _falloff_1d(float(y), band["center_y"], band["half_h"])
			base_contribs.append(float(entry["amp"]) * f)
		for x in range(region.position.x, region.position.x + region.size.x):
			var total_dy := 0.0
			for i in range(bands.size()):
				var band: Dictionary = bands[i]["band"]
				total_dy += base_contribs[i] * _x_weight(band, float(x))
			var dy_i := _round_display_aligned(total_dy)
			if dy_i == 0:
				continue
			var src_y := y + dy_i
			if src_y < 0 or src_y >= source_frame.get_height():
				continue
			out.set_pixel(x, y, source_frame.get_pixel(x, src_y))

func _apply_full_body_warp(out: Image, source_frame: Image, region: Rect2i, spec: Dictionary) -> void:
	var shoulder: Dictionary = spec["shoulder"]
	var pelvis: Dictionary = spec["pelvis"]
	var hem: Dictionary = spec["hem"]
	var legs: Array = spec["legs"]
	# 追加修正パス（2026-09-03、11回目）「頭・首の連動」対応: "head"は
	# 任意キー——旧来の呼び出し（headキーを持たないspec）とも互換を保つ
	# ため、無ければ寄与ゼロのまま無改修で動く。
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

func _apply_hand_and_cuff(out: Image, source_frame: Image, rect: Rect2i, anchor: Vector2, radius: float, hand_disp: Vector2, cuff_band_y: Dictionary, cuff_band_x: Dictionary, cuff_disp: Vector2) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		var fy := _falloff_1d(float(y), cuff_band_y["center_y"], cuff_band_y["half_h"])
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var dist := Vector2(x, y).distance_to(anchor)
			var t := clampf(dist / radius, 0.0, 1.0)
			var w := t * t * (3.0 - 2.0 * t)

			var dx := hand_disp.x * w
			var dy := hand_disp.y * w

			if fy > 0.0:
				var fx := _falloff_1d(float(x), cuff_band_x["center_x"], cuff_band_x["half_x"])
				if fx > 0.0:
					dx += cuff_disp.x * fy * fx
					dy += cuff_disp.y * fy * fx

			var dx_i := _round_display_aligned(dx)
			var dy_i := _round_display_aligned(dy)
			if dx_i == 0 and dy_i == 0:
				continue
			var src_x := x - dx_i
			var src_y := y - dy_i
			if src_x < 0 or src_x >= source_frame.get_width() or src_y < 0 or src_y >= source_frame.get_height():
				continue
			out.set_pixel(x, y, source_frame.get_pixel(src_x, src_y))

func _build_strip(images: Array, out_path: String, scale: float) -> void:
	var first: Image = images[0]
	var w: int = int(round(first.get_width() * scale))
	var h: int = int(round(first.get_height() * scale))
	var gap := 8
	var strip := Image.create(w * images.size() + gap * (images.size() - 1), h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.08, 0.08, 0.1, 1.0))
	for i in range(images.size()):
		var img: Image = images[i]
		var scaled: Image = img.duplicate()
		if scale != 1.0:
			scaled.resize(w, h, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(scaled, Rect2i(0, 0, w, h), Vector2i(i * (w + gap), 0))
	strip.save_png(ProjectSettings.globalize_path(out_path))

func _build_zoom_strip(images: Array, crop_rect: Rect2i, out_path: String) -> void:
	var zoom := 3.0
	var crop_w := int(round(crop_rect.size.x * DISPLAY_SCALE * zoom))
	var crop_h := int(round(crop_rect.size.y * DISPLAY_SCALE * zoom))
	var gap := 8
	var strip := Image.create(crop_w * images.size() + gap * (images.size() - 1), crop_h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.08, 0.08, 0.1, 1.0))
	for i in range(images.size()):
		var img: Image = images[i]
		var cropped: Image = img.get_region(crop_rect)
		cropped.resize(crop_w, crop_h, Image.INTERPOLATE_NEAREST)
		strip.blit_rect(cropped, Rect2i(0, 0, crop_w, crop_h), Vector2i(i * (crop_w + gap), 0))
	strip.save_png(ProjectSettings.globalize_path(out_path))
