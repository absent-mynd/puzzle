class_name PlayerBody extends CharacterBody2D

## PlayerBody
##
## Minimal side-view platformer body for the fold prototype: run, gravity,
## jump with coyote time + input buffer, and a cheap blob squash so the
## character reads as soft. Input is raw physical keys so the prototype needs
## no project input-map changes.

const GRAVITY := 1800.0
const MAX_FALL := 1400.0
const RUN_SPEED := 320.0
const RUN_ACCEL := 2600.0
const RUN_DECEL := 3200.0
const JUMP_VELOCITY := -780.0
const COYOTE_TIME := 0.09
const JUMP_BUFFER := 0.11
const RADIUS := 20.0
## Exponential approach rate of the camera toward the body (1/s).
const CAM_SMOOTHING := 8.0
## ...and of the zoom toward its target. Much lazier than the follow: a frame
## that resizes as briskly as it pans reads as breathing, not as attention.
const CAM_ZOOM_SMOOTHING := 2.5

var _coyote := 0.0
var _buffer := 0.0
var _visual: Polygon2D
var _cam: Camera2D

## Last horizontal input: -1 left, +1 right. Default faces right.
var facing := 1

## How much world the frame should be showing, as a Camera2D zoom (smaller sees
## more). Written each frame by `FoldWorld._update_camera` — the body knows its
## own speed but not what the moment is about; the camera eases toward whatever
## is here. See `WorldCore.camera_zoom_for`.
var zoom_target := WorldCore.ZOOM_RESTING

## Set during fold animations: physics and input are suspended while the
## world rearranges, and the animator drives global_position directly.
var frozen := false


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)

	_visual = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(20):
		var ang := TAU * i / 20.0
		pts.append(Vector2(cos(ang), sin(ang)) * RADIUS)
	_visual.polygon = pts
	_visual.color = Color("ffd27f")
	add_child(_visual)

	# Smoothing is driven here rather than by Camera2D's own, because the
	# subspace wrap must displace the camera by exactly one strip width while
	# KEEPING its lag. Camera2D exposes no way to move its smoothed centre —
	# only reset_smoothing(), which drops the lag to zero and reads as a jolt
	# every time you walk through a glue line. So the camera is top_level and
	# this script owns its position.
	_cam = Camera2D.new()
	_cam.position_smoothing_enabled = false
	_cam.top_level = true
	add_child(_cam)
	_cam.global_position = global_position
	_cam.zoom = Vector2.ONE * zoom_target
	_cam.make_current()


func _process(delta: float) -> void:
	if _cam == null:
		return
	# Frame-rate independent exponential approach (stable for large deltas).
	_cam.global_position = _cam.global_position.lerp(
		global_position, 1.0 - exp(-CAM_SMOOTHING * delta))
	var z := lerpf(_cam.zoom.x, zoom_target, 1.0 - exp(-CAM_ZOOM_SMOOTHING * delta))
	_cam.zoom = Vector2(z, z)


func _physics_process(delta: float) -> void:
	if frozen:
		return
	var dir := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir += 1.0
	if dir > 0.0:
		facing = 1
	elif dir < 0.0:
		facing = -1

	var accel := RUN_ACCEL if absf(dir) > 0.0 else RUN_DECEL
	velocity.x = move_toward(velocity.x, dir * RUN_SPEED, accel * delta)
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

	_coyote = COYOTE_TIME if is_on_floor() else maxf(_coyote - delta, 0.0)
	# Space only: W/Up are reserved for POINTING (anchor placement direction).
	var jump_pressed := Input.is_physical_key_pressed(KEY_SPACE)
	_buffer = JUMP_BUFFER if jump_pressed else maxf(_buffer - delta, 0.0)
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_coyote = 0.0
		_buffer = 0.0

	move_and_slide()

	# Blob squash: stretch along the dominant velocity axis, conserve area.
	var stretch := clampf(absf(velocity.y) / 2800.0, 0.0, 0.30)
	if absf(velocity.y) > absf(velocity.x):
		_visual.scale = Vector2(1.0 - stretch, 1.0 + stretch)
	else:
		var s := clampf(absf(velocity.x) / 2200.0, 0.0, 0.18)
		_visual.scale = Vector2(1.0 + s, 1.0 - s)


## Hard placement (fold rides, respawn): move without sweeping and drop
## any velocity into the ground so the landing reads as a plant, not a launch.
func teleport(to: Vector2, keep_velocity: bool = true) -> void:
	global_position = to
	if not keep_velocity:
		velocity = Vector2.ZERO


## 4-way pointing for anchor placement: held vertical keys win, otherwise you
## point where you face. Sampled at interact time.
func point_dir() -> Vector2i:
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		return Vector2i(0, -1)
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		return Vector2i(0, 1)
	return Vector2i(facing, 0)


## How hard the body is moving, 0 (still) to 1 (all-out). The camera reads this:
## speed is the cheapest signal for "the frame you have is not the frame you
## need". Falling weighs heaviest — a long drop is the move where you most need
## to see where you are going — and running least, since running is the resting
## state of play and should not sit the camera permanently at its limit.
##
## Frozen (riding a fold) reports still: the velocity is stale, and the
## transition frames itself from its own endpoints.
func motion_intensity() -> float:
	if frozen:
		return 0.0
	var run := absf(velocity.x) / RUN_SPEED
	var fall := maxf(velocity.y, 0.0) / MAX_FALL
	var rise := maxf(-velocity.y, 0.0) / absf(JUMP_VELOCITY)
	return clampf(0.45 * run + 0.75 * fall + 0.25 * rise, 0.0, 1.0)


## The zoom the camera is actually at, easing and all.
func camera_zoom() -> float:
	return _cam.zoom.x if _cam != null else zoom_target


## Cut the camera to the body with no pan. For hard relocations — respawn,
## doors, region changes, being turned back by the fold. The lens cuts with it:
## easing a zoom across a warp would read as the new room inflating.
func snap_camera() -> void:
	if _cam != null:
		_cam.global_position = global_position
		_cam.zoom = Vector2.ONE * zoom_target


## Carry the camera through a wrap teleport. Inside a fold the strip repeats
## with period `offset`, so displacing the body AND the camera by the same
## vector leaves the rendered frame pixel-identical: crossing a glue line is
## just walking. Snapping instead would discard the smoothing lag (~40px at a
## full run) and jolt the view by it — the hitch this replaces.
func shift_camera(offset: Vector2) -> void:
	if _cam != null:
		_cam.global_position += offset


## Where the camera actually is, lag and all.
func camera_position() -> Vector2:
	return _cam.global_position if _cam != null else global_position


## A fresh Polygon2D matching the blob's outline and colour. The subspace wrap
## draws one of these in every visible copy of the strip.
func make_visual_copy() -> Polygon2D:
	var node := Polygon2D.new()
	node.polygon = _visual.polygon
	node.color = _visual.color
	return node


## The blob's current squash, so the copies breathe with the original.
func visual_squash() -> Vector2:
	return _visual.scale
