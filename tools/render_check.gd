extends SceneTree

## Render check: a held world is ONE image.
##
## The suite runs headless and so cannot see a frame. This can: it boots the shipped
## world beside the cistern's waterfall — the busiest picture the game draws without
## being touched: sliding water, a flickering lamp, drifting dust, a blinking face —
## and asks two things of the pixels.
##
##   1. Running, two frames half a second apart DIFFER. Without this the second
##      question proves nothing: a world that never moves is trivially still.
##   2. With a hand raised and the held look arrived, two frames half a second apart
##      are IDENTICAL, byte for byte.
##
## The second is the rule in AGENTS.md §"Rendering" and §7: everything in the world
## that animates reads `WorldClock`, the held shader is a fixed function of its input,
## and no shader reads `TIME`. `test_world_clock` holds the first and last of those by
## reading the source; this holds all three by looking.
##
## Needs a display and a real renderer, so it is not part of `run_tests.sh`:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/godot/godot --path . \
##       --rendering-driver opengl3 --resolution 1280x720 -s tools/render_check.gd
##
## Exits 0 if both hold, 1 if either does not.

const REGION := "cistern"
const BESIDE_THE_WATER := Vector2i(7, 11)
## Frames to let the held look ease all the way in before the first sample.
const SETTLE := 150
## Frames between the two samples: half a second at 60.
const APART := 30


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame


func _pixels() -> PackedByteArray:
	return root.get_texture().get_image().get_data()


func _key(world, code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = down
	world._unhandled_input(ev)


func _run() -> void:
	var world = load("res://scenes/world/World.tscn").instantiate()
	world.world_override = WorldData.SHIPPED_WORLD
	world.spawn_override = {"region": REGION, "cell": BESIDE_THE_WATER}
	root.add_child(world)
	await _frames(60)

	var before := _pixels()
	await _frames(APART)
	var moves := before != _pixels()
	print("running world moves:      ", "yes" if moves else "NO — the check proves nothing")

	_key(world, KEY_F, true)
	_key(world, KEY_F, false)
	if not world.placing():
		print("could not raise a hand; nothing was checked")
		quit(1)
		return
	await _frames(SETTLE)
	var held := _pixels()
	await _frames(APART)
	var still := held == _pixels()
	print("held world is one image:  ", "yes" if still else "NO — something is still animating")

	quit(0 if moves and still else 1)
