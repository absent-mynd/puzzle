## Space-Folding Puzzle Game - GridManager Class
##
## Manages the 10x10 grid of cells, handles cell creation, provides grid queries,
## and manages the anchor selection system.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0

extends Node2D
class_name GridManager

## Grid dimensions (10x10)
var grid_size := Vector2i(10, 10)

## Size of each cell in pixels
var cell_size := 64.0

## Dictionary of all cells (Vector2i -> Cell)
var cells: Dictionary = {}

## Currently selected anchors for folding
var selected_anchors: Array[Vector2i] = []

## Grid origin in world space
var grid_origin: Vector2 = Vector2.ZERO

## Preview line between selected anchors
var preview_line: Line2D

## Currently hovered cell (for visual feedback)
var hovered_cell: Cell = null


## Initialize grid when added to scene
func _ready():
	setup_preview_line()
	create_grid()
	center_grid_on_screen()


## Set up the preview line for anchor selection
func setup_preview_line():
	preview_line = Line2D.new()
	preview_line.width = 3.0
	preview_line.default_color = Color.CYAN
	preview_line.visible = false
	preview_line.z_index = 100  # Draw on top of cells
	add_child(preview_line)


## Create the 10x10 grid of cells
func create_grid():
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var grid_pos = Vector2i(x, y)
			var world_pos = grid_to_world_local(grid_pos)

			var cell = Cell.new(grid_pos, world_pos, cell_size)
			cells[grid_pos] = cell
			add_child(cell)


## Center the grid on the screen
func center_grid_on_screen():
	var viewport_size = get_viewport_rect().size
	var grid_pixel_size = Vector2(grid_size) * cell_size
	grid_origin = (viewport_size - grid_pixel_size) / 2
	position = grid_origin


## Get cell at grid position
func get_cell(grid_pos: Vector2i) -> Cell:
	return cells.get(grid_pos)


## Get cell at world position
func get_cell_at_world_pos(world_pos: Vector2) -> Cell:
	# First try simple grid lookup
	var grid_pos = world_to_grid(world_pos)
	if is_valid_position(grid_pos):
		var cell = get_cell(grid_pos)
		if cell and cell.contains_point(world_pos):
			return cell

	# For partial cells, check all cells (slower but handles split cells)
	for cell in cells.values():
		if cell.contains_point(world_pos):
			return cell

	return null


## Check if grid position is valid
func is_valid_position(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.x < grid_size.x and \
		   grid_pos.y >= 0 and grid_pos.y < grid_size.y


## Get neighboring cells (up, down, left, right)
func get_neighbors(grid_pos: Vector2i) -> Array[Cell]:
	var neighbors: Array[Cell] = []
	var offsets = [
		Vector2i(0, -1),  # Up
		Vector2i(0, 1),   # Down
		Vector2i(-1, 0),  # Left
		Vector2i(1, 0)    # Right
	]

	for offset in offsets:
		var neighbor_pos = grid_pos + offset
		if is_valid_position(neighbor_pos):
			var neighbor = get_cell(neighbor_pos)
			if neighbor:
				neighbors.append(neighbor)

	return neighbors


## Convert world coordinates to grid coordinates
func world_to_grid(world_pos: Vector2) -> Vector2i:
	var local_pos = world_pos - grid_origin
	return Vector2i(
		int(local_pos.x / cell_size),
		int(local_pos.y / cell_size)
	)


## Convert grid coordinates to world coordinates (top-left corner)
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return grid_origin + Vector2(grid_pos) * cell_size


## Convert grid coordinates to local coordinates (relative to GridManager)
func grid_to_world_local(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos) * cell_size


## Get bounding rectangle of entire grid
func get_grid_bounds() -> Rect2:
	return Rect2(grid_origin, Vector2(grid_size) * cell_size)


## Handle input for anchor selection
func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var world_pos = get_global_mouse_position()
			var cell = get_cell_at_world_pos(world_pos)
			if cell:
				select_cell(cell.grid_position)

	elif event is InputEventMouseMotion:
		var world_pos = get_global_mouse_position()
		update_hover_feedback(world_pos)


## Select a cell as an anchor
func select_cell(grid_pos: Vector2i):
	if not is_valid_position(grid_pos):
		return

	# Clear hover effect
	clear_all_hover_effects()

	# Handle selection based on count
	if selected_anchors.size() == 0:
		# First anchor - red
		selected_anchors.append(grid_pos)
		get_cell(grid_pos).set_outline_color(Color.RED)

	elif selected_anchors.size() == 1:
		# Second anchor - blue
		selected_anchors.append(grid_pos)
		get_cell(grid_pos).set_outline_color(Color.BLUE)
		update_preview_line()

	else:
		# Third click - reset
		clear_selection()
		selected_anchors.append(grid_pos)
		get_cell(grid_pos).set_outline_color(Color.RED)


## Clear all anchor selections
func clear_selection():
	# Clear visual feedback from all selected cells
	for grid_pos in selected_anchors:
		var cell = get_cell(grid_pos)
		if cell:
			cell.clear_visual_feedback()

	selected_anchors.clear()
	preview_line.visible = false


## Get the currently selected anchors
func get_selected_anchors() -> Array[Vector2i]:
	return selected_anchors


## Update hover feedback
func update_hover_feedback(world_pos: Vector2):
	var cell = get_cell_at_world_pos(world_pos)

	# Clear previous hover
	if hovered_cell and hovered_cell != cell:
		hovered_cell.set_hover_highlight(false)

	# Set new hover
	hovered_cell = cell
	if hovered_cell:
		hovered_cell.set_hover_highlight(true)


## Clear all hover effects
func clear_all_hover_effects():
	if hovered_cell:
		hovered_cell.set_hover_highlight(false)
		hovered_cell = null


## Update the preview line between anchors
func update_preview_line():
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


## Optional: Set up test walls (for debugging)
func setup_test_walls():
	# Example: Create border walls
	for x in range(grid_size.x):
		get_cell(Vector2i(x, 0)).set_cell_type(1)  # Top wall
		get_cell(Vector2i(x, grid_size.y - 1)).set_cell_type(1)  # Bottom wall

	for y in range(grid_size.y):
		get_cell(Vector2i(0, y)).set_cell_type(1)  # Left wall
		get_cell(Vector2i(grid_size.x - 1, y)).set_cell_type(1)  # Right wall


## Debug: Draw grid lines (optional)
func _draw():
	if OS.is_debug_build():
		# This could be used for debug visualization
		pass
