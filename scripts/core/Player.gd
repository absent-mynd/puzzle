## Space-Folding Puzzle Game - Player Class
##
## Manages player character movement on the grid with smooth animations.
## Supports grid-based movement with WASD/Arrow keys, collision detection,
## and smooth tweening between cells.
##
## @author: Space-Folding Puzzle Team
## @version: 1.0

extends CharacterBody2D
class_name Player

## Signals

## Emitted when player reaches a goal cell
signal goal_reached

## PHASE 8: Emitted after a successful move completes (from_pos, to_pos)
signal moved(from_pos: Vector2i, to_pos: Vector2i)

## PHASE 8: Emitted on every move attempt, including blocked ones (direction, success)
signal move_attempted(direction: Vector2i, success: bool)

## Properties

## Current grid position
var grid_position: Vector2i

## PHASE 8: Direction the player is facing (updated on every move attempt)
var facing: Vector2i = Vector2i(1, 0)

## PHASE 8: Visual arrow showing facing direction
var facing_indicator: Polygon2D = null

## PHASE 8: Origin of the in-progress move (for the `moved` signal)
var _move_from_pos: Vector2i = Vector2i.ZERO

## Target world position for movement
var target_position: Vector2

## Whether player is currently moving
var is_moving: bool = false

## Whether player input is enabled
var input_enabled: bool = true

## Movement lock: set true while a fold is executing/animating so movement input is
## deferred until the fold completes (prevents mid-fold move glitches).
var movement_locked: bool = false

## Movement speed in pixels per second (only used for backup non-tween movement)
var movement_speed: float = 300.0

## Tween duration for grid movement in seconds
var move_duration: float = 0.2

## Reference to the GridManager
var grid_manager: GridManager = null

## Active tween for movement animation
var move_tween: Tween = null

## Visual representation (sprite or shape)
var sprite: ColorRect = null


## Initialize player at starting position
func _ready() -> void:
	# Create visual representation (simple colored square for now)
	sprite = ColorRect.new()
	sprite.size = Vector2(48, 48)  # Slightly smaller than cell (64x64)
	sprite.position = Vector2(-24, -24)  # Center the sprite
	sprite.color = Color(1.0, 0.5, 0.0)  # Orange color
	add_child(sprite)

	# PHASE 8: Facing arrow (small triangle pointing +x by default, rotated to face)
	facing_indicator = Polygon2D.new()
	facing_indicator.polygon = PackedVector2Array([
		Vector2(18, 0),    # Tip (points right = +x)
		Vector2(2, -8),    # Back-top
		Vector2(2, 8),     # Back-bottom
	])
	facing_indicator.color = Color(0.1, 0.1, 0.1, 0.9)
	facing_indicator.z_index = 1  # Above the body sprite
	add_child(facing_indicator)
	_update_facing_visual()


## Initialize player with grid manager and starting position
## @param manager: Reference to GridManager
## @param start_pos: Starting grid position
func initialize(manager: GridManager, start_pos: Vector2i) -> void:
	grid_manager = manager
	grid_position = start_pos

	# Set world position to center of starting cell
	# Cell centers are in GridManager's local space, so convert to global
	if grid_manager:
		var cell = grid_manager.get_cell(grid_position)
		if cell:
			global_position = grid_manager.to_global(cell.get_center())
			target_position = global_position


## Process input and update position
func _process(delta: float) -> void:
	if not is_moving:
		handle_input()


## Handle keyboard input for movement
func handle_input() -> void:
	# Don't accept input if disabled, or while a fold is executing (deferred until done).
	if not input_enabled or movement_locked:
		return

	var input_direction := Vector2i.ZERO

	# Check for WASD or Arrow keys
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_direction.y = -1
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_direction.y = 1
	elif Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_direction.x = -1
	elif Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_direction.x = 1

	# Attempt to move if direction was pressed
	if input_direction != Vector2i.ZERO:
		attempt_move(input_direction)


