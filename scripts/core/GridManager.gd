## Space-Folding Puzzle Game - GridManager Class
##
## Manages the 10x10 grid of cells, handles cell creation, provides grid queries,
## and manages the anchor selection system.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0

extends Node2D
class_name GridManager

## Properties

## Grid dimensions (10x10)
var grid_size := Vector2i(10, 10)

## Size of each cell in pixels
var cell_size := 64.0

## Dictionary mapping grid positions to Cell instances
## Key: Vector2i (grid position), Value: Cell
var cells: Dictionary = {}

## Selected anchor cells for folding (max 2)
var selected_anchors: Array[Vector2i] = []

## Base-space (unfolded) point each selected anchor is pinned to (parallel to
## selected_anchors). Vector2.INF = ambiguous (placed on a seam) -> the anchor
## disappears on the next geometry change. The anchor's current position is DERIVED by
## transforming this point forward through the fold list (see reresolve_anchors), the
## same way crease dots are positioned — stable, and hidden if the point gets excised.
var selected_anchor_points: Array[Vector2] = []

## Origin point for grid positioning
var grid_origin: Vector2 = Vector2.ZERO

## Preview line for showing connection between anchors
var preview_line: Line2D

## PHASE 8: Region-preview visuals shown when 2 anchors are selected
var preview_cut_line1: Line2D      # First fold-region border
var preview_cut_line2: Line2D      # Second fold-region border
var preview_region_fill: Polygon2D # Shaded region between the borders

## Currently hovered cell
var hovered_cell: Cell = null

## Reference to the fold controller for validation, preview, and undo history.
var fold_system: FoldController = null

## PHASE 8: Reference to the active InteractionConfig (set externally by MainScene)
## Governs Axis D (null-anchor eligibility). May be null in tests / debug.
var interaction_config: InteractionConfig = null

## PHASE 8: Guards against overlapping player-flash restores (see _flash_player_red)
var _player_flash_active: bool = false


## Initialize grid on ready
func _ready() -> void:
	# Set up preview line (Issue #9: increased width for better visibility)
	# PHASE 8: All preview visuals are created before the cells (added in create_grid),
	# so a high z_index is required for them to draw ON TOP of the map rather than behind
	# it. Cell contents top out at z_index 3 (the highlight dot).
	const PREVIEW_FILL_Z := 10
	const PREVIEW_LINE_Z := 11

	preview_line = Line2D.new()
	preview_line.width = 5.0  # Increased from 3.0 for better visibility
	preview_line.default_color = Color.CYAN
	preview_line.visible = false
	preview_line.z_index = PREVIEW_LINE_Z
	add_child(preview_line)

	# PHASE 8: Region-preview visuals (two border lines + shaded fill between them)
	preview_region_fill = Polygon2D.new()
	preview_region_fill.color = Color(1.0, 0.5, 0.0, 0.15)
	preview_region_fill.visible = false
	preview_region_fill.z_index = PREVIEW_FILL_Z
	add_child(preview_region_fill)

	preview_cut_line1 = Line2D.new()
	preview_cut_line1.width = 3.0
	preview_cut_line1.default_color = Color.GREEN
	preview_cut_line1.visible = false
	preview_cut_line1.z_index = PREVIEW_LINE_Z
	add_child(preview_cut_line1)

	preview_cut_line2 = Line2D.new()
	preview_cut_line2.width = 3.0
	preview_cut_line2.default_color = Color.GREEN
	preview_cut_line2.visible = false
	preview_cut_line2.z_index = PREVIEW_LINE_Z
	add_child(preview_cut_line2)

	# Create the grid
	create_grid()
	center_grid_on_screen()


## Create all cells in the 10x10 grid
func create_grid() -> void:
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var grid_pos = Vector2i(x, y)
			# Use local position (relative to GridManager) not absolute world position
			# since cells are children of GridManager and GridManager.position = grid_origin
			var local_pos = Vector2(grid_pos) * cell_size

			var cell = Cell.new(grid_pos, local_pos, cell_size)
			cells[grid_pos] = cell
			add_child(cell)


