extends Node
## 朽ちた機械武者の「墨」の層(承認済み 2026-09-27)。戦闘ステージ(rbm_battle_stage.gd)が武者のときだけ1つ作る。
## 本番の演出(音・技名・画面揺れ・ダメージ通知)はそのまま動かし、その外側へ墨を重ねる。
## 表示専用(戦闘の状態・乱数・行動順には触れない)。覚醒前は何も描かない。攻撃の効果はすべて墨(属性で変わるのは技名の文字だけ)。
##
## 常時(覚醒後待機): 足元の墨溜まり(艶・波紋・呼吸) / 地を這う墨の指 / 立ち昇る墨の筋 / 外套の裾から垂れる雫 /
##   墨溜まりから逆流して昇る雫 / 時々の筆の払い / 刀身から立ち昇る墨
## 覚醒: ロックが外れた関節から墨が滲み、足元に溜まり始め、解放で墨が丸い塊になって大きくはじけ飛び(すぐ消える)、
##   墨溜まりが一気に広がり、抜刀と同時に刀から墨が立ち昇る
## 単体「境」: 刀を掲げる → 溜め(刀から立ち昇る墨が大きく激しくなる) → 振り下ろし → 振り切ってから墨の三日月が飛ぶ
##   → 斬線に着弾 → 空間が斬線でずれて割れる(白い閃光の線・墨の飛沫) → 墨の爆発 → 閉じて墨の傷跡になり、垂れて消える
## 全体「界」: 血振り → 納刀(鍔鳴り) → 居合の構え・溜め(常時のオーラをすべて刀へ吸い込んで無くし、さらに溜める)
##   → 抜く瞬間に画面全体が白くなり、見えない斬撃が8回走る → 白が引くと納め直していて鍔鳴り → 静かな間
##   → 8回の斬撃が同じ速さで味方の体に現れる → 墨の大爆発(画面を貫く墨の一文字・集中線・墨の花・円相) → 抜刀待機へ
## 自己強化: 墨が螺旋を描いて機体を昇り、刀の墨が膨らむ → 再点灯で一気に吸い込まれ、刀の墨が赤く縁取られる
## 自己回復: 墨の糸が墨溜まりから関節へ流れ込む(緑の光) → 再点灯で機体に満ち、墨溜まりに光の波紋
##
## 墨は半分の解像度の描画先(2px単位)へ描き、左上の縁にだけ濡れた照りを付ける(黒煙にしない)。
## 空間の表現(単体の斬線で空間がずれて割れる)は、本体・VFXより下を読み取ってずらす全面パス。
## 意図した全画面の演出の瞬間(単体の墨の爆発・全体の白い画面・全体の墨の大爆発)だけは、全画面の戦闘画面のUI欄(ステージより前、
## z 20)の上にも墨の層の絵を重ねて見せる(UI欄の矩形の中だけ。ステージの見え方は変えない。終わればすぐUI欄が前に戻る)。
## 承認時の確認用の動画(UIなし)と同じく、閃光・円相・飛沫・白い画面が画面いっぱいに見えるように。
## ほかのキャラの大技の効果がUIより前に出るのと同じ扱い(UIを常に後ろへ回すことはしない)。
## 攻撃・支援の時刻は各演出(rbm_musha_frame_presentation.gd / rbm_musha_awakened_frame_presentation.gd)の時刻 = 下の定数。
const Rig = preload("res://src/bossmaker/visuals/rbm_musha_frames.gd")
const AwMotion = preload("res://src/bossmaker/visuals/rbm_musha_awakened_motion.gd")
const INK := Color(0.018, 0.017, 0.026)
const INK2 := Color(0.085, 0.085, 0.105)
const STEEL := Color(0.80, 0.82, 0.87)
const GLOSS := Color(0.33, 0.35, 0.44)
## 描く範囲(ステージの大きさ。_sync_layout() が合わせる)
var VIEW := Vector2(1280, 720)
const BUFF_RED := Color(0.94, 0.28, 0.28)
const HEAL_GREEN := Color(0.44, 0.86, 0.53)
## 覚醒後単体「境」(演出の時刻)。掲げてから振り下ろすまでの溜めを入れるため、元の音と時刻を SD 秒うしろへずらす。
const SD := 2.4
const S_RISE := 0.45        # 足元から墨が昇り始める
const S_COAT := 1.2         # 刀の墨が大きく激しくなり始める
const S_FULL := 3.0         # 溜めきる
const S_SWING := 0.92 + SD  # 振り下ろし(本番 0.92 + SD)
const S_RELEASE := S_SWING + 0.10   # 振り切ってから斬撃が離れる
const S_ARRIVE := 1.30 + SD # 斬線へ着弾(本番 1.30 + SD)
const S_CUT := 2.15 + SD    # 空間が斬れる(本番の着弾 2.15 + SD)
const S_BACK := 3.55 + SD   # 抜刀待機へ戻る(本番 3.55 + SD)
const S_END := S_BACK + 0.95
## 空間が割れる大きさ(隙間の半分の幅・線に沿った食い違い)
const SLICE_GAP := 12.0
const SLICE_SLIDE := 90.0
## 覚醒後全体「界」(演出の時刻): 血振り(風切り音) → 納刀の鍔鳴り → 居合の構え・溜め → 見えない速さの抜刀(白い画面)
## → 納め直しの鍔鳴り → 遅れて入る斬撃 → 墨の大爆発(着弾)。元の時刻(技名・画面揺れ・ダメージ通知)は2.45秒で止めて着弾に合わせる。
const A_CHIBURI := 1.38
const A_CLICK := 2.15
const A_STANCE := 2.30
const A_DEEP := 3.4
const A_GATHER_END := 3.95   # 常時の墨のオーラを刀へ吸い込み終わる。ここから抜く瞬間まで約0.8秒、オーラの無いまま構えて溜める
const A_PULL := 4.81     # 右手が柄を引き、刀身が鯉口から出始める(a1c)
## 見えない速さの抜刀: 抜く瞬間に画面全体が真っ白になり、何かが高速で走る → 白が引くと刀はもう鞘へ戻りかけている
const A_FLASH := 4.86
const A_FLASH_END := 5.76
const A_DRAW := A_FLASH
const A_CLICK2 := 6.85   # 納め直しの鍔鳴り(kc)。白が引いてから約1.1秒かけてゆっくり納める
## 鍔鳴りの後、約1.2秒の間(静かに構えたまま) → 白い画面の中で斬った8回の斬撃が、同じ速さで味方の体に現れる(A_SWEEP〜)
## → 墨の大爆発(本番の着弾 4.85)
const A_SWEEP := 8.05
const A_IMPACT := 8.92
const A_BACK := 10.50     # 抜刀待機へ戻る(本番の抜刀の原画 a1 → a2 → a3)
const A_END := 11.07
## 自己強化/回復の再点灯
const RELIGHT := 2.30

const RIM_SHADER := """shader_type canvas_item;
// 墨の液面: 左上から光を受ける縁だけ、濡れた照り返しの色にする(暗い背景でも墨の形が液体として読める)。
void fragment(){
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	float up = min(texture(TEXTURE, UV + vec2(-px.x, -px.y)).a, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);
	if (c.a > 0.5 && up < 0.5) { c.rgb = mix(c.rgb, vec3(0.32, 0.34, 0.42), 0.85); }
	COLOR = c;
}"""

const POOL_SHADER := """shader_type canvas_item;
uniform vec2 origin;
uniform vec2 c;
uniform vec2 rad;
uniform float time;
uniform vec4 ripples[6];
uniform vec3 ripple_col = vec3(0.34, 0.36, 0.43);
varying vec2 wp;
void vertex(){ wp = VERTEX + origin; }
float h21(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p){ return 0.55 * vn(p) + 0.30 * vn(p * 2.1 + 7.3) + 0.15 * vn(p * 4.3 + 3.1); }
void fragment(){
	vec2 p = floor(wp) + 0.5;
	vec2 v = (p - c) / max(rad, vec2(0.01));
	float q = length(v);
	float nz = fbm(p * vec2(0.045, 0.16) + vec2(time * 0.05, 0.0));
	float edge = q + (nz - 0.5) * 0.38;
	if (edge > 1.0) {
		float halo = 1.0 - smoothstep(1.0, 1.22, edge);
		COLOR = vec4(0.0, 0.0, 0.0, 0.34 * halo * step(1.0, rad.x));
	} else {
		vec3 col = vec3(0.018, 0.017, 0.026);
		float rim = step(0.84, edge) * step(v.y, -0.10);
		col = mix(col, vec3(0.30, 0.32, 0.39), rim * 0.8);
		float sx = sin(p.x * 0.075 + time * 0.35) * 0.5 + 0.5;
		float band = exp(-pow((v.y + 0.38 + 0.05 * sin(time * 0.4)) * 5.0, 2.0));
		float spec = step(0.80, sx * band * (1.0 - smoothstep(0.5, 0.92, abs(v.x))));
		col = mix(col, vec3(0.24, 0.25, 0.31), spec * 0.85);
		for (int i = 0; i < 6; i++) {
			vec4 r = ripples[i];
			if (r.w <= 0.0) { continue; }
			vec2 d = (p - r.xy) * vec2(1.0, 4.4);
			float rr = 2.0 + r.z * 30.0;
			float ring = 1.0 - smoothstep(0.0, 1.2, abs(length(d) - rr));
			col = mix(col, ripple_col, ring * min(r.w, 1.0) * (1.0 - smoothstep(0.1, 1.15, r.z)));
		}
		COLOR = vec4(col, 1.0);
	}
}"""

## UI欄の上に重ねる墨の層の表示: RIM_SHADER と同じ縁の照りを付け、UI欄の矩形(rects、ステージの座標)の中だけを amount の濃さで出す。
const HUD_OVER_SHADER := """shader_type canvas_item;
uniform vec2 view = vec2(1280.0, 720.0);
uniform vec4 rects[12];
uniform int count = 0;
uniform float amount = 0.0;
void fragment(){
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	float up = min(texture(TEXTURE, UV + vec2(-px.x, -px.y)).a, texture(TEXTURE, UV + vec2(0.0, -px.y)).a);
	if (c.a > 0.5 && up < 0.5) { c.rgb = mix(c.rgb, vec3(0.32, 0.34, 0.42), 0.85); }
	vec2 p = UV * view;
	float inside = 0.0;
	for (int i = 0; i < 12; i++) {
		if (i >= count) { break; }
		vec4 r = rects[i];
		if (p.x >= r.x && p.y >= r.y && p.x < r.x + r.z && p.y < r.y + r.w) { inside = 1.0; }
	}
	COLOR = vec4(c.rgb, c.a * inside * amount);
}"""
## UI欄の上に重ねる表示の z(全画面の戦闘画面のUI欄 z 20 より前、確認ダイアログ z 60 より後ろ)
const HUD_OVER_Z := 30
const HUD_OVER_MAX_RECTS := 12

## 空間(単体の斬線): 本体・VFXより下の画面を読み、斬線の両側を線に沿って逆向きへずらし、線から押し広げて墨の隙間を開く。
## s_mis は斬線が残っている間の小さな食い違い(空間に線が入った気配)。w_* は覚醒の解放の波。
const SPACE_SHADER := """shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 view = vec2(1280.0, 720.0);
uniform vec2 s_c = vec2(0.0);
uniform vec2 s_u = vec2(0.0, 1.0);
uniform float s_half = 280.0;
uniform float s_slide = 0.0;
uniform float s_gap = 0.0;
uniform float s_mis = 0.0;
uniform vec2 w_center = vec2(0.0);
uniform float w_radius = -1.0;
uniform float w_amp = 0.0;
uniform float w_width = 40.0;
void fragment(){
	vec2 p = UV * view;
	vec2 off = vec2(0.0);
	bool in_gap = false;
	if (abs(s_slide) + s_gap + abs(s_mis) > 0.01) {
		vec2 n = vec2(-s_u.y, s_u.x);
		vec2 d = p - s_c;
		float a = dot(d, s_u);
		float s = dot(d, n);
		float along = 1.0 - smoothstep(s_half * 0.8, s_half * 1.12, abs(a));
		float sg = s >= 0.0 ? 1.0 : -1.0;
		float gap = s_gap * along;
		float fall = 1.0 - smoothstep(gap + 60.0, gap + 460.0, abs(s));
		off += s_u * sg * (s_slide + s_mis) * 0.5 * along * fall;
		off += n * sg * gap * fall;
		if (abs(s) < gap) { in_gap = true; }
	}
	if (w_amp > 0.01) {
		vec2 d = p - w_center;
		float r = length(d);
		float band = (r - w_radius) / w_width;
		float k = exp(-band * band * 3.0) * band;
		off += (r > 0.001 ? d / r : vec2(0.0)) * k * w_amp;
	}
	vec3 col = texture(screen_tex, (p - off) / view).rgb;
	if (in_gap) { col = vec3(0.018, 0.017, 0.026); }
	COLOR = vec4(col, 1.0);
}"""

var stage: Control
var home := Vector2.ZERO
var aura_t := 20.0   # 最初から定常状態(筋や雫が出そろった状態)で始める
## 攻撃・支援(本番の演出の経過)。負なら待機。kind: "single" | "all" | "buff" | "heal"
var kind := ""
var at := -1.0
var attack_start := -1000.0   # 始まった時の aura_t
var shake := Vector2.ZERO
var hit_at := Vector2.ZERO
var center := Vector2.ZERO
var feet: Array = []
var tint := Color(0.89, 0.23, 0.18)
## 覚醒演出の経過(負なら覚醒演出中ではない)
var awk_t := -1.0
## 墨の出現(0: 覚醒前 → 1: 覚醒後)
var em_pool := 0.0
var em_aura := 0.0
var em_sheath := 0.0
## 本体(変形リグの状態)。刀の位置はここから求める。
var body: Dictionary = {}
var back: Dictionary
var mid: Dictionary
var top: Dictionary
var accent: Node2D
var pool: ColorRect
var pool_mat: ShaderMaterial
var space_rect: ColorRect
var space_mat: ShaderMaterial
var _bbc: BackBufferCopy
## UI欄の上に重ねる墨の層の表示(背面・中間・前面の絵をそのまま使う)と、そのときのUI欄の矩形
var hud_over: Array = []
var hud_over_mat: ShaderMaterial
var _hud_rects: Array = []
var _hud_checked := false
## 直近の刀と刀の墨(残像・振り出し・垂れた雫の出どころ)
var _hist: Array = []
var _cracks: Array = []
## 味方全員の足元(単体の斬線を、対象以外の味方に掛けないため)
var allies: Array = []

func _h(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)

# ---------------------------------------------------------------------------
# まとめ描き: 円・多角形を1つずつエンジンへ渡すと、着弾の瞬間は1フレームに数百〜千個になり、実時間で重くなる
# (1個ごとに描画の命令と頂点の入れ物が作られるため)。同じ描き先・同じ色で続く円・多角形を1つの三角形の並びにまとめて渡す。
# 円はエンジンの draw_circle と同じ64角形、多角形はエンジンの draw_colored_polygon と同じ三角形分割
# (Geometry2D.triangulate_polygon)なので、描かれる画素は1つずつ描いた場合と同じ。色が変わる時・線や矩形の前・各層を
# 描き終えた時にまとめた分を出すので、重なり順も変わらない。
# (頂点ごとに色を持たせて色が変わってもまとめ続ける方法は、頂点の色のデータが増えてかえって遅かった)
# ---------------------------------------------------------------------------
const CIRCLE_SEGMENTS := 64
static var _unit_circle := PackedVector2Array()
var _batch_ci: CanvasItem = null
var _batch_col := Color()
var _batch := PackedVector2Array()

## 半径1の64角形を中心からの扇形の三角形に分けた頂点の並び(エンジンの draw_circle と同じ頂点)。
static func _circle_tris() -> PackedVector2Array:
	if _unit_circle.is_empty():
		var ring := PackedVector2Array()
		for i in range(CIRCLE_SEGMENTS + 1):
			var a := i * TAU / CIRCLE_SEGMENTS
			ring.append(Vector2(cos(a), sin(a)))
		for i in range(CIRCLE_SEGMENTS):
			_unit_circle.append(Vector2.ZERO)
			_unit_circle.append(ring[i])
			_unit_circle.append(ring[i + 1])
	return _unit_circle

func _to_batch(ci: CanvasItem, col: Color) -> void:
	if ci != _batch_ci or col != _batch_col:
		_flush()
		_batch_ci = ci
		_batch_col = col

## まとめた円・多角形を描き先へ出す。
func _flush() -> void:
	if not _batch.is_empty() and is_instance_valid(_batch_ci):
		RenderingServer.canvas_item_add_triangle_array(_batch_ci.get_canvas_item(), PackedInt32Array(), _batch, PackedColorArray([_batch_col]))
	_batch = PackedVector2Array()
	_batch_ci = null

