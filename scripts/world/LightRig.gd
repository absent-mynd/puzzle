class_name LightRig extends Node2D

## LightRig
##
## The view side of lighting: it owns the lit materials, pushes the live light
## set into them once per frame, and draws the lamp glyph at each light so the
## source is visibly an object standing in the world.
##
## WHICH lights are live is not decided here — `FoldWorld` resolves them through
## `BaseFrame` against whatever configuration is on screen (see `LightSource`),
## so a light folded out of the world simply stops being handed to the rig.
##
## TWO materials share one shader, so a single uniform upload lights everything:
##
##     foreground (FG)   what stops you: walls, pins
##     background (BG)   what you move through: air, water, goals, plates
##
## Background answers light more weakly than foreground. That difference is the
## only depth cue the flat world has, and it is what makes a lamp read as
## standing *in front of* the sheet rather than painted onto it.
##
## HOW DEEP you are folded in is a tint on the same two materials rather than a
## second pair of them (`set_depth`). Only one space is ever on screen, so a
## uniform says it; and because it is a uniform rather than a material choice,
## folding yourself deeper than one layer tints further with no new state — the
## world outside is white, one fold in is lavender, two is more so.
##
## Everything not in this table — the player, the overlay's anchors and seam
## diamonds, the lamp glyphs themselves — is drawn unlit on purpose. Lighting is
## style; navigation aids must never dim.

const SHADER_PATH := "res://assets/shaders/pixel_lit.gdshader"

## Must match `MAX_LIGHTS` in the shader.
const MAX_LIGHTS := 12

## The two material groups. Strings rather than an enum because they are also the
## keys `TileBatch` groups its pieces by.
const FG := "fg"
const BG := "bg"

## Ambient floor per surface class. Unlit ground stays clearly readable.
const AMBIENT_FG := Vector3(0.68, 0.70, 0.80)
const AMBIENT_BG := Vector3(0.40, 0.43, 0.56)
const GAIN_FG := 1.0
const GAIN_BG := 0.70

## Hue shift per depth of folded-in-ness, applied as a tint uniform so it
## multiplies the tileset rather than replacing it. Depth 0 is the region.
const TINT_WORLD := Vector3(1.0, 1.0, 1.0)
const TINT_SUB := Vector3(0.86, 0.80, 1.12)
## How far a second and third layer push past the first. Sub-linear on purpose:
## deep folds should still be legible, and the tint is a cue, not a filter.
const TINT_DEPTH_FALLOFF := 0.55

var cell_size := 64.0
var _depth := 0

var _shader: Shader = null
var _materials: Dictionary = {}
var _lamps: Node2D
## Live lights: [{"pos", "color", "radius", "energy", "flicker"}, ...]
var _lights: Array = []
var _focus := Vector2.ZERO
var _time := 0.0
var _any_flicker := false


func _ready() -> void:
	_lamps = Node2D.new()
	add_child(_lamps)
	if ResourceLoader.exists(SHADER_PATH):
		_shader = load(SHADER_PATH)
	if _shader == null:
		# No shader, no lighting: tiles fall back to their flat tileset colours
		# and the world stays fully playable.
		push_warning("LightRig: %s missing — rendering unlit." % SHADER_PATH)
		return
	for key in [FG, BG]:
		_materials[key] = _make_material(key)
	_apply_tint()
	_upload()


