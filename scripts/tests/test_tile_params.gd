## TileParams tests
##
## The per-tile parameter schema and everything done with it: defaults, reading a
## stored value, coercing an edited one, deciding what is worth writing, and
## saying what is wrong.
##
## The point of this file existing at all is that the editor's tile inspector is
## GENERATED from the schema. So the tests that matter most are the ones that
## hold for any declared parameter rather than for triggers specifically — and
## the ones that assert a world file survives a round trip through it.

extends GutTest

const CHANNEL := {"key": "channel", "type": "string", "default": "", "label": "channel"}
const COUNT := {"key": "count", "type": "int", "default": 3, "label": "count"}
const RATE := {"key": "rate", "type": "float", "default": 1.5, "label": "rate"}
const ARMED := {"key": "armed", "type": "bool", "default": false, "label": "armed"}
const PAIR := {"key": "anchors", "type": "cells", "default": [], "count": 2, "label": "anchors"}


# ---------------------------------------------------------------------------
# The schema
# ---------------------------------------------------------------------------

func test_most_tiles_take_no_parameters():
	assert_false(TileParams.has_params(TileTypes.WALL), "a wall is just a wall")
	assert_eq(TileParams.specs_for(TileTypes.WALL), [], "and declares nothing")


func test_the_trigger_declares_a_channel_and_two_anchors():
	assert_true(TileParams.has_params(TileTypes.TRIGGER_FOLD), "a plate is configurable")
	var keys: Array = []
	for spec in TileParams.specs_for(TileTypes.TRIGGER_FOLD):
		keys.append(String(spec["key"]))
	assert_eq(keys, ["channel", "anchors"], "the two things TriggerResolver reads")


func test_every_declared_parameter_is_well_formed():
	# The schema is hand-written in a const table; this is what stops a typo in it
	# from reaching the editor as a blank row or a crash.
	var kinds := [TileParams.STRING, TileParams.INT, TileParams.FLOAT,
		TileParams.BOOL, TileParams.CELLS]
	for type in TileTypes.all_types():
		for spec in TileParams.specs_for(int(type)):
			var where := "%s.%s" % [TileTypes.type_name(int(type)), spec.get("key", "?")]
			assert_true(spec.has("key"), "%s has a key" % where)
			assert_true(kinds.has(String(spec.get("type", ""))), "%s has a known type" % where)
			assert_true(spec.has("label"), "%s has a label for the inspector" % where)
			if String(spec["type"]) == TileParams.CELLS:
				assert_gt(int(spec.get("count", 0)), 0, "%s says how many cells it wants" % where)


func test_the_burst_plate_declares_one_number():
	var keys: Array = []
	for spec in TileParams.specs_for(TileTypes.TRIGGER_BURST):
		keys.append(String(spec["key"]))
	assert_eq(keys, ["radius"], "how far it reaches is the whole of a plate's configuration")
	assert_eq(String(TileParams.spec_of(TileTypes.TRIGGER_BURST, "radius")["type"]),
		TileParams.FLOAT, "a reach in cells, so half a cell is sayable")


func test_a_plate_left_alone_reads_a_real_reach():
	# Declaring the parameter is the whole job: a plate painted and never inspected
	# still bursts, because the default is a number and not a hole.
	assert_almost_eq(float(TileParams.get_value(TileTypes.TRIGGER_BURST, {}, "radius")),
		1.3, 0.001, "an unconfigured plate reads its default reach")
	assert_eq(TileParams.to_storage(TileTypes.TRIGGER_BURST, {"radius": 1.3}), {},
		"...and stores nothing, like every other value that equals its default")


func test_types_with_params_finds_the_trigger():
	assert_true(TileParams.types_with_params().has(TileTypes.TRIGGER_FOLD),
		"the trigger is listed as configurable")
	assert_true(TileParams.types_with_params().has(TileTypes.TRIGGER_BURST),
		"and so is the burst plate")
	assert_false(TileParams.types_with_params().has(TileTypes.WALL), "a wall is not")


func test_spec_of_finds_a_key_and_misses_cleanly():
	assert_eq(String(TileParams.spec_of(TileTypes.TRIGGER_FOLD, "channel")["key"]), "channel",
		"a declared key is found")
	assert_eq(TileParams.spec_of(TileTypes.TRIGGER_FOLD, "nope"), {}, "an undeclared one is not")


# ---------------------------------------------------------------------------
# Defaults and coercion
# ---------------------------------------------------------------------------

func test_defaults_come_from_the_spec():
	assert_eq(TileParams.default_of(CHANNEL), "", "a string default")
	assert_eq(TileParams.default_of(COUNT), 3, "an int default")
	assert_almost_eq(TileParams.default_of(RATE), 1.5, 0.001, "a float default")
	assert_eq(TileParams.default_of(ARMED), false, "a bool default")