## Center the grid on the screen
func center_grid_on_screen() -> void:
	var viewport_size = get_viewport_rect().size
	var grid_pixel_size = Vector2(grid_size) * cell_size
	grid_origin = (viewport_size - grid_pixel_size) / 2
	position = grid_origin


## Query Methods

## Get cell at grid position
## @param grid_pos: Grid coordinates
## @return: Cell at position, or null if out of bounds or cell has been freed
func get_cell(grid_pos: Vector2i) -> Cell:
	var cell = cells.get(grid_pos, null)

	# Validate cell hasn't been freed
	if cell and not is_instance_valid(cell):
		# Cell has been freed - remove from dictionary
		cells.erase(grid_pos)
		return null

	return cell


## Get cell at world position
## @param world_pos: World coordinates (global)
## @return: Cell at position, or null if none found
func get_cell_at_world_pos(world_pos: Vector2) -> Cell:
	# Convert global world position to local coordinates (relative to GridManager)
	var local_pos = to_local(world_pos)

	# First try simple grid lookup
	var grid_pos = world_to_grid(world_pos)
	var cell = get_cell(grid_pos)

	# For cells that haven't been split, simple lookup works
	if cell and cell.contains_point(local_pos):
		return cell

	# For partial cells, check all cells for containment
	# (This becomes important after folding splits cells)
	for c in cells.values():
		# Skip freed cells
		if not is_instance_valid(c):
			continue
		if c.contains_point(local_pos):
			return c

	return null


## Check if grid position is valid
## @param grid_pos: Grid coordinates to check
## @return: true if position is within grid bounds
func is_valid_position(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_size.x and \
		   grid_pos.y >= 0 and grid_pos.y < grid_size.y


## Get adjacent cells (up, down, left, right)
## @param grid_pos: Grid coordinates
## @return: Array of neighboring cells
func get_neighbors(grid_pos: Vector2i) -> Array[Cell]:
	var neighbors: Array[Cell] = []

	# Check all four directions
	var directions = [
		Vector2i(0, -1),  # Up
		Vector2i(0, 1),   # Down
		Vector2i(-1, 0),  # Left
		Vector2i(1, 0)    # Right
	]

	for dir in directions:
		var neighbor_pos = grid_pos + dir
		if is_valid_position(neighbor_pos):
			var neighbor = get_cell(neighbor_pos)
			if neighbor:
				neighbors.append(neighbor)

	return neighbors


## Grid Utility Methods

## Convert world coordinates to grid coordinates
## @param world_pos: World position
## @return: Grid coordinates
func world_to_grid(world_pos: Vector2) -> Vector2i:
	var local_pos = world_pos - grid_origin
	return Vector2i(
		int(local_pos.x / cell_size),
		int(local_pos.y / cell_size)
	)


## Convert grid coordinates to world coordinates
## @param grid_pos: Grid coordinates
## @return: World position (top-left corner of cell)
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return grid_origin + Vector2(grid_pos) * cell_size


## Get bounding rectangle of entire grid
## @return: Rect2 encompassing the entire grid
func get_grid_bounds() -> Rect2:
	return Rect2(
		grid_origin,
		Vector2(grid_size) * cell_size
	)


## Anchor Selection Methods (for Issue 6)

## Handle input for cell selection and hover
## Using _input() instead of _unhandled_input() to ensure mouse events are received
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_pos = get_global_mouse_position()
			var cell = get_cell_at_world_pos(world_pos)
			if cell:
				# Pass the precise click point so the anchor pins to the right seam side.
				select_cell(cell.grid_position, to_local(world_pos))
				get_viewport().set_input_as_handled()  # Mark input as handled

	elif event is InputEventMouseMotion:
		var world_pos = get_global_mouse_position()
		update_hover_feedback(world_pos)


## Select a cell as an anchor point
##
## PHASE 8: Applies anchor-eligibility and fold-validity guards (shared by the mouse
## debug flow and the player facing-interact flow). Rejected placements are NOT added.
##
## @param grid_pos: Grid position of cell to select
## @param point: Optional sub-cell LOCAL point that decides which tile/side the anchor
##               pins to (mouse: click point; facing: a point biased toward the player).
##               Defaults to the cell center. Determines the anchor's base-tile identity.
## @return: true if the anchor was placed, false if it was rejected
func select_cell(grid_pos: Vector2i, point: Vector2 = Vector2.INF) -> bool:
	# Clear hover effects
	clear_all_hover_effects()

	if point == Vector2.INF:
		point = Vector2(grid_pos) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)

	# Third selection resets and starts a new first anchor
	if selected_anchors.size() >= 2:
		clear_selection()

	if selected_anchors.size() == 0:
		# First anchor - eligibility only (a lone anchor defines no fold yet)
		if not is_anchor_eligible(grid_pos):
			_reject_anchor(grid_pos)
			return false
		AudioManager.play_sfx("selection")
		selected_anchors.append(grid_pos)
		selected_anchor_points.append(_anchor_base_point(point))
		var cell = get_cell(grid_pos)
		if cell:
			cell.set_outline_color(Color.RED)
		# Placing an anchor is an undoable input (Baba-style history).
		if fold_system:
			fold_system.commit_input()
		return true

	else:
		# Second anchor - eligibility AND fold validity (geometry + player)
		var anchor1 = selected_anchors[0]
		if not is_anchor_eligible(grid_pos):
			_show_rejected_fold_preview(anchor1, grid_pos, "null")
			return false
		if fold_system:
			var geo: Dictionary = fold_system.validate_fold(anchor1, grid_pos)
			if not geo.valid:
				_show_rejected_fold_preview(anchor1, grid_pos, "geometry")
				return false
			# Player-position validation is ALWAYS deferred to commit now: the player may place
			# anchors and move freely (anchors ride their tiles). The player check + red flash
			# happen in flash_invalid_fold() on commit.

		AudioManager.play_sfx("selection")
		selected_anchors.append(grid_pos)
		selected_anchor_points.append(_anchor_base_point(point))
		var cell = get_cell(grid_pos)
		if cell:
			cell.set_outline_color(Color.BLUE)
		update_preview_line()
		# Placing the second anchor is an undoable input.
		if fold_system:
			fold_system.commit_input()
		return true