## Attempt to move in the given direction
## @param direction: Direction to move (grid coordinates)
## @return: true if move was successful, false otherwise
func attempt_move(direction: Vector2i) -> bool:
	if is_moving or not grid_manager:
		return false

	# PHASE 8: Update facing on every attempt, BEFORE validation, so bumping a wall
	# still turns the player toward the obstacle.
	facing = direction
	_update_facing_visual()

	# Calculate target grid position
	var new_grid_pos = grid_position + direction

	# Validate move
	if not can_move_to(new_grid_pos):
		emit_signal("move_attempted", direction, false)
		return false

	# Execute move
	execute_move(new_grid_pos)
	emit_signal("move_attempted", direction, true)
	return true


## PHASE 8: Rotate the facing arrow to point in the current facing direction
func _update_facing_visual() -> void:
	if facing_indicator and facing != Vector2i.ZERO:
		facing_indicator.rotation = Vector2(facing).angle()


## Set the facing direction and refresh the visual (used by undo to restore heading).
func set_facing(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return
	facing = direction
	_update_facing_visual()


## Check if player can move to target position
## @param target_grid_pos: Target grid position
## @return: true if move is valid, false otherwise
##
## PHASE 5: Uses dominant type for multi-piece cells
## NOTE: Does NOT check initial grid bounds - allows movement to shifted cells
func can_move_to(target_grid_pos: Vector2i) -> bool:
	# Get target cell (this is the real validation - does a cell exist there?)
	var target_cell = grid_manager.get_cell(target_grid_pos)
	if not target_cell:
		return false

	# Incomplete tiles (merged with empty space) are not walkable.
	if not target_cell.is_complete():
		return false

	# PHASE 5: Check dominant type for collision
	# Cell types: -1=null, 0=empty, 1=wall, 2=water, 3=goal
	var dominant_type = target_cell.get_dominant_type()

	# Can't move into walls or null (void) cells
	if dominant_type == 1 or dominant_type == CellPiece.CELL_TYPE_NULL:
		return false

	# Can move into empty, water, or goal
	return true


## Execute the move to new grid position
## @param new_grid_pos: New grid position to move to
func execute_move(new_grid_pos: Vector2i) -> void:
	# PHASE 8: Remember origin so we can report it when the move completes
	_move_from_pos = grid_position

	# Update grid position
	grid_position = new_grid_pos

	# Get target cell and calculate world position
	# Cell centers are in GridManager's local space, so convert to global
	var target_cell = grid_manager.get_cell(new_grid_pos)
	if not target_cell:
		return

	target_position = grid_manager.to_global(target_cell.get_center())

	# Start movement animation
	start_move_tween()


## Start smooth tween animation to target position
func start_move_tween() -> void:
	is_moving = true

	# Play footstep sound with pitch variation
	AudioManager.play_sfx("footstep", true)

	# Kill existing tween if any
	if move_tween:
		move_tween.kill()

	# Create new tween
	move_tween = create_tween()
	move_tween.set_ease(Tween.EASE_IN_OUT)
	move_tween.set_trans(Tween.TRANS_CUBIC)

	# Animate global_position since target_position is in global coordinates
	move_tween.tween_property(self, "global_position", target_position, move_duration)

	# Connect to finished signal
	move_tween.finished.connect(_on_move_finished)


## Called when movement tween completes
func _on_move_finished() -> void:
	is_moving = false

	# PHASE 8: Notify listeners the move landed
	emit_signal("moved", _move_from_pos, grid_position)

	# Check if player reached goal
	check_goal()


## Check if player is on goal cell
##
## PHASE 5: Uses has_cell_type() to detect goal in multi-piece cells
func check_goal() -> void:
	var current_cell = grid_manager.get_cell(grid_position)
	if current_cell and current_cell.has_cell_type(3):  # Goal (checks all pieces)
		# Play victory sound
		AudioManager.play_sfx("victory")
		emit_signal("goal_reached")


## Get current grid position
## @return: Current grid position
func get_grid_position() -> Vector2i:
	return grid_position


## Set grid position (teleport)
## @param new_pos: New grid position
## NOTE: Does NOT check initial grid bounds - allows teleporting to shifted cells
func set_grid_position(new_pos: Vector2i) -> void:
	if not grid_manager:
		return

	# Check if a cell exists at the target position
	var cell = grid_manager.get_cell(new_pos)
	if not cell:
		return

	grid_position = new_pos
	# Cell centers are in GridManager's local space, so convert to global
	global_position = grid_manager.to_global(cell.get_center())
	target_position = global_position
