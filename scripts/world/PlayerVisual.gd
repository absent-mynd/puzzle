class_name PlayerVisual extends WrapCanvas

## PlayerVisual
##
## The blob, drawn wherever the space says the body is.
##
## Outside a fold that is one place. Inside one, the strip is a cylinder and you
## are one point on it, so you are in every band at once — and inside a fold
## inside a perpendicular fold it is a torus, so you are in every band both ways.
## None of which this file knows: it paints the body once, and `WrapCanvas`
## repeats it wherever the lattice says there is another copy of here.
##
## That replaces a hand-managed list of ghost `Polygon2D`s that had to be created
## on every rebuild, positioned every frame, and kept off the copy the real body
## was in. The body is not special; it is just another thing standing in a space
## that repeats.

var player: PlayerBody


func _process(_delta: float) -> void:
	queue_redraw()


func paint() -> void:
	if player == null:
		return
	var at := player.global_position
	var squash := player.visual_squash()
	var col := player.visual_color()
	var pts := PackedVector2Array()
	for v in player.visual_outline():
		pts.append(at + Vector2(v) * squash)
	if pts.size() >= 3:
		draw_colored_polygon(pts, col)