## Check whether a cell may be used as a fold anchor, per Axis D (null eligibility)
##
## @param grid_pos: Grid position to test
## @return: true if the cell exists and satisfies the active null-anchor rule
func is_anchor_eligible(grid_pos: Vector2i) -> bool:
	var cell = get_cell(grid_pos)
	if not cell:
		return false

	# Reject tiles whose type explicitly disallows anchor placement.
	var dominant_type: int
	var fs_state: FoldedState = fold_system.get_state() if fold_system else null
	if fs_state:
		dominant_type = fs_state.dominant_type_at(grid_pos)
	else:
		dominant_type = cell.get_dominant_type()
	if TileTypes.blocks_anchor(dominant_type):
		return false

	var mode := InteractionConfig.NullAnchor.CENTROID_IN_NULL
	if interaction_config:
		mode = interaction_config.null_anchor

	match mode:
		InteractionConfig.NullAnchor.OFF:
			return true
		InteractionConfig.NullAnchor.CENTROID_IN_NULL:
			return not cell.is_centroid_in_null()
		InteractionConfig.NullAnchor.ANY_NULL_PIECE:
			return not cell.has_null_piece()
		_:
			return true


## Show the invalid-region feedback for a fold that failed at COMMIT time.
##
## Used when player-position validation was deferred (ALLOW_MOVEMENT) and the fold turns
## out to be invalid when committed. Determines the reason and flashes the red region +
## offending feature; the selection is kept so the player can adjust and retry.
##
## @param anchor1: First anchor
## @param anchor2: Second anchor
func flash_invalid_fold(anchor1: Vector2i, anchor2: Vector2i) -> void:
	var reason := "geometry"
	var blocking := Vector2i(-1, -1)
	if fold_system:
		var pl: Dictionary = fold_system.validate_fold_with_player(anchor1, anchor2)
		if fold_system.validate_fold(anchor1, anchor2).valid and not pl.valid:
			reason = "player"
			blocking = pl.get("blocking_pos", Vector2i(-1, -1))
	_show_rejected_fold_preview(anchor1, anchor2, reason, blocking)


