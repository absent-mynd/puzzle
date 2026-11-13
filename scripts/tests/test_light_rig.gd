extends GutTest

## LightRig: the two materials the whole sheet is drawn through, and everything about
## the look of a place that is said ONCE for the room rather than per tile — how deep
## you are folded, what mood the room is in, and what time it is.
##
## What a lamp is and where it burns is `test_light_source.gd`. This is what the rig
## tells the shader.

var rig: LightRig


func before_each() -> void:
	rig = LightRig.new()
	add_child_autofree(rig)


func _param(key: String, name: String):
	return (rig.material_for_key(key) as ShaderMaterial).get_shader_parameter(name)


func _close(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.0001


func test_each_material_knows_whether_it_draws_what_stops_you() -> void:
	# The neighbour mask means opposite things for the two groups — faces to rim, or
	# neighbours to shade by — and this is the flag that says which.
	assert_true(_param(LightRig.FG, "solid"), "the foreground is what stops you")
	assert_false(_param(LightRig.BG, "solid"), "the background is what you move through")


func test_the_shader_is_told_the_shape_of_the_tileset() -> void:
	# It needs it to find the water row and to keep a slid texel inside its own tile.
	# Fed from `TileAtlas`, so a new kind cannot leave the shader counting the old ones.
	for key in [LightRig.FG, LightRig.BG]:
		assert_eq(_param(key, "atlas_kinds"), float(TileAtlas.KINDS))
		assert_eq(_param(key, "atlas_variants"), float(TileAtlas.VARIANTS))
		assert_eq(_param(key, "water_kind"), float(TileAtlas.K_WATER))


# ---------------------------------------------------------------------------
# Mood
# ---------------------------------------------------------------------------

func test_with_no_mood_the_sheet_is_untinted() -> void:
	assert_true(_close(_param(LightRig.FG, "tint"), LightRig.TINT_WORLD))


func test_a_rooms_mood_tints_both_materials() -> void:
	rig.set_mood(Color(1.0, 0.5, 0.25))
	for key in [LightRig.FG, LightRig.BG]:
		assert_true(_close(_param(key, "tint"), Vector3(1.0, 0.5, 0.25)),
			"%s takes the room's colour" % key)


func test_being_folded_in_tints_on_top_of_the_mood() -> void:
	# Two cues, one uniform. The depth shift is a ratio, so it has to MULTIPLY the
	# mood — a warm room folded into is a warm room pushed toward violet, not a room
	# that forgot which one it was.
	rig.set_depth(1)
	var deep_only: Vector3 = _param(LightRig.FG, "tint")
	rig.set_mood(Color(1.0, 0.5, 0.25))
	var both: Vector3 = _param(LightRig.FG, "tint")
	assert_true(_close(both, deep_only * Vector3(1.0, 0.5, 0.25)))
	rig.set_depth(0)
	assert_true(_close(_param(LightRig.FG, "tint"), Vector3(1.0, 0.5, 0.25)),
		"and surfacing leaves the mood where it was")


# ---------------------------------------------------------------------------
# Time
# ---------------------------------------------------------------------------

func test_the_shaders_clock_is_the_world_clock() -> void:
	# The water moves in the shader, and a shader's own TIME would keep moving through
	# a hold. So the rig hands it world time, which is the only clock that stops.
	WorldClock.advance(0.75)
	rig._process(0.016)
	for key in [LightRig.FG, LightRig.BG]:
		assert_almost_eq(float(_param(key, "world_time")), WorldClock.now(), 0.0001)


func test_a_stopped_world_sends_the_shader_nothing_new() -> void:
	WorldClock.advance(0.25)
	rig._process(0.016)
	var was := float(_param(LightRig.FG, "world_time"))
	# Frames go by and the world's clock does not move: that is a hold.
	for _i in range(5):
		rig._process(0.016)
	assert_eq(float(_param(LightRig.FG, "world_time")), was,
		"held water is one unchanging image")


# ---------------------------------------------------------------------------
# Motes: dust in the lamplight
# ---------------------------------------------------------------------------

const CS := 64.0


func test_motes_stay_in_their_lamps_light() -> void:
	var reach := LightRig.MOTE_REACH * CS
	for i in range(LightRig.MOTES):
		for step in range(400):
			var at := LightRig.mote_offset(i, 7, float(step) * 0.37, CS)
			assert_true(absf(at.x) <= reach.x + 0.001 and absf(at.y) <= reach.y + 0.001,
				"mote %d strayed to %s" % [i, at])


func test_motes_drift_and_only_on_the_time_they_are_given() -> void:
	# `_draw` passes `WorldClock.now()`. No hidden state, so a world that is not
	# advancing draws the same dust in the same place.
	assert_ne(LightRig.mote_offset(0, 7, 1.0, CS), LightRig.mote_offset(0, 7, 3.0, CS), "it drifts")
	assert_eq(LightRig.mote_offset(0, 7, 3.0, CS), LightRig.mote_offset(0, 7, 3.0, CS))


func test_each_lamp_has_its_own_dust_and_each_mote_its_own_path() -> void:
	assert_ne(LightRig.mote_offset(0, 7, 2.0, CS), LightRig.mote_offset(0, 8, 2.0, CS))
	assert_ne(LightRig.mote_offset(0, 7, 2.0, CS), LightRig.mote_offset(1, 7, 2.0, CS))


func test_a_lamps_copies_share_one_swarm() -> void:
	# Inside a fold a lamp stands in every copy of the space. Its dust is keyed on the
	# lamp's ID, not on its place in the list, so every copy shows the same motes —
	# or walking through the glue would swap the dust in front of you.
	var near := {"id": "lamp", "pos": Vector2.ZERO}
	var copy := {"id": "lamp", "pos": Vector2(640, 0)}
	assert_eq(LightRig.mote_seed(near), LightRig.mote_seed(copy))
	assert_ne(LightRig.mote_seed(near), LightRig.mote_seed({"id": "other", "pos": Vector2.ZERO}))


func test_a_mote_is_never_bright() -> void:
	# It is dust. It must not read as a pickup, a marker, or anything to walk toward.
	for step in range(200):
		var alpha := LightRig.mote_alpha(2, 7, float(step) * 0.21)
		assert_between(alpha, 0.0, LightRig.MOTE_ALPHA)