func _circle(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	_to_batch(ci, col)
	_batch.append_array(Transform2D(0.0, Vector2(r, r), 0.0, p) * _circle_tris())

func _polygon(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() == 3:
		_to_batch(ci, col)
		_batch.append_array(pts)
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		return
	_to_batch(ci, col)
	for k in idx:
		_batch.append(pts[k])

func _line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float) -> void:
	_flush()
	ci.draw_line(a, b, col, width)

func _rect(ci: CanvasItem, r: Rect2, col: Color) -> void:
	_flush()
	ci.draw_rect(r, col)

## 各層の描画(描き終えたらまとめた分を出す)。
func _draw_layer(cb: Callable, ci: Node2D) -> void:
	cb.call(ci)
	_flush()

func _draw_accent_layer() -> void:
	_draw_accent()
	_flush()

# ---------------------------------------------------------------------------
# 組み立て
# ---------------------------------------------------------------------------
func setup(st: Control, attribute_color: Color) -> void:
	stage = st
	tint = attribute_color
	home = st._foot("boss")
	if st.size.x >= 2.0 and st.size.y >= 2.0:
		VIEW = st.size
	st.add_child(self)
	back = _canvas(1, _draw_back)
	var boss_vis: Control = st._visuals["boss"]
	st.move_child(back.disp, boss_vis.get_index())
	pool = ColorRect.new()
	pool.position = home - Vector2(170, 48)
	pool.size = Vector2(340, 96)
	pool_mat = ShaderMaterial.new()
	pool_mat.shader = Shader.new()
	pool_mat.shader.code = POOL_SHADER
	pool_mat.set_shader_parameter("origin", pool.position)
	pool_mat.set_shader_parameter("c", home + Vector2(0, 1))
	pool.material = pool_mat
	(back.world as Node2D).add_child(pool)
	(back.world as Node2D).move_child(pool, 0)
	_bbc = BackBufferCopy.new()
	_bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_bbc.z_index = 3
	st.add_child(_bbc)
	space_rect = ColorRect.new()
	space_rect.size = VIEW
	space_rect.z_index = 3
	space_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space_mat = ShaderMaterial.new()
	space_mat.shader = Shader.new()
	space_mat.shader.code = SPACE_SHADER
	space_mat.set_shader_parameter("view", VIEW)
	space_rect.material = space_mat
	space_rect.visible = false
	st.add_child(space_rect)
	mid = _canvas(4, _draw_mid)
	top = _canvas(6, _draw_top)
	accent = Node2D.new()
	accent.z_index = 7
	accent.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	accent.material = add
	st.add_child(accent)
	accent.draw.connect(_draw_accent_layer)
	hud_over_mat = ShaderMaterial.new()
	hud_over_mat.shader = Shader.new()
	hud_over_mat.shader.code = HUD_OVER_SHADER
	hud_over_mat.set_shader_parameter("view", VIEW)
	for i in range(3):
		var c: Dictionary = [back, mid, top][i]
		var s := Sprite2D.new()
		s.texture = (c.vp as SubViewport).get_texture()
		s.centered = false
		s.scale = (c.disp as Sprite2D).scale
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.z_index = HUD_OVER_Z + i
		s.material = hud_over_mat
		s.visible = false
		st.add_child(s)
		hud_over.append(s)

func _canvas(z: int, cb: Callable) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(ceili(VIEW.x * 0.5), ceili(VIEW.y * 0.5))
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(vp)
	var world := Node2D.new()
	world.scale = Vector2(0.5, 0.5)
	vp.add_child(world)
	var drawer := Node2D.new()
	world.add_child(drawer)
	drawer.draw.connect(_draw_layer.bind(cb, drawer))
	# 表示は Sprite2D(TextureRect にしない: ステージの背景は「画像を持つ TextureRect」として探されるため、取り違えさせない)
	var disp := Sprite2D.new()
	disp.texture = vp.get_texture()
	disp.centered = false
	disp.scale = VIEW / Vector2(vp.size)
	disp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	disp.z_index = z
	var rim := ShaderMaterial.new()
	rim.shader = Shader.new()
	rim.shader.code = RIM_SHADER
	disp.material = rim
	stage.add_child(disp)
	return {"vp": vp, "world": world, "drawer": drawer, "disp": disp}

# ---------------------------------------------------------------------------
# 時計・入力
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not is_instance_valid(stage):
		return
	aura_t += delta
	_sync_layout()
	_refresh()

## ステージの大きさ・ボスの足元が変わったら(画面の大きさの変更・並び直し)、描画先と墨溜まりを合わせ直す。
## ステージが見えていない間(ホーム画面のモニターが閉じている等)は、描画先の更新を止める。
func _sync_layout() -> void:
	if not is_instance_valid(stage):
		return
	var sz := stage.size
	if sz.x >= 2.0 and sz.y >= 2.0 and sz != VIEW:
		VIEW = sz
		for c in [back, mid, top]:
			(c.vp as SubViewport).size = Vector2i(ceili(sz.x * 0.5), ceili(sz.y * 0.5))
			(c.disp as Sprite2D).scale = sz / Vector2((c.vp as SubViewport).size)
		for s in hud_over:
			(s as Sprite2D).scale = (back.disp as Sprite2D).scale
		space_rect.size = sz
		space_mat.set_shader_parameter("view", sz)
		hud_over_mat.set_shader_parameter("view", sz)
	if not stage.is_playing():
		var f: Vector2 = stage._foot("boss")
		if f != home:
			home = f
			pool.position = home - Vector2(170, 48)
			pool_mat.set_shader_parameter("origin", pool.position)
			pool_mat.set_shader_parameter("c", home + Vector2(0, 1))
	var mode := SubViewport.UPDATE_ALWAYS if stage.is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	for c in [back, mid, top]:
		if (c.vp as SubViewport).render_target_update_mode != mode:
			(c.vp as SubViewport).render_target_update_mode = mode

## ステージから外す(別のボスへの切り替え・ステージの破棄)。ステージへ足した表示をすべて片付ける。
func dispose() -> void:
	for c in [back, mid, top]:
		if c is Dictionary and c.has("disp") and is_instance_valid(c.disp):
			(c.disp as Node).queue_free()
	for n in [_bbc, space_rect, accent] + hud_over:
		if is_instance_valid(n):
			n.queue_free()
	hud_over = []
	stage = null
	queue_free()

func set_body(s: Dictionary) -> void:
	body = s

## 本番の演出の_advance()から毎コマ呼ばれる(本体・VFXと同じコマで墨と空間を合わせる)。
func advance_attack(k: String, t: float, shake_offset: Vector2, info: Dictionary) -> void:
	if at < 0.0 or t < at - 0.001 or k != kind:
		attack_start = aura_t - t
		_landing.clear()
	kind = k
	at = t
	shake = shake_offset
	hit_at = info.get("hit", hit_at)
	center = info.get("center", center)
	feet = info.get("feet", feet)
	allies = info.get("allies", allies)
	_refresh()

func end_attack() -> void:
	at = -1.0
	kind = ""
	shake = Vector2.ZERO
	_refresh()

func advance_awakening(t: float, shake_offset: Vector2) -> void:
	awk_t = t
	shake = shake_offset
	if t >= AwMotion.APPEARANCE_SWITCH:
		body = Rig.state("a3", home)
	_refresh()

func end_awakening() -> void:
	awk_t = -1.0
	shake = Vector2.ZERO
	_refresh()

func _awakened() -> bool:
	return str(stage._asset_ids.get("boss", "")) == "musha_awakened"

func _t_end() -> float:
	match kind:
		"single":
			return S_END
		"all":
			return A_END
	return 4.2

func _refresh() -> void:
	if not is_instance_valid(stage):
		return
	# 墨の出現: 覚醒前は0、覚醒演出の中で段階的に現れ、覚醒後は1
	if awk_t >= 0.0:
		em_pool = 0.28 * smoothstep(2.9, 4.7, awk_t) + 0.72 * smoothstep(4.8, 5.35, awk_t)
		em_aura = 0.25 * smoothstep(3.3, 4.7, awk_t) + 0.75 * smoothstep(4.9, 6.2, awk_t)
		em_sheath = smoothstep(5.3, 5.85, awk_t)
	elif _awakened():
		em_pool = 1.0
		em_aura = 1.0
		em_sheath = 1.0
	else:
		em_pool = 0.0
		em_aura = 0.0
		em_sheath = 0.0
	var sh := shake * 0.5 if (at >= 0.0 or awk_t >= 0.0) else Vector2.ZERO
	for c in [back, mid, top]:
		(c.world as Node2D).position = sh
	accent.position = shake if (at >= 0.0 or awk_t >= 0.0) else Vector2.ZERO
	_record()
	_update_pool()
	_update_space()
	_update_hud_over()
	for c in [back, mid, top]:
		(c.drawer as Node2D).queue_redraw()
	accent.queue_redraw()

## UI欄の上にも重ねる濃さ(0〜1)。意図した全画面の演出の間だけ(それ以外は0 = UI欄が前):
##   単体の着弾: 空間が斬れてから墨の爆発が終わるまで(約1.4秒、終わりは薄れて消える)
##   全体の白い画面(見えない速さの抜刀): 白い画面の濃さのまま(白が引くと同時にUI欄が前に戻る)
##   全体の着弾: 墨の大爆発が終わるまで(約2秒、攻撃が終わる前に薄れて消える)
func _hud_peak() -> float:
	if kind == "single" and at >= S_CUT:
		return 1.0 - smoothstep(S_CUT + 1.1, S_CUT + 1.4, at)
	if kind == "all" and at >= A_FLASH and at <= A_FLASH_END:
		return _flash_white(at - A_FLASH)
	if kind == "all" and at >= A_IMPACT:
		return 1.0 - smoothstep(A_IMPACT + 1.7, A_END - 0.05, at)
	return 0.0

## 着弾の瞬間だけ、UI欄の上にも墨の層の絵を重ねる(UI欄の矩形は着弾ごとに1回だけ読む)。
func _update_hud_over() -> void:
	var k := _hud_peak()
	if k <= 0.001:
		_hud_checked = false
		_hud_rects = []
		for s in hud_over:
			(s as Sprite2D).visible = false
		return
	if not _hud_checked:
		_hud_checked = true
		_hud_rects = _collect_hud_rects()
		var packed := PackedVector4Array()
		for r in _hud_rects:
			packed.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
		while packed.size() < HUD_OVER_MAX_RECTS:
			packed.append(Vector4.ZERO)
		hud_over_mat.set_shader_parameter("rects", packed)
		hud_over_mat.set_shader_parameter("count", _hud_rects.size())
	hud_over_mat.set_shader_parameter("amount", k)
	for s in hud_over:
		(s as Sprite2D).visible = not _hud_rects.is_empty()

## 全画面の戦闘画面のUI欄(rbm_fullscreen_battle_ui.gd がステージの meta "battle_hud" に渡す)の、見えている欄とボタンの矩形
## (ステージの座標)。ほかの矩形に含まれるものは除き、大きい順に HUD_OVER_MAX_RECTS 個まで。UI欄が無い(ホーム画面のモニター等)なら空。
func _collect_hud_rects() -> Array:
	if not is_instance_valid(stage) or not stage.has_meta("battle_hud"):
		return []
	var hud = stage.get_meta("battle_hud")
	if not is_instance_valid(hud) or not (hud is Control) or not (hud as Control).is_visible_in_tree():
		return []
	var inv := stage.get_global_transform().affine_inverse()
	var found: Array = []
	_collect_hud_node(hud, inv, found)
	found.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.get_area() > b.get_area())
	var out: Array = []
	for r in found:
		var inside := false
		for o in out:
			if (o as Rect2).encloses(r):
				inside = true
				break
		if not inside and out.size() < HUD_OVER_MAX_RECTS:
			out.append(r)
	return out

func _collect_hud_node(n: Node, inv: Transform2D, found: Array) -> void:
	for c in n.get_children():
		if not (c is Control) or not (c as Control).is_visible_in_tree():
			continue
		if c is Panel or c is BaseButton:
			var r: Rect2 = inv * (c as Control).get_global_rect()
			if r.size.x >= 1.0 and r.size.y >= 1.0:
				found.append(r)
		else:
			_collect_hud_node(c, inv, found)

## 刀と刀の墨を1コマごとに記録する(1.6秒ぶん)。
func _record() -> void:
	if not _hist.is_empty() and absf(float(_hist[_hist.size() - 1].t) - aura_t) < 0.0005:
		return
	var bl := _blade_now()
	var entry := {"t": aura_t, "a": at, "k": kind}
	if not bl.is_empty():
		entry["H"] = bl[0]
		entry["P"] = bl[1]
		var sh := _sheath(bl, at, aura_t)
		entry["pts"] = sh.pts
		entry["rs"] = sh.rs
		entry["rmax"] = sh.rmax
	_hist.append(entry)
	while _hist.size() > 0 and aura_t - float(_hist[0].t) > 1.6:
		_hist.pop_front()

func _hist_at(te: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1e9
	for e in _hist:
		var d := absf(float(e.t) - te)
		if d < bd and e.has("pts"):
			bd = d
			best = e
	return best

## 時刻 te(墨オーラの時計)の、攻撃の経過(待機なら-1)。
func _at_of(te: float) -> float:
	var x := te - attack_start
	return x if x >= 0.0 and x < _t_end() and kind != "" else -1.0

## 攻撃中の抑制(オーラの墨が刀へ集まって一時的に減り、攻撃の後に戻る)。
func _supp(a: float) -> float:
	if a < 0.0:
		return 0.0
	match kind:
		"single":
			return smoothstep(0.3, 1.0, a) * (1.0 - smoothstep(S_BACK - 0.3, S_END, a))
		"all":
			# 溜めの間にオーラを刀へ全部吸い込んで無くし、抜刀待機へ戻る時に戻す
			return smoothstep(A_STANCE, A_GATHER_END - 0.35, a) * (1.0 - smoothstep(A_BACK - 0.4, A_END - 0.1, a))
		"buff":
			return 0.55 * smoothstep(0.3, 0.9, a) * (1.0 - smoothstep(2.3, 3.4, a))
	return 0.35 * smoothstep(0.3, 0.9, a) * (1.0 - smoothstep(2.3, 3.4, a))

# ---------------------------------------------------------------------------
# 描画部品
# ---------------------------------------------------------------------------
func _ribbon(ci: CanvasItem, pts: Array, ws: Array, col: Color) -> void:
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var d := b - a
		if d.length() < 0.05:
			continue
		var nrm := Vector2(-d.y, d.x).normalized()
		var wa: float = float(ws[i]) * 0.5
		var wb: float = float(ws[i + 1]) * 0.5
		if wa < 0.3 and wb < 0.3:
			continue
		wa = maxf(wa, 0.5)
		wb = maxf(wb, 0.5)
		_polygon(ci, PackedVector2Array([a + nrm * wa, b + nrm * wb, b - nrm * wb, a - nrm * wa]), col)
		if wb > 1.0:
			_circle(ci, b, wb, col)

## 太さの変わる液体の流れ(円を密に連ねる=塊の和になり、照りは和の縁にだけ付く)。
## (円が多いので、_circle() と同じ円をここで直接まとめる。描き先・色はこの中で変わらない)
func _chain(ci: CanvasItem, pts: Array, rs: Array, col: Color = INK) -> void:
	_to_batch(ci, col)
	var tris := _circle_tris()
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ra: float = rs[i]
		var rb: float = rs[i + 1]
		var n := int(ceil(a.distance_to(b) / 2.0)) + 1
		for k in range(n):
			var f := float(k) / n
			var r := lerpf(ra, rb, f)
			if r >= 0.7:
				_batch.append_array(Transform2D(0.0, Vector2(r, r), 0.0, a.lerp(b, f)) * tris)
	var last: float = rs[rs.size() - 1]
	if last >= 0.7:
		_circle(ci, pts[pts.size() - 1], last, col)

func _drop(ci: CanvasItem, p: Vector2, vel: Vector2, r: float) -> void:
	if r < 0.6:
		return
	_circle(ci, p, r, INK)
	var sp := vel.length()
	if sp > 30.0:
		var bk := -vel / sp
		var L := minf(r * 4.0, sp * 0.028)
		var nrm := Vector2(-bk.y, bk.x)
		_polygon(ci, PackedVector2Array([p + nrm * r * 0.9, p + bk * (r + L), p - nrm * r * 0.9]), INK)

func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color = INK) -> void:
	if rx < 0.6 or ry < 0.4:
		return
	var pts := PackedVector2Array()
	for i in range(16):
		var a := i * TAU / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	_polygon(ci, pts, col)

## 縁の揺らいだ墨溜まり(地面に広がる墨)。
func _blob(ci: CanvasItem, c: Vector2, rx: float, ry: float, seed: float, t: float) -> void:
	if rx < 1.0 or ry < 0.6:
		return
	var pts := PackedVector2Array()
	var n := 40
	for i in range(n):
		var a := i * TAU / n
		var k := 1.0 + 0.16 * sin(a * 3.0 + seed + t * 0.4) + 0.10 * sin(a * 7.0 + seed * 2.3 - t * 0.6) + 0.07 * sin(a * 13.0 + seed * 1.7)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry) * k)
	_polygon(ci, pts, INK)

## 放物線で飛ぶ雫。空中は front=true の層、着地後の染みは front=false(地面)の層。
func _ballistic(ci: CanvasItem, front: bool, p0: Vector2, v: Vector2, g: float, age: float, r: float, gy: float, life: float) -> void:
	if age < 0.0:
		return
	var disc := v.y * v.y + 2.0 * g * (gy - p0.y)
	var tl := (-v.y + sqrt(disc)) / g if disc >= 0.0 else 1e9
	if age < tl:
		if front:
			_drop(ci, p0 + v * age + Vector2(0, 0.5 * g * age * age), v + Vector2(0, g * age), r)
	elif not front:
		var k := 1.0 - smoothstep(life * 0.4, life, age - tl)
		if k > 0.05:
			_ellipse(ci, p0 + v * tl + Vector2(0, 0.5 * g * tl * tl), r * 1.9 * k, r * 0.6 * k)

## 毛筆: 芯を塗り、縁の毛と先の掠れで荒々しさを出す(from_r〜revealの範囲)。
func _brush(ci: CanvasItem, pts: Array, ws: Array, seed: float, reveal: float, dry_from: float, from_r: float = 0.0, dissolve: float = 0.0) -> void:
	var N := pts.size() - 1
	var lim := mini(int(floor(reveal * N)), N)
	var i0 := int(floor(from_r * N))
	if lim - i0 < 1:
		return
	var cp: Array = []
	var cw: Array = []
	for i in range(i0, lim + 1):
		var r := float(i) / N
		cp.append(pts[i])
		var keep := 1.0 if dissolve <= 0.0 else (0.0 if _h(seed, float(i) * 0.7) < dissolve else 1.0)
		cw.append(float(ws[i]) * lerpf(0.9, 0.12, smoothstep(dry_from, 1.0, r)) * keep)
	_ribbon(ci, cp, cw, INK)
	# ここから先は線だけなので、まとめた分を先に出し、線は直接描く(_line() と同じ順・同じ線)
	_flush()
	var B := 11
	for j in range(B):
		var cj := float(j) / (B - 1) - 0.5
		var thin := _h(seed, 200.0 + j) < 0.35
		var end_r := 1.0 - 0.22 * _h(seed, 300.0 + j) * absf(cj) * 2.0
		for i in range(i0, lim):
			var r := float(i) / N
			if r > end_r:
				break
			var dry := smoothstep(dry_from, 1.0, r)
			if dry <= 0.0 and absf(cj) < 0.3:
				continue
			if _h(seed + j * 7.7, floorf(i * 0.5)) < dry * 0.92 + dissolve:
				continue
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var d := b - a
			if d.length() < 0.05:
				continue
			var nrm := Vector2(-d.y, d.x).normalized()
			var wa: float = ws[i]
			var wb: float = ws[i + 1]
			if maxf(wa, wb) < 0.5:
				continue
			ci.draw_line(a + nrm * cj * wa, b + nrm * cj * wb, INK2 if thin and dry > 0.0 else INK, maxf(2.0, maxf(wa, wb) / (B - 1) * 1.4))
	if lim >= N and N >= 3 and dissolve < 0.5 and float(ws[N - 3]) >= 0.5:
		var last: Vector2 = pts[N]
		var d2 := (last - (pts[N - 2] as Vector2)).normalized()
		var n2 := Vector2(-d2.y, d2.x)
		var wl: float = maxf(float(ws[N - 3]), 4.0)
		for j in range(5):
			var off := (float(j) - 2.0) * wl * 0.16
			ci.draw_line(last + n2 * off, last + n2 * off * 1.7 + d2 * (6.0 + 12.0 * _h(seed, 400.0 + j)), INK, 2.0)