## Current player grid position (via the fold controller), or a sentinel if unknown.
func _player_grid_pos() -> Vector2i:
	if fold_system and fold_system.player:
		return fold_system.player.grid_position
	return Vector2i(-9999, -9999)


## Reject a first-anchor placement: error feedback + brief red flash on the cell dot
func _reject_anchor(grid_pos: Vector2i) -> void:
	AudioManager.play_sfx("error")
	_flash_cell_dot(grid_pos, Color.RED)


## Show a temporary red "this fold was rejected" preview and flash the offending feature
##
## @param anchor1: The already-placed first anchor
## @param bad_pos: The rejected second-anchor position
## @param reason: "null", "geometry", or "player" (drives which feature is flashed)
## @param blocking_pos: for "player" rejections, the tile the player would have landed
##                      on (a wall/void) — flashed alongside the player. Vector2i(-1,-1)
##                      when the player is simply inside the fold region.
func _show_rejected_fold_preview(anchor1: Vector2i, bad_pos: Vector2i, reason: String,
		blocking_pos: Vector2i = Vector2i(-1, -1)) -> void:
	AudioManager.play_sfx("error")
	_draw_region_preview(anchor1, bad_pos, Color.RED, Color(1.0, 0.0, 0.0, 0.18))

	# Highlight the offending feature
	match reason:
		"null":
			_flash_cell_dot(bad_pos, Color.RED)
		"player":
			_flash_player_red()
			# Also flash the tile that blocked the player's landing, when applicable.
			if blocking_pos != Vector2i(-1, -1) and blocking_pos != _player_grid_pos():
				_flash_cell_dot(blocking_pos, Color.RED)
		_:
			_flash_cell_dot(bad_pos, Color.RED)

	# Auto-clear the red preview after a short delay. If both anchors are still selected
	# (a deferred commit-time rejection), revert to the normal validity-coloured preview;
	# otherwise hide it.
	var timer := get_tree().create_timer(0.6)
	timer.timeout.connect(func():
		if selected_anchors.size() == 2:
			update_preview_line()
		else:
			_hide_region_preview())


## Briefly flash a cell's highlight dot a given color, then restore it
func _flash_cell_dot(grid_pos: Vector2i, color: Color) -> void:
	var cell = get_cell(grid_pos)
	if not cell:
		return
	cell.set_outline_color(color)
	var timer := get_tree().create_timer(0.6)
	timer.timeout.connect(func():
		if is_instance_valid(cell) and grid_pos not in selected_anchors:
			cell.clear_visual_feedback())


## Briefly flash the player's sprite red to indicate it blocked the fold
##
## Guarded so overlapping rejections don't capture the RED flash as the "original"
## color (which would leave the sprite stuck red).
func _flash_player_red() -> void:
	if not fold_system or _player_flash_active:
		return
	var player: Player = fold_system.player
	if not player or not is_instance_valid(player) or not player.sprite:
		return
	_player_flash_active = true
	var original: Color = player.sprite.color
	player.sprite.color = Color.RED
	var timer := get_tree().create_timer(0.6)
	timer.timeout.connect(func():
		if is_instance_valid(player) and player.sprite:
			player.sprite.color = original
		_player_flash_active = false)


## Clear anchor selection
func clear_selection() -> void:
	# Clear outlines from selected cells
	for anchor_pos in selected_anchors:
		var cell = get_cell(anchor_pos)
		if cell:
			cell.clear_visual_feedback()

	selected_anchors.clear()
	selected_anchor_points.clear()
	if preview_line:
		preview_line.visible = false
	_hide_region_preview()


## Remove only the most recently placed anchor (keeps earlier anchors)
func deselect_last_anchor() -> void:
	if selected_anchors.is_empty():
		return
	var last = selected_anchors[selected_anchors.size() - 1]
	var cell = get_cell(last)
	if cell:
		cell.clear_visual_feedback()
	selected_anchors.remove_at(selected_anchors.size() - 1)
	if not selected_anchor_points.is_empty():
		selected_anchor_points.remove_at(selected_anchor_points.size() - 1)
	if preview_line:
		preview_line.visible = false
	_hide_region_preview()


