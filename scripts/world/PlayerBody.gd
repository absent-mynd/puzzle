class_name PlayerBody extends CharacterBody2D

## PlayerBody
##
## Minimal side-view platformer body for the fold prototype: run, gravity,
## variable-height jump with coyote time + input buffer, and a cheap blob squash
## so the character reads as soft. Input is raw physical keys so the prototype
## needs no project input-map changes.
##
## **The jump is variable-height.** Every jump leaves the floor at the same speed;
## how high it goes is decided on the way up, by whether you are still holding the
## key (see `gravity_scale`). A tap clears a one-tile step, a full hold clears the
## two-tile pillar, and nothing clears the three-tile wall — those bounds are
## authored into the world, and `test_player_body` pins them.

const GRAVITY := 1800.0
const MAX_FALL := 1400.0
const RUN_SPEED := 320.0
const RUN_ACCEL := 2600.0
const RUN_DECEL := 3200.0
## Deceleration with nothing held, in the AIR. Much gentler than on the ground:
## letting go of the stick mid-jump should not stop you dead over a pit, so a
## jump keeps the run that launched it. Steering the other way is unaffected —
## that is `RUN_ACCEL` and always was, so nothing you could reach before is
## harder to reach now; only stopping in mid-air is.
const AIR_DECEL := 1400.0
const JUMP_VELOCITY := -780.0
## Gravity multiplier while rising with the jump key RELEASED — the whole of the
## tap-versus-hold difference. Cutting the rise short with weight rather than by
## clipping the velocity is what makes the height a continuum: release at any
## point in the rise and you get the height you paid for, instead of one of two
## jumps. The floor of that continuum is the shortest possible tap, which this
## number sets: a bare tap rises about 1.35 cells against a full hold's 2.7.
const JUMP_CUT_GRAVITY := 2.0
## ...and while falling. A landing that arrives a little sooner than the rise that
## earned it reads as weight; a symmetric arc reads as the moon. Deliberately
## small — the fall is also the part of the arc you steer a landing in.
const FALL_GRAVITY := 1.12
## The band around the apex, in vertical speed, that gets `APEX_GRAVITY`.
const APEX_SPEED := 200.0
## Gravity multiplier inside that band. The top of a jump is where you are barely
## moving vertically and entirely occupied with where you are going to land — and
## with pinning the mid-air anchor the sealed chamber wants. Lightening it buys
## more of those frames without raising the arc much (about 6 units, which is why
## the three-cell wall is still a wall).
const APEX_GRAVITY := 0.7
const COYOTE_TIME := 0.09
const JUMP_BUFFER := 0.11
const RADIUS := 20.0
## Exponential approach rate of the camera toward the body (1/s).
const CAM_SMOOTHING := 8.0
## ...and of the zoom toward its target. Much lazier than the follow: a frame
## that resizes as briskly as it pans reads as breathing, not as attention.
const CAM_ZOOM_SMOOTHING := 2.5
## ...and of the LEAD toward its target. Also lazy, for a different reason: the
## lead flips sign the instant you turn around, and a lead that tracked that at
## the follow's rate would whip the frame across the body on every direction
## change. Eased, a reversal reads as the view swinging round to your new heading.
const CAM_LOOKAHEAD_SMOOTHING := 3.0

## World units between footsteps. Distance, not time: a step is a stride, so
## walking slowly must give slow steps rather than the same steps quieter. At
## RUN_SPEED that is a little over three a second. (`Sounds.FOOTSTEP` also
## carries a retrigger floor, but that is a backstop for the degenerate cases —
## a body shoved along a wall, a fold landing you mid-run — not the stride.)
const STRIDE := 96.0

## Downward speed a landing must exceed to be heard. Below this the body is
## settling onto a slope or stepping off a lip, and a sound for it would fire
## several times while you simply walked along uneven ground.
const LAND_SPEED := 220.0

var _coyote := 0.0
var _buffer := 0.0
## Last frame's held state of the jump key, so a press can be told from a hold.
var _jump_held := false
## True from the launch of a jump until you let go or the rise ends. This — not
## the held key — is what buys height: it is armed only by a jump WE launched, so
## a body thrown upward by the world is not quietly made floatier by a key that
## happened to be down, and a key held through a landing cannot re-arm it without
## a fresh press.
var _sustaining := false