func _catmull(pts: Array, samples: int) -> Array:
	var out: Array = []
	var n := pts.size()
	for i in range(samples + 1):
		var f := float(i) / samples * (n - 1)
		var k := mini(int(f), n - 2)
		var x := f - k
		var p0: Vector2 = pts[maxi(k - 1, 0)]
		var p1: Vector2 = pts[k]
		var p2: Vector2 = pts[k + 1]
		var p3: Vector2 = pts[mini(k + 2, n - 1)]
		var x2 := x * x
		out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * x + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * x2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * x2 * x))
	return out

## 毛筆の払い(anchorから dir へ、先が垂れて掠れる)。
func _flick(ci: CanvasItem, anchor: Vector2, dir: Vector2, L: float, w: float, seed: float, reveal: float, fade: float) -> void:
	var pts: Array = []
	var ws: Array = []
	for i in range(19):
		var r := float(i) / 18.0
		pts.append(anchor + dir * L * r + Vector2(0, 0.3 * L * r * r))
		ws.append((w * pow(1.0 - r, 0.65) + 1.0) * fade)
	_brush(ci, pts, ws, seed, reveal, 0.42)

## 墨の塊(液体): 進む向きに少し伸び、後ろ側がふくらんだ不定形の輪郭(ゆっくり揺れる)。速いときは後ろに小さな雫がちぎれる。
## 線や針にはしない(丸みのある塊として読ませる)。
func _glob(ci: CanvasItem, p: Vector2, vel: Vector2, r: float, seed: float) -> void:
	if r < 0.8:
		return
	var sp := vel.length()
	var d := vel / sp if sp > 1.0 else Vector2(0, 1)
	var nrm := Vector2(-d.y, d.x)
	var st := minf(sp / 520.0, 1.3)
	if r < 2.2:
		_circle(ci, p, r, INK)
		if st > 0.6:
			_circle(ci, p - d * r * 2.2, r * 0.55, INK)
		return
	# 丸い頭と、速いほど細く尖る尾(涙形)。輪郭はなめらかに(わずかに揺れる)。
	var pts := PackedVector2Array()
	var N := GLOB_N
	var tab := _glob_table()
	for i in range(N):
		var a: float = tab[i * 3]
		var ca: float = tab[i * 3 + 1]
		var sa: float = tab[i * 3 + 2]
		var k := 1.0 + 0.04 * sin(a * 3.0 + seed)
		var lx: float
		var ly: float
		if ca >= 0.0:
			lx = ca * r * k * (1.0 + 0.12 * st)
			ly = sa * r * k * (1.0 - 0.12 * st)
		else:
			lx = ca * r * k * (1.0 + 1.5 * st)
			ly = sa * r * k * (1.0 - 0.12 * st) * (1.0 - 0.6 * st * (-ca) * 0.77)
		pts.append(p + d * lx + nrm * ly)
	_polygon(ci, pts, INK)
	# 濡れた艶(左上の小さな照り)
	if r >= 3.0:
		_circle(ci, p + d * r * 0.15 + Vector2(-0.32, -0.42) * r, maxf(1.0, r * 0.22), GLOSS)
	# 速いときは尾の先に小さな雫がちぎれる
	if st > 0.5 and r > 3.0:
		_circle(ci, p - d * r * (2.9 + 1.4 * st), r * 0.3, INK)

## _glob() の輪郭の角度と cos/sin(毎回同じ値なので一度だけ計算する)。[角度, cos, sin] × GLOB_N
const GLOB_N := 24
static var _glob_tab := PackedFloat64Array()

static func _glob_table() -> PackedFloat64Array:
	if _glob_tab.is_empty():
		for i in range(GLOB_N):
			var a := i * TAU / GLOB_N
			_glob_tab.append(a)
			_glob_tab.append(cos(a))
			_glob_tab.append(sin(a))
	return _glob_tab

## 互換: 墨の飛沫の一粒(塊として描く)。
func _blob_drop(ci: CanvasItem, p: Vector2, vel: Vector2, r: float, seed: float = 0.0) -> void:
	_glob(ci, p, vel, r, seed)

## 墨の斬撃の筋(彗星形): path に沿って tail〜head の範囲だけを描く。頭は尖り、頭の少し手前が最も太く、尾は長く細って掠れる。
## head を先に走らせ、tail を遅れて追わせると「画面を横切って消える斬撃」になる(跡が棒のように残らない)。
func _path_at(path: Array, f: float) -> Vector2:
	var x := clampf(f, 0.0, 1.0) * (path.size() - 1)
	var i := mini(int(x), path.size() - 2)
	return (path[i] as Vector2).lerp(path[i + 1], x - i)

func _streak(ci: CanvasItem, path: Array, w: float, head: float, tail: float, seed: float) -> void:
	if head <= tail + 0.004 or w < 0.6:
		return
	var N := 44
	var pts: Array = []
	var ws: Array = []
	for i in range(N + 1):
		var s := float(i) / N
		var f := lerpf(tail, head, s)
		pts.append(_path_at(path, f))
		ws.append(w * 1.5 * pow(s, 0.55) * pow(1.0 - s, 0.2) * (1.0 + 0.08 * sin(f * 41.0 + seed)))
	_ribbon(ci, pts, ws, INK)
	_flush()   # ここから先は線だけ(線は直接描く。_line() と同じ順・同じ線)
	# 尾の掠れ(細い毛の線が途切れながら続く)
	for j in range(6):
		var off := float(j) / 5.0 - 0.5
		for i in range(int(N * 0.55)):
			if _h(seed + j * 3.1, float(i)) < 0.5:
				continue
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var dd := b - a
			if dd.length() < 0.1:
				continue
			var nr := Vector2(-dd.y, dd.x).normalized()
			var ww: float = float(ws[i]) * 1.1 + 3.0
			ci.draw_line(a + nr * off * ww, b + nr * off * ww, INK, 2.0)

## 飛沫の運動: 空気抵抗で減速しながら重力で落ちる(はじけ飛んで、ふわりと止まって、落ちる)。
func _splash_pos(p0: Vector2, v0: Vector2, t: float, k: float, g: float) -> Vector2:
	var e := exp(-k * t)
	return p0 + v0 * (1.0 - e) / k + Vector2(0, g / k * (t - (1.0 - e) / k))

func _splash_vel(v0: Vector2, t: float, k: float, g: float) -> Vector2:
	var e := exp(-k * t)
	return v0 * e + Vector2(0, g / k * (1.0 - e))

## 飛沫が床(gy)に落ちる時刻(life 秒までに落ちなければ 1e9)。一粒ごとに始点・速度が決まっていて毎フレーム同じ値になるので、
## 一度求めたら覚えておく(攻撃が始まるたびに捨てる)。
var _landing := {}

func _landing_time(p0: Vector2, v0: Vector2, gy: float, life: float, k: float, g: float) -> float:
	if p0.y >= gy:
		return 1e9
	var key := [p0, v0, gy, life, k, g]
	var hit = _landing.get(key)
	if hit != null:
		return hit
	var tl := 1e9
	if _splash_pos(p0, v0, life, k, g).y >= gy:
		var lo := 0.0
		var hi := life
		for i in range(10):
			var mid := (lo + hi) * 0.5
			if _splash_pos(p0, v0, mid, k, g).y >= gy:
				hi = mid
			else:
				lo = mid
		tl = hi
	if _landing.size() > 8192:
		_landing.clear()
	_landing[key] = tl
	return tl

## 墨の飛沫(はじける塊): 空中は前面、床に落ちた染みは背面。life 秒で消え(最後は縮む)、床の染みは0.25秒で乾く。
func _splash(ci: CanvasItem, front: bool, p0: Vector2, v0: Vector2, age: float, r: float, gy: float, life: float, k: float = 3.2, g: float = 520.0) -> void:
	if age < 0.0 or age > life + 0.3 or r < 0.7:
		return
	var tl := _landing_time(p0, v0, gy, life, k, g)
	if age < tl:
		if front and age <= life:
			var shrink := 1.0 - smoothstep(life * 0.65, life, age)
			_glob(ci, _splash_pos(p0, v0, age, k, g), _splash_vel(v0, age, k, g), r * shrink, p0.x * 0.37 + p0.y * 0.11 + r * 7.3 + age * 5.0)
	elif not front:
		var q := 1.0 - smoothstep(0.0, 0.25, age - tl)
		if q > 0.05:
			var lp := _splash_pos(p0, v0, tl, k, g)
			_ellipse(ci, Vector2(lp.x, gy), r * 2.0 * q, r * 0.55 * q)

## 墨がはじける塊(大・中・小の飛沫を四方へ)。squash: 縦の広がり(横へ広がる爆発は小さく)。
func _burst(ci: CanvasItem, front: bool, c: Vector2, age: float, n: int, scale_k: float, gy: float, seed: float, squash: float = 0.75, up: float = 120.0, life: float = 0.95) -> void:
	if age < 0.0 or age > life + 0.3:
		return
	for m in range(n):
		var ang := _h(float(m), seed) * TAU
		var tier := m % 7
		var r: float
		var sp: float
		if tier == 0:
			r = 8.0 + 6.0 * _h(float(m), seed + 1.0)
			sp = 380.0 + 360.0 * _h(float(m), seed + 2.0)
		elif tier < 3:
			r = 4.2 + 3.4 * _h(float(m), seed + 1.0)
			sp = 540.0 + 560.0 * _h(float(m), seed + 2.0)
		else:
			r = 1.8 + 2.2 * _h(float(m), seed + 1.0)
			sp = 700.0 + 860.0 * _h(float(m), seed + 2.0)
		var d := Vector2(cos(ang), sin(ang) * squash)
		var v := d * sp * scale_k + Vector2(0, -up * scale_k)
		_splash(ci, front, c + d * 16.0 * scale_k, v, age - 0.03 * _h(float(m), seed + 3.0), r * minf(scale_k, 1.4), gy + 30.0 * _h(float(m), seed + 4.0), life, 2.6, 700.0)

# ---------------------------------------------------------------------------
# 刀と、刀を包む墨
# ---------------------------------------------------------------------------
func _blade_now() -> Array:
	if body.is_empty() or em_sheath <= 0.0 or float(body.get("alpha", 1.0)) < 0.5:
		return []
	return Rig.blade(body)

## 刀身の墨の大きさ(1=待機)。
## 単体: 刀を掲げると刀身の墨は落ちて消え(溜めでは足元から新しく纏い直す: _draw_coat)、抜刀待機へ戻るとまた纏う。
## 全体: 血振りで墨を振り飛ばし、納刀〜抜き打ちの間は刀身に墨は無く、抜刀待機へ戻るとまた纏う。
func _sheath_scale(a: float) -> float:
	var S := 1.0
	if a >= 0.0:
		match kind:
			"single":
				# 掲げた刀から立ち昇る墨が、溜めの間に大きく激しくなり、振り出すと斬撃へ移って消える
				if a < S_SWING:
					S = 1.0 + 1.8 * smoothstep(S_RISE, S_FULL, a) + 0.15 * sin(a * 20.0) * smoothstep(S_COAT, S_FULL, a)
				else:
					S = smoothstep(S_BACK, S_BACK + 0.8, a)
			"all":
				S = (1.0 - smoothstep(A_CHIBURI - 0.08, A_CHIBURI, a)) + smoothstep(A_BACK, A_END, a)
			"buff":
				if a < RELIGHT:
					S = 1.0 + 1.3 * smoothstep(0.35, 2.2, a) + 0.1 * sin(a * 18.0) * smoothstep(1.2, 2.2, a)
				else:
					S = lerpf(2.3, 1.55, smoothstep(RELIGHT, RELIGHT + 0.12, a)) - 0.55 * smoothstep(2.6, 3.9, a)
			"heal":
				S = 1.0 + 0.3 * smoothstep(0.4, 2.2, a) * (1.0 - smoothstep(RELIGHT, 3.2, a))
	return S * em_sheath

func _charge(a: float) -> float:
	return clampf((_sheath_scale(a) / maxf(em_sheath, 0.01) - 1.0) / 1.6, 0.0, 1.0)

## 刀を包む墨の中心線と半径。r: 0=鍔元, 1=切っ先, 1〜=切っ先の先へ伸びる墨(重さで垂れ、床に着けば這う)。
func _sheath(bl: Array, a: float, T: float) -> Dictionary:
	var H: Vector2 = bl[0]
	var P: Vector2 = bl[1]
	var d := P - H
	var L := maxf(d.length(), 1.0)
	var u := d / L
	var n := Vector2(-u.y, u.x)
	var S := _sheath_scale(a)
	var ch := _charge(a)
	var b := 9.5 * S
	var ext := lerpf(0.65, 1.1, ch) * minf(1.0, S)
	var gy := home.y + 1.0
	var pts: Array = []
	var rs: Array = []
	var N := 46
	var rmax := 1.0 + ext
	# 覚醒の抜刀で、墨が鍔元から切っ先へ向かって纏わり始める
	var grow_to := 1.0 if em_sheath >= 1.0 else lerpf(0.1, rmax, em_sheath)
	for i in range(N + 1):
		var r := 0.04 + (rmax - 0.04) * float(i) / N
		var c: Vector2
		if r <= 1.0:
			c = H + d * r
		else:
			var e := (r - 1.0) * L
			c = P + u * e + Vector2(0, 0.30 * e * e / L)
		c += n * sin(r * 7.0 - T * 3.0) * (1.2 + 1.6 * ch) * minf(r, 1.4)
		if c.y > gy:
			c.y = gy
		var prof: float
		if r < 0.14:
			prof = lerpf(0.5, 0.85, r / 0.14)
		elif r <= 1.0:
			prof = lerpf(0.85, 1.0, sin(clampf((r - 0.14) / 0.86, 0.0, 1.0) * PI * 0.5))
		else:
			prof = pow(maxf(0.0, 1.0 - (r - 1.0) / maxf(ext, 0.01)), 0.7)
		var wob := 1.0 + 0.30 * sin(r * 13.0 - T * 4.6) + 0.12 * sin(r * 29.0 + T * 2.1)
		if r > grow_to:
			prof = 0.0
		pts.append(c)
		rs.append(b * prof * wob)
	return {"pts": pts, "rs": rs, "H": H, "P": P, "u": u, "n": n, "L": L, "S": S, "ch": ch, "rmax": rmax}

func _in_swing(a: float) -> bool:
	if kind == "single":
		return a >= S_SWING and a < S_SWING + 0.1
	return false

## 刀から立ち昇る墨(常時): 刀身に薄く墨が乗り、刀身の上側から墨が黒い炎のように立ち昇る。
## 1本ずつ、根元から伸びて揺れながら細り、先がちぎれて粒になって昇り、消える(刀にまとわりつかず、上へ抜けていく)。
## 大きさ S: 待機1、溜めで大きく、振り出すと0(墨は斬撃へ移る)。
const SWORD_WISPS := 11

func _draw_sheath(ci: CanvasItem) -> void:
	if _in_swing(at):
		return
	var bl := _blade_now()
	if bl.is_empty():
		return
	var S := _sheath_scale(at)
	if S < 0.05:
		return
	var H: Vector2 = bl[0]
	var P: Vector2 = bl[1]
	var d := P - H
	var L := maxf(d.length(), 1.0)
	var u := d / L
	var nrm := Vector2(-u.y, u.x)
	var up_side := nrm if nrm.y < 0.0 else -nrm
	var grow := clampf(em_sheath, 0.0, 1.0)
	# 刀身に薄く乗る墨(鋼の芯が合間に覗く)
	var film: Array = []
	var fr: Array = []
	for i in range(21):
		var f := 0.06 + 0.94 * float(i) / 20.0
		if f > lerpf(0.1, 1.0, grow):
			break
		film.append(H.lerp(P, f) + up_side * 0.6)
		fr.append((1.4 + 0.8 * minf(S, 2.0)) * (1.0 + 0.25 * sin(f * 19.0 - aura_t * 5.0)))
	if film.size() >= 2:
		_chain(ci, film, fr)
	for i in range(14):
		var r0 := 0.08 + 0.92 * float(i) / 14.0
		var r1 := 0.08 + 0.92 * float(i + 1) / 14.0
		if sin(r0 * 13.0 - aura_t * 4.0) > -0.2 or r1 > lerpf(0.1, 1.0, grow):
			continue
		_line(ci, H.lerp(P, r0), H.lerp(P, r1), STEEL, 2.0)
	# 立ち昇る墨の炎
	for k in range(SWORD_WISPS):
		var f := 0.1 + 0.88 * (float(k) + 0.35 + 0.3 * _h(float(k), 1.0)) / SWORD_WISPS
		if f > lerpf(0.1, 1.0, grow):
			continue
		var root := H.lerp(P, f) + up_side * 1.5
		var period := 1.5 + 0.9 * _h(float(k), 2.0)
		var ph := fposmod(aura_t / period + _h(float(k), 3.0), 1.0)
		var life := sin(PI * ph)
		var height := (30.0 + 38.0 * _h(float(k), 4.0)) * (0.55 + 0.45 * minf(S, 3.0)) * (0.35 + 0.65 * life)
		var w0 := (4.2 + 2.8 * _h(float(k), 5.0)) * (0.6 + 0.4 * minf(S, 2.5)) * (0.5 + 0.5 * life)
		var sway_ph := _h(float(k), 6.0) * TAU
		var pts: Array = []
		var ws: Array = []
		var N := 12
		for j in range(N + 1):
			var g := float(j) / N
			var x := (2.5 + 1.5 * minf(S, 2.0)) * sin(aura_t * 2.4 + sway_ph + g * 3.2) * g
			pts.append(root + Vector2(x, -height * g))
			ws.append(w0 * pow(1.0 - g, 0.75) + 0.4)
		_ribbon(ci, pts, ws, INK)
		_circle(ci, root, w0 * 0.55, INK)
		# 先がちぎれて粒になって昇る
		if ph > 0.45:
			var q := (ph - 0.45) / 0.55
			var tip: Vector2 = pts[N]
			var dp := tip + Vector2(4.0 * sin(aura_t * 3.0 + k), -64.0 * q * (0.7 + 0.6 * _h(float(k), 7.0)))
			_drop(ci, dp, Vector2(0, -60), (1.4 + 1.4 * minf(S, 2.0)) * (1.0 - q))
	# 刀の上の空気まで墨の粒が揺らめきながら高く昇る(待機でも。溜めが大きいほど多く大きく)
	var mote := clampf(0.55 + 0.45 * (S - 1.0), 0.4, 1.6)
	var step := 0.16 if S < 1.3 else 0.09
	var k2 := int(floor(aura_t / step))
	for k in range(k2 - 16, k2 + 1):
		var age := aura_t - k * step
		if age > 1.5:
			continue
		var f := 0.1 + 0.85 * _h(float(k), 21.0)
		var p0 := H.lerp(P, f) + up_side * 3.0
		var p := p0 + Vector2(5.0 * sin(age * 3.0 + k), -64.0 * age)
		_drop(ci, p, Vector2(0, -64), (1.4 + 1.2 * _h(float(k), 22.0)) * mote * (1.0 - age / 1.5) * grow)

