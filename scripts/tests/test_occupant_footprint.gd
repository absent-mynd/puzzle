## Occupant footprint accessor tests (collision engine, Stage 2)
##
## The footprint is the occupant's current geometry (the polygons of the base-tile
## fragments it rides). A whole occupant on a full tile is a full square; once a fold
## cuts its tile, its footprint is the surviving flap (smaller). No behavior change yet
## — this just exposes the geometry the swept-collision gate (Stage 3) will use.

extends GutTest

const CELL := 64.0


func _engine(start: Vector2i, cells := {}, grid := Vector2i(10, 10)) -> FoldEngine:
	var ld := LevelData.new()
	ld.grid_size = grid
	ld.cell_size = CELL
	ld.cell_data = cells
	var e := FoldEngine.new()
	e.load_base(BaseGrid.from_level_data(ld))
	e.set_player_start(start)
	return e


func _total_area(polys: Array) -> float:
	var a := 0.0
	for p in polys:
		a += GeometryCore.polygon_area(p)
	return a


func test_whole_player_footprint_is_a_full_square():
	var e := _engine(Vector2i(4, 5))
	var fp := e.player_footprint()
	assert_eq(fp.size(), 1, "one polygon for a whole, unsplit player")
	assert_almost_eq(_total_area(fp), CELL * CELL, 1.0, "footprint area is a full cell")


func test_player_footprint_after_fold_ride_still_full():
	# Player on the B-flap rides inward but keeps a full cell — footprint stays full.
	var e := _engine(Vector2i(8, 5))
	e.apply_fold(Vector2i(2, 5), Vector2i(5, 5))
	assert_almost_eq(_total_area(e.player_footprint()), CELL * CELL, 1.0,
		"a body that only rode (not cut) keeps a full footprint")


func test_cut_player_footprint_is_the_flap():
	# Player on anchor_a is cut by the fold: its footprint is the surviving flap (< cell).
	var e := _engine(Vector2i(2, 5), {Vector2i(5, 5): 1})  # wall at anchor_b
	e.apply_fold(Vector2i(2, 5), Vector2i(5, 5))
	var area := _total_area(e.player_footprint())
	assert_lt(area, CELL * CELL - 1.0, "a cut body's footprint is smaller than a full cell")
	assert_gt(area, 0.0, "but non-empty (the flap survives)")


func test_box_footprint_exposed():
	var e := _engine(Vector2i(0, 0), {Vector2i(2, 1): {"type": 0, "occupant": "box"}})
	var boxes := e.occupant_footprints(StepReplay.KIND_BOX)
	assert_eq(boxes.size(), 1, "one box occupant")
	assert_almost_eq(_total_area(boxes[0]["polys"]), CELL * CELL, 1.0, "box is a full square")
