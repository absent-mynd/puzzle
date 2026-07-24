extends Node2D

## ProtoWorld
##
## Playable proof-of-concept for the metroidvania pivot: the REAL fold model
## (BaseGrid / Fold / FoldReplay / CollisionCore, unchanged) driving a
## side-view world with gravity and a free-moving blob player.
##
## What it demonstrates:
##   - World geometry derived per fold and turned into physics colliders.
##   - The player decoupled from the grid: standing on a flap when a fold
##     commits teleports you with it (you "ride" the fold).
##   - PINCH ENTRY: standing inside the excised strip when a fold commits
##     drops you into the SUBSPACE — the strip's interior rendered as a
##     cylinder (content repeating across the glue line). Gravity stays on.
##   - Exit hotkey (U / Esc) unfolds the subspace's fold; your position inside
##     the strip IS your position in the restored world, so moving inside the
##     fold moves you in the world — the dive-traversal verb, v1.
##
## v1 shortcuts (deliberate): a pinch fold is never applied to the outside
## world (you can't see outside and exiting would undo it — same outcome,
## fewer states); only the newest fold can be unfolded (stack discipline);
## folding is disabled while inside a subspace.

enum Mode { WORLD, SUBSPACE }

const CS := ProtoCore.CELL
const TYPE_COLORS := {
	BaseTile.TYPE_EMPTY: Color(0.13, 0.14, 0.20),   # faint: the "paper" exists
	BaseTile.TYPE_WALL: Color(0.55, 0.60, 0.70),
	BaseTile.TYPE_WATER: Color(0.25, 0.45, 0.75),
	BaseTile.TYPE_GOAL: Color(0.91, 0.76, 0.35),
}
const SUB_TINT := Color(0.72, 0.62, 0.95)  # subspace pieces shift hue

var base: BaseGrid
var folds: Array[Fold] = []
var next_fold_id := 0
var mode: Mode = Mode.WORLD
var pending_anchor = null  # Vector2i or null

var current_pieces: Array[FoldedPiece] = []
var wall_polys: Array = []
var goal_polys: Array = []
var _on_goal := false

# Subspace state
var sub_fold: Fold = null
var sub_strip: Array = []
var sub_extent: Dictionary = {}
var sub_copies := 1

var _spawn := Vector2((4.0 + 0.5) * CS, (12.0 + 0.5) * CS)
var player: ProtoPlayer
var world_geo: Node2D
var world_solid: StaticBody2D
var sub_geo: Node2D
var overlay: ProtoOverlay
var _bg: ColorRect
var _status: Label
var _flash: Label
var _flash_left := 0.0


func _ready() -> void:
	base = ProtoCore.parse_map(_make_map())

	world_geo = Node2D.new()
	add_child(world_geo)
	sub_geo = Node2D.new()
	add_child(sub_geo)

	overlay = ProtoOverlay.new()
	overlay.world = self
	overlay.z_index = 50
	add_child(overlay)

	player = ProtoPlayer.new()
	player.position = _spawn
	player.z_index = 40
	add_child(player)

	_build_hud()
	rebuild_world()


# ---------------------------------------------------------------------------
# Map: authored programmatically so beats are easy to retune (no ASCII counting)
# ---------------------------------------------------------------------------
# Beats, left to right: start plateau | 8-wide unjumpable pit | tower with a
# goal on top | flat run | fully sealed chamber with a goal inside.
func _make_map() -> Array:
	var w := 44
	var h := 18
	var rows: Array = []
	for y in range(h):
		rows.append(".".repeat(w))

	var put := func(x: int, y: int, ch: String) -> void:
		var row: String = rows[y]
		rows[y] = row.substr(0, x) + ch + row.substr(x + 1)

	for y in range(14, 18):            # ground, with the pit at x 10..17
		for x in range(0, 10):
			put.call(x, y, "#")
		for x in range(18, w):
			put.call(x, y, "#")
	for y in range(7, 14):             # tower
		for x in range(22, 25):
			put.call(x, y, "#")
	put.call(23, 6, "G")               # goal on the tower top
	for x in range(32, 41):            # chamber roof
		put.call(x, 9, "#")
	for y in range(10, 14):            # chamber side walls
		put.call(32, y, "#")
		put.call(40, y, "#")
	put.call(36, 13, "G")              # goal sealed inside the chamber
	return rows


# ---------------------------------------------------------------------------
# Derived world -> visuals + colliders
# ---------------------------------------------------------------------------

