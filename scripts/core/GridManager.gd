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

## Origin point for grid positioning
var grid_origin: Vector2 = Vector2.ZERO

## Preview line for showing connection between anchors
var preview_line: Line2D

## Currently hovered cell
var hovered_cell: Cell = null


## Initialize grid on ready
func _ready() -> void:
	# Set up preview line
	preview_line = Line2D.new()
	preview_line.width = 3.0
	preview_line.default_color = Color.CYAN
	preview_line.visible = false
	add_child(preview_line)

	# Create the grid
	create_grid()
	center_grid_on_screen()


## Create all cells in the 10x10 grid
func create_grid() -> void:
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var grid_pos = Vector2i(x, y)
			var world_pos = grid_to_world(grid_pos)

			var cell = Cell.new(grid_pos, world_pos, cell_size)
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
## @return: Cell at position, or null if out of bounds
func get_cell(grid_pos: Vector2i) -> Cell:
	return cells.get(grid_pos, null)


## Get cell at world position
## @param world_pos: World coordinates
## @return: Cell at position, or null if none found
func get_cell_at_world_pos(world_pos: Vector2) -> Cell:
	# First try simple grid lookup
	var grid_pos = world_to_grid(world_pos)
	var cell = get_cell(grid_pos)

	# For cells that haven't been split, simple lookup works
	if cell and cell.contains_point(world_pos):
		return cell

	# For partial cells, check all cells for containment
	# (This becomes important after folding splits cells)
	for c in cells.values():
		if c.contains_point(world_pos):
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
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_pos = get_global_mouse_position()
			var cell = get_cell_at_world_pos(world_pos)
			if cell:
				select_cell(cell.grid_position)

	elif event is InputEventMouseMotion:
		var world_pos = get_global_mouse_position()
		update_hover_feedback(world_pos)


## Select a cell as an anchor point
## @param grid_pos: Grid position of cell to select
func select_cell(grid_pos: Vector2i) -> void:
	# Clear hover effects
	clear_all_hover_effects()

	# Handle selection based on count
	if selected_anchors.size() == 0:
		# First anchor - red outline
		selected_anchors.append(grid_pos)
		var cell = get_cell(grid_pos)
		if cell:
			cell.set_outline_color(Color.RED)

	elif selected_anchors.size() == 1:
		# Second anchor - blue outline
		selected_anchors.append(grid_pos)
		var cell = get_cell(grid_pos)
		if cell:
			cell.set_outline_color(Color.BLUE)
		update_preview_line()

	else:
		# Third click - reset and start over
		clear_selection()
		selected_anchors.append(grid_pos)
		var cell = get_cell(grid_pos)
		if cell:
			cell.set_outline_color(Color.RED)


## Clear anchor selection
func clear_selection() -> void:
	# Clear outlines from selected cells
	for anchor_pos in selected_anchors:
		var cell = get_cell(anchor_pos)
		if cell:
			cell.clear_visual_feedback()

	selected_anchors.clear()
	if preview_line:
		preview_line.visible = false


## Get selected anchor positions
## @return: Array of selected anchor grid positions
func get_selected_anchors() -> Array[Vector2i]:
	return selected_anchors


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
			var pos1 = cell1.get_center()
			var pos2 = cell2.get_center()

			# Convert to local coordinates
			pos1 = to_local(pos1)
			pos2 = to_local(pos2)

			preview_line.points = PackedVector2Array([pos1, pos2])
			preview_line.visible = true
	else:
		preview_line.visible = false


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