func test_a_cells_default_is_the_right_number_of_unset_slots():
	assert_eq(TileParams.default_of(PAIR), [TileParams.UNSET, TileParams.UNSET],
		"two declared cells means two slots to fill, not an empty list")


func test_a_cells_default_is_a_fresh_array_each_time():
	# It comes out of a const registry; handing back the same instance would let a
	# caller edit the table through it.
	var a: Array = TileParams.default_of(PAIR)
	a.append(Vector2i(9, 9))
	assert_eq((TileParams.default_of(PAIR) as Array).size(), 2, "the next caller gets a clean one")


func test_defaults_for_a_type_covers_every_key():
	var d := TileParams.defaults_for(TileTypes.TRIGGER_FOLD)
	assert_true(d.has("channel") and d.has("anchors"), "every declared key is present")
	assert_eq(d["channel"], "", "at its default")


func test_coerce_forces_the_declared_shape():
	assert_eq(TileParams.coerce(CHANNEL, 42), "42", "a number into a string field")
	assert_eq(TileParams.coerce(COUNT, 7.9), 7, "a float into an int field")
	assert_almost_eq(TileParams.coerce(RATE, 2), 2.0, 0.001, "an int into a float field")
	assert_eq(TileParams.coerce(ARMED, 1), true, "a number into a bool field")


func test_coerce_falls_back_rather_than_failing():
	# A world file is hand-editable; a typo in one field must not stop the region
	# loading.
	assert_eq(TileParams.coerce(COUNT, "banana"), 3, "an unreadable int lands on its default")
	assert_almost_eq(TileParams.coerce(RATE, "banana"), 1.5, 0.001, "and so does a float")


func test_cells_read_from_the_stored_pair_form():
	assert_eq(TileParams.coerce(PAIR, [[26, 9], [28, 9]]),
		[Vector2i(26, 9), Vector2i(28, 9)], "the [[x,y],...] a world file stores")


func test_cells_are_padded_and_truncated_to_the_declared_count():
	assert_eq(TileParams.coerce(PAIR, [[1, 1]]), [Vector2i(1, 1), TileParams.UNSET],
		"a short list gains an unfilled slot")
	assert_eq(TileParams.coerce(PAIR, [[1, 1], [2, 2], [3, 3]]),
		[Vector2i(1, 1), Vector2i(2, 2)],
		"a long one is cut — the runtime reads anchors[0] and [1] and ignores the rest")


func test_cells_accept_typed_vectors_too():
	assert_eq(TileParams.coerce(PAIR, [Vector2i(4, 5), Vector2i(6, 7)]),
		[Vector2i(4, 5), Vector2i(6, 7)], "the editor's own form round-trips without conversion")


func test_get_value_defaults_a_missing_key():
	assert_eq(TileParams.get_value(TileTypes.TRIGGER_FOLD, {}, "channel"), "",
		"an unconfigured trigger reads as its default, not as null")


# ---------------------------------------------------------------------------
# Normalizing and storing
# ---------------------------------------------------------------------------

func test_normalize_fills_in_what_the_file_left_out():
	var full := TileParams.normalize(TileTypes.TRIGGER_FOLD, {"channel": "vault"})
	assert_eq(full["channel"], "vault", "what was stored survives")
	assert_eq(full["anchors"], [TileParams.UNSET, TileParams.UNSET],
		"and what was not gets its slots")


func test_normalize_keeps_unknown_keys():
	# A key this build has no spec for is data somebody meant. Dropping it would
	# make opening a file in the editor a lossy operation.
	var full := TileParams.normalize(TileTypes.TRIGGER_FOLD, {"future_thing": {"a": 1}})
	assert_true(full.has("future_thing"), "an unrecognised key is carried through")
	assert_eq(full["future_thing"], {"a": 1}, "untouched")


func test_a_default_value_is_not_worth_storing():
	assert_null(TileParams.to_stored(CHANNEL, ""), "an empty channel is the default — store nothing")
	assert_eq(TileParams.to_stored(CHANNEL, "vault"), "vault", "a real one is stored")


func test_storage_drops_defaults_and_keeps_the_rest():
	var stored := TileParams.to_storage(TileTypes.TRIGGER_FOLD,
		{"channel": "", "anchors": [Vector2i(1, 1), Vector2i(5, 1)]})
	assert_false(stored.has("channel"), "the default channel is not written")
	assert_eq(stored["anchors"], [[1, 1], [5, 1]], "the anchors are, in the file's own form")


func test_storage_of_an_untouched_tile_is_empty():
	assert_eq(TileParams.to_storage(TileTypes.TRIGGER_FOLD,
		TileParams.defaults_for(TileTypes.TRIGGER_FOLD)), {},
		"a freshly painted trigger writes nothing at all — a hundred of them do not bloat the file")