## 刀身の墨はまとわりついて垂れない(立ち昇る)。垂れる雫は描かない。
func _draw_sheath_drips(_ci: CanvasItem, _front: bool) -> void:
	pass

# ---------------------------------------------------------------------------
# 常時の墨オーラ
# ---------------------------------------------------------------------------
func _pool_rx() -> float:
	var drain := 1.0
	if at >= 0.0:
		match kind:
			"single":
				drain = 1.0 - 0.35 * smoothstep(S_RISE, S_FULL, at) + 0.35 * smoothstep(S_CUT, S_END, at)
			"all":
				# 墨溜まりは溜めの間に刀へ吸い込まれて無くなり、抜刀待機へ戻る時に戻る
				drain = 1.0 - smoothstep(A_STANCE + 0.05, A_GATHER_END, at) + smoothstep(A_BACK - 0.4, A_END, at)
			"buff":
				drain = 1.0 - 0.25 * smoothstep(0.3, 2.2, at) + 0.25 * smoothstep(2.4, 3.8, at)
			"heal":
				drain = 1.0 - 0.3 * smoothstep(0.3, 2.3, at) + 0.3 * smoothstep(2.5, 4.0, at)
	var burst := 0.0
	if awk_t >= 0.0:
		burst = 0.12 * sin(clampf((awk_t - 4.8) / 0.6, 0.0, 1.0) * PI)
	return 104.0 * drain * (1.0 + 0.025 * sin(aura_t * 0.7) + burst) * em_pool

func _hem_drip(k: int) -> Dictionary:
	var t0 := 0.55 * k + 0.25 * _h(float(k), 1.0)
	var x := home.x - 24.0 + 48.0 * _h(float(k), 2.0)
	var hy := home.y - 46.0 + 6.0 * _h(float(k), 3.0)
	var fall := sqrt(2.0 * (home.y - 1.0 - hy - 2.0) / 600.0)
	return {"t0": t0, "x": x, "hy": hy, "land": t0 + 0.35 + fall}

func _reverse(k: int) -> Dictionary:
	var t0 := 0.8 * k + 0.3 * _h(float(k), 31.0)
	var side := -1.0 if k % 2 == 0 else 1.0
	return {"t0": t0, "o": home + Vector2(side * (12.0 + 50.0 * _h(float(k), 32.0)), -1.0), "front": k % 3 == 0}

func _update_pool() -> void:
	var rx := _pool_rx()
	pool.visible = rx > 1.0
	pool_mat.set_shader_parameter("rad", Vector2(rx, rx * 0.2 + 1.5 * minf(1.0, em_pool * 3.0)))
	pool_mat.set_shader_parameter("time", aura_t)
	var rip := PackedVector4Array()
	# 回復: 再点灯で墨溜まりに光の波紋(緑)が広がる
	var heal_rip := kind == "heal" and at >= RELIGHT and at < RELIGHT + 1.4
	pool_mat.set_shader_parameter("ripple_col", Vector3(0.40, 0.78, 0.50) if heal_rip else Vector3(0.34, 0.36, 0.43))
	if heal_rip:
		for i in range(3):
			var a := (at - RELIGHT - 0.18 * i) * 0.9
			if a >= 0.0:
				rip.append(Vector4(home.x + (i - 1) * 26.0, home.y - 1.0, a, 1.4))
	var k1 := int(floor(aura_t / 0.55))
	for k in range(k1, k1 - 6, -1):
		if k < 0 or rip.size() >= 6:
			break
		var d := _hem_drip(k)
		var age := aura_t - float(d.land)
		if age >= 0.0 and age < 1.2 and _supp(_at_of(float(d.t0))) < 0.5 and em_aura > 0.5:
			rip.append(Vector4(d.x, home.y - 1.0, age, 1.0))
	var k2 := int(floor(aura_t / 0.8))
	for k in range(k2, k2 - 4, -1):
		if k < 0 or rip.size() >= 6:
			break
		var r := _reverse(k)
		var age := aura_t - float(r.t0) - 0.5
		if age >= 0.0 and age < 1.2 and em_aura > 0.5:
			rip.append(Vector4((r.o as Vector2).x, home.y - 1.0, age * 1.3, 0.8))
	while rip.size() < 6:
		rip.append(Vector4(0, 0, 0, 0))
	pool_mat.set_shader_parameter("ripples", rip)

## 立ち昇る墨の筋(水中の墨のように曲がりながらゆっくり昇り、細って消える)。
func _strand(k: int) -> Dictionary:
	var P := 6.0 + 1.3 * float(k % 3)
	var tt := aura_t + _h(float(k), 1.0) * P
	var cyc := floorf(tt / P)
	var s := tt - cyc * P
	if aura_t - s < 0.5:
		return {}
	var seed := k * 13.1 + cyc * 7.3
	var side := -1.0 if _h(seed, 1.0) < 0.5 else 1.0
	var front := k % 3 == 0
	var hem := not front and _h(seed, 2.0) < 0.35
	var o: Vector2
	if hem:
		o = home + Vector2(side * (14.0 + 18.0 * _h(seed, 3.0)), -46.0)
	else:
		o = home + Vector2(side * (26.0 + 64.0 * _h(seed, 3.0)), -2.0 - 4.0 * _h(seed, 4.0))
	var ph := _h(seed, 5.0) * TAU
	var up := 14.0 + 8.0 * _h(seed, 6.0)
	var reach := 100.0 if front else 140.0
	var wmax := 5.0 + 4.0 * _h(seed, 7.0)
	var env := smoothstep(0.0, 1.0, s) * (1.0 - smoothstep(P - 2.3, P - 0.3, s))
	var pts: Array = []
	var ws: Array = []
	var N := 16
	for i in range(N + 1):
		var a := maxf(0.0, s - float(i) * 0.11)
		var rise := reach * (1.0 - exp(-a * up / reach))
		pts.append(Vector2(o.x + side * 5.0 * a + 10.0 * (sin(0.8 * a + ph) - sin(ph)), o.y - rise - 4.0 * (sin(1.3 * a + ph * 1.7) - sin(ph * 1.7))))
		var f := float(i) / N
		ws.append(wmax * env * (1.3 - f) * pow(sin(PI * clampf(f * 0.95 + 0.05, 0.0, 1.0)), 0.5))
	return {"pts": pts, "ws": ws, "front": front, "bead": wmax * env * 0.65}

func _draw_aura(ci: CanvasItem, front: bool) -> void:
	if em_aura <= 0.01 and em_pool <= 0.01:
		return
	var supp := _supp(at)
	var live := (1.0 - supp) * em_aura
	# 地を這う墨の指(墨溜まりの縁から床へ伸び、ゆっくり蠢く)
	if not front and live > 0.02:
		var rx := _pool_rx()
		for k in range(10):
			var side := -1.0 if k % 2 == 0 else 1.0
			var ang0 := (PI if side < 0.0 else 0.0) + (_h(float(k), 41.0) - 0.5) * 1.1
			var root := home + Vector2(cos(ang0) * rx * 0.86, sin(ang0) * (rx * 0.2) * 0.86 + 1.0)
			var dir := Vector2(cos(ang0), sin(ang0) * 0.3).normalized()
			var perp := Vector2(-dir.y, dir.x)
			var L := (40.0 + 62.0 * _h(float(k), 42.0)) * (0.72 + 0.28 * sin(aura_t * 0.45 + k * 1.9)) * live
			if L < 3.0:
				continue
			var pts: Array = []
			var rs: Array = []
			for j in range(11):
				var f := float(j) / 10.0
				pts.append(root + dir * L * f + perp * sin(f * 5.0 - aura_t * 1.1 + k) * 3.0 * f)
				rs.append(lerpf(5.5, 1.4, f) * minf(1.0, live * 1.5))
			_chain(ci, pts, rs)
			_circle(ci, pts[10], 2.6 * minf(1.0, live * 1.5), INK)
	# 立ち昇る墨の筋
	for k in range(15):
		var sd := _strand(k)
		if sd.is_empty() or bool(sd.front) != front:
			continue
		var ws: Array = sd.ws
		for i in range(ws.size()):
			ws[i] = float(ws[i]) * live
		_ribbon(ci, sd.pts, ws, INK)
		_circle(ci, sd.pts[0], float(sd.bead) * live, INK)
	# 外套の裾から雫が垂れ、墨溜まりへ落ちる
	if front and live > 0.3:
		var k1 := int(floor(aura_t / 0.55))
		for k in range(k1 - 3, k1 + 1):
			if k < 0:
				continue
			var d := _hem_drip(k)
			var a: float = aura_t - float(d.t0)
			if a < 0.0 or aura_t > float(d.land) or _supp(_at_of(float(d.t0))) > 0.5:
				continue
			if a < 0.35:
				var g := a / 0.35
				_line(ci, Vector2(d.x, float(d.hy) - 1.0), Vector2(d.x, float(d.hy) + 4.0 * g), INK, 3.0)
				_drop(ci, Vector2(d.x, float(d.hy) + 4.0 * g + 2.0), Vector2(0, 25), 3.2 * g)
			else:
				var fa := a - 0.35
				_drop(ci, Vector2(d.x, float(d.hy) + 5.0 + 300.0 * fa * fa), Vector2(0, 600.0 * fa), 3.2)
	# 逆流: 墨溜まりから雫が糸を引いて持ち上がり、ゆっくり昇って細る
	var k2 := int(floor(aura_t / 0.8))
	for k in range(k2 - 5, k2 + 1):
		if k < 0:
			continue
		var r := _reverse(k)
		if bool(r.front) != front:
			continue
		var a: float = aura_t - float(r.t0)
		if a < 0.0 or a > 3.0:
			continue
		var fade := (1.0 - _supp(_at_of(float(r.t0)))) * em_aura
		if fade <= 0.05:
			continue
		var o: Vector2 = r.o
		var ph := _h(float(k), 3.0) * TAU
		if a < 0.8:
			var topv := 16.0 * smoothstep(0.0, 0.5, a)
			var base_top := topv * (1.0 - smoothstep(0.5, 0.8, a))
			if a < 0.5:
				_line(ci, o, o + Vector2(0, -topv), INK, 3.0)
			elif base_top > 0.5:
				_line(ci, o, o + Vector2(0, -base_top), INK, 3.0)
		var dd := maxf(0.0, a - 0.5)
		var p := o + Vector2(4.0 * sin(dd * 2.4 + ph), -16.0 * smoothstep(0.0, 0.5, a) - 30.0 * dd - 5.0 * dd * dd)
		_drop(ci, p, Vector2(0, -40.0 - 20.0 * dd), 4.6 * smoothstep(0.0, 0.5, a) * (1.0 - smoothstep(1.4, 2.4, dd)) * fade)
	# 時々、筆で払ったような墨の飛沫
	if em_aura < 0.9:
		return
	var kf := int(floor(aura_t / 2.7))
	for k in range(kf - 1, kf + 1):
		if k < 0:
			continue
		var t0 := 2.7 * k + 1.1
		var a := aura_t - t0
		if a < 0.0 or a > 2.2 or _supp(_at_of(t0)) > 0.3:
			continue
		var seed := 50.0 + k * 9.1
		var side := 1.0 if k % 2 == 0 else -1.0
		var anchor := home + Vector2(side * (30.0 + 14.0 * _h(seed, 1.0)), -(64.0 + 40.0 * _h(seed, 2.0)))
		var ang := -0.25 - 0.35 * _h(seed, 3.0)
		var dir := Vector2(cos(ang) * side, sin(ang))
		var L := 70.0 + 26.0 * _h(seed, 4.0)
		var fadew := 1.0 - smoothstep(0.45, 1.1, a)
		var pts: Array = []
		var ws: Array = []
		for i in range(21):
			var rr := float(i) / 20.0
			pts.append(anchor + dir * L * rr + Vector2(0, L * 0.45 * rr * rr))
			ws.append((16.0 * pow(1.0 - rr, 0.7) + 1.5) * fadew)
		if front:
			_brush(ci, pts, ws, seed, smoothstep(0.0, 0.1, a), 0.4)
		for j in range(12):
			var o: Vector2 = pts[int((0.75 + 0.25 * _h(seed, 40.0 + j)) * 20.0)]
			var perp := Vector2(-dir.y, dir.x)
			var v := dir * (130.0 + 130.0 * _h(seed, 50.0 + j)) + Vector2(0, -30.0 + 60.0 * _h(seed, 60.0 + j)) + perp * (_h(seed, 70.0 + j) - 0.5) * 80.0
			_ballistic(ci, front, o, v, 560.0, a - 0.06 - 0.04 * _h(seed, 30.0 + j), 1.8 + 2.4 * _h(seed, 80.0 + j), home.y - 2.0 + 16.0 * _h(seed, 90.0 + j), 1.0)

# ---------------------------------------------------------------------------
# 覚醒後単体「境」: 掲げる → 溜め(足元から墨が昇り、鍔元から切っ先へ刀身をゆっくり包む) → 振り下ろし(墨の軌跡)
# → 振り切ってから墨の三日月が離れて飛ぶ → 斬線に着弾 → 空間に墨の斬線(張りつめる)
# → 空間が斬線でずれて割れる(墨の隙間・縁から墨が噴き出す)+ 墨の爆発 → 閉じて墨の傷跡になり、垂れて消える
# ---------------------------------------------------------------------------
## 斬撃が離れる所(振り切った刀の前)。
const S_LAUNCH_OFF := Vector2(-112, -104)

## 斬線の傾き(度): 飛んできた向きに垂直な線から、上の端を武者の側(右)へ、下の端を前(左)へ倒す(袈裟の斜め「/」)。
## 真上から真下の線だと、対象の上下に並んだ味方まで斬線が掛かるため、斜めにして対象の体の上だけにする。
const S_CUT_TILT := 30.0

## 斬線の半分の長さ(画面の高さの2/3ほどの大きな斬線。斬撃・斬線・空間の割れはすべてこの大きさ)。
const S_HALF := 240.0

var _cl_cache: Dictionary = {}

## 斬線: 対象の胴の中心(hit_at)を通る、大きな斜めの一本の線。
## 飛ぶ斬撃は、この線の真ん中(=胴の中心)に着弾し、斬線・空間の割れ・墨の爆発はすべてこの点が中心。
## 傾きは 20〜45度(袈裟の「/」)の中から、ほかの味方の体から最も離れる角度を選ぶ(斬線が対象以外に掛からないように)。
func _cut_line() -> Dictionary:
	if not _cl_cache.is_empty() and float(_cl_cache.key) == attack_start and (_cl_cache.c as Vector2) == hit_at:
		return _cl_cache
	var L0 := home + S_LAUNCH_OFF
	var c := hit_at
	var d := (c - L0).normalized()
	var u0 := Vector2(-d.y, d.x)
	if u0.y < 0.0:
		u0 = -u0
	var half := S_HALF
	var best_u := u0.rotated(deg_to_rad(S_CUT_TILT))
	var best := -1e9
	for tilt in [20.0, 25.0, 30.0, 35.0, 40.0, 45.0]:
		var uu := u0.rotated(deg_to_rad(float(tilt)))
		var a := c - uu * half
		var b := c + uu * half
		var mind := 1e9
		for fp in allies:
			var f: Vector2 = fp
			if not feet.is_empty() and f.distance_to(feet[0]) < 4.0:
				continue   # 対象自身
			var q := Geometry2D.get_closest_points_between_segments(a, b, f + Vector2(0, -8), f + Vector2(0, -88))
			mind = minf(mind, (q[0] as Vector2).distance_to(q[1]))
		var score := minf(mind, 60.0) - absf(float(tilt) - S_CUT_TILT) * 0.3
		if score > best:
			best = score
			best_u = uu
	var u := best_u
	var n := Vector2(-u.y, u.x)
	# 三日月がふくらむ向き(線に垂直で、飛ぶ向きの側)
	var fwd := n if n.dot(d) > 0.0 else -n
	_cl_cache = {"u": u, "n": n, "c": c, "half": half, "a": c - u * half, "d": d, "l0": L0, "fwd": fwd, "key": attack_start}
	return _cl_cache

## 溜め(1): 足元の墨溜まりから墨の筋がゆっくり昇り、手元(鍔元)に集まる。周りの雫も刀身へ吸い寄せられる。
func _draw_rise(ci: CanvasItem, front: bool) -> void:
	if kind != "single" or at < S_RISE or at > S_FULL + 0.25:
		return
	var bl := _blade_now()
	if bl.is_empty():
		return
	var H: Vector2 = bl[0]
	var P: Vector2 = bl[1]
	for i in range(7):
		var st := S_RISE + 0.08 * i
		var g := pow(smoothstep(st, st + 0.85, at), 1.3)
		var gt := smoothstep(st + 0.6, st + 1.4, at)
		if g <= 0.0 or gt >= 1.0 or (i % 3 == 0) != front:
			continue
		var side := -1.0 if i % 2 == 0 else 1.0
		var p0 := home + Vector2(side * (16.0 + 58.0 * _h(float(i), 1.0)), 1.0)
		var p1 := p0 + Vector2(side * (30.0 + 26.0 * _h(float(i), 2.0)), -70.0 - 50.0 * _h(float(i), 3.0))
		var pts: Array = []
		var rs: Array = []
		for j in range(15):
			var f := lerpf(gt, g, j / 14.0)
			pts.append(p0.lerp(p1, f).lerp(p1.lerp(H, f), f))
			rs.append(lerpf(2.6, 5.6, j / 14.0) * (1.0 + 0.25 * sin(j * 1.7 + aura_t * 9.0)))
		_chain(ci, pts, rs)
		if gt < 0.2 and not front:
			_ellipse(ci, p0, 8.0 * (1.0 - gt * 5.0), 3.0)
	if front:
		for m in range(16):
			var t0 := S_RISE + 0.1 * m
			var s := smoothstep(t0, t0 + 0.9, at)
			if s <= 0.0 or s >= 1.0:
				continue
			var ang := _h(float(m), 5.0) * TAU
			var start := home + Vector2(cos(ang) * (80.0 + 80.0 * _h(float(m), 6.0)), -30.0 - 120.0 * _h(float(m), 7.0) + sin(ang) * 20.0)
			var tgt := H.lerp(P, 0.1 + 0.85 * _h(float(m), 8.0) * _coat_amount())
			var e := pow(s, 2.0)
			_drop(ci, start.lerp(tgt, e), (tgt - start) * 2.0 * pow(s, 1.2), 3.4 * (1.0 - 0.5 * e))

func _coat_amount() -> float:
	return smoothstep(S_COAT, S_FULL, at)

