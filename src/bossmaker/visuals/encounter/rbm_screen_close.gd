extends CanvasLayer
## 登場演出の入り（表示専用）: 戦闘を始める操作（「挑戦する」・クリアチェックの「開始」・「もう一度挑戦」・
## 「最初からやり直す」）の直後、前の画面を残したまま、その上で古いモニターの電源を切るように閉じる（0.30秒）。
## 閉じ終わったら on_closed を呼んで戦闘を始め、登場演出が始まるまで黒のまま待つ（release() で外す）。
## 前の画面は GPU の中の画面のテクスチャとして読むだけで、CPU へ読み出さない（rbm_screen_close.gdshader）。
## 閉じている間はクリック・キー入力を下の画面へ届けない（二重に押されない）。
## 戦闘の状態・乱数・保存データには触れない（on_closed は呼び出し元の今までの処理そのもの）。

const SHADER := preload("res://src/bossmaker/visuals/encounter/rbm_screen_close.gdshader")
const Audio := preload("res://src/bossmaker/visuals/encounter/rbm_encounter_audio.gd")
const GROUP := "rbm_screen_close"
## 閉じる長さ（登場演出の時刻 0〜0.30秒に当たる）。
const DURATION := 0.30
## 黒のまま待つ上限（登場演出が始まらない時に、黒い画面が残り続けないように）。
const HOLD_LIMIT := 8.0

class Blocker:
	extends ColorRect
	func _gui_input(_event: InputEvent) -> void:
		accept_event()

var _rect: Blocker
var _material: ShaderMaterial
var _on_closed: Callable
var _age := 0.0
var _closed := false
var _hold := 0.0
var _audio: Node

## host の下に閉じる層を作って始める。前の画面がまだ出ているフレームで呼ぶ。
static func start(host: Node, on_closed: Callable) -> CanvasLayer:
	var layer: CanvasLayer = load("res://src/bossmaker/visuals/encounter/rbm_screen_close.gd").new()
	layer._on_closed = on_closed
	host.add_child(layer)
	return layer

## 登場演出が始まった時に呼ぶ（黒い幕を外す）。tree の中のすべての閉じる層を外す。
static func release_all(tree: SceneTree) -> void:
	if tree == null:
		return
	for n in tree.get_nodes_in_group(GROUP):
		(n as Node).queue_free()

## 黒い幕を出している層があるか（テスト・検証用）。
static func active_count(tree: SceneTree) -> int:
	return tree.get_nodes_in_group(GROUP).size() if tree != null else 0

func _init() -> void:
	layer = 41
	add_to_group(GROUP)
	_rect = Blocker.new()
	_rect.name = "ScreenCloseRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.focus_mode = Control.FOCUS_ALL
	_rect.size = Vector2(1280, 720)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	add_child(_rect)
	_audio = Audio.new()
	add_child(_audio)

func _ready() -> void:
	_rect.grab_focus()
	_apply()
	_audio.play("enc:crt_off", -3.0)

func _apply() -> void:
	var vp := get_viewport()
	var scale := Vector2.ONE
	if vp != null:
		scale = vp.get_final_transform().get_scale()
	_material.set_shader_parameter("screen_scale", scale)
	_material.set_shader_parameter("closing", clampf(_age / DURATION, 0.0, 1.0))

func _process(delta: float) -> void:
	_audio.advance(delta)
	if not _closed:
		_age += delta
		_apply()
		if _age >= DURATION:
			_closed = true
			if _on_closed.is_valid():
				_on_closed.call()
		return
	_hold += delta
	if _hold >= HOLD_LIMIT:
		queue_free()