func test_storage_keeps_unknown_keys():
	var stored := TileParams.to_storage(TileTypes.TRIGGER_FOLD, {"mystery": 5})
	assert_eq(stored["mystery"], 5, "unrecognised data survives a save")


func test_stored_form_is_json_safe():
	var stored := TileParams.to_storage(TileTypes.TRIGGER_FOLD,
		{"channel": "vault", "anchors": [Vector2i(1, 1), Vector2i(5, 1)]})
	var back = JSON.parse_string(JSON.stringify(stored))
	assert_true(back is Dictionary, "it encodes")
	assert_eq(TileParams.coerce(PAIR, back["anchors"]), [Vector2i(1, 1), Vector2i(5, 1)],
		"and decodes back to the same cells — no Vector2i reaches the file")


func test_the_shipped_trigger_round_trips_unchanged():
	# The exact data in worlds/overworld.json, through the whole pipeline.
	var authored := {"channel": "vault", "anchors": [[26, 9], [28, 9]]}
	var stored := TileParams.to_storage(TileTypes.TRIGGER_FOLD,
		TileParams.normalize(TileTypes.TRIGGER_FOLD, authored))
	assert_eq(stored, authored, "reading and writing the shipped plate changes nothing")


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

func test_a_fully_configured_trigger_has_no_issues():
	assert_eq(TileParams.issues(TileTypes.TRIGGER_FOLD,
		{"channel": "vault", "anchors": [[1, 1], [5, 1]]}, Vector2i(10, 10)), [],
		"nothing to say about a finished plate")


func test_an_unconfigured_trigger_says_what_is_missing():
	var issues := TileParams.issues(TileTypes.TRIGGER_FOLD, {}, Vector2i(10, 10))
	assert_gt(issues.size(), 0, "an empty plate is reported")
	assert_true(_has(issues, "2 of 2 not chosen"), "and it says which slots: %s" % [issues])


func test_a_half_configured_trigger_counts_correctly():
	var issues := TileParams.issues(TileTypes.TRIGGER_FOLD,
		{"anchors": [[1, 1]]}, Vector2i(10, 10))
	assert_true(_has(issues, "1 of 2 not chosen"), "one slot left: %s" % [issues])


func test_an_anchor_outside_the_region_is_reported():
	var issues := TileParams.issues(TileTypes.TRIGGER_FOLD,
		{"anchors": [[1, 1], [99, 99]]}, Vector2i(10, 10))
	assert_true(_has(issues, "outside the region"), "a cell off the grid: %s" % [issues])


func test_two_anchors_on_one_cell_are_reported():
	var issues := TileParams.issues(TileTypes.TRIGGER_FOLD,
		{"anchors": [[3, 3], [3, 3]]}, Vector2i(10, 10))
	assert_true(_has(issues, "the same cell twice"),
		"the one pair that is never a fold: %s" % [issues])


func test_two_unset_slots_are_not_a_duplicate():
	var issues := TileParams.issues(TileTypes.TRIGGER_FOLD, {}, Vector2i(10, 10))
	assert_false(_has(issues, "the same cell twice"),
		"two things you have not done yet are not the same thing done twice")


func test_bounds_checking_is_optional():
	assert_false(_has(TileParams.issues(TileTypes.TRIGGER_FOLD,
		{"anchors": [[99, 99], [98, 98]]}), "outside"),
		"with no grid size given, cells are not bounds-checked")


func test_is_complete_agrees_with_issues():
	assert_true(TileParams.is_complete(TileTypes.TRIGGER_FOLD,
		{"anchors": [[1, 1], [5, 1]]}, Vector2i(10, 10)), "a usable plate")
	assert_false(TileParams.is_complete(TileTypes.TRIGGER_FOLD, {}, Vector2i(10, 10)),
		"an empty one")


func test_a_tile_with_no_parameters_never_has_issues():
	assert_eq(TileParams.issues(TileTypes.WALL, {}, Vector2i(10, 10)), [],
		"a wall cannot be misconfigured")


# ---------------------------------------------------------------------------
# tile_data keys
# ---------------------------------------------------------------------------

func test_cell_keys_round_trip():
	assert_eq(TileParams.key_of(Vector2i(25, 9)), "25,9", "the spelling a world file uses")
	assert_eq(TileParams.cell_of_key("25,9"), Vector2i(25, 9), "and back")


func test_a_malformed_key_reads_as_unset():
	assert_eq(TileParams.cell_of_key("nonsense"), TileParams.UNSET,
		"a hand-mangled key does not crash the walk over tile_data")


func _has(messages: Array, needle: String) -> bool:
	for m in messages:
		if String(m).findn(needle) >= 0:
			return true
	return false
