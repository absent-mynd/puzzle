class_name WrapCanvas extends Node2D

## WrapCanvas
##
## A canvas item that paints itself once per copy of the space it stands in.
##
## The wrap is not each drawer's problem. Subclasses override `paint()` and draw
## in ordinary world coordinates, exactly as they would in a world that did not
## repeat; this repeats those commands at every lattice offset. Put a new thing
## in the world — a hand floating beside the body, a marker, a creature — and it
## appears in every band for free, because it never had a say in the matter.
##
## That is the whole design rule. Before this, "repeat across the wrap" was
## written out again in the terrain builder, the player's ghost list, the light
## resolver and the overlay, and anything that forgot (the floating hands did)
## simply vanished from every copy but one. There is now one loop, here.
##
## `offsets` comes from `FoldLattice` and is handed down by `FoldWorld` whenever
## the space changes — a plain array so a subclass never has to know whether it
## is standing in a region, a cylinder or a torus. It always contains ZERO, so a
## flat world costs exactly one pass.
##
## Three hooks, because not everything in the frame belongs to the space:
##
##   - `prepare()` — once, before any copy. Work out WHAT to draw here, so a
##     question that costs something is asked once rather than once per band.
##   - `paint()` — drawn once per copy. Anything that IS somewhere.
##   - `paint_once()` — drawn once, at the origin. Guides that span the world and
##     translucent bands, which repeated would tile the screen and stack their
##     alpha into a wash.

var offsets: Array = [Vector2.ZERO]


## Point this canvas at a new set of copies and redraw. Cheap enough to call on
## every rebuild; the array is small and shared.
func set_offsets(list: Array) -> void:
	offsets = list if not list.is_empty() else [Vector2.ZERO]
	queue_redraw()


func _draw() -> void:
	prepare()
	for off in offsets:
		draw_set_transform(off)
		paint()
	draw_set_transform(Vector2.ZERO)
	paint_once()


## Carry whatever state this canvas holds through a wrap teleport.
##
## Crossing a glue line slides the body back by a whole period, and the camera with
## it, so the rendered frame is unchanged and the crossing is invisible. That only
## holds for things the frame re-derives every time it is drawn. A canvas that
## remembers a world position across frames — a spring, a trail, a hand floating
## beside you — is left standing a period away from the body it belongs to, and
## whatever pulls it home then drags it across the space in full view. So the same
## displacement is offered to every canvas, and one that keeps positions of its own
## overrides this and adds it. Most keep none, and do nothing.
##
## Dispatched over `FoldWorld._wrap_canvases()`, the same list `set_offsets` uses:
## a new canvas is registered once and is handed both.
func carry_through_wrap(_offset: Vector2) -> void:
	pass


## Gather whatever the copies will all draw. Override when a query is worth more
## than the loop that would repeat it.
func prepare() -> void:
	pass


## Draw the contents of one copy of the space. Override this.
func paint() -> void:
	pass


## Draw what belongs to the frame rather than to the space. Override if needed.
func paint_once() -> void:
	pass