## 溜め(2): 刀身を包む墨。鍔元から切っ先へゆっくり這い上がり(先端は少しふくらんだ液の先)、刀身に沿って締まった形で包む
## (刀より少し太いだけ・向きは刀と同じ)。包み終えると切っ先の先へ少しだけ伸び、峰側から小さな墨の炎、刃側から雫。
func _draw_coat(ci: CanvasItem) -> void:
	if kind != "single" or at < S_COAT or at >= S_SWING:
		return
	var bl := _blade_now()
	if bl.is_empty():
		return
	var H: Vector2 = bl[0]
	var P: Vector2 = bl[1]
	var d := P - H
	var L := maxf(d.length(), 1.0)
	var u := d / L
	var n := Vector2(-u.y, u.x)
	if n.y > 0.0:
		n = -n
	var g := _coat_amount()
	var full := smoothstep(S_FULL - 0.1, S_SWING - 0.05, at)
	var ext := 0.14 * full
	var thick := lerpf(4.6, 6.6, full)
	var lim := g + ext
	var pts: Array = []
	var rs: Array = []
	var N := 36
	for i in range(N + 1):
		var f := float(i) / N * (1.0 + ext)
		if f > lim:
			break
		var c := H + u * L * f + n * sin(f * 8.0 - aura_t * 5.0) * 0.9
		var r := thick * lerpf(0.75, 1.0, smoothstep(0.0, 0.12, f))
		if f > 1.0:
			r *= 1.0 - (f - 1.0) / maxf(ext, 0.001) * 0.85
		r *= 1.0 + 0.45 * exp(-pow((f - lim) * 14.0, 2.0)) * (1.0 - full)
		r *= 1.0 + 0.12 * sin(f * 23.0 + aura_t * 7.0)
		pts.append(c)
		rs.append(r)
	if pts.size() >= 2:
		_chain(ci, pts, rs)
	# 峰側から立ちのぼる小さな墨の炎(包まれた所から)
	for k in range(6):
		var f := 0.15 + 0.14 * k
		if f > g:
			continue
		var root := H + u * L * f + n * thick * 0.8
		var cyc := fposmod(aura_t * (1.1 + 0.25 * _h(float(k), 4.0)) + _h(float(k), 5.0), 1.0)
		var Lw := (7.0 + 9.0 * _h(float(k), 6.0)) * (0.6 + 0.6 * full) * sin(cyc * PI)
		if Lw < 1.5:
			continue
		var fp: Array = []
		var fr: Array = []
		var p := root
		var ang := atan2(n.y, n.x) * 0.6 + (-PI * 0.5) * 0.4
		for j in range(7):
			var q := float(j) / 6.0
			fp.append(p)
			fr.append(lerpf(2.6, 0.8, q))
			ang += 0.2 * sin(aura_t * 4.0 + k + q * 3.0)
			p = p + Vector2(cos(ang), sin(ang)) * Lw / 6.0
		_chain(ci, fp, fr)
	# 刃側から垂れる雫
	for k in range(4):
		var f := 0.3 + 0.18 * k
		if f > g:
			continue
		var cyc := fposmod(aura_t * 0.9 + k * 0.37, 1.0)
		var base := H + u * L * f - n * thick * 0.7
		var dl := 9.0 * cyc
		_line(ci, base, base + Vector2(0, dl), INK, 3.0)
		_circle(ci, base + Vector2(0, dl + 2.0), 2.4 + 1.2 * cyc, INK)
	# 墨の合間に刀身が光る
	for i in range(18):
		var r0 := 0.06 + 0.94 * float(i) / 18.0
		var r1 := 0.06 + 0.94 * float(i + 1) / 18.0
		if r1 > g or sin(r0 * 13.0 - aura_t * 6.0) > -0.25:
			continue
		_line(ci, H.lerp(P, r0), H.lerp(P, r1), STEEL, 2.0)

## 振り下ろし: 刀身を包んだ墨が、振りの弧に沿って墨の帯として振り出される(切っ先の軌跡をなぞる)。
func _draw_smear(ci: CanvasItem) -> void:
	if kind != "single" or at < S_SWING or at > S_SWING + 0.22:
		return
	var ents: Array = []
	for e in _hist:
		if not e.has("P") or str(e.k) != "single":
			continue
		var ea: float = e.a
		if ea < S_SWING - 0.035 or ea > at + 0.001:
			continue
		ents.append(e)
	if ents.size() < 2:
		return
	var tips: Array = []
	for i in range(ents.size() - 1):
		var e0: Dictionary = ents[i]
		var e1: Dictionary = ents[i + 1]
		var H0: Vector2 = e0.H
		var H1: Vector2 = e1.H
		var d0: Vector2 = (e0.P as Vector2) - H0
		var d1: Vector2 = (e1.P as Vector2) - H1
		var a0 := d0.angle()
		var a1 := d1.angle()
		var steps := clampi(int(absf(angle_difference(a0, a1)) / 0.12), 1, 16)
		for j in range(steps):
			var f := float(j) / steps
			tips.append(H0.lerp(H1, f) + Vector2.from_angle(lerp_angle(a0, a1, f)) * (lerpf(d0.length(), d1.length(), f) + 18.0))
	var el: Dictionary = ents[ents.size() - 1]
	tips.append((el.P as Vector2) + ((el.P as Vector2) - (el.H as Vector2)).normalized() * 18.0)
	var last: Vector2 = tips[tips.size() - 1]
	var prev: Vector2 = tips[tips.size() - 2]
	tips.append(last + (last - prev) * 0.25)
	var path := _catmull(tips, maxi(24, tips.size() * 2))
	path.reverse()
	var fade := 1.0 - smoothstep(S_SWING + 0.08, S_SWING + 0.2, at)
	var ws: Array = []
	for i in range(path.size()):
		var r := float(i) / (path.size() - 1)
		ws.append(34.0 * (0.75 + 0.25 * smoothstep(0.0, 0.1, r)) * pow(1.0 - smoothstep(0.35, 1.0, r), 0.55) * fade)
	_brush(ci, path, ws, 51.0, 1.0, 0.4)
	for m in range(12):
		var src: Vector2 = path[int(_h(float(m), 9.0) * 0.6 * (path.size() - 1))]
		var v := Vector2(-180.0 - 160.0 * _h(float(m), 10.0), -80.0 + 160.0 * _h(float(m), 11.0))
		_ballistic(ci, true, src, v, 700.0, at - (S_SWING + 0.03) - 0.01 * m, 1.6 + 1.6 * _h(float(m), 12.0), home.y + 8.0 * _h(float(m), 13.0), 0.9)

## 飛ぶ墨の斬撃の形(s: 飛行の進み, flat: 着弾で潰れる)。太筆の一筆で斜めに払った三日月:
## 中心線は斬線と平行な弧(飛ぶ側へふくらむ)。筆の入り(上の端)は押しつけて太く丸く、下の端へ向かって細く抜ける(払い)。
## 着弾でふくらみと太さが潰れて、そのまま斬線になる。
func _flying_shape(s: float, flat: float) -> Dictionary:
	var cl := _cut_line()
	var u: Vector2 = cl.u
	var d: Vector2 = cl.d
	var fwd: Vector2 = cl.fwd
	var c0: Vector2 = cl.l0
	var c1: Vector2 = cl.c
	var e := pow(s, 0.85)
	var pos := c0.lerp(c1, e)
	var len := lerpf(190.0, 2.0 * float(cl.half), pow(s, 0.8))
	var bulge := minf(len * 0.24, 92.0) * (1.0 - flat)
	var thick := minf(len * 0.2, 64.0) * (1.0 - flat) + 3.0 * flat
	var center: Array = []
	var widths: Array = []
	var N := 40
	for i in range(N + 1):
		var f := float(i) / N
		var sn := sin(PI * f)
		center.append(pos + u * (f - 0.5) * len + fwd * (bulge - thick * 0.45) * sn)
		var prof := (0.5 + 0.5 * smoothstep(0.0, 0.16, f)) * (1.0 - 0.9 * smoothstep(0.4, 1.0, f))
		widths.append(thick * prof * (1.0 + 0.08 * sin(f * 23.0 + 1.7)))
	return {"center": center, "widths": widths, "d": d, "u": u, "pos": pos, "len": len, "c0": c0, "thick": thick}

## 飛ぶ墨の斬撃(振り切ってから): 太筆で一気に払ったような三日月。先頭(進む側)の縁は締まり、後ろへ筆の掠れ(かすれ)が
## 尾を引き、墨の飛沫が散る。対象の胴の中心へまっすぐ飛び、着弾で潰れてそのまま斬線になる。
func _draw_flying(ci: CanvasItem, front: bool) -> void:
	if kind != "single" or at < S_RELEASE or at > S_ARRIVE + 0.07:
		return
	var s := clampf((at - S_RELEASE) / (S_ARRIVE - S_RELEASE), 0.0, 1.0)
	var flat := smoothstep(S_ARRIVE, S_ARRIVE + 0.06, at)
	var shp := _flying_shape(s, flat)
	var center: Array = shp.center
	var widths: Array = shp.widths
	var d: Vector2 = shp.d
	if front:
		# 一筆の三日月(上の端から下の端へ、終わりが掠れる)
		_brush(ci, center, widths, 71.0, 1.0, 0.55)
		# 筆の入り(上の端)の周りに散った墨の点(斬撃と一緒に飛ぶ)
		var head: Vector2 = center[3]
		for k in range(10):
			var ang := _h(float(k), 87.0) * TAU
			var rr := (10.0 + 24.0 * _h(float(k), 88.0)) * (1.0 - flat)
			var dr := (1.3 + 2.8 * _h(float(k), 89.0)) * (1.0 - flat)
			if dr > 0.7:
				_circle(ci, head + Vector2(cos(ang), sin(ang)) * rr - d * 4.0, dr, INK)
		# 後ろへ引く筆の掠れ: 太い所ほど長く、途切れ途切れに
		var N := center.size() - 1
		for k in range(26):
			var f := 0.1 + 0.8 * _h(float(k), 81.0)
			var i := int(f * N)
			var w: float = widths[i]
			if w < 2.0:
				continue
			var off := (_h(float(k), 82.0) - 0.5) * w * 0.9
			var base: Vector2 = (center[i] as Vector2) + (shp.u as Vector2) * off - d * w * 0.35
			var ln := (18.0 + 56.0 * _h(float(k), 83.0)) * (w / maxf(float(shp.thick), 1.0)) * (1.0 - flat)
			var seg := 0.0
			var gap := 3.0 + 4.0 * _h(float(k), 84.0)
			while seg < ln:
				var a := base - d * seg
				var b := base - d * minf(seg + 6.0 + 6.0 * _h(float(k), 85.0 + seg), ln)
				_line(ci, a, b, INK if k % 3 != 0 else INK2, 2.0 if k % 2 == 0 else 1.0)
				seg += 6.0 + gap + 6.0 * _h(float(k), 86.0 + seg)
	# 離れた瞬間、振り切った刀の前で墨がはじける
	_burst(ci, front, shp.c0 as Vector2, at - S_RELEASE, 18, 0.55, home.y + 4.0, 451.0, 0.8, 60.0, 0.6)
	# 飛びながら後ろへ散る墨の飛沫
	for j in range(24):
		var rs := float(j) / 24.0
		var rt := S_RELEASE + rs * (S_ARRIVE - S_RELEASE)
		var sh0 := _flying_shape(rs, 0.0)
		var cc: Array = sh0.center
		var p0: Vector2 = cc[int((0.15 + 0.7 * _h(float(j), 8.0)) * (cc.size() - 1))]
		var v := -d * (70.0 + 140.0 * _h(float(j), 9.0)) + (shp.u as Vector2) * (_h(float(j), 12.0) - 0.5) * 120.0 + Vector2(0, -40.0)
		_splash(ci, front, p0, v, at - rt, 1.8 + 2.6 * _h(float(j), 10.0), hit_at.y + 58.0 + 10.0 * _h(float(j), 11.0), 0.6, 2.8, 700.0)

## 着弾の瞬間: 墨の冠と飛沫。
func _crown(ci: CanvasItem, front: bool, p: Vector2, a: float, scale_k: float) -> void:
	if a < 0.0:
		return
	if front and a < 0.12:
		var k := 1.0 - smoothstep(0.0, 0.12, a)
		for m in range(12):
			var ang := PI + (float(m) / 11.0 - 0.5) * 3.8 + (_h(float(m), 16.0) - 0.5) * 0.3
			var d := Vector2(cos(ang), sin(ang))
			var L := (22.0 + 32.0 * _h(float(m), 17.0)) * (1.0 + a * 5.0) * k * scale_k
			var w := (5.0 + 5.0 * _h(float(m), 18.0)) * k * scale_k
			var nrm := Vector2(-d.y, d.x)
			if L > 1.0:
				_polygon(ci, PackedVector2Array([p + nrm * w * 0.5, p + d * L, p - nrm * w * 0.5]), INK)
				_circle(ci, p + d * L, w * 0.45, INK)
		_circle(ci, p, 11.0 * k * scale_k, INK)
	for m in range(14):
		var ang := PI + (_h(float(m), 19.0) - 0.5) * 2.6
		var v := Vector2(cos(ang), sin(ang)) * (130.0 + 200.0 * _h(float(m), 20.0)) * scale_k + Vector2(0, -70)
		_ballistic(ci, front, p, v, 650.0, a, (1.6 + 1.8 * _h(float(m), 21.0)) * scale_k, hit_at.y + 58.0 + 12.0 * _h(float(m), 22.0), 0.6)

## 斬撃が胴の中心に当たった瞬間: 中心で大きく、線に沿った上下で小さく墨が弾ける。
func _draw_arrival(ci: CanvasItem, front: bool) -> void:
	if kind != "single" or at > S_CUT:
		return
	var cl := _cut_line()
	_crown(ci, front, cl.c, at - S_ARRIVE, 1.8)
	for j in range(4):
		var off: float = [-0.3, 0.3, -0.65, 0.65][j]
		_crown(ci, front, (cl.c as Vector2) + (cl.u as Vector2) * float(cl.half) * off, at - S_ARRIVE - 0.02 - 0.02 * float(j / 2), 1.0 if j < 2 else 0.7)

func _cut_center(i: int, N: int, tremble: float) -> Vector2:
	var cl := _cut_line()
	var f := float(i) / N
	return (cl.a as Vector2) + (cl.u as Vector2) * 2.0 * float(cl.half) * f + (cl.n as Vector2) * ((_h(float(i), 13.0) - 0.5) * 3.0 + tremble)

func _cut_write() -> float:
	return smoothstep(S_ARRIVE, S_ARRIVE + 0.04, at)

func _cut_tense() -> float:
	return smoothstep(S_ARRIVE + 0.3, S_CUT, at)

## 斬線(着弾〜空間が斬れるまで): 空間に残った一本の墨の線。張りつめて細かく震え、縁から墨が滲んで垂れ、周りの墨の粒が吸い込まれる。
func _draw_cutline(ci: CanvasItem) -> void:
	if kind != "single" or at < S_ARRIVE or at >= S_CUT + 0.03:
		return
	var cl := _cut_line()
	var u: Vector2 = cl.u
	var n: Vector2 = cl.n
	var write := _cut_write()
	var tense := _cut_tense()
	var tremble := sin(at * 70.0) * 0.9 * tense
	var N := 44
	var left: Array = []
	var right: Array = []
	for i in range(N + 1):
		var f := float(i) / N
		if f > write:
			break
		var c := _cut_center(i, N, tremble)
		var w := maxf(2.0, (4.0 + 9.0 * sin(PI * f)) * (0.8 + 0.4 * _h(float(i), 35.0)) * (1.0 + 0.6 * tense))
		left.append(c - n * w * 0.5)
		right.append(c + n * w * 0.5)
	for i in range(left.size() - 1):
		_polygon(ci, PackedVector2Array([left[i], left[i + 1], right[i + 1], right[i]]), INK)
	for m in range(12):
		var f := 0.08 + 0.075 * m
		if f > write:
			continue
		var base := _cut_center(int(f * N), N, tremble) + Vector2(0, 3)
		var dl := (5.0 + 10.0 * _h(float(m), 14.0)) * smoothstep(S_ARRIVE + 0.1, S_ARRIVE + 0.6, at)
		var det := S_ARRIVE + 0.55 + 0.06 * m
		if at < det:
			if dl > 0.8:
				_line(ci, base, base + Vector2(0, dl), INK, 3.0)
				_circle(ci, base + Vector2(0, dl + 2.0), 2.6, INK)
		else:
			_ballistic(ci, true, base + Vector2(0, dl), Vector2(0, 10), 620.0, at - det, 2.4, hit_at.y + 58.0 + 8.0 * _h(float(m), 15.0), 0.5)
	for m in range(18):
		var t0 := S_ARRIVE + 0.25 + 0.03 * m
		var s := smoothstep(t0, t0 + 0.45, at)
		if s <= 0.0 or s >= 1.0:
			continue
		var ang := _h(float(m), 44.0) * TAU
		var tgt := (cl.a as Vector2) + u * 2.0 * float(cl.half) * (0.1 + 0.8 * _h(float(m), 47.0))
		var src := tgt + Vector2(cos(ang) * (90.0 + 90.0 * _h(float(m), 45.0)), sin(ang) * (60.0 + 60.0 * _h(float(m), 46.0)))
		var e := pow(s, 2.4)
		_drop(ci, src.lerp(tgt, e), (tgt - src) * 2.4 * pow(s, 1.4), 2.8 * (1.0 - 0.55 * e))

## 空間の割れの開き(0→1→0): 一瞬で割れ、しばらく開き、閉じる。
func _slice_env(u2: float) -> float:
	return smoothstep(0.0, 0.07, u2) * (1.0 - smoothstep(0.55, 0.95, u2))

