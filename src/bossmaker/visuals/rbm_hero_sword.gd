extends Node2D
# Keep the overhead pose's blade proportional to the idle sword.
func _process(_delta: float) -> void:
 visible=get_parent().pose==8
func _draw() -> void:
 draw_colored_polygon(PackedVector2Array([Vector2(384,60),Vector2(396,78),Vector2(396,180),Vector2(372,180),Vector2(372,78)]),Color('#34313b'))
 draw_colored_polygon(PackedVector2Array([Vector2(384,64),Vector2(392,80),Vector2(392,178),Vector2(376,178),Vector2(376,80)]),Color('#a8abb0'))
 draw_rect(Rect2(376,82,8,94),Color('#e8e7df'))
 draw_rect(Rect2(384,76,4,102),Color('#f8f5eb'))
 draw_rect(Rect2(364,178,40,8),Color('#494650'))
 draw_rect(Rect2(368,178,32,4),Color('#bfc1bd'))