func rebuild_world() -> void:
	current_pieces = FoldReplay.derive_pieces(base, folds)
	for child in world_geo.get_children():
		child.queue_free()
	wall_polys = []
	goal_polys = []

	world_solid = StaticBody2D.new()
	world_geo.add_child(world_solid)
	for piece in current_pieces:
		var vis := Polygon2D.new()
		vis.polygon = piece.polygon
		vis.color = TYPE_COLORS.get(piece.type, Color.MAGENTA)
		world_geo.add_child(vis)
		if piece.type == BaseTile.TYPE_WALL:
			wall_polys.append(piece.polygon)
			var col := CollisionPolygon2D.new()
			col.polygon = piece.polygon
			world_solid.add_child(col)
		elif piece.type == BaseTile.TYPE_GOAL:
			goal_polys.append(piece.polygon)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_U:
				if mode == Mode.SUBSPACE:
					exit_subspace("Unfolded — you emerge where you walked to.")
				else:
					pop_fold()
			KEY_ESCAPE:
				if mode == Mode.SUBSPACE:
					exit_subspace("Unfolded — you emerge where you walked to.")
				else:
					pending_anchor = null
			KEY_R:
				_reset()
		return

	if mode != Mode.WORLD:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			pending_anchor = null
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_handle_anchor_click(hovered_cell())


func hovered_cell() -> Vector2i:
	return Vector2i((get_global_mouse_position() / CS).floor())


func _handle_anchor_click(cell: Vector2i) -> void:
	if not base.is_in_bounds(cell):
		return
	if pending_anchor == null:
		pending_anchor = cell
		return
	if ProtoCore.anchors_valid(pending_anchor, cell):
		do_fold(pending_anchor, cell)
		pending_anchor = null
	else:
		# Misaligned second click re-picks the first anchor (fast retry UX).
		pending_anchor = cell


# ---------------------------------------------------------------------------
# Fold / unfold with a free-moving player
# ---------------------------------------------------------------------------

func do_fold(a1: Vector2i, a2: Vector2i) -> void:
	var fold := Fold.create(next_fold_id, a1, a2, CS)
	var side := ProtoCore.side_of_fold(player.global_position, fold)

	if side == 0:
		# Player is in the excised strip: the fold swallows them. Capture the
		# strip from the CURRENT pieces (pre-fold frame) and dive in.
		var strip := ProtoCore.capture_strip(current_pieces, fold, CS)
		if strip.is_empty():
			_show_flash("Nothing there to fold into.")
			return
		next_fold_id += 1
		enter_subspace(fold, strip)
		return

	var shift := ProtoCore.fold_shift_for_side(side, fold, CS)
	folds.append(fold)
	rebuild_world()
	var landed := ProtoCore.depenetrate(player.global_position + shift, ProtoPlayer.RADIUS, wall_polys)
	if landed == Vector2.INF:
		folds.pop_back()
		rebuild_world()
		_show_flash("Fold blocked — nowhere for you to land.")
		return
	next_fold_id += 1
	player.teleport(landed)


func pop_fold() -> void:
	if folds.is_empty():
		_show_flash("Nothing to unfold.")
		return
	var fold: Fold = folds.pop_back()
	var shift := ProtoCore.unfold_shift(player.global_position, fold, CS)
	rebuild_world()
	var landed := ProtoCore.depenetrate(player.global_position + shift, ProtoPlayer.RADIUS, wall_polys)
	if landed == Vector2.INF:
		folds.append(fold)
		rebuild_world()
		_show_flash("Unfold blocked — nowhere for you to land.")
		return
	player.teleport(landed)


# ---------------------------------------------------------------------------
# Subspace: the strip's interior as a cylinder (wrap along the fold normal)
# ---------------------------------------------------------------------------