## 空間が斬線でずれて割れる(S_CUT〜): 片側ずつ線に沿って逆へずれ、線から押し広げられて細い墨の隙間が開く(シェーダ)。
## ここでは隙間の縁の墨(細く鋭い縁)と、斬線に沿って両端へ飛ぶ墨の飛沫、閉じた後の墨の傷跡を描く。
## 隙間の中の赤熱した継ぎ目(属性の色)は加算の層(_draw_accent)で描く。横へ噴き出す墨の舌は描かない。
func _draw_slice(ci: CanvasItem, front: bool) -> void:
	if kind != "single":
		return
	var u2 := at - S_CUT
	if u2 < 0.0 or u2 > 2.3:
		return
	var cl := _cut_line()
	var u: Vector2 = cl.u
	var n: Vector2 = cl.n
	var a: Vector2 = cl.a
	var half: float = cl.half
	var env := _slice_env(u2)
	var N := 56
	if front and env > 0.01:
		for sv in [-1.0, 1.0]:
			var side: float = sv
			var pts: Array = []
			var rs: Array = []
			for i in range(N + 1):
				var f := float(i) / N
				var along := 1.0 - smoothstep(0.8, 1.12, absf(f * 2.0 - 1.0))
				var gap := SLICE_GAP * env * along
				var r := (1.3 + 1.4 * _h(float(i), 71.0 + side)) * env * along
				pts.append(a + u * 2.0 * half * f + n * side * (gap + r * 0.2))
				rs.append(r)
			_chain(ci, pts, rs)
	# 割れた瞬間、斬線に沿って両端へ飛ぶ墨の飛沫(線の向きに鋭く。横へは広げない)
	for m in range(26):
		var f := 0.12 + 0.76 * _h(float(m), 74.0)
		var o := a + u * 2.0 * half * f
		var dir := u * (1.0 if f > 0.5 else -1.0)
		var d := (dir + n * (_h(float(m), 75.0) - 0.5) * 0.25).normalized()
		var sp := 240.0 + 420.0 * _h(float(m), 76.0)
		_splash(ci, front, o, d * sp, u2 - 0.02 * _h(float(m), 77.0), 1.3 + 2.2 * _h(float(m), 78.0), hit_at.y + 50.0 + 20.0 * _h(float(m), 79.0), 0.6, 3.2, 500.0)
	# 閉じた跡: 斬線の形の墨の傷跡(書かれ、垂れて、掠れて消える)
	if front and u2 >= 0.78:
		var pts2: Array = []
		var ws2: Array = []
		for i in range(33):
			var f := float(i) / 32.0
			pts2.append(a + u * 2.0 * half * f + n * (_h(float(i), 81.0) - 0.5) * 3.0)
			ws2.append(maxf(3.0, 16.0 * sin(PI * f) + 3.0) * (1.0 + 0.12 * sin(f * 31.0)))
		_brush(ci, pts2, ws2, 93.0, smoothstep(0.78, 0.9, u2), 0.62, 0.0, smoothstep(1.35, 2.1, u2))
		for m in range(6):
			var f := 0.15 + 0.13 * m
			var base := a + u * 2.0 * half * f + Vector2(0, 8.0 * sin(PI * f))
			var dl := (8.0 + 12.0 * _h(float(m), 94.0)) * smoothstep(0.9, 1.3, u2)
			var det := 1.3 + 0.07 * m
			if u2 < det:
				if dl > 1.0:
					_line(ci, base, base + Vector2(0, dl), INK, 3.0)
					_circle(ci, base + Vector2(0, dl + 2.0), 2.8, INK)
			else:
				_ballistic(ci, true, base + Vector2(0, dl), Vector2(0, 10), 650.0, u2 - det, 2.4, hit_at.y + 58.0, 0.5)

# ---------------------------------------------------------------------------
# 墨の爆発(単体の空間切り): 紙の閃光 → 円相の衝撃波(2重) → 爆心の墨の塊 → 大・中・小の墨の飛沫が四方へはじける。すべて墨。
# ---------------------------------------------------------------------------
func _paper_flash(ci: CanvasItem, u: float) -> void:
	if u < 0.0 or u >= 0.12:
		return
	_rect(ci, Rect2(-80, -80, VIEW.x + 160, VIEW.y + 160), Color(0.97, 0.95, 0.90, 0.9 * (1.0 - u / 0.12)))

## 円相(筆で一息に描いた輪): 太く入り、細く抜け、終わりは掠れる。x_max より右は細って消える(武者の体に掛けない)。
func _enso(ci: CanvasItem, p: Vector2, R: float, w: float, seed: float, dissolve: float, flat: float, x_max: float = INF) -> void:
	var pts: Array = []
	var ws: Array = []
	var a0 := seed * 2.3
	var N := 64
	for i in range(N + 1):
		var f := float(i) / N
		var a := a0 + f * TAU * 0.9
		var rr := R * (1.0 + 0.035 * sin(f * 9.0 + seed * 3.0))
		var pt := p + Vector2(cos(a), sin(a) * flat) * rr
		pts.append(pt)
		var clip := 1.0 if x_max == INF else 1.0 - smoothstep(x_max - 60.0, x_max, pt.x)
		ws.append(w * (0.45 + 0.55 * smoothstep(0.0, 0.12, f)) * (1.0 - 0.6 * smoothstep(0.55, 1.0, f)) * clip)
	_brush(ci, pts, ws, 400.0 + seed, 1.0, 0.72, 0.0, dissolve)

func _enso_R(u: float, k: float) -> float:
	return 30.0 + 1050.0 * k * pow(clampf(u / 0.8, 0.0, 1.0), 0.55)

func _enso_w(q: float, k: float) -> float:
	return 34.0 * k * (1.0 - q) + 5.0

func _ink_blast(ci: CanvasItem, front: bool, p: Vector2, u: float, k: float, gy: float) -> void:
	if u < 0.0 or u > 1.4:
		return
	if front:
		for j in range(2):
			var uj := u - 0.08 * j
			if uj < 0.0 or uj > 0.8:
				continue
			var q := uj / 0.8
			_enso(ci, p, _enso_R(uj, k), _enso_w(q, k), 1.3 + j * 2.9, smoothstep(0.3, 0.95, q), 0.78)
		if u < 0.22:
			var g := u / 0.22
			_blob(ci, p, (46.0 + 110.0 * g) * k * (1.0 - g), (40.0 + 90.0 * g) * k * (1.0 - g), 7.7, u * 10.0)
	_burst(ci, front, p, u, 80, k, gy, 203.0)

# ---------------------------------------------------------------------------
# 覚醒後全体「界」: 血振りで刀身の墨を振り飛ばす → 納刀(鍔鳴り) → 居合の構え・溜め(墨が鞘へ渦を巻いて吸い込まれ、
# 画面の縁から墨が滲む) → 抜き打ちの横薙ぎ(墨の巨大な横一文字が画面を走る・各人の胴に横の斬線) → 一瞬止まる
# → 墨の大爆発(紙の閃光・横一文字が上下に割れて墨が噴き出す・各人から墨がはじける・画面を横切る墨の斬撃が次々に走る・
# 床を走る墨の円相・墨の雨) → 掠れて消える。空間は切らない。すべて墨。
# ---------------------------------------------------------------------------
func _feet_mean() -> Vector2:
	if feet.is_empty():
		return center + Vector2(0, 85)
	var s := Vector2.ZERO
	for f in feet:
		s += f
	return s / float(feet.size())

## 横一文字の高さ(味方の胴の高さ)。
func _sweep_y() -> float:
	return _feet_mean().y - 58.0

## 居合の鯉口(納刀した腰の鍔元)。
func _koiguchi() -> Vector2:
	if not body.is_empty() and Rig.has_point(body, "tsuba"):
		return Rig.point(body, "tsuba") + Vector2(4, 4)
	return Rig.point(Rig.state("a0", home), "tsuba") + Vector2(4, 4)

## 納刀へ(本番の風切り音): 下げていた刀を鯉口へ振り上げる勢いで、刀身の墨が前へ振り飛ばされる(床に落ちてすぐ乾く)。
## 前へ振り下ろす動きはしない(刀は下から鯉口へ運ぶだけ)。
func _draw_chiburi(ci: CanvasItem, front: bool) -> void:
	var a := at - A_CHIBURI
	if kind != "all" or a < -0.06 or a > 1.2:
		return
	var bl := Rig.blade(Rig.state("a3", home))
	var H: Vector2 = bl[0]
	var P: Vector2 = bl[1]
	for m in range(44):
		var f := 0.25 + 0.85 * _h(float(m), 401.0)
		var o := H.lerp(P, f)
		# 刀は下(左下)から上へ回るので、墨は刀身から左・左上へ接線方向に飛ぶ
		var ang := PI * 1.12 + (_h(float(m), 403.0) - 0.5) * 0.8
		var sp := (240.0 + 520.0 * _h(float(m), 404.0)) * (0.5 + 0.7 * f)
		var tier := m % 6
		var r := (6.5 + 5.0 * _h(float(m), 405.0)) if tier == 0 else ((3.4 + 2.6 * _h(float(m), 405.0)) if tier < 3 else (1.6 + 1.8 * _h(float(m), 405.0)))
		_splash(ci, front, o, Vector2(cos(ang), sin(ang)) * sp + Vector2(0, -40.0), a + 0.04 - 0.03 * (1.0 - f), r, home.y + 4.0 + 16.0 * _h(float(m), 406.0), 0.85, 2.4, 760.0)

## 鍔鳴り(本番の小さな音): 鯉口から小さな墨の飛沫。納刀の時(A_CLICK)と、見えない速さで斬った後の納め直しの時(A_CLICK2、大きめ)。
func _draw_click(ci: CanvasItem, front: bool) -> void:
	if kind != "all":
		return
	var K := _koiguchi()
	for ci_i in range(2):
		var a := at - (A_CLICK if ci_i == 0 else A_CLICK2)
		if a < 0.0 or a > 0.8:
			continue
		var k := 1.0 if ci_i == 0 else 1.6
		for m in range(12 if ci_i == 0 else 20):
			var ang := -PI * 0.5 + (-1.3 + 2.6 * _h(float(m), 411.0))
			var sp := (120.0 + 200.0 * _h(float(m), 412.0)) * k
			_splash(ci, front, K, Vector2(cos(ang), sin(ang)) * sp, a - 0.02 * _h(float(m), 413.0), (1.6 + 2.0 * _h(float(m), 414.0)) * k, home.y + 4.0, 0.5, 3.0, 700.0)
## 溜め(居合の構え〜抜く瞬間): 常時の墨のオーラ(足元の墨溜まり・立ち昇る墨の筋・漂う墨の粒)を、すべて腰の刀(鯉口)へ吸い込む。
## A_STANCE〜A_GATHER_END で墨溜まりは縮んで消え(_pool_rx)、立ち昇る筋も消え(_supp)、その墨が渦を巻きながら鯉口へ流れ込む。
## 吸い込み終わるとオーラは無くなり、鯉口に集まった墨だけが脈打ち、鞘に沿って墨が這う(抜く瞬間まで)。
func _draw_charge(ci: CanvasItem, front: bool) -> void:
	if kind != "all" or at < A_STANCE or at >= A_FLASH:
		return
	var K := _koiguchi()
	var g := smoothstep(A_STANCE, A_GATHER_END, at)
	var deep := smoothstep(A_DEEP - 0.1, A_DEEP + 0.2, at)
	var flow := 1.0 - smoothstep(A_GATHER_END - 0.25, A_GATHER_END, at)
	var rel := 1.0 - smoothstep(A_FLASH - 0.06, A_FLASH, at)
	# 1) 墨溜まりの縁から床を這い、渦を巻いて鯉口へ昇る太い筋(墨溜まりが縮むのと一緒に)
	for i in range(14):
		if (i % 2 == 0) != front:
			continue
		var period := lerpf(0.85, 0.42, deep)
		var ph := fposmod((at - A_STANCE) / period + i * 0.071, 1.0)
		var ang0 := i * TAU / 14.0 + 0.4 * _h(float(i), 421.0)
		var r0 := 104.0 * (1.0 - 0.75 * g) * (0.8 + 0.3 * _h(float(i), 422.0))
		var p0 := home + Vector2(cos(ang0) * r0, 1.0 + sin(ang0) * r0 * 0.2)
		var p1 := p0.lerp(K, 0.5) + Vector2(cos(ang0 + 1.2) * 60.0, -44.0)
		var head := ph
		var tail := maxf(0.0, ph - 0.45)
		var pts: Array = []
		var rs: Array = []
		for j in range(13):
			var f := lerpf(tail, head, j / 12.0)
			pts.append(p0.lerp(p1, f).lerp(p1.lerp(K, f), f))
			rs.append(lerpf(2.5, 6.0, j / 12.0) * (0.7 + 0.6 * g) * flow)
		_chain(ci, pts, rs)
	# 2) 立ち昇っていた墨の筋が、空中から渦を巻いて鯉口へ引き寄せられる
	for i in range(12):
		if (i % 2 == 1) != front:
			continue
		var period := lerpf(0.9, 0.5, deep)
		var ph := fposmod((at - A_STANCE) / period + i * 0.083, 1.0)
		var ang := _h(float(i), 426.0) * TAU
		var start := home + Vector2(cos(ang) * (50.0 + 70.0 * _h(float(i), 427.0)), -40.0 - 130.0 * _h(float(i), 428.0))
		var spin := (1.6 + 1.2 * _h(float(i), 429.0)) * (1.0 if i % 4 < 2 else -1.0)
		var pts: Array = []
		var rs: Array = []
		for j in range(15):
			var f := clampf(ph - 0.4 + 0.4 * j / 14.0, 0.0, 1.0)
			pts.append(K + (start - K).rotated(spin * f) * (1.0 - f))
			rs.append(lerpf(1.2, 4.6, j / 14.0) * flow * (0.6 + 0.4 * (1.0 - g)))
		_chain(ci, pts, rs)
	if not front:
		return
	# 3) 漂う墨の粒も集まる
	for m in range(44):
		var ph := fposmod((at - A_STANCE) / 0.9 + _h(float(m), 423.0), 1.0)
		var ang := _h(float(m), 424.0) * TAU
		var start := K + Vector2(cos(ang) * (150.0 + 150.0 * _h(float(m), 425.0)), sin(ang) * (100.0 + 90.0 * _h(float(m), 426.0)))
		var e := pow(ph, 2.2)
		_drop(ci, start.lerp(K, e), (K - start) * 2.2 * pow(ph, 1.2), 3.6 * (1.0 - 0.6 * e) * flow)
	# 4) 鯉口に集まった墨: 吸い込むほど大きく濃く脈打つ。吸い込み終わると鞘に沿って墨が這い、揺らめきが立つ
	var pulse := 0.5 + 0.5 * sin((at - A_STANCE) * lerpf(9.0, 24.0, g))
	_blob(ci, K, (4.0 + 8.0 * g + 2.5 * pulse) * rel, (3.5 + 6.0 * g + 2.0 * pulse) * rel, 5.1, aura_t)
	var hold := smoothstep(A_GATHER_END - 0.3, A_GATHER_END, at) * rel
	if hold > 0.02:
		var sv := Vector2.from_angle(deg_to_rad(14.0))
		var film: Array = []
		var fr: Array = []
		for j in range(15):
			var f := float(j) / 14.0
			film.append(K + sv * 62.0 * f * hold + Vector2(0, -3.0))
			fr.append((2.6 + 1.2 * pulse) * (1.0 - 0.6 * f) * hold)
		_chain(ci, film, fr)
		for k in range(7):
			var f := 0.1 + 0.8 * float(k) / 6.0
			var root := K + sv * 62.0 * f * hold + Vector2(0, -4.0)
			var phk := fposmod(aura_t * 1.6 + _h(float(k), 431.0), 1.0)
			var tip := root + Vector2(3.0 * sin(aura_t * 3.0 + k), -(10.0 + 14.0 * _h(float(k), 432.0)) * sin(PI * phk))
			_ribbon(ci, [root, root.lerp(tip, 0.5), tip], [3.4 * hold, 2.2 * hold, 0.6], INK)
## 画面の縁から墨が滲む(溜めの間に強まり、抜き打ちで一段暗く、爆発の後に引く)。重ね塗りでも半透明に収める。
func _vignette(ci: CanvasItem) -> void:
	if kind != "all" or at < A_STANCE:
		return
	var k := 0.8 * smoothstep(A_STANCE, A_DRAW, at) + 0.2 * smoothstep(A_DRAW, A_SWEEP + 0.1, at)
	k *= 1.0 - smoothstep(A_IMPACT, A_IMPACT + 0.9, at)
	if k <= 0.01:
		return
	for i in range(10):
		var inset := float(i) * 22.0
		var c := Color(INK.r, INK.g, INK.b, k * 0.065 * (1.0 - float(i) / 10.0))
		_rect(ci, Rect2(-80, -80, VIEW.x + 160, 80 + inset), c)
		_rect(ci, Rect2(-80, VIEW.y - inset, VIEW.x + 160, 80 + inset), c)
		_rect(ci, Rect2(-80, -80, 80 + inset, VIEW.y + 160), c)
		_rect(ci, Rect2(VIEW.x - inset, -80, 80 + inset, VIEW.y + 160), c)

## 抜き付けの斬線: 味方の胴の高さの中心を、右(武者の側)から左へ、上りながら走る一本の斜めの線(わずかに反る)。
## 片手で横へ抜き払った刀の勢いが、そのまま斜め上へ抜けていく向き。点の並びは書き始め(右下)→ 書き終わり(左上)。
## off: 線に垂直なずらし(px、正で上側)、bow: 反り(正で上へふくらむ)、ang: 傾き(度、左上がりが正)。
const CUT_DEG := 22.0

## 斬線の進む向き(右から左へ、ang 度だけ上る)。
func _cut_dir(ang_deg: float = CUT_DEG) -> Vector2:
	return Vector2.from_angle(PI + deg_to_rad(ang_deg))

func _cut_path(off: float, bow: float, ang_deg: float = CUT_DEG, len_back: float = 300.0, len_fwd: float = 560.0) -> Array:
	var d := _cut_dir(ang_deg)
	var n := Vector2(-d.y, d.x)   # 線の上側
	var C0 := _feet_mean() + Vector2(0, -58)
	var A := C0 - d * len_back + n * off
	var B := C0 + d * len_fwd + n * off
	var pts: Array = []
	for i in range(41):
		var f := float(i) / 40.0
		pts.append(A.lerp(B, f) + n * bow * sin(PI * f))
	return pts

## 斜めの筆(path に沿って、両端が尖り中ほどが太い)。reveal: 書かれた所まで(書きかけの先も尖る)、
## gone: 書き始めの側から消えていく所まで。
func _hbrush(ci: CanvasItem, path: Array, w: float, reveal: float, gone: float, seed: float) -> void:
	if reveal <= gone + 0.01:
		return
	var pts: Array = []
	var ws: Array = []
	var N := path.size() - 1
	for i in range(N + 1):
		var f := float(i) / N
		if f < gone or f > reveal:
			continue
		pts.append(path[i])
		var head := clampf((reveal - f) / 0.07, 0.0, 1.0)
		var tail := clampf((f - gone) / 0.07, 0.0, 1.0) if gone > 0.0 else 1.0
		ws.append(w * pow(sin(PI * clampf(f, 0.02, 0.98)), 0.55) * sqrt(head) * sqrt(tail) * (1.0 + 0.1 * sin(f * 37.0 + seed)))
	if pts.size() >= 2:
		_brush(ci, pts, ws, seed, 1.0, 0.8)

## 全体の着弾点: 各対象の胴の中心(足元から 44px 上)と、武者に近い順(右から)の番号。斬撃はすべてこの点を通す。
const TORSO := Vector2(0, -44)
const T_STAGGER := 0.05   # 武者に近い対象から順に斬れていく間隔