func _make_material(key: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	var background := key == BG
	mat.set_shader_parameter("ambient", AMBIENT_BG if background else AMBIENT_FG)
	mat.set_shader_parameter("light_gain", GAIN_BG if background else GAIN_FG)
	mat.set_shader_parameter("tint", TINT_WORLD)
	mat.set_shader_parameter("pixel_size", PixelArt.WORLD_PER_PIXEL)
	return mat


## The material for one of the two groups (`FG` / `BG`). Null when the shader is
## unavailable — callers then draw unlit rather than not at all.
func material_for_key(key: String) -> ShaderMaterial:
	return _materials.get(key, null)


## The material a piece of `type` should draw with.
##
## The split follows the registry's walkability, not the type list: what stops
## you is foreground, what you move through is background. Asking `TileTypes`
## also means a walkable tile that carries a motif (a goal, a pressure plate)
## does not brighten its whole cell relative to the air around it.
func material_for(type: int) -> ShaderMaterial:
	return material_for_key(BG if TileTypes.is_walkable(type) else FG)


## How many folds deep the space on screen is: 0 for the region, 1 inside a fold,
## 2 inside a fold inside one. Tints the sheet further with each layer, so how far
## in you are is legible without a readout.
func set_depth(depth: int) -> void:
	if depth == _depth:
		return
	_depth = maxi(depth, 0)
	_apply_tint()


func depth() -> int:
	return _depth


## Compound the per-layer shift, with each layer pushing less than the one above.
func _apply_tint() -> void:
	var tint := TINT_WORLD
	var strength := 1.0
	for _i in range(_depth):
		tint = tint.lerp(Vector3(tint.x * TINT_SUB.x, tint.y * TINT_SUB.y,
			tint.z * TINT_SUB.z), strength)
		strength *= TINT_DEPTH_FALLOFF
	for key in _materials:
		(_materials[key] as ShaderMaterial).set_shader_parameter("tint", tint)


# ---------------------------------------------------------------------------
# The live light set
# ---------------------------------------------------------------------------

## Hand the rig the lights currently in the world. Rebuilds the lamp glyphs;
## uniforms follow on the next frame.
func set_lights(lights: Array) -> void:
	_lights = lights
	_any_flicker = false
	for entry in lights:
		if absf(float(entry.get("flicker", 0.0))) > 0.0:
			_any_flicker = true
			break
	_rebuild_lamps()
	_upload()


## Where the camera is looking. Only the nearest `MAX_LIGHTS` reach the shader,
## and this is what "nearest" is measured from.
func set_focus(point: Vector2) -> void:
	_focus = point


func _process(delta: float) -> void:
	_time += delta
	if _any_flicker:
		_upload()


func _rebuild_lamps() -> void:
	for child in _lamps.get_children():
		child.queue_free()
	var texture := TileAtlas.texture()
	if texture == null:
		return
	for i in range(_lights.size()):
		var entry: Dictionary = _lights[i]
		var pos: Vector2 = entry["pos"]
		var glyph := Polygon2D.new()
		glyph.polygon = TileAtlas.quad_polygon(PixelArt.snap_round(pos), cell_size)
		glyph.texture = texture
		glyph.uv = TileAtlas.quad_uv(TileAtlas.K_LAMP, i % TileAtlas.VARIANTS)
		# Unlit by design: a lamp is not illuminated by its own light.
		glyph.color = Color(entry["color"]).lerp(Color.WHITE, 0.35)
		_lamps.add_child(glyph)


## Push the nearest lights into every material. Arrays are always sent at full
## length with the tail zeroed; `light_count` is what bounds the shader loop.
func _upload() -> void:
	if _materials.is_empty():
		return
	var chosen := _nearest()
	var positions := PackedVector2Array()
	var colors := PackedVector3Array()
	var falloff := PackedVector2Array()
	positions.resize(MAX_LIGHTS)
	colors.resize(MAX_LIGHTS)
	falloff.resize(MAX_LIGHTS)
	for i in range(chosen.size()):
		var entry: Dictionary = chosen[i]
		var c := Color(entry["color"])
		positions[i] = entry["pos"]
		colors[i] = Vector3(c.r, c.g, c.b)
		falloff[i] = Vector2(float(entry["radius"]), _energy_of(entry, i))
	for key in _materials:
		var mat: ShaderMaterial = _materials[key]
		mat.set_shader_parameter("light_pos", positions)
		mat.set_shader_parameter("light_color", colors)
		mat.set_shader_parameter("light_falloff", falloff)
		mat.set_shader_parameter("light_count", chosen.size())


## Idle flicker: two out-of-phase sines, so a torch breathes without ever
## reaching a period the eye can lock onto.
func _energy_of(entry: Dictionary, index: int) -> float:
	var energy := float(entry["energy"])
	var amount := float(entry.get("flicker", 0.0))
	if absf(amount) <= 0.0:
		return energy
	var phase := float(index) * 1.7
	var wave := 0.6 * sin(_time * 9.3 + phase) + 0.4 * sin(_time * 5.1 + phase * 2.3)
	return maxf(energy * (1.0 + amount * wave), 0.0)


func _nearest() -> Array:
	if _lights.size() <= MAX_LIGHTS:
		return _lights
	var sorted := _lights.duplicate()
	var focus := _focus
	sorted.sort_custom(func(a, b):
		return focus.distance_squared_to(a["pos"]) < focus.distance_squared_to(b["pos"]))
	return sorted.slice(0, MAX_LIGHTS)
