shader_type canvas_item;

// エオスバースト竜召喚: v8（出現方向の修正 — 「頭がソティリスの背後から
// 移動し、身体がその軌跡を追う」出現アニメーション）。
//
// v7はpath_mask_texベースのreveal_threshold(頭→首→胴→尾の順に閾値discard
// で表示範囲を広げる)を実装し、解剖学的な出現「順序」自体は正しくなった
// が、竜画像自体は常に完成時と同じ画面位置に静止したままだった——ユーザー
// 報告: 「頭が空中の最終位置にそのまま出現する」。これはreveal_threshold
// が「どのピクセルを見せるか」しか制御しておらず、「どこに見せるか」は
// 常に完成位置のままだったため。
//
// 今回追加したのが4つの新しいuniform(head/neck/body/tail_offset_px)—
// GDScript側が各部位ごとに「ソティリスの背後(DragonEmergenceOrigin)から
// 完成位置までの軌跡」上の現在地をVector2オフセットとして毎フレーム計算
// し、vertex()でpath_mask_texの値に応じて4つのオフセットをブレンドして
// 適用する。頭のmask値が高い頂点は主にhead_offset_pxの影響を受け、尾の
// mask値が低い頂点は主にtail_offset_pxの影響を受ける——結果、いま見えて
// いる部位がまさにその部位自身の軌跡に沿って引き出されるように動く。
// reveal_threshold(どのピクセルが見えるか)とこのオフセットブレンド(見え
// ている部位がどこにあるか)は完全に独立した2つの仕組みで、両方を同時に
// 満たすことで「頭から出現かつソティリスの背後から動く」を実現する。
//
// シェーダーが担うのは6つ:
// 1. reveal_threshold — path_mask_texに基づく出現時だけの閾値discard。
//    exit中は常に0.0(全身表示、マスクなし)。
// 2. head/neck/body/tail_offset_px — 4部位ごとの出現軌跡オフセット。
//    path_mask_texの値でスムーズにブレンドし、頂点位置へ加算する。
// 3. silhouette_mix — 出現直後(白金シルエット→crossfadeで本来の色)と
//    消滅直前(本来の色→白いシルエット)の、色だけを変える単純なmix。
//    アルファは常にテクスチャ自身の値のまま(マスクなし)。
// 4. recoil_offset_px — 発射フレームの反動。頂点シェーダーで全頂点に
//    均一に加算するだけ(身体部位ごとの重み付けは行わない、"竜全体を"
//    後方へ押す仕様のため)。出現オフセットとは別の窓でのみ発生するため
//    干渉しない。
// 5. 目/口/たてがみ外周の小さな発光（release_flash/life_pulse）— 従来
//    通りeye_uv/mouth_uv/alphaの近傍検出ベース。

uniform float brightness : hint_range(0.5, 2.0) = 1.0;
uniform float alpha_mult : hint_range(0.0, 1.0) = 1.0;
// 召喚完了後の生命感（外周を流れる発光+たてがみの弱いパルス）。
uniform float life_pulse : hint_range(0.0, 1.0) = 0.0;
// 0〜1: 発射の瞬間だけ、竜の目・口・角・たてがみを一瞬最大輝度にする
// (GDScript側で発射フラッシュ/段階出現フラッシュをmaxf()でまとめて渡す)。
uniform float release_flash : hint_range(0.0, 1.0) = 0.0;
// 0〜1: 出現直後/消滅直前の「白金シルエット」への色ブレンド量。
uniform float silhouette_mix : hint_range(0.0, 1.0) = 0.0;
// 焼き込み済みの進行率マスク(0=尾...1=頭+たてがみ+鼻先)。
uniform sampler2D path_mask_tex : hint_default_black, filter_linear;
// 0〜1: mask値がこの値以上のピクセルだけを表示する閾値。出現中だけ
// 1.0(何も見えない)→0.0(全身表示)へ減少し、それ以外(exit含む)は常に
// 0.0(全身表示、マスクなし)。
uniform float reveal_threshold : hint_range(0.0, 1.0) = 0.0;
// UV空間での目・口の位置（EOS_BURST_DRAGON_EYE_FRAC/_MOUTH_FRACと同じ
// 値）。(-1,-1)なら無効。
uniform vec2 eye_uv = vec2(-1.0, -1.0);
uniform vec2 mouth_uv = vec2(-1.0, -1.0);
// 発射フレームの反動オフセット（メッシュのローカルpx単位、全頂点へ
// 均一に加算——身体部位ごとの重み付けは行わない）。
uniform vec2 recoil_offset_px = vec2(0.0, 0.0);
// 出現軌跡オフセット(メッシュのローカルpx単位) — GDScript側が毎フレーム
// 計算する、DragonEmergenceOrigin(ソティリス背後)から完成位置までの
// 現在地(完成すると(0,0)に収束)。4部位それぞれ独立した軌跡・スケジュール
// を持つ——mask値で滑らかにブレンドして適用する(下記vertex()参照)。
uniform vec2 head_offset_px = vec2(0.0, 0.0);
uniform vec2 neck_offset_px = vec2(0.0, 0.0);
uniform vec2 body_offset_px = vec2(0.0, 0.0);
uniform vec2 tail_offset_px = vec2(0.0, 0.0);