func _targets() -> Array:
	var out: Array = []
	for i in range(feet.size()):
		var fp: Vector2 = feet[i]
		out.append({"i": i, "c": fp + TORSO, "foot": fp})
	out.sort_custom(func(p, q): return (p.c as Vector2).x > (q.c as Vector2).x)
	for r in range(out.size()):
		out[r]["rank"] = r
	return out

## 点 c を通る斜めの斬線(右下=武者の側 → 左上)。点の並びは書き始め → 書き終わり。
## off: 線に垂直なずらし(正で上側)、bow: 反り(正で上へふくらむ)、back / fwd: c から右下 / 左上への長さ。
func _through(c: Vector2, ang: float, off: float, bow: float, back: float, fwd: float) -> Array:
	var d := _cut_dir(ang)
	var n := Vector2(-d.y, d.x)
	var A := c - d * back + n * off
	var B := c + d * fwd + n * off
	var pts: Array = []
	for i in range(25):
		var f := float(i) / 24.0
		pts.append(A.lerp(B, f) + n * bow * sin(PI * f))
	return pts

## 各対象の斬線の傾きのばらつき(度)
const SLASH_JIT := [0.0, 13.0, -10.0, 7.0, -5.0, 10.0]

## 対象の胴を斬る斬線(長さは対象の体より少し長いだけ。隣の味方には掛けない)。
func _slash_of(tg: Dictionary, off: float = 0.0) -> Array:
	var ang: float = CUT_DEG + float(SLASH_JIT[int(tg.i) % SLASH_JIT.size()])
	return _through(tg.c, ang, off, 8.0, 105.0, 110.0)

## 対象の斬線が書き始められる時刻(武者に近い対象から順に)。
func _slash_t(tg: Dictionary) -> float:
	return A_SWEEP + T_STAGGER * float(tg.rank)

func _shift(pts: Array, o: Vector2) -> Array:
	if o == Vector2.ZERO:
		return pts
	var out: Array = []
	for p in pts:
		out.append((p as Vector2) + o)
	return out

## 見えない速さの抜刀(A_FLASH〜A_FLASH_END): 画面全体が真っ白(紙の白)になり、その中を見えない斬撃がいくつも走る。
## 斬るたびに(FLASH_CUTS の時刻)、太い墨の斬線が一瞬で白い画面を走って細く抜け、同時に斬る音が鳴る(音は rbm_musha_awakened_frame_presentation.gd)。
## 細い墨の速さの線も、右(武者)から左(味方)へ流れ続ける。白は一瞬で満ち、保って、引く。引くと刀はもう鞘へ戻りかけている。
## [白くなってからの時刻, 傾き(度、左上がりが正), 線に垂直なずらし(px), 太さ]
const FLASH_CUTS := [
	[0.04, 10.0, 0.0, 26.0], [0.15, -30.0, -40.0, 20.0], [0.26, 38.0, 34.0, 22.0], [0.36, -8.0, 64.0, 18.0],
	[0.46, 52.0, -22.0, 20.0], [0.55, -46.0, 12.0, 18.0], [0.63, 22.0, -62.0, 16.0], [0.71, -16.0, 40.0, 24.0],
]

## 白い画面の濃さ(A_FLASH からの経過 a 秒): 一瞬で真っ白になり、最後の0.12秒で引く。
func _flash_white(a: float) -> float:
	var dur := A_FLASH_END - A_FLASH
	if a < 0.0 or a > dur:
		return 0.0
	return smoothstep(0.0, 0.025, a) * (1.0 - smoothstep(dur - 0.12, dur, a))

func _draw_flash(ci: CanvasItem) -> void:
	if kind != "all":
		return
	var a := at - A_FLASH
	var dur := A_FLASH_END - A_FLASH
	if a < 0.0 or a > dur:
		return
	var w := _flash_white(a)
	_rect(ci, Rect2(-80, -80, VIEW.x + 160, VIEW.y + 160), Color(0.97, 0.95, 0.90, w))
	if a > dur - 0.1:
		return
	var C0 := _feet_mean() + TORSO + Vector2(40, 0)
	# 1) 見えない斬撃の跡(斬るたびに一本)
	for j in range(FLASH_CUTS.size()):
		var cdef: Array = FLASH_CUTS[j]
		var u := a - float(cdef[0])
		if u < 0.0 or u > 0.16:
			continue
		var path := _through(C0, float(cdef[1]), float(cdef[2]), 10.0, 520.0, 620.0)
		_hbrush(ci, path, float(cdef[3]), smoothstep(0.0, 0.03, u), smoothstep(0.05, 0.16, u), 720.0 + j)
		# 斬った所に小さな墨の飛沫
		for m in range(8):
			var f := 0.3 + 0.4 * _h(float(m) + j * 11.0, 725.0)
			var dv := Vector2.from_angle(_h(float(m) + j * 5.0, 726.0) * TAU)
			_drop(ci, _path_at(path, f) + dv * 60.0 * u * 6.0, dv * 200.0, 3.0 * (1.0 - u / 0.16))
	# 2) 速さの線(右から左へ流れる)
	for m in range(36):
		var st := 0.02 + (dur - 0.3) * _h(float(m), 721.0)
		var u := (a - st) / 0.09
		if u < 0.0 or u > 1.4:
			continue
		var y := lerpf(C0.y - 160.0, home.y + 20.0, _h(float(m), 722.0))
		var Lm := 180.0 + 420.0 * _h(float(m), 723.0)
		var head := lerpf(home.x + 140.0, -160.0, clampf(u, 0.0, 1.0))
		var tail := minf(head + Lm, home.x + 200.0)
		var fade := 1.0 - smoothstep(1.0, 1.4, u)
		var th := (1.2 + 3.2 * _h(float(m), 724.0)) * fade
		if th > 0.4 and tail > head:
			_line(ci, Vector2(head, y), Vector2(tail, y), INK, th)
			_line(ci, Vector2(head, y), Vector2(head + 12.0, y), INK, th + 1.5)
## 遅れて入る見えない斬撃(A_SWEEP〜着弾): 白い画面の中で斬った8回の斬撃(FLASH_CUTS)が、同じ速さ・同じ向きで味方の体に現れる。
## 覚醒前の全体攻撃「千切」のように、鋭く細い墨の斬線が一人ひとりの体を斬り抜けて一瞬で走り、すぐ消える。
## 一回ごとに全員へ(武者に近い人から FLURRY_STAGGER 秒ずつずらして)入り、斬れた所で墨がはじける。最後の一回の後に墨の大爆発(着弾)。
const FLURRY_STAGGER := 0.015

func _draw_sweep(ci: CanvasItem, front: bool) -> void:
	if kind != "all" or at < A_SWEEP or at >= A_IMPACT + 0.3:
		return
	var tgs := _targets()
	for j in range(FLASH_CUTS.size()):
		var cdef: Array = FLASH_CUTS[j]
		for tg in tgs:
			var ti: int = tg.i
			var t0 := A_SWEEP + float(cdef[0]) + FLURRY_STAGGER * float(tg.rank)
			var u := at - t0
			if u < 0.0 or u > 0.6:
				continue
			var ang := float(cdef[1]) + (_h(float(j * 7 + ti), 740.0) - 0.5) * 26.0
			var c: Vector2 = (tg.c as Vector2) + Vector2((_h(float(j * 3 + ti), 741.0) - 0.5) * 10.0, (_h(float(j + ti * 5), 742.0) - 0.5) * 34.0)
			var path := _through(c, ang, 0.0, 3.0, 125.0, 135.0)
			if front and u < 0.15:
				# 鋭く細い墨の斬線(両端が尖る)と、並んで走る細い一筋
				_hbrush(ci, path, 12.0, smoothstep(0.0, 0.03, u), smoothstep(0.05, 0.15, u), 750.0 + j * 4.0 + ti)
				_hbrush(ci, _through(c, ang, 7.0, 3.0, 95.0, 105.0), 3.5, smoothstep(0.0, 0.035, u), smoothstep(0.04, 0.12, u), 760.0 + j * 4.0 + ti)
			# 斬れた所で墨がはじける(線の両側へ)
			var dv := Vector2.from_angle(PI + deg_to_rad(ang))
			var nv := Vector2(dv.y, -dv.x)
			for m in range(7):
				var side := 1.0 if m % 2 == 0 else -1.0
				var v := nv * side * (120.0 + 220.0 * _h(float(m + j * 7 + ti * 3), 743.0)) + dv * (140.0 * (_h(float(m), 744.0) - 0.3))
				_splash(ci, front, _path_at(path, 0.4 + 0.2 * _h(float(m + j), 745.0)), v, u - 0.01, 1.6 + 2.4 * _h(float(m + ti), 746.0), (tg.foot as Vector2).y + 8.0, 0.6, 3.0, 700.0)
## 着弾の斬撃の嵐: 各対象の胴の中心を、いろいろな傾きの斬撃が次々に斬り抜ける(どの線も対象の上を通る)。
## [対象(武者に近い順の番号), 傾き(度、左上がりが正), 開始(着弾から), 太さ]
const BARRAGE := [
	[0, -28.0, 0.00, 44.0], [1, 34.0, 0.02, 40.0], [2, -24.0, 0.04, 42.0], [3, 30.0, 0.06, 38.0],
	[0, 12.0, 0.09, 34.0], [1, -36.0, 0.11, 34.0], [2, 40.0, 0.13, 32.0], [3, -18.0, 0.15, 34.0],
	[0, 46.0, 0.18, 30.0], [2, -8.0, 0.20, 30.0], [1, 20.0, 0.22, 30.0], [3, -44.0, 0.24, 28.0],
	[0, -60.0, 0.27, 28.0], [2, 62.0, 0.29, 26.0], [1, -4.0, 0.31, 26.0], [3, 52.0, 0.33, 24.0],
]

func _barrage_path(b: Array, tgs: Array) -> Array:
	var r := int(b[0]) % tgs.size()
	var tg: Dictionary = tgs[r]
	return _through(tg.c, float(b[1]), 0.0, 10.0, 200.0, 250.0)

## 画面を横に貫く墨の一文字(着弾の瞬間): 味方の胴の高さを、武者の手前から画面の左の外まで、巨大な墨の一筆が一瞬で走り、
## 上下に割れて(二筋に分かれて)離れながら掠れて消える。
## x0 → x1 の範囲だけ描く(front: 武者より左は前面、武者の前後から右は背面の層に描いて武者の後ろを通す)。
func _draw_world_cut(ci: CanvasItem, u: float, x0: float = INF, x1: float = -100.0) -> void:
	if u < 0.0 or u > 0.7:
		return
	var y := _feet_mean().y + TORSO.y
	if x0 == INF:
		x0 = home.x - 120.0
	var split := 26.0 * smoothstep(0.08, 0.45, u)
	for side in [-1.0, 1.0]:
		var sd: float = side
		var pts: Array = []
		for i in range(41):
			var f := float(i) / 40.0
			pts.append(Vector2(lerpf(x0, x1, f), y + sd * split + 6.0 * sin(f * 5.0 + sd)))
		var w := (60.0 if u < 0.08 else 34.0) * (1.0 - smoothstep(0.3, 0.7, u))
		_hbrush(ci, pts, w, smoothstep(0.0, 0.04, u), smoothstep(0.25, 0.7, u), 660.0 + sd)

## 墨の花(着弾): 各対象の胴で墨の塊が一気にふくらんで花びらのように裂け、しぼみながら消える。
func _ink_bloom(ci: CanvasItem, c: Vector2, u: float, seed: float) -> void:
	if u < 0.0 or u > 0.45:
		return
	var g := smoothstep(0.0, 0.1, u)
	var shrink := 1.0 - smoothstep(0.12, 0.45, u)
	var R := (12.0 + 26.0 * g) * shrink
	if R < 1.5:
		return
	_blob(ci, c, R, R * 0.8, seed, u * 12.0)
	# 花びら(外へ伸びる墨の舌)
	for k in range(9):
		var ang := TAU * float(k) / 9.0 + _h(float(k), seed) * 0.5
		var L := R * (1.3 + 0.8 * _h(float(k), seed + 1.0))
		var dv := Vector2(cos(ang), sin(ang) * 0.8)
		var nv := Vector2(-dv.y, dv.x)
		var wv := R * 0.28
		_polygon(ci, PackedVector2Array([c + nv * wv, c + dv * L, c - nv * wv]), INK)
		_circle(ci, c + dv * L, wv * 0.45, INK)

## 画面全体の集中線(漫画の効果線): 画面の四方の端から爆心へ向かって、細く鋭い墨の線が一瞬で走り、端の方へ引いて消える。
## 墨の量は少ないまま、画面全体(右側・武者の後ろも)に衝撃の勢いを出す。背面の層に描く(人物の後ろ)。
func _draw_speed_burst(ci: CanvasItem, u: float, c: Vector2) -> void:
	if u < 0.0 or u > 0.42:
		return
	var grow := smoothstep(0.0, 0.05, u)
	var retract := smoothstep(0.12, 0.42, u)
	var N := 56
	for i in range(N):
		var ang := TAU * (float(i) + 0.5 * _h(float(i), 800.0)) / N
		var dv := Vector2(cos(ang), sin(ang))
		# 画面の外枠との交点(線の外側の端)
		var tx := INF
		var ty := INF
		if absf(dv.x) > 0.001:
			tx = ((VIEW.x + 40.0 if dv.x > 0.0 else -40.0) - c.x) / dv.x
		if absf(dv.y) > 0.001:
			ty = ((VIEW.y + 40.0 if dv.y > 0.0 else -40.0) - c.y) / dv.y
		var r_out := minf(tx, ty)
		var r_in0 := (150.0 + 90.0 * _h(float(i), 801.0))
		var r_in := lerpf(r_out, r_in0, grow)
		r_in = lerpf(r_in, r_out, retract)
		if r_out - r_in < 4.0:
			continue
		var w := (2.0 + 4.5 * _h(float(i), 802.0)) * (1.0 - 0.5 * retract)
		var nv := Vector2(-dv.y, dv.x)
		var a := c + dv * r_in
		var b := c + dv * r_out
		_polygon(ci, PackedVector2Array([a, b + nv * w, b - nv * w]), INK)

## 墨の大爆発(着弾): 量より形で見せる。
##   紙の白い閃光 → 画面を右端から左端まで貫く墨の一文字(二筋に割れて離れる) + 画面全体の集中線
##   → 各対象の斬線が一瞬ふくらんで砕け、胴で墨の花が咲き、足元から墨の冠が立つ(飛沫は少なめ・大きめ)
##   → 斬撃の嵐(8本) → 床を走る二重の円相(画面の端まで) → わずかな墨の雨。どれも2秒ほどで消える。
func _draw_all_blast(ci: CanvasItem, front: bool) -> void:
	if kind != "all":
		return
	var u := at - A_IMPACT
	if u < 0.0 or u > 2.4:
		return
	var fm := _feet_mean()
	var tgs := _targets()
	if tgs.is_empty():
		return
	var d := _cut_dir()
	var nrm := Vector2(d.y, -d.x)
	var mid := Vector2(lerpf(fm.x, home.x, 0.5), fm.y)
	if front:
		_draw_world_cut(ci, u)
		var swell := 1.0 + 0.8 * (1.0 - smoothstep(0.0, 0.1, u))
		for tg in tgs:
			var ti: int = tg.i
			_hbrush(ci, _slash_of(tg), 24.0 * swell, 1.0, smoothstep(0.04, 0.3, u), 601.0 + ti)
			_hbrush(ci, _slash_of(tg, -16.0), 9.0, 1.0, smoothstep(0.03, 0.22, u), 611.0 + ti)
			_ink_bloom(ci, tg.c, u - 0.02 * float(tg.rank), 670.0 + ti * 5.0)
			_crown(ci, true, (tg.foot as Vector2) + Vector2(0, -6), u - 0.03 * float(tg.rank), 1.3)
		for j in range(0, BARRAGE.size(), 2):
			var b: Array = BARRAGE[j]
			var t0: float = b[2]
			var head := smoothstep(t0, t0 + 0.08, u)
			var tail := smoothstep(t0 + 0.06, t0 + 0.24, u)
			_streak(ci, _barrage_path(b, tgs), float(b[3]) * 0.8, head, tail, 630.0 + j)
	else:
		# 背面の層(人物の後ろ): 一文字の右側(武者の後ろを通る)、画面全体の集中線、床を走る円相
		_draw_world_cut(ci, u, VIEW.x + 100.0, home.x - 120.0)
		_draw_speed_burst(ci, u - 0.01, fm + TORSO + Vector2(60, 0))
		for j in range(2):
			var uj := u - 0.08 * j
			if uj >= 0.0 and uj < 1.0:
				var qj := uj / 1.0
				_enso(ci, mid + Vector2(0, 8), 40.0 + 1400.0 * pow(qj, 0.55), 22.0 * (1.0 - qj) + 3.0, 2.1 + j * 3.3, smoothstep(0.3, 0.95, qj), 0.28)
	# 斬線が砕けた墨の塊(少なく大きく)と、各人の胴からはじける墨
	for tg in tgs:
		var ti: int = tg.i
		var path := _slash_of(tg)
		var gy: float = (tg.foot as Vector2).y
		for m in range(12):
			var f := 0.1 + 0.8 * _h(float(m) + ti * 31.0, 640.0)
			var side := 1.0 if m % 2 == 0 else -1.0
			var dir := (nrm * side + d * (_h(float(m), 641.0) - 0.5) * 1.0).normalized()
			var spd := 360.0 + 620.0 * _h(float(m) + ti, 642.0)
			var r := (7.0 + 6.0 * _h(float(m), 644.0)) if m % 3 == 0 else (3.2 + 2.6 * _h(float(m), 644.0))
			_splash(ci, front, _path_at(path, f), dir * spd + Vector2(0, -90.0), u - (0.03 + 0.15 * f), r, gy + 16.0 + 20.0 * _h(float(m), 645.0), 0.8, 2.6, 760.0)
		_burst(ci, front, tg.c, u - 0.03 * float(tg.rank), 16, 1.1, gy + 4.0, 700.0 + ti * 13.0, 0.6, 100.0, 0.85)
	# わずかな墨の雨
	for m in range(26):
		var t0 := 0.3 + 0.9 * _h(float(m), 650.0)
		var a := u - t0
		if a < 0.0:
			continue
		var x := -20.0 + (VIEW.x + 40.0) * _h(float(m), 651.0)
		_splash(ci, front, Vector2(x, -20.0), Vector2(-30.0, 280.0), a, 2.0 + 2.4 * _h(float(m), 652.0), fm.y + 30.0 * (_h(float(m), 653.0) - 0.5), 0.9, 0.6, 900.0)