## Distance run along the ground since the last footstep.
var _stride := 0.0

## Whether the body was on the floor last frame, for the air->ground edge.
var _was_grounded := true

var _visual: Polygon2D
var _cam: Camera2D

## Last horizontal input: -1 left, +1 right. Default faces right.
var facing := 1

## How much world the frame should be showing, as a LOGICAL zoom (smaller sees
## more). Written each frame by `FoldWorld._update_camera` — the body knows its
## own speed but not what the moment is about; this eases toward whatever is
## here. See `WorldCore.camera_zoom_for`.
##
## "Logical" because the Camera2D's own zoom is pinned to `PixelArt.CAMERA_ZOOM`
## and never moves: that is what makes one art pixel exactly WORLD_PER_PIXEL
## world units. Showing more world means giving the render target more pixels,
## not changing the lens. `FoldWorld` resizes it from `camera_zoom()`.
var zoom_target := WorldCore.ZOOM_RESTING

## The eased logical zoom — what the target is actually sized from right now.
var _zoom := WorldCore.ZOOM_RESTING

## Where the frame should sit relative to the body — the lead. Written each frame
## by `FoldWorld._update_camera` alongside `zoom_target`; the camera eases toward
## it. See `WorldCore.camera_lookahead_for`.
var lookahead_target := Vector2.ZERO

## The lead the camera is currently applying, eased. Kept apart from
## `lookahead_target` so the follow can aim at `global_position + this` — the body
## is what the camera chases, and the lead is an offset on top of it.
var _lookahead := Vector2.ZERO

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
	# The camera's zoom is FIXED, and it is what keeps the art crisp: one art
	# pixel must cover exactly PixelArt.WORLD_PER_PIXEL world units, and inside a
	# render target that is purely a function of zoom. How much world is on
	# screen is set by RESIZING the target instead — see `PixelArt.target_size`
	# and `FoldWorld._update_camera`. So `zoom_target` below is a LOGICAL zoom: it
	# sizes the target, it does not touch the lens.
	_cam.zoom = PixelArt.CAMERA_ZOOM
	add_child(_cam)
	_cam.global_position = global_position
	_cam.make_current()


func _process(delta: float) -> void:
	if _cam == null:
		return
	# Frame-rate independent exponential approach (stable for large deltas).
	_lookahead = _lookahead.lerp(
		lookahead_target, 1.0 - exp(-CAM_LOOKAHEAD_SMOOTHING * delta))
	_cam.global_position = _cam.global_position.lerp(
		global_position + _lookahead, 1.0 - exp(-CAM_SMOOTHING * delta))
	_zoom = lerpf(_zoom, zoom_target, 1.0 - exp(-CAM_ZOOM_SMOOTHING * delta))
	_apply_pixel_snap()


## Pixel-snap the view. A camera resting between art pixels makes every edge in
## the world crawl as it slides, so the rendered centre is rounded to a whole art
## pixel. The snap lives in `offset`, leaving `global_position` the unsnapped
## truth: quantizing the smoothing state itself would let a slow pan stall
## whenever a frame's step landed inside the pixel it started in.
func _apply_pixel_snap() -> void:
	_cam.offset = PixelArt.snap_round(_cam.global_position) - _cam.global_position


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

	# Steering always gets the full accel; only letting go reads the ground.
	var accel := RUN_ACCEL
	if is_zero_approx(dir):
		accel = RUN_DECEL if is_on_floor() else AIR_DECEL
	velocity.x = move_toward(velocity.x, dir * RUN_SPEED, accel * delta)

	_coyote = COYOTE_TIME if is_on_floor() else maxf(_coyote - delta, 0.0)
	# Space only: W/Up are reserved for POINTING (anchor placement direction).
	var jump_pressed := take_jump_press()
	if not _jump_held:
		_sustaining = false
	_buffer = JUMP_BUFFER if jump_pressed else maxf(_buffer - delta, 0.0)
	if _buffer > 0.0 and _coyote > 0.0:
		# The launch frame takes no gravity: the jump IS this frame's vertical step.
		velocity.y = JUMP_VELOCITY
		_sustaining = true
		_coyote = 0.0
		_buffer = 0.0
		# The launch, not the key: a buffered press that never finds coyote time
		# makes no sound, and one that finds it a few frames later sounds then.
		AudioManager.play_sfx(Sounds.JUMP)
	else:
		velocity.y = step_fall(velocity.y, _sustaining, delta)
	if velocity.y >= 0.0:
		# The rise is over — by apex, by ceiling, or by landing. Nothing left to
		# sustain, and holding the key must not lighten a fall.
		_sustaining = false

	# Read before the move: `move_and_slide` zeroes the fall the moment the body
	# touches down, so afterwards there is no landing speed left to judge.
	var fall_speed := velocity.y
	move_and_slide()
	_step_audio(delta, fall_speed)

	# Blob squash: stretch along the dominant velocity axis, conserve area.
	var stretch := clampf(absf(velocity.y) / 2800.0, 0.0, 0.30)
	if absf(velocity.y) > absf(velocity.x):
		_visual.scale = Vector2(1.0 - stretch, 1.0 + stretch)
	else:
		var s := clampf(absf(velocity.x) / 2200.0, 0.0, 0.18)
		_visual.scale = Vector2(1.0 + s, 1.0 - s)