## Get selected anchor positions
## @return: Array of selected anchor grid positions
func get_selected_anchors() -> Array[Vector2i]:
	return selected_anchors


## Restore an exact anchor selection (positions + base-tile identities) without
## validation or history side-effects. Used by undo to reinstate a snapshot.
##
## @param anchors: Array of Vector2i anchor positions (0, 1, or 2 entries)
## @param bases: parallel Array of base_ids (defaults to empty -> unknown/-1)
func set_selection(anchors: Array, points: Array = []) -> void:
	# Clear current highlights first.
	for anchor_pos in selected_anchors:
		var c = get_cell(anchor_pos)
		if c:
			c.clear_visual_feedback()
	selected_anchors.clear()
	selected_anchor_points.clear()
	if preview_line:
		preview_line.visible = false
	_hide_region_preview()

	# Reinstate highlights: first anchor RED, second BLUE.
	for i in range(anchors.size()):
		var pos: Vector2i = anchors[i]
		selected_anchors.append(pos)
		selected_anchor_points.append(points[i] if i < points.size() else Vector2.INF)
		var cell = get_cell(pos)
		if cell:
			cell.set_outline_color(Color.RED if i == 0 else Color.BLUE)
	if selected_anchors.size() == 2:
		update_preview_line()


## Base-space (unfolded) point the anchor pins to (delegates to the fold controller).
## Vector2.INF if ambiguous (on a seam / void).
func _anchor_base_point(point: Vector2) -> Vector2:
	if fold_system and fold_system.has_method("base_point_at"):
		return fold_system.base_point_at(point)
	return Vector2.INF


## Re-resolve placed anchors to their tiles' current positions after a geometry change
## (e.g. an unfold). Each anchor's base-space point is transformed forward through the
## current fold list; an anchor whose point is now hidden/excised (INF) disappears.
func reresolve_anchors() -> void:
	if selected_anchors.is_empty() or fold_system == null:
		return

	var new_anchors: Array[Vector2i] = []
	var new_points: Array[Vector2] = []
	for i in range(selected_anchors.size()):
		var bp: Vector2 = selected_anchor_points[i] if i < selected_anchor_points.size() else Vector2.INF
		var cur: Vector2 = fold_system.forward_point(bp)
		if cur == Vector2.INF:
			continue  # ambiguous -> the anchor disappears
		var cell := Vector2i(int(floor(cur.x / cell_size)), int(floor(cur.y / cell_size)))
		# Hidden if the derived cell's center rests in a void (not real ground).
		if not fold_system.cell_center_covered(cell):
			continue
		new_anchors.append(cell)
		new_points.append(bp)

	# Rebuild highlights + preview from the surviving anchors.
	set_selection(new_anchors, new_points)


## Update hover feedback for mouse position
## @param world_pos: Current mouse world position
func update_hover_feedback(world_pos: Vector2) -> void:
	var cell = get_cell_at_world_pos(world_pos)

	# Clear previous hover
	if hovered_cell and hovered_cell != cell:
		hovered_cell.set_hover_highlight(false)

	# Set new hover
	hovered_cell = cell
	if hovered_cell:
		hovered_cell.set_hover_highlight(true)


## Clear hover effects from all cells
func clear_all_hover_effects() -> void:
	if hovered_cell:
		hovered_cell.set_hover_highlight(false)
		hovered_cell = null