# ---------------------------------------------------------------------------
# 自己強化 / 回復
# ---------------------------------------------------------------------------
func _joint_pos(jn: String) -> Vector2:
	var joints := {"knee": Vector2(-10, -36), "knee2": Vector2(14, -34), "hip": Vector2(0, -80), "core": Vector2(-8, -104), "shoulder": Vector2(-20, -128), "shoulder2": Vector2(18, -126)}
	var l: Vector2 = joints.get(jn, Vector2.ZERO)
	if body.is_empty():
		return home + l
	var p := Rig.local(l.x, -l.y, body)
	return (body.foot as Vector2) + p

## 強化: 墨が螺旋を描いて機体を昇る(front: 手前の半周だけ / 奥の半周だけ)。
func _draw_buff(ci: CanvasItem, front: bool) -> void:
	if kind != "buff" or at < 0.25:
		return
	var grow := smoothstep(0.3, 1.6, at)
	var snapk := smoothstep(RELIGHT, RELIGHT + 0.12, at)
	if snapk >= 1.0:
		return
	for j in range(3):
		var ph0 := j * TAU / 3.0 + aura_t * 1.8
		var segs := 48
		var pts: Array = []
		var rs: Array = []
		var prev_front := false
		for i in range(segs + 1):
			var s := float(i) / segs
			if s > grow:
				break
			var th := ph0 + s * TAU * 1.35
			var R := lerpf(46.0, 22.0, s) * (1.0 - snapk * 0.85)
			var y := -s * 172.0 * (1.0 - snapk * 0.4)
			var q := home + Vector2(cos(th) * R, y + sin(th) * R * 0.28)
			var is_front := sin(th) > 0.0
			if is_front != prev_front and pts.size() >= 2:
				if prev_front == front:
					_chain(ci, pts, rs)
				pts = []
				rs = []
			prev_front = is_front
			pts.append(q)
			rs.append(lerpf(6.5, 2.0, s) * (1.0 + 0.2 * sin(s * 20.0 - aura_t * 6.0)) * (1.0 - snapk))
		if pts.size() >= 2 and prev_front == front:
			_chain(ci, pts, rs)
	# 再点灯で弾ける墨
	var a := at - RELIGHT
	if a >= 0.0:
		for m in range(20):
			var ang := m * TAU / 20.0 + _h(float(m), 3.0) * 0.3
			var v := Vector2(cos(ang), sin(ang) * 0.45) * (160.0 + 120.0 * _h(float(m), 4.0)) + Vector2(0, -140.0)
			_ballistic(ci, front, home + Vector2(cos(ang) * 30.0, -60.0), v, 700.0, a, 2.0 + 1.6 * _h(float(m), 5.0), home.y + 6.0 * _h(float(m), 6.0), 1.0)

## 支援の終わりの風の衝撃波(本体側の rbm_musha_frame_presentation.gd が風を描く)に乗って、墨の粒が床を走って散る(覚醒後)。
const SUP_WIND := 2.66

func _draw_support_wind(ci: CanvasItem, front: bool) -> void:
	var a := at - SUP_WIND
	if a < 0.0 or a > 0.8:
		return
	for m in range(30):
		var ang := m * TAU / 30.0 + 0.2 * _h(float(m), 301.0)
		var sp := 240.0 + 260.0 * _h(float(m), 302.0)
		var d := Vector2(cos(ang), sin(ang) * 0.28)
		if (sin(ang) > 0.0) != front:
			continue
		var hop := 12.0 * _h(float(m), 303.0) * sin(PI * minf(a / 0.55, 1.0))
		var pos := home + d * (34.0 + sp * a * (1.0 - 0.45 * a)) + Vector2(0, -2.0 - hop)
		var r := (1.8 + 2.4 * _h(float(m), 304.0)) * (1.0 - smoothstep(0.35, 0.8, a))
		_drop(ci, pos, d * sp, r)

## 回復: 墨の糸が墨溜まりから関節へ流れ込む。
func _draw_heal(ci: CanvasItem, front: bool) -> void:
	if kind != "heal" or at < 0.25:
		return
	var names := ["knee", "knee2", "hip", "core", "shoulder", "shoulder2"]
	var back_ok := not front
	for i in range(names.size()):
		var is_front := i % 2 == 0
		if is_front != front and not (back_ok and i == 2):
			continue
		var st := 0.35 + 0.18 * i
		var g := smoothstep(st, st + 0.5, at) * (1.0 - smoothstep(RELIGHT, RELIGHT + 0.25, at))
		if g <= 0.01:
			continue
		var j := _joint_pos(names[i])
		var side := -1.0 if i % 2 == 0 else 1.0
		var p0 := home + Vector2(side * (30.0 + 40.0 * _h(float(i), 1.0)), 1.0)
		var p1 := p0.lerp(j, 0.5) + Vector2(side * 30.0, 10.0)
		var pts: Array = []
		var rs: Array = []
		for k in range(13):
			var f := float(k) / 12.0 * g
			pts.append(p0.lerp(p1, f).lerp(p1.lerp(j, f), f))
			rs.append(lerpf(3.4, 1.6, float(k) / 12.0))
		_chain(ci, pts, rs)
		# 糸を昇る墨の粒
		for m in range(3):
			var f := fposmod(aura_t * 0.9 + m * 0.33 + i * 0.17, 1.0) * g
			var q := p0.lerp(p1, f).lerp(p1.lerp(j, f), f)
			_circle(ci, q, 3.2, INK)

# ---------------------------------------------------------------------------
# 覚醒の墨
# ---------------------------------------------------------------------------
func _draw_awakening_ink(ci: CanvasItem, front: bool) -> void:
	if awk_t < 0.0:
		return
	var t := awk_t
	# ロックが外れた関節から墨が滲み、垂れる
	for i in range(6):
		var t0 := AwMotion.LOCK_START + i * AwMotion.LOCK_INTERVAL
		var a := t - t0
		if a < 0.0:
			continue
		var p: Vector2 = home + AwMotion.LOCK_OFFSETS[i] + shake * 0.0
		if front:
			var r := 3.8 * smoothstep(0.0, 0.3, a) * (1.0 - smoothstep(3.2, 4.0, a))
			_circle(ci, p, r, INK)
			var dl := 10.0 * smoothstep(0.25, 0.8, a)
			if a < 0.9 and dl > 1.0:
				_line(ci, p, p + Vector2(0, dl), INK, 3.0)
				_circle(ci, p + Vector2(0, dl + 2.0), 2.6, INK)
		_ballistic(ci, front, p + Vector2(0, 12), Vector2(0, 20), 650.0, a - 0.9, 2.6, home.y + 4.0 * _h(float(i), 1.0), 1.6)
	# 暗転の間、墨の粒が浮かび上がって集まる
	if front and t > 3.3 and t < 4.9:
		for m in range(16):
			var s := fposmod(t * 0.5 + m * 0.137, 1.0)
			var ang := m * 2.399
			var q := home + Vector2(cos(ang) * (60.0 - 40.0 * s), -20.0 - 150.0 * s + sin(ang) * 10.0)
			_drop(ci, q, Vector2(0, -60), 2.6 * sin(s * PI) * smoothstep(3.3, 3.8, t))

## 覚醒の解放: 体を覆っていた墨が、体じゅうから一斉に大きくはじけ飛ぶ(本番の暗転・閃光より上の層に描く)。
## 線は使わない。不定形の墨の塊(大・中・小)が勢いよく飛び出し、ふわりと減速して落ち、1秒ほどで縮んで消える。
## 床に落ちた染みもすぐ乾く(残らない)。
func _draw_awakening_burst(ci: CanvasItem, front: bool) -> void:
	if awk_t < 0.0:
		return
	var a2 := awk_t - AwMotion.AWAKENING_RELEASE
	if a2 < 0.0 or a2 > 1.3:
		return
	var c := home + Vector2(0, -95)
	for m in range(130):
		# 体の輪郭の中から飛び出す
		var o := home + Vector2((_h(float(m), 31.0) - 0.5) * 64.0, -12.0 - 160.0 * _h(float(m), 32.0))
		var out := o - c
		var ang := atan2(out.y, out.x) + (_h(float(m), 33.0) - 0.5) * 1.3
		if out.length() < 8.0:
			ang = _h(float(m), 34.0) * TAU
		var tier := m % 8
		var r: float
		var sp: float
		if tier == 0:
			r = 10.0 + 6.0 * _h(float(m), 35.0)
			sp = 480.0 + 420.0 * _h(float(m), 36.0)
		elif tier < 3:
			r = 5.0 + 3.5 * _h(float(m), 35.0)
			sp = 660.0 + 560.0 * _h(float(m), 36.0)
		else:
			r = 2.0 + 2.4 * _h(float(m), 35.0)
			sp = 820.0 + 880.0 * _h(float(m), 36.0)
		var v := Vector2(cos(ang), sin(ang) * 0.8) * sp + Vector2(0, -140.0)
		_splash(ci, front, o, v, a2 - 0.04 * _h(float(m), 37.0), r, home.y + 50.0 * (_h(float(m), 38.0) - 0.2), 0.95, 2.5, 760.0)

# ---------------------------------------------------------------------------
# 色のアクセント(加算): 強化の赤 / 回復の緑 / 単眼。攻撃(単体・全体)は墨だけで、色は付けない。
# ---------------------------------------------------------------------------
func _draw_accent() -> void:
	var ci := accent
	if kind == "single" and at >= S_CUT - 0.01:
		# 空間の割れ: 割れた瞬間に白い閃光の線が走る(属性の色は使わない。属性で変わるのは技名の文字だけ)
		var u2 := at - S_CUT
		var flash := 1.0 - smoothstep(0.0, 0.1, u2)
		if flash > 0.02:
			var cl := _cut_line()
			var u: Vector2 = cl.u
			var a: Vector2 = cl.a
			var half: float = cl.half
			var N := 64
			for i in range(N):
				var f0 := float(i) / N
				var f1 := float(i + 1) / N
				var along := 1.0 - smoothstep(0.8, 1.12, absf(f0 + f1 - 1.0))
				_line(ci, a + u * 2.0 * half * f0, a + u * 2.0 * half * f1, Color(1.0, 0.97, 0.9) * (flash * along), 3.0)
	if kind == "buff" and at >= 0.0:
		# 再点灯から: 刀身に乗った墨の縁が赤く灯り、立ち昇る墨の根元に赤い火の粉が混じる
		var bl := _blade_now()
		var k := smoothstep(RELIGHT, RELIGHT + 0.06, at) * (1.0 - smoothstep(2.9, 3.9, at))
		if k > 0.01 and not bl.is_empty():
			var H: Vector2 = bl[0]
			var P: Vector2 = bl[1]
			for i in range(24):
				var f := 0.08 + 0.9 * float(i) / 23.0
				var p := H.lerp(P, f) + Vector2(0, -3.0)
				_rect(ci, Rect2(p.round(), Vector2(2, 1)), BUFF_RED * (0.75 * k * (0.6 + 0.4 * sin(f * 21.0 + aura_t * 9.0))))
			for m in range(14):
				var f := 0.1 + 0.85 * _h(float(m), 31.0)
				var age := fposmod(aura_t * 0.9 + _h(float(m), 32.0), 1.0)
				var p := H.lerp(P, f) + Vector2(3.0 * sin(age * 7.0 + m), -40.0 * age)
				_rect(ci, Rect2(p.round(), Vector2(2, 2)), BUFF_RED * (0.9 * k * (1.0 - age)))
		var g := smoothstep(RELIGHT, RELIGHT + 0.05, at) * exp(-maxf(0.0, at - RELIGHT - 0.05) / 0.5)
		_eye_flare(ci, g * 1.2, Color(1.0, 0.16, 0.08))
	elif kind == "heal" and at >= 0.0:
		var names := ["knee", "knee2", "hip", "core", "shoulder", "shoulder2"]
		for i in range(names.size()):
			var st := 0.35 + 0.18 * i
			var arr := smoothstep(st + 0.4, st + 0.5, at)
			var pulse := 0.5 + 0.5 * sin(aura_t * 9.0 + i)
			var k := arr * (0.35 + 0.35 * pulse) * (1.0 - smoothstep(RELIGHT + 0.3, 3.2, at))
			k += 1.1 * smoothstep(RELIGHT, RELIGHT + 0.05, at) * exp(-maxf(0.0, at - RELIGHT - 0.05) / 0.35)
			if k > 0.02:
				var j := _joint_pos(names[i]).round()
				_rect(ci, Rect2(j + Vector2(-2, -2), Vector2(4, 4)), HEAL_GREEN * (0.7 * k))
				_rect(ci, Rect2(j + Vector2(-5, -0.5), Vector2(10, 1)), HEAL_GREEN * (0.4 * k))
		var a := at - RELIGHT
		if a >= 0.0 and a < 1.3:
			for m in range(16):
				var q := clampf(a * 1.1 - 0.04 * m, 0.0, 1.0)
				if q <= 0.0:
					continue
				var p := home + Vector2((_h(float(m), 1.0) - 0.5) * 80.0, -10.0 - 160.0 * q * (0.6 + 0.4 * _h(float(m), 2.0)))
				_rect(ci, Rect2(p.round(), Vector2(2, 2)), HEAL_GREEN * (0.9 * (1.0 - q)))
	if awk_t >= 0.0:
		# 解放の瞬間、再点灯した単眼が墨の中で強く光る
		var a := awk_t - AwMotion.AWAKENING_RELEASE
		var g := smoothstep(0.0, 0.05, a) * exp(-maxf(0.0, a - 0.05) / 0.6) if a >= 0.0 else 0.0
		if awk_t >= AwMotion.APPEARANCE_SWITCH:
			_eye_flare(ci, g * 1.1, Color(1.0, 0.16, 0.08))

func _eye_flare(ci: CanvasItem, g: float, col: Color) -> void:
	if g <= 0.03 or body.is_empty() or not Rig.has_point(body, "eye"):
		return
	var e := Rig.point(body, "eye").round()
	var c := col * minf(g, 1.2)
	_rect(ci, Rect2(e + Vector2(-5, -1), Vector2(10, 2)), c * 0.5)
	_rect(ci, Rect2(e + Vector2(-1, -1), Vector2(3, 3)), c)
	if g > 0.45:
		var L := roundf(24.0 * (g - 0.35))
		_rect(ci, Rect2(e + Vector2(-L, 0), Vector2(L * 2.0, 1)), Color(1.0, 0.32, 0.18) * (g - 0.35))

# ---------------------------------------------------------------------------
# 空間(全面パス)の値: 単体の斬線(線が残る間の小さな食い違い → 空間がずれて割れる)と、覚醒の解放の波だけ。
# ---------------------------------------------------------------------------
func _update_space() -> void:
	var m := space_mat
	var on := false
	var sh := shake
	m.set_shader_parameter("s_slide", 0.0)
	m.set_shader_parameter("s_gap", 0.0)
	m.set_shader_parameter("s_mis", 0.0)
	m.set_shader_parameter("w_amp", 0.0)
	if kind == "single" and at >= S_ARRIVE - 0.01 and at < S_CUT + 1.0:
		on = true
		var cl := _cut_line()
		m.set_shader_parameter("s_c", (cl.c as Vector2) + sh)
		m.set_shader_parameter("s_u", cl.u)
		m.set_shader_parameter("s_half", cl.half)
		if at < S_CUT:
			m.set_shader_parameter("s_mis", 4.0 * _cut_write() + 4.0 * _cut_tense() + sin(at * 57.0) * 1.2 * _cut_tense())
		else:
			var env := _slice_env(at - S_CUT)
			m.set_shader_parameter("s_slide", SLICE_SLIDE * env)
			m.set_shader_parameter("s_gap", SLICE_GAP * env)
	elif awk_t >= AwMotion.AWAKENING_RELEASE and awk_t < AwMotion.AWAKENING_RELEASE + 0.9:
		on = true
		var a := (awk_t - AwMotion.AWAKENING_RELEASE) / 0.9
		m.set_shader_parameter("w_center", home + Vector2(0, -95) + sh)
		m.set_shader_parameter("w_radius", 40.0 + 1300.0 * pow(a, 0.7))
		m.set_shader_parameter("w_amp", 14.0 * (1.0 - a))
		m.set_shader_parameter("w_width", 54.0)
	space_rect.visible = on

# ---------------------------------------------------------------------------
# 層ごとの描画
# ---------------------------------------------------------------------------
## 地面(本体の奥): 墨溜まり(シェーダ)・地を這う墨・奥の筋・床の染み
func _draw_back(ci: Node2D) -> void:
	_draw_aura(ci, false)
	_draw_sheath_drips(ci, false)
	_draw_awakening_ink(ci, false)
	_draw_awakening_burst(ci, false)
	if at < 0.0:
		return
	match kind:
		"single":
			_draw_rise(ci, false)
			_draw_flying(ci, false)
			_draw_arrival(ci, false)
			_draw_slice(ci, false)
			_ink_blast(ci, false, hit_at, at - S_CUT, 1.05, hit_at.y + 50.0)
		"all":
			_draw_chiburi(ci, false)
			_draw_click(ci, false)
			_draw_charge(ci, false)
			_draw_sweep(ci, false)
			_draw_all_blast(ci, false)
		"buff":
			_draw_buff(ci, false)
			_draw_support_wind(ci, false)
		"heal":
			_draw_heal(ci, false)
			_draw_support_wind(ci, false)

## 本体の手前: 刀の墨・手前の筋・雫・溜め・振り下ろし・斬線・横一文字
func _draw_mid(ci: Node2D) -> void:
	if at >= 0.0 and kind == "all":
		_vignette(ci)
	_draw_aura(ci, true)
	_draw_sheath(ci)
	_draw_awakening_ink(ci, true)
	if at < 0.0:
		return
	match kind:
		"single":
			_draw_rise(ci, true)
			_draw_smear(ci)
			_draw_cutline(ci)
		"all":
			_draw_chiburi(ci, true)
			_draw_click(ci, true)
			_draw_charge(ci, true)
			_draw_sweep(ci, true)
		"buff":
			_draw_buff(ci, true)
			_draw_support_wind(ci, true)
		"heal":
			_draw_heal(ci, true)
			_draw_support_wind(ci, true)

## 最前面(技名より下): 覚醒の解放の墨 / 紙の閃光 → 飛ぶ斬撃・着弾・空間の割れの墨・墨の爆発
func _draw_top(ci: Node2D) -> void:
	_draw_awakening_burst(ci, true)
	if at < 0.0:
		return
	match kind:
		"single":
			_paper_flash(ci, at - S_CUT)
			_draw_flying(ci, true)
			_draw_arrival(ci, true)
			_draw_slice(ci, true)
			_ink_blast(ci, true, hit_at, at - S_CUT, 1.05, hit_at.y + 50.0)
		"all":
			_paper_flash(ci, (at - A_IMPACT) * 0.6)
			_draw_all_blast(ci, true)
			_draw_flash(ci)