## Whether the jump key has been pressed AFRESH since this was last asked — the
## rising edge, not the held state. Reading it consumes the edge, so call it once
## per physics frame; after it returns, `_jump_held` is this frame's held state.
##
## The edge is what makes holding mean "keep rising" rather than "jump again the
## moment you land": sampling the held key straight into the buffer, as this used
## to, left the buffer permanently full, so a player holding for height bounced off
## the floor on the frame they touched it and spent the hold on the wrong jump.
func take_jump_press() -> bool:
	var held := Input.is_physical_key_pressed(KEY_SPACE)
	var fresh := held and not _jump_held
	_jump_held = held
	return fresh


## The gravity multiplier in force for a body moving at `vy` (negative up), where
## `sustaining` means "a jump we launched is still rising and the key is still
## down". Pure, and the whole shape of the jump:
##
## - **rising, held** — plain gravity. This is the full jump, the arc the world
##   is authored against.
## - **rising, released** — `JUMP_CUT_GRAVITY`. The rise is cut short by weight,
##   not by clipping the velocity, so how high you go is a continuous function of
##   how long you held rather than a choice between two jumps.
## - **falling** — `FALL_GRAVITY`, whatever the key is doing. Sustain is a
##   rise-only affordance; a held key must never slow a fall.
## - **either, near the apex** — `APEX_GRAVITY` on top. The frames where you are
##   barely moving vertically are the frames you steer and pin anchors in, so they
##   are the ones worth having more of.
static func gravity_scale(vy: float, sustaining: bool) -> float:
	var scale := 1.0
	if vy < 0.0:
		if not sustaining:
			scale = JUMP_CUT_GRAVITY
	else:
		scale = FALL_GRAVITY
	if absf(vy) < APEX_SPEED:
		scale *= APEX_GRAVITY
	return scale


## One frame of vertical motion: `vy` a frame on, terminal fall respected. The
## body takes exactly this step, so anything that integrates it is predicting the
## real arc — see `jump_height_for_hold`.
static func step_fall(vy: float, sustaining: bool, delta: float) -> float:
	return minf(vy + GRAVITY * gravity_scale(vy, sustaining) * delta, MAX_FALL)


## How high a jump rises, in world units, if the key is held for `hold` seconds —
## the tap-to-hold curve, integrated from the same step the body takes.
##
## This is here to be *asked*: the world is authored against these heights (a
## one-tile step a tap clears, the two-tile pillar a full hold clears, the
## three-tile wall nothing clears), and a constant nudged for feel can quietly
## move them. `test_player_body` asks it so that cannot happen silently.
static func jump_height_for_hold(hold: float, step: float = 1.0 / 60.0) -> float:
	var vy := JUMP_VELOCITY
	var y := 0.0
	var peak := 0.0
	var t := 0.0
	while vy < 0.0:
		vy = step_fall(vy, t < hold, step)
		y += vy * step
		peak = minf(peak, y)
		t += step
	return -peak


