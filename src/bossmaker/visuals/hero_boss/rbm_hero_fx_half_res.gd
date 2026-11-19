class_name RBMHeroFxHalfRes
extends Node
## 爆炎の矩形（blast.gdshader）を、画面の半分の解像度の描画先（SubViewport）で描いて、2倍に拡大して元の層へ重ねる（2026-11-19。性能）。
## blast.gdshader は画面の2×2画素ごとに同じ1点（2×2の中心）の値を出す（hfx_grid、2画素の格子）。半分の解像度の1画素の中心は、
## その2×2の中心と同じ所なので、格子をやめて（grid_px=1）1画素ずつ計算すれば、計算する位置は元と同じ。計算の量は4分の1になる。
## 重ね方: 描画先は透明から、元と同じ premultiplied で塗り重ね、元の層の同じ順番の所に、premultiplied のまま最近傍で2倍に拡大して重ねる。
## 画面への写し方（揺れ・寄り・2倍の論理ドット）は、毎フレームの描画の直前に元の層から読み直す（frame_pre_draw）。
## 矩形そのもの（ColorRect）と、そのシェーダーの値・表示・位置を変えるコードは今までのまま（親が替わるだけ）。

## false にすると、新しく作る矩形は今までどおり元の層へ直接描く（見た目の比較・計測の切り替え用）
static var enabled := true

var quad: ColorRect
var layer: Node2D
var viewport: SubViewport
var display: Sprite2D

## parent に足した矩形 q を、半分の解像度で描く形へ付け替える。enabled が false なら何もしない（null を返す）。
static func wrap(parent: Node, q: ColorRect) -> RBMHeroFxHalfRes:
	if not enabled or not (parent is Node2D):
		return null
	var h := RBMHeroFxHalfRes.new()
	h.name = "HalfRes_" + str(q.get_instance_id())
	h.quad = q
	h.layer = parent
	h.viewport = SubViewport.new()
	h.viewport.transparent_bg = true
	h.viewport.disable_3d = true
	h.viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	h.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	h.viewport.size = Vector2i(2, 2)
	h.add_child(h.viewport)
	# 元の層の、矩形がいた順番の所に、拡大して重ねる絵を置く
	h.display = Sprite2D.new()
	h.display.name = "HalfResDisplay"
	h.display.centered = false
	h.display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	h.display.texture = h.viewport.get_texture()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	h.display.material = m
	h.display.visible = false
	var at := q.get_index()
	parent.add_child(h.display)
	parent.move_child(h.display, at)
	parent.remove_child(q)
	h.viewport.add_child(q)
	(q.material as ShaderMaterial).set_shader_parameter("grid_px", 1.0)
	parent.add_child(h)
	RenderingServer.frame_pre_draw.connect(h._sync)
	return h

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync):
		RenderingServer.frame_pre_draw.disconnect(_sync)

## 描画の直前: 表示の有無と、画面への写し方を元の層から写す
func _sync() -> void:
	if not is_instance_valid(quad) or not is_instance_valid(layer) or not layer.is_inside_tree():
		return
	var on := quad.visible and layer.is_visible_in_tree()
	display.visible = on
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	var vp := layer.get_viewport()
	# 元の層の座標 → 窓の画素（揺れ・寄り・全画面の拡大を含む）
	var t := vp.get_final_transform() * layer.get_global_transform_with_canvas()
	var win := (vp.get_final_transform().basis_xform(vp.get_visible_rect().size)).abs()
	var size := Vector2i(ceili(win.x * 0.5), ceili(win.y * 0.5))
	if viewport.size != size:
		viewport.size = size
	viewport.canvas_transform = Transform2D(0.0, Vector2(0.5, 0.5), 0.0, Vector2.ZERO) * t
	display.transform = t.affine_inverse() * Transform2D(0.0, Vector2(2.0, 2.0), 0.0, Vector2.ZERO)