## Update preview line between anchors
func update_preview_line() -> void:
	if not preview_line:
		return

	if selected_anchors.size() == 2:
		var cell1 = get_cell(selected_anchors[0])
		var cell2 = get_cell(selected_anchors[1])

		if cell1 and cell2:
			# Cell centers are already in GridManager's local coordinate space
			# (since cell geometry is relative to GridManager)
			var pos1 = cell1.get_center()
			var pos2 = cell2.get_center()

			preview_line.points = PackedVector2Array([pos1, pos2])

			# Update color based on fold validation (Issue #9)
			if fold_system:
				var validation = fold_system.validate_fold(selected_anchors[0], selected_anchors[1])
				if validation.valid:
					preview_line.default_color = Color.GREEN  # Valid fold
				else:
					preview_line.default_color = Color.RED  # Invalid fold
			else:
				preview_line.default_color = Color.CYAN  # Default if no fold_system

			preview_line.visible = true

			# PHASE 8: Also draw the fold-region border lines + shaded fill
			var region_valid := true
			if fold_system:
				region_valid = fold_system.validate_fold(selected_anchors[0], selected_anchors[1]).valid
			var border_color := Color.GREEN if region_valid else Color.RED
			var fill_color := Color(0.0, 1.0, 0.0, 0.13) if region_valid else Color(1.0, 0.0, 0.0, 0.15)
			_draw_region_preview(selected_anchors[0], selected_anchors[1], border_color, fill_color)
	else:
		preview_line.visible = false


## Draw the fold-region preview: two border lines + shaded fill between them
##
## Reused for both the normal (green) selection preview and the red rejection preview.
## Skips degenerate cases (same anchor). Geometry uses NOMINAL cell centers to match
## FoldSystem's cut-line math (cell centers can drift after prior folds).
##
## @param anchor1: First anchor grid position
## @param anchor2: Second anchor grid position
## @param border_color: Color for the two border lines
## @param fill_color: Color (with alpha) for the shaded region
func _draw_region_preview(anchor1: Vector2i, anchor2: Vector2i, border_color: Color, fill_color: Color) -> void:
	if not fold_system or anchor1 == anchor2:
		_hide_region_preview()
		return

	var half := Vector2(cell_size / 2.0, cell_size / 2.0)
	var a1_local := Vector2(anchor1) * cell_size + half
	var a2_local := Vector2(anchor2) * cell_size + half

	var cut = fold_system.calculate_cut_lines(a1_local, a2_local)

	# Direction along each (parallel) cut line = perpendicular to the shared normal
	var normal: Vector2 = cut.line1.normal
	var dir := Vector2(-normal.y, normal.x)
	var span := Vector2(grid_size).length() * cell_size

	var l1_start: Vector2 = cut.line1.point - dir * span
	var l1_end: Vector2 = cut.line1.point + dir * span
	var l2_start: Vector2 = cut.line2.point - dir * span
	var l2_end: Vector2 = cut.line2.point + dir * span

	preview_cut_line1.points = PackedVector2Array([l1_start, l1_end])
	preview_cut_line1.default_color = border_color
	preview_cut_line1.visible = true

	preview_cut_line2.points = PackedVector2Array([l2_start, l2_end])
	preview_cut_line2.default_color = border_color
	preview_cut_line2.visible = true

	# Quad spanning the strip between the two parallel borders
	preview_region_fill.polygon = PackedVector2Array([l1_start, l1_end, l2_end, l2_start])
	preview_region_fill.color = fill_color
	preview_region_fill.visible = true


## Animate the region preview closing to follow a MEET-IN-THE-MIDDLE fold: both crease
## border lines and the shaded fill sweep inward onto the meeting line over `duration`.
## Called by FoldController during an animated fold; the caller hides the preview
## afterwards (via clear_selection).
##
## @param crease1: LOCAL point on anchor_a's crease
## @param crease2: LOCAL point on anchor_b's crease
## @param meeting_point: LOCAL point on the line where the two halves meet
## @param normal: shared crease normal (anchor_a -> anchor_b)
## @param duration: seconds
func animate_region_close(crease1: Vector2, crease2: Vector2, meeting_point: Vector2, normal: Vector2, duration: float) -> void:
	var dir := Vector2(-normal.y, normal.x)
	var span := Vector2(grid_size).length() * cell_size
	var c1a := crease1 - dir * span
	var c1b := crease1 + dir * span
	var c2a := crease2 - dir * span
	var c2b := crease2 + dir * span
	var ma := meeting_point - dir * span
	var mb := meeting_point + dir * span

	preview_cut_line1.visible = true
	preview_cut_line2.visible = true
	preview_region_fill.visible = true

	var setter := func(t: float):
		var a1 := c1a.lerp(ma, t)
		var b1 := c1b.lerp(mb, t)
		var a2 := c2a.lerp(ma, t)
		var b2 := c2b.lerp(mb, t)
		if is_instance_valid(preview_cut_line1):
			preview_cut_line1.points = PackedVector2Array([a1, b1])
		if is_instance_valid(preview_cut_line2):
			preview_cut_line2.points = PackedVector2Array([a2, b2])
		if is_instance_valid(preview_region_fill):
			preview_region_fill.polygon = PackedVector2Array([a1, b1, b2, a2])
	var tw := create_tween()
	tw.tween_method(setter, 0.0, 1.0, duration)