void vertex() {
	// path_mask_texの値(0=尾...1=頭)で4部位のオフセットを滑らかにブレンド
	// する——GDScript側のreveal_threshold用バンド境界(0.2/0.45/0.7/0.9、
	// EOS_BURST_PATH_CONTROL_VALUES参照)と同じ位置を使い、smoothstepで
	// 境目を滑らかにする(矩形クロップではなくマスク値ベースの連続的な
	// ブレンドなので、部位の境界に不自然な段差が出ない)。
	float mask_value = texture(path_mask_tex, UV).r;
	vec2 emergence_offset = tail_offset_px;
	emergence_offset = mix(emergence_offset, body_offset_px, smoothstep(0.15, 0.25, mask_value));
	emergence_offset = mix(emergence_offset, neck_offset_px, smoothstep(0.40, 0.50, mask_value));
	emergence_offset = mix(emergence_offset, head_offset_px, smoothstep(0.65, 0.75, mask_value));
	VERTEX += recoil_offset_px + emergence_offset;
}

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (tex_color.a <= 0.001) {
		discard;
	}
	float mask_value = texture(path_mask_tex, UV).r;
	bool revealed = mask_value >= reveal_threshold;
	if (!revealed) {
		discard;
	}

	vec3 rgb = tex_color.rgb * brightness;

	// 外周リム: 近傍のアルファが低いほど輪郭に近いとみなす簡易検出
	// （角の先端・たてがみの外周はどちらもシルエットの輪郭上にある
	// ため、この検出で自然に拾える）。
	float texel = 1.0 / 700.0;
	float a_u = texture(TEXTURE, UV + vec2(0.0, -texel * 3.0)).a;
	float a_d = texture(TEXTURE, UV + vec2(0.0, texel * 3.0)).a;
	float a_l = texture(TEXTURE, UV + vec2(-texel * 3.0, 0.0)).a;
	float a_r = texture(TEXTURE, UV + vec2(texel * 3.0, 0.0)).a;
	float neighbor_min = min(min(a_u, a_d), min(a_l, a_r));
	float rim = clamp(tex_color.a - neighbor_min, 0.0, 1.0);
	// 頭部領域だけに制限する近似——path_mask_texのbase値が高いほど頭側。
	float head_region = smoothstep(0.80, 0.95, mask_value);
	float horn_mane_rim = rim * head_region;

	vec3 rim_glow = mix(vec3(1.0, 0.86, 0.45), vec3(0.55, 0.94, 1.0), 0.5);
	rim_glow = mix(rim_glow, vec3(1.0), 0.55);

	float eye_glow = eye_uv.x >= 0.0 ? (1.0 - smoothstep(0.0, 0.045, distance(UV, eye_uv))) : 0.0;
	float mouth_glow = mouth_uv.x >= 0.0 ? (1.0 - smoothstep(0.0, 0.045, distance(UV, mouth_uv))) : 0.0;
	float flash_mask = clamp(eye_glow + mouth_glow + horn_mane_rim, 0.0, 1.0);
	rgb = mix(rgb, vec3(1.9, 1.8, 1.6), release_flash * flash_mask * 0.65);

	// 召喚後の生命感: 外周を流れる発光 + たてがみ(頭部限定rim)の弱い
	// パルス。
	rgb += rim_glow * rim * life_pulse * 0.5;
	rgb += rim_glow * horn_mane_rim * life_pulse * 0.35;

	// 出現中(reveal_threshold>0.001)だけ、表示境界のすぐ内側に短い発光
	// の帯を添える——「輪郭に沿ったマスクで分け...短い発光で順番に表示」。
	// exit中はreveal_thresholdが常に0固定なのでこの項は自然にゼロになる。
	if (reveal_threshold > 0.001) {
		float reveal_edge = 1.0 - smoothstep(0.0, 0.04, mask_value - reveal_threshold);
		vec3 edge_col = mix(vec3(1.0, 0.9, 0.6), vec3(0.6, 0.95, 1.0), 0.5);
		rgb += edge_col * reveal_edge * 1.3;
	}

	// 全身シルエット化（出現直後の一瞬の白金フラッシュ／消滅直前の白い
	// シルエット化）— 竜画像の一部分だけを対象にしたマスクではなく、
	// 全ピクセルへ均一に適用する単純な色ミックス。アルファは常にテク
	// スチャ自身の値のまま(マスクなし)。
	vec3 silhouette_col = vec3(1.9, 1.75, 1.2);
	rgb = mix(rgb, silhouette_col, silhouette_mix);

	COLOR = vec4(rgb, tex_color.a * alpha_mult);
}
