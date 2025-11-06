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

## Properties

## Current grid position
var grid_position: Vector2i

## Target world position for movement
var target_position: Vector2

## Whether player is currently moving
var is_moving: bool = false

## Whether player input is enabled
var input_enabled: bool = true

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
	# Don't accept input if disabled
	if not input_enabled:
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

	# Calculate target grid position
	var new_grid_pos = grid_position + direction

	# Validate move
	if not can_move_to(new_grid_pos):
		return false

	# Execute move
	execute_move(new_grid_pos)
	return true


## Check if player can move to target position
## @param target_grid_pos: Target grid position
## @return: true if move is valid, false otherwise
func can_move_to(target_grid_pos: Vector2i) -> bool:
	# Check if position is within grid bounds
	if not grid_manager.is_valid_position(target_grid_pos):
		return false

	# Get target cell
	var target_cell = grid_manager.get_cell(target_grid_pos)
	if not target_cell:
		return false

	# Check if target cell is walkable (not a wall)
	# Cell types: 0=empty, 1=wall, 2=water, 3=goal
	if target_cell.cell_type == 1:  # Wall
		return false

	return true


## Execute the move to new grid position
## @param new_grid_pos: New grid position to move to
func execute_move(new_grid_pos: Vector2i) -> void:
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

	# Check if player reached goal
	check_goal()


## Check if player is on goal cell
func check_goal() -> void:
	var current_cell = grid_manager.get_cell(grid_position)
	if current_cell and current_cell.cell_type == 3:  # Goal
		# Play victory sound
		AudioManager.play_sfx("victory")
		emit_signal("goal_reached")


## Get current grid position
## @return: Current grid position
func get_grid_position() -> Vector2i:
	return grid_position


## Set grid position (teleport)
## @param new_pos: New grid position
func set_grid_position(new_pos: Vector2i) -> void:
	if not grid_manager or not grid_manager.is_valid_position(new_pos):
		return

	grid_position = new_pos
	# Cell centers are in GridManager's local space, so convert to global
	var cell = grid_manager.get_cell(grid_position)
	if cell:
		global_position = grid_manager.to_global(cell.get_center())
		target_position = global_position