func enter_subspace(fold: Fold, strip: Array) -> void:
	mode = Mode.SUBSPACE
	sub_fold = fold
	sub_strip = strip
	var tangent := Vector2(-fold.crease_normal.y, fold.crease_normal.x)
	sub_extent = ProtoCore.strip_extent(strip, tangent)

	world_geo.visible = false
	world_solid.collision_layer = 0
	pending_anchor = null
	_bg.color = Color("191030")

	var gap := fold.gap_distance()
	sub_copies = clampi(int(ceil(1400.0 / gap)), 1, 24)
	for k in range(-sub_copies, sub_copies + 1):
		var copy := Node2D.new()
		copy.position = fold.crease_normal * (k * gap)
		sub_geo.add_child(copy)
		var solid: StaticBody2D = null
		if absi(k) <= 1:
			solid = StaticBody2D.new()
			copy.add_child(solid)
		for entry in strip:
			var vis := Polygon2D.new()
			vis.polygon = entry["polygon"]
			var c: Color = TYPE_COLORS.get(entry["type"], Color.MAGENTA)
			vis.color = c.lerp(SUB_TINT, 0.35) if entry["type"] != BaseTile.TYPE_EMPTY else c
			copy.add_child(vis)
			if entry["type"] == BaseTile.TYPE_WALL and solid != null:
				var col := CollisionPolygon2D.new()
				col.polygon = entry["polygon"]
				solid.add_child(col)
	_show_flash("Folded IN. You are inside the fold — it repeats at the glue. U to unfold.")


func exit_subspace(message: String) -> void:
	mode = Mode.WORLD
	sub_fold = null
	sub_strip = []
	for child in sub_geo.get_children():
		child.queue_free()
	world_geo.visible = true
	world_solid.collision_layer = 1
	_bg.color = Color("14151f")
	# Strip content is captured in the pre-fold frame and the pinch fold was
	# never applied to the outside world, so the player's subspace position IS
	# their world position: emerging displaced is the dive-traversal verb.
	var landed := ProtoCore.depenetrate(player.global_position, ProtoPlayer.RADIUS, wall_polys)
	if landed != Vector2.INF:
		player.teleport(landed)
	_show_flash(message)


func _physics_process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	if _flash_left == 0.0 and _flash != null:
		_flash.visible = false
	_update_status()

	if mode == Mode.SUBSPACE:
		_subspace_wrap_and_eject()
	else:
		_check_goal()
		if player.global_position.y > (base.grid_size.y + 6) * CS:
			player.teleport(_spawn, false)
			_show_flash("You fell out of the world — respawned.")


func _subspace_wrap_and_eject() -> void:
	var n := sub_fold.crease_normal
	var gap := sub_fold.gap_distance()
	var c1 := sub_fold.crease_point1.dot(n)
	var proj := player.global_position.dot(n)
	if proj < c1:
		player.global_position += n * gap
		player.snap_camera()
	elif proj >= c1 + gap:
		player.global_position -= n * gap
		player.snap_camera()

	var tangent := Vector2(-n.y, n.x)
	var tproj := player.global_position.dot(tangent)
	if tproj < sub_extent["min"] - 4.0 * CS or tproj > sub_extent["max"] + 4.0 * CS:
		exit_subspace("You fell out of the fold — it sprang open.")


func _check_goal() -> void:
	var touching := false
	for poly in goal_polys:
		if ProtoCore.circle_overlaps_polygon(player.global_position, ProtoPlayer.RADIUS, poly):
			touching = true
			break
	if touching and not _on_goal:
		_show_flash("★ GOAL reached! ★")
	_on_goal = touching


func _reset() -> void:
	if mode == Mode.SUBSPACE:
		exit_subspace("")
	folds.clear()
	pending_anchor = null
	rebuild_world()
	player.teleport(_spawn, false)
	_show_flash("Reset.")


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	_bg = ColorRect.new()
	_bg.color = Color("14151f")
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(_bg)

	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)

	var help := Label.new()
	help.text = "Move: A/D or arrows   Jump: Space/W\n" \
		+ "Fold: click two aligned tiles (same row or column, 2+ apart)\n" \
		+ "Right-click/Esc: cancel anchor   U: unfold last   R: reset\n" \
		+ "Stand INSIDE the red band when folding to be folded in."
	help.position = Vector2(12, 8)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	hud.add_child(help)

	_status = Label.new()
	_status.position = Vector2(12, 92)
	_status.add_theme_color_override("font_color", Color("59e0d0"))
	hud.add_child(_status)

	_flash = Label.new()
	_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_flash.position = Vector2(340, 130)
	_flash.add_theme_font_size_override("font_size", 22)
	_flash.add_theme_color_override("font_color", Color("ffd27f"))
	_flash.visible = false
	hud.add_child(_flash)


func _update_status() -> void:
	if _status == null:
		return
	var mode_name := "WORLD" if mode == Mode.WORLD else "INSIDE FOLD"
	_status.text = "Folds: %d   Mode: %s" % [folds.size(), mode_name]


func _show_flash(text: String) -> void:
	if text.is_empty():
		return
	_flash.text = text
	_flash.visible = true
	_flash_left = 2.5