## Footsteps and landings, from the state the move left behind.
##
## Both live here rather than in the world because both are facts about the
## BODY — how far it has run, how hard it hit — and the world does not track
## either. Neither is allowed to influence anything: this reads state and makes
## noise, and that is the whole of it.
func _step_audio(delta: float, fall_speed: float) -> void:
	var grounded := is_on_floor()
	if grounded and not _was_grounded:
		if fall_speed > LAND_SPEED:
			AudioManager.play_sfx(Sounds.LAND)
		# Whatever the stride had accumulated belongs to the run before the
		# jump; starting fresh keeps the first step after a landing a full one.
		_stride = 0.0
	_was_grounded = grounded

	if grounded:
		_stride += absf(velocity.x) * delta
		if _stride >= STRIDE:
			_stride = 0.0
			AudioManager.play_sfx(Sounds.FOOTSTEP)
	else:
		_stride = 0.0


## Hard placement (fold rides, respawn): move without sweeping and drop
## any velocity into the ground so the landing reads as a plant, not a launch.
##
## Silent, and it resets the step state: arriving somewhere is not walking
## there. The fold, the door or the respawn that moved you has its own sound,
## and a footstep or a landing thud underneath it would say you had travelled.
func teleport(to: Vector2, keep_velocity: bool = true) -> void:
	global_position = to
	if not keep_velocity:
		velocity = Vector2.ZERO
	_stride = 0.0
	_was_grounded = true


## Held vertical intent: -1 up, +1 down, 0 neither. Up wins when both are held —
## one reading of the keys, used both to aim an anchor and to lean the frame, so
## pressing up to point up shows you what you are pointing at.
func look_dir() -> float:
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		return -1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		return 1.0
	return 0.0


## 4-way pointing for anchor placement: held vertical keys win, otherwise you
## point where you face. Sampled at interact time.
func point_dir() -> Vector2i:
	var v := look_dir()
	if v != 0.0:
		return Vector2i(0, int(v))
	return Vector2i(facing, 0)


## Velocity as a signed per-axis fraction of the body's OWN limits: x in units of
## run speed, y of terminal fall going down and of jump launch going up. Both the
## lead and the zoom are expressed in these terms — "as fast as I can run" is the
## thing they want to know, and only the body knows what that is.
func motion_fraction() -> Vector2:
	# Up divides by the jump launch, down by terminal fall: they are different
	# limits, and a rise at "full speed" means the top of a fresh jump.
	var up_down := (velocity.y / MAX_FALL if velocity.y >= 0.0
		else velocity.y / absf(JUMP_VELOCITY))
	return Vector2(clampf(velocity.x / RUN_SPEED, -1.0, 1.0), clampf(up_down, -1.0, 1.0))


## How hard the body is moving, 0 (still) to 1 (all-out). The zoom reads this:
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
	var f := motion_fraction()
	return clampf(0.45 * absf(f.x) + 0.75 * maxf(f.y, 0.0) + 0.25 * maxf(-f.y, 0.0), 0.0, 1.0)


## The LOGICAL zoom in force right now, easing and all — how much world the frame
## is showing. `FoldWorld` sizes the pixel target from this; the lens itself never
## moves (see `zoom_target`).
func camera_zoom() -> float:
	return _zoom


## The lead the camera is currently applying, easing and all.
func camera_lookahead() -> Vector2:
	return _lookahead


## Cut the camera to the body with no pan. For hard relocations — respawn,
## doors, region changes, being turned back by the fold. The framing and the lead
## cut with it: easing the zoom across a warp would read as the new room
## inflating, and easing the lead would drift the frame sideways as you arrive,
## which reads as the camera having lost you.
func snap_camera() -> void:
	if _cam != null:
		_lookahead = lookahead_target
		_zoom = zoom_target
		_cam.global_position = global_position + _lookahead
		_apply_pixel_snap()


## Carry the camera through a wrap teleport. Inside a fold the strip repeats
## with period `offset`, so displacing the body AND the camera by the same
## vector leaves the rendered frame pixel-identical: crossing a glue line is
## just walking. Snapping instead would discard the smoothing lag (~40px at a
## full run) and jolt the view by it — the hitch this replaces.
func shift_camera(offset: Vector2) -> void:
	if _cam != null:
		_cam.global_position += offset
		_apply_pixel_snap()


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