## Hide all region-preview visuals
func _hide_region_preview() -> void:
	if preview_cut_line1:
		preview_cut_line1.visible = false
	if preview_cut_line2:
		preview_cut_line2.visible = false
	if preview_region_fill:
		preview_region_fill.visible = false


## Debug and Visualization Methods

## Optional: Set up test walls (for testing purposes)
func setup_test_walls() -> void:
	# Create border walls
	for x in range(grid_size.x):
		var top_cell = get_cell(Vector2i(x, 0))
		if top_cell:
			top_cell.set_cell_type(1)

		var bottom_cell = get_cell(Vector2i(x, grid_size.y - 1))
		if bottom_cell:
			bottom_cell.set_cell_type(1)

	for y in range(grid_size.y):
		var left_cell = get_cell(Vector2i(0, y))
		if left_cell:
			left_cell.set_cell_type(1)

		var right_cell = get_cell(Vector2i(grid_size.x - 1, y))
		if right_cell:
			right_cell.set_cell_type(1)


## Set a cell as the goal cell
## @param grid_pos: Grid position to set as goal
## @return: true if successful, false if cell doesn't exist
func set_goal_cell(grid_pos: Vector2i) -> bool:
	var cell = get_cell(grid_pos)
	if cell:
		cell.set_cell_type(3)  # Goal type
		return true
	return false


## DERIVE/REPLAY: Reconcile the view cells to match a derived FoldedState.
##
## The `cells` dictionary becomes a VIEW CACHE (not the source of truth): for every
## occupied plane position, ensure a Cell node exists and render the derived pieces
## into it; free view cells at positions that are now empty. After this call all the
## usual consumers (get_cell / Player collision / rendering / hit-testing) see the
## folded configuration.
##
## @param state: FoldedState produced by FoldReplay.derive()
func refresh_from_state(state: FoldedState) -> void:
	# 1. Ensure/update a view cell at every occupied position.
	var occupied := {}
	for pos in state.stacks.keys():
		if not state.is_occupied(pos):
			continue
		occupied[pos] = true
		var cell = get_cell(pos)
		if not cell:
			cell = Cell.new(pos, Vector2(pos) * cell_size, cell_size)
			cells[pos] = cell
			add_child(cell)
		cell.apply_folded_pieces(state.surface_pieces_at(pos))

	# 2. Free view cells at positions that are no longer occupied.
	var stale: Array = []
	for pos in cells.keys():
		if not occupied.has(pos):
			stale.append(pos)
	for pos in stale:
		var cell = cells[pos]
		cells.erase(pos)
		if is_instance_valid(cell):
			if cell.get_parent():
				cell.get_parent().remove_child(cell)
			cell.queue_free()


## Clean up freed cell references from the dictionary
## Call this after fold operations to ensure dictionary integrity
func cleanup_freed_cells() -> int:
	var freed_count = 0
	var positions_to_remove = []

	# Find all positions with freed cells
	for pos in cells.keys():
		var cell = cells[pos]
		if not is_instance_valid(cell):
			positions_to_remove.append(pos)
			freed_count += 1

	# Remove them from dictionary
	for pos in positions_to_remove:
		cells.erase(pos)

	if freed_count > 0:
		push_warning("GridManager: Cleaned up %d freed cell references" % freed_count)

	return freed_count
